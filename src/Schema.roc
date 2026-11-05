import Ql
import Types
import Translate

# The schema: `DEFINE` statements from the row types and from the builder's
# clauses. A clause is translated when it is given, so a `Defined` holds only
# text and names. `script` puts the statements of every table in order and
# adds what each link needs: an existence check, and a delete policy at any
# depth (native `REFERENCE` at the root, generated events elsewhere).
Schema :: {}.{

	## What a delete does to the rows that link to the deleted row.
	Policy : [Reject, Unset, Cascade, Ignore]

	## One clause of the builder, translated. Paths are spelled as a field
	## definition names them (`items[*].qty`). Conditions are over `$value`,
	## a row check is over `$after`, a computed value is over `$this`.
	Rule := [
		Assert({ path : Str, cond : Str }),
		Check({ name : Str, cond : Str, holders : List({ path : Str, cond : Str }) }),
		Index({ paths : List(Str), unique : Bool }),
		SearchIndex({ path : Str, kind : Str, spec : Str, analyzers : List(Str) }),
		Default({ path : Str, value : Str }),
		Computed({ path : Str, expr : Str }),
		Readonly(Str),
		Comment({ path : Str, text : Str }),
		OnDelete({ table : Str, policy : Schema.Policy }),
		OnDeleteAt({ path : Str, policy : Schema.Policy }),
		Changefeed(U64),
		Permit({ actions : List(Schema.Action), grant : Schema.Grant }),
		PermitField({ path : Str, actions : List(Schema.Action), grant : Schema.Grant }),
	].{
		is_eq : _
	}

	## What a permission is for: a statement of a record user that reads
	## or writes the table or the field.
	Action : [Select, Create, Update, Delete]

	## A permission: the rows that the condition keeps (`WHERE`, over the
	## row, which may read the session: `$auth.id`), every row, or none.
	Grant : [Where(Str), Full, No]

	## A finished table definition, the database functions of one
	## `Surreal.function`, or a read row of a table, which writes no
	## statement and is checked against the stored row: what
	## `Surreal.schema` takes.
	Defined :: [
		Table({ source : Types.Source, rules : List(Schema.Rule), problems : List(Ql.Error) }),
		Function(Try(List(Schema.Function), Ql.Error)),
		Read({ name : Str, row_ty : Code.Ty }),
		Access(Try(Str, Ql.Error)),
		Analyzer({ name : Str, line : Str }),
	]

	## A database function, translated: `$a1`, `$a2`, .. have the types of
	## `params`, and `body` is the value it returns.
	Function : { name : Str, params : List(Code.Ty), result : Code.Ty, body : Str }

	defined : Types.Source, List(Schema.Rule), List(Ql.Error) -> Schema.Defined
	defined = |source, rules, problems| Defined.(Table({ source, rules, problems }))

	function : Try(List(Schema.Function), Ql.Error) -> Schema.Defined
	function = |functions| Defined.(Function(functions))

	read : Str, Code.Ty -> Schema.Defined
	read = |name, row_ty| Defined.(Read({ name, row_ty }))

	## `DEFINE ANALYZER`, which a full-text index names: a statement of
	## the database, before every table.
	analyzer : Str, Str -> Schema.Defined
	analyzer = |name, line| Defined.(Analyzer({ name, line }))

	## A full-text or a vector index on the field at `path`: `kind` names
	## it, `spec` is what follows `FIELDS path` (`FULLTEXT ANALYZER a BM25
	## HIGHLIGHTS`, `HNSW DIMENSION 3 DIST COSINE TYPE F64`), and
	## `analyzers` the analyzer it names, which the schema must define.
	search_index : Str, Str, Str, List(Str) -> Try(List(Schema.Rule), Ql.Error)
	search_index = |path, kind, spec, analyzers| Ok([SearchIndex({ path, kind, spec, analyzers })])

	## `DEFINE ACCESS name ON DATABASE TYPE RECORD`: a signup is a
	## `CREATE` of the content, a signin a `SELECT` of the row that the
	## condition keeps, each over the variables of the RPC as `$name`.
	## The durations are nanoseconds; one that is not given is
	## SurrealDB's default (a token of 1 hour, a session with no end).
	access : { name : Str, table : Str, content : Try(Str, Ql.Error), cond : Try(Str, Ql.Error), token : Try(U64, [Unset]), session : Try(U64, [Unset]) } -> Schema.Defined
	access = |a| {
		line = |{}| {
			durations = [("TOKEN", a.token), ("SESSION", a.session)].keep_oks(|(what, d)| d.map_ok(|nanos| "FOR ${what} ${Ql.duration(nanos)}"))
			during = if (durations.is_empty()) "" else " DURATION ${Str.join_with(durations, ", ")}"
			Ok("DEFINE ACCESS OVERWRITE ${Ql.ident(a.name)} ON DATABASE TYPE RECORD SIGNUP (CREATE ${Ql.ident(a.table)} CONTENT ${a.content?}) SIGNIN (SELECT * FROM ${Ql.ident(a.table)} WHERE ${a.cond?})${during};")
		}
		Defined.(Access(line({})))
	}

	## The tables of the definitions, where a link finds its table: each
	## stored row, and each read row with the name of its table.
	tables : List(Schema.Defined) -> Types.Registry
	tables = |all| all.keep_oks(
		|Defined.(d)| match d {
			Table(t) => Ok(t.source)
			Read(r) => Ok({ name: r.name, row_ty: r.row_ty, kind: Types.Kind.Normal })
			Function(_) | Access(_) | Analyzer(_) => Err(NotTable)
		},
	)

	## One step to a link: a field, each element of a list, the arm of a
	## union (the value there is that arm), or one item of an array.
	Hop : [Field(Str), Each, Arm(Str), Item(U64)]

	## A `Link` or `Id` in a row. A list of links ends in `Each`. `optional`
	## is True when the link's own field is `?:`.
	Site : { hops : List(Schema.Hop), target : Code.Ty, optional : Bool }

	# ------------------------------------------------------------ clauses

	## A row check, placed by one rule: when it reads only one top-level
	## field, it is that field's `ASSERT`; when it reads more, it is the
	## `ASSERT` of one of them (`place_checks`), or else an event over
	## `$after`; when it reads none, it is an error. `extensions` give
	## the forms of the calls of each clause here (`Translate.form`).
	check : List(Translate.Extension), Types.Source, Str, Code.Graph -> Try(List(Schema.Rule), Ql.Error)
	check = |extensions, source, name, graph| {
		whole = Translate.render(extensions, graph, [Translate.document("$after", Schema.is_edge(source))], Translate.variable)?
		fields = Types.record_fields(source.row_ty)?.keep_if(|f| !Schema.skipped(source).contains(f.name))
		match Schema.placed(extensions, graph, fields) {
			NoField => Err(BadSchema("the check `${name}` reads no field, so it is always or never true"))
			OnField(f) => Ok([Assert({ path: Ql.ident(f.name), cond: f.cond })])
			Several => Ok([Check({ name, cond: whole, holders: Schema.holders(extensions, graph, fields) })])
		}
	}

	## The fields that can hold a check over several fields as their `ASSERT`:
	## each required field that the check reads, with the check over `$value`
	## for that field and `$this` for the others. `$this` is the row with the
	## new values of every field (verified), so the other fields are final.
	## It is empty when the check reads a field with no definition (the key).
	holders : List(Translate.Extension), Code.Graph, List(Types.Field) -> List({ path : Str, cond : Str })
	holders = |extensions, graph, fields| {
		bound = |f, expr| if (f.presence == Optional) Translate.Binding.Maybe(expr) else Translate.at(expr, f.ty)
		render = |held, shown| {
			all = shown.map(|f| { name: f.name, binding: bound(f, if (f.name == held) "$value" else "$this.${Ql.member(f.name)}") })
			Translate.render(extensions, graph, [Translate.Binding.Fields(all)], Translate.variable)
		}
		reads = |f| render("", fields.keep_if(|g| g.name != f.name)).is_err()
		if render("", fields).is_err() {
			[]
		} else {
			fields.keep_if(|f| f.presence != Optional and reads(f)).keep_oks(|f| render(f.name, fields).map_ok(|cond| { path: Ql.ident(f.name), cond }))
		}
	}

	## A check over several fields is the `ASSERT` of its first holder that
	## is not read-only and has no field permission: SurrealDB runs the
	## assert of a required field on every write, but not the assert of a
	## read-only field that does not change (verified), and an event has no
	## field permission. With no such holder, it stays an event.
	place_checks : List(Schema.Rule) -> List(Schema.Rule)
	place_checks = |rules| rules.map(
		|r| match r {
			Check({ holders: candidates, .. }) =>
				match candidates.find_first(|h| !rules.any(|o| o == Readonly(h.path) or Schema.permits_field(o, h.path))) {
					Ok(h) => Assert({ path: h.path, cond: h.cond })
					Err(_) => r
				}
			_ => r
		},
	)

	permits_field : Schema.Rule, Str -> Bool
	permits_field = |rule, path| match rule {
		PermitField(p) => p.path == path
		_ => Bool.False
	}

	## A permission of the table for `actions`: the condition over the
	## row, a `filter`'s (`Translate.table_row`), or `FULL` or `NONE`.
	permit : List(Translate.Extension), Types.Source, List(Schema.Action), [Where(Code.Graph), Full, No] -> Try(List(Schema.Rule), Ql.Error)
	permit = |extensions, source, actions, grant| Ok([Permit({ actions, grant: Schema.grant(extensions, source, grant)? })])

	## A permission of the field at a path for `actions`, as `permit`.
	permit_field : List(Translate.Extension), Types.Source, Code.Graph, List(Schema.Action), [Where(Code.Graph), Full, No] -> Try(List(Schema.Rule), Ql.Error)
	permit_field = |extensions, source, path_graph, actions, grant| {
		path = Schema.one_field(path_graph, "permit_field")?
		if actions.contains(Delete) {
			return Err(BadSchema("`${source.name}.${path}`: a field has no `delete` permission; the table's decides"))
		}
		Ok([PermitField({ path, actions, grant: Schema.grant(extensions, source, grant)? })])
	}

	grant : List(Translate.Extension), Types.Source, [Where(Code.Graph), Full, No] -> Try(Schema.Grant, Ql.Error)
	grant = |extensions, source, given| match given {
		Where(graph) => Translate.render(extensions, graph, [Translate.table_row(source.name, Schema.is_edge(source))], Translate.variable).map_ok(|cond| Where(cond))
		Full => Ok(Full)
		No => Ok(No)
	}

	## `PERMISSIONS FOR select WHERE .., FOR create, update FULL`: one
	## `FOR` for each permission, in the order given. Each action is in
	## one at most. A table names the actions that no permission names
	## `NONE`, which is SurrealDB's default for a table; a field leaves
	## them out, and SurrealDB's default for a field is `FULL`.
	permissions : Str, List({ actions : List(Schema.Action), grant : Schema.Grant }), Bool -> Try(Str, Ql.Error)
	permissions = |what, given, table| {
		if given.is_empty() {
			return Ok("")
		}
		named = given.join_map(|p| p.actions)
		all = [Select, Create, Update, Delete]
		match all.find_first(|a| named.count_if(|n| n == a) > 1) {
			Ok(twice) => return Err(BadSchema("${what} has two permissions for `${Schema.action_name(twice)}`"))
			Err(_) => {}
		}
		unnamed = all.keep_if(|a| !named.contains(a))
		parts = if (table and !unnamed.is_empty()) given.append({ actions: unnamed, grant: No }) else given
		fors = parts.map(
			|p| {
				granted = match p.grant {
					Where(cond) => "WHERE ${cond}"
					Full => "FULL"
					No => "NONE"
				}
				"FOR ${Str.join_with(p.actions.map(Schema.action_name), ", ")} ${granted}"
			},
		)
		Ok(" PERMISSIONS ${Str.join_with(fors, ", ")}")
	}

	action_name : Schema.Action -> Str
	action_name = |action| match action {
		Select => "select"
		Create => "create"
		Update => "update"
		Delete => "delete"
	}

	## Where a predicate over a record goes. It is evaluated with the record
	## holding one field at a time, bound to `$value`: it evaluates exactly
	## when it reads nothing outside that field.
	placed : List(Translate.Extension), Code.Graph, List(Types.Field) -> [NoField, OnField({ name : Str, cond : Str }), Several]
	placed = |extensions, graph, fields| {
		evaluated = |only| Translate.render(extensions, graph, [Translate.Binding.Fields(only)], Translate.variable)
		if evaluated([]).is_ok() {
			NoField
		} else {
			found = fields.keep_oks(
				|f| {
					value = if (f.presence == Optional) Translate.Binding.Maybe("$value") else Translate.at("$value", f.ty)
					evaluated([{ name: f.name, binding: value }]).map_ok(|cond| { name: f.name, cond })
				},
			)
			match found {
				[one] => OnField(one)
				_ => Several
			}
		}
	}

	## A predicate on one field: its `ASSERT`.
	assert : List(Translate.Extension), Code.Graph, Code.Graph -> Try(List(Schema.Rule), Ql.Error)
	assert = |extensions, path_graph, predicate| {
		path = Schema.one_field(path_graph, "assert")?
		cond = Translate.render(extensions, predicate, [Translate.at("$value", Schema.param_ty(predicate))], Translate.variable)?
		Ok([Assert({ path, cond })])
	}

	## A predicate on each element of a list field. On a list of records it
	## goes on the one element field it reads, as `check` does on a row;
	## otherwise it is `$value.all(..)` on the list.
	assert_each : List(Translate.Extension), Code.Graph, Code.Graph -> Try(List(Schema.Rule), Ql.Error)
	assert_each = |extensions, path_graph, predicate| {
		path = Schema.one_field(path_graph, "assert_each")?
		item = Schema.param_ty(predicate)
		every = |{}| {
			cond = Translate.render(extensions, predicate, [Translate.at("$item", item)], Translate.variable)?
			Ok([Assert({ path, cond: "$value.all(|$item| ${cond})" })])
		}
		match Types.unwrap(item) {
			Record(fields) => match Schema.placed(extensions, predicate, fields) {
				NoField => Err(BadSchema("the check on each element of `${path}` reads no field, so it is always or never true"))
				OnField(f) => Ok([Assert({ path: Types.dot("${path}[*]", f.name), cond: f.cond })])
				Several => every({})
			}
			_ => every({})
		}
	}

	## An index on one path or on a record of paths.
	index : Types.Source, Code.Graph, Bool -> Try(List(Schema.Rule), Ql.Error)
	index = |source, graph, unique| {
		paths = Translate.paths_of(graph)?
		Ok([Index({ paths: paths.map(|p| Schema.index_path(p, Schema.is_edge(source))), unique })])
	}

	## An index path. An edge's `from` and `to` are SurrealDB's `in` and `out`.
	index_path : List(Translate.Step), Bool -> Str
	index_path = |steps, edge| match steps {
		[Field(name)] if edge and (name == "from" or name == "to") => Translate.spell_name(name, edge)
		_ => Translate.spell(steps)
	}

	default : Code.Graph, Ql.Value -> Try(List(Schema.Rule), Ql.Error)
	default = |graph, value| Ok([Default({ path: Translate.spell(Translate.path_of(graph)?), value: Ql.literal(value) })])

	## A default that is an expression over `$this`, which may call `Rand`.
	default_by : List(Translate.Extension), Types.Source, Code.Graph, Code.Graph -> Try(List(Schema.Rule), Ql.Error)
	default_by = |extensions, source, path_graph, value| {
		path = Translate.spell(Translate.path_of(path_graph)?)
		expr = Translate.row_value(extensions, value, [Translate.document("$this", Schema.is_edge(source))], Translate.variable)?
		Ok([Default({ path, value: expr })])
	}

	## A value SurrealDB computes on every write, over `$this`. It may call `Rand`.
	computed : List(Translate.Extension), Types.Source, Code.Graph, Code.Graph -> Try(List(Schema.Rule), Ql.Error)
	computed = |extensions, source, path_graph, value| {
		path = Translate.spell(Translate.path_of(path_graph)?)
		expr = Translate.row_value(extensions, value, [Translate.document("$this", Schema.is_edge(source))], Translate.variable)?
		Ok([Computed({ path, expr })])
	}

	readonly : Code.Graph -> Try(List(Schema.Rule), Ql.Error)
	readonly = |graph| Ok([Readonly(Translate.spell(Translate.path_of(graph)?))])

	## The time of the first write, kept: `VALUE time::now() READONLY`
	## (verified: an update keeps it, a create cannot set it).
	created_now : Code.Graph -> Try(List(Schema.Rule), Ql.Error)
	created_now = |graph| {
		path = Translate.spell(Translate.path_of(graph)?)
		Ok([Computed({ path, expr: "time::now()" }), Readonly(path)])
	}

	## A change history of this many nanoseconds, on the table line.
	changefeed : U64 -> Try(List(Schema.Rule), Ql.Error)
	changefeed = |nanos| Ok([Changefeed(nanos)])

	comment : Code.Graph, Str -> Try(List(Schema.Rule), Ql.Error)
	comment = |graph, text| Ok([Comment({ path: Translate.spell(Translate.path_of(graph)?), text })])

	on_delete : Str, Schema.Policy -> Try(List(Schema.Rule), Ql.Error)
	on_delete = |table, policy| Ok([OnDelete({ table, policy })])

	on_delete_at : Code.Graph, Schema.Policy -> Try(List(Schema.Rule), Ql.Error)
	on_delete_at = |graph, policy| Ok([OnDeleteAt({ path: Translate.spell(Translate.path_of(graph)?), policy })])

	one_field : Code.Graph, Str -> Try(Str, Ql.Error)
	one_field = |graph, clause| {
		steps = Translate.path_of(graph)?
		if steps.contains(Each) {
			Err(Unsupported("`${clause}` reads one field; for each element of a list use `assert_each`"))
		} else {
			Ok(Translate.spell(steps))
		}
	}

	param_ty : Code.Graph -> Code.Ty
	param_ty = |graph| match graph.root_row().params {
		[ty] => ty
		_ => crash "a `Code(v -> Bool)` has one parameter"
	}

	is_edge : Types.Source -> Bool
	is_edge = |source| match source.kind {
		Relation(_) => Bool.True
		Normal | View(_) => Bool.False
	}

	## Fields with no definition: the record key, and an edge's two ends.
	skipped : Types.Source -> List(Str)
	skipped = |source| Types.skipped(source.kind)

	# ------------------------------------------------------------ link sites

	## Every `Link` and `Id` in a row, as `Types.link_sites` lists them, with
	## the steps that reach each one. The ends of an edge are not listed:
	## SurrealDB's `ENFORCED` relation checks them and deletes the edge with
	## either end.
	sites : Types.Source -> Try(List(Schema.Site), Ql.Error)
	sites = |source| {
		fields = Types.record_fields(source.row_ty)?
		Ok(
			fields
				.keep_if(|f| !Schema.skipped(source).contains(f.name))
				.join_map(|f| Schema.walk(f.ty, [Field(f.name)], f.presence == Optional)),
		)
	}

	walk : Code.Ty, List(Schema.Hop), Bool -> List(Schema.Site)
	walk = |ty, hops, optional| match Types.site_of(ty) {
		Ok({ target, .. }) => [{ hops, target, optional }]
		Err(NotASite) => match Types.unwrap(ty) {
			Record(fields) => fields.join_map(|f| Schema.walk(f.ty, hops.append(Field(f.name)), f.presence == Optional))
			ListOf(item) => Schema.walk(item, hops.append(Each), Bool.False)
			TagUnion(variants) => variants.join_map(
				|v| {
					arm = hops.append(Arm(v.name))
					match v.payloads {
						[] => []
						[one] => match Types.unwrap(one) {
							Record(_) => Schema.walk(one, arm, Bool.False)
							_ => Schema.walk(one, arm.append(Field("value")), Bool.False)
						}
						many => many.map_with_index(|p, i| Schema.walk(p, arm.append(Field("value")).append(Item(i)), Bool.False)).join()
					}
				},
			)
			_ => []
		}
	}

	## The field a site is in: a list of links is the list.
	site_path : List(Schema.Hop) -> Str
	site_path = |hops| match hops.last() {
		Ok(Each) => Schema.spell(hops.drop_last(1))
		_ => Schema.spell(hops)
	}

	spell : List(Schema.Hop) -> Str
	spell = |hops| hops.fold(
		"",
		|text, hop| match hop {
			Field(name) => if (text.is_empty()) Ql.ident(name) else Types.dot(text, name)
			Each => "${text}[*]"
			Item(i) => "${text}[${i.to_str()}]"
			Arm(_) => text
		},
	)

	## The shape `Types.link_sites` gives the same site.
	shape : Schema.Site -> Types.Shape
	shape = |site| {
		tags = site.hops.keep_oks(
			|h| match h {
				Arm(tag) => Ok(tag)
				_ => Err(NotArm)
			},
		)
		inner = site.hops.drop_last(1)
		match tags.last() {
			Ok(tag) => InUnionArm({ tag: tag })
			Err(_) =>
				if inner.contains(Each) {
					InList
				} else if site.hops.len() > 2 or (site.hops.len() == 2 and site.hops.last() != Ok(Each)) {
					InObject
				} else if site.hops.len() == 2 {
					RootList
				} else if site.optional {
					RootOptional
				} else {
					Root
				}
		}
	}

	## A site SurrealDB's own `REFERENCE` covers: a root field, or a root
	## list of links. `REFERENCE` is refused on a nested field (SF).
	is_native : List(Schema.Hop) -> Bool
	is_native = |hops| match hops {
		[Field(_)] | [Field(_), Each] => Bool.True
		_ => Bool.False
	}

	## A condition over a row of the linking table: the link at `hops` is the
	## deleted row, `$before.id`.
	mentions : Str, List(Schema.Hop), U64 -> Str
	mentions = |at, hops, depth| match hops {
		[] => "${at} = $before.id"
		[Each] => "$before.id IN ${at}"
		[Field(name), .. as rest] => Schema.mentions(Schema.member(at, name), rest, depth)
		[Arm(tag), .. as rest] => "(${at}.kind = ${Ql.quote(tag)} AND ${Schema.mentions(at, rest, depth)})"
		[Item(i), .. as rest] => Schema.mentions("${at}[${i.to_str()}]", rest, depth)
		# One list of objects: `IN` reads the index of the path (`EXPLAIN`:
		# `IndexScan`), where `any` reads the table (`TableScan`).
		[Each, .. as rest] if Schema.only_fields(rest) => "$before.id IN ${at}${Schema.spell([Each].concat(rest))}"
		[Each, .. as rest] => {
			item = "$e${(depth + 1).to_str()}"
			"${at}.any(|${item}| ${Schema.mentions(item, rest, depth + 1)})"
		}
	}

	only_fields : List(Schema.Hop) -> Bool
	only_fields = |hops| hops.all(
		|h| match h {
			Field(_) => Bool.True
			_ => Bool.False
		},
	)

	is_arm : Schema.Hop -> Bool
	is_arm = |hop| match hop {
		Arm(_) => Bool.True
		_ => Bool.False
	}

	member : Str, Str -> Str
	member = |at, name| if (at.is_empty()) Ql.ident(name) else "${at}.${Ql.member(name)}"

	## The `SET` that unsets a nested link: an optional field becomes `NONE`,
	## a link leaves its list, and an element of a list of objects that holds
	## the link leaves the list, as native `UNSET` does to a list of links.
	unset : Schema.Site -> Try(Str, Str)
	unset = |site| {
		hops = site.hops
		if hops.any(Schema.is_arm) {
			return Err("an arm of a union cannot be unset; use Reject, Cascade or Ignore")
		}
		match hops.find_first_index(|h| h == Each) {
			Err(_) =>
				if site.optional {
					Ok("${Schema.spell(hops)} = NONE")
				} else {
					Err("the link is a required field, so it cannot be unset; make it optional (`?:`) or use Reject, Cascade or Ignore")
				}
			Ok(i) => {
				list = Schema.spell(hops.take_first(i))
				rest = hops.drop_first(i + 1)
				if rest.is_empty() {
					Ok("${list} = ${list}.filter(|$l| $l != $before.id)")
				} else if Schema.only_fields(rest) {
					Ok("${list} = ${list}.filter(|$e1| !(${Schema.mentions("$e1", rest, 1)}))")
				} else {
					Err("a link in a list inside a list cannot be unset; use Reject, Cascade or Ignore")
				}
			}
		}
	}

	# ------------------------------------------------------------ the script

	## The schema script: every `DEFINE FUNCTION`, then every `DEFINE ANALYZER`, then every `DEFINE TABLE`,
	## then every view, then every field, then the indexes, the row-check
	## events, the delete events and the access methods, so that no statement names a function or
	## a table defined later. A view that calls a function needs it defined
	## first (verified).
	script : List(Schema.Defined) -> Try(Str, Ql.Error)
	script = |all| Schema.script_lines(all).map_ok(|lines| Str.join_with(lines, "\n"))

	## The statements of `script`, one for each item, in its order.
	script_lines : List(Schema.Defined) -> Try(List(Str), Ql.Error)
	script_lines = |all| {
		defs = all.keep_oks(
			|Defined.(d)| match d {
				Table(t) => Ok(t)
				Function(_) | Read(_) | Access(_) | Analyzer(_) => Err(NotTable)
			},
		)
		registry = defs.map(|d| d.source)
		Types.check_registry(registry)?
		_ = all.map_try(
			|Defined.(d)| match d {
				Read(r) => Types.check_read(r.name, r.row_ty, registry)
				Table(_) | Function(_) | Access(_) | Analyzer(_) => Ok({})
			},
		)?
		match defs.join_map(|d| d.problems) {
			[first, ..] => return Err(first)
			[] => {}
		}
		translated = all.join_map(
			|Defined.(d)| match d {
				Function(found) => [found]
				Table(_) | Read(_) | Access(_) | Analyzer(_) => []
			},
		)
		accesses = all.join_map(
			|Defined.(d)| match d {
				Access(line) => [line]
				Table(_) | Read(_) | Function(_) | Analyzer(_) => []
			},
		).map_try(|line| line)?
		analyzers = all.join_map(
			|Defined.(d)| match d {
				Analyzer(a) => [a]
				Table(_) | Read(_) | Function(_) | Access(_) => []
			},
		)
		_ = defs.map_try(|d| Schema.analyzed(d, analyzers.map(|a| a.name)))?
		functions = Schema.functions(translated.map_try(|f| f)?.join(), registry)?
		parts = defs.map_try(|d| Schema.statements(d, registry))?
		Schema.no_cycle(defs, registry)?
		names = parts.join_map(|p| p.names)
		match names.find_first(|n| names.keep_if(|m| m == n).len() > 1) {
			Ok(n) => return Err(BadSchema("two generated statements are named `${n}`; rename a field or a check"))
			Err(_) => {}
		}
		Ok([functions, analyzers.map(|a| a.line), parts.join_map(|p| p.tables), parts.join_map(|p| p.views), parts.join_map(|p| p.fields), parts.join_map(|p| p.indexes), parts.join_map(|p| p.checks), parts.join_map(|p| p.deletes), accesses].join())
	}

	## A field of a table as `script` defines it: `table` and `path` as
	## the `DEFINE FIELD` names them, its type and its `DEFAULT`.
	FieldInfo : { table : Str, path : Str, ty : Str, default : Try(Str, [NoDefault]) }

	## The fields of the tables of a schema, with the values that
	## `field` prints, before they are printed.
	field_infos : List(Schema.Defined) -> Try(List(Schema.FieldInfo), Ql.Error)
	field_infos = |all| {
		defs = all.keep_oks(
			|Defined.(d)| match d {
				Table(t) => Ok(t)
				Function(_) | Read(_) | Access(_) | Analyzer(_) => Err(NotTable)
			},
		)
		registry = defs.map(|d| d.source)
		per_table = defs.map_try(
			|d| match d.source.kind {
				View(_) => Ok([])
				Normal | Relation(_) => {
					fields = Schema.key_def(Types.field_defs(d.source.name, d.source.row_ty, registry)?, d.rules)
					fields.map_try(|f| Schema.field_default(f, d.rules).map_ok(|given| { table: Ql.ident(d.source.name), path: f.path, ty: f.ty, default: given }))
				}
			},
		)?
		Ok(per_table.join())
	}

	## One step of a migration. `Remove` loses no row: an index, an
	## event, a function, an analyzer, an access or a view. `DropField` and
	## `DropTable` remove the data of the field or the table. `Fill` is a
	## new field on a table that has rows: `line` defines it, and the rows
	## get `value`, its `DEFAULT`. `Retype` is a field whose type changed
	## and does not take every old value: the rows convert to `to`, and
	## `value` is its `DEFAULT`.
	Step : [
		Define(Str),
		Remove(Str),
		DropField({ table : Str, path : Str }),
		DropTable(Str),
		Fill({ line : Str, table : Str, path : Str, value : Try(Str, [NoDefault]) }),
		Retype({ line : Str, table : Str, path : Str, from : Str, to : Str, value : Try(Str, [NoDefault]) }),
	]

	## The steps from the statements of the schema `old` to those of `new`:
	## what `old` has and `new` does not, from the last to the first, then
	## each statement of `new` that is new or changed, in its order. What
	## is on a table that `new` does not have goes with the table. Only a
	## statement whose text changed is in the steps.
	migration_steps : List(Str), List(Str), List(Schema.FieldInfo) -> List(Schema.Step)
	migration_steps = |old, new, fields| {
		before = old.map(Schema.entry)
		after = new.map(Schema.entry)
		same = |a, b| a.kind == b.kind and a.name == b.name and a.on == b.on
		gone = before.keep_if(|b| !after.any(|a| same(a, b)))
		dropped = gone.keep_if(|b| b.kind == "TABLE" and !Schema.is_view(b.line)).map(|b| b.name)
		removed = gone.rev().keep_oks(
			|b| match b.kind {
				_ if dropped.contains(b.on) => Err(OnDropped)
				"TABLE" if Schema.is_view(b.line) => Ok(Remove("REMOVE TABLE IF EXISTS ${b.name}"))
				"TABLE" => Ok(DropTable(b.name))
				"FIELD" => Ok(DropField({ table: b.on, path: b.name }))
				_ => Ok(Remove("REMOVE ${b.kind} IF EXISTS ${b.name}${if (b.on == "") "" else " ON ${b.on}"}"))
			},
		)
		existing = before.keep_if(|b| b.kind == "TABLE").map(|b| b.name)
		changed = after.keep_if(|a| !before.any(|b| same(a, b) and a.line == b.line)).map(
			|a| {
				line = a.line.drop_suffix(";")
				nested = a.name.contains(".") or a.name.contains("[") or a.name == "id"
				given = fields.find_first(|f| f.table == a.on and f.path == a.name).map_ok(|f| f.default) ?? Err(NoDefault)
				match (before.find_first(|b| same(a, b)), Schema.fill_value(a, fields)) {
					(Err(_), Ok(value)) if existing.contains(a.on) => Fill({ line, table: a.on, path: a.name, value })
					(Ok(b), _) if a.kind == "FIELD" and !nested and !Schema.widens(Schema.field_type(b.line), Schema.field_type(a.line)) => Retype({ line, table: a.on, path: a.name, from: Schema.field_type(b.line), to: Schema.field_type(a.line), value: given })
					_ => Define(line)
				}
			},
		)
		removed.concat(changed)
	}

	## The value that the rows of a table get for a new field: its
	## `DEFAULT` from `fields`, or `NoDefault`. A `DEFAULT` is not given
	## to the rows that are there (verified). A field in an object or a
	## list, an optional field and the key get no value.
	fill_value : Schema.Entry, List(Schema.FieldInfo) -> Try(Try(Str, [NoDefault]), [NoFill])
	fill_value = |e, fields| {
		nested = e.name.contains(".") or e.name.contains("[") or e.name == "id"
		match fields.find_first(|f| f.table == e.on and f.path == e.name) {
			Ok(f) if e.kind == "FIELD" and !nested and !f.ty.starts_with("option<") => Ok(f.default)
			_ => Err(NoFill)
		}
	}

	## The `TYPE` of a `DEFINE FIELD`: the words after `TYPE`, up to the
	## next clause. "" when it has none.
	field_type : Str -> Str
	field_type = |line| {
		words = Schema.words(line.drop_suffix(";"))
		clauses = ["DEFAULT", "VALUE", "ASSERT", "READONLY", "PERMISSIONS", "REFERENCE", "COMMENT", "FLEXIBLE", "MIGRATE"]
		match words.find_first_index(|w| w == "TYPE") {
			Ok(at) => {
				rest = words.drop_first(at + 1)
				Str.join_with(rest.take_first(rest.find_first_index(|w| clauses.contains(w)) ?? rest.len()), " ")
			}
			Err(_) => ""
		}
	}

	## The type without `option<..>`, and whether it had it.
	unwrapped : Str -> { optional : Bool, inner : Str }
	unwrapped = |ty| if (ty.starts_with("option<") and ty.ends_with(">")) { optional: Bool.True, inner: ty.drop_prefix("option<").drop_suffix(">") } else { optional: Bool.False, inner: ty }

	## The members of a union type, split at the top level only.
	members : Str -> List(Str)
	members = |ty| {
		depth = |s| s.to_utf8().fold(0.I64, |n, b| if (b == '<' or b == '{' or b == '[' or b == '(') n + 1 else if (b == '>' or b == '}' or b == ']' or b == ')') n - 1 else n)
		ty.split_on(" | ").fold(
			[],
			|acc, part| match acc.last() {
				Ok(open) if depth(open) > 0 => acc.drop_last(1).append("${open} | ${part}")
				_ => acc.append(part)
			},
		)
	}

	## Whether a field of type `new` takes every value of type `old`: the
	## same members and more, `option` kept or added, `any`, or `number`
	## for `int`, `float` and `decimal`.
	widens : Str, Str -> Bool
	widens = |old, new| {
		a = Schema.unwrapped(old)
		b = Schema.unwrapped(new)
		wide = Schema.members(b.inner)
		taken = |m| wide.contains(m) or (wide.contains("number") and ["int", "float", "decimal"].contains(m))
		old == new or b.inner == "any" or ((b.optional or !a.optional) and Schema.members(a.inner).all(taken))
	}

	## A statement of `script` by what it defines: `kind` is the word after
	## `DEFINE`, `on` the table of a field, an index or an event
	## (`DATABASE` for an access), or "" for the others.
	Entry : { kind : Str, name : Str, on : Str, line : Str }

	entry : Str -> Schema.Entry
	entry = |line| {
		words = Schema.words(line)
		word = |k| words.get(k) ?? ""
		kind = word(1)
		# `DEFINE FUNCTION OVERWRITE fn::name($a1: T) ..`
		name = if (kind == "FUNCTION") word(3).split_on("(").first() ?? "" else word(3)
		on = if (word(4) == "ON" and kind != "FUNCTION") word(5) else ""
		{ kind, name, on, line }
	}

	## A view is `DEFINE TABLE OVERWRITE name TYPE NORMAL AS SELECT ..`.
	is_view : Str -> Bool
	is_view = |line| Schema.words(line).drop_first(4).take_first(3) == ["TYPE", "NORMAL", "AS"]

	## The words of a line, a name in `⟨ ⟩` with a space in it one word.
	words : Str -> List(Str)
	words = |line| {
		count = |s, part| s.split_on(part).len() - 1
		line.split_on(" ").fold(
			[],
			|acc, word| match acc.last() {
				Ok(open) if count(open, "⟨") > count(open, "⟩") => acc.drop_last(1).append("${open} ${word}")
				_ => acc.append(word)
			},
		)
	}

	## One `DEFINE FUNCTION` for each name. A function that two
	## `Surreal.function` entries reach is written once; two different bodies
	## with one name are a `BadSchema`.
	functions : List(Schema.Function), Types.Registry -> Try(List(Str), Ql.Error)
	functions = |all, registry| {
		lines = all.map_try(|f| Schema.function_line(f, registry).map_ok(|line| { name: f.name, line }))?
		once = lines.fold_try(
			[],
			|kept, f| match kept.find_first(|k| k.name == f.name) {
				Ok(k) if k.line == f.line => Ok(kept)
				Ok(_) => Err(BadSchema("two database functions are named `fn::${f.name}` and have different bodies"))
				Err(_) => Ok(kept.append(f))
			},
		)?
		Ok(once.map(|f| f.line))
	}

	## `DEFINE FUNCTION OVERWRITE fn::name($a1: T1, ..) -> R { RETURN body };`
	function_line : Schema.Function, Types.Registry -> Try(Str, Ql.Error)
	function_line = |f, registry| {
		type_of = |ty| Types.inline_type(ty, registry).map_err(|e| Translate.within(e, f.name))
		params = f.params.map_with_index(|ty, k| (ty, k)).map_try(|(ty, k)| Ok("$a${(k + 1).to_str()}: ${type_of(ty)?}"))?
		Ok("DEFINE FUNCTION OVERWRITE fn::${f.name}(${Str.join_with(params, ", ")}) -> ${type_of(f.result)?} { RETURN ${f.body} };")
	}

	## Each full-text index of a table names an analyzer of the schema.
	analyzed : { source : Types.Source, rules : List(Schema.Rule), problems : List(Ql.Error) }, List(Str) -> Try({}, Ql.Error)
	analyzed = |d, names| {
		_ = d.rules.map_try(
			|r| match r {
				SearchIndex(i) => match i.analyzers.find_first(|name| !names.contains(name)) {
					Ok(name) => Err(BadSchema("the full-text index on `${d.source.name}.${i.path}` names the analyzer `${name}`, which the schema does not define: give its `define()` to `schema`"))
					Err(_) => Ok({})
				}
				_ => Ok({})
			},
		)?
		Ok({})
	}

	Parts : { tables : List(Str), views : List(Str), fields : List(Str), indexes : List(Str), checks : List(Str), deletes : List(Str), names : List(Str) }

	statements : { source : Types.Source, rules : List(Schema.Rule), problems : List(Ql.Error) }, Types.Registry -> Try(Schema.Parts, Ql.Error)
	statements = |d, registry| {
		src = d.source.name
		rules = Schema.place_checks(d.rules)
		match d.source.kind {
			View(select) => return Schema.view(src, select?, d.rules)
			Normal | Relation(_) => {}
		}
		on = "ON ${Ql.ident(src)}"
		defs = Schema.key_def(Types.field_defs(src, d.source.row_ty, registry)?, rules)
		paths = defs.map(|f| f.path)
		ends = if (Schema.is_edge(d.source)) ["in", "out"] else []
		_ = rules.map_try(|r| Schema.known(src, paths, ends, r))?
		links = Schema.sites(d.source)?.map_try(|s| Schema.policy_of(src, s, rules, registry))?
		_ = rules.map_try(|r| Schema.used(src, links, r))?
		fields = defs.map_try(|f| Schema.field(on, f, rules, links))?.keep_if(|line| line != "")
		indexes = rules.keep_oks(
			|r| match r {
				Index({ paths: on_paths, unique }) => {
					name = Schema.index_name(src, on_paths, unique)
					Ok({ name, line: "DEFINE INDEX OVERWRITE ${Ql.ident(name)} ${on} FIELDS ${Str.join_with(on_paths, ", ")}${if (unique) " UNIQUE" else ""};" })
				}
				_ => Err(NotIndex)
			},
		)
		searches = rules.keep_oks(
			|r| match r {
				SearchIndex(i) => {
					name = "${src}_${Schema.slug(i.path)}_${i.kind}"
					Ok({ name, line: "DEFINE INDEX OVERWRITE ${Ql.ident(name)} ${on} FIELDS ${i.path} ${i.spec};" })
				}
				_ => Err(NotIndex)
			},
		)
		nested = links.keep_if(|l| !Schema.is_native(l.site.hops) and l.policy != Ignore)
		link_indexes = nested.keep_oks(
			|l|
				if l.site.hops.any(Schema.is_arm) {
					# An arm of a union has no field definition to index (verified).
					Err(InArm)
				} else {
					name = "${src}_${Schema.slug(Schema.site_path(l.site.hops))}_link"
					Ok({ name, line: "DEFINE INDEX OVERWRITE ${Ql.ident(name)} ${on} FIELDS ${Schema.site_path(l.site.hops)};" })
				},
		)
		checks = rules.keep_oks(
			|r| match r {
				Check({ name: check_name, cond, .. }) => {
					name = Schema.check_name(src, check_name)
					Ok({ name, line: "DEFINE EVENT OVERWRITE ${Ql.ident(name)} ${on} WHEN $event IN ['CREATE', 'UPDATE'] THEN { IF !(${cond}) { THROW ${Ql.quote("${src}: ${check_name}")} } };" })
				}
				_ => Err(NotCheck)
			},
		)
		deletes = nested.map_try(|l| Schema.delete_event(src, l))?
		named = indexes.concat(searches).concat(link_indexes).concat(checks).concat(deletes)
		feeds = rules.keep_oks(
			|r| match r {
				Changefeed(nanos) => Ok(" CHANGEFEED ${Ql.duration(nanos)}")
				_ => Err(Other)
			},
		)
		feed = match feeds {
			[] => ""
			[one] => one
			_ => return Err(BadSchema("`${src}` has two changefeeds"))
		}
		permitted = Schema.permissions(
			"`${src}`",
			rules.keep_oks(
				|r| match r {
					Permit(p) => Ok(p)
					_ => Err(Other)
				},
			),
			Bool.True,
		)?
		table = match d.source.kind {
			Normal | View(_) => "DEFINE TABLE OVERWRITE ${Ql.ident(src)} SCHEMAFULL${feed}${permitted};"
			Relation({ from, to }) => "DEFINE TABLE OVERWRITE ${Ql.ident(src)} TYPE RELATION IN ${Ql.ident(from)} OUT ${Ql.ident(to)} ENFORCED SCHEMAFULL${feed}${permitted};"
		}
		Ok({
			tables: [table],
			views: [],
			fields,
			indexes: indexes.concat(searches).concat(link_indexes).map(|n| n.line),
			checks: checks.map(|n| n.line),
			deletes: deletes.map(|n| n.line),
			names: named.map(|n| n.name),
		})
	}

	## The field definitions with one for a text key that a clause gives
	## a default: `.default_by(|r| r.id, |_| Surreal.Rand.ulid())` is
	## `DEFINE FIELD id .. TYPE string DEFAULT rand::ulid()`, and a create
	## with no key gets that key (`Table.create_new`). A key with no
	## default has no definition, and SurrealDB makes a random key.
	key_def : List(Types.FieldDef), List(Schema.Rule) -> List(Types.FieldDef)
	key_def = |defs, rules| {
		keyed = rules.any(
			|r| match r {
				Default(a) => a.path == "id"
				_ => Bool.False
			},
		)
		if keyed and !defs.any(|f| f.path == "id") {
			defs.prepend({ path: "id", top: "id", ty: "string", asserts: [], defaults: [] })
		} else {
			defs
		}
	}

	## A view: `DEFINE TABLE .. AS SELECT ..`. SurrealDB fills it from its
	## query, so it has no field definitions, and it takes no rule: a view is
	## read-only.
	view : Str, Str, List(Schema.Rule) -> Try(Schema.Parts, Ql.Error)
	view = |src, select, rules|
		if rules.is_empty() {
			Ok({ tables: [], views: ["DEFINE TABLE OVERWRITE ${Ql.ident(src)} TYPE NORMAL AS ${select};"], fields: [], indexes: [], checks: [], deletes: [], names: [] })
		} else {
			Err(BadSchema("`${src}` is a view, and a view is read-only, so it takes no rule"))
		}

	Link : { site : Schema.Site, table : Str, policy : Schema.Policy }

	## The policy of one site: `on_delete_at` for its path, else `on_delete`
	## for its target table, else `Reject`.
	policy_of : Str, Schema.Site, List(Schema.Rule), Types.Registry -> Try(Schema.Link, Ql.Error)
	policy_of = |src, site, rules, registry| {
		table = Types.table_for(registry, site.target)?
		path = Schema.site_path(site.hops)
		at_path = rules.keep_oks(
			|r| match r {
				OnDeleteAt(p) if p.path == path => Ok(p.policy)
				_ => Err(Other)
			},
		)
		for_table = rules.keep_oks(
			|r| match r {
				OnDelete(p) if p.table == table => Ok(p.policy)
				_ => Err(Other)
			},
		)
		policy = match (at_path.last(), for_table.last()) {
			(Ok(p), _) => p
			(_, Ok(p)) => p
			_ => Reject
		}
		site_name = "`${src}.${Schema.spell(site.hops)}`"
		if policy == Unset {
			if Schema.is_native(site.hops) {
				if site.hops.len() == 1 and !site.optional {
					return Err(BadSchema("${site_name} is required, so a delete cannot unset it; make it optional (`?:`) or use Reject, Cascade or Ignore"))
				}
			} else {
				match Schema.unset(site) {
					Ok(_) => {}
					Err(why) => return Err(BadSchema("${site_name}: ${why}"))
				}
			}
		}
		Ok({ site, table, policy })
	}

	## A clause's path must be a field the table defines.
	known : Str, List(Str), List(Str), Schema.Rule -> Try({}, Ql.Error)
	known = |src, paths, ends, rule| {
		path = match rule {
			Assert(a) => a.path
			Default(a) => a.path
			Computed(a) => a.path
			Readonly(p) => p
			Comment(a) => a.path
			PermitField(p) => p.path
			Index(i) => return i.paths.map_try(|p| Schema.known_index(src, paths.concat(ends), p)).map_ok(|_| {})
			SearchIndex(i) => return Schema.known_index(src, paths, i.path)
			Check(_) | OnDelete(_) | OnDeleteAt(_) | Changefeed(_) | Permit(_) => return Ok({})
		}
		if paths.contains(path) {
			Ok({})
		} else {
			Err(BadSchema("`${src}.${path}` has no field definition to put this on; the record key and an edge's ends are SurrealDB's own"))
		}
	}

	known_index : Str, List(Str), Str -> Try({}, Ql.Error)
	known_index = |src, paths, path|
		if paths.contains(path) or paths.contains("${path}[*]") or paths.any(|p| p.starts_with("${path}[*].")) {
			Ok({})
		} else {
			Err(BadSchema("`${src}.${path}` has no field definition to index"))
		}

	## A delete clause must name a link of the table.
	used : Str, List(Schema.Link), Schema.Rule -> Try({}, Ql.Error)
	used = |src, links, rule| match rule {
		OnDelete({ table, .. }) =>
			if (links.any(|l| l.table == table)) Ok({}) else Err(BadSchema("no link in `${src}` points at table `${table}`"))
		OnDeleteAt({ path, .. }) =>
			if (links.any(|l| Schema.site_path(l.site.hops) == path)) Ok({}) else Err(BadSchema("`${src}.${path}` is not a link"))
		_ => Ok({})
	}

	## The `DEFAULT` of a field: the `??` default of the type, or a
	## `default` or `default_by` clause. Two are a `BadSchema`.
	field_default : Types.FieldDef, List(Schema.Rule) -> Try(Try(Str, [NoDefault]), Ql.Error)
	field_default = |def, rules| {
		typed = def.defaults.map_try(|d| Translate.captured(d.ty, d.value).map_ok(Ql.literal))?
		clauses = rules.keep_oks(
			|r| match r {
				Default(a) if a.path == def.path => Ok(a.value)
				_ => Err(Other)
			},
		)
		match typed.concat(clauses) {
			[] => Ok(Err(NoDefault))
			[one] => Ok(Ok(one))
			_ => Err(BadSchema("`${def.path}` has two defaults"))
		}
	}

	## One `DEFINE FIELD`, with what the clauses add to it.
	field : Str, Types.FieldDef, List(Schema.Rule), List(Schema.Link) -> Try(Str, Ql.Error)
	field = |on, def, rules, links| {
		mine = |pick| rules.keep_oks(pick)
		asserts = def.asserts.concat(
			mine(
				|r| match r {
					Assert(a) if a.path == def.path => Ok(a.cond)
					_ => Err(Other)
				},
			),
		)
		at_most_one = |values, what| match values {
			[] => Ok("")
			[one] => Ok(one)
			_ => Err(BadSchema("`${def.path}` has two ${what}"))
		}
		default_part = match Schema.field_default(def, rules)? {
			Ok(value) => " DEFAULT ${value}"
			Err(NoDefault) => ""
		}
		value_part = at_most_one(
			mine(
				|r| match r {
					Computed(a) if a.path == def.path => Ok(" VALUE ${a.expr}")
					_ => Err(Other)
				},
			),
			"computed values",
		)?
		readonly_part = if (rules.any(|r| r == Readonly(def.path))) " READONLY" else ""
		reference_part = at_most_one(
			links.keep_oks(|l| if (Schema.is_native(l.site.hops) and Schema.site_path(l.site.hops) == def.path) Ok(" REFERENCE ON DELETE ${Schema.keyword(l.policy)}") else Err(Other)),
			"links",
		)?
		assert_part = match asserts {
			[] => ""
			[one] => " ASSERT ${one}"
			many => " ASSERT ${Str.join_with(many.map(|a| "(${a})"), " AND ")}"
		}
		permission_part = Schema.permissions(
			"`${def.path}`",
			mine(
				|r| match r {
					PermitField(p) if p.path == def.path => Ok({ actions: p.actions, grant: p.grant })
					_ => Err(Other)
				},
			),
			Bool.False,
		)?
		comment_part = at_most_one(
			mine(
				|r| match r {
					Comment(a) if a.path == def.path => Ok(" COMMENT ${Ql.quote(a.text)}")
					_ => Err(Other)
				},
			),
			"comments",
		)?
		type_part = if (def.ty == "") "" else " TYPE ${def.ty}"
		clauses = "${default_part}${value_part}${readonly_part}${reference_part}${assert_part}${permission_part}${comment_part}"
		# A member of a literal element type is defined by that type, so with no clause it has no line.
		if def.ty == "" and clauses == "" {
			return Ok("")
		}
		Ok("DEFINE FIELD OVERWRITE ${def.path} ${on}${type_part}${default_part}${value_part}${readonly_part}${reference_part}${assert_part}${permission_part}${comment_part};")
	}

	keyword : Schema.Policy -> Str
	keyword = |policy| match policy {
		Reject => "REJECT"
		Unset => "UNSET"
		Cascade => "CASCADE"
		Ignore => "IGNORE"
	}

	## The event on the target table that does a nested link's policy.
	delete_event : Str, Schema.Link -> Try({ name : Str, line : Str }, Ql.Error)
	delete_event = |src, link| {
		hops = link.site.hops
		name = "${src}_${Str.join_with(hops.keep_oks(Schema.hop_slug), "_")}_on_delete"
		cond = Schema.mentions("", hops, 0)
		body = match link.policy {
			Reject => Ok("IF (SELECT VALUE id FROM ${Ql.ident(src)} WHERE ${cond} LIMIT 1) != [] { THROW <string>$before.id + ${Ql.quote(" is referenced by ${src}.${Schema.spell(hops)}")} }")
			Cascade => Ok("DELETE ${Ql.ident(src)} WHERE ${cond}")
			Unset => match Schema.unset(link.site) {
				Ok(set) => Ok("UPDATE ${Ql.ident(src)} SET ${set} WHERE ${cond}")
				Err(why) => Err(BadSchema(why))
			}
			Ignore => Err(BadSchema("an ignored link has no event"))
		}?
		Ok({ name, line: "DEFINE EVENT OVERWRITE ${Ql.ident(name)} ON ${Ql.ident(link.table)} WHEN $event = 'DELETE' THEN { ${body} };" })
	}

	hop_slug : Schema.Hop -> Try(Str, [Skip])
	hop_slug = |hop| match hop {
		Field(name) => Ok(Schema.slug(name))
		Arm(tag) => Ok(Schema.slug(tag))
		Item(i) => Ok(i.to_str())
		Each => Err(Skip)
	}

	## A name part made of letters, digits and `_`: `items[*].qty` is `items_qty`.
	slug : Str -> Str
	slug = |text| {
		bytes = text.to_utf8().fold(
			[],
			|out, b|
				if (b >= 97 and b <= 122) or (b >= 65 and b <= 90) or (b >= 48 and b <= 57) {
					out.append(b)
				} else if out.last() == Ok(95) or out.is_empty() {
					out
				} else {
					out.append(95)
				},
		)
		trimmed = if (bytes.last() == Ok(95)) bytes.drop_last(1) else bytes
		match Str.from_utf8(trimmed) {
			Ok(s) => s
			Err(_) => crash "ASCII letters, digits and `_` are valid UTF-8"
		}
	}

	## The name of the index of `Def.unique` or `Def.index` on these paths.
	index_name : Str, List(Str), Bool -> Str
	index_name = |src, paths, unique| "${src}_${Str.join_with(paths.map(Schema.slug), "_")}${if (unique) "_unique" else "_index"}"

	## The name of the event of `Def.check`.
	check_name : Str, Str -> Str
	check_name = |src, name| "${src}_check_${Schema.slug(name)}"

	# ------------------------------------------------- the server's errors

	## A unique index that the schema defines: its name, table and paths.
	Known : { index : Str, table : Str, fields : List(Str) }

	## The unique indexes of the definitions, which `Session.knowing`
	## keeps so that a violation of one names its fields.
	unique_indexes : List(Schema.Defined) -> List(Schema.Known)
	unique_indexes = |all| all.join_map(
		|Defined.(d)| match d {
			Table(t) =>
				t.rules.keep_oks(
					|r| match r {
						Index({ paths, unique: Bool.True }) => Ok({ index: Schema.index_name(t.source.name, paths, Bool.True), table: t.source.name, fields: paths })
						_ => Err(NotUnique)
					},
				)
			Function(_) | Read(_) | Access(_) | Analyzer(_) => []
		},
	)

	## An error of the kind `Internal`, read from its message where it has
	## a form that SurrealDB 3.3.4 writes for a constraint (verified):
	##
	## | Message | Tag |
	## | --- | --- |
	## | ``Database index `i` already contains v, with record `r` `` | `Unique` for a known index, else `Index` |
	## | ``Found v for field `f`, with record `r`, but field must conform to: c`` | `Assert` |
	## | ``Couldn't coerce value for field `f` of `r`: Expected `t` but found `v` `` | `Type` |
	## | ``Cannot delete `r` as it is referenced by `b` with an ON DELETE REJECT clause`` | `Referenced` (a root link) |
	## | ``Error while processing event e: An error occurred: t`` | `Check` when `e` and `t` are those of a `Def.check`; `Referenced` when `e` is the delete event of a nested link; else `Thrown` |
	## | ``Error while processing event e: m`` | What `m` is |
	##
	## Any other message is `Other`. A record id is as the server writes
	## it, `vet:a` or `` `my t`:k ``; the table is the part before `:`.
	violation : Str, Str, List(Schema.Known) -> Ql.ServerError
	violation = |message, text, indexes| {
		other = Ql.ServerError.Other({ kind: "Internal", message })
		if text.starts_with("Database index `") {
			match text.drop_prefix("Database index `").split_first("` already contains ") {
				Ok(i) =>
					match i.after.split_last(", with record `") {
						Ok(r) if r.after.ends_with("`") => {
							record = r.after.drop_suffix("`")
							match indexes.find_first(|k| k.index == i.before) {
								Ok(k) => Unique({ table: k.table, index: k.index, fields: k.fields, value: r.before, record, message })
								Err(_) => Index({ index: i.before, value: r.before, record, message })
							}
						}
						_ => other
					}
				Err(_) => other
			}
		} else if text.starts_with("Found ") {
			match text.split_first("`, but field must conform to: ") {
				Ok(c) =>
					match c.before.split_last("`, with record `") {
						Ok(r) =>
							match r.before.drop_prefix("Found ").split_last(" for field `") {
								Ok(f) => Assert({ table: Schema.table_of(r.after), field: f.after, record: r.after, value: f.before, condition: c.after, message })
								Err(_) => other
							}
						Err(_) => other
					}
				Err(_) => other
			}
		} else if text.starts_with("Couldn't coerce value for field `") {
			match (text.drop_prefix("Couldn't coerce value for field `").split_first("` of `"), text.split_first("`: Expected `")) {
				(Ok(f), Ok(e)) =>
					match (f.after.split_first("`: Expected `"), e.after.split_first("` but found `")) {
						(Ok(r), Ok(t)) if t.after.ends_with("`") => Type({ table: Schema.table_of(r.before), field: f.before, record: r.before, expected: t.before, found: t.after.drop_suffix("`"), message })
						_ => other
					}
				_ => other
			}
		} else if text.starts_with("Cannot delete `") and text.ends_with("` with an ON DELETE REJECT clause") {
			match text.drop_prefix("Cannot delete `").drop_suffix("` with an ON DELETE REJECT clause").split_first("` as it is referenced by `") {
				Ok(r) => Referenced({ record: r.before, by: r.after, message })
				Err(_) => other
			}
		} else if text.starts_with("Error while processing event ") {
			match text.drop_prefix("Error while processing event ").split_first(": ") {
				Ok(e) =>
					match e.after.split_first("An error occurred: ") {
						Ok(t) if t.before == "" => Schema.thrown_in(e.before, t.after, message)
						_ => Schema.violation(message, e.after, indexes)
					}
				Err(_) => other
			}
		} else {
			other
		}
	}

	## The text that an event threw: a `Def.check` throws `table: name`
	## from the event `table_check_<name>`, and the delete event of a
	## nested link `record is referenced by table.path`.
	thrown_in : Str, Str, Str -> Ql.ServerError
	thrown_in = |event, thrown, message| {
		parts = thrown.split_on(": ")
		splits = parts.map_with_index(|_, k| k).drop_first(1).map(|k| { table: Str.join_with(parts.take_first(k), ": "), name: Str.join_with(parts.drop_first(k), ": ") })
		match splits.find_first(|s| Schema.check_name(s.table, s.name) == event) {
			Ok(s) => Check({ table: s.table, name: s.name, message })
			Err(_) =>
				match thrown.split_first(" is referenced by ") {
					Ok(r) if event.ends_with("_on_delete") => Referenced({ record: r.before, by: r.after, message })
					_ => Thrown({ text: thrown, message })
				}
		}
	}

	## The table of a record id as the server writes it: `vet` of `vet:a`,
	## `my t` of `` `my t`:k ``.
	table_of : Str -> Str
	table_of = |record|
		if record.starts_with("`") {
			match record.drop_prefix("`").split_first("`") {
				Ok(t) => t.before
				Err(_) => record
			}
		} else {
			match record.split_first(":") {
				Ok(t) => t.before
				Err(_) => record
			}
		}

	# ------------------------------------------------------------ cycles

	## Rows are written one at a time and each link must exist, so a cycle of
	## required root links can never be filled.
	no_cycle : List({ source : Types.Source, rules : List(Schema.Rule), problems : List(Ql.Error) }), Types.Registry -> Try({}, Ql.Error)
	no_cycle = |defs, registry| {
		edges = defs.map_try(
			|d| {
				required = Schema.sites(d.source)?.keep_if(|s| s.hops.len() == 1 and !s.optional)
				required.map_try(|s| Ok({ from: d.source.name, field: Schema.spell(s.hops), to: Types.table_for(registry, s.target)? }))
			},
		)?.join()
		_ = edges.map_try(|e| Schema.follow(edges, [], e.from))?
		Ok({})
	}

	Edge : { from : Str, field : Str, to : Str }

	follow : List(Schema.Edge), List(Schema.Edge), Str -> Try({}, Ql.Error)
	follow = |edges, trail, table| match trail.find_first_index(|e| e.from == table) {
		Ok(start) => {
			loop = trail.drop_first(start)
			steps = Str.join_with(loop.map(|e| "${e.from}.${e.field}"), " -> ")
			Err(BadSchema("required links form a cycle (${steps} -> ${table}), so no row of it can be written first; make one of them optional (`?:`)"))
		}
		Err(_) => {
			_ = edges.keep_if(|e| e.from == table).map_try(|e| Schema.follow(edges, trail.append(e), e.to))?
			Ok({})
		}
	}
}

