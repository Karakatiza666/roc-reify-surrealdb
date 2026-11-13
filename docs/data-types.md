# Row types and data types

This page shows how to write the row types of your tables. Each Roc type has one SurrealDB type. You learn which types the package accepts, which it refuses, and how optional fields, defaults, tag unions, datetimes, the CBOR v2 types, time series keys and geometry work.

The schema comes from the type. You write no `DEFINE FIELD` by hand. See [Tables and schema](schema.md) for the clauses that add constraints and indexes.

## Row types

A row type is a Roc record. You can write it in three ways:

| Form | Example | Helper over an open row | `??` default |
| --- | --- | --- | --- |
| Alias | `Visit : { .. }` | Yes | No. Use `.default(..)` |
| Nominal | `Medication := { .. }.{ .. }` | Yes | Yes |
| Opaque | `Row :: { .. }` | No | Not usable as a row |

An alias is the simple case. A nominal row is for a field that has a `??` default. Add two lines that ask the compiler to derive the encoder and the parser of the row:

```roc
# Fragment: uses `import surreal.Surreal`.
Medication := { id : Str, name : Str, form : Str, label : Str, unit_price : Dec, stock : I32 ?? 0 }.{
	encoder_for : _
	parser_for : _
}
```

From `examples/main.roc`, `Medication`. Both forms work with the helpers of [Writing queries](queries.md#reuse-query-parts), such as `low : { stock : I32, ..r } -> Bool`.

Do not use an opaque type (`::`) for a row. A clause outside its module cannot read its fields: the compiler says `cannot reify this type` with the reason `a field the record's type does not have`. `Surreal.schema` also refuses it with ``BadSchema("a row is a record, and this is `Opaque`")``.

The record must have a required field `id`. Its type is `Str` or `Surreal.TimeKey(s)` (see [Time series keys](#time-series-keys)). This field is the key of the row.

## How Roc types map to SurrealDB types

`Surreal.schema` reads each field type and writes the `TYPE` of the field.

| Roc type | SurrealDB `TYPE` | Extra constraint |
| --- | --- | --- |
| `Str` | `string` | |
| `Bool` | `bool` | |
| `I64` | `int` | |
| `I8`, `I16`, `I32` | `i8`, `i16`, `i32` | |
| `U8`, `U16`, `U32`, `U64` | `u8`, `u16`, `u32`, `u64` | |
| `F32` | `f32` | |
| `F64` | `float` | |
| `Dec` | `decimal` | |
| `Surreal.Datetime` | `datetime` | |
| `Surreal.Date`, `Surreal.TimeOfDay`, `Surreal.Timestamp` | `date`, `time`, `timestamp` | |
| `Surreal.Interval`, `Surreal.Regex`, `Surreal.BigDecimal` | `interval`, `regex`, `bigdecimal` | |
| `Surreal.Id(row)`, `Surreal.Link(row)` | `record<table>` | `record::exists($value)`. A link also has a delete policy |
| `Surreal.Point`, `Line`, `Polygon`, `MultiPoint`, `MultiLine`, `MultiPolygon`, `Collection` | `geometry<point>` and so on | `geo::is_valid($value)` |
| `Surreal.Geometry` | `geometry` | `geo::is_valid($value)` |
| `id : Surreal.TimeKey(s)` | `[<type of s>, datetime]` | None |
| `{ a : A }` | `object`, then `DEFINE FIELD f.a` | |
| `List(T)` of a scalar | `array<T>` | |
| `List({ a : A })` | `array<{ a: A }>`, then `DEFINE FIELD f[*].a ASSERT ..` for a member with a condition | The literal type refuses other keys, so there is no key check |
| `List({ a : A ?? x })` (a member with a `??` default) | `array<object>`, then `DEFINE FIELD f[*].a TYPE A DEFAULT x` | A check that an object has no other keys. A literal type takes no missing key, so it cannot carry a default |
| `List(Link(row))` | `array<record<table>>` | `$value.all(\|$e1\| record::exists($e1))` |
| `[A, B({ x : X }), C(Y), D(Y, Z)]` | A union of literals and objects | See [Tag unions](#tag-unions) |
| `f ?: T` | `option<T>` | See [Optional fields](#optional-fields) |
| A named type `T := ..` | The type of its backing | |

A sized integer or float has the sized type of SurrealDB 4. The server refuses a value outside the range of the type, so the schema has no range `ASSERT`. A write gives each value a sized literal, such as `5u8` or `1.5f32`. Thus a field of a `SCHEMALESS` table also keeps its type. See [The CBOR v2 types](#the-cbor-v2-types).

Here is a row from `examples/main.roc` and the script that `Surreal.schema` prints for it:

```roc
# Fragment: uses `Contact` and `Specialty` from examples/main.roc.
VetRow(years) : { id : Str, name : Str, license : Str, contact : Contact, years : years, rate : Dec, specialty : Specialty }

Vet : VetRow(U8)
```

```surql
DEFINE TABLE OVERWRITE vet SCHEMAFULL;
DEFINE FIELD OVERWRITE contact ON vet TYPE object;
DEFINE FIELD OVERWRITE contact.email ON vet TYPE string;
DEFINE FIELD OVERWRITE contact.phone ON vet TYPE string;
DEFINE FIELD OVERWRITE license ON vet TYPE string;
DEFINE FIELD OVERWRITE name ON vet TYPE string;
DEFINE FIELD OVERWRITE rate ON vet TYPE decimal;
DEFINE FIELD OVERWRITE specialty ON vet TYPE "Dental" | "General" | { kind: "Surgery", board: string };
DEFINE FIELD OVERWRITE years ON vet TYPE u8;
```

Fields come out in name order, and a record gets one `DEFINE FIELD` for each part.

### Types that are refused

`Surreal.schema` gives `Err(BadSchema(why))` for these types. `why` names the field.

| Roc type | Reason in `why` |
| --- | --- |
| `I128`, `U128` | Does not fit SurrealDB's `int`, which is 64-bit signed |
| `Dict`, `Set` | `` `Dict` has no SurrealDB type `` |
| A tuple | `a tuple has no SurrealDB type` |
| `Try` | `` `Builtin.Try` has no SurrealDB type `` |
| A function | `a function has no SurrealDB type` |
| `Surreal.Duration` | `` `Surreal.Duration` has no SurrealDB type `` |
| `Surreal.TimeKey` in any field but `id` | `` `Surreal.TimeKey` has no SurrealDB type `` |
| `Linked`, `Out`, `In` | These belong to a read row, which is not stored (see [Ids, links and graph edges](links-and-graphs.md#read-rows)) |

The refusal is a value, not a compile error. See [Errors](errors.md#build-time-errors).

## Optional fields

Write `f ?: T` for a field that a row can leave out. The schema gives it `option<T>`. A value that is absent is `NONE` on the server.

| You write | SurrealQL |
| --- | --- |
| `o.?phone ?? "none"` | `phone ?? 'none'` |
| `o.address.?zip ?? "-"` | `address.zip ?? '-'` |
| `o.?phone.is_ok()` | `phone IS NOT NONE` |
| `match o.?phone { Ok(p) => .., Err(_) => .. }` | `(IF phone IS NONE THEN .. ELSE .. END)` |

The read `o.?phone` has the type `Try(Str, [MissingField])`. Use `??` for a fallback value, `is_ok` for a test, or `match` to use the value.

```roc
# Fragment: uses `Owner` from examples/main.roc.
phone_label : Owner -> Str
phone_label = |o| match o.?phone {
	Ok(p) => "call ${p}"
	Err(_) => "no phone"
}
```

`Owner` is the row of `examples/main.roc`. With `.select(|o| { id: o.id, label: phone_label(o) })` the label column is:

```surql
(IF phone IS NONE THEN 'no phone' ELSE 'call ' + phone END) AS label
```

An absent field in a write is a key that the statement leaves out. The `INSERT` of an owner with no phone has no `phone` key. To remove an optional field in a `set` patch, write `Err(Missing)` (see [Writing rows](writes.md#set-only-some-fields)). That patch gives `SET phone = NONE`.

An optional record, `chip ?: Chip`, gives `option<object>`. Its own fields keep their own `DEFINE FIELD` lines.

## Default values

A default fills a field that a write leaves out. You have three ways to give one:

| Way | Where | Schema |
| --- | --- | --- |
| `f : T ?? literal` | In a nominal row | `DEFAULT <literal>` |
| `.default(\|r\| r.f, value)` | In `define()` | `DEFAULT <literal>` |
| `.default_by(\|r\| r.f, \|r\| expr)` | In `define()` | `DEFAULT <expression>` |

A `??` default works at any depth. A nominal type inside a row, or inside a list, gives `size.w` or `crates[*].w` its default.

```roc
# Fragment: uses `plans : Surreal.Table(Plan)`. `Plan` is a small row for this page.
Plan : { id : Str, base : I64, limit : I64, tags : List(Str), opened : Surreal.Datetime }

plan_def : Surreal.Defined
plan_def =
	plans.define()
		.default(|p| p.tags, [])
		.default(|p| p.limit, 100)
		.default_by(|p| p.opened, |_| Surreal.Time.now())
		.done()
```

The script has these lines:

```surql
DEFINE FIELD OVERWRITE limit ON plan TYPE int DEFAULT 100;
DEFINE FIELD OVERWRITE opened ON plan TYPE datetime DEFAULT time::now();
DEFINE FIELD OVERWRITE tags ON plan TYPE array<string> DEFAULT [];
```

Use `default_by` for a value that reads the row or calls `Rand`. `.default_by(|p| p.limit, |p| p.base * 2)` gives `DEFAULT $this.base * 2`. `.default_by(|p| p.id, |_| Surreal.Rand.ulid())` gives the key a ULID (see [Writing rows](writes.md#keys-that-the-server-makes)).

| Case | Result |
| --- | --- |
| `??` on a field of an alias | Compile error: `default not allowed in structural record`. Use a nominal row or `.default(..)` |
| `??` with a value that is not a literal, such as `?? make({})` | `BadSchema`: the type does not carry the value. Use `.default_by(..)` |
| A `??` and a `.default(..)` on one field | ``BadSchema("`stock` has two defaults")`` |
| `??` in the record of a union arm | No default in the schema (see [Limits](#limits)) |

## Tag unions

A union of tags is a SurrealDB union of literals and objects. The tag is the field `kind`. The schema lists the arms in name order.

| Arm | Stored as | Example arm | `TYPE` part |
| --- | --- | --- | --- |
| No payload | `'Dog'` | `Dog` | `"Dog"` |
| One record payload | `{ kind: 'Bird', wingspan_cm: 30u8 }` | `Bird({ wingspan_cm : U8 })` | `{ kind: "Bird", wingspan_cm: u8 }` |
| One other payload | `{ kind: 'Weight', value: 4 }` | `Weight(I64)` | `{ kind: "Weight", value: int }` |
| Several payloads | `{ kind: 'Span', value: [1, 'x'] }` | `Span(I64, Str)` | `{ kind: "Span", value: [int, string] }` |

The type of the payload decides the shape, not the value. A record payload is a record type, or a nominal type with a derived `encoder_for` and `parser_for`. These payloads are not records, so they use `value`:

| Payload type | `TYPE` of `value` |
| --- | --- |
| `Surreal.Point` and the other geometry types | `geometry<point>` |
| `Surreal.Datetime` | `datetime` |
| `Dec` | `decimal` |
| `Link(row)`, `Id(row)` | `record<table>` |

Use `match` to read a union in a clause. It becomes an `IF` chain. The arm of a record payload reads the fields of the record:

```roc
# Fragment: uses `Species` from examples/main.roc.
species_label : Species -> Str
species_label = |species| match species {
	Dog => "dog"
	Cat => "cat"
	Bird(_) => "bird"
	Exotic(e) => e.latin
}
```

```surql
(IF species.kind = 'Bird' THEN 'bird' ELSE IF species = 'Cat' THEN 'cat' ELSE IF species = 'Dog' THEN 'dog' ELSE species.latin END)
```

From `examples/main.roc`, `Species`. See [Writing queries](queries.md#match-on-unions-and-optional-fields) for filters and `==` on unions.

## Datetimes and durations

`Surreal.Datetime` holds a time in UTC as text, such as `2026-03-04T05:06:07.5Z`. Make one with `Surreal.datetime`:

| Call | Type | Notes |
| --- | --- | --- |
| `Surreal.datetime(text)` | `Str -> Try(Datetime, [BadDatetime])` | Form `YYYY-MM-DDTHH:MM:SS`, a fraction of up to 9 digits, and `Z` |
| `Surreal.Datetime.to_unix_nanos(at)` | `Datetime -> I128` | Nanoseconds since 1970-01-01T00:00:00Z |
| `Surreal.Datetime.from_unix_nanos(n)` | `I128 -> Try(Datetime, [BadDatetime])` | A year outside 0 to 9999 is refused |

`Surreal.datetime` refuses an offset such as `+01:00` and a date that does not exist. It drops trailing zeros of the fraction, so `07.1230Z` is `07.123Z`. Use the two nanosecond calls to move between this type and the instant type of another time package. For example, `from_unix_nanos(1772600767123456789)` gives `Ok(2026-03-04T05:06:07.123456789Z)`.

Compare datetimes with `<`, `<=`, `>` and `>=`. The comparison is by time, in Roc and in the clause.

A clause cannot call `Surreal.datetime`. A call in a clause gives ``Unsupported("in `filter`: `Str.to_utf8` has no SurrealQL form")``. Bring a datetime into a clause as a parameter:

```roc
# Fragment: uses `Visit` with `seen : Surreal.Datetime`, and `moment` that unwraps `Surreal.datetime`.
seen_since : { since : Surreal.Datetime }, Visit -> Bool
seen_since = |p, v| v.seen >= p.since

# .filter_by(seen_since).prepare({ since: moment("2026-03-01T00:00:00Z") })
```

```surql
LET $since = d'2026-03-01T00:00:00Z';
SELECT record::id(id) AS id, seen AS seen FROM visit WHERE $since <= seen;
```

A clause can also read a datetime from around the function (see [Writing queries](queries.md#use-values-from-around-the-function)).

### Durations

A `Surreal.Duration` is a length of time. Make one with a function of `Surreal.Time`. Each takes a `U64`:

| Call | Unit |
| --- | --- |
| `Time.nanos`, `Time.micros`, `Time.millis` | Nanosecond, microsecond, millisecond |
| `Time.secs`, `Time.mins`, `Time.hours` | Second, minute, hour |
| `Time.days`, `Time.weeks` | Day, week |

Use a duration with `Time.plus`, `Time.minus`, `Time.floor` and the like (see [Functions in clauses](functions.md#time)). A clause writes a duration with a known count as a literal in the largest units that fit (`1w`, `1d`, `1h30m`):

```roc
# Fragment: uses `Visit` and `visits` from above.
recent : Visit -> Bool
recent = |v| v.seen > Surreal.Time.minus(Surreal.Time.now(), Surreal.Time.days(7))
```

```surql
SELECT VALUE record::id(id) FROM visit WHERE (time::now() - 1w) < seen
```

A `Duration` is not a column type. A field of this type is a `BadSchema`. A clause can read a `Duration` from around the function. Its slot is a duration literal: `LET $_1 = 1h;`.

## Time series keys

A time series is a table whose key has two parts: a series and a time. SurrealDB keeps the rows in key order, so a range of one series is a scan of keys. Write the `id` field as a `Surreal.TimeKey(s)`:

| Part | What to write |
| --- | --- |
| The row type | `Vital : { id : Surreal.TimeKey(Surreal.Id(Kennel)), pulse : I64, temp_c : Dec }` |
| A key | `Surreal.time_key(kennels.id("a"), at)` |
| The series of a key in a clause | `v.id.series()` gives `record::id(id)[0]` |
| The time of a key in a clause | `v.id.time()` gives `record::id(id)[1]` |
| The schema | `DEFINE FIELD OVERWRITE id ON vital TYPE [record<kennel>, datetime];` |

The series is an `Id`, a `Str`, an integer, or a record of them. A record series holds a key of several parts. `TimeKey({ site : Str, sensor : Str })` gives the type `[{ sensor: string, site: string }, datetime]`.

A series must not hold a `Link`. A key has no delete policy. `Surreal.schema` refuses it:

```text
BadSchema("table `bad`: the series of `id` holds a `Link`; a key holds an `Id`, because a key has no delete policy")
```

A create of a reading uses the key as the record id:

```surql
CREATE vital:[kennel:⟨a⟩, d'2026-03-01T08:00:00Z'] CONTENT { pulse: 80, temp_c: 38.5dec } RETURN AFTER;
```

```roc
# Fragment: uses `Vital`, `vitals` and `kennels` from examples/monitoring.roc.
vital_line : Vital -> { kennel : Surreal.Id(Kennel), at : Surreal.Datetime, pulse : I64 }
vital_line = |v| { kennel: v.id.series(), at: v.id.time(), pulse: v.pulse }
```

`vital_line` in `examples/monitoring.roc` also reads `temp_c`. `select(|r| r)` reads the whole key as `record::id(id) AS id`. In Roc, `key.within(series, from, to)` tests a key against a range. [Writing queries](queries.md#read-a-range-of-a-time-series) shows `between`, which reads one range of a series. [Tables and schema](schema.md#views) shows views and [changefeeds](schema.md#changefeeds) over a time series.

## Geometry

Seven types of `Surreal` hold a geometry. `Surreal.Geometry` is the union of the seven.

| Type | Holds | `TYPE` | Make one with |
| --- | --- | --- | --- |
| `Point` | A longitude and a latitude | `geometry<point>` | `Surreal.point(lon, lat)` |
| `Line` | `List(Point)` | `geometry<line>` | `Surreal.Line.(points)` |
| `Polygon` | `{ exterior, holes }` | `geometry<polygon>` | `Surreal.Polygon.({ exterior: .., holes: [] })` |
| `MultiPoint` | `List(Point)` | `geometry<multipoint>` | `Surreal.MultiPoint.(points)` |
| `MultiLine` | `List(Line)` | `geometry<multiline>` | `Surreal.MultiLine.(lines)` |
| `MultiPolygon` | `List(Polygon)` | `geometry<multipolygon>` | `Surreal.MultiPolygon.(polygons)` |
| `Collection` | `List(Geometry)` | `geometry<collection>` | `Surreal.Collection.(items)` |

Give the longitude first, as GeoJSON does. Each field also gets `ASSERT geo::is_valid($value)`, so the server refuses a longitude outside -180 to 180 and a latitude outside -90 to 90. A ring is closed when its last point is its first. SurrealDB closes a ring that is not.

| Call | Type | In a clause |
| --- | --- | --- |
| `p.lon()` | `Point -> F64` | `location.coordinates[0]` |
| `p.lat()` | `Point -> F64` | `location.coordinates[1]` |
| `g.to_geometry()` | `Point`, `Line` and so on `-> Geometry` | The value itself |

Most functions of `Surreal.Geo` take a `Geometry`. Call `to_geometry()` first. See [Functions in clauses](functions.md#geo). A search for the sites that hold a point:

```roc
# Fragment: uses `Site` and `sites` from examples/monitoring.roc.
covering : { here : Surreal.Point }, Site -> Bool
covering = |p, s| Surreal.Geo.inside(p.here.to_geometry(), s.area.to_geometry())
```

The same filter is in `examples/monitoring.roc`, query `sites_covering`. With `.filter_by(covering).select_value(|s| s.id).prepare({ here: Surreal.point(10.5, 59.5) })`:

```surql
LET $here = { type: 'Point', coordinates: [10.5f, 59.5f] };
SELECT VALUE record::id(id) FROM site WHERE $here INSIDE area;
```

A point can be built in a clause: `Surreal.point(10.0, 59.0)` gives `<point> [10f, 59f]`. Any other geometry must come as a parameter. A polygon in a clause gives ``Unsupported("in `filter`: a `Polygon` in a clause has no SurrealQL form; pass a geometry as a parameter with `filter_by` and `prepare`")``.

## The CBOR v2 types

SurrealDB 4 sends each of these values with its own CBOR tag. The package talks CBOR v2 only (see [Sessions](sessions.md)), and reads each tag into one Roc type.

| Roc type | `TYPE` | Tag | Literal |
| --- | --- | --- | --- |
| `I8`, `U8`, `I16`, `U16`, `I32`, `U32`, `U64` | `i8`, `u8` and so on | 180 to 186 | `5u8`, `-128i8`, `18446744073709551615u64` |
| `F32` | `f32` | 188 | `1.5f32`, `<f32>NaN` |
| `Surreal.Date` | `date` | 100 | `<date>'2026-11-13'` |
| `Surreal.TimeOfDay` | `time` | 189 | `<time>'12:30:00.5'` |
| `Surreal.Timestamp` | `timestamp` | 190 | `<timestamp>'2026-11-13T12:30:00.5'` |
| `Surreal.Interval` | `interval` | 191 | `<interval>'P1M-2DT-1.000001S'` |
| `Surreal.BigDecimal` | `bigdecimal` | 192 | `<bigdecimal>'1.000000000000000000000000000001'` |
| `Surreal.Regex` | `regex` | 193 | `<regex>'^[a-z]+$'` |

A read of a sized number into a narrower Roc type that does not hold the value is an error, not a wrap. A `u64` up to 2^64 - 1 reads into a `U64`. Tag 187 (`f16`) reads into an `F32` or an `F64`. Roc has no `F16`, so the schema never writes `f16`.

Make a value with these calls:

| Call | Type | Notes |
| --- | --- | --- |
| `Surreal.date(text)` | `Str -> Try(Date, [BadDate])` | Form `YYYY-MM-DD`, years 0 to 9999 |
| `Surreal.Date.from_days(n)`, `d.to_days()` | `I32 -> Date`, `Date -> I32` | Days since 1970-01-01 |
| `Surreal.TimeOfDay.from_nanos(n)`, `t.to_nanos()` | `U64 -> Try(TimeOfDay, [BadTime])`, `TimeOfDay -> U64` | Nanoseconds since midnight, less than one day |
| `Surreal.Timestamp.from_parts({ secs, nanos })`, `t.to_parts()` | `{ secs : I64, nanos : U32 } -> Try(Timestamp, [BadTimestamp])` | Seconds since 1970-01-01T00:00:00, no time zone. `nanos` is less than 10^9 |
| `Surreal.Interval.from_parts({ months, days, micros })`, `i.to_parts()` | `{ months : I32, days : I32, micros : I64 } -> Interval` | Each part has its own sign |
| `Surreal.BigDecimal.from_str(text)`, `from_dec(d)`, `b.to_str()` | `Str -> Try(BigDecimal, [BadDecimal])` | The text of a JSON number |
| `Surreal.Regex.from_pattern(text)`, `r.pattern()` | `Str -> Regex` | The server checks the pattern when it reads it |

Each type but `Regex` has `to_str`, which gives the text of the literal. Each type has `==`. `Date`, `TimeOfDay` and `Timestamp` also have `<`.

A clause can use a `Date` or a `TimeOfDay` in a comparison. The package compares the days or the nanoseconds:

```surql
SELECT VALUE record::id(id) FROM kinds WHERE (day - <date>'1970-01-01') < 0;
LET $at = <time>'00:00:00.000000001';
SELECT VALUE record::id(id) FROM kinds WHERE duration::nanos(<duration>at) = duration::nanos(<duration>$at);
```

A `Timestamp`, an `Interval`, a `BigDecimal` or a `Regex` in a clause is refused: ``Unsupported("in `filter_by`: a `interval` in a clause has no SurrealQL form for its parts; compare it in Roc after the read")``. Read the rows, then compare in Roc. These types can be fields, parameters and values of a write.

Sized numbers in a clause:

| Case | What the package writes |
| --- | --- |
| A captured `U8` | `LET $_1 = 5u8;` |
| Arithmetic on a sized field, such as `r.stock + p.add` | `<int>stock + <int>$add`, because sized arithmetic fails on overflow and `u64` division gives a decimal |
| `to_str` on a sized field | `<string><decimal>stock`, because `<string>5u8` is `'5u8'` |
| A `LIMIT` or `START` from a parameter | `LIMIT <int>$_2`, because `LIMIT` refuses a `u64` |

The result of arithmetic in a clause is an `int`. A write of it to a field of a `SCHEMALESS` table stores an `int`, not the sized type. A `SCHEMAFULL` field converts it to its type.

A record key is exact about the type: `kt:[5u8, 1]` is not `kt:[5, 1]`. Give a key part the same Roc type in each program that reads or writes the table.

## Limits

| Limit | What to do instead |
| --- | --- |
| A field of a union arm record cannot be named `kind`, because `kind` is the tag | Name the field another way. `Surreal.schema` says ``the arm `A` has a field named `kind`, which tells the arms apart`` |
| `??` on an alias row is a compile error | Use a nominal row, or `.default(..)` in `define()` |
| A `??` that is not a literal is a `BadSchema` | Use `.default_by(..)` |
| A `??` in the record of a union arm is not in the schema. A write from outside the program that leaves the field out is refused | Write the field every time. A write from Roc always has it |
| `I128` and `U128` are refused as field types and as parameter fields | Use `I64`, `U64` or a narrower integer |
| A `Timestamp`, `Interval`, `BigDecimal` or `Regex` in a clause is refused | Compare it in Roc after the read |
| A `Duration` is not a column type | Store a count, and build the duration in the clause with `Time.hours(2)` |
| `Surreal.datetime` takes UTC text with `Z` only | Convert the offset before you call it |
| A clause cannot call `Surreal.datetime` | Pass the datetime as a parameter or a captured value |
| An opaque row (`::`) is refused | Use `:=` or an alias |
| A geometry other than a point is a parameter, not a literal in a clause | Pass it with `filter_by` and `prepare` |
| `CONTAINSALL`, `CONTAINSANY`, `ALLINSIDE` and the other list forms of geometry have no Roc function | Use `Surreal.Unchecked.query!` ([Escape hatches](advanced.md#raw-surrealql)) |
| A `TimeKey` series cannot hold a `Link` | Use an `Id` |
| A `TimeKey` has two parts: the series and the time | Put several series parts in a record series |
| `Id` holds a text key, so `at`, `update_at`, `set_at` and `delete_at` cannot address a time series row | Read a range with `between`. Delete with `edit(Delete(row))` |
| A record update `{ ..r, f: x }` has the type of `r`, so it cannot change the type of a field | Write the row of the other type in full |
