import Ql

# The format the compiler's derived `encoder_for` is run against, so a Roc
# row or a parameter record becomes a `Ql.Value`.
#
# The state is a stack. Every encoder pushes exactly one value. A container
# remembers the stack height, lets its members push, then folds everything
# above that height into one value.
Encode :: {}.{

	## What the derived encoder threads through: the values built so far.
	State : List(Encode.Item)

	## One value on the stack. `Fields` is a record, and only `encode_record`
	## pushes it: the encoder of a record type, or of a nominal of the app over
	## a record. So the type of a union payload picks its form (`tagged`), not
	## the shape of its value.
	Item : [Fields(List({ name : Str, value : Ql.Value })), Value(Ql.Value)]

	## Anything the derived encoder can write as SurrealQL values. Nested
	## signatures spell the constraint out, as `Sql.Bindable` does.
	a.Writable : where [a.encoder_for : Encode.Format -> (a, Encode.State -> Try(Encode.State, []))]

	## The format the encoder is derived against. `I128` and `U128` have no
	## method here on purpose: a row that holds one does not type-check where
	## it is written, because SurrealDB has no 128-bit integer. A sized number
	## is the value of its type (`U8` is `5u8`), so a table with no schema
	## stores the type of the Roc field. `I64` is `int`, `F64` is `float`.
	Format := [Surreal].{
		rename_field : Format, Str -> Str
		rename_field = |_, name| name

		encode_str : Str, Encode.State -> Try(Encode.State, [])
		encode_str = |s, state| Ok(state.append(Value(Ql.Value.Str(s))))

		encode_bool : Bool, Encode.State -> Try(Encode.State, [])
		encode_bool = |b, state| Ok(state.append(Value(Ql.Value.Bool(b))))

		encode_i8 : I8, Encode.State -> Try(Encode.State, [])
		encode_i8 = |n, state| Ok(state.append(Value(Ql.Value.I8(n))))

		encode_i16 : I16, Encode.State -> Try(Encode.State, [])
		encode_i16 = |n, state| Ok(state.append(Value(Ql.Value.I16(n))))

		encode_i32 : I32, Encode.State -> Try(Encode.State, [])
		encode_i32 = |n, state| Ok(state.append(Value(Ql.Value.I32(n))))

		encode_i64 : I64, Encode.State -> Try(Encode.State, [])
		encode_i64 = |n, state| Ok(state.append(Value(Ql.Value.Int(n))))

		encode_u8 : U8, Encode.State -> Try(Encode.State, [])
		encode_u8 = |n, state| Ok(state.append(Value(Ql.Value.U8(n))))

		encode_u16 : U16, Encode.State -> Try(Encode.State, [])
		encode_u16 = |n, state| Ok(state.append(Value(Ql.Value.U16(n))))

		encode_u32 : U32, Encode.State -> Try(Encode.State, [])
		encode_u32 = |n, state| Ok(state.append(Value(Ql.Value.U32(n))))

		encode_u64 : U64, Encode.State -> Try(Encode.State, [])
		encode_u64 = |n, state| Ok(state.append(Value(Ql.Value.U64(n))))

		encode_dec : Dec, Encode.State -> Try(Encode.State, [])
		encode_dec = |d, state| Ok(state.append(Value(Ql.Value.Decimal(d))))

		encode_f32 : F32, Encode.State -> Try(Encode.State, [])
		encode_f32 = |f, state| Ok(state.append(Value(Ql.Value.F32(f))))

		encode_f64 : F64, Encode.State -> Try(Encode.State, [])
		encode_f64 = |f, state| Ok(state.append(Value(Ql.Value.Float(f))))

		## A record id, written by the hand-written encoders of `Surreal.Id`
		## and `Surreal.Link`.
		encode_id : Str, Str, Encode.State -> Try(Encode.State, [])
		encode_id = |table, key, state| Ok(state.append(Value(Ql.Value.Record({ table: table, key: key }))))

		## A record id with a key of any value, written by the encoder of
		## `Surreal.Ref`.
		encode_ref : Str, Ql.Value, Encode.State -> Try(Encode.State, [])
		encode_ref = |table, key, state| Ok(state.append(Value(Ql.Value.Ref({ table, key }))))

		## A datetime, written by the encoder of `Surreal.Datetime`.
		encode_datetime : Str, Encode.State -> Try(Encode.State, [])
		encode_datetime = |iso, state| Ok(state.append(Value(Ql.Value.Datetime(iso))))

		## A geometry as its GeoJSON object, written by the encoders of the
		## geometry types of `Surreal`. SurrealDB reads the object as a geometry.
		encode_geometry : Ql.Value, Encode.State -> Try(Encode.State, [])
		encode_geometry = |geojson, state| Ok(state.append(Value(geojson)))

		## A value of a SurrealDB type that has no Roc type, written by the
		## encoders of `Surreal.Regex`, `Surreal.Date` and the like.
		encode_value : Ql.Value, Encode.State -> Try(Encode.State, [])
		encode_value = |value, state| Ok(state.append(Value(value)))

		## Each field pushes its name, then its value. A field that is absent
		## pushes nothing, so the key is left out.
		encode_record : Encode.State, U64, (Encode.State, (Encode.State, Str, (Encode.State -> Try(Encode.State, [])) -> Try(Encode.State, [])) -> Try(Encode.State, [])) -> Try(Encode.State, [])
		encode_record = |state, _, write_fields| {
			base = state.len()
			written = write_fields(state, |acc, name, write_value| write_value(acc.append(Value(Ql.Value.Str(name)))))?
			Ok(Encode.fold_above(written, base, |items| Fields(Encode.pair_up(items, []))))
		}

		encode_list : Encode.State, U64, (Encode.State, (Encode.State, (Encode.State -> Try(Encode.State, [])) -> Try(Encode.State, [])) -> Try(Encode.State, [])) -> Try(Encode.State, [])
		encode_list = |state, _, write_items| {
			base = state.len()
			written = write_items(state, |acc, write_item| write_item(acc))?
			Ok(Encode.fold_above(written, base, |items| Value(Ql.Value.Array(items.map(Encode.value)))))
		}

		## The union payload rule: no payload is the bare tag
		## name, a record payload is spread next to `kind`, one other payload
		## is `value`, several are the array `value`. A record is a payload
		## that `encode_record` wrote (`Item`).
		encode_tag : Encode.State, Str, U64, (Encode.State, (Encode.State, (Encode.State -> Try(Encode.State, [])) -> Try(Encode.State, [])) -> Try(Encode.State, [])) -> Try(Encode.State, [])
		encode_tag = |state, tag, _, write_payloads| {
			base = state.len()
			written = write_payloads(state, |acc, write_item| write_item(acc))?
			Ok(Encode.fold_above(written, base, |items| Value(Encode.tagged(tag, items))))
		}
	}

	## The format a captured value is bound in where its type may hold an
	## opaque type of another package (`Code.Binds`, `Query.filter_with`).
	## The compiler runs the value's own `encoder_for` against it while the
	## program runs and hands the bytes to the translator, which reads them
	## back as the `Ql.Value` that `Encode.Format` gives for the same calls
	## (`Encode.bound`). Each value is a kind byte, then its contents: a text
	## is its byte count (8 bytes, big-endian) and its bytes, an integer 8
	## bytes, a `Dec` its attos in 16, a float its bits in 8, and a record, a
	## list and a tag hold their members up to a `0`. A sized integer is a
	## `10`, the byte of its type (`Encode.sized_kinds`) and 8 bytes, and an
	## `F32` an `11` and its bits in 4.
	Bind := [Default].{
		default : () -> Bind
		default = || Default

		rename_field : Bind, Str -> Str
		rename_field = |_, name| name

		encode_str : Str, List(U8) -> Try(List(U8), [])
		encode_str = |s, out| Ok(Encode.put_text(out.append(1), s))

		encode_bool : Bool, List(U8) -> Try(List(U8), [])
		encode_bool = |b, out| Ok(out.concat([2, if (b) 1 else 0]))

		encode_i8 : I8, List(U8) -> Try(List(U8), [])
		encode_i8 = |n, out| Ok(Encode.put_sized(out, 0, n.to_i64().to_u64_wrap()))

		encode_i16 : I16, List(U8) -> Try(List(U8), [])
		encode_i16 = |n, out| Ok(Encode.put_sized(out, 2, n.to_i64().to_u64_wrap()))

		encode_i32 : I32, List(U8) -> Try(List(U8), [])
		encode_i32 = |n, out| Ok(Encode.put_sized(out, 4, n.to_i64().to_u64_wrap()))

		encode_i64 : I64, List(U8) -> Try(List(U8), [])
		encode_i64 = |n, out| Ok(Encode.put_int(out, n))

		encode_u8 : U8, List(U8) -> Try(List(U8), [])
		encode_u8 = |n, out| Ok(Encode.put_sized(out, 1, n.to_u64()))

		encode_u16 : U16, List(U8) -> Try(List(U8), [])
		encode_u16 = |n, out| Ok(Encode.put_sized(out, 3, n.to_u64()))

		encode_u32 : U32, List(U8) -> Try(List(U8), [])
		encode_u32 = |n, out| Ok(Encode.put_sized(out, 5, n.to_u64()))

		encode_u64 : U64, List(U8) -> Try(List(U8), [])
		encode_u64 = |n, out| Ok(Encode.put_sized(out, 6, n))

		encode_dec : Dec, List(U8) -> Try(List(U8), [])
		encode_dec = |d, out| Ok(Encode.big_endian(out.append(4), d.to_attos().to_u128_wrap(), 16))

		encode_f32 : F32, List(U8) -> Try(List(U8), [])
		encode_f32 = |f, out| Ok(Encode.big_endian(out.append(11), f.to_bits().to_u128(), 4))

		encode_f64 : F64, List(U8) -> Try(List(U8), [])
		encode_f64 = |f, out| Ok(Encode.big_endian(out.append(5), f.to_bits().to_u128(), 8))

		## Each field is a `7`, its name, then its value. A field that is
		## absent writes nothing, so the key is left out.
		encode_record : List(U8), U64, (List(U8), (List(U8), Str, (List(U8) -> Try(List(U8), [])) -> Try(List(U8), [])) -> Try(List(U8), [])) -> Try(List(U8), [])
		encode_record = |out, _, write_fields| Ok(write_fields(out.append(6), |acc, name, write_value| write_value(Encode.put_text(acc.append(7), name)))?.append(0))

		encode_list : List(U8), U64, (List(U8), (List(U8), (List(U8) -> Try(List(U8), [])) -> Try(List(U8), [])) -> Try(List(U8), [])) -> Try(List(U8), [])
		encode_list = |out, _, write_items| Ok(write_items(out.append(8), |acc, write_item| write_item(acc))?.append(0))

		encode_tag : List(U8), Str, U64, (List(U8), (List(U8), (List(U8) -> Try(List(U8), [])) -> Try(List(U8), [])) -> Try(List(U8), [])) -> Try(List(U8), [])
		encode_tag = |out, tag, _, write_payloads| Ok(write_payloads(Encode.put_text(out.append(9), tag), |acc, write_item| write_item(acc))?.append(0))
	}

	put_text : List(U8), Str -> List(U8)
	put_text = |out, text| {
		bytes = text.to_utf8()
		Encode.big_endian(out, bytes.len().to_u128(), 8).concat(bytes)
	}

	## A sized integer: `10`, the byte of its type, and its 64 bits.
	put_sized : List(U8), U8, U64 -> List(U8)
	put_sized = |out, kind, bits| Encode.big_endian(out.concat([10, kind]), bits.to_u128(), 8)

	## The value of a sized integer of `put_sized`.
	sized_value : U8, U64 -> Try(Ql.Value, [BadBytes])
	sized_value = |kind, bits| match kind {
		0 => bits.to_i64_wrap().to_i8_try().map_ok(|n| Ql.Value.I8(n)).map_err(|_| BadBytes)
		1 => bits.to_u8_try().map_ok(|n| Ql.Value.U8(n)).map_err(|_| BadBytes)
		2 => bits.to_i64_wrap().to_i16_try().map_ok(|n| Ql.Value.I16(n)).map_err(|_| BadBytes)
		3 => bits.to_u16_try().map_ok(|n| Ql.Value.U16(n)).map_err(|_| BadBytes)
		4 => bits.to_i64_wrap().to_i32_try().map_ok(|n| Ql.Value.I32(n)).map_err(|_| BadBytes)
		5 => bits.to_u32_try().map_ok(|n| Ql.Value.U32(n)).map_err(|_| BadBytes)
		6 => Ok(Ql.Value.U64(bits))
		_ => Err(BadBytes)
	}

	put_int : List(U8), I64 -> List(U8)
	put_int = |out, n| Encode.big_endian(out.append(3), n.to_u64_wrap().to_u128(), 8)

	## The low `width` bytes of `bits`, the most significant first.
	big_endian : List(U8), U128, U8 -> List(U8)
	big_endian = |out, bits, width|
		if width == 0 {
			out
		} else {
			Encode.big_endian(out.append(bits.shr_zf_wrap((width - 1) * 8).to_u8_wrap()), bits, width - 1)
		}

	## The value of the bytes `Bind` wrote for one captured value.
	bound : List(U8) -> Try(Ql.Value, [BadBytes])
	bound = |bytes| match Encode.read_item(bytes, 0)? {
		(item, next) if next == bytes.len() => Ok(Encode.value(item))
		_ => Err(BadBytes)
	}

	## The item that starts at `at`, and where the next one starts.
	read_item : List(U8), U64 -> Try((Encode.Item, U64), [BadBytes])
	read_item = |bytes, at| match bytes.get(at) {
		Ok(1) => {
			(text, next) = Encode.read_text(bytes, at + 1)?
			Ok((Value(Ql.Value.Str(text)), next))
		}
		Ok(2) => match bytes.get(at + 1) {
			Ok(b) => Ok((Value(Ql.Value.Bool(b == 1)), at + 2))
			Err(_) => Err(BadBytes)
		}
		Ok(3) => Ok((Value(Ql.Value.Int(Encode.read_bits(bytes, at + 1, 8)?.to_u64_wrap().to_i64_wrap())), at + 9))
		Ok(4) => Ok((Value(Ql.Value.Decimal(Dec.from_attos(Encode.read_bits(bytes, at + 1, 16)?.to_i128_wrap()))), at + 17))
		Ok(5) => Ok((Value(Ql.Value.Float(F64.from_bits(Encode.read_bits(bytes, at + 1, 8)?.to_u64_wrap()))), at + 9))
		Ok(10) => {
			kind = bytes.get(at + 1).map_err(|_| BadBytes)?
			Ok((Value(Encode.sized_value(kind, Encode.read_bits(bytes, at + 2, 8)?.to_u64_wrap())?), at + 10))
		}
		Ok(11) => Ok((Value(Ql.Value.F32(F32.from_bits(Encode.read_bits(bytes, at + 1, 4)?.to_u32_wrap()))), at + 5))
		Ok(6) => {
			(fields, next) = Encode.read_fields(bytes, at + 1, [])?
			Ok((Fields(fields), next))
		}
		Ok(8) => {
			(items, next) = Encode.read_items(bytes, at + 1, [])?
			Ok((Value(Ql.Value.Array(items.map(Encode.value))), next))
		}
		Ok(9) => {
			(tag, start) = Encode.read_text(bytes, at + 1)?
			(payloads, next) = Encode.read_items(bytes, start, [])?
			Ok((Value(Encode.tagged(tag, payloads)), next))
		}
		_ => Err(BadBytes)
	}

	read_fields : List(U8), U64, List({ name : Str, value : Ql.Value }) -> Try((List({ name : Str, value : Ql.Value }), U64), [BadBytes])
	read_fields = |bytes, at, done| match bytes.get(at) {
		Ok(0) => Ok((done, at + 1))
		Ok(7) => {
			(name, start) = Encode.read_text(bytes, at + 1)?
			(item, next) = Encode.read_item(bytes, start)?
			Encode.read_fields(bytes, next, done.append({ name, value: Encode.value(item) }))
		}
		_ => Err(BadBytes)
	}

	read_items : List(U8), U64, List(Encode.Item) -> Try((List(Encode.Item), U64), [BadBytes])
	read_items = |bytes, at, done| match bytes.get(at) {
		Ok(0) => Ok((done, at + 1))
		Ok(_) => {
			(item, next) = Encode.read_item(bytes, at)?
			Encode.read_items(bytes, next, done.append(item))
		}
		Err(_) => Err(BadBytes)
	}

	read_text : List(U8), U64 -> Try((Str, U64), [BadBytes])
	read_text = |bytes, at| {
		count = Encode.read_bits(bytes, at, 8)?.to_u64_wrap()
		part = bytes.drop_first(at + 8).take_first(count)
		if part.len() != count {
			return Err(BadBytes)
		}
		match Str.from_utf8(part) {
			Ok(text) => Ok((text, at + 8 + count))
			Err(_) => Err(BadBytes)
		}
	}

	## The `width` bytes at `at`, big-endian.
	read_bits : List(U8), U64, U64 -> Try(U128, [BadBytes])
	read_bits = |bytes, at, width| {
		part = bytes.drop_first(at).take_first(width)
		if (part.len() == width) Ok(part.fold(0, |bits, b| bits.shl_wrap(8).bitwise_or(b.to_u128()))) else Err(BadBytes)
	}

	## Encode a value the way a row is written.
	value_of : a -> Try(Ql.Value, Ql.Error) where [a.encoder_for : Encode.Format -> (a, Encode.State -> Try(Encode.State, []))]
	value_of = |value| {
		Shape : a
		encode = Shape.encoder_for(Encode.Format.Surreal)
		match encode(value, []) {
			Ok([one]) => Ok(Encode.value(one))
			Ok(_) => Err(BadSchema("an encoder wrote other than one value"))
		}
	}

	## The stack above `base` becomes one value on top of what was below.
	fold_above : Encode.State, U64, (List(Encode.Item) -> Encode.Item) -> Encode.State
	fold_above = |state, base, build| {
		below = state.take_first(base)
		below.append(build(state.drop_first(base)))
	}

	## Names and values alternate on the stack, as `encode_record` pushed them.
	pair_up : List(Encode.Item), List({ name : Str, value : Ql.Value }) -> List({ name : Str, value : Ql.Value })
	pair_up = |items, done| match items {
		[Value(Ql.Value.Str(name)), item, .. as rest] => Encode.pair_up(rest, done.append({ name: name, value: Encode.value(item) }))
		_ => done
	}

	## The value of an item: a record is an object.
	value : Encode.Item -> Ql.Value
	value = |item| match item {
		Fields(fields) => Ql.Value.Object(fields)
		Value(v) => v
	}

	## One union value from its tag and the payloads the arm carried. Only a
	## record payload is spread next to `kind`. A geometry is an object too,
	## but its type is not a record, so it is `value`, as the schema and the
	## reader have it.
	tagged : Str, List(Encode.Item) -> Ql.Value
	tagged = |tag, payloads| {
		kind = { name: "kind", value: Ql.Value.Str(tag) }
		match payloads {
			[] => Ql.Value.Str(tag)
			[Fields(fields)] => Ql.Value.Object(fields.prepend(kind))
			[one] => Ql.Value.Object([kind, { name: "value", value: Encode.value(one) }])
			many => Ql.Value.Object([kind, { name: "value", value: Ql.Value.Array(many.map(Encode.value)) }])
		}
	}
}

