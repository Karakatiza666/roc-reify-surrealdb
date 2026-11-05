import Ql

# Roc types as SurrealDB types. Reads the `Code.Ty` that the identity lambda
# of a table definition reified and gives:
#   - the SurrealDB `TYPE` of each field, with the generated constraints
#   - every place a `Link` or `Id` sits, for the delete policy
#   - the checks that make a row type a valid schema (`BadSchema`)
#   - the check that a read row agrees with its stored row
Types :: {}.{

	## A normal table, an edge table with the names of the tables its ends
	## point at, or a view: a table that SurrealDB keeps from a grouped query,
	## with the text of that query.
	Kind := [Normal, Relation({ from : Str, to : Str }), View(Try(Str, Ql.Error))].{
		is_eq : _
	}

	## A table the schema lists. A link finds its target table here.
	Source : { name : Str, row_ty : Code.Ty, kind : Types.Kind }

	Registry : List(Types.Source)

	## One field of a record type, as `Code.Ty` describes it. A field with a
	## `??` default is `Default(value)` when the default is a literal, and
	## `DefaultComputed` when it is not.
	Field : { name : Str, ty : Code.Ty, presence : [Required, Optional, Default(Code.Value), DefaultComputed] }

	## One `DEFINE FIELD`. `path` is spelled for SurrealQL (`items[*].product`)
	## and `top` is its first part. `asserts` are conditions over `$value`,
	## each safe to join with `AND`. `defaults` holds the `??` default of the
	## field's type, if any, with the type it has: `Schema` writes it as the
	## `DEFAULT` of the field.
	FieldDef : { path : Str, top : Str, ty : Str, asserts : List(Str), defaults : List({ ty : Code.Ty, value : Code.Value }) }

	## Where a link sits. `elements` is True when the site is a `List` of links.
	Shape : [Root, RootOptional, RootList, InObject, InList, InUnionArm({ tag : Str })]

	## A `Link` or an `Id` at any depth. `target` is the row type it points
	## at; `table_for` turns it into a table. `required` is True when no
	## optional field, list or union arm is on the way to it.
	## `linked` is True for a `Linked` of a read row, and `lists` counts
	## the lists on the way, the list of a `List(Link(r))` too.
	LinkSite : { path : Str, top : Str, target : Code.Ty, is_id : Bool, linked : Bool, required : Bool, shape : Types.Shape, elements : Bool, lists : U64 }

	# ------------------------------------------------------------ nominal names

	## Every nominal type the translator and the schema treat apart, by the
	## name a `Code.Ty.Named` gives it. This is the one place that compares
	## those names: `Named` carries no type id (a limit of the reifier today),
	## so a nominal is known by its name only, and another package's nominal
	## of the same name would be taken for it. A call is known by its id
	## (`Translate.Form`), and an opaque type by its `Code.TypeId`.
	## `Geometry` holds the SurrealDB type of a geometry type of `Surreal`.
	Nominal : [Link, Id, Datetime, Duration, DbFn, TimeKey, Geometry(Str), Linked, Out, In, Try, Bool, Other]

	nominal : Str -> Nominal
	nominal = |name| match name {
		"Surreal.Link" => Link
		"Surreal.Id" => Id
		"Surreal.Datetime" => Datetime
		"Surreal.Duration" => Duration
		"Surreal.DbFn" => DbFn
		"Surreal.TimeKey" => TimeKey
		"Surreal.Linked" => Linked
		"Surreal.Out" => Out
		"Surreal.In" => In
		"Surreal.Point" => Geometry("geometry<point>")
		"Surreal.Line" => Geometry("geometry<line>")
		"Surreal.Polygon" => Geometry("geometry<polygon>")
		"Surreal.MultiPoint" => Geometry("geometry<multipoint>")
		"Surreal.MultiLine" => Geometry("geometry<multiline>")
		"Surreal.MultiPolygon" => Geometry("geometry<multipolygon>")
		"Surreal.Collection" => Geometry("geometry<collection>")
		"Surreal.Geometry" => Geometry("geometry")
		"Builtin.Try" => Try
		"Builtin.Bool" => Bool
		_ => Other
	}

	## Whether a nominal is a point: SurrealDB reads its `lon` and `lat`.
	is_point : Str -> Bool
	is_point = |name| Types.nominal(name) == Geometry("geometry<point>")

	## A user nominal is read through to its backing. `Surreal.*` and
	## `Builtin.*` types are not.
	user_named : Str -> Bool
	user_named = |name| !name.starts_with("Surreal.") and !name.starts_with("Builtin.")

	## The names that a `Recursive` in a described type refers back with,
	## and that `row_of` and `unfold` take.
	link_name : Str
	link_name = "Surreal.Link"

	id_name : Str
	id_name = "Surreal.Id"

	## The SurrealDB type of a geometry type of `Surreal`.
	geometry_type : Str -> Try(Str, [NotGeometry])
	geometry_type = |name| match Types.nominal(name) {
		Geometry(surql) => Ok(surql)
		_ => Err(NotGeometry)
	}

	# ------------------------------------------------------------ read rows

	## A read row of `table` against its stored row in the registry. They
	## agree when they have the same fields with the same presence, a
	## `Linked(r)` stands where the stored row has a `Link` to the row that
	## `r` agrees with, and every other type is equal. A field
	## `name : Out(e)` or `name : In(e)` is not stored: `name` is an edge
	## table that starts (`Out`) or ends (`In`) at `table`, and `e` agrees
	## with its row.
	##
	## A read row may hold a `Linked` of itself (`OwnerRead := { ..,
	## referred_by ?: Linked(OwnerRead) }`). The description gives the
	## inner one as `Recursive("Surreal.Linked")`, so the comparison is
	## coinductive: `seen` holds the pairs of a `Linked` and a stored type
	## that are on the way here, and a pair that is on the way agrees.
	check_read : Str, Code.Ty, Types.Registry -> Try({}, Ql.Error)
	check_read = |table, view, registry| {
		stored = match registry.find_first(|src| src.name == table) {
			Ok(found) => found
			Err(_) => return Err(BadSchema("the read row of `${table}` has no stored table of that name; list the table in the schema"))
		}
		view_fields = Types.record_fields(view)?
		edge_fields = view_fields.keep_if(|f| Types.edge_list(f.ty).is_ok())
		_ = edge_fields.map_try(|f| Types.check_edge_field(table, f, registry))?
		plain = view_fields.keep_if(|f| Types.edge_list(f.ty).is_err())
		Types.agree_fields(table, plain, Types.record_fields(stored.row_ty)?, "", registry, [])
	}

	## The edge row and the end of the row of an `Out(e)` or an `In(e)`.
	edge_list : Code.Ty -> Try({ edge : Code.Ty, end : [From, To] }, [NotEdges])
	edge_list = |ty| match ty {
		Named(name, _, ListOf(edge)) if Types.nominal(name) == Out => Ok({ edge, end: From })
		Named(name, _, ListOf(edge)) if Types.nominal(name) == In => Ok({ edge, end: To })
		_ => Err(NotEdges)
	}

	check_edge_field : Str, Types.Field, Types.Registry -> Try({}, Ql.Error)
	check_edge_field = |table, f, registry| {
		list = match Types.edge_list(f.ty) {
			Ok(found) => found
			Err(_) => return Ok({})
		}
		wrong = |why| Err(BadSchema("the read row of `${table}`: the field `${f.name}` ${why}"))
		if f.presence == Optional {
			return wrong("is optional; an edge list is required, and empty when there are no edges")
		}
		edge_table = match registry.find_first(|src| src.name == f.name) {
			Ok(found) => found
			Err(_) => return wrong("names no table; an edge list has the name of its edge table")
		}
		(word, end) = match (edge_table.kind, list.end) {
			(Relation(ends), From) => ("start", ends.from)
			(Relation(ends), To) => ("end", ends.to)
			_ => return wrong("names `${f.name}`, which is not an edge table")
		}
		if end != table {
			return wrong("names edges that ${word} at `${end}`, not at `${table}`")
		}
		Types.agree_fields(table, Types.record_fields(list.edge)?, Types.record_fields(edge_table.row_ty)?, Ql.ident(f.name), registry, [])
	}

	agree_fields : Str, List(Types.Field), List(Types.Field), Str, Types.Registry, List(Str) -> Try({}, Ql.Error)
	agree_fields = |table, view, stored, path, registry, seen| {
		names = |fs| fs.map(|f| if (f.presence == Optional) "${f.name}?" else f.name)
		if names(view) != names(stored) {
			return Err(BadSchema("the read row of `${table}` has the fields ${Str.join_with(names(view), ", ")}${if (path.is_empty()) "" else " at `${path}`"}, and its stored row ${Str.join_with(names(stored), ", ")}"))
		}
		_ = List.map2(view, stored, |v, st| (v, st)).map_try(|(v, st)| Types.agree(table, v.ty, st.ty, if (path.is_empty()) Ql.ident(v.name) else Types.dot(path, v.name), registry, seen))?
		Ok({})
	}

	## One type of a read row against the stored type at the same path.
	## A `Linked` opens its row with each `Recursive("Surreal.Linked")`
	## that refers to it in its place (`Types.unfold`). So the walk meets
	## the same `Linked` again one hop down, and stops there: its pair
	## with the stored type is in `seen`.
	agree : Str, Code.Ty, Code.Ty, Str, Types.Registry, List(Str) -> Try({}, Ql.Error)
	agree = |table, view, stored, path, registry, seen| {
		bad = |why| Err(BadSchema("the read row of `${table}` does not agree with its stored row at `${path}`: ${why}"))
		if Types.key(view) == Types.key(stored) {
			return Ok({})
		}
		match (Types.open(view), Types.open(stored)) {
			(Named(name, args, backing), _) if Types.nominal(name) == Linked =>
				match Types.site_of(stored) {
					Ok({ target, is_id: Bool.False }) => {
						linked = Named(name, args, backing)
						pair = "${Types.key(linked)}=${Types.key(target)}"
						if seen.contains(pair) {
							Ok({})
						} else {
							Types.agree(table, Types.unfold(backing, name, linked), target, path, registry, seen.append(pair))
						}
					}
					_ => bad("a `Linked` stands where the stored row has no `Link`")
				}
			(Named(name, _, _), _) if Types.nominal(name) == Out or Types.nominal(name) == In => bad("an edge list is a field of the row itself")
			(ListOf(v), ListOf(st)) => Types.agree(table, v, st, "${path}[*]", registry, seen)
			(Record(vs), Record(sts)) => Types.agree_fields(table, vs, sts, path, registry, seen)
			(TagUnion(vs), TagUnion(sts)) if vs.map(|v| v.name) == sts.map(|st| st.name) => {
				_ = List.map2(vs, sts, |v, st| (v, st)).map_try(
					|(v, st)|
						if v.payloads.len() == st.payloads.len() {
							List.map2(v.payloads, st.payloads, |a, b| (a, b)).map_try(|(a, b)| Types.agree(table, a, b, path, registry, seen)).map_ok(|_| {})
						} else {
							bad("the arm `${v.name}` has other payloads")
						},
				)?
				Ok({})
			}
			_ => bad("the read row has `${view.name()}` and the stored row `${stored.name()}`")
		}
	}

	# ---------------------------------------------------------------- shapes

	unwrap : Code.Ty -> Code.Ty
	unwrap = |ty| match ty {
		Named(name, _, backing) => if (user_named(name)) Types.unwrap(backing) else ty
		_ => ty
	}

	## `unwrap` that keeps the meaning of a `Recursive` in the backing: a
	## nominal row that links to itself, `Owner := { .., referred_by ?:
	## Link(Owner) }`, holds `Recursive("Owner")`, and the backing has
	## `Owner` in its place (`Types.unfold`). A walk that compares types
	## reads it, and stops where the two sides have the same `key`.
	open : Code.Ty -> Code.Ty
	open = |ty| match ty {
		Named(name, _, backing) => if (user_named(name)) Types.open(Types.unfold(backing, name, ty)) else ty
		_ => ty
	}

	record_fields : Code.Ty -> Try(List(Types.Field), Ql.Error)
	record_fields = |ty| match Types.open(ty) {
		Record(fields) => Ok(fields)
		other => Err(BadSchema("a row is a record, and this is `${other.name()}`"))
	}

	## The row type a `Link` or an `Id` points at, or `Err` for any other type.
	## A link to a nominal row that links back, `Link(Owner)` with
	## `referred_by ?: Link(Owner)`, holds `Recursive("Surreal.Link")` in its
	## row. The target has that link in its place (`Types.unfold`), so a read
	## of the target sees the same type as a read of the link.
	site_of : Code.Ty -> Try({ target : Code.Ty, is_id : Bool }, [NotASite])
	site_of = |ty| {
		site = Types.unwrap(ty)
		match site {
			Named(name, args, _) => match Types.nominal(name) {
				Link => Ok({ target: Types.unfold(Types.row_of(Types.link_name, args), Types.link_name, site), is_id: Bool.False })
				Id => Ok({ target: Types.row_of(Types.id_name, args), is_id: Bool.True })
				_ => Err(NotASite)
			}
			_ => Err(NotASite)
		}
	}

	## The row type of a `Link(row)`, a `Linked(row)` or an `Id(row)` named
	## `name`: its one type argument.
	row_of : Str, List(Code.Ty) -> Code.Ty
	row_of = |name, args| match args {
		[row] => row
		_ => crash "${name} has one type argument"
	}

	## `ty` with each `Recursive(name)` that refers to `whole`, a
	## `Named(name, ..)`, in its place. A `Recursive` refers to the nearest
	## `Named` of its name that holds it, so one inside another `Named` of
	## that name stays.
	unfold : Code.Ty, Str, Code.Ty -> Code.Ty
	unfold = |ty, name, whole| {
		go = |t| Types.unfold(t, name, whole)
		match ty {
			Recursive(n) => if (n == name) whole else ty
			Named(n, args, backing) => if (n == name) ty else Named(n, args.map(go), go(backing))
			ListOf(item) => ListOf(go(item))
			Record(fields) => Record(fields.map(|f| { name: f.name, ty: go(f.ty), presence: f.presence }))
			Tuple(parts) => Tuple(parts.map(go))
			Fn(params, result) => Fn(params.map(go), go(result))
			TagUnion(variants) => TagUnion(variants.map(|v| { name: v.name, payloads: v.payloads.map(go) }))
			Opaque(n, id, args) => Opaque(n, id, args.map(go))
			_ => ty
		}
	}

	## A name for a row type that is equal for the same type however it was
	## reached. A nominal is its name: its body shows a link back to itself
	## differently from each side, so bodies are not compared. A `Link`, a
	## `Linked` and an `Id` are the key of their row, their type argument.
	key : Code.Ty -> Str
	key = |ty| match ty {
		Named(name, args, _) =>
			if Types.nominal(name) == Link {
				"Link<${Types.key(Types.row_of(name, args))}>"
			} else if Types.nominal(name) == Linked {
				"Linked<${Types.key(Types.row_of(name, args))}>"
			} else if Types.nominal(name) == Id {
				"Id<${Types.key(Types.row_of(name, args))}>"
			} else {
				"N:${name}"
			}
		Recursive(name) => "N:${name}"
		ListOf(item) => "List(${Types.key(item)})"
		Record(fields) => "{${Str.join_with(fields.map(|f| "${f.name}${if (f.presence == Optional) "?:" else ":"}${Types.key(f.ty)}"), ",")}}"
		Tuple(parts) => "(${Str.join_with(parts.map(Types.key), ",")})"
		TagUnion(variants) => "[${Str.join_with(variants.map(|v| "${v.name}(${Str.join_with(v.payloads.map(Types.key), ",")})"), ",")}]"
		Fn(params, result) => "Fn(${Str.join_with(params.map(Types.key), ",")}->${Types.key(result)})"
		Opaque(name, _, args) => "O:${name}(${Str.join_with(args.map(Types.key), ",")})"
		other => other.name()
	}

	## The table that holds rows of this type. Two tables with an equal row
	## type make a link to it ambiguous, so that is a `BadSchema`.
	table_for : Types.Registry, Code.Ty -> Try(Str, Ql.Error)
	table_for = |registry, target| match Types.lookup(registry, target) {
		Ok(name) => Ok(name)
		Err(message) => Err(BadSchema(message))
	}

	lookup : Types.Registry, Code.Ty -> Try(Str, Str)
	lookup = |registry, target| {
		wanted = Types.key(target)
		match registry.keep_if(|s| Types.key(s.row_ty) == wanted) {
			[one] => Ok(one.name)
			[] => Err("no table holds the row type `${target.name()}`; list its table in the schema")
			[first, second, ..] => Err("tables `${first.name}` and `${second.name}` have the same row type, so a link to it is ambiguous; make one of the rows a nominal type (`:=`)")
		}
	}

	## Tables must have different names and different row types.
	check_registry : Types.Registry -> Try({}, Ql.Error)
	check_registry = |registry| {
		clash = registry.map_with_index(
			|s, i| registry.drop_first(i + 1).find_first(|t| t.name == s.name or Types.key(t.row_ty) == Types.key(s.row_ty)).map_ok(|t| (s, t)),
		).keep_oks(|r| r)
		match clash {
			[(a, b), ..] =>
				if a.name == b.name {
					Err(BadSchema("two tables are named `${a.name}`"))
				} else {
					Err(BadSchema("tables `${a.name}` and `${b.name}` have the same row type, so a link to it is ambiguous; make one of the rows a nominal type (`:=`)"))
				}
			[] => Ok({})
		}
	}

	# ------------------------------------------------------------ the checks

	## The rules a table must meet, each a `BadSchema` that names the field:
	## `id : Str` or `id : TimeKey(s)`, the two ends of an edge, no field named
	## `kind` in a union arm record, no integer wider than `I64`, and only
	## types SurrealDB has.
	check_table : Types.Source, Types.Registry -> Try({}, Ql.Error)
	check_table = |source, registry| {
		fields = Types.record_fields(source.row_ty)?
		_ = Types.key_type(source.name, fields, registry)?
		skip = Types.skipped(source.kind)
		Types.check_ends(source, fields, registry)?
		_ = fields.keep_if(|f| !skip.contains(f.name)).map_try(|f| Types.scan_field(f, Ql.ident(f.name), registry))?
		Ok({})
	}

	## A field and its type against the rules. A `??` default that is not
	## a literal is `DefaultComputed`: the type does not carry its value, so
	## the schema cannot give it to the database.
	scan_field : Types.Field, Str, Types.Registry -> Try({}, Ql.Error)
	scan_field = |f, path, registry|
		if f.presence == DefaultComputed {
			Err(BadSchema(Types.computed_default(path)))
		} else {
			Types.scan(f.ty, path, registry)
		}

	computed_default : Str -> Str
	computed_default = |path| "field `${path}` has a `??` default that is not a literal, so the type does not carry its value; give it a literal default, or remove the `??` and use `.default_by(|r| r.${path}, |_| ..)`"

	check_ends : Types.Source, List(Types.Field), Types.Registry -> Try({}, Ql.Error)
	check_ends = |source, fields, registry| match source.kind {
		Normal | View(_) => Ok({})
		Relation({ from, to }) => {
			_ = Types.check_end(source.name, "from", from, fields, registry)?
			Types.check_end(source.name, "to", to, fields, registry)
		}
	}

	## An end of an edge is a required `Link` to a row of the table the end
	## names. The link's row type finds its table in the registry.
	check_end : Str, Str, Str, List(Types.Field), Types.Registry -> Try({}, Ql.Error)
	check_end = |table, end, endpoint, fields, registry| {
		wrong = Err(BadSchema("edge table `${table}` needs a required field `${end}` that is a `Link` to a row of table `${endpoint}`"))
		match fields.find_first(|f| f.name == end) {
			Ok({ ty, presence: Required, .. }) => match Types.site_of(ty) {
				Ok({ target, is_id: Bool.False }) =>
					match Types.lookup(registry, target) {
						Ok(name) => if (name == endpoint) Ok({}) else wrong
						Err(message) => Err(BadSchema(message))
					}
				_ => wrong
			}
			_ => wrong
		}
	}

	## One field type, and everything in it, against the rules.
	scan : Code.Ty, Str, Types.Registry -> Try({}, Ql.Error)
	scan = |ty, path, registry| {
		bad = |why| Err(BadSchema("field `${path}`: ${why}"))
		match Types.unwrap(ty) {
			I128 => bad("I128 does not fit SurrealDB's `int`, which is 64-bit signed")
			U128 => bad("U128 does not fit SurrealDB's `int`, which is 64-bit signed")
			Named(name, args, _) =>
				if Types.nominal(name) == Datetime or Types.geometry_type(name).is_ok() {
					Ok({})
				} else if Types.nominal(name) == Link or Types.nominal(name) == Id {
					match Types.lookup(registry, Types.row_of(name, args)) {
						Ok(_) => Ok({})
						Err(why) => bad(why)
					}
				} else if Types.nominal(name) == Linked or Types.nominal(name) == Out or Types.nominal(name) == In {
					bad("`${name}` is a field of a read row, which is not stored; the stored row holds a `Link`, and a read row is checked with `define_read`")
				} else {
					bad("`${name}` has no SurrealDB type")
				}
			Record(fields) => {
				_ = fields.map_try(|f| Types.scan_field(f, Types.dot(path, f.name), registry))?
				Ok({})
			}
			ListOf(item) => Types.scan(item, "${path}[*]", registry)
			TagUnion([]) => bad("an empty union has no values")
			TagUnion(variants) => {
				_ = variants.map_try(
					|v| match v.payloads {
						[] => Ok({})
						[one] => match Types.unwrap(one) {
							Record(fields) =>
								if fields.any(|f| f.name == "kind") {
									bad("the arm `${v.name}` has a field named `kind`, which tells the arms apart")
								} else {
									Types.scan(one, path, registry)
								}
							_ => Types.scan(one, Types.dot(path, "value"), registry)
						}
						many => {
							_ = many.map_with_index(|p, i| Types.scan(p, Types.payload_at(path, i), registry)).map_try(|r| r)?
							Ok({})
						}
					},
				)?
				Ok({})
			}
			Recursive(name) => bad("`${name}` refers back to itself; only a `Link` or an `Id` may do that")
			Tuple(_) => bad("a tuple has no SurrealDB type")
			Fn(_, _) => bad("a function has no SurrealDB type")
			Opaque(name, _, _) => bad("`${name}` has no SurrealDB type")
			_ => Ok({})
		}
	}

	## Fields with no definition of their own: the record key, and an edge's
	## two ends. A view has no field definitions at all.
	skipped : Types.Kind -> List(Str)
	skipped = |kind| match kind {
		Normal | View(_) => ["id"]
		Relation(_) => ["id", "from", "to"]
	}

	## The `TYPE` of the record key, when it is not a text: `[series, datetime]`
	## for `id : TimeKey(s)`. The series has the type of a field of its Roc
	## type, and holds no `Link`: a key has no delete policy. A key may have
	## a literal default (`id : Str ?? "main"`): a create that leaves the key
	## out gets it, as SurrealDB does for a `DEFAULT` on `id`.
	key_type : Str, List(Types.Field), Types.Registry -> Try([Text, Typed(Str)], Ql.Error)
	key_type = |table, fields, registry| match fields.find_first(|f| f.name == "id") {
		Ok({ presence: DefaultComputed, .. }) => Err(BadSchema("table `${table}`: ${Types.computed_default("id")}"))
		Ok({ presence: Optional, .. }) => Err(BadSchema("table `${table}` needs a required field `id : Str` or `id : Surreal.TimeKey(..)`; it is the record key"))
		Ok({ ty: Str, .. }) => Ok(Text)
		Ok({ ty: Named(name, _, backing), .. }) if Types.nominal(name) == TimeKey => {
			series = Types.series_of(backing)
			walk = { path: "id", top: "id", optional: Bool.False, nested: Bool.False, in_list: Bool.False, tag: "", reads: Bool.False, lists: 0 }
			if Types.sites(series, walk).any(|s| !s.is_id) {
				return Err(BadSchema("table `${table}`: the series of `id` holds a `Link`; a key holds an `Id`, because a key has no delete policy"))
			}
			Ok(Typed("[${Types.inline_type(series, registry)?}, datetime]"))
		}
		_ => Err(BadSchema("table `${table}` needs a required field `id : Str` or `id : Surreal.TimeKey(..)`; it is the record key"))
	}

	## `TimeKey(s)` holds its series in `series : s`.
	series_of : Code.Ty -> Code.Ty
	series_of = |backing| match backing {
		Record(fields) => match fields.find_first(|f| f.name == "series") {
			Ok({ ty, .. }) => ty
			_ => crash "Surreal.TimeKey has a series field"
		}
		_ => crash "Surreal.TimeKey is a record"
	}

	## A path part after a dot.
	dot : Str, Str -> Str
	dot = |path, name| "${path}.${Ql.member(name)}"

	## Payload `i` of an arm with several payloads: `pay.value[1]`.
	payload_at : Str, U64 -> Str
	payload_at = |path, i| "${Types.dot(path, "value")}[${i.to_str()}]"

	# ----------------------------------------------------------- type mapping

	## The range of a narrow Roc integer, which SurrealDB's `int` does not hold.
	int_range : Code.Ty -> Try({ lo : I64, hi : I64 }, [NotRanged])
	int_range = |ty| match ty {
		I8 => Ok({ lo: -128, hi: 127 })
		U8 => Ok({ lo: 0, hi: 255 })
		I16 => Ok({ lo: -32768, hi: 32767 })
		U16 => Ok({ lo: 0, hi: 65535 })
		I32 => Ok({ lo: -2147483648, hi: 2147483647 })
		U32 => Ok({ lo: 0, hi: 4294967295 })
		_ => Err(NotRanged)
	}

	## The `TYPE` of a field. A record is `object` and a list of records is
	## `array<object>`: their fields get their own definitions.
	surreal_type : Code.Ty, Types.Registry -> Try(Str, Ql.Error)
	surreal_type = |ty, registry| match Types.unwrap(ty) {
		Record(_) => Ok("object")
		ListOf(item) => match Types.unwrap(item) {
			Record(_) => Ok("array<object>")
			_ => Types.inline_type(ty, registry)
		}
		_ => Types.inline_type(ty, registry)
	}

	## A type written out in full, as inside a union arm or an array.
	inline_type : Code.Ty, Types.Registry -> Try(Str, Ql.Error)
	inline_type = |ty, registry| match Types.unwrap(ty) {
		Str => Ok("string")
		Bool => Ok("bool")
		I64 | I8 | I16 | I32 | U8 | U16 | U32 | U64 => Ok("int")
		F32 | F64 => Ok("float")
		Dec => Ok("decimal")
		Named(name, args, _) =>
			if Types.nominal(name) == Datetime {
				Ok("datetime")
			} else if Types.nominal(name) == Link or Types.nominal(name) == Id {
				table = Types.table_for(registry, Types.row_of(name, args))?
				Ok("record<${Ql.ident(table)}>")
			} else {
				Types.geometry_type(name).map_err(|_| BadSchema("`${name}` has no SurrealDB type"))
			}
		Record(fields) => {
			parts = fields.map_try(|f| Types.member_type(f, registry))?
			Ok("{ ${Str.join_with(parts, ", ")} }")
		}
		ListOf(item) => Ok("array<${Types.inline_type(item, registry)?}>")
		TagUnion(variants) => Types.union_type(variants, registry)
		other => Err(BadSchema("`${other.name()}` has no SurrealDB type"))
	}

	member_type : Types.Field, Types.Registry -> Try(Str, Ql.Error)
	member_type = |f, registry| {
		inner = Types.inline_type(f.ty, registry)?
		Ok("${Ql.member(f.name)}: ${if (f.presence == Optional) "option<${inner}>" else inner}")
	}

	## `"A" | { kind: "B", x: X } | { kind: "C", value: Y } | { kind: "D", value: [Y, Z] }`
	union_type : List({ name : Str, payloads : List(Code.Ty) }), Types.Registry -> Try(Str, Ql.Error)
	union_type = |variants, registry| {
		if variants.is_empty() {
			return Err(BadSchema("an empty union has no values"))
		}
		arms = variants.map_try(
			|v| {
				kind = "kind: \"${v.name}\""
				match v.payloads {
					[] => Ok("\"${v.name}\"")
					[one] => match Types.unwrap(one) {
						Record(fields) => {
							parts = fields.map_try(|f| Types.member_type(f, registry))?
							Ok("{ ${Str.join_with([kind].concat(parts), ", ")} }")
						}
						_ => Ok("{ ${kind}, value: ${Types.inline_type(one, registry)?} }")
					}
					many => {
						parts = many.map_try(|p| Types.inline_type(p, registry))?
						Ok("{ ${kind}, value: [${Str.join_with(parts, ", ")}] }")
					}
				}
			},
		)?
		Ok(Str.join_with(arms, " | "))
	}

	# ------------------------------------------------------------ constraints

	## Conditions a value of this type must meet beyond its `TYPE`, over the
	## expression `subject`. `depth` numbers the closure variables of lists.
	## Each is safe to join with `AND`. SurrealDB stores a geometry with a
	## coordinate out of range, so a geometry asserts `geo::is_valid`.
	constraints : Code.Ty, Str, U64 -> List(Str)
	constraints = |ty, subject, depth| match Types.unwrap(ty) {
		Named(name, _, _) =>
			if Types.nominal(name) == Link or Types.nominal(name) == Id {
				["record::exists(${subject})"]
			} else if Types.geometry_type(name).is_ok() {
				["geo::is_valid(${subject})"]
			} else {
				[]
			}
		Record(fields) => fields.join_map(
			|f| {
				member = "${subject}.${Ql.member(f.name)}"
				inner = Types.constraints(f.ty, member, depth)
				if (f.presence == Optional) inner.map(|c| "(${member} = NONE OR (${c}))") else inner
			},
		)
		ListOf(item) => {
			item_var = "$e${(depth + 1).to_str()}"
			match Types.constraints(item, item_var, depth + 1) {
				[] => []
				inner => ["${subject}.all(|${item_var}| ${Str.join_with(inner, " AND ")})"]
			}
		}
		TagUnion(variants) => variants.join_map(
			|v| {
				inner = match v.payloads {
					[] => []
					[one] => match Types.unwrap(one) {
						Record(_) => Types.constraints(one, subject, depth)
						_ => Types.constraints(one, "${subject}.value", depth)
					}
					many => many.map_with_index(|p, i| Types.constraints(p, Types.payload_at(subject, i), depth)).join()
				}
				match inner {
					[] => []
					_ => ["(IF ${subject}.kind = ${Ql.quote(v.name)} THEN ${Str.join_with(inner, " AND ")} ELSE true END)"]
				}
			},
		)
		# `int` holds no more than an `I64`, and the encoder writes a larger `U64` as a decimal.
		U64 => ["${subject} >= 0"]
		other => match Types.int_range(other) {
			Ok({ lo, hi }) => ["${subject} >= ${lo.to_str()} AND ${subject} <= ${hi.to_str()}"]
			Err(_) => []
		}
	}

	## The `DEFINE FIELD` list of a table, parents before children, in name
	## order. `id` is the record key, and the `from` and `to` of an edge are
	## SurrealDB's `in` and `out`, so none of the three is defined. A key of a
	## time series is the exception: its `TYPE` comes first.
	field_defs : Str, Code.Ty, Types.Registry -> Try(List(Types.FieldDef), Ql.Error)
	field_defs = |table, row_ty, registry| {
		source = match registry.find_first(|s| s.name == table) {
			Ok(s) => s
			Err(_) => return Err(BadSchema("table `${table}` is not in the schema list"))
		}
		Types.check_table({ ..source, row_ty: row_ty }, registry)?
		skip = Types.skipped(source.kind)
		fields = Types.record_fields(row_ty)?
		key_default = match fields.find_first(|f| f.name == "id") {
			Ok({ ty, presence: Default(value), .. }) => [{ ty, value }]
			_ => []
		}
		key_def = match (Types.key_type(table, fields, registry)?, key_default) {
			(Text, []) => []
			(Text, _) => [{ path: "id", top: "id", ty: "string", asserts: [], defaults: key_default }]
			(Typed(ty), _) => [{ path: "id", top: "id", ty, asserts: [], defaults: key_default }]
		}
		defs = fields.keep_if(|f| !skip.contains(f.name)).map_try(|f| Types.defs_of("", "", f, registry))?
		Ok(key_def.concat(defs.join()))
	}

	defs_of : Str, Str, Types.Field, Types.Registry -> Try(List(Types.FieldDef), Ql.Error)
	defs_of = |prefix, top, f, registry| {
		path = if (prefix == "") Ql.ident(f.name) else Types.dot(prefix, f.name)
		first = if (top == "") path else top
		optional = f.presence == Optional
		wrap = |t| if (optional) "option<${t}>" else t
		guard = |cs| if (optional) cs.map(|c| "($value = NONE OR (${c}))") else cs
		defaults = match f.presence {
			Default(value) => [{ ty: f.ty, value }]
			_ => []
		}
		children = |fields, under|
			fields.map_try(|c| Types.defs_of(under, first, c, registry)).map_ok(|lists| lists.join())
		match Types.unwrap(f.ty) {
			Record(fields) => {
				kids = children(fields, path)?
				Ok(kids.prepend({ path: path, top: first, ty: wrap("object"), asserts: [], defaults }))
			}
			ListOf(item) => match Types.unwrap(item) {
				Record(fields) => {
					kids = children(fields, "${path}[*]")?
					if Types.has_default(item) {
						check = Types.key_check(fields)
						Ok(kids.prepend({ path: path, top: first, ty: wrap("array<object>"), asserts: guard([check]), defaults }))
					} else {
						# The literal type of the element refuses extra keys, and holds the
						# member types, so the members keep only their conditions.
						literal = Types.inline_type(f.ty, registry)?
						Ok(kids.map(|k| { ..k, ty: "" }).prepend({ path: path, top: first, ty: wrap(literal), asserts: [], defaults }))
					}
				}
				_ => Types.leaf(path, first, f.ty, optional, defaults, registry)
			}
			_ => Types.leaf(path, first, f.ty, optional, defaults, registry)
		}
	}

	leaf : Str, Str, Code.Ty, Bool, List({ ty : Code.Ty, value : Code.Value }), Types.Registry -> Try(List(Types.FieldDef), Ql.Error)
	leaf = |path, top, ty, optional, defaults, registry| {
		type = Types.inline_type(ty, registry)?
		cs = Types.constraints(ty, "$value", 0)
		asserts = if (optional) cs.map(|c| "($value = NONE OR (${c}))") else cs
		Ok([{ path: path, top: top, ty: if (optional) "option<${type}>" else type, asserts: asserts, defaults }])
	}

	## Whether a record has a member with a default at any depth, through
	## records and lists. A literal element type takes no missing key, so a
	## list of such records is an `array<object>` with a definition for each
	## member.
	has_default : Code.Ty -> Bool
	has_default = |ty| match Types.unwrap(ty) {
		Record(fields) => fields.any(
			|f| Types.has_default(f.ty) or match f.presence {
				Required | Optional => Bool.False
				Default(_) | DefaultComputed => Bool.True
			},
		)
		ListOf(item) => Types.has_default(item)
		_ => Bool.False
	}

	## Elements of an `array<object>` may carry extra keys, so the keys are
	## checked by a generated condition.
	key_check : List(Types.Field) -> Str
	key_check = |fields| "$value.all(|$e| object::keys($e).all(|$k| $k IN [${Str.join_with(fields.map(|f| Ql.quote(f.name)), ", ")}]))"

	# ------------------------------------------------------------- link sites

	## Every `Link` and `Id` in a row type, at any depth, in name order. A
	## `Link` or `Id` is not entered: it is another table's row. The `from`
	## and `to` of an edge row are listed like any other link, though they
	## are SurrealDB's `in` and `out`.
	link_sites : Code.Ty -> List(Types.LinkSite)
	link_sites = |row_ty| Types.sites_of(row_ty, Bool.False, Ql.ident)

	## The `Linked` rows that a whole value of type `ty` at `path` reads,
	## under `lists` lists: each `Linked` in it, at any depth, and after each
	## the `Linked` rows of its own row. A `Link` and an `Id` in it are
	## record ids. The `target` of each is its row type, whose table
	## `lookup` finds. A read row that holds a `Linked` of itself has no end,
	## so a `Linked` of a row in `entered`, by key, is not read again: the
	## translator refuses that whole row. `spell` spells a field of the row
	## at `""`, `in` and `out` for the ends of an edge. A live query watches
	## the table of each (`Translate.whole`, `Selected.live`).
	whole_reads : Code.Ty, Str, U64, (Str -> Str), List(Str) -> List({ path : Str, target : Code.Ty, lists : U64 })
	whole_reads = |ty, path, lists, spell, entered| {
		found =
			if path.is_empty() {
				Types.sites_of(ty, Bool.True, spell)
			} else {
				Types.sites(ty, { path, top: path, optional: Bool.False, nested: Bool.False, in_list: Bool.False, tag: "", reads: Bool.True, lists })
			}
		found.keep_if(|s| s.linked).join_map(
			|s| {
				row = Types.key(s.target)
				if entered.contains(row) {
					[]
				} else {
					[{ path: s.path, target: s.target, lists: s.lists }].concat(Types.whole_reads(s.target, s.path, s.lists, Ql.ident, entered.append(row)))
				}
			},
		)
	}

	## The sites of a row type. With `reads`, a `Linked` is a site too.
	sites_of : Code.Ty, Bool, (Str -> Str) -> List(Types.LinkSite)
	sites_of = |row_ty, reads, spell| match Types.unwrap(row_ty) {
		Record(fields) => fields.join_map(
			|f| {
				path = spell(f.name)
				Types.sites(f.ty, { path: path, top: path, optional: f.presence == Optional, nested: Bool.False, in_list: Bool.False, tag: "", reads, lists: 0 })
			},
		)
		_ => []
	}

	Walk : { path : Str, top : Str, optional : Bool, nested : Bool, in_list : Bool, tag : Str, reads : Bool, lists : U64 }

	## A `Link` or an `Id`, and with `reads` a `Linked`, which points at
	## its row, its type argument, as a `Link` does.
	site_in : Code.Ty, Bool -> Try({ target : Code.Ty, is_id : Bool, linked : Bool }, [NotASite])
	site_in = |ty, reads| match (Types.site_of(ty), ty) {
		(Ok({ target, is_id }), _) => Ok({ target, is_id, linked: Bool.False })
		(Err(NotASite), Named(name, args, _)) if reads and Types.nominal(name) == Linked => Ok({ target: Types.row_of(name, args), is_id: Bool.False, linked: Bool.True })
		(Err(NotASite), _) => Err(NotASite)
	}

	sites : Code.Ty, Types.Walk -> List(Types.LinkSite)
	sites = |ty, w| match Types.site_in(ty, w.reads) {
		Ok(found) => [Types.site(w, found, Bool.False)]
		Err(NotASite) => match Types.unwrap(ty) {
			Record(fields) => fields.join_map(
				|f| Types.sites(
					f.ty,
					{ ..w, path: Types.dot(w.path, f.name), optional: w.optional or f.presence == Optional, nested: Bool.True },
				),
			)
			ListOf(item) => match Types.site_in(item, w.reads) {
				Ok(found) => [Types.site({ ..w, lists: w.lists + 1 }, found, Bool.True)]
				Err(NotASite) => Types.sites(item, { ..w, path: "${w.path}[*]", nested: Bool.True, in_list: Bool.True, lists: w.lists + 1 })
			}
			TagUnion(variants) => variants.join_map(
				|v| {
					arm = { ..w, nested: Bool.True, tag: v.name }
					match v.payloads {
						[] => []
						[one] => match Types.unwrap(one) {
							Record(_) => Types.sites(one, arm)
							_ => Types.sites(one, { ..arm, path: Types.dot(w.path, "value") })
						}
						many => many.map_with_index(|p, i| Types.sites(p, { ..arm, path: Types.payload_at(w.path, i) })).join()
					}
				},
			)
			_ => []
		}
	}

	site : Types.Walk, { target : Code.Ty, is_id : Bool, linked : Bool }, Bool -> Types.LinkSite
	site = |w, found, elements| {
		shape =
			if w.tag != "" {
				InUnionArm({ tag: w.tag })
			} else if w.in_list {
				InList
			} else if w.nested {
				InObject
			} else if elements {
				RootList
			} else if w.optional {
				RootOptional
			} else {
				Root
			}
		{
			path: w.path,
			top: w.top,
			target: found.target,
			is_id: found.is_id,
			linked: found.linked,
			lists: w.lists,
			required: !w.optional and !w.in_list and w.tag == "" and !elements,
			shape: shape,
			elements: elements,
		}
	}
}

