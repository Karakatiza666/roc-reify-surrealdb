app [] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.4.0/EnfRKFT7uPHmd3zT5PcwAiBWUtGmBXapJqFK5166U33J.tar.zst",
	internal: "../src/internal.roc",
}

import internal.Ql
import internal.Surreal
import Temperature

# Tests of a translator extension. `Temperature` is an opaque type of
# another module, so the translator has no SurrealQL form for its
# functions. A `Surreal.Extension` gives one for each by the id the
# compiler gives it, and `Surreal.select_where_with` binds a captured
# `Temperature` as its own encoder writes it. Nothing outside this file
# imports it.
ExtensionTest :: {}

Reading : { id : Str, patient : Str, temp_c : Dec }

readings : Surreal.Table(Reading)
readings = Surreal.table("reading")

## What a glue package for `Temperature` would export. A temperature is
## its `Dec` in SurrealDB, which is what its encoder writes too.
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

only : { args : List(Str), evidence : List(Code.Evidence) } -> Try(Str, Str)
only = |call| match call.args {
	[one] => Ok(one)
	_ => Err("takes one operand")
}

binary : Str -> ({ args : List(Str), evidence : List(Code.Evidence) } -> Try(Str, Str))
binary = |op| |call| match call.args {
	[a, b] => Ok("(${a} ${op} ${b})")
	_ => Err("`${op}` takes two operands")
}

script : Try(Surreal.Prepared(List(Reading)), Ql.Error) -> Try(Str, Ql.Error)
script = |prepared| prepared.map_ok(|p| p.statement().to_script())

inlined : Try(Surreal.Prepared(List(Reading)), Ql.Error) -> Try(Str, Ql.Error)
inlined = |prepared| prepared.map_ok(|p| p.statement().inlined)

# `>` on two temperatures is `Temperature.is_gt`, which the extension
# renders. The captured limit is one input, bound as the `Dec` that
# `encoder_for` wrote.
fever : Temperature -> Try(Surreal.Prepared(List(Reading)), Ql.Error)
fever = |limit| Surreal.bind_captured(Surreal.select_where_with(readings, [temperature_surreal], |r| Temperature.from_celsius(r.temp_c) > limit))

expect script(fever(Temperature.from_celsius(38.5))) == Ok("LET $_1 = 38.5dec;\nSELECT record::id(id) AS id, patient, temp_c FROM reading WHERE (temp_c > $_1);")
expect inlined(fever(Temperature.from_celsius(38.5))) == Ok("SELECT record::id(id) AS id, patient, temp_c FROM reading WHERE (temp_c > 38.5dec)")

# The value read out of the captured temperature is a `Dec`, and `>=` on it
# is the builtin's. A captured text next to it is bound as before.
at_least : Str, Temperature -> Try(Surreal.Prepared(List(Reading)), Ql.Error)
at_least = |who, limit| Surreal.bind_captured(Surreal.select_where_with(readings, [temperature_surreal], |r| r.patient == who and r.temp_c >= limit.celsius()))

expect inlined(at_least("rex", Temperature.from_celsius(39))) == Ok("SELECT record::id(id) AS id, patient, temp_c FROM reading WHERE (patient = 'rex') AND (temp_c >= 39.0dec)")

# A captured record that holds a temperature, read as a field path: the
# field is one input.
Ward : { name : Str, alarm : Temperature }

alarming : Ward -> Try(Surreal.Prepared(List(Reading)), Ql.Error)
alarming = |ward| Surreal.bind_captured(Surreal.select_where_with(readings, [temperature_surreal], |r| Temperature.from_celsius(r.temp_c) > ward.alarm))

expect script(alarming({ name: "east", alarm: Temperature.from_celsius(40) })) == Ok("LET $_1 = 40.0dec;\nSELECT record::id(id) AS id, patient, temp_c FROM reading WHERE (temp_c > $_1);")

# Without the extension, `Temperature.is_gt` is refused by name, not read
# as the builtin `>`.
unextended : Temperature -> Try(Surreal.Prepared(List(Reading)), Ql.Error)
unextended = |limit| Surreal.bind_captured(Surreal.select_where_with(readings, [], |r| Temperature.from_celsius(r.temp_c) > limit))

expect script(unextended(Temperature.from_celsius(38.5))) == Err(Unsupported("in the filter of `select_where`: `Temperature.is_gt` has no SurrealQL form"))

# An operation the extension does not cover is refused by name.
cold : Temperature -> Try(Surreal.Prepared(List(Reading)), Ql.Error)
cold = |limit| Surreal.bind_captured(Surreal.select_where_with(readings, [temperature_surreal], |r| Temperature.from_celsius(r.temp_c) < limit))

expect script(cold(Temperature.from_celsius(35))) == Err(Unsupported("in the filter of `select_where`: `Temperature.is_lt` has no SurrealQL form"))

# `Temperature.is_gt` and `Dec.is_gt` share a method name and have two ids,
# so an extension covers the one and leaves the builtin as it is.
expect Code.prim(Temperature.is_gt) != Code.prim(Dec.is_gt)
