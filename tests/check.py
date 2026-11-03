#!/usr/bin/env python3
"""Run the scripts that `roc main.roc`, `roc builtins.roc`, `roc monitoring.roc` and `roc search.roc` print against SurrealDB and check every block.

Blocks are separated by one blank line; a block has no blank line inside.
Line 1 of a block is its header, then directive lines, then SurrealQL:
  -- schema | -- seed: T | -- accepts: N      all statements must be OK
  -- query: N | -- write: N                   last statement result is compared
       `-- roc: <SurrealQL literal>` (one line), `-- ordered` (else multiset),
       `-- intrinsic: a, b` (the columns whose value reads an intrinsic, which
       the package names: the `-- roc:` literal may leave out these columns,
       and no other; a column it leaves out is not compared)
  -- rejects: N  with `-- error: <substring>`  some statement must be ERR
  -- live: N  with `-- roles: <role>, ..` (one per LIVE statement: node, edge,
       read, raw or diff; a read statement sends a list of rows, each one
       notice), an optional
       `-- snapshot: <literal>`, `-- roc: <literal>` (one list of notices per
       write), the request, then each write after a `-- write` line. The
       request runs in a WebSocket session; each write runs over HTTP, and
       the notices that arrive are compared with the list of that write.
The scripts run, one after the other, in the same fresh database. Three
blocks of check.py's own (`SELF_CHECKS`) then show that a literal that
leaves out a column that reads no intrinsic is reported. Then
`roc watch.roc` runs on that database: a live session on basic-cli that
checks each change it reads against the Roc Mirror, and exits with 0 when
all agree. Then `roc client.roc`: plain queries and writes in a session,
each typed result checked against the result that Roc computes. Then
`roc client.roc -- --http`: the same queries in a session over HTTP. Then
`roc server.roc`, a web server on basic-webserver that runs a typed query
in a WebSocket session of each request: the checker asks it for the
readings, and compares the answer. They are the last four blocks (not with `--script`).
With `--record DIR`, each WebSocket message of a
live block is saved as `DIR/<block>/<nn>.cbor`, in the order it came: the
reply to the request, the notices, the replies to `kill` and the `KILLED`
notices. Two requests that fail are saved too, as `DIR/errors/00.cbor` (a
query whose statement fails) and `01.cbor` (an unknown method), and the
reply to one request for each kind of error of the server, as
`DIR/errors/<name>.cbor`, in a database `roc_errors` with the schema of
`fixtures/errors/schema.surql`, for `ErrorTest.roc`.
With `--record DIR`, `client.roc` also saves the reply to each of its
requests as `DIR/queries/<name>.cbor`, and as `DIR/http/<name>.cbor` over
HTTP. `DecodeTest.roc` and
`PreparedTest.roc` read such files from `fixtures/`. It also records the
frames of one session with two watches and requests in flight, as
`DIR/mux/<case>/<nn>.cbor`, for `MuxTest.roc`.
Usage: check.py [path/to/roc] [--script FILE]... [--url U] [--user X] [--pass Y] [--record DIR]
Env: SURREAL_URL (default http://localhost:8000), SURREAL_USER, SURREAL_PASS.
"""

import argparse
import base64
import decimal
import json
import os
import pathlib
import socket
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
EXAMPLES = HERE.parent / "examples"
APPS = ["main.roc", "builtins.roc", "monitoring.roc", "search.roc"]
NS, DB = "roc", "roc_surreal"
DOCKER = "docker run --rm -d -p 8000:8000 surrealdb/surrealdb:v3.3.4 start --user root --pass root memory"


class Server:
    def __init__(self, url, user, password):
        self.url = url.rstrip("/")
        self.auth = "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()

    def run(self, text, db=DB):
        """One HTTP request. Returns (statements, None) or (None, error text).

        The reply is CBOR, not JSON: JSON prints a decimal as a string, so
        it cannot tell the decimal 42 from the string "42". CBOR tags it.
        """
        headers = {"Accept": "application/cbor", "Content-Type": "text/plain",
                   "Authorization": self.auth, "surreal-ns": NS}
        if db:
            headers["surreal-db"] = db
        request = urllib.request.Request(self.url + "/sql", text.encode(), headers)
        try:
            return cbor(urllib.request.urlopen(request).read()), None
        except urllib.error.HTTPError as e:
            return None, f"HTTP {e.code} {e.read().decode()}"


