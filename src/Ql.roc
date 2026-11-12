# SurrealQL text: the value type every module shares, and the quoting rules
# that turn a value, a name or a record id into source text.
import ws.Ws

Ql :: {}.{

	## Why a reified function is not SurrealQL, or a schema is not one
	## SurrealDB can create. Every rejection names the construct. A live
	## session adds six: `Decode` for a value of the server that does not
	## fit the Roc type it is read as, with the path to it when the reader
	## names one (`result.row.temp_c`, else empty), `Wire` for bytes from
	## the server that are not what the protocol says, `Server` for a
	## request or a statement that the server refused, by its kind,
	## `Aborted` for a transaction that a statement failed, `Transport`
	## for a post over HTTP that the platform could not do, and
	## `WebSocket` for an error of the WebSocket adapter (roc-websocket's
	## `Ws.Error`): the connection ended (`Closed`, with how), it is
	## closing (`Closing`), or a tag of the adapter, as `Str.inspect`
	## writes it (`Adapter`, such as `Tcp(TimedOut)` or `Refused("..")`).
	## `at` of `Aborted` is the place of the prepared statement that
	## failed it (`Transaction.then`): 0 for the first, and the count of
	## them for the `COMMIT`, such as a `Conflict`. Every other statement
	## of the transaction is rolled back, or did not run. `Migration` is a
	## migration file or a history that the runner refuses (`name` is the
	## file, "" for `Surreal.check`): see `MigrationProblem`.
	Error := [Unsupported(Str), BadSchema(Str), Decode({ path : Str, message : Str }), Wire(Str), Server(ServerError), Aborted({ at : U64, error : ServerError }), Transport(Str), WebSocket([Closed(Ws.Closure), Closing, Adapter(Str)]), Migration({ name : Str, problem : MigrationProblem })].{
		is_eq : _
	}

	## Why a migration does not run:
	##
	## | Tag | Meaning |
	## | --- | --- |
	## | `Changed` | The database applied the file, and its text changed after that (the checksum) |
	## | `OutOfOrder` | The file is not applied, and a later file of the list is |
	## | `Edit` | The file still has a `-- reify: edit` line: write the value it asks for, then remove the line |
	## | `Text(why)` | The runner does not read the file: its header, a `BEGIN` or `COMMIT`, an index and a write on one table in one section of a `V4` file, two files with one name |
	## | `Target(t)` | A `V4` file and a server that cannot run it: SurrealDB 3, or a database at compatibility level 3 |
	## | `Unplanned(statements)` | `Surreal.check`: the schema has changes that no migration file has |
	MigrationProblem : [Changed, OutOfOrder, Edit, Text(Str), Target({ file : Str, server : Str }), Unplanned(List(Str))]

	## Why the server refused a request or a statement: the `kind` of its
	## error, and for the kind `Internal` (and a `Validation` of a type),
	## what its message says when the message has the form SurrealDB 4.0.1
	## writes. Each keeps the message.
	##
	## | Tag | The server's error |
	## | --- | --- |
	## | `Exists` | `AlreadyExists`: `what` is the details' kind (`Record`, `Table`, ..), `name` the record id or the name |
	## | `NotFound` | `NotFound`, as `Exists`: a table, a record, a method |
	## | `Unique` | A unique index of the schema the session knows (`Session.knowing`) already holds the value: its table and fields (SurrealQL paths) |
	## | `Index` | The same for an index the session does not know |
	## | `Assert` | A field's `ASSERT` fails: the field, the record, the value and the condition |
	## | `Type` | A value does not fit the field's `TYPE` (`Validation` with details `InvalidRequest`) |
	## | `Check` | A `.check(name, ..)` of the schema that is an event fails (a check that a field holds is an `Assert`) |
	## | `Referenced` | A delete of a record that a link with `Reject` points at: `by` is the linking record (a root link) or `table.path` (a nested link) |
	## | `Denied` | `NotAllowed`, a post that HTTP refuses with 401 or 403, or a signup, a signin or a token that the server refuses (`Session.open!`) |
	## | `Parse` | `Validation` whose message is a parse error |
	## | `Invalid` | Any other `Validation`, such as a protected variable |
	## | `Conflict` | `Query` with `TransactionConflict`: the transaction can be retried |
	## | `Timeout` | `Query` with `TimedOut` |
	## | `Thrown` | `Thrown`: a `THROW`, with its text |
	## | `Other` | Any other kind, or a message of another form |
	ServerError := [
		Exists({ what : Str, name : Str, message : Str }),
		NotFound({ what : Str, name : Str, message : Str }),
		Unique({ table : Str, index : Str, fields : List(Str), value : Str, record : Str, message : Str }),
		Index({ index : Str, value : Str, record : Str, message : Str }),
		Assert({ table : Str, field : Str, record : Str, value : Str, condition : Str, message : Str }),
		Type({ table : Str, field : Str, record : Str, expected : Str, found : Str, message : Str }),
		Check({ table : Str, name : Str, message : Str }),
		Referenced({ record : Str, by : Str, message : Str }),
		Denied(Str),
		Parse(Str),
		Invalid(Str),
		Conflict(Str),
		Timeout(Str),
		Thrown({ text : Str, message : Str }),
		Other({ kind : Str, message : Str }),
	].{
		is_eq : _

		## The server's message, as it sent it.
		message : ServerError -> Str
		message = |error| match error {
			Exists(e) => e.message
			NotFound(e) => e.message
			Unique(e) => e.message
			Index(e) => e.message
			Assert(e) => e.message
			Type(e) => e.message
			Check(e) => e.message
			Referenced(e) => e.message
			Denied(m) | Parse(m) | Invalid(m) | Conflict(m) | Timeout(m) => m
			Thrown(e) => e.message
			Other(e) => e.message
		}
	}

	## One SurrealQL value, as a parameter, a seed or a default. `Float` and
	## `Decimal` stay apart because SurrealDB keeps them apart. `Record` is a
	## record id with a text key, and `Ref` one with a key of any value, such
	## as the array of a time series key.
	Value := [
		None,
		Bool(Bool),
		Int(I64),
		Float(F64),
		Decimal(Dec),
		Str(Str),
		Datetime(Str),
		Duration(U64),
		Record({ table : Str, key : Str }),
		Ref({ table : Str, key : Value }),
		Array(List(Value)),
		Object(List({ name : Str, value : Value })),
	]

	## The value as source text: `'it\'s'`, `20dec`, `customer:⟨ada⟩`, `{ a: 1 }`.
	literal : Value -> Str
	literal = |value| match value {
		None => "NONE"
		Bool(b) => if (b) "true" else "false"
		Int(n) => n.to_str()
		Float(f) => Ql.float(f)
		Decimal(d) => "${d.to_str()}dec"
		Str(s) => Ql.quote(s)
		Datetime(iso) => "d${Ql.quote(iso)}"
		Duration(nanos) => Ql.duration(nanos)
		Record(r) => Ql.record_id(r.table, r.key)
		Ref(r) => Ql.record_ref(r.table, r.key)
		Array(items) => "[${Str.join_with(items.map(Ql.literal), ", ")}]"
		Object([]) => "{}"
		Object(fields) => "{ ${Str.join_with(fields.map(|f| "${Ql.member(f.name)}: ${Ql.literal(f.value)}"), ", ")} }"
	}

	## A float with the `f` suffix, so a whole number stays a float. SurrealQL
	## spells the two non-finite values `NaN` and `Infinity`.
	float : F64 -> Str
	float = |f|
		if f.is_nan() {
			"NaN"
		} else if f.is_infinite() {
			if (f < 0) "-Infinity" else "Infinity"
		} else {
			"${f.to_str()}f"
		}

	## A duration of `nanos` nanoseconds as a literal in the largest units
	## that fit: `1d`, `1w`, `1h30m`, `0ns`.
	duration : U64 -> Str
	duration = |nanos| {
		units = [("w", 604800000000000), ("d", 86400000000000), ("h", 3600000000000), ("m", 60000000000), ("s", 1000000000), ("ms", 1000000), ("us", 1000), ("ns", 1)]
		(parts, _) = units.fold(
			([], nanos),
			|(found, left), (name, size)| if (left >= size) (found.append("${(left // size).to_str()}${name}"), left % size) else (found, left),
		)
		if parts.is_empty() "0ns" else Str.join_with(parts, "")
	}

	## A string literal in single quotes.
	quote : Str -> Str
	quote = |text| "'${Ql.escape(text, Bool.False)}'"

	## A table or field name, bare when SurrealQL reads it as a name and in
	## angle brackets otherwise (`⟨x y⟩`, `⟨select⟩`).
	ident : Str -> Str
	ident = |name|
		if Ql.is_plain(name) and !Ql.keywords.contains(name) {
			name
		} else {
			"⟨${Ql.escape(name, Bool.True)}⟩"
		}

	## A name after a dot or an object key. Words such as `value` and `select`
	## are fine there (verified), so only a name that is not plain is bracketed.
	member : Str -> Str
	member = |name| if (Ql.is_plain(name)) name else "⟨${Ql.escape(name, Bool.True)}⟩"

	## A record id. The key is always bracketed, so any key is one token:
	## `customer:⟨o'neil⟩`, `customer:⟨x y⟩`.
	record_id : Str, Str -> Str
	record_id = |table, key| "${Ql.ident(table)}:⟨${Ql.escape(key, Bool.True)}⟩"

	## A record id with a key of any value: `t:⟨key⟩` for a text key, as
	## `record_id`, and `t:[..]` for an array key, the key of a time series.
	record_ref : Str, Value -> Str
	record_ref = |table, key| match key {
		Str(text) => Ql.record_id(table, text)
		other => "${Ql.ident(table)}:${Ql.literal(other)}"
	}

	## Names SurrealQL does not accept bare as a table or a field. Found by
	## running each candidate word against SurrealDB 3.3.4.
	keywords : List(Str)
	keywords = [
		"break",
		"continue",
		"create",
		"define",
		"delete",
		"explain",
		"false",
		"for",
		"from",
		"function",
		"if",
		"info",
		"insert",
		"let",
		"none",
		"null",
		"only",
		"rebuild",
		"relate",
		"remove",
		"return",
		"select",
		"sleep",
		"table",
		"throw",
		"true",
		"update",
		"upsert",
		"value",
	]

	## A name made of lower case letters, digits and `_`, not starting with a digit.
	is_plain : Str -> Bool
	is_plain = |name| {
		bytes = name.to_utf8()
		is_letter = |b| (b >= 97 and b <= 122) or (b >= 65 and b <= 90) or b == 95
		is_digit = |b| b >= 48 and b <= 57
		match bytes {
			[first, .. as rest] => is_letter(first) and rest.all(|b| is_letter(b) or is_digit(b))
			[] => Bool.False
		}
	}

	## Text as it goes between quotes: `\`, the quote, and control characters
	## are escaped. Inside angle brackets, `⟩` is escaped too.
	escape : Str, Bool -> Str
	escape = |text, in_brackets| {
		bytes = text.to_utf8().fold(
			[],
			|out, byte|
				if byte == 92 {
					out.concat([92, 92])
				} else if byte == 39 and !in_brackets {
					out.concat([92, 39])
				} else if byte == 10 {
					out.concat([92, 110])
				} else if byte == 13 {
					out.concat([92, 114])
				} else if byte == 9 {
					out.concat([92, 116])
				} else if byte < 32 {
					# \u{1f}: two hex digits.
					out.concat(Str.to_utf8("\\u{${Ql.hex(byte // 16)}${Ql.hex(byte % 16)}}"))
				} else {
					out.append(byte)
				},
		)
		escaped = match Str.from_utf8(bytes) {
			Ok(s) => s
			Err(_) => crash "escaping whole bytes of valid UTF-8 keeps it valid"
		}
		if (in_brackets) escaped.replace_each("⟩", "\\u{27E9}") else escaped
	}

	hex : U8 -> Str
	hex = |digit| match ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"].get(digit.to_u64()) {
		Ok(c) => c
		Err(_) => crash "a hex digit is below 16"
	}
}

