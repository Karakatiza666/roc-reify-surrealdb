import Ql
import Encode
import Types
import Translate
import Schema
import Migrate
import Diff
import Rpc
import HttpRpc
import cbor.Cbor
import ws.Ws

# A SurrealDB ORM over reified Roc functions: rows are ordinary Roc records,
# and every constraint, filter and projection is a Roc function that the
# compiler reifies and the translator reads.
#
# This file has the parts in sections: the foundations (links, ids,
# datetimes and tables), the schema builder, the query API and the live
# queries, each an associated item of `Surreal`. Two namespaces hold what
# an application does not need: `Surreal.Unchecked`, the escape hatch,
# and `Surreal.Mirror`, the Roc model of what the server sends, for the
# checks and the tests. The helpers are module-level definitions after
# the type (see "internals"), which no other module sees.
Surreal :: {}.{

	## What the translator does not look inside (see `cut`): every type
	## below with a method that takes `Code` names this list.
	code_primitives = cut

	# ======================================================== foundations

	## Why a statement is not built or does not run, one type for every
	## call (see `Ql.Error`): `Unsupported` and `BadSchema` when the
	## program builds it, then `Transport`, `Wire`, `Server` and `Decode`
	## when a session runs it.
	Error : Ql.Error

	## Why the server refused a request or a statement, by the kind of its
	## error (see `Ql.ServerError`).
	ServerError : Ql.ServerError

	## A typed record id: `customer:⟨ada⟩`. The type parameter `row` ties the
	## id to its row type: no value holds it, and the type checker keeps an
	## `Id(Customer)` from an `Id(Product)`. The reifier gives it as the
	## type argument of the `Named` (`Types.row_of`), so a captured id holds
	## only its table and key.
	Id(row) := { table : Str, key : Str }.{

		## Equal when the table and the key are equal.
		is_eq : Id(row), Id(row) -> Bool
		is_eq = |Id.(a), Id.(b)| a.table == b.table and a.key == b.key

		## The key, without the table: `record::id(id)` in a clause.
		key : Id(row) -> Str
		key = |Id.(i)| i.key

		## The name of the table: `record::tb(id)` in a clause.
		table : Id(row) -> Str
		table = |Id.(i)| i.table

		encoder_for : Encode.Format -> (Id(row), Encode.State -> Try(Encode.State, []))
		encoder_for = |_format| |Id.(i), state| Encode.Format.encode_id(i.table, i.key, state)

		## A record id from the server: tag 8 and `[table, key]`, with a text key.
		parser_for : Cbor -> (Cbor.Reader -> Try({ value : Id(row), rest : Cbor.Reader }, [InvalidCbor(U64)]))
		parser_for = |encoding| |state| {
			pair : { value : (Str, Str), rest : Cbor.Reader }
			pair = tagged(encoding, state, 8)?
			Ok({ value: Id.({ table: pair.value.0, key: pair.value.1 }), rest: pair.rest })
		}
	}

	## A row that `Table.create_new` or `Table.insert_new` made, with the
	## key that the server gave it: its `Id`, and its other fields as
	## stored. `new` is the row without its `id`, so a `Created(Customer,
	## { name : Str })` reads `made.id.key()` and `made.fields.name`, and
	## `customers.link(made.id.key())` links to it.
	Created(row, new) : { id : Id(row), fields : new }

	## A stored link. `fetched` holds the row when the application has it (seed
	## data, a row read back). In a clause, `get` is a traversal: `customer.name`.
	Link(row) := { id : Id(row), fetched : [Fetched(row), NotFetched] }.{

		## The row. A link that was not fetched has none, and this crashes: the
		## row lives in the database, so only a clause can read through it.
		get : Link(row) -> row
		get = |Link.(l)| match l.fetched {
			Fetched(r) => r
			NotFetched => crash "this link was not fetched"
		}

		## The record id the link holds: the id itself in a clause. In a clause
		## the field `link.id` is the same. The field `fetched` has no meaning
		## in the database, so a clause that reads it is refused.
		id : Link(row) -> Id(row)
		id = |Link.(l)| l.id

		## Equal when the ids are equal.
		is_eq : Link(row), Link(row) -> Bool
		is_eq = |a, b| a.id() == b.id()

		encoder_for : Encode.Format -> (Link(row), Encode.State -> Try(Encode.State, []))
		encoder_for = |_format| |Link.(l), state| {
			Id.(i) = l.id
			Encode.Format.encode_id(i.table, i.key, state)
		}

		## A link from the server: its record id. The row is not fetched.
		parser_for : Cbor -> (Cbor.Reader -> Try({ value : Link(row), rest : Cbor.Reader }, [InvalidCbor(U64)]))
		parser_for = |encoding| |state| {
			read = Id.parser_for(encoding)(state)?
			Ok({ value: Link.({ id: read.value, fetched: NotFetched }), rest: read.rest })
		}
	}

	## A read view of a link: the linked row, read as a field of this row,
	## so `p.owner.name` is the traversal `owner.name` with no `.get()`. It
	## is for reads only. A row that holds one has no encoder, so a write of
	## it is a type error, and the stored row of its table holds a `Link`
	## at the same place (`Table.define_read` checks it). The linked row is
	## an alias of a record or a nominal over one, also a row that links to
	## its own table (`Linked(Owner)` with `referred_by ?: Link(Owner)`), or a
	## read row. It finds its table by its row, the type argument, as a `Link`.
	Linked(row) := { ..row }.{
		parser_for : _
	}

	## A `Linked` that holds its row: a Roc value of a read view.
	linked : { ..row } -> Linked(row)
	linked = |row| Linked.(row)

	## The edges that leave the row, in a field of a read view that has the
	## name of the edge table: `treats : Surreal.Out(Treats)` is `->treats`.
	## It is not stored, and `Table.define_read` checks that the edge table
	## starts at this table.
	Out(edge) := List(edge).{
		parser_for : _

		## The edges: `v.treats.list().len()` is `->treats.len()`.
		list : Out(edge) -> List(edge)
		list = |Out.(edges)| edges
	}

	## The edges that end at the row, in a field of a read view that has the
	## name of the edge table: `treats : Surreal.In(Treats)` is `<-treats`.
	## `Table.define_read` checks that the edge table ends at this table.
	In(edge) := List(edge).{
		parser_for : _

		## The edges: `p.treats.list().len()` is `<-treats.len()`.
		list : In(edge) -> List(edge)
		list = |In.(edges)| edges
	}

	## An `Out` that holds its edges: a Roc value of a read view.
	out_edges : List(edge) -> Out(edge)
	out_edges = |edges| Out.(edges)

	## An `In` that holds its edges.
	in_edges : List(edge) -> In(edge)
	in_edges = |edges| In.(edges)

	## A SurrealDB `datetime`, held as UTC ISO 8601 with a `Z`
	## (`2026-10-28T04:53:59Z`). A fraction has no trailing zeros, so equal
	## times are equal strings. Make one with `datetime`.
	Datetime := { iso : Str }.{
		is_eq : _

		## Earlier. The order is the order of the text without its `Z`: with
		## the `Z` kept, `...59Z` would sort after `...59.5Z`.
		is_lt : Datetime, Datetime -> Bool
		is_lt = |Datetime.(a), Datetime.(b)| bytes_lt(a.iso.drop_suffix("Z").to_utf8(), b.iso.drop_suffix("Z").to_utf8())

		is_lte : Datetime, Datetime -> Bool
		is_lte = |a, b| a == b or Datetime.is_lt(a, b)

		is_gt : Datetime, Datetime -> Bool
		is_gt = |a, b| Datetime.is_lt(b, a)

		is_gte : Datetime, Datetime -> Bool
		is_gte = |a, b| Datetime.is_lte(b, a)

		## Nanoseconds since 1970-01-01T00:00:00Z, as `time::nano` counts them. `I128` holds all years.
		to_unix_nanos : Datetime -> I128
		to_unix_nanos = |at| {
			part = |value| value.to_i128()
			days = days_from_civil(part(Surreal.Time.year(at)), part(Surreal.Time.month(at)), part(Surreal.Time.day(at)))
			seconds = ((days * 24 + part(Surreal.Time.hour(at))) * 60 + part(Surreal.Time.minute(at))) * 60 + part(Surreal.Time.second(at))
			seconds * 1000000000 + fraction_nanos(at)
		}

		## The datetime at this many nanoseconds since 1970. A year outside 0 to 9999 is refused.
		from_unix_nanos : I128 -> Try(Datetime, [BadDatetime])
		from_unix_nanos = |nanos| {
			seconds = nanos.div_floor_by(1000000000)
			rest = nanos.mod_by(1000000000)
			day_seconds = seconds.mod_by(86400)
			(year, month, day) = civil_from_days(seconds.div_floor_by(86400))
			if year < 0 or year > 9999 {
				Err(BadDatetime)
			} else {
				fraction = if (rest == 0) "" else ".${pad(rest, 9)}"
				clock = "${pad(day_seconds // 3600, 2)}:${pad(day_seconds % 3600 // 60, 2)}:${pad(day_seconds % 60, 2)}"
				Surreal.datetime("${pad(year, 4)}-${pad(month, 2)}-${pad(day, 2)}T${clock}${fraction}Z")
			}
		}

		encoder_for : Encode.Format -> (Datetime, Encode.State -> Try(Encode.State, []))
		encoder_for = |_format| |Datetime.(d), state| Encode.Format.encode_datetime(d.iso, state)

		## A datetime from the server: tag 12 and `[seconds, nanoseconds]`
		## since 1970. The nanoseconds are left out when they are 0.
		parser_for : Cbor -> (Cbor.Reader -> Try({ value : Datetime, rest : Cbor.Reader }, [InvalidCbor(U64)]))
		parser_for = |encoding| |state| {
			parts : { value : List(I64), rest : Cbor.Reader }
			parts = tagged(encoding, state, 12)?
			match datetime_of(parts.value) {
				Ok(at) => Ok({ value: at, rest: parts.rest })
				Err(_) => Err(Cbor.invalid_value(encoding, state))
			}
		}
	}

	## A datetime from `YYYY-MM-DDTHH:MM:SS`, an optional fraction of up to
	## nine digits, and `Z`. Other offsets are refused: the order of the text
	## is the order of the time only in UTC.
	datetime : Str -> Try(Datetime, [BadDatetime])
	datetime = |text| {
		bytes = text.to_utf8()
		match bytes {
			[y1, y2, y3, y4, 45, m1, m2, 45, d1, d2, 84, h1, h2, 58, n1, n2, 58, s1, s2, .. as rest] => {
				number = |digits| digits.fold(0.U64, |acc, b| acc * 10 + (b - 48).to_u64())
				is_digits = |digits| digits.all(|b| b >= 48 and b <= 57)
				year = number([y1, y2, y3, y4])
				month = number([m1, m2])
				day = number([d1, d2])
				fraction = match rest {
					[90] => Ok([])
					[46, .. as more] => match more.last() {
						Ok(90) => if (more.len() > 1) Ok(more.drop_last(1)) else Err(BadDatetime)
						_ => Err(BadDatetime)
					}
					_ => Err(BadDatetime)
				}
				digits_ok = is_digits([y1, y2, y3, y4, m1, m2, d1, d2, h1, h2, n1, n2, s1, s2])
				in_range = month >= 1 and month <= 12 and day >= 1 and day <= days_in_month(year, month) and number([h1, h2]) < 24 and number([n1, n2]) < 60 and number([s1, s2]) < 60
				match fraction {
					Ok(frac) =>
						if digits_ok and is_digits(frac) and frac.len() <= 9 and in_range {
							kept = drop_zeros(frac)
							whole = bytes.take_first(19)
							iso = if (kept.is_empty()) whole.append(90) else whole.append(46).concat(kept).append(90)
							match Str.from_utf8(iso) {
								Ok(s) => Ok(Datetime.({ iso: s }))
								Err(_) => crash "ASCII digits and punctuation are valid UTF-8"
							}
						} else {
							Err(BadDatetime)
						}
					Err(_) => Err(BadDatetime)
				}
			}
			_ => Err(BadDatetime)
		}
	}

	## The key of a reading in a time series: `table:[series, time]`. The
	## series is an `Id`, a `Str`, an integer, or a record of them for a key
	## of several parts: `TimeKey({ site : Str, sensor : Str })` is
	## `table:[{ sensor: .., site: .. }, time]`. A table whose `id` is a
	## `TimeKey` is a time series, and `Query.between` reads one range of it.
	TimeKey(s) := { series : s, time : Datetime }.{

		## The series: `record::id(id)[0]` in a clause.
		series : TimeKey(s) -> s
		series = |TimeKey.(k)| k.series

		## The time: `record::id(id)[1]` in a clause.
		time : TimeKey(s) -> Datetime
		time = |TimeKey.(k)| k.time

		## Whether the key is in `between(series, from, to)`: the series is
		## equal, and `from <= time < to`. For a reference result in Roc.
		within : TimeKey(s), s, Datetime, Datetime -> Bool where [s.is_eq : s, s -> Bool]
		within = |TimeKey.(k), wanted, from, to| k.series == wanted and from <= k.time and k.time < to

		## The array `[series, time]`.
		encoder_for : Encode.Format -> (TimeKey(s), Encode.State -> Try(Encode.State, [])) where [s.encoder_for : Encode.Format -> (s, Encode.State -> Try(Encode.State, []))]
		encoder_for = |format| |TimeKey.(k), state| {
			Series : s
			write_series = Series.encoder_for(format)
			write_time = Datetime.encoder_for(format)
			Encode.Format.encode_list(
				state,
				2,
				|acc, item| {
					next = item(acc, |st| write_series(k.series, st))?
					item(next, |st| write_time(k.time, st))
				},
			)
		}

		## The array `[series, time]` from the server, as `record::id(id)`
		## gives it.
		parser_for : Cbor -> (Cbor.Reader -> Try({ value : TimeKey(s), rest : Cbor.Reader }, [InvalidCbor(U64), ..errs])) where [s.Cbor.Parseable([InvalidCbor(U64), ..errs])]
		parser_for = |encoding| |state| {
			start = Cbor.parse_tuple_start(encoding, state, 2)?
			first : { value : s, rest : Cbor.Reader }
			first = Cbor.parse_item(encoding, start)?
			second = Datetime.parser_for(encoding)(first.rest)?
			Ok({ value: TimeKey.({ series: first.value, time: second.value }), rest: second.rest })
		}
	}

	## The key of the reading of `series` at `time`.
	time_key : s, Datetime -> TimeKey(s)
	time_key = |series, time| TimeKey.({ series, time })

	# ============================================================ geometry

	## A point on the earth: a longitude and a latitude in degrees, the
	## longitude first as in GeoJSON. A field of this type is
	## `geometry<point>`. Make one with `point`.
	Point := { lon : F64, lat : F64 }.{
		is_eq : _

		## The longitude: `field.coordinates[0]` in a clause.
		lon : Point -> F64
		lon = |Point.(p)| p.lon

		## The latitude: `field.coordinates[1]` in a clause.
		lat : Point -> F64
		lat = |Point.(p)| p.lat

		to_geometry : Point -> Geometry
		to_geometry = |p| Geometry.Point(p)

		encoder_for : Encode.Format -> (Point, Encode.State -> Try(Encode.State, []))
		encoder_for = |_format| |p, state| Encode.Format.encode_geometry(geojson(Geometry.Point(p)), state)

		## A point from the server: tag 88 and `[lon, lat]`.
		parser_for : Cbor -> (Cbor.Reader -> Try({ value : Point, rest : Cbor.Reader }, [InvalidCbor(U64)]))
		parser_for = |encoding| |state| {
			pair : { value : (F64, F64), rest : Cbor.Reader }
			pair = tagged(encoding, state, 88)?
			Ok({ value: Point.({ lon: pair.value.0, lat: pair.value.1 }), rest: pair.rest })
		}
	}

	## A line through the points: `geometry<line>`.
	Line := List(Point).{
		is_eq : _

		to_geometry : Line -> Geometry
		to_geometry = |l| Geometry.Line(l)

		encoder_for : Encode.Format -> (Line, Encode.State -> Try(Encode.State, []))
		encoder_for = |_format| |l, state| Encode.Format.encode_geometry(geojson(Geometry.Line(l)), state)

		## Tag 89 and the points, each a tag 88.
		parser_for : Cbor -> (Cbor.Reader -> Try({ value : Line, rest : Cbor.Reader }, [InvalidCbor(U64)]))
		parser_for = |encoding| |state| {
			points : { value : List(Point), rest : Cbor.Reader }
			points = tagged(encoding, state, 89)?
			Ok({ value: Line.(points.value), rest: points.rest })
		}
	}

	## An area: the outer ring, and a ring for each hole. A ring is closed
	## when its last point is its first: SurrealDB closes a ring that is not.
	## `geometry<polygon>`.
	Polygon := { exterior : List(Point), holes : List(List(Point)) }.{
		is_eq : _

		to_geometry : Polygon -> Geometry
		to_geometry = |p| Geometry.Polygon(p)

		encoder_for : Encode.Format -> (Polygon, Encode.State -> Try(Encode.State, []))
		encoder_for = |_format| |p, state| Encode.Format.encode_geometry(geojson(Geometry.Polygon(p)), state)

		## Tag 90 and the rings, each a line (tag 89): the outer ring first.
		parser_for : Cbor -> (Cbor.Reader -> Try({ value : Polygon, rest : Cbor.Reader }, [InvalidCbor(U64)]))
		parser_for = |encoding| |state| {
			rings : { value : List(Line), rest : Cbor.Reader }
			rings = tagged(encoding, state, 90)?
			match rings.value {
				[Line.(exterior), .. as holes] => Ok({ value: Polygon.({ exterior, holes: holes.map(|Line.(points)| points) }), rest: rings.rest })
				[] => Err(Cbor.invalid_value(encoding, state))
			}
		}
	}

	## `geometry<multipoint>`.
	MultiPoint := List(Point).{
		is_eq : _

		to_geometry : MultiPoint -> Geometry
		to_geometry = |m| Geometry.MultiPoint(m)

		encoder_for : Encode.Format -> (MultiPoint, Encode.State -> Try(Encode.State, []))
		encoder_for = |_format| |m, state| Encode.Format.encode_geometry(geojson(Geometry.MultiPoint(m)), state)

		## Tag 91 and the points.
		parser_for : Cbor -> (Cbor.Reader -> Try({ value : MultiPoint, rest : Cbor.Reader }, [InvalidCbor(U64)]))
		parser_for = |encoding| |state| {
			points : { value : List(Point), rest : Cbor.Reader }
			points = tagged(encoding, state, 91)?
			Ok({ value: MultiPoint.(points.value), rest: points.rest })
		}
	}

	## `geometry<multiline>`.
	MultiLine := List(Line).{
		is_eq : _

		to_geometry : MultiLine -> Geometry
		to_geometry = |m| Geometry.MultiLine(m)

		encoder_for : Encode.Format -> (MultiLine, Encode.State -> Try(Encode.State, []))
		encoder_for = |_format| |m, state| Encode.Format.encode_geometry(geojson(Geometry.MultiLine(m)), state)

		## Tag 92 and the lines.
		parser_for : Cbor -> (Cbor.Reader -> Try({ value : MultiLine, rest : Cbor.Reader }, [InvalidCbor(U64)]))
		parser_for = |encoding| |state| {
			lines : { value : List(Line), rest : Cbor.Reader }
			lines = tagged(encoding, state, 92)?
			Ok({ value: MultiLine.(lines.value), rest: lines.rest })
		}
	}

	## `geometry<multipolygon>`.
	MultiPolygon := List(Polygon).{
		is_eq : _

		to_geometry : MultiPolygon -> Geometry
		to_geometry = |m| Geometry.MultiPolygon(m)

		encoder_for : Encode.Format -> (MultiPolygon, Encode.State -> Try(Encode.State, []))
		encoder_for = |_format| |m, state| Encode.Format.encode_geometry(geojson(Geometry.MultiPolygon(m)), state)

		## Tag 93 and the polygons.
		parser_for : Cbor -> (Cbor.Reader -> Try({ value : MultiPolygon, rest : Cbor.Reader }, [InvalidCbor(U64)]))
		parser_for = |encoding| |state| {
			polygons : { value : List(Polygon), rest : Cbor.Reader }
			polygons = tagged(encoding, state, 93)?
			Ok({ value: MultiPolygon.(polygons.value), rest: polygons.rest })
		}
	}

	## Geometries of any kind: `geometry<collection>`.
	Collection := List(Geometry).{
		is_eq : _

		to_geometry : Collection -> Geometry
		to_geometry = |c| Geometry.Collection(c)

		encoder_for : Encode.Format -> (Collection, Encode.State -> Try(Encode.State, []))
		encoder_for = |_format| |c, state| Encode.Format.encode_geometry(geojson(Geometry.Collection(c)), state)

		## Tag 94 and the geometries.
		parser_for : Cbor -> (Cbor.Reader -> Try({ value : Collection, rest : Cbor.Reader }, [InvalidCbor(U64)]))
		parser_for = |encoding| |state| {
			items : { value : List(Geometry), rest : Cbor.Reader }
			items = tagged(encoding, state, 94)?
			Ok({ value: Collection.(items.value), rest: items.rest })
		}
	}

	## A geometry of any kind: `geometry`. The functions of `Geo` take one.
	## `to_geometry()` makes one of each kind, and is the value itself in a
	## clause.
	Geometry := [Point(Point), Line(Line), Polygon(Polygon), MultiPoint(MultiPoint), MultiLine(MultiLine), MultiPolygon(MultiPolygon), Collection(Collection)].{
		is_eq : _

		encoder_for : Encode.Format -> (Geometry, Encode.State -> Try(Encode.State, []))
		encoder_for = |_format| |g, state| Encode.Format.encode_geometry(geojson(g), state)

		## The kind of the geometry is its tag: 88 to 94.
		parser_for : Cbor -> (Cbor.Reader -> Try({ value : Geometry, rest : Cbor.Reader }, [InvalidCbor(U64)]))
		parser_for = |encoding| |state| match Cbor.peek(encoding, state)? {
			Tag(88) => Point.parser_for(encoding)(state).map_ok(|r| { value: Geometry.Point(r.value), rest: r.rest })
			Tag(89) => Line.parser_for(encoding)(state).map_ok(|r| { value: Geometry.Line(r.value), rest: r.rest })
			Tag(90) => Polygon.parser_for(encoding)(state).map_ok(|r| { value: Geometry.Polygon(r.value), rest: r.rest })
			Tag(91) => MultiPoint.parser_for(encoding)(state).map_ok(|r| { value: Geometry.MultiPoint(r.value), rest: r.rest })
			Tag(92) => MultiLine.parser_for(encoding)(state).map_ok(|r| { value: Geometry.MultiLine(r.value), rest: r.rest })
			Tag(93) => MultiPolygon.parser_for(encoding)(state).map_ok(|r| { value: Geometry.MultiPolygon(r.value), rest: r.rest })
			Tag(94) => Collection.parser_for(encoding)(state).map_ok(|r| { value: Geometry.Collection(r.value), rest: r.rest })
			_ => Err(Cbor.invalid_value(encoding, state))
		}
	}

	## The point at a longitude and a latitude, in that order, as in GeoJSON.
	## In a clause it is `<point> [lon, lat]`.
	point : F64, F64 -> Point
	point = |lon, lat| Point.({ lon, lat })

	# ============================================== functions of the database

	## A length of time, as SurrealDB's `duration`. Make one with the functions
	## of `Time`, such as `Time.hours`. It cannot be a column or a captured value.
	Duration := { nanos : U64 }.{
		is_eq : _

		## A duration from the server: tag 14 and `[seconds, nanoseconds]`.
		## The nanoseconds are left out when they are 0, and both when the
		## duration is 0.
		parser_for : Cbor -> (Cbor.Reader -> Try({ value : Duration, rest : Cbor.Reader }, [InvalidCbor(U64)]))
		parser_for = |encoding| |state| {
			parts : { value : List(U64), rest : Cbor.Reader }
			parts = tagged(encoding, state, 14)?
			nanos = match parts.value {
				[] => Ok(0)
				[secs] => Ok(secs * 1000000000)
				[secs, rest] if rest < 1000000000 => Ok(secs * 1000000000 + rest)
				_ => Err(Cbor.invalid_value(encoding, state))
			}?
			Ok({ value: Duration.({ nanos: nanos }), rest: parts.rest })
		}
	}

	## The `string::` functions that Roc has no builtin for. A function with no
	## body is an intrinsic: SurrealDB computes it, so it exists only in a clause,
	## and a call in code that runs is a compile error.
	Text :: {}.{

		## `string::is_email`. An intrinsic: SurrealDB computes it.
		is_email : Str -> Bool

		## `string::is_url`. An intrinsic: SurrealDB computes it.
		is_url : Str -> Bool

		## `string::is_domain`. An intrinsic: SurrealDB computes it.
		is_domain : Str -> Bool

		## `string::is_ip`. An intrinsic: SurrealDB computes it.
		is_ip : Str -> Bool

		## `string::is_ipv4`. An intrinsic: SurrealDB computes it.
		is_ipv4 : Str -> Bool

		## `string::is_ipv6`. An intrinsic: SurrealDB computes it.
		is_ipv6 : Str -> Bool

		## `string::is_uuid`. An intrinsic: SurrealDB computes it.
		is_uuid : Str -> Bool

		## `string::is_ulid`. An intrinsic: SurrealDB computes it.
		is_ulid : Str -> Bool

		## `string::is_semver`. An intrinsic: SurrealDB computes it.
		is_semver : Str -> Bool

		## `string::is_alpha`. It is Unicode: `abé` is true. An intrinsic: SurrealDB computes it.
		is_alpha : Str -> Bool

		## `string::is_alphanum`. It is Unicode. An intrinsic: SurrealDB computes it.
		is_alphanum : Str -> Bool

		## `string::is_numeric`. It is Unicode: Arabic digits are true. An intrinsic: SurrealDB computes it.
		is_numeric : Str -> Bool

		## `string::is_latitude`, for a text such as `45.5`. An intrinsic: SurrealDB computes it.
		is_latitude : Str -> Bool

		## `string::is_longitude`, for a text such as `45.5`. An intrinsic: SurrealDB computes it.
		is_longitude : Str -> Bool

		## `string::is_datetime`: the text read with a `strftime` pattern. An intrinsic: SurrealDB computes it.
		is_datetime : Str, Str -> Bool

		## `string::matches`: the pattern is Rust regex syntax. An intrinsic: SurrealDB computes it.
		matches : Str, Str -> Bool

		## `string::similarity::jaro`. An intrinsic: SurrealDB computes it.
		similarity_jaro : Str, Str -> F64

		## `string::similarity::jaro_winkler`. An intrinsic: SurrealDB computes it.
		similarity_jaro_winkler : Str, Str -> F64

		## `string::distance::levenshtein`: edits counted in characters. An intrinsic: SurrealDB computes it.
		distance_levenshtein : Str, Str -> I64

		## `string::distance::damerau_levenshtein`. An intrinsic: SurrealDB computes it.
		distance_damerau_levenshtein : Str, Str -> I64

		## `string::distance::normalized_levenshtein`: a similarity, 1 for equal texts. An intrinsic: SurrealDB computes it.
		distance_normalized_levenshtein : Str, Str -> F64

		## `string::is_ascii`: not empty, and every byte is below 128.
		is_ascii : Str -> Bool
		is_ascii = |text| {
			bytes = text.to_utf8()
			!bytes.is_empty() and bytes.all(|b| b < 128)
		}

		## `string::is_hexadecimal`: not empty, and every byte is `0-9`, `a-f` or `A-F`.
		is_hexadecimal : Str -> Bool
		is_hexadecimal = |text| {
			bytes = text.to_utf8()
			!bytes.is_empty() and bytes.all(|b| (b >= 48 and b <= 57) or (b >= 97 and b <= 102) or (b >= 65 and b <= 70))
		}
	}

	## The `crypto::` hashes, as lower-case hex text.
	Hash :: {}.{

		## `crypto::sha256`.
		sha256 : Str -> Str
		sha256 = |text| Crypto.SHA256.hash(text.to_utf8()).to_hex()

		## `crypto::blake3`.
		blake3 : Str -> Str
		blake3 = |text| Crypto.BLAKE3.hash(text.to_utf8()).to_hex()

		## `crypto::md5`. An intrinsic: SurrealDB computes it.
		md5 : Str -> Str

		## `crypto::sha1`. An intrinsic: SurrealDB computes it.
		sha1 : Str -> Str

		## `crypto::sha512`. An intrinsic: SurrealDB computes it.
		sha512 : Str -> Str

		## `crypto::argon2::generate`: the hash of a password, with a new
		## salt on every call, so it follows the rule of `Rand`: a
		## signup (`Access.define`), a default, a computed field or an
		## update. An intrinsic: SurrealDB computes it.
		argon2 : Str -> Str

		## `crypto::argon2::compare(hash, password)`: whether the password
		## gives the hash, as a `SIGNIN` checks it. An intrinsic: SurrealDB computes it.
		argon2_matches : Str, Str -> Bool
	}

	## The values of the session that a statement runs in, which a clause
	## reads: a table permission (`Def.permit`), a query that a record
	## user runs. The record user is `Table.auth`. Intrinsics: SurrealDB
	## computes them, as a clause reads them on the server, and Roc does
	## not know them.
	Auth :: {}.{

		## `$access`: the name of the access method that the session
		## signed in with, `NONE` for a system user.
		access : () -> Str

		## `$token.exp`: when the token of the session expires, in seconds
		## since 1970.
		expires : () -> I64
	}

	## The `array::` functions on a list of values.
	Array :: {}.{

		## `array::distinct`: each value once, in the order of its first place.
		distinct : List(a) -> List(a) where [a.is_eq : a, a -> Bool]
		distinct = |items| items.fold([], |seen, item| if (seen.contains(item)) seen else seen.append(item))

		## `array::union`: the distinct values of both lists.
		union : List(a), List(a) -> List(a) where [a.is_eq : a, a -> Bool]
		union = |a, b| Array.distinct(a.concat(b))

		## `array::intersect`: the distinct values of the first list that the second has.
		intersect : List(a), List(a) -> List(a) where [a.is_eq : a, a -> Bool]
		intersect = |a, b| Array.distinct(a).keep_if(|item| b.contains(item))

		## `array::complement`: the values of the first list that the second has not. It is not `array::difference`.
		complement : List(a), List(a) -> List(a) where [a.is_eq : a, a -> Bool]
		complement = |a, b| a.keep_if(|item| !b.contains(item))
	}

	## The `time::` functions, and the constructors of `Duration`. Every part of a
	## time is read in UTC, as the library keeps every `Datetime`.
	Time :: {}.{

		## A `Duration` of this many nanoseconds.
		nanos : U64 -> Duration
		nanos = |n| Duration.({ nanos: n })

		micros : U64 -> Duration
		micros = |n| Duration.({ nanos: n * 1000 })

		millis : U64 -> Duration
		millis = |n| Duration.({ nanos: n * 1000000 })

		secs : U64 -> Duration
		secs = |n| Duration.({ nanos: n * 1000000000 })

		mins : U64 -> Duration
		mins = |n| Duration.({ nanos: n * 60000000000 })

		hours : U64 -> Duration
		hours = |n| Duration.({ nanos: n * 3600000000000 })

		days : U64 -> Duration
		days = |n| Duration.({ nanos: n * 86400000000000 })

		weeks : U64 -> Duration
		weeks = |n| Duration.({ nanos: n * 604800000000000 })

		## `time::now`. It differs on each call, so a clause must not compare it to itself. An intrinsic: SurrealDB computes it.
		now : () -> Datetime

		## `time::floor`: the start of the span that holds the time. Spans count
		## from 1970-01-01T00:00:00Z, so a week starts on a Thursday.
		floor : Datetime, Duration -> Datetime
		floor = |at, span| Time.bucket(at, span, |past, _| -past)

		## `time::ceil`: the end of the span that holds the time. A time on a
		## boundary stays.
		ceil : Datetime, Duration -> Datetime
		ceil = |at, span| Time.bucket(at, span, |past, size| if (past == 0) 0 else size - past)

		## `time::round`: the nearest span boundary. A half goes up, also before 1970.
		round : Datetime, Duration -> Datetime
		round = |at, span| Time.bucket(at, span, |past, size| if (past * 2 >= size) size - past else -past)

		## The time moved by `step`, which gets the nanoseconds since the last span
		## boundary and the span, and gives the move. A span of zero keeps the
		## time. SurrealDB refuses a time outside the nanoseconds of an `I64`
		## (1677-09-21T00:12:43.145224192Z to 2262-04-11T23:47:16.854775807Z) and
		## a span above `I64.highest` nanoseconds, so these stop the program.
		bucket : Datetime, Duration, (I128, I128 -> I128) -> Datetime
		bucket = |at, Duration.(d), step| {
			since = at.to_unix_nanos()
			size = d.nanos.to_i128()
			if since < I64.lowest.to_i128() or since > I64.highest.to_i128() or size > I64.highest.to_i128() {
				crash "SurrealDB refuses this time function: the time is outside 1677-09-21 to 2262-04-11, or the span is above I64.highest nanoseconds"
			}
			if size == 0 {
				at
			} else {
				match Datetime.from_unix_nanos(since + step(since.mod_by(size), size)) {
					Ok(moved) => moved
					Err(_) => crash "a time from 1677 to 2262 moved by less than 293 years is inside the years 0 to 9999"
				}
			}
		}

		## `time::group`: the start of the unit that holds the time. An intrinsic: SurrealDB computes it.
		group : Datetime, [Year, Month, Day, Hour, Minute, Second] -> Datetime

		## The time `duration` later: `datetime + duration`. An intrinsic: SurrealDB computes it.
		plus : Datetime, Duration -> Datetime

		## The time `duration` earlier: `datetime - duration`. An intrinsic: SurrealDB computes it.
		minus : Datetime, Duration -> Datetime

		## `time::wday`: Monday is 1 and Sunday is 7. An intrinsic: SurrealDB computes it.
		wday : Datetime -> I64

		## `time::yday`: 1 for the first of January. An intrinsic: SurrealDB computes it.
		yday : Datetime -> I64

		## `time::week`: the week of the year. An intrinsic: SurrealDB computes it.
		week : Datetime -> I64

		## `time::unix`: whole seconds since 1970. An intrinsic: SurrealDB computes it.
		unix : Datetime -> I64

		## `time::millis`: whole milliseconds since 1970. It is not `millis`, which makes a `Duration`. An intrinsic: SurrealDB computes it.
		unix_millis : Datetime -> I64

		## `time::micros`: whole microseconds since 1970. It is not `micros`, which makes a `Duration`. An intrinsic: SurrealDB computes it.
		unix_micros : Datetime -> I64

		## `time::nano`: whole nanoseconds since 1970. An intrinsic: SurrealDB computes it.
		nano : Datetime -> I64

		## `time::format`: the time written with a `strftime` pattern. An intrinsic: SurrealDB computes it.
		format : Datetime, Str -> Str

		## `time::from_unix`: the time at this many seconds since 1970. An intrinsic: SurrealDB computes it.
		from_unix : I64 -> Datetime

		## `time::year`.
		year : Datetime -> I64
		year = |at| Time.digits(at, 0, 4)

		## `time::month`: 1 to 12.
		month : Datetime -> I64
		month = |at| Time.digits(at, 5, 2)

		## `time::day`: 1 to 31.
		day : Datetime -> I64
		day = |at| Time.digits(at, 8, 2)

		## `time::hour`: 0 to 23.
		hour : Datetime -> I64
		hour = |at| Time.digits(at, 11, 2)

		## `time::minute`: 0 to 59.
		minute : Datetime -> I64
		minute = |at| Time.digits(at, 14, 2)

		## `time::second`: 0 to 59, without the fraction.
		second : Datetime -> I64
		second = |at| Time.digits(at, 17, 2)

		## The number in `count` digits of the text of a datetime, from byte `start`.
		digits : Datetime, U64, U64 -> I64
		digits = |Datetime.(d), start, count| d.iso.to_utf8().drop_first(start).take_first(count).fold(0, |acc, b| acc * 10 + (b - 48).to_i64())
	}

	## The `math::` statistics on a list of floats. Convert an `I64` field with `to_f64()`.
	Math :: {}.{

		## `math::mean`. A list with no value has no mean: the result is not a number.
		mean : List(F64) -> F64
		mean = |values| values.sum() / values.len().to_f64()

		## `math::mean` of decimals, as a float: the mean of `v.to_f64()` of each
		## value, as `mean` has it. SurrealDB gives a decimal mean of decimals with 28
		## digits, which a `Dec` of 18 digits cannot hold, so the values go to
		## floats first. A list with no value has no mean: the result is `NaN`, which a
		## `Dec` cannot be.
		mean_dec : List(Dec) -> F64
		mean_dec = |values| Math.mean(values.map(|v| v.to_f64()))

		## `math::median`. An intrinsic: SurrealDB computes it.
		median : List(F64) -> F64

		## `math::stddev`: the sample deviation. An intrinsic: SurrealDB computes it.
		stddev : List(F64) -> F64

		## `math::variance`: the sample variance. An intrinsic: SurrealDB computes it.
		variance : List(F64) -> F64

		## `math::percentile`: a value of the list, with the percentage 0 to 100, interpolated. An intrinsic: SurrealDB computes it.
		percentile : List(F64), F64 -> F64
	}

	## The `rand::` functions. Each gives a new value on every call, so a clause
	## may use them only in a default, a computed field or an update. Intrinsics:
	## SurrealDB computes them.
	Rand :: {}.{

		## `rand::uuid`, as text.
		uuid : () -> Str

		## `rand::ulid`: 26 characters that sort by time.
		ulid : () -> Str

		## `rand::int`: a whole number from the first to the second, both included.
		int : I64, I64 -> I64
	}

	## The `geo::` functions, and the operators of SurrealDB on geometries.
	## Give a kind other than `Geometry` with `to_geometry()`.
	Geo :: {}.{

		## `geo::area`: the area on the earth in square metres. An intrinsic: SurrealDB computes it.
		area : Geometry -> F64

		## `geo::bearing`: the direction from the first point to the second, in degrees. An intrinsic: SurrealDB computes it.
		bearing : Point, Point -> F64

		## `geo::centroid`: the centre of the geometry. An intrinsic: SurrealDB computes it.
		centroid : Geometry -> Point

		## `geo::distance`: the distance on the earth in metres. An intrinsic: SurrealDB computes it.
		distance : Point, Point -> F64

		## `geo::hash::encode`: the geohash of the point in 1 to 12 characters.
		## SurrealDB refuses another length with an error. An intrinsic: SurrealDB computes it.
		hash_encode : Point, U8 -> Str

		## `geo::hash::decode`: the centre of the cell of a geohash. An intrinsic: SurrealDB computes it.
		hash_decode : Str -> Point

		## `geo::is_valid`: every longitude is from -180 to 180 and every
		## latitude from -90 to 90. A NaN is not. SurrealDB stores a point out
		## of range, so a field of a geometry type asserts this.
		is_valid : Geometry -> Bool
		is_valid = |geometry| points_of(geometry).all(|Point.(p)| p.lon >= -180 and p.lon <= 180 and p.lat >= -90 and p.lat <= 90)

		## `a CONTAINS b`: the first geometry holds the second. An intrinsic: SurrealDB computes it.
		contains : Geometry, Geometry -> Bool

		## `a INSIDE b`: the second geometry holds the first. An intrinsic: SurrealDB computes it.
		inside : Geometry, Geometry -> Bool

		## `a OUTSIDE b`: the geometries have no point in common. An intrinsic: SurrealDB computes it.
		outside : Geometry, Geometry -> Bool

		## `a INTERSECTS b`: the geometries have a point in common. An intrinsic: SurrealDB computes it.
		intersects : Geometry, Geometry -> Bool
	}

	## A tokenizer of an analyzer. `Blank` splits a text at white space,
	## `Class` where the class of a character changes (a letter, a digit,
	## white space, anything else), `Camel` before an upper-case letter
	## that follows a lower-case one, and `Punct` at punctuation, which
	## it keeps as tokens.
	Tokenizer : [Blank, Class, Camel, Punct]

	## A filter of the tokens of an analyzer, in the order given:
	## `Snowball("english")` is the stem of a word, `EdgeNgram(1, 3)` its
	## first one to three characters.
	TokenFilter : [Lowercase, Uppercase, Ascii, Snowball(Str), EdgeNgram(U8, U8), Ngram(U8, U8)]

	## An analyzer of the database, `DEFINE ANALYZER`: how a full-text
	## index (`Table.text_index`) and a search (`Query.search`) cut a text
	## into terms. Give `define()` to `schema`.
	##
	## `clinical = Surreal.analyzer("clinical", [Class], [Lowercase])`
	Analyzer :: { name : Str, tokenizers : List(Tokenizer), filters : List(TokenFilter) }.{

		## `DEFINE ANALYZER OVERWRITE name TOKENIZERS .. FILTERS ..;`
		define : Analyzer -> Defined
		define = |Analyzer.(a)| {
			tokenizers = a.tokenizers.map(
				|t| match t {
					Blank => "blank"
					Class => "class"
					Camel => "camel"
					Punct => "punct"
				},
			)
			filters = a.filters.map(
				|f| match f {
					Lowercase => "lowercase"
					Uppercase => "uppercase"
					Ascii => "ascii"
					Snowball(language) => "snowball(${language})"
					EdgeNgram(low, high) => "edgengram(${low.to_str()},${high.to_str()})"
					Ngram(low, high) => "ngram(${low.to_str()},${high.to_str()})"
				},
			)
			parts = keyword(" TOKENIZERS", tokenizers, ",").concat(keyword(" FILTERS", filters, ","))
			Schema.analyzer(a.name, "DEFINE ANALYZER OVERWRITE ${Ql.ident(a.name)}${Str.join_with(parts, "")};")
		}

		## The terms of a text, as `search::analyze` gives them. The Roc
		## meaning covers the tokenizers `Blank` and `Class` and the filters
		## `Lowercase` and `Uppercase`, over ASCII text, where it is the
		## server's (verified on 3.3.4). Another analyzer, or a text with a
		## character outside ASCII, runs in the database only: the call
		## stops the program.
		tokens : Analyzer, Str -> List(Str)
		tokens = |Analyzer.(a), text| {
			mirrored = a.tokenizers.all(
				|t| match t {
					Blank | Class => Bool.True
					Camel | Punct => Bool.False
				},
			)
				and a.filters.all(
					|f| match f {
						Lowercase | Uppercase => Bool.True
						_ => Bool.False
					},
				)
			if !mirrored {
				crash "Surreal.Analyzer.tokens of `${a.name}` runs in the database only: its Roc meaning covers the tokenizers Blank and Class and the filters Lowercase and Uppercase"
			}
			bytes = text.to_utf8()
			if bytes.any(|b| b >= 128) {
				crash "Surreal.Analyzer.tokens of `${a.name}` runs in the database only for a text outside ASCII"
			}
			by_class = a.tokenizers.any(
				|t| match t {
					Class => Bool.True
					_ => Bool.False
				},
			)
			pieces = if (a.tokenizers.is_empty()) [bytes] else ascii_runs(bytes, by_class)
			pieces.map(
				|piece| {
					cased = a.filters.fold(
						piece,
						|acc, f| match f {
							Lowercase => acc.map(|b| if (b >= 65 and b <= 90) b + 32 else b)
							Uppercase => acc.map(|b| if (b >= 97 and b <= 122) b - 32 else b)
							_ => acc
						},
					)
					match Str.from_utf8(cased) {
						Ok(term) => term
						Err(_) => crash "ASCII bytes are valid UTF-8"
					}
				},
			)
		}

		## Whether a full-text search over this analyzer keeps the text: the
		## query has a term, and the text has every term of it, as
		## `text @@ query` (verified on 3.3.4: a query of no term, such as
		## `''`, keeps no row, and a query of two terms keeps the rows that
		## have both). The Roc meaning of `Query.search`, under the rule of
		## `tokens`.
		matches : Analyzer, Str, Str -> Bool
		matches = |this, text, query| {
			terms = Analyzer.tokens(this, query)
			have = Analyzer.tokens(this, text)
			!terms.is_empty() and terms.all(|term| have.contains(term))
		}
	}

	## An analyzer of this name, with its tokenizers and filters.
	analyzer : Str, List(Tokenizer), List(TokenFilter) -> Analyzer
	analyzer = |name, tokenizers, filters| Analyzer.({ name, tokenizers, filters })

	## A full-text index of a `Str` field of a table, over an analyzer
	## (`Table.text_index`): the definition (`Def.text_index`) and the
	## searches (`Query.search`) take the same value.
	FullText(row) :: { table : Str, path : Try(Str, Error), analyzer : Analyzer }

	## How a vector index measures the distance of two vectors.
	Distance : [Cosine, Euclidean, Manhattan, Chebyshev]

	## A vector index of a `List(F64)` or `List(F32)` field of a table
	## (`Table.vector_index`), HNSW: the definition (`Def.vector_index`)
	## and the searches (`Query.nearest`) take the same value, so a probe
	## of another dimension is refused when the query is built.
	VectorIndex(row) :: { table : Str, path : Try(Str, Error), dimension : U64, distance : Distance, element : Try(Str, Error) }

	## The rows of `Query.nearest`: the `k` nearest by the distance of
	## the index, `<|k,ef|>` through the HNSW graph with `ef` candidates,
	## which may miss a row, or `<|k,DISTANCE|>`, every row measured.
	Knn : [Approx({ k : U64, ef : U64 }), Exact(U64)]

	## A row that `Query.search` kept, the second of the pair `(row, hit)`
	## of the query: what the search knows of it. Its methods are
	## intrinsics: SurrealDB computes them, a clause reads them, and the
	## program has no hit to call them on. Its backing is `[]`, a type of
	## no value: a hit exists only in a clause.
	Hit :: [].{

		## `search::score(1)`: the BM25 score of the row for the terms of
		## the search. A term that half the rows or more have adds 0.
		score : Hit -> F64

		## `search::highlight(before, after, 1)`: the text with each term
		## of the search between `before` and `after`.
		highlight : Hit, Str, Str -> Str

		## `search::offsets(1)`: where each term of the search is in the
		## text, from `start` to `end`, `end` left out.
		offsets : Hit -> List({ start : I64, end : I64 })
	}

	## A row that `Query.nearest` kept, the second of the pair `(row,
	## near)` of the query. Its method is an intrinsic: SurrealDB computes it.
	## Its backing is `[]`, as `Hit`'s is.
	Near :: [].{

		## `vector::distance::knn()`: the distance of the row from the
		## probe, by the distance of the index. Through the HNSW graph it
		## is computed on the index's own copy of the vector (`TYPE F32`
		## rounds it), so it has no Roc meaning; measure the row with
		## `Vector` for one.
		distance : Near -> F64
	}

	## The `vector::` functions over two vectors of the same dimension.
	## SurrealDB refuses two dimensions with an error, and the Roc
	## meaning stops the program. Each sum runs from the first element to
	## the last, as SurrealDB's does, so the Roc result is the server's to
	## the bit (verified on 3.3.4).
	Vector :: {}.{

		## `vector::similarity::cosine`: the dot product over the product of
		## the magnitudes. A zero vector gives `NaN`.
		similarity_cosine : List(F64), List(F64) -> F64
		similarity_cosine = |a, b| Vector.dot(a, b) / (Vector.magnitude(a) * Vector.magnitude(b))

		## `vector::distance::euclidean`.
		distance_euclidean : List(F64), List(F64) -> F64
		distance_euclidean = |a, b| same_dimension("distance_euclidean", a, b).fold(0.F64, |sum, (x, y)| sum + (x - y) * (x - y)).sqrt()

		## `vector::distance::manhattan`: the sum of the differences.
		distance_manhattan : List(F64), List(F64) -> F64
		distance_manhattan = |a, b| same_dimension("distance_manhattan", a, b).fold(0.F64, |sum, (x, y)| sum + (x - y).abs())

		## `vector::distance::chebyshev`: the largest difference.
		distance_chebyshev : List(F64), List(F64) -> F64
		distance_chebyshev = |a, b| same_dimension("distance_chebyshev", a, b).fold(0.F64, |most, (x, y)| if ((x - y).abs() > most) (x - y).abs() else most)

		## `vector::dot`.
		dot : List(F64), List(F64) -> F64
		dot = |a, b| same_dimension("dot", a, b).fold(0.F64, |sum, (x, y)| sum + x * y)

		## `vector::magnitude`: the length of the vector.
		magnitude : List(F64) -> F64
		magnitude = |a| a.fold(0.F64, |sum, x| sum + x * x).sqrt()
	}

	## A Roc function that the database also holds, as `fn::name`. Make it a
	## top-level constant with `db_fn`, and give it to `schema` with `function`.
	## A call in a clause is `fn::name(..)`, and a call in Roc runs `run`.
	DbFn(f) := { name : Str, run : f }.{

		## `fn::name(a)`.
		call1 : DbFn((a -> r)), a -> r
		call1 = |DbFn.(d), a| (d.run)(a)

		## `fn::name(a, b)`.
		call2 : DbFn((a, b -> r)), a, b -> r
		call2 = |DbFn.(d), a, b| (d.run)(a, b)

		## `fn::name(a, b, c)`.
		call3 : DbFn((a, b, c -> r)), a, b, c -> r
		call3 = |DbFn.(d), a, b, c| (d.run)(a, b, c)
	}

	## A database function named `fn::name`. `name` is `[a-z_][a-z0-9_]*`, and
	## `run` is a top-level function:
	##
	## fever_fn : Surreal.DbFn((Dec, I64 -> Bool))
	## fever_fn = Surreal.db_fn("fever", fever)
	db_fn : Str, f -> DbFn(f)
	db_fn = |name, run| DbFn.({ name, run })

	## The `DEFINE FUNCTION` of a database function and of each database
	## function its body calls, for `schema`: `Surreal.function(|_| fever_fn)`.
	function : Code(({} -> DbFn(f))) -> Defined
	function = |code| Schema.function(Translate.function_defs(own, code.graph()))

	## What a table is: a normal table, an edge table with the names of the
	## tables its ends point at, or a view.
	TableKind : [Normal, Relation({ from : Str, to : Str }), View]

	## A table whose rows are `row`. It holds the name and the kind, and no
	## `Code` value, so a clause can read it: `visits.rows()`,
	## `vets.id("ruth")`. The row type comes from `define()`, where
	## `Types` reads the schema off it.
	Table(row) :: { name : Str, kind : TableKind }.{

		## The id of a row of this table. In a clause it is the record id:
		## `vets.id("ruth")` is `vet:⟨ruth⟩`.
		id : Table(row), Str -> Id(row)
		id = |Table.(t), key| Id.({ table: t.name, key: key })

		## The row with this key, to start a query from: `FROM vet:⟨tia⟩`.
		## SurrealDB reads the one record, where a filter on the key
		## reads the table (see `Translate.key_compare`).
		## `Selected.prepare_one` reads the result as the row or
		## `NotFound`. The key is an escaped record id, so any text is one
		## key, and an id of another table is refused.
		at : Table(row), Code(Id(row)) -> Query(p, row)
		at = |this, row_id| {
			Table.(t) = this
			Query.(q) = Surreal.from(this)
			key = key_of(t, row_id)
			Query.({ ..q, target: Record(key.text), slots: key.slots })
		}

		## A link to a row of this table. It is not fetched.
		link : Table(row), Str -> Link(row)
		link = |this, key| Link.({ id: Table.id(this, key), fetched: NotFetched })

		## The rows of the table, inside a clause: `(SELECT VALUE id FROM t)`.
		## Each row is a record id, so a field read is a traversal. With it a
		## clause writes a correlated subquery or a semi join:
		## `visits.rows().keep_if(|v| v.patient.get().id == p.id).len()`.
		## An intrinsic: SurrealDB computes it.
		rows : Table(row) -> List(row)

		## The edges of this edge table that leave the row, inside a clause:
		## `->treats` off the row, `$v1.out->treats` off a row that a link
		## points at. A filter of them is `[WHERE ..]`, and their `to.get()`
		## is the next hop, so a clause writes a graph path of any length:
		## `treats.edges_from(v).keep_if(|e| e.primary).map(|e| e.to.get().owner.get().name)`
		## is `->treats[WHERE primary]->patient.owner.name`. The edge row's
		## `from` links to the row, so edges that leave another table are a
		## type error. An intrinsic: SurrealDB computes it.
		edges_from : Table({ from : Link(a), ..e }), a -> List({ from : Link(a), ..e })

		## The edges of this edge table that end at the row: `<-treats`. The
		## edge row's `to` links to the row, and `from.get()` is the next hop
		## back: `<-treats<-vet`. An intrinsic: SurrealDB computes it.
		edges_to : Table({ to : Link(b), ..e }), b -> List({ to : Link(b), ..e })

		## The record user of the session, a row of this table, inside a
		## clause: `$auth.id`. `|m| m.owner.id() == users.auth()` is
		## `owner = $auth.id`. A session of a system user has no record
		## user, and `$auth.id` is `NONE`. An intrinsic: SurrealDB computes it.
		auth : Table(row) -> Id(row)

		## A full-text index of the `Str` field at the path, over the
		## analyzer: `notes.text_index(|n| n.body, clinical)`. Give it to
		## `Def.text_index` and to `Query.search`.
		text_index : Table(row), Code(row -> Str), Analyzer -> FullText(row)
		text_index = |Table.(t), path, an| FullText.({ table: t.name, path: within_clause("`text_index`", one_path(stored_graph(path, "an index"), "a full-text index")), analyzer: an })

		## An HNSW index of the vector field at the path, of `dimension`
		## numbers, by `distance`: `notes.vector_index(|n| n.embedding, {
		## dimension: 3, distance: Cosine })`. A `List(F64)` is indexed as
		## `TYPE F64`, a `List(F32)` as `TYPE F32`. Give it to
		## `Def.vector_index` and to `Query.nearest`.
		vector_index : Table(row), Code(row -> List(n)), { dimension : U64, distance : Distance } -> VectorIndex(row)
		vector_index = |Table.(t), path, shape| {
			element = match path.graph().root_row().result {
				ListOf(F64) => Ok("F64")
				ListOf(F32) => Ok("F32")
				other => Err(BadSchema("a vector index of `${t.name}` is over a `List(F64)` or a `List(F32)`, not a `${other.name()}`"))
			}
			VectorIndex.({ table: t.name, path: within_clause("`vector_index`", one_path(stored_graph(path, "an index"), "a vector index")), dimension: shape.dimension, distance: shape.distance, element })
		}

		## The schema builder of this table. The definition holds the type of
		## the row: `Code.ty_of` describes `row` at each use that fixes it, so
		## `customers.define()` has the description of `Customer`. A view
		## takes its query with `define_as`.
		define : Table(row) -> Def(row)
		define = |Table.(t)| {
			kind = match t.kind {
				Normal => Types.Kind.Normal
				Relation(ends) => Types.Kind.Relation(ends)
				View => Types.Kind.View(Err(Unsupported("`${t.name}` is a view: give its query with `define_as`")))
			}
			proxy : Code.Proxy(row)
			proxy = Code.proxy()
			Def.({ source: { name: t.name, row_ty: Code.ty_of(proxy), kind }, rules: [], problems: [] })
		}

		## A read row of the table: the same row as the stored one, with a
		## `Linked` for a `Link` and with `Out` and `In` fields for the edge
		## tables at the row. It writes no statement. `schema` checks that it
		## agrees with the stored row of the table of the same name, and
		## reports a `BadSchema` when not:
		##
		## pets : Surreal.Table(Pet)               # owner : Surreal.Linked(Owner)
		## stored_pets : Surreal.Table(StoredPet)  # owner : Surreal.Link(Owner)
		## Surreal.schema([.., stored_pets.define().done(), pets.define_read()])
		define_read : Table(row) -> Defined
		define_read = |Table.(t)| {
			proxy : Code.Proxy(row)
			proxy = Code.proxy()
			Schema.read(t.name, Code.ty_of(proxy))
		}

		## The definition of a view: `DEFINE TABLE name TYPE NORMAL AS SELECT
		## .. GROUP BY ..`. Each write to the source table updates it. It
		## takes no rule, and its query reads a whole table, not a range
		## (SurrealDB refuses a range in a view). The row type is the result
		## of `per_group`:
		##
		## daily = Surreal.view("vital_daily")
		## daily_def = daily.define_as(Surreal.from(vitals).group_by(day_of), day_line).done()
		define_as : Table(out), Grouped({}, row, k), Code((k, List(row) -> out)) -> Def(out)
		define_as = |Table.(t), grouped, per_group| {
			Grouped.(g) = grouped
			Query.(q) = g.query
			select = match (t.kind, q.target) {
				(Normal, _) | (Relation(_), _) => Err(Unsupported("`${t.name}` is not a view: make it with `Surreal.view`"))
				(View, Range(_)) => Err(Unsupported("the view `${t.name}` reads a range; a view reads a whole table"))
				(View, Record(_)) => Err(Unsupported("the view `${t.name}` reads the record of one key; a view reads a whole table"))
				(View, Sub(_)) => Err(Unsupported("the view `${t.name}` reads a subquery; a view reads a whole table"))
				(View, Whole(_)) => {
					Selected.(view) = aggregated(grouped, per_group, Bool.True)
					if !view.slots.is_empty() {
						crash stored_message("a view")
					}
					Selected.render(Selected.(view), Translate.variable)
				}
			}
			Def.({ source: { name: t.name, row_ty: stored_graph(per_group, "a view").root_row().result, kind: Types.Kind.View(select) }, rules: [], problems: [] })
		}

		# ---------------------------------------------------- writes

		## The cut of `update` and `delete` clauses (see `Surreal.code_primitives`).
		code_primitives = cut

		## One transaction that inserts every row, with the values the
		## compiler's derived encoder writes. An absent optional field is a key
		## left out. The `id` field stays in the row: it is the record key.
		## The result is the rows as stored, with the fields that the
		## database computes: `BEGIN`, the `INSERT`, `COMMIT`, and a
		## failure is the insert's.
		insert : Table(row), List(row) -> Prepared(List(row)) where [row.encoder_for : Encode.Format -> (row, Encode.State -> Try(Encode.State, [])), row.Cbor.Readable(errs)]
		insert = |Table.(t), new_rows| prepared_of(insert_body(t, new_rows, return_clause(After)).map_ok(|statement| { statement, slots: [], count: 1, atomic: Whole, read: read_stored(0, is_edge(t.kind)) }))

		## [Table.insert] of rows whose keys the server makes, as
		## [Table.create_new] does: each row without its `id`. The result is
		## the rows as stored, in the order of `rows`.
		insert_new : Table({ id : Str, ..new }), List(new) -> Prepared(List(Created({ id : Str, ..new }, new))) where [new.encoder_for : Encode.Format -> (new, Encode.State -> Try(Encode.State, [])), new.Cbor.Readable(errs)]
		insert_new = |Table.(t), new_rows| prepared_of(insert_body(t, new_rows, return_clause(After)).map_ok(|statement| { statement, slots: [], count: 1, atomic: Whole, read: read_created(t) }))

		## A new row at `table:⟨id⟩`, or for an edge table the edge between
		## the rows of `from` and `to`: `CREATE`, `RELATE`. It fails when
		## the row exists. The result is the row as stored.
		create : Table(row), row -> Prepared(List(row)) where [row.encoder_for : Encode.Format -> (row, Encode.State -> Try(Encode.State, [])), row.Cbor.Readable(errs)]
		create = |this, row| Table.edit(this, Create(row))

		## A new row whose key the server makes: the row without its `id`.
		## `CREATE t CONTENT ..`, or for an edge table `RELATE` with no key.
		## The key is the default of `id` in the schema
		## (`.default_by(|r| r.id, |_| Surreal.Rand.ulid())`), or else
		## SurrealDB's random 20 characters. The result is the row as
		## stored: its `Id`, and its other fields.
		create_new : Table({ id : Str, ..new }), new -> Prepared(List(Created({ id : Str, ..new }, new))) where [new.encoder_for : Encode.Format -> (new, Encode.State -> Try(Encode.State, [])), new.Cbor.Readable(errs)]
		create_new = |Table.(t), row| {
			built = |{}| {
				fields = keyless(t, row)?
				statement = match t.kind {
					Relation(_) => relate_fields(t, Err(Generated), fields)?
					Normal | View => statement_of("CREATE ${Ql.ident(t.name)} CONTENT ${Ql.literal(Ql.Value.Object(fields))}")
				}
				Statement.(made) = statement
				Ok({ statement: statement_of("${made.surql}${return_clause(After)}"), slots: [], count: 1, atomic: No, read: read_created(t) })
			}
			prepared_of(built({}))
		}

		## The row at `table:⟨id⟩`, replaced when it exists and made when
		## not. The result is the row as stored after the write.
		upsert : Table(row), row -> Prepared(List(row)) where [row.encoder_for : Encode.Format -> (row, Encode.State -> Try(Encode.State, [])), row.Cbor.Readable(errs)]
		upsert = |Table.(t), row| stored_write(t, content_write("UPSERT", t, row), After)

		## The row at `table:⟨id⟩`, replaced by this one when it exists:
		## `UPDATE .. CONTENT`. The result is the row as stored after the
		## write, or none when the key has no row.
		replace : Table(row), row -> Prepared(List(row)) where [row.encoder_for : Encode.Format -> (row, Encode.State -> Try(Encode.State, [])), row.Cbor.Readable(errs)]
		replace = |Table.(t), row| stored_write(t, content_write("UPDATE", t, row), After)

		## Insert rows, and where a row with the same key exists, change the
		## stored row instead: `INSERT INTO t [..] ON DUPLICATE KEY UPDATE ..`.
		## The patch takes the new row and the stored one, `|new, old| {
		## ..old, visits: old.visits + new.visits }`, and is translated as
		## the patch of `update` is: each changed field is an item, and the
		## new row is `$input`. One transaction, as `insert` is. The result
		## is the rows as stored. SurrealDB 4.0.1 takes a duplicate to be the
		## same record key; a row that only repeats the value of a unique
		## index is refused (`Unique`). A relation table is refused.
		insert_or_update : Table(row), List(row), Code((row, row -> row)) -> Prepared(List(row)) where [row.encoder_for : Encode.Format -> (row, Encode.State -> Try(Encode.State, [])), row.Cbor.Readable(errs)]
		insert_or_update = |Table.(t), new_rows, patch| {
			built = |{}| {
				writable(t)?
				if is_edge(t.kind) {
					return Err(Unsupported("`insert_or_update` is not defined for the relation table `${t.name}`"))
				}
				new = Translate.Binding.Row({ at: "$input", of: Doc(Of(t.name)), edge: Bool.False })
				sets = within_clause("the patch of `insert_or_update`", Translate.assignments(own, patch.graph(), [new, Translate.table_row(t.name, Bool.False)], spelled(patch, Translate.variable)))?
				statement = insert_body(t, new_rows, " ON DUPLICATE KEY UPDATE ${set_list(sets)}${return_clause(After)}")?
				Ok({ statement, slots: slots_of(patch), count: 1, atomic: Whole, read: read_stored(0, Bool.False) })
			}
			prepared_of(built({}))
		}

		## Replay patches on the row with this key, in order: `UPDATE
		## t:⟨k⟩ PATCH [..]`, a JSON Patch. The patches are those of
		## `Query.live_diff` (`Patch`), so a client can apply the changes
		## that another client saw. A patch of a create (the replace of `""`
		## by the whole row) sets each field. These are refused when the
		## statement is built: a patch of another row, a patch of a delete
		## (`delete_at` is that), an op below `/id`, and a `change` op, a
		## text diff that the ORM reads and does not write. A path that the
		## row does not have, or a value of another type, is the server's
		## error. The result is the row as stored, or none for a key with
		## no row.
		patch_at : Table(row), Id(row), List(Patch(row)) -> Prepared(List(row)) where [row.Cbor.Readable(errs)]
		patch_at = |this, row_id, patches| {
			Id.(i) = row_id
			foreign = patches.keep_if(|Patch.(p)| p.ref.to_str() != Ql.record_ref(i.table, Ql.Value.Str(i.key)))
			if !foreign.is_empty() {
				prepared_of(Err(Unsupported("a patch is of another row than `${Ql.record_id(i.table, i.key)}`")))
			} else {
				Table.patch_ops_at(this, row_id, patches.join_map(|Patch.(p)| p.ops))
			}
		}

		## [Table.patch_at] of ops that the app made, `Replace(["tag"],
		## Cbor.Value.Text("x"))`.
		patch_ops_at : Table(row), Id(row), List(Op) -> Prepared(List(row)) where [row.Cbor.Readable(errs)]
		patch_ops_at = |Table.(t), row_id, ops| {
			built = |{}| {
				writable(t)?
				record = record_at(t, row_id)?
				items = ops.map_try(patch_item)?
				Ok(statement_of("UPDATE ${record} PATCH [${Str.join_with(items, ", ")}]"))
			}
			stored_write(t, built({}), After)
		}

		## Merge a record into the row with this key: `UPDATE t:⟨k⟩ MERGE
		## { .. }`. The record is a value of the app with only the fields
		## to change, and an object field in it is merged into the stored
		## object, key by key. `set_at` writes the same, but each field as
		## a clause; this takes the record whole. Roc has no type for a
		## record of some of the row's fields, so a field the row does not
		## have, or of another type, is the server's error (`SCHEMAFULL`
		## checks a `MERGE`), and `id` is refused. A union field is merged
		## key by key too, so the keys of its old arm stay (verified): change
		## a union with `set_at`, as `update` does. The result is the row as
		## stored, or none for a key with no row.
		merge_at : Table(row), Id(row), partial -> Prepared(List(row)) where [partial.encoder_for : Encode.Format -> (partial, Encode.State -> Try(Encode.State, [])), row.Cbor.Readable(errs)]
		merge_at = |Table.(t), row_id, partial| stored_write(t, keyed_merge("UPDATE", t, row_id, partial), After)

		## [Table.merge_at] where the row is made when the key has none:
		## `UPSERT t:⟨k⟩ MERGE { .. }`, so the record must hold every field
		## that the schema requires.
		upsert_merge_at : Table(row), Id(row), partial -> Prepared(List(row)) where [partial.encoder_for : Encode.Format -> (partial, Encode.State -> Try(Encode.State, [])), row.Cbor.Readable(errs)]
		upsert_merge_at = |Table.(t), row_id, partial| stored_write(t, keyed_merge("UPSERT", t, row_id, partial), After)

		## [Table.merge_at] in every row that the condition keeps:
		## `UPDATE t MERGE { .. } WHERE ..`.
		merge : Table(row), Code(row -> Bool), partial -> Prepared(List(row)) where [partial.encoder_for : Encode.Format -> (partial, Encode.State -> Try(Encode.State, [])), row.Cbor.Readable(errs)]
		merge = |Table.(t), condition, partial| {
			built = |{}| {
				keep = within_clause("the condition of `merge`", Translate.render(own, condition.graph(), [Translate.table_row(t.name, is_edge(t.kind))], spelled(condition, Translate.variable)))?
				Statement.(made) = merge_write("UPDATE", t, Ql.ident(t.name), partial)?
				Ok(statement_of("${made.surql} WHERE ${keep}"))
			}
			keyed_write(t, built({}), slots_of(condition), After)
		}

		## One write of whole rows, as the Mirror describes it (`Edit`):
		## `CREATE` or, for an edge, `RELATE`; `UPDATE .. CONTENT` with the
		## whole new row; `DELETE` of the record. The result is the row as
		## stored: after a create and a replace, before a delete, and none
		## for a replace or a delete of a row that is not there. A write
		## that has only the new row or the key is `replace` or `delete_at`.
		edit : Table(row), Edit(row) -> Prepared(List(row)) where [row.encoder_for : Encode.Format -> (row, Encode.State -> Try(Encode.State, [])), row.Cbor.Readable(errs)]
		edit = |Table.(t), change| match change {
			Create(row) =>
				match t.kind {
					Relation(_) => stored_write(t, relate_row(t, row), After)
					Normal | View => stored_write(t, content_write("CREATE", t, row), After)
				}
			Replace(_, row) => stored_write(t, content_write("UPDATE", t, row), After)
			Delete(row) => stored_write(t, delete_of(t, row), Before)
		}

		## The record id of a row, as a live query reports it.
		ref : Table(row), row -> Try(Ref, Error) where [row.encoder_for : Encode.Format -> (row, Encode.State -> Try(Encode.State, []))]
		ref = |Table.(t), row| ref_of(t, row)

		## The record id of a row of a view: the values of its group key, in
		## the order of `GROUP BY`, which is the name order of a key record.
		group_ref : Table(row), k -> Try(Ref, Error) where [k.encoder_for : Encode.Format -> (k, Encode.State -> Try(Encode.State, []))]
		group_ref = |Table.(t), key| match t.kind {
			View =>
				match Encode.value_of(key)? {
					Object(fields) => Ok(Ref.({ table: t.name, key: Ql.Value.Array(fields.map(|f| f.value)) }))
					one => Ok(Ref.({ table: t.name, key: Ql.Value.Array([one]) }))
				}
			Normal | Relation(_) => Err(Unsupported("`${t.name}` is not a view, so its rows have no group key"))
		}

		## Set the fields the patch changes in every row the condition keeps.
		## The patch is the row with some fields replaced, `|o| { ..o, f: .. }`,
		## and each changed field is a `SET` item. An optional field that the
		## patch's row leaves out is `NONE`. `SET`, never `MERGE`, because
		## `MERGE` breaks a union field.
		update : Table(row), Code(row -> Bool), Code(row -> row) -> Write(p, row)
		update = |Table.(t), condition, patch| {
			row = Translate.table_row(t.name, is_edge(t.kind))
			build = |param| {
				writable(t)?
				keep = within_clause("the condition of `update`", Translate.render(own, condition.graph(), [row], spelled(condition, param)))?
				sets = within_clause("the patch of `update`", Translate.assignments(own, patch.graph(), [row], spelled(patch, param)))?
				Ok("UPDATE ${Ql.ident(t.name)} SET ${set_list(sets)} WHERE ${keep}")
			}
			Write.({ build: build, gives: After, edge: is_edge(t.kind), slots: slots_of(condition).concat(slots_of(patch)) })
		}

		## [Table.update] where the condition and the patch read the parameter
		## record, `|p, o| ..`.
		update_by : Table(row), Code((p, row -> Bool)), Code((p, row -> row)) -> Write(p, row)
		update_by = |Table.(t), condition, patch| {
			row = Translate.table_row(t.name, is_edge(t.kind))
			build = |param| {
				writable(t)?
				keep = within_clause("the condition of `update_by`", Translate.render(own, condition.graph(), [Translate.Binding.Params, row], spelled(condition, param)))?
				sets = within_clause("the patch of `update_by`", Translate.assignments(own, patch.graph(), [Translate.Binding.Params, row], spelled(patch, param)))?
				Ok("UPDATE ${Ql.ident(t.name)} SET ${set_list(sets)} WHERE ${keep}")
			}
			Write.({ build: build, gives: After, edge: is_edge(t.kind), slots: slots_of(condition).concat(slots_of(patch)) })
		}

		## Set the fields of a patch in every row the condition keeps. The
		## patch is a record of only the fields it sets, `|o| { name: "Jo",
		## visits: o.visits + 1 }`, each one a `SET` item. Roc cannot type a
		## record of some of the row's fields, so the statement checks each
		## field against the row when it is built: a name the row does not
		## have, or another type, is `BadSchema`. An optional field takes its
		## value or a `Try` of it, whose `Err` makes it `NONE`.
		set : Table(row), Code(row -> Bool), Code(row -> patch) -> Write(p, row)
		set = |Table.(t), condition, patch| {
			row = Translate.table_row(t.name, is_edge(t.kind))
			build = |param| {
				writable(t)?
				keep = within_clause("the condition of `set`", Translate.render(own, condition.graph(), [row], spelled(condition, param)))?
				sets = within_clause("the patch of `set`", Translate.patch_assignments(own, patch.graph(), [row], spelled(patch, param)))?
				Ok("UPDATE ${Ql.ident(t.name)} SET ${set_list(sets)} WHERE ${keep}")
			}
			Write.({ build: build, gives: After, edge: is_edge(t.kind), slots: slots_of(condition).concat(slots_of(patch)) })
		}

		## [Table.set] where the condition and the patch read the parameter
		## record, `|p, o| ..`.
		set_by : Table(row), Code((p, row -> Bool)), Code((p, row -> patch)) -> Write(p, row)
		set_by = |Table.(t), condition, patch| {
			row = Translate.table_row(t.name, is_edge(t.kind))
			build = |param| {
				writable(t)?
				keep = within_clause("the condition of `set_by`", Translate.render(own, condition.graph(), [Translate.Binding.Params, row], spelled(condition, param)))?
				sets = within_clause("the patch of `set_by`", Translate.patch_assignments(own, patch.graph(), [Translate.Binding.Params, row], spelled(patch, param)))?
				Ok("UPDATE ${Ql.ident(t.name)} SET ${set_list(sets)} WHERE ${keep}")
			}
			Write.({ build: build, gives: After, edge: is_edge(t.kind), slots: slots_of(condition).concat(slots_of(patch)) })
		}

		## [Table.update] of the row with this key: `UPDATE vet:⟨tia⟩ SET ..`.
		## The key is a typed `Id` of this table. A key with no row changes
		## nothing.
		update_at : Table(row), Code(Id(row)), Code(row -> row) -> Write(p, row)
		update_at = |Table.(t), row_id, patch| update_key(t, row_id, slots_of(patch), |row, param| within_clause("the patch of `update_at`", Translate.assignments(own, patch.graph(), [row], spelled(patch, param))))

		## [Table.update_at] where the patch reads the parameter record.
		update_at_by : Table(row), Code(Id(row)), Code((p, row -> row)) -> Write(p, row)
		update_at_by = |Table.(t), row_id, patch| update_key(t, row_id, slots_of(patch), |row, param| within_clause("the patch of `update_at_by`", Translate.assignments(own, patch.graph(), [Translate.Binding.Params, row], spelled(patch, param))))

		## [Table.set] of the row with this key: `UPDATE vet:⟨tia⟩ SET ..`.
		set_at : Table(row), Code(Id(row)), Code(row -> patch) -> Write(p, row)
		set_at = |Table.(t), row_id, patch| update_key(t, row_id, slots_of(patch), |row, param| within_clause("the patch of `set_at`", Translate.patch_assignments(own, patch.graph(), [row], spelled(patch, param))))

		## [Table.set_at] where the patch reads the parameter record.
		set_at_by : Table(row), Code(Id(row)), Code((p, row -> patch)) -> Write(p, row)
		set_at_by = |Table.(t), row_id, patch| update_key(t, row_id, slots_of(patch), |row, param| within_clause("the patch of `set_at_by`", Translate.patch_assignments(own, patch.graph(), [Translate.Binding.Params, row], spelled(patch, param))))

		## Delete the row with this key: `DELETE vet:⟨tia⟩`. A key with no
		## row deletes nothing.
		delete_at : Table(row), Code(Id(row)) -> Write(p, row)
		delete_at = |Table.(t), row_id| {
			key = key_of(t, row_id)
			build = |_param| {
				writable(t)?
				Ok("DELETE ${key.text?}")
			}
			Write.({ build: build, gives: Before, edge: is_edge(t.kind), slots: key.slots })
		}

		## Delete every row the condition keeps.
		delete : Table(row), Code(row -> Bool) -> Write(p, row)
		delete = |Table.(t), condition| {
			row = Translate.table_row(t.name, is_edge(t.kind))
			build = |param| {
				writable(t)?
				Ok("DELETE ${Ql.ident(t.name)} WHERE ${within_clause("the condition of `delete`", Translate.render(own, condition.graph(), [row], spelled(condition, param)))?}")
			}
			Write.({ build: build, gives: Before, edge: is_edge(t.kind), slots: slots_of(condition) })
		}

		## [Table.delete] where the condition reads the parameter record.
		delete_by : Table(row), Code((p, row -> Bool)) -> Write(p, row)
		delete_by = |Table.(t), condition| {
			row = Translate.table_row(t.name, is_edge(t.kind))
			build = |param| {
				writable(t)?
				Ok("DELETE ${Ql.ident(t.name)} WHERE ${within_clause("the condition of `delete_by`", Translate.render(own, condition.graph(), [Translate.Binding.Params, row], spelled(condition, param)))?}")
			}
			Write.({ build: build, gives: Before, edge: is_edge(t.kind), slots: slots_of(condition) })
		}
	}

	## A table. The annotation on the binding fixes `row`:
	##
	## customers : Surreal.Table(Customer)
	## customers = Surreal.table("customer")
	table : Str -> Table(row)
	table = |name| Table.({ name: name, kind: Normal })

	## An edge table from one table to another. The row has `from : Link(a)`
	## and `to : Link(b)`: SurrealDB's `in` and `out`, which a row cannot name
	## because `in` is a keyword. The type says so, so a row whose ends do not
	## point at the two tables, in this order, is a type error.
	relation : Str, Table(a), Table(b) -> Table({ from : Link(a), to : Link(b), ..r })
	relation = |name, Table.(from), Table.(to)| Table.({ name: name, kind: Relation({ from: from.name, to: to.name }) })

	## A table that SurrealDB keeps from a grouped query. It is read-only.
	## Its query is in its definition (`Table.define_as`), so the table
	## itself holds only the name, and a clause can read it.
	view : Str -> Table(row)
	view = |name| Table.({ name: name, kind: View })

	## A link that holds its row, for seed data and for a row read back.
	fetched : Table({ id : Str, ..others }), { id : Str, ..others } -> Link({ id : Str, ..others })
	fetched = |tbl, row| Link.({ id: Table.id(tbl, row.id), fetched: Fetched(row) })

	# ============================================================= schema

	## A table's schema being built. Each clause is a Roc function that is
	## reified and translated where it is given; a clause SurrealQL cannot
	## hold is kept as a problem, and `schema` reports the first one.
	Def(row) :: { source : Types.Source, rules : List(Schema.Rule), problems : List(Error) }.{

		## The schema entry of a table definition: what `Types` reads.
		source : Def(row) -> Types.Source
		source = |Def.(d)| d.source

		## The cut of schema clauses (see `Surreal.code_primitives`).
		code_primitives = cut

		## A row predicate, named for its error message. It is the `ASSERT`
		## of the one field it reads, or an event when it reads several.
		check : Def(row), Str, Code(row -> Bool) -> Def(row)
		check = |this, name, predicate| Def.add(this, |src| Schema.check(own, src, name, stored_graph(predicate, "a `check`")))

		## A predicate on one field. Through `.?` it sees a `Try`.
		assert : Def(row), Code(row -> v), Code(v -> Bool) -> Def(row)
		assert = |this, path, predicate| Def.add(this, |_| Schema.assert(own, stored_graph(path, "an `assert`"), stored_graph(predicate, "an `assert`")))

		## A predicate on each element of a list field.
		assert_each : Def(row), Code(row -> List(v)), Code(v -> Bool) -> Def(row)
		assert_each = |this, path, predicate| Def.add(this, |_| Schema.assert_each(own, stored_graph(path, "an `assert_each`"), stored_graph(predicate, "an `assert_each`")))

		## A unique index on a path, or on a record of paths.
		unique : Def(row), Code(row -> k) -> Def(row)
		unique = |this, key| Def.add(this, |src| Schema.index(src, stored_graph(key, "a `unique` index"), Bool.True))

		index : Def(row), Code(row -> k) -> Def(row)
		index = |this, key| Def.add(this, |src| Schema.index(src, stored_graph(key, "an `index`"), Bool.False))

		## The value a field takes when a write leaves it out: `.default(|c| c.tags, [])`.
		default : Def(row), Code(row -> v), v -> Def(row) where [v.encoder_for : Encode.Format -> (v, Encode.State -> Try(Encode.State, []))]
		default = |this, path, value| Def.add(this, |_| Schema.default(stored_graph(path, "a `default`"), Encode.value_of(value)?))

		## As `default`, with the value an expression of the row, which may call
		## `Rand`: `.default_by(|o| o.key, |_| Surreal.Rand.ulid())`.
		default_by : Def(row), Code(row -> v), Code(row -> v) -> Def(row)
		default_by = |this, path, value| Def.add(this, |src| Schema.default_by(own, src, stored_graph(path, "a `default_by`"), stored_graph(value, "a `default_by`")))

		## A field SurrealDB computes on every write from the row.
		computed : Def(row), Code(row -> v), Code(row -> v) -> Def(row)
		computed = |this, path, value| Def.add(this, |src| Schema.computed(own, src, stored_graph(path, "a `computed` field"), stored_graph(value, "a `computed` field")))

		readonly : Def(row), Code(row -> v) -> Def(row)
		readonly = |this, path| Def.add(this, |_| Schema.readonly(stored_graph(path, "a `readonly` field")))

		## The time of the row's first write, which later writes keep.
		created_now : Def(row), Code(row -> Datetime) -> Def(row)
		created_now = |this, path| Def.add(this, |_| Schema.created_now(stored_graph(path, "a `created_now` field")))

		## What deleting a row of `target` does to every link from this table
		## to it, at any depth. Without one, the delete is rejected.
		on_delete : Def(row), Table(t), [Reject, Unset, Cascade, Ignore] -> Def(row)
		on_delete = |this, target, policy| Def.add(this, |_| Schema.on_delete(name_of(target), policy))

		## The same for the one link at a path; it wins over `on_delete`.
		on_delete_at : Def(row), Code(row -> l), [Reject, Unset, Cascade, Ignore] -> Def(row)
		on_delete_at = |this, path, policy| Def.add(this, |_| Schema.on_delete_at(stored_graph(path, "an `on_delete_at`"), policy))

		## A change history of this length: `CHANGEFEED <n>ns` on the table line.
		## SurrealDB keeps it, and `SHOW CHANGES FOR TABLE` reads it.
		changefeed : Def(row), Duration -> Def(row)
		changefeed = |this, Duration.(d)| Def.add(this, |_| Schema.changefeed(d.nanos))

		## The full-text index of `Table.text_index`: `DEFINE INDEX .. FIELDS
		## body FULLTEXT ANALYZER clinical BM25 HIGHLIGHTS`. `schema`
		## refuses an analyzer that it is not given.
		text_index : Def(row), FullText(row) -> Def(row)
		text_index = |this, FullText.(f)| Def.add(
			this,
			|src| {
				Analyzer.(a) = f.analyzer
				_ = same_table(src.name, f.table)?
				Schema.search_index(f.path?, "fulltext", "FULLTEXT ANALYZER ${Ql.ident(a.name)} BM25 HIGHLIGHTS", [a.name])
			},
		)

		## The vector index of `Table.vector_index`: `DEFINE INDEX .. FIELDS
		## embedding HNSW DIMENSION 3 DIST COSINE TYPE F64`. SurrealDB then
		## refuses a write of a vector of another dimension (verified).
		vector_index : Def(row), VectorIndex(row) -> Def(row)
		vector_index = |this, VectorIndex.(v)| Def.add(
			this,
			|src| {
				_ = same_table(src.name, v.table)?
				Schema.search_index(v.path?, "hnsw", "HNSW DIMENSION ${v.dimension.to_str()} DIST ${distance_name(v.distance)} TYPE ${v.element?}", [])
			},
		)

		comment : Def(row), Code(row -> v), Str -> Def(row)
		comment = |this, path, text| Def.add(this, |_| Schema.comment(stored_graph(path, "a `comment`"), text))

		## A permission of the table for a record user: the rows that the
		## condition keeps, for each of `actions`, which may read the
		## session (`Table.auth`, `Auth`). `.permit([Select], |m|
		## m.owner.id() == users.auth())` is `PERMISSIONS FOR select WHERE
		## owner = $auth.id`. A table with no permission keeps SurrealDB's
		## default, and a table with one names each action: an action that
		## no permission names is `NONE`. A system user is not checked.
		permit : Def(row), List(Action), Code(row -> Bool) -> Def(row)
		permit = |this, actions, condition| Def.add(this, |src| Schema.permit(own, src, actions, Where(stored_graph(condition, "a permission"))))

		## [Def.permit] of every row: `FOR .. FULL`.
		permit_full : Def(row), List(Action) -> Def(row)
		permit_full = |this, actions| Def.add(this, |src| Schema.permit(own, src, actions, Full))

		## A permission of one field (`select`, `create`, `update`): the rows
		## whose field a record user reads or writes. A field with no
		## permission is `FULL`, SurrealDB's default for a field. A field
		## that a select may not read is not in its row: give it a type
		## that reads with it left out (`?:`), or select the other fields.
		permit_field : Def(row), Code(row -> v), List(Action), Code(row -> Bool) -> Def(row)
		permit_field = |this, path, actions, condition| Def.add(this, |src| Schema.permit_field(own, src, stored_graph(path, "a field permission"), actions, Where(stored_graph(condition, "a field permission"))))

		## [Def.permit_field] of no row: `FOR .. NONE`, such as the hash of a
		## password that no record user reads.
		deny_field : Def(row), Code(row -> v), List(Action) -> Def(row)
		deny_field = |this, path, actions| Def.add(this, |src| Schema.permit_field(own, src, stored_graph(path, "a field permission"), actions, No))

		## The definition, ready for `schema`.
		done : Def(row) -> Defined
		done = |Def.(d)| Schema.defined(d.source, d.rules, d.problems)

		add : Def(row), (Types.Source -> Try(List(Schema.Rule), Error)) -> Def(row)
		add = |Def.(d), clause| match clause(d.source) {
			Ok(rules) => Def.({ ..d, rules: d.rules.concat(rules) })
			Err(problem) => Def.({ ..d, problems: d.problems.append(problem) })
		}
	}

	## A finished table definition.
	Defined : Schema.Defined

	## What a permission is for (`Def.permit`): `Select`, `Create`,
	## `Update` or `Delete`.
	Action : Schema.Action

	## A record access method of the database, by its name: `DEFINE ACCESS
	## name ON DATABASE TYPE RECORD`. A record user signs up with the
	## variables `up` and signs in with `on`, both records: the
	## annotation on the binding fixes them, as for a table.
	##
	## accounts : Surreal.Access({ email : Str, pass : Str }, { email : Str, pass : Str })
	## accounts = Surreal.access("account")
	Access(up, on) :: { name : Str }.{

		## The cut of the signup and the signin (see `Surreal.code_primitives`).
		code_primitives = cut

		## The definition of the access method, over the rows of a table of
		## users. The signup is the new row, without its `id`, from the
		## variables, each a `$name`: `|v| { email: v.email, pass:
		## Surreal.Hash.argon2(v.pass) }` is `CREATE user CONTENT { email:
		## $email, pass: crypto::argon2::generate($pass) }`, and it may
		## call `Rand` and `Hash.argon2`, as a write. The signin keeps the
		## row of the user, as `filter_by` does: `|v, u| u.email == v.email
		## and Surreal.Hash.argon2_matches(u.pass, v.pass)` is `SELECT *
		## FROM user WHERE email = $email AND crypto::argon2::compare(pass,
		## $pass)`. The server runs both as a system user, so the
		## permissions of the table do not apply to them.
		define : Access(up, on), Table({ id : Str, ..new }), Code((up -> new)), Code((on, { id : Str, ..new } -> Bool)) -> AccessDef
		define = |Access.(a), Table.(t), signup, signin| AccessDef.(
			{
				name: a.name,
				table: t.name,
				content: within_clause("the signup of `${a.name}`", Translate.row_value(own, stored_graph(signup, "an access method"), [Translate.Binding.Params], Translate.variable)),
				cond: within_clause("the signin of `${a.name}`", Translate.render(own, stored_graph(signin, "an access method"), [Translate.Binding.Params, Translate.table_row(t.name, is_edge(t.kind))], Translate.variable)),
				token: Err(Unset),
				session: Err(Unset),
			},
		)

		## The login of a new record user (`Session.open!`): `signup` with
		## the variables of the record.
		sign_up : Access(up, on), { ns : Str, db : Str }, up -> Login where [up.Cbor.Writable]
		sign_up = |Access.(a), at, vars| SignUp({ access: a.name, ns: at.ns, db: at.db, vars: cbor_entries(vars) })

		## The login of a record user: `signin` with the variables of the record.
		sign_in : Access(up, on), { ns : Str, db : Str }, on -> Login where [on.Cbor.Writable]
		sign_in = |Access.(a), at, vars| SignIn({ access: a.name, ns: at.ns, db: at.db, vars: cbor_entries(vars) })
	}

	## An access method of this name. The annotation on the binding fixes
	## its variables.
	access : Str -> Access(up, on)
	access = |name| Access.({ name: name })

	## The definition of an access method being built (`Access.define`).
	AccessDef :: { name : Str, table : Str, content : Try(Str, Error), cond : Try(Str, Error), token : Try(U64, [Unset]), session : Try(U64, [Unset]) }.{

		## How long a token of a signup or a signin is valid:
		## `DURATION FOR TOKEN`. SurrealDB's default is 1 hour.
		token_for : AccessDef, Duration -> AccessDef
		token_for = |AccessDef.(a), Duration.(d)| AccessDef.({ ..a, token: Ok(d.nanos) })

		## How long a session that signed in is valid: `DURATION FOR
		## SESSION`. SurrealDB's default is no end.
		session_for : AccessDef, Duration -> AccessDef
		session_for = |AccessDef.(a), Duration.(d)| AccessDef.({ ..a, session: Ok(d.nanos) })

		## The definition, ready for `schema`.
		done : AccessDef -> Defined
		done = |AccessDef.(a)| Schema.access(a)
	}

	## The schema script of every function and table: functions, tables,
	## fields, indexes, events, in that order. The list is also where a link
	## finds its target table.
	schema : List(Defined) -> Try(Str, Error)
	schema = |defined| Schema.script(defined)

	## What a person reads before a migration file runs (`Plan.warnings`).
	## Each is a `-- warning:` line of the file.
	Warning : Migrate.Warning

	## The diff from the snapshot `from` (the text of `schema` that the
	## migrations make, "" for an empty database) to the schema `to`, for
	## SurrealDB 4 at compatibility level 4. Only a statement that is new
	## or changed is in it, so an index or a view that did not change is
	## not built again. A rename is a drop and a definition.
	plan : Str, List(Defined) -> Try(Plan, Error)
	plan = |from, to| {
		old = Migrate.lines(from)
		new = Schema.script_lines(to)?
		Ok(Plan.({ p: { steps: Schema.migration_steps(old, new, Schema.field_infos(to)?), old, new, from, replaces: [] } }))
	}

	## Whether the snapshot is the schema: `Ok` with the tables and fields
	## that a `KeepData` file kept and the schema dropped, else a
	## `Migration` error with `Unplanned` and the statements that a new
	## file needs. For an `expect` next to the schema.
	check : Str, List(Defined) -> Try({ pending_drops : List(Str) }, Error)
	check = |snapshot, defined| {
		planned = Surreal.plan(snapshot, defined)?
		match planned.statements(KeepData).join() {
			[] => Ok({ pending_drops: planned.dropped() })
			pending => Err(Migration({ name: "", problem: Unplanned(pending) }))
		}
	}

	## The steps of `plan`. A removed index, event, function, analyzer,
	## access or view loses no row, and always runs. A dropped table or
	## field loses its data, so it runs only with `DropData`. With
	## `KeepData` it stays in the database and in the snapshot.
	##
	## | Change | Statement |
	## | --- | --- |
	## | New field that is not optional, on a table that was there | `DEFINE FIELD .. MIGRATE EXISTING ROWS AS .. USING <DEFAULT>` |
	## | A type that does not take every old value | `MIGRATE EXISTING ROWS .. USING <type> $value FALLBACK <DEFAULT>` |
	## | Dropped field (`DropData`) | `REMOVE FIELD` (level 4 clears the values) |
	##
	## With no `DEFAULT`, or no cast, the file has a `-- reify: edit` line
	## and a placeholder: the runner refuses it until a person writes the
	## value and removes the line.
	Plan :: { p : Migrate.Plan }.{

		## The statements of each section, in order, with no `;`. Section 2
		## has what SurrealDB 4 refuses in the transaction of section 1:
		## an index on a table that section 1 writes to or migrates, a view
		## over a migrated table, a `REBUILD INDEX`.
		statements : Plan, [KeepData, DropData] -> List(List(Str))
		statements = |Plan.(m), mode| Migrate.sections(m.p, mode).map(|part| part.map(|i| i.line))

		## The tables and the fields (`table.path`) that the schema dropped:
		## what `DropData` removes with their data.
		dropped : Plan -> List(Str)
		dropped = |Plan.(m)| Migrate.dropped(m.p)

		## What a person reads before the file runs.
		warnings : Plan -> List(Warning)
		warnings = |Plan.(m)| Migrate.warnings(m.p)

		## Whether the plan has no statement.
		is_empty : Plan, [KeepData, DropData] -> Bool
		is_empty = |Plan.(m), mode| Migrate.sections(m.p, mode).is_empty()

		## The migration file `name`: the header, the warnings as comments,
		## the sections split by `-- reify: commit`, and a `-- reify: edit`
		## line before each statement that needs a value.
		to_file : Plan, Str, [KeepData, DropData] -> Str
		to_file = |Plan.(m), name, mode| Migrate.file(name, m.p, mode)

		## The snapshot after the file: the statements of the schema, with
		## no `MIGRATE` clause. With `KeepData` the dropped tables and
		## fields stay in it.
		snapshot : Plan, [KeepData, DropData] -> Str
		snapshot = |Plan.(m), mode| Migrate.snapshot(m.p, mode)

		## A squashed file: the header names the files it replaces. A
		## database that applied all of them records it and does not run
		## it; an empty database runs it.
		replacing : Plan, List(Str) -> Plan
		replacing = |Plan.(m), names| Plan.({ p: { ..m.p, replaces: names } })

		## Each section as one transaction, for `Session.run!`: all of a
		## section runs, or none. A statement that fails is a `Server`
		## error. A plan that needs an edit is a `Migration` error.
		prepare : Plan, [KeepData, DropData] -> Try(List(Prepared({})), Error)
		prepare = |Plan.(m), mode| {
			parts = Migrate.sections(m.p, mode)
			if parts.any(|part| part.any(|i| i.edit.is_ok())) {
				return Err(Migration({ name: "", problem: Edit }))
			}
			Ok(parts.map(|part| prepared_of(Ok({ statement: statement_of(Str.join_with(part.map(|i| i.line), ";\n")), slots: [], count: part.len(), atomic: Whole, read: |_| Ok({}) }))))
		}
	}

	## A migration file, read for `Session.migrate!`: its name, its text
	## (`import "db/migrations/0002_bin_size.surql" as m0002 : Str`), its
	## sections and its checksum.
	Migration :: { file : Migrate.File }.{
		is_eq : _

		name : Migration -> Str
		name = |Migration.(m)| m.file.name

		## The SHA-256 of the text, as the history records it.
		checksum : Migration -> Str
		checksum = |Migration.(m)| m.file.checksum

		## The count of the sections: each is one transaction.
		sections : Migration -> U64
		sections = |Migration.(m)| m.file.sections.len()

		## The files that a squashed file replaces.
		replaces : Migration -> List(Str)
		replaces = |Migration.(m)| m.file.replaces
	}

	## Reads a migration file: its header (`-- reify-surrealdb migration
	## <name> target V4 from <hash> [replaces <name> ..]`) must name
	## `name`. A `-- reify: edit` line is a `Migration` error with `Edit`;
	## a `BEGIN`, `COMMIT` or `CANCEL` is a `Text` error, as the runner
	## makes each section a transaction, and so is an index on a table
	## that the same section writes to. A file with `target V3`, for
	## SurrealDB 3 (0.0.3 and before), is a `Migration` error with `Legacy`.
	migration : Str, Str -> Try(Migration, Error)
	migration = |name, text| Migrate.parse(name, text).map_ok(|file| Migration.({ file: file }))

	## What `Session.migrate!` did: the files it ran, the squashed files
	## it recorded and did not run, and the records of the history that no
	## file of the list has (a newer app applied them).
	Applied : { ran : List(Str), adopted : List(Str), ahead : List(Str) }

	# ======================================================== queries

	## A clause is written when its statement is, because the spelling of a
	## parameter is chosen then: `$name` for a driver, the literal for a script.
	Clause : (Str -> Str) -> Try(Str, Error)

	## The row of a query at the two records a statement reads it at:
	## `now` is the row the statement reads, and `before` is that row
	## before the write that a live query reports, `$before`. `reach` is
	## the row as a live query reads it, for the tables that the clauses
	## read (`Translate.reads`).
	Rows : { now : Try(Translate.Binding, Error), before : Try(Translate.Binding, Error), reach : Translate.Reach }

	## A filter is written when its statement is, over one of the `Rows`.
	## The result is a binding, so a live query can put an infix filter in
	## parentheses.
	Filter : [Now, Before], (Str -> Str) -> Try(Translate.Binding, Error)

	## A query over the rows of a table, taking parameters of type `p`.
	## `source` says what a clause reads its row as, now and before a write
	## (see `Rows`): the table row, the pair of a row and its edges once
	## `outgoing` or `incoming` ran, or a result row of `Selected.query`. It is an error when that result row has no
	## SurrealQL form. `watched` are the other tables that a live query
	## watches (see `Watched`).
	Query(p, row) :: {
		target : Target,
		source : Rows,
		filters : List(Filter),
		watched : List(Watched),
		slots : List(Slot),
	}.{

		## The cut of filters, projections and keys (see `Surreal.code_primitives`).
		code_primitives = cut

		## Keep the rows the function is true for: `WHERE`.
		filter : Query(p, row), Code(row -> Bool) -> Query(p, row)
		filter = |Query.(q), predicate| {
			base = q.source
			clause = |at, param| within_clause("`filter`", Translate.evaluate(own, predicate.graph(), [pick(base, at)?], spelled(predicate, param)))
			Query.({ ..q, filters: q.filters.append(clause), slots: q.slots.concat(slots_of(predicate)), watched: reached_watches(q.watched, predicate.graph(), [base.reach], narrowed(predicate.graph(), base.now.map_ok(|row| [row]))) })
		}

		## `filter`, where the predicate may call the functions of another
		## package's types and read values of them from around itself. Each
		## extension gives the SurrealQL of some of those functions, by
		## their ids (`Surreal.extension`), and a captured value is bound as
		## its own `encoder_for` writes it in `Encode.Bind`: a value of an
		## opaque type is the value its encoder writes. A captured `Id` or
		## `Datetime` needs no encoder.
		filter_with : Query(p, row), List(Extension), Code.Binds(Code(row -> Bool), Encode.Bind) -> Query(p, row)
		filter_with = |Query.(q), extensions, predicate| {
			base = q.source
			clause = |at, param| within_clause("`filter_with`", Translate.evaluate(own.concat(extensions), predicate.graph(), [pick(base, at)?], spelled(predicate, param)))
			Query.({ ..q, filters: q.filters.append(clause), slots: q.slots.concat(keyed_slots(predicate, Any, Bool.True)), watched: reached_watches(q.watched, predicate.graph(), [base.reach], narrowed(predicate.graph(), base.now.map_ok(|row| [row]))) })
		}

		## A filter that reads the parameter record, its first argument. Each
		## field it reads is a `$name` that `prepare` gives a `LET`.
		filter_by : Query(p, row), Code((p, row -> Bool)) -> Query(p, row)
		filter_by = |Query.(q), predicate| {
			base = q.source
			clause = |at, param| within_clause("`filter_by`", Translate.evaluate(own, predicate.graph(), [Translate.Binding.Params, pick(base, at)?], spelled(predicate, param)))
			Query.({ ..q, filters: q.filters.append(clause), slots: q.slots.concat(slots_of(predicate)), watched: reached_watches(q.watched, predicate.graph(), [Translate.Reach.Nothing, base.reach], narrowed(predicate.graph(), base.now.map_ok(|row| [Translate.Binding.Params, row]))) })
		}

		## The row and its edges in `edges`, `->edges`. The row becomes the pair
		## `(row, List(edge))`, which a clause takes apart with a tuple pattern.
		## The edge row's `from` links to `a`, so edges that leave another
		## table are a type error.
		outgoing : Query(p, a), Table({ from : Link(a), ..e }) -> Query(p, (a, List({ from : Link(a), ..e })))
		outgoing = |Query.(q), Table.(t)| {
			rows = { now: with_edges(q.source.now, |at| Translate.edge_list(at, "->", t.name, ends_of(t.kind))), before: with_edges(q.source.before, |at| Translate.edge_list(at, "->", t.name, ends_of(t.kind))), reach: Translate.with_edges(q.source.reach, "->", t.name) }
			Query.({ ..q, source: rows, watched: add_watched(q.watched, Edge({ name: t.name, node: "in" })) })
		}

		## As `outgoing`, with the edges that point at the row: `<-edges`. The
		## edge row's `to` links to `b`.
		incoming : Query(p, b), Table({ to : Link(b), ..e }) -> Query(p, (b, List({ to : Link(b), ..e })))
		incoming = |Query.(q), Table.(t)| {
			rows = { now: with_edges(q.source.now, |at| Translate.edge_list(at, "<-", t.name, ends_of(t.kind))), before: with_edges(q.source.before, |at| Translate.edge_list(at, "<-", t.name, ends_of(t.kind))), reach: Translate.with_edges(q.source.reach, "<-", t.name) }
			Query.({ ..q, source: rows, watched: add_watched(q.watched, Edge({ name: t.name, node: "out" })) })
		}

		## A second edge table on the row: after `outgoing` or `incoming`,
		## the edges that leave the row in `edges` too. The row becomes the
		## triple `(row, List(e1), List(edge))`. A live query watches both
		## edge tables. For more edge tables, take a read row with an `Out`
		## or `In` field for each.
		and_outgoing : Query(p, (a, List(x))), Table({ from : Link(a), ..e }) -> Query(p, (a, List(x), List({ from : Link(a), ..e })))
		and_outgoing = |Query.(q), Table.(t)| {
			rows = { now: with_edges(q.source.now, |at| Translate.edge_list(at, "->", t.name, ends_of(t.kind))), before: with_edges(q.source.before, |at| Translate.edge_list(at, "->", t.name, ends_of(t.kind))), reach: Translate.with_edges(q.source.reach, "->", t.name) }
			Query.({ ..q, source: rows, watched: add_watched(q.watched, Edge({ name: t.name, node: "in" })) })
		}

		## As `and_outgoing`, with the edges that point at the row.
		and_incoming : Query(p, (b, List(x))), Table({ to : Link(b), ..e }) -> Query(p, (b, List(x), List({ to : Link(b), ..e })))
		and_incoming = |Query.(q), Table.(t)| {
			rows = { now: with_edges(q.source.now, |at| Translate.edge_list(at, "<-", t.name, ends_of(t.kind))), before: with_edges(q.source.before, |at| Translate.edge_list(at, "<-", t.name, ends_of(t.kind))), reach: Translate.with_edges(q.source.reach, "<-", t.name) }
			Query.({ ..q, source: rows, watched: add_watched(q.watched, Edge({ name: t.name, node: "out" })) })
		}

		## The rows whose text matches the terms, by the full-text index:
		## `WHERE body @1@ 'limping'`. The row becomes the pair `(row,
		## hit)`, and the hit reads what the search knows of the row,
		## `search::score(1)` and the highlights: `select(|(n, hit)| { id:
		## n.id, score: hit.score() })`. The library numbers the search,
		## so no clause writes the number. The index, the search and the
		## hit are of one row type, so a query has one search, and no
		## `nearest`. The Roc meaning of which rows it keeps is
		## `Analyzer.matches`. A live query refuses it.
		search : Query(p, row), FullText(row), Str -> Query(p, (row, Hit))
		search = |Query.(q), FullText.(f), terms| {
			clause = |at, _| match at {
				Now => Ok(Translate.Binding.Infix("${f.path?} @1@ ${Ql.quote(terms)}"))
				Before => Err(live_search)
			}
			Query.({ ..q, source: paired(q.source, f.table, "1"), filters: q.filters.append(clause) })
		}

		## The `k` rows whose vector is nearest the probe, by the vector
		## index: `WHERE embedding <|2,40|> [..]` (`Approx`), or `<|2,COSINE|>`
		## (`Exact`), among the rows that the other filters keep (verified).
		## The row becomes the pair `(row, near)`, and `near.distance()`
		## is `vector::distance::knn()`. A probe of another dimension than
		## the index's is refused. The Roc meaning of `Exact` is the rows
		## sorted by their `Vector` distance from the probe, the first `k`.
		## A live query refuses it.
		nearest : Query(p, row), VectorIndex(row), List(F64), Knn -> Query(p, (row, Near))
		nearest = |Query.(q), VectorIndex.(v), probe, knn| {
			clause = |at, _| match at {
				Now => {
					if probe.len() != v.dimension {
						return Err(Unsupported("the probe of `nearest` has ${probe.len().to_str()} numbers, and the vector index of `${v.table}.${v.path?}` has the dimension ${v.dimension.to_str()}"))
					}
					how = match knn {
						Approx({ k, ef }) => "${k.to_str()},${ef.to_str()}"
						Exact(k) => "${k.to_str()},${distance_name(v.distance)}"
					}
					Ok(Translate.Binding.Infix("${v.path?} <|${how}|> ${Ql.literal(Ql.Value.Array(probe.map(|x| Ql.Value.Float(x))))}"))
				}
				Before => Err(live_search)
			}
			Query.({ ..q, source: paired(q.source, v.table, "vector::distance::knn()"), filters: q.filters.append(clause) })
		}

		## The rows of one series of a time series with `from <= time < to`:
		## `FROM t:[series, from]..[series, to]`. It reads the range of keys, not
		## the whole table. A query takes one `between`.
		between : Query(p, { id : TimeKey(s), ..others }), s, Datetime, Datetime -> Query(p, { id : TimeKey(s), ..others }) where [s.encoder_for : Encode.Format -> (s, Encode.State -> Try(Encode.State, []))]
		between = |Query.(q), series, from, to| {
			range = match q.target {
				Whole(name) => key_range(name, TimeKey.({ series, time: from }), TimeKey.({ series, time: to }))
				Range(_) => Err(Unsupported("a query takes one `between`"))
				Record(_) => Err(Unsupported("`between` reads a range of keys of a table, and this query reads the record of one key"))
				Sub(_) => Err(Unsupported("`between` reads a range of keys of a table, and this query reads a subquery"))
			}
			Query.({ ..q, target: Range(range) })
		}

		## The columns of the result. The function returns a record, and its
		## fields name the columns, in name order: `SELECT e AS f, ..`. A whole
		## record is one column per field of its Roc type: `select(|r| r)` is
		## `SELECT record::id(id) AS id, name, ..`, where `id` is the key, as
		## the row holds it, and a field that SurrealDB has but the type does
		## not is not selected. The same holds for a linked row
		## (`|p| p.owner.get()`) and an object (`|v| v.contact`).
		select : Query(p, row), Code(row -> out) -> Selected(p, out)
		select = |Query.(q), projection| {
			base = q.source
			ty = projection.graph().root_row().result
			columns = |param| within_clause("`select`", column_list(within_clause("`select`", Translate.evaluate(own, projection.graph(), [base.now?], spelled(projection, param)))?, ty))
			value = |param| within_clause("`select`", row_value(within_clause("`select`", Translate.evaluate(own, projection.graph(), [base.now?], spelled(projection, param)))?, ty))
			selected_of({ ..q, slots: q.slots.concat(slots_of(projection)), watched: reached_watches(q.watched, projection.graph(), [base.reach], narrowed(projection.graph(), base.now.map_ok(|row| [row]))) }, { columns, value, intrinsic: intrinsic_columns(projection.graph()) }, by_name, [], { ty, over: Projected(projected_rows(base, projection.graph())), nested: nested_row(ty) })
		}

		## One value per row: `SELECT VALUE e`. A whole row of a table, as
		## `|r| r` or `|e| e.to.get()`, is the object of the fields of its
		## Roc type, `SELECT VALUE { id: record::id(id), name, .. }`, so that
		## `id` is the key, as `select(|r| r)` gives it. `order_by` reads a
		## value that is a path of fields of the source row (see `ResultOrder`).
		select_value : Query(p, row), Code(row -> v) -> Selected(p, v)
		select_value = |Query.(q), projection| {
			base = q.source
			ty = projection.graph().root_row().result
			value = |param| match within_clause("`select_value`", Translate.evaluate(own, projection.graph(), [base.now?], spelled(projection, param)))? {
				Row({ of: Doc(named), at, edge }) => row_value(Translate.Binding.Row({ at, of: Doc(named), edge }), ty)
				other => Translate.text(other)
			}
			columns = |param| Ok("VALUE ${value(param)?}")
			results = |key, param| {
				path = field_path(projection.graph()) and !reads_id(projection.graph()) and field_path(key)
				whole = projection.graph().root_row().nodes.is_empty() and key.root_row().nodes.is_empty()
				if !path or whole {
					return Err(value_order)
				}
				match Translate.evaluate(own, projection.graph(), [base.now?], spelled(projection, param))? {
					Row(r) => Ok(Translate.Binding.Row({ ..r, of: Obj }))
					other => Ok(other)
				}
			}
			selected_of({ ..q, slots: q.slots.concat(slots_of(projection)), watched: reached_watches(q.watched, projection.graph(), [base.reach], narrowed(projection.graph(), base.now.map_ok(|row| [row]))) }, { columns, value, intrinsic: intrinsic_columns(projection.graph()) }, results, [], { ty, over: Projected(projected_rows(base, projection.graph())), nested: nested_row(ty) })
		}

		## Group the rows by what the function returns: a value, or a record of
		## them.
		group_by : Query(p, row), Code(row -> k) -> Grouped(p, row, k)
		group_by = |query, key| Grouped.({ query: query, key: key })

		## The totals of the rows, as one result: `GROUP ALL`. The function
		## takes the rows as a `List(row)`, as the one of `aggregate` does:
		## `rows.len()` is `count()`, and `rows.map(f).sum()` is
		## `math::sum(f)`. The result is one row also for no rows, with the
		## values that SurrealDB gives (verified on 3.3.4): a count and a
		## sum are 0, and a mean, a standard deviation and a variance are
		## `NaN`. That is why `group_by(|_| {})` is refused: a group of no
		## rows is no group. `math::median` of no rows is `NONE`, so it is
		## refused.
		totals : Query(p, row), Code(List(row) -> out) -> Totals(p, out)
		totals = |query, per_total| totalled(query, per_total)

		## The whole rows of the query: the `prepare` of `select(|r| r)`
		## (see `Selected.prepare`).
		prepare : Query(p, row), p -> Prepared(List(row)) where [p.encoder_for : Encode.Format -> (p, Encode.State -> Try(Encode.State, [])), row.Cbor.Readable(errs)]
		prepare = |query, params| whole_of(query).prepare(params)

		## The whole rows of a query that has no parameter: `prepare({})`.
		ready : Query({}, row) -> Prepared(List(row)) where [row.Cbor.Readable(errs)]
		ready = |query| whole_of(query).prepare({})

		## The whole row of a query of one key: `select(|r| r)` and
		## `Selected.prepare_one`.
		prepare_one : Query(p, row), p -> Prepared(Try(row, [NotFound])) where [p.encoder_for : Encode.Format -> (p, Encode.State -> Try(Encode.State, [])), row.Cbor.Readable(errs)]
		prepare_one = |query, params| whole_of(query).prepare_one(params)

		## `prepare_one` of a query that has no parameter.
		ready_one : Query({}, row) -> Prepared(Try(row, [NotFound])) where [row.Cbor.Readable(errs)]
		ready_one = |query| whole_of(query).prepare_one({})

		## The whole rows of the query, kept current: `select(|r| r)` and
		## `Selected.live`.
		live : Query(p, row), p, List(Defined) -> Watch(row) where [p.encoder_for : Encode.Format -> (p, Encode.State -> Try(Encode.State, []))]
		live = |query, params, tables| whole_of(query).live(params, tables)

		## `live` of a query that has no parameter.
		ready_live : Query({}, row), List(Defined) -> Watch(row)
		ready_live = |query, tables| whole_of(query).live({}, tables)

		## Escape hatch: the patches of each write to the stored rows that the
		## filters keep, `LIVE SELECT DIFF`. It takes no projection, so it is
		## on `Query`. A row that no longer matches sends nothing, and a row
		## that starts to match sends only the ops of the write. It watches
		## the table only, not the tables that the filters read.
		live_diff : Query(p, row), p -> Try(DiffWatch(row), Error) where [p.encoder_for : Encode.Format -> (p, Encode.State -> Try(Encode.State, []))]
		live_diff = |Query.(q), params| {
			name = Ql.ident(whole_table(q.target)?)
			if q.watched.any(is_edge_of) {
				return Err(Unsupported("a DIFF live query has no edges: its patches are of the stored row; watch the edges with `live`"))
			}
			match q.source.now? {
				Row({ of: Doc(_), .. }) => {}
				_ => return Err(Unsupported("`live_diff` sends patches of the stored row, so it reads a table: take it on `Surreal.from(table)` with filters only"))
			}
			lets = lets_of(params)?
			param = Translate.variable
			now = all_of(q.filters.map_try(|f| f(Now, param))?)?
			Ok(DiffWatch.({ lets, live: "LIVE SELECT DIFF FROM ${name}${where_text(now)?}" }))
		}
	}

	## Rows grouped by a key, waiting for what to compute per group.
	Grouped(p, row, k) :: { query : Query(p, row), key : Code(row -> k) }.{

		## The cut of the per-group function, which reads the group's rows
		## (see `Surreal.code_primitives`).
		code_primitives = cut

		## One result row per group. The function takes the key and the group's
		## rows as a `List(row)`: `rows.len()` is `count()`, and
		## `rows.map(f).sum()` is `math::sum(f)`.
		aggregate : Grouped(p, row, k), Code((k, List(row) -> out)) -> Selected(p, out)
		aggregate = |grouped, per_group| aggregated(grouped, per_group, Bool.False)
	}

	## The one row of `Query.totals`. It has no `filter`, `order_by`,
	## `limit` or `live`: a row that is always there is not a list.
	Totals(p, out) :: Selected(p, out).{

		## The statement, `GROUP ALL`.
		to_surql : Totals(p, out) -> Try(Str, Error)
		to_surql = |Totals.(selected)| Selected.render(selected, Translate.variable).map_ok(group_all)

		## As `Selected.prepare`, and the result is the row itself: the
		## database always gives one.
		prepare : Totals(p, out), p -> Prepared(out) where [p.encoder_for : Encode.Format -> (p, Encode.State -> Try(Encode.State, [])), out.Cbor.Readable(errs)]
		prepare = |Totals.(selected), params| {
			Selected.(s) = selected
			rows = result_rows(0)
			read = |results| match rows(results)? {
				[one] => Ok(one)
				more => Err(Wire("`GROUP ALL` returned ${more.len().to_str()} rows instead of one"))
			}
			prepared_of(bound_statement(|param| Selected.render(selected, param).map_ok(group_all), params).map_ok(|statement| { statement: with_intrinsic(statement, selected), slots: s.slots, count: 1, atomic: No, read }))
		}

		## `prepare` of a query that has no parameter.
		ready : Totals({}, out) -> Prepared(out) where [out.Cbor.Readable(errs)]
		ready = |totals| totals.prepare({})
	}

	## What `order_by` reads a result row as, given the key: the binding of
	## the row, or why SurrealDB cannot order by the key. `ORDER BY` takes a
	## field path only, and it reads it as SurrealDB reads it (verified on
	## 3.3.4): a top-level name is a column of the result, and a longer path
	## is read off the source row. A call is a parse error, and a path into
	## an aliased column, or through a record link (`owner.name`), is
	## accepted and does not order: the rows come in the same order for
	## `ASC` and `DESC`.
	ResultOrder : Code.Graph, (Str -> Str) -> Try(Translate.Binding, Error)

	## A query with its result columns fixed. `fetches` are the paths of
	## `Unchecked.fetch`. `value` is a result row as one SurrealQL value, the
	## `row` of a live query, or why it has none. `results` is what
	## `order_by` reads a result row as, and `rows` is what `filter` and
	## `query` read it as.
	Selected(p, out) :: {
		target : Target,
		filters : List(Filter),
		watched : List(Watched),
		fetches : List(Str),
		groups : List(Clause),
		columns : Clause,
		value : Clause,
		intrinsic : List(Str),
		results : ResultOrder,
		rows : ResultRow,
		order : List(Clause),
		limit : [Unlimited, Limit(Try(Str, Error))],
		start : [FromFirst, Start(Try(Str, Error))],
		slots : List(Slot),
	}.{

		## The cut of a filter of the result rows (see `Surreal.code_primitives`).
		code_primitives = cut

		## Order by one column of a result row: `|r| r.rate`. Several calls
		## order by the first, then the second. SurrealDB's `ORDER BY` takes a
		## field path, so any other key is refused when the statement is
		## built (see `ResultOrder`).
		order_by : Selected(p, out), Code(out -> k), [Asc, Desc] -> Selected(p, out)
		order_by = |Selected.(s), key, direction| {
			clause = |param| {
				result = (s.results)(key.graph(), param)?
				parts = parts_of(within_clause("`order_by`", Translate.evaluate(own, key.graph(), [result], spelled(key, param)))?)?
				suffix = match direction {
					Asc => ""
					Desc => " DESC"
				}
				Ok(Str.join_with(parts.map(|part| "${part}${suffix}"), ", "))
			}
			Selected.({ ..s, order: s.order.append(clause), slots: s.slots.concat(slots_of(key)) })
		}

		## Keep the result rows the function is true for. Before a group, a
		## limit or a start, a result row is one source row projected, so
		## this is a filter of the source row in the same `WHERE`: the
		## predicate reads the projection's fields. After one, it is the
		## `WHERE` of an outer query over a subquery (`Selected.query`). After
		## a group, that is SQL's `HAVING`.
		filter : Selected(p, out), Code(out -> Bool) -> Selected(p, out)
		filter = |selected, predicate| {
			Selected.(s) = selected
			match (s.rows.over, s.limit, s.start) {
				(Projected(fields), Unlimited, FromFirst) => {
					clause = |at, param| within_clause("`filter`", Translate.evaluate(own, predicate.graph(), [pick(fields, at)?], spelled(predicate, param)))
					Selected.({ ..s, filters: s.filters.append(clause), slots: s.slots.concat(slots_of(predicate)), watched: reached_watches(s.watched, predicate.graph(), [fields.reach], narrowed(predicate.graph(), fields.now.map_ok(|row| [row]))) })
				}
				_ => whole_rows(Selected.query(selected).filter(predicate), s.rows.ty)
			}
		}

		## The result rows as the rows of a new query, which every `Query`
		## method reads as the type `out`:
		##
		## | The result | The new query |
		## | --- | --- |
		## | A projection with no order, limit, start or fetch | The same `SELECT`. A clause reads the projection's fields over the source row |
		## | Any other | A subquery, `FROM (SELECT ..)`: the target `Sub` |
		##
		## The target keeps the two apart, because a `LIVE SELECT` takes no
		## subquery.
		query : Selected(p, out) -> Query(p, out)
		query = |selected| {
			Selected.(s) = selected
			match (s.rows.over, s.order, s.limit, s.start, s.fetches) {
				(Projected(fields), [], Unlimited, FromFirst, []) => Query.({ target: s.target, source: fields, filters: s.filters, watched: s.watched, slots: s.slots })
				_ => Query.({ target: Sub(|param| Selected.render(selected, param).map_ok(|inner| "(${inner})")), source: { now: Ok(s.rows.nested), before: Err(Unsupported("a row of a subquery has no `$before`")), reach: Translate.Reach.Nothing }, filters: [], watched: [], slots: s.slots })
			}
		}

		## At most this many rows: `LIMIT n`. The rows after it are a
		## `Limited`, which has no `order_by`, `limit` or `start` (see
		## `Started`).
		limit : Selected(p, out), Code(U64) -> Limited(p, out)
		limit = |Selected.(s), count| Limited.(Selected.({ ..s, limit: Limit(count_text(count)), slots: s.slots.concat(slots_of(count)) }))

		## Skip this many rows first: `START n`. The rows after it are a
		## `Started`, which takes a `limit` and no `order_by` or `start`.
		start : Selected(p, out), Code(U64) -> Started(p, out)
		start = |Selected.(s), count| Started.(Selected.({ ..s, start: Start(count_text(count)), slots: s.slots.concat(slots_of(count)) }))

		## The statement with a `$name` for each parameter it reads.
		to_surql : Selected(p, out) -> Try(Str, Error)
		to_surql = |selected| Selected.render(selected, Translate.variable)

		## The statement with a `LET` for each field of the parameter
		## record, and the type of its result: the result rows, each read
		## as `out`. The record is the type the filters read, so a
		## parameter a filter reads is a field the record has.
		## `Session.run!` runs it, and `Prepared.statement` is its text.
		prepare : Selected(p, out), p -> Prepared(List(out)) where [p.encoder_for : Encode.Format -> (p, Encode.State -> Try(Encode.State, [])), out.Cbor.Readable(errs)]
		prepare = |selected, params| {
			Selected.(s) = selected
			prepared_of(bound_statement(|param| Selected.render(selected, param), params).map_ok(|statement| { statement: with_intrinsic(statement, selected), slots: s.slots, count: 1, atomic: No, read: result_rows(0) }))
		}

		## `prepare` of a query that has no parameter: `prepare({})`.
		ready : Selected({}, out) -> Prepared(List(out)) where [out.Cbor.Readable(errs)]
		ready = |selected| selected.prepare({})

		## `prepare` of a query of one key (`Table.at`): the row, or
		## `NotFound` when the table has no row with the key. Any other
		## query can return several rows, so it is refused.
		prepare_one : Selected(p, out), p -> Prepared(Try(out, [NotFound])) where [p.encoder_for : Encode.Format -> (p, Encode.State -> Try(Encode.State, [])), out.Cbor.Readable(errs)]
		prepare_one = |selected, params| {
			Selected.(s) = selected
			rows = result_rows(0)
			read = |results| match rows(results)? {
				[] => Ok(Err(NotFound))
				[one] => Ok(Ok(one))
				more => Err(Wire("the record of one key returned ${more.len().to_str()} rows"))
			}
			built = match s.target {
				Record(_) => bound_statement(|param| Selected.render(selected, param), params)
				Whole(_) | Range(_) | Sub(_) => Err(Unsupported("`prepare_one` reads the row of one key, a query from `Table.at`; this query can return several rows: take `prepare`"))
			}
			prepared_of(built.map_ok(|statement| { statement: with_intrinsic(statement, selected), slots: s.slots, count: 1, atomic: No, read }))
		}

		## `prepare_one` of a query that has no parameter.
		ready_one : Selected({}, out) -> Prepared(Try(out, [NotFound])) where [out.Cbor.Readable(errs)]
		ready_one = |selected| selected.prepare_one({})

		## The rows of the query, kept current: the twin of `prepare`. A
		## `LIVE SELECT` on the table, and one on each other table that
		## the rows read (see `Watched`), report every write that changes
		## the result. Each notice holds the row and the filter `now`. The
		## filter is also read on `$before`, so a row that no longer
		## matches is reported:
		##
		## `LIVE SELECT VALUE { row: <row>, now: <p> } FROM t WHERE <p> OR ($before IS NOT NONE AND <p on $before>)`
		##
		## The guard is necessary: a filter that reads `$before` of a
		## `CREATE` fails, and SurrealDB then sends nothing (verified).
		## A filter that reads the row only through its id and its edges
		## has the same value before and after a write of the row, so the
		## statement tests it once, and each notice has `now: true`:
		##
		## `LIVE SELECT VALUE { row: <row>, now: true } FROM t WHERE <p>`
		## `tables` are the definitions that `Surreal.schema` takes: a link
		## of the row finds its table there, as in the schema.
		live : Selected(p, out), p, List(Defined) -> Watch(out) where [p.encoder_for : Encode.Format -> (p, Encode.State -> Try(Encode.State, []))]
		live = |selected, params, tables| Watch.(Code.Bound.of(watching(selected, params, tables)))

		## `live` of a query that has no parameter: `live({}, tables)`.
		ready_live : Selected({}, out), List(Defined) -> Watch(out)
		ready_live = |selected, tables| selected.live({}, tables)

		## What `live` builds.
		watching : Selected(p, out), p, List(Defined) -> Try({ lets : List({ name : Str, value : Ql.Value }), slots : List(Bind), lives : List({ role : Role, surql : Str }), snapshot : Str }, Error) where [p.encoder_for : Encode.Format -> (p, Encode.State -> Try(Encode.State, []))]
		watching = |selected, params, tables| {
			Selected.(s) = selected
			name = Ql.ident(live_table(selected)?)
			lets = lets_of(params)?
			param = Translate.variable
			row = (s.value)(param)?
			now = all_of(s.filters.map_try(|f| f(Now, param))?)?
			before = all_of(s.filters.map_try(|f| f(Before, param))?)?
			now_text = condition_text(now)?
			(watched, node_now) = match (now, before) {
				(When(p), When(q)) =>
					if keyed_only(Translate.text(q)?) {
						(" WHERE ${Translate.text(p)?}", "true")
					} else {
						(" WHERE ${Translate.operand(p)?} OR ($before IS NOT NONE AND ${Translate.operand(q)?})", now_text)
					}
				_ => ("", now_text)
			}
			node = { role: Node, surql: "LIVE SELECT VALUE { row: ${row}, now: ${node_now} } FROM ${name}${watched}" }
			edges = s.watched.keep_oks(
				|w| match w {
					Edge(e) => Ok({ role: Edge, surql: "LIVE SELECT VALUE { ref: ${e.node}, node: (SELECT VALUE { row: ${row}, now: ${now_text} } FROM ONLY $parent.${e.node}) } FROM ${Ql.ident(e.name)}" })
					LinkAt(_) | Rows(_) | Near(_) => Err(NotEdge)
				},
			)
			reads = read_lives(s.watched, Schema.tables(tables), "SELECT VALUE { ref: id, row: ${row}, now: ${now_text} }", name)?
			snapshot = "SELECT VALUE { ref: id, row: ${row} } FROM ${name}${where_text(now)?}"
			Ok({ lets, slots: binds_of(s.slots)?, lives: [node].concat(edges).concat(reads), snapshot })
		}

		## Escape hatch: the server's own events for the rows of the query.
		## There is no snapshot and no `$before`, so a row that no longer
		## matches sends nothing, a row that starts to match is `Updated`,
		## and a write to an edge table, or to a table that the rows read,
		## sends nothing.
		live_raw : Selected(p, out), p -> Try(RawWatch(out), Error) where [p.encoder_for : Encode.Format -> (p, Encode.State -> Try(Encode.State, []))]
		live_raw = |selected, params| {
			Selected.(s) = selected
			name = Ql.ident(live_table(selected)?)
			lets = lets_of(params)?
			param = Translate.variable
			row = (s.value)(param)?
			now = all_of(s.filters.map_try(|f| f(Now, param))?)?
			Ok(RawWatch.({ lets, live: "LIVE SELECT VALUE ${row} FROM ${name}${where_text(now)?}" }))
		}

		## The text of the `SELECT`. A `LIMIT` or a `START` with no `order_by`
		## and no group gets `ORDER BY id`: SurrealDB 4 reads the rows of a
		## table in no fixed order, so without it the rows of a limit are
		## any rows, not the first by key. A group already gives its rows
		## in the order of the group.
		render : Selected(p, out), (Str -> Str) -> Try(Str, Error)
		render = |Selected.(s), param| {
			run = |clause| clause(param)
			filters = s.filters.map_try(|f| Translate.text(f(Now, param)?))?
			limited = !(is_unlimited(s.limit)) or !(from_first(s.start))
			order = if (s.order.is_empty() and s.groups.is_empty() and limited) ["id"] else s.order.map_try(run)?
			parts = [
				"SELECT ${run(s.columns)?}",
				"FROM ${from_text(s.target, param)?}",
			]
				.concat(keyword("WHERE", if (filters.len() > 1) filters.map(|f| "(${f})") else filters, " AND "))
				.concat(keyword("GROUP BY", s.groups.map_try(run)?, ", "))
				.concat(keyword("ORDER BY", order, ", "))
				.concat(
					match s.limit {
						Unlimited => []
						Limit(n) => ["LIMIT ${n?}"]
					},
				)
				.concat(
					match s.start {
						FromFirst => []
						Start(n) => ["START ${n?}"]
					},
				)
				.concat(keyword("FETCH", s.fetches, ", "))
			Ok(Str.join_with(parts, " "))
		}
	}

	## The rows of a `Selected` after `start`. SurrealQL writes its clauses
	## in one order, `ORDER BY`, `LIMIT`, `START`, and runs them in the order
	## `ORDER BY`, `START`, `LIMIT`. A chain of Roc steps reads as the steps
	## in turn, as `List.drop_first` then `List.take_first`, so the types
	## take only the chains that SurrealQL runs as they read: `order_by` any
	## number of times, then `start` at most once, then `limit` at most once.
	## `.limit(2).order_by(..)` (which SurrealDB runs as order, then limit),
	## `.limit(10).start(20)` and a second `limit` are type errors. `filter`
	## and `query` read the rows as a subquery, so a chain goes on from
	## there: `.limit(3).filter(..)`, `.limit(3).query().select(|r| r).order_by(..)`.
	## A live query takes no limit or start, so neither type has `live`.
	Started(p, out) :: Selected(p, out).{

		## At most this many of the rows: `START s LIMIT n`.
		limit : Started(p, out), Code(U64) -> Limited(p, out)
		limit = |Started.(Selected.(s)), count| Limited.(Selected.({ ..s, limit: Limit(count_text(count)), slots: s.slots.concat(slots_of(count)) }))

		## As `Selected.filter`: the `WHERE` of a query over the rows.
		filter : Started(p, out), Code(out -> Bool) -> Selected(p, out)
		filter = |Started.(selected), predicate| selected.filter(predicate)

		## As `Selected.query`: the rows as a subquery.
		query : Started(p, out) -> Query(p, out)
		query = |Started.(selected)| selected.query()

		to_surql : Started(p, out) -> Try(Str, Error)
		to_surql = |Started.(selected)| selected.to_surql()

		prepare : Started(p, out), p -> Prepared(List(out)) where [p.encoder_for : Encode.Format -> (p, Encode.State -> Try(Encode.State, [])), out.Cbor.Readable(errs)]
		prepare = |Started.(selected), params| selected.prepare(params)

		## `prepare` of a query that has no parameter.
		ready : Started({}, out) -> Prepared(List(out)) where [out.Cbor.Readable(errs)]
		ready = |Started.(selected)| selected.prepare({})
	}

	## The rows of a `Selected` after `limit`: no more `order_by`, `limit`
	## or `start` (see `Started`).
	Limited(p, out) :: Selected(p, out).{

		## As `Selected.filter`: the `WHERE` of a query over the rows.
		filter : Limited(p, out), Code(out -> Bool) -> Selected(p, out)
		filter = |Limited.(selected), predicate| selected.filter(predicate)

		## As `Selected.query`: the rows as a subquery.
		query : Limited(p, out) -> Query(p, out)
		query = |Limited.(selected)| selected.query()

		to_surql : Limited(p, out) -> Try(Str, Error)
		to_surql = |Limited.(selected)| selected.to_surql()

		prepare : Limited(p, out), p -> Prepared(List(out)) where [p.encoder_for : Encode.Format -> (p, Encode.State -> Try(Encode.State, [])), out.Cbor.Readable(errs)]
		prepare = |Limited.(selected), params| selected.prepare(params)

		## `prepare` of a query that has no parameter.
		ready : Limited({}, out) -> Prepared(List(out)) where [out.Cbor.Readable(errs)]
		ready = |Limited.(selected)| selected.prepare({})
	}

	## A write that reads a clause: an update or a delete. `gives` is the
	## row that `prepare` returns: the row after an update, the row before
	## a delete. `edge` is true for a relation table.
	Write(p, row) :: { build : (Str -> Str) -> Try(Str, Error), gives : [After, Before], edge : Bool, slots : List(Slot) }.{

		## The statement with a `$name` for each parameter it reads.
		to_surql : Write(p, row) -> Try(Str, Error)
		to_surql = |Write.(w)| (w.build)(Translate.variable)

		## The statement with a `LET` for each field of the parameter
		## record, and the type of its result: the rows that the write
		## changed, as stored. An update returns each row after the write, and a delete
		## each row before it: `RETURN AFTER`, `RETURN BEFORE`.
		prepare : Write(p, row), p -> Prepared(List(row)) where [p.encoder_for : Encode.Format -> (p, Encode.State -> Try(Encode.State, [])), row.Cbor.Readable(errs)]
		prepare = |Write.(w), params| {
			back = return_clause(w.gives)
			prepared_of(bound_statement(|param| (w.build)(param).map_ok(|text| "${text}${back}"), params).map_ok(|statement| { statement, slots: w.slots, count: 1, atomic: No, read: read_stored(0, w.edge) }))
		}

		## `prepare` of a write that has no parameter.
		ready : Write({}, row) -> Prepared(List(row)) where [row.Cbor.Readable(errs)]
		ready = |write| write.prepare({})
	}

	## A statement ready for a driver: the text with a `$name` per parameter,
	## the value each name is bound to, and the same text with the values
	## written in. `surql` has no final `;`. `intrinsic` names the columns of
	## its result that read an intrinsic (`intrinsic_columns`): SurrealDB
	## computes them, and Roc has no value for them. A captured value is
	## `$_1`, `$_2`, .., numbered across the statements of a request.
	Statement := { surql : Str, lets : List({ name : Str, value : Ql.Value }), inlined : Str, intrinsic : List(Str) }.{

		## What a script holds: a `LET` line per parameter, then the statement.
		to_script : Statement -> Str
		to_script = |Statement.(s)| {
			lets = s.lets.map(|l| "LET $${l.name} = ${Ql.literal(l.value)};")
			Str.join_with(if (s.surql.is_empty()) lets else lets.append("${s.surql};"), "\n")
		}

		## One block of a script that `check.py` runs: the header line, the
		## directive lines (`-- ordered`, `-- roc: ..`), then the script. A
		## statement whose result has columns that read an intrinsic says so
		## in `-- intrinsic: a, b`: a `-- roc:` literal may leave those out,
		## and only those.
		block : Statement, Str, List(Str) -> Str
		block = |Statement.(s), header, directives| {
			named = if (s.intrinsic.is_empty()) [] else ["-- intrinsic: ${Str.join_with(s.intrinsic, ", ")}"]
			Str.join_with(List.concat([header], named).concat(directives).append(Statement.(s).to_script()), "\n")
		}
	}

	## The type of a captured value of a clause, by its place among the
	## slots of the chain (`Code.first_slot` and its own index). `table` is
	## the table that a captured key must name (`Table.at`, `set_at`, ..).
	Slot : { at : U64, ty : Code.Ty, table : [Any, Of(Str)] }

	## A slot of a statement: its type, the table a key must name, and its
	## value once the chain's call gives it.
	Bind : { ty : Code.Ty, table : [Any, Of(Str)], value : [Pending, Given(Code.Value)] }

	## What a terminal call builds. `statement` has a `Translate.slot_mark`
	## for each captured value, and `slots` the type and the value of each,
	## in order. `count` is the statements after the `LET`s, without a
	## `BEGIN` and a `COMMIT`, and `read` reads their results, in order, as
	## `out`. `atomic` says how they run: on their own (`No`), or in a
	## transaction, whose failure is the error of the statement that failed
	## it (`Whole`, an insert) or `Aborted` with its place (`Parts`, the
	## count of the statements of each part of `Transaction.commit`).
	Ready(out) : { statement : Statement, slots : List(Bind), count : U64, atomic : [No, Whole, Parts(List(U64))], read : List(Outcome) -> Try(out, Error) }

	## A statement with the type of its result: what every query and write
	## gives, and what a session runs (`Session.run!`). A query in a
	## function, as `|limit| Surreal.from(meds).filter(|m| m.price < limit).ready()`,
	## is translated once, when the program is built, with a `$_1` for
	## `limit`. Each call gives the statement and the value of `limit`, and
	## the session binds it with a `LET`. A statement that cannot be built
	## holds its error: `run!` and `send!` give it, and `checked` gives it
	## before a session.
	##
	## | Made by | `out` | The result |
	## | --- | --- | --- |
	## | `Selected.prepare` | `List(out)` | The result rows |
	## | `Write.prepare` | `List(row)` | The rows after an update, the rows before a delete |
	## | `Selected.prepare_one` | `Try(out, [NotFound])` | The row of the key of `Table.at`, or `NotFound` |
	## | `Table.create`, `Table.edit` | `List(row)` | The row after a create, a relate or a replace, the row before a delete. A replace or a delete of a row that is not there gives none |
	## | `Table.upsert`, `Table.insert` | `List(row)` | The rows that the write wrote |
	## | `Table.replace` | `List(row)` | The row after the write, or none for a key with no row |
	## | `Table.create_new`, `Table.insert_new` | `List(Created(row, new))` | The rows that the write made, each with the key that the server gave it |
	## | `Prepared.then` | `(Try(a, Error), Try(b, Error))` | The result of each of two prepared statements, which run on their own |
	## | `Transaction.commit` | `(a, b)`, `((a, b), c)`, .. | The results of the statements of one transaction, or one `Aborted` error |
	## | `Surreal.transaction` | `List(out)` | The result of each statement of one transaction, or one `Aborted` error |
	## | `Plan.prepare` | `{}` | Nothing, or the `Server` error of the statement that failed the section |
	Prepared(out) :: Code.Bound(Try(Ready(out), Error)).{

		## The prepared statement, or why it cannot be built: a clause
		## with no SurrealQL form, or a captured value with no SurrealQL
		## value. `session.run!(q)` gives the same error as its result; this
		## gives it before a session, for `?` or `match`.
		checked : Prepared(out) -> Try(Prepared(out), Error)
		checked = |prepared| {
			_ = resolved(ready_of(prepared)?)?
			Ok(prepared)
		}

		## The statement, for a script or a `check.py` block: in a
		## transaction, between `BEGIN` and `COMMIT`, with a `LET` for each
		## parameter and each captured value.
		statement : Prepared(out) -> Try(Statement, Error)
		statement = |prepared| ready_statement(ready_of(prepared)?)

		## The text of the `query` request: a `LET` line for each
		## parameter, then the statements.
		request : Prepared(out) -> Try(Str, Error)
		request = |prepared| prepared.statement().map_ok(Statement.to_script)

		## The reply to `request`, read as `out`. The result of a `LET` is
		## not read. A request that the server refused, or a statement that
		## failed, is a `Server` error, by its kind; a unique index is an
		## `Index`, since no schema is known here (`Session.run!` reads it
		## as the session knows it). Pure.
		result : Prepared(out), List(U8) -> Try(out, Error)
		result = |prepared, bytes| prepared.result_in(bytes, [])

		## `result`, with the unique indexes of a schema (`Schema.unique_indexes`).
		result_in : Prepared(out), List(U8), List(Schema.Known) -> Try(out, Error)
		result_in = |prepared, bytes, indexes| {
			ready = ready_of(prepared)?
			Statement.(s) = ready_statement(ready)?
			outcomes = query_outcomes(bytes, s.lets.len() + ready_size(ready), indexes)?
			read_all(ready, outcomes.drop_first(s.lets.len()))
		}

		## This statement, then the other, in one request: the `LET`s of
		## both, which must give a name one value, then the statements of
		## each, a transaction with its `BEGIN` and `COMMIT`. The captured
		## values of the second are numbered after those of the first. Each
		## runs on its own: the server runs every statement of a request,
		## also after one failed (verified), so the result is the pair of
		## their results, each with its own error. A request that the server
		## refused is the error of the whole. `Transaction` runs them all or
		## none. A statement that cannot be built makes the whole hold its
		## error, the first one's first.
		then : Prepared(a), Prepared(b) -> Prepared((Try(a, Error), Try(b, Error)))
		then = |first, second| Prepared.(Code.Bound.of(then_ready(ready_of(first), ready_of(second))))

		## The prepared statement as the first of a transaction, which
		## `Transaction.then` adds to.
		begin : Prepared(out) -> Transaction(out)
		begin = |prepared| Transaction.(ready_of(prepared).map_ok(|r| { statement: r.statement, slots: r.slots, count: r.count, parts: [r.count], read: r.read }))
	}

	## Prepared statements that run as one transaction: `BEGIN`, the
	## statements of each, `COMMIT`, in one request, on either transport.
	## Either every statement runs and the result is the results of all,
	## or none of their writes stays, and the result is `Aborted` with the
	## place of the statement that failed and its error (verified: a unique
	## index that fails the second write rolls back the first). Made by
	## `Prepared.begin`; `commit` gives the `Prepared`. A part that is a
	## transaction of its own, such as an insert, is a part of this one.
	## A part that cannot be built makes the transaction hold its error.
	Transaction(out) :: Try(Parts(out), Error).{

		## The transaction, then a statement in it: the result is the pair
		## of their results, so each `then` nests the pair once more. A
		## name bound in both must have one value (`Prepared.then`).
		then : Transaction(a), Prepared(b) -> Transaction((a, b))
		then = |Transaction.(built), prepared| {
			joined = |t, p| {
				read = |outcomes| Ok(((t.read)(outcomes.take_first(t.count))?, (p.read)(outcomes.drop_first(t.count))?))
				both = join_statements({ statement: t.statement, slots: t.slots }, { statement: p.statement, slots: p.slots })?
				Ok({ statement: both.statement, slots: both.slots, count: t.count + p.count, parts: t.parts.append(p.count), read })
			}
			Transaction.(
				match (built, ready_of(prepared)) {
					(Ok(t), Ok(p)) => joined(t, p)
					(Err(e), _) | (_, Err(e)) => Err(e)
				},
			)
		}

		## The transaction as one prepared statement, for `Session.run!`.
		commit : Transaction(out) -> Prepared(out)
		commit = |Transaction.(built)| Prepared.(Code.Bound.of(built.map_ok(|t| { statement: t.statement, slots: t.slots, count: t.count, atomic: Parts(t.parts), read: t.read })))
	}

	## Prepared statements with one type of result, as one transaction
	## (`Transaction`): the result is the result of each, in order, or
	## `Aborted` with the place of the one that failed it. A list with no
	## statement is an `Unsupported` error.
	transaction : List(Prepared(out)) -> Prepared(List(out))
	transaction = |all| {
		start : Transaction(List(out))
		start = match all.first() {
			Ok(first) => Transaction.(ready_of(first).map_ok(|r| { statement: r.statement, slots: r.slots, count: r.count, parts: [r.count], read: |outcomes| (r.read)(outcomes).map_ok(|x| [x]) }))
			Err(_) => Transaction.(Err(Unsupported("a transaction needs a statement")))
		}
		whole = all.drop_first(1).fold(
			start,
			|Transaction.(built), prepared| {
				joined = |t, p| {
					read = |outcomes| Ok((t.read)(outcomes.take_first(t.count))?.append((p.read)(outcomes.drop_first(t.count))?))
					both = join_statements({ statement: t.statement, slots: t.slots }, { statement: p.statement, slots: p.slots })?
					Ok({ statement: both.statement, slots: both.slots, count: t.count + p.count, parts: t.parts.append(p.count), read })
				}
				Transaction.(
					match (built, ready_of(prepared)) {
						(Ok(t), Ok(p)) => joined(t, p)
						(Err(e), _) | (_, Err(e)) => Err(e)
					},
				)
			},
		)
		whole.commit()
	}

	## The statements of a transaction: `count` of them, and `parts` the
	## count of each part, for the place of an `Aborted` error.
	Parts(out) : { statement : Statement, slots : List(Bind), count : U64, parts : List(U64), read : List(Outcome) -> Try(out, Error) }

	## The result of one statement of a reply: its value, or its error, by
	## its kind. An error `follows` when it is a statement of a transaction
	## that another failed: `NotExecuted`, or `Cancelled` after it.
	Outcome : Try(Cbor.Value, { error : ServerError, follows : Bool })

	## Queries, ids and replies that the Roc types do not describe: the
	## escape hatch. Use them when the typed API has no form for a query.
	## Each takes or gives SurrealQL text, a table by its name, or bytes
	## read as any type, and a reviewer sees the name `Unchecked` at each
	## use.
	Unchecked :: {}.{

		## A row of `SELECT *`. It has no fields in Roc and no decoder to the
		## table row: `*` gives `id` as a record id, and a field that the row
		## type does not have.
		Row :: {}

		## Every field that SurrealDB has: `SELECT *`.
		select_star : Query(p, row) -> Selected(p, Unchecked.Row)
		select_star = |Query.(q)| {
			ty = Code.Ty.Named("Surreal.Unchecked.Row", [], Record([]))
			selected_of(q, { columns: |_| Ok("*"), value: |_| Err(live_star), intrinsic: [] }, by_name, [], { ty, over: Projected(q.source), nested: Translate.Binding.Row({ at: "", of: Obj, edge: Bool.False }) })
		}

		## Replace the record ids at a result column with the rows they
		## point at: `FETCH owner`, `FETCH items[*].product`. The path names
		## a column of the result, not a field of the table row, so it is text
		## and is written as it is.
		fetch : Selected(p, Unchecked.Row), Str -> Selected(p, Unchecked.Row)
		fetch = |Selected.(s), path| Selected.({ ..s, fetches: s.fetches.append(path) })

		## The id of a row of any table, by the name of the table:
		## `Table.id` with a name that no table checks.
		id : Str, Str -> Id(row)
		id = |name, key| Id.({ table: name, key: key })

		## A value of any type from CBOR bytes of the server, such as a
		## reply of `query!`. The type is the caller's: a value that does
		## not fit it is a `Decode` error.
		decode : List(U8) -> Try(a, Error) where [a.Cbor.Readable(errs)]
		decode = |bytes| read_cbor(bytes)

		## One `query` request with this text, which no type checks, and
		## its reply, not read: the bytes that `result` and `decode` read.
		## The other frames that come before the reply go into the inbox.
		query! : Session, Str => Try({ session : Session, reply : List(U8) }, Error)
		query! = |session, text| {
			Session.(s) = session
			sent = post_request!(session, Cbor.encode(Rpc.query(s.next_id, text)))?
			reply_for!(sent, s.next_id)
		}

		## A reply of `query!` to the request of `prepared`, read as
		## `Session.run!` reads it: the result of `prepared`, against the
		## schema the session knows. Pure.
		result : Session, Prepared(out), List(U8) -> Try(out, Error)
		result = |Session.(s), prepared, bytes| prepared.result_in(bytes, s.known)
	}

	## What a package adds to the translator: the SurrealQL of functions it
	## does not know, each named by the id the compiler gives it
	## (`Code.prim(f)`), so two packages' functions of the same name never
	## meet. `render` takes the SurrealQL of each argument, as an operand,
	## and the evidence of the call, and gives the SurrealQL of the call or
	## why it has none.
	Extension : Translate.Extension

	extension : { prims : List({ prim : Code.PrimId, render : { args : List(Str), evidence : List(Code.Evidence) } -> Try(Str, Str) }) } -> Extension
	extension = |entries| Translate.extension(entries)

	## The forms of `Surreal`'s own functions: the extension that every
	## clause is translated with.
	library : Extension
	library = surreal_library

	## The table's rows, to start a query from.
	from : Table(row) -> Query(p, row)
	from = |Table.(t)| {
		edge = is_edge(t.kind)
		Query.({ target: Whole(t.name), source: { now: Ok(Translate.table_row(t.name, edge)), before: Ok(Translate.document("$before", edge)), reach: Translate.row_reach(edge) }, filters: [], watched: [], slots: [] })
	}

	# ======================================================= live queries

	## The record a change is about: its table and its key. The key is a
	## text, or the array `[series, time]` of a `TimeKey`. Two refs are
	## equal when their record ids are.
	Ref := { table : Str, key : Ql.Value }.{

		## The record id: `vital:[kennel:⟨a⟩, d'2026-03-03T08:00:00Z']`.
		to_str : Ref -> Str
		to_str = |Ref.(r)| Ql.record_ref(r.table, r.key)

		is_eq : Ref, Ref -> Bool
		is_eq = |a, b| a.to_str() == b.to_str()

		to_hash : Ref, Hasher -> Hasher
		to_hash = |ref, hasher| hasher.write_str(ref.to_str())

		encoder_for : Encode.Format -> (Ref, Encode.State -> Try(Encode.State, []))
		encoder_for = |_format| |Ref.(r), state| Encode.Format.encode_ref(r.table, r.key, state)

		## A record id from the server: tag 8 and `[table, key]`. The key
		## is read as a value that the ORM writes (`value_of`), so a
		## key of another kind, such as a duration, is an error.
		parser_for : Cbor -> (Cbor.Reader -> Try({ value : Ref, rest : Cbor.Reader }, [InvalidCbor(U64)]))
		parser_for = |encoding| |state| {
			pair : { value : (Str, Cbor.Value), rest : Cbor.Reader }
			pair = tagged(encoding, state, 8)?
			match value_of(pair.value.1) {
				Ok(key) => Ok({ value: Ref.({ table: pair.value.0, key: key }), rest: pair.rest })
				Err(_) => Err(Cbor.invalid_value(encoding, state))
			}
		}
	}

	## The uuid of a live query (see `Rpc.Uuid`).
	Uuid : Rpc.Uuid

	## The live queries of a watch that runs: the uuid of each `LIVE`
	## statement, with its role, in the order of the request.
	Lives : List({ id : Uuid, role : Role })

	## One message of a session, read: a notice of the watch (`Mine`), a
	## notice of another live query, the end of a live query, or the reply
	## to a request.
	Frame(a) : [Mine(a), Other, Killed(Uuid), Reply({ id : U64, result : Cbor.Value }), ReplyError({ id : U64, error : ServerError })]

	## A change to the result of a live query. `Removed` has the last row:
	## the old row of a delete, the new row of a row that no longer matches.
	Change(out) : [Added(Ref, out), Updated(Ref, out), Removed(Ref, out)]

	## A raw event of `Selected.live_raw`: what the server sends, no more.
	Event(out) : [Created(Ref, out), Updated(Ref, out), Deleted(Ref, out)]

	## The statement of a live query that sent a notice: the one on the
	## table (`Node`), one on an edge table (`Edge`), or one on a table
	## that the rows read through a link or with `rows()` (`Read`).
	Role : [Node, Edge, Read]

	## One notice of `Selected.live`, before it is a change. `now` is the
	## filter after the write. `row` is `Gone` when an edge notice comes
	## after its node was deleted.
	Notice(out) : { action : [Create, Update, Delete], role : Role, ref : Ref, row : Try(out, [Gone]), now : Bool }

	## One write of one row, for the Mirror and for a test:
	## `Table.edit` writes it, and `Mirror.notices` predicts what it sends.
	Edit(row) : [Create(row), Replace(row, row), Delete(row)]

	## The records in the result of a live query now. The snapshot sets
	## it, and each change updates it (`Watch.step`).
	Members := Set(Ref).{
		empty : {} -> Members
		empty = |_| Members.(Set.empty())

		contains : Members, Ref -> Bool
		contains = |Members.(set), ref| set.contains(ref)
	}

	## The result of a live query, by record.
	View(out) := Dict(Ref, out).{

		## The view of the snapshot.
		of_rows : List({ ref : Ref, row : out }) -> View(out)
		of_rows = |snapshot| View.(snapshot.fold(Dict.empty(), |acc, r| acc.insert(r.ref, r.row)))

		## `Added` and `Updated` put the row in, `Removed` takes it out.
		apply : View(out), Change(out) -> View(out)
		apply = |View.(entries), change| match change {
			Added(ref, row) | Updated(ref, row) => View.(entries.insert(ref, row))
			Removed(ref, _) => View.(entries.remove(ref))
		}

		rows : View(out) -> List(out)
		rows = |View.(entries)| entries.values()

		members : View(out) -> Members
		members = |View.(entries)| Members.(Set.from_list(entries.keys()))
	}

	## A live query, ready for a session: the `LET` of each parameter, one
	## `LIVE SELECT` on the table and one on each other table that the rows
	## read (see `Watched`), and the `SELECT` of the rows in the result now.
	## The rows of the snapshot are `{ ref, row }`.
	Watch(out) :: Code.Bound(Try({ lets : List({ name : Str, value : Ql.Value }), slots : List(Bind), lives : List({ role : Role, surql : Str }), snapshot : Str }, Error)).{

		## The watch, or why it cannot be built, as `Prepared.checked`.
		checked : Watch(out) -> Try(Watch(out), Error)
		checked = |watch| {
			_ = watch.request()?
			Ok(watch)
		}

		## One `query` request: the `LET`s, the `LIVE`s, then the snapshot.
		## The `LIVE`s come first, so no write between them and the
		## snapshot is lost: the snapshot holds it, and a notice reports it
		## again (`step` gives `Updated`). A captured value is a `LET` too,
		## and the server fixes its value when the `LIVE` starts.
		request : Watch(out) -> Try(Str, Error)
		request = |watch| {
			w = watch_of(watch)?
			lines = w.lives.map(|l| "${l.surql};").append("${w.snapshot};")
			statement = resolved({ statement: Statement.({ surql: Str.join_with(lines, "\n"), lets: w.lets, inlined: "", intrinsic: [] }), slots: w.slots, count: 0, atomic: No, read: |_| Ok({}) })?
			Ok(statement.to_script().drop_suffix(";"))
		}

		## A `-- live:` block for `check.py`. `directives` hold the
		## `-- snapshot:` and the `-- roc:` literals.
		block : Watch(out), Str, List(Str), List(Statement) -> Try(Str, Error)
		block = |watch, header, directives, writes| {
			w = watch_of(watch)?
			roles = w.lives.map(|l| role_name(l.role))
			Ok(live_block(header, roles, directives, [watch.request()?], writes))
		}

		## Sort one notice into the changes of the result, by whether its
		## record is a member and whether the filter holds after the write.
		## A delete is `Removed` when the record is a member. An edge notice
		## whose node is gone gives nothing: the node's own `DELETE` comes
		## next (verified). Any other notice, one of a `Read` statement too:
		##
		## | `now` | Member | Change |
		## | --- | --- | --- |
		## | true | no | `Added` |
		## | true | yes | `Updated` |
		## | false | yes | `Removed` |
		## | false | no | none: the write did not touch the result |
		step : Members, Notice(out) -> { members : Members, changes : List(Change(out)) }
		step = |Members.(set), notice| {
			ref = notice.ref
			unchanged = { members: Members.(set), changes: [] }
			match (notice.action, notice.role, notice.row) {
				(_, _, Err(Gone)) => unchanged
				(Delete, Node, Ok(row)) =>
					if set.contains(ref) {
						{ members: Members.(set.remove(ref)), changes: [Removed(ref, row)] }
					} else {
						unchanged
					}
				(_, _, Ok(row)) =>
					match (notice.now, set.contains(ref)) {
						(Bool.True, Bool.False) => { members: Members.(set.insert(ref)), changes: [Added(ref, row)] }
						(Bool.True, Bool.True) => { members: Members.(set), changes: [Updated(ref, row)] }
						(Bool.False, Bool.True) => { members: Members.(set.remove(ref)), changes: [Removed(ref, row)] }
						(Bool.False, Bool.False) => unchanged
					}
			}
		}

		## The reply to `request`, read: the watch that runs, with the uuid
		## of each `LIVE` and its role, and the view of the snapshot. A
		## statement that failed is a `Server` error with its message.
		## `Session.live!` reads it.
		start : Watch(out), List(U8) -> Try({ live : Live(out), view : View(out) }, Error) where [out.Cbor.Readable(errs)]
		start = |watch, bytes| {
			w = watch_of(watch)?
			let_count = w.lets.len() + w.slots.len()
			results = query_results(bytes, let_count + w.lives.len() + 1, [])?
			ids = results.drop_first(let_count).take_first(w.lives.len()).map_try(uuid_of)?
			lives = List.map2(w.lives, ids, |l, id| { id, role: l.role })
			entries : List({ ref : Ref, row : Cbor.Value })
			entries = read_cbor(Cbor.encode(results.last() ?? Cbor.Value.Null))?
			snapshot = entries.map_try(|entry| row_of(entry.row).map_ok(|row| { ref: entry.ref, row }))?
			start_view = View.of_rows(snapshot)
			Ok({ live: Live.({ watch, lives, members: start_view.members() }), view: start_view })
		}

		## One message of the session, read. A message of one of `lives`
		## is `Mine`, with the notices of its payload: one of the row
		## statement and of an edge statement, one for each row that a
		## `Read` statement gives, none when it gives none. Pure.
		notice : Watch(out), Lives, List(U8) -> Try(Frame(List(Notice(out))), Error) where [out.Cbor.Readable(errs)]
		notice = |_watch, lives, bytes| match message_of(lives, bytes)? {
			Mine({ action, role: Node }) => {
				read : { result : { record : Ref, result : { row : Cbor.Value, now : Bool } } }
				read = read_cbor(bytes)?
				row = row_of(read.result.result.row)?
				Ok(Mine([{ action, role: Node, ref: read.result.record, row: Ok(row), now: read.result.result.now }]))
			}
			Mine({ action, role: Edge }) => {
				read : { result : { result : { ref : Ref, node : Try({ row : Cbor.Value, now : Bool }, [Missing]) } } }
				read = read_cbor(bytes)?
				payload = read.result.result
				match payload.node {
					Ok(node) => Ok(Mine([{ action, role: Edge, ref: payload.ref, row: Ok(row_of(node.row)?), now: node.now }]))
					Err(Missing) => Ok(Mine([{ action, role: Edge, ref: payload.ref, row: Err(Gone), now: Bool.False }]))
				}
			}
			Mine({ action, role: Read }) => {
				read : { result : { result : List({ ref : Ref, row : Cbor.Value, now : Bool }) } }
				read = read_cbor(bytes)?
				notices = read.result.result.map_try(|r| Ok({ action, role: Read, ref: r.ref, row: Ok(row_of(r.row)?), now: r.now }))?
				Ok(Mine(notices))
			}
			Other => Ok(Other)
			Killed(id) => Ok(Killed(id))
			Reply(r) => Ok(Reply(r))
			ReplyError(r) => Ok(ReplyError(r))
		}

	}

	## A raw live query (`Selected.live_raw`): the `LET` of each parameter
	## and one `LIVE SELECT`. It has no snapshot.
	RawWatch(out) :: { lets : List({ name : Str, value : Ql.Value }), live : Str }.{
		request : RawWatch(out) -> Try(Str, Error)
		request = |RawWatch.(w)| Ok(Str.join_with(let_lines(w.lets).append("${w.live};"), "\n"))

		## A `-- live:` block for `check.py`, with the `-- roc:` literal of
		## `Mirror.events_literal` in `directives`.
		block : RawWatch(out), Str, List(Str), List(Statement) -> Str
		block = |watch, header, directives, writes| live_block(header, ["raw"], directives, [watch.request() ?? ""], writes)

		## The reply to `request`, read: the watch that runs, with the uuid
		## of the `LIVE`. There is no snapshot, so the view is `{}`.
		start : RawWatch(out), List(U8) -> Try({ live : RawLive(out), view : {} }, Error)
		start = |RawWatch.(w), bytes| {
			results = query_results(bytes, w.lets.len() + 1, [])?
			id = uuid_of(results.last() ?? Cbor.Value.Null)?
			Ok({ live: RawLive.({ watch: RawWatch.(w), lives: [{ id, role: Node }] }), view: {} })
		}

		## One message of the session, read: an event of the `LIVE` of
		## `lives` is `Mine`. Pure.
		event : RawWatch(out), Lives, List(U8) -> Try(Frame(Event(out)), Error) where [out.Cbor.Readable(errs)]
		event = |_watch, lives, bytes| match message_of(lives, bytes)? {
			Mine({ action, .. }) => {
				read : { result : { record : Ref, result : Cbor.Value } }
				read = read_cbor(bytes)?
				ref = read.result.record
				row = row_of(read.result.result)?
				Ok(
					Mine(
						match action {
							Create => Created(ref, row)
							Update => Updated(ref, row)
							Delete => Deleted(ref, row)
						},
					),
				)
			}
			Other => Ok(Other)
			Killed(id) => Ok(Killed(id))
			Reply(r) => Ok(Reply(r))
			ReplyError(r) => Ok(ReplyError(r))
		}
	}

	## A live query of patches of the stored rows (`Query.live_diff`): the
	## `LET` of each parameter and one `LIVE SELECT DIFF`.
	DiffWatch(row) :: { lets : List({ name : Str, value : Ql.Value }), live : Str }.{
		request : DiffWatch(row) -> Try(Str, Error)
		request = |DiffWatch.(w)| Ok(Str.join_with(let_lines(w.lets).append("${w.live};"), "\n"))

		block : DiffWatch(row), Str, List(Str), List(Statement) -> Str
		block = |watch, header, directives, writes| live_block(header, ["diff"], directives, [watch.request() ?? ""], writes)

		## The reply to `request`, read: the watch that runs, with the uuid
		## of the `LIVE`, and an empty view that its patches fill
		## (`DiffView.apply`).
		start : DiffWatch(row), List(U8) -> Try({ live : DiffLive(row), view : DiffView(row) }, Error)
		start = |DiffWatch.(w), bytes| {
			results = query_results(bytes, w.lets.len() + 1, [])?
			id = uuid_of(results.last() ?? Cbor.Value.Null)?
			Ok({ live: DiffLive.({ watch: DiffWatch.(w), lives: [{ id, role: Node }] }), view: DiffView.empty({}) })
		}

		## One message of the session, read: a patch of the `LIVE` of
		## `lives` is `Mine`. Pure.
		patch : DiffWatch(row), Lives, List(U8) -> Try(Frame(Patch(row)), Error)
		patch = |_watch, lives, bytes| match message_of(lives, bytes)? {
			Mine({ action, .. }) => {
				read : { result : { record : Ref, result : List({ op : Str, path : Str, value : Try(Cbor.Value, [Missing]) }) } }
				read = read_cbor(bytes)?
				ops = read.result.result.map_try(Diff.op_of).map_err(|BadOp(why)| Wire("a patch with ${why}"))?
				Ok(Mine(Patch.({ ref: read.result.record, action, ops })))
			}
			Other => Ok(Other)
			Killed(id) => Ok(Killed(id))
			Reply(r) => Ok(Reply(r))
			ReplyError(r) => Ok(ReplyError(r))
		}
	}

	## One op of a `live_diff` patch (see `Diff.Op`).
	Op : Diff.Op

	## One notice of `Query.live_diff`: the ops of one write to a stored
	## row, in order. A create replaces the whole row (the pointer `""`),
	## and a delete replaces it with `NULL`.
	Patch(row) := { ref : Ref, action : [Create, Update, Delete], ops : List(Op) }.{

		## The cut of `field` (see `Surreal.code_primitives`).
		code_primitives = cut

		ref : Patch(row) -> Ref
		ref = |Patch.(p)| p.ref

		action : Patch(row) -> [Create, Update, Delete]
		action = |Patch.(p)| p.action

		ops : Patch(row) -> List(Op)
		ops = |Patch.(p)| p.ops

		## What the patch did to one field of the row: the function reads
		## the field, `|v| v.temp_c`. The last op that reaches the field
		## decides:
		##
		## | Op | Result |
		## | --- | --- |
		## | `Add` or `Replace` at the field | `Set(value)` |
		## | `Remove` at the field | `Unset` |
		## | An op below the field, or `Change` of its text | `Inside` |
		## | `Add` or `Replace` above the field (a create replaces `""`) | `Set` of the field in the new value, or `Unset` when it has none |
		## | `Remove` above the field | `Unset` |
		## | No op reaches the field | `Untouched` |
		field : Patch(row), Code(row -> a) -> Try([Untouched, Set(a), Unset, Inside], Error) where [a.Cbor.Readable(errs)]
		field = |Patch.(p), path| {
			steps = Translate.path_of(path.graph())?
			pointer = steps.map_try(
				|step| match step {
					Field(name) => Ok(name)
					Each => Err(Unsupported("a field of a patch is one field, not each item of a list"))
				},
			)?
			last = p.ops.keep_if(|op| op_reaches(Diff.path_of(op), pointer)).last()
			match last {
				Err(_) => Ok(Untouched)
				Ok(Remove(at)) => Ok(if (at.len() == pointer.len()) Unset else Inside)
				Ok(Change(_, _)) => Ok(Inside)
				Ok(Add(at, value)) | Ok(Replace(at, value)) =>
					if at.len() > pointer.len() {
						Ok(Inside)
					} else {
						match value_at(value, pointer.drop_first(at.len())) {
							Ok(inner) => row_of(inner).map_ok(|v| Set(v))
							Err(Absent) => Ok(Unset)
						}
					}
			}
		}
	}

	## The stored rows of a `live_diff` watch, kept as values: each patch
	## applied in order. `get` reads one as `row`.
	DiffView(row) := Dict(Ref, Cbor.Value).{
		empty : {} -> DiffView(row)
		empty = |_| DiffView.(Dict.empty())

		## The view after the patch. A create adds the row, and a delete
		## (`NULL` at `""`) removes it. An update of a row that the view
		## does not hold is `UnknownRef`: the row entered the filter, and
		## the patch has only the ops of the write.
		apply : DiffView(row), Patch(row) -> Try(DiffView(row), [UnknownRef(Ref), BadPath(Pointer), Mismatch(U64)])
		apply = |DiffView.(stored_rows), Patch.(p)| {
			base = match (stored_rows.get(p.ref), p.action) {
				(Ok(stored), _) => stored
				(Err(_), Create) => Cbor.Value.Null
				(Err(_), _) => return Err(UnknownRef(p.ref))
			}
			after = p.ops.fold_try(base, Diff.apply)?
			Ok(DiffView.(if (after == Cbor.Value.Null) stored_rows.remove(p.ref) else stored_rows.insert(p.ref, after)))
		}

		## The stored row, read as `row`. The `id` of a stored row is a
		## record id, and a row of the ORM holds its key, as
		## `record::id(id)` gives it, so the key is read.
		get : DiffView(row), Ref -> Try(row, [UnknownRef(Ref), Unreadable(Error)]) where [row.Cbor.Readable(errs)]
		get = |DiffView.(stored_rows), ref| match stored_rows.get(ref) {
			Ok(stored) => row_of(keyed(stored)).map_err(|e| Unreadable(e))
			Err(_) => Err(UnknownRef(ref))
		}

		## Every stored row, read as `row`.
		rows : DiffView(row) -> Try(List(row), Error) where [row.Cbor.Readable(errs)]
		rows = |DiffView.(stored_rows)| stored_rows.values().map_try(|one| row_of(keyed(one)))

		refs : DiffView(row) -> List(Ref)
		refs = |DiffView.(stored_rows)| stored_rows.keys()
	}

	## The HTTP function of the platform that a session uses: one `POST`
	## and its response, of any status. The app makes it from the `Http` of
	## its platform (`client.roc` on basic-cli, `server.roc` on
	## basic-webserver). An `Err` is a post that got no response.
	HttpClient : {
		post! : HttpRpc.Post => Try({ status : U16, body : List(U8) }, Str),
	}

	## Who a session signs in as (`Session.open!`):
	##
	## | Login | RPC | The session is |
	## | --- | --- | --- |
	## | `Root({ ns, db, user, pass })` | `signin` of a system user, then `use` | That user, in the namespace and the database |
	## | `SignUp(RecordLogin)` | `signup` with the access method and its variables (`Access.sign_up`) | The new record user, with a token |
	## | `SignIn(RecordLogin)` | `signin` with the access method and its variables (`Access.sign_in`) | The record user, with a token |
	## | `Token(token)` | `authenticate` | The user of a token that a signup or a signin gave (`Session.token`) |
	Login : [Root({ ns : Str, db : Str, user : Str, pass : Str }), SignUp(RecordLogin), SignIn(RecordLogin), Token(Str)]

	## A signup or a signin of a record user: the access method, its
	## namespace and database, and the variables of its `SIGNUP` or
	## `SIGNIN` query, a CBOR map that `Access.sign_up` and
	## `Access.sign_in` write from a typed record.
	RecordLogin : { access : Str, ns : Str, db : Str, vars : List((Cbor.Value, Cbor.Value)) }

	## Who the requests of a session are from (`HttpRpc.Auth`). A WebSocket
	## session signs in once, on its connection, and the server keeps it;
	## a post over HTTP carries it, as the server keeps nothing between
	## two posts.
	Credentials : HttpRpc.Auth

	## How a session reaches the server: a WebSocket (`websocket`) or HTTP
	## (`http`). `Session.open!` takes either, and the session and the
	## type of each function of its API are the same on both. Nothing is
	## sent until `Session.open!`, which makes the `Connection`.
	Transport :: { connect! : {} => Try(Connection, Error) }.{

		## A WebSocket on `/rpc` of `url` (`ws://127.0.0.1:8000`), with the
		## subprotocol `cbor.2` (CBOR v2), through an adapter of roc-websocket:
		## `connect` opens the connection (`Ws.Connect`, such as
		## `WsClient.connect`), and `ops` sends and receives on it (any
		## record with `send!` and `receive!`, such as `WsClient.ops`).
		## `Session.open!` connects. The adapter answers pings and closes;
		## its errors are `WebSocket` errors. A watch on this session
		## waits with no deadline (`Session.next!`), and
		## `Session.next_within!` is an `Unsupported` error. An adapter
		## with `receive_within!` takes `websocket_timed`.
		websocket : Ws.Connect(c, e, r), { send! : c, Ws.Message => Try(c, Ws.Error(e)), receive! : c => Try((c, Ws.Message), Ws.Error(e)), .. }, Str -> Transport
		websocket = |connect, ops, url| Transport.({ connect!: |{}| websocket!(connect, url, |conn| websocket_connection(ops, conn)) })

		## A WebSocket as `websocket`, through an adapter that also has
		## `receive_within!` (the `Ws.ReceiveWithin` feature of
		## roc-websocket, such as `WsClient.ops` of roc-basic-cli-websocket),
		## so that `Session.next_within!` waits for a notice with a
		## deadline.
		websocket_timed : Ws.Connect(c, e, r), { send! : c, Ws.Message => Try(c, Ws.Error(e)), receive! : c => Try((c, Ws.Message), Ws.Error(e)), receive_within! : c, U64 => Try((c, [Message(Ws.Message), TimedOut]), Ws.Error(e)), .. }, Str -> Transport
		websocket_timed = |connect, ops, url| Transport.({ connect!: |{}| websocket!(connect, url, |conn| websocket_timed_connection(ops, conn)) })

		## HTTP: each request is one `POST /rpc` to `url`
		## (`http://127.0.0.1:8000`), which carries the credentials of the
		## session.
		http : HttpClient, Str -> Transport
		http = |client, url| Transport.({ connect!: |{}| Ok(http_connection(client, url)) })
	}

	## What a transport does for a session once it connects, one field for
	## each feature. The session calls only these, so one session type runs
	## on either transport, and the API is the same on both:
	##
	## | Field | Feature | WebSocket (`websocket_connection`) | HTTP (`http_connection`) |
	## | --- | --- | --- | --- |
	## | `request!` | Sends one RPC message, from the session's `Credentials` | A `Binary` message: `Sent`, and the reply comes later as a message of `pushed`. The credentials are the connection's, which the login set | A `POST /rpc` with the credentials in its headers: `Replied`, with the reply |
	## | `pushed` | The messages that the server sends when it wants: the replies to `Sent` requests and the notices of live queries | `Supported`: the next message of the session | `Unsupported` |
	## | `within` | The next pushed message with a deadline, for `Session.next_within!` | `Within` with `Transport.websocket_timed` (the adapter's `receive_within!`), else `NoDeadline` | `NoDeadline` |
	##
	## Each call gives the connection after it, which the session keeps: a
	## connection of roc-websocket is a value that holds the state of the
	## protocol (bytes read past a frame, a message in pieces), and the
	## closures of the next `Connection` hold the next value. An adapter
	## of any type fits one `Connection`, so the `Session` has no type
	## parameter. Over HTTP the connection stays the same.
	##
	## A feature that a connection lacks is a tag, not a function that
	## fails, so the session knows before it sends anything: a watch on a
	## session with no `pushed` is an `Unsupported` error, and nothing is
	## sent. So is `Session.next_within!` on a session with `NoDeadline`:
	## the error comes before anything is read.
	Connection :: {
		request! : Credentials, List(U8) => Try({ connection : Connection, reply : [Sent, Replied(List(U8))] }, Error),
		pushed : Pushed,
		within : Deadline,
	}

	## The next pushed message with a deadline, when the connection has
	## one: each call of `Within` gives the next message, or `TimedOut`
	## when none came in `ms` milliseconds (a ping does not count), with
	## the connection after it. A timeout loses nothing.
	Deadline : [Within(U64 => Try({ connection : Connection, got : [Message(List(U8)), TimedOut] }, Error)), NoDeadline]

	## The messages that a connection pushes, when it does: each call of
	## `next!` gives the next one, with the connection after it. A
	## connection that the server or the adapter ended is the error
	## `WebSocket(Closed(closure))`.
	Pushed : [Supported({ next! : {} => Try({ connection : Connection, message : List(U8) }, Error) }), Unsupported]

	## The messages that a session read and that no call took yet. Pure:
	## the session puts each message that it reads here (`accept`), and
	## each call takes its own. Replies to requests in flight come in any
	## order, and a notice can come before or after any reply, also the
	## reply to its own write (verified on SurrealDB 3.3.4).
	##
	## | Message | Kept |
	## | --- | --- |
	## | A reply | By its id, until `take_reply` |
	## | A notice of a watched uuid | With its uuid, in the order it came, until `take_notice` |
	## | `KILLED` of a watched uuid | As a notice, and the uuid is no longer watched |
	## | A notice of a uuid that is not watched | Dropped. While a watch starts (`start`), kept apart until `watch` |
	##
	## There is no limit on the queued notices of a watch that the app
	## does not read.
	Inbox :: {
		replies : Dict(U64, List(U8)),
		notices : List({ live : Uuid, killed : Bool, bytes : List(U8) }),
		watched : Set(Uuid),
		early : [Idle, Starting(List({ live : Uuid, killed : Bool, bytes : List(U8) }))],
	}.{

		## The key of a message: the id of a reply, or the uuid of the live
		## query of a notice, and whether it is `KILLED`.
		key_of : List(U8) -> Try([Reply(U64), Notice({ live : Uuid, killed : Bool })], Error)
		key_of = |bytes| message_key(bytes)
		empty : {} -> Inbox
		empty = |_| Inbox.({ replies: Dict.empty(), notices: [], watched: Set.empty(), early: Idle })

		## One message, sorted by its key (`key_of`). A message
		## whose key does not read is a `Wire` error.
		accept : Inbox, List(U8) -> Try(Inbox, Error)
		accept = |inbox, bytes| {
			Inbox.(i) = inbox
			match message_key(bytes)? {
				Reply(id) => Ok(Inbox.({ ..i, replies: i.replies.insert(id, bytes) }))
				Notice({ live, killed }) => Ok(inbox.keep({ live, killed, bytes }))
			}
		}

		## A notice, queued when its uuid is watched, held while a watch
		## starts, else dropped. `KILLED` ends the watch of its uuid.
		keep : Inbox, { live : Uuid, killed : Bool, bytes : List(U8) } -> Inbox
		keep = |Inbox.(i), notice| match (i.watched.contains(notice.live), i.early) {
			(Bool.True, _) => Inbox.({ ..i, notices: i.notices.append(notice), watched: if (notice.killed) i.watched.remove(notice.live) else i.watched })
			(Bool.False, Starting(held)) => Inbox.({ ..i, early: Starting(held.append(notice)) })
			(Bool.False, Idle) => Inbox.(i)
		}

		## The reply to the request `id`, taken out of the inbox.
		take_reply : Inbox, U64 -> [Taken({ bytes : List(U8), inbox : Inbox }), Waiting]
		take_reply = |Inbox.(i), id| match i.replies.get(id) {
			Ok(bytes) => Taken({ bytes, inbox: Inbox.({ ..i, replies: i.replies.remove(id) }) })
			Err(_) => Waiting
		}

		## The first queued notice of one of `lives`, taken out of the inbox.
		## `Ended` when none is queued and none of `lives` is watched: the
		## watch was killed, and no notice of it comes again.
		take_notice : Inbox, Lives -> [Taken({ bytes : List(U8), inbox : Inbox }), Waiting, Ended]
		take_notice = |Inbox.(i), lives| {
			mine = |id| lives.any(|l| l.id == id)
			match i.notices.find_first_index(|n| mine(n.live)) {
				Ok(at) =>
					match i.notices.get(at) {
						Ok(n) => Taken({ bytes: n.bytes, inbox: Inbox.({ ..i, notices: i.notices.drop_at(at) }) })
						Err(_) => crash "find_first_index gives an index of the list"
					}
				Err(NotFound) => if (lives.any(|l| i.watched.contains(l.id))) Waiting else Ended
			}
		}

		## A watch starts: until `watch`, a notice of a uuid that is not
		## watched is held, because the uuids of the new watch are in the
		## reply, and a notice can come before it.
		start : Inbox -> Inbox
		start = |Inbox.(i)| Inbox.({ ..i, early: Starting([]) })

		## The uuids of a watch that started: they are watched, and the
		## notices held since `start` are kept again, in the order they
		## came. A held notice of another uuid is dropped.
		watch : Inbox, Lives -> Inbox
		watch = |Inbox.(i), lives| {
			held = match i.early {
				Starting(notices) => notices
				Idle => []
			}
			opened = Inbox.({ ..i, watched: lives.fold(i.watched, |set, l| set.insert(l.id)), early: Idle })
			held.fold(opened, |inbox, notice| inbox.keep(notice))
		}

		## The uuids of a watch that ends (`Session.kill!`): they are no
		## longer watched, and their queued notices are dropped. The
		## notices of other watches stay.
		unwatch : Inbox, Lives -> Inbox
		unwatch = |Inbox.(i), lives| {
			gone = |id| lives.any(|l| l.id == id)
			Inbox.({ ..i, watched: lives.fold(i.watched, |set, l| set.remove(l.id)), notices: i.notices.drop_if(|n| gone(n.live)) })
		}

		## The queued notices, in the order they came, with their uuids.
		notices : Inbox -> List({ live : Uuid, bytes : List(U8) })
		notices = |Inbox.(i)| i.notices.map(|n| { live: n.live, bytes: n.bytes })

		## The ids of the replies that no call took yet.
		replies : Inbox -> List(U64)
		replies = |Inbox.(i)| i.replies.keys()
	}

	## A watch that runs (`Session.live!`): the watch, the uuids of its
	## live queries, and the members of its result. Pure data:
	## `Session.next!` reads its next changes. The three kinds of running
	## watch, `Live`, `RawLive` and `DiffLive`, each have `lives` and
	## `receive`, which `Session.next!` and `Session.stream` read.
	Live(out) :: { watch : Watch(out), lives : Lives, members : Members }.{

		lives : Live(out) -> Lives
		lives = |Live.(l)| l.lives

		members : Live(out) -> Members
		members = |Live.(l)| l.members

		## One message of the session, applied (`Watch.step`): `Got` with
		## the changes of a notice of the watch and the watch after it,
		## `Skip` for a notice that changes nothing and any other message,
		## and `Ended` for its `KILLED`. Pure.
		receive : Live(out), List(U8) -> Try([Got({ item : List(Change(out)), live : Live(out) }), Skip(Live(out)), Ended], Error) where [out.Cbor.Readable(errs)]
		receive = |Live.(l), bytes| match changes_of(l.watch, l.lives, l.members, bytes)? {
			Changed(c) if c.changes.is_empty() => Ok(Skip(Live.({ ..l, members: c.members })))
			Changed(c) => Ok(Got({ item: c.changes, live: Live.({ ..l, members: c.members }) }))
			Ended => Ok(Ended)
		}
	}

	## A raw watch that runs (`Session.live!` of a `RawWatch`).
	RawLive(out) :: { watch : RawWatch(out), lives : Lives }.{
		lives : RawLive(out) -> Lives
		lives = |RawLive.(l)| l.lives

		## One message of the session, read (`RawWatch.event`): `Got` with
		## an event of the watch, `Skip` for any other message, `Ended`
		## for its `KILLED`. Pure.
		receive : RawLive(out), List(U8) -> Try([Got({ item : Event(out), live : RawLive(out) }), Skip(RawLive(out)), Ended], Error) where [out.Cbor.Readable(errs)]
		receive = |RawLive.(l), bytes| match l.watch.event(l.lives, bytes)? {
			Mine(event) => Ok(Got({ item: event, live: RawLive.(l) }))
			Killed(id) if l.lives.any(|one| one.id == id) => Ok(Ended)
			_ => Ok(Skip(RawLive.(l)))
		}
	}

	## A watch of patches that runs (`Session.live!` of a `DiffWatch`).
	DiffLive(row) :: { watch : DiffWatch(row), lives : Lives }.{
		lives : DiffLive(row) -> Lives
		lives = |DiffLive.(l)| l.lives

		## One message of the session, read (`DiffWatch.patch`): `Got`
		## with a patch of the watch, `Skip` for any other message,
		## `Ended` for its `KILLED`. Pure.
		receive : DiffLive(row), List(U8) -> Try([Got({ item : Patch(row), live : DiffLive(row) }), Skip(DiffLive(row)), Ended], Error)
		receive = |DiffLive.(l), bytes| match l.watch.patch(l.lives, bytes)? {
			Mine(patch) => Ok(Got({ item: patch, live: DiffLive.(l) }))
			Killed(id) if l.lives.any(|one| one.id == id) => Ok(Ended)
			_ => Ok(Skip(DiffLive.(l)))
		}
	}

	## A request in flight (`Session.send!`): its id, and the type of its
	## result, which `Session.await!` reads.
	Ticket(out) :: { id : Try(U64, Error) }

	## A session of SurrealDB's RPC on `/rpc`, over a `Transport`: a
	## WebSocket with the subprotocol `cbor.2` (`Transport.websocket`), or
	## HTTP (`Transport.http`). The id of a request is a count, so each id is
	## unique: SurrealDB does not check (verified). The session puts each
	## reply and notice into its `Inbox`, and a call that waits reads one
	## message at a time until the inbox holds what it waits for. Each
	## call gives the session after it back: use the session that the
	## last call gave, because an older copy has an older inbox. A call
	## that fails (an `Err`) gives no session: the connection or a message
	## failed. `run!` and `await!` always give a session, and one `Try`
	## with the result or the error of any kind: after a `Transport` error
	## the session's connection is gone, and a new session is opened.
	##
	## Over HTTP, `send!` posts the request and waits for its reply, which
	## it keeps in the inbox for `await!`. So `send!` then `await!` works
	## on both, but over HTTP the requests run one after the other, in the
	## order they were sent. A watch needs `pushed`: on a session over
	## HTTP, `live!`, `next!`, `stream` and `kill!` give an `Unsupported`
	## error. `next_within!` also needs `within` (`Transport.websocket_timed`). `next_within!` also needs `within` (`Transport.websocket_timed`).
	Session :: { connection : Connection, next_id : U64, inbox : Inbox, known : List(Schema.Known), auth : Credentials }.{

		## Connects the transport (the opening request of a WebSocket), then
		## signs in as the `Login` says: `signin` and `use` of a system
		## user, `signup` or `signin` of a record user, `authenticate` of a
		## token. Over HTTP, each later post carries the user and the scope
		## (`Credentials`): Basic authentication of a system user, else the
		## token, which holds its namespace and database. A refused
		## signup, signin or token is `Server(Denied(message))` (see
		## `login_error`).
		open! : Transport, Login => Try(Session, Error)
		open! = |Transport.(t), login| {
			connection = (t.connect!)({})?
			match login {
				Root(root) => {
					auth = { who: Basic({ user: root.user, pass: root.pass }), scope: Scope({ ns: root.ns, db: root.db }) }
					opened = Session.({ connection, next_id: 1, inbox: Inbox.empty({}), known: [], auth })
					signed = ask!(opened, Cbor.encode(Rpc.signin(1, { user: root.user, pass: root.pass })))?
					ask!(signed, Cbor.encode(Rpc.use_db(2, root.ns, root.db)))
				}
				SignUp(r) => record_login!(connection, "signup", r)
				SignIn(r) => record_login!(connection, "signin", r)
				Token(token) => {
					opened = Session.({ connection, next_id: 1, inbox: Inbox.empty({}), known: [], auth: { who: Anonymous, scope: FromToken } })
					checked = answer!(opened, Cbor.encode(Rpc.authenticate(1, token))).map_err(login_error)?
					Session.(c) = checked.session
					Ok(Session.({ ..c, auth: { who: Bearer(token), scope: FromToken } }))
				}
			}
		}

		## The token of a session of a record user or of a token: what
		## `signup` or `signin` gave, which a later session opens with
		## (`Token`). A system user has none.
		token : Session -> Try(Str, [NoToken])
		token = |Session.(s)| match s.auth.who {
			Bearer(token) => Ok(token)
			Basic(_) | Anonymous => Err(NoToken)
		}

		## `invalidate`: the session is no one, and each request after it
		## is refused (`Denied`) until it signs in again. The token stays
		## valid until it expires: SurrealDB keeps no list of the tokens
		## it gave, so a session can open with it again (verified on 3.3.4).
		## Over HTTP the session sends no credentials after it.
		invalidate! : Session => Try(Session, Error)
		invalidate! = |session| {
			Session.(before) = session
			Session.(s) = ask!(session, Cbor.encode(Rpc.invalidate(before.next_id)))?
			Ok(Session.({ ..s, auth: { ..s.auth, who: Anonymous } }))
		}

		## The session, reading the errors of the server against the schema
		## of `defined`: a violation of a `Def.unique` index is `Unique`, with
		## the table and the fields of the index, not `Index`.
		knowing : Session, List(Defined) -> Session
		knowing = |Session.(s), defined| Session.({ ..s, known: s.known.concat(Schema.unique_indexes(defined)) })

		## Whether the connection gives the messages that the server
		## pushes, which a watch reads: a WebSocket session does, a session
		## over HTTP does not.
		pushes : Session -> Bool
		pushes = |Session.(s)| match s.connection.pushed {
			Supported(_) => Bool.True
			Unsupported => Bool.False
		}

		## Starts a watch of any kind: a `Watch` (`Selected.live`), a
		## `RawWatch` (`Selected.live_raw`) or a `DiffWatch`
		## (`Query.live_diff`). Sends its request, and reads the uuids and
		## the view it starts from: the snapshot of a `Watch`, an empty
		## `DiffView`, `{}` of a raw watch. A notice that comes before the
		## reply stays in the inbox. `next!` reads what the watch gives.
		live! : Session, watch => Try({ session : Session, live : live, view : view }, Error) where [watch.request : watch -> Try(Str, Error), watch.start : watch, List(U8) -> Try({ live : live, view : view }, Error), live.lives : live -> Lives]
		live! = |session, watch| {
			got = start!(session, watch.request()?)?
			started = watch.start(got.reply)?
			Ok({ session: watching(got.session, started.live.lives()), live: started.live, view: started.view })
		}

		## What the watch gives next, from the inbox first, then from the
		## frames that the session reads; another frame goes into the
		## inbox. A `Live` gives the changes of the next notice that has
		## any, a `RawLive` an event, a `DiffLive` a patch. `Ended` when
		## the watch was killed; `Unread` when a notice does not read, and
		## the watch goes on after it.
		next! : Session, live => Try({ session : Session, live : live, next : [Got(item), Ended, Unread(Error)] }, Error) where [live.lives : live -> Lives, live.receive : live, List(U8) -> Try([Got({ item : item, live : live }), Skip(live), Ended], Error)]
		next! = |session, live| {
			got = notice_for!(session, live.lives())?
			match got.notice {
				Ended => Ok({ session: got.session, live, next: Ended })
				Notice(bytes) =>
					match live.receive(bytes) {
						Ok(Got(g)) => Ok({ session: got.session, live: g.live, next: Got(g.item) })
						Ok(Skip(later)) => Session.next!(got.session, later)
						Ok(Ended) => Ok({ session: got.session, live, next: Ended })
						Err(e) => Ok({ session: got.session, live, next: Unread(e) })
					}
			}
		}

		## `next!` with a deadline: what the watch gives next, or `TimedOut`
		## when no message arrives in `ms` milliseconds. A notice that the
		## inbox already holds is returned before any wait. Otherwise the
		## session reads messages (a reply or a notice of another watch
		## goes into the inbox), and each wait for a message takes up to
		## `ms`: a notice that gives no change, or a message for another
		## call, starts the wait again, and a ping does not count. A
		## timeout loses nothing: the session and the watch it gives go on.
		## A session whose transport has no `receive_within!` (a session
		## over HTTP, or `Transport.websocket`) is an `Unsupported` error,
		## before anything is read.
		next_within! : Session, live, U64 => Try({ session : Session, live : live, next : [Got(item), Ended, Unread(Error), TimedOut] }, Error) where [live.lives : live -> Lives, live.receive : live, List(U8) -> Try([Got({ item : item, live : live }), Skip(live), Ended], Error)]
		next_within! = |session, live, ms| {
			_ = within_of(session)?
			got = notice_within!(session, live.lives(), ms)?
			match got.notice {
				Ended => Ok({ session: got.session, live, next: Ended })
				TimedOut => Ok({ session: got.session, live, next: TimedOut })
				Notice(bytes) =>
					match live.receive(bytes) {
						Ok(Got(g)) => Ok({ session: got.session, live: g.live, next: Got(g.item) })
						Ok(Skip(later)) => Session.next_within!(got.session, later, ms)
						Ok(Ended) => Ok({ session: got.session, live, next: Ended })
						Err(e) => Ok({ session: got.session, live, next: Unread(e) })
					}
			}
		}

		## What `next!` reads, one at a time, as a stream. Each item has
		## the session and the watch after it, so the app can stop and go
		## on with them. A notice that does not read is an error in the
		## stream, and the stream goes on; a read that fails ends it after
		## its error. It ends when the watch ends.
		stream : Session, live -> Stream(Try({ item : item, session : Session, live : live }, Error)) where [live.lives : live -> Lives, live.receive : live, List(U8) -> Try([Got({ item : item, live : live }), Skip(live), Ended], Error)]
		stream = |session, live| Stream.custom({ session, live, open: Bool.True }, Err(Unknown), stream_step!)

		## Sends a prepared statement, and does not wait for its reply: the
		## ticket names it for `await!`. Requests in flight run with no
		## order between them on the server (verified), so a step that
		## needs another goes in one request (`Prepared.then`). A statement
		## that cannot be built (`Prepared.checked`) is not sent: its ticket
		## holds the error, and `await!` gives it.
		send! : Session, Prepared(out) => Try({ session : Session, ticket : Ticket(out) }, Error)
		send! = |session, prepared| {
			Session.(s) = session
			match prepared.request() {
				Ok(text) => {
					sent = post_request!(session, Cbor.encode(Rpc.query(s.next_id, text)))?
					Ok({ session: sent, ticket: Ticket.({ id: Ok(s.next_id) }) })
				}
				Err(e) => Ok({ session, ticket: Ticket.({ id: Err(e) }) })
			}
		}

		## The reply to a ticket, read as the result of `prepared`: from the
		## inbox, else from the frames that the session reads. Another frame
		## goes into the inbox. The result is the rows, or the error of the
		## read (`Transport`, `Wire`), of the server (`Server`) or of the
		## rows (`Decode`). After an error of the read it is this session.
		await! : Session, Ticket(out), Prepared(out) => { session : Session, result : Try(out, Error) }
		await! = |session, Ticket.(t), prepared| {
			Session.(s) = session
			match t.id {
				Ok(id) =>
					match reply_for!(session, id) {
						Ok(got) => { session: got.session, result: prepared.result_in(got.reply, s.known) }
						Err(e) => { session, result: Err(e) }
					}
				Err(e) => { session, result: Err(e) }
			}
		}

		## Runs a prepared statement, and reads its reply as the type of its
		## result: `send!`, then `await!`. A send that fails is the error of
		## the result, with this session.
		run! : Session, Prepared(out) => { session : Session, result : Try(out, Error) }
		run! = |session, prepared| match Session.send!(session, prepared) {
			Ok(sent) => Session.await!(sent.session, sent.ticket, prepared)
			Err(e) => { session, result: Err(e) }
		}

		## Applies the migration files that the database does not have, in
		## the order of the list. The first request makes the history table
		## `_reify_migration` (`IF NOT EXISTS`), reads the compatibility
		## level (`INFO FOR DB`) and the history; when all files are applied
		## it is the only request. Each section of a file is one transaction
		## that also writes the history record, so a crash between sections
		## goes on at the next section. Two runners at once: the record of
		## the first section is created once, so one of them fails on it,
		## reads the history again and goes on; no section runs twice. A
		## file that the database applied and whose text changed, a file
		## before an applied one and a squashed file over a part of its
		## files are `Migration`
		## errors, and nothing runs. So is a database below compatibility
		## level 4 (`Level`): a SurrealDB 3 datastore that was upgraded to
		## SurrealDB 4 stays at level 3 until `ALTER DATABASE COMPATIBILITY 4`.
		migrate! : Session, List(Migration) => Try({ session : Session, applied : Applied }, Error)
		migrate! = |session, migrations| {
			files = migrations.map(|Migration.(m)| m.file)
			start = migration_state!(session)?
			decided = Migrate.decide(start.history, files, start.level)?
			var $session = start.session
			var $ran = []
			var $adopted = []
			for action in decided.actions {
				match action {
					Run(r) =>
						match files.find_first(|f| f.name == r.name) {
							Ok(file) => {
								done = run_sections!($session, file, r.from)?
								$session = done.session
								if done.mine {
									$ran = $ran.append(r.name)
								}
							}
							Err(_) => {}
						}
					Adopt(name) =>
						match files.find_first(|f| f.name == name) {
							Ok(file) => {
								done = adopt_file!($session, file)?
								$session = done.session
								if done.mine {
									$adopted = $adopted.append(name)
								}
							}
							Err(_) => {}
						}
				}
			}
			Ok({ session: $session, applied: { ran: $ran, adopted: $adopted, ahead: decided.ahead } })
		}

		## Ends the live queries of a watch with the RPC method `kill`. Their
		## queued notices are dropped, and so is a notice of them that comes
		## later, `KILLED` too. The notices of other watches stay.
		kill! : Session, Lives => Try(Session, Error)
		kill! = |session, lives| {
			Session.(s) = session
			_ = push_of(session)?
			kill_each!(Session.({ ..s, inbox: s.inbox.unwatch(lives) }), lives)
		}
	}

	## The Roc Mirror of a live query and the literals of `check.py`: what
	## the server sends for a write, computed in Roc from the same
	## functions that the clauses reify, over the same rows, and a Roc
	## value written as a SurrealQL literal. The checks and the tests use
	## it; an application does not need it.
	Mirror :: [].{

		## A Roc value as a SurrealQL literal: the reference result of a query,
		## which `check.py` compares with what the database returns.
		literal : a -> Try(Str, Error) where [a.encoder_for : Encode.Format -> (a, Encode.State -> Try(Encode.State, []))]
		literal = |value| Encode.value_of(value).map_ok(Ql.literal)

		## The expected notices of a `-- live:` block, one list for each write,
		## as the `-- roc:` literal that `check.py` compares.
		notices_literal : List(List(Notice(out))) -> Try(Str, Error) where [out.encoder_for : Encode.Format -> (out, Encode.State -> Try(Encode.State, []))]
		notices_literal = |writes| {
			lists = writes.map_try(|notices| notices.map_try(notice_value).map_ok(|values| Ql.Value.Array(values)))?
			Ok(Ql.literal(Ql.Value.Array(lists)))
		}

		## The same for the events of `live_raw`.
		events_literal : List(List(Event(out))) -> Try(Str, Error) where [out.encoder_for : Encode.Format -> (out, Encode.State -> Try(Encode.State, []))]
		events_literal = |writes| {
			lists = writes.map_try(|events| events.map_try(event_value).map_ok(|values| Ql.Value.Array(values)))?
			Ok(Ql.literal(Ql.Value.Array(lists)))
		}

		## The notices of one message, applied to the members in turn.
		step_all : Members, List(Notice(out)) -> { members : Members, changes : List(Change(out)) }
		step_all = |members, notices| notices.fold(
			{ members, changes: [] },
			|acc, n| {
				one = Watch.step(acc.members, n)
				{ members: one.members, changes: acc.changes.concat(one.changes) }
			},
		)

		## The notices one write of the table sends to the row
		## statement of a live query (`Selected.live`). `keep` is the filter
		## and `show` the projection, the plain Roc functions that the
		## clauses reify, over the row as stored:
		##
		## | Write | Notice when | `now` |
		## | --- | --- | --- |
		## | `Create(r)` | `keep(r)` | true |
		## | `Replace(a, b)` | `keep(a)` or `keep(b)`, and `a` and `b` differ | `keep(b)` |
		## | `Delete(r)` | `keep(r)` | true: the payload reads the old row |
		notices : Table(row), Edit(row), (row -> Bool), (row -> out) -> Try(List(Notice(out)), Error) where [row.encoder_for : Encode.Format -> (row, Encode.State -> Try(Encode.State, []))]
		notices = |Table.(t), change, keep, show| match change {
			Create(row) => Ok(if (keep(row)) [{ action: Create, role: Node, ref: ref_of(t, row)?, row: Ok(show(row)), now: Bool.True }] else [])
			Replace(old, new) =>
				if same_row(old, new)? or !(keep(old) or keep(new)) {
					Ok([])
				} else {
					Ok([{ action: Update, role: Node, ref: ref_of(t, new)?, row: Ok(show(new)), now: keep(new) }])
				}
			Delete(row) => Ok(if (keep(row)) [{ action: Delete, role: Node, ref: ref_of(t, row)?, row: Ok(show(row)), now: Bool.True }] else [])
		}

		## The notices one write of the edge table sends to the edge
		## statement of a live query (`outgoing` or `incoming`). `node_of`
		## is the end of an edge that is the row of the query, and `state`
		## the node with its edges after the write, or `Gone`. Each write
		## sends one notice, also when the node is not in the result.
		edge_notices : Table(row), Edit(row), (row -> Link(n)), (Link(n) -> Try(m, [Gone])), (m -> Bool), (m -> out) -> Try(List(Notice(out)), Error) where [row.encoder_for : Encode.Format -> (row, Encode.State -> Try(Encode.State, []))]
		edge_notices = |_, change, node_of, state, keep, show| match change {
			Create(edge) => Ok(edge_notice(Create, link_ref(node_of(edge)), state(node_of(edge)), keep, show))
			Replace(old, new) =>
				if same_row(old, new)? {
					Ok([])
				} else {
					Ok(edge_notice(Update, link_ref(node_of(new)), state(node_of(new)), keep, show))
				}
			Delete(edge) => Ok(edge_notice(Delete, link_ref(node_of(edge)), state(node_of(edge)), keep, show))
		}

		## The notices one write of the table sends to a `Read`
		## statement of a live query: this table is one that the rows of
		## the result read, through a link or with `rows()`. `reached` are
		## the rows of the result's table that the write reaches, as they
		## are after the write, each with its record: the rows whose link
		## is the written record; for `rows()`, the rows that the clause
		## relates to the written row (`related`), or every row when the
		## clause has no such relation (see `Watched`). An update that
		## changes no field that the clauses read of the record reaches
		## none (`read_lives`). Each sends one
		## notice with the action of the write. A write that changes no
		## field sends none.
		read_notices : Table(row), Edit(row), List({ ref : Ref, row : m }), (m -> Bool), (m -> out) -> Try(List(Notice(out)), Error) where [row.encoder_for : Encode.Format -> (row, Encode.State -> Try(Encode.State, []))]
		read_notices = |_, change, reached, keep, show| {
			action = match change {
				Create(_) => Create
				Replace(old, new) => if (same_row(old, new)?) return Ok([]) else Update
				Delete(_) => Delete
			}
			Ok(reached.map(|r| { action, role: Read, ref: r.ref, row: Ok(show(r.row)), now: keep(r.row) }))
		}

		## The rows of the result's table that one write reaches, when a
		## clause reads the written table with `rows()` and relates its rows
		## to the row of the result with an equality (`Near` in `Watched`):
		## each of `rows` that `relates` holds for with the written row,
		## before or after the write. A write that moves a row from one row
		## of the result to another reaches both.
		related : Edit(row), List({ ref : Ref, row : m }), (row, m -> Bool) -> List({ ref : Ref, row : m })
		related = |change, rows, relates| {
			written = match change {
				Create(r) | Delete(r) => [r]
				Replace(old, new) => [old, new]
			}
			rows.keep_if(|n| written.any(|w| relates(w, n.row)))
		}

		## The events one write of the table sends to a raw live
		## query (`Selected.live_raw`). A row that no longer matches sends
		## nothing, and a row that starts to match is `Updated`.
		events : Table(row), Edit(row), (row -> Bool), (row -> out) -> Try(List(Event(out)), Error) where [row.encoder_for : Encode.Format -> (row, Encode.State -> Try(Encode.State, []))]
		events = |Table.(t), change, keep, show| match change {
			Create(row) => Ok(if (keep(row)) [Created(ref_of(t, row)?, show(row))] else [])
			Replace(old, new) =>
				if same_row(old, new)? or !keep(new) {
					Ok([])
				} else {
					Ok([Updated(ref_of(t, new)?, show(new))])
				}
			Delete(row) => Ok(if (keep(row)) [Deleted(ref_of(t, row)?, show(row))] else [])
		}
	}

	## The path of an op of a `live_diff` patch (see `Diff.Pointer`).
	Pointer : Diff.Pointer

	## The text patch of a `change` op of a `live_diff` patch (see `Diff.TextPatch`).
	TextPatch : Diff.TextPatch

	# ------------------------------------------------------------- helpers

	## What a query reads: a whole table, a range of keys of a time series
	## (`Query.between`) or the record of one key (`Table.at`), spelled
	## when the query is made, or the result of another `SELECT`
	## (`Selected.query`), spelled with the statement.
	Target : [Whole(Str), Range(Try(Str, Error)), Record(Try(Str, Error)), Sub(Clause)]

	## A result row, as a later clause reads it. `ty` is its type. `over`
	## says what it is over the source row:
	##
	## | `over` | Result row | A later `filter` or `query` |
	## | --- | --- | --- |
	## | `Projected(fields)` | One source row projected, `fields` the projection, now and before a write (see `Rows`) | Reads the source row through `fields`, in the same `SELECT` |
	## | `PerGroup` | One group | Reads a subquery |
	##
	## `nested` is the row in the outer query of a subquery: a record by
	## its column names, another value as `$this`.
	ResultRow : { ty : Code.Ty, over : [Projected(Rows), PerGroup], nested : Translate.Binding }

	## A table that a live query watches besides the table of the query,
	## and how a write to it reaches the rows of the result:
	##
	## | Watched | The table | The rows a write reaches |
	## | --- | --- | --- |
	## | `Edge({ name, node })` | An edge table of `outgoing` or `incoming`, or of an `Out` or `In` field of a read row. `node` is the end of an edge that is the row: `in` for `outgoing`, `out` for `incoming` | The row at the end of the edge |
	## | `LinkAt({ path, target, lists, read })` | The table of the row type `target`, which a link that a clause reads through points at, a `Link` with `.get()` or a `Linked` (`Translate.reads`, `Types.lookup`). `read` is the field of the record that the clause reads, or `Whole` | The rows whose link at `path` is the written record |
	## | `Rows(name)` | A table that a clause reads with `rows()` | Every row |
	## | `Near({ name, related })` | A table that a clause reads with `rows()`, where each read keeps, finds or tests the rows with an equality to a value of the row (`Translate.narrowings`) | The rows that `related` gives, for the written record before and after the write |
	Watched : [Edge({ name : Str, node : Str }), LinkAt({ path : Str, target : Code.Ty, lists : U64, read : [Field(Str), Whole] }), Rows(Try(Str, Error)), Near({ name : Str, related : Translate.Related })]

	expect link_test("site", 0) == "site = $parent.id"
	expect link_test("items[*].product", 1) == "$parent.id IN items[*].product"
	expect link_test("nest[*].xs[*].p", 2) == "$parent.id IN array::flatten(nest[*].xs[*].p)"




	## An error of the server, of a request or of a statement.
	Failure : { kind : Str, message : Str, details : Try(Cbor.Value, [Missing]) }

}

# ============================================================ internals
#
# The helpers of the API above. They are not associated items of
# `Surreal`, so other modules do not see them.

## What the translator does not look inside. A call to one of these stays
## a call in the reified description, and the translator knows its form:
## `get` is a traversal, `id` the record id, `==` on ids `=`, `key`
## `record::id`, and `<` and `<=` on datetimes the same operators. Their
## bodies have no SurrealQL form (a byte loop, a field of the backing
## record). An intrinsic is not here: it has no body to look inside
## (`intrinsic_forms`). Every type of `Surreal` with a method that takes
## `Code` names this one list as its `code_primitives`.
cut : List(Code.PrimId)
cut = [Code.prim(Link.get), Code.prim(Link.id), Code.prim(Id.is_eq), Code.prim(Id.key), Code.prim(Id.table), Code.prim(Datetime.is_lt), Code.prim(Datetime.is_lte), Code.prim(Text.is_ascii), Code.prim(Text.is_hexadecimal), Code.prim(Hash.sha256), Code.prim(Hash.blake3), Code.prim(Array.distinct), Code.prim(Array.union), Code.prim(Array.intersect), Code.prim(Array.complement), Code.prim(Time.floor), Code.prim(Time.ceil), Code.prim(Time.round), Code.prim(Time.year), Code.prim(Time.month), Code.prim(Time.day), Code.prim(Time.hour), Code.prim(Time.minute), Code.prim(Time.second), Code.prim(Math.mean), Code.prim(Math.mean_dec), Code.prim(DbFn.call1), Code.prim(DbFn.call2), Code.prim(DbFn.call3), Code.prim(TimeKey.series), Code.prim(TimeKey.time), Code.prim(Geo.is_valid), Code.prim(Vector.similarity_cosine), Code.prim(Vector.distance_euclidean), Code.prim(Vector.distance_manhattan), Code.prim(Vector.distance_chebyshev), Code.prim(Vector.dot), Code.prim(Vector.magnitude)]


## The forms of the intrinsics of `Surreal`: the functions with a type and
## no body, which SurrealDB computes. They are `Prim`s of a description, as
## builtins are, and need no place in the cut. This table is how the package
## knows that a value reads an intrinsic (`intrinsic_ids`).
intrinsic_forms : List({ prim : Code.PrimId, form : Translate.Form })
intrinsic_forms = [
	{ prim: Code.prim(Text.is_email), form: Function({ surql: "string::is_email", random: Bool.False }) },
	{ prim: Code.prim(Text.is_url), form: Function({ surql: "string::is_url", random: Bool.False }) },
	{ prim: Code.prim(Text.is_domain), form: Function({ surql: "string::is_domain", random: Bool.False }) },
	{ prim: Code.prim(Text.is_ip), form: Function({ surql: "string::is_ip", random: Bool.False }) },
	{ prim: Code.prim(Text.is_ipv4), form: Function({ surql: "string::is_ipv4", random: Bool.False }) },
	{ prim: Code.prim(Text.is_ipv6), form: Function({ surql: "string::is_ipv6", random: Bool.False }) },
	{ prim: Code.prim(Text.is_uuid), form: Function({ surql: "string::is_uuid", random: Bool.False }) },
	{ prim: Code.prim(Text.is_ulid), form: Function({ surql: "string::is_ulid", random: Bool.False }) },
	{ prim: Code.prim(Text.is_semver), form: Function({ surql: "string::is_semver", random: Bool.False }) },
	{ prim: Code.prim(Text.is_alpha), form: Function({ surql: "string::is_alpha", random: Bool.False }) },
	{ prim: Code.prim(Text.is_alphanum), form: Function({ surql: "string::is_alphanum", random: Bool.False }) },
	{ prim: Code.prim(Text.is_numeric), form: Function({ surql: "string::is_numeric", random: Bool.False }) },
	{ prim: Code.prim(Text.is_latitude), form: Function({ surql: "string::is_latitude", random: Bool.False }) },
	{ prim: Code.prim(Text.is_longitude), form: Function({ surql: "string::is_longitude", random: Bool.False }) },
	{ prim: Code.prim(Text.is_datetime), form: Function({ surql: "string::is_datetime", random: Bool.False }) },
	{ prim: Code.prim(Text.matches), form: Function({ surql: "string::matches", random: Bool.False }) },
	{ prim: Code.prim(Text.similarity_jaro), form: Function({ surql: "string::similarity::jaro", random: Bool.False }) },
	{ prim: Code.prim(Text.similarity_jaro_winkler), form: Function({ surql: "string::similarity::jaro_winkler", random: Bool.False }) },
	{ prim: Code.prim(Text.distance_levenshtein), form: Function({ surql: "string::distance::levenshtein", random: Bool.False }) },
	{ prim: Code.prim(Text.distance_damerau_levenshtein), form: Function({ surql: "string::distance::damerau_levenshtein", random: Bool.False }) },
	{ prim: Code.prim(Text.distance_normalized_levenshtein), form: Function({ surql: "string::distance::normalized_levenshtein", random: Bool.False }) },
	{ prim: Code.prim(Hash.md5), form: Function({ surql: "crypto::md5", random: Bool.False }) },
	{ prim: Code.prim(Hash.sha1), form: Function({ surql: "crypto::sha1", random: Bool.False }) },
	{ prim: Code.prim(Hash.sha512), form: Function({ surql: "crypto::sha512", random: Bool.False }) },
	{ prim: Code.prim(Hash.argon2), form: Function({ surql: "crypto::argon2::generate", random: Bool.True }) },
	{ prim: Code.prim(Hash.argon2_matches), form: Function({ surql: "crypto::argon2::compare", random: Bool.False }) },
	{ prim: Code.prim(Auth.access), form: Variable("$access") },
	{ prim: Code.prim(Auth.expires), form: Variable("$token.exp") },
	{ prim: Code.prim(Table.auth), form: Variable("$auth.id") },
	{ prim: Code.prim(Time.now), form: Function({ surql: "time::now", random: Bool.False }) },
	{ prim: Code.prim(Time.wday), form: Function({ surql: "time::wday", random: Bool.False }) },
	{ prim: Code.prim(Time.yday), form: Function({ surql: "time::yday", random: Bool.False }) },
	{ prim: Code.prim(Time.week), form: Function({ surql: "time::week", random: Bool.False }) },
	{ prim: Code.prim(Time.unix), form: Function({ surql: "time::unix", random: Bool.False }) },
	{ prim: Code.prim(Time.unix_millis), form: Function({ surql: "time::millis", random: Bool.False }) },
	{ prim: Code.prim(Time.unix_micros), form: Function({ surql: "time::micros", random: Bool.False }) },
	{ prim: Code.prim(Time.nano), form: Function({ surql: "time::nano", random: Bool.False }) },
	{ prim: Code.prim(Time.format), form: Function({ surql: "time::format", random: Bool.False }) },
	{ prim: Code.prim(Time.from_unix), form: Function({ surql: "time::from_unix", random: Bool.False }) },
	{ prim: Code.prim(Rand.ulid), form: Function({ surql: "rand::ulid", random: Bool.True }) },
	{ prim: Code.prim(Rand.int), form: Function({ surql: "rand::int", random: Bool.True }) },
	{ prim: Code.prim(Math.median), form: Aggregate("math::median") },
	{ prim: Code.prim(Math.stddev), form: Aggregate("math::stddev") },
	{ prim: Code.prim(Math.variance), form: Aggregate("math::variance") },
	{ prim: Code.prim(Geo.area), form: Function({ surql: "geo::area", random: Bool.False }) },
	{ prim: Code.prim(Geo.bearing), form: Function({ surql: "geo::bearing", random: Bool.False }) },
	{ prim: Code.prim(Geo.centroid), form: Function({ surql: "geo::centroid", random: Bool.False }) },
	{ prim: Code.prim(Geo.distance), form: Function({ surql: "geo::distance", random: Bool.False }) },
	{ prim: Code.prim(Geo.hash_encode), form: Function({ surql: "geo::hash::encode", random: Bool.False }) },
	{ prim: Code.prim(Geo.hash_decode), form: Function({ surql: "geo::hash::decode", random: Bool.False }) },
	{ prim: Code.prim(Math.percentile), form: Percentile },
	{ prim: Code.prim(Rand.uuid), form: Uuid },
	{ prim: Code.prim(Time.group), form: TimeGroup },
	{ prim: Code.prim(Time.plus), form: Operator("+") },
	{ prim: Code.prim(Time.minus), form: Operator("-") },
	{ prim: Code.prim(Geo.contains), form: Operator("CONTAINS") },
	{ prim: Code.prim(Geo.inside), form: Operator("INSIDE") },
	{ prim: Code.prim(Geo.outside), form: Operator("OUTSIDE") },
	{ prim: Code.prim(Geo.intersects), form: Operator("INTERSECTS") },
	{ prim: Code.prim(Hit.score), form: Function({ surql: "search::score", random: Bool.False }) },
	{ prim: Code.prim(Hit.highlight), form: Render(highlight_form) },
	{ prim: Code.prim(Hit.offsets), form: Render(offsets_form) },
	{ prim: Code.prim(Near.distance), form: Variable("vector::distance::knn()") },
	{ prim: Code.prim(Table.rows), form: Rows },
	{ prim: Code.prim(Table.edges_from), form: EdgesOf("->") },
	{ prim: Code.prim(Table.edges_to), form: EdgesOf("<-") },
]

## The ids of the intrinsics of `Surreal`, as `intrinsic_forms` binds them.
intrinsic_ids : List(Code.PrimId)
intrinsic_ids = intrinsic_forms.map(|entry| entry.prim)

## The forms of the functions of `Surreal` that a clause may call, by their
## ids: the intrinsics, the cut, and the tables a clause names. The translator
## cannot import this module, so every call into it carries this extension
## (`own`), and `Query.filter_with` adds the caller's after it.
surreal_library : Translate.Extension
surreal_library = Translate.forms(
	intrinsic_forms.concat(
		[
			{ prim: Code.prim(Link.get), form: LinkGet },
			{ prim: Code.prim(Link.id), form: LinkId },
			{ prim: Code.prim(Id.is_eq), form: IdEq },
			{ prim: Code.prim(Id.key), form: IdKey },
			{ prim: Code.prim(Id.table), form: IdTable },
			{ prim: Code.prim(Datetime.is_lt), form: DatetimeOrder },
			{ prim: Code.prim(Datetime.is_lte), form: DatetimeOrder },
			{ prim: Code.prim(Text.is_ascii), form: Function({ surql: "string::is_ascii", random: Bool.False }) },
			{ prim: Code.prim(Text.is_hexadecimal), form: Function({ surql: "string::is_hexadecimal", random: Bool.False }) },
			{ prim: Code.prim(Hash.sha256), form: Function({ surql: "crypto::sha256", random: Bool.False }) },
			{ prim: Code.prim(Hash.blake3), form: Function({ surql: "crypto::blake3", random: Bool.False }) },
			{ prim: Code.prim(Array.distinct), form: Function({ surql: "array::distinct", random: Bool.False }) },
			{ prim: Code.prim(Array.union), form: Function({ surql: "array::union", random: Bool.False }) },
			{ prim: Code.prim(Array.intersect), form: Function({ surql: "array::intersect", random: Bool.False }) },
			{ prim: Code.prim(Array.complement), form: Function({ surql: "array::complement", random: Bool.False }) },
			{ prim: Code.prim(Time.floor), form: Function({ surql: "time::floor", random: Bool.False }) },
			{ prim: Code.prim(Time.ceil), form: Function({ surql: "time::ceil", random: Bool.False }) },
			{ prim: Code.prim(Time.round), form: Function({ surql: "time::round", random: Bool.False }) },
			{ prim: Code.prim(Time.year), form: Function({ surql: "time::year", random: Bool.False }) },
			{ prim: Code.prim(Time.month), form: Function({ surql: "time::month", random: Bool.False }) },
			{ prim: Code.prim(Time.day), form: Function({ surql: "time::day", random: Bool.False }) },
			{ prim: Code.prim(Time.hour), form: Function({ surql: "time::hour", random: Bool.False }) },
			{ prim: Code.prim(Time.minute), form: Function({ surql: "time::minute", random: Bool.False }) },
			{ prim: Code.prim(Time.second), form: Function({ surql: "time::second", random: Bool.False }) },
			{ prim: Code.prim(Math.mean), form: Aggregate("math::mean") },
			{ prim: Code.prim(Math.mean_dec), form: FloatAggregate("math::mean") },
			{ prim: Code.prim(Geo.is_valid), form: Function({ surql: "geo::is_valid", random: Bool.False }) },
			{ prim: Code.prim(Vector.similarity_cosine), form: Function({ surql: "vector::similarity::cosine", random: Bool.False }) },
			{ prim: Code.prim(Vector.distance_euclidean), form: Function({ surql: "vector::distance::euclidean", random: Bool.False }) },
			{ prim: Code.prim(Vector.distance_manhattan), form: Function({ surql: "vector::distance::manhattan", random: Bool.False }) },
			{ prim: Code.prim(Vector.distance_chebyshev), form: Function({ surql: "vector::distance::chebyshev", random: Bool.False }) },
			{ prim: Code.prim(Vector.dot), form: Function({ surql: "vector::dot", random: Bool.False }) },
			{ prim: Code.prim(Vector.magnitude), form: Function({ surql: "vector::magnitude", random: Bool.False }) },
			{ prim: Code.prim(DbFn.call1), form: CallDbFn },
			{ prim: Code.prim(DbFn.call2), form: CallDbFn },
			{ prim: Code.prim(DbFn.call3), form: CallDbFn },
			{ prim: Code.prim(TimeKey.series), form: SeriesOf },
			{ prim: Code.prim(TimeKey.time), form: TimeOf },
			{ prim: Code.prim(Surreal.table), form: TableOf },
			{ prim: Code.prim(Surreal.view), form: TableOf },
			{ prim: Code.prim(Surreal.relation), form: RelationOf },
			{ prim: Code.prim(Table.id), form: RecordOf },
		],
	),
)

own : List(Translate.Extension)
own = [surreal_library]

## Byte order, as the text of a datetime sorts.
bytes_lt : List(U8), List(U8) -> Bool
bytes_lt = |a, b| match (a, b) {
	([x, .. as xs], [y, .. as ys]) => x < y or (x == y and bytes_lt(xs, ys))
	([], [_, ..]) => Bool.True
	_ => Bool.False
}

days_in_month : U64, U64 -> U64
days_in_month = |year, month|
	if month == 2 {
		if (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)) 29 else 28
	} else if month == 4 or month == 6 or month == 9 or month == 11 {
		30
	} else {
		31
	}

## The day number of a date, counting from 1970-01-01.
days_from_civil : I128, I128, I128 -> I128
days_from_civil = |year, month, day| {
	shifted = if (month <= 2) year - 1 else year
	era = shifted.div_floor_by(400)
	year_of_era = shifted - era * 400
	day_of_year = (153 * (if (month > 2) month - 3 else month + 9) + 2) // 5 + day - 1
	era * 146097 + year_of_era * 365 + year_of_era // 4 - year_of_era // 100 + day_of_year - 719468
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

## The nanoseconds of the fraction of a datetime.
fraction_nanos : Datetime -> I128
fraction_nanos = |Datetime.(d)| {
	digits = d.iso.to_utf8().drop_first(20).drop_last(1)
	digits.concat(List.repeat(48, 9 - digits.len())).fold(0.I128, |acc, b| acc * 10 + (b - 48).to_i128())
}

## A number in at least `width` digits, with leading zeros.
pad : I128, U64 -> Str
pad = |n, width| {
	text = n.to_str()
	Str.repeat("0", width - text.count_utf8_bytes()).concat(text)
}

## A fraction without its trailing zeros.
drop_zeros : List(U8) -> List(U8)
drop_zeros = |digits| match digits.last() {
	Ok(48) => drop_zeros(digits.drop_last(1))
	_ => digits
}

## The datetime of `[seconds]` or `[seconds, nanoseconds]` since 1970,
## the item of the tag 12 of SurrealDB.
datetime_of : List(I64) -> Try(Datetime, [BadDatetime])
datetime_of = |parts| match parts {
	[secs] => Datetime.from_unix_nanos(secs.to_i128() * 1000000000)
	[secs, nanos] if nanos >= 0 and nanos < 1000000000 => Datetime.from_unix_nanos(secs.to_i128() * 1000000000 + nanos.to_i128())
	_ => Err(BadDatetime)
}

## The item after a CBOR tag, read as `a`. Another tag is an error at the tag.
tagged : Cbor, Cbor.Reader, U64 -> Try({ value : a, rest : Cbor.Reader }, [InvalidCbor(U64), ..errs]) where [a.Cbor.Parseable([InvalidCbor(U64), ..errs])]
tagged = |encoding, state, number| {
	tag = Cbor.parse_cbor_tag(encoding, state)?
	if tag.value == number {
		Cbor.parse_item(encoding, tag.rest)
	} else {
		Err(Cbor.invalid_value(encoding, state))
	}
}

## The GeoJSON object of a geometry. SurrealDB 3.3.4 reads an object of
## this shape as a geometry: `{ type: 'Point', coordinates: [lon, lat] }`.
geojson : Geometry -> Ql.Value
geojson = |geometry| match geometry {
	Point(p) => shaped("Point", position(p))
	Line(Line.(points)) => shaped("LineString", Ql.Value.Array(points.map(position)))
	Polygon(p) => shaped("Polygon", rings_of(p))
	MultiPoint(MultiPoint.(points)) => shaped("MultiPoint", Ql.Value.Array(points.map(position)))
	MultiLine(MultiLine.(lines)) => shaped("MultiLineString", Ql.Value.Array(lines.map(|Line.(points)| Ql.Value.Array(points.map(position)))))
	MultiPolygon(MultiPolygon.(polygons)) => shaped("MultiPolygon", Ql.Value.Array(polygons.map(rings_of)))
	Collection(Collection.(items)) => Ql.Value.Object([{ name: "type", value: Ql.Value.Str("GeometryCollection") }, { name: "geometries", value: Ql.Value.Array(items.map(geojson)) }])
}

## `{ type: kind, coordinates: .. }`.
shaped : Str, Ql.Value -> Ql.Value
shaped = |kind, coordinates| Ql.Value.Object([{ name: "type", value: Ql.Value.Str(kind) }, { name: "coordinates", value: coordinates }])

## `[lon, lat]`.
position : Point -> Ql.Value
position = |Point.(p)| Ql.Value.Array([Ql.Value.Float(p.lon), Ql.Value.Float(p.lat)])

## The outer ring, then the holes.
rings_of : Polygon -> Ql.Value
rings_of = |Polygon.(p)| Ql.Value.Array([p.exterior].concat(p.holes).map(|ring| Ql.Value.Array(ring.map(position))))

## Every point of a geometry, at any depth.
points_of : Geometry -> List(Point)
points_of = |geometry| match geometry {
	Point(p) => [p]
	Line(Line.(points)) | MultiPoint(MultiPoint.(points)) => points
	Polygon(Polygon.(p)) => [p.exterior].concat(p.holes).join()
	MultiLine(MultiLine.(lines)) => lines.join_map(|Line.(points)| points)
	MultiPolygon(MultiPolygon.(polygons)) => polygons.join_map(|Polygon.(p)| [p.exterior].concat(p.holes).join())
	Collection(Collection.(items)) => items.join_map(points_of)
}

## The name of a table.
name_of : Table(row) -> Str
name_of = |Table.(t)| t.name

## The query of `Grouped.aggregate`, and of a view when `in_view` is set.
## A key part is grouped by the alias of the column that projects it:
## SurrealDB refuses a call after `GROUP BY`, and a part that no column
## selects ("Missing group idiom"), and an alias wins over a field of the
## same name (verified). The column and the part are one binding, so
## their texts are equal. A key with no parts, `|_| {}`, is refused:
## `GROUP BY` takes a part, and `GROUP ALL` gives one row for no rows,
## where a group of no rows is no group (`Query.totals` is that query).
aggregated : Grouped(p, row, k), Code((k, List(row) -> out)), Bool -> Selected(p, out)
aggregated = |Grouped.(g), per_group, in_view| {
	Query.(q) = g.query
	base = q.source.now
	key = g.key
	groups = |param| {
		parts = parts_of(within_clause("`group_by`", Translate.evaluate(own, key.graph(), [base?], spelled(key, param)))?)?
		columns = within_clause("`aggregate`", group_columns(key, per_group, base?, param, in_view))?
		if parts.is_empty() {
			return Err(Unsupported("`group_by(|_| {})` groups by a key of no parts, and SurrealDB has no `GROUP BY` of nothing. `GROUP ALL` is not the same: it gives one row for no rows. Take `totals`"))
		}
		named = parts.map_try(
			|part| match columns.find_first(|c| c.surql == part) {
				Ok(c) => Ok(Ql.ident(c.name))
				Err(_) => Err(Unsupported("the group key part `${part}` is not a column of the result: SurrealDB groups by a selected column only (\"Missing group idiom\"). Return the key, or its part, from the function of `aggregate`"))
			},
		)?
		Ok(Str.join_with(named, ", "))
	}
	columns = |param| Ok(aliased(within_clause("`aggregate`", group_columns(key, per_group, base?, param, in_view))?))
	ty = per_group.graph().root_row().result
	selected_of({ ..q, slots: q.slots.concat(slots_of(key)).concat(slots_of(per_group)) }, { columns, value: |_| Err(live_group), intrinsic: intrinsic_columns(per_group.graph()) }, by_name, [groups], { ty, over: PerGroup, nested: nested_row(ty) })
}

## The query of `Query.totals`: the columns of the one function of the rows.
totalled : Query(p, row), Code(List(row) -> out) -> Totals(p, out)
totalled = |Query.(q), per_total| {
	base = q.source.now
	columns = |param| Ok(aliased(within_clause("`totals`", Translate.total_columns(own, per_total.graph(), [Translate.Binding.Group(base?)], spelled(per_total, param)))?))
	ty = per_total.graph().root_row().result
	Totals.(selected_of({ ..q, slots: q.slots.concat(slots_of(per_total)) }, { columns, value: |_| Err(live_group), intrinsic: intrinsic_columns(per_total.graph()) }, by_name, [], { ty, over: PerGroup, nested: nested_row(ty) }))
}

group_all : Str -> Str
group_all = |text| "${text} GROUP ALL"

## The result columns of one group: the key and the group's rows bound.
group_columns : Code(row -> k), Code((k, List(row) -> out)), Translate.Binding, (Str -> Str), Bool -> Try(List({ name : Str, surql : Str }), Error)
group_columns = |key, per_group, base, param, in_view| {
	group_key = Translate.evaluate(own, key.graph(), [base], spelled(key, param))?
	bindings = [group_key, Translate.Binding.Group(base)]
	if (in_view) Translate.view_columns(own, per_group.graph(), bindings, spelled(per_group, param)) else Translate.columns(own, per_group.graph(), bindings, spelled(per_group, param))
}

## The id of a row by its table's name. `Table.id` is the same with the
## name from the table.
id_of : Str, Str -> Id(row)
id_of = |name, key| Id.({ table: name, key: key })

is_edge : TableKind -> Bool
is_edge = |kind| match kind {
	Relation(_) => Bool.True
	Normal | View => Bool.False
}

## Whether a filter over `$before` reads the row only through its record
## id (`$before.id`) and its edges (`$before<-e`, `$before->e`), which a
## write of the row does not change.
keyed_only : Str -> Bool
keyed_only = |text| {
	parts = text.split_on("$before")
	parts.drop_first(1).all(
		|rest| {
			after_id = rest.drop_prefix(".id")
			ends_id = rest.starts_with(".id") and (after_id.is_empty() or !Ql.is_plain(Str.from_utf8(after_id.to_utf8().take_first(1)) ?? ""))
			ends_id or rest.starts_with("<-") or rest.starts_with("->")
		},
	)
}

expect keyed_only("type::record('kennel', record::id($before.id)).chain(|$v1| $v1)")
expect keyed_only("$before<-cares_for.len() = 0")
expect !keyed_only("$before.site.name = 'Oslo'")
expect !keyed_only("$before.identity = 1")
expect !keyed_only("fn::fever($before.temp_c, $before.pulse)")

## The text after `FROM`.
from_text : Target, (Str -> Str) -> Try(Str, Error)
from_text = |target, param| match target {
	Whole(name) => Ok(Ql.ident(name))
	Range(range) => range
	Record(record) => record
	Sub(clause) => clause(param)
}

is_edge_of : Watched -> Bool
is_edge_of = |w| match w {
	Edge(_) => Bool.True
	LinkAt(_) | Rows(_) | Near(_) => Bool.False
}

## The `LIVE` of each table that the rows read, after those of the
## edges, in the order the clauses reach them. `rows` is the payload
## over the rows of the result's table: one notice for each row it
## gives. A table of `rows()` gives every row. Any other gives the
## rows that link to the written record, `$parent`:
##
## `LIVE SELECT VALUE (SELECT VALUE { ref: id, row: <row>, now: <p> } FROM t WHERE site = $parent.id) FROM site`
##
## The test of a link in a list is `$parent.id IN items[*].product`.
## When the clauses read only some fields of the written table, an
## update that changes none of them sends nothing, a create and a
## delete always send (verified):
##
## `LIVE SELECT VALUE (..) FROM site WHERE $before IS NONE OR $after IS NONE OR $before.name != $after.name`
##
## A table of `Near` gives the rows that its relations reach, where the
## relation reads the written record before and after the write (see
## `near_rows`). When the rows are records of the result's table, the
## subquery reads them, and no other row:
##
## `LIVE SELECT VALUE (SELECT VALUE { ref: id, .. } FROM record::id($parent.id)[0]) FROM vital`
read_lives : List(Watched), Types.Registry, Str, Str -> Try(List({ role : Role, surql : Str }), Error)
read_lives = |watched, registry, select, table| {
	reached = watched.map_try(
		|w| match w {
			Edge(_) => Ok([])
			Rows(name) => Ok([{ table: name?, test: Whole, read: Whole }])
			Near(n) => Ok([{ table: n.name, test: Near(n.related), read: Whole }])
			LinkAt(l) =>
				match Types.lookup(registry, l.target) {
					Ok(found) => Ok([{ table: found, test: Test(link_test(l.path, l.lists)), read: l.read }])
					Err(message) => Err(BadSchema("a live query watches the table of each link of its row, and the tables it takes do not name the one at `${l.path}`: ${message}"))
				}
		},
	)?.join()
	names = reached.fold([], |kept, r| if (kept.contains(r.table)) kept else kept.append(r.table))
	distinct = |texts| texts.fold([], |kept, t| if (kept.contains(t)) kept else kept.append(t))
	Ok(
		names.map(
			|named| {
				of_table = reached.keep_if(|r| r.table == named)
				tests = distinct(of_table.map(|r| r.test))
				rows = match tests {
					_ if tests.contains(Whole) => "${select} FROM ${table}"
					[Near(r)] if r.node == "id" => "${select} FROM ${near_rows(r)}"
					_ => {
						texts = tests.keep_oks(
							|t| match t {
								Test(text) => Ok(text)
								Near(r) => Ok(near_test(r))
								Whole => Err(NoTest)
							},
						)
						"${select} FROM ${table} WHERE ${Str.join_with(texts, " OR ")}"
					}
				}
				reads = of_table.map(|r| r.read)
				changed = if reads.contains(Whole) {
					""
				} else {
					fields = reads.keep_oks(
						|r| match r {
							Field(name) => Ok(name)
							Whole => Err(NoField)
						},
					)
					" WHERE $before IS NONE OR $after IS NONE OR ${Str.join_with(distinct(fields).map(|f| "$before.${f} != $after.${f}"), " OR ")}"
				}
				{ role: Read, surql: "LIVE SELECT VALUE (${rows}) FROM ${Ql.ident(named)}${changed}" }
			},
		),
	)
}

## The values of a relation of `Near` over the written record: of the
## record, `$parent`, when the relation reads only its id; else of the
## record before and after the write, so that a row the write moves from
## one row of the result to another reaches both. `$before` of a `CREATE`
## and `$after` of a `DELETE` are NONE, and are left out (verified on
## SurrealDB 3.3.5 and 4.0.0).
near_rows : Translate.Related -> Str
near_rows = |r| {
	docs = "[$before, $after].filter(|$w| $w != NONE).map(|$w| ${r.each})"
	match (r.fixed, r.many) {
		(Bool.True, Bool.False) => r.written
		(Bool.True, Bool.True) => "array::distinct(${r.written})"
		(Bool.False, Bool.False) => "array::distinct(${docs})"
		(Bool.False, Bool.True) => "array::distinct(array::flatten(${docs}))"
	}
}

## The test of a relation of `Near` over a row of the result.
near_test : Translate.Related -> Str
near_test = |r| if (r.fixed and !r.many) "${r.node} = ${r.written}" else "${r.node} IN ${near_rows(r)}"

## The test that the link at `path` is the written record. Under
## `lists` lists, the path gives a list of lists, which
## `array::flatten` makes one list (verified).
link_test : Str, U64 -> Str
link_test = |path, lists| match lists {
	0 => "${path} = $parent.id"
	n => "$parent.id IN ${flattened(path, n - 1)}"
}

flattened : Str, U64 -> Str
flattened = |text, times| if (times == 0) text else flattened("array::flatten(${text})", times - 1)

add_watched : List(Watched), Watched -> List(Watched)
add_watched = |kept, w| if (kept.contains(w)) kept else kept.append(w)

## The tables a live query watches after one more clause: the edge
## table of each `Out` and `In` field of the row that the clause reads,
## the table of each row that it reads through a link, at the path of
## the link (`Translate.reads`), and each table that it reads with
## `rows()`. `params` are what the clause's parameters are.
reached_watches : List(Watched), Code.Graph, List(Translate.Reach), Try(List(Translate.Narrow), [Unknown]) -> List(Watched)
reached_watches = |watched, graph, params, narrows| {
	reads = Translate.reads(own, graph, params).reads.map(
		|r| match r {
			Hop(site) => LinkAt(site)
			Edges(e) => Edge(e)
			Every(name) => Rows(Ok(name))
		},
	)
	reads.concat(rows_read(graph).join_map(|w| near(w, narrows))).fold(watched, add_watched)
}

## A table of `rows()` as the rows that a write to it reaches: `Near`
## when each read of the table in the clause is `Related`, else every
## row. A read that the walk did not find is every row.
near : Watched, Try(List(Translate.Narrow), [Unknown]) -> List(Watched)
near = |w, narrows| match (w, narrows) {
	(Rows(Ok(name)), Ok(found)) => {
		mine = found.keep_if(|n| n.table == Ql.ident(name))
		related = mine.keep_oks(
			|n| match n.reach {
				Related(r) => Ok(r)
				Every => Err(Every)
			},
		)
		if mine.is_empty() or related.len() != mine.len() [w] else related.map(|r| Near({ name, related: r }))
	}
	_ => [w]
}

## The reads of `rows()` in a clause over `bindings`, as a live query
## spells them (`Translate.narrowings`).
narrowed : Code.Graph, Try(List(Translate.Binding), Error) -> Try(List(Translate.Narrow), [Unknown])
narrowed = |graph, bindings| match bindings {
	Ok(found) => Translate.narrowings(own, graph, found, Translate.variable).map_err(|_| Unknown)
	Err(_) => Err(Unknown)
}

## The tables that a clause reads with `rows()`, each by the literal
## name that the clause gives it, as the translator reads it.
rows_read : Code.Graph -> List(Watched)
rows_read = |graph| graph.rows().join_map(
	|row| row.nodes.keep_oks(
		|node| match (node.op, node.args) {
			(Prim({ id, .. }), [arg]) if id == Code.prim(Table.rows) => Ok(Rows(table_name(row, arg)))
			_ => Err(NotRows)
		},
	),
)

## The name of a table that a clause builds with `Surreal.table`,
## `view` or `relation` and a literal name.
table_name : Code.Row, Code.Val -> Try(Str, Error)
table_name = |row, value| {
	named = Unsupported("a live query watches the table that `rows()` reads, so the clause names it: `Surreal.table(\"name\")` or a constant of one")
	match value {
		Node(i) =>
			match (row.node(i).op, row.node(i).args) {
				(Prim({ id, .. }), [Node(n), ..]) if id == Code.prim(Surreal.table) or id == Code.prim(Surreal.view) or id == Code.prim(Surreal.relation) =>
					match row.node(n).op {
						Lit(Str(name)) => Ok(name)
						_ => Err(named)
					}
				_ => Err(named)
			}
		_ => Err(named)
	}
}

## A projection over the source rows, evaluated once. A projection reads
## no parameter record, so the spelling of a parameter does not change it.
projected_rows : Rows, Code.Graph -> Rows
projected_rows = |rows, graph| {
	over = |row| Translate.evaluate(own, graph, [row?], Translate.variable)
	{ now: over(rows.now), before: over(rows.before), reach: Translate.reads(own, graph, [rows.reach]).reach }
}

## The row a filter reads.
pick : Rows, [Now, Before] -> Try(Translate.Binding, Error)
pick = |rows, at| match at {
	Now => rows.now
	Before => rows.before
}

## A result row of type `ty` in the outer query of a subquery.
nested_row : Code.Ty -> Translate.Binding
nested_row = |ty| match Translate.at("$this", ty) {
	Row(_) => Translate.Binding.Row({ at: "", of: Obj, edge: Bool.False })
	other => other
}

## A table row with its edges, which `edges` reads off the record the
## row is at: the pair `(row, List(edge))`, and after a second edge
## table the triple `(row, List(e1), List(e2))`. A row of a subquery has
## no edges: it is a copy, and its `id` is the key, not the record id.
with_edges : Try(Translate.Binding, Error), (Str -> Translate.Binding) -> Try(Translate.Binding, Error)
with_edges = |row, edges| match row? {
	Row({ at, of: Doc(named), edge }) => Ok(Translate.Binding.WithEdges(Translate.Binding.Row({ at, of: Doc(named), edge }), [edges(at)]))
	WithEdges(Row({ at, of: Doc(named), edge }), lists) => Ok(Translate.Binding.WithEdges(Translate.Binding.Row({ at, of: Doc(named), edge }), lists.append(edges(at))))
	_ => Err(Unsupported("only a row of a table has edges; take `outgoing` or `incoming` before `select`"))
}

## The tables at the ends of an edge table, for a hop to an end.
ends_of : TableKind -> Translate.Ends
ends_of = |kind| match kind {
	Relation(ends) => ends
	_ => Translate.any_ends
}

## The row of `Query.search` and `Query.nearest`: the pair of the table
## row and what the search knows of it, `ref`, which `Hit` and `Near`
## read: the number of the search, or `vector::distance::knn()`. The
## search reads the rows of the table of its index, so a row of a
## subquery or of another table is refused.
paired : Rows, Str, Str -> Rows
paired = |rows, table, ref| {
	now = match rows.now {
		Ok(Row({ at: "", of: Doc(Of(name)), edge })) if name == table => Ok(Translate.Binding.WithEdges(Translate.Binding.Row({ at: "", of: Doc(Of(name)), edge }), [Translate.Binding.Expr(ref)]))
		Ok(Row({ of: Doc(Of(name)), .. })) => Err(Unsupported("the index is of the table `${table}`, and this query reads `${name}`"))
		Ok(_) => Err(Unsupported("a search reads the rows of the table of its index, and this query reads the rows of a subquery"))
		Err(e) => Err(e)
	}
	{ now, before: Err(live_search), reach: Translate.Reach.Pair([rows.reach, Translate.Reach.Nothing]) }
}

live_search : Error
live_search = Unsupported("a live query has no full-text or vector search: a search reads its index, and a notice is of one written row; watch the rows with a `filter`, and search them when a notice comes")

## `search::highlight(before, after, n)` of `Hit.highlight`.
highlight_form : { args : List(Str), evidence : List(Code.Evidence) } -> Try(Str, Str)
highlight_form = |call| match call.args {
	[hit, before, after] => Ok(Translate.call("search::highlight", [before, after, hit]))
	_ => Err("it takes a hit and two texts")
}

## `search::offsets(n)` of `Hit.offsets`: an object of the offsets of
## each value of the field, under its place, `'0'` for a `Str`.
offsets_form : { args : List(Str), evidence : List(Code.Evidence) } -> Try(Str, Str)
offsets_form = |call| match call.args {
	[hit] => Ok("search::offsets(${hit})['0'].map(|$o| { end: $o.e, start: $o.s })")
	_ => Err("it takes a hit")
}

## The path of the one field of an index: no element of a list.
one_path : Code.Graph, Str -> Try(Str, Error)
one_path = |graph, what| {
	steps = Translate.path_of(graph)?
	if steps.contains(Each) {
		Err(Unsupported("${what} is on one field, not on each element of a list"))
	} else {
		Ok(Translate.spell(steps))
	}
}

same_table : Str, Str -> Try({}, Error)
same_table = |defined, indexed| if (defined == indexed) Ok({}) else Err(BadSchema("the index is of the table `${indexed}`, and this definition is of `${defined}`"))

distance_name : Distance -> Str
distance_name = |distance| match distance {
	Cosine => "COSINE"
	Euclidean => "EUCLIDEAN"
	Manhattan => "MANHATTAN"
	Chebyshev => "CHEBYSHEV"
}

## The pairs of the elements of two vectors of one dimension. SurrealDB
## refuses two dimensions with an error.
same_dimension : Str, List(F64), List(F64) -> List((F64, F64))
same_dimension = |name, a, b|
	if a.len() == b.len() {
		List.map2(a, b, |x, y| (x, y))
	} else {
		crash "Surreal.Vector.${name}: the two vectors must be of the same dimension"
	}

## The class of an ASCII character for a tokenizer: 0 white space, 1 a
## letter, 2 a digit, 3 anything else.
char_class : U8 -> U8
char_class = |b|
	if b == 32 or (b >= 9 and b <= 13) {
		0
	} else if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) {
		1
	} else if b >= 48 and b <= 57 {
		2
	} else {
		3
	}

## The tokens of ASCII text: the runs between white space, and with
## `by_class` each run of one class.
ascii_runs : List(U8), Bool -> List(List(U8))
ascii_runs = |bytes, by_class| {
	var $runs = []
	var $current = []
	var $last = 0
	for b in bytes {
		class = char_class(b)
		kind = if (by_class or class == 0) class else 1
		if kind == 0 {
			if !$current.is_empty() {
				$runs = $runs.append($current)
				$current = []
			}
		} else if !$current.is_empty() and kind != $last {
			$runs = $runs.append($current)
			$current = [b]
		} else {
			$current = $current.append(b)
		}
		$last = kind
	}
	if ($current.is_empty()) $runs else $runs.append($current)
}

## The keys from `low` to `high`, `high` left out: `t:[s, lo]..[s, hi]`.
key_range : Str, TimeKey(s), TimeKey(s) -> Try(Str, Error) where [s.encoder_for : Encode.Format -> (s, Encode.State -> Try(Encode.State, []))]
key_range = |name, low, high| {
	lo = Encode.value_of(low)?
	hi = Encode.value_of(high)?
	Ok("${Ql.record_ref(name, lo)}..${Ql.literal(hi)}")
}

## The record id of `id` in the table `t`, its key escaped
## (`Ql.record_id`). An id of another table is refused: two tables
## can have the same row type.
record_at : { name : Str, kind : TableKind }, Id(row) -> Try(Str, Error)
record_at = |t, Id.(i)|
	if i.table == t.name {
		Ok(Ql.record_id(t.name, i.key))
	} else {
		Err(Unsupported("the id `${Ql.record_id(i.table, i.key)}` is of the table `${i.table}`, not of `${t.name}`"))
	}

## The `UPDATE` of the record of `id` with the `SET` items of `sets`
## over its row (`Table.update_at`, `set_at`).
update_key : { name : Str, kind : TableKind }, Code(Id(row)), List(Slot), (Translate.Binding, (Str -> Str) -> Try(List({ name : Str, surql : Str }), Error)) -> Write(p, row)
update_key = |t, id, patch_slots, sets| {
	row = Translate.table_row(t.name, is_edge(t.kind))
	key = key_of(t, id)
	build = |param| {
		writable(t)?
		record = key.text?
		Ok("UPDATE ${record} SET ${set_list(sets(row, param)?)}")
	}
	Write.({ build: build, gives: After, edge: is_edge(t.kind), slots: key.slots.concat(patch_slots) })
}

## The record id of a key of `Table.at` or a keyed write: the literal id
## of a key that the program fixes, and the slot of one it only knows when
## it runs, whose table is checked when it is bound. An id of another
## table is refused.
key_of : { name : Str, kind : TableKind }, Code(Id(row)) -> { text : Try(Str, Error), slots : List(Slot) }
key_of = |t, key| {
	slots = keyed_slots(key, Of(t.name), Bool.False)
	text = within_clause("the key", Translate.render(own, key.graph(), [], spelled(key, Translate.variable)))
	checked = match text {
		Ok(spelled_key) if !slots.is_empty() or spelled_key.starts_with("${Ql.ident(t.name)}:") => Ok(spelled_key)
		Ok(spelled_key) => Err(Unsupported("the id `${spelled_key}` is not of the table `${t.name}`"))
		Err(e) => Err(e)
	}
	{ text: checked, slots }
}

## The `MERGE` of `partial` into the record of a key.
keyed_merge : Str, { name : Str, kind : TableKind }, Id(row), a -> Try(Statement, Error) where [a.encoder_for : Encode.Format -> (a, Encode.State -> Try(Encode.State, []))]
keyed_merge = |verb, t, row_id, partial| {
	record = record_at(t, row_id)?
	merge_write(verb, t, record, partial)
}

## The `DELETE` of the record of a row.
delete_of : { name : Str, kind : TableKind }, a -> Try(Statement, Error) where [a.encoder_for : Encode.Format -> (a, Encode.State -> Try(Encode.State, []))]
delete_of = |t, row| {
	writable(t)?
	Ok(statement_of("DELETE ${ref_of(t, row)?.to_str()}"))
}

## The graph of a clause that the database stores: a schema rule, an
## index, a permission, a view, an access method. SurrealDB stores its
## text and runs it with no parameters, so a captured value, which
## exists only when the program runs, is refused at the place the clause
## reads it. Only a chain that the compiler runs has captured values, so
## this is a compile error.
stored_graph : Code(f), Str -> Code.Graph
stored_graph = |code, context| {
	graph = code.graph()
	if !graph.slots().is_empty() {
		match input_node(graph, 0) {
			Ok(at) => code.refuse_at(at, stored_message(context))
			Err(_) => crash stored_message(context)
		}
	} else {
		graph
	}
}

stored_message : Str -> Str
stored_message = |context| "${context} is stored in the database and runs with no parameters, so it cannot read a value that exists only when the program runs. Use a top-level constant"

## A view is filled by SurrealDB from its query, so a write to it is refused.
writable : { name : Str, kind : TableKind } -> Try({}, Error)
writable = |t| match t.kind {
	View => Err(Unsupported("`${t.name}` is a view, and a view is read-only"))
	Normal | Relation(_) => Ok({})
}

## A `Selected` of a query. `shape` is its columns, and its result row as one value.
selected_of : { target : Target, filters : List(Filter), source : Rows, watched : List(Watched), slots : List(Slot) }, { columns : Clause, value : Clause, intrinsic : List(Str) }, ResultOrder, List(Clause), ResultRow -> Selected(p, out)
selected_of = |q, shape, results, groups, rows| Selected.(
	{
		target: q.target,
		filters: q.filters,
		watched: q.watched,
		fetches: [],
		groups: groups,
		columns: shape.columns,
		value: shape.value,
		intrinsic: shape.intrinsic,
		results: results,
		rows: rows,
		order: [],
		limit: Unlimited,
		start: FromFirst,
		slots: q.slots,
	},
)

## The count of `limit` or `start`: its literal, or the mark of its slot.
count_text : Code(U64) -> Try(Str, Error)
count_text = |count| within_clause("the count", Translate.render(own, count.graph(), [], spelled(count, Translate.variable)))

is_unlimited : [Unlimited, Limit(Try(Str, Error))] -> Bool
is_unlimited = |limit| match limit {
	Unlimited => Bool.True
	Limit(_) => Bool.False
}

from_first : [FromFirst, Start(Try(Str, Error))] -> Bool
from_first = |start| match start {
	FromFirst => Bool.True
	Start(_) => Bool.False
}

row_of_pair : Error
row_of_pair = Unsupported("a pair of a row and its edges is not a record; select its columns with `select(|(row, edges)| { .. })`")

live_group : Error
live_group = Unsupported("a live query has no GROUP BY: SurrealDB refuses it. Define the group as a view with `Surreal.view` and watch the view")

live_star : Error
live_star = Unsupported("a live query sends typed rows, and `Unchecked.select_star` has no row type; select the fields with `select`")

## A result row is read by the names of its columns, so `id` is the column
## and not the key of the record. A column may be an alias, so the key
## reads one column and no further.
by_name : ResultOrder
by_name = |key, _| if (one_column(key)) Ok(Translate.Binding.Row({ at: "", of: Obj, edge: Bool.False })) else Err(column_order)

column_order : Error
column_order = Unsupported("`order_by` orders by one column of the result, `|r| r.column`: SurrealDB orders by a field path only, and does not order by a path into a column or through a link (it accepts one and leaves the rows unordered). Select the value as a column of its own and order by that column")

value_order : Error
value_order = Unsupported("`order_by` of a `select_value` reads the value as a field path of the source row, and this value is computed, read through a link or `id`: SurrealDB orders by a field path only. Take `select` with the value as a column and order by the column")

## The key is one field of the row it takes: `|r| r.rate`.
one_column : Code.Graph -> Bool
one_column = |graph| match graph.rows() {
	[row] => match row.nodes {
		[{ op: Field(_), args: [Param(0)], .. }] | [{ op: OptField(_), args: [Param(0)], .. }] => Bool.True
		_ => Bool.False
	}
	_ => Bool.False
}

## The function reads a path of fields of records off the row it takes,
## and nothing else: each node is a field of a record, or the record of a
## nominal type, so no link is traversed and nothing is computed. `|r| r`
## is the empty path.
field_path : Code.Graph -> Bool
field_path = |graph| match graph.rows() {
	[row] => row.nodes.all(
		|node| match (node.op, node.args) {
			(Field(_), [arg]) | (OptField(_), [arg]) | (Unwrap, [arg]) => match val_ty(row, arg) {
				Ok(ty) => record_like(ty)
				Err(_) => Bool.False
			}
			_ => Bool.False
		},
	)
	_ => Bool.False
}

## The `id` of the row the function takes: on a table row it is the
## record id, `record::id(id)` as a column, so it is not a field path.
reads_id : Code.Graph -> Bool
reads_id = |graph| graph.root_row().nodes.any(
	|node| match (node.op, node.args) {
		(Field("id"), [Param(0)]) => Bool.True
		_ => Bool.False
	},
)

## A record, or a nominal type of one, which a field reads in place. A
## `Linked` is a record link: a field read through it is a traversal.
record_like : Code.Ty -> Bool
record_like = |ty| match ty {
	Record(_) => Bool.True
	Named(name, _, backing) => Types.nominal(name) != Linked and record_like(backing)
	_ => Bool.False
}

val_ty : Code.Row, Code.Val -> Try(Code.Ty, [NoType])
val_ty = |row, val| match val {
	Param(i) => row.params.get(i.to_u64()).map_err(|_| NoType)
	Node(i) => Ok(row.node(i).ty)
	Out(_) | Arg(_) | Input(_) => Err(NoType)
}

## The columns of a whole row at `place`, with `AS` only where the column
## is not the field: `record::id(id) AS id, name, in AS ⟨from⟩`.
row_list : Code.Ty, { at : Str, of : [Doc([Of(Str), Unnamed]), Ref(Code.Ty), Obj], edge : Bool } -> Try(Str, Error)
row_list = |row_ty, place| {
	columns = Translate.row_columns(row_ty, place)?
	Ok(Str.join_with(columns.map(|c| if (c.surql == Ql.ident(c.name)) c.surql else "${c.surql} AS ${Ql.ident(c.name)}"), ", "))
}

## The columns of a result row of `select`: a record the function builds
## names each column, and a whole record (the row, a linked row, an
## object) is one column per field of its type `ty`.
column_list : Translate.Binding, Code.Ty -> Try(Str, Error)
column_list = |result, ty| match result {
	Row(r) => row_list(ty, r)
	WithEdges(_, _) => Err(row_of_pair)
	other => Ok(aliased(Translate.typed_fields(other, ty)?))
}

## The same result row as one SurrealQL value: the `row` of a live query.
row_value : Translate.Binding, Code.Ty -> Try(Str, Error)
row_value = |result, ty| match result {
	Row(r) => Translate.text(Fields(Translate.row_columns(ty, r)?.map(|c| { name: c.name, binding: Translate.Binding.Expr(c.surql) })))
	WithEdges(_, _) => Err(row_of_pair)
	Fields(fields) => Translate.text(Fields(Translate.typed_fields(Fields(fields), ty)?.map(|c| { name: c.name, binding: Translate.Binding.Expr(c.surql) })))
	other => Translate.shaped(other, ty)
}

## The whole rows of `ty` of a query over a subquery: the result of a
## filter after a group, a limit or a start (`Selected.filter`). The
## row is the result row of the inner query: its columns, or `VALUE`
## for a result of `select_value`.
whole_rows : Query(p, row), Code.Ty -> Selected(p, row)
whole_rows = |Query.(q), ty| {
	columns = |_| match q.source.now? {
		Row(r) => row_list(ty, r)
		Fields(fields) => Ok(aliased(Translate.fields_of(Fields(fields))?))
		WithEdges(_, _) => Err(row_of_pair)
		value => Ok("VALUE ${Translate.text(value)?}")
	}
	value = |_| match q.source.now? {
		WithEdges(_, _) => Err(row_of_pair)
		result => row_value(result, ty)
	}
	# A row of values of the subquery is `$this`, which is not a field path.
	results = |key, param| match q.source.now? {
		Row(_) | Fields(_) | WithEdges(_, _) => by_name(key, param)
		_ => Err(value_order)
	}
	selected_of(q, { columns, value, intrinsic: [] }, results, [], { ty, over: Projected(q.source), nested: nested_row(ty) })
}

## The whole rows of a query, as `select(|r| r)` has them. `ty` is the
## type of the row: `Code.ty_of` describes it where the call fixes `row`.
whole_of : Query(p, row) -> Selected(p, row)
whole_of = |query| {
	proxy : Code.Proxy(row)
	proxy = Code.proxy()
	whole_rows(query, Code.ty_of(proxy))
}

aliased : List({ name : Str, surql : Str }) -> Str
aliased = |columns| Str.join_with(columns.map(|c| "${c.surql} AS ${Ql.ident(c.name)}"), ", ")

## The values a key or an ordering is made of: one, or a record's fields.
parts_of : Translate.Binding -> Try(List(Str), Error)
parts_of = |binding| match binding {
	Fields(fields) => fields.map_try(|f| Translate.text(f.binding))
	other => Translate.text(other).map_ok(|one| [one])
}

keyword : Str, List(Str), Str -> List(Str)
keyword = |word, parts, separator| if (parts.is_empty()) [] else ["${word} ${Str.join_with(parts, separator)}"]

set_list : List({ name : Str, surql : Str }) -> Str
set_list = |sets| Str.join_with(sets.map(|a| "${a.name} = ${a.surql}"), ", ")

statement_of : Str -> Statement
statement_of = |surql| Statement.({ surql, lets: [], inlined: surql, intrinsic: [] })

## The statement of a query, with the columns of its result that read an
## intrinsic.
with_intrinsic : Statement, Selected(p, out) -> Statement
with_intrinsic = |Statement.(st), Selected.(s)| Statement.({ ..st, intrinsic: s.intrinsic })

## The columns of the record a clause returns whose value reads an
## intrinsic of `Surreal`, by their Roc names: the translator's own
## binding of each intrinsic (`intrinsic_ids`) decides, through every
## function the column calls.
intrinsic_columns : Code.Graph -> List(Str)
intrinsic_columns = |graph| Translate.column_prims(graph).keep_if(|c| c.prims.any(|id| intrinsic_ids.contains(id))).map(|c| c.name)

## The fields a row or a parameter record encodes to.
object_of : a -> Try(List({ name : Str, value : Ql.Value }), Error) where [a.encoder_for : Encode.Format -> (a, Encode.State -> Try(Encode.State, []))]
object_of = |value| match Encode.value_of(value)? {
	Object(fields) => Ok(fields)
	_ => Err(Unsupported("a row or a parameter record is a record"))
}

## The ends of an edge are SurrealDB's `in` and `out`.
ends_named : List({ name : Str, value : Ql.Value }), TableKind -> List({ name : Str, value : Ql.Value })
ends_named = |fields, kind| fields.map(|f| { ..f, name: Translate.spell_name(f.name, is_edge(kind)) })

field_of : List({ name : Str, value : Ql.Value }), Str -> Try(Ql.Value, Error)
field_of = |fields, name| match fields.find_first(|f| f.name == name) {
	Ok(f) => Ok(f.value)
	Err(_) => Err(Unsupported("a row of a relation table has the field for `${name}`"))
}

## A row split into its key and the other fields, the key written once
## as the record id and not again in the content. The key is a text, or
## the array `[series, time]` of a `TimeKey`.
split_id : { name : Str, kind : TableKind }, a -> Try({ key : Ql.Value, fields : List({ name : Str, value : Ql.Value }) }, Error) where [a.encoder_for : Encode.Format -> (a, Encode.State -> Try(Encode.State, []))]
split_id = |t, row| {
	fields = ends_named(object_of(row)?, t.kind)
	match fields.find_first(|f| f.name == "id") {
		Ok({ value: Str(key), .. }) => Ok({ key: Ql.Value.Str(key), fields: fields.keep_if(|f| f.name != "id") })
		Ok({ value: Array(key), .. }) => Ok({ key: Ql.Value.Array(key), fields: fields.keep_if(|f| f.name != "id") })
		_ => Err(Unsupported("a row of `${t.name}` needs an `id : Str` or `id : Surreal.TimeKey(..)` field, the record key"))
	}
}

content_write : Str, { name : Str, kind : TableKind }, a -> Try(Statement, Error) where [a.encoder_for : Encode.Format -> (a, Encode.State -> Try(Encode.State, []))]
content_write = |verb, t, row| {
	writable(t)?
	split = split_id(t, row)?
	Ok(statement_of("${verb} ${Ql.record_ref(t.name, split.key)} CONTENT ${Ql.literal(Ql.Value.Object(split.fields))}"))
}

## The `MERGE` of a record into the record at `target`: `verb` is
## `UPDATE` or `UPSERT`. The fields of the record are those of its
## encoding, the ends of an edge as `in` and `out`.
merge_write : Str, { name : Str, kind : TableKind }, Str, a -> Try(Statement, Error) where [a.encoder_for : Encode.Format -> (a, Encode.State -> Try(Encode.State, []))]
merge_write = |verb, t, target, partial| {
	writable(t)?
	fields = ends_named(object_of(partial)?, t.kind)
	if fields.any(|f| f.name == "id") {
		return Err(Unsupported("a merge cannot change `id`, the record key"))
	}
	Ok(statement_of("${verb} ${target} MERGE ${Ql.literal(Ql.Value.Object(fields))}"))
}

## One op of a JSON Patch for `UPDATE .. PATCH`: `{ op: 'replace', path:
## '/n', value: 7 }`.
patch_item : Op -> Try(Str, Error)
patch_item = |op| {
	path = Diff.path_of(op)
	if path.first() == Ok("id") {
		return Err(Unsupported("a patch cannot change `id`, the record key (the op is at `${Diff.pointer_text(path)}`)"))
	}
	at = Ql.literal(Ql.Value.Str(Diff.pointer_text(path)))
	given = |word, value| match value_of(value) {
		Ok(v) => Ok("{ op: '${word}', path: ${at}, value: ${Ql.literal(v)} }")
		Err(NoValue(why)) => Err(Unsupported("a patch with ${why} as a value"))
	}
	match op {
		Add(_, value) => given("add", value)
		Replace([], Null) => Err(Unsupported("a patch of a delete: delete the row with `delete_at`"))
		Replace(_, value) => given("replace", value)
		Remove(_) => Ok("{ op: 'remove', path: ${at} }")
		Change(_, _) => Err(Unsupported("a `change` op is a text diff, and the ORM reads it and does not write it; replay the field with a `replace`"))
	}
}

## The `RELATE` of an edge between the rows of `from` and `to`
## (`Table.create`). Only a relation table has edges.
relate_row : { name : Str, kind : TableKind }, a -> Try(Statement, Error) where [a.encoder_for : Encode.Format -> (a, Encode.State -> Try(Encode.State, []))]
relate_row = |t, row| {
	writable(t)?
	split = split_id(t, row)?
	relate_fields(t, Ok(split.key), split.fields)
}

## The `RELATE` of an edge with these fields, `in` and `out` among them,
## at its key, or at a key that the server makes (`Table.create_new`).
relate_fields : { name : Str, kind : TableKind }, Try(Ql.Value, [Generated]), List({ name : Str, value : Ql.Value }) -> Try(Statement, Error)
relate_fields = |t, key, fields| {
	from = field_of(fields, "in")?
	to = field_of(fields, "out")?
	rest = fields.keep_if(|f| f.name != "in" and f.name != "out")
	edge = match key {
		Ok(k) => Ql.record_ref(t.name, k)
		Err(Generated) => Ql.ident(t.name)
	}
	Ok(statement_of("RELATE ${Ql.literal(from)}->${edge}->${Ql.literal(to)} CONTENT ${Ql.literal(Ql.Value.Object(rest))}"))
}

## The fields of a new row with no key (`Table.create_new`,
## `Table.insert_new`), the ends of an edge named `in` and `out`.
keyless : { name : Str, kind : TableKind }, a -> Try(List({ name : Str, value : Ql.Value }), Error) where [a.encoder_for : Encode.Format -> (a, Encode.State -> Try(Encode.State, []))]
keyless = |t, row| {
	writable(t)?
	Ok(ends_named(object_of(row)?, t.kind))
}


## A write of one row with a typed result: the row as stored, after
## the write or before it (`RETURN AFTER`, `RETURN BEFORE`).
stored_write : { name : Str, kind : TableKind }, Try(Statement, Error), [After, Before] -> Prepared(List(row)) where [row.Cbor.Readable(errs)]
stored_write = |t, built, gives| keyed_write(t, built, [], gives)

## `stored_write` of a statement over the slots of its clauses.
keyed_write : { name : Str, kind : TableKind }, Try(Statement, Error), List(Slot), [After, Before] -> Prepared(List(row)) where [row.Cbor.Readable(errs)]
keyed_write = |t, built, slots, gives| prepared_of(built.map_ok(|Statement.(s)| { statement: Statement.({ ..s, surql: "${s.surql}${return_clause(gives)}", inlined: "${s.inlined}${return_clause(gives)}" }), slots, count: 1, atomic: No, read: read_stored(0, is_edge(t.kind)) }))

## The spelling of a parameter for a clause of `code`: a captured value
## is a mark of its slot in the chain (`Translate.slotted`).
spelled : Code(f), (Str -> Str) -> (Str -> Str)
spelled = |code, param| Translate.slotted(code.first_slot(), param)

## The count of the results of the statements: with the `BEGIN`
## and the `COMMIT` of a transaction.
ready_size : Ready(out) -> U64
ready_size = |r| match r.atomic {
	No => r.count
	Whole | Parts(_) => r.count + 2
}

## What a terminal call built, with the values of the captured values
## that the chain's call gave: one per slot that has none yet. A statement
## that a combination made at run time has every value, and the call gives
## none.
ready_of : Prepared(out) -> Try(Ready(out), Error)
ready_of = |Prepared.(bound)| {
	ready = bound.value()?
	Ok({ ..ready, slots: given_binds(ready.slots, bound.inputs())? })
}

## The slots with the values that a chain's call gave: one per slot that
## has none yet, in order.
given_binds : List(Bind), List(Code.Value) -> Try(List(Bind), Error)
given_binds = |slots, given| {
	pending = slots.count_if(|b| is_pending(b.value))
	if given.len() != pending {
		return Err(Unsupported("the chain captured ${given.len().to_str()} value(s), and its statement has ${pending.to_str()} slot(s) for them"))
	}
	filled = slots.fold(
		{ next: 0, binds: [] },
		|acc, b| match b.value {
			Pending =>
				match given.get(acc.next) {
					Ok(v) => { next: acc.next + 1, binds: acc.binds.append({ ..b, value: Given(v) }) }
					Err(_) => { ..acc, binds: acc.binds.append(b) }
				}
			Given(_) => { ..acc, binds: acc.binds.append(b) }
		},
	)
	Ok(filled.binds)
}

is_pending : [Pending, Given(Code.Value)] -> Bool
is_pending = |value| match value {
	Pending => Bool.True
	Given(_) => Bool.False
}

## The slots of a statement from the slots its clauses read, in the order
## of the chain. Two clauses that read one slot give it once. A slot that
## no clause typed is an error: a builder did not keep its slots.
binds_of : List(Slot) -> Try(List(Bind), Error)
binds_of = |slots| {
	sorted = slots.sort_with(|a, b| a.at.order_relative_to(b.at))
	unique = sorted.fold([], |acc, s| if acc.any(|t| t.at == s.at) acc else acc.append(s))
	unique.map_with_index(|s, k| { s, k }).map_try(
		|p|
			if p.s.at == p.k {
				Ok({ ty: p.s.ty, table: p.s.table, value: Pending })
			} else {
				Err(Unsupported("the captured value ${(p.k + 1).to_str()} of the chain has no type: a clause did not keep it"))
			},
	)
}

## The slots of a clause's `Code`, numbered in its chain. A value that has
## no SurrealQL form is refused at the place the clause reads it: a
## captured value only exists in a chain that the compiler runs, so this
## is a compile error.
slots_of : Code(f) -> List(Slot)
slots_of = |code| keyed_slots(code, Any, Bool.False)

## `slots_of`, where each slot is a key of the table `table`, and where
## `encoded` says that the clause binds a value of an opaque type with its
## encoder (`Code.Binds`).
keyed_slots : Code(f), [Any, Of(Str)], Bool -> List(Slot)
keyed_slots = |code, table, encoded| {
	graph = code.graph()
	graph.slots().map_with_index(
		|ty, k| {
			match Translate.bindable(ty, encoded) {
				Ok({}) => {}
				Err(reason) =>
					match input_node(graph, k.to_u32_wrap()) {
						Ok(at) => code.refuse_at(at, reason)
						Err(_) => {}
					}
			}
			{ at: code.first_slot() + k, ty, table }
		},
	)
}

## The first node of the graph that reads the captured value `k`.
input_node : Code.Graph, U32 -> Try({ row : U32, node : U32 }, [NotFound])
input_node = |graph, k| {
	found = graph.rows().join_map(
		|row| row.nodes.map_with_index(|node, i| { row: row.id, node: i.to_u32_wrap(), reads: node.args.contains(Input(k)) }),
	)
	match found.find_first(|f| f.reads) {
		Ok(f) => Ok({ row: f.row, node: f.node })
		Err(_) => Err(NotFound)
	}
}

## The statement with the name and the `LET` of each captured value, in
## a transaction between `BEGIN` and `COMMIT`.
ready_statement : Ready(out) -> Try(Statement, Error)
ready_statement = |ready| {
	s = resolved(ready)?
	match ready.atomic {
		No => Ok(s)
		Whole | Parts(_) => Ok(in_transaction(s))
	}
}

## The statement with each `Translate.slot_mark` replaced: by `$_k` in
## the text, by the value in the text with the values written in, and a
## `LET $_k` for each. A key of another table is refused.
resolved : Ready(out) -> Try(Statement, Error)
resolved = |ready| {
	Statement.(s) = ready.statement
	values = ready.slots.map_try(
		|b| match b.value {
			Given(v) => {
				value = Translate.captured(b.ty, v)?
				match (b.table, value) {
					(Any, _) => Ok(value)
					(Of(name), Record(r)) =>
						if r.table == name {
							Ok(value)
						} else {
							Err(Unsupported("the id `${Ql.record_id(r.table, r.key)}` is of the table `${r.table}`, not of `${name}`"))
						}
					(Of(name), _) => Err(Unsupported("a key of `${name}` that is not an id"))
				}
			}
			Pending => Err(Unsupported("a captured value that the chain did not give"))
		},
	)?
	lets = values.map_with_index(|value, k| { name: Translate.input_name(k), value })
	surql = unmark(s.surql, |k| "$${Translate.input_name(k)}")?
	inlined = unmark(
		s.inlined,
		|k| match values.get(k) {
			Ok(v) => Ql.literal(v)
			Err(_) => "NONE"
		},
	)?
	Ok(Statement.({ ..s, surql, lets: s.lets.concat(lets), inlined }))
}

## The text with each `Translate.slot_mark` replaced by `spell(k)`.
unmark : Str, (U64 -> Str) -> Try(Str, Error)
unmark = |text, spell| {
	var $done = ""
	var $i = 0
	for part in text.split_on(Translate.mark_byte) {
		if $i % 2 == 0 {
			$done = Str.concat($done, part)
		} else {
			k = U64.from_str(part) ? |_| Unsupported("a slot mark without its number")
			$done = Str.concat($done.drop_suffix("$"), spell(k))
		}
		$i = $i + 1
	}
	Ok($done)
}

## The text with each mark numbered `offset` higher.
shifted : Str, U64 -> Try(Str, Error)
shifted = |text, offset| if offset == 0 Ok(text) else unmark(text, |k| Translate.slot_mark(k + offset))

## Two statements as one, the first first: the marks of the second are
## numbered after the slots of the first.
join_statements : { statement : Statement, slots : List(Bind) }, { statement : Statement, slots : List(Bind) } -> Try({ statement : Statement, slots : List(Bind) }, Error)
join_statements = |a, b| {
	Statement.(second) = b.statement
	offset = a.slots.len()
	moved = Statement.({ ..second, surql: shifted(second.surql, offset)?, inlined: shifted(second.inlined, offset)? })
	Ok({ statement: then_statement(a.statement, moved)?, slots: a.slots.concat(b.slots) })
}

## `Prepared.then` of what two terminal calls built.
then_ready : Try(Ready(a), Error), Try(Ready(b), Error) -> Try(Ready((Try(a, Error), Try(b, Error))), Error)
then_ready = |built_first, built_second| {
	first = built_first?
	second = built_second?
	in_text = |r| match r.atomic {
		No => r.statement
		Whole | Parts(_) => in_transaction(r.statement)
	}
	both = join_statements({ statement: in_text(first), slots: first.slots }, { statement: in_text(second), slots: second.slots })?
	split = ready_size(first)
	read = |outcomes| Ok((read_all(first, outcomes.take_first(split)), read_all(second, outcomes.drop_first(split))))
	Ok({ statement: both.statement, slots: both.slots, count: split + ready_size(second), atomic: No, read })
}

## A terminal call's result: the statement over the slots of its clauses.
prepared_of : Try({ statement : Statement, slots : List(Slot), count : U64, atomic : [No, Whole, Parts(List(U64))], read : List(Outcome) -> Try(out, Error) }, Error) -> Prepared(out)
prepared_of = |built| Prepared.(
	Code.Bound.of(
		match built {
			Ok(b) => binds_of(b.slots).map_ok(|binds| { statement: b.statement, slots: binds, count: b.count, atomic: b.atomic, read: b.read })
			Err(e) => Err(e)
		},
	),
)

## The results of the statements, `ready_size` of them, read as `out`. In
## a transaction that failed, the error is the first that is not
## `follows`: the statement that failed it.
read_all : Ready(out), List(Outcome) -> Try(out, Error)
read_all = |p, outcomes| {

	match p.atomic {
		No => return (p.read)(outcomes)
		Whole | Parts(_) => {}
	}
	causes = outcomes.map_with_index(
		|o, at| match o {
			Err(f) if !f.follows => Ok({ at, error: f.error })
			_ => Err(NotCause)
		},
	)
	match (p.atomic, causes.keep_oks(|c| c).first()) {
		(Parts(parts), Ok(c)) => Err(Aborted({ at: part_at(parts, c.at), error: c.error }))
		(_, Ok(c)) => Err(Server(c.error))
		_ if outcomes.all(Try.is_ok) => (p.read)(outcomes.drop_first(1).take_first(p.count))
		_ => Err(Wire("a transaction failed, and no statement of it has the error that failed it"))
	}
}

## This statement, then the other. A name bound in both must have one value.
then_statement : Statement, Statement -> Try(Statement, Error)
then_statement = |Statement.(a), Statement.(b)| {
	text = |l| Ql.literal(l.value)
	clash = b.lets.find_first(|l| a.lets.any(|m| m.name == l.name and text(m) != text(l)))
	match clash {
		Ok(l) => Err(Unsupported("`$${l.name}` is bound to two different values in one script"))
		Err(_) =>
			Ok(
				Statement.(
					{
						surql: "${a.surql};\n${b.surql}",
						lets: a.lets.concat(b.lets.keep_if(|l| !a.lets.any(|m| m.name == l.name))),
						inlined: "${a.inlined};\n${b.inlined}",
						# check.py compares the result of the last statement.
						intrinsic: b.intrinsic,
					},
				),
			)
	}
}

## The `INSERT` of `Table.insert`, without `BEGIN` and `COMMIT`. `back`
## is its `RETURN` clause.
insert_body : { name : Str, kind : TableKind }, List(row), Str -> Try(Statement, Error) where [row.encoder_for : Encode.Format -> (row, Encode.State -> Try(Encode.State, []))]
insert_body = |t, new_rows, back| {
	writable(t)?
	objects = new_rows.map_try(|row| object_of(row).map_ok(|fields| ends_named(fields, t.kind)))?
	head = match t.kind {
		Relation(_) => "INSERT RELATION INTO"
		Normal | View => "INSERT INTO"
	}
	literals = Str.join_with(objects.map(|fields| Ql.literal(Ql.Value.Object(fields))), ", ")
	Ok(statement_of("${head} ${Ql.ident(t.name)} [${literals}]${back}"))
}

## The statement between `BEGIN` and `COMMIT`, its `LET`s before them.
in_transaction : Statement -> Statement
in_transaction = |Statement.(s)| Statement.({ ..s, surql: "BEGIN;\n${s.surql};\nCOMMIT", inlined: "BEGIN;\n${s.inlined};\nCOMMIT" })

## The `RETURN` clause of a typed write.
return_clause : [After, Before] -> Str
return_clause = |gives| match gives {
	After => " RETURN AFTER"
	Before => " RETURN BEFORE"
}

## Fields a statement cannot take as a `LET`: SurrealDB sets them itself.
protected : List(Str)
protected = ["session", "auth", "token", "access"]

## A statement over the parameter record: its text with names, the `LET`
## of each field, and its text with the values written in.
bound_statement : ((Str -> Str) -> Try(Str, Error)), p -> Try(Statement, Error) where [p.encoder_for : Encode.Format -> (p, Encode.State -> Try(Encode.State, []))]
bound_statement = |render, params| {
	lets = lets_of(params)?
	surql = render(Translate.variable)?
	inlined = render(
		|name| match lets.find_first(|l| l.name == name) {
			Ok(l) => Ql.literal(l.value)
			Err(_) => Translate.variable(name)
		},
	)?
	Ok(Statement.({ surql, lets, inlined, intrinsic: [] }))
}

## The `LET` of each field of the parameter record, by name.
lets_of : p -> Try(List({ name : Str, value : Ql.Value }), Error) where [p.encoder_for : Encode.Format -> (p, Encode.State -> Try(Encode.State, []))]
lets_of = |params| {
	lets = object_of(params)?
	match lets.find_first(|l| protected.contains(l.name)) {
		Ok(l) => Err(Unsupported("`$${l.name}` is a protected variable in SurrealDB; name the parameter otherwise"))
		Err(_) => Ok(lets)
	}
}

## What a watch built, with the values of its captured values (`ready_of`).
watch_of : Watch(out) -> Try({ lets : List({ name : Str, value : Ql.Value }), slots : List(Bind), lives : List({ role : Role, surql : Str }), snapshot : Str }, Error)
watch_of = |Watch.(bound)| {
	w = bound.value()?
	Ok({ ..w, slots: given_binds(w.slots, bound.inputs())? })
}

## The `LET` lines of the parameters, before the statements of a live query.
let_lines : List({ name : Str, value : Ql.Value }) -> List(Str)
let_lines = |lets| lets.map(|l| "LET $${l.name} = ${Ql.literal(l.value)};")

## The table a live query reads, or why it has no live form: SurrealDB
## takes one `SELECT` over a whole table, with no group, order, limit
## or start (verified).
live_table : Selected(p, out) -> Try(Str, Error)
live_table = |Selected.(s)| {
	name = whole_table(s.target)?
	if !s.groups.is_empty() {
		Err(live_group)
	} else if !s.order.is_empty() or !(is_unlimited(s.limit)) or !(from_first(s.start)) {
		Err(Unsupported("SurrealDB refuses ORDER BY, LIMIT and START in a live query; order the rows of a `View`"))
	} else {
		Ok(name)
	}
}

## An error of the translator in the clause `clause`, which names it:
## a refusal carries no source line (see README, "Errors"), so the
## message says where it is.
within_clause : Str, Try(a, Error) -> Try(a, Error)
within_clause = |clause, translated| match translated {
	Err(Unsupported(why)) => Err(Unsupported("in ${clause}: ${why}"))
	other => other
}

## The table of a target that a live query can read.
whole_table : Target -> Try(Str, Error)
whole_table = |target| match target {
	Whole(name) => Ok(name)
	Range(_) => Err(Unsupported("a live query reads a whole table, not a range of keys; filter on `v.id.time()`"))
	Record(_) => Err(Unsupported("a live query reads a whole table, not the record of one key; filter on `v.id`"))
	Sub(_) => Err(Unsupported("a live query is one `SELECT`, and this query reads a subquery (`FROM (SELECT ..)`), which SurrealDB refuses in a `LIVE SELECT`; filter before `group_by`, `order_by`, `limit` and `start`, or watch a view (`Surreal.view`)"))
}

## The filters of a query as one condition: `(a) AND (b)` for several,
## `Always` for none.
all_of : List(Translate.Binding) -> Try([Always, When(Translate.Binding)], Error)
all_of = |filters| match filters {
	[] => Ok(Always)
	[one] => Ok(When(one))
	many => Ok(When(Translate.Binding.Infix(Str.join_with(many.map_try(|f| Translate.text(f).map_ok(|t| "(${t})"))?, " AND "))))
}

## The text of a condition, `true` for none.
condition_text : [Always, When(Translate.Binding)] -> Try(Str, Error)
condition_text = |condition| match condition {
	Always => Ok("true")
	When(b) => Translate.text(b)
}

## ` WHERE <p>`, or nothing.
where_text : [Always, When(Translate.Binding)] -> Try(Str, Error)
where_text = |condition| match condition {
	Always => Ok("")
	When(b) => Ok(" WHERE ${Translate.text(b)?}")
}

## The record id of a row, split as `split_id` splits it.
ref_of : { name : Str, kind : TableKind }, a -> Try(Ref, Error) where [a.encoder_for : Encode.Format -> (a, Encode.State -> Try(Encode.State, []))]
ref_of = |t, row| Ok(Ref.({ table: t.name, key: split_id(t, row)?.key }))

## The record a link points at.
link_ref : Link(row) -> Ref
link_ref = |Link.(l)| {
	Id.(i) = l.id
	Ref.({ table: i.table, key: Ql.Value.Str(i.key) })
}

## Whether two rows are stored the same: a write of one over the other
## changes no field, and SurrealDB sends no notice for it (verified).
same_row : a, a -> Try(Bool, Error) where [a.encoder_for : Encode.Format -> (a, Encode.State -> Try(Encode.State, []))]
same_row = |a, b| Ok(Ql.literal(Encode.value_of(a)?) == Ql.literal(Encode.value_of(b)?))

## One notice of the edge statement of a live query: the node of the
## edge after the write, or `Gone` when it was deleted.
edge_notice : [Create, Update, Delete], Ref, Try(n, [Gone]), (n -> Bool), (n -> out) -> List(Notice(out))
edge_notice = |action, ref, state, keep, show| match state {
	Ok(node) => [{ action, role: Edge, ref, row: Ok(show(node)), now: keep(node) }]
	Err(Gone) => [{ action, role: Edge, ref, row: Err(Gone), now: Bool.False }]
}

## The name of a role in a `-- live:` block.
role_name : Role -> Str
role_name = |role| match role {
	Node => "node"
	Edge => "edge"
	Read => "read"
}

## The name SurrealDB gives an action.
action_name : [Create, Update, Delete] -> Str
action_name = |action| match action {
	Create => "CREATE"
	Update => "UPDATE"
	Delete => "DELETE"
}

## A notice as `check.py` reads it from the server: the action, the
## role of the statement, the record, and the row and `now` of the
## payload. A node that is gone has neither.
notice_value : Notice(out) -> Try(Ql.Value, Error) where [out.encoder_for : Encode.Format -> (out, Encode.State -> Try(Encode.State, []))]
notice_value = |n| {
	Ref.(r) = n.ref
	role = role_name(n.role)
	action = { name: "action", value: Ql.Value.Str(action_name(n.action)) }
	at = [{ name: "ref", value: Ql.Value.Ref(r) }, { name: "role", value: Ql.Value.Str(role) }]
	match n.row {
		Ok(row) => Ok(Ql.Value.Object([action, { name: "now", value: Ql.Value.Bool(n.now) }].concat(at).append({ name: "row", value: Encode.value_of(row)? })))
		Err(Gone) => Ok(Ql.Value.Object([action].concat(at)))
	}
}

## An event as `check.py` reads it from the server.
event_value : Event(out) -> Try(Ql.Value, Error) where [out.encoder_for : Encode.Format -> (out, Encode.State -> Try(Encode.State, []))]
event_value = |event| {
	(action, ref, row) = match event {
		Created(f, r) => ("CREATE", f, r)
		Updated(f, r) => ("UPDATE", f, r)
		Deleted(f, r) => ("DELETE", f, r)
	}
	Ref.(at) = ref
	Ok(Ql.Value.Object([{ name: "action", value: Ql.Value.Str(action) }, { name: "ref", value: Ql.Value.Ref(at) }, { name: "row", value: Encode.value_of(row)? }]))
}

## One `-- live:` block for `check.py`: the header, the role of each
## `LIVE` statement in order, the directives, the request, then each
## write after a `-- write` line.
live_block : Str, List(Str), List(Str), List(Str), List(Statement) -> Str
live_block = |header, roles, directives, request, writes| {
	lines = [header, "-- roles: ${Str.join_with(roles, ", ")}"].concat(directives).concat(request)
	Str.join_with(writes.fold(lines, |acc, w| acc.append("-- write").append(w.to_script())), "\n")
}

## The options of each read of the server's CBOR: a tag 6 (NONE)
## before `null` is no value, a `Dec` reads the text of a tag 10
## (`'4E+1'` is 40), and a tag union reads the form that `Encode`
## writes: `'Cash'`, `{ kind: 'Card', last4: .. }`, `{ kind: 'Check',
## value: 7 }`, `{ kind: 'Wire', value: ['eu', 9] }`. The tags 180 to
## 188 of CBOR v2 (`u8` is `181(5)`) are skipped, so a sized number of
## SurrealDB reads into any Roc number type that holds it. The other
## lenient reads are the ones of roc-cbor 0.4 (`Cbor.sql_rows`): a `null`
## is no value too, as `undefined` is.
read_options : Cbor.Options
read_options = { ignore_tags: [6, 10, 180, 181, 182, 183, 184, 185, 186, 187, 188], allow: [DecFromText, BoolFromInt, FloatToInt, NullAsAbsent, UndefinedAsNull, BytesFromArray], unions: Internal({ tag: "kind", content: "value" }) }

## A value of the type `a` from CBOR bytes of the server.
read_cbor : List(U8) -> Try(a, Error) where [a.Cbor.Readable(errs)]
read_cbor = |bytes| match Cbor.parse_with(bytes, read_options) {
	Ok(value) => Ok(value)
	Err(InvalidCbor(pos)) => {
		path = path_of(bytes, pos)
		Err(Decode({ path, message: "the value at byte ${pos.to_str()}${if (path.is_empty()) "" else " (${path})"} does not fit its Roc type" }))
	}
	Err(MissingRequiredField(name)) => Err(Decode({ path: "", message: "a map has no field `${name}`" }))
	Err(_) => Err(Decode({ path: "", message: "the value does not fit its Roc type" }))
}

## A row of a notice or of a snapshot, read as `out`. The envelope
## around it has fixed types, and holds the row as a `Cbor.Value`: the
## compiler derives no `parser_for` of a record, a list or a tuple over
## a type variable (`{ row : out }`), so the row is read on its own.
row_of : Cbor.Value -> Try(out, Error) where [out.Cbor.Readable(errs)]
row_of = |value| read_cbor(Cbor.encode(value))

## The path to a byte position: `result.row.temp_c`, `result[2].id`,
## or empty when the position is at the top or in no value.
path_of : List(U8), U64 -> Str
path_of = |bytes, pos| match Cbor.path_at(bytes, pos) {
	Ok(steps) => {
		parts = steps.map(
			|step| match step {
				Index(i) => "[${i.to_str()}]"
				Key(name) => ".${name}"
			},
		)
		Str.join_with(parts, "").drop_prefix(".")
	}
	Err(NotFound) => ""
}

## A value of the server as a value of the ORM. A record id is `Ref`,
## a datetime (tag 12) `Datetime`, a decimal (tag 10) `Decimal`, and
## NONE (tag 6) and `null` are `None`. A value that the ORM does not
## write, such as a duration or bytes, is `NoValue`.
value_of : Cbor.Value -> Try(Ql.Value, [NoValue(Str)])
value_of = |value| match value {
	Int(n) =>
		match n.to_i128().to_i64_try() {
			Ok(i) => Ok(Ql.Value.Int(i))
			Err(_) => Err(NoValue("an integer outside I64"))
		}
	Float(f) => Ok(Ql.Value.Float(f))
	Text(text) => Ok(Ql.Value.Str(text))
	Bool(b) => Ok(Ql.Value.Bool(b))
	Null | Undefined | Tag(6, _) => Ok(Ql.Value.None)
	Tag(8, Array([Text(name), key])) => Ok(Ql.Value.Ref({ table: name, key: value_of(key)? }))
	Tag(10, Text(_)) =>
		match Cbor.parse_with(Cbor.encode(value), read_options) {
			Ok(d) => Ok(Ql.Value.Decimal(d))
			Err(_) => Err(NoValue("a decimal outside Dec"))
		}
	Tag(12, Array(parts)) => {
		numbers = parts.map_try(
			|part| match part {
				Int(n) => n.to_i128().to_i64_try().map_err(|_| NoValue("a datetime outside I64 seconds"))
				_ => Err(NoValue("a datetime that is not numbers"))
			},
		)?
		match datetime_of(numbers) {
			Ok(Datetime.(d)) => Ok(Ql.Value.Datetime(d.iso))
			Err(BadDatetime) => Err(NoValue("a datetime outside the years 0 to 9999"))
		}
	}
	Array(items) => Ok(Ql.Value.Array(items.map_try(value_of)?))
	Map(entries) =>
		Ok(
			Ql.Value.Object(
				entries.to_list().map_try(
					|(name, item)| match name {
						Text(text) => Ok({ name: text, value: value_of(item)? })
						_ => Err(NoValue("a map key that is not text"))
					},
				)?,
			),
		)
	Tag(number, _) => Err(NoValue("a value of the tag ${number.to_str()}"))
	Bytes(_) => Err(NoValue("bytes"))
	Simple(n) => Err(NoValue("the simple value ${Str.inspect(n)}"))
}

## The results of the statements of a `query` reply, which must be
## `count`. A refused request, or a statement that failed, is a
## `Server` error, read by its kind (`server_error`), against the
## unique indexes in `indexes`. In a transaction that failed, each
## statement that did not run has an error `NotExecuted`: the error is
## the first other one, the statement that failed it.
query_results : List(U8), U64, List(Schema.Known) -> Try(List(Cbor.Value), Error)
query_results = |bytes, count, indexes| {
	outcomes = reply_outcomes(bytes, indexes)?
	failed = outcomes.keep_oks(
		|o| match o {
			Err(f) => Ok(f)
			Ok(_) => Err(NotFailed)
		},
	)
	match failed.find_first(|f| !f.follows).on_err(|_| failed.first()) {
		Ok(f) => return Err(Server(f.error))
		Err(_) => {}
	}
	results = outcomes.map(|o| o ?? Cbor.Value.Null)
	if results.len() == count {
		Ok(results)
	} else {
		Err(Wire("a reply of ${results.len().to_str()} results to ${count.to_str()} statements"))
	}
}

## The result of each statement of a `query` reply, which must be
## `count`: its value or its error (see `Outcome`). A refused request
## is a `Server` error, and so is a reply to another request with a
## statement that failed, as `query_results` reads it.
query_outcomes : List(U8), U64, List(Schema.Known) -> Try(List(Outcome), Error)
query_outcomes = |bytes, count, indexes| {
	outcomes = reply_outcomes(bytes, indexes)?
	if outcomes.len() == count {
		Ok(outcomes)
	} else {
		query_results(bytes, count, indexes).map_ok(|_| outcomes)
	}
}

## The result of each statement of a `query` reply, of any count.
reply_outcomes : List(U8), List(Schema.Known) -> Try(List(Outcome), Error)
reply_outcomes = |bytes, indexes| {
	head : { error : Try(Surreal.Failure, [Missing]) }
	head = read_cbor(bytes)?
	match head.error {
		Ok(e) => return Err(Server(server_error(e, indexes)))
		Err(Missing) => {}
	}
	reply : { result : List({ status : Str, result : Try(Cbor.Value, [Missing]), kind : Try(Str, [Missing]), details : Try(Cbor.Value, [Missing]) }) }
	reply = read_cbor(bytes)?
	reply.result.map_try(
		|entry| match (entry.status, entry.kind, entry.result) {
			("OK", _, got) => Ok(Ok(got ?? Cbor.Value.Null))
			(_, Ok(kind), Ok(Text(message))) => {
				follows = match detail_kind(entry.details) {
					Ok("NotExecuted") | Ok("Cancelled") => Bool.True
					_ => Bool.False
				}
				Ok(Err({ error: server_error({ kind, message, details: entry.details }, indexes), follows }))
			}
			_ => Err(Wire("a statement has the status ${entry.status} and no error kind and message"))
		},
	)
}

## The typed error of a `Failure` (see `ServerError`). The message of
## an `Internal` error is read by `Schema.violation`, and so is a value
## that does not fit a field's `TYPE`: SurrealDB 4 sends it as kind
## `Validation` with details `InvalidRequest` (verified on 4.0.1).
server_error : Surreal.Failure, List(Schema.Known) -> ServerError
server_error = |e, indexes| match (e.kind, detail_kind(e.details)) {
	("AlreadyExists", what) => Exists({ what: what ?? "", name: detail_name(e.details), message: e.message })
	("NotFound", what) => NotFound({ what: what ?? "", name: detail_name(e.details), message: e.message })
	("NotAllowed", _) => Denied(e.message)
	("Validation", Ok("InvalidRequest")) if e.message.starts_with("Couldn't coerce value for field `") =>
		match Schema.violation(e.message, e.message, indexes) {
			Type(t) => Type(t)
			_ => Invalid(e.message)
		}
	("Validation", _) if e.message.starts_with("Parse error") => Parse(e.message)
	("Validation", _) => Invalid(e.message)
	("Query", Ok("TransactionConflict")) => Conflict(e.message)
	("Query", Ok("TimedOut")) => Timeout(e.message)
	("Thrown", _) =>
		match e.message.split_first("An error occurred: ") {
			Ok(t) if t.before == "" => Thrown({ text: t.after, message: e.message })
			_ => Thrown({ text: e.message, message: e.message })
		}
	("Internal", _) => Schema.violation(e.message, e.message, indexes)
	(kind, _) => Other({ kind, message: e.message })
}

## The `kind` of an error's `details`: `Record`, `TimedOut`, ..
detail_kind : Try(Cbor.Value, [Missing]) -> Try(Str, [Missing])
detail_kind = |details| match details {
	Ok(Map(entries)) => text_at(entries.to_list(), "kind")
	_ => Err(Missing)
}

## The record id or the name that an error's `details` hold, as
## `{ kind: 'Record', details: { id: 'vet:a' } }`, else empty.
detail_name : Try(Cbor.Value, [Missing]) -> Str
detail_name = |details| match details {
	Ok(Map(entries)) =>
		match entries.to_list().find_first(|(key, _)| key == Text("details")) {
			Ok((_, Map(inner))) => text_at(inner.to_list(), "id").on_err(|_| text_at(inner.to_list(), "name")) ?? ""
			_ => ""
		}
	_ => ""
}

text_at : List((Cbor.Value, Cbor.Value)), Str -> Try(Str, [Missing])
text_at = |entries, key| match entries.find_first(|(k, _)| k == Text(key)) {
	Ok((_, Text(text))) => Ok(text)
	_ => Err(Missing)
}

## The uuid of a `LIVE` statement, from its result.
uuid_of : Cbor.Value -> Try(Uuid, Error)
uuid_of = |value| match value {
	Tag(37, Bytes(bytes)) => Rpc.Uuid.from_bytes(bytes).map_err(|_| Wire("a uuid that is not 16 bytes"))
	_ => Err(Wire("the result of a `LIVE` statement is not a uuid"))
}

## The key of a message, for the `Inbox`: the id of a reply, or the
## uuid of the live query of a notice, and whether it is `KILLED`.
message_key : List(U8) -> Try([Reply(U64), Notice({ live : Uuid, killed : Bool })], Error)
message_key = |bytes| {
	head : { id : Try(U64, [Missing]) }
	head = read_cbor(bytes)?
	match head.id {
		Ok(id) => Ok(Reply(id))
		Err(Missing) => {
			notice : { result : { id : Uuid, action : Str } }
			notice = read_cbor(bytes)?
			Ok(Notice({ live: notice.result.id, killed: notice.result.action == "KILLED" }))
		}
	}
}

## The kind of a message: a reply has an `id`, and a notice has none.
## A notice of one of `lives` is `Mine`, with its action and the role of
## its statement.
message_of : Lives, List(U8) -> Try(Frame({ action : [Create, Update, Delete], role : Role }), Error)
message_of = |lives, bytes| {
	head : { id : Try(U64, [Missing]), error : Try(Surreal.Failure, [Missing]) }
	head = read_cbor(bytes)?
	match (head.id, head.error) {
		(Ok(id), Ok(e)) => Ok(ReplyError({ id, error: server_error(e, []) }))
		(Ok(id), Err(Missing)) => {
			reply : { result : Try(Cbor.Value, [Missing]) }
			reply = read_cbor(bytes)?
			Ok(Reply({ id, result: reply.result ?? Cbor.Value.Null }))
		}
		(Err(Missing), _) => {
			notice : { result : { id : Uuid, action : Str } }
			notice = read_cbor(bytes)?
			live = notice.result.id
			match (notice.result.action, lives.find_first(|l| l.id == live)) {
				("KILLED", _) => Ok(Killed(live))
				(_, Err(_)) => Ok(Other)
				("CREATE", Ok(l)) => Ok(Mine({ action: Create, role: l.role }))
				("UPDATE", Ok(l)) => Ok(Mine({ action: Update, role: l.role }))
				("DELETE", Ok(l)) => Ok(Mine({ action: Delete, role: l.role }))
				(other, Ok(_)) => Err(Wire("the unknown action `${other}`"))
			}
		}
	}
}



## The messages that the server pushes, which a watch needs, or the
## `Unsupported` error of a connection that gives none (HTTP).
push_of : Session -> Try({ next! : {} => Try({ connection : Connection, message : List(U8) }, Error) }, Error)
push_of = |Session.(s)| match s.connection.pushed {
	Supported(p) => Ok(p)
	Unsupported => Err(no_push)
}

no_push : Error
no_push = Unsupported("a watch reads the messages that the server pushes, and this session's connection gives none: a session over HTTP (`Transport.http`) has only requests and replies. Watch on a WebSocket session (`Transport.websocket`, or `Transport.websocket_timed` for a deadline)")

## The wait with a deadline of the connection (`Transport.websocket_timed`),
## or the `Unsupported` error of a connection that has none. Pure: it reads
## nothing, so `Session.next_within!` fails before it waits.
within_of : Session -> Try(U64 => Try({ connection : Connection, got : [Message(List(U8)), TimedOut] }, Error), Error)
within_of = |Session.(s)| match (s.connection.pushed, s.connection.within) {
	(Unsupported, _) => Err(no_push)
	(Supported(_), NoDeadline) => Err(no_deadline)
	(Supported(_), Within(wait!)) => Ok(wait!)
}

no_deadline : Error
no_deadline = Unsupported("a watch with a deadline waits with the `receive_within!` of the adapter, and this session's transport has none: a session built with `Transport.websocket` waits with no deadline. Build the transport with `Transport.websocket_timed` over an adapter with `receive_within!`, such as roc-basic-cli-websocket's")

## `kill` for each live query, one at a time, each reply read.
kill_each! : Session, Lives => Try(Session, Error)
kill_each! = |session, lives| match lives {
	[] => Ok(session)
	[live, .. as later] => {
		Session.(s) = session
		killed = ask!(session, Cbor.encode(Rpc.kill(s.next_id, live.id)))?
		kill_each!(killed, later)
	}
}

## The entries of the CBOR map of a record.
cbor_entries : a -> List((Cbor.Value, Cbor.Value)) where [a.Cbor.Writable]
cbor_entries = |record| {
	value : Try(Cbor.Value, _)
	value = Cbor.parse(Cbor.encode(record))
	match value {
		Ok(Map(entries)) => entries.to_list()
		_ => crash "the derived encoder writes a record as a CBOR map"
	}
}

## Sends a request whose id is the next id, reads its reply, and
## checks that it is not an error.
ask! : Session, List(U8) => Try(Session, Error)
ask! = |session, request| answer!(session, request).map_ok(|got| got.session)

## [ask!], with the result of the reply.
answer! : Session, List(U8) => Try({ session : Session, result : Cbor.Value }, Error)
answer! = |session, request| {
	Session.(s) = session
	sent = post_request!(session, request)?
	got = reply_for!(sent, s.next_id)?
	match message_of([], got.reply)? {
		ReplyError(e) => Err(Server(e.error))
		Reply(r) => Ok({ session: got.session, result: r.result })
		_ => Err(Wire("the reply to request ${s.next_id.to_str()} is not a reply"))
	}
}

## `signup` or `signin` of a record user, on a new connection: the reply
## is the token, which each later post over HTTP carries.
record_login! : Connection, Str, RecordLogin => Try(Session, Error)
record_login! = |connection, method, r| {
	scope = Scope({ ns: r.ns, db: r.db })
	opened = Session.({ connection, next_id: 1, inbox: Inbox.empty({}), known: [], auth: { who: Anonymous, scope } })
	got = answer!(opened, Cbor.encode(Rpc.access(1, method, { ns: r.ns, db: r.db, access: r.access }, r.vars))).map_err(login_error)?
	Session.(signed) = got.session
	match got.result {
		Text(token) => Ok(Session.({ ..signed, auth: { who: Bearer(token), scope } }))
		_ => Err(Wire("the reply to `${method}` is not a token"))
	}
}

## The error of a login that the server refused. SurrealDB 3.3.4 answers
## a `signin` whose `SIGNIN` query finds no record with `NotFound` (`No
## record was returned`), a `signup` whose `SIGNUP` query fails, such as
## on a unique email that is taken, with `Query` (`The record access
## signup query failed`), and a token that does not verify with
## `NotAllowed` (verified). Each is `Denied`: the server does not say
## why, by design. Any other error stays.
login_error : Error -> Error
login_error = |e| match e {
	Server(NotFound(n)) => Server(Denied(n.message))
	Server(Other({ kind: "Query", message })) => Server(Denied(message))
	other => other
}

## Sends a request, which has the next id. The session after it: a
## reply that came back with the request (HTTP) is in its inbox.
post_request! : Session, List(U8) => Try(Session, Error)
post_request! = |Session.(s), request| {
	sent = (s.connection.request!)(s.auth, request)?
	inbox = match sent.reply {
		Sent => s.inbox
		Replied(bytes) => s.inbox.accept(bytes)?
	}
	Ok(Session.({ ..s, connection: sent.connection, next_id: s.next_id + 1, inbox }))
}

## Sends the text of a watch, and reads its reply. The notices that
## come before the reply are held (`Inbox.start`).
start! : Session, Str => Try({ session : Session, reply : List(U8) }, Error)
start! = |session, text| {
	Session.(s) = session
	_ = push_of(session)?
	sent = post_request!(Session.({ ..s, inbox: s.inbox.start() }), Cbor.encode(Rpc.query(s.next_id, text)))?
	reply_for!(sent, s.next_id)
}

## The session, with the uuids of a watch that started (`Inbox.watch`).
watching : Session, Lives -> Session
watching = |Session.(s), lives| Session.({ ..s, inbox: s.inbox.watch(lives) })

## The reply to the request `id`: from the inbox, else read messages
## into the inbox until it comes. A connection that pushes nothing
## (HTTP) put each reply into the inbox when it sent the request, so
## one that is not there does not come: the session is an older copy,
## or the reply was taken.
reply_for! : Session, U64 => Try({ session : Session, reply : List(U8) }, Error)
reply_for! = |session, id| {
	Session.(s) = session
	match (s.inbox.take_reply(id), s.connection.pushed) {
		(Taken(t), _) => Ok({ session: Session.({ ..s, inbox: t.inbox }), reply: t.bytes })
		(Waiting, Supported(_)) => reply_for!(read_one!(session)?, id)
		(Waiting, Unsupported) => Err(Wire("the session holds no reply to request ${id.to_str()}, and its connection gives each reply with its request: use the session that the last call gave, and await a ticket once"))
	}
}

## One message of the session, applied to the members of a watch: the
## members after it and its changes (`Watch.step`), or `Ended` when it
## is the end of one of `lives`. Another message gives no change.
changes_of : Watch(out), Lives, Members, List(U8) -> Try([Changed({ members : Members, changes : List(Change(out)) }), Ended], Error) where [out.Cbor.Readable(errs)]
changes_of = |watch, lives, members, bytes| match watch.notice(lives, bytes)? {
	Mine(notices) => Ok(Changed(Mirror.step_all(members, notices)))
	Killed(id) => if (lives.any(|l| l.id == id)) Ok(Ended) else Ok(Changed({ members, changes: [] }))
	_ => Ok(Changed({ members, changes: [] }))
}

## One step of `Session.stream`: what the watch gives next, with the
## session and the watch after it.
stream_step! : { session : Session, live : live, open : Bool } => Try((Try({ item : item, session : Session, live : live }, Error), { session : Session, live : live, open : Bool }), [NoMore]) where [live.lives : live -> Lives, live.receive : live, List(U8) -> Try([Got({ item : item, live : live }), Skip(live), Ended], Error)]
stream_step! = |state| {
	if !state.open {
		return Err(NoMore)
	}
	match Session.next!(state.session, state.live) {
		Ok(got) =>
			match got.next {
				Got(item) => Ok((Ok({ item, session: got.session, live: got.live }), { ..state, session: got.session, live: got.live }))
				Ended => Err(NoMore)
				Unread(e) => Ok((Err(e), { ..state, session: got.session, live: got.live }))
			}
		Err(e) => Ok((Err(e), { ..state, open: Bool.False }))
	}
}

## The next notice of one of `lives`: from the inbox, else read frames
## into the inbox until one comes. `Ended` as `Inbox.take_notice`.
notice_for! : Session, Lives => Try({ session : Session, notice : [Notice(List(U8)), Ended] }, Error)
notice_for! = |session, lives| {
	Session.(s) = session
	match s.inbox.take_notice(lives) {
		Taken(t) => Ok({ session: Session.({ ..s, inbox: t.inbox }), notice: Notice(t.bytes) })
		Ended => Ok({ session, notice: Ended })
		Waiting => notice_for!(read_one!(session)?, lives)
	}
}

## The next notice of one of `lives`, as `notice_for!` gives it, with a
## deadline: the inbox first, so a notice it holds comes before any wait;
## else one message is read with a wait of `ms` (`TimedOut` when none
## comes), and the search starts again with the inbox.
notice_within! : Session, Lives, U64 => Try({ session : Session, notice : [Notice(List(U8)), Ended, TimedOut] }, Error)
notice_within! = |session, lives, ms| {
	Session.(s) = session
	match s.inbox.take_notice(lives) {
		Taken(t) => Ok({ session: Session.({ ..s, inbox: t.inbox }), notice: Notice(t.bytes) })
		Ended => Ok({ session, notice: Ended })
		Waiting => {
			read = read_within!(session, ms)?
			match read {
				Read(later) => notice_within!(later, lives, ms)
				TimedOut(later) => Ok({ session: later, notice: TimedOut })
			}
		}
	}
}

## One message of the session, read into its inbox, or `TimedOut` when none
## came in `ms` milliseconds. The session after it holds the connection that
## the adapter gave back either way.
read_within! : Session, U64 => Try([Read(Session), TimedOut(Session)], Error)
read_within! = |session, ms| {
	Session.(s) = session
	wait! = within_of(session)?
	got = wait!(ms)?
	match got.got {
		Message(message) => Ok(Read(Session.({ ..s, connection: got.connection, inbox: s.inbox.accept(message)? })))
		TimedOut => Ok(TimedOut(Session.({ ..s, connection: got.connection })))
	}
}

## One message of the session, read into its inbox.
read_one! : Session => Try(Session, Error)
read_one! = |session| {
	Session.(s) = session
	push = push_of(session)?
	got = (push.next!)({})?
	Ok(Session.({ ..s, connection: got.connection, inbox: s.inbox.accept(got.message)? }))
}






## Whether an op at `at` reaches the field at `field`: one is a prefix
## of the other.
op_reaches : Pointer, Pointer -> Bool
op_reaches = |at, field| if (at.len() <= field.len()) field.starts_with(at) else at.starts_with(field)

## The value at the keys of `path` in maps.
value_at : Cbor.Value, Pointer -> Try(Cbor.Value, [Absent])
value_at = |value, path| match (path, value) {
	([], Null) => Err(Absent)
	([], _) => Ok(value)
	([key, .. as deeper], Map(entries)) =>
		match entries.to_list().find_first(|(k, _)| k == Cbor.Value.Text(key)) {
			Ok((_, child)) => value_at(child, deeper)
			Err(_) => Err(Absent)
		}
	_ => Err(Absent)
}

## A stored row with its `id` as the key: `[table, key]` of tag 8 is `key`.
keyed : Cbor.Value -> Cbor.Value
keyed = |stored| match stored {
	Map(entries) =>
		Diff.vmap(
			entries.to_list().map(
				|(k, v)| match (k, v) {
					(Text("id"), Tag(8, Array([_, key]))) => (k, key)
					_ => (k, v)
				},
			),
		)
	other => other
}

## A stored row as a write returns it, keyed (`keyed`). The ends of an
## edge are SurrealDB's `in` and `out`, and the Roc row's `from` and `to`.
stored_row : Cbor.Value, Bool -> Cbor.Value
stored_row = |stored, edge| match (keyed(stored), edge) {
	(Map(entries), Bool.True) =>
		Diff.vmap(
			entries.to_list().map(
				|(k, v)| match k {
					Text("in") => (Cbor.Value.Text("from"), v)
					Text("out") => (Cbor.Value.Text("to"), v)
					_ => (k, v)
				},
			),
		)
	(other, _) => other
}

## The rows that a write of `Table.create_new` or `Table.insert_new`
## returned: the record id of each as an `Id` of the table, and its other
## fields read as `new`.
read_created : { name : Str, kind : TableKind } -> (List(Outcome) -> Try(List(Created(row, new)), Error)) where [new.Cbor.Readable(errs)]
read_created = |t| |results|
	rows_at(results, 0)?.map_try(
		|one| match stored_row(one, is_edge(t.kind)) {
			Map(entries) => {
				id = match one {
					Map(stored) => stored.to_list().find_first(|(k, _)| k == Cbor.Value.Text("id")).map_ok(|(_, v)| v)
					_ => Err(NotFound)
				}
				match id {
					Ok(Tag(8, Array([Text(table), Text(key)]))) if table == t.name => {
						fields = row_of(Diff.vmap(entries.to_list().keep_if(|(k, _)| k != Cbor.Value.Text("id"))))?
						Ok({ id: Id.({ table, key }), fields })
					}
					_ => Err(Wire("a row that a write of `${t.name}` made has no text key of `${t.name}`"))
				}
			}
			_ => Err(Wire("a row that a write of `${t.name}` made is not an object"))
		},
	)

## The result rows of the statement at `at`, each read as `out`.
result_rows : U64 -> (List(Outcome) -> Try(List(out), Error)) where [out.Cbor.Readable(errs)]
result_rows = |at| |results| rows_at(results, at)?.map_try(row_of)

## The stored rows that the write at `at` returned, each read as `row`.
read_stored : U64, Bool -> (List(Outcome) -> Try(List(row), Error)) where [row.Cbor.Readable(errs)]
read_stored = |at, edge| |results| rows_at(results, at)?.map_try(|one| row_of(stored_row(one, edge)))

## The rows of the result at `at`: an array, or the error of the
## statement. `Prepared.result` checked the count of the results, so
## `at` is in the list.
rows_at : List(Outcome), U64 -> Try(List(Cbor.Value), Error)
rows_at = |results, at| match results.get(at) {
	Ok(Ok(Array(items))) => Ok(items)
	Ok(Ok(_)) => Err(Wire("the result of statement ${(at + 1).to_str()} is not an array of rows"))
	Ok(Err(failure)) => Err(Server(failure.error))
	Err(_) => crash "Prepared.result checked the count of the results"
}

## The place of a statement of a transaction among its parts, each
## `parts` statements long: `at` counts the `BEGIN` as 0, and the
## `COMMIT` is the count of the parts.
part_at : List(U64), U64 -> U64
part_at = |parts, at| {
	var $before = 1
	var $part = 0
	for count in parts {
		if at < $before + count {
			return $part
		}
		$before = $before + count
		$part = $part + 1
	}
	$part
}


## A connection over HTTP: each request is one `POST /rpc`, whose
## response holds the reply. The server pushes nothing.
http_connection : HttpClient, Str -> Connection
http_connection = |client, url| Connection.({
	request!: |auth, message| {
		response = (client.post!)(HttpRpc.post(url, auth, message)).map_err(|e| Transport(e))?
		reply = HttpRpc.reply(response).map_err(|Refused(r)| Server(if (r.status == 401 or r.status == 403) Denied(r.message) else Other({ kind: "HTTP ${r.status.to_str()}", message: r.message })))?
		Ok({ connection: http_connection(client, url), reply: Replied(reply) })
	},
	pushed: Unsupported,
	within: NoDeadline,
})

## The WebSocket of `Transport.websocket` and `Transport.websocket_timed`:
## opens it on `/rpc` with the subprotocol `cbor.2`, which the server must
## choose, and makes the `Connection` of the opened value with `wrap`.
websocket! : Ws.Connect(c, e, a), Str, (c -> Connection) => Try(Connection, Error)
websocket! = |connect, url, wrap| {
	opened = (connect.connect!)({ url: "${url.drop_suffix("/")}/rpc", protocols: ["cbor.2"] }).map_err(ws_error)?
	if opened.protocol != "cbor.2" {
		return Err(Wire("the server did not choose the WebSocket subprotocol `cbor.2`"))
	}
	Ok(wrap(opened.conn))
}

## A connection over the WebSocket `conn` of an adapter: each request is
## one `Binary` message, and each message of the server, a reply or a
## notice, is one message that `pushed` reads. The adapter answers pings
## and the closing handshake. Each call gives the connection over the
## value of `conn` that the adapter gave back. It has no deadline.
websocket_connection : WsOps(c, e, r), c -> Connection
websocket_connection = |ops, conn| Connection.({
	request!: |_auth, message| websocket_send!(ops, |after| websocket_connection(ops, after), conn, message),
	pushed: Supported({ next!: |{}| websocket_next!(ops, |after| websocket_connection(ops, after), conn) }),
	within: NoDeadline,
})

## The connection of `websocket_connection` over an adapter with
## `receive_within!`, which `within` calls.
websocket_timed_connection : WsTimedOps(c, e, r), c -> Connection
websocket_timed_connection = |ops, conn| Connection.({
	request!: |_auth, message| websocket_send!(ops, |after| websocket_timed_connection(ops, after), conn, message),
	pushed: Supported({ next!: |{}| websocket_next!(ops, |after| websocket_timed_connection(ops, after), conn) }),
	within: Within(|ms| websocket_within!(ops, conn, ms)),
})

## The send and the receive of a WebSocket adapter that a session uses.
WsOps(c, e, r) : { send! : c, Ws.Message => Try(c, Ws.Error(e)), receive! : c => Try((c, Ws.Message), Ws.Error(e)), ..r }

## `WsOps` with the receive that has a deadline.
WsTimedOps(c, e, r) : WsOps(c, e, { receive_within! : c, U64 => Try((c, [Message(Ws.Message), TimedOut]), Ws.Error(e)), ..r })

## One request, in a `Binary` message. `wrap` makes the connection of the
## value that the adapter gave back.
websocket_send! : WsOps(c, e, r), (c -> Connection), c, List(U8) => Try({ connection : Connection, reply : [Sent, Replied(List(U8))] }, Error)
websocket_send! = |ops, wrap, conn, message| {
	sent = (ops.send!)(conn, Binary(message)).map_err(ws_error)?
	Ok({ connection: wrap(sent), reply: Sent })
}

## The next message of the server, a `Binary` one.
websocket_next! : WsOps(c, e, r), (c -> Connection), c => Try({ connection : Connection, message : List(U8) }, Error)
websocket_next! = |ops, wrap, conn| {
	(after, message) = (ops.receive!)(conn).map_err(ws_error)?
	Ok({ connection: wrap(after), message: binary_of(message)? })
}

## The next message of the server, or `TimedOut` when none comes in `ms`
## milliseconds, however many pings come meanwhile. The adapter gives the
## connection back either way.
websocket_within! : WsTimedOps(c, e, r), c, U64 => Try({ connection : Connection, got : [Message(List(U8)), TimedOut] }, Error)
websocket_within! = |ops, conn, ms| {
	(after, got) = (ops.receive_within!)(conn, ms).map_err(ws_error)?
	connection = websocket_timed_connection(ops, after)
	match got {
		Message(message) => Ok({ connection, got: Message(binary_of(message)?) })
		TimedOut => Ok({ connection, got: TimedOut })
	}
}

## The bytes of a message of a session with the subprotocol `cbor.2`: a
## `Binary` one.
binary_of : Ws.Message -> Try(List(U8), Error)
binary_of = |message| match message {
	Binary(bytes) => Ok(bytes)
	Text(_) => Err(Wire("a text message on a session with the subprotocol `cbor.2`"))
}

## An error of the WebSocket adapter. `Closed` and `Closing`, the tags
## of every adapter, stay; a tag of the adapter (`e`) is its text.
ws_error : Ws.Error(e) -> Error
ws_error = |err| match err {
	Closed(closure) => WebSocket(Closed(closure))
	Closing => WebSocket(Closing)
	other => WebSocket(Adapter(Str.inspect(other)))
}

# ------------------------------------------------------------------ tests

Person : { id : Str, name : Str }

people : Surreal.Table(Person)
people = Surreal.table("person")

ada : Person
ada = { id: "ada", name: "Ada" }

fetched_ada : Surreal.Link(Person)
fetched_ada = Surreal.fetched(people, ada)

# Ids and links are equal by table and key.
expect people.id("ada") == people.id("ada")
expect people.id("ada") != people.id("bob")
expect people.id("ada").key() == "ada"
expect people.link("ada") == fetched_ada
expect people.link("ada") != people.link("bob")
expect fetched_ada.get().name == "Ada"
expect fetched_ada.id() == people.id("ada")

# What a row holding a link or an id is written as.
Holder : { id : Str, who : Surreal.Link(Person), by : Surreal.Id(Person), at : Surreal.Datetime }

holder : Holder
holder = match Surreal.datetime("2026-10-28T04:53:59Z") {
	Ok(at) => { id: "h", who: fetched_ada, by: people.id("o'neil"), at: at }
	Err(_) => crash "a valid datetime"
}

expect Encode.value_of(holder).map_ok(Ql.literal) == Ok("{ at: d'2026-10-28T04:53:59Z', by: person:⟨o'neil⟩, id: 'h', who: person:⟨ada⟩ }")

# A union payload is spread next to `kind` only when its type is a record,
# also a nominal of the app over one. A geometry writes an object, and is
# `value`, as the schema types it and the reader reads it.
Shelf := { aisle : Str, bin : I64 }.{
	is_eq : _
	encoder_for : _
}

Placed : { id : Str, place : [Away, At(Point), Kept(Link(Person)), Since(Datetime), Shelved(Shelf), Box({ w : I64 })] }

placed : [Away, At(Point), Kept(Link(Person)), Since(Datetime), Shelved(Shelf), Box({ w : I64 })] -> Try(Str, Ql.Error)
placed = |place| {
	row : Placed
	row = { id: "p", place }
	Encode.value_of(row).map_ok(Ql.literal)
}

expect placed(Away) == Ok("{ id: 'p', place: 'Away' }")
expect placed(At(Surreal.point(10.75, 59.91))) == Ok("{ id: 'p', place: { kind: 'At', value: { type: 'Point', coordinates: [10.75f, 59.91f] } } }")
expect placed(Kept(people.link("ada"))) == Ok("{ id: 'p', place: { kind: 'Kept', value: person:⟨ada⟩ } }")
expect placed(Since(holder.at)) == Ok("{ id: 'p', place: { kind: 'Since', value: d'2026-10-28T04:53:59Z' } }")
expect placed(Shelved(Shelf.({ aisle: "b", bin: 4 }))) == Ok("{ id: 'p', place: { kind: 'Shelved', aisle: 'b', bin: 4 } }")
expect placed(Box({ w: 2 })) == Ok("{ id: 'p', place: { kind: 'Box', w: 2 } }")

expect Surreal.Mirror.literal([{ id: "a", n: 2.U8 }, { id: "b", n: 3 }]) == Ok("[{ id: 'a', n: 2 }, { id: 'b', n: 3 }]")

# Datetimes: one shape in, one text out.
iso_of : Str -> Str
iso_of = |text| match Surreal.datetime(text) {
	Ok(d) => Str.inspect(d)
	Err(BadDatetime) => "bad"
}

expect iso_of("2026-10-28T04:53:59Z") == "{ iso: \"2026-10-28T04:53:59Z\" }"
expect iso_of("2026-10-28T04:53:59.500Z") == "{ iso: \"2026-10-28T04:53:59.5Z\" }"
expect iso_of("2026-10-28T04:53:59.000Z") == "{ iso: \"2026-10-28T04:53:59Z\" }"
expect iso_of("2026-10-28T04:53:59.123456789Z") == "{ iso: \"2026-10-28T04:53:59.123456789Z\" }"
expect iso_of("2024-02-29T00:00:00Z") == "{ iso: \"2024-02-29T00:00:00Z\" }"
expect iso_of("2026-02-29T00:00:00Z") == "bad"
expect iso_of("1900-02-29T00:00:00Z") == "bad"
expect iso_of("2000-02-29T00:00:00Z") == "{ iso: \"2000-02-29T00:00:00Z\" }"
expect iso_of("2026-13-01T00:00:00Z") == "bad"
expect iso_of("2026-04-31T00:00:00Z") == "bad"
expect iso_of("2026-10-28T24:00:00Z") == "bad"
expect iso_of("2026-10-28T04:60:00Z") == "bad"
expect iso_of("2026-10-28T04:53:60Z") == "bad"
expect iso_of("2026-10-28T04:53:59") == "bad"
expect iso_of("2026-10-28T04:53:59+01:00") == "bad"
expect iso_of("2026-10-28 04:53:59Z") == "bad"
expect iso_of("2026-10-28T04:53:59.Z") == "bad"
expect iso_of("2026-10-28T04:53:59.1234567890Z") == "bad"
expect iso_of("2026-1a-28T04:53:59Z") == "bad"
expect iso_of("") == "bad"

# Order is time order, with or without a fraction.
at : Str -> Surreal.Datetime
at = |text| match Surreal.datetime(text) {
	Ok(d) => d
	Err(_) => crash "a valid datetime"
}

expect at("2026-10-28T04:53:59Z") < at("2026-10-28T04:54:00Z")
expect at("2026-10-28T04:53:59Z") < at("2026-10-28T04:53:59.5Z")
expect at("2026-10-28T04:53:59.25Z") < at("2026-10-28T04:53:59.5Z")
expect at("2026-10-28T04:53:59.05Z") < at("2026-10-28T04:53:59.5Z")
expect !(at("2026-10-28T04:53:59.5Z") < at("2026-10-28T04:53:59Z"))
expect !(at("2026-10-28T04:53:59Z") < at("2026-10-28T04:53:59Z"))
expect at("2026-10-28T04:53:59Z") <= at("2026-10-28T04:53:59.000Z")
expect at("2026-10-28T04:53:59.5Z") > at("2026-10-28T04:53:59Z")
expect at("2026-10-28T04:53:59Z") >= at("2026-10-28T04:53:59Z")
expect at("2026-10-28T04:53:59.500Z") == at("2026-10-28T04:53:59.5Z")

# Tables: a plain one, and an edge table that remembers both ends. The row
# type comes from the definition.
Knows : { id : Str, from : Surreal.Link(Person), to : Surreal.Link(Person), since : I64 }

knows : Surreal.Table(Knows)
knows = Surreal.relation("knows", people, people)

expect Surreal.Def.source(people.define()).name == "person"
expect Surreal.Def.source(people.define()).kind == Types.Kind.Normal
expect Surreal.Def.source(knows.define()).name == "knows"
expect Surreal.Def.source(knows.define()).kind == Types.Kind.Relation({ from: "person", to: "person" })
expect Surreal.Def.source(people.define()).row_ty == Record([{ name: "id", ty: Str, presence: Required }, { name: "name", ty: Str, presence: Required }])

# A record id of the server as a value of the ORM.
expect value_of(Cbor.Value.Tag(8, Cbor.Value.Array([Cbor.Value.Text("t"), Cbor.Value.Int(5)]))).map_ok(Ql.literal) == Ok("t:5")

# The part of a statement: the `BEGIN` is 0, and the `COMMIT` the count of the parts.
expect [0, 1, 2, 3, 4, 5].map(|k| part_at([1, 3], k)) == [0, 0, 1, 1, 1, 2]

# An error of a WebSocket adapter keeps its cause: the closure, or the text
# of the adapter's own tag.
expect {
	closed : Ws.Error([Tcp(Str)])
	closed = Closed({ code: 1006, reason: "", clean: Bool.False, by: Transport })
	ws_error(closed) == WebSocket(Closed({ code: 1006, reason: "", clean: Bool.False, by: Transport }))
}
expect {
	closing : Ws.Error([Tcp(Str)])
	closing = Closing
	ws_error(closing) == WebSocket(Closing)
}
expect {
	refused : Ws.Error([Refused(Str), Tcp(Str)])
	refused = Refused("HTTP/1.1 403 Forbidden")
	ws_error(refused) == WebSocket(Adapter("Refused(\"HTTP/1.1 403 Forbidden\")"))
}

# The message of a session with the subprotocol `cbor.2` is a `Binary` one.
expect binary_of(Binary([1, 2])) == Ok([1, 2])
expect binary_of(Text("a")) == Err(Wire("a text message on a session with the subprotocol `cbor.2`"))

# `Session.next_within!` needs a connection with a deadline, and is an
# `Unsupported` error before it reads on any other: on a connection that
# pushes nothing (HTTP) with the error of a watch, on one that pushes
# with `NoDeadline` with the error that names `Transport.websocket_timed`.
scripted : Pushed, Deadline -> Session
scripted = |pushed, within| Session.({
	connection: Connection.({ request!: |_auth, _message| Err(Wire("scripted")), pushed, within }),
	next_id: 1,
	inbox: Inbox.empty({}),
	known: [],
	auth: { who: Anonymous, scope: FromToken },
})

pushing : Pushed
pushing = Supported({ next!: |{}| Err(Wire("scripted")) })

expect match within_of(scripted(Unsupported, NoDeadline)) {
	Err(e) => e == no_push
	Ok(_) => Bool.False
}
expect match within_of(scripted(pushing, NoDeadline)) {
	Err(e) => e == no_deadline
	Ok(_) => Bool.False
}
expect match no_deadline {
	Unsupported(why) => why.contains("Transport.websocket_timed")
	_ => Bool.False
}
expect match within_of(scripted(pushing, Within(|_ms| Err(Wire("scripted"))))) {
	Ok(_) => Bool.True
	Err(_) => Bool.False
}

# ========================================================= migrations

## A request of migration statements: the session after it, and the
## result of each statement. Only a failed read is an error here.
migration_request! : Session, Str => Try({ session : Session, outcomes : List(Outcome) }, Error)
migration_request! = |session, text| {
	got = Unchecked.query!(session, text)?
	Ok({ session: got.session, outcomes: reply_outcomes(got.reply, [])? })
}

## The error that failed a request: the first that does not follow
## another one.
first_failure : List(Outcome) -> Try(ServerError, [NoFailure])
first_failure = |outcomes| {
	errors = outcomes.keep_oks(
		|o| match o {
			Err(f) => Ok(f)
			Ok(_) => Err(Fine)
		},
	)
	match errors.find_first(|f| !f.follows) {
		Ok(f) => Ok(f.error)
		Err(_) => errors.first().map_ok(|f| f.error).map_err(|_| NoFailure)
	}
}

## The result at `at`, read as `out`.
outcome_at : List(Outcome), U64 -> Try(out, Error) where [out.Cbor.Readable(errs)]
outcome_at = |outcomes, place| match outcomes.get(place) {
	Ok(Ok(value)) => row_of(value)
	Ok(Err(f)) => Err(Server(f.error))
	Err(_) => Err(Wire("the reply to the migration history has ${outcomes.len().to_str()} results"))
}

## The history table, the compatibility level and the history
## (`Migrate.bootstrap`). Two runners that make the table at once can
## conflict: it tries again.
migration_state! : Session => Try({ session : Session, history : List(Migrate.Row), level : U64 }, Error)
migration_state! = |session| {
	var $session = session
	var $tries = 0
	while $tries < 3 {
		got = migration_request!($session, Migrate.bootstrap)?
		$session = got.session
		match first_failure(got.outcomes) {
			Ok(Conflict(_)) => {}
			Ok(error) => return Err(Server(error))
			Err(_) => {
				count = got.outcomes.len()
				level : Str
				level = outcome_at(got.outcomes, count - 2)?
				history : List(Migrate.Row)
				history = outcome_at(got.outcomes, count - 1)?
				return Ok({ session: $session, history, level: Migrate.level_of(level)? })
			}
		}
		$tries = $tries + 1
	}
	Err(Wire("the migration history conflicted three times"))
}

## Runs the sections of a file from `from`. A section that fails because
## another runner applied it (the history shows it) is not an error.
## `mine` is true when this runner applied a section.
run_sections! : Session, Migrate.File, U64 => Try({ session : Session, mine : Bool }, Error)
run_sections! = |session, file, from| {
	var $session = session
	var $mine = Bool.False
	var $k = from
	while $k <= file.sections.len() {
		got = migration_request!($session, Migrate.request(file, $k))?
		$session = got.session
		match first_failure(got.outcomes) {
			Ok(error) => {
				state = migration_state!($session)?
				$session = state.session
				match state.history.find_first(|h| h.name == file.name) {
					Ok(h) if h.checksum == file.checksum and h.done >= $k => {}
					_ => return Err(Server(error))
				}
			}
			Err(_) => {
				$mine = Bool.True
			}
		}
		$k = $k + 1
	}
	Ok({ session: $session, mine: $mine })
}

## Records a squashed file without running it.
adopt_file! : Session, Migrate.File => Try({ session : Session, mine : Bool }, Error)
adopt_file! = |session, file| {
	got = migration_request!(session, Migrate.adopt(file))?
	match first_failure(got.outcomes) {
		Ok(error) => {
			state = migration_state!(got.session)?
			if state.history.any(|h| h.name == file.name) Ok({ session: state.session, mine: Bool.False }) else Err(Server(error))
		}
		Err(_) => Ok({ session: got.session, mine: Bool.True })
	}
}
