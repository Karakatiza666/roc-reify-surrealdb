app [] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.4.0/EnfRKFT7uPHmd3zT5PcwAiBWUtGmBXapJqFK5166U33J.tar.zst",
	internal: "../src/internal.roc",
}

import internal.Rpc
import cbor.Cbor

# Tests of the RPC requests of a session and of the uuids of live queries,
# without a server. Nothing outside this file imports it.
RpcTest :: {}

uuid : List(U8)
uuid = [1, 35, 69, 103, 137, 171, 205, 239, 1, 35, 69, 103, 137, 171, 205, 239]

expect Rpc.signin(1, { user: "root", pass: "root" }) == { id: 1, method: "signin", params: [{ user: "root", pass: "root" }] }
expect Rpc.use_db(2, "roc", "roc_surreal") == { id: 2, method: "use", params: ["roc", "roc_surreal"] }
expect Rpc.query(3, "LIVE SELECT DIFF FROM vital;") == { id: 3, method: "query", params: ["LIVE SELECT DIFF FROM vital;"] }
expect Rpc.authenticate(4, "eyJ.a.b") == { id: 4, method: "authenticate", params: ["eyJ.a.b"] }
expect Rpc.invalidate(5) == { id: 5, method: "invalidate", params: [] }

# A signup or a signin of a record user is one map: the namespace, the
# database and the access method, then the variables of its query.
expect
	Rpc.access(1, "signin", { ns: "roc", db: "roc_surreal", access: "account" }, [(Cbor.Value.Text("email"), Cbor.Value.Text("ann@roc"))])
		== {
			id: 1,
			method: "signin",
			params: [Cbor.Value.Map([(Text("ns"), Text("roc")), (Text("db"), Text("roc_surreal")), (Text("ac"), Text("account")), (Text("email"), Text("ann@roc"))])],
		}
expect Rpc.Uuid.from_bytes(uuid).map_ok(|u| u.to_str()) == Ok("01234567-89ab-cdef-0123-456789abcdef")
expect Rpc.Uuid.from_bytes([1]) == Err(BadUuid)

# The bytes that `check.py` writes for the same request: the uuid is tag 37
# (`d8 25`) and a byte string of 16 bytes (`50`).
expect
	match Rpc.Uuid.from_bytes(uuid) {
		Ok(live) => Cbor.encode(Rpc.kill(4, live)) == [163, 98, 105, 100, 4, 102, 109, 101, 116, 104, 111, 100, 100, 107, 105, 108, 108, 102, 112, 97, 114, 97, 109, 115, 129, 216, 37, 80].concat(uuid)
		Err(_) => Bool.False
	}

# A uuid reads back from its own bytes, and other bytes are refused.
expect {
	back : Try(Rpc.Uuid, _)
	back = Cbor.parse([216, 37, 80].concat(uuid))
	back == Rpc.Uuid.from_bytes(uuid)
}

expect {
	wrong_tag : Try(Rpc.Uuid, _)
	wrong_tag = Cbor.parse([216, 36, 80].concat(uuid))
	wrong_tag == Err(InvalidCbor(0))
}

expect {
	short : Try(Rpc.Uuid, _)
	short = Cbor.parse([216, 37, 65, 1])
	short == Err(InvalidCbor(0))
}