def cbor(data):
    """Decodes one CBOR value. Only what SurrealDB sends is supported."""
    value, end = cbor_item(data, 0)
    assert end == len(data), "trailing bytes in the CBOR reply"
    return value


def cbor_item(data, at):
    major, info = data[at] >> 5, data[at] & 31
    at += 1
    if major == 7 and info in (25, 26, 27):
        size = {25: 2, 26: 4, 27: 8}[info]
        return struct.unpack(">" + {2: "e", 4: "f", 8: "d"}[size], data[at:at + size])[0], at + size
    if info < 24:
        arg = info
    else:
        size = {24: 1, 25: 2, 26: 4, 27: 8}[info]
        arg, at = int.from_bytes(data[at:at + size], "big"), at + size
    if major == 0:
        return arg, at
    if major == 1:
        return -1 - arg, at
    if major in (2, 3):
        raw = data[at:at + arg]
        return (raw if major == 2 else raw.decode()), at + arg
    if major == 4:
        items = []
        for _ in range(arg):
            item, at = cbor_item(data, at)
            items.append(item)
        return items, at
    if major == 5:
        pairs = {}
        for _ in range(arg):
            name, at = cbor_item(data, at)
            pairs[name], at = cbor_item(data, at)
        return pairs, at
    if major == 6:
        inner, at = cbor_item(data, at)
        if arg == 10:  # a decimal, sent as its text
            # -0 equals 0 in SurrealQL (`math::ceil(-0.5dec)` is -0), so one text stands for both.
            number = decimal.Decimal(inner).normalize()
            return {"$decimal": "0" if number == 0 else str(number)}, at
        if arg == 6:  # NONE
            return None, at
        return {"$tag": arg, "value": inner}, at
    return {20: False, 21: True, 22: None, 23: None}[arg], at


def cbor_encode(value):
    """Encodes the values of an RPC request: text, integers, lists, maps, null."""
    def head(major, n):
        if n < 24:
            return bytes([major << 5 | n])
        for info, size in ((24, 1), (25, 2), (26, 4), (27, 8)):
            if n < 1 << (8 * size):
                return bytes([major << 5 | info]) + n.to_bytes(size, "big")
        raise ValueError(n)
    if value is None:
        return b"\xf6"
    if isinstance(value, bool):
        return b"\xf5" if value else b"\xf4"
    if isinstance(value, int):
        return head(0, value) if value >= 0 else head(1, -1 - value)
    if isinstance(value, str):
        raw = value.encode()
        return head(3, len(raw)) + raw
    if isinstance(value, list):
        return head(4, len(value)) + b"".join(cbor_encode(v) for v in value)
    if isinstance(value, dict):
        return head(5, len(value)) + b"".join(cbor_encode(k) + cbor_encode(v) for k, v in value.items())
    if isinstance(value, Tagged):
        raw = value.value
        return head(6, value.tag) + head(2, len(raw)) + raw
    raise TypeError(value)


class Tagged:
    """A byte string with a CBOR tag: the uuid (tag 37) of a live query in `kill`."""

    def __init__(self, tag, value):
        self.tag, self.value = tag, value


