# roc-reify-surrealdb

A SurrealDB ORM for Roc, built on reified functions.

Row types are plain Roc records. A table is a `Surreal.Table(row)` over one.
Every query clause, every projection and every database constraint is a Roc
function over that record. The builder takes the function as a `Code(f)`, so
the compiler describes it, and the translator turns the description into
SurrealQL. The function stays an ordinary Roc function: the same records are
the seed data, the arguments of the application's own functions, and the
inputs of its tests.

```roc
CityParam : { city : Str }

in_city : CityParam, Owner -> Bool
in_city = |p, o| o.address.city == p.city

OwnerCard : { id : Str, name : Str, phone : Str }

owner_card : Owner -> OwnerCard
owner_card = |o| { id: o.id, name: o.name, phone: o.?phone ?? "none" }

Surreal.from(owners).filter_by(in_city).select(owner_card).order_by(|r| r.id, Asc).prepare({ city: "Oslo" })
```

```surql
LET $city = 'Oslo';
SELECT record::id(id) AS id, name AS name, phone ?? 'none' AS phone FROM owner WHERE address.city = $city ORDER BY id;
```

`in_city` and `owner_card` are ordinary Roc functions. The program calls them
on its own rows too (`examples/main.roc`).

**This package needs the reify fork of the Roc compiler.** `Code(f)` is a type
of that fork. Stock Roc has no `Code` type, and these sources do not compile
with it. See [Requirements](#requirements).

| Item | Value |
| --- | --- |
| Modules | `Surreal` (the whole public API). `src/internal.roc` is a second header that also exposes `Ql`, `Encode`, `Types`, `Translate`, `Schema`, `Diff`, `Rpc` and `HttpRpc`, for the tests |
| Dependencies | [roc-cbor](https://github.com/Karakatiza666/roc-cbor) 0.4.0, [roc-websocket](https://github.com/Karakatiza666/roc-websocket) 0.0.4 |
| Examples only | [roc-basic-cli-websocket](https://github.com/Karakatiza666/roc-basic-cli-websocket) 0.0.1 (basic-cli 0.26.0), [roc-basic-webserver-websocket](https://github.com/Karakatiza666/roc-basic-webserver-websocket) 0.0.1 (basic-webserver 0.20.0) |
| Compiler | the `reify` branch of [Karakatiza666/roc](https://github.com/Karakatiza666/roc), at or after commit `846019dd8d` (based on Roc nightly 2026-11-01) |
| Database | SurrealDB 3.3.4 |
| Tests | `scripts/all_tests.sh` |
| License | UPL-1.0 (`LICENSE`) |

The package covers:

- tables, links, edge tables and read rows, with the schema built from the
  row types and from clauses (`ASSERT`, `UNIQUE`, `DEFINE EVENT`, computed
  fields, permissions);
- queries and writes, with parameters and captured values;
- Roc functions as SurrealDB functions, time series keys, views, geometry,
  full-text and vector search;
- live queries, with the Roc prediction of their notices (the `Mirror`);
- sessions over WebSocket or HTTP, with typed results and typed errors;
- translator extensions for types the package does not know.

`roc examples/main.roc` prints one SurrealQL script: the schema, the seed
rows, the queries, the writes the database must refuse, and the writes it must
accept. `tests/check.py` runs it on a real server and compares each query with
the result that Roc computes from the same functions over the same rows.

## Requirements

The compiler is the `reify` branch of
[github.com/Karakatiza666/roc](https://github.com/Karakatiza666/roc), at or
after commit `846019dd8d`. It is based on Roc nightly 2026-11-01. Build it as
the compiler repo says and point `ROC` at the `roc` binary it makes:

```sh
export ROC=/path/to/fork/zig-out/bin/roc
```

The language feature is described in
[docs/langref/reifying.md](https://github.com/Karakatiza666/roc/blob/reify/docs/langref/reifying.md)
of that repo. A function that stands where the type says `Code(f)` is
described at compile time and passed to the library as data. The library
translates it, and the compiler still checks it as an ordinary function.

SurrealDB is needed to run the checks and the apps. The version the package is
tested on is 3.3.4.

## Setup

The package is not released yet. The examples name it by a local path, from
the `examples/` folder:

```roc
surreal: "../src/main.roc",
```

An app of your own names the path of this checkout, for example
`surreal: "/path/to/roc-reify-surrealdb/src/main.roc"`. A release URL will
replace the path when the package is released, as it does for the other
packages of the header.

The package brings roc-cbor and roc-websocket. An app that uses `Cbor`
itself (`Cbor.Value`, as `examples/client.roc` does for patch ops) names
roc-cbor in its own header too.

A session reaches the server through a `Transport`, and the transport comes
from the platform. A platform needs a WebSocket adapter package for it, or an
HTTP function of its own (see "Transports" below).

### Connect on basic-cli

The app names basic-cli and the WebSocket adapter
[roc-basic-cli-websocket](https://github.com/Karakatiza666/roc-basic-cli-websocket):

```roc
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.26.0/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t.tar.zst",
	cli_ws: "https://github.com/Karakatiza666/roc-basic-cli-websocket/releases/download/0.0.1/7GBAW8zCyUjhD1MuDzJpR4mYYNajtMjyNjvqSKUhKHmm.tar.zst",
	surreal: "../src/main.roc",
}

import pf.OsStr
import pf.Stdout
import cli_ws.WsClient
import surreal.Surreal
```

The transport and the login, as in `examples/watch.roc` and
`examples/client.roc`:

```roc
login : Surreal.Login
login = Root({ ns: "roc", db: "roc_surreal", user: "root", pass: "root" })

transport : Surreal.Transport
transport = Surreal.Transport.websocket(WsClient.connect, WsClient.ops, "ws://127.0.0.1:8000")
```

`WsClient.connect` and `WsClient.ops` are the adapter's connect feature and
its operations. The session connects to the URL plus `/rpc`, with the
subprotocol `cbor`. Then open a session and run a prepared statement. Each
call gives the session back, and `result` holds the rows as the Roc type of
the query:

```roc
run! : I64 => Try(List(Reading), Str)
run! = |least| {
	prepared = readings_above(least).map_err(Str.inspect)?
	session = Surreal.Session.open!(transport, login).map_err(Str.inspect)?
	session.run!(prepared).result.map_err(Str.inspect)
}

main! : List(OsStr) => Try({}, _)
main! = |_args| match run!(120) {
	Ok(rows) => Stdout.line!("${rows.len().to_str()} readings")
	Err(why) => Stdout.line!("failed: ${why}")
}
```

`Reading` and `readings_above` are in `examples/server.roc`. The app above
checks with the fork's compiler. `examples/client.roc` is the long form: plain
queries and writes, each checked against the result that Roc computes.
`examples/watch.roc` starts live queries on the same kind of session.

On basic-cli the same app runs over HTTP when the transport is
`Surreal.Transport.http(http_client, "http://127.0.0.1:8000")`, with the
`http_client` of `examples/client.roc` (`roc examples/client.roc -- --http`).
A live query needs the WebSocket: over HTTP `live!` is `Unsupported`.

### Connect on basic-webserver

The app names basic-webserver and
[roc-basic-webserver-websocket](https://github.com/Karakatiza666/roc-basic-webserver-websocket),
as in `examples/server.roc`:

```roc
app [Context, program] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.4.0/EnfRKFT7uPHmd3zT5PcwAiBWUtGmBXapJqFK5166U33J.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.20.0/7dR2ewuEbpPQXTAZL3aH62weBwpNNjbCJtyyiRsufTNZ.tar.zst",
	bws_ws: "https://github.com/Karakatiza666/roc-basic-webserver-websocket/releases/download/0.0.1/AZvwBodinTMyUrV1ikMs9qicuYd3p7EXvFCYcZ6Zwn2A.tar.zst",
	surreal: "../src/main.roc",
}

import pf.Server
import http.Response
import bws_ws.WsClient
import surreal.Surreal
```

The transport and the login are the same as on basic-cli, with the adapter of
the platform:

```roc
transport : Surreal.Transport
transport = Surreal.Transport.websocket(WsClient.connect, WsClient.ops, "ws://127.0.0.1:8000")

login : Surreal.Login
login = Root({ ns: "roc", db: "roc_surreal", user: "root", pass: "root" })
```

A handler opens a session of its own and runs the query:

```roc
run! : I64 => Try(List(Reading), Str)
run! = |least| {
	prepared = readings_above(least).map_err(Str.inspect)?
	session = Surreal.Session.open!(transport, login).map_err(Str.inspect)?
	session.run!(prepared).result.map_err(Str.inspect)
}
```

A session lives for one request on basic-webserver. The platform scopes a
connection to the handler that opened it, and each TCP read times out after
30 s, so a session cannot outlive its request. A watch waits for notices with
no end, so it has no place in a handler. Open the session in the handler, run
what the request needs, and let the session end with it.

The same server runs over HTTP. In the comment next to `transport` in
`examples/server.roc`:

```roc
transport : Surreal.Transport
transport = Surreal.Transport.http(http_client, "http://127.0.0.1:8000")

http_client : Surreal.HttpClient
http_client = {
	post!: |post| {
		request = post.headers.fold(Request.from_method(POST).with_uri(post.uri).with_body(post.body), |r, h| r.add_header(h.name, h.value))
		response = Http.send!(request).map_err(Str.inspect)?
		Ok({ status: response.status(), body: response.body() })
	},
}
```

Put these in place of the WebSocket `transport`, add `import pf.Http` and
`import http.Request`, and drop the `bws_ws` package. A plain query is then one
post. A query that runs longer than the 30 s of `Http.send!` is a `Transport`
error.

`examples/server.roc` serves `GET /readings?min_pulse=N` on 127.0.0.1:8001:

```
$ roc examples/server.roc &
$ curl 'http://127.0.0.1:8001/readings?min_pulse=120'
kennel b at 2026-03-01T23:59:59Z: pulse 130, temp_c 38.0
kennel a at 2026-03-02T09:15:00Z: pulse 125, temp_c 38.0
kennel b at 2026-03-02T11:00:00Z: pulse 121, temp_c 39.1
kennel b at 2026-03-01T10:00:00Z: pulse 120, temp_c 39.0
```

## What is in the repository

| File | What it is |
| --- | --- |
| `src/main.roc` | The package header. It exposes `Surreal`, and depends on roc-cbor 0.4.0 for the CBOR of a live session and on roc-websocket 0.0.4 for the types of a WebSocket adapter. |
| `src/Surreal.roc` | The public API: ids, links, read rows (`Linked`, `Out`, `In`), datetimes, tables, the schema builder, queries and writes, live queries, `Mirror` (the Roc prediction of their notices, and the `-- roc:` literals that `check.py` compares), and `Unchecked` (the escape hatch: `SELECT *`, `FETCH`, record ids by text, decoding, and a raw `query!` with its `result`). The `parser_for` of each SurrealDB value, the reading of the messages of a live session, the `Session` itself with its `Inbox` of the replies and the notices that it read, the `Connection` that it runs on (a WebSocket, or HTTP), the patches of `live_diff` (`Patch`, `DiffView`), and the typed results of plain queries and writes (`Prepared`). Also the package functions for SurrealDB (`Text`, `Hash`, `Array`, `Time`, `Math`, `Rand`, `Vector`), analyzers and the full-text and vector indexes with their searches (`Analyzer`, `FullText`, `VectorIndex`, `Hit`, `Near`), database functions (`DbFn`), time series keys (`TimeKey`), views, the geometry types (`Point`, `Polygon`, ..) and their functions (`Geo`). |
| `src/Translate.roc` | The translator. A `Code` graph in, a SurrealQL expression out. It knows a call by the id of its definition: the builtins in its own table, the functions of `Surreal` in the extension `Surreal.library`, and an app's in the extensions it passes (see "Extending the translator"). |
| `src/Schema.roc` | `DEFINE` statements from row types, builder clauses and database functions. It also writes the delete policy of every link. |
| `src/Types.roc` | Roc types as SurrealDB types, the `BadSchema` checks, and the list of link sites of a row. `Types.nominal` is the one place that knows a nominal type by its name. |
| `src/Encode.roc` | The format that the derived `encoder_for` runs against. It turns a row into a SurrealQL literal. `Encode.Bind` is the byte format of a value that `select_where_with` captures, which reads back as the same literal. |
| `src/Ql.roc` | SurrealQL text: values, quoting, identifiers and the error type, with the errors of a live session (`Wire`, `Server`, `Transport`). |
| `src/Diff.roc` | The ops of `LIVE SELECT DIFF`: the paths, the text patches, and each op applied to a stored row as a `Cbor.Value`. |
| `src/Rpc.roc` | The RPC requests of a live session (`signin`, `signup`, `authenticate`, `invalidate`, `use`, `query`, `kill`), and the uuid of a live query (CBOR tag 37). |
| `src/HttpRpc.roc` | The RPC over HTTP, pure: the `POST /rpc` of a message, with its headers and the authentication of the session (Basic for a system user, the `Bearer` token of a record user), and the reply in its response. |
| `examples/main.roc` | A veterinary clinic: rows, constraints, seeds, queries, writes, and the script. |
| `examples/Clinic.roc` | The functions of `main.roc` over the rows of visits and medications, each annotated with an open row (`{ seen : Surreal.Datetime, ..r }`), some of them calling another, and two query fragments (`recent`, `by_id`). |
| `examples/builtins.roc` | Tables with seed rows for the builtin mappings and for the package functions (`Text`, `Hash`, `Array`, `Time`, `Math`, `Rand`, `Geo`, `Id.table`). It prints its own script, with a Roc result for each of its 46 queries and writes. |
| `examples/monitoring.roc` | Sites, the kennels at them, and the vital signs of their animals, a time series keyed by kennel and time. A Roc function is the database function `fn::fever`, which a filter, a projection, a computed field and a view call. A range query and its whole rows, a daily rollup, its view, a changefeed and a retention delete. Filters of result rows: after a projection, after a group (`HAVING`) and after an order and a limit. A site has a location and an area: queries find the sites whose area holds a point and the sites near it. Carers look after kennels through the edge table `cares_for`, and check them through the edge table `checks`. A read row of a kennel reads its site and its carers with no `.get()` and no `incoming`, and a query reads the rows of the readings in a clause: a count per kennel and a semi join. Eleven live queries: the fevered readings, the readings above a parameter, the daily view, the kennels with no carer (with `incoming`, and through the read row), the kennels with a fever, the kennels with the name of their site (through the read row), the kennels at the site named Oslo (through `.get()`), the kennels with no carer and no check (two edge tables), and the two escape hatches. It prints its own script, which `check.py` runs. |
| `examples/search.roc` | The chart notes of a clinic, searched by their text and by their embeddings: an analyzer, a full-text index and an HNSW vector index of one table, searches with their scores, highlights and offsets, the nearest notes to a probe, the `Vector` functions in a projection and a filter, and a write of the wrong dimension that the index refuses. It prints its own script, which `check.py` runs. |
| `examples/watch.roc` | An app on basic-cli 0.26.0: a live session on a running server. It starts eight watches, makes writes on the same session, two of them in flight together, and checks each change and each patch that the server sends against the Roc Mirror. Four of them watch the links that the clauses read, in a database of their own. |
| `examples/client.roc` | An app on basic-cli 0.26.0: plain queries and writes in a session on a running server, on a WebSocket or, with `-- --http`, over HTTP, each read as the Roc type of its result and checked against the result that Roc computes from the same functions. Its rows with a tag union show each form of an arm, and a union with a payload of each kind: a geometry, a link, a datetime, a nominal record and two values, each also written from fields of the row. Its shifts, tasks and handovers have keys that the server makes. Two record users sign up through an access method of its own, and each reads and writes only the memos that the permissions of the table give it; a token is reused and a session is invalidated. Its case notes are searched by their text, with scores and highlights, and by their embeddings. |
| `examples/server.roc` | An app on basic-webserver 0.20.0: a web server whose `GET /readings?min_pulse=N` runs a typed query in a WebSocket session of its own, through roc-basic-webserver-websocket, and answers with its rows. |
| `examples/refactored.roc` | `main.roc` with the parameters of the reified functions renamed and bindings added, reordered, inlined and extracted. Like `main.roc`, it gives `Owner.tags` and `Medication.stock` `??` defaults in their types, and takes the constraints and the query fragments from `Clinic.roc`. It prints `expected_output.surql` byte for byte, which its last `expect` checks. |
| `tests/TypesTest.roc` | Tests of `Types` and the table constructors on a small domain. |
| `tests/TranslateTest.roc` | Tests of the translator, one per kind of clause. |
| `tests/Temperature.roc` | An opaque `Temperature`, as a package of its own would declare it. It knows nothing of SurrealDB. |
| `tests/ExtensionTest.roc` | Tests of an extension of the translator for `Temperature`: its functions in a clause, a captured temperature, and the refusals without the extension. |
| `tests/SchemaTest.roc` | Tests of the schema builder, of the link policies, of access methods and permissions, and of analyzers (with the Roc meaning of their terms) and full-text and vector indexes. |
| `tests/QueriesTest.roc` | Tests of queries, parameters, captured values, writes, the statements of live queries and their refusals, and clauses that read the record user of the session, full-text searches and nearest rows, and their refusals. |
| `tests/LiveTest.roc` | Tests of the Mirror of the notices of each write, of `Watch.step` and of `View`. |
| `tests/DiffTest.roc` | Tests of the text patches, the paths and the ops of `LIVE SELECT DIFF`, of `DiffView` and of `Patch.field`, with patches that SurrealDB sent. |
| `tests/DecodeTest.roc` | Tests of the decoding of a live session: the values of SurrealDB, the reply to a watch, notices, changes and raw events, from messages that SurrealDB sent. |
| `tests/PreparedTest.roc` | Tests of the typed results of plain queries and writes: the text of each request, and the replies that SurrealDB sent to `client.roc`, read as the type of each query, rows with a tag union too, and a search with its scores and the nearest notes. |
| `tests/MuxTest.roc` | Tests of the `Inbox` of a session: the frames of one session with two watches and requests in flight, in the order that SurrealDB sent them. |
| `tests/RpcTest.roc` | Tests of the RPC requests and the uuid. |
| `tests/ErrorTest.roc` | Tests of the typed errors of the server: a reply of each kind of error that SurrealDB sent, read as a `ServerError`, the constraints of a schema read back as `Unique`, `Assert`, `Check` and `Referenced`, and the messages of the constraints. |
| `tests/HttpTest.roc` | Tests of the posts of a session over HTTP, with the authentication of each login, of the replies in their responses, and of replies that SurrealDB sent over HTTP, read through the `Inbox` in another order than they were sent. |
| `tests/fixtures/` | Messages of a live session that SurrealDB 3.3.4 sent, one file each, in `fixtures/queries/` the replies to the requests of `client.roc`, in `fixtures/http/` the same replies over HTTP (`client.roc -- --http`), in `fixtures/mux/` the frames of one session with two watches and requests in flight, and in `fixtures/errors/` a reply of each kind of error (`check.py --record fixtures`). |
| `tests/check.py` | Runs the scripts of `main.roc`, `builtins.roc`, `monitoring.roc` and `search.roc` on SurrealDB and compares every block, the live blocks in a WebSocket session, then runs `watch.roc`, `client.roc` on a WebSocket and over HTTP, and `server.roc`, which it asks for a query over HTTP. With `--record DIR`, it saves the messages of each live block, the replies to `client.roc` on both transports and the frames of `MuxTest.roc`. Python standard library only. |
| `examples/expected_output.surql` | What `roc main.roc` prints. |
| `scripts/all_tests.sh` | The local checks: `roc check` of the package and the examples, `roc test` of the package and of every test file, and `tests/check.py` when SurrealDB answers on 127.0.0.1:8000. |
| `LICENSE` | UPL-1.0. |

## Testing

`scripts/all_tests.sh` runs all the checks. Point `ROC` at the fork's `roc`:

```sh
ROC=/path/to/fork/zig-out/bin/roc scripts/all_tests.sh
```

It runs `roc check` on `src/main.roc`, `src/internal.roc` and every example,
`roc test` on `src/main.roc` and on every `tests/*Test.roc`, and, when
SurrealDB answers on 127.0.0.1:8000, `tests/check.py`, which runs the scripts
and the apps of the examples against it.

There is no public SurrealDB endpoint to run against. Surrealist's sandbox
runs in the browser as WASM, so it has no address that a script can reach.
Start a local server instead:

```sh
docker run --rm -d --name surreal-roc -p 8000:8000 surrealdb/surrealdb:v3.3.4 start --user root --pass root memory
```

Without a server, the script skips `tests/check.py` and says so. Stop the
server with `docker stop surreal-roc`.

One check at a time, from the repository root (`roc` is the fork's):

```sh
roc examples/main.roc                  # the SurrealQL script
roc examples/main.roc | diff - examples/expected_output.surql
roc examples/builtins.roc              # the SurrealQL script of the builtin rows
roc examples/monitoring.roc            # the SurrealQL script of the database functions, the time series and the geometry
roc examples/search.roc                # the SurrealQL script of the full-text and vector search
roc test examples/main.roc             # the expects of main.roc and of the modules it imports
roc test examples/builtins.roc         # the expects of builtins.roc
roc test examples/monitoring.roc       # the expects of monitoring.roc
roc test examples/search.roc           # the expects of search.roc
roc test examples/refactored.roc       # the same, and the script is expected_output.surql
roc test tests/TypesTest.roc
roc test tests/TranslateTest.roc
roc test tests/ExtensionTest.roc
roc test tests/SchemaTest.roc
roc test tests/QueriesTest.roc
roc test tests/LiveTest.roc
roc test tests/DiffTest.roc
roc test tests/RpcTest.roc
roc test tests/DecodeTest.roc
roc test tests/PreparedTest.roc
roc test tests/MuxTest.roc
roc test tests/HttpTest.roc
python3 tests/check.py "$ROC"     # run the four scripts on SurrealDB 3.3.4, compare with Roc
roc examples/watch.roc                 # check.py runs it: a live session on the server, checked against the Mirror
roc examples/client.roc                # check.py runs it: plain queries with typed results, checked against Roc
roc examples/client.roc -- --http      # check.py runs it: the same queries in a session over HTTP
roc examples/server.roc                # check.py runs it last: a web server on 127.0.0.1:8001 that runs a query in a WebSocket session
python3 tests/check.py --record tests/fixtures   # record the messages again
```

The package depends on roc-cbor and roc-websocket by their release URLs
(`src/main.roc`). A file with no header gets no dependency. Each app names
the package (`surreal: "../src/main.roc"`), which brings the dependencies.
Each test file names roc-cbor and `src/internal.roc`
(`internal: "../src/internal.roc"`), a second package header that exposes every
module, for the tests of the internal modules. `watch.roc` and `client.roc`
name basic-cli, roc-cbor and the WebSocket adapter roc-basic-cli-websocket, and
`server.roc` names basic-webserver, roc-cbor and roc-basic-webserver-websocket.
`client.roc` and `server.roc` also name the `http` package of their platform,
for its `Request` and `Response`.

`tests/check.py` takes the path of `roc` as its first argument (default
`roc`). It runs `main.roc`, then `builtins.roc`, then `monitoring.roc`, then
`search.roc` in one fresh database, then `watch.roc`, `client.roc`,
`client.roc -- --http` and `server.roc` on it. It reads `SURREAL_URL` (default
`http://localhost:8000`), `SURREAL_USER` and `SURREAL_PASS` (default `root`).
It prints one line for each block and exits with 0 when all blocks agree. It
removes and creates its own database at the start.

| Block header | What the checker does |
| --- | --- |
| `-- schema`, `-- seed: T` | Every statement must succeed. |
| `-- query: N`, `-- write: N` | The last statement result must equal the `-- roc:` literal. `-- ordered` keeps the order. Without it, the rows are compared as a multiset. `-- intrinsic: score` names the columns whose value reads an intrinsic, which the library writes from the clause (`Statement.block`): the literal may leave out these columns, and no other, and a column it leaves out is not compared. A literal that leaves out any other column fails, and three blocks of `check.py`'s own (`self: ..`) show it. |
| `-- rejects: N` | Some statement must fail, and its error must contain the `-- error:` text. |
| `-- live: N` | A live query (see "Live queries"). The request runs in a WebSocket session. Each write after a `-- write` line runs over HTTP, and the notices that arrive must equal the list of that write in the `-- roc:` literal, as a multiset. `-- roles:` names the statement of each `LIVE` (`node`, `edge`, `read`). A message of a `read` statement holds a list of rows, and each is one notice. `-- snapshot:` is the rows of the snapshot. Each live query is then killed with the RPC method `kill`, and must send `KILLED`. |
| `app: watch.roc`, `app: client.roc`, `app: client.roc --http` | The app runs on the database that the scripts leave, and must exit with 0. Not with `--script`. |
| `app: server.roc` | The server starts, `GET /readings?min_pulse=120` must answer with the four readings of that pulse or more, and `min_pulse=many` with status 400. Then the checker stops it. Not with `--script`. |

The `-- roc:` literal is a SurrealQL value that Roc printed. The checker sends
`RETURN <literal>` to the same server, so both sides use one serialiser.
It asks for CBOR, not JSON. JSON prints a decimal as a string, so the decimal
`42` and the string `"42"` look the same. CBOR tags a decimal, so the checker
treats a number-like string as a string, and only a tagged decimal is
compared as a decimal. A string field `"42"` against the number `42` fails.

## What it covers

The first rows are the three headline features: constraints of each kind, links
in nested fields with the same constraints as top-level ones, and unions as
Roc tag unions with `match` in a query.

| Feature | Roc | SurrealQL | Where |
| --- | --- | --- | --- |
| Check over one field | `.check("weight above zero", \|p\| p.weight_kg > 0)` | `weight_kg ... TYPE decimal ASSERT $value > 0.0dec` | `examples/main.roc:382` |
| Check over several fields | `.check("items need a fee", Clinic.fee_covers_items)` | `DEFINE EVENT ... ON visit WHEN $event IN ['CREATE', 'UPDATE'] THEN { IF !(..) { THROW 'visit: items need a fee' } }` | `examples/main.roc:395` |
| Check on an edge table | `.check("since a real year", \|e\| e.since_year >= 1990)` | `since_year ON treats TYPE int ASSERT $value >= 1990` | `examples/main.roc:405` |
| Assert on a field, with a function the program also calls | `.assert(\|o\| o.email, valid_email)` | `ASSERT string::contains($value, '@') AND (!string::starts_with($value, '@'))` | `examples/main.roc:353` |
| Assert on a nested path, with a SurrealDB function | `.assert(\|v\| v.contact.email, \|e\| Surreal.Text.is_email(e))` | `DEFINE FIELD contact.email ON vet TYPE string ASSERT string::is_email($value)` | `examples/main.roc:364` |
| Assert on each element | `.assert_each(\|o\| o.tags, \|t\| t != "")` | `tags ... ASSERT $value.all(\|$item\| $item != '')` | `examples/main.roc:354` |
| Assert on a field of each record in a list | `.assert_each(\|v\| v.items, Clinic.positive_doses)` | `items[*].doses ON visit TYPE int ASSERT $value > 0` | `examples/main.roc:393` |
| Assert on a union | `.assert(\|p\| p.species, possible_species)` | `species ... ASSERT (IF $value.kind = 'Bird' THEN $value.wingspan_cm > 0 ELSE true END)` | `examples/main.roc:380` |
| Unique, with a nested path | `.unique(\|v\| v.contact.email)` | `DEFINE INDEX ... ON vet FIELDS contact.email UNIQUE` | `examples/main.roc:363` |
| Unique, over several fields and a link | `.unique(\|p\| { name: p.name, owner: p.owner })` | `DEFINE INDEX ... ON patient FIELDS name, owner UNIQUE` | `examples/main.roc:379` |
| Unique, over the ends of an edge | `.unique(\|e\| { from: e.from, to: e.to })` | `DEFINE INDEX ... ON treats FIELDS in, out UNIQUE` | `examples/main.roc:406` |
| Index | `.index(\|o\| o.address.city)` | `DEFINE INDEX ... ON owner FIELDS address.city` | `examples/main.roc:356` |
| Default value from the type | `tags : List(Str) ?? []` in `Owner := { .. }`, `stock : I32 ?? 0` in `Medication := { .. }` | `tags ... TYPE array<string> DEFAULT []`, `stock ... TYPE int DEFAULT 0` | `examples/main.roc:26`, `examples/main.roc:43` |
| Default value of an alias row | `.default(\|c\| c.tags, ["new"])` | `tags ... TYPE array<string> DEFAULT ['new']` | `tests/SchemaTest.roc:75` |
| Computed field | `.computed(\|m\| m.label, \|m\| label_of(m.name, m.form))` | `label ON medication TYPE string VALUE $this.name + ' (' + $this.form + ')'` | `examples/main.roc:373` |
| Read-only field | `.readonly(\|v\| v.license)` | `license ON vet TYPE string READONLY ASSERT ..` | `examples/main.roc:366` |
| Range from the Roc type | `Vet : VetRow(U8)`, `stock : I32` | `years ... TYPE int ASSERT $value >= 0 AND $value <= 255` | `examples/main.roc:39` |
| Link in an optional object | `chip ?: { code : Str, implanted_by : Surreal.Link(Vet) }` | `chip.implanted_by ... TYPE record<vet> ASSERT record::exists($value)`, and an event on `vet` that throws on delete | `examples/main.roc:58` |
| Link in a list of records | `vaccines : List({ name : Str, given : Str, vet : Surreal.Link(Vet) })` | `vaccines[*].vet ... TYPE record<vet> ASSERT record::exists($value)`, and an event on `vet` | `examples/main.roc:55` |
| Link in a list of records, second site | `items : List({ medication : Surreal.Link(Medication), doses : I64 })` | `items[*].medication ... ASSERT record::exists($value)`, and an event on `medication` | `examples/main.roc:72` |
| Link in a union arm | `Referred({ to : Surreal.Link(Vet), reason : Str })` | `IF $value.kind = 'Referred' THEN record::exists($value.to) ELSE true END`, and an event on `vet` | `examples/main.roc:75` |
| Optional link to a row of the same table | `referred_by ?: Surreal.Link(Owner)` in `Owner := { .. }`, `.on_delete(owners, Unset)` | `referred_by ON owner TYPE option<record<owner>> REFERENCE ON DELETE UNSET ASSERT ($value = NONE OR (record::exists($value)))` | `examples/main.roc:26` |
| Top-level link, same constraints | `owner : Surreal.Link(Owner)`, `.on_delete(owners, Cascade)` | `owner ... TYPE record<owner> REFERENCE ON DELETE CASCADE ASSERT record::exists($value)` | `examples/main.roc:385` |
| Top-level list of links, per-path policy | `allergies : List(Surreal.Link(Medication))`, `.on_delete_at(\|p\| p.allergies, Unset)` | `allergies ... TYPE array<record<medication>> ... REFERENCE ON DELETE UNSET` | `examples/main.roc:387` |
| A write that names a missing target is refused at every depth | `patients.create(ghost_chip_patient)`, and one row for each other shape | `ASSERT record::exists($value)` fails for the field `chip.implanted_by` | `examples/main.roc:953` |
| A delete of a target in use is refused at every depth | `vets.delete_at(vets.id("tia"))` | the event throws: `is referenced by visit.outcome.to` | `examples/main.roc:957` |
| A tag union is a literal union | `Species : [Dog, Cat, Bird({ wingspan_cm : U8 }), Exotic({ latin : Str })]` | `TYPE { kind: "Bird", wingspan_cm: int } \| "Cat" \| "Dog" \| { kind: "Exotic", latin: string }` | `examples/main.roc:52` |
| `match` in a projection | `species_label(p.species)` with `match` on `Dog`, `Cat`, `Bird(_)`, `Exotic(other)` | `(IF species.kind = 'Bird' THEN 'bird' ELSE IF species = 'Cat' THEN 'cat' ELSE IF species = 'Dog' THEN 'dog' ELSE species.latin END)` | `examples/main.roc:133` |
| `match` in a filter | `wide_wings(p)` reads the wingspan of `Bird(wings)` | `WHERE (IF species.kind = 'Bird' THEN species.wingspan_cm >= 20 ELSE false END)` | `examples/main.roc:154` |
| `match` that reads a link in an arm | `Referred(r) => "referred to ${r.to.get().name}"` | `'referred to ' + outcome.to.name` | `examples/main.roc:144` |
| `match` on an optional object | `match p.?chip { Ok(c) => .., Err(_) => .. }` | `(IF chip IS NONE THEN 'nobody' ELSE chip.implanted_by.name END)` | `examples/main.roc:449` |
| A union in a write | `{ ..v, years: v.years + 1, specialty: Surgery({ board: "ECVS" }) }` | `UPDATE vet:⟨tia⟩ SET specialty = { kind: 'Surgery', board: 'ECVS' }, years = years + 1 RETURN AFTER` | `examples/main.roc:551` |
| A union in a write that reads the row | `{ ..p, place: Since(p.at) }`. Each `SET` item reads the row before the update, as Roc does (verified) | `UPDATE placement:⟨away⟩ SET place = { kind: 'Since', value: at } RETURN AFTER` | `examples/client.roc:397` |
| `==` on a union | `.filter(\|o\| o.kind == o.prev)`, against a parameter or against a literal arm. The derived `==` expands into `match`es | `(IF kind.kind = 'Firm' THEN (IF prev.kind = 'Firm' THEN kind.vat = prev.vat ELSE false END) ELSE (IF prev.kind = 'Firm' THEN false ELSE true END) END)`. A run on SurrealDB 3.3.4 keeps the rows that agree in kind and payload | |
| A parameter record | `filter_by(in_city)`, `.prepare({ city: "Oslo" })` | `LET $city = 'Oslo'; .. WHERE address.city = $city` | `examples/main.roc:414` |
| Optional field with `??` | `o.?phone ?? "none"` | `phone ?? 'none'` | `examples/main.roc:420` |
| `.?` on an optional self-link | `match o.?referred_by { Ok(r) => r.get().name, Err(_) => "nobody" }` | `(IF referred_by IS NONE THEN 'nobody' ELSE referred_by.name END)` | `examples/main.roc:428` |
| A link read with `get()` | `p.owner.get().name` | `owner.name` | `examples/main.roc:441` |
| A link compared by id | `v.vet.id() == ruth_id` | `$v1.vet = vet:⟨ruth⟩` | `examples/main.roc:466` |
| The same, with the field `id` | `v.vet.id == ruth_id` | `$v1.vet = vet:⟨ruth⟩` | `tests/QueriesTest.roc:626` |
| Fields through links, with no `FETCH` | `contact_line` reads `p.owner.get().address.city` and `p.vaccines.map(\|v\| v.vet.get().name)` | `owner.address.city AS city, .. vaccines.map(\|$v1\| $v1.vet.name) AS vets` | `examples/main.roc:874` |
| Whole linked rows | `{ id: p.id, owner: p.owner.get(), vets: p.vaccines.map(\|v\| v.vet.get()) }` | `owner.{ address, email, id: record::id(id), name, .. } AS owner, vaccines.map(\|$v1\| $v1.vet.{ contact, id: record::id(id), .. }) AS vets` | `examples/main.roc:880` |
| The whole row of the table | `.between(kennel_a, day_start, day_end).select(\|r\| r)` | `SELECT fevered, record::id(id) AS id, pulse, temp_c FROM vital:[..]..[..]` | `examples/monitoring.roc:346` |
| A read row: a link read with no `get()` | `site : Surreal.Linked(Site)`, then `k.site.name` | `site.name` | `examples/monitoring.roc:77` |
| The edges at a row as a field of a read row | `cares_for : Surreal.In(CareRead)`, then `k.cares_for.list().map(\|e\| e.from)` | `<-cares_for.map(\|$v1\| $v1.in.{ id: record::id(id), name })` | `examples/monitoring.roc:414` |
| A read row agrees with its stored row | `kennel_reads.define_read()` in the schema list | None. A field, a link or an edge table that does not agree is a `BadSchema` | `examples/monitoring.roc:116` |
| The rows of a table in a clause: a correlated count | `vitals.rows().keep_if(\|v\| v.id.series() == kennels.id(k.id)).len()` | `(SELECT VALUE id FROM vital).filter(\|$v1\| record::id($v1)[0] = type::record('kennel', record::id(id))).len()` | `examples/monitoring.roc:420` |
| A semi join | `.filter(\|k\| vitals.rows().any(\|v\| .. and v.fevered))` | `WHERE (SELECT VALUE id FROM vital).any(\|$v1\| .. AND $v1.fevered)` | `examples/monitoring.roc:425` |
| The id of a row of a table, read in a clause | `ruth_id = vets.id("ruth")` | `vet:⟨ruth⟩` | `examples/main.roc:116` |
| Graph traversal | `.outgoing(treats)`, `.incoming(treats)` with `edges.keep_if(..).len()` | `->treats.len()`, `<-treats.filter(\|$v1\| $v1.primary).map(..)` | `examples/main.roc:832` |
| An edge table in the wrong direction is a type error | `Surreal.from(products).outgoing(purchased)` | None: `outgoing` needs a table whose `from` links to `product` | `Query.outgoing` |
| A count as `I64` | `edges.len().to_i64_wrap()` | `->treats.len()` (the conversion is the identity) | `examples/main.roc:487` |
| Group and aggregate | `.group_by(\|v\| v.vet.get().name).aggregate(ledger_line)` | `math::sum(fee) AS revenue, vet.name AS vet, count() AS visits .. GROUP BY vet` | `examples/main.roc:844` |
| A statistic over a group | `avg_fee: Surreal.Math.mean(rows.map(\|v\| v.fee.to_f64()))` in `ledger_line` | `math::mean(<float>fee) AS avg_fee .. GROUP BY vet` | `examples/main.roc:498` |
| Totals of all matching rows | `.totals(visit_totals)` with `rows.len()`, `rows.map(\|v\| v.fee).sum()` and `Math.mean(..)` | `SELECT math::mean(<float>fee) AS avg_fee, math::sum(fee) AS revenue, count() AS visits FROM visit GROUP ALL`, read as one `VisitTotals`, not a list (`Totals.prepare`) | `examples/main.roc:1129` |
| Totals of no rows | `.filter(\|v\| v.fee > 1000).totals(\|rows\| { visits: rows.len().to_i64_wrap() })` | `SELECT count() AS visits FROM visit WHERE fee > 1000.0dec GROUP ALL`: one row, `visits: 0`. With a sum and a mean it is `revenue: 0` and `avg_fee: NaN` (verified on 3.3.4), as `vital_totals([])` computes in `client.roc` | `examples/main.roc:1135` |
| The database clock in a read | `.filter(\|v\| v.seen < Surreal.Time.now())` | `WHERE seen < time::now()` | `examples/main.roc:820` |
| A helper that the program also calls | `Clinic.bill(v)` in `visit_line` | `fee + math::sum(items.map(\|$v1\| <decimal>$v1.doses * $v1.medication.unit_price))` | `examples/Clinic.roc:15` |
| A helper over an open row that calls another | `Clinic.seen_since : { since : Surreal.Datetime, ..p }, { seen : Surreal.Datetime, ..r } -> Bool` calls `Clinic.seen_from`, and `filter_by(Clinic.seen_since)` takes it over `Visit` | `WHERE seen >= $since` | `examples/Clinic.roc:33` |
| A helper over an open row, at a nominal row | `Clinic.low_stock : { floor : I32, ..p }, { stock : I32, ..r } -> Bool` in `medications.update_by(Clinic.low_stock, refill)`, with `Medication := { .. }` | `WHERE stock < $floor` | `examples/Clinic.roc:41` |
| A query fragment over an open row | `Clinic.recent : Surreal.Query({ since : Surreal.Datetime, ..p }, { seen : Surreal.Datetime, ..r }) -> ..`, `Clinic.by_id(Clinic.recent(Surreal.from(visits)).select(visit_line))` | `SELECT .. FROM visit WHERE $since <= seen ORDER BY id` | `examples/Clinic.roc:50`, `examples/main.roc:814` |
| A captured run-time value | `cheaper_than(limit)`, with `Surreal.bind_captured(select_where(medications, \|m\| m.unit_price < limit))`, a `Try(Prepared(List(row)), Error)` | `LET $_1 = 0.9dec; SELECT form, record::id(id) AS id, label, .. FROM medication WHERE unit_price < $_1` | `examples/main.roc:508` |
| A captured record with an optional field | `owners_at(places)`, with `select_where(owners, \|o\| places.contains(o.address))` and an address with no `zip`. Also `owner_at(place)`, with `select_where(owners, \|o\| o.address == place)`, once with a `zip` and once without | `LET $_1 = [{ city: 'Lyon', line: 'Rue Merciere 9' }, { city: 'Oslo', .., zip: '0155' }]; SELECT .. FROM owner WHERE $_1 CONTAINS address`. The absent `zip` is `Code.Value.Absent`, and the object leaves it out. For `owner_at`, the captured address is one input, `$_1`, because the comparison reads it whole, and the script compares `address.city = $_1.city`, `address.line = $_1.line` and `address.zip = $_1.zip`. The compiler describes that as a switch on the presence of each `zip`. SurrealDB reads an absent field as NONE, and `NONE = NONE` is true, so the translator prints the comparison alone, and `!=` as `!=` | `owners_at` and `owner_at` in `main.roc` |
| Order, start and limit | `.order_by(\|r\| r.id, Asc).start(2).limit(2)`, in the order that SurrealDB runs them. Another order is a type error (see Clauses after `select`) | `ORDER BY id LIMIT 2 START 2` | `examples/main.roc:868` |
| A whole row as one value | `select_value(\|v\| v)`: the fields of the row type, so `id` is the key | `SELECT VALUE { contact: contact, id: record::id(id), license: license, .. } FROM vet` | `examples/main.roc:862` |
| A filter of a projection | `.select(vital_line).filter(\|l\| fever_fn.call2(l.temp_c, l.pulse))` | `SELECT .. FROM vital WHERE fn::fever(temp_c, pulse)` | `examples/monitoring.roc:354` |
| A filter of groups (`HAVING`) | `.aggregate(day_line).filter(\|d\| d.fevers < d.readings)` | `SELECT day, fevers, kennel, readings FROM (SELECT .. GROUP BY day, kennel) WHERE fevers < readings` | `examples/monitoring.roc:361` |
| A filter after an order and a limit | `.order_by(\|l\| l.pulse, Desc).limit(3).filter(\|l\| l.temp_c < 39)` | `SELECT at, kennel, pulse, temp_c FROM (SELECT .. ORDER BY pulse DESC LIMIT 3) WHERE temp_c < 39.0dec` | `examples/monitoring.roc:367` |
| Result rows as the rows of a new query | `.select(hot_line).query().filter(\|r\| r.hot).group_by(\|r\| r.kennel)` | `SELECT count() AS fevers, record::id(id)[0] AS kennel FROM vital WHERE fn::fever(temp_c, pulse) GROUP BY kennel` | `examples/monitoring.roc:378` |
| Update and delete with a parameter | `medications.update_by(Clinic.low_stock, refill)`, `visits.delete_by(Clinic.too_old)` | `UPDATE medication SET stock = stock + $add WHERE stock < $floor RETURN AFTER`, `DELETE visit WHERE seen < $before RETURN BEFORE` | `examples/main.roc:998`, `examples/main.roc:1070` |
| Read, update and delete by key | `vets.at(ruth_id).select(specialty_line)`, `vets.update_at(vets.id("tia"), certified)`, `owners.delete_at(owners.id("noor"))`. The key is an `Id` of the table, written as an escaped record id. `update_at_by` and `set_at_by` read a parameter record | `SELECT .. FROM vet:⟨ruth⟩`, `UPDATE vet:⟨tia⟩ SET ..`, `DELETE owner:⟨noor⟩`. SurrealDB reads and writes the one record (`EXPLAIN`: `RecordIdScan`, `Iterate Record`) | `examples/main.roc:784`, `examples/main.roc:1007`, `examples/main.roc:1049` |
| A key compared with a value of the statement | `.filter_by(\|p, v\| v.id == p.key)`, `.filter(\|v\| v.id == "ruth")`, or a captured key in `select_where` | `WHERE id = type::record('vet', $key)`, `WHERE id = vet:⟨ruth⟩`: a `SELECT` reads the one record, where `record::id(id) = $key` scans the table (`Translate.key_compare`) | `examples/main.roc:790` |
| An update of a row with optional fields | `owners.update_at(owners.id("jon"), renamed)`, with `renamed = \|o\| { ..o, name: "Jon B. Berg" }` and `phone ?:`, `referred_by ?:` in `Owner`. The reifier gives `..o` over each optional field as a switch on its presence, with the row in each arm, and each arm keeps the field. A field that the arms set differently is an `IF` on the presence. An optional field that the patch's row leaves out is `NONE`. A record field built with `..` is set field by field | `UPDATE owner:⟨jon⟩ SET name = 'Jon B. Berg'`; `{ ..m, address: { ..m.address, city: "Rome" } }` is `SET address.city = 'Rome'` | `examples/main.roc:1013` |
| A patch of only the fields it sets | `owners.set_at(owners.id("lena"), moved)`, with `moved = \|o\| { address: { ..o.address, zip: "69002" }, phone: Err(Missing) }`. `set` takes a condition instead of a key, and `set_by` and `set_at_by` read a parameter record. A `Try` sets an optional field, and `Err` removes it. Each field is checked against the row when the statement is built (see Design limits) | `UPDATE owner:⟨lena⟩ SET address.zip = '69002', phone = NONE` | `examples/main.roc:1022` |
| A record merged into a row | `tallies.merge_at(tallies.id("t1"), { label: "Merged", meta: { a: 9 } })`, `upsert_merge_at` for a key with no row, `merge(\|t\| t.hits > 10, { tags: ["hot"] })` for a condition. The record is a value of the app, with only the fields to change; an object in it is merged into the stored object, so `meta.b` stays. `set_at` writes the same, each field as a clause, and stays the way to change a union field (a merged union keeps the keys of its old arm) or to remove an optional one. The fields are the server's to check, as Roc has no type for a record of some of the row's fields; `id` is refused | `UPDATE tally:⟨t1⟩ MERGE { label: 'Merged', meta: { a: 9 } } RETURN AFTER`, `UPSERT tally:⟨t4⟩ MERGE { .. }`, `UPDATE tally MERGE { tags: ['hot'] } WHERE hits > 10` | `examples/client.roc:1286` |
| JSON Patch ops replayed on a row | `tallies.patch_at(tallies.id("t3"), patches)` takes the `Patch`es of `live_diff`, in order, so a client replays what another saw; `patch_ops_at` takes `Op`s that the app made, `[Replace(["label"], Cbor.Value.Text("Patched")), Add(["tags", "-"], ..)]`. A patch of another row, a patch of a delete, an op at `/id` and a `change` op (a text diff, read and not written) are refused when the statement is built. A path that the row does not have is the server's error | `UPDATE tally:⟨t3⟩ PATCH [{ op: 'replace', path: '/label', value: 'Patched' }, { op: 'add', path: '/tags/-', value: 'p' }, { op: 'replace', path: '/meta/b', value: 7 }] RETURN AFTER` | `examples/client.roc:1289`, `tests/DiffTest.roc:272` |
| Insert, or update the row that exists | `tallies.insert_or_update(incoming, \|new, old\| { ..old, label: new.label, hits: old.hits + new.hits })`. The patch is translated as the one of `update` is, with the new row at `$input`; the row is the last argument, as in `update_by`. One transaction. A duplicate is the same record key: a row that repeats only the value of a unique index is `Unique`, as for `insert`. A relation table is refused | `BEGIN; INSERT INTO tally [..] ON DUPLICATE KEY UPDATE hits = IF id != NONE { hits + $input.hits }, label = IF id != NONE { $input.label } RETURN AFTER; COMMIT`. SurrealDB 3.3.4 evaluates the clause once with no stored row, where `hits + 1` is an error even for a new key (verified), so each item is guarded with `IF id != NONE` | `examples/client.roc:1284` |
| Seeds through the derived encoder | `vets.insert(seed_vets)`, `treats.insert(seed_treats)` | `BEGIN; INSERT INTO vet [..] RETURN AFTER; COMMIT`, `BEGIN; INSERT RELATION INTO treats [..] RETURN AFTER; COMMIT` | `examples/main.roc:925`, `examples/main.roc:930` |
| A Roc function as a database function | `fever_fn = Surreal.db_fn("fever", fever)`, `Surreal.function(\|_\| fever_fn)` in the schema | `DEFINE FUNCTION OVERWRITE fn::fever($a1: decimal, $a2: int) -> bool { RETURN ($a1 > 39.0dec) OR ($a2 > 120) };` | `examples/monitoring.roc:92` |
| A database function in a filter | `.filter(\|v\| fever_fn.call2(v.temp_c, v.pulse))` | `WHERE fn::fever(temp_c, pulse)` | `examples/monitoring.roc:334` |
| A database function in a computed field | `.computed(\|v\| v.fevered, \|v\| fever_fn.call2(v.temp_c, v.pulse))` | `fevered ON vital TYPE bool VALUE fn::fever($this.temp_c, $this.pulse)` | `examples/monitoring.roc:121` |
| A time series key | `id : Surreal.TimeKey(Surreal.Id(Kennel))`, `Surreal.time_key(kennels.id("a"), at)` | `DEFINE FIELD OVERWRITE id ON vital TYPE [record<kennel>, datetime]`, `BEGIN; INSERT INTO vital [{ id: [kennel:⟨a⟩, d'..'], .. }] RETURN AFTER; COMMIT` | `examples/monitoring.roc:43` |
| A range of one series | `.between(kennel_a, day_start, day_end)` | `FROM vital:[kennel:⟨a⟩, d'..']..[kennel:⟨a⟩, d'..']` | `examples/monitoring.roc:340` |
| Bucket by day | `.group_by(day_of)` with `Surreal.Time.floor(v.id.time(), Surreal.Time.days(1))` | `time::floor(record::id(id)[1], ..) AS day, record::id(id)[0] AS kennel .. GROUP BY day, kennel` | `examples/monitoring.roc:131` |
| A view | `daily.define_as(Surreal.from(vitals).group_by(day_of), day_line)` | `DEFINE TABLE OVERWRITE vital_daily TYPE NORMAL AS SELECT .. count(fn::fever(temp_c, pulse)) AS fevers .. GROUP BY day, kennel` | `examples/monitoring.roc:143` |
| A changefeed | `vitals.define().changefeed(Surreal.Time.days(7))` | `DEFINE TABLE OVERWRITE vital SCHEMAFULL CHANGEFEED 604800000000000ns` | `examples/monitoring.roc:122` |
| Retention by time | `vitals.delete_by(\|p, v\| v.id.time() < p.before)` | `DELETE vital WHERE record::id(id)[1] < $before RETURN BEFORE` | `examples/monitoring.roc:396` |
| Geometry fields | `location : Surreal.Point`, `area : Surreal.Polygon` | `location ON site TYPE geometry<point> ASSERT geo::is_valid($value)` | `examples/monitoring.roc:39` |
| The coordinates of a point | `s.location.lat()` | `location.coordinates[1]` | `examples/monitoring.roc:274` |
| A geometry parameter in a relation | `filter_by(\|p, s\| Surreal.Geo.inside(p.here.to_geometry(), s.area.to_geometry()))`, `.prepare({ here: here })` | `LET $here = { type: 'Point', coordinates: [10.75f, 59.91f] }; .. WHERE $here INSIDE area` | `examples/monitoring.roc:403` |
| A distance | `filter_by(\|p, s\| Surreal.Geo.distance(s.location, p.here) < 50000)` | `WHERE geo::distance(location, $here) < 50000f` | `examples/monitoring.roc:408` |
| A point out of range is refused | `sites.create({ .., location: Surreal.point(200, 2), .. })` | `geo::is_valid($value)` fails for the field `location` | `examples/monitoring.roc:430` |
| A live query | `Surreal.from(vitals).filter(\|v\| fever_fn.call2(v.temp_c, v.pulse)).select(vital_line).live({}, definitions)` | `LIVE SELECT VALUE { row: { at: record::id(id)[1], .. }, now: fn::fever(temp_c, pulse) } FROM vital WHERE fn::fever(temp_c, pulse) OR ($before IS NOT NONE AND fn::fever($before.temp_c, $before.pulse))` | `examples/monitoring.roc:440` |
| A live query with a parameter | `.filter_by(\|p, v\| v.temp_c > p.limit).select(vital_line).live({ limit: limit }, definitions)` | `LET $limit = 39.2dec;` then `LIVE SELECT .. WHERE (temp_c > $limit) OR ($before IS NOT NONE AND ($before.temp_c > $limit))` | `examples/monitoring.roc:445` |
| A live query of a view | `Surreal.from(daily).select(..).live({}, definitions)` | `LIVE SELECT VALUE { row: { day: day, .. }, now: true } FROM vital_daily` | `examples/monitoring.roc:449` |
| A live query of a row and its edges | `Surreal.from(kennels).incoming(cares_for).filter(no_carer).select(unattended_line).live({}, definitions)` | A second `LIVE SELECT VALUE { ref: out, node: (SELECT VALUE { row: .., now: .. } FROM ONLY $parent.out) } FROM cares_for` | `examples/monitoring.roc:463` |
| A live query of a read row with an `In` field | `Surreal.from(kennel_reads).filter(\|k\| k.cares_for.list().len() == 0)..live({}, definitions)` | The same second `LIVE SELECT .. FROM cares_for` as for `incoming` | `examples/monitoring.roc:468` |
| A live query with a semi join | `.filter(\|k\| vitals.rows().any(..)).select_value(\|k\| k.label).live({}, definitions)` | `LIVE SELECT VALUE { row: label, now: (SELECT VALUE id FROM vital).any(..) } FROM kennel WHERE ..`, and a `LIVE` on `vital` that sends every kennel: `LIVE SELECT VALUE (SELECT VALUE { ref: id, row: label, now: .. } FROM kennel) FROM vital` | `examples/monitoring.roc:473` |
| A live query that reads a linked table | `Surreal.from(kennel_reads).select(\|k\| { label: k.label, site: k.site.name }).live({}, definitions)` | A `LIVE` on `site` that sends the kennels that link to the written site: `LIVE SELECT VALUE (SELECT VALUE { ref: id, row: .., now: true } FROM kennel WHERE site = $parent.id) FROM site` | `examples/monitoring.roc:495` |
| A live query of two edge tables | `Surreal.from(kennels).incoming(cares_for).and_incoming(checks).filter(no_one).select(neglected_line).live({}, definitions)` | A `LIVE` on `cares_for` and one on `checks`, each with the node after the write | `examples/monitoring.roc:487` |
| The raw events of a live query | `.select(vital_line).live_raw({})` | `LIVE SELECT VALUE { at: record::id(id)[1], .. } FROM vital WHERE fn::fever(temp_c, pulse)` | `examples/monitoring.roc:505` |
| The patches of the stored rows | `Surreal.from(vitals).live_diff({})` | `LIVE SELECT DIFF FROM vital` | `examples/monitoring.roc:509` |
| A live session, on basic-cli | `Surreal.Session.open!(transport, ..)`, then `session.live!(watch)`, writes on the same session, and `next!` | `query` with the request of the watch, in CBOR over a WebSocket on `/rpc` | `examples/watch.roc:535` |
| Requests in flight together | `session.send!(prepared)` for each, then `await!(ticket, prepared)`, the last first | Several `query` requests before the first reply | `examples/client.roc:715` |
| A typed row of one key, in a session | `sites.at(sites.id("oslo")).select(\|r\| r).prepare_one({})` | `SELECT area, record::id(id) AS id, location, name FROM site:⟨oslo⟩`, read as `Try(Site, [NotFound])` | `examples/client.roc:181` |
| A typed query result, in a session | `session.run!(Surreal.from(vitals).filter(..).select(vital_line).prepare({}))` | `query` with the request of the prepared statement, the reply read as `List(VitalLine)` | `examples/client.roc:159` |
| A typed write result | `kennels.create(quay)`, `kennels.delete_at(kennels.id("q")).prepare({})`, `carers.delete(\|c\| ..).prepare({})` | `CREATE kennel:⟨q⟩ CONTENT { .. } RETURN AFTER`, `DELETE kennel:⟨q⟩ RETURN BEFORE`, `DELETE carer WHERE .. RETURN BEFORE`, each read as the stored rows | `examples/client.roc:795` |
| Two statements in one request | `write.then(read)` | `LET $key = 'q'; LET $label = ..; UPDATE kennel SET .. RETURN AFTER; SELECT ..`, read as `(Try(List(Kennel), Error), Try(List(KennelLine), Error))`, each with its own error | `examples/client.roc:230` |
| Statements in one transaction | `create.begin().then(insert)?.then(rows)?.commit()` | `BEGIN; CREATE bin:⟨b3⟩ .. RETURN AFTER; INSERT INTO bin [..] RETURN AFTER; SELECT .. FROM bin; COMMIT`, read as `((List(Bin), List(Bin)), List(Bin))`, or `Aborted({ at, error })` | `examples/client.roc:367` |
| A typed read of a patch | `patch.field(\|v\| v.temp_c)` | `{ op: 'replace', path: '/temp_c', value: 37.9dec }` is `Set(37.9)` | `examples/watch.roc:586` |
| The notices of a write, in Roc | `Surreal.Mirror.notices(vitals, Replace(hot, cooled), is_fever, vital_line)` | `[{ action: 'UPDATE', now: false, ref: vital:[..], role: 'node', row: { .. } }]` | `Mirror.notices` |
| A key that the server makes | `.default_by(\|n\| n.id, \|_\| Surreal.Rand.ulid())`, then `notes.insert_new(new_notes)` with rows that have no `id` | `DEFINE FIELD OVERWRITE id ON note TYPE string DEFAULT rand::ulid()`, `INSERT INTO note [{ text: .., vet: vet:⟨ruth⟩ }] RETURN AFTER`, each row read back as a `Created` with its `Id` | `examples/main.roc:1076` |
| A link and an edge to a row with a key from the server | `tasks.insert_new([{ title: "Feed", shift: shifts.link(made.id.key()) }])`, `handovers.create_new({ from: .., to: .., notes: "keys" })` | `INSERT INTO task [{ shift: shift:⟨01M6..⟩, title: 'Feed' }] ..`, `RELATE shift:⟨01M6..⟩->handover->shift:⟨01M6..⟩ CONTENT { notes: 'keys' } RETURN AFTER` | `examples/client.roc:682` |
| A record access method, typed | `accounts.define(users, \|v\| { email: v.email, pass: Surreal.Hash.argon2(v.pass) }, \|v, u\| u.email == v.email and Surreal.Hash.argon2_matches(u.pass, v.pass))` | `DEFINE ACCESS OVERWRITE account ON DATABASE TYPE RECORD SIGNUP (CREATE user CONTENT { email: $email, pass: crypto::argon2::generate($pass) }) SIGNIN (SELECT * FROM user WHERE (email = $email) AND crypto::argon2::compare(pass, $pass)) DURATION FOR TOKEN 3600000000000ns` | `examples/client.roc:945` |
| A table permission over the row and the record user | `.permit([Select], \|m\| m.owner.id() == users.auth() or m.shared)`, `.permit([Create, Update, Delete], ..)` | `DEFINE TABLE OVERWRITE memo SCHEMAFULL PERMISSIONS FOR select WHERE (owner = $auth.id) OR shared, FOR create, update, delete WHERE owner = $auth.id` | `examples/client.roc:940` |
| A field permission | `.deny_field(\|u\| u.pass, [Select])`, `.permit_field(\|m\| m.text, [Update], \|m\| !m.shared)` | `pass ON user TYPE string PERMISSIONS FOR select NONE`, `text ON memo TYPE string PERMISSIONS FOR update WHERE !shared` | `examples/client.roc:938` |
| The record user in a query | `.filter(\|m\| m.owner.id() == users.auth())` | `WHERE owner = $auth.id` | `examples/client.roc:970` |
| A session of a record user, on both transports | `Session.open!(transport, accounts.sign_up(scope, ann))`, then `Token(session.token()?)` and `session.invalidate!()` | RPC `signup`, `signin`, `authenticate`, `invalidate`; over HTTP each post has `Authorization: Bearer <token>` | `examples/client.roc:1057` |
| An analyzer | `Surreal.analyzer("clinical", [Class], [Lowercase])`, `clinical.define()` in the schema list | `DEFINE ANALYZER OVERWRITE clinical TOKENIZERS class FILTERS lowercase;`, before the tables | `examples/search.roc:28` |
| A full-text index | `chart_text = charts.text_index(\|c\| c.body, clinical)`, `.text_index(chart_text)` | `DEFINE INDEX OVERWRITE chart_body_fulltext ON chart FIELDS body FULLTEXT ANALYZER clinical BM25 HIGHLIGHTS` | `examples/search.roc:31` |
| A full-text search, with a Roc meaning | `.search(chart_text, "limping").select(\|(c, _)\| { id: c.id })`, and `clinical.matches(c.body, "limping")` in Roc | `SELECT .. FROM chart WHERE body @1@ 'limping'` | `examples/search.roc:123` |
| The score and the highlights of a search | `.select(\|(c, hit)\| { id: c.id, score: hit.score(), marked: hit.highlight("<b>", "</b>") }).order_by(\|r\| r.score, Desc)` | `search::highlight('<b>', '</b>', 1) AS marked, search::score(1) AS score .. ORDER BY score DESC` | `examples/search.roc:149` |
| A vector index | `charts.vector_index(\|c\| c.embedding, { dimension: 3, distance: Cosine })`, `.vector_index(chart_vectors)` | `DEFINE INDEX OVERWRITE chart_embedding_hnsw ON chart FIELDS embedding HNSW DIMENSION 3 DIST COSINE TYPE F64` | `examples/search.roc:34` |
| The nearest rows | `.nearest(chart_vectors, limp_probe, Exact(3)).select(\|(c, near)\| { id: c.id, distance: near.distance() })`, `Approx({ k: 3, ef: 40 })` | `vector::distance::knn() AS distance .. WHERE embedding <\|3,COSINE\|> [1f, 0f, 0f]`, `<\|3,40\|>` | `examples/search.roc:185` |
| Vector functions | `Surreal.Vector.similarity_cosine(c.embedding, probe)` and the distances, the same to the bit in Roc | `vector::similarity::cosine(embedding, [0.5f, 0.25f, 0.125f])` | `examples/search.roc:171` |
| A search in a session, on both transports | `session.run!(ranked_notes)`, read as `List(Ranked)`, and `close_notes` | The same statements, over RPC | `examples/client.roc:1158` |
| Writes the database must refuse | ``rejects("check_as_assert", "field `weight_kg`", patients.create(light_patient))`` | the check reports a failed statement | `examples/main.roc:935` |

`check.py` runs the whole script with the Roc result next to each query. A
query and its Roc result use the same functions: `owner_card`, `pet_line`,
`case_load`, `ledger_line` and the others run over the seed rows in the program
(`seed_vets` and the other `seed_` lists of `main.roc`), and over the stored rows in the database. The checker tests
that the two results agree.

## How it is built

A clause is a function over the row. The translator reads the root row of its
`Code` graph as a tree and evaluates the tree (`Translate.run`).
Each parameter is bound to what it stands for in SurrealQL. A node that the
tree keeps as a definition is evaluated once, where its block defines it.

| Binding | Stands for | A field read off it is |
| --- | --- | --- |
| `Row` at `Doc` | The record a statement runs over: `""`, `$after` in an event, `$this` in a field | A path: `address.city` |
| `Row` at `Ref` | The record behind a link after `get()` or a `Linked` field, or an edge `$v1` or a row `$v1` of `rows()`, with its Roc type | A path through the record: `owner.name`. The whole record is the fields of its type: `owner.{ id: record::id(id), name, .. }` (`Translate.typed_fields`) |
| `Row` at `Obj` | An object inside a record, or a result row in the outer query of a subquery | A path. The whole result row is `$this` |
| `WithEdges(row, lists)` | A row and its edge lists from `outgoing` or `incoming`, then `and_outgoing` or `and_incoming` | Nothing. `.0` is the row, `.1` and `.2` the edge lists (`Translate.op`, the `Index` arm) |
| `ListOf` | A list at a path, the edges `->t`, or the rows of a table `(SELECT VALUE id FROM t)`. Its items are values, or record ids with their type when it is known (`Translate.Items`) | Nothing. A list operation makes a closure over `$v1`, `$v2` (`Translate.lambda`). A whole list of typed records is `list.{ id: record::id(id), .. }` |
| `Union` | A tag-union value | Nothing. A `match` is an `IF .. THEN .. END` (`Translate.switch`) |
| `Maybe` | A read of an optional field | Nothing. `??`, `is_ok` and `match` test it for `NONE` |
| `Params` | The parameter record of a `filter_by` | The variable `$name` |
| `Group` | The rows of a group | Nothing. `len`, `keep_if(..).len()` and `map(..).sum()` aggregate it (`Translate.over_group`) |
| `Column` | `rows.map(f)` over a `Group`: the expression `f` reads | Nothing. Each aggregate (`sum`, `mean`, `median`, `stddev`, `variance`) writes its own call, so one `map` may feed several (`Translate.aggregate_arg`) |
| `Moment` | The text of a datetime, which is how the derived `==` on a `Datetime` arrives | Not a record. `==` compares the datetimes (see below) |
| `Expr`, `Infix` | The text of a scalar. `Infix` needs parentheses as an operand | Not a record |
| `Fields` | A record that the body built | The binding of that field |
| `Table` | A table of `Surreal.table`, `relation` or `view`, by its literal name (`Translate.table_of`) | Nothing. `rows()` is its rows, and `id(key)` a record id (`Translate.prim`) |

A call to one of the application's own functions is a `Call` of another row
of the same graph. The translator expands it with that row's parameters bound
the same way (`Translate.expand`). A function that calls itself is
refused, except a database function that calls its own row (see "Database functions"). A call of a builtin or of a function of `Surreal` is a
`Prim`, and the translator looks up its form by the id of the function (`Translate.form`), never by its name. The builtins
are one table, `Translate.builtins`, read by `Translate.builtin`. The intrinsics, the cut functions and the tables a clause names are the extension
`Surreal.library`, which `Surreal` passes into every translation, as `Translate` cannot import `Surreal` (see "Extending the translator").
A builtin is mapped only when
SurrealDB 3.3.4 gives the same result as Roc. `builtins.roc` checks the risky
rows on a live server.

### Row types and defaults

A row is an alias or a nominal. Both work with the helpers over open rows
in `Clinic.roc`. A field default (`??`) needs a nominal: the language refuses
`??` on an alias.

| Row | Helper over an open row | `??` default |
| --- | --- | --- |
| An alias, `Visit : { .. }` | Yes | No. Give the default with `.default(..)` |
| A nominal over a record, `Medication := { .. }` | Yes: a record-backed `:=` extends an open row (design.md of the compiler repo, "Record Extension Well-Formedness") | Yes |
| An opaque type, `T :: { .. }` | No: refused by design | Yes |

`Code.Ty` gives each default to the schema (`Types.defs_of`, `Schema.field`):

| Default in the type | Schema |
| --- | --- |
| A literal: `?? 0`, `?? []`, `?? Gold`, a record of literals | `DEFAULT <literal>` on its field, at any depth: `size.w`, `crates[*].w`, and `id` (a create with no key gets that key) |
| A literal in a record of a union arm | None. An arm has no field definition, so the server does not fill it |
| Not a literal: `?? make({})` | `BadSchema` that names the field: give it a literal default, or remove the `??` and use `.default_by(..)` |
| A `??` and a `.default(..)` on one field | `BadSchema`: two defaults |

### Tables and read rows

A table holds its name and its kind, and no `Code` value (`Surreal.TableKind`).
The row type comes from the definition, `define()` (`Table.define`):
`Code.ty_of` describes `row` at each use that fixes it, and `Types` reads the
schema off that description. So a clause can read a table:

| Roc | SurrealQL |
| --- | --- |
| `orders.rows()` | `(SELECT VALUE id FROM order)`. Each row is a record id, so a field read is a traversal: `$v1.total` |
| `orders.rows().keep_if(\|o\| o.customer.get().id == c.id).len()` | A correlated count: `(SELECT VALUE id FROM order).filter(\|$v1\| record::id($v1.customer) = record::id(id)).len()` |
| `.filter(\|c\| orders.rows().any(\|o\| ..))` | A semi join, also in a live query |
| `vets.id("ruth")` | `vet:⟨ruth⟩`; with a key that is not a literal, `type::record('vet', ..)` |
| `vets.at(vets.id("ruth"))` | A query of the record of one key: `FROM vet:⟨ruth⟩`. An `Id` of another table is an `Unsupported` |
| `.select(\|r\| r)` | The whole row: one column per field of its type. The same for a linked row (`\|o\| o.customer.get()`) and an object |

| Definition | What it gives |
| --- | --- |
| `Surreal.table(name)`, `Surreal.relation(name, from, to)`, `Surreal.view(name)` | A table: the name and the kind |
| `t.define()` | The schema builder, with the row type |
| `t.define_as(grouped, per_group)` | The definition of a view, with its query |
| `t.define_read()` | A read row: no statement, and a check against the stored row |

A read row is the stored row with a `Surreal.Linked(r)` for each `Link(r)`,
to an alias row or to a nominal row, and with `Surreal.Out(e)` and `Surreal.In(e)` fields for the
edge tables at the row. A field read through a `Linked` is
a traversal with no `.get()`, and a whole read row is the fetch plan: each
`Linked` is the fields of its row, at any depth (`Translate.Reach`).

| Stored row | Read row | Roc | SurrealQL |
| --- | --- | --- | --- |
| `customer : Link(Customer)` | `customer : Linked(Customer)` | `o.customer.name`, `o.customer.id` | `customer.name`, `record::id(customer)` |
| `items : List({ product : Link(Product), qty : I64 })` | `items : List({ product : Linked(Product), qty : I64 })` | `o.items.map(\|i\| i.product.title)` | `items.map(\|$v1\| $v1.product.title)` |
| None: the edge table `purchased` starts at `customer` | `purchased : Out(PurchasedRead)` | `c.purchased.list().len()` | `->purchased.len()` |
| None: `purchased` ends at `product` | `purchased : In(PurchasedRead)` | `p.purchased.list().any(\|e\| e.quantity > 2)` | `<-purchased.any(\|$v1\| $v1.quantity > 2)` |
| The whole row | | `.select(\|o\| o)` | `customer.{ address, id: record::id(id), name, tags } AS customer, record::id(id) AS id, items.{ product: product.{ id: record::id(id), price, title }, qty } AS items, ..` |

### The id of a link: `link.id` and `link.id()`

A stored `Link(r)` is the record `{ id : Id(r), fetched : [Fetched(r), NotFetched] }`. In a clause, `link.id` reads the field `id`, and `link.id()` calls the method of the same name. Both give the record id that the link holds, which is the link itself in SurrealQL (`customer`). They go through one function (`Translate.link_field`), so they cannot differ. The field `fetched` is the row that the program holds, and the database has no such field. A clause that reads it gets an `Unsupported`.

| Written | Type of `o.customer` | SurrealQL | Meaning |
| --- | --- | --- | --- |
| `o.customer.id`, `o.customer.id()` | `Link(Customer)` | `customer` | The record id. Compare it with an `Id`: `o.customer.id == ada_id` is `customer = customer:⟨ada⟩` |
| `o.customer.id.key()` | `Link(Customer)` | `record::id(customer)` | The key of the id, as text |
| `o.customer.fetched` | `Link(Customer)` | Refused | Write `o.customer.get().field`, or `o.customer.id` |
| `o.customer.id` | `Linked(Customer)` | `record::id(customer)` | The field `id` of the linked row, as text. A read row has no `id()` on a `Linked` |
| `c.id` | A row with its own field `id : Str` | `record::id(id)` | The key of the row. The row is not a `Link`, so the translator reads a field. On the row that a statement reads, `c.id == "ada"` and `c.id == p.key` compare the record id instead: `id = customer:⟨ada⟩`, `id = type::record('customer', $key)` |

Use the field when the id is compared or captured, as in `o.customer.id == who`. Use `link.id()` when a method call reads better in a chain. The two forms give the same SurrealQL in filters, `select`, `select_value`, `order_by`, `group_by`, updates, live queries, captured ids and edge ends (`tests/QueriesTest.roc:626`).

| Rule | Detail |
| --- | --- |
| The check | `Surreal.schema` checks a read row against the stored row of the table of the same name (`src/Types.roc:120`): the same fields with the same presence, a `Linked(r)` where the stored row has a `Link` to a row that `r` agrees with, an `Out` or `In` field that names an edge table that starts or ends at the table, and every other type equal. Else a `BadSchema` that names the path |
| Writes | `Linked`, `Out` and `In` have no `encoder_for`, so a write of a read row is a type error. A table definition with one is a `BadSchema` |
| `Link` and `.get()` | The main form: a visible hop that works for every row. A `Linked` works for every row too: an alias row, a nominal row, and a row that links to its own table (`Linked(Owner)`, whose own `referred_by` is a `Link`) |
| A nominal row in a `Linked` | The reifier gives `Linked(Owner)` with its type argument, `Owner`. So a live query finds its table by that row, as for a `Link` (`Types.site_in`), and two tables whose rows have the same fields, a nominal and an alias, are told apart. A `Linked` of a read row, `Linked(OwnerRead)`, finds the table whose `define_read` lists that read row |
| A read row that holds a `Linked` of itself | `OwnerRead := { .., referred_by ?: Linked(OwnerRead) }`. The reifier gives the inner `Linked` as `Recursive("Surreal.Linked")`. The check is coinductive (`Types.agree`, `src/Types.roc:181`): it keeps the pairs of a `Linked` and a stored type on the way, and a pair that it meets again agrees. So the read row agrees with its stored row when its fields agree. A field read goes any number of hops: `o.?referred_by` then `.?referred_by` is `referred_by.referred_by`. The whole row is refused, and a live query watches the first hop (see Design limits) |
| Live queries | A clause over the table row of a read row adds the edge table of each `Out` and `In` field of the row type to the watch, as `outgoing` and `incoming` do, and the table of each `Linked` and `Link`, as a link of a stored row does (`Surreal.reached_watches`) |

### Keys that the server makes

A row type keeps its `id : Str`, and a write of a new row leaves it out:
`create_new` and `insert_new` take the row without its `id`, and the
server makes the key. The schema says how, as a default of the key:

```roc
Shift : { id : Str, label : Str }
shifts.define().default_by(|s| s.id, |_| Surreal.Rand.ulid()).done()
# DEFINE FIELD OVERWRITE id ON shift TYPE string DEFAULT rand::ulid();

made = shifts.create_new({ label: "Early" })?      # CREATE shift CONTENT { label: 'Early' } RETURN AFTER
match session.run!(made).result {
	Ok([early]) => tasks.insert_new([{ title: "Feed", shift: shifts.link(early.id.key()) }])  # early.id : Id(Shift)
	..
}
```

| Roc | Type |
| --- | --- |
| `Table.create_new` | `Table({ id : Str, ..new }), new -> Try(Prepared(List(Created({ id : Str, ..new }, new))), Error)` |
| `Table.insert_new` | `Table({ id : Str, ..new }), List(new) -> Try(Prepared(List(Created({ id : Str, ..new }, new))), Error)` |
| `Surreal.Created(row, new)` | `{ id : Id(row), fields : new }`: the key that the server gave, as an `Id` of the table, and the other fields as stored |

| The key | Schema | Key (verified on 3.3.4) |
| --- | --- | --- |
| No default | None: the key has no definition | SurrealDB's random key, 20 lower-case letters and digits: `handover:5cydmqi6344mvu5l5uhj` |
| `.default_by(\|r\| r.id, \|_\| Surreal.Rand.ulid())` | `DEFINE FIELD OVERWRITE id .. TYPE string DEFAULT rand::ulid()` | A ULID: `shift:01M6C3BN3QZJM8Y0GRCFTYK5NR` |
| `.default_by(\|r\| r.id, \|_\| Surreal.Rand.uuid())` | `.. DEFAULT <string>rand::uuid()` | A UUID as text: `task:⟨01a19835-d479-78d2-ab74-94d43551495f⟩` |
| `.default_by(\|r\| r.id, \|r\| r.title)` | `.. DEFAULT $this.title` | A key from the content |
| `id : Str ?? "main"`, `.default(\|r\| r.id, "main")` | `.. DEFAULT 'main'` | One key |

| Rule | Detail |
| --- | --- |
| Why the row minus `id` | The table's row type ties the two: `Table({ id : Str, ..new })` takes `new`, so a field that the row does not have, or one of another type, is a type error, and `Created` holds an `Id(row)`, so the key reads (`Table.at`), updates and deletes (`*_at`) the row and links to it (`Table.link`) with no other step. A `Def.ids(..)` option would keep the generator out of the type of the write, but the write would still need a row without `id`, so the default of the key is the one place that says how the key is made, as for any other field |
| Why `Created` and not the row | The compiler derives no `parser_for` of `{ id : Str, ..new }` with `new` a type variable, and Roc cannot add a field to a record, so the library cannot make a `Shift` from a key and a `{ label : Str }`. The result reads the key off the record id (tag 8) and the rest as `new` (`Surreal.read_created`): a record id of another table is a `Wire` error |
| A ULID, a UUID and a random key are text | So `Id(row)` holds them, and every read and write by key works as for a key that the app gives. SurrealDB's `t:uuid()` makes a key of the type `uuid`, which a text key never equals, so a UUID key is `<string>rand::uuid()` (verified: a `TYPE string` key refuses the `uuid` value) |
| Links and edges | A `Link` holds the `Id`, so a link to a row with a key from the server is `shifts.link(made.id.key())`, a `Linked` reads through it, `outgoing` and `incoming` read its edges, and a delete by its key cascades to the rows that link to it (`client.roc`, `server_keys!`) |
| An edge | `RELATE a->t->b CONTENT ..` with no key, `INSERT RELATION INTO t [{ in, out, .. }]` with none. A default of `id` on an edge table works the same (verified) |
| The order of an insert | The rows of the result are in the order of the rows written (verified) |
| In one transaction | `create_new(..).begin().then(insert_new(..))` works, but a part cannot read the key that an earlier part made: each part is built before the request runs. Link to a key from the server after its write's result |
| Not for | A nominal row (`Medication := { .. }`): it does not unify with `{ id : Str, ..new }`, so `create_new` is a type error. A `TimeKey` key: the same. Keys that are numbers: `Id(row)` holds a text key, so an integer key does not read back |

### Clauses after `select`

The steps after a projection run in the order they are written, as list
steps do. SurrealQL runs `ORDER BY`, then `START`, then `LIMIT`, whatever
the order of the Roc calls, so the types take only the chains that run as
they read (`Started`, `Limited`):

| Roc | What it gives |
| --- | --- |
| `.order_by(..).order_by(..).start(s).limit(n)`, each part optional | `ORDER BY .. LIMIT n START s` |
| `.limit(2).order_by(..)`, `.limit(10).start(20)`, `.limit(2).limit(5)`, `.start(1).start(2)` | A type error: a `Limited` has no `order_by`, `limit` or `start`, and a `Started` no `order_by` or `start` |
| `.limit(2).query().select(\|r\| r).order_by(..)` | The rows of the limit, then ordered: `SELECT .. FROM (SELECT .. LIMIT 2) ORDER BY ..` |
| `.limit(3).live(..)` | A type error. SurrealDB refuses `LIMIT` and `START` in a live query |

`ORDER BY` takes a field path, not an expression: a call is a parse error.
SurrealDB 3.3.4 reads a top-level name as a column of the result and a
longer path off the source row, and it accepts a path into an aliased
column or through a record link (`ORDER BY owner.name`) but leaves the
rows unordered, in the same order for `ASC` and `DESC` (verified). So
the key of `order_by` is one column, `|r| r.rate`. After a `select_value`
the key reads the value, and the value and the key together must be a
path of fields of the source row: `select_value(\|c\| c.address).order_by(\|a\| a.city, Desc)`
is `ORDER BY address.city DESC`. Any other key is an `Unsupported` that
says to select the value as a column of its own (`tests/QueriesTest.roc:91`).

`Selected.filter` keeps the result rows that a function is true for.
`Selected.query()` makes the result rows the rows of a new query, so every
`Query` method can come after a `select`. The function reads the result type
`out`, so a read of a field that the projection did not keep is a type error.
The `rows` of a `Selected` (`ResultRow`) record which
form a step takes:

| Before the step | Form | Roc | SurrealQL |
| --- | --- | --- | --- |
| A projection: `select`, `select_value` | One `SELECT`. The function reads the projection's fields over the source row | `.select(vital_line).filter(\|l\| fever_fn.call2(l.temp_c, l.pulse))` | `SELECT .. FROM vital WHERE fn::fever(temp_c, pulse)` |
| A projection, then `order_by` | `filter`: one `SELECT`, because an order does not change which rows a filter keeps. `query`: a subquery | `.select(order_line).order_by(\|r\| r.total, Desc).filter(\|r\| r.who == "Ada")` | `.. WHERE customer.name = 'Ada' ORDER BY total DESC` |
| A group: `aggregate` | A subquery: SQL's `HAVING` | `.aggregate(day_line).filter(\|d\| d.fevers < d.readings)` | `SELECT day, fevers, kennel, readings FROM (SELECT .. GROUP BY day, kennel) WHERE fevers < readings` |
| `limit` or `start` (a `Limited`, a `Started`) | A subquery. The outer query keeps the order of the inner one (verified) | `.order_by(\|l\| l.pulse, Desc).limit(3).filter(\|l\| l.temp_c < 39)` | `SELECT at, kennel, pulse, temp_c FROM (SELECT .. ORDER BY pulse DESC LIMIT 3) WHERE temp_c < 39.0dec` |
| `Unchecked.fetch` | `filter`: one `SELECT`. `query`: a subquery, which keeps the `FETCH` | `Unchecked.select_star(Unchecked.fetch(all, "customer").query())` | `SELECT * FROM (SELECT * FROM order FETCH customer)` |

| Rule | Detail |
| --- | --- |
| Columns of the outer query | `select(\|r\| r)` lists the fields of `out` by name. `id` is the key already, so it is not `record::id(id)` again |
| A row of values | The outer query reads a `select_value` row as `$this`: `SELECT VALUE $this FROM (SELECT VALUE pulse FROM vital ORDER BY pulse DESC LIMIT 3) WHERE $this < 130` |
| Parameters | A `filter_by` over a subquery reads `$name`, and `prepare` writes a `LET` for it, as for any query |
| Edges | `outgoing` and `incoming` take a row of a table. After `select(\|r\| r).query()` the row is still the table row. A row of a subquery is a copy with no record id, so they are `Unsupported` |
| `between`, `view` | `Unsupported` over a subquery: each reads a table |
| `LIVE SELECT` | SurrealDB 3.3.4 refuses `LIVE SELECT .. FROM (SELECT ..)`: "Cannot execute LIVE statement using value". The target of a query over a subquery is `Sub` (`Surreal.Target`), so `live` refuses it (`Surreal.live_table`) and takes the form of one `SELECT` |

### Edge types

The ends of an edge table are in its type (`Surreal.relation`, `Query.outgoing`,
`Query.incoming`):

| Function | Type of the edge table |
| --- | --- |
| `Surreal.relation(name, from, to)` with `Table(a)`, `Table(b)` | `Table({ from : Link(a), to : Link(b), ..r })` |
| `outgoing` on a `Query(p, a)` | `Table({ from : Link(a), ..e })` |
| `incoming` on a `Query(p, b)` | `Table({ to : Link(b), ..e })` |

So an edge table in the wrong direction, or a relation with its ends swapped,
is a type error and not a wrong query. `roc check` reports:

```roc
Surreal.from(products).outgoing(purchased)
# The first argument being passed to this function has the wrong type.
# This argument has the type:
#     Surreal.Table({ from: Surreal.Link(Customer), id: Str, quantity: I64, to:
#     Surreal.Link(Product) })
# But outgoing needs the first argument to be:
#     Surreal.Table({ from: Surreal.Link(Product), id: Str, quantity: I64, to:
#     Surreal.Link(Product) })

swapped : Surreal.Table(Purchased)
swapped = Surreal.relation("purchased", products, customers)
# This expression is used in an unexpected way.
# It has the type:
#     Surreal.Table({ from: Surreal.Link(Product), id: Str, quantity: I64, to:
#     Surreal.Link(Customer) })
# But the annotation says it should be:
#     Surreal.Table(Purchased)
```

| Mistake | Before | Now |
| --- | --- | --- |
| `outgoing` or `incoming` in the wrong direction | A query that SurrealDB runs and that finds no edges: `SELECT ->purchased.len() AS n .. FROM product` | A type error |
| A relation with its ends swapped | `BadSchema` when the schema is built | A type error |

`Types.check_ends` still checks the ends of a table source, and
`TypesTest.roc` builds its bad sources by hand. The tests of this example run
with `roc test`, which has no form for a test that must not compile, so the
messages above are the evidence.

### Live queries

A live query keeps the result of a query current. `Selected.live(params, tables)`
is the same builder as `prepare`, with the same clauses
and the same refusals, and gives a `Surreal.Watch(out)` in
place of a `Prepared`. `tables` are the definitions that `Surreal.schema`
takes, where a link of the row finds its table. The watch is one request of
a WebSocket session: the `LET` of each parameter, a `LIVE SELECT` on the
table, one on each other table that the clauses read (`Watched`), and a snapshot of the rows in the result now. A notice
holds the row and `now`, the filter after the write.

| Table that the rows read | Roc | Statement | Its notices |
| --- | --- | --- | --- |
| An edge table (`Edge`) | `outgoing`, `incoming`, `and_outgoing`, `and_incoming`, an `Out` or `In` field of a read row that a clause reads | The edge statement (`edge`) | The node at the end of the edge, after the write |
| A table that a link points at, which a clause reads through (`LinkAt`) | A `Link` with `.get()` and a `Linked` of a read row, a field read through it or the whole linked row, at any hop: of the row, of an edge row, of a row of `rows()`, of a linked row (`Translate.reads`) | A `read` statement (`Surreal.read_lives`), with a test of each link to that table at its path: `site = $parent.id`, `$parent.id IN items[*].product`, `kennel.site = $parent.id`, and a `WHERE` on the fields that the clauses read of that table | One for each row that links to the written record |
| A table of `rows()` (`Rows`) | `vitals.rows()` in a filter or a projection (`Surreal.rows_read`) | A `read` statement with no test | One for each row of the result's table |

| Roc | SurrealQL |
| --- | --- |
| `.filter(\|v\| fever_fn.call2(v.temp_c, v.pulse)).select(vital_line).live({}, definitions)` | `LIVE SELECT VALUE { row: { at: record::id(id)[1], kennel: record::id(id)[0], pulse: pulse, temp_c: temp_c }, now: fn::fever(temp_c, pulse) } FROM vital WHERE fn::fever(temp_c, pulse) OR ($before IS NOT NONE AND fn::fever($before.temp_c, $before.pulse))` |
| Its snapshot | `SELECT VALUE { ref: id, row: { at: .., kennel: .., pulse: pulse, temp_c: temp_c } } FROM vital WHERE fn::fever(temp_c, pulse)` |
| An infix filter, or two filters | `WHERE ((a) AND (b)) OR ($before IS NOT NONE AND ((a') AND (b')))`: each side is in parentheses (`Surreal.all_of`) |
| No filter | `now: true`, and no `WHERE` |
| `select_value(f)`, `select(\|r\| r)` | `row: <f>`, `row: { id: record::id(id), level: level, .. }` |
| An `In` field of a read row, `k.cares_for` | The same second statement as `.incoming(cares_for)`. An `Out` field is as `outgoing` |
| `.incoming(cares_for)` | A second statement on the edge table, whose payload is the node after the write: `LIVE SELECT VALUE { ref: out, node: (SELECT VALUE { row: <row>, now: <p> } FROM ONLY $parent.out) } FROM cares_for`. `outgoing` reads `in` |
| `.incoming(cares_for).and_incoming(checks)` | The row is the triple `(k, cares, checks)`, and each edge table has its statement (`Query.and_incoming`). For three or more, take a read row with an `Out` or `In` field for each |
| A link of the row, `k.site.get().name` or `k.site.name` | `LIVE SELECT VALUE (SELECT VALUE { ref: id, row: <row>, now: <p> } FROM kennel WHERE site = $parent.id) FROM site WHERE $before IS NONE OR $after IS NONE OR $before.name != $after.name`. Two links to one table are one statement, their tests joined by `OR`, and so are the fields that the clauses read |
| A second hop, `b.kennel.get().site.get().name` | A statement on `kennel` with the test `kennel = $parent.id` and the field `site`, and one on `site` with the test `kennel.site = $parent.id` and the field `name` |
| A link of an edge row, `.incoming(cares_for)` and `edges.map(\|e\| e.from.get().name)` | The edge statement, and a statement on `carer` with the test `$parent.id IN <-cares_for.in`. An `Out` or `In` field of a read row is the same, `->t` and `<-t` |
| A link of a row of `rows()`, `badges.rows().any(\|b\| b.kennel.get().label == c.name)` | The statement on `badge`, and one on `kennel` with the test `$parent.id IN (SELECT VALUE id FROM badge).kennel`: a write to a kennel that a badge links to reaches every row |
| `vitals.rows()` in a clause | `LIVE SELECT VALUE (SELECT VALUE { ref: id, row: <row>, now: <p> } FROM kennel) FROM vital` |
| `.live_raw({})` | `LIVE SELECT VALUE <row> FROM vital WHERE <p>` (`Selected.live_raw`) |
| `Query.live_diff({})` | `LIVE SELECT DIFF FROM vital WHERE <p>` (`Query.live_diff`) |

| Rule | Detail |
| --- | --- |
| The row before the write | A filter reads the row at `""` and at `$before`: the source of a query holds both (`Rows`), and a `Filter` takes `Now` or `Before`. The edges are read off the same record: `$before<-cares_for` (`Translate.outgoing`) |
| The guard | `$before IS NOT NONE AND` keeps a filter on `$before` from failing on a `CREATE`. A filter that fails sends nothing (verified) |
| A filter of a projection | It reads the source row through the projection, on `$before` too, so `.select(f).filter(g).live({}, tables)` is one `LIVE SELECT` |
| Refused | A group, an order, `between`, a subquery (`Surreal.live_table`) and `Unchecked.select_star`. A limit and a start are type errors: `Limited` and `Started` have no `live`. `live_diff` also refuses the edges and a projection |
| A link with no table | A `BadSchema` from `live`: `tables` must hold the table of the row type that each link of the row points at, as for `Surreal.schema` |
| The edge statement | No `WHERE`: a filter on the node after the write hides a node that leaves. It sends one notice for each edge write |
| The links that the clauses read | The reads of the clauses decide what a live query watches, not the row type (`Translate.reads`, `Surreal.reached_watches`). The translator walks each clause with the place of each value: a field read through a `Linked` or a `.get()` is a hop, at the path of the link from the row, also through a list (`items[*].product`), the edges of an `Out`, an `In`, `outgoing` or `incoming` (`<-cares_for.in`), a row of `rows()` and a hop before it (`kennel.site`). The result of a projection is read whole: each `Linked` in it, at any depth (`Types.whole_reads`, `src/Types.roc:735`), and each `Out` and `In` field of a whole row. A `Link` in a whole row is a record id, `link.id` and the `id` of a linked row read no linked row, and the count of a list (`len`, `is_empty`) reads no element. So a link that no clause reads through is not watched, and a write to its table sends nothing |
| The fields that the clauses read | Each hop names the field that it reads of the linked record, or the whole record. When the clauses read only some fields of a table, its `read` statement has `WHERE $before IS NONE OR $after IS NONE OR $before.f != $after.f ..`: an update that changes none of them sends nothing, and a create or a delete sends (verified) |
| The edges of a read row | Each `Out` and `In` field that a clause reads is an edge statement. A read row with two `Out` or `In` fields that the clauses read is one watch of two edge tables |
| The `read` statement | The `WHERE` on the written table tests only the fields that the clauses read: the payload is the rows of the result's table that the write reaches, each with its `now`, so a row that leaves is sent too. A write that reaches no row sends an empty list |
| `$parent` | The written record in the subquery of a payload. On a `DELETE` it is the record before the delete (verified) |

`Watch.step` sorts each notice into a change of the
result with the set of its records (`Members`), which the snapshot starts:

| Notice | Member | Change |
| --- | --- | --- |
| `Delete` of the row statement | yes | `Removed`, with the old row |
| `Delete` of the row statement | no | none |
| An edge notice of a node that is gone | | none: the node's own `DELETE` comes next (verified) |
| A notice of a `read` statement | | as any other: whatever the action of the write, `now` and the members decide |
| Any other, `now` true | no | `Added` |
| Any other, `now` true | yes | `Updated`. A write between the `LIVE` and the snapshot comes again: an update, not a second add |
| Any other, `now` false | yes | `Removed`, with the new row |
| Any other, `now` false | no | none |

`View(out)` is the result by record: `of_rows` takes the
snapshot, and `apply` a change. The Mirror predicts the notices of a write in Roc, from the
same functions that the clauses reify:

| Function | Notices |
| --- | --- |
| `Table.edit(Create(r))`, `Replace(a, b)`, `Delete(r)` | The write: `CREATE` (`RELATE` for an edge), `UPDATE .. CONTENT`, `DELETE`, each with `RETURN AFTER` (`RETURN BEFORE` for a delete) (`Table.edit`) |
| `Mirror.notices(table, edit, keep, show)` | A create or a delete when `keep` holds, an update when `keep` holds before or after, none when the two rows are stored the same |
| `Mirror.edge_notices(table, edit, node_of, state, keep, show)` | One for each edge write, with the node after the write, or `Gone` |
| `Mirror.read_notices(table, edit, reached, keep, show)` | A `read` statement: one for each row in `reached`, the rows of the result's table that the write reaches, as they are after it, and none for an update that changes no field that the clauses read. None when the two rows are stored the same |
| `Mirror.events(table, edit, keep, show)` | `live_raw`: a create, an update and a delete when `keep` holds after the write |
| `Mirror.notices_literal`, `Mirror.events_literal` | The `-- roc:` literal of a `-- live:` block, one list for each write |

Facts of SurrealDB 3.3.4 that the design reads, each run on the server:

| Write | Row statement | Edge statement | `read` statement |
| --- | --- | --- | --- |
| A row that leaves the filter | `UPDATE` with `now: false`, because the `WHERE` reads `$before` | | |
| A write that changes no field | nothing | nothing | nothing |
| `RELATE`, or an edge `UPDATE` or `DELETE` | nothing | the node after the write | |
| A delete of a node, which deletes its edges | `DELETE` of the node, read with no edges | first `DELETE` of each edge with `node: NULL` | |
| A write to the source table of a view | `UPDATE` (or `CREATE`, `DELETE`) of the group row on a watch of the view | | |
| A write to a linked record that the projection or the filter reads | nothing | nothing | the rows that link to it, after the write: `SELECT .. WHERE site = $parent.id` in the payload. The test may go through an edge (`$parent.id IN <-cares_for.in`), a second hop (`kennel.site = $parent.id`) or `rows()` (`$parent.id IN (SELECT VALUE id FROM badge).kennel`) |
| An update of a linked record that changes no field that the clauses read | nothing | nothing | nothing: the `WHERE $before.f != $after.f` on the written table. A create and a delete pass it |
| A write to a record that no row links to | nothing | nothing | an empty list |
| A write to a table that a filter reads with `rows()` | nothing | | every row of the result's table, with the write in `rows()` |
| Two edge tables in one watch | | one notice of the statement of each table that the write is in | |

The live blocks of `monitoring.roc` (`examples/monitoring.roc:867`) check each part:

| Block | Writes | Shows |
| --- | --- | --- |
| `fevered`, `hotter_than` | create, a row with no fever, leave, enter, stay, no change, delete | `now`, the leave, the `LET` |
| `daily_view` | a reading, then its delete | the group row of the view |
| `unattended` | a kennel, a carer comes, a label, the carer goes, a carer is deleted, the kennel is deleted | the edge statement, `node: NULL` |
| `unattended_read` | a kennel, a carer comes, the carer goes, the kennel is deleted | the edge statement of an `In` field of a read row |
| `fevered_kennels` | a label of a kennel with a fever, the label back, a reading written and deleted | a semi join in the filter; a write to the readings sends each kennel, and the kennel with the new fever enters |
| `kennel_sites` | a new name of each of two sites, a site that no kennel is at comes and goes, a write that changes nothing, the old names back | a `Linked` of a read row: a new name is an update of the kennel at the site |
| `oslo_kennels` | the same writes | a filter through `.get()`: the kennel leaves when its site gets a new name and enters again with the old one |
| `neglected` | a kennel, a check comes, a carer comes, the check goes, the carer goes, a check comes, the kennel is deleted | two edge tables, `and_incoming`: a write to either reaches the kennel |
| `fever_events` | the writes of `fevered` | `live_raw`: the leave sends nothing |
| `vital_patches` | create, update, delete | `live_diff`, with the patches written by hand |

#### Decoding

A live session speaks CBOR, the WebSocket subprotocol `cbor`. The package
reads it with roc-cbor 0.4.0, through the `parser_for` of each Roc type.
Each read uses the options `{ ignore_tags: [6, 10], dec_from_text: Bool.True,
unions: Internal({ tag: "kind", content: "value" }) }` (`Surreal.read_options`), so NONE before `null` is no value, a decimal reads from
its text, and a tag union reads the form that the ORM writes (`Encode.tagged`):
`'Cash'`, `{ kind: 'Card', last4: .. }`, `{ kind: 'Check', value: 7 }`,
`{ kind: 'Wire', value: ['eu', 9] }`. roc-cbor reads the map itself for a
payload whose reader is a record reader (`parse_record_start`), and the item
at `value` for any other reader, so `At(Point)` reads
`{ kind: 'At', value: <geometry> }`. SurrealDB's own values are nominals
of `Surreal` with a `parser_for` of their own, on the tag API of roc-cbor:

| SurrealDB value | CBOR | Roc type | Where |
| --- | --- | --- | --- |
| Record id | tag 8, `[table, key]` | `Id(row)`, a `Link(row)` that is not fetched, `Ref` | `Surreal.Id`, `Surreal.Link`, `Surreal.Ref` |
| Time series key | `[series, time]`, as `record::id(id)` gives it | `TimeKey(s)` | `Surreal.TimeKey` |
| Datetime | tag 12, `[seconds, nanoseconds]`, the nanoseconds left out when 0 | `Datetime` | `Surreal.Datetime` |
| Duration | tag 14, `[]`, `[seconds]` or `[seconds, nanoseconds]` | `Duration` | `Surreal.Duration` |
| Decimal | tag 10 and its text: `'4E+1'` is 40 | `Dec` | the options |
| NONE | tag 6 and `null` | an absent `?:` field, `Err(Missing)` | the options |
| Geometry | tags 88 to 94, each point a tag 88 of floats | `Point`, `Line`, `Polygon`, `MultiPoint`, `MultiLine`, `MultiPolygon`, `Collection`, `Geometry` | `Surreal.Geometry` |
| Uuid of a live query | tag 37, 16 bytes | `Surreal.Uuid` (`Rpc.Uuid`) | `src/Rpc.roc:13` |

The key of a `Ref` is a `Ql.Value`, as the Mirror writes it, so a decoded
`Ref` and a predicted one are equal. `Surreal.value_of`
reads a key: a text, a number, a record id, a datetime, a decimal, an array
or an object. A key of another kind, such as a duration, is an error.

A message of the session has fixed fields around a row of the type `out`.
The fields are read with fixed types, and the row as a `Cbor.Value`, which
`Surreal.row_of` reads as `out`: the compiler derives no
`parser_for` of a record, a list or a tuple over a type variable, such as
`{ row : out, now : Bool }`, in a generic function.

| Function | Reads | Gives |
| --- | --- | --- |
| `Watch.start`, `RawWatch.start`, `DiffWatch.start` | The reply to the request | `{ live, view }`: the `Live` with the `Lives`, the uuid and the role of each `LIVE` (`Lives`), and the `View` of the snapshot (an empty `DiffView`, or `{}` for a raw watch). A statement or a request that failed is `Server(error)`, by its kind (see "Errors") |
| `Watch.notice`, `RawWatch.event`, `DiffWatch.patch` | One message | A `Frame`: `Mine` for a message of the watch, with its notices (a list for `Watch.notice`: one for each row of a `read` statement), `Other` for one of another live query, `Killed(uuid)`, `Reply` or `ReplyError` |
| `Live.receive`, `RawLive.receive`, `DiffLive.receive` | One message | `Got({ item, live })`: the changes (with the members of `Watch.step`), the event or the patch, and the watch after it; `Skip(live)` for a message of another query; or `Ended` when its live query is killed. Pure |

`DecodeTest.roc` reads the messages of `fixtures/`, which SurrealDB sent for
the live blocks of `monitoring.roc`. Each notice of `fevered` decodes to the
notice that the Mirror predicts for its write, the messages of
`unattended` give the changes of the block, in order, and a message of the
`read` statement of `kennel_sites` gives one notice for each kennel at the
site, or none.

#### The session

`Surreal.Session` is a session of SurrealDB's RPC on
`/rpc`, over a `Transport`: a WebSocket or HTTP (see "Transports" below).
For a WebSocket, the app gives the adapter of roc-websocket for its
platform, which does the opening handshake, the frames, the masks, the
pings and the close. The requests are `Rpc.roc`.

SurrealDB multiplexes one session: many requests can be in flight, a reply
has the id of its request, and a notice has the uuid of its live query.
The session holds an `Inbox`, which is pure. Each call
reads frames into the inbox until the inbox holds what the call waits for,
and takes that out. The other frames stay for the calls that want them. So
the watches, the plain queries and the writes of an app share one session,
and no notice is lost.

| Frame | The inbox |
| --- | --- |
| A reply | Keeps it by its id, until `await!` or `Unchecked.query!` takes it |
| A notice of a watch of the session | Keeps it with its uuid, in the order it came, until `next!` takes it |
| A notice that comes before the reply to `live!` | Holds it until the reply gives the uuids of the watch |
| `KILLED` of a watch | Keeps it as a notice of the watch, which then ends |
| A notice of a uuid that no `live!` of the session opened | Drops it. A `LIVE` in the text of `Unchecked.query!` is not a watch |

SurrealDB 3.3.4 sends the frames in these orders (`MuxTest.roc` reads them
from `fixtures/mux/`):

| Fact | Frames |
| --- | --- |
| Replies to requests in flight come out of order | Five requests, and the first sleeps 800 ms: its reply comes last |
| A notice can come while a call waits for the reply to another request | A write over HTTP while a request sleeps |
| The notice of a write can come before or after the reply to that write | A create and a `RETURN` in one request, and a write to each of two tables in one request |
| `KILLED` can come before or after the reply to `kill` | Both orders, in two runs of one probe. `MuxTest.roc` reads the recorded order and the other |
| Requests in flight run at the same time on the server, so they have no order | The create of request 11, sent after request 10, runs and replies while 10 sleeps |
| The notices of two requests can come in the other order, also when the app waited for the reply to the first before it sent the second | One session, 300 groups of a create, an update and a delete of one row, each request sent after the reply to the one before: in 5 of 10 runs on a busy machine, notices came in another order, for example the delete of a row before its update. A notice has no count or time that gives the order of the writes |

| Method | Does |
| --- | --- |
| `open!` | A session over a `Transport`: the opening request of a WebSocket, then the `Login`: `signin` and `use` of a system user, `signup` or `signin` of a record user, `authenticate` of a token (see "Record users and permissions") |
| `token`, `invalidate!` | The token of a session of a record user. `invalidate`: the session is no one |
| `pushes` | Whether the transport gives pushed messages, which a watch needs |
| `live!(watch)` | A `Watch` (`Selected.live`), a `RawWatch` (`Selected.live_raw`) or a `DiffWatch` (`Query.live_diff`): the request of the watch, and its reply read, as `{ session, live, view }`. `live` is a `Live(out)`, `RawLive(out)` or `DiffLive(row)`, the state of the watch, as pure data. `view` is the snapshot `View(out)`, an empty `DiffView(row)`, or `{}` for a raw watch |
| `next!(live)` | The next item of the watch: `Got(item)`, `Ended` when the watch was killed, or `Unread(error)` for a notice that does not read. `item` is the `List(Change(out))` of the next notice that has any, an `Event(out)` or a `Patch(row)`. `live.receive` reads each message |
| `stream(live)` | The items as a stream, for any kind of watch. Each item has the item, and the session and the watch after it, so the app can stop and use that session |
| `send!`, `await!` | A prepared statement sent with no wait, and its `Ticket(out)`. Then its reply, read as `out` |
| `run!` | `send!`, then `await!`: `{ session, result }`, one `Try` |
| `knowing(defs)` | The session, reading a unique index violation against the schema of `defs` (see "Errors") |
| `kill!` | The RPC method `kill` for each live query of a watch. The inbox drops the queued notices of the watch, and the ones that come later. The notices of other watches stay |

| Rule | Detail |
| --- | --- |
| Use the session that the last call gave back | Each call gives the session after it. An older copy has an older inbox and an older id. Roc cannot check this |
| A call that fails gives no session | An `Err` is a connection that failed or a frame that does not read. `run!` and `await!` are the exception: they always give the session, and `result` holds the rows or any error. After `Transport` the connection is gone |
| Requests in flight have no order | The server runs them at the same time. A step that needs another goes in one request (`Prepared.then`), or waits for the reply to the other (`await!`) |
| The notices of two writes can have no order | The reply to a write does not put its notice before the notices of the writes after it. A notice is before the notice of a write only when the app read it before it sent that write (see the note on order below) |
| Each request has a new id | The id is a count. SurrealDB does not check that two requests have different ids |
| The queued notices have no limit | The inbox keeps each notice of a watch until the app reads it or kills the watch |

Note on order. SurrealDB 3.3.4 can deliver the live notices of two writes
out of order. This can happen when both writes come from the same client, and
when the app sends the second write after the reply to the first. This is
upstream issue https://github.com/surrealdb/surrealdb/issues/7603. The
SurrealDB docs promise notices in order for transactions from the same client
(https://surrealdb.com/docs/surrealql/statements/live-select). A maintainer
says that SurrealDB 4.0 fixes the issue.

Until then, a view is correct only when the app received each change before
it sent the next write to the same records. `watch.roc` does this: it reads
the changes of each group before it sends the next group. When 4.0 is
available, test this again: make `watch.roc` send all the writes of a watch
before it reads the changes, and run it many times. If the order holds, remove
that step.

A different open issue is https://github.com/surrealdb/surrealdb/issues/6983.
A write made at about the same time as the `LIVE SELECT` can be missing from
both the first read and the live notices.

`watch.roc` runs on basic-cli 0.26.0 against the database that `check.py`
leaves. It starts `unattended`, `fevered`, `kennel_sites` and a `live_diff`
of the readings on one session. For each watch, it writes rows of its own
on the same session with `send!` and `await!`. Two writes of `fevered` that
do not depend on each other are in flight together, and their replies are
read the last first. After each group of writes, the app reads the changes
of the group with `next!`: the inbox kept the notices that came
while the writes ran. Then it starts the next group, because the notices of
two writes have no order. The changes of
each group of writes must equal the changes that the Mirror and
`Watch.step` predict from the members of the snapshot, in any order, and
each patch, applied to a `DiffView`, must give the row that Roc wrote.

Then a second session, on a database `roc_watch` that the app makes again
with tables of its own, starts four watches of the links that the clauses
read. A write that the Mirror predicts no change for comes before a write
that changes the result, so a notice that should not come is a `FAIL` of
the next group:

| Watch | Clause | Writes that send nothing | Writes that change the result |
| --- | --- | --- | --- |
| `labels` | `select(\|k\| { label: k.label })` of a read row with a `Linked(Site)` and an `In(CaresFor)` | a new name of the site, a carer that comes and goes | a new label |
| `carer_names` | `.incoming(cares_for)`, `edges.map(\|e\| e.from.get().name)` | a new name of a carer of no kennel | the carer comes (the edge), gets a new name (the link of the edge row), goes |
| `badge_sites` | `b.kennel.get().site.get().name` | a new label of the kennel, a new place of the site, a new name of a site that the badge no longer reaches | a new name of the site (the second hop), the kennel moves to another site (the first hop) |
| `badged_carers` | `badges.rows().any(\|b\| b.kennel.get().label == c.name)` | a kennel that no badge links to, the badge (no carer enters) | the kennel of the badge gets the label of the carer (it enters), then its old label (it leaves) |


```
unattended: 1 rows in the snapshot
ok   Added kennel:⟨w⟩ { carers: 0, label: "Watch" }
ok   Removed kennel:⟨w⟩ { carers: 1, label: "Watch" }
..
kennel_sites: 2 rows in the snapshot
ok   Added kennel:⟨v⟩ { label: "Pier", site: "Harbour" }
ok   Updated kennel:⟨v⟩ { label: "Pier", site: "Old harbour" }
ok   Removed kennel:⟨v⟩ { label: "Pier", site: "Old harbour" }
vital_patches:
ok   Create vital:[kennel:⟨a⟩, d'2026-03-09T12:00:00Z'], temp_c Set(39.4), row .. pulse 85 temp_c 39.4 fevered True
ok   Update vital:[kennel:⟨a⟩, d'2026-03-09T12:00:00Z'], temp_c Set(37.9), row .. pulse 85 temp_c 37.9 fevered False
ok   Delete vital:[kennel:⟨a⟩, d'2026-03-09T12:00:00Z'], temp_c Unset, no row
..
badge_sites: 0 rows in the snapshot
ok   Added badge:⟨tag⟩ { note: "Tag", site: "Dock" }
ok   Updated badge:⟨tag⟩ { note: "Tag", site: "Old dock" }
ok   Updated badge:⟨tag⟩ { note: "Tag", site: "Quay" }
ok   Removed badge:⟨tag⟩ { note: "Tag", site: "Quay" }
```

The exit code is 1 when a line fails. A notice that does not come is a
wait with no end: the server pings the session every 5 s, so the read
timeout of the adapter does not end the wait (verified), and `check.py`
stops the app after 900 s. `check.py` runs `watch.roc` as its last block,
`app: watch.roc`, on the database that its scripts leave. The app connects
to `127.0.0.1:8000` as `root`.

#### Transports

A session reaches the server through a `Transport`,
a value of one type with two constructors. `Session.open!` takes either,
so the session type, and the type of each function of the API, is the same
on both. Only the transport that the app builds differs:

```roc
# A WebSocket, through the adapter of the platform (`watch.roc` and
# `client.roc` on basic-cli, `server.roc` on basic-webserver)
transport = Surreal.Transport.websocket(WsClient.connect, WsClient.ops, "ws://127.0.0.1:8000")
# HTTP (`client.roc -- --http`, and the comment in `server.roc`)
transport = Surreal.Transport.http(http_client, "http://127.0.0.1:8000")

session = Surreal.Session.open!(transport, Root({ ns: "roc", db: "roc_surreal", user: "root", pass: "root" }))?
```

| Constructor | Takes | From the platform |
| --- | --- | --- |
| `Transport.websocket(connect, ops, url)` | A `Ws.Connect` record of roc-websocket, `{ connect! }`, and a record with `send!` and `receive!` over the same connection type and error row, such as the adapter's `ops`. The session connects to `url` + `/rpc` with the subprotocol `cbor` | The adapter of the platform: `WsClient.connect` and `WsClient.ops` of roc-basic-cli-websocket 0.0.1 or roc-basic-webserver-websocket 0.0.1 |
| `Transport.http(client, url)` | `HttpClient`: `{ post! }`, an `HttpRpc.Post` (the URI, the headers and the body) in, the status and the body of the response out | basic-cli's or basic-webserver's `Http.send!` |

A transport sends nothing until `Session.open!` connects it. Connected,
it is a `Connection`, one field for each feature, and the session calls
only these fields:

```roc
Connection :: {
	request! : Credentials, List(U8) => Try({ connection : Connection, reply : [Sent, Replied(List(U8))] }, Error),
	pushed : [Supported({ next! : {} => Try({ connection : Connection, message : List(U8) }, Error) }), Unsupported],
}
```

| Field | Feature | WebSocket (`websocket_connection`) | HTTP (`http_connection`) |
| --- | --- | --- | --- |
| `request!` | Sends one RPC message, a CBOR `{ id, method, params }`, with the `Credentials` of the session | One `Binary` message: `Sent`. The reply comes later, as a message of `pushed`. The credentials are the connection's: the server keeps the login of the socket | One `POST /rpc` with the credentials in its headers: `Replied`, with the reply that its response holds |
| `pushed` | The messages that the server sends when it wants: the replies to `Sent` requests, and the notices of live queries | `Supported`: the next message of the session (the adapter answers a `Ping`) | `Unsupported` |

A connection of roc-websocket is a value that each call gives back
changed: it holds the state of the protocol, such as the bytes read past
a frame. So each call of a `Connection` gives the next `Connection`, whose
closures hold the next value of the adapter's connection, and the session
keeps it, as it keeps its inbox. The type of the adapter's connection and
of its errors stays inside those closures, so the `Session` has no type
parameter, and one `Session` runs on any adapter and over HTTP.

Every connection has `request!`, because a session needs `signin`, `use`
and `query`. `pushed` is a tag and not a function that fails, so the
session knows what the transport lacks before it sends anything. The
WebSocket is one section of `Surreal.roc` (`websocket!`,
`websocket_connection` and `ws_error`); the rest of the session knows only
the `Connection`. An error of the adapter is `WebSocket`: `Closed` with how
the connection ended, `Closing`, or the adapter's own tag as text (see
"Errors").

`HttpRpc.roc` writes the post: `Content-Type` and `Accept`
`application/cbor`, the `Authorization` of the session, and `surreal-ns`
and `surreal-db`. SurrealDB 3.3.4 keeps no state between two posts
(verified: after a `use`, a post with no `surreal-ns` is refused with
"Specify a namespace to use"), so each post carries who the session is, the
`Credentials` that the session holds (`HttpRpc.Auth`):

| Session | `Authorization` | `surreal-ns`, `surreal-db` |
| --- | --- | --- |
| `Root` | `Basic` with the user and the password: its `signin` and `use` only check them | The login's |
| `SignUp`, `SignIn` | `Bearer` with the token that the reply gave. The `signup` or `signin` post itself has none | The login's |
| `Token` | `Bearer` with the token. The `authenticate` post has none | None: the token holds them, and SurrealDB 3.3.4 runs a post with a token and no `surreal-ns` in the token's (verified) |
| After `invalidate!` | None | As before |

The response has status 200 for each RPC reply, also one with an error; any
other status is a `Server` error, such as 401 for a wrong password or a
token that does not verify (`Denied`).

| Function | WebSocket | HTTP |
| --- | --- | --- |
| `run!`, `Unchecked.query!` | The request, then frames read into the inbox until the reply comes | One post, its reply into the inbox, and the reply taken out |
| `send!` | Sends the frame, and does not wait | Posts, waits for the response, and keeps the reply in the inbox by its id |
| `await!` | The reply from the inbox, else frames read until it comes | The reply from the inbox. None there (an older session, or a ticket awaited twice) is a `Wire` error |
| `send!` twice, then `await!` the last first | Both in flight together, with no order on the server | Works: the first runs to the end before the second is sent, so the requests run in order |
| `live!` | Starts the watch | `Unsupported`, and nothing is sent |
| `next!`, `stream` | The next notice | `Unsupported` |
| `kill!` | Ends the watch | `Unsupported` |

`client.roc` runs its queries on either: `roc client.roc` on a WebSocket,
`roc client.roc -- --http` over HTTP. Only `open!` in the app tells them
apart. It also sends two requests and awaits the second first
(`pipelined`), and over HTTP checks that `live!` is `Unsupported`
(`watch_over_http`).

`server.roc` is a web server on basic-webserver 0.20.0. `GET
/readings?min_pulse=N` opens a WebSocket session through
roc-basic-webserver-websocket, runs a typed query with
a parameter, and answers with the readings, one line each:

```
$ roc server.roc &
$ curl 'http://127.0.0.1:8001/readings?min_pulse=120'
kennel b at 2026-03-01T23:59:59Z: pulse 130, temp_c 38.0
kennel a at 2026-03-02T09:15:00Z: pulse 125, temp_c 38.0
kennel b at 2026-03-02T11:00:00Z: pulse 121, temp_c 39.1
kennel b at 2026-03-01T10:00:00Z: pulse 120, temp_c 39.0
```

A limit of basic-webserver 0.20.0: each handler runs for one request, and
its effects are scoped to that request, so a session does not outlive the
request that opened it. The `Tcp` reads of the platform time out after
30 s (the adapter's `receive!` waits on through them), and a watch, which
waits for notices with no end, has no place in a handler. A comment next
to `transport` in `server.roc` gives the same server over HTTP
(`Transport.http` with the platform's `Http.send!`), where a plain query
takes one post, and a query that runs longer than the 30 s of
`Http.send!` is a `Transport` error. Any error is answered with status
502.

#### Patches

A `live_diff` op has a path and a value. `Diff.pointer` splits a path, and
`Diff.TextPatch` reads and applies the text patch of a `change` op, which
SurrealDB sends for a string edited in place. Its positions count Unicode
scalar values, and its text is UTF-8 with `%XX` escapes. `apply` is exact:
the text must hold each kept and deleted part where the hunk starts.

| Item | Detail |
| --- | --- |
| `Diff.Op` | `Add(pointer, value)`, `Remove(pointer)`, `Replace(pointer, value)`, `Change(pointer, text patch)`. A value is a `Cbor.Value`, with its tags |
| `Diff.apply` | One op on a stored row. A part of a pointer is a map key or an array index; `Add` puts an array item before the index, and `-` is the end. A pointer that the row does not have is `BadPath` |
| `Surreal.Patch(row)` | The ref, the action and the ops of one write |
| `Patch.field` | What the patch did to one field, read with a reified path: `patch.field(\|v\| v.temp_c)` is `Set(39.6)`, `Unset`, `Inside` or `Untouched`. The last op that reaches the field decides; the replace of `""` by a create sets each field |
| `Surreal.DiffView(row)` | The stored rows as values. `apply` adds a row on a create, removes it on a delete, and gives `UnknownRef` for an update of a row it does not hold. `get` and `rows` read a row as `row`, with its record id read as its key |

### Typed results of plain queries

A plain query runs in a session too, and its result comes back as Roc
values of the type of the query. `prepare(params)` is the one way to make a statement
of a query or a write. It gives a `Surreal.Prepared(out)` that
knows the type of its result. `prepared.statement()` is its text for a script or a test (a `Statement`: `to_script()`, `block(header, directives)`), `prepared.request()` the text of the request, and `to_surql()` the text with a `$name` for each parameter. `Session.run!` sends its text with
the RPC method `query` and reads the reply as `out`, with the readers of
"Decoding". The result is `{ session, result : Try(out, Surreal.Error) }`:
a statement that fails is `Server(error)`, typed by the server's kind (see
"Errors").

| Roc | SurrealQL | Result |
| --- | --- | --- |
| `Selected.prepare(p)` | The query | `List(out)`: the result rows |
| `Selected.prepare_one(p)` | The query, from `Table.at`. Any other query is an `Unsupported` | `Try(out, [NotFound])`: the row of the key, or `NotFound` |
| `Totals.prepare(p)` | The query of `Query.totals`, `GROUP ALL` | `out`: the one row, also for no rows |
| `Write.prepare(p)` | `UPDATE .. RETURN AFTER`, `DELETE .. RETURN BEFORE`. By key, `update_at`, `set_at` and `delete_at`: `UPDATE t:⟨k⟩ ..`, `DELETE t:⟨k⟩ ..` | `List(row)`: the rows after an update, before a delete. None for a key with no row |
| `Table.insert(rows)` | `BEGIN; INSERT .. RETURN AFTER; COMMIT` (`INSERT RELATION` on an edge table) | `List(row)`: the rows that the write wrote |
| `Table.create(row)` | `CREATE t:⟨k⟩ CONTENT .. RETURN AFTER`, or `RELATE` on an edge table | `List(row)`: one row. A row that exists is an error |
| `Table.upsert(row)` | `UPSERT .. RETURN AFTER` | `List(row)` |
| `Table.replace(row)` | `UPDATE t:⟨k⟩ CONTENT .. RETURN AFTER`, with the key of the new row: the old row is not needed, as `Replace(a, b)` takes it for the Mirror only | `List(row)`: one row, or none for a key with no row |
| `Table.insert_or_update(rows, \|new, old\| ..)` | `BEGIN; INSERT INTO t [..] ON DUPLICATE KEY UPDATE .. RETURN AFTER; COMMIT`; each item is `IF id != NONE { .. }` | `List(row)`: the rows as stored, in the order of `rows` |
| `Table.merge_at(id, partial)`, `Table.upsert_merge_at(id, partial)`, `Table.merge(condition, partial)` | `UPDATE t:⟨k⟩ MERGE { .. } RETURN AFTER`, `UPSERT t:⟨k⟩ MERGE { .. }`, `UPDATE t MERGE { .. } WHERE .. RETURN AFTER` | `List(row)`: the rows after the write. None for a key with no row (`merge_at`) |
| `Table.patch_at(id, patches)`, `Table.patch_ops_at(id, ops)` | `UPDATE t:⟨k⟩ PATCH [{ op, path, value }, ..] RETURN AFTER`, the ops of the patches in order | `List(row)`: one row, or none for a key with no row |
| `Table.create_new(new)` | `CREATE t CONTENT .. RETURN AFTER`, or `RELATE a->t->b` on an edge table: no key, the server makes it | `List(Created(row, new))`: one row, its `Id` and its other fields |
| `Table.insert_new(rows)` | `BEGIN; INSERT .. RETURN AFTER; COMMIT`, rows with no `id` | `List(Created(row, new))`: each row, in the order of `rows` |
| `Table.edit(Create(r) \| Replace(a, b) \| Delete(r))` | `Create(r)` is `Table.create`. `Replace(a, b)`: `UPDATE t:⟨k⟩ CONTENT .. RETURN AFTER`. `Delete(r)`: `DELETE t:⟨k⟩ RETURN BEFORE` | `List(row)`: one row, or none for a replace or a delete of a row that is not there |
| `a.then(b)` | The `LET`s of both, each name once, then the statements of `a` and of `b`, each runs on its own | `(Try(x, Error), Try(y, Error))` |
| `a.begin().then(b)?.commit()` | The `LET`s, `BEGIN`, the statements of `a` and of `b`, `COMMIT` | `(x, y)`, or `Aborted` |

| Rule | Detail |
| --- | --- |
| A reply has one result for each statement | A `LET`, a `BEGIN` and a `COMMIT` too. A `Prepared` holds the count of its statements, whether they run in a transaction, and a reader of their results, each a value or an error (`Surreal.Outcome`). `result` skips the results of the `LET`s, and `then` gives each side its own results |
| A result row of a query | Read as `out` (`Surreal.row_of`), with the options of "Decoding". The columns of a projection are the fields of `out` |
| A write needs a `parser_for` of its row | The five writes read the stored row back, so the row type needs a `parser_for` (a nominal row declares `parser_for : _`) |
| A row that a write returns | The row as stored: its `id` is a record id, and the ends of an edge are `in` and `out`. `Surreal.stored_row` reads the record id as its key, and `in` and `out` as `from` and `to`, as `DiffView` reads a row. A field that the database computes has the stored value |
| The type is checked when the program compiles | `prepare` needs a `parser_for` of the result row, so a `prepare` of `Unchecked.select_star` is a type error |
| The text is pure, and so is the reading | `request` is the text, and `result` reads the bytes of a reply. `Unchecked.query!` sends a text and gives the reply, not read, and `Unchecked.result` reads it. `run!` sends the text of a `Prepared` and reads its reply. `send!` and `await!` are its two halves, for requests in flight together |

A plain query goes over RPC on either transport, also over HTTP: a `POST
/rpc`, not `/sql`. A `POST /sql` with `Accept: application/cbor` also works
(verified), but its reply is a list of results with no envelope. Over
`/rpc` the reply is the same message as on a WebSocket, so the session has
one reader of a reply (`Surreal.query_results`) for a watch and a plain
query, on either `Transport`.

`client.roc` runs on basic-cli 0.26.0 against the database that `check.py`
leaves. It runs queries of `monitoring.roc` (a filter, whole rows with a
`TimeKey`, a group, a `LET` over a subquery, an order and a limit, a
geometry parameter, whole rows with a point and a polygon, a read row with
`Linked` and `In`), then writes of its
own: a create, the same create again, a relate, an update and a query in
one request, an insert, a reading whose `fevered` the database computes,
and the deletes. Last, it defines a table of its own, `payment`, with a tag
union field that has each form of an arm (`Cash`, `Card({ last4 })`,
`Check(7)`, `Wire("eu", 9)`), inserts a row of each form, reads them back as
`Pay` and in a `match` of a clause, and removes the table. Then it defines
`placement`, with a union of a geometry, a link, a datetime, a nominal
record and two values (`At(Point)`, `Kept(Link(Bin))`, `Since(Datetime)`,
`Shelved(Shelf)`, `Stacked(Str, I64)`), and the table `bin` that it links
to, with a unique `label`: a second bin with the label of the first is a
`Unique` error that names the field. A transaction of a create and an
insert of another `Top` is `Aborted` at the insert, and the create is
rolled back; the same create of a twin and a read, on their own, give the
error and the rows; a transaction of a create, an insert and a read
commits. It inserts a row of each arm, reads them back, writes an arm in a
clause, as a parameter and from fields of the row, and removes both tables.
Last, it defines `shift` (ULID keys), `task` (UUID keys, a link to a
shift) and the edge table `handover` (SurrealDB's random keys), writes
rows with no `id`, links tasks and an edge to the keys that the server
gave, reads a shift by its `Id`, deletes it by its `Id`, and removes the
three tables (see "Keys that the server makes"). Each result must equal the result that Roc computes from
the same functions over the rows in the database:

```
ok   fevers: 4 rows
ok   kennel_a_rows: vital:[kennel:⟨a⟩, d'2026-03-01T00:00:00Z'] pulse 82 temp_c 38.4 fevered False; ..
..
ok   create_kennel_again: Server(Exists({ message: "Database record `kennel:q` already exists", name: "kennel:q", what: "Record" }))
ok   relate_carer: 1 row
ok   relabel_then_read: 1 row, then 1 row
..
ok   create_reading: vital:[kennel:⟨a⟩, d'2026-03-10T12:00:00Z'] pulse 85 temp_c 39.4 fevered True
..
ok   define_payments: 2 statements
ok   insert_payments: 4 rows
ok   payment_rows: 4 rows
ok   payment_lines: 4 rows
ok   remove_payments: 1 statement
ok   define_places: 9 statements
ok   insert_bins: 1 row
ok   insert_bin_again: Server(Unique({ fields: ["label"], index: "bin_label_unique", message: "..", record: "bin:b1", table: "bin", value: "'Top'" }))
ok   twin_in_transaction: Aborted({ at: 1, error: Unique({ fields: ["label"], .. }) })
ok   bins_after_abort: 1 row
ok   twin_then_rows: Server(Unique({ fields: ["label"], .. })), then 1 row
ok   stock_up: 1 row, then 1 row, then 3 rows
ok   insert_places: 6 rows
ok   place_rows: 6 rows
ok   place_literal: 1 row
ok   place_bound_point: 1 row
..
ok   place_row_datetime: 1 row
..
ok   place_rows_after: 6 rows
ok   remove_places: 2 statements
ok   define_shifts: 9 statements
ok   create_shift: 1 row, ULID keys
ok   insert_shifts: 2 rows, ULID keys
ok   insert_tasks: 2 rows, UUID keys
ok   relate_handover: 1 row, random keys
ok   shift_at_key: the row
..
ok   delete_shift: 1 row
ok   task_lines_after: 1 row
ok   remove_shifts: 3 statements
```

The exit code is 1 when a line fails. `check.py` runs it as its last
block, `app: client.roc`, after `watch.roc`. With `-- --record DIR`, it
saves the reply to each request as `DIR/<name>.cbor`: `check.py --record
fixtures` passes `fixtures/queries`, and `PreparedTest.roc` reads the
files.

#### Transactions

`Prepared.then` sends two prepared statements in one request, and each
runs on its own: SurrealDB 3.3.4 runs every statement of a request, also
after one failed (verified: a create that a unique index refuses, then a
select, gives the error and the rows). So the result keeps the result of
each, with its own error, and nothing that ran is hidden behind the error
of another. A transaction is a combinator of its own, not what `then`
does: a read after a write needs no transaction, a transaction can
conflict with another and fail at its `COMMIT`, and its result is all or
nothing.

```roc
stocked = create.begin().then(insert)?.then(rows)?.commit()
# BEGIN; CREATE bin:⟨b3⟩ .. RETURN AFTER; INSERT INTO bin [..] RETURN AFTER; SELECT .. FROM bin; COMMIT;
match session.run!(stocked).result {
	Ok(((created, inserted), after)) => ..
	Err(Aborted({ at: 1, error: Unique({ fields: ["label"], .. }) })) => "the insert has a label that is taken"
	Err(e) => Str.inspect(e)
}
```

| Roc | SurrealQL | Result |
| --- | --- | --- |
| `p.begin()` | `p`, the first part of a `Surreal.Transaction(out)` | |
| `t.then(q)` | The parts of `t`, then `q`; a name bound in both must have one value | `Transaction((a, b))`: each `then` nests the pair |
| `t.commit()` | `LET`s, `BEGIN;`, the statements of each part, `COMMIT;`, one `query` | A `Prepared(out)`, for `run!`, `send!` or `then` |

| Rule | Detail |
| --- | --- |
| One request, either transport | The text is one `query`, on a WebSocket or in one `POST /rpc`, so the transaction is the server's (verified on both: a unique index that fails the second write rolls back the first) |
| The failure | `Aborted({ at, error })`: `at` is the part that failed it, 0 for the one `begin` took, and the count of the parts for the `COMMIT`, such as a `Conflict`; `error` is its `ServerError`. Every other statement is rolled back or did not run: the server gives each `NotExecuted`, and `Cancelled` for those after the failure (`Surreal.Outcome` marks them `follows`) |
| A part that is a transaction | An insert runs in a transaction of its own (`BEGIN; INSERT ..; COMMIT`). As a part it has none: SurrealDB refuses a nested `BEGIN` (verified). On its own, its failure is `Server`, the error of the `INSERT` |
| A transaction in a batch | `commit` gives a `Prepared`, so `then` takes it as one side: its `Aborted` is the error of that side |
| `LET`s | Before the `BEGIN`: their values are literals, and the server reads them in the transaction (verified) |
| `THROW` and `CANCEL` | A `THROW` in a transaction fails it with `Thrown`, and `CANCEL TRANSACTION` gives `Cancelled` for each statement and no error (verified). The typed API writes neither: a conditional abort is a constraint of the schema (`Def.assert`, `Def.check`), which fails the statement that breaks it |

`PreparedTest.roc` reads the replies of the transactions of `client.roc`
(`fixtures/queries/twin_in_transaction.cbor`, `stock_up.cbor`, and the
batch `twin_then_rows.cbor`), and `HttpTest.roc` the same over HTTP.
`ErrorTest.roc` reads the recorded transaction of an `Assert` as
`Aborted` at 1, and the recorded `Conflict` as `Aborted` at the `COMMIT`.

### Record users and permissions

A record user signs up and signs in through an access method of the
database, and the permissions of a table decide which rows each record
user reads and writes. Both are clauses of the schema, Roc functions that
the translator writes as SurrealQL, in `client.roc`:

```roc
Credentials : { email : Str, pass : Str }

accounts : Surreal.Access(Credentials, Credentials)   # the variables of a signup, of a signin
accounts = Surreal.access("account")

accounts.define(users, |v| { email: v.email, pass: Surreal.Hash.argon2(v.pass) }, |v, u| u.email == v.email and Surreal.Hash.argon2_matches(u.pass, v.pass))
	.token_for(Surreal.Time.hours(1))
	.done()

memos.define()
	.permit([Select], |m| m.owner.id() == users.auth() or m.shared)
	.permit([Create, Update, Delete], |m| m.owner.id() == users.auth())
	.permit_field(|m| m.text, [Update], |m| !m.shared)
	.done()
```

```sql
DEFINE ACCESS OVERWRITE account ON DATABASE TYPE RECORD SIGNUP (CREATE user CONTENT { email: $email, pass: crypto::argon2::generate($pass) }) SIGNIN (SELECT * FROM user WHERE (email = $email) AND crypto::argon2::compare(pass, $pass)) DURATION FOR TOKEN 3600000000000ns;
DEFINE TABLE OVERWRITE memo SCHEMAFULL PERMISSIONS FOR select WHERE (owner = $auth.id) OR shared, FOR create, update, delete WHERE owner = $auth.id;
DEFINE FIELD OVERWRITE text ON memo TYPE string PERMISSIONS FOR update WHERE !shared;
```

| Definition | Roc | SurrealQL |
| --- | --- | --- |
| `Access(up, on).define(table, signup, signin)` | `signup : Code(up -> new)`, the new row without its `id`. `signin : Code((on, row -> Bool))`, a `filter_by` over the variables and the row. The table is `Table({ id : Str, ..new })`, so the signup gives a row of the table and the signin reads one, both checked by the compiler | `SIGNUP (CREATE t CONTENT { .. })`, `SIGNIN (SELECT * FROM t WHERE ..)`. Each variable is a `$name`. The signup may call `Hash.argon2` and `Rand`, as a write (see "`Rand` and the effect rule"); the signin may not |
| `AccessDef.token_for(d)`, `session_for(d)` | A `Duration` | `DURATION FOR TOKEN ..ns, FOR SESSION ..ns`. Without them SurrealDB's defaults: a token of 1 hour, a session with no end |
| `Def.permit(actions, condition)` | `condition : Code(row -> Bool)`, as a `filter` | `FOR select, update WHERE ..` on the table |
| `Def.permit_full(actions)` | | `FOR .. FULL` |
| `Def.permit_field(path, actions, condition)`, `deny_field(path, actions)` | `select`, `create`, `update` of one field; `Delete` is a `BadSchema` | `PERMISSIONS FOR .. WHERE ..`, `FOR .. NONE` on the field |

A table with no permission keeps SurrealDB's default, and the tables of
the other examples have none, so their scripts are as before. A table with
a permission names each action: the ones that no permission names are
`NONE`, which is SurrealDB's default for a table, written out. A field
names only its own, and SurrealDB's default for a field is `FULL`. An
action in two permissions is a `BadSchema`. A system user is not checked.

The access method is typed in full: the bodies are clauses, and the
variables are the records `up` and `on`, which `Access.sign_up` and
`sign_in` write with the derived encoder, so a variable that the signup
reads and the login does not send is a type error. What is left out: an
access method `ON NAMESPACE` or `ON ROOT`, `TYPE JWT` and `TYPE BEARER`,
`WITH JWT` keys of another issuer, an `AUTHENTICATE` clause, and a signup
other than a `CREATE` of one row. Each is a definition of its own, not a
clause over a row, so it would be text, and a script with a raw `DEFINE
ACCESS` (`Unchecked.query!`) gives the same.

The values of the session in a clause are intrinsics (see "Package
functions"): `users.auth()` is `$auth.id` as an `Id` of the table, so a
link compares with it (`m.owner.id() == users.auth()`), and so does the key
of a row (`users.id(u.id) == users.auth()`). `Surreal.Auth.access()` is
`$access`, the name of the access method, `NONE` for a system user, and
`Surreal.Auth.expires()` is `$token.exp`, in seconds since 1970. A query,
a write and a live query read them too, as the record user that runs them.

| Login (`Surreal.Login`) | RPC | The session |
| --- | --- | --- |
| `Root({ ns, db, user, pass })` | `signin` of a system user, then `use` | That user |
| `accounts.sign_up(scope, vars)`: `SignUp(RecordLogin)` | `signup` with `ns`, `db`, `ac` and the variables in one map | The new record user, with its token (`session.token()`) |
| `accounts.sign_in(scope, vars)`: `SignIn(RecordLogin)` | `signin`, the same | The record user, with its token |
| `Token(token)` | `authenticate` | The user of the token, which a session of a signup or a signin gave |
| `session.invalidate!()` | `invalidate` | No one: each request is refused, `Denied`, until a new session signs in |

`Session.open!` takes the login, and the session works the same on both
transports. A WebSocket session signs in once, and the server keeps the
login of the socket; `signup`, `signin` and `authenticate` there also set
the namespace and the database of the token (verified). Over HTTP each post
carries the credentials (see "Transports").

`client.roc` signs up Ann and Bob, and runs each step on a WebSocket and
over HTTP. SurrealDB 3.3.4 gives the same on both (verified):

| Step | Result |
| --- | --- |
| A record user selects `memo` | The rows that the permission keeps: Ann's two memos for Ann; Ann's shared memo and Bob's own for Bob. No error |
| `users.auth()` in a filter (`mine`) | Bob's memo only |
| Bob updates or deletes Ann's shared memo | No row, and no error: a write leaves out the rows that its permission does not keep. Also `UPSERT` and `INSERT` of a row that the permission refuses give none |
| Bob creates a memo whose `owner` is Ann | `Assert` on `memo.owner`: the link's `record::exists` runs as Bob, and Bob cannot read Ann's row of `user` |
| Ann updates the text of her shared memo | The row, with the text as it was: the field permission leaves the field out of the update |
| A field that a select may not read (`user.pass`) | Not in the row: `whoami` selects the key only |
| A request after `invalidate!` | `Denied`: `Anonymous access not allowed` |
| `Token(token)` of Ann's session, after Ann's session is invalidated | A session of Ann: SurrealDB keeps no list of the tokens it gave, so `invalidate` does not end a token |
| A signin with a wrong password | `Denied`. The server's error is `NotFound` (`No record was returned`) |
| A signup with an email that the unique index holds | `Denied`. The server's error is `Query` (`The record access signup query failed`) |
| A token that does not verify | `Denied`: `NotAllowed` of `authenticate`, and HTTP 401 of a post with it |
| A record user defines or removes a table, or reads `INFO` | `Denied` (`IAM error: Not enough permissions`) |

The three errors of a refused login are `Denied` in `Session.open!`
(`login_error`): the server does not say whether the user exists, by
design, and the kind of its error is all that differs.

### Full-text and vector search

An analyzer, a full-text index and a vector index are values, and the
definition of a table and the queries over it take the same values
(`search.roc`):

```roc
Chart : { id : Str, patient : Str, body : Str, embedding : List(F64) }

clinical = Surreal.analyzer("clinical", [Class], [Lowercase])
chart_text = charts.text_index(|c| c.body, clinical)
chart_vectors = charts.vector_index(|c| c.embedding, { dimension: 3, distance: Cosine })
Surreal.schema([clinical.define(), charts.define().text_index(chart_text).vector_index(chart_vectors).done()])
# DEFINE ANALYZER OVERWRITE clinical TOKENIZERS class FILTERS lowercase;
# DEFINE INDEX OVERWRITE chart_body_fulltext ON chart FIELDS body FULLTEXT ANALYZER clinical BM25 HIGHLIGHTS;
# DEFINE INDEX OVERWRITE chart_embedding_hnsw ON chart FIELDS embedding HNSW DIMENSION 3 DIST COSINE TYPE F64;

Surreal.from(charts)
	.search(chart_text, "limping")
	.select(|(c, hit)| { id: c.id, score: hit.score(), marked: hit.highlight("<b>", "</b>") })
	.order_by(|r| r.score, Desc)
# SELECT record::id(id) AS id, search::highlight('<b>', '</b>', 1) AS marked, search::score(1) AS score
#   FROM chart WHERE body @1@ 'limping' ORDER BY score DESC

Surreal.from(charts).filter(|c| c.patient != "rex").nearest(chart_vectors, [1, 0, 0], Exact(2)).select(|(c, near)| { id: c.id, distance: near.distance() })
# SELECT vector::distance::knn() AS distance, record::id(id) AS id FROM chart WHERE (patient != 'rex') AND (embedding <|2,COSINE|> [1f, 0f, 0f])
```

| Roc | SurrealQL | Rule |
| --- | --- | --- |
| `Surreal.analyzer(name, tokenizers, filters)`, `.define()` | `DEFINE ANALYZER OVERWRITE name TOKENIZERS .. FILTERS ..` | Tokenizers `Blank`, `Class`, `Camel`, `Punct`; filters `Lowercase`, `Uppercase`, `Ascii`, `Snowball("english")`, `EdgeNgram(a, b)`, `Ngram(a, b)`. `schema` writes the analyzers after the functions and before the tables |
| `t.text_index(\|r\| r.body, analyzer)`, `Def.text_index` | `DEFINE INDEX t_body_fulltext ON t FIELDS body FULLTEXT ANALYZER a BM25 HIGHLIGHTS` | The field is a `Str`, at any depth of objects. `schema` refuses an analyzer it is not given, and an index of another table |
| `t.vector_index(\|r\| r.embedding, { dimension, distance })`, `Def.vector_index` | `DEFINE INDEX t_embedding_hnsw ON t FIELDS embedding HNSW DIMENSION n DIST COSINE TYPE F64` | A `List(F64)` is `TYPE F64`, a `List(F32)` `TYPE F32`, any other type a `BadSchema`. `distance` is `Cosine`, `Euclidean`, `Manhattan` or `Chebyshev`. A write of another dimension is refused by the server: "Incorrect vector dimension (2)" (`vector_dimension`) |
| `q.search(index, terms)` | `WHERE body @1@ 'terms'`, `AND`ed with the other filters | The row becomes `(row, hit)`. The library numbers the search: the index, the query and the hit are of one row, so a query has one search and no `nearest` (a type error), and no clause writes the number |
| `hit.score()`, `hit.highlight(a, b)`, `hit.offsets()` | `search::score(1)`, `search::highlight(a, b, 1)`, `search::offsets(1)['0'].map(\|$o\| { end: $o.e, start: $o.s })` | Intrinsics: SurrealDB computes them, and they have no Roc body. `Hit` and `Near` are backed by `[]`, so the program has no value of them. `ORDER BY` takes a column, so the score is selected as one |
| `q.nearest(index, probe, Approx({ k, ef }))`, `Exact(k)` | `WHERE embedding <\|k,ef\|> [..]` through the HNSW graph, `<\|k,COSINE\|>` over every row | The row becomes `(row, near)`, and `near.distance()` is `vector::distance::knn()`. A probe of another dimension than the index's is an `Unsupported` when the statement is built. `<\|k\|>` alone is refused by 3.3.4 ("no longer supported"), and `MTREE` is a parse error |
| A live query of a search | Refused | A search reads its index, and a notice is of one written row; watch the rows with a `filter` |

The Roc meanings:

| Part | Roc meaning | Verified on 3.3.4 |
| --- | --- | --- |
| The rows of `search` | `Analyzer.matches(text, terms)`: the terms of the query, by the analyzer, are not empty, and the text has each of them. `Analyzer.tokens` is the analyzer for the tokenizers `Blank` and `Class` and the filters `Lowercase` and `Uppercase`, over ASCII text. Any other analyzer, or a text outside ASCII, stops the program: only the database computes it | `Class` cuts at a change of letter, digit and anything else, and keeps the punctuation as terms: `a!+b` is `a`, `!+`, `b`. A query of two terms keeps the rows that have both. `''` keeps none (`search_limping`, `search_two_terms`, `search_no_term`, `search_after_filter`) |
| The score, the highlights, the offsets, the distance of a KNN | None: they are intrinsics. The block names the column in `-- intrinsic:`, the literal leaves it out, or the order or the text is written by hand | BM25 gives 0 to a term that half the rows or more have. The KNN distance through the graph is computed on the index's copy, and `<\|k,COSINE\|>` differs from `1 - vector::similarity::cosine` in the last bits. By `EUCLIDEAN` over `F64` it is the Roc distance to the bit (`client.roc`, `close_notes`) |
| The rows of `nearest` | The rows that the other filters keep, sorted by their `Vector` distance from the probe, the first `k` | The `k` are taken after the other filters (`nearest_after_filter`). On a few rows `Approx` gives the exact rows |
| `Vector` | A real implementation | Each sum runs from the first element, as the server's does, so the six functions agree to the bit (`vector_measures`, `vector_filter`) |

| Roc | Type | SurrealQL | Kind |
| --- | --- | --- | --- |
| `Vector.similarity_cosine` | `List(F64), List(F64) -> F64` | `vector::similarity::cosine(a, b)` | mirror: `NaN` for a zero vector |
| `Vector.distance_euclidean` | `List(F64), List(F64) -> F64` | `vector::distance::euclidean(a, b)` | mirror |
| `Vector.distance_manhattan` | `List(F64), List(F64) -> F64` | `vector::distance::manhattan(a, b)` | mirror |
| `Vector.distance_chebyshev` | `List(F64), List(F64) -> F64` | `vector::distance::chebyshev(a, b)` | mirror |
| `Vector.dot` | `List(F64), List(F64) -> F64` | `vector::dot(a, b)` | mirror |
| `Vector.magnitude` | `List(F64) -> F64` | `vector::magnitude(a)` | mirror |

Two vectors of different dimensions are an error in SurrealDB, and the
Roc meaning stops the program. The dot product of two empty vectors is
the integer `0` in SurrealDB.

`client.roc` defines `case_note` with an analyzer and both indexes, and
reads a search with its scores and highlights and the nearest notes as
typed rows, on a WebSocket and over HTTP (`searches!`), then removes the
table. `PreparedTest.roc` reads the recorded replies.

### Errors

Every call has one error type, `Surreal.Error` (`Ql.Error`):

| Tag | When | What it holds |
| --- | --- | --- |
| `Unsupported(why)` | The program builds a statement that has no SurrealQL form: a translation refusal | The reason. A refusal in a clause names the clause: `in `filter`: `Str.split_first` has no SurrealQL form`, `in the patch of `update`: ..` |
| `BadSchema(why)` | `Surreal.schema` refuses a definition | The reason |
| `Transport(why)` | The platform could not post over HTTP | The platform's text. The session's connection is gone |
| `WebSocket(why)` | The WebSocket adapter failed | `Closed(closure)`: the connection ended, with roc-websocket's `Ws.Closure` (code, reason, clean, by whom); `Closing`; or `Adapter(text)`: a tag of the adapter, such as `Tcp(TimedOut)` or `Refused(..)`, as `Str.inspect` writes it. The session's connection is gone |
| `Wire(why)` | A message is not what the protocol says | The reason |
| `Decode({ path, message })` | A value of the server does not fit the Roc type it is read as | The path to the value, `result[0].temp_c`, or empty when the reader names none |
| `Server(error)` | The server refused the request or a statement | A `Surreal.ServerError`, below |
| `Aborted({ at, error })` | A statement failed a transaction of `Transaction.commit` | The part that failed it, and its `ServerError` (see "Transactions") |

`run!` and `await!` give `{ session, result : Try(out, Surreal.Error) }`,
the same on both transports: the session always comes back, and `result`
has the rows or any of the errors. A `Transport` or `WebSocket` error ends
the session, and the app opens a new one.

SurrealDB 3.3.4 sends each error with a `kind`, also over CBOR and over
HTTP (verified: a statement's result is `{ status: 'ERR', kind, details,
result: message }`, a request's error `{ code, kind, details, message }`).
`Surreal.server_error` reads the kind and its `details`,
and the message of an `Internal` error when it has a form that the server
writes for a constraint (`Schema.violation`, `src/Schema.roc:950`). Each tag keeps
the message:

| Server error | Tag |
| --- | --- |
| `AlreadyExists` | `Exists({ what, name })`: `what` is the details' kind (`Record`), `name` the record id |
| `NotFound` | `NotFound({ what, name })`: a table, a record, a method |
| `NotAllowed`, or HTTP 401 or 403 | `Denied` |
| A refused login: `NotFound` of a `signin`, `Query` of a `signup` (see "Record users and permissions") | `Denied` |
| `Validation`, a parse error | `Parse` |
| `Validation`, other | `Invalid`, such as a protected variable |
| `Query` with `TransactionConflict` | `Conflict`: the transaction can be retried |
| `Query` with `TimedOut` | `Timeout` |
| `Thrown` | `Thrown({ text })`, the text of the `THROW` |
| `Internal`: ``Database index `i` already contains v, with record `r` `` | `Unique({ table, index, fields, value, record })` for an index of a `Def.unique` the session knows (`Session.knowing(defs)`), else `Index({ index, value, record })` |
| `Internal`: ``Found v for field `f`, with record `r`, but field must conform to: c`` | `Assert({ table, field, record, value, condition })` |
| `Internal`: ``Couldn't coerce value for field `f` of `r`: Expected `t` but found `v` `` | `Type({ table, field, record, expected, found })` |
| `Internal`: an event `t_check_<name>` throws `t: name` | `Check({ table, name })`, a `Def.check` that reads several fields. A check of one field is its `ASSERT`, so it is `Assert` |
| `Internal`: ``Cannot delete `r` as it is referenced by `b` ..``, or the delete event of a nested link throws `r is referenced by t.path` | `Referenced({ record, by })` |
| Any other | `Other({ kind, message })` |

The library parses only what it wrote or what the server writes the same
way each time: the names of indexes and events are its own, and a
`Def.check` throws `table: name`. The message of a constraint has no
fields of an index, so `Unique` needs the schema: `Session.knowing` keeps
the index of each `Def.unique` with its paths (`Schema.unique_indexes`).
An app matches on the tag, as Ecto's `unique_constraint` does:

```roc
match session.run!(bins.create(bin)).result {
	Ok(rows) => ..
	Err(Server(Unique({ table: "bin", fields: ["label"], .. }))) => "the label is taken"
	Err(e) => Str.inspect(e)
}
```

In a transaction that fails, each statement that did not run has the error
`Query` with `NotExecuted`, before and after the one that failed it. The
error of the reply is the first other one, so a `BEGIN; ..; COMMIT` gives
the `Assert` of its bad row, not `NotExecuted`, as `Aborted` with its
place for a transaction of `Transaction.commit`. `ErrorTest.roc` reads a
reply of each kind, which `check.py --record` saves in `fixtures/errors/`
from a database with the schema `fixtures/errors/schema.surql`, the one
that `Surreal.schema` writes for the tables of the test.

A translation refusal is not a compile error: `Code.refuse_at` needs the
index of a node, and `Code.Tree`, which the translator walks, has none,
and it crashes when the translator runs at program run time (see Design
limits). So the message names where it is: the clause, as `in `select`:
..`, `in the condition of `delete`: ..`.

### Supported builtins

`s` is a string, `n` and `m` are integers, `d` is a `Dec`, `list` is a list field.

| Roc builtin | SurrealQL | Note |
| --- | --- | --- |
| `a + b`, `"${a}${b}"`, `s.is_empty()`, `a == b`, `a < b` | `a + b`, `s = ''`, `a = b`, `a < b` | |
| `s.starts_with(x)`, `ends_with`, `contains` | `string::starts_with(s, x)` and the same for the others | |
| `s.with_ascii_uppercased()`, `with_ascii_lowercased` | `array::join(string::split(s, '').map(\|$ch\| IF $ch >= 'a' AND $ch <= 'z' THEN string::uppercase($ch) ELSE $ch END), '')` | `string::uppercase` also changes `ß` and `é`, and Roc does not |
| `s.caseless_ascii_equals(x)` | Both sides lowercased as above, then `=` | |
| `s.trim()`, `trim_start`, `trim_end` | `string::replace(s, /^[\s\u{200E}\u{200F}]+\|[\s\u{200E}\u{200F}]+$/, '')` | `string::trim` keeps U+200E and U+200F |
| `s.repeat(n)`, `s.with_prefix(p)`, `Str.join_with(list, x)` | `string::repeat(s, n)`, `p + s`, `array::join(list, x)` | |
| `s.drop_prefix(p)`, `drop_suffix` | `IF string::starts_with(s, p) THEN string::slice(s, string::len(p)) ELSE s END` | |
| `s.split_on(x)` | `string::split(s, x)` | An empty `x` gives `[s]` in Roc. A literal `""` is read at translation. Another `x` gets an `IF x = ''` guard |
| `s.replace_each(a, b)` | `string::replace(s, a, b)` | An empty `a` gives `s` in Roc. Same literal rule and guard |
| `s.count_utf8_bytes()` | `bytes::len(<bytes>s)` | `string::len` counts characters |
| `s.to_str()`, `n.to_str()` | `s`, `<string>n` | |
| `n.max(m)`, `n.min(m)` (also `Dec`) | `math::max([n, m])`, `math::min([n, m])` | |
| `n.pow(m)` | `math::pow(n, m)` | |
| `n.mod_by(m)` | `(((n % m) + m) % m)` | Floored modulus, as Roc |
| `n.is_multiple_of(m)` | `n % m = 0` | A divisor that is not a non-zero literal gets `IF m = 0 THEN n = 0 ELSE ..` |
| `n.is_zero()`, `is_negative`, `is_positive` (also `Dec`) | `n = 0`, `n < 0`, `n > 0` | |
| `n.is_even()`, `n.is_odd()` | `n % 2 = 0`, `n % 2 != 0` | |
| `d.round()` | `IF d >= 0 THEN math::floor(d + 0.5dec) ELSE math::ceil(d - 0.5dec) END` | `math::round` rounds a tie to even, and Roc rounds it away from zero |
| `d.floor()`, `d.ceiling()`, `d.trunc()` | `math::floor(d)`, `math::ceil(d)`, `IF d >= 0 THEN math::floor(d) ELSE math::ceil(d) END` | No `math::trunc` in SurrealDB |
| `n.to_i64()`, `to_i128`, `to_u32` and other conversions without a check | `n` | An integer is an `int` already. Integer owners only |
| `n.to_u8_try()` and the other `to_<int>_try` | `Maybe(IF n >= 0 AND n <= 255 THEN n ELSE NONE END)` | |
| `d.to_i64_try()` | `Maybe(IF d > -9223372036854775809dec AND d < 9223372036854775808dec THEN <int>(trunc) ELSE NONE END)` | Roc cuts the fraction, then tests the range |
| `n.to_dec()`, `n.to_f64()` | `<decimal>n`, `<float>n` | |
| `list.len()`, `list.is_empty()`, `list.contains(x)` | `list.len()`, `list.len() = 0`, `list CONTAINS x` | |
| `list.any(f)`, `all`, `map`, `keep_if`, `drop_if`, `count_if`, `find_first` | `list.any(\|$v1\| ..)`, `.all`, `.map`, `.filter`, `.find` | |
| `list.map(f).sum()` | `math::sum(list.map(\|$v1\| ..))` | |
| `list.first()`, `last`, `get(i)`, `min`, `max` | `array::first(list)`, `array::last`, `array::at(list, i)`, `array::min`, `array::max` | A `Try` is a `Maybe`: `NONE` stands for `Err`. `math::max([])` is `NULL`, so it is not used |
| `list.take_first(n)`, `drop_first(n)`, `rev()`, `join()` | `array::slice(list, 0, n)`, `array::slice(list, n)`, `array::reverse`, `array::flatten` | |
| `list.sort()`, `sort_reversed()` | `array::sort::asc(list)`, `array::sort::desc(list)` | Only for whole numbers and `Dec`. Their `order_relative_to` is the order of SurrealDB, and the evidence of the call says so. Roc has no default order for `Str` or a float, and a type with an order of its own is refused: the translator reads the evidence and does not guess |
| `list.concat(l)`, `append(x)`, `prepend(x)`, `list == l` | `array::concat`, `array::append`, `array::prepend`, `list = l` | |
| `t.is_ok()`, `t.is_err()`, `t.ok_or(x)`, `t ?? x` | `t IS NOT NONE`, `t IS NONE`, `t ?? x` | `t` comes from an optional field or a `Try` row above |
| `t.map_ok(f)` | `(IF t IS NONE THEN NONE ELSE f(t) END)` | `f` may not return a `Try`: NONE would stand for both errors (`Translate.map_ok`) |
| `Ok(x)`, `Err(_)` of a `Try` | `x`, `NONE` | The value must have the type `Try`. Without an annotation, `Ok` and `Err` are tags of a union (`Translate.try_value`) |
| `link.get()` | A traversal of the stored record id | The whole row is `link.{ id: record::id(id), .. }`, and NONE for a NONE link |
| `link.id`, `link.id()` | The id itself. The field and the method are the same (`Translate.link_field`) | |
| `link.fetched` | Refused: `fetched` is the row that the program holds, and the database has no such field | Write `link.get().field` for a field of the row, or `link.id` |
| `id.key()` | `record::id(id)` | |
| `v.id.series()`, `v.id.time()` on a `TimeKey` | `record::id(id)[0]`, `record::id(id)[1]` | See "Time series" |
| `a < b` on a `Datetime` | `a < b`, with the literal written as `d'..'` | |
| `a == b`, `a != b` on a `Datetime` | `a = b`, `a != b`, with the literal written as `d'..'` | Compared as datetimes, never as text: SurrealDB prints a fraction with 3, 6 or 9 digits (`.500Z`), and Roc without trailing zeros (`.5Z`). The text of a datetime is compared only with a datetime or a literal (`Translate.moments`) |

A `Try` builtin maps only when the error has one tag and SurrealQL gives
`NONE`, not `NULL`, for it. A `match` writes the `Ok` expression again in each arm.

### Refused builtins

| Roc builtin | Reason |
| --- | --- |
| `from_str` on `I64`, `Dec`, `F64` | Roc accepts `1_0`, `0x1f` and `1e3`. `<int>` raises an error and does not give `NONE` |
| `to_i64`, `to_i64_wrap` on `Dec` or `F64` | Roc cuts the fraction. `<int>` raises an error. Use `to_i64_try` |
| `to_str` on `Dec`, `F32`, `F64` | Roc prints `3.0`, SurrealDB prints `3` or `3f` |
| `pow` on `Dec`, and `max`, `min`, `pow`, sign tests on `F32`, `F64` | Digits, NaN and -0.0 differ |
| `//` on `Dec` | Roc cuts the fraction. Divide with `/` |
| `replace_first`, `replace_last` | `string::replace` replaces every match |
| `Str.len` | The Roc type gives only an error |
| `split_first`, `split_last`, `to_utf8`, `from_utf8`, `drop_first_bytes` | A record result in a `Try`, or a byte list |
| `div_floor_by`, `div_ceil_by`, `abs_diff`, shifts, `bitwise_*`, `to_<int>_wrap`, narrowing `to_<int>_wrap`, `*_saturated` | No SurrealQL function with the same meaning |
| `div_try` | Two error tags, and a `Maybe` cannot tell them apart |
| `sort` and `sort_reversed` on a type with an order of its own, `sort_by`, `sort_with`, `fold`, `map_try`, `split_*`, `chunks_of` | No SurrealQL form |

A refused builtin is a translation error with the reason, never a wrong query.

### Package functions

SurrealDB has functions that Roc has no builtin for. They are functions of one
nominal for each namespace, inside `Surreal`: `Text`, `Hash`, `Array`, `Time`, `Math`,
`Rand` and `Geo`. A call is written `Surreal.Text.is_email(s)`. The nominal has
no value, so it is not a method of `Str`. The name is `Text` and not `Str`,
because a nominal named `Str` shadows the builtin in the whole module. In the
tables below `Datetime` is `Surreal.Datetime`.

The translator maps each function to one SurrealQL function (its form in
`Surreal.library`, by its id). A function is one of two kinds, and no third:

| Kind | Body | Where a call runs |
| --- | --- | --- |
| Mirror | A real Roc implementation that gives the SurrealDB result. A live block proves it equal. It is in the cut (`Surreal.code_primitives`), so the reifier does not read its body | In a clause (as SurrealQL) and in Roc: an `expect`, seed data and the `-- roc:` reference |
| Intrinsic | None: a type and no body, `is_email : Str -> Bool`. SurrealDB computes it. It is a `Prim` in a description, as a builtin is, so it is not in the cut (listing it there is the compile error `already a primitive`); its forms are `intrinsic_forms` | In a clause only. A call in code that runs (an entry point, a top-level constant, an `expect`) is the compile error `exists only in reified code`, with the chain of calls |

A stand-in that gives a plausible value is not allowed: it would give a wrong
answer without a message. An intrinsic has no Roc result, so its
live block has the expected rows written by hand next to the seed rows
(`builtins.roc`), and a column that reads one may be left out of a `-- roc:`
literal (`-- intrinsic:`). `roc check --intrinsics src/main.roc` lists the
intrinsics. The cut is one list, `Surreal.code_primitives`, and every nominal that
takes a `Code` parameter names it as its `code_primitives`.

#### `Text`

`is_alpha`, `is_alphanum` and `is_numeric` are Unicode: `abé` is alphabetic and
the Arabic digits `١٢٣` are numeric. An empty text is false for every `is_*` check.
`matches` takes Rust regex syntax, and a pattern that is not anchored finds a
part of the text. `distance_normalized_levenshtein` is a similarity: 1 for equal
texts. The distances count characters, not bytes.

| Roc | Type | SurrealQL | Kind | Live block |
| --- | --- | --- | --- | --- |
| `Text.is_email` | `Str -> Bool` | `string::is_email(a)` | intrinsic | text_checks |
| `Text.is_url` | `Str -> Bool` | `string::is_url(a)` | intrinsic | text_checks |
| `Text.is_domain` | `Str -> Bool` | `string::is_domain(a)` | intrinsic | text_checks |
| `Text.is_ip` | `Str -> Bool` | `string::is_ip(a)` | intrinsic | text_addresses |
| `Text.is_ipv4` | `Str -> Bool` | `string::is_ipv4(a)` | intrinsic | text_addresses |
| `Text.is_ipv6` | `Str -> Bool` | `string::is_ipv6(a)` | intrinsic | text_addresses |
| `Text.is_uuid` | `Str -> Bool` | `string::is_uuid(a)` | intrinsic | text_identifiers |
| `Text.is_ulid` | `Str -> Bool` | `string::is_ulid(a)` | intrinsic | text_identifiers |
| `Text.is_semver` | `Str -> Bool` | `string::is_semver(a)` | intrinsic | text_identifiers |
| `Text.is_alpha` | `Str -> Bool` | `string::is_alpha(a)` | intrinsic | text_unicode |
| `Text.is_alphanum` | `Str -> Bool` | `string::is_alphanum(a)` | intrinsic | text_unicode |
| `Text.is_numeric` | `Str -> Bool` | `string::is_numeric(a)` | intrinsic | text_unicode |
| `Text.is_latitude` | `Str -> Bool` | `string::is_latitude(a)` | intrinsic | text_places |
| `Text.is_longitude` | `Str -> Bool` | `string::is_longitude(a)` | intrinsic | text_places |
| `Text.is_datetime` | `Str, Str -> Bool` | `string::is_datetime(a, b)` | intrinsic | text_dates |
| `Text.matches` | `Str, Str -> Bool` | `string::matches(a, b)` | intrinsic | text_pattern |
| `Text.similarity_jaro` | `Str, Str -> F64` | `string::similarity::jaro(a, b)` | intrinsic | text_similarity |
| `Text.similarity_jaro_winkler` | `Str, Str -> F64` | `string::similarity::jaro_winkler(a, b)` | intrinsic | text_similarity |
| `Text.distance_levenshtein` | `Str, Str -> I64` | `string::distance::levenshtein(a, b)` | intrinsic | text_distance |
| `Text.distance_damerau_levenshtein` | `Str, Str -> I64` | `string::distance::damerau_levenshtein(a, b)` | intrinsic | text_distance |
| `Text.distance_normalized_levenshtein` | `Str, Str -> F64` | `string::distance::normalized_levenshtein(a, b)` | intrinsic | text_distance |
| `Text.is_ascii` | `Str -> Bool` | `string::is_ascii(a)` | mirror | text_unicode |
| `Text.is_hexadecimal` | `Str -> Bool` | `string::is_hexadecimal(a)` | mirror | text_unicode |

#### `Hash`

The hash of a text is lower-case hex. `argon2` is the hash of a password
for an access method (see "Record users and permissions"): it makes a new
salt on every call, so it follows the rule of `Rand`. The other password
hashes are not included (see the dropped functions below).

| Roc | Type | SurrealQL | Kind | Live block |
| --- | --- | --- | --- | --- |
| `Hash.sha256` | `Str -> Str` | `crypto::sha256(a)` | mirror | hashes |
| `Hash.blake3` | `Str -> Str` | `crypto::blake3(a)` | mirror | hashes |
| `Hash.md5` | `Str -> Str` | `crypto::md5(a)` | intrinsic | hashes_old |
| `Hash.sha1` | `Str -> Str` | `crypto::sha1(a)` | intrinsic | hashes_old |
| `Hash.sha512` | `Str -> Str` | `crypto::sha512(a)` | intrinsic | hashes_old |
| `Hash.argon2` | `Str -> Str` | `crypto::argon2::generate(a)` | intrinsic, a new value on every call | `client.roc`: signup_ann |
| `Hash.argon2_matches` | `Str, Str -> Bool` | `crypto::argon2::compare(a, b)` | intrinsic | `client.roc`: signin_ann, wrong_password |

#### `Array`

The functions take lists of values that have `is_eq`. They keep the first place
of a value, as SurrealDB does: `distinct([3, 1, 3, 2, 1])` is `[3, 1, 2]`.
`complement(a, b)` is the values of `a` that `b` has not. It is not
`array::difference`, which is a symmetric difference.

| Roc | Type | SurrealQL | Kind | Live block |
| --- | --- | --- | --- | --- |
| `Array.distinct` | `List(a) -> List(a)` | `array::distinct(a)` | mirror | arrays |
| `Array.union` | `List(a), List(a) -> List(a)` | `array::union(a, b)` | mirror | arrays |
| `Array.intersect` | `List(a), List(a) -> List(a)` | `array::intersect(a, b)` | mirror | arrays |
| `Array.complement` | `List(a), List(a) -> List(a)` | `array::complement(a, b)` | mirror | arrays |

#### `Time` and `Duration`

A `Duration` is `Duration := { nanos : U64 }`, a `U64` because SurrealDB refuses
a negative duration. The constructors are plain Roc, not in the cut. A call is
inlined, and one rule in `Translate.wrap` writes `duration::from_nanos(N)`:

| Roc | Type | Nanoseconds |
| --- | --- | --- |
| `Time.nanos`, `micros`, `millis`, `secs`, `mins`, `hours`, `days`, `weeks` | `U64 -> Duration` | 1, 1000, 1000000, 10^9, 6 * 10^10, 3.6 * 10^12, 8.64 * 10^13, 6.048 * 10^14 |

A `Duration` is not a column type and not a captured value (both are refused
with a message). Every part of a time is read in UTC, as the library keeps every
`Datetime`. `Time.unix` counts seconds, `unix_millis` milliseconds, `unix_micros`
microseconds and `nano` nanoseconds since 1970, each rounded down. The two
extractors are `unix_millis` and `unix_micros` because `Time.millis` and
`Time.micros` already make a `Duration`. `wday` is Monday 1 to Sunday 7, `week`
is the ISO week, and `yday` counts from 1.

`floor`, `ceil` and `round` count spans from 1970-01-01T00:00:00Z, so a week
starts on a Thursday. The Roc body takes the nanoseconds since 1970 and the
span `d`:

| Function | Result for `t` nanoseconds and `r = t mod d` (floored) | A span of zero |
| --- | --- | --- |
| `floor` | `t - r` | `t` |
| `ceil` | `t` when `r = 0`, else `t - r + d` | `t` |
| `round` | `t - r + d` when `2r >= d`, else `t - r`: a half goes up, also before 1970 | `t` |

SurrealDB 3.3.4 refuses a time outside 1677-09-21T00:12:43.145224192Z to
2262-04-11T23:47:16.854775807Z (the nanoseconds of an `I64`) and a span above
`I64.highest` nanoseconds. The Roc body stops the program with a message there.
The block `time_floor_weeks` checks spans of 1 week, 7 hours, 13 seconds, 365
days, 3 nanoseconds, zero and `I64.highest` nanoseconds, ties, and times before
1970 and at both limits.

| Roc | Type | SurrealQL | Kind | Live block |
| --- | --- | --- | --- | --- |
| `Time.now` | `() -> Datetime` | `time::now()` | intrinsic | now_filter, now_future |
| `Time.floor` | `Datetime, Duration -> Datetime` | `time::floor(a, b)` | mirror | time_buckets, time_floor_weeks, daily |
| `Time.ceil` | `Datetime, Duration -> Datetime` | `time::ceil(a, b)` | mirror | time_buckets, time_floor_weeks |
| `Time.round` | `Datetime, Duration -> Datetime` | `time::round(a, b)` | mirror | time_buckets, time_floor_weeks |
| `Time.group` | `Datetime, [Year, Month, Day, Hour, Minute, Second] -> Datetime` | `time::group(t, 'month')` | intrinsic | time_group |
| `Time.plus` | `Datetime, Duration -> Datetime` | `t + d` | intrinsic | time_plus |
| `Time.minus` | `Datetime, Duration -> Datetime` | `t - d` | intrinsic | time_plus |
| `Time.wday` | `Datetime -> I64` | `time::wday(a)` | intrinsic | time_calendar |
| `Time.yday` | `Datetime -> I64` | `time::yday(a)` | intrinsic | time_calendar |
| `Time.week` | `Datetime -> I64` | `time::week(a)` | intrinsic | time_calendar |
| `Time.unix` | `Datetime -> I64` | `time::unix(a)` | intrinsic | time_epoch |
| `Time.unix_millis` | `Datetime -> I64` | `time::millis(a)` | intrinsic | time_epoch |
| `Time.unix_micros` | `Datetime -> I64` | `time::micros(a)` | intrinsic | time_epoch |
| `Time.nano` | `Datetime -> I64` | `time::nano(a)` | intrinsic | time_epoch |
| `Time.format` | `Datetime, Str -> Str` | `time::format(a, b)` | intrinsic | time_format |
| `Time.from_unix` | `I64 -> Datetime` | `time::from_unix(a)` | intrinsic | time_from_unix |
| `Time.year` | `Datetime -> I64` | `time::year(a)` | mirror | time_parts |
| `Time.month` | `Datetime -> I64` | `time::month(a)` | mirror | time_parts |
| `Time.day` | `Datetime -> I64` | `time::day(a)` | mirror | time_parts |
| `Time.hour` | `Datetime -> I64` | `time::hour(a)` | mirror | time_parts |
| `Time.minute` | `Datetime -> I64` | `time::minute(a)` | mirror | time_parts |
| `Time.second` | `Datetime -> I64` | `time::second(a)` | mirror | time_parts |

#### `Math`

The statistics take `List(F64)` and give `F64`. SurrealDB's result type depends
on the element type (an `int` array has a `float` mean, a `decimal` array has a
`decimal` one), and a Roc signature cannot say that. Convert an `I64` or `Dec`
field with `to_f64()`, which the translator writes as `<float>`. Over a group's
rows the same call is an aggregate: `Math.mean(rows.map(|v| v.fee.to_f64()))` is
`math::mean(<float>fee)`. `percentile` is refused over a group, because
SurrealDB gives `NULL` there. The mean of a list with no value is not a number.
`stddev` and `variance` are the sample ones.

| Roc | Type | SurrealQL | Kind | Live block |
| --- | --- | --- | --- | --- |
| `Math.mean` | `List(F64) -> F64` | `math::mean(list)` | mirror | stats_mean, group_shared_map |
| `Math.median` | `List(F64) -> F64` | `math::median(list)` | intrinsic | stats_spread, group_shared_map |
| `Math.stddev` | `List(F64) -> F64` | `math::stddev(list)` | intrinsic | stats_spread, group_shared_map |
| `Math.variance` | `List(F64) -> F64` | `math::variance(list)` | intrinsic | stats_spread, group_shared_map |
| `Math.percentile` | `List(F64), F64 -> F64` | `math::percentile(list, p)` | intrinsic | stats_spread |

#### `Rand` and the effect rule

Each `Rand` function gives a new value on every call, and `Time.now` is not the
same twice in one statement. One rule says where each may be used:

| Function | Query filter, projection, order, group key | `check`, `assert` | `computed`, `default_by`, update `SET` |
| --- | --- | --- | --- |
| `Time.now` | allowed | allowed | allowed |
| `Rand.*` | refused | refused | allowed |

A `rand::` call in a `WHERE` or a `SELECT` makes one query give other rows each
time, and in a `check` or `assert` it makes a write pass or fail by chance. In a
computed field, a default and an `UPDATE .. SET` a new value is the aim. The
caller states which case it is: `Translate.evaluate` sets `Env.random` to false,
and `Translate.row_value` (`src/Translate.roc:260`) sets it true. `Schema.computed`,
`Schema.default_by` (`src/Schema.roc:263`) call `row_value`, and `Translate.assignments`
and `Translate.patch_assignments` set it true for each `SET` item.
`Def.default_by` is the `DEFAULT <expr>` form of `default`:
`.default_by(|k| k.uid, |_| Surreal.Rand.ulid())`.

| Roc | Type | SurrealQL | Kind | Live block |
| --- | --- | --- | --- | --- |
| `Rand.uuid` | `() -> Str` | `<string>rand::uuid()` | intrinsic | rand_defaults |
| `Rand.ulid` | `() -> Str` | `rand::ulid()` | intrinsic | rand_defaults |
| `Rand.int` | `I64, I64 -> I64` | `rand::int(a, b)` | intrinsic | rand_defaults, rand_update |

| Case | Result |
| --- | --- |
| `Surreal.Rand.int(1, 6)` in a filter or a `check` | `Unsupported`: "`Surreal.Rand.int` gives a new value on every call: use it in a default, a computed field or an update" |
| `.default_by(\|k\| k.roll, \|_\| Surreal.Rand.int(1, 6))` | `DEFAULT rand::int(1, 6)` |
| `.computed(\|k\| k.tag, \|_\| Surreal.Rand.ulid())` | `VALUE rand::ulid()` |
| `keyeds.update(\|k\| .., \|k\| { ..k, roll: Surreal.Rand.int(9, 9) })` | `SET roll = rand::int(9, 9)` |

A `uuid` is its own type in SurrealDB and a `string` column refuses it, so the
translator writes the cast `<string>rand::uuid()`.

#### `Id.table`

| Roc | Type | SurrealQL | Kind | Live block |
| --- | --- | --- | --- | --- |
| `Id.table` | `Id(row) -> Str` | `record::tb(id)` | mirror | ids |

It is in the cut of the existing nominal `Id`, next to `Id.key`. It reads the
table of a link that can point at several tables.

#### Database functions

A database function is a Roc function that the database also holds, as
`fn::name`. `Surreal.DbFn(f)` holds the name and the Roc
function. Its `call1`, `call2` and `call3` are in the cut.

```roc
fever : Dec, I64 -> Bool
fever = |temp_c, pulse| temp_c > 39.0 or pulse > 120

fever_fn : Surreal.DbFn((Dec, I64 -> Bool))
fever_fn = Surreal.db_fn("fever", fever)

schema = Surreal.schema([Surreal.function(|_| fever_fn), kennel_def, vital_def])
query = Surreal.from(vitals).filter(|v| fever_fn.call2(v.temp_c, v.pulse))
```

| Roc | Type | SurrealQL | Kind |
| --- | --- | --- | --- |
| `Surreal.db_fn` | `Str, f -> DbFn(f)` | Not in a clause by itself | Plain Roc, not in the cut |
| `Surreal.function` | `Code(({} -> DbFn(f))) -> Defined` | `DEFINE FUNCTION OVERWRITE fn::name($a1: T1, ..) -> R { RETURN body };` | Schema entry |
| `DbFn.call1`, `call2`, `call3` | `DbFn((a -> r)), a -> r` and the same for 2 and 3 arguments | `fn::name(a, ..)` | Mirror: the body is `(d.run)(..)`. It exists only in reified code when the Roc function calls an intrinsic |

The reifier gives the call as a `Prim` whose first argument is the constant:
a `Wrap` of the record of a `Lit` name and a `Closure` of the body row. So the
name and the body are explicit data in the description.

| Rule | Detail |
| --- | --- |
| Parameter names | `$a1`, `$a2`, .. in parameter order. A reified row has no parameter names |
| Parameter and result types | The type of a field of the same Roc type (`Types.inline_type`), so a record, a union, a link and a datetime are written as in a field |
| Statement order | Every `DEFINE FUNCTION` comes first in the schema script (`src/Schema.roc:486`). A field or an event that calls a function then finds it |
| Called functions | `Surreal.function` also defines each database function that the body calls (`src/Translate.roc:277`). A function that two entries reach is written once. Two different bodies with one name are a `BadSchema` |
| Name | `[a-z_][a-z0-9_]*`, else `Unsupported`, at the call and at the definition |
| Not a constant | A name that is not a literal: `Unsupported("a database function is a top-level constant made with Surreal.db_fn")` |
| Captures | A function that captures values: `Unsupported`. A database function is a top-level function |
| `Rand` in the body | Refused, as in a filter. A function can run in a `WHERE` |
| Recursion | A call of the function's own row in its body is `fn::name(..)` (`Translate.op`). A recursive helper inside the body is refused, as in a clause |

| Case | Result |
| --- | --- |
| `sum_to = \|n\| if (n <= 0) 0 else n + sum_to(n - 1)` | `RETURN (IF $a1 > 0 THEN $a1 + fn::sum_to($a1 - 1) ELSE 0 END)` |
| `twice_sum = \|n\| sum_to_fn.call1(n) * 2 + sum_to_fn.call1(1)` | `fn::twice_sum` and `fn::sum_to`, each defined once |
| `settled : Payment, Dec -> Bool` with a union `Payment` | `$a1: { kind: "Card", last4: string } \| "Cash" \| { kind: "Invoice", contact: record<customer>, due: string }` |
| `Surreal.db_fn("Doubled", doubled)` in a clause | `Unsupported`: "`Doubled` is not a database function name; use `[a-z_][a-z0-9_]*`" |

#### Time series

A time series is a table whose `id` is a `Surreal.TimeKey(s)`:
the record id `table:[series, time]`. SurrealDB keeps the rows in key order, so
a range of one series is a range scan and not a filter over the table.

```roc
Vital : { id : Surreal.TimeKey(Surreal.Id(Kennel)), pulse : I64, temp_c : Dec, fevered : Bool }

day_of : Vital -> { kennel : Surreal.Id(Kennel), day : Surreal.Datetime }
day_of = |v| { kennel: v.id.series(), day: Surreal.Time.floor(v.id.time(), Surreal.Time.days(1)) }

reading = { id: Surreal.time_key(kennels.id("a"), at), pulse: 80, temp_c: 38.5, fevered: Bool.False }
Surreal.from(vitals).between(kennels.id("a"), day_start, day_end).select(vital_line)
Surreal.from(vitals).group_by(day_of).aggregate(day_line)
daily = Surreal.view("vital_daily")
daily.define_as(Surreal.from(vitals).group_by(day_of), day_line).done()
vitals.define().changefeed(Surreal.Time.days(7)).done()
```

| Roc | Type | SurrealQL | Kind |
| --- | --- | --- | --- |
| `Surreal.time_key` | `s, Datetime -> TimeKey(s)` | `[series, time]` in a write, `table:[series, time]` as a record id | Plain Roc, not in the cut |
| `TimeKey.series`, `TimeKey.time` | `TimeKey(s) -> s`, `TimeKey(s) -> Datetime` | `record::id(id)[0]`, `record::id(id)[1]` (`Translate.prim`) | Mirror |
| `TimeKey.within` | `TimeKey(s), s, Datetime, Datetime -> Bool` | Not in a clause. The Roc result of `between` | Plain Roc |
| `Query.between` | `Query(p, { id : TimeKey(s), ..others }), s, Datetime, Datetime -> Query(..)` | `FROM t:[s, from]..[s, to]`: `from` is in the range, `to` is not (`Query.between`) | Query |
| `Surreal.view`, `Table.define_as` | `Str -> Table(row)`, `Table(out), Grouped({}, row, k), Code((k, List(row) -> out)) -> Def(out)` | `DEFINE TABLE OVERWRITE name TYPE NORMAL AS SELECT .. GROUP BY ..` (`Table.define_as`) | Schema entry, with `define_as(..).done()` |
| `Def.changefeed` | `Def(row), Duration -> Def(row)` | `DEFINE TABLE .. SCHEMAFULL CHANGEFEED <n>ns` | Schema clause |

| Rule | Detail |
| --- | --- |
| The series | An `Id`, a `Str`, an integer, or a record of them. A key of several parts is a record series: `TimeKey({ site : Str, sensor : Str })` is `table:[{ sensor: .., site: .. }, time]`. The `TYPE` of `id` is `[<series type>, datetime]`, with the series typed as a field of the same Roc type (`Types.key_type`) |
| A `Link` in the series | Refused with `BadSchema`: a key has no delete policy. Use an `Id`. SurrealDB does not check that the `Id` of a key exists |
| The whole key | `v.id` is `record::id(id)`, the array `[series, time]`, which the Roc `TimeKey` also encodes to. `select(\|r\| r)` selects it as `record::id(id) AS id` |
| `between` | One per query. It writes the series and the times as literals. The rows are in the range of keys, so a filter after it reads only those rows |
| Group key | A key part that a result column shows is grouped by the column's alias: `GROUP BY day, kennel`. SurrealDB refuses `GROUP BY time::floor(..)`, and an alias wins over a field of the same name (verified). The column and the key part are one binding, so their texts are equal (`Surreal.group_columns`) |
| A view's query | A whole table, with no `between`: SurrealDB refuses a range in a view. `Grouped({}, ..)` takes no parameters, and has no order or limit |
| A view's columns | `Translate.view_columns` refuses `Math.median` and the `sum` of an integer column: SurrealDB refuses the first in a view, and keeps the second as a `float` (`Translate.sum`, `Translate.aggregate_arg`). `Math.percentile` is not an aggregate anywhere. `count`, `count(cond)`, `mean`, `stddev`, `variance` and the `sum` of a float work |
| A view table | Read-only: a write to it (`insert`, `create`, `upsert`, `update`, `delete`) is `Unsupported`, and a rule on it (`index`, `changefeed`, ..) is `BadSchema` (`src/Schema.roc:693`). It has no field definitions |
| Statement order | Functions, tables, views, then fields, indexes and events (`src/Schema.roc:486`). A view that calls a database function needs it defined first |
| A changefeed | The table line only, because a second `DEFINE TABLE OVERWRITE` resets the table to `SCHEMALESS` (verified). Two changefeeds on one table are a `BadSchema` |

| Case | Result |
| --- | --- |
| `vitals.create(row)` | `CREATE vital:[kennel:⟨a⟩, d'2026-03-01T08:00:00Z'] CONTENT { .. } RETURN AFTER` |
| `.between(kennel_a, day_start, day_end)` | `SELECT .. FROM vital:[kennel:⟨a⟩, d'2026-03-01T00:00:00Z']..[kennel:⟨a⟩, d'2026-03-02T00:00:00Z']` |
| `.group_by(day_of).aggregate(day_line)` | `SELECT time::floor(record::id(id)[1], duration::from_nanos(86400000000000)) AS day, count(fn::fever(temp_c, pulse)) AS fevers, record::id(id)[0] AS kennel, count() AS readings FROM vital GROUP BY day, kennel` |
| `daily.insert(rows)` | `Unsupported`: "`vital_daily` is a view, and a view is read-only" |
| `id : Surreal.TimeKey(Surreal.Link(Kennel))` | `BadSchema`: "the series of `id` holds a `Link`; a key holds an `Id`, because a key has no delete policy" |

`check.py` reads the result of a changefeed with `INFO FOR DB` only (block
`changefeed`). `SHOW CHANGES` gives versionstamps that Roc cannot predict, so
it has no Roc API.

#### Geometry

Eight nominals of `Surreal` hold a geometry: `Point` (`Surreal.Point`),
`Line`, `Polygon`, `MultiPoint`, `MultiLine`, `MultiPolygon`, `Collection` and
`Geometry` (`Surreal.Geometry`), the union of the other seven. Each one encodes
to its GeoJSON object through `Surreal.geojson` (`Surreal.geojson`) and
`Encode.Format.encode_geometry` (`src/Encode.roc:84`). SurrealDB 3.3.4 reads an
object of GeoJSON shape as a geometry in a write, a `LET` and a `RETURN`, so
`Ql.Value` has no geometry arm. As the one payload of a union arm, a geometry
is `{ kind, value }`, not spread: its type is not a record (see the union
payload rule).

```roc
Site : { id : Str, name : Str, location : Surreal.Point, area : Surreal.Polygon }

oslo = { id: "oslo", name: "Oslo", location: Surreal.point(10.75, 59.91), area: Surreal.Polygon.({ exterior: [..], holes: [] }) }
Surreal.from(sites).filter_by(|p, s| Surreal.Geo.inside(p.here.to_geometry(), s.area.to_geometry())).select_value(|s| s.id).prepare({ here: here })
Surreal.from(sites).select(|s| { id: s.id, lat: s.location.lat() })
```

| Roc | Type | SurrealQL | Kind |
| --- | --- | --- | --- |
| `Surreal.point` | `F64, F64 -> Point` | `<point> [lon, lat]` in a clause (`Translate.library`), the longitude first as in GeoJSON | Plain Roc, not in the cut |
| `Point.lon`, `Point.lat` | `Point -> F64` | `field.coordinates[0]`, `field.coordinates[1]` (`Translate.op`) | Plain Roc |
| `to_geometry` of each kind | `K -> Geometry` | The value itself: a `Geometry` of one payload is that payload (`Translate.library`) | Plain Roc |
| A field or a parameter of a geometry type | | `{ type: 'Point', coordinates: [10.75f, 59.91f] }`, `{ type: 'Polygon', coordinates: [[exterior..], [hole..]] }`, `{ type: 'GeometryCollection', geometries: [..] }` | Encoder |

| Roc | Type | SurrealQL | Kind | Live block |
| --- | --- | --- | --- | --- |
| `Geo.area` | `Geometry -> F64` | `geo::area(a)` | intrinsic | `geo_measures` |
| `Geo.bearing` | `Point, Point -> F64` | `geo::bearing(a, b)` | intrinsic | `geo_measures` |
| `Geo.centroid` | `Geometry -> Point` | `geo::centroid(a)` | intrinsic | `geo_measures` |
| `Geo.distance` | `Point, Point -> F64` | `geo::distance(a, b)` | intrinsic | `geo_measures`, `sites_near` |
| `Geo.hash_encode` | `Point, U8 -> Str` | `geo::hash::encode(a, n)`. SurrealDB refuses `n` outside 1 to 12 with an error | intrinsic | `geo_hash` |
| `Geo.hash_decode` | `Str -> Point` | `geo::hash::decode(a)` | intrinsic | `geo_hash` |
| `Geo.is_valid` | `Geometry -> Bool` | `geo::is_valid(a)` | Mirror: every longitude is from -180 to 180 and every latitude from -90 to 90. A NaN is not | `geo_valid` |
| `Geo.contains` | `Geometry, Geometry -> Bool` | `a CONTAINS b` (`Translate.library`) | intrinsic | `geo_relations` |
| `Geo.inside` | `Geometry, Geometry -> Bool` | `a INSIDE b` | intrinsic | `geo_relations`, `sites_covering` |
| `Geo.outside` | `Geometry, Geometry -> Bool` | `a OUTSIDE b`: no point in common. A line that crosses the edge is not `OUTSIDE` (verified) | intrinsic | `geo_relations` |
| `Geo.intersects` | `Geometry, Geometry -> Bool` | `a INTERSECTS b` | intrinsic | `geo_relations` |

| Rule | Detail |
| --- | --- |
| Field type | `TYPE geometry<kind> ASSERT geo::is_valid($value)` (`src/Types.roc:99`). SurrealDB stores a point out of range, so the assert refuses it (`bad_point`) |
| A ring | SurrealDB closes a ring that is not closed. `geo_values` reads one back closed, and the `-- roc:` literal goes through the same server, so the two agree |
| A geometry in a clause | A point is the cast `<point> [lon, lat]`, which takes any number expressions. Another kind is `Unsupported`: "pass a geometry as a parameter with `filter_by` and `prepare`". A tuple takes only number literals, and `<geometry>` of an object fails in 3.3.4 |
| A captured geometry | Refused in `select_where` with the same advice (`Translate.captured`) |
| `geo_valid` | Each field asserts `geo::is_valid`, so the stored points are valid. The query doubles the coordinates of `at` to reach the range limits: `(180, 90)` is valid, `-180.0000002` and `-90.0000002` are not |

#### Dropped, renamed and left out

| Function | Decision | Reason |
| --- | --- | --- |
| `array::sort`, `array::sort::asc`, `array::sort::desc` | `List.sort` and `List.sort_reversed` (not `Array.sort`) | A `Prim` with the evidence of an integer or `Dec` order translates to `array::sort::asc` and `array::sort::desc`. Any other evidence is refused with the reason (verified on SurrealDB 3.3.4: `array::sort::desc([3, 1, 2])` is `[3, 2, 1]`) |
| `array::difference` | Replaced by `Array.complement` | SurrealDB's `array::difference` is a symmetric difference. `array::complement` is the values of the first list that the second has not, which is what the name `complement` says |
| `time::millis`, `time::micros` | Renamed `Time.unix_millis`, `Time.unix_micros` | `Time.millis` and `Time.micros` make a `Duration`. The prefix `unix_` matches `Time.unix` and `Time.from_unix` |
| `string::similarity::fuzzy`, `smithwaterman` | Left out | Both give 0 for `('martha', 'marhta')` on SurrealDB 3.3.4, so the meaning is not clear |
| `string::distance::hamming` | Left out | An error for texts of different length. A clause cannot guard it, because the length is in characters |
| `string::distance::osa_distance` | Left out | "Invalid function" in 3.3.4 |
| `crypto::bcrypt`, `scrypt`, `pbkdf2` | Left out | A random salt makes each call differ, and `argon2` is the one hash that the signup and the signin of an access method need |
| `Datetime - Datetime` | Left out | An error in SurrealDB when the result is negative. Subtract `Time.unix(a) - Time.unix(b)` |
| `time::timezone`, `is_leap_year`, `max`, `min` | Left out | Low use, or a Roc builtin and a test say the same |
| `vector::add`, `subtract`, `multiply`, `divide`, `scale`, `normalize`, `cross`, `project`, `angle`, `distance::hamming`, `distance::minkowski`, `similarity::jaccard`, `similarity::pearson` | Left out | Vector arithmetic is rare in a clause, and each is one row of `Vector` with a Mirror; the six of `Vector` are the measures a search needs (see "Full-text and vector search") |
| `search::analyze`, `search::linear`, `search::rrf` | Left out | A search is a step of a query (`Query.search`), and the Roc meaning of an analyzer is `Analyzer.tokens` |
| `math::mode`, `spread`, `product`, `top`, `bottom`, `midhinge`, `trimean`, `interquartile`, `nearestrank` | Left out | Rarely needed in a clause. They exist in 3.3.4 |
| `rand::string`, `bool`, `float`, `enum`, `time`, `guid` | Left out | Rare. The first three have the shape of `rand::int`, so one row of `functions` adds each |
| `geo::*`, `http::*`, `sleep`, `session::*`, `sequence::*`, `meta::*`, `value::*`, `object::*`, `parse::*`, `ml::*` | Left out | A point type, a side effect, a different kind of clause, or a different feature |
| `record::id`, `record::exists`, `type::is_*` | Not needed | `Id.key` and `Link.id` read the id, the schema asserts that every link exists, and the Roc type of a column fixes the type |

#### Time packages other than `Surreal`

A `Surreal.Datetime` is UTC text, `2026-03-04T05:06:07.5Z`, in the form that
SurrealDB prints (a fraction has no trailing zeros). A Roc time package has its
own instant type. Convert through the nanoseconds since 1970-01-01T00:00:00Z:

| Method | Type | Notes |
| --- | --- | --- |
| `Surreal.Datetime.to_unix_nanos` | `Datetime -> I128` | The same count as `time::nano`. `I128` holds every year. Mirror: it runs in Roc |
| `Surreal.Datetime.from_unix_nanos` | `I128 -> Try(Datetime, [BadDatetime])` | A year outside 0 to 9999 is refused. A negative count rounds down. Mirror |
| `Surreal.datetime` | `Str -> Try(Datetime, [BadDatetime])` | `YYYY-MM-DDTHH:MM:SS`, a fraction of up to 9 digits, and `Z`. Another offset is refused |

```roc
# `instant` is a value of another time package, and `nanos_of` and `of_nanos`
# are that package's own conversions to and from nanoseconds since 1970.
at = Surreal.Datetime.from_unix_nanos(nanos_of(instant))
back = of_nanos(Surreal.Datetime.to_unix_nanos(at))
```

`Surreal.Datetime.from_unix_nanos(1772600767123456789)` is
`Ok(2026-03-04T05:06:07.123456789Z)` (`TranslateTest.roc`).

The description is a normal form, so two spellings of one computation reach
the translator as one. A record that a body builds arrives with its fields in
name order, so `SELECT` and `SET` lists are in name order too.

The Roc type of a field decides its SurrealDB type (`Types.inline_type`):

| Roc | SurrealDB `TYPE` | Extra constraint |
| --- | --- | --- |
| `Str` | `string` | |
| `Bool` | `bool` | |
| `I64` | `int` | |
| `I8`, `I16`, `I32`, `U8`, `U16`, `U32` | `int` | `ASSERT $value >= lo AND $value <= hi`, the Roc range |
| `U64`, `I128`, `U128` | Refused with `BadSchema` | The type does not fit `int`, and it has no encoder |
| `F32`, `F64` | `float` | |
| `Dec` | `decimal` | |
| `Surreal.Datetime` | `datetime` | |
| `Surreal.Id(row)`, `Surreal.Link(row)` | `record<table>` | `record::exists($value)`, and a delete policy for a link |
| `Surreal.Point`, `Line`, `Polygon`, `MultiPoint`, `MultiLine`, `MultiPolygon`, `Collection` | `geometry<point>`, `<line>`, `<polygon>`, `<multipoint>`, `<multiline>`, `<multipolygon>`, `<collection>` | `geo::is_valid($value)`: SurrealDB stores a point out of range |
| `Surreal.Geometry` | `geometry` | `geo::is_valid($value)` |
| `id : Surreal.TimeKey(s)` | `[<type of s>, datetime]`, defined on `id` | None: a key has no delete policy, and a `Link` in `s` is refused |
| `{ a : A }` nested | `object`, then `DEFINE FIELD f.a` | |
| `f ?: T` | `option<T>` | |
| `List(T)` of a scalar | `array<T>` | |
| `List({ .. })` | `array<object>`, then `DEFINE FIELD f[*].a` | A key check, so an object has no other keys |
| `List(Link(row))` | `array<record<table>>` | `$value.all(\|$e1\| record::exists($e1))` |
| `[A, B]` | `"A" \| "B"` | |
| `[A, B({ x : X }), C(Y), D(Y, Z)]` | `"A" \| { kind: "B", x: X } \| { kind: "C", value: Y } \| { kind: "D", value: [Y, Z] }` | A link in an arm is checked with `IF $value.kind = 'B' THEN .. END` |
| A named type `T := ..` | The type of its backing | |
| `Try`, `Dict`, `Set`, tuples, functions | Refused with `BadSchema` that names the type | |

One rule for a union payload serves the schema, the encoder, the translator and
the reader of a session, so the four agree. The reader is roc-cbor 0.4.0 with the
option `unions: Internal({ tag: "kind", content: "value" })`:

| Arm | Written as | A `match` reads |
| --- | --- | --- |
| No payload | `'A'` | Nothing |
| One record payload | `{ kind: 'B', ..fields }` | `u.x` for a field `x` |
| One other payload | `{ kind: 'C', value: v }` | `u.value` |
| Several payloads | `{ kind: 'D', value: [.., ..] }` | `u.value[0]`, `u.value[1]` |

The type of the payload, not the shape of its value, decides "record". Each
of the four parts reads it from the type:

| Part | A record payload is | Where |
| --- | --- | --- |
| Schema | A `Record` after `Types.unwrap`, which reads through a nominal of the app | `Types.union_type` |
| Encoder | A payload that `encode_record` wrote, the item `Fields` | `src/Encode.roc:315` |
| Translator | The same test as the schema | `Translate.is_record` |
| Reader | A payload whose reader calls `parse_record_start` | roc-cbor 0.4.0 |

| Payload type | Encodes as | Arm |
| --- | --- | --- |
| `{ x : X }`, or `Shelf := { .. }` with a derived `encoder_for` and `parser_for` | An object | Spread |
| `Point` and the other geometry types | An object (GeoJSON) | `value` |
| `Link(r)`, `Id(r)` | A record id | `value` |
| `Datetime` | A datetime | `value` |
| `TimeKey(s)` | An array | `value` |
| `Dec` | A decimal | `value` |

`client.roc` writes and reads back an arm of each kind (`place_rows`), in a
clause (`place_literal`), as a parameter (`place_bound_*`) and from fields
of the row (`place_row_*`).

Every link at any depth must exist when a row is written, and has a policy for
the delete of its target. The default policy is `Reject`. The schema picks the
mechanism from the shape of the link (`src/Schema.roc:385`):

| Shape of the link | Existence | Reject, Cascade | Unset | Mechanism |
| --- | --- | --- | --- | --- |
| Root, required (`owner`) | `ASSERT record::exists($value)` | native `REFERENCE ON DELETE` | Refused: the field is required | Native |
| Root, optional (`referrer ?:`) | `ASSERT $value = NONE OR record::exists($value)` | native | Native `UNSET` | Native |
| Root, list (`allergies`) | `$value.all(\|$e1\| record::exists($e1))` | native | Native `UNSET`: the element goes | Native |
| In an object (`chip.implanted_by`) | `ASSERT record::exists($value)` on the path | Event on the target table: `THROW`, or `DELETE` of the holder | Event: sets `NONE`. The field must be optional | Generated event |
| In a list of objects (`vaccines[*].vet`, `items[*].medication`) | `ASSERT record::exists($value)` on the path | Event: `THROW`, or `DELETE` of the holder | Event: filters out the element | Generated event |
| In a union arm (`outcome` arm `Referred`) | `IF $value.kind = 'Referred' THEN record::exists($value.to) ELSE true END` | Event on the target table | Refused: an arm field cannot be unset | Generated event |

`Ignore` writes nothing for the delete. All 44 shape and policy cases were run
on SurrealDB 3.3.4. A native `REFERENCE` works only on a root field, which is
why the other shapes use events. The two mechanisms differ in a few places:

| Native `REFERENCE` | Generated event |
| --- | --- |
| Reverse lookup `<~visit` works | No reverse lookup. Query with `WHERE $id IN items.medication` |
| The behaviour belongs to the referencing field | The behaviour lives on the target table, in an event named `<table>_<path>_on_delete` |
| Error text: `Cannot delete .. as it is referenced by ..` | The `THROW` text: `.. is referenced by visit.items[*].medication` |
| Indexed | A scan per delete, so the schema adds `DEFINE INDEX .. _link` for each nested link path |

Rows are written one at a time and each link must exist, so seeds go in
dependency order. A cycle of required links is a `BadSchema` that names the
cycle (`src/Schema.roc:1046`).

Values cross into SurrealQL through the compiler's derived `encoder_for`,
pointed at `Encode.roc`. A row, a parameter record and a default use it. An
absent optional field is a key that is left out. `Link`, `Id` and `Datetime`
have hand-written encoders.

### Extending the translator

The translator knows the builtins and the functions of `Surreal`. A package
of another type, such as a temperature or a money type, is one it cannot
know, and `Surreal` cannot import. An app or a glue package tells it with a
`Surreal.Extension`: the SurrealQL of each function, keyed by the id that
the compiler gives the function (`Code.prim`), as [the language reference](https://github.com/Karakatiza666/roc/blob/reify/docs/langref/reifying.md#extending-a-translator)
has it under "Extending a Translator". `Temperature.roc` is an opaque type with no SurrealDB in
it, and `ExtensionTest.roc` extends the translator for it:

```roc
temperature_surreal : Surreal.Extension
temperature_surreal = Surreal.extension(
	{
		prims: [
			{ prim: Code.prim(Temperature.from_celsius), render: only },
			{ prim: Code.prim(Temperature.celsius), render: only },
			{ prim: Code.prim(Temperature.is_gt), render: binary(">") },
		],
	},
)

fever : Temperature -> Try(Surreal.Prepared(List(Reading)), Ql.Error)
fever = |limit| Surreal.bind_captured(Surreal.select_where_with(readings, [temperature_surreal], |r| Temperature.from_celsius(r.temp_c) > limit))
```

`fever(Temperature.from_celsius(38.5))` is
`LET $_1 = 38.5dec; SELECT record::id(id) AS id, patient, temp_c FROM reading WHERE (temp_c > $_1)`.

| Part | What it does |
| --- | --- |
| `render` | Takes the SurrealQL of each argument as an operand, and the evidence of the call, and gives the SurrealQL of the call or why it has none. An operator puts its own parentheses, as `binary` does |
| The id | `Temperature.is_gt` and `Dec.is_gt` have one name and two ids. A `>` on two temperatures is refused without the extension (`` `Temperature.is_gt` has no SurrealQL form ``), never read as the builtin `>`, and the extension leaves the builtin as it is. An operation the extension does not cover, such as `<`, is refused by name |
| A captured value | `select_where_with` takes a `Code.Binds(Code(row -> Bool), Encode.Bind)`. A captured value whose type holds an opaque type arrives as the bytes its own `encoder_for` wrote in `Encode.Bind` (`encoder_for : _` in `Temperature.roc`), and `Encode.bound` reads them back as the literal that `Encode.Format` gives the same value. A temperature is its `Dec`. A field path of a captured record, `ward.alarm`, is one input too |
| The order | `Surreal.library` comes first, then the extensions in the order given. A builtin is looked up before them all |

`Surreal`'s own functions are an extension too, `Surreal.library`. The
translator cannot import `Surreal`, which imports it, so the ids of the cut
and of the intrinsics cannot be named in `Translate.roc`. `Surreal` passes `Surreal.library` into
every call of the translator instead, and `select_where_with` adds the
caller's after it. One lookup by id (`Translate.form`) serves the builtins,
`Surreal` and the extensions.

A nominal type that a description gives as `Named` has no type id, so the
translator and the schema know `Surreal.Link`, `Surreal.Datetime`,
`Builtin.Try` and the rest by name. That is one function,
`Types.nominal`, and the limit is in "Design limits".

## Findings: what current Roc and reification cannot do ergonomically

Each finding below was reproduced with a `roc` built at commit `f0e659f0a7`. Each one has a minimal snippet. The proposal files named below (`roc-reify-structural-proposal.md`) are in the [compiler repo](https://github.com/Karakatiza666/roc).

| # | Finding | Effect on the library | Kind |
| --- | --- | --- | --- |
| 1 | Solved. A captured `Id(row)` was refused when `row` had an optional field | A captured `Id` binds whatever fields its row has, and so does a captured record with an optional field (D8). A captured `Link` still holds its fetched row | Reifier limit (compiler limit Y8) |
| 2 | Solved. A value built from a table, like `table.id("pen")`, did not reify inside a clause | A table holds no `Code` value now, so a clause reads it: `vets.id("ruth")`, `visits.rows()` | Reifier limit, avoided by the library (compiler limit Y4) |
| 3 | A record update `{ ..r, f: x }` has the type of `r`, so it cannot change the type of a field | A row of another field type is written in full | Language |
| 4 | `{ x }` with a single field parses as a block | Write `{ x: x }` | Language |
| 5 | `in` is a reserved word | Edge rows name their ends `from` and `to`. The translator writes `in` and `out` | Language |

### 1. A captured `Id` of a row with an optional field (solved)

```roc
Customer : { id : Str, zip ?: Str, tags : Set(Str) }
Order : { id : Str, customer : Surreal.Link(Customer) }

of_customer : Surreal.Id(Customer) -> Code.Bound(Try({ surql : Str, slots : List(Code.Ty) }, Surreal.Error))
of_customer = |who| Surreal.select_where(orders, |o| o.customer.id == who)
# before the change: cannot bind this captured value: a captured record with an optional field
```

An `Id(Customer)` held a phantom `List(Customer)`, so the slot type held the
optional `zip` though the value never held a customer. Now `Id(row) := {
table : Str, key : Str }`: `row` is a type parameter that no value holds,
and the type checker still keeps an `Id(Customer)` from an `Id(Product)`.
The `Code.Ty` of an `Id(Customer)` is `Named("Surreal.Id", [customer],
Record(..))`, so the translator reads the row type from the type arguments
(`Types.row_of`, `src/Types.roc:263`), and the slot holds only the table and the
key. The capture binds (`TranslateTest.roc`, the test of a captured `Id`).

A captured `Link(row)` still holds its fetched row, `fetched : [Fetched(row),
NotFetched]`, so a captured `Link` of a row with a field of an opaque type is
still refused, and `Translate.captured` refuses a captured `Link`. Capture
its `id()` instead. A structural optional field in a slot binds (structural
proposal D8): the `Code.Value` of a field that the record does not hold is
`Absent`, and `Translate.captured` leaves the field out of the object. See `owners_at` in `main.roc` and `at_places` in `TranslateTest.roc`.

### 2. A table-built constant in a clause (solved)

```roc
ruth_id = vets.id("ruth")     # read inside a clause, before the change:
# cannot reify this type: a reified value that is not a function
```

A table held the row type that its identity lambda reified,
`Surreal.table("vet", |v| v)`. A description cannot hold a `Code` value,
so a clause that read the table was refused, at the identity lambda (compiler
limit Y4 in `roc-reify-structural-proposal.md`). Now a table holds only its
name and its kind, `Surreal.table("vet")`, and the row type comes from
`define()`. A constructor of a table is a function of `Surreal`, so it
arrives in a clause as a call with the name as a literal, and the row type is
its result type. `vets.id("ruth")` is `vet:⟨ruth⟩` (`examples/main.roc:116`), and
`visits.rows()` is the rows of the table (see "Tables and read rows").

### 3. A record update keeps the type of its base

```roc
# ruth : Vet, where years : U8
old_vet : VetRow(I64)
old_vet = { ..ruth, id: "bad", years: 300 }
# type mismatch: it has the type Vet, but the annotation says VetRow(I64)
```

`{ ..base, f: v }` has the type of `base`. A row whose `years` is an `I64`, so
that the database can refuse 300, is another type. `main.roc` writes `old_vet`
in full (`examples/main.roc:655`).

### 4 and 5. Syntax

```roc
q = { x }          # a block that returns x, so: Nothing is named x in this scope
T : { in : Str }   # expected a field name: `in` is a keyword
```

## Design limits

A reason that starts with "Fix later" is a limit of a live query that a later change can remove.
A reason that starts with "By design" is a limit of a live query that stays.

| Limit | Why |
| --- | --- |
| A `match` whose arms return whole records is refused | A whole record has no single SurrealQL value. Return the fields |
| No unique constraint through an optional record | SurrealDB does not index a path through an optional object |
| A field of a union arm cannot be named `kind` | `kind` is the tag of the arm in SurrealQL |
| SurrealDB cannot index a union sub-path | An index needs a path of one type |
| `REFERENCE` works only on root fields | Links in objects, lists of objects and union arms use generated events |
| `MERGE` breaks unions | An `update` writes `SET` for each changed field. `merge_at` takes a record whole, and a union field in it is merged key by key, which keeps the keys of the old arm (verified): use `set_at` for it |
| A record payload of a union is built field by field in a clause: `Full({ a: s.crate.a, b: s.crate.b })`, not `Full(s.crate)` | The arm writes the fields of the record next to `kind`, and the clause has `s.crate` as one value. `Full(s.crate)` is refused |
| The fields of a `set` patch are checked when the statement is built, not by the compiler | Roc has no type for a record of some of the row's fields, so `set` takes any record. `Translate.patch_assignments` checks each field against the row: `{ nmae: "x" }` is `BadSchema("the row has no field \`nmae\` ..")`, and a field of another type is a `BadSchema` too. A number literal without a suffix is a `Dec`, so a patch writes `5.I64` for an `I64` field. `update` takes the whole row, so the compiler checks its fields |
| An update patch that branches around the whole row is refused | `\|o\| if c { ..o, f: x } else o` has one `SET` list only when each arm changes the same fields. Branch inside the field, `{ ..o, f: if c x else o.f }`. A `match` on an optional field of the row is the exception: it is the switch that `..o` makes |
| A record that leaves out an optional field needs its type | `\|o\| { ..o, address: { city: o.address.city } }` is a type mismatch in a lambda. Annotate the patch as a function, `Owner -> Owner` (`without_zip` in `TranslateTest.roc`) |
| `created_now` overwrites a value that a create gives | A seed cannot set it. A query must not select it for a `-- roc:` comparison |
| A condition on the key does not make an `UPDATE` or a `DELETE` read one record | SurrealDB 3.3.4 plans `UPDATE t SET .. WHERE id = t:⟨k⟩` and `DELETE t WHERE id = t:⟨k⟩` as `Iterate Table` (verified with `EXPLAIN`), and only a `SELECT` reads the record. Write by key with `update_at`, `set_at` and `delete_at` |
| `at`, `update_at`, `set_at` and `delete_at` take a text key | An `Id(row)` holds a text key. A row of a time series is read with `between` and deleted with `Delete(row)` |
| A captured run-time value works in `select_where` and `select_where_with` only | The other clauses take a parameter record, which types the values by name |
| A nominal type is known by its name | `Code.Ty.Named` has no type id, so `Types.nominal` compares names, and an app's or another package's nominal named `Surreal.Link` or `Builtin.Try` would be taken for that one. A call is known by its id, and an opaque type by its `Code.TypeId`, so only the nominals of `Surreal` and `Builtin` have this limit. A type id on `Named`, a change to the reifier, removes it |
| A captured `Id`, `Datetime` or geometry in `select_where_with` is a type error | Their encoders write rows (`Encode.Format`), and `Code.Binds` needs an encoder in `Encode.Bind` for every captured value. Capture them in `select_where`, which binds them without a format |
| An extension renders calls only | A field of an opaque type has no SurrealDB type, so a row cannot hold one (`BadSchema`). An extension gives the SurrealQL of the type's functions, and a captured value is what its encoder writes |
| `U64`, `I128` and `U128` are refused as field types | They do not fit `int`, and the derived encoder has no case for them. `len().to_i64_wrap()` makes a count an `I64` |
| The schema is the current type, with no migration history | `OVERWRITE` re-defines. A removed field stays in the database |
| Two tables with an equal row type are ambiguous as link targets | The link carries the row type, not the table. Make one row a nominal |
| `Link.get()` on a link that was not fetched crashes in Roc | In a clause it is a traversal. The program has only the rows it read |
| A whole read row that holds a `Linked` of itself is refused | By design. `OwnerRead := { .., referred_by ?: Linked(OwnerRead) }` agrees with its stored row, and a field read through it works. The whole row, `select(\|o\| o)`, has no finite fetch plan: each `Linked` of it fetches the row again, with no last hop. So it is an `Unsupported` (`Translate.whole_linked`). Select the fields, or write `Linked(Owner)`, a `Linked` of the stored row, whose own links are `Link` |
| A read row is not written | `Linked`, `Out` and `In` have no encoder, so a write of a read row is a type error. Write the stored row; `define_read` checks that the two agree |
| An `Out` or `In` field has the name of its edge table | The field name is the table. `define_read` checks that it is an edge table that starts (`Out`) or ends (`In`) at the table of the row |
| A live query takes the definitions of the tables | A link holds the row type, not the table, so `live(params, tables)` finds the table of each link in `tables`, as `Surreal.schema` does, and the table of a `Linked` of a read row by its `define_read`. A row type with no table there is a `BadSchema` |
| A live query does not watch an `Id` field | By design. A clause cannot read the row of an `Id`: it has no `.get()` |
| A live query does not watch the edges of a linked row: an `Out` or `In` field of a `Linked` | Fix later. The edge statement reads the node at the end of the edge, `$parent.in`, which is the row of the result only for an edge of the row. An edge of a linked row needs a `read` statement on the edge table with the test of the link to the end, `site = $parent.in` |
| A linked row that a `map` returns is read whole | A list that a `map` made has no place in the row, so the walk reads the result of the function whole (`Translate.reach_lambda`), also when a later clause reads one field of it: an update of any field of that row is a notice. A `match` or `if` whose arms return linked rows is read arm by arm, as a field read of each |
| One more edge table with `and_outgoing` and `and_incoming` | The row becomes a triple. For three or more edge tables, take a read row with an `Out` or `In` field for each |
| After an order, a limit, a start or a group, a read row is a copy | A linked row in it holds its key as `id`, not a record id, so a later clause that reads `row.owner.id` fails in SurrealDB (`record::id` of an object). Read the `id` before the order |
| A whole union or a list of lists that holds a `Linked` is refused | Its shape has no destructure. Select its fields |
| `rows()` reads a whole table in a clause | It is `(SELECT VALUE id FROM t)`, and each field read traverses a record. A filter over a large table is better as its own query. On each write to that table, a live query sends a notice for each row of the result's table |
| A query fragment that calls a method of its query needs an annotation | `whole = \|q\| q.select(\|r\| r)` with no annotation is a type error: the type of `q` is not known where the lambda is checked, so the lambda is a plain function and not a `Code`. Annotate it with open rows, as `Clinic.recent` and `Clinic.by_id` are. By design (Y1b in `roc-reify-structural-proposal.md`) |
| A `??` default in a record of a union arm is not in the schema | An arm has no field definition, so a write from outside the program that leaves the field out is refused by the field's `TYPE`, not filled (verified). A write from Roc always has the field |
| A `??` default that is not a literal is refused | The type does not carry its value (`DefaultComputed`), so the schema cannot give it to the database. Give a literal default, or remove the `??` and use `.default_by(..)` |
| A refusal is an `Err(Unsupported(..))` value, not a compile error at the source line | The message names the clause instead (`in `filter`: ..`, see "Errors"). `Code.refuse_at` takes the index of a node, and `Code.Tree`, which the translator walks, has none. `refuse_at` also crashes when the translator runs at program run time, and a query built in a function is translated then, at `prepare`, so the library could call it only from a separate entry point. A library copy of the tree builder that keeps indices would repeat the compiler's normal form logic. A compiler change, an index on each node of `Code.Tree`, makes it small. An `expect` cannot test a refusal that stops the compile, so it would be an extra entry point, such as `to_surql_or_stop` |
| `SELECT *` and `FETCH` are in `Surreal.Unchecked` only | `*` gives `id` as a record id and the fields that the row type does not have. `FETCH` names a column of the result, not a field of the row, so `Unchecked.fetch` takes the path as text. Its row, `Unchecked.Row`, has no fields in Roc (`Surreal.Unchecked`) |
| `order_by` takes one column of the result | SurrealDB orders by a field path only, and does not order by a path through a link or into an aliased column (verified). Select the value as a column and order by the column. Several keys are several calls |
| Each read of a field through a link is a traversal of its own | Two reads of one link are two traversals. A whole linked row is one |
| A script app does not read results | The Echo platform has no TCP, so `main.roc` and the other script apps print SurrealQL. An app on basic-cli reads typed results with `Session.run!` (`client.roc`) |
| The order of an edge list differs between Roc and SurrealDB | Compare as multisets, or sort in the clause |
| A datetime in Roc orders as its string | This is right for the normalised UTC strings that `Surreal.datetime` accepts |
| An intrinsic exists only in a clause | It has no Roc body, so a call in code that runs (an entry point, a top-level constant such as `right_now = Surreal.Time.now()`, an `expect`) is the compile error `exists only in reified code`, and so is a call of a function that reaches one. In a clause it is read as a call, whether it is written directly or in a named helper (`is_past = \|v\| v.at < Surreal.Time.now()`, then `.filter(is_past)`): each gives `time::now()`. An intrinsic used as a value in a clause (`xs.map(Surreal.Text.is_email)`) is `cannot reify this expression`; write `\|s\| Surreal.Text.is_email(s)` |
| `Rand` works in `default_by`, `computed` and an update only | See the effect rule |
| Each key part of `group_by` is a column of the result | SurrealDB refuses `GROUP BY` of a part that no column selects, a field or a call ("Missing group idiom", verified), so it is an `Unsupported`. A part that a column shows is grouped by the column's alias (`GROUP BY day`), so a call works there. Return the key from the function of `aggregate` |
| `group_by(\|_\| {})` is refused | A key of no parts has no `GROUP BY`. `GROUP ALL` gives one row for no rows, where Roc's groups of no rows are none, so it is not the same query. `Query.totals` is that query under its own name |
| `totals` gives one row, with the server's values for no rows | `GROUP ALL` of no rows gives `count()` 0, `math::sum` 0 (an `int`, which a `Dec` column reads), and `NaN` for `mean`, `stddev` and `variance`; `Math.mean([])` in Roc is `NaN` too. `math::median` is `NONE`, which is no `F64`, so `totals` refuses it. It has no `min` or `max` (a group has none), no `filter` after it (it has one row), no `live` and no view. `Totals.prepare` gives the row, `Prepared(out)`, and a reply with another count of rows is a `Wire` error (`tests/QueriesTest.roc:103`, `client.roc` checks `all_totals` and `no_totals` on both transports) |
| The text of a datetime is compared with a datetime or a literal only | The datetimes are compared, not the text, so a fraction of 3, 6 or 9 digits does not matter |
| `List.sort` is for whole numbers and `Dec` only | The evidence of the sort must be the `order_relative_to` of a builtin integer or `Dec`. `Str` and floats have no order in Roc, so they cannot be sorted. A type with its own order is refused |
| A query that calls `fn::x` needs the schema to define it | Queries render apart from the schema, so `Surreal.schema` cannot see the calls of a query. SurrealDB reports "The function 'fn::x' does not exist". Give each database function that a query calls to `Surreal.schema` with `Surreal.function` |
| Parameters of a database function are `$a1`, `$a2`, .. | A reified row has no parameter names. `INFO FOR DB` shows these names |
| A database function is a top-level constant of a top-level function | The name and the body must be literal data in the description |
| `create_new` and `insert_new` take an alias row with `id : Str` | The type `Table({ id : Str, ..new })` takes the row apart, which a nominal row and a `TimeKey` key do not allow. The result is a `Created`, not the row: the compiler derives no `parser_for` of a record with a type variable extension |
| A part of a transaction cannot read a key that another part made | Each part is built before the request runs. Write the rows that link to it after the result |
| `id : TimeKey(Link(..))` is refused | A key has no delete policy. Use an `Id` |
| A key has two parts, the series and the time | A key of several parts puts them in a record series. SurrealDB 4.0 has named key parts, and 3.3.4 does not |
| Views are grouped views only, with no parameters, order, limit or range | SurrealDB refuses order and a range in a view. A plain projection view adds no capability |
| No median, percentile, or integer sum in a view | SurrealDB refuses the first two, and gives a float for the sum |
| `SHOW CHANGES` has no Roc API | Its versionstamps cannot be predicted |
| `Time.floor`, `ceil` and `round` stop the program outside 1677 to 2262 | SurrealDB refuses a time outside the nanoseconds of an `I64` |
| A geometry other than a point is a parameter, not a clause literal | A tuple takes only number literals, and `<geometry>` of an object fails in 3.3.4. A captured geometry in `select_where` is refused with the same advice |
| `CONTAINSALL`, `CONTAINSANY`, `ALLINSIDE` and the other list forms have no Roc API | List semantics over geometries. Low use |
| A clause after a group, a limit or a start reads a subquery | SurrealDB 3.3.4 has no `HAVING` (verified), and a limit comes after `WHERE`. A `LIVE SELECT` refuses a subquery, so a live query can take only the form of one `SELECT` |
| No live query with `GROUP BY`, `ORDER BY`, `LIMIT`, `START`, `between` or a subquery | SurrealDB refuses them. Watch a view for a group, and order the rows of a `View` |
| A parameter of a live query is fixed when it starts | The `LET` is read once. Start a new watch for a new value |
| A filter that raises an error in SurrealDB drops the notice | SurrealDB sends nothing. The guard `$before IS NOT NONE` keeps a filter on `$before` from failing on a `CREATE` |
| The edge statement of a live query sends one notice for each edge write | It has no `WHERE`: a filter on the node after the write hides a node that leaves. `Watch.step` drops a notice of a record that is not in the result and does not match |
| `live_raw`: a row that leaves sends nothing, a row that enters is `Updated`, and a write to an edge table or to a table that the rows read sends nothing | By design. It is the server's own stream |
| `live_diff` watches the table only | By design. Its patches are of the stored row. A write to a table that a filter reads sends nothing |
| `live_diff`: a row that leaves sends nothing, and a row that enters sends only the ops of its write | A DIFF has no projection and no `now`. A patch replayed on a snapshot that already holds its write is wrong |
| `live_diff`: a field name with `/` or `~` gives a pointer that is not exact | SurrealDB does not escape them. Roc field names have neither |
| No live query and no typed result of `Unchecked.select_star` | Its row has no type, and a notice and a typed result are typed rows |
| A live query needs a session on a platform with TCP | `/sql` has no live queries. The Echo platform has no TCP, so only `watch.roc` and `client.roc`, on basic-cli, and `server.roc`, on basic-webserver, open a session |
| Requests in flight run with no order between them | SurrealDB runs the requests of a session at the same time, and their replies come out of order (verified). A step that needs another goes in one request (`Prepared.then`), or waits for the reply to the other |
| The queued notices of a watch have no limit | The inbox of the session keeps each notice of a watch until the app reads it or kills the watch |
| A `LIVE` statement in the text of `Unchecked.query!` is not watched | Its notices are dropped: only `live!` gives the uuids of a watch to the inbox |
| A `Ref` with a key that the ORM does not write does not decode | A key is a `Ql.Value`, so a duration, bytes or a uuid key is a `Wire` error. A table of the ORM has a text key or a `TimeKey` |
| A row of a message or of a typed result is read twice | The fields around it are read with fixed types, and the row as a `Cbor.Value` that is then read as `out`: the compiler derives no `parser_for` of `{ row : out }` with `out` a type variable |
| `Patch.field` reads one path of fields | A path through each item of a list has no single pointer |

## The cost

`Surreal` is the largest module, and the translator is the largest single
part. `Surreal` is large because it holds the whole public API in one module:
the queries and writes, the schema builder, the live session with its inbox,
and the typed results. The translator is hard because it has to cover every
operation that a closure can build. Its `op` has one arm per `Code.Op`
variant.

The cost of a new feature is small and local:

- A new SurrealQL function is one row in the table of builtins, or one row of
  the table of package functions. It needs a test in `tests/TranslateTest.roc`.
  When its result is risky, it also needs a query in `examples/builtins.roc`.
- Nothing in `examples/main.roc` is SurrealQL-specific except the method
  names. Its queries use Roc's operators, its `match`, its optional fields
  and its `??`, and each query uses functions that the application also calls.