Row : { id : Str, qty : I64, price : Dec, ratio : F64, ok : Bool, tags : List(Str), note ?: Str, pay : [Cash, Card({ last4 : Str }), Check(I64), Wire(Str, I64)] }

row_a : Row
row_a = { id: "o'neil", qty: 3, price: 1.5, ratio: 2.0, ok: Bool.True, tags: ["a", "b"], pay: Card({ last4: "4242" }) }

row_b : Row
row_b = { id: "x", qty: -1, price: 0, ratio: 0.5, ok: Bool.False, tags: [], note: "hi", pay: Cash }

small : { a : I8, b : U8, c : I16, d : U16, e : I32, f : U32, g : F32 }
small = { a: -1, b: 255, c: -300, d: 65535, e: -70000, f: 4000000000, g: 1.5 }

expect Encode.value_of(row_a).map_ok(Ql.literal) == Ok("{ id: 'o\\'neil', ok: true, pay: { kind: 'Card', last4: '4242' }, price: 1.5dec, qty: 3, ratio: 2f, tags: ['a', 'b'] }")
expect Encode.value_of(row_b).map_ok(Ql.literal) == Ok("{ id: 'x', note: 'hi', ok: false, pay: 'Cash', price: 0.0dec, qty: -1, ratio: 0.5f, tags: [] }")
expect Encode.value_of(small).map_ok(Ql.literal) == Ok("{ a: -1i8, b: 255u8, c: -300i16, d: 65535u16, e: -70000i32, f: 4000000000u32, g: 1.5f32 }")