class Session:
    """A WebSocket RPC session on `/rpc`, subprotocol `cbor`, for live queries."""

    def __init__(self, url, user, password, db=DB, login=None):
        parsed = urllib.parse.urlparse(url)
        host, port = parsed.hostname, parsed.port or 80
        self.sock = socket.create_connection((host, port))
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall((f"GET /rpc HTTP/1.1\r\nHost: {host}:{port}\r\nUpgrade: websocket\r\n"
                           f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n"
                           f"Sec-WebSocket-Protocol: cbor\r\n\r\n").encode())
        data = b""
        while b"\r\n\r\n" not in data:
            data += self.sock.recv(4096)
        head, self.rest = data.split(b"\r\n\r\n", 1)
        if b" 101 " not in head.split(b"\r\n")[0]:
            raise ConnectionError(head.decode(errors="replace"))
        self.next_id = 0
        self.notices = []
        self.recorded = None
        for method, params in (("signin", [login or {"user": user, "pass": password}]), ("use", [NS, db])):
            reply = self.call(method, params)
            if "error" in reply:
                raise ConnectionError(str(reply["error"]))

    def bytes(self, count):
        while len(self.rest) < count:
            more = self.sock.recv(65536)
            if not more:
                raise EOFError("the server closed the session")
            self.rest += more
        out, self.rest = self.rest[:count], self.rest[count:]
        return out

    def send(self, opcode, payload):
        size = len(payload)
        head = bytes([0x80 | opcode])
        if size < 126:
            head += bytes([0x80 | size])
        elif size < 65536:
            head += bytes([0x80 | 126]) + struct.pack(">H", size)
        else:
            head += bytes([0x80 | 127]) + struct.pack(">Q", size)
        mask = os.urandom(4)
        self.sock.sendall(head + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))

    def frame(self, timeout=None):
        """The next message, or None when none comes in `timeout` seconds."""
        while True:
            self.sock.settimeout(timeout)
            try:
                b0, b1 = self.bytes(2)
            except (socket.timeout, TimeoutError):
                return None
            finally:
                self.sock.settimeout(None)
            size = b1 & 0x7F
            if size == 126:
                size = struct.unpack(">H", self.bytes(2))[0]
            elif size == 127:
                size = struct.unpack(">Q", self.bytes(8))[0]
            payload = self.bytes(size)
            opcode = b0 & 0x0F
            if opcode == 9:
                self.send(10, payload)
            elif opcode == 8:
                raise EOFError("the server closed the session")
            elif opcode in (1, 2):
                if self.recorded is not None:
                    self.recorded.append(payload)
                return cbor(payload)

    def call(self, method, params):
        self.next_id += 1
        self.send(2, cbor_encode({"id": self.next_id, "method": method, "params": params}))
        while True:
            message = self.frame()
            if message.get("id") == self.next_id:
                return message
            self.notices.append(message)

    def request(self, id, method, params):
        """Sends a request with this id, and does not wait for its reply."""
        self.send(2, cbor_encode({"id": id, "method": method, "params": params}))

    def replies(self, ids):
        """Reads messages until each of `ids` has its reply. Returns the replies by id."""
        got = {}
        while set(ids) - set(got):
            message = self.frame()
            if "id" in message:
                got[message["id"]] = message
        return got

    def drain(self, quiet=0.3):
        """The notices that arrive until none comes for `quiet` seconds."""
        out, self.notices = self.notices, []
        while True:
            message = self.frame(quiet)
            if message is None:
                return out
            out.append(message)

    def close(self):
        self.sock.close()


def notices_of(role, action, record, result):
    """The notices of one message, as the `-- roc:` literal of a live block writes them.

    A `read` statement sends the rows that the write reaches: one notice each.
    """
    if role == "node":
        return [{"action": action, "role": role, "ref": record, "row": result["row"], "now": result["now"]}]
    if role == "edge":
        node = result["node"] or {}
        return [{"action": action, "role": role, "ref": result["ref"], "row": node.get("row"), "now": node.get("now")}]
    if role == "read":
        return [{"action": action, "role": role, "ref": r["ref"], "row": r["row"], "now": r["now"]} for r in result]
    if role == "raw":
        return [{"action": action, "ref": record, "row": result}]
    return [{"action": action, "ref": record, "ops": result}]


def same_rows(server, got, literal):
    """None when the rows equal the Roc literal as a multiset, else a failure text."""
    reference, error = server.run(f"RETURN {literal};")
    if error or reference[0]["status"] != "OK":
        return f"bad Roc literal: {error or reference[0]['result']}"
    want = normal(reference[0]["result"])
    got = normal(got)
    if sorted(got, key=key) != sorted(want, key=key):
        return f"Roc computed {json.dumps(want)}, database returned {json.dumps(got)}"
    return None