# Tests that need no table. The rest are in `SchemaTest.roc`.

expect Schema.slug("items[*].qty") == "items_qty"
expect Schema.slug("⟨x y⟩") == "x_y"
expect Schema.slug("total matches items") == "total_matches_items"
expect Schema.mentions("", [Field("customer")], 0) == "customer = $before.id"
expect Schema.mentions("", [Field("wishlist"), Each], 0) == "$before.id IN wishlist"
expect Schema.mentions("", [Field("gift"), Field("to")], 0) == "gift.to = $before.id"
expect Schema.mentions("", [Field("items"), Each, Field("product")], 0) == "$before.id IN items[*].product"
expect Schema.mentions("", [Field("items"), Each, Field("dose"), Field("by")], 0) == "$before.id IN items[*].dose.by"
expect Schema.mentions("", [Field("items"), Each, Arm("Given"), Field("by")], 0) == "items.any(|$e1| ($e1.kind = 'Given' AND $e1.by = $before.id))"
expect Schema.mentions("", [Field("payment"), Arm("Invoice"), Field("contact")], 0) == "(payment.kind = 'Invoice' AND payment.contact = $before.id)"
expect Schema.mentions("", [Field("via"), Arm("Agent"), Field("value"), Item(1)], 0) == "(via.kind = 'Agent' AND via.value[1] = $before.id)"
expect Schema.mentions("", [Field("xs"), Each, Each], 0) == "xs.any(|$e1| $before.id IN $e1)"
expect Schema.unset({ hops: [Field("gift"), Field("to")], target: Str, optional: Bool.True }) == Ok("gift.to = NONE")
expect Schema.unset({ hops: [Field("gift"), Field("to")], target: Str, optional: Bool.False }).is_err()
expect Schema.unset({ hops: [Field("gift"), Field("tags"), Each], target: Str, optional: Bool.False }) == Ok("gift.tags = gift.tags.filter(|$l| $l != $before.id)")
expect Schema.unset({ hops: [Field("items"), Each, Field("product")], target: Str, optional: Bool.False }) == Ok("items = items.filter(|$e1| !($e1.product = $before.id))")
expect Schema.unset({ hops: [Field("payment"), Arm("Invoice"), Field("contact")], target: Str, optional: Bool.False }).is_err()
expect Schema.unset({ hops: [Field("xs"), Each, Each], target: Str, optional: Bool.False }).is_err()