# A `U64` is a `u64`, all of its range.
wide : { a : U64, b : U64, c : U64, d : U64 }
wide = { a: 0, b: 9223372036854775807, c: 9223372036854775808, d: 18446744073709551615 }

expect Encode.value_of(wide).map_ok(Ql.literal) == Ok("{ a: 0u64, b: 9223372036854775807u64, c: 9223372036854775808u64, d: 18446744073709551615u64 }")

pay_check : Row
pay_check = { ..row_b, pay: Check(7) }

pay_wire : Row
pay_wire = { ..row_b, pay: Wire("eu", 9) }

expect Encode.value_of(pay_check).map_ok(Ql.literal) == Ok("{ id: 'x', note: 'hi', ok: false, pay: { kind: 'Check', value: 7 }, price: 0.0dec, qty: -1, ratio: 0.5f, tags: [] }")
expect Encode.value_of(pay_wire).map_ok(Ql.literal) == Ok("{ id: 'x', note: 'hi', ok: false, pay: { kind: 'Wire', value: ['eu', 9] }, price: 0.0dec, qty: -1, ratio: 0.5f, tags: [] }")

## A value as `Bind` binds it.
bound_of : a -> Try(Ql.Value, [BadBytes]) where [a.encoder_for : Encode.Bind -> (a, List(U8) -> Try(List(U8), []))]
bound_of = |value| {
	Shape : a
	encode = Shape.encoder_for(Encode.Bind.default())
	match encode(value, []) {
		Ok(bytes) => Encode.bound(bytes)
	}
}

# The bytes `Bind` writes read back as the value `Format` gives.
expect bound_of(row_a).map_ok(Ql.literal) == Encode.value_of(row_a).map_ok(Ql.literal).map_err(|_| BadBytes)
expect bound_of(row_b).map_ok(Ql.literal) == Encode.value_of(row_b).map_ok(Ql.literal).map_err(|_| BadBytes)
expect bound_of(small).map_ok(Ql.literal) == Encode.value_of(small).map_ok(Ql.literal).map_err(|_| BadBytes)
expect bound_of(wide).map_ok(Ql.literal) == Encode.value_of(wide).map_ok(Ql.literal).map_err(|_| BadBytes)
expect bound_of(pay_wire).map_ok(Ql.literal) == Encode.value_of(pay_wire).map_ok(Ql.literal).map_err(|_| BadBytes)
negative : F64
negative = -2.5

expect bound_of(negative).map_ok(Ql.literal) == Ok("-2.5f")
expect Encode.bound([3, 0]).is_err()

