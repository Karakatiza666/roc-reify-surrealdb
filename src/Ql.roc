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
	## | `Text(why)` | The runner does not read the file: its header, a `BEGIN` or `COMMIT`, an index and a write on one table in one section, two files with one name |
	## | `Legacy` | The header has `target V3`: a file for SurrealDB 3, from 0.0.3 or before. With 0.0.3, raise the database to level 4 and squash the files into one `V4` file that `replaces` them; then upgrade |
	## | `Level(l)` | The database is at a compatibility level below 4 (`found`), such as a SurrealDB 3 datastore upgraded to SurrealDB 4. `name` is "". Raise it with `ALTER DATABASE COMPATIBILITY 4` |
	## | `Unplanned(statements)` | `Surreal.check`: the schema has changes that no migration file has |
	MigrationProblem : [Changed, OutOfOrder, Edit, Text(Str), Legacy, Level({ found : U64 }), Unplanned(List(Str))]

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
	##
	## The sized numbers of SurrealDB (`I8` to `U64`, `F16` and `F32`) are
	## apart from `Int` (`i64`) and `Float` (`f64`): their literal has the
	## suffix of the type (`5u8`), and CBOR v2 tags them (180 to 188). The
	## other types of CBOR v2: `Regex` (tag 193) and `BigDecimal` (192) hold
	## their text, `Date` (100) the days since 1970-01-01, `Time` (189) the
	## nanoseconds since midnight, `Timestamp` (190) the seconds and
	## nanoseconds since 1970 with no time zone, and `Interval` (191) the
	## months, the days and the microseconds.
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
		I8(I8),
		U8(U8),
		I16(I16),
		U16(U16),
		I32(I32),
		U32(U32),
		U64(U64),
		F16(F32),
		F32(F32),
		Regex(Str),
		BigDecimal(Str),
		Date(I32),
		Time(U64),
		Timestamp({ secs : I64, nanos : U32 }),
		Interval({ months : I32, days : I32, micros : I64 }),
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
		I8(n) => "${n.to_str()}i8"
		U8(n) => "${n.to_str()}u8"
		I16(n) => "${n.to_str()}i16"
		U16(n) => "${n.to_str()}u16"
		I32(n) => "${n.to_str()}i32"
		U32(n) => "${n.to_str()}u32"
		U64(n) => "${n.to_str()}u64"
		F16(f) => Ql.sized_float(f, "f16")
		F32(f) => Ql.sized_float(f, "f32")
		Regex(pattern) => "<regex>${Ql.quote(pattern)}"
		BigDecimal(text) => "<bigdecimal>${Ql.quote(text)}"
		Date(days) => "<date>'${Ql.date_text(days.to_i128())}'"
		Time(nanos) => "<time>'${Ql.clock_text(nanos.to_i128())}'"
		Timestamp(t) => {
			days = t.secs.to_i128().div_floor_by(86400)
			nanos = t.secs.to_i128().mod_by(86400) * 1000000000 + t.nanos.to_i128()
			"<timestamp>'${Ql.date_text(days)}T${Ql.clock_text(nanos)}'"
		}
		Interval(i) => "<interval>'${Ql.interval_text(i)}'"
	}

	## A float of a sized type with its suffix (`1.5f32`). The non-finite
	## values have no literal, so they are a cast: `<f32>NaN`.
	sized_float : F32, Str -> Str
	sized_float = |f, suffix|
		if f.is_nan() {
			"<${suffix}>NaN"
		} else if f.is_infinite() {
			if (f < 0) "<${suffix}>-Infinity" else "<${suffix}>Infinity"
		} else {
			"${f.to_str()}${suffix}"
		}

	## The date of a day number counted from 1970-01-01, as SurrealDB reads
	## it: `2026-11-13`, `-0001-01-01`, `+10000-01-01`.
	date_text : I128 -> Str
	date_text = |days| {
		(year, month, day) = Ql.civil_from_days(days)
		year_text = if year < 0 "-${Ql.pad(0 - year, 4)}" else if year > 9999 "+${year.to_str()}" else Ql.pad(year, 4)
		"${year_text}-${Ql.pad(month, 2)}-${Ql.pad(day, 2)}"
	}

	## The time of day of the nanoseconds since midnight: `12:30:00`,
	## `12:30:00.5`. The fraction has no trailing zeros.
	clock_text : I128 -> Str
	clock_text = |nanos| {
		secs = nanos // 1000000000
		rest = nanos % 1000000000
		clock = "${Ql.pad(secs // 3600, 2)}:${Ql.pad(secs % 3600 // 60, 2)}:${Ql.pad(secs % 60, 2)}"
		if (rest == 0) clock else "${clock}.${Ql.fraction(rest, 9)}"
	}

	## An interval in ISO 8601: `P1M2DT3.5S`. Each part has its own sign,
	## as SurrealDB reads it (`P1M-2D`).
	interval_text : { months : I32, days : I32, micros : I64 } -> Str
	interval_text = |i| {
		micros = i.micros.to_i128()
		size = if (micros < 0) 0 - micros else micros
		seconds = "${if (micros < 0) "-" else ""}${(size // 1000000).to_str()}${if (size % 1000000 == 0) "" else ".${Ql.fraction(size % 1000000, 6)}"}"
		"P${i.months.to_str()}M${i.days.to_str()}DT${seconds}S"
	}

	## The digits of a fraction of `width` digits, without trailing zeros:
	## 500000000 of 9 is `5`.
	fraction : I128, U64 -> Str
	fraction = |n, width| {
		var $digits = Ql.pad(n, width).to_utf8()
		while $digits.last() == Ok(48) {
			$digits = $digits.drop_last(1)
		}
		Str.from_utf8($digits) ?? ""
	}

	## The year, month and day of a day number counted from 1970-01-01.
	civil_from_days : I128 -> (I128, I128, I128)
	civil_from_days = |days| {
		shifted = days + 719468
		era = shifted.div_floor_by(146097)
		day_of_era = shifted - era * 146097
		year_of_era = (day_of_era - day_of_era // 1460 + day_of_era // 36524 - day_of_era // 146096) // 365
		day_of_year = day_of_era - (365 * year_of_era + year_of_era // 4 - year_of_era // 100)
		march_month = (5 * day_of_year + 2) // 153
		month = if (march_month < 10) march_month + 3 else march_month - 9
		(year_of_era + era * 400 + (if (month <= 2) 1 else 0), month, day_of_year - (153 * march_month + 2) // 5 + 1)
	}

	## A number in at least `width` digits, with leading zeros.
	pad : I128, U64 -> Str
	pad = |n, width| {
		text = n.to_str()
		Str.repeat("0", width - text.count_utf8_bytes()).concat(text)
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
	## running each candidate word against SurrealDB 4.0.1.
	keywords : List(Str)
	keywords = [
		"alter",
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
		"overwrite",
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
expect Ql.ident("alter") == "⟨alter⟩"
expect Ql.ident("overwrite") == "⟨overwrite⟩"
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

# The sized numbers have the suffix of their type; a non-finite float is a cast.
expect Ql.literal(Value.U8(5)) == "5u8"
expect Ql.literal(Value.I8(-128)) == "-128i8"
expect Ql.literal(Value.I16(-300)) == "-300i16"
expect Ql.literal(Value.U16(65535)) == "65535u16"
expect Ql.literal(Value.I32(-70000)) == "-70000i32"
expect Ql.literal(Value.U32(4000000000)) == "4000000000u32"
expect Ql.literal(Value.U64(18446744073709551615)) == "18446744073709551615u64"
expect Ql.literal(Value.F32(1.5)) == "1.5f32"
expect Ql.literal(Value.F32(0.1)) == "0.1f32"
expect Ql.literal(Value.F32(F32.nan)) == "<f32>NaN"
expect Ql.literal(Value.F16(-F32.infinity)) == "<f16>-Infinity"
expect Ql.literal(Value.F16(1.5)) == "1.5f16"

# The other types of CBOR v2 are casts of their text (verified on 4.0.1).
expect Ql.literal(Value.Regex("a'b/c")) == "<regex>'a\\'b/c'"
expect Ql.literal(Value.BigDecimal("1.50")) == "<bigdecimal>'1.50'"
expect Ql.literal(Value.Date(20770)) == "<date>'2026-11-13'"
expect Ql.literal(Value.Date(-1)) == "<date>'1969-12-31'"
expect Ql.literal(Value.Date(-719893)) == "<date>'-0001-01-01'"
expect Ql.literal(Value.Date(2932897)) == "<date>'+10000-01-01'"
expect Ql.literal(Value.Time(45000500000000)) == "<time>'12:30:00.5'"
expect Ql.literal(Value.Time(0)) == "<time>'00:00:00'"
expect Ql.literal(Value.Timestamp({ secs: 1794573000, nanos: 123456789 })) == "<timestamp>'2026-11-13T12:30:00.123456789'"
expect Ql.literal(Value.Timestamp({ secs: -1, nanos: 500000000 })) == "<timestamp>'1969-12-31T23:59:59.5'"
expect Ql.literal(Value.Interval({ months: 1, days: 2, micros: 3000000 })) == "<interval>'P1M2DT3S'"
expect Ql.literal(Value.Interval({ months: 1, days: -2, micros: -1000001 })) == "<interval>'P1M-2DT-1.000001S'"
expect Ql.literal(Value.Interval({ months: 0, days: 0, micros: 0 })) == "<interval>'P0M0DT0S'"