def check_live(server, url, user, password, directives, body, record=None):
    """Runs one `-- live:` block. Returns None when it agrees, else a failure text.

    `record` is a directory: each message of the block is saved in it.
    """
    parts = body.split("\n-- write\n")
    request, writes = parts[0], parts[1:]
    roles = directives.get("roles", "").split(", ")
    statements = request.split("\n")
    lives = [i for i, line in enumerate(statements) if line.startswith("LIVE ")]
    if len(lives) != len(roles):
        return f"{len(lives)} LIVE statements and {len(roles)} roles"
    session = Session(url, user, password)
    if record:
        session.recorded = []
    try:
        reply = session.call("query", [request])
        if "error" in reply:
            return f"database error: {reply['error']}"
        results = reply["result"]
        failed = [r["result"] for r in results if r["status"] != "OK"]
        if failed:
            return f"database error: {failed[0]}"
        ids = {results[i]["result"]["value"]: role for i, role in zip(lives, roles)}
        if "snapshot" in directives:
            problem = same_rows(server, results[-1]["result"], directives["snapshot"])
            if problem:
                return f"snapshot: {problem}"
        got = []
        for write in writes:
            statements, error = server.run(write)
            if error or any(s["status"] != "OK" for s in statements):
                return f"write failed: {error or statements}"
            notices = []
            for message in session.drain():
                n = message["result"]
                if n["action"] != "KILLED" and n["id"]["value"] in ids:
                    notices.extend(notices_of(ids[n["id"]["value"]], n["action"], n["record"], n["result"]))
            got.append(notices)
        reference, error = server.run(f"RETURN {directives['roc']};")
        if error or reference[0]["status"] != "OK":
            return f"bad -- roc literal: {error or reference[0]['result']}"
        want = reference[0]["result"]
        if len(want) != len(got):
            return f"Roc has {len(want)} writes, the block {len(got)}"
        for number, (one_got, one_want) in enumerate(zip(got, want), 1):
            one_got, one_want = normal(one_got), normal(one_want)
            if sorted(one_got, key=key) != sorted(one_want, key=key):
                return f"write {number}: Roc computed {json.dumps(one_want)}, database sent {json.dumps(one_got)}"
        for live in ids:
            reply = session.call("kill", [Tagged(37, live)])
            if "error" in reply:
                return f"kill failed: {reply}"
        killed = {m["result"]["id"]["value"] for m in session.drain() if m["result"]["action"] == "KILLED"}
        if killed != set(ids):
            return f"{len(killed)} of {len(ids)} live queries sent KILLED"
        return None
    finally:
        session.close()
        if record:
            folder = pathlib.Path(record)
            folder.mkdir(parents=True, exist_ok=True)
            for number, payload in enumerate(session.recorded):
                (folder / f"{number:02}.cbor").write_bytes(payload)


def normal(value):
    # NONE is a missing key or null, so a null field is dropped before comparing.
    # A decimal is already normalised by `cbor`, so "42" and 42dec stay apart.
    if isinstance(value, dict):
        return {k: normal(v) for k, v in value.items() if v is not None}
    if isinstance(value, list):
        return [normal(v) for v in value]
    return value


def key(value):
    return json.dumps(value, sort_keys=True)


def split_block(block):
    """Returns (header, directives, body) for one block."""
    lines = block.strip().split("\n")
    directives = {}
    body = []
    for line in lines[1:]:
        if line == "-- ordered":
            directives["ordered"] = True
        elif line.startswith("-- roc: "):
            directives["roc"] = line.removeprefix("-- roc: ")
        elif line.startswith("-- error: "):
            directives["error"] = line.removeprefix("-- error: ")
        elif line.startswith("-- roles: "):
            directives["roles"] = line.removeprefix("-- roles: ")
        elif line.startswith("-- intrinsic: "):
            directives["intrinsic"] = line.removeprefix("-- intrinsic: ").split(", ")
        elif line.startswith("-- snapshot: "):
            directives["snapshot"] = line.removeprefix("-- snapshot: ")
        else:
            body.append(line)
    return lines[0], directives, "\n".join(body)


def left_out(got, want):
    """The columns of the result rows that no row of the literal has."""
    if not (isinstance(got, list) and isinstance(want, list) and want):
        return set()
    have = {k for row in got if isinstance(row, dict) for k in row}
    wanted = {k for row in want if isinstance(row, dict) for k in row}
    return have - wanted if wanted else set()


# Blocks that check the check: a literal that leaves out a column that
# reads no intrinsic must fail, and one that leaves out only an intrinsic
# column must agree. (header, block, whether it must agree)
SELF_CHECKS = [
    ("self: omits a plain column", "-- query: omits_plain\n-- intrinsic: score\n-- roc: [{ id: 1 }]\nRETURN [{ id: 1, score: 0.5, name: 'x' }];", False),
    ("self: omits an intrinsic column", "-- query: omits_intrinsic\n-- intrinsic: score\n-- roc: [{ id: 1, name: 'x' }]\nRETURN [{ id: 1, score: 0.5, name: 'x' }];", True),
    ("self: omits a column, no intrinsic", "-- query: omits_undeclared\n-- roc: [{ id: 1 }]\nRETURN [{ id: 1, score: 0.5 }];", False),
]