# Tests that need no table. The rest are in `TypesTest.roc`, where a row type
# comes from a reified table.

expect Types.int_range(U8) == Ok({ lo: 0, hi: 255 })
expect Types.int_range(I32) == Ok({ lo: -2147483648, hi: 2147483647 })
expect Types.int_range(I64) == Err(NotRanged)
expect Types.int_range(Str) == Err(NotRanged)
expect Types.user_named("Customer")
expect !Types.user_named("Surreal.Link")
expect !Types.user_named("Builtin.Try")
expect Types.unwrap(Named("Customer", [], Str)) == Str
expect Types.unwrap(Named("Surreal.Datetime", [], Str)) == Named("Surreal.Datetime", [], Str)
expect Types.key(ListOf(Str)) == "List(Str)"
expect Types.key(Record([{ name: "a", ty: I64, presence: Required }, { name: "b", ty: Str, presence: Optional }])) == "{a:I64,b?:Str}"
expect Types.key(Named("Customer", [], Str)) == "N:Customer"
expect Types.key(Named("Surreal.Id", [Named("Customer", [], Str)], Record([]))) == "Id<N:Customer>"
expect Types.key(Recursive("Customer")) == "N:Customer"
expect Types.unfold(Record([{ name: "next", ty: Recursive("N"), presence: Optional }]), "N", Named("N", [], Str)) == Record([{ name: "next", ty: Named("N", [], Str), presence: Optional }])
expect Types.unfold(ListOf(Named("N", [], Recursive("N"))), "N", Named("N", [], Str)) == ListOf(Named("N", [], Recursive("N")))
expect Types.unfold(ListOf(Recursive("M")), "N", Named("N", [], Str)) == ListOf(Recursive("M"))
expect Types.unfold(Named("Surreal.Id", [Recursive("N")], Record([])), "N", Named("N", [], Str)) == Named("Surreal.Id", [Named("N", [], Str)], Record([]))
expect Types.open(Named("N", [], Record([{ name: "next", ty: Recursive("N"), presence: Optional }]))) == Record([{ name: "next", ty: Named("N", [], Record([{ name: "next", ty: Recursive("N"), presence: Optional }])), presence: Optional }])
expect Types.dot("items[*]", "qty") == "items[*].qty"
expect Types.dot("payment", "value") == "payment.value"
expect Types.dot("a", "x y") == "a.⟨x y⟩"
expect Types.constraints(U8, "$value", 0) == ["$value >= 0 AND $value <= 255"]
expect Types.constraints(Str, "$value", 0) == []
expect Types.constraints(U64, "$value", 0) == ["$value >= 0"]
expect Types.constraints(ListOf(U64), "$value", 0) == ["$value.all(|$e1| $e1 >= 0)"]
expect Types.constraints(ListOf(I8), "$value", 0) == ["$value.all(|$e1| $e1 >= -128 AND $e1 <= 127)"]
expect Types.constraints(ListOf(ListOf(U8)), "$value", 0) == ["$value.all(|$e1| $e1.all(|$e2| $e2 >= 0 AND $e2 <= 255))"]
expect Types.constraints(Record([{ name: "n", ty: U16, presence: Optional }]), "$value", 0) == ["($value.n = NONE OR ($value.n >= 0 AND $value.n <= 65535))"]
expect Types.constraints(TagUnion([{ name: "A", payloads: [] }, { name: "B", payloads: [U8] }]), "$value", 0) == ["(IF $value.kind = 'B' THEN $value.value >= 0 AND $value.value <= 255 ELSE true END)"]
expect Types.constraints(TagUnion([{ name: "C", payloads: [Str, U8] }]), "$value", 0) == ["(IF $value.kind = 'C' THEN $value.value[1] >= 0 AND $value.value[1] <= 255 ELSE true END)"]
expect Types.key_check([{ name: "a", ty: Str, presence: Required }, { name: "it's", ty: Str, presence: Optional }]) == "$value.all(|$e| object::keys($e).all(|$k| $k IN ['a', 'it\\'s']))"
expect Types.union_type([{ name: "A", payloads: [] }, { name: "B", payloads: [Str] }, { name: "C", payloads: [Str, I64] }], []) == Ok("\"A\" | { kind: \"B\", value: string } | { kind: \"C\", value: [string, int] }")
expect Types.union_type([], []) == Err(BadSchema("an empty union has no values"))
expect Types.inline_type(ListOf(Record([{ name: "n", ty: I64, presence: Optional }])), []) == Ok("array<{ n: option<int> }>")
expect Types.inline_type(U64, []) == Ok("int")
expect Types.inline_type(I128, []).is_err()
expect Types.inline_type(Tuple([Str]), []).is_err()
expect Types.inline_type(Recursive("C"), []).is_err()
expect Types.surreal_type(Record([]), []) == Ok("object")