expect Ql.duration(0) == "0ns"
expect Ql.duration(7) == "7ns"
expect Ql.duration(999) == "999ns"
expect Ql.duration(1000) == "1us"
expect Ql.duration(1000000) == "1ms"
expect Ql.duration(1000000000) == "1s"
expect Ql.duration(60000000000) == "1m"
expect Ql.duration(3600000000000) == "1h"
expect Ql.duration(3600000000001) == "1h1ns"
expect Ql.duration(59999999999) == "59s999ms999us999ns"
expect Ql.duration(86400000000000) == "1d"
expect Ql.duration(604800000000000) == "1w"
expect Ql.duration(5400000000000) == "1h30m"
expect Ql.duration(691200000000000) == "1w1d"
expect Ql.duration(1001000) == "1ms1us"
expect Ql.duration(18446744073709551615) == "30500w3d23h34m33s709ms551us615ns"
expect Ql.quote("plain") == "'plain'"
expect Ql.quote("o'neil") == "'o\\'neil'"
expect Ql.quote("a\\b") == "'a\\\\b'"
expect Ql.quote("two\nlines\ttab") == "'two\\nlines\\ttab'"
expect Ql.quote("\u(1)") == "'\\u{01}'"
expect Ql.quote("é☃") == "'é☃'"
expect Ql.ident("name") == "name"
expect Ql.ident("x y") == "⟨x y⟩"
expect Ql.ident("select") == "⟨select⟩"
expect Ql.ident("9lives") == "⟨9lives⟩"
expect Ql.ident("") == "⟨⟩"
expect Ql.record_id("customer", "ada") == "customer:⟨ada⟩"
expect Ql.record_id("customer", "o'neil") == "customer:⟨o'neil⟩"
expect Ql.record_id("customer", "x y") == "customer:⟨x y⟩"
expect Ql.record_id("order", "a⟩b\\c") == "order:⟨a\\u{27E9}b\\\\c⟩"
expect Ql.record_id("my table", "1") == "⟨my table⟩:⟨1⟩"
expect Ql.record_ref("customer", Value.Str("o'neil")) == "customer:⟨o'neil⟩"
expect Ql.record_ref("vital", Value.Array([Value.Record({ table: "kennel", key: "a" }), Value.Datetime("2026-03-01T08:00:00Z")])) == "vital:[kennel:⟨a⟩, d'2026-03-01T08:00:00Z']"
expect Ql.literal(Value.None) == "NONE"
expect Ql.literal(Value.Bool(Bool.True)) == "true"
expect Ql.literal(Value.Int(-5)) == "-5"
expect Ql.literal(Value.Float(2.0)) == "2f"
expect Ql.literal(Value.Float(F64.nan)) == "NaN"
expect Ql.literal(Value.Float(-F64.infinity)) == "-Infinity"
expect Ql.literal(Value.Decimal(20)) == "20.0dec"
expect Ql.literal(Value.Decimal(-1.5)) == "-1.5dec"
expect Ql.literal(Value.Datetime("2026-10-28T04:53:59Z")) == "d'2026-10-28T04:53:59Z'"
expect Ql.literal(Value.Record({ table: "customer", key: "o'neil" })) == "customer:⟨o'neil⟩"
expect Ql.literal(Value.Ref({ table: "vital", key: Value.Array([Value.Record({ table: "kennel", key: "a" }), Value.Datetime("2026-03-01T08:00:00Z")]) })) == "vital:[kennel:⟨a⟩, d'2026-03-01T08:00:00Z']"
expect Ql.literal(Value.Array([Value.Int(1), Value.Str("a")])) == "[1, 'a']"
expect Ql.literal(Value.Array([])) == "[]"
expect Ql.literal(Value.Object([])) == "{}"
expect Ql.literal(Value.Object([{ name: "kind", value: Value.Str("Card") }, { name: "x y", value: Value.None }])) == "{ kind: 'Card', ⟨x y⟩: NONE }"
expect Ql.literal(Value.Float(0.00001)) == "1e-5f"
expect Ql.member("value") == "value"
expect Ql.member("x y") == "⟨x y⟩"
expect Ql.literal(Value.Object([{ name: "value", value: Value.Int(1) }])) == "{ value: 1 }"