def check_block(server, header, directives, body, args):
    """Returns None when the block agrees, else a failure text."""
    kind, _, name = header.removeprefix("-- ").partition(": ")
    if kind == "live":
        record = args.record and str(pathlib.Path(args.record) / name)
        return check_live(server, args.url, args.user, args.password, directives, body, record)
    if kind not in ("schema", "seed", "query", "write", "rejects", "accepts"):
        return "unknown block header"
    statements, error = server.run(body)
    if error:
        return error
    errors = [s["result"] for s in statements if s["status"] != "OK"]
    if kind == "rejects":
        if not errors:
            return "the database accepted this write"
        want = directives.get("error")
        if want and not any(want in str(e) for e in errors):
            return f"error does not contain {want!r}; got {errors}"
        return None
    if errors:
        return f"database error: {errors[0]}"
    if kind in ("query", "write") and "roc" in directives:
        # The server evaluates the Roc literal, so both sides share a serialiser.
        reference, error = server.run(f"RETURN {directives['roc']};")
        if error or reference[0]["status"] != "OK":
            return f"bad -- roc literal: {error or reference[0]['result']}"
        got, want = normal(statements[-1]["result"]), normal(reference[0]["result"])
        omitted = left_out(got, want)
        if omitted:
            # A column that reads an intrinsic, such as a search score, has
            # no Roc value: the literal may leave it out, and the rows are
            # compared without it. Any other column must be in the literal.
            plain = sorted(omitted - set(directives.get("intrinsic", [])))
            if plain:
                return f"the -- roc literal leaves out {', '.join(plain)}, which read no intrinsic"
            got = [{k: v for k, v in row.items() if k not in omitted} if isinstance(row, dict) else row for row in got]
        if not directives.get("ordered") and isinstance(got, list) and isinstance(want, list):
            got, want = sorted(got, key=key), sorted(want, key=key)
        if got != want:
            if isinstance(got, list) and isinstance(want, list):
                # A long result: show only the rows that differ.
                got_keys, want_keys = {key(v) for v in got}, {key(v) for v in want}
                if got_keys != want_keys:
                    return (f"Roc computed {json.dumps([v for v in want if key(v) not in got_keys])}, "
                            f"database returned {json.dumps([v for v in got if key(v) not in want_keys])} (rows that differ)")
            return f"Roc computed {json.dumps(want)}, database returned {json.dumps(got)}"
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("roc", nargs="?", default="roc")
    parser.add_argument("--script", action="append", help="run this script file instead of calling roc (repeatable)")
    parser.add_argument("--url", default=os.environ.get("SURREAL_URL", "http://localhost:8000"))
    parser.add_argument("--user", default=os.environ.get("SURREAL_USER", "root"))
    parser.add_argument("--pass", dest="password", default=os.environ.get("SURREAL_PASS", "root"))
    parser.add_argument("--record", help="save the messages of each live block in this directory")
    args = parser.parse_args()

    server = Server(args.url, args.user, args.password)
    try:
        urllib.request.urlopen(server.url + "/health")
    except OSError as e:
        print(f"Cannot reach SurrealDB at {server.url}: {e}\nStart one with:\n  {DOCKER}")
        sys.exit(2)

    if args.script:
        scripts = [pathlib.Path(f).read_text() for f in args.script]
    else:
        scripts = [subprocess.run([args.roc, str(EXAMPLES / app)], capture_output=True, text=True, check=True).stdout
                   for app in APPS]
    script = "\n\n".join(text.strip("\n") for text in scripts)

    # A fresh database for every run.
    _, error = server.run(f"DEFINE NAMESPACE IF NOT EXISTS {NS};", db=None)
    if not error:
        _, error = server.run(f"DEFINE DATABASE IF NOT EXISTS {DB}; REMOVE DATABASE {DB}; DEFINE DATABASE {DB};", db=None)
    if error:
        print(f"Cannot prepare the database: {error}")
        sys.exit(2)

    failures = 0
    total = 0
    for block in script.split("\n\n"):
        if not block.strip():
            continue
        header, directives, body = split_block(block)
        total += 1
        if "unsupported" in header or "bad schema" in header:
            problem = "the Roc program reported an error"
        elif not header.startswith("-- "):
            problem = "block does not start with a `-- ` header"
        else:
            problem = check_block(server, header, directives, body, args)
        print(f"{'FAIL' if problem else 'ok  '} {header.removeprefix('-- ')}")
        if problem:
            print(f"     {problem}")
            failures += 1
    for name, block, agrees in SELF_CHECKS:
        total += 1
        header, directives, body = split_block(block)
        found = check_block(server, header, directives, body, args)
        problem = None
        if agrees and found:
            problem = f"must agree, and check_block said: {found}"
        elif not agrees and not found:
            problem = "must be reported, and check_block let it agree"
        print(f"{'FAIL' if problem else 'ok  '} {name}" + ("" if agrees or problem else f" (reported: {found})"))
        if problem:
            print(f"     {problem}")
            failures += 1
    if not args.script:
        def recorded(name):
            return ["--record", str(pathlib.Path(args.record).resolve() / name)] if args.record else []
        for name, app, extra in (("watch.roc", "watch.roc", []), ("client.roc", "client.roc", recorded("queries")),
                                 ("client.roc --http", "client.roc", ["--http"] + recorded("http"))):
            total += 1
            problem = check_app(args, app, ["--"] + extra if extra else [])
            print(f"{'FAIL' if problem else 'ok  '} app: {name}")
            if problem:
                print(f"     {problem}")
                failures += 1
        total += 1
        problem = check_server(args)
        print(f"{'FAIL' if problem else 'ok  '} app: server.roc")
        if problem:
            print(f"     {problem}")
            failures += 1
    if args.record:
        record_errors(args, pathlib.Path(args.record) / "errors")
        record_mux(args, server, pathlib.Path(args.record) / "mux")
    print(f"{total - failures}/{total} blocks agree")
    sys.exit(1 if failures else 0)


