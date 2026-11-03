import cbor.Cbor

# The requests of SurrealDB's RPC protocol that a live session sends, as
# records. A request is one WebSocket message: `{ id, method, params }`,
# which `Cbor.encode` writes with the derived `encoder_for`. A parameter of
# a query is in its text as a `LET`, as `prepare` writes it, so only `kill`
# holds a tagged CBOR value: the uuid of the live query.
Rpc :: {}.{

	## The uuid of a live query: CBOR tag 37 and a byte string of 16 bytes.
	## SurrealDB gives one for each `LIVE SELECT`, and puts it in each
	## notice of that query.
	Uuid := List(U8).{
		is_eq : _
		to_hash : _

		## The uuid of these 16 bytes.
		from_bytes : List(U8) -> Try(Uuid, [BadUuid])
		from_bytes = |bytes| if (bytes.len() == 16) Ok(Uuid.(bytes)) else Err(BadUuid)

		## The text form: `8-4-4-4-12` hex digits.
		to_str : Uuid -> Str
		to_str = |Uuid.(bytes)| {
			hex = |part| Str.join_with(part.map(Rpc.hex_byte), "")
			Str.join_with([bytes.sublist({ start: 0, len: 4 }), bytes.sublist({ start: 4, len: 2 }), bytes.sublist({ start: 6, len: 2 }), bytes.sublist({ start: 8, len: 2 }), bytes.sublist({ start: 10, len: 6 })].map(hex), "-")
		}

		parser_for : Cbor -> (Cbor.State -> Try({ value : Uuid, rest : Cbor.State }, [InvalidCbor(U64)]))
		parser_for = |encoding| |state| {
			tag = Cbor.parse_cbor_tag(encoding, state)?
			bytes = Cbor.parse_bytes(encoding, tag.rest)?
			if tag.value == 37 and bytes.value.len() == 16 {
				Ok({ value: Uuid.(bytes.value), rest: bytes.rest })
			} else {
				Err(Cbor.invalid_value(encoding, state))
			}
		}

		encoder_for : Cbor -> (Uuid, List(U8) -> Try(List(U8), []))
		encoder_for = |_| |Uuid.(bytes), out| {
			tagged = Cbor.encode_cbor_tag(37, out)?
			Cbor.encode_item(Cbor.Bytes.(bytes), tagged)
		}
	}

	## `signin` as a system user of the server.
	signin : U64, { user : Str, pass : Str } -> { id : U64, method : Str, params : List({ user : Str, pass : Str }) }
	signin = |id, who| { id, method: "signin", params: [who] }

	## `signup` or `signin` (`method`) of a record user: one map of the
	## namespace, the database, the access method (`ac`) and the variables
	## of its `SIGNUP` or `SIGNIN` query. The reply is the token.
	access : U64, Str, { ns : Str, db : Str, access : Str }, List((Cbor.Value, Cbor.Value)) -> { id : U64, method : Str, params : List(Cbor.Value) }
	access = |id, method, at, vars| {
		head = [(Cbor.Value.Text("ns"), Cbor.Value.Text(at.ns)), (Cbor.Value.Text("db"), Cbor.Value.Text(at.db)), (Cbor.Value.Text("ac"), Cbor.Value.Text(at.access))]
		{ id, method, params: [Cbor.Value.Map(head.concat(vars))] }
	}

	## `authenticate`: the session is the user of a token.
	authenticate : U64, Str -> { id : U64, method : Str, params : List(Str) }
	authenticate = |id, token| { id, method: "authenticate", params: [token] }

	## `invalidate`: the session is no one.
	invalidate : U64 -> { id : U64, method : Str, params : List(Str) }
	invalidate = |id| { id, method: "invalidate", params: [] }

	## `use`: the namespace and the database of the session.
	use_db : U64, Str, Str -> { id : U64, method : Str, params : List(Str) }
	use_db = |id, ns, db| { id, method: "use", params: [ns, db] }

	## `query`: one text of statements, such as `Watch.request`.
	query : U64, Str -> { id : U64, method : Str, params : List(Str) }
	query = |id, text| { id, method: "query", params: [text] }

	## `kill`: the end of a live query. SurrealDB sends `KILLED` for it.
	kill : U64, Uuid -> { id : U64, method : Str, params : List(Uuid) }
	kill = |id, live| { id, method: "kill", params: [live] }

	hex_byte : U8 -> Str
	hex_byte = |b| "${Rpc.hex_digit(b // 16)}${Rpc.hex_digit(b % 16)}"

	hex_digit : U8 -> Str
	hex_digit = |d| match ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"].get(d.to_u64()) {
		Ok(c) => c
		Err(_) => crash "a hex digit is below 16"
	}
}