def check_app(args, app, extra):
    """Runs an app on basic-cli. None when it exits with 0, else its last lines."""
    try:
        run = subprocess.run([args.roc, str(EXAMPLES / app)] + extra, capture_output=True, text=True, timeout=900)
    except subprocess.TimeoutExpired:
        return f"{app} did not end in 900 s"
    if run.returncode == 0:
        return None
    lines = [line for line in (run.stdout + run.stderr).split("\n") if line.strip()]
    return "\n     ".join(lines[-8:])


# What `server.roc` answers on the rows that the scripts leave: the
# readings of `monitoring.roc` with a pulse of 120 or more, fastest first.
SERVER = "http://127.0.0.1:8001"
SERVER_READINGS = ("kennel b at 2026-03-01T23:59:59Z: pulse 130, temp_c 38.0\n"
                   "kennel a at 2026-03-02T09:15:00Z: pulse 125, temp_c 38.0\n"
                   "kennel b at 2026-03-02T11:00:00Z: pulse 121, temp_c 39.1\n"
                   "kennel b at 2026-03-01T10:00:00Z: pulse 120, temp_c 39.0\n")


def check_server(args):
    """Runs `server.roc` on basic-webserver, and asks it for the readings
    over HTTP, and for a target it refuses. None when both answers agree."""
    server = subprocess.Popen([args.roc, str(EXAMPLES / "server.roc")], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        deadline = time.time() + 900
        while True:
            try:
                urllib.request.urlopen(SERVER + "/", timeout=5)
            except urllib.error.HTTPError:
                break  # the server answers, with a 404
            except OSError:
                if server.poll() is not None:
                    return "server.roc ended: " + server.stdout.read().strip()[-400:]
                if time.time() > deadline:
                    return "server.roc did not listen in 900 s"
                time.sleep(1)
        body = urllib.request.urlopen(SERVER + "/readings?min_pulse=120", timeout=30).read().decode()
        if body != SERVER_READINGS:
            return f"GET /readings?min_pulse=120 gave {body!r}, expected {SERVER_READINGS!r}"
        try:
            urllib.request.urlopen(SERVER + "/readings?min_pulse=many", timeout=30)
            return "GET /readings?min_pulse=many was not refused"
        except urllib.error.HTTPError as e:
            if e.code != 400:
                return f"GET /readings?min_pulse=many gave {e.code}, expected 400"
        return None
    finally:
        server.terminate()
        try:
            server.wait(timeout=30)
        except subprocess.TimeoutExpired:
            server.kill()


def record_errors(args, folder):
    """Saves the replies to a query whose statement fails and to an unknown method."""
    session = Session(args.url, args.user, args.password)
    session.recorded = []
    try:
        session.call("query", ["SELECT * FROM nothing_here WHERE fn::no_such_function()"])
        session.call("no_such_method", [])
    finally:
        session.close()
    folder.mkdir(parents=True, exist_ok=True)
    for number, payload in enumerate(session.recorded):
        (folder / f"{number:02}.cbor").write_bytes(payload)
    record_server_errors(args, folder)


# One request for each error of `ErrorTest.roc`, after the seed: its name,
# and the text of the `query`. Each must fail.
ERROR_SEED = ("CREATE owner:ann CONTENT { email: 'ann@x', city: 'oslo', age: 30 };"
              " CREATE owner:cat CONTENT { email: 'cat@x', city: 'rome', age: 40 };"
              " CREATE pet:rex CONTENT { name: 'Rex', owner: owner:ann };"
              " CREATE visit:v1 CONTENT { by: { vet: owner:cat } };"
              " DEFINE USER OVERWRITE viewer ON DATABASE PASSWORD 'viewer' ROLES VIEWER;")
ERRORS = [
    ("exists", "CREATE owner:ann CONTENT { email: 'ann2@x', city: 'oslo', age: 31 }"),
    ("unique", "CREATE owner:bob CONTENT { email: 'ann@x', city: 'bergen', age: 50 }"),
    ("unique_pair", "CREATE owner:bob CONTENT { email: 'bob@x', city: 'oslo', age: 30 }"),
    ("assert", "CREATE owner:bob CONTENT { email: 'bob@x', city: 'oslo', age: -1 }"),
    ("type", "CREATE owner:bob CONTENT { email: 'bob@x', city: 'oslo', age: 'old' }"),
    ("check", "CREATE owner:kid CONTENT { email: 'kid@x', city: 'oslo', age: 9 }"),
    ("referenced", "DELETE owner:ann"),
    ("referenced_nested", "DELETE owner:cat"),
    ("transaction", "BEGIN; CREATE owner:dan CONTENT { email: 'dan@x', city: 'lima', age: 20 };"
                    " CREATE owner:eve CONTENT { email: 'eve@x', city: 'lima', age: -2 }; COMMIT;"),
    ("not_found", "SELECT * FROM nothing_here"),
    ("parse", "SELECT * FROM"),
    ("invalid", "LET $session = 1"),
    ("thrown", "THROW 'boom'"),
    ("timeout", "SELECT * FROM owner TIMEOUT 0ns"),
]


def record_server_errors(args, folder):
    """Saves the reply to a request for each kind of error, in the database `roc_errors`."""
    server = Server(args.url, args.user, args.password)
    schema = (HERE / "fixtures" / "errors" / "schema.surql").read_text()
    for text, db in (("REMOVE DATABASE IF EXISTS roc_errors; DEFINE DATABASE roc_errors;", None), (schema, "roc_errors"), (ERROR_SEED, "roc_errors")):
        statements, error = server.run(text, db=db)
        assert error is None and all(s["status"] == "OK" for s in statements), (text, error or statements)
    session = Session(args.url, args.user, args.password, db="roc_errors")
    for name, text in ERRORS:
        session.recorded = []
        reply = session.call("query", [text])
        assert "error" in reply or any(s["status"] != "OK" for s in reply["result"]), (name, reply)
        (folder / f"{name}.cbor").write_bytes(session.recorded[-1])
    session.close()
    # Denied: a viewer of the database defines a table.
    viewer = Session(args.url, args.user, args.password, db="roc_errors",
                     login={"ns": NS, "db": "roc_errors", "user": "viewer", "pass": "viewer"})
    viewer.recorded = []
    viewer.call("query", ["DEFINE TABLE nope"])
    (folder / "denied.cbor").write_bytes(viewer.recorded[-1])
    viewer.close()
    # Conflict: transactions in flight that write one record, until one
    # fails at COMMIT, each on a session of its own.
    text = "BEGIN; UPDATE owner:cat SET age += 1; SLEEP 100ms; COMMIT;"
    for _ in range(20):
        sessions = [Session(args.url, args.user, args.password, db="roc_errors") for _ in range(3)]
        for one in sessions:
            one.recorded = []
            one.request(1000, "query", [text])
        replies = [(one, one.replies([1000])[1000]) for one in sessions]
        for one in sessions:
            one.close()
        conflicted = [one for one, reply in replies
                      if any(s.get("details", {}) and s["details"].get("kind") == "TransactionConflict" for s in reply["result"])]
        if conflicted:
            (folder / "conflict.cbor").write_bytes(conflicted[0].recorded[-1])
            break
    else:
        raise AssertionError("no transaction conflicted")
    server.run("REMOVE DATABASE roc_errors;", db=None)


# The requests of the two watches of `MuxTest.roc`: `Watch.request` of
# `Surreal.from(mux_a).select(|r| r).live({}, [])`, and the same on `mux_b`.
MUX_WATCH = ("LIVE SELECT VALUE {{ row: {{ id: record::id(id), v: v }}, now: true }} FROM {0};\n"
             "SELECT VALUE {{ ref: id, row: {{ id: record::id(id), v: v }} }} FROM {0};")


def record_mux(args, server, folder):
    """Records the frames of one session with two watches and requests in flight.

    Each case sends its requests with no wait, reads up to the reply of
    each, then the notices that come in 0.5 s. Its frames are saved as
    `folder/<case>/<nn>.cbor` in the order they came. A case with another
    count of frames is an error: `MuxTest.roc` imports each file.

    | Case | Requests | Frames |
    | --- | --- | --- |
    | start | 3: the watch of `mux_a`. 40: the watch of `mux_b` | 2 replies |
    | a | 10 `SLEEP 800ms`, 11 a create, 12 `RETURN`, 13 a create, 14 a select | 5 replies, 2 notices |
    | b | 20 `SLEEP 600ms`, and a write over HTTP while it runs | 1 reply, 2 notices |
    | c | 30 a create and a `RETURN` in one request | 1 reply, 1 notice |
    | two | 41 a create and an update on each table | 1 reply, 4 notices |
    | e | 50 a create, its reply read; then 51 `kill` of the watch of `mux_a`, 52 a create on `mux_b` | 3 replies, a notice and `KILLED` of `mux_a`, a notice of `mux_b` |
    """
    def write(text):
        statements, error = server.run(text)
        if error or any(s["status"] != "OK" for s in statements):
            raise RuntimeError(f"mux: {error or statements}")

    def case(name, requests, count, during=None):
        session.recorded = []
        for id, text in requests:
            session.request(id, "query", [text])
        if during:
            time.sleep(0.1)
            during()
        got = session.replies([id for id, _ in requests])
        session.drain(0.5)
        if len(session.recorded) != count:
            raise RuntimeError(f"mux: case {name} has {len(session.recorded)} frames, not {count}")
        frames[name] = frames.get(name, []) + session.recorded
        return got

    write("DEFINE TABLE OVERWRITE mux_a SCHEMALESS; DEFINE TABLE OVERWRITE mux_b SCHEMALESS; DELETE mux_a; DELETE mux_b;")
    session = Session(args.url, args.user, args.password)
    frames = {}
    try:
        started = case("start", [(3, MUX_WATCH.format("mux_a"))], 1)
        live_a = started[3]["result"][0]["result"]["value"]
        started = case("start", [(40, MUX_WATCH.format("mux_b"))], 1)
        live_b = started[40]["result"][0]["result"]["value"]
        case("a", [(10, "SLEEP 800ms; RETURN 'slow';"), (11, "CREATE mux_a:k1 SET v = 1;"), (12, "RETURN 'fast';"),
                   (13, "CREATE mux_a:k2 SET v = 2;"), (14, "SELECT * FROM mux_a;")], 7)
        case("b", [(20, "SLEEP 600ms; RETURN 'slow';")], 3, lambda: write("CREATE mux_a:k3 SET v = 3; DELETE mux_a:k1;"))
        case("c", [(30, "CREATE mux_a:k4 SET v = 4; RETURN 'after';")], 2)
        case("two", [(41, "CREATE mux_a:k5 SET v = 5; CREATE mux_b:k1 SET v = 1; UPDATE mux_a:k5 SET v = 6; UPDATE mux_b:k1 SET v = 2;")], 5)
        # The reply of 50 is read before the kill is sent, as `kill!` sends it
        # after the create; its notice comes before or after that reply.
        session.recorded = []
        session.request(50, "query", ["CREATE mux_a:k6 SET v = 6;"])
        session.replies([50])
        first = session.recorded
        session.recorded = []
        session.request(51, "kill", [Tagged(37, live_a)])
        session.request(52, "query", ["CREATE mux_b:k2 SET v = 2;"])
        session.replies([51, 52])
        session.drain(0.5)
        frames["e"] = first + session.recorded
        if len(frames["e"]) != 6:
            raise RuntimeError(f"mux: case e has {len(frames['e'])} frames, not 6")
        session.recorded = None
        session.request(60, "kill", [Tagged(37, live_b)])
        session.replies([60])
    finally:
        session.close()
        write("REMOVE TABLE mux_a; REMOVE TABLE mux_b;")
    for name, payloads in frames.items():
        (folder / name).mkdir(parents=True, exist_ok=True)
        for number, payload in enumerate(payloads):
            (folder / name / f"{number:02}.cbor").write_bytes(payload)


if __name__ == "__main__":
    main()
