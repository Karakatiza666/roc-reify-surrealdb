# The clause translator: a reified Roc function in, a SurrealQL expression out.
#
# A clause is a Roc function over a row. The translator reads the root row of
# its `Code.Graph` as a tree and evaluates the tree with each parameter bound
# to what it stands for in SurrealQL. The row, a linked row, an element of a
# list and a union arm are places in a document, so a field read off one is a
# path, and a list operation with a closure is a SurrealQL closure over `$vN`.
import Ql
import Types
import Encode

Translate :: {}.{

	## What a value in a reified function stands for.
	##
	## `Row` is a record at a place: `Doc` is the record a statement is over
	## (`""` for the row itself, `$after`, `$this`), with the name of its
	## table for the row a statement reads (`table_row`), `Ref` is a record
	## id that a read traverses (`customer` after `Link.get`, an edge `$v1`),
	## with the type of the record it points at, and `Obj` is an object inside a
	## record. `edge` says the record is a relation, whose `from` and `to` are
	## SurrealDB's `in` and `out`. `Expr` is a value that needs no parentheses
	## around it as an operand, and `Infix` one that does. `Column` is
	## `rows.map(f)` over a `Group`: the expression `f` reads, that each
	## aggregate writes for itself. `Moment` is the text of a datetime, and
	## holds the datetime expression. `Function` is a database function made
	## with `Surreal.db_fn`: its name, and the row of its Roc body. `Table`
	## is a table of `Surreal.table`, `relation` or `view`: its name,
	## whether it is an edge table, and the tables at the ends of an edge
	## table (`?` when not known).
	Binding := [
		Row({ at : Str, of : [Doc([Of(Str), Unnamed]), Ref(Code.Ty), Obj], edge : Bool }),
		WithEdges(Binding, List(Binding)),
		ListOf({ at : Str, items : Items }),
		Union({ at : Str, variants : List({ name : Str, payloads : List(Code.Ty) }) }),
		Maybe(Str),
		Params,
		Group(Binding),
		Column(Str),
		Moment(Str),
		Expr(Str),
		Infix(Str),
		Fields(List({ name : Str, binding : Binding })),
		Function({ name : Str, row : U32 }),
		Table({ name : Str, edge : Bool, ends : Ends }),
	]

	## The tables at the ends of the edges of an edge table, `in` and
	## `out`. `?` is any table: `->?`.
	Ends : { from : Str, to : Str }

	## What the elements of a list are: values at a path, values that the
	## clause made (`map`, a list literal), whose text is whole already, or
	## record ids that a read traverses. `edge` says the records are edges,
	## and `row` is their type when the list has one: the whole list is then
	## the fields of the type of each record, `list.{ id: record::id(id), .. }`.
	## `graph` says the list is a graph path, which a filter and a hop
	## continue: `Edges` for the edges of an edge table with its ends,
	## `Nodes` for the records at the ends of edges, `Off` for any other list.
	Items : [Values, Made, Records({ edge : Bool, row : [Typed(Code.Ty), Untyped], graph : Graph })]

	## Whether a list of records is a graph path (see `Items`).
	Graph : [Edges(Ends), Nodes, Off]

	## One step of a field path: `items[*].qty` is `Field("items")`, `Each`,
	## `Field("qty")`.
	Step := [Field(Str), Each].{
		is_eq : _
	}

	## A `Prim` of a description: the call of a primitive.
	Call : { owner : Str, method : Str, id : Code.PrimId, evidence : List(Code.Evidence) }

	## What the call of a primitive is in SurrealQL. The translator looks a
	## call up by its `id` (`Code.prim` of the definition), and never by its
	## owner and method, which name it in a refusal only: a module's own
	## `Bool` with a `not` has another id, so its `not` is not `!`.
	##
	## `Builtin` is a builtin of Roc (`Translate.builtins`), under the name
	## the translator's rules for builtins use. The ids of `Surreal`'s cut
	## come from `Surreal.library`, as this module cannot import `Surreal`:
	## `Function` is one SurrealQL function of the same arguments, which gives
	## a new value on every call when `random` is set, `Aggregate` one over a
	## list or a group's column (`FloatAggregate` casts each value to a float
	## first), and `Operator` an operator between two
	## operands. `Variable` is a value of the session that the statement
	## reads, such as `$auth.id`, whatever the arguments: a table that
	## types it. The rest are each one function of the cut. `Render` is an
	## extension's (`Translate.extension`): it takes the SurrealQL of each
	## argument and the evidence of the call, and gives the SurrealQL of the
	## call, or why it has none.
	Form : [
		Builtin({ owner : Str, method : Str }),
		Function({ surql : Str, random : Bool }),
		Aggregate(Str),
		FloatAggregate(Str),
		Operator(Str),
		Percentile,
		Uuid,
		TimeGroup,
		LinkGet,
		LinkId,
		IdEq,
		IdKey,
		IdTable,
		DatetimeOrder,
		SeriesOf,
		TimeOf,
		CallDbFn,
		TableOf,
		RelationOf,
		Rows,
		EdgesOf(Str),
		RecordOf,
		Variable(Str),
		Render({ args : List(Str), evidence : List(Code.Evidence) } -> Try(Str, Str)),
	]

	## Forms by the ids of the primitives they are for. `Surreal.library` is
	## the one of `Surreal`'s cut, and an app or a glue package makes one
	## for the functions of its own types with `Translate.extension`.
	Extension := { prims : List({ prim : Code.PrimId, form : Form }) }

	## An extension of the functions it renders, each by its id.
	extension : { prims : List({ prim : Code.PrimId, render : { args : List(Str), evidence : List(Code.Evidence) } -> Try(Str, Str) }) } -> Extension
	extension = |entries| Extension.({ prims: entries.prims.map(|entry| { prim: entry.prim, form: Render(entry.render) }) })

	## An extension of any forms: the one `Surreal.library` makes.
	forms : List({ prim : Code.PrimId, form : Form }) -> Extension
	forms = |entries| Extension.({ prims: entries })

	## The form of the primitive `id`: a builtin's, or the one the first
	## extension that names `id` gives it.
	form : Code.PrimId, List(Extension) -> Try(Form, [NotFound])
	form = |id, extensions| match Translate.builtins.get(id) {
		Ok(builtin) => Ok(Builtin(builtin))
		Err(KeyNotFound) => match extensions.join_map(|e| e.prims).find_first(|entry| entry.prim == id) {
			Ok(entry) => Ok(entry.form)
			Err(_) => Err(NotFound)
		}
	}

	## Whether the primitive `id` is `==` of a builtin or of an `Id`.
	is_equality : Code.PrimId, Env -> Bool
	is_equality = |id, env| match Translate.form(id, env.extensions) {
		Ok(Builtin({ method: "is_eq", .. })) | Ok(IdEq) => Bool.True
		_ => Bool.False
	}

	## The builtins a clause may call, by the ids of their definitions, with
	## the names `Translate.builtin` reads them by. A method a type of these
	## does not have is not listed.
	builtins : Dict(Code.PrimId, { owner : Str, method : Str })
	builtins = Dict.from_list(
		List.join(
			[
				Translate.named("Num.I8", [("plus", Code.prim(I8.plus)), ("minus", Code.prim(I8.minus)), ("times", Code.prim(I8.times)), ("div_by", Code.prim(I8.div_by)), ("div_trunc_by", Code.prim(I8.div_trunc_by)), ("rem_by", Code.prim(I8.rem_by)), ("is_lt", Code.prim(I8.is_lt)), ("is_gt", Code.prim(I8.is_gt)), ("is_lte", Code.prim(I8.is_lte)), ("is_gte", Code.prim(I8.is_gte)), ("is_eq", Code.prim(I8.is_eq)), ("order_relative_to", Code.prim(I8.order_relative_to)), ("negate", Code.prim(I8.negate)), ("abs", Code.prim(I8.abs)), ("to_dec", Code.prim(I8.to_dec)), ("to_f64", Code.prim(I8.to_f64)), ("to_f32", Code.prim(I8.to_f32)), ("to_i16", Code.prim(I8.to_i16)), ("to_i32", Code.prim(I8.to_i32)), ("to_i64", Code.prim(I8.to_i64)), ("to_i128", Code.prim(I8.to_i128)), ("from_str", Code.prim(I8.from_str)), ("is_zero", Code.prim(I8.is_zero)), ("is_negative", Code.prim(I8.is_negative)), ("is_positive", Code.prim(I8.is_positive)), ("is_even", Code.prim(I8.is_even)), ("is_odd", Code.prim(I8.is_odd)), ("to_str", Code.prim(I8.to_str)), ("max", Code.prim(I8.max)), ("min", Code.prim(I8.min)), ("pow", Code.prim(I8.pow)), ("mod_by", Code.prim(I8.mod_by)), ("is_multiple_of", Code.prim(I8.is_multiple_of)), ("to_i8_try", Code.prim(I8.to_i8_try)), ("to_u128_try", Code.prim(I8.to_u128_try)), ("to_u16_try", Code.prim(I8.to_u16_try)), ("to_u32_try", Code.prim(I8.to_u32_try)), ("to_u64_try", Code.prim(I8.to_u64_try)), ("to_u8_try", Code.prim(I8.to_u8_try))]),
				Translate.named("Num.U8", [("plus", Code.prim(U8.plus)), ("minus", Code.prim(U8.minus)), ("times", Code.prim(U8.times)), ("div_by", Code.prim(U8.div_by)), ("div_trunc_by", Code.prim(U8.div_trunc_by)), ("rem_by", Code.prim(U8.rem_by)), ("is_lt", Code.prim(U8.is_lt)), ("is_gt", Code.prim(U8.is_gt)), ("is_lte", Code.prim(U8.is_lte)), ("is_gte", Code.prim(U8.is_gte)), ("is_eq", Code.prim(U8.is_eq)), ("order_relative_to", Code.prim(U8.order_relative_to)), ("to_dec", Code.prim(U8.to_dec)), ("to_f64", Code.prim(U8.to_f64)), ("to_f32", Code.prim(U8.to_f32)), ("to_i16", Code.prim(U8.to_i16)), ("to_i32", Code.prim(U8.to_i32)), ("to_i64", Code.prim(U8.to_i64)), ("to_i128", Code.prim(U8.to_i128)), ("to_u16", Code.prim(U8.to_u16)), ("to_u32", Code.prim(U8.to_u32)), ("to_u64", Code.prim(U8.to_u64)), ("to_u128", Code.prim(U8.to_u128)), ("from_str", Code.prim(U8.from_str)), ("is_zero", Code.prim(U8.is_zero)), ("is_even", Code.prim(U8.is_even)), ("is_odd", Code.prim(U8.is_odd)), ("to_str", Code.prim(U8.to_str)), ("max", Code.prim(U8.max)), ("min", Code.prim(U8.min)), ("pow", Code.prim(U8.pow)), ("mod_by", Code.prim(U8.mod_by)), ("is_multiple_of", Code.prim(U8.is_multiple_of)), ("to_i8_try", Code.prim(U8.to_i8_try)), ("to_u8_try", Code.prim(U8.to_u8_try))]),
				Translate.named("Num.I16", [("plus", Code.prim(I16.plus)), ("minus", Code.prim(I16.minus)), ("times", Code.prim(I16.times)), ("div_by", Code.prim(I16.div_by)), ("div_trunc_by", Code.prim(I16.div_trunc_by)), ("rem_by", Code.prim(I16.rem_by)), ("is_lt", Code.prim(I16.is_lt)), ("is_gt", Code.prim(I16.is_gt)), ("is_lte", Code.prim(I16.is_lte)), ("is_gte", Code.prim(I16.is_gte)), ("is_eq", Code.prim(I16.is_eq)), ("order_relative_to", Code.prim(I16.order_relative_to)), ("negate", Code.prim(I16.negate)), ("abs", Code.prim(I16.abs)), ("to_dec", Code.prim(I16.to_dec)), ("to_f64", Code.prim(I16.to_f64)), ("to_f32", Code.prim(I16.to_f32)), ("to_i16", Code.prim(I16.to_i16)), ("to_i32", Code.prim(I16.to_i32)), ("to_i64", Code.prim(I16.to_i64)), ("to_i128", Code.prim(I16.to_i128)), ("from_str", Code.prim(I16.from_str)), ("is_zero", Code.prim(I16.is_zero)), ("is_negative", Code.prim(I16.is_negative)), ("is_positive", Code.prim(I16.is_positive)), ("is_even", Code.prim(I16.is_even)), ("is_odd", Code.prim(I16.is_odd)), ("to_str", Code.prim(I16.to_str)), ("max", Code.prim(I16.max)), ("min", Code.prim(I16.min)), ("pow", Code.prim(I16.pow)), ("mod_by", Code.prim(I16.mod_by)), ("is_multiple_of", Code.prim(I16.is_multiple_of)), ("to_i16_try", Code.prim(I16.to_i16_try)), ("to_i8_try", Code.prim(I16.to_i8_try)), ("to_u128_try", Code.prim(I16.to_u128_try)), ("to_u16_try", Code.prim(I16.to_u16_try)), ("to_u32_try", Code.prim(I16.to_u32_try)), ("to_u64_try", Code.prim(I16.to_u64_try)), ("to_u8_try", Code.prim(I16.to_u8_try))]),
				Translate.named("Num.U16", [("plus", Code.prim(U16.plus)), ("minus", Code.prim(U16.minus)), ("times", Code.prim(U16.times)), ("div_by", Code.prim(U16.div_by)), ("div_trunc_by", Code.prim(U16.div_trunc_by)), ("rem_by", Code.prim(U16.rem_by)), ("is_lt", Code.prim(U16.is_lt)), ("is_gt", Code.prim(U16.is_gt)), ("is_lte", Code.prim(U16.is_lte)), ("is_gte", Code.prim(U16.is_gte)), ("is_eq", Code.prim(U16.is_eq)), ("order_relative_to", Code.prim(U16.order_relative_to)), ("to_dec", Code.prim(U16.to_dec)), ("to_f64", Code.prim(U16.to_f64)), ("to_f32", Code.prim(U16.to_f32)), ("to_i32", Code.prim(U16.to_i32)), ("to_i64", Code.prim(U16.to_i64)), ("to_i128", Code.prim(U16.to_i128)), ("to_u16", Code.prim(U16.to_u16)), ("to_u32", Code.prim(U16.to_u32)), ("to_u64", Code.prim(U16.to_u64)), ("to_u128", Code.prim(U16.to_u128)), ("from_str", Code.prim(U16.from_str)), ("is_zero", Code.prim(U16.is_zero)), ("is_even", Code.prim(U16.is_even)), ("is_odd", Code.prim(U16.is_odd)), ("to_str", Code.prim(U16.to_str)), ("max", Code.prim(U16.max)), ("min", Code.prim(U16.min)), ("pow", Code.prim(U16.pow)), ("mod_by", Code.prim(U16.mod_by)), ("is_multiple_of", Code.prim(U16.is_multiple_of)), ("to_i16_try", Code.prim(U16.to_i16_try)), ("to_i8_try", Code.prim(U16.to_i8_try)), ("to_u16_try", Code.prim(U16.to_u16_try)), ("to_u8_try", Code.prim(U16.to_u8_try))]),
				Translate.named("Num.I32", [("plus", Code.prim(I32.plus)), ("minus", Code.prim(I32.minus)), ("times", Code.prim(I32.times)), ("div_by", Code.prim(I32.div_by)), ("div_trunc_by", Code.prim(I32.div_trunc_by)), ("rem_by", Code.prim(I32.rem_by)), ("is_lt", Code.prim(I32.is_lt)), ("is_gt", Code.prim(I32.is_gt)), ("is_lte", Code.prim(I32.is_lte)), ("is_gte", Code.prim(I32.is_gte)), ("is_eq", Code.prim(I32.is_eq)), ("order_relative_to", Code.prim(I32.order_relative_to)), ("negate", Code.prim(I32.negate)), ("abs", Code.prim(I32.abs)), ("to_dec", Code.prim(I32.to_dec)), ("to_f64", Code.prim(I32.to_f64)), ("to_f32", Code.prim(I32.to_f32)), ("to_i32", Code.prim(I32.to_i32)), ("to_i64", Code.prim(I32.to_i64)), ("to_i128", Code.prim(I32.to_i128)), ("from_str", Code.prim(I32.from_str)), ("is_zero", Code.prim(I32.is_zero)), ("is_negative", Code.prim(I32.is_negative)), ("is_positive", Code.prim(I32.is_positive)), ("is_even", Code.prim(I32.is_even)), ("is_odd", Code.prim(I32.is_odd)), ("to_str", Code.prim(I32.to_str)), ("max", Code.prim(I32.max)), ("min", Code.prim(I32.min)), ("pow", Code.prim(I32.pow)), ("mod_by", Code.prim(I32.mod_by)), ("is_multiple_of", Code.prim(I32.is_multiple_of)), ("to_i16_try", Code.prim(I32.to_i16_try)), ("to_i32_try", Code.prim(I32.to_i32_try)), ("to_i8_try", Code.prim(I32.to_i8_try)), ("to_u128_try", Code.prim(I32.to_u128_try)), ("to_u16_try", Code.prim(I32.to_u16_try)), ("to_u32_try", Code.prim(I32.to_u32_try)), ("to_u64_try", Code.prim(I32.to_u64_try)), ("to_u8_try", Code.prim(I32.to_u8_try))]),
				Translate.named("Num.U32", [("plus", Code.prim(U32.plus)), ("minus", Code.prim(U32.minus)), ("times", Code.prim(U32.times)), ("div_by", Code.prim(U32.div_by)), ("div_trunc_by", Code.prim(U32.div_trunc_by)), ("rem_by", Code.prim(U32.rem_by)), ("is_lt", Code.prim(U32.is_lt)), ("is_gt", Code.prim(U32.is_gt)), ("is_lte", Code.prim(U32.is_lte)), ("is_gte", Code.prim(U32.is_gte)), ("is_eq", Code.prim(U32.is_eq)), ("order_relative_to", Code.prim(U32.order_relative_to)), ("to_dec", Code.prim(U32.to_dec)), ("to_f64", Code.prim(U32.to_f64)), ("to_f32", Code.prim(U32.to_f32)), ("to_i64", Code.prim(U32.to_i64)), ("to_i128", Code.prim(U32.to_i128)), ("to_u32", Code.prim(U32.to_u32)), ("to_u64", Code.prim(U32.to_u64)), ("to_u128", Code.prim(U32.to_u128)), ("from_str", Code.prim(U32.from_str)), ("is_zero", Code.prim(U32.is_zero)), ("is_even", Code.prim(U32.is_even)), ("is_odd", Code.prim(U32.is_odd)), ("to_str", Code.prim(U32.to_str)), ("max", Code.prim(U32.max)), ("min", Code.prim(U32.min)), ("pow", Code.prim(U32.pow)), ("mod_by", Code.prim(U32.mod_by)), ("is_multiple_of", Code.prim(U32.is_multiple_of)), ("to_i16_try", Code.prim(U32.to_i16_try)), ("to_i32_try", Code.prim(U32.to_i32_try)), ("to_i8_try", Code.prim(U32.to_i8_try)), ("to_u16_try", Code.prim(U32.to_u16_try)), ("to_u32_try", Code.prim(U32.to_u32_try)), ("to_u8_try", Code.prim(U32.to_u8_try))]),
				Translate.named("Num.I64", [("plus", Code.prim(I64.plus)), ("minus", Code.prim(I64.minus)), ("times", Code.prim(I64.times)), ("div_by", Code.prim(I64.div_by)), ("div_trunc_by", Code.prim(I64.div_trunc_by)), ("rem_by", Code.prim(I64.rem_by)), ("is_lt", Code.prim(I64.is_lt)), ("is_gt", Code.prim(I64.is_gt)), ("is_lte", Code.prim(I64.is_lte)), ("is_gte", Code.prim(I64.is_gte)), ("is_eq", Code.prim(I64.is_eq)), ("order_relative_to", Code.prim(I64.order_relative_to)), ("negate", Code.prim(I64.negate)), ("abs", Code.prim(I64.abs)), ("to_dec", Code.prim(I64.to_dec)), ("to_f64", Code.prim(I64.to_f64)), ("to_f32", Code.prim(I64.to_f32)), ("to_i64", Code.prim(I64.to_i64)), ("to_i128", Code.prim(I64.to_i128)), ("to_i64_wrap", Code.prim(I64.to_i64_wrap)), ("from_str", Code.prim(I64.from_str)), ("is_zero", Code.prim(I64.is_zero)), ("is_negative", Code.prim(I64.is_negative)), ("is_positive", Code.prim(I64.is_positive)), ("is_even", Code.prim(I64.is_even)), ("is_odd", Code.prim(I64.is_odd)), ("to_str", Code.prim(I64.to_str)), ("max", Code.prim(I64.max)), ("min", Code.prim(I64.min)), ("pow", Code.prim(I64.pow)), ("mod_by", Code.prim(I64.mod_by)), ("is_multiple_of", Code.prim(I64.is_multiple_of)), ("to_i16_try", Code.prim(I64.to_i16_try)), ("to_i32_try", Code.prim(I64.to_i32_try)), ("to_i64_try", Code.prim(I64.to_i64_try)), ("to_i8_try", Code.prim(I64.to_i8_try)), ("to_u128_try", Code.prim(I64.to_u128_try)), ("to_u16_try", Code.prim(I64.to_u16_try)), ("to_u32_try", Code.prim(I64.to_u32_try)), ("to_u64_try", Code.prim(I64.to_u64_try)), ("to_u8_try", Code.prim(I64.to_u8_try))]),
				Translate.named("Num.U64", [("plus", Code.prim(U64.plus)), ("minus", Code.prim(U64.minus)), ("times", Code.prim(U64.times)), ("div_by", Code.prim(U64.div_by)), ("div_trunc_by", Code.prim(U64.div_trunc_by)), ("rem_by", Code.prim(U64.rem_by)), ("is_lt", Code.prim(U64.is_lt)), ("is_gt", Code.prim(U64.is_gt)), ("is_lte", Code.prim(U64.is_lte)), ("is_gte", Code.prim(U64.is_gte)), ("is_eq", Code.prim(U64.is_eq)), ("order_relative_to", Code.prim(U64.order_relative_to)), ("to_dec", Code.prim(U64.to_dec)), ("to_f64", Code.prim(U64.to_f64)), ("to_f32", Code.prim(U64.to_f32)), ("to_i128", Code.prim(U64.to_i128)), ("to_u64", Code.prim(U64.to_u64)), ("to_u128", Code.prim(U64.to_u128)), ("to_i64_wrap", Code.prim(U64.to_i64_wrap)), ("from_str", Code.prim(U64.from_str)), ("is_zero", Code.prim(U64.is_zero)), ("is_even", Code.prim(U64.is_even)), ("is_odd", Code.prim(U64.is_odd)), ("to_str", Code.prim(U64.to_str)), ("max", Code.prim(U64.max)), ("min", Code.prim(U64.min)), ("pow", Code.prim(U64.pow)), ("mod_by", Code.prim(U64.mod_by)), ("is_multiple_of", Code.prim(U64.is_multiple_of)), ("to_i16_try", Code.prim(U64.to_i16_try)), ("to_i32_try", Code.prim(U64.to_i32_try)), ("to_i64_try", Code.prim(U64.to_i64_try)), ("to_i8_try", Code.prim(U64.to_i8_try)), ("to_u16_try", Code.prim(U64.to_u16_try)), ("to_u32_try", Code.prim(U64.to_u32_try)), ("to_u64_try", Code.prim(U64.to_u64_try)), ("to_u8_try", Code.prim(U64.to_u8_try))]),
				Translate.named("Num.I128", [("plus", Code.prim(I128.plus)), ("minus", Code.prim(I128.minus)), ("times", Code.prim(I128.times)), ("div_by", Code.prim(I128.div_by)), ("div_trunc_by", Code.prim(I128.div_trunc_by)), ("rem_by", Code.prim(I128.rem_by)), ("is_lt", Code.prim(I128.is_lt)), ("is_gt", Code.prim(I128.is_gt)), ("is_lte", Code.prim(I128.is_lte)), ("is_gte", Code.prim(I128.is_gte)), ("is_eq", Code.prim(I128.is_eq)), ("order_relative_to", Code.prim(I128.order_relative_to)), ("negate", Code.prim(I128.negate)), ("abs", Code.prim(I128.abs)), ("to_f64", Code.prim(I128.to_f64)), ("to_f32", Code.prim(I128.to_f32)), ("to_i128", Code.prim(I128.to_i128)), ("to_i64_wrap", Code.prim(I128.to_i64_wrap)), ("from_str", Code.prim(I128.from_str)), ("is_zero", Code.prim(I128.is_zero)), ("is_negative", Code.prim(I128.is_negative)), ("is_positive", Code.prim(I128.is_positive)), ("is_even", Code.prim(I128.is_even)), ("is_odd", Code.prim(I128.is_odd)), ("to_str", Code.prim(I128.to_str)), ("max", Code.prim(I128.max)), ("min", Code.prim(I128.min)), ("pow", Code.prim(I128.pow)), ("mod_by", Code.prim(I128.mod_by)), ("is_multiple_of", Code.prim(I128.is_multiple_of)), ("to_dec_try", Code.prim(I128.to_dec_try)), ("to_i128_try", Code.prim(I128.to_i128_try)), ("to_i16_try", Code.prim(I128.to_i16_try)), ("to_i32_try", Code.prim(I128.to_i32_try)), ("to_i64_try", Code.prim(I128.to_i64_try)), ("to_i8_try", Code.prim(I128.to_i8_try)), ("to_u128_try", Code.prim(I128.to_u128_try)), ("to_u16_try", Code.prim(I128.to_u16_try)), ("to_u32_try", Code.prim(I128.to_u32_try)), ("to_u64_try", Code.prim(I128.to_u64_try)), ("to_u8_try", Code.prim(I128.to_u8_try))]),
				Translate.named("Num.U128", [("plus", Code.prim(U128.plus)), ("minus", Code.prim(U128.minus)), ("times", Code.prim(U128.times)), ("div_by", Code.prim(U128.div_by)), ("div_trunc_by", Code.prim(U128.div_trunc_by)), ("rem_by", Code.prim(U128.rem_by)), ("is_lt", Code.prim(U128.is_lt)), ("is_gt", Code.prim(U128.is_gt)), ("is_lte", Code.prim(U128.is_lte)), ("is_gte", Code.prim(U128.is_gte)), ("is_eq", Code.prim(U128.is_eq)), ("order_relative_to", Code.prim(U128.order_relative_to)), ("to_f64", Code.prim(U128.to_f64)), ("to_f32", Code.prim(U128.to_f32)), ("to_u128", Code.prim(U128.to_u128)), ("to_i64_wrap", Code.prim(U128.to_i64_wrap)), ("from_str", Code.prim(U128.from_str)), ("is_zero", Code.prim(U128.is_zero)), ("is_even", Code.prim(U128.is_even)), ("is_odd", Code.prim(U128.is_odd)), ("to_str", Code.prim(U128.to_str)), ("max", Code.prim(U128.max)), ("min", Code.prim(U128.min)), ("pow", Code.prim(U128.pow)), ("mod_by", Code.prim(U128.mod_by)), ("is_multiple_of", Code.prim(U128.is_multiple_of)), ("to_dec_try", Code.prim(U128.to_dec_try)), ("to_i128_try", Code.prim(U128.to_i128_try)), ("to_i16_try", Code.prim(U128.to_i16_try)), ("to_i32_try", Code.prim(U128.to_i32_try)), ("to_i64_try", Code.prim(U128.to_i64_try)), ("to_i8_try", Code.prim(U128.to_i8_try)), ("to_u128_try", Code.prim(U128.to_u128_try)), ("to_u16_try", Code.prim(U128.to_u16_try)), ("to_u32_try", Code.prim(U128.to_u32_try)), ("to_u64_try", Code.prim(U128.to_u64_try)), ("to_u8_try", Code.prim(U128.to_u8_try))]),
				Translate.named("Num.Dec", [("plus", Code.prim(Dec.plus)), ("minus", Code.prim(Dec.minus)), ("times", Code.prim(Dec.times)), ("div_by", Code.prim(Dec.div_by)), ("div_trunc_by", Code.prim(Dec.div_trunc_by)), ("rem_by", Code.prim(Dec.rem_by)), ("is_lt", Code.prim(Dec.is_lt)), ("is_gt", Code.prim(Dec.is_gt)), ("is_lte", Code.prim(Dec.is_lte)), ("is_gte", Code.prim(Dec.is_gte)), ("is_eq", Code.prim(Dec.is_eq)), ("order_relative_to", Code.prim(Dec.order_relative_to)), ("negate", Code.prim(Dec.negate)), ("abs", Code.prim(Dec.abs)), ("to_dec", Code.prim(Dec.to_dec)), ("to_f64", Code.prim(Dec.to_f64)), ("to_i128", Code.prim(Dec.to_i128)), ("to_i64_wrap", Code.prim(Dec.to_i64_wrap)), ("from_str", Code.prim(Dec.from_str)), ("is_zero", Code.prim(Dec.is_zero)), ("is_negative", Code.prim(Dec.is_negative)), ("is_positive", Code.prim(Dec.is_positive)), ("to_str", Code.prim(Dec.to_str)), ("round", Code.prim(Dec.round)), ("floor", Code.prim(Dec.floor)), ("ceiling", Code.prim(Dec.ceiling)), ("trunc", Code.prim(Dec.trunc)), ("max", Code.prim(Dec.max)), ("min", Code.prim(Dec.min)), ("pow", Code.prim(Dec.pow)), ("to_i64_try", Code.prim(Dec.to_i64_try))]),
				Translate.named("Num.F32", [("plus", Code.prim(F32.plus)), ("minus", Code.prim(F32.minus)), ("times", Code.prim(F32.times)), ("div_by", Code.prim(F32.div_by)), ("div_trunc_by", Code.prim(F32.div_trunc_by)), ("rem_by", Code.prim(F32.rem_by)), ("is_lt", Code.prim(F32.is_lt)), ("is_gt", Code.prim(F32.is_gt)), ("is_lte", Code.prim(F32.is_lte)), ("is_gte", Code.prim(F32.is_gte)), ("is_eq", Code.prim(F32.is_eq)), ("negate", Code.prim(F32.negate)), ("abs", Code.prim(F32.abs)), ("to_f64", Code.prim(F32.to_f64)), ("to_f32", Code.prim(F32.to_f32)), ("to_i64_wrap", Code.prim(F32.to_i64_wrap)), ("from_str", Code.prim(F32.from_str)), ("is_zero", Code.prim(F32.is_zero)), ("is_negative", Code.prim(F32.is_negative)), ("is_positive", Code.prim(F32.is_positive)), ("to_str", Code.prim(F32.to_str)), ("max", Code.prim(F32.max)), ("min", Code.prim(F32.min)), ("pow", Code.prim(F32.pow))]),
				Translate.named("Num.F64", [("plus", Code.prim(F64.plus)), ("minus", Code.prim(F64.minus)), ("times", Code.prim(F64.times)), ("div_by", Code.prim(F64.div_by)), ("div_trunc_by", Code.prim(F64.div_trunc_by)), ("rem_by", Code.prim(F64.rem_by)), ("is_lt", Code.prim(F64.is_lt)), ("is_gt", Code.prim(F64.is_gt)), ("is_lte", Code.prim(F64.is_lte)), ("is_gte", Code.prim(F64.is_gte)), ("is_eq", Code.prim(F64.is_eq)), ("negate", Code.prim(F64.negate)), ("abs", Code.prim(F64.abs)), ("to_f64", Code.prim(F64.to_f64)), ("to_i64_wrap", Code.prim(F64.to_i64_wrap)), ("from_str", Code.prim(F64.from_str)), ("is_zero", Code.prim(F64.is_zero)), ("is_negative", Code.prim(F64.is_negative)), ("is_positive", Code.prim(F64.is_positive)), ("to_str", Code.prim(F64.to_str)), ("max", Code.prim(F64.max)), ("min", Code.prim(F64.min)), ("pow", Code.prim(F64.pow))]),
				Translate.named("Str", [("concat", Code.prim(Str.concat)), ("starts_with", Code.prim(Str.starts_with)), ("ends_with", Code.prim(Str.ends_with)), ("contains", Code.prim(Str.contains)), ("is_empty", Code.prim(Str.is_empty)), ("to_str", Code.prim(Str.to_str)), ("is_eq", Code.prim(Str.is_eq)), ("repeat", Code.prim(Str.repeat)), ("with_prefix", Code.prim(Str.with_prefix)), ("join_with", Code.prim(Str.join_with)), ("drop_prefix", Code.prim(Str.drop_prefix)), ("drop_suffix", Code.prim(Str.drop_suffix)), ("count_utf8_bytes", Code.prim(Str.count_utf8_bytes)), ("trim", Code.prim(Str.trim)), ("trim_start", Code.prim(Str.trim_start)), ("trim_end", Code.prim(Str.trim_end)), ("with_ascii_uppercased", Code.prim(Str.with_ascii_uppercased)), ("with_ascii_lowercased", Code.prim(Str.with_ascii_lowercased)), ("caseless_ascii_equals", Code.prim(Str.caseless_ascii_equals)), ("split_on", Code.prim(Str.split_on)), ("replace_each", Code.prim(Str.replace_each))]),
				Translate.named("List", [("len", Code.prim(List.len)), ("is_empty", Code.prim(List.is_empty)), ("contains", Code.prim(List.contains)), ("sum", Code.prim(List.sum)), ("any", Code.prim(List.any)), ("all", Code.prim(List.all)), ("map", Code.prim(List.map)), ("join_map", Code.prim(List.join_map)), ("keep_if", Code.prim(List.keep_if)), ("drop_if", Code.prim(List.drop_if)), ("count_if", Code.prim(List.count_if)), ("find_first", Code.prim(List.find_first)), ("first", Code.prim(List.first)), ("last", Code.prim(List.last)), ("min", Code.prim(List.min)), ("max", Code.prim(List.max)), ("get", Code.prim(List.get)), ("take_first", Code.prim(List.take_first)), ("drop_first", Code.prim(List.drop_first)), ("rev", Code.prim(List.rev)), ("concat", Code.prim(List.concat)), ("append", Code.prim(List.append)), ("prepend", Code.prim(List.prepend)), ("join", Code.prim(List.join)), ("is_eq", Code.prim(List.is_eq)), ("sort", Code.prim(List.sort)), ("sort_reversed", Code.prim(List.sort_reversed))]),
				Translate.named("Try", [("is_ok", Code.prim(Try.is_ok)), ("is_err", Code.prim(Try.is_err)), ("map_ok", Code.prim(Try.map_ok)), ("ok_or", Code.prim(Try.ok_or))]),
				Translate.named("Bool", [("not", Code.prim(Bool.not))]),
			],
		),
	)

	named : Str, List((Str, Code.PrimId)) -> List((Code.PrimId, { owner : Str, method : Str }))
	named = |owner, methods| methods.map(|(method, id)| (id, { owner, method }))

	## What the translation of one row's tree reads: the graph its calls name,
	## what the row's parameters and kept nodes stand for, and how a parameter
	## of the statement is spelled. `self` is the database function whose body
	## this is, so a call of its own row is `fn::name(..)`. `view` is `View` for
	## the columns of a view, which take fewer aggregates. `extensions` give
	## the forms of the calls that are not builtins (`Translate.form`).
	Env : {
		graph : Code.Graph,
		params : List(Binding),
		row : U32,
		nodes : List({ id : U32, binding : Binding, ty : Try(Code.Ty, [Untyped]) }),
		param : Str -> Str,
		depth : U64,
		random : Bool,
		view : [Plain, View, Totals],
		self : [Inside({ row : U32, name : Str }), Outside],
		extensions : List(Extension),
	}

	# ------------------------------------------------------------ bindings

	## The record a statement runs over: the table row (`""`), `$after` in an
	## event, `$this` in a field definition. `edge` is set for a relation table.
	document : Str, Bool -> Binding
	document = |at, edge| Binding.Row({ at, of: Doc(Unnamed), edge })

	## The row of the table `name` that a statement reads. A comparison of
	## its key with a value given to the statement compares the record id
	## (`Translate.key_compare`).
	table_row : Str, Bool -> Binding
	table_row = |name, edge| Binding.Row({ at: "", of: Doc(Of(name)), edge })

	## The edges of a relation table from the record at `at`: `->t` going
	## out, `<-t` coming in, `$before<-t` from the row before a write. Each
	## element is an edge record. The tables at the ends are not known.
	outgoing : Str, Str -> Binding
	outgoing = |at, table| Translate.edge_list(at, "->", table, Translate.any_ends)

	incoming : Str, Str -> Binding
	incoming = |at, table| Translate.edge_list(at, "<-", table, Translate.any_ends)

	## The edges of `table` at the record at `at`, by the arrow, with the
	## tables at their ends. A hop to an end continues the path:
	## `->treats->patient` (`Translate.hop`).
	edge_list : Str, Str, Str, Ends -> Binding
	edge_list = |at, arrow, table, ends| Binding.ListOf({ at: "${at}${arrow}${Ql.ident(table)}", items: Records({ edge: Bool.True, row: Untyped, graph: Edges(ends) }) })

	## Ends of any table.
	any_ends : Ends
	any_ends = { from: "?", to: "?" }

	## A value at a SurrealQL expression, bound by its type: a record is a
	## place to read fields from, a list takes list operations, a union is
	## matched, a `Try` (an optional field) is tested, anything else is a
	## scalar. `at("$value", ty)` is the value of a field `ASSERT`.
	at : Str, Code.Ty -> Binding
	at = |expr, ty| match ty {
		Record(_) => Binding.Row({ at: expr, of: Obj, edge: Bool.False })
		ListOf(item) => Binding.ListOf({ at: expr, items: Translate.items_of(ListOf(item)) })
		TagUnion(variants) => Binding.Union({ at: expr, variants })
		Named(name, _, backing) => match Types.nominal(name) {
			Try => Binding.Maybe(expr)
			# A read view of a link: a field read through it is a traversal.
			Linked => Binding.Row({ at: expr, of: Ref(backing), edge: Bool.False })
			Other | Out | In => Translate.at(expr, backing)
			_ => Binding.Expr(expr)
		}
		_ => Binding.Expr(expr)
	}

	## The elements of a list of type `list_ty` read off a record: the
	## records of a read view (`List(Linked(r))`), or values.
	items_of : Code.Ty -> Items
	items_of = |list_ty| match list_ty {
		ListOf(Named(name, _, row)) if Types.nominal(name) == Linked => Records({ edge: Bool.False, row: Typed(row), graph: Off })
		_ => Values
	}

	## The elements of a list of record ids of type `list_ty`: the rows of a
	## table, or the edges of a read view's `Out` and `In` fields.
	records : Bool, Code.Ty -> Items
	records = |edge, list_ty| Translate.records_of(edge, list_ty, Off)

	## The same items, as the value of a function: an `array::` call is
	## not a graph path, which a `->` or `[WHERE ..]` continues.
	off_path : Items -> Items
	off_path = |items| match items {
		Records(r) => Records({ ..r, graph: Off })
		other => other
	}

	## The same, with what graph path the list is.
	records_of : Bool, Code.Ty, Graph -> Items
	records_of = |edge, list_ty, graph| match list_ty {
		ListOf(row) => Records({ edge, row: Typed(row), graph })
		_ => Records({ edge, row: Untyped, graph })
	}

	## A statement parameter `p.name` as a `LET` variable: `$name`.
	variable : Str -> Str
	variable = |name| "$${name}"

	## The name of captured value `k`, numbered from 1: `_1`, `_2`, ...
	input_name : U64 -> Str
	input_name = |k| "_${(k + 1).to_str()}"

	## The index of the captured value that `input_name` names: `_1` is 0.
	input_index : Str -> Try(U64, [NotInput])
	input_index = |name| {
		digits = name.drop_prefix("_")
		if !name.starts_with("_") or digits.is_empty() or !digits.to_utf8().all(|b| b >= 48 and b <= 57) {
			return Err(NotInput)
		}
		match U64.from_str(digits) {
			Ok(n) if n > 0 => Ok(n - 1)
			_ => Err(NotInput)
		}
	}

	## The mark of slot `k` of a chain, in a statement before its values are
	## known: `$`, then `k` between two bytes 1. A quoted text or name never
	## holds byte 1 (`Ql.escape`), so a mark is found by its bytes alone,
	## and a statement that joins two chains numbers the marks again.
	slot_mark : U64 -> Str
	slot_mark = |k| "$${Translate.mark_byte}${k.to_str()}${Translate.mark_byte}"

	## The byte around the number of a `slot_mark`.
	mark_byte : Str
	mark_byte = "\u(1)"

	## Whether a name of a path is a mark of `slot_mark`, without its `$`.
	is_mark : Str -> Bool
	is_mark = |name| name.starts_with(Translate.mark_byte) and name.ends_with(Translate.mark_byte) and name.count_utf8_bytes() > 2

	## A parameter spelling for a clause whose captured values are slots
	## `first`, `first + 1`, .. of its chain (`Code.first_slot`): a captured
	## value is its `slot_mark`, and any other name is `param`'s.
	slotted : U64, (Str -> Str) -> (Str -> Str)
	slotted = |first, param| |name| match Translate.input_index(name) {
		Ok(k) => Translate.slot_mark(first + k)
		Err(_) => param(name)
	}

	# ------------------------------------------------------------ entry points

	## A reified function applied to what its parameters stand for. A clause
	## that reads rows may not call `Rand`: it would give other rows each time.
	evaluate : List(Extension), Code.Graph, List(Binding), (Str -> Str) -> Try(Binding, Ql.Error)
	evaluate = |extensions, graph, bindings, param| Translate.run(extensions, graph, bindings, param, Bool.False, Plain)

	## The same, as one SurrealQL expression, for a value that SurrealDB gives to
	## one row: a default, a computed field or an update. `Rand` is allowed.
	row_value : List(Extension), Code.Graph, List(Binding), (Str -> Str) -> Try(Str, Ql.Error)
	row_value = |extensions, graph, bindings, param| Translate.text(Translate.run(extensions, graph, bindings, param, Bool.True, Plain)?)

	run : List(Extension), Code.Graph, List(Binding), (Str -> Str), Bool, [Plain, View, Totals] -> Try(Binding, Ql.Error)
	run = |extensions, graph, bindings, param, random, view| {
		root = graph.root_row()
		if root.params.len() != bindings.len() {
			return Err(Unsupported("this clause takes ${bindings.len().to_str()} argument(s)"))
		}
		Translate.eval(graph.to_tree(root.id), { graph, params: bindings, row: root.id, nodes: [], param, depth: 0, random, view, self: Outside, extensions })
	}

	## A database function and every database function its body calls, each
	## once: the name, the types of the parameters `$a1`, `$a2`, .. and of the
	## result, and the body as one SurrealQL expression. The root of the graph
	## is the constant that `Surreal.db_fn` made. A body may not call `Rand`,
	## because a function can run in a `WHERE`.
	function_defs : List(Extension), Code.Graph -> Try(List({ name : Str, params : List(Code.Ty), result : Code.Ty, body : Str }), Ql.Error)
	function_defs = |extensions, graph| {
		_ = match Translate.body(graph.to_tree(graph.root_row().id)) {
			Op({ op: Wrap(name), args: [inner], .. }) if Types.nominal(name) == DbFn => Translate.function_ref(inner)?
			_ => return Err(Translate.not_constant)
		}
		found = graph.rows().join_map(|r| Translate.function_values(graph.to_tree(r.id))).map_try(Translate.function_ref)?
		once = found.fold([], |kept, f| if (kept.contains(f)) kept else kept.append(f))
		once.map_try(|f| Translate.function_def(extensions, graph, f))
	}

	## The body of one database function, with its own row's calls as `fn::name(..)`.
	function_def : List(Extension), Code.Graph, { name : Str, row : U32 } -> Try({ name : Str, params : List(Code.Ty), result : Code.Ty, body : Str }, Ql.Error)
	function_def = |extensions, graph, f| {
		r = graph.row(f.row)
		params = r.params.map_with_index(|ty, k| Translate.at("$a${(k + 1).to_str()}", ty))
		env = { graph, params, row: f.row, nodes: [], param: Translate.variable, depth: 0, random: Bool.False, view: Plain, self: Inside(f), extensions }
		body = Translate.body_text(graph.to_tree(f.row), env).map_err(|e| Translate.within(e, f.name))?
		Ok({ name: f.name, params: r.params, result: r.result, body })
	}

	body_text : Code.Tree, Env -> Try(Str, Ql.Error)
	body_text = |tree, env| Translate.text(Translate.eval(tree, env)?)

	## An error in the body of a database function names the function.
	within : Ql.Error, Str -> Ql.Error
	within = |error, name| match error {
		Unsupported(why) => Unsupported("in `fn::${name}`: ${why}")
		BadSchema(why) => BadSchema("in `fn::${name}`: ${why}")
		Decode(d) => Decode({ ..d, message: "in `fn::${name}`: ${d.message}" })
		Wire(why) => Wire("in `fn::${name}`: ${why}")
		Server(e) => Server(e)
		Aborted(a) => Aborted(a)
		Transport(why) => Transport("in `fn::${name}`: ${why}")
		WebSocket(w) => WebSocket(w)
		Migration(m) => Migration(m)
	}

	## The value of every `Surreal.db_fn` constant in a tree: the record of
	## its name and its Roc function.
	function_values : Code.Tree -> List(Code.Tree)
	function_values = |tree| match tree {
		Op({ op: Wrap(name), args, .. }) if Types.nominal(name) == DbFn => args
		Op({ args, .. }) => args.join_map(Translate.function_values)
		Block({ defs, end }) => {
			ends = match end {
				Value(values) | Continue(values) | Break(values) => values
				Jump(j) => j.args
				Return(one) | Branch(one) => [one]
			}
			defs.map(|d| d.value).concat(ends).join_map(Translate.function_values)
		}
		_ => []
	}

	## The name and the body row of a database function, from the record that
	## `Surreal.db_fn` builds. The name is a literal and the function captures
	## nothing, so both are fixed when the program compiles.
	function_ref : Code.Tree -> Try({ name : Str, row : U32 }, Ql.Error)
	function_ref = |tree| match (Translate.record_field(tree, "name"), Translate.record_field(tree, "run")) {
		(Ok(Op({ op: Lit(Str(name)), .. })), Ok(Op({ op: Closure(row), args: captures, .. }))) =>
			if !captures.is_empty() {
				Err(Unsupported("the database function `fn::${name}` captures values; a database function is a top-level function"))
			} else if !Translate.is_function_name(name) {
				Err(Unsupported("`${name}` is not a database function name; use `[a-z_][a-z0-9_]*`"))
			} else {
				Ok({ name, row })
			}
		_ => Err(Translate.not_constant)
	}

	not_constant : Ql.Error
	not_constant = Unsupported("a database function is a top-level constant made with Surreal.db_fn")

	## `[a-z_][a-z0-9_]*`.
	is_function_name : Str -> Bool
	is_function_name = |name| match name.to_utf8() {
		[first, .. as rest] => (first == 95 or (first >= 97 and first <= 122)) and rest.all(|b| b == 95 or (b >= 97 and b <= 122) or (b >= 48 and b <= 57))
		[] => Bool.False
	}

	## The clause as one SurrealQL expression.
	render : List(Extension), Code.Graph, List(Binding), (Str -> Str) -> Try(Str, Ql.Error)
	render = |extensions, graph, bindings, param| Translate.text(Translate.evaluate(extensions, graph, bindings, param)?)

	## The fields of a record the clause builds, in name order, as SurrealQL
	## expressions. The names are Roc's; a caller spells them with `Ql.ident`.
	columns : List(Extension), Code.Graph, List(Binding), (Str -> Str) -> Try(List({ name : Str, surql : Str }), Ql.Error)
	columns = |extensions, graph, bindings, param| Translate.fields_of(Translate.evaluate(extensions, graph, bindings, param)?)

	## The same, for the columns of a view. SurrealDB keeps fewer aggregates
	## in a view (`Translate.aggregate_arg`).
	view_columns : List(Extension), Code.Graph, List(Binding), (Str -> Str) -> Try(List({ name : Str, surql : Str }), Ql.Error)
	view_columns = |extensions, graph, bindings, param| Translate.fields_of(Translate.run(extensions, graph, bindings, param, Bool.False, View)?)

	## The same, for the columns of `Query.totals`: the one row of `GROUP ALL`,
	## which also exists for no rows (`Translate.aggregate_arg`).
	total_columns : List(Extension), Code.Graph, List(Binding), (Str -> Str) -> Try(List({ name : Str, surql : Str }), Ql.Error)
	total_columns = |extensions, graph, bindings, param| Translate.fields_of(Translate.run(extensions, graph, bindings, param, Bool.False, Totals)?)

	fields_of : Binding -> Try(List({ name : Str, surql : Str }), Ql.Error)
	fields_of = |binding| match binding {
		Fields(fields) => fields.map_try(|f| Ok({ name: f.name, surql: Translate.text(f.binding)? }))
		_ => Err(Unsupported("a result row is a record, so each field has a name"))
	}

	# ------------------------------------------------------------ reached primitives

	## Where `prims_of` walks: the graph, the primitives that each parameter
	## of the row stands for, the kept definitions read so far with the
	## primitives each one reaches, and the rows on the way, so a row that
	## calls itself is walked once.
	Reaching : { graph : Code.Graph, params : List(List(Code.PrimId)), defs : List({ id : U32, value : Code.Tree, prims : List(Code.PrimId) }), rows : List(U32) }

	## The ids of the primitives that the value of a tree reaches: its own
	## `Prim` nodes, those of the kept definitions and the parameters it
	## reads, and those of each row it calls or makes a closure of.
	prims_of : Code.Tree, Reaching -> List(Code.PrimId)
	prims_of = |tree, walk| match tree {
		Param(k) => walk.params.get(k.to_u64()) ?? []
		Def(n) => match walk.defs.find_last(|d| d.id == n) {
			Ok(d) => d.prims
			Err(_) => []
		}
		Input(_) | Arg(_) | Out(_) => []
		Block(block) => {
			inner = Translate.reaching_defs(block.defs, walk)
			ends = match block.end {
				Value(trees) | Continue(trees) | Break(trees) => trees
				Jump(j) => j.args
				Return(t) | Branch(t) => [t]
			}
			ends.join_map(|t| Translate.prims_of(t, inner))
		}
		Op(node) => {
			held = node.args.map(|a| Translate.prims_of(a, walk))
			own = held.join_map(|p| p)
			match node.op {
				Prim(call) => own.append(call.id)
				Call(row) => own.concat(Translate.row_prims(row, held, walk))
				Closure(row) => own.concat(Translate.row_prims(row, held, walk))
				_ => own
			}
		}
	}

	## The kept definitions of a block, each with the primitives it reaches.
	reaching_defs : List({ id : U32, value : Code.Tree }), Reaching -> Reaching
	reaching_defs = |defs, walk| defs.fold(walk, |acc, def| { ..acc, defs: acc.defs.append({ id: def.id, value: def.value, prims: Translate.prims_of(def.value, acc) }) })

	## The primitives that row `row` reaches, with its first parameters
	## standing for `params` (a closure's captured values; the element it
	## is called with is the list's, which the caller walks).
	row_prims : U32, List(List(Code.PrimId)), Reaching -> List(Code.PrimId)
	row_prims = |row, params, walk|
		if walk.rows.contains(row) {
			[]
		} else {
			count = walk.graph.row(row).params.len()
			bound = params.concat(List.repeat([], count - params.len().min(count)))
			Translate.prims_of(walk.graph.to_tree(row), { graph: walk.graph, params: bound, defs: [], rows: walk.rows.append(row) })
		}

	## The primitives that each field of the record a clause returns
	## reaches, by the field's Roc name: one entry per column of a
	## `SELECT`. A clause that returns no record built in it, such as a
	## whole row, gives none.
	column_prims : Code.Graph -> List({ name : Str, prims : List(Code.PrimId) })
	column_prims = |graph| {
		root = graph.root_row()
		Translate.record_prims(graph.to_tree(root.id), { graph, params: root.params.map(|_| []), defs: [], rows: [root.id] })
	}

	record_prims : Code.Tree, Reaching -> List({ name : Str, prims : List(Code.PrimId) })
	record_prims = |tree, walk| match tree {
		Op({ op: Record(names), args, .. }) => List.map2(names, args, |name, value| { name, prims: Translate.prims_of(value, walk) })
		Op({ op: Call(row), args, .. }) if !walk.rows.contains(row) => Translate.record_prims(walk.graph.to_tree(row), { graph: walk.graph, params: args.map(|a| Translate.prims_of(a, walk)), defs: [], rows: walk.rows.append(row) })
		Def(n) => match walk.defs.find_last(|d| d.id == n) {
			Ok(d) => Translate.record_prims(d.value, walk)
			Err(_) => []
		}
		Block({ defs, end: Value([one]) }) => Translate.record_prims(one, Translate.reaching_defs(defs, walk))
		_ => []
	}

	## The `SET` list of an update patch `|o| { ..o, f: .. }`, whose last
	## parameter is the row. A field that reads the row's field of its own name
	## is unchanged and left out; every other field is `f = <expr>`, in name
	## order. A field whose type is a record and that the patch builds as one,
	## `address: { ..o.address, city: .. }`, is set field by field,
	## `address.city = ..`. An optional field that the patch's row leaves out
	## is `f = NONE`. The names are spelled as SurrealDB names them. Each
	## expression reads the row before the update, as in Roc: SurrealDB 3.3.4
	## reads the old row in each `SET` item (verified).
	##
	## The reifier gives `..o` over an optional field as a presence switch on
	## it, with the row in each arm: without the field in `Err`, with its own
	## payload in `Ok` (the same switch that `Translate.presence_equality`
	## reads for `==`). Each arm gives its changes. A field that the arms
	## change alike is one item, and one they change differently is
	## `f = (IF <field> IS NONE THEN .. ELSE .. END)`.
	assignments : List(Extension), Code.Graph, List(Binding), (Str -> Str) -> Try(List({ name : Str, surql : Str }), Ql.Error)
	assignments = |extensions, graph, bindings, param| {
		(here, env) = Translate.patch_start(extensions, graph, bindings, param)?
		root = graph.root_row()
		row_fields = match root.params.last() {
			Ok(row_ty) => Types.record_fields(row_ty)?
			Err(_) => return Err(Unsupported("an update patch reads the row"))
		}
		found = Translate.changes(graph.to_tree(root.id), row_fields, here, env)?
		if found.any(|c| c.path == ["id"] and c.value != Same) {
			return Err(Unsupported("an update cannot change `id`, the record key"))
		}
		Translate.set_items(found, "this update changes no field")
	}

	## Where the patch of an update starts: the row itself, and the
	## environment its expressions read, where `Rand` is allowed.
	patch_start : List(Extension), Code.Graph, List(Binding), (Str -> Str) -> Try((PatchAt, Env), Ql.Error)
	patch_start = |extensions, graph, bindings, param| {
		root = graph.root_row()
		if root.params.len() != bindings.len() {
			return Err(Unsupported("this clause takes ${bindings.len().to_str()} argument(s)"))
		}
		edge = match bindings.last() {
			Ok(Row(r)) => r.edge
			_ => Bool.False
		}
		here = { path: [], absent: [], kept: [], row: (root.params.len() - 1).to_u32_wrap(), edge }
		Ok((here, { graph, params: bindings, row: root.id, nodes: [], param, depth: 0, random: Bool.True, view: Plain, self: Outside, extensions }))
	}

	## The `SET` items of the changes of a patch, or `none` when it changes
	## no field.
	set_items : List(Change), Str -> Try(List({ name : Str, surql : Str }), Ql.Error)
	set_items = |found, none| {
		sets = found.keep_oks(
			|c| match c.value {
				To(surql) => Ok({ name: c.name, surql })
				Same => Err(Same)
			},
		)
		if (sets.is_empty()) Err(Unsupported(none)) else Ok(sets)
	}

	## The `SET` list of a patch of only the fields it sets, `|o| { name: .. }`,
	## whose last parameter is the row. Each field is set as the same field
	## of a whole-row patch (`Translate.assignments`). Roc has no type for a
	## record of some of the row's fields, so this checks the patch against
	## the row: each field is a field of the row other than `id`, of the same
	## type. An optional field of the row takes its value, which makes it
	## present, or a `Try` of it, whose `Err` is NONE.
	patch_assignments : List(Extension), Code.Graph, List(Binding), (Str -> Str) -> Try(List({ name : Str, surql : Str }), Ql.Error)
	patch_assignments = |extensions, graph, bindings, param| {
		root = graph.root_row()
		row_fields = match root.params.last() {
			Ok(row_ty) => Types.record_fields(row_ty)?
			Err(_) => return Err(Unsupported("a patch reads the row"))
		}
		patch_fields = match Types.open(root.result) {
			Record(fields) => fields
			other => return Err(Unsupported("a patch is a record of the fields it sets, as `|o| { field: .. }`; this one is `${other.name()}`"))
		}
		_ = patch_fields.map_try(|f| Translate.patch_field(f, row_fields))?
		(here, env) = Translate.patch_start(extensions, graph, bindings, param)?
		Translate.set_items(Translate.patch_changes(graph.to_tree(root.id), row_fields, here, env)?, "this patch changes no field")
	}

	## The changes of a patch record, each field as the same field of the row
	## that `Translate.assignments` reads: a record field built as a record is
	## set field by field.
	patch_changes : Code.Tree, List(Types.Field), PatchAt, Env -> Try(List(Change), Ql.Error)
	patch_changes = |tree, row_fields, here, env| match Translate.kept_value(tree, here.kept) {
		Block({ defs, end: Value([one]) }) => Translate.patch_changes(one, row_fields, { ..here, kept: here.kept.concat(defs) }, Translate.define(defs, env)?)
		Op({ op: Record(names), args, .. }) => {
			found = List.map2(names, args, |name, arg| { name, arg }).map_try(
				|given| match row_fields.find_first(|r| r.name == given.name) {
					Ok(stored) => Translate.field_change(stored, Ok(given.arg), here, env)
					Err(_) => Err(BadSchema("the row has no field `${given.name}`, so a patch cannot set it"))
				},
			)?
			Ok(found.join())
		}
		_ => Err(Unsupported("a patch is a record of the fields it sets, as `|o| { field: .. }`"))
	}

	## One field of a patch against the fields of the row.
	patch_field : Types.Field, List(Types.Field) -> Try({}, Ql.Error)
	patch_field = |f, row_fields| {
		stored = match row_fields.find_first(|r| r.name == f.name) {
			Ok(found) => found
			Err(_) => return Err(BadSchema("the row has no field `${f.name}`, so a patch cannot set it; it has ${Str.join_with(row_fields.map(|r| "`${r.name}`"), ", ")}"))
		}
		if f.name == "id" {
			return Err(Unsupported("an update cannot change `id`, the record key"))
		}
		if f.presence == Optional {
			return Err(Unsupported("the patch's `${f.name}` is optional; a patch sets each field it has, and a `Try` sets an optional field or makes it NONE"))
		}
		agrees = match (stored.presence, f.ty) {
			(Optional, Named(name, [inner, _], _)) if Types.nominal(name) == Try => Translate.fits(inner, stored.ty)
			_ => Translate.fits(f.ty, stored.ty)
		}
		if agrees {
			Ok({})
		} else {
			literal = if (f.ty == Dec and Translate.is_integer(stored.ty)) "; a number literal without a suffix is a `Dec`, so write `1.${stored.ty.name()}`" else ""
			Err(BadSchema("the patch's `${f.name}` is `${f.ty.name()}`, and the row's `${f.name}` is `${stored.ty.name()}`${literal}"))
		}
	}

	## Whether a value of the patch's type `got` is a value of the row's type
	## `want`. The patch's type is inferred from the patch alone, so a tag is a
	## union of the tags it has, `Cash` is `[Cash]`, and a record leaves out
	## the optional fields it does not set.
	fits : Code.Ty, Code.Ty -> Bool
	fits = |got, want|
		if Types.key(got) == Types.key(want) {
			Bool.True
		} else {
			match (got, Types.unwrap(want)) {
				(TagUnion(gs), TagUnion(ws)) =>
					gs.all(
						|g| match ws.find_first(|w| w.name == g.name) {
							Ok(w) => g.payloads.len() == w.payloads.len() and List.map2(g.payloads, w.payloads, |a, b| Translate.fits(a, b)).all(|ok| ok)
							Err(_) => Bool.False
						},
					)
				(Record(gs), Record(ws)) => {
					known = gs.all(
						|g| match ws.find_first(|w| w.name == g.name) {
							Ok(w) => g.presence != Optional and Translate.fits(g.ty, w.ty)
							Err(_) => Bool.False
						},
					)
					known and ws.all(|w| w.presence == Optional or gs.any(|g| g.name == w.name))
				}
				(ListOf(g), ListOf(w)) => Translate.fits(g, w)
				_ => Bool.False
			}
		}

	## Where a part of an update patch builds the row: the field `path` from
	## the row, the optional fields that a presence switch around it says are
	## absent, the kept definitions of the blocks around it, the row parameter
	## and whether the row is an edge.
	PatchAt : { path : List(Str), absent : List(List(Str)), kept : List({ id : U32, value : Code.Tree }), row : U32, edge : Bool }

	## One field of a patched row: unchanged, or set to an expression.
	Change : { path : List(Str), name : Str, value : [Same, To(Str)] }

	## The changes of the part of a patch that builds the record at `here.path`,
	## whose fields in the row are `fields`. A kept definition, such as a field
	## that `..o` keeps and the patch reads, is read as its value.
	changes : Code.Tree, List(Types.Field), PatchAt, Env -> Try(List(Change), Ql.Error)
	changes = |tree, fields, here, env| match Translate.kept_value(tree, here.kept) {
		Block({ defs, end: Value([one]) }) => Translate.changes(one, fields, { ..here, kept: here.kept.concat(defs) }, Translate.define(defs, env)?)
		Op({ op: Wrap(name), args: [inner], .. }) if Types.user_named(name) => Translate.changes(inner, fields, here, env)
		Op({ op: Record(names), args, .. }) => {
			given = List.map2(names, args, |name, arg| { name, arg })
			found = fields.map_try(|f| Translate.field_change(f, given.find_first(|g| g.name == f.name).map_ok(|g| g.arg), here, env))?
			Ok(found.join())
		}
		Op({ op: Switch(sw), args: [scrutinee, .. as arms], .. }) => match Translate.presence_field(sw.arms.map(|a| a.key), scrutinee, arms, here) {
			Ok(presence) => {
				field = here.path.append(presence.name)
				when_absent = Translate.changes(presence.absent, fields, { ..here, absent: here.absent.append(field) }, env)?
				when_present = Translate.changes(presence.present, fields, here, env)?
				Translate.merge(when_absent, when_present, Translate.expr(scrutinee, env)?)
			}
			Err(_) => Translate.whole_change(tree, here, env)
		}
		_ => Translate.whole_change(tree, here, env)
	}

	## The changes of the two arms of a presence switch on the field that
	## `test` reads. A field that an arm leaves out is unchanged there, because
	## the arm keeps the record around it. A field that the arms change alike
	## is that change, and one they change differently is an `IF` on the
	## presence. A field that one arm sets whole, while the other sets its
	## fields, has no one `SET` list.
	merge : List(Change), List(Change), Str -> Try(List(Change), Ql.Error)
	merge = |when_absent, when_present, test| {
		fields = when_present.fold(when_absent, |acc, c| if (acc.any(|e| e.path == c.path)) acc else acc.append(c))
		value_in = |arm, path| arm.find_first(|c| c.path == path).map_ok(|c| c.value) ?? Same
		merged = fields.map(
			|f| {
				current = |value| match value {
					To(surql) => surql
					Same => f.name
				}
				(a, p) = (value_in(when_absent, f.path), value_in(when_present, f.path))
				{ ..f, value: if (a == p) a else To("(IF ${test} IS NONE THEN ${current(a)} ELSE ${current(p)} END)") }
			},
		)
		inside = |outer, inner| inner.len() > outer.len() and inner.take_first(outer.len()) == outer
		match merged.find_first(|c| c.value != Same and merged.any(|other| inside(c.path, other.path))) {
			Ok(c) => Err(Unsupported("this update sets `${c.name}` whole when `${test}` is one way, and its fields when it is the other; build `${c.name}` the same way in both"))
			Err(_) => Ok(merged)
		}
	}

	## A part of a patch that does not build its record field by field: the
	## row's own value, unchanged, or a value that the field is set to. The
	## patch itself builds the row it returns.
	whole_change : Code.Tree, PatchAt, Env -> Try(List(Change), Ql.Error)
	whole_change = |tree, here, env| {
		if Translate.is_at(tree, here.path, here) {
			return Ok(if (here.path.is_empty()) [] else [{ path: here.path, name: Translate.spell_path(here.path, here.edge), value: Same }])
		}
		match (here.path, tree) {
			([], Op({ op: Switch(_), .. })) => Err(Unsupported("an update patch builds one row; a branch around the row has no `SET` form, so branch inside each field that changes: `|o| { ..o, f: if .. }`"))
			([], Op({ op, .. })) => Err(Unsupported("an update patch builds the row it returns, as `|o| { ..o, field: .. }`; this one returns ${Translate.describe(op)}"))
			([], _) => Err(Unsupported("an update patch builds the row it returns, as `|o| { ..o, field: .. }`"))
			_ => Ok([{ path: here.path, name: Translate.spell_path(here.path, here.edge), value: To(Translate.expr(tree, env)?) }])
		}
	}

	## The change of field `f` of a record the patch builds, where `given` is
	## the value the record gives it. An optional field the record leaves out
	## is unchanged where a presence switch says the row has no such field,
	## and `NONE` elsewhere.
	field_change : Types.Field, Try(Code.Tree, [NotFound]), PatchAt, Env -> Try(List(Change), Ql.Error)
	field_change = |f, given, here, env| {
		path = here.path.append(f.name)
		name = Translate.spell_path(path, here.edge)
		same = Ok([{ path, name, value: Same }])
		match given {
			Err(_) =>
				if here.absent.contains(path) {
					same
				} else {
					Ok([{ path, name, value: To("NONE") }])
				}
			Ok(arg) if f.presence == Optional => match Translate.kept_value(arg, here.kept) {
				Op({ op: Payload("Ok", 0), args: [read], .. }) if Translate.optional_read(read, here) == Ok(f.name) => same
				_ => Ok([{ path, name, value: To(Translate.expr(arg, env)?) }])
			}
			Ok(arg) if Translate.is_at(arg, path, here) => same
			Ok(arg) => match f.ty {
				Record(inner) => Translate.changes(arg, inner, { ..here, path }, env)
				_ => Ok([{ path, name, value: To(Translate.expr(arg, env)?) }])
			}
		}
	}

	## The optional field of the record at `here.path` that a switch tests for
	## presence, with its arm where the field is absent and its arm where it
	## is present: the scrutinee reads the field, and the arms are `Err` and
	## `Ok`.
	presence_field : List(Code.Key), Code.Tree, List(Code.Tree), PatchAt -> Try({ name : Str, absent : Code.Tree, present : Code.Tree }, [NotOptional])
	presence_field = |keys, scrutinee, arms, here| {
		name = Translate.optional_read(scrutinee, here)?
		match (keys, arms) {
			([first, second], [one, other]) if Translate.key_is(first, "Err") and Translate.key_is(second, "Ok") => Ok({ name, absent: one, present: other })
			([first, second], [one, other]) if Translate.key_is(first, "Ok") and Translate.key_is(second, "Err") => Ok({ name, absent: other, present: one })
			_ => Err(NotOptional)
		}
	}

	## The name of the optional field that a tree reads off the record at
	## `here.path`, `Unwrap(OptField(name))`.
	optional_read : Code.Tree, PatchAt -> Try(Str, [NotOptional])
	optional_read = |tree, here| match Translate.kept_value(tree, here.kept) {
		Op({ op: Unwrap, args: [Op({ op: OptField(name), args: [inner], .. })], .. }) if Translate.is_at(inner, here.path, here) => Ok(name)
		_ => Err(NotOptional)
	}

	## Whether a tree is the row's own value at a field path, unchanged.
	is_at : Code.Tree, List(Str), PatchAt -> Bool
	is_at = |tree, path, here| match Translate.kept_value(tree, here.kept) {
		Param(k) => path.is_empty() and k == here.row
		Op({ op: Unwrap, args: [inner], .. }) => Translate.is_at(inner, path, here)
		Op({ op: Field(name), args: [inner], .. }) => path.last() == Ok(name) and Translate.is_at(inner, path.drop_last(1), here)
		_ => Bool.False
	}

	## A field path of the row as SurrealDB names it, `address.city`.
	spell_path : List(Str), Bool -> Str
	spell_path = |path, edge| match path {
		[first, .. as rest] => rest.fold(Translate.spell_name(first, edge), |text, name| "${text}.${Ql.ident(name)}")
		[] => ""
	}

	## The tree that a read of a kept definition stands for.
	kept_value : Code.Tree, List({ id : U32, value : Code.Tree }) -> Code.Tree
	kept_value = |tree, kept| match tree {
		Def(n) => match kept.find_last(|d| d.id == n) {
			Ok(d) => Translate.kept_value(d.value, kept)
			Err(_) => tree
		}
		other => other
	}

	## A row's tree without the block around it, where the block holds one
	## value and no definitions.
	body : Code.Tree -> Code.Tree
	body = |tree| match tree {
		Block({ defs: [], end: Value([one]) }) => one
		other => other
	}

	# ------------------------------------------------------------ field paths

	## The field path a path lambda reads: a chain of field reads, `.?` reads
	## and `List.map` with a closure that is itself a path.
	path_of : Code.Graph -> Try(List(Step), Ql.Error)
	path_of = |graph| {
		root = graph.root_row()
		if root.params.len() != 1 {
			return Err(Unsupported("a field path reads one row"))
		}
		Translate.steps(graph, graph.to_tree(root.id))
	}

	## The paths a key lambda reads: one path, or a record or tuple of them.
	paths_of : Code.Graph -> Try(List(List(Step)), Ql.Error)
	paths_of = |graph| {
		root = graph.root_row()
		if root.params.len() != 1 {
			return Err(Unsupported("a field path reads one row"))
		}
		# A row read twice (a nominal row's `Unwrap`) is a kept definition.
		(kept, value) = match graph.to_tree(root.id) {
			Block({ defs, end: Value([one]) }) => (defs, one)
			other => ([], other)
		}
		match value {
			Op({ op: Record(_), args, .. }) | Op({ op: Tuple, args, .. }) => args.map_try(|arg| Translate.steps_in(graph, kept, arg))
			single => Ok([Translate.steps_in(graph, kept, single)?])
		}
	}

	steps : Code.Graph, Code.Tree -> Try(List(Step), Ql.Error)
	steps = |graph, tree| Translate.steps_in(graph, [], tree)

	## The steps of a path, where `defs` are the kept definitions in scope.
	steps_in : Code.Graph, List({ id : U32, value : Code.Tree }), Code.Tree -> Try(List(Step), Ql.Error)
	steps_in = |graph, defs, tree| match tree {
		Param(_) => Ok([])
		Def(n) => match defs.find_last(|d| d.id == n) {
			Ok(d) => Translate.steps_in(graph, defs, d.value)
			Err(_) => Err(Unsupported("a value is read before its block computes it"))
		}
		Block({ defs: more, end: Value([one]) }) => Translate.steps_in(graph, defs.concat(more), one)
		Op({ op: Unwrap, args: [inner], .. }) => Translate.steps_in(graph, defs, inner)
		Op({ op: Field(name), args: [inner], .. }) | Op({ op: OptField(name), args: [inner], .. }) =>
			Ok(Translate.steps_in(graph, defs, inner)?.append(Step.Field(name)))
		Op({ op: Prim({ id, .. }), args: [list, Op({ op: Closure(row), args: [], .. })], .. }) if id == Code.prim(List.map) => {
			outer = Translate.steps_in(graph, defs, list)?
			inner = Translate.steps(graph, graph.to_tree(row))?
			Ok(outer.append(Step.Each).concat(inner))
		}
		Op({ op, .. }) => Err(Unsupported("a field path reads fields only; this one calls `${Translate.describe(op)}`"))
		_ => Err(Unsupported("a field path reads fields only"))
	}

	## A path as a field definition names it: `items[*].qty`.
	spell : List(Step) -> Str
	spell = |path| path.fold(
		"",
		|text, step| match step {
			Each => "${text}[*]"
			Field(name) => if (text.is_empty()) Ql.ident(name) else "${text}.${Ql.member(name)}"
		},
	)

	## What an op is, for a refusal that names it.
	describe : Code.Op -> Str
	describe = |op| match op {
		Prim({ owner, method, .. }) => "${owner}.${method}"
		Call(_) => "a helper"
		Closure(_) | Lambda(_) => "a function"
		Lit(_) => "a literal"
		Record(_) => "a record"
		Tuple => "a tuple"
		List => "a list"
		Tag(name) => name
		Wrap(name) => name
		Index(_) => "a tuple position"
		Payload(name, _) => "the payload of ${name}"
		Item => "a list index"
		Switch(_) => "a branch"
		And(_) => "`and`"
		Or(_) => "`or`"
		ForRange(_) | ForList(_) | Loop(_) => "a loop"
		Crash => "`crash`"
		Derived(method, _) => method
		Unwrap | Field(_) | OptField(_) => "a field read"
	}

	# ------------------------------------------------------------ captured values

	## The SurrealQL value of a value captured from around the clause, by the
	## slot type the graph gives it. An `Id` is its record id, a `Datetime`
	## its datetime. A captured `Link` is refused. Capture its `id()` instead.
	## An optional field that a captured record does not hold (`Absent`) is
	## left out of its object, as a stored row leaves out a field that is
	## `NONE`. A value whose type holds an opaque type is the bytes its own
	## encoder wrote in `Encode.Bind` (`Query.filter_with`), which
	## read back as `Encode.Format` writes a row.
	captured : Code.Ty, Code.Value -> Try(Ql.Value, Ql.Error)
	captured = |ty, value| match (ty, value) {
		(_, Encoded(bytes)) => Encode.bound(bytes).map_err(|_| Unsupported("a captured `${ty.name()}` whose bytes `Encode.Bind` did not write"))
		(Named(name, _, backing), Wrap(inner)) => match Types.nominal(name) {
			Id => match Translate.captured(backing, inner)? {
				Object(fields) => match (Translate.named_str(fields, "table"), Translate.named_str(fields, "key")) {
					(Ok(table), Ok(key)) => Ok(Ql.Value.Record({ table, key }))
					_ => Err(Unsupported("a captured id without its table and key"))
				}
				_ => Err(Unsupported("a captured id without its table and key"))
			}
			Datetime => match Translate.captured(backing, inner)? {
				Object(fields) => Translate.named_str(fields, "iso").map_ok(|iso| Ql.Value.Datetime(iso)).map_err(|_| Unsupported("a captured datetime without its text"))
				_ => Err(Unsupported("a captured datetime without its text"))
			}
			Link => Err(Unsupported("a captured `Link` has no SurrealQL value; capture its `id()`"))
			Duration => match Translate.captured(backing, inner)? {
				Object(fields) => match fields.find_first(|f| f.name == "nanos").map_ok(|f| Ql.int_of(f.value)) {
					Ok(Ok(n)) if n >= 0 => Ok(Ql.Value.Duration(n.to_u64_wrap()))
					_ => Err(Unsupported("a captured duration without its nanoseconds"))
				}
				_ => Err(Unsupported("a captured duration without its nanoseconds"))
			}
			DbFn => Err(Translate.not_constant)
			TimeKey => match Translate.captured(backing, inner)? {
				Object(fields) => match (fields.find_first(|f| f.name == "series"), fields.find_first(|f| f.name == "time")) {
					(Ok(series), Ok(time)) => Ok(Ql.Value.Array([series.value, time.value]))
					_ => Err(Unsupported("a captured time key without its series and its time"))
				}
				_ => Err(Unsupported("a captured time key without its series and its time"))
			}
			Geometry(_) => Translate.geojson(name, Translate.captured(backing, inner)?)
			Scalar(surql) => Translate.v2_scalar(surql, Translate.captured(backing, inner)?)
			_ => Translate.captured(backing, inner)
		}
		(_, Int(n)) => Translate.captured_int(ty, n.to_i128())
		(_, U128(n)) => match n.to_i128_try() {
			Ok(i) => Translate.captured_int(ty, i)
			Err(_) => Err(Unsupported("a captured integer outside the range of a SurrealDB int"))
		}
		(F32, Frac(f)) => Ok(Ql.Value.F32(f.to_f32_wrap()))
		(_, Frac(f)) => Ok(Ql.Value.Float(f))
		(_, Dec(d)) => Ok(Ql.Value.Decimal(d))
		(_, Bool(b)) => Ok(Ql.Value.Bool(b))
		(_, Str(s)) => Ok(Ql.Value.Str(s))
		(Record(fields), Record(values)) => {
			pairs = List.map2(fields, values, |f, v| { f, v }).drop_if(
				|p| match p.v {
					Absent => Bool.True
					_ => Bool.False
				},
			)
			Ok(Ql.Value.Object(pairs.map_try(|p| Ok({ name: p.f.name, value: Translate.captured(p.f.ty, p.v)? }))?))
		}
		(ListOf(item), List(values)) => Ok(Ql.Value.Array(values.map_try(|v| Translate.captured(item, v))?))
		(TagUnion(variants), Tag(name, payloads)) => {
			types = match variants.find_first(|v| v.name == name) {
				Ok(v) => v.payloads
				Err(_) => return Err(Unsupported("a captured tag `${name}` outside its union"))
			}
			values = List.map2(types, payloads, |t, v| { t, v }).map_try(|p| Translate.captured(p.t, p.v))?
			kind = { name: "kind", value: Ql.Value.Str(name) }
			match (types, values) {
				([], _) => Ok(Ql.Value.Str(name))
				([only], [Object(fields)]) if Translate.is_record(only) => Ok(Ql.Value.Object(List.concat([kind], fields)))
				(_, [one]) => Ok(Ql.Value.Object([kind, { name: "value", value: one }]))
				_ => Ok(Ql.Value.Object([kind, { name: "value", value: Ql.Value.Array(values) }]))
			}
		}
		_ => Err(Unsupported("a captured `${ty.name()}` has no SurrealQL value"))
	}

	## The value of a captured type of CBOR v2 (`Types.Scalar`), from the
	## object of its backing record: `Surreal.Date` is `{ days }`.
	v2_scalar : Str, Ql.Value -> Try(Ql.Value, Ql.Error)
	v2_scalar = |surql, backing| {
		bad = Unsupported("a captured `${surql}` without its parts")
		fields = match backing {
			Object(f) => f
			_ => return Err(bad)
		}
		int = |name| match fields.find_first(|f| f.name == name).map_ok(|f| Ql.int_of(f.value)) {
			Ok(Ok(n)) => n.to_i64_try().map_err(|_| bad)
			_ => Err(bad)
		}
		match surql {
			"regex" => Translate.named_str(fields, "pattern").map_ok(|t| Ql.Value.Regex(t)).map_err(|_| bad)
			"bigdecimal" => Translate.named_str(fields, "text").map_ok(|t| Ql.Value.BigDecimal(t)).map_err(|_| bad)
			"date" => Ok(Ql.Value.Date(int("days")?.to_i32_try().map_err(|_| bad)?))
			"time" => Ok(Ql.Value.Time(int("nanos")?.to_u64_try().map_err(|_| bad)?))
			"timestamp" => Ok(Ql.Value.Timestamp({ secs: int("secs")?, nanos: int("nanos")?.to_u32_try().map_err(|_| bad)? }))
			"interval" => Ok(Ql.Value.Interval({ months: int("months")?.to_i32_try().map_err(|_| bad)?, days: int("days")?.to_i32_try().map_err(|_| bad)?, micros: int("micros")? }))
			_ => Err(bad)
		}
	}

	## A captured integer as the value of its type: `5u8` for a `U8`, as
	## `Encode.Format` writes it.
	captured_int : Code.Ty, I128 -> Try(Ql.Value, Ql.Error)
	captured_int = |ty, n| {
		out = Unsupported("a captured integer outside the range of its type")
		match ty {
			I8 => n.to_i8_try().map_ok(|v| Ql.Value.I8(v)).map_err(|_| out)
			U8 => n.to_u8_try().map_ok(|v| Ql.Value.U8(v)).map_err(|_| out)
			I16 => n.to_i16_try().map_ok(|v| Ql.Value.I16(v)).map_err(|_| out)
			U16 => n.to_u16_try().map_ok(|v| Ql.Value.U16(v)).map_err(|_| out)
			I32 => n.to_i32_try().map_ok(|v| Ql.Value.I32(v)).map_err(|_| out)
			U32 => n.to_u32_try().map_ok(|v| Ql.Value.U32(v)).map_err(|_| out)
			U64 => n.to_u64_try().map_ok(|v| Ql.Value.U64(v)).map_err(|_| out)
			_ => n.to_i64_try().map_ok(|v| Ql.Value.Int(v)).map_err(|_| Unsupported("a captured integer outside the range of a SurrealDB int"))
		}
	}

	## Whether a captured value of this type has a SurrealQL value
	## (`captured`), or why not. A clause reads the type of each captured
	## value when the compiler runs it, so this check is a compile error.
	bindable : Code.Ty, Bool -> Try({}, Str)
	bindable = |ty, encoded| match ty {
		Named(name, _, backing) =>
			match Types.nominal(name) {
				Link => Err("a captured `Link` has no SurrealQL value; capture its `id()`")
				DbFn => Err("a captured database function has no SurrealQL value; name the function in the clause")
				Id | Datetime | Duration | TimeKey | Geometry(_) | Scalar(_) => Ok({})
				_ => Translate.bindable(backing, encoded)
			}
		Record(fields) => fields.map_try(|f| Translate.bindable(f.ty, encoded)).map_ok(|_| {})
		Tuple(items) => items.map_try(|t| Translate.bindable(t, encoded)).map_ok(|_| {})
		ListOf(item) => Translate.bindable(item, encoded)
		TagUnion(variants) => variants.map_try(|v| v.payloads.map_try(|t| Translate.bindable(t, encoded))).map_ok(|_| {})
		Fn(_, _) => Err("a captured function has no SurrealQL value; call it in the clause")
		Opaque(_, _, _) if encoded => Ok({})
		Opaque(name, _, _) => Err("a captured `${name}` has no SurrealQL value; name the format of its values with `Code.Binds`")
		_ => Ok({})
	}

	## The GeoJSON object of a captured geometry, from the value of its
	## backing, in which each point is already its GeoJSON object. SurrealDB
	## reads an object of this shape as a geometry:
	## `{ type: 'Point', coordinates: [lon, lat] }`.
	geojson : Str, Ql.Value -> Try(Ql.Value, Ql.Error)
	geojson = |name, value| {
		shaped = |kind, coordinates| Ql.Value.Object([{ name: "type", value: Ql.Value.Str(kind) }, { name: "coordinates", value: coordinates }])
		field = |fields, key| match fields.find_first(|f| f.name == key) {
			Ok(f) => Ok(f.value)
			Err(_) => Err(Unsupported("a captured `${name}` without its `${key}`"))
		}
		coordinates = |v| match v {
			Object(fields) => field(fields, "coordinates")
			_ => Err(Unsupported("a captured `${name}` whose parts are not geometries"))
		}
		all = |v| match v {
			Array(items) => items.map_try(coordinates).map_ok(|xs| Ql.Value.Array(xs))
			_ => Err(Unsupported("a captured `${name}` that is not a list"))
		}
		match (name, value) {
			("Surreal.Point", Object(fields)) => Ok(shaped("Point", Ql.Value.Array([field(fields, "lon")?, field(fields, "lat")?])))
			("Surreal.Line", _) => Ok(shaped("LineString", all(value)?))
			("Surreal.Polygon", Object(fields)) => {
				exterior = all(field(fields, "exterior")?)?
				holes = match field(fields, "holes")? {
					Array(rings) => rings.map_try(all)?
					_ => []
				}
				Ok(shaped("Polygon", Ql.Value.Array(List.concat([exterior], holes))))
			}
			("Surreal.MultiPoint", _) => Ok(shaped("MultiPoint", all(value)?))
			("Surreal.MultiLine", _) => Ok(shaped("MultiLineString", all(value)?))
			("Surreal.MultiPolygon", _) => Ok(shaped("MultiPolygon", all(value)?))
			("Surreal.Collection", Array(items)) => Ok(Ql.Value.Object([{ name: "type", value: Ql.Value.Str("GeometryCollection") }, { name: "geometries", value: Ql.Value.Array(items) }]))
			("Surreal.Geometry", _) => Ok(value)
			_ => Err(Translate.geometry_parameter(name))
		}
	}

	named_str : List({ name : Str, value : Ql.Value }), Str -> Try(Str, [Missing])
	named_str = |fields, name| match fields.find_first(|f| f.name == name) {
		Ok({ value: Str(s), .. }) => Ok(s)
		_ => Err(Missing)
	}

	## Whether a union payload of this type is spread next to `kind`: a
	## record, or a nominal of the app over one (`Types.unwrap`), as in the
	## schema and `Encode.tagged`. A type of `Surreal`, such as a geometry or
	## a `Link`, is `value`.
	is_record : Code.Ty -> Bool
	is_record = |ty| match Types.unwrap(ty) {
		Record(_) => Bool.True
		_ => Bool.False
	}

	# ------------------------------------------------------------ reads

	## What a value of a clause reads, for the tables that a live query
	## watches (`Translate.reads`). `At` is a place, by its `via`:
	##
	## | `via` | The place |
	## | --- | --- |
	## | `Doc` | A value in a record that the statement reads: the row, a field of it, a field of a linked row after a hop |
	## | `Ref(row)` | A record that a link points at, before a field of it is read: a `Linked` of a read row, `link.get()`. A field read through it is a hop to a row of type `row` |
	## | `Records` | A list of records whose table the live query watches already: the edges of `outgoing`, `incoming`, an `Out` or an `In`, and `rows()` |
	##
	## `path` is the place as a `read` statement tests it, from the row of
	## the statement (`items[*].product`, `<-cares_for.in`, `kennel.site`),
	## `lists` counts the lists on it, `edge` says it is an edge record, and
	## `ty` is its type. `Fields` is a record the clause built, `Pair` a row
	## with its edges, `Either` the value of a branch, which is one of its
	## arms, and `Table` a table that the clause names.
	Reach := [
		At({ path : Str, lists : U64, edge : Bool, via : [Doc, Ref(Code.Ty), Records], ty : Code.Ty }),
		Fields(List({ name : Str, reach : Reach })),
		Pair(List(Reach)),
		Either(List(Reach)),
		Table({ name : Str, edge : Bool }),
		Nothing,
	]

	## What a live query watches for one read of a clause: a hop through a
	## link, a read of the record at `path` that a link points at, whose
	## row is `target`, or the edges of an `Out` or `In` field of the row,
	## whose `node` is the end of an edge that is the row. `read` is the
	## field of that record that the clause reads, as SurrealDB spells it,
	## or `Whole` for the whole record. `Every` is an edge table whose edges
	## the clause reads off a record other than the row, `edges_from` of a
	## linked row: a write to it can change every row.
	Read : [Hop({ path : Str, target : Code.Ty, lists : U64, read : [Field(Str), Whole] }), Edges({ name : Str, node : Str }), Every(Str)]

	## The walk of `Translate.reads`: what the row's parameters and kept
	## nodes reach.
	Walk : { graph : Code.Graph, row : U32, params : List(Reach), nodes : List({ id : U32, reach : Reach }), depth : U64, extensions : List(Extension) }

	Reached : { reach : Reach, reads : List(Read) }

	## The row of a table, as a clause reads it: the record at `""`. It has
	## the type of the parameter that reads it (`Translate.retyped`).
	row_reach : Bool -> Reach
	row_reach = |edge| Reach.At({ path: "", lists: 0, edge, via: Doc, ty: Record([]) })

	## A row and its edges in `table`, after `->` (`outgoing`) or `<-`
	## (`incoming`) the row's own place.
	with_edges : Reach, Str, Str -> Reach
	with_edges = |row, arrow, table| match row {
		At(p) => Reach.Pair([row, Translate.edges_reach(p, arrow, table)])
		Pair(parts) => match parts.first() {
			Ok(At(p)) => Reach.Pair(parts.append(Translate.edges_reach(p, arrow, table)))
			_ => Reach.Nothing
		}
		_ => Reach.Nothing
	}

	edges_reach : { path : Str, lists : U64, edge : Bool, via : [Doc, Ref(Code.Ty), Records], ty : Code.Ty }, Str, Str -> Reach
	edges_reach = |p, arrow, table| Reach.At({ path: "${p.path}${arrow}${Ql.ident(table)}", lists: p.lists, edge: Bool.True, via: Records, ty: Record([]) })

	## The record ids of the rows of a table in a clause.
	rows_at : Str -> Str
	rows_at = |name| "(SELECT VALUE id FROM ${Ql.ident(name)})"

	## What a clause reads through links, for the tables a live query
	## watches, and what its result is. A read is a field read through a
	## link (`Hop`), at the path of the link, and an `Out` or `In` field of
	## the row (`Edges`). The result is read whole: a whole linked row in it
	## is a hop too, and a `Link` in it is a record id. `params` are what the
	## parameters are. A form that the translator refuses reads nothing.
	reads : List(Extension), Code.Graph, List(Reach) -> Reached
	reads = |extensions, graph, params| {
		root = graph.root_row()
		got = Translate.reach(graph.to_tree(root.id), { graph, row: root.id, params, nodes: [], depth: 0, extensions })
		{ reach: got.reach, reads: got.reads.concat(Translate.read_whole(got.reach)) }
	}

	reach : Code.Tree, Walk -> Reached
	reach = |tree, w| match tree {
		Param(k) => match (w.params.get(k.to_u64()), w.graph.row(w.row).params.get(k.to_u64())) {
			(Ok(found), Ok(ty)) => Translate.reached_as(Translate.retyped(found, ty))
			_ => Translate.reached_as(Reach.Nothing)
		}
		Def(n) => match w.nodes.find_last(|entry| entry.id == n) {
			Ok(entry) => Translate.reached_as(entry.reach)
			Err(_) => Translate.reached_as(Reach.Nothing)
		}
		Block(block) => {
			inner = block.defs.fold(
				{ walk: w, reads: [] },
				|acc, def| {
					got = Translate.reach(def.value, acc.walk)
					{ walk: { ..acc.walk, nodes: acc.walk.nodes.append({ id: def.id, reach: got.reach }) }, reads: acc.reads.concat(got.reads) }
				},
			)
			match block.end {
				Value([one]) => Translate.with_reads(inner.reads, Translate.reach(one, inner.walk))
				_ => { reach: Reach.Nothing, reads: inner.reads }
			}
		}
		Op(node) => Translate.reach_op(node.op, node.args, node.ty, w)
		Input(_) | Arg(_) | Out(_) => Translate.reached_as(Reach.Nothing)
	}

	reach_op : Code.Op, List(Code.Tree), Code.Ty, Walk -> Reached
	reach_op = |operation, args, ty, w| {
		of = |tree| Translate.reach(tree, w)
		holder = |f| match args {
			[one] => {
				got = of(one)
				Translate.with_reads(got.reads, Translate.each_arm(got.reach, f))
			}
			_ => Translate.consumed(args, w)
		}
		match operation {
			Prim(call) => Translate.reach_prim(call, args, ty, w)
			Call(row) => {
				got = args.map(of)
				Translate.with_reads(got.join_map(|g| g.reads), Translate.expand_reach(row, got.map(|g| g.reach), w))
			}
			Record(names) => {
				got = args.map(of)
				{ reach: Reach.Fields(List.map2(names, got, |name, g| { name, reach: g.reach })), reads: got.join_map(|g| g.reads) }
			}
			Field(name) | OptField(name) => holder(|h| Translate.member_reach(h, name, ty))
			Index(position) => holder(
				|h| match h {
					Pair(parts) => match parts.get(position) {
						Ok(part) => Translate.reached_as(part)
						Err(_) => Translate.reached_as(Reach.Nothing)
					}
					_ => Translate.reached_as(Reach.Nothing)
				},
			)
			Payload(tag, k) => holder(|h| Translate.reached_as(Translate.payload_reach(h, tag, k, ty)))
			Unwrap => holder(Translate.reached_as)
			Wrap(name) => match (Types.nominal(name), args) {
				(Try, [Op({ op: Tag("Ok"), args: [payload], .. })]) => of(payload)
				(Other, [inner]) | (Bool, [inner]) | (Linked, [inner]) | (Out, [inner]) | (In, [inner]) => of(inner)
				_ => Translate.consumed(args, w)
			}
			# The scrutinee is tested, and a payload of it is read with
			# `Payload`. The value is one of the arms.
			Switch(_) => match args {
				[scrutinee, .. as arms] => {
					tested = of(scrutinee)
					got = arms.map(of)
					{ reach: Reach.Either(got.map(|g| g.reach)), reads: tested.reads.concat(got.join_map(|g| g.reads)) }
				}
				[] => Translate.reached_as(Reach.Nothing)
			}
			_ => Translate.consumed(args, w)
		}
	}

	reach_prim : Call, List(Code.Tree), Code.Ty, Walk -> Reached
	reach_prim = |call, args, ty, w| {
		of = |tree| Translate.reach(tree, w)
		match (Translate.form(call.id, w.extensions), args) {
			(Ok(LinkGet), [link]) => {
				got = of(link)
				Translate.with_reads(
					got.reads,
					Translate.each_arm(
						got.reach,
						|l| match l {
							At(p) => Translate.reached_as(Reach.At({ ..p, edge: Bool.False, via: Ref(ty), ty }))
							_ => Translate.reached_as(Reach.Nothing)
						},
					),
				)
			}
			(Ok(Rows), [table]) => {
				got = of(table)
				Translate.with_reads(
					got.reads,
					Translate.each_arm(
						got.reach,
						|t| match t {
							Table(found) => Translate.reached_as(Reach.At({ path: Translate.rows_at(found.name), lists: 0, edge: found.edge, via: Records, ty }))
							_ => Translate.reached_as(Reach.Nothing)
						},
					),
				)
			}
			(Ok(EdgesOf(arrow)), [table, row]) => {
				t = of(table)
				r = of(row)
				seen = t.reads.concat(r.reads)
				match (t.reach, r.reach) {
					(Table(found), At(p)) => {
						at_row = match p.via {
							Doc => p.path.is_empty() and p.lists == 0
							_ => Bool.False
						}
						# The edges of the row are the edge statement's, as for an `Out` field.
						watch = if (at_row) Edges({ name: found.name, node: if (arrow == "->") "in" else "out" }) else Every(found.name)
						{ reach: Reach.At({ path: "${p.path}${arrow}${Ql.ident(found.name)}", lists: p.lists, edge: Bool.True, via: Records, ty }), reads: seen.append(watch) }
					}
					(Table(found), _) => { reach: Reach.Nothing, reads: seen.append(Every(found.name)) }
					_ => { reach: Reach.Nothing, reads: seen }
				}
			}
			(Ok(TableOf), [Op({ op: Lit(Str(name)), .. })]) => Translate.reached_as(Reach.Table({ name, edge: Bool.False }))
			(Ok(RelationOf), [Op({ op: Lit(Str(name)), .. }), _, _]) => Translate.reached_as(Reach.Table({ name, edge: Bool.True }))
			(Ok(Builtin({ owner: "List", method: "any" })), [list, f]) | (Ok(Builtin({ owner: "List", method: "all" })), [list, f]) | (Ok(Builtin({ owner: "List", method: "map" })), [list, f]) | (Ok(Builtin({ owner: "List", method: "join_map" })), [list, f]) | (Ok(Builtin({ owner: "List", method: "count_if" })), [list, f]) => Translate.reach_lambda(list, f, Each, w)
			(Ok(Builtin({ owner: "List", method: "keep_if" })), [list, f]) | (Ok(Builtin({ owner: "List", method: "drop_if" })), [list, f]) => Translate.reach_lambda(list, f, Kept, w)
			(Ok(Builtin({ owner: "List", method: "find_first" })), [list, f]) => Translate.reach_lambda(list, f, Found(ty), w)
			(Ok(Builtin({ owner: "Try", method: "map_ok" })), [m, f]) => Translate.reach_lambda(m, f, Mapped, w)
			# The count of a list reads no element.
			(Ok(Builtin({ owner: "List", method: "len" })), [list]) | (Ok(Builtin({ owner: "List", method: "is_empty" })), [list]) => Translate.with_reads(of(list).reads, Translate.reached_as(Reach.Nothing))
			_ => Translate.consumed(args, w)
		}
	}

	## A list operation with a closure, as `Translate.lambda` reads it, and
	## `map_ok`: the closure's row with its element. The closure's result is
	## read whole. `gives` is the result of the operation: none, the list
	## (`keep_if`, `drop_if`), an element (`find_first`), or the closure's
	## result (`map_ok`).
	reach_lambda : Code.Tree, Code.Tree, [Each, Kept, Found(Code.Ty), Mapped], Walk -> Reached
	reach_lambda = |source, f, gives, w| match (f, Translate.closure_element(f, w)) {
		(Op({ op: Closure(row), args: captures, .. }), Ok(element_ty)) => {
			list = Translate.reach(source, w)
			held = captures.map(|c| Translate.reach(c, w))
			item = match gives {
				Mapped => Translate.payload_reach(list.reach, "Ok", 0, element_ty)
				Each | Kept | Found(_) => Translate.element_reach(list.reach, element_ty)
			}
			result = Translate.expand_reach(row, held.map(|h| h.reach).append(item), w)
			seen = list.reads.concat(held.join_map(|h| h.reads)).concat(result.reads)
			match gives {
				Each => { reach: Reach.Nothing, reads: seen.concat(Translate.read_whole(result.reach)) }
				Kept => { reach: list.reach, reads: seen.concat(Translate.read_whole(result.reach)) }
				Found(found_ty) => { reach: Translate.retyped(item, found_ty), reads: seen.concat(Translate.read_whole(result.reach)) }
				Mapped => { reach: result.reach, reads: seen }
			}
		}
		_ => Translate.consumed([source, f], w)
	}

	## The type of the element of a closure's row: its last parameter.
	closure_element : Code.Tree, Walk -> Try(Code.Ty, [NotAClosure])
	closure_element = |f, w| match f {
		Op({ op: Closure(row), .. }) => w.graph.row(row).params.last().map_err(|_| NotAClosure)
		_ => Err(NotAClosure)
	}

	## A row of the graph with its parameters bound, as `Translate.expand`
	## reads a call.
	expand_reach : U32, List(Reach), Walk -> Reached
	expand_reach = |row, params, w|
		if w.depth > 32 or w.graph.row(row).recursive {
			Translate.reached_as(Reach.Nothing)
		} else {
			Translate.reach(w.graph.to_tree(row), { ..w, row, params, nodes: [], depth: w.depth + 1 })
		}

	## The arguments of an operation that reads them as values: each is
	## read whole.
	consumed : List(Code.Tree), Walk -> Reached
	consumed = |args, w| {
		got = args.map(|a| Translate.reach(a, w))
		{ reach: Reach.Nothing, reads: got.join_map(|g| g.reads.concat(Translate.read_whole(g.reach))) }
	}

	reached_as : Reach -> Reached
	reached_as = |r| { reach: r, reads: [] }

	with_reads : List(Read), Reached -> Reached
	with_reads = |earlier, got| { ..got, reads: earlier.concat(got.reads) }

	## A step over each arm of a branch.
	each_arm : Reach, (Reach -> Reached) -> Reached
	each_arm = |r, step| match r {
		Either(arms) => {
			got = arms.map(|a| Translate.each_arm(a, step))
			{ reach: Reach.Either(got.map(|g| g.reach)), reads: got.join_map(|g| g.reads) }
		}
		_ => step(r)
	}

	## A value of the type of the parameter that reads it.
	retyped : Reach, Code.Ty -> Reach
	retyped = |r, ty| match (r, Types.unwrap(ty)) {
		(At(p), _) => Reach.At({ ..p, ty })
		(Pair(parts), Tuple(types)) => Reach.Pair(List.map2(parts, types, Translate.retyped))
		_ => r
	}

	## A place of a value of type `ty`: a `Linked` is a record that a link
	## points at.
	place_of : Str, U64, Bool, Code.Ty -> Reach
	place_of = |path, lists, edge, ty| match Types.site_in(ty, Bool.True) {
		Ok(found) if found.linked => Reach.At({ path, lists, edge: Bool.False, via: Ref(found.target), ty })
		_ => Reach.At({ path, lists, edge, via: Doc, ty })
	}

	## A field of a value, as `Translate.member` reads it. A field read off
	## a record that a link points at is a hop. Its `id` is the record id
	## the link holds, and is not.
	member_reach : Reach, Str, Code.Ty -> Reached
	member_reach = |holder, name, ty| match holder {
		At(p) => {
			path =
				if p.path.is_empty() {
					Translate.spell_name(name, p.edge)
				} else if p.edge {
					"${p.path}.${Translate.spell_name(name, Bool.True)}"
				} else {
					Types.dot(p.path, name)
				}
			match (p.via, ty) {
				(Ref(_), _) if name == "id" => Translate.reached_as(Reach.Nothing)
				(Ref(target), _) => { reach: Translate.place_of(path, p.lists, Bool.False, ty), reads: [Hop({ path: p.path, target, lists: p.lists, read: Field(Ql.ident(name)) })] }
				(Records, _) => Translate.reached_as(Reach.Nothing)
				(Doc, Named(kind, _, _)) if Types.nominal(kind) == Out => Translate.edge_field(p, name, "->", "in", ty)
				(Doc, Named(kind, _, _)) if Types.nominal(kind) == In => Translate.edge_field(p, name, "<-", "out", ty)
				(Doc, _) => Translate.reached_as(Translate.place_of(path, p.lists, Bool.False, ty))
			}
		}
		Fields(fields) => match fields.find_first(|f| f.name == name) {
			Ok(f) => Translate.reached_as(f.reach)
			Err(_) => Translate.reached_as(Reach.Nothing)
		}
		_ => Translate.reached_as(Reach.Nothing)
	}

	## An `Out` or `In` field: the edges of the record. The edge statement
	## of a live query watches the edges of the row only.
	edge_field : { path : Str, lists : U64, edge : Bool, via : [Doc, Ref(Code.Ty), Records], ty : Code.Ty }, Str, Str, Str, Code.Ty -> Reached
	edge_field = |p, name, arrow, node, ty| {
		edges = if (p.path.is_empty() and p.lists == 0) [Edges({ name, node })] else []
		{ reach: Reach.At({ path: "${p.path}${arrow}${Ql.ident(name)}", lists: p.lists, edge: Bool.True, via: Records, ty }), reads: edges }
	}

	## The element of a list, as `Translate.lambda` binds it. An element of
	## a list of records is the record, and of a list of links or `Linked`
	## rows the list itself (`$parent.id IN wishlist`).
	element_reach : Reach, Code.Ty -> Reach
	element_reach = |list, ty| match list {
		At(p) => match p.via {
			Records => Reach.At({ path: p.path, lists: p.lists + 1, edge: p.edge, via: Doc, ty })
			Doc => match Types.site_in(ty, Bool.True) {
				Ok(found) if !found.is_id => Translate.place_of(p.path, p.lists + 1, Bool.False, ty)
				_ => Translate.place_of("${p.path}[*]", p.lists + 1, Bool.False, ty)
			}
			Ref(_) => Reach.Nothing
		}
		Either(arms) => Reach.Either(arms.map(|a| Translate.element_reach(a, ty)))
		_ => Reach.Nothing
	}

	## A payload, as `Translate.payload` reads it: the value of a `Try` is
	## at its place, and a union arm at `value`, unless it is a record.
	payload_reach : Reach, Str, U64, Code.Ty -> Reach
	payload_reach = |holder, tag, k, ty| match holder {
		At(p) => match (p.ty, Types.unwrap(p.ty)) {
			(Named(name, _, _), _) if Types.nominal(name) == Try => Translate.place_of(p.path, p.lists, p.edge, ty)
			(_, TagUnion(variants)) => match variants.find_first(|v| v.name == tag) {
				Ok({ payloads: [one], .. }) =>
					if Translate.is_record(one) {
						Translate.place_of(p.path, p.lists, p.edge, ty)
					} else {
						Translate.place_of(Types.dot(p.path, "value"), p.lists, Bool.False, ty)
					}
				Ok(_) => Translate.place_of("${Types.dot(p.path, "value")}[${k.to_str()}]", p.lists, Bool.False, ty)
				Err(_) => Reach.Nothing
			}
			_ => Reach.Nothing
		}
		Either(arms) => Reach.Either(arms.map(|a| Translate.payload_reach(a, tag, k, ty)))
		_ => Reach.Nothing
	}

	## What a value read whole reads: each `Linked` in it, at any depth
	## (`Types.whole_reads`), also in the records of a list of them, and the
	## edges of each `Out` and `In` field of the row. A `Link` in it is its
	## record id.
	read_whole : Reach -> List(Read)
	read_whole = |r| match r {
		At(p) => match p.via {
			Ref(target) => [Hop({ path: p.path, target, lists: p.lists, read: Whole })].concat(Translate.linked_reads(target, p.path, p.lists, Bool.False))
			Doc => Translate.linked_reads(p.ty, p.path, p.lists, p.edge).concat(if (p.path.is_empty() and p.lists == 0) Translate.row_edges(p.ty) else [])
			Records => match p.ty {
				ListOf(item) | Named(_, _, ListOf(item)) => Translate.linked_reads(item, p.path, p.lists + 1, p.edge)
				_ => []
			}
		}
		Fields(fields) => fields.join_map(|f| Translate.read_whole(f.reach))
		Pair(parts) | Either(parts) => parts.join_map(Translate.read_whole)
		Table(_) | Nothing => []
	}

	## The `Linked` rows of a whole value at `path`. The fields of an edge
	## after a path are spelled as at the row, `in` and `out`.
	linked_reads : Code.Ty, Str, U64, Bool -> List(Read)
	linked_reads = |ty, path, lists, edge| {
		spelled = |name| Translate.spell_name(name, edge)
		sites = match Types.unwrap(ty) {
			Record(fields) if edge and !path.is_empty() => fields.join_map(|f| Types.whole_reads(f.ty, "${path}.${spelled(f.name)}", lists, Ql.ident, []))
			_ => Types.whole_reads(ty, path, lists, spelled, [])
		}
		sites.map(|site| Hop({ path: site.path, target: site.target, lists: site.lists, read: Whole }))
	}

	## The edges of each `Out` and `In` field of a whole row, and the
	## `Linked` rows of each edge.
	row_edges : Code.Ty -> List(Read)
	row_edges = |ty| match Types.unwrap(ty) {
		Record(fields) => fields.join_map(
			|f| match f.ty {
				Named(kind, _, edges) if Types.nominal(kind) == Out => [Edges({ name: f.name, node: "in" })].concat(Translate.edge_rows(edges, "->${Ql.ident(f.name)}"))
				Named(kind, _, edges) if Types.nominal(kind) == In => [Edges({ name: f.name, node: "out" })].concat(Translate.edge_rows(edges, "<-${Ql.ident(f.name)}"))
				_ => []
			},
		)
		_ => []
	}

	edge_rows : Code.Ty, Str -> List(Read)
	edge_rows = |edges, path| match edges {
		ListOf(item) => Translate.linked_reads(item, path, 1, Bool.True)
		_ => []
	}

	# ------------------------------------------------------------ text

	## A binding as a SurrealQL expression that stands on its own.
	text : Binding -> Try(Str, Ql.Error)
	text = |binding| match binding {
		Expr(s) | Infix(s) | Maybe(s) => Ok(s)
		Moment(s) => Ok("<string>${s}")
		ListOf(list) => match list.items {
			Records({ edge, row: Typed(row), .. }) => Translate.whole_row(list.at, row, edge)
			_ => Ok(list.at)
		}
		Union(u) => Ok(u.at)
		Row(r) => match r.of {
			Doc(_) => Ok(if (r.at.is_empty()) "$this" else r.at)
			Ref(row_ty) => Translate.whole_row(r.at, row_ty, r.edge)
			# A result row read by its column names, in the outer query of a
			# subquery: the whole row is `$this`.
			Obj => Ok(if (r.at.is_empty()) "$this" else r.at)
		}
		Fields(fields) => {
			parts = fields.map_try(|f| Ok("${Ql.member(f.name)}: ${Translate.text(f.binding)?}"))?
			Ok(if (parts.is_empty()) "{}" else "{ ${Str.join_with(parts, ", ")} }")
		}
		WithEdges(_, _) => Err(Unsupported("a row with its edges has no SurrealQL value; take `.0` or the edges at `.1`, `.2`"))
		Params => Err(Unsupported("the parameter record has no SurrealQL value; read one of its fields"))
		Function(f) => Err(Unsupported("the database function `fn::${f.name}` has no SurrealQL value; call it with `call1`, `call2` or `call3`"))
		Table(t) => Err(Unsupported("the table `${t.name}` has no SurrealQL value; read its `rows()` or an `id(..)`"))
		Group(_) | Column(_) => Err(Unsupported("a group's rows have no SurrealQL value; aggregate them with `len`, `keep_if(..).len()` or `map(..).sum()`"))
	}

	## A binding as the operand of an operator: an infix expression is
	## parenthesised, so nesting never depends on SurrealQL's precedence.
	operand : Binding -> Try(Str, Ql.Error)
	operand = |binding| match binding {
		Infix(s) => Ok("(${s})")
		other => Translate.text(other)
	}

	expr : Code.Tree, Env -> Try(Str, Ql.Error)
	expr = |tree, env| Translate.text(Translate.eval(tree, env)?)

	arg : Code.Tree, Env -> Try(Str, Ql.Error)
	arg = |tree, env| Translate.operand(Translate.eval(tree, env)?)

	# ------------------------------------------------------------ evaluation

	## What one tree stands for. A kept node is computed once, where its block
	## defines it, and each read of it is what it stands for.
	eval : Code.Tree, Env -> Try(Binding, Ql.Error)
	eval = |tree, env| match tree {
		Param(k) => match env.params.get(k.to_u64()) {
			Ok(binding) => Ok(binding)
			Err(_) => Err(Unsupported("this clause reads a parameter it does not take"))
		}
		Def(n) => match env.nodes.find_last(|entry| entry.id == n) {
			Ok(entry) => Ok(entry.binding)
			Err(_) => Err(Unsupported("a value is read before its block computes it"))
		}
		Input(k) => {
			spell_param = env.param
			ty = match env.graph.slots().get(k.to_u64()) {
				Ok(found) => found
				Err(_) => return Err(Unsupported("a captured value the graph has no slot for"))
			}
			Ok(Translate.at(spell_param(Translate.input_name(k.to_u64())), ty))
		}
		Arg(_) => Err(Translate.no_loop)
		Out(_) => Err(Unsupported("a branch that delivers several values has no SurrealQL form"))
		Block(block) => {
			inner = Translate.define(block.defs, env)?
			match block.end {
				Value([one]) => Translate.eval(one, inner)
				Value(_) => Err(Unsupported("a branch that delivers several values has no SurrealQL form"))
				Return(_) | Jump(_) | Branch(_) => Err(Unsupported("a clause cannot leave early; every branch delivers its value"))
				Continue(_) | Break(_) => Err(Translate.no_loop)
			}
		}
		Op(node) => Translate.op(node.op, node.args, node.ty, env)
	}

	## The environment with the kept definitions of a block computed, in order.
	define : List({ id : U32, value : Code.Tree }), Env -> Try(Env, Ql.Error)
	define = |defs, env| defs.fold_try(
		env,
		|acc, def| {
			value = Translate.eval(def.value, acc)?
			Ok({ ..acc, nodes: acc.nodes.append({ id: def.id, binding: value, ty: Translate.type_of(def.value, acc) }) })
		},
	)

	## The type of a value, where the tree or the graph states it.
	type_of : Code.Tree, Env -> Try(Code.Ty, [Untyped])
	type_of = |tree, env| match tree {
		Op({ ty, .. }) => Ok(ty)
		Param(k) => env.graph.row(env.row).params.get(k.to_u64()).map_err(|_| Untyped)
		Input(k) => env.graph.slots().get(k.to_u64()).map_err(|_| Untyped)
		Def(n) => match env.nodes.find_last(|entry| entry.id == n) {
			Ok(entry) => entry.ty
			Err(_) => Err(Untyped)
		}
		_ => Err(Untyped)
	}

	## The SurrealDB type of a value of a type of CBOR v2 (`Types.Scalar`).
	scalar_of : Code.Tree, Env -> Try(Str, [NotScalar])
	scalar_of = |tree, env| match Translate.type_of(tree, env) {
		Ok(Named(name, _, _)) => Types.scalar_type(name)
		_ => Err(NotScalar)
	}

	## The fields of the backing record of a type of CBOR v2.
	scalar_fields : Str -> List(Str)
	scalar_fields = |surql| match surql {
		"regex" => ["pattern"]
		"bigdecimal" => ["text"]
		"date" => ["days"]
		"time" => ["nanos"]
		"timestamp" => ["secs", "nanos"]
		"interval" => ["months", "days", "micros"]
		_ => []
	}

	is_datetime : Code.Tree, Env -> Bool
	is_datetime = |tree, env| match Translate.type_of(tree, env) {
		Ok(Named(name, _, _)) => Types.nominal(name) == Datetime
		_ => Bool.False
	}

	## Whether a value's type is a record payload (`Translate.is_record`). The
	## type, not the tree, decides, so a kept definition reads as its value.
	is_record_value : Code.Tree, Env -> Bool
	is_record_value = |tree, env| match Translate.type_of(tree, env) {
		Ok(ty) => Translate.is_record(ty)
		Err(_) => Bool.False
	}

	## Whether a value's type is a stored `Link`.
	is_link : Code.Tree, Env -> Bool
	is_link = |tree, env| match Translate.type_of(tree, env) {
		Ok(Named(name, _, _)) => Types.nominal(name) == Link
		_ => Bool.False
	}

	is_point : Code.Tree, Env -> Bool
	is_point = |tree, env| match Translate.type_of(tree, env) {
		Ok(Named(name, _, _)) => Types.is_point(name)
		_ => Bool.False
	}

	## Why a geometry other than a point has no SurrealQL form in a clause:
	## a tuple takes only number literals, and `<geometry>` of an object
	## fails in SurrealDB 3.3.4.
	geometry_parameter : Str -> Ql.Error
	geometry_parameter = |name| Unsupported("a `${name.drop_prefix("Surreal.")}` in a clause has no SurrealQL form; pass a geometry as a parameter with `filter_by` and `prepare`")

	no_loop : Ql.Error
	no_loop = Unsupported("a clause has no loop; use `any`, `all`, `map`, `keep_if` or `sum` over a list")

	## One operation, over the trees of its arguments and regions, with the
	## type of its result.
	op : Code.Op, List(Code.Tree), Code.Ty, Env -> Try(Binding, Ql.Error)
	op = |operation, args, ty, env| {
		first = |_| match args.first() {
			Ok(tree) => Translate.eval(tree, env)
			Err(_) => Err(Unsupported("an operation with no operand"))
		}
		match operation {
			Lit(literal) => Translate.literal(literal).map_ok(|s| Binding.Expr(s))
			Prim(call) => Translate.prim(call, args, ty, env)
			Call(row) => match env.self {
				# The body of a database function calls itself through the database.
				Inside(f) if f.row == row => Ok(Translate.at(Translate.call("fn::${f.name}", args.map_try(|a| Translate.expr(a, env))?), ty))
				_ => Translate.expand(row, args.map_try(|a| Translate.eval(a, env))?, env)
			}
			Closure(_) | Lambda(_) => Err(Unsupported("a function in a clause means something only as the argument of a list operation"))
			Record(names) => {
				fields = List.map2(names, args, |name, value| { name, value }).map_try(|f| Ok({ name: f.name, binding: Translate.eval(f.value, env)? }))?
				Ok(Binding.Fields(fields))
			}
			Tuple => Err(Unsupported("a tuple has no SurrealQL value; a key of several fields is a record"))
			List => {
				items = args.map_try(|a| Translate.expr(a, env))?
				Ok(Binding.ListOf({ at: "[${Str.join_with(items, ", ")}]", items: Made }))
			}
			Item => Err(Unsupported("a list index has no SurrealQL form here; use `find_first` or `any`"))
			Tag(name) => Translate.tag(name, args, env)
			Wrap(name) => Translate.wrap(name, args, env)
			Unwrap => match args {
				[inner] if Translate.is_datetime(inner, env) => {
					# A datetime's `iso` is its text, which is how `==` on a
					# `Datetime` arrives. An equality compares the datetimes.
					Ok(Binding.Fields([{ name: "iso", binding: Binding.Moment(Translate.arg(inner, env)?) }]))
				}
				[inner] if Translate.scalar_of(inner, env).is_ok() => {
					# `==` and `<` on a type of CBOR v2 compare the fields of its
					# backing, and a captured value arrives as those fields. So a
					# field is an expression of the SurrealDB value: the `days` of
					# a `date`, the `nanos` of a `time`. The other types have no
					# such expression for each field.
					value = Translate.arg(inner, env)?
					match Translate.scalar_of(inner, env) ?? "" {
						"date" => Ok(Binding.Fields([{ name: "days", binding: Binding.Expr("(${value} - <date>'1970-01-01')") }]))
						"time" => Ok(Binding.Fields([{ name: "nanos", binding: Binding.Expr("duration::nanos(<duration>${value})") }]))
						surql => Err(Unsupported("a `${surql}` in a clause has no SurrealQL form for its parts; compare it in Roc after the read"))
					}
				}
				[inner] if Translate.is_point(inner, env) => {
					# A point is GeoJSON in SurrealDB: `lon` and `lat` are its coordinates.
					place = Translate.arg(inner, env)?
					Ok(Binding.Fields([{ name: "lon", binding: Binding.Expr("${place}.coordinates[0]") }, { name: "lat", binding: Binding.Expr("${place}.coordinates[1]") }]))
				}
				_ => first({})
			}
			Field(name) | OptField(name) => match args {
				# A field read of a stored `Link`, `link.id`, is its method `link.id()`.
				[Op({ op: Unwrap, args: [link], .. })] if Translate.is_link(link, env) => Translate.link_field(link, name, env)
				_ => Translate.field(first({})?, name, ty, env)
			}
			Index(position) => match first({})? {
				WithEdges(row, lists) =>
					if position == 0 {
						Ok(row)
					} else {
						match lists.get(position - 1) {
							Ok(edges) => Ok(edges)
							Err(_) => Err(Unsupported("a row with its edges has no position ${position.to_str()}"))
						}
					}
				_ => Err(Unsupported("only a row with its edges has positions `.0`, `.1`, .."))
			}
			Payload(tag, k) => Translate.payload(first({})?, tag, k, ty)
			Switch(sw) => Translate.switch(sw.arms.map(|a| a.key), sw.joins.len(), sw.outputs.len(), args, env)
			And(_) => Translate.connective("AND", args, env)
			Or(_) => Translate.connective("OR", args, env)
			ForRange(_) | ForList(_) | Loop(_) => Err(Translate.no_loop)
			Crash => Err(Unsupported("a clause cannot crash"))
			Derived(method, _) => Err(Unsupported("`${method}` is derived by the compiler and has no SurrealQL form; compare fields, or `match` on a union"))
		}
	}

	connective : Str, List(Code.Tree), Env -> Try(Binding, Ql.Error)
	connective = |word, args, env| {
		parts = args.map_try(|a| Translate.arg(a, env))?
		Ok(Binding.Infix(Str.join_with(parts, " ${word} ")))
	}

	## A field of a stored `Link`, `{ id, fetched }`, read in a clause: `link.id`
	## and `link.id()` are the same, the record id the link holds, which is the
	## link itself in SurrealQL. `fetched` is the row that the program holds,
	## and the database has no such field.
	link_field : Code.Tree, Str, Env -> Try(Binding, Ql.Error)
	link_field = |link, name, env| match name {
		"id" => Ok(Binding.Expr(Translate.expr(link, env)?))
		"fetched" => Err(Unsupported("`fetched` is the row that the program holds, and the database has no such field; read a field of the row with `link.get().field`, or use `link.id`"))
		_ => Err(Unsupported("a `Link` has the fields `id` and `fetched`, and this clause reads `${name}`"))
	}

	field : Binding, Str, Code.Ty, Env -> Try(Binding, Ql.Error)
	field = |holder, name, ty, env| match holder {
		Row(r) => Ok(Translate.member(r, name, ty))
		Params => {
			spell_param = env.param
			Ok(Translate.at(spell_param(name), ty))
		}
		Fields(fields) => match fields.find_first(|f| f.name == name) {
			Ok(f) => Ok(f.binding)
			Err(_) => Err(Unsupported("this record has no `${name}`"))
		}
		WithEdges(_, _) => Err(Unsupported("a row with its edges has no `${name}`; take `.0` or the edges at `.1`, `.2` first"))
		Group(_) => Err(Unsupported("a group's rows have no single `${name}`; aggregate them"))
		_ => Err(Unsupported("`${name}` is read from a value that is not a record"))
	}

	## A field of a record at a place, by the field's type.
	member : { at : Str, of : [Doc([Of(Str), Unnamed]), Ref(Code.Ty), Obj], edge : Bool }, Str, Code.Ty -> Binding
	member = |r, name, ty| {
		spelled = Translate.spell_name(name, r.edge)
		path = if (r.at.is_empty()) spelled else "${r.at}.${if (r.edge) spelled else Ql.member(name)}"
		match (name, r.of) {
			# The key of a record: `c.id` is the `ada` of `customer:ada`.
			("id", Ref(_)) => Binding.Expr("record::id(${r.at})")
			("id", Doc(_)) => Binding.Expr("record::id(${path})")
			(_, Doc(_)) | (_, Ref(_)) => match ty {
				# An edge list of a read view is read off the record: `v.treats`
				# is `->treats`, and its elements are the edges.
				Named(kind, _, edges) if Types.nominal(kind) == Out => Binding.ListOf({ at: "${r.at}->${Ql.ident(name)}", items: Translate.records_of(Bool.True, edges, Edges(Translate.any_ends)) })
				Named(kind, _, edges) if Types.nominal(kind) == In => Binding.ListOf({ at: "${r.at}<-${Ql.ident(name)}", items: Translate.records_of(Bool.True, edges, Edges(Translate.any_ends)) })
				_ => Translate.at(path, ty)
			}
			_ => Translate.at(path, ty)
		}
	}

	## The fields of a whole row of type `row_ty`, in name order, each read
	## off the record at `place`. Off the row a statement is over, that is
	## `record::id(id)` for `id`, `in` for the `from` of an edge, the field's
	## name for the others. `select(|r| r)` selects them, and a linked row
	## destructures them.
	row_columns : Code.Ty, { at : Str, of : [Doc([Of(Str), Unnamed]), Ref(Code.Ty), Obj], edge : Bool } -> Try(List({ name : Str, surql : Str }), Ql.Error)
	row_columns = |row_ty, place| {
		fields = match Types.unwrap(row_ty) {
			Record(found) => found
			other => return Err(Unsupported("a whole row is a record, and this is `${other.name()}`"))
		}
		fields.map_try(|f| Ok({ name: f.name, surql: Translate.shaped(Translate.member(place, f.name, f.ty), f.ty)? }))
	}

	## A whole value of type `ty`. A record or a list of records that holds
	## a `Linked` is the destructure of its fields, so that each linked row
	## in it is the fields of its type: `items.{ product: product.{ id:
	## record::id(id), title, .. }, qty }`. Any other value is its text.
	shaped : Binding, Code.Ty -> Try(Str, Ql.Error)
	shaped = |binding, ty| {
		inner = |fields| {
			parts = fields.map_try(
				|f| {
					part = Translate.shaped(Translate.member({ at: "", of: Obj, edge: Bool.False }, f.name, f.ty), f.ty)?
					Ok(if (part == Ql.member(f.name)) part else "${Ql.member(f.name)}: ${part}")
				},
			)?
			Ok("{ ${Str.join_with(parts, ", ")} }")
		}
		if !Translate.holds_linked(ty) {
			Translate.text(binding)
		} else if Translate.refers_back(ty) {
			Err(Translate.self_linked)
		} else {
			match (binding, Types.unwrap(ty)) {
				(Row({ of: Ref(_), .. }), _) | (ListOf({ items: Records(_), .. }), _) | (ListOf({ items: Made, .. }), _) => Translate.text(binding)
				(Row({ at: place, of: Obj, .. }), Record(fields)) => Ok("${place}.${inner(fields)?}")
				(ListOf({ at: place, items: Values }), ListOf(item)) =>
					match Types.unwrap(item) {
						Record(fields) => Ok("${place}.${inner(fields)?}")
						_ => Err(Translate.whole_linked)
					}
				_ => Err(Translate.whole_linked)
			}
		}
	}

	whole_linked : Ql.Error
	whole_linked = Unsupported("a whole value that holds a `Linked` in a union or in a list of lists has no SurrealQL form; select its fields")

	self_linked : Ql.Error
	self_linked = Unsupported("a whole read row that holds a `Linked` of itself has no finite fetch plan: each `Linked` of it fetches the row again, with no last hop; select its fields, or make the link a `Linked` of the stored row (`Linked(Owner)` for a stored `Owner`), whose own links are `Link`")

	## Whether a type is a `Linked` that the description gives as
	## `Recursive`: a read row that holds a `Linked` of itself, at this
	## place or in a list here.
	refers_back : Code.Ty -> Bool
	refers_back = |ty| match ty {
		Recursive(name) => Types.nominal(name) == Linked
		ListOf(item) => Translate.refers_back(item)
		_ => Bool.False
	}

	## Whether a type holds a `Linked`, or an `Out` or `In` field, other than
	## through a `Link`.
	holds_linked : Code.Ty -> Bool
	holds_linked = |ty| match ty {
		Named(name, _, backing) =>
			if Types.nominal(name) == Linked or Types.nominal(name) == Out or Types.nominal(name) == In {
				Bool.True
			} else if Types.user_named(name) {
				Translate.holds_linked(backing)
			} else {
				Bool.False
			}
		Recursive(name) => Types.nominal(name) == Linked
		Record(fields) => fields.any(|f| Translate.holds_linked(f.ty))
		ListOf(item) => Translate.holds_linked(item)
		TagUnion(variants) => variants.any(|v| v.payloads.any(Translate.holds_linked))
		_ => Bool.False
	}

	## The columns of a result row the clause built, of type `ty`. A field
	## that holds a `Linked` is shaped by its type (`Translate.shaped`).
	typed_fields : Binding, Code.Ty -> Try(List({ name : Str, surql : Str }), Ql.Error)
	typed_fields = |binding, ty| match (binding, Types.unwrap(ty)) {
		(Fields(fields), Record(types)) =>
			fields.map_try(
				|f| match types.find_first(|t| t.name == f.name) {
					Ok(t) => Ok({ name: f.name, surql: Translate.shaped(f.binding, t.ty)? })
					Err(_) => Ok({ name: f.name, surql: Translate.text(f.binding)? })
				},
			)
		_ => Translate.fields_of(binding)
	}

	## A whole linked row, with the fields of its Roc type and `id` as the
	## key, not the record id: `owner.{ id: record::id(id), name, address }`.
	## The value is NONE when the link is NONE.
	whole_row : Str, Code.Ty, Bool -> Try(Str, Ql.Error)
	whole_row = |link, row_ty, edge| {
		entries = Translate.row_columns(row_ty, { at: "", of: Doc(Unnamed), edge })?.map(|c| if (c.surql == Ql.member(c.name)) c.surql else "${Ql.member(c.name)}: ${c.surql}")
		Ok("${link}.{ ${Str.join_with(entries, ", ")} }")
	}

	## A field name as SurrealDB names it: an edge's `from` and `to` are `in`
	## and `out`, because `in` is a Roc keyword.
	spell_name : Str, Bool -> Str
	spell_name = |name, edge|
		if edge and name == "from" {
			"in"
		} else if edge and name == "to" {
			"out"
		} else {
			Ql.ident(name)
		}

	## A union literal in the union encoding of `Encode`: `'Cash'`,
	## `{ kind: 'Card', last4: .. }`, `{ kind: 'C', value: .. }`,
	## `{ kind: 'D', value: [.., ..] }`.
	tag : Str, List(Code.Tree), Env -> Try(Binding, Ql.Error)
	tag = |name, args, env| {
		kind = "kind: ${Ql.quote(name)}"
		match args {
			[] => Ok(Binding.Expr(Ql.quote(name)))
			[only] if Translate.is_record_value(only, env) => match Translate.eval(only, env)? {
				Fields(fields) => {
					parts = fields.map_try(|f| Ok("${Ql.member(f.name)}: ${Translate.text(f.binding)?}"))?
					Ok(Binding.Expr("{ ${Str.join_with(List.concat([kind], parts), ", ")} }"))
				}
				_ => Err(Unsupported("the payload of `${name}` is a record the clause does not build field by field${if (name == "Ok") "; annotate the value as a `Try`, whose `Err` is NONE" else ""}"))
			}
			[only] => Ok(Binding.Expr("{ ${kind}, value: ${Translate.expr(only, env)?} }"))
			_ => {
				parts = args.map_try(|a| Translate.expr(a, env))?
				Ok(Binding.Expr("{ ${kind}, value: [${Str.join_with(parts, ", ")}] }"))
			}
		}
	}

	## A nominal value written in the clause. An `Id` or a `Datetime` of
	## literals is its SurrealQL literal; a user nominal is its backing.
	wrap : Str, List(Code.Tree), Env -> Try(Binding, Ql.Error)
	wrap = |name, args, env| {
		inner = match args {
			[one] => one
			_ => return Err(Unsupported("a nominal value with no backing"))
		}
		match Types.nominal(name) {
			Id => match (Translate.record_field(inner, "table"), Translate.record_field(inner, "key")) {
				(Ok(Op({ op: Lit(Str(table)), .. })), Ok(Op({ op: Lit(Str(key)), .. }))) => Ok(Binding.Expr(Ql.record_id(table, key)))
				(Ok(table), Ok(key)) => Ok(Binding.Expr("type::record(${Translate.expr(table, env)?}, ${Translate.expr(key, env)?})"))
				_ => Err(Unsupported("an id built without its table and key"))
			}
			Datetime => match Translate.record_field(inner, "iso") {
				Ok(Op({ op: Lit(Str(iso)), .. })) => Ok(Binding.Expr(Ql.literal(Ql.Value.Datetime(iso))))
				Ok(other) => Ok(Binding.Expr("<datetime>${Translate.arg(other, env)?}"))
				Err(_) => Err(Unsupported("a datetime built without its text"))
			}
			Link => Err(Unsupported("a `Link` written in a clause has no SurrealQL form; compare `link.id()` with an `Id`"))
			# A type of CBOR v2 of literals is its literal.
			Scalar(surql) => {
				parts = Translate.scalar_fields(surql).map_try(
					|f| match Translate.record_field(inner, f) {
						Ok(Op({ op: Lit(Str(t)), .. })) => Ok({ name: f, value: Ql.Value.Str(t) })
						Ok(Op({ op: Lit(Int(n, _)), .. })) => n.to_i64_try().map_ok(|i| { name: f, value: Ql.Value.Int(i) }).map_err(|_| NotLiteral)
						_ => Err(NotLiteral)
					},
				)
				match parts {
					Ok(fields) => Translate.v2_scalar(surql, Ql.Value.Object(fields)).map_ok(|v| Binding.Expr(Ql.literal(v)))
					Err(_) => Err(Unsupported("a `${surql}` written in a clause must be of literals; capture it, or pass it as a parameter"))
				}
			}
			Duration => match Translate.record_field(inner, "nanos") {
				# A known count is a duration literal: `1d`, not `duration::from_nanos(86400000000000)`.
				Ok(Op({ op: Lit(Int(n, _)), .. })) if n.to_u64_try().is_ok() => Ok(Binding.Expr(Ql.duration(n.to_u64_wrap())))
				Ok(nanos) => Ok(Binding.Expr(Translate.call("duration::from_nanos", [Translate.expr(nanos, env)?])))
				Err(_) => Err(Unsupported("a duration built without its nanoseconds"))
			}
			DbFn => Translate.function_ref(inner).map_ok(|f| Binding.Function(f))
			# The key of a time series is the array `[series, time]`.
			TimeKey => match (Translate.record_field(inner, "series"), Translate.record_field(inner, "time")) {
				(Ok(series), Ok(time)) => Ok(Binding.Expr("[${Translate.expr(series, env)?}, ${Translate.expr(time, env)?}]"))
				_ => Err(Unsupported("a time key built without its series and time"))
			}
			# A point of any numbers is a cast of its pair. `to_geometry()` of a
			# geometry is the geometry: a tag with one payload, that payload.
			Geometry(surql) => match (surql, inner) {
				("geometry<point>", _) => match (Translate.record_field(inner, "lon"), Translate.record_field(inner, "lat")) {
					(Ok(lon), Ok(lat)) => Ok(Binding.Infix("<point> [${Translate.expr(lon, env)?}, ${Translate.expr(lat, env)?}]"))
					_ => Err(Unsupported("a point built without its longitude and latitude"))
				}
				("geometry", Op({ op: Tag(_), args: [payload], .. })) => Translate.eval(payload, env)
				_ => Err(Translate.geometry_parameter(name))
			}
			Try => Translate.try_value(inner, env)
			_ => Translate.eval(inner, env)
		}
	}

	## A `Try` built in a clause, as a value that may be NONE: `Ok(x)` is
	## `x`, and `Err(_)` is NONE, as for a `Try` read from an optional field.
	try_value : Code.Tree, Env -> Try(Binding, Ql.Error)
	try_value = |inner, env| match inner {
		Op({ op: Tag("Ok"), args: [payload], .. }) => match Translate.eval(payload, env)? {
			Maybe(_) => Err(Translate.nested_try)
			value => Ok(Binding.Maybe(Translate.text(value)?))
		}
		Op({ op: Tag("Err"), .. }) => Ok(Binding.Maybe("NONE"))
		_ => Err(Unsupported("a `Try` built in a clause is `Ok(value)` or `Err(_)`"))
	}

	nested_try : Ql.Error
	nested_try = Unsupported("a `Try` that holds a `Try` has no SurrealQL form; NONE stands for the error of both")

	record_field : Code.Tree, Str -> Try(Code.Tree, [Missing])
	record_field = |tree, name| match tree {
		Op({ op: Record(names), args, .. }) => match List.map2(names, args, |n, a| { n, a }).find_first(|p| p.n == name) {
			Ok(p) => Ok(p.a)
			Err(_) => Err(Missing)
		}
		_ => Err(Missing)
	}

	## A payload read, by the union payload rule of `Encode`: a record
	## payload is the union object itself, one other payload is `value`,
	## several are the items of the array `value`: `value[0]`, `value[1]`, ...
	payload : Binding, Str, U64, Code.Ty -> Try(Binding, Ql.Error)
	payload = |holder, tag_name, k, ty| match holder {
		Maybe(s) if tag_name == "Ok" => Ok(Translate.at(s, ty))
		Union(u) => match u.variants.find_first(|v| v.name == tag_name) {
			Ok({ payloads: [only], .. }) =>
				if Translate.is_record(only) {
					Ok(Binding.Row({ at: u.at, of: Obj, edge: Bool.False }))
				} else {
					Ok(Translate.at("${u.at}.value", ty))
				}
			Ok(_) => Ok(Translate.at("${u.at}.value[${k.to_str()}]", ty))
			Err(_) => Err(Unsupported("the union has no `${tag_name}`"))
		}
		_ => Err(Unsupported("`${tag_name}` is read from a value that is not a union"))
	}

	# ------------------------------------------------------------ branches

	## A branch: a `match` on a union, a test of an optional value, a `Bool`
	## test, or a test of a value against literals (a guard arrives as one).
	switch : List(Code.Key), U64, U64, List(Code.Tree), Env -> Try(Binding, Ql.Error)
	switch = |keys, joins, outputs, args, env| {
		if joins != 0 or outputs != 1 {
			return Err(Unsupported("a clause cannot leave early; every branch delivers its value"))
		}
		scrutinee = match args.first() {
			Ok(tree) => tree
			Err(_) => return Err(Unsupported("a branch with nothing to test"))
		}
		arms = List.map2(keys, args.drop_first(1), |key, tree| { key, tree })
		arm = |name| match arms.find_first(|a| Translate.key_is(a.key, name)) {
			Ok(found) => Translate.expr(found.tree, env)
			Err(_) => Err(Unsupported("a branch in a clause has no `${name}` arm"))
		}
		match Translate.tag_test(keys, args, env) {
			Ok(found) => Ok(Binding.Infix("${found.at} = ${Ql.quote(found.name)}"))
			Err(_) =>
				match Translate.presence_equality(keys, args, env) {
					Ok(comparison) => Translate.eval(comparison, env)
					Err(_) => Translate.branch(keys, arms, scrutinee, arm, env)
				}
		}
	}

	## The shape of `==` on a union and a tag with no payload: a switch on the
	## union where that tag gives `True`, and every other arm gives `False`.
	## The stored value of the tag is its name as text, and any other arm is
	## another text or an object, so `at = 'Name'` is the same test, and
	## `at != 'Name'` is its `not`, also for a value that is NONE.
	tag_test : List(Code.Key), List(Code.Tree), Env -> Try({ at : Str, name : Str }, [NotTagTest])
	tag_test = |keys, args, env| {
		scrutinee = args.first().map_err(|_| NotTagTest)?
		flags = args.drop_first(1).map_try(|tree| Translate.bool_of(tree).map_err(|_| NotTagTest))?
		flagged = List.map2(keys, flags, |key, flag| { key, flag })
		if flagged.count_if(|k| k.flag) != 1 or flagged.len() != keys.len() {
			return Err(NotTagTest)
		}
		name = match flagged.find_first(|k| k.flag) {
			Ok({ key: Tag(tag_name), .. }) => tag_name
			_ => return Err(NotTagTest)
		}
		others_are_tags = flagged.all(|k| k.flag or k.key == Default or Translate.is_tag(k.key))
		match Translate.eval(scrutinee, env) {
			Ok(Union(u)) if others_are_tags and u.variants.any(|v| v.name == name and v.payloads.is_empty()) => Ok({ at: u.at, name })
			_ => Err(NotTagTest)
		}
	}

	is_tag : Code.Key -> Bool
	is_tag = |key| match key {
		Tag(_) => Bool.True
		_ => Bool.False
	}

	## Whether the `Ok` arm only reads fields of the record in the optional
	## `s`, through objects: `c.code` of `Ok(c)`. The record's fields are
	## required, so the arm is never NONE for a present `s`, and `s.code ?? d`
	## is the same as the test of NONE. A link breaks this: `c.vet.get().name`
	## is NONE when the row is gone.
	reads_object : List({ key : Code.Key, tree : Code.Tree }), Str, Str -> Bool
	reads_object = |arms, present, s| {
		through = |tree| match tree {
			Block({ defs: [], end: Value([one]) }) => through(one)
			Op({ op: Payload(_, _), .. }) => Bool.True
			Op({ op: Unwrap, args: [inner], .. }) => Translate.is_own_row(inner) and through(inner)
			Op({ op: Field(name), args: [inner], .. }) => name != "id" and Translate.is_record_typed(inner) and through(inner)
			_ => Bool.False
		}
		match arms.find_first(|a| Translate.key_is(a.key, "Ok")) {
			Ok(found) => through(found.tree) and Translate.reads_path(present, s)
			Err(_) => Bool.False
		}
	}

	## A value of a record or of a nominal record of the application, not a
	## `Link` or a read view of one, which hold a record that may be gone.
	is_own_row : Code.Tree -> Bool
	is_own_row = |tree| match tree {
		Op({ ty: Named(name, _, _), .. }) => Types.nominal(name) == Other
		_ => Bool.True
	}

	is_record_typed : Code.Tree -> Bool
	is_record_typed = |tree| match tree {
		Op({ ty, .. }) => match Types.unwrap(ty) {
			Record(_) => Bool.True
			_ => Bool.False
		}
		_ => Bool.False
	}

	## The branch itself, when it is not an equality of two optional fields.
	branch : List(Code.Key), List({ key : Code.Key, tree : Code.Tree }), Code.Tree, (Str -> Try(Str, Ql.Error)), Env -> Try(Binding, Ql.Error)
	branch = |keys, arms, scrutinee, arm, env| {
		match Translate.eval(scrutinee, env)? {
			Maybe(s) => {
				present = arm("Ok")?
				absent = arm("Err")?
				if present == s or Translate.reads_object(arms, present, s) {
					fallback = match arms.find_first(|a| Translate.key_is(a.key, "Err")) {
						Ok(found) => Translate.arg(found.tree, env)?
						Err(_) => absent
					}
					Ok(Binding.Infix("${present} ?? ${fallback}"))
				} else {
					Ok(Binding.Expr("(IF ${s} IS NONE THEN ${absent} ELSE ${present} END)"))
				}
			}
			Union(u) => {
				tests = arms.map_try(
					|a| match a.key {
						Tag(name) => match u.variants.find_first(|v| v.name == name) {
							Ok({ payloads: [], .. }) => Ok({ test: "${u.at} = ${Ql.quote(name)}", value: Translate.expr(a.tree, env)? })
							Ok(_) => Ok({ test: "${u.at}.kind = ${Ql.quote(name)}", value: Translate.expr(a.tree, env)? })
							Err(_) => Err(Unsupported("the union has no `${name}`"))
						}
						_ => Err(Unsupported("a union is matched by its tags"))
					},
				)?
				Ok(Translate.chain(tests, Free))
			}
			scalar => {
				s = Translate.operand(scalar)?
				if keys.any(|k| Translate.key_is(k, "True")) {
					Ok(Translate.chain([{ test: Translate.text(scalar)?, value: arm("True")? }, { test: "", value: arm("False")? }], Free))
				} else {
					tests = arms.map_try(
						|a| match a.key {
							Lit(literal) => Ok({ test: "${s} = ${Translate.literal(literal)?}", value: Translate.expr(a.tree, env)? })
							Default => Ok({ test: "", value: Translate.expr(a.tree, env)? })
							_ => Err(Unsupported("a list pattern has no SurrealQL form"))
						},
					)?
					Ok(Translate.chain(tests, Fixed))
				}
			}
		}
	}

	## `IF .. THEN .. ELSE IF .. ELSE .. END`, from arms whose tests exclude
	## one another. The `ELSE` value is the one most arms give (the last such
	## arm on a tie), and every arm that gives it needs no test. With `Fixed`,
	## the last arm is the `ELSE`, because it is the `Default` of a literal
	## test and has no test of its own.
	chain : List({ test : Str, value : Str }), [Free, Fixed] -> Binding
	chain = |tests, choice| {
		count_of = |value| tests.count_if(|t| t.value == value)
		fallback = match choice {
			Fixed => tests.last().map_ok(|t| t.value) ?? ""
			Free => tests.fold("", |best, t| if (count_of(t.value) >= count_of(best)) t.value else best)
		}
		tested = tests.keep_if(|t| t.value != fallback)
		if tested.is_empty() {
			Binding.Expr(fallback)
		} else {
			branches = Str.join_with(tested.map(|t| "IF ${t.test} THEN ${t.value}"), " ELSE ")
			Binding.Expr("(${branches} ELSE ${fallback} END)")
		}
	}

	## The shape the reifier gives `==` on two optional fields: a presence
	## switch on the first value, and in each arm a presence switch on the
	## second. Both absent is `true`, one absent is `false`, and both present
	## compare the two payloads. `!=` has the arms inverted, with `not` around
	## the comparison. SurrealDB reads an absent field as NONE and `NONE = NONE`
	## is true, so the comparison of the two values alone answers all four
	## cases. This gives that comparison, which is the tree of the last arm.
	## Any other switch is not this shape.
	presence_equality : List(Code.Key), List(Code.Tree), Env -> Try(Code.Tree, [NotPresenceEquality])
	presence_equality = |keys, args, env| {
		outer = Translate.presence_parts(keys, args)?
		when_absent = Translate.presence_of(outer.absent)?
		when_present = Translate.presence_of(outer.present)?
		if when_absent.node != when_present.node {
			return Err(NotPresenceEquality)
		}
		both_absent = Translate.bool_of(when_absent.absent)?
		only_second = Translate.bool_of(when_absent.present)?
		only_first = Translate.bool_of(when_present.absent)?
		payload_of = |tree, node| match Translate.single(tree) {
			Op({ op: Payload("Ok", _), args: [Def(read)], .. }) => read == node
			_ => Bool.False
		}
		compares = |tree| match tree {
			Op({ op: Prim({ id, .. }), args: [x, y], .. }) if Translate.is_equality(id, env) => payload_of(x, outer.node) and payload_of(y, when_absent.node)
			_ => Bool.False
		}
		comparison = Translate.single(when_present.present)
		matches = match comparison {
			Op({ op: Prim({ id, .. }), args: [inner], .. }) if id == Code.prim(Bool.not) =>
				compares(inner) and !both_absent and only_second and only_first
			_ => compares(comparison) and both_absent and !only_second and !only_first
		}
		if (matches) Ok(comparison) else Err(NotPresenceEquality)
	}

	## A presence switch on a kept node, as the node and its two arms.
	presence_of : Code.Tree -> Try({ node : U32, absent : Code.Tree, present : Code.Tree }, [NotPresenceEquality])
	presence_of = |tree| match Translate.single(tree) {
		Op({ op: Switch(sw), args, .. }) => Translate.presence_parts(sw.arms.map(|arm| arm.key), args)
		_ => Err(NotPresenceEquality)
	}

	presence_parts : List(Code.Key), List(Code.Tree) -> Try({ node : U32, absent : Code.Tree, present : Code.Tree }, [NotPresenceEquality])
	presence_parts = |keys, args| match args {
		[Def(node), first, second] if keys.len() == 2 => {
			arms = List.map2(keys, [first, second], |key, tree| { key, tree })
			match (arms.find_first(|a| Translate.key_is(a.key, "Err")), arms.find_first(|a| Translate.key_is(a.key, "Ok"))) {
				(Ok(absent), Ok(present)) => Ok({ node, absent: absent.tree, present: present.tree })
				_ => Err(NotPresenceEquality)
			}
		}
		_ => Err(NotPresenceEquality)
	}

	bool_of : Code.Tree -> Try(Bool, [NotPresenceEquality])
	bool_of = |tree| match Translate.single(tree) {
		Op({ op: Lit(Bool(flag)), .. }) => Ok(flag)
		_ => Err(NotPresenceEquality)
	}

	## A region that only delivers one value is that value.
	single : Code.Tree -> Code.Tree
	single = |tree| match tree {
		Block({ defs: [], end: Value([one]) }) => one
		_ => tree
	}

	key_is : Code.Key, Str -> Bool
	key_is = |key, name| match key {
		Tag(tag_name) => tag_name == name
		Lit(Bool(flag)) => (if (flag) "True" else "False") == name
		Lit(_) | Len(_) | AtLeast(_) | Default => Bool.False
	}

	# ------------------------------------------------------------ builtins

	## A call of a primitive, in the form its id has (`Translate.form`). The
	## owner and the method of the call name it in a refusal only.
	prim : Call, List(Code.Tree), Code.Ty, Env -> Try(Binding, Ql.Error)
	prim = |call, args, ty, env| {
		sql = |node| Translate.expr(node, env)
		opd = |node| Translate.arg(node, env)
		name = "${call.owner}.${call.method}"
		found = match Translate.form(call.id, env.extensions) {
			Ok(known) => known
			Err(NotFound) => return Err(Unsupported("`${name}` has no SurrealQL form"))
		}
		match (found, args) {
			(Builtin({ owner: "List", method: "sort" }), _) => Translate.sorted("sort", call.evidence, args, env)
			(Builtin({ owner: "List", method: "sort_reversed" }), _) => Translate.sorted("sort_reversed", call.evidence, args, env)
			(Builtin(b), _) => Translate.builtin(b.owner, b.method, args, env)
			(LinkGet, [link]) => match Translate.eval(link, env)? {
				Expr(path) => Ok(Binding.Row({ at: path, of: Ref(ty), edge: Bool.False }))
				_ => Err(Unsupported("`get` traverses a stored link"))
			}
			(LinkId, [link]) => Translate.link_field(link, "id", env)
			(IdEq, [a, b]) => Ok(Binding.Infix("${opd(a)?} = ${opd(b)?}"))
			(IdKey, [id]) => Ok(Binding.Expr("record::id(${sql(id)?})"))
			(IdTable, [id]) => Ok(Binding.Expr("record::tb(${sql(id)?})"))
			(DatetimeOrder, [lhs, rhs]) => Translate.binary(call.owner, call.method, lhs, rhs, env)
			# A key `[series, time]`: `record::id(id)[0]` and `record::id(id)[1]`.
			(SeriesOf, [key]) => Ok(Translate.at("${sql(key)?}[0]", ty))
			(TimeOf, [key]) => Ok(Translate.at("${sql(key)?}[1]", ty))
			(CallDbFn, [f, .. as rest]) => match Translate.eval(f, env)? {
				Function(defined) => Ok(Translate.at(Translate.call("fn::${defined.name}", rest.map_try(sql)?), ty))
				_ => Err(Translate.not_constant)
			}
			# A table that a clause names. Its constructor is a function of
			# `Surreal`, so it arrives as a call with the name as a literal.
			(TableOf, [table_name]) => Translate.table_of(table_name, Err(NotEdge))
			(RelationOf, [table_name, from, to]) => {
				# The name of the table at an end, or any table.
				end = |tree| match Translate.eval(tree, env) {
					Ok(Table(t)) => t.name
					_ => "?"
				}
				Translate.table_of(table_name, Ok({ from: end(from), to: end(to) }))
			}
			(Rows, [table]) => match Translate.eval(table, env)? {
				Table(t) => Ok(Binding.ListOf({ at: Translate.rows_at(t.name), items: Translate.records(t.edge, ty) }))
				_ => Err(Unsupported("`rows` reads a table that the clause names"))
			}
			# The edges of a row: `->treats` off the row, `$v1.in->treats` off a linked row.
			(EdgesOf(arrow), [table, row]) => match (Translate.eval(table, env)?, Translate.eval(row, env)?) {
				(Table(t), Row({ at: place, of: Doc(_), .. })) | (Table(t), Row({ at: place, of: Ref(_), .. })) => Ok(Binding.ListOf({ at: "${place}${arrow}${Ql.ident(t.name)}", items: Translate.records_of(Bool.True, ty, Edges(t.ends)) }))
				(Table(_), _) => Err(Unsupported("the edges are of a record: the row, or a row that a link points at"))
				_ => Err(Unsupported("the edges are of an edge table that the clause names"))
			}
			(RecordOf, [table, key]) => match (Translate.eval(table, env)?, key) {
				(Table(t), Op({ op: Lit(Str(k)), .. })) => Ok(Binding.Expr(Ql.record_id(t.name, k)))
				(Table(t), _) => match Translate.own_record(key, t.name, env) {
					Ok(record) => Ok(Binding.Expr(record))
					Err(_) => Ok(Binding.Expr("type::record(${Ql.quote(t.name)}, ${sql(key)?})"))
				}
				_ => Err(Unsupported("`id` reads a table that the clause names"))
			}
			(Variable(value), _) => Ok(Translate.at(value, ty))
			(Render(draw), _) => match draw({ args: args.map_try(opd)?, evidence: call.evidence }) {
				Ok(written) => Ok(Translate.rendered(written, ty))
				Err(why) => Err(Unsupported("`${name}`: ${why}"))
			}
			(Function(_), _) | (Aggregate(_), _) | (FloatAggregate(_), _) | (Operator(_), _) | (Percentile, _) | (Uuid, _) | (TimeGroup, _) => Translate.library(found, name, args, ty, env)
			_ => Err(Unsupported("`${name}` has no SurrealQL form"))
		}
	}

	## The record of a row of `table` that a statement reads, where `key`
	## is its key: `kennels.id(k.id)` is `id`, not
	## `type::record('kennel', record::id(id))`.
	own_record : Code.Tree, Str, Env -> Try(Str, [NotOwn])
	own_record = |key, table, env| match key {
		Op({ op: Field("id"), args: [holder], .. }) =>
			match Translate.eval(holder, env) {
				Ok(Row({ at: place, of: Doc(Of(name)), .. })) if name == table => Ok(if (place.is_empty()) "id" else "${place}.id")
				_ => Err(NotOwn)
			}
		_ => Err(NotOwn)
	}

	## The text an extension rendered, at the type of the call. It is taken
	## as one operand: an extension that writes an operator puts the
	## parentheses around it.
	rendered : Str, Code.Ty -> Binding
	rendered = |written, ty| Translate.at(written, ty)

	## `List.sort` and `List.sort_reversed` over items whose Roc order is the order that `array::sort` gives:
	## the whole numbers and `Dec` by value. The evidence says which `order_relative_to` the sort uses: a type that
	## writes its own order has a `Row` there, and any order other than a builtin integer's or `Dec`'s is refused.
	sorted : Str, List(Code.Evidence), List(Code.Tree), Env -> Try(Binding, Ql.Error)
	sorted = |method, evidence, args, env| {
		natural = match evidence {
			[{ target: Prim(order), .. }] => match Translate.builtins.get(order.id) {
				Ok({ owner, method: "order_relative_to" }) => owner == "Num.Dec" or owner.starts_with("Num.I") or owner.starts_with("Num.U")
				_ => Bool.False
			}
			_ => Bool.False
		}
		if !natural {
			return Err(Unsupported("`List.${method}` orders by `order_relative_to`, and only the order of whole numbers and `Dec` is the order of `array::sort`; sort a list of numbers, or sort in Roc"))
		}
		match args {
			[list] => {
				source = Translate.list_parts(list, env)?
				direction = if (method == "sort") "asc" else "desc"
				Ok(Binding.ListOf({ at: Translate.call("array::sort::${direction}", [source.at]), items: Translate.off_path(source.items) }))
			}
			_ => Err(Unsupported("`List.${method}` takes one list"))
		}
	}

	## A table by its literal name, with its ends when it is an edge table.
	table_of : Code.Tree, Try(Ends, [NotEdge]) -> Try(Binding, Ql.Error)
	table_of = |name, ends| match name {
		Op({ op: Lit(Str(found)), .. }) => Ok(Binding.Table({ name: found, edge: ends.is_ok(), ends: ends ?? Translate.any_ends }))
		_ => Err(Unsupported("a table in a clause has a literal name"))
	}

	builtin : Str, Str, List(Code.Tree), Env -> Try(Binding, Ql.Error)
	builtin = |owner, method, args, env| {
		sql = |node| Translate.expr(node, env)
		opd = |node| Translate.arg(node, env)
		plain = |node| Translate.plain_list(node, env)
		string_fn = |name, s, x| Ok(Binding.Expr("string::${name}(${sql(s)?}, ${sql(x)?})"))
		whole = owner.starts_with("Num.I") or owner.starts_with("Num.U")
		dec = owner == "Num.Dec"
		match ("${owner}.${method}", args) {
			("Str.concat", _) => Ok(Binding.Infix(Str.join_with(args.map_try(opd)?, " + ")))
			("Str.starts_with", [s, x]) => string_fn("starts_with", s, x)
			("Str.ends_with", [s, x]) => string_fn("ends_with", s, x)
			("Str.contains", [s, x]) => string_fn("contains", s, x)
			("Str.is_empty", [s]) => Ok(Binding.Infix("${opd(s)?} = ''"))
			("Str.to_str", [s]) => Translate.eval(s, env)
			("Str.is_eq", [a, b]) => match Translate.key_compare(a, b, "=", env)? {
				Keyed(compared) => Ok(compared)
				Plain =>
					match Translate.moments(a, b, env)? {
						Moments(pair) => Ok(Binding.Infix("${pair.left} = ${pair.right}"))
						Texts => Translate.binary(owner, method, a, b, env)
					}
			}
			("Str.repeat", [s, n]) => Ok(Binding.Expr(Translate.call("string::repeat", [sql(s)?, sql(n)?])))
			# `with_prefix(s, p)` is `p + s`.
			("Str.with_prefix", [s, p]) => Ok(Binding.Infix("${opd(p)?} + ${opd(s)?}"))
			("Str.join_with", [list, x]) => Ok(Binding.Expr(Translate.call("array::join", [plain(list)?, sql(x)?])))
			# Equal prefixes in bytes are equal in characters, so `string::len` cuts at the same place.
			("Str.drop_prefix", [s, p]) =>
				Ok(Binding.Expr("(IF string::starts_with(${sql(s)?}, ${sql(p)?}) THEN string::slice(${sql(s)?}, string::len(${sql(p)?})) ELSE ${sql(s)?} END)"))
			("Str.drop_suffix", [s, p]) =>
				Ok(Binding.Expr("(IF string::ends_with(${sql(s)?}, ${sql(p)?}) THEN string::slice(${sql(s)?}, 0, string::len(${sql(s)?}) - string::len(${sql(p)?})) ELSE ${sql(s)?} END)"))
			# `string::len` counts characters, so the byte count goes through `<bytes>`.
			("Str.count_utf8_bytes", [s]) => Ok(Binding.Expr("bytes::len(<bytes>${opd(s)?})"))
			# `string::trim` keeps U+200E and U+200F, which Roc removes.
			("Str.trim", [s]) => Ok(Binding.Expr("string::replace(${sql(s)?}, /^${Translate.blank}|${Translate.blank}$/, '')"))
			("Str.trim_start", [s]) => Ok(Binding.Expr("string::replace(${sql(s)?}, /^${Translate.blank}/, '')"))
			("Str.trim_end", [s]) => Ok(Binding.Expr("string::replace(${sql(s)?}, /${Translate.blank}$/, '')"))
			("Str.with_ascii_uppercased", [s]) => Ok(Binding.Expr(Translate.ascii_case(sql(s)?, "a", "z", "uppercase")))
			("Str.with_ascii_lowercased", [s]) => Ok(Binding.Expr(Translate.ascii_case(sql(s)?, "A", "Z", "lowercase")))
			("Str.caseless_ascii_equals", [s, x]) =>
				Ok(Binding.Infix("${Translate.ascii_case(sql(s)?, "A", "Z", "lowercase")} = ${Translate.ascii_case(sql(x)?, "A", "Z", "lowercase")}"))
			# `string::split` with an empty separator cuts every character, and Roc gives the whole text.
			("Str.split_on", [s, x]) => {
				split = "string::split(${sql(s)?}, ${sql(x)?})"
				pieces = match Translate.str_lit(x) {
					Ok("") => "[${sql(s)?}]"
					Ok(_) => split
					Err(_) => "(IF ${opd(x)?} = '' THEN [${sql(s)?}] ELSE ${split} END)"
				}
				Ok(Binding.ListOf({ at: pieces, items: Values }))
			}
			# `string::replace` with an empty needle puts the replacement between all characters, and Roc keeps the text.
			("Str.replace_each", [s, x, y]) => {
				replace = "string::replace(${sql(s)?}, ${sql(x)?}, ${sql(y)?})"
				match Translate.str_lit(x) {
					Ok("") => Translate.eval(s, env)
					Ok(_) => Ok(Binding.Expr(replace))
					Err(_) => Ok(Binding.Expr("(IF ${opd(x)?} = '' THEN ${sql(s)?} ELSE ${replace} END)"))
				}
			}
			("Try.is_ok", [m]) => Translate.none_test(m, "IS NOT NONE", env)
			("Try.is_err", [m]) => Translate.none_test(m, "IS NONE", env)
			("Try.map_ok", [m, f]) => Translate.map_ok(m, f, env)
			("Try.ok_or", [m, d]) => match Translate.eval(m, env)? {
				Maybe(s) => Ok(Binding.Infix("${s} ?? ${opd(d)?}"))
				_ => Err(Unsupported("a clause gives a default only to an optional value"))
			}
			("List.len", [list]) => Translate.count(list, env)
			("List.is_empty", [list]) => Ok(Binding.Infix("${Translate.list_at(list, env)?}.len() = 0"))
			# A captured list (a slot) is `x IN $_k`; a list in the clause is `list CONTAINS x`.
			("List.contains", [list, x]) => match Translate.unwrapped(list) {
				Input(_) => Ok(Binding.Infix("${opd(x)?} IN ${Translate.list_at(list, env)?}"))
				_ => Ok(Binding.Infix("${Translate.list_at(list, env)?} CONTAINS ${opd(x)?}"))
			}
			("List.sum", [list]) => Translate.sum(list, env)
			("List.any", [list, f]) => Translate.lambda(list, f, "any", env)
			("List.all", [list, f]) => Translate.lambda(list, f, "all", env)
			("List.map", [list, f]) => Translate.lambda(list, f, "map", env)
			("List.join_map", [list, f]) => Translate.lambda(list, f, "join_map", env)
			("List.keep_if", [list, f]) => Translate.lambda(list, f, "filter", env)
			("List.drop_if", [list, f]) => Translate.lambda(list, f, "drop", env)
			("List.count_if", [list, f]) => Translate.lambda(list, f, "count", env)
			("List.find_first", [list, f]) => Translate.lambda(list, f, "find", env)
			# An empty list gives `NONE` here, and a float `NULL` from `math::max`.
			("List.first", [list]) => Ok(Binding.Maybe(Translate.call("array::first", [plain(list)?])))
			("List.last", [list]) => Ok(Binding.Maybe(Translate.call("array::last", [plain(list)?])))
			("List.min", [list]) => Ok(Binding.Maybe(Translate.call("array::min", [plain(list)?])))
			("List.max", [list]) => Ok(Binding.Maybe(Translate.call("array::max", [plain(list)?])))
			("List.get", [list, i]) => Ok(Binding.Maybe(Translate.call("array::at", [plain(list)?, sql(i)?])))
			("List.take_first", [list, n]) => {
				source = Translate.list_parts(list, env)?
				Ok(Binding.ListOf({ at: Translate.call("array::slice", [source.at, "0", sql(n)?]), items: Translate.off_path(source.items) }))
			}
			("List.drop_first", [list, n]) => {
				source = Translate.list_parts(list, env)?
				Ok(Binding.ListOf({ at: Translate.call("array::slice", [source.at, sql(n)?]), items: Translate.off_path(source.items) }))
			}
			("List.rev", [list]) => {
				source = Translate.list_parts(list, env)?
				Ok(Binding.ListOf({ at: Translate.call("array::reverse", [source.at]), items: Translate.off_path(source.items) }))
			}
			("List.concat", [a, b]) => Ok(Binding.ListOf({ at: Translate.call("array::concat", [plain(a)?, plain(b)?]), items: Values }))
			("List.append", [list, x]) => Ok(Binding.ListOf({ at: Translate.call("array::append", [plain(list)?, sql(x)?]), items: Values }))
			("List.prepend", [list, x]) => Ok(Binding.ListOf({ at: Translate.call("array::prepend", [plain(list)?, sql(x)?]), items: Values }))
			# `List.join` flattens one level, as `array::flatten` does.
			("List.join", [list]) => Ok(Binding.ListOf({ at: Translate.call("array::flatten", [plain(list)?]), items: Values }))
			("List.is_eq", [a, b]) => Ok(Binding.Infix("${plain(a)?} = ${plain(b)?}"))
			("Bool.not", [x]) => match x {
				Op({ op: Prim({ id, .. }), args: [lhs, rhs], .. }) if Translate.is_equality(id, env) => match (if (id == Code.prim(Str.is_eq)) Translate.key_compare(lhs, rhs, "!=", env)? else Plain) {
					Keyed(compared) => Ok(compared)
					Plain =>
						match Translate.moments(lhs, rhs, env)? {
							Moments(pair) => Ok(Binding.Infix("${pair.left} != ${pair.right}"))
							Texts => Ok(Binding.Infix("${opd(lhs)?} != ${opd(rhs)?}"))
						}
				}
				Op({ op: Switch(sw), args: switch_args, .. }) if sw.joins.is_empty() and sw.outputs.len() == 1 =>
					match Translate.tag_test(sw.arms.map(|a| a.key), switch_args, env) {
						Ok(found) => Ok(Binding.Infix("${found.at} != ${Ql.quote(found.name)}"))
						Err(_) => Ok(Binding.Infix("!${opd(x)?}"))
					}
				_ => Ok(Binding.Infix("!${opd(x)?}"))
			}
			("Num.Dec.to_i64_try", [d]) => {
				truncated = "(IF ${opd(d)?} >= 0 THEN math::floor(${sql(d)?}) ELSE math::ceil(${sql(d)?}) END)"
				Ok(Binding.Maybe("(IF ${opd(d)?} > -9223372036854775809dec AND ${opd(d)?} < 9223372036854775808dec THEN <int>${truncated} ELSE NONE END)"))
			}
			(_, [n]) if whole and method.starts_with("to_") and method.ends_with("_try") => Translate.int_try(method, n, env)
			(_, [n]) if owner.starts_with("Num.") => match method {
				"negate" => Ok(Binding.Infix("-${opd(n)?}"))
				"abs" => Ok(Binding.Expr("math::abs(${sql(n)?})"))
				"to_dec" => Ok(Binding.Expr("<decimal>${opd(n)?}"))
				"to_f64" | "to_f32" => Ok(Binding.Expr("<float>${opd(n)?}"))
				# SurrealDB integers are already `int` (I64). The conversions that Roc allows without a check are the identity.
				"to_i16" | "to_i32" | "to_i64" | "to_i128" | "to_u16" | "to_u32" | "to_u64" | "to_u128" | "to_i64_wrap" if whole => Translate.eval(n, env)
				"to_i64" | "to_i64_wrap" =>
					Err(Unsupported("`${method}` on `${owner}` cuts the fraction, and SurrealDB's `<int>` raises an error on one; use `to_i64_try`"))
				"from_str" => Err(Unsupported("`from_str` accepts more forms than SurrealDB casts; parse in Roc and store a number"))
				"is_zero" if whole or dec => Ok(Binding.Infix("${opd(n)?} = 0"))
				"is_negative" if whole or dec => Ok(Binding.Infix("${opd(n)?} < 0"))
				"is_positive" if whole or dec => Ok(Binding.Infix("${opd(n)?} > 0"))
				"is_even" if whole => Ok(Binding.Infix("${opd(n)?} % 2 = 0"))
				"is_odd" if whole => Ok(Binding.Infix("${opd(n)?} % 2 != 0"))
				# `<string>5u8` is `'5u8'`: a sized integer is a `decimal` first.
				"to_str" if whole and Translate.is_sized(owner) => Ok(Binding.Expr("<string><decimal>${opd(n)?}"))
				"to_str" if whole => Ok(Binding.Expr("<string>${opd(n)?}"))
				"to_str" if dec => Err(Unsupported("`to_str` on `Dec` prints differently: Roc `3.0`, SurrealDB `3`; compare the number"))
				# SurrealDB `math::round` rounds a tie to even, and Roc rounds it away from zero.
				"round" if dec =>
					Ok(Binding.Expr("(IF ${opd(n)?} >= 0 THEN math::floor(${opd(n)?} + 0.5dec) ELSE math::ceil(${opd(n)?} - 0.5dec) END)"))
				"floor" if dec => Ok(Binding.Expr("math::floor(${sql(n)?})"))
				"ceiling" if dec => Ok(Binding.Expr("math::ceil(${sql(n)?})"))
				# SurrealDB has no `math::trunc`.
				"trunc" if dec => Ok(Binding.Expr("(IF ${opd(n)?} >= 0 THEN math::floor(${sql(n)?}) ELSE math::ceil(${sql(n)?}) END)"))
				"is_zero" | "is_negative" | "is_positive" | "to_str" => Err(Translate.float_note(owner, method))
				_ => Err(Unsupported("`${owner}.${method}` has no SurrealQL form"))
			}
			(_, [a, b]) if owner.starts_with("Num.") => match method {
				"max" | "min" if whole or dec => Ok(Binding.Expr("math::${method}([${sql(a)?}, ${sql(b)?}])"))
				"pow" if whole => Ok(Binding.Expr(Translate.call("math::pow", [sql(a)?, sql(b)?])))
				"pow" if dec => Err(Unsupported("`pow` on `Dec` keeps 18 digits in Roc and 28 in SurrealDB; the two differ"))
				# `mod_by` is the floored modulus: the sign of the divisor.
				"mod_by" if whole => {
					x = Translate.whole_operand(owner, Bool.True, a, env)?
					y = Translate.whole_operand(owner, Bool.True, b, env)?
					Ok(Binding.Expr("(((${x} % ${y}) + ${y}) % ${y})"))
				}
				"is_multiple_of" if whole =>
					if Translate.is_nonzero(b) {
						Ok(Binding.Infix("${opd(a)?} % ${opd(b)?} = 0"))
					} else {
						Ok(Binding.Expr("(IF ${opd(b)?} = 0 THEN ${opd(a)?} = 0 ELSE ${opd(a)?} % ${opd(b)?} = 0 END)"))
					}
				"max" | "min" | "pow" => Err(Translate.float_note(owner, method))
				_ => Translate.binary(owner, method, a, b, env)
			}
			(_, [lhs, rhs]) if owner == "Str" => Translate.binary(owner, method, lhs, rhs, env)
			_ => Err(Unsupported("`${owner}.${method}` has no SurrealQL form"))
		}
	}

	## The operands of an equality where one text is the text of a datetime. The datetimes are compared,
	## because SurrealDB prints a fraction with 3, 6 or 9 digits and Roc does not. The other text must be a literal.
	moments : Code.Tree, Code.Tree, Env -> Try([Moments({ left : Str, right : Str }), Texts], Ql.Error)
	moments = |lhs, rhs, env| {
		not_literal = Unsupported("the text of a datetime is compared with a datetime or a literal; SurrealDB prints a fraction with 3, 6 or 9 digits, so other texts differ")
		literal = |tree| match Translate.str_lit(tree) {
			Ok(iso) => Ok(Ql.literal(Ql.Value.Datetime(iso)))
			Err(_) => Err(not_literal)
		}
		match (Translate.eval(lhs, env)?, Translate.eval(rhs, env)?) {
			(Moment(a), Moment(b)) => Ok(Moments({ left: a, right: b }))
			(Moment(a), _) => Ok(Moments({ left: a, right: literal(rhs)? }))
			(_, Moment(b)) => Ok(Moments({ left: b, right: literal(lhs)? }))
			_ => Ok(Texts)
		}
	}

	## A function of `Surreal.Text`, `Hash`, `Array`, `Time`, `Math`, `Rand` or `Geo`, in the
	## form `Surreal.library` gives its id. `name` names the call in a refusal.
	library : Form, Str, List(Code.Tree), Code.Ty, Env -> Try(Binding, Ql.Error)
	library = |found, name, args, ty, env| {
		sql = |node| Translate.expr(node, env)
		opd = |node| Translate.arg(node, env)
		random = match found {
			Function(f) => f.random
			Uuid => Bool.True
			_ => Bool.False
		}
		if random and !env.random {
			return Err(Unsupported("`${name}` gives a new value on every call: use it in a default, a computed field or an update"))
		}
		match (found, args) {
			# A `uuid` is its own type in SurrealDB, and a `string` column refuses it.
			(Uuid, []) => Ok(Binding.Expr("<string>rand::uuid()"))
			# The unit is a tag that the clause writes: `Month` is `'month'`.
			(TimeGroup, [time, Op({ op: Tag(unit), args: [], .. })]) => Ok(Binding.Expr(Translate.call("time::group", [sql(time)?, Ql.quote(unit.with_ascii_lowercased())])))
			(TimeGroup, _) => Err(Unsupported("the unit of `Time.group` is a tag that the clause writes, as `Month`"))
			(Operator(symbol), [a, b]) => Ok(Binding.Infix("${opd(a)?} ${symbol} ${opd(b)?}"))
			# `math::percentile` of a group's rows gives `NULL` in SurrealDB.
			(Percentile, [list, percent]) => {
				values = Translate.aggregate_list(list, env)?
				if values.grouped {
					Err(Unsupported("`math::percentile` is not an aggregate in SurrealDB; use it on a list"))
				} else {
					Ok(Binding.Expr(Translate.call("math::percentile", [values.text, sql(percent)?])))
				}
			}
			(Aggregate(surql), [list]) => Translate.aggregate_arg(surql, list, env)
			(Aggregate(_), _) => Err(Unsupported("`${name}` takes a list"))
			(FloatAggregate(surql), [list]) => Translate.float_aggregate_arg(surql, list, env)
			(FloatAggregate(_), _) => Err(Unsupported("`${name}` takes a list"))
			(Function(f), _) => Ok(Translate.at(Translate.call(f.surql, args.map_try(sql)?), ty))
			_ => Err(Unsupported("`${name}` has no SurrealQL form"))
		}
	}

	## A call to a SurrealQL function: `name(a, b)`.
	call : Str, List(Str) -> Str
	call = |name, parts| "${name}(${Str.join_with(parts, ", ")})"

	## The characters that Roc's `Str.trim` removes, as a SurrealQL regex class.
	blank : Str
	blank = "[\\s\\u{200E}\\u{200F}]+"

	## The text with the letters from `low` to `high` changed by a SurrealQL
	## function. It works per character, because `string::uppercase` also
	## changes the letters outside ASCII, and Roc does not.
	ascii_case : Str, Str, Str, Str -> Str
	ascii_case = |input, low, high, fn|
		"array::join(string::split(${input}, '').map(|$ch| IF $ch >= '${low}' AND $ch <= '${high}' THEN string::${fn}($ch) ELSE $ch END), '')"

	## The text of a string literal, when the tree is one.
	str_lit : Code.Tree -> Try(Str, [NotLiteral])
	str_lit = |tree| match tree {
		Op({ op: Lit(Str(found)), .. }) => Ok(found)
		_ => Err(NotLiteral)
	}

	## Whether a tree is an integer literal other than zero.
	is_nonzero : Code.Tree -> Bool
	is_nonzero = |tree| match tree {
		Op({ op: Lit(Int(n, _)), .. }) => n != 0
		_ => Bool.False
	}

	## What a float operation differs in, for a refusal.
	float_note : Str, Str -> Ql.Error
	float_note = |owner, method| Unsupported("`${method}` on `${owner}` differs from SurrealDB for NaN, -0.0 and how a float prints; use `Dec` or an integer")

	## A conversion `to_<int>_try` of an integer: `NONE` when the value is
	## outside the range of the target. A value of a SurrealDB int is always
	## inside the range that has no bound.
	int_try : Str, Code.Tree, Env -> Try(Binding, Ql.Error)
	int_try = |method, n, env| {
		target = method.drop_prefix("to_").drop_suffix("_try")
		(lo, hi) = match Translate.int_range(target) {
			Ok(range) => range
			Err(_) => return Err(Unsupported("`${method}` has no SurrealQL form"))
		}
		value = Translate.arg(n, env)?
		tests = List.concat(if (lo.is_empty()) [] else ["${value} >= ${lo}"], if (hi.is_empty()) [] else ["${value} <= ${hi}"])
		if tests.is_empty() {
			Ok(Binding.Maybe(value))
		} else {
			Ok(Binding.Maybe("(IF ${Str.join_with(tests, " AND ")} THEN ${Translate.expr(n, env)?} ELSE NONE END)"))
		}
	}

	## The bounds of an integer type by its Roc name. A bound is empty when
	## no value of a SurrealDB int is beyond it.
	int_range : Str -> Try((Str, Str), [NotInt])
	int_range = |name| match name {
		"i8" => Ok(("-128", "127"))
		"i16" => Ok(("-32768", "32767"))
		"i32" => Ok(("-2147483648", "2147483647"))
		"i64" | "i128" => Ok(("", ""))
		"u8" => Ok(("0", "255"))
		"u16" => Ok(("0", "65535"))
		"u32" => Ok(("0", "4294967295"))
		"u64" | "u128" => Ok(("0", ""))
		_ => Err(NotInt)
	}

	none_test : Code.Tree, Str, Env -> Try(Binding, Ql.Error)
	none_test = |tree, test, env| match Translate.eval(tree, env)? {
		Maybe(s) => Ok(Binding.Infix("${s} ${test}"))
		_ => Err(Unsupported("a clause tests presence only of an optional value"))
	}

	## The list a list operation runs over, as the start of a method chain.
	list_at : Code.Tree, Env -> Try(Str, Ql.Error)
	list_at = |tree, env| Ok(Translate.list_parts(tree, env)?.at)

	## The same, with whether its elements are values, or record ids that a
	## read traverses: the edges of a relation, or the rows of a table.
	list_parts : Code.Tree, Env -> Try({ at : Str, items : Items }, Ql.Error)
	list_parts = |tree, env| match Translate.eval(tree, env)? {
		ListOf(list) => Ok(list)
		Group(_) | Column(_) => Err(Unsupported("a group's rows take `len`, `keep_if(..).len()` and `map(..).sum()`"))
		other => Ok({ at: Translate.operand(other)?, items: Values })
	}

	## A list of values. The edges of a relation and the rows of a table are
	## record ids, so an operation that gives one element or a new list
	## refuses them.
	plain_list : Code.Tree, Env -> Try(Str, Ql.Error)
	plain_list = |tree, env| {
		source = Translate.list_parts(tree, env)?
		match source.items {
			Records({ edge, .. }) => Err(Unsupported("the ${if (edge) "edges of a relation" else "rows of a table"} take `keep_if`, `map`, `any`, `all` and `len`"))
			Values | Made => Ok(source.at)
		}
	}

	## `len`: over a group's rows `count()`, or `count(f)` after `keep_if(f)`;
	## over a list `.len()`.
	count : Code.Tree, Env -> Try(Binding, Ql.Error)
	count = |list, env| match list {
		Op({ op: Prim({ id, .. }), args: [rows, Op({ op: Closure(row), args: captures, .. }) as f], .. }) if id == Code.prim(List.keep_if) =>
			match Translate.eval(rows, env)? {
				Group(source) => Ok(Binding.Expr("count(${Translate.over_group(row, captures, source, env)?})"))
				# The rows of a table: a count needs no order (`Translate.where_of`).
				found if Translate.rows_table(found).is_ok() => Translate.lambda(rows, f, "count", env)
				_ => Ok(Binding.Expr("${Translate.list_at(list, env)?}.len()"))
			}
		_ => match Translate.eval(list, env)? {
			Group(_) => Ok(Binding.Expr("count()"))
			_ => Ok(Binding.Expr("${Translate.list_at(list, env)?}.len()"))
		}
	}

	## `sum`: `map(f).sum()` over a group's rows is `math::sum(f)`, and over a
	## list `math::sum` of the list.
	sum : Code.Tree, Env -> Try(Binding, Ql.Error)
	sum = |list, env| {
		whole = match Translate.type_of(list, env) {
			Ok(ListOf(item)) => Translate.is_integer(item)
			_ => Bool.False
		}
		if env.view == View and whole and Translate.aggregate_list(list, env)?.grouped {
			# A view keeps `math::sum` of an `int` column as a `float` (verified).
			Err(Unsupported("`math::sum` of an integer column is a float in a view; convert it with `to_f64()`"))
		} else {
			Translate.aggregate_arg("math::sum", list, env)
		}
	}

	is_integer : Code.Ty -> Bool
	is_integer = |ty| match ty {
		I8 | I16 | I32 | I64 | I128 | U8 | U16 | U32 | U64 | U128 => Bool.True
		_ => Bool.False
	}

	## An aggregate function of a list: over a group's rows `fn(f)` for
	## `map(f)`, and over a list `fn` of the list. A view refuses
	## `math::median` over a group's rows (verified).
	aggregate_arg : Str, Code.Tree, Env -> Try(Binding, Ql.Error)
	aggregate_arg = |function, list, env| {
		values = Translate.aggregate_list(list, env)?
		if env.view == View and values.grouped and function == "math::median" {
			Err(Unsupported("SurrealDB does not keep `math::median` in a view; compute it in a query"))
		} else if env.view == Totals and values.grouped and function == "math::median" {
			Err(Unsupported("`math::median` of no rows is `NONE`, not a number, and `totals` always gives one row; take the median per group with `group_by`"))
		} else {
			Ok(Binding.Expr(Translate.call(function, [values.text])))
		}
	}

	## An aggregate of a list of decimals or integers, over each value as a
	## float: `math::mean(<float>fee)` over a group's rows, and over a list
	## `math::mean(list.map(|$c| <float>$c))`.
	float_aggregate_arg : Str, Code.Tree, Env -> Try(Binding, Ql.Error)
	float_aggregate_arg = |function, list, env| {
		values = Translate.aggregate_list(list, env)?
		floats = if values.grouped "<float>${values.text}" else "${values.text}.map(|$c| <float>$c)"
		Ok(Binding.Expr(Translate.call(function, [floats])))
	}

	## The text of the list of an aggregate, and whether it is a group's rows.
	aggregate_list : Code.Tree, Env -> Try({ text : Str, grouped : Bool }, Ql.Error)
	aggregate_list = |list, env| match Translate.eval(list, env)? {
		Column(found) => Ok({ text: found, grouped: Bool.True })
		_ => Ok({ text: Translate.list_at(list, env)?, grouped: Bool.False })
	}

	## A closure over a group's rows: its parameter is the row the group
	## aggregates, so `|o| o.total` is `total`.
	over_group : U32, List(Code.Tree), Binding, Env -> Try(Str, Ql.Error)
	over_group = |row, captures, source, env| {
		values = captures.map_try(|c| Translate.eval(c, env))?
		Translate.text(Translate.expand(row, values.append(source), env)?)
	}

	## A list operation with a closure: `xs.any(|$v1| ..)`. The closure's row
	## is expanded with its captured values and its element bound to `$vN`,
	## where `N` is the row's id, so a nested closure never shadows its
	## parent's variable. Over a graph path, a filter that reads only its
	## element is `[WHERE ..]`, and a `map` or `join_map` whose function
	## reads a path off its element continues the path (`Translate.hop`).
	lambda : Code.Tree, Code.Tree, Str, Env -> Try(Binding, Ql.Error)
	lambda = |list, f, name, env| {
		(row, captures) = match f {
			Op({ op: Closure(r), args: c, .. }) => (r, c)
			_ => return Err(Unsupported("`${name}` takes a function the clause writes or names"))
		}
		source = Translate.eval(list, env)?
		(list_text, items) = match source {
			ListOf(l) => (l.at, l.items)
			Group(rows) if name == "map" => return Ok(Binding.Column(Translate.over_group(row, captures, rows, env)?))
			Group(_) | Column(_) => return Err(Unsupported("a group's rows take `len`, `keep_if(..).len()` and `map(..).sum()`"))
			other => (Translate.operand(other)?, Values)
		}
		var_name = "$v${row.to_str()}"
		element_ty = match env.graph.row(row).params.last() {
			Ok(found) => found
			Err(_) => return Err(Unsupported("`${name}` takes a function of one element"))
		}
		graph = match items {
			Records({ graph: Edges(ends), .. }) => Edges(ends)
			Records({ graph: Nodes, .. }) => Nodes
			_ => Off
		}
		on_path = graph != Off
		if on_path and captures.is_empty() and (name == "filter" or name == "drop") {
			# The record of the filter is the one that the path reads.
			edge = match items {
				Records(r) => r.edge
				_ => Bool.False
			}
			test = Translate.expand(row, [Binding.Row({ at: "", of: Doc(Unnamed), edge })], env)?
			condition = if (name == "filter") Translate.text(test)? else "!${Translate.operand(test)?}"
			return Ok(Binding.ListOf({ at: "${list_text}[WHERE ${condition}]", items }))
		}
		element = match items {
			Records({ edge, .. }) => Binding.Row({ at: var_name, of: Ref(element_ty), edge })
			Values => Translate.at(var_name, element_ty)
			Made =>
				if Translate.holds_linked(element_ty) {
					return Err(Unsupported("a list that the clause made holds whole linked rows, which are copies; read their fields in the `map` that made it"))
				} else {
					Translate.at(var_name, element_ty)
				}
		}
		values = captures.map_try(|c| Translate.eval(c, env))?
		if name == "filter" or name == "count" {
			match Translate.series_range(list, row, values.append(element), var_name, env)? {
				Ranged(range) => return Ok(if (name == "count") Binding.Expr("${range}.len()") else Binding.ListOf({ at: range, items }))
				Scan => {}
			}
		}
		if ["filter", "count", "any", "find"].contains(name) {
			match (Translate.rows_table(source), items) {
				(Ok(table), Records(r)) =>
					match Translate.where_of(table, r.edge, row, values, element, name, items, env)? {
						Pushed(pushed) => return Ok(pushed)
						Scan => {}
					}
				_ => {}
			}
		}
		plain = match items {
			Values => Bool.True
			Made | Records(_) => Bool.False
		}
		if name == "any" and plain {
			match Translate.member_of(list_text, row, values, element_ty, env)? {
				Member(test) => return Ok(Binding.Infix(test))
				Scan => {}
			}
		}
		result = Translate.expand(row, values.append(element), env)?
		closure = |inner| "|${var_name}| ${inner}"
		if on_path and (name == "map" or name == "join_map") {
			match Translate.hop(list_text, graph, var_name, result, name == "join_map") {
				Ok(continued) => return Ok(continued)
				Err(NotAPath) => {}
			}
		}
		match name {
			"any" | "all" => Ok(Binding.Expr("${list_text}.${name}(${closure(Translate.text(result)?)})"))
			"map" => Ok(Binding.ListOf({ at: "${list_text}.map(${closure(Translate.text(result)?)})", items: Made }))
			"join_map" => {
				# `array::flatten` joins one level, as `List.join_map` does.
				joined = match result {
					ListOf(l) => Translate.off_path(l.items)
					_ => Values
				}
				Ok(Binding.ListOf({ at: Translate.call("array::flatten", ["${list_text}.map(${closure(Translate.text(result)?)})"]), items: joined }))
			}
			"filter" => Ok(Binding.ListOf({ at: "${list_text}.filter(${closure(Translate.text(result)?)})", items }))
			"drop" => Ok(Binding.ListOf({ at: "${list_text}.filter(${closure("!${Translate.operand(result)?}")})", items }))
			"count" => Ok(Binding.Expr("${list_text}.filter(${closure(Translate.text(result)?)}).len()"))
			_ => Ok(Binding.Maybe("${list_text}.find(${closure(Translate.text(result)?)})"))
		}
	}

	## `t.rows().keep_if(|v| v.id.series() == x)` over a time series: a
	## range scan of the keys `[x, ..]`, where `filter` reads the whole
	## table for each `x` (verified: 0.3 s against 19 s, 200 kennels of
	## 20000 readings). The subquery reads `x` as `$vN`, because its
	## `FROM` does not read the fields of the row:
	## `x.chain(|$v1| (SELECT VALUE id FROM t:[$v1, NONE]..=[$v1, ..]))`.
	## A key always has its time, so no key is `[x]`, the one key the
	## range leaves out. `Scan` is any other filter.
	series_range : Code.Tree, U32, List(Binding), Str, Env -> Try([Ranged(Str), Scan], Ql.Error)
	series_range = |list, row, values, var_name, env| {
		table = match list {
			Op({ op: Prim({ id, .. }), args: [table_tree], .. }) =>
				match Translate.form(id, env.extensions) {
					Ok(Rows) =>
						match Translate.eval(table_tree, env)? {
							Table(t) if !t.edge => t.name
							_ => return Ok(Scan)
						}
					_ => return Ok(Scan)
				}
			_ => return Ok(Scan)
		}
		element = (env.graph.row(row).params.len() - 1).to_u32_wrap()
		is_series = |tree| match tree {
			Op({ op: Prim({ id, .. }), args: [Op({ op: Field("id"), args: [Param(k)], .. })], .. }) if k == element =>
				match Translate.form(id, env.extensions) {
					Ok(SeriesOf) => Bool.True
					_ => Bool.False
				}
			_ => Bool.False
		}
		(lhs, rhs) = match Translate.body(env.graph.to_tree(row)) {
			Op({ op: Prim({ id, .. }), args: [a, b], .. }) if Translate.is_equality(id, env) => (a, b)
			_ => return Ok(Scan)
		}
		key_tree =
			if is_series(lhs) {
				rhs
			} else if is_series(rhs) {
				lhs
			} else {
				return Ok(Scan)
			}
		if Translate.reads_param(key_tree, element) {
			return Ok(Scan)
		}
		key = Translate.operand(Translate.eval(key_tree, { ..env, params: values, row, nodes: [], depth: env.depth + 1 })?)?
		Ok(Ranged("${key}.chain(|${var_name}| (SELECT VALUE id FROM ${Ql.ident(table)}:[${var_name}, NONE]..=[${var_name}, ..]))"))
	}

	## `t.rows()` with a `keep_if`, `count_if`, `any` or `find_first`: the
	## conjuncts of the function that read the element go into the
	## `WHERE` of the subquery, so an index can serve them; the other
	## conjuncts stay a `filter`. A value of the
	## clause that a conjunct compares with is bound around the subquery
	## with `chain`, as the subquery reads its own row:
	## `id.chain(|$v3_0| (SELECT VALUE id FROM kennel WHERE site = $v3_0)).len()`.
	## `$parent.id` in place of `chain` is a `TableScan` on 3.3.5 and
	## 4.0.0, and is `NONE` in an `UPDATE .. WHERE` and in a view on
	## 3.3.5 (verified). `chain` uses the index on 3.3.5. A filter or a
	## find with a test other than `==` reads the rows `ORDER BY id`, the
	## order of the table. `Scan` when no conjunct can go into the `WHERE`.
	where_of : Str, Bool, U32, List(Binding), Binding, Str, Items, Env -> Try([Pushed(Binding), Scan], Ql.Error)
	where_of = |table, edge, row, values, element, name, items, env| {
		k = values.len().to_u32_wrap()
		var_name = "$v${row.to_str()}"
		outside = { ..env, params: values.append(element), row, nodes: [], depth: env.depth + 1 }
		inside = { ..outside, params: values.append(Translate.table_row(table, edge)) }
		start = { kept: [], rest: [], chains: [], nodes: [], ordered: Bool.False }
		split = Translate.conjuncts(Translate.body(env.graph.to_tree(row))).fold(
			start,
			|acc, c| match Translate.pushed_test(c, k, acc.nodes.len(), "${var_name}_", outside, inside) {
				Ok(p) =>
					{
						kept: acc.kept.append(p.test),
						rest: acc.rest,
						chains: acc.chains.concat(p.chains),
						nodes: acc.nodes.concat(p.nodes),
						ordered: acc.ordered or !Translate.is_equality_tree(c, env),
					}
				Err(_) => { ..acc, rest: acc.rest.append(c) }
			},
		)
		if split.kept.is_empty() {
			return Ok(Scan)
		}
		# The pushed tests read the bound values as kept nodes.
		tests = split.kept.map_try(
			|tree| {
				spelled = Translate.eval(tree, { ..inside, nodes: split.nodes })?
				if (split.kept.len() == 1) Translate.text(spelled) else Translate.operand(spelled)
			},
		)?
		rest = split.rest.map_try(|c| Translate.eval(c, outside))?
		rest_text = match rest {
			[] => ""
			[one] => Translate.text(one)?
			many => Str.join_with(many.map_try(Translate.operand)?, " AND ")
		}
		# `find` takes the first row by key, as the Roc `find_first` over the
		# rows in key order: SurrealDB 4 reads them in no fixed order.
		order = if ((split.ordered and name == "filter") or name == "find") " ORDER BY id" else ""
		select = |limit| split.chains.fold_rev("(SELECT VALUE id FROM ${table} WHERE ${Str.join_with(tests, " AND ")}${order}${limit})", |c, inner| "${c.value}.chain(|${c.slot}| ${inner})")
		closure = |method| "${select("")}.${method}(|${var_name}| ${rest_text})"
		pushed = match (name, rest_text) {
			("filter", "") => Binding.ListOf({ at: select(""), items })
			("filter", _) => Binding.ListOf({ at: closure("filter"), items })
			("count", "") => Binding.Expr("${select("")}.len()")
			("count", _) => Binding.Expr("${closure("filter")}.len()")
			("any", "") => Binding.Infix("${select(" LIMIT 1")} != []")
			("any", _) => Binding.Expr(closure("any"))
			(_, "") => Binding.Maybe("${select(" LIMIT 1")}[0]")
			_ => Binding.Maybe(closure("find"))
		}
		Ok(Pushed(pushed))
	}

	## One conjunct of a function over the rows of a table as a test of
	## the `WHERE`: each largest part that does not read the element `k`
	## and reads a value of the clause becomes a kept node, bound to that
	## value. A `$` parameter is read in place; any other value is bound
	## with `chain` to `<prefix><n>`. `Err` when the conjunct does not read
	## the element as a value, or a part has no SurrealQL value to bind.
	pushed_test : Code.Tree, U32, U64, Str, Env, Env -> Try({ test : Code.Tree, chains : List({ value : Str, slot : Str }), nodes : List({ id : U32, binding : Binding, ty : Try(Code.Ty, [Untyped]) }) }, [Stays])
	pushed_test = |conjunct, k, before, prefix, outside, inside| {
		# A conjunct that does not read the row is no test of the row.
		if !Translate.reads_param(conjunct, k) {
			return Err(Stays)
		}
		(test, parts) = Translate.lift(conjunct, k, before, [])?
		bound = parts.map_try(
			|part| {
				n = part.n
				ty = Translate.type_of(part.tree, outside)
				at_place = |place| match ty {
					Ok(found) => Translate.at(place, found)
					Err(_) => Binding.Expr(place)
				}
				# A row of a table keeps its table, so `t.id(r.id)` stays its id.
				(value, at_slot) = match Translate.eval(part.tree, outside) {
					Ok(Expr(s)) | Ok(Maybe(s)) => (s, at_place)
					Ok(Infix(s)) => ("(${s})", at_place)
					Ok(ListOf({ at: place, items: Values })) | Ok(ListOf({ at: place, items: Made })) => (place, at_place)
					Ok(Row(r)) if r.of != Obj => (if (r.at.is_empty()) "$this" else r.at, |place| Binding.Row({ ..r, at: place }))
					_ => return Err(Stays)
				}
				node = |place| { id: Translate.lifted_id(n), binding: at_slot(place), ty }
				if Translate.is_variable(value) {
					Ok({ chains: [], node: node(value) })
				} else {
					slot = "${prefix}${n.to_str()}"
					Ok({ chains: [{ value, slot }], node: node(slot) })
				}
			},
		)?
		# The test itself must spell in the subquery's row.
		probe = Translate.eval(test, { ..inside, nodes: bound.map(|b| b.node) })
		match probe {
			Ok(Expr(_)) | Ok(Infix(_)) => Ok({ test, chains: bound.join_map(|b| b.chains), nodes: bound.map(|b| b.node) })
			_ => Err(Stays)
		}
	}

	## The id of the kept node of a lifted part `n`, above the ids of a
	## row's own nodes.
	lifted_id : U64 -> U32
	lifted_id = |n| 4000000000 + n.to_u32_wrap()

	## A tree with each largest part that does not read the parameter `k`
	## and is not a constant replaced by a read of a kept node
	## (`Translate.lifted_id`, numbered from `base`), and the parts in
	## order. `Err` for a tree
	## that reads `k` through a kept node or a region.
	lift : Code.Tree, U32, U64, List({ n : U64, tree : Code.Tree }) -> Try((Code.Tree, List({ n : U64, tree : Code.Tree })), [Stays])
	lift = |tree, k, base, parts| {
		# A function is no value: its captured values are.
		if !Translate.reads_param(tree, k) and !Translate.is_closure(tree) {
			if Translate.closed(tree) {
				return Ok((tree, parts))
			}
			n = base + parts.len()
			return Ok((Def(Translate.lifted_id(n)), parts.append({ n, tree })))
		}
		match tree {
			Param(p) if p == k => Ok((tree, parts))
			Op({ op: held, args, ty }) if held.regions().is_empty() => {
				(done, after) = args.fold_try(
					([], parts),
					|(kept, seen), a| {
						(t, more) = Translate.lift(a, k, base, seen)?
						Ok((kept.append(t), more))
					},
				)?
				Ok((Op({ op: held, args: done, ty }), after))
			}
			_ => Err(Stays)
		}
	}

	## Whether a tree reads no parameter and no kept node: a constant, or
	## a parameter of the statement.
	closed : Code.Tree -> Bool
	closed = |tree| match tree {
		Input(_) => Bool.True
		Op({ op: held, args, .. }) => held.regions().is_empty() and args.all(Translate.closed)
		_ => Bool.False
	}

	## Whether a text is a path off a `$` parameter that a subquery reads
	## as the clause does: not `$this` or `$parent`, which name its row.
	is_variable : Str -> Bool
	is_variable = |spelled| {
		names = spelled.drop_prefix("$").split_on(".")
		root = names.first() ?? ""
		spelled.starts_with("$") and names.all(|name| Ql.is_plain(name) or Translate.is_mark(name)) and root != "this" and root != "parent"
	}

	is_equality_tree : Code.Tree, Env -> Bool
	is_equality_tree = |tree, env| match tree {
		Op({ op: Prim({ id, .. }), .. }) => Translate.is_equality(id, env)
		_ => Bool.False
	}

	## `xs.any(|x| x.f == v)` over a list of values, where `v` does not
	## read `x`: `v IN xs[*].f`. An index of `xs[*].f` serves `IN`
	## (`EXPLAIN`: `IndexScan`), where `any` reads the table
	## (`TableScan`). The path reads fields and link ids only. `Scan` is
	## any other closure.
	member_of : Str, U32, List(Binding), Code.Ty, Env -> Try([Member(Str), Scan], Ql.Error)
	member_of = |list_text, row, values, element_ty, env| {
		element = values.len().to_u32_wrap()
		is_path = |tree| Translate.element_path(tree, element, env)
		(lhs, rhs) = match Translate.body(env.graph.to_tree(row)) {
			Op({ op: Prim({ id, .. }), args: [a, b], .. }) if Translate.is_equality(id, env) => (a, b)
			_ => return Ok(Scan)
		}
		(path, value) =
			if is_path(lhs) and !Translate.reads_param(rhs, element) {
				(lhs, rhs)
			} else if is_path(rhs) and !Translate.reads_param(lhs, element) {
				(rhs, lhs)
			} else {
				return Ok(Scan)
			}
		each = "${list_text}[*]"
		inner = { ..env, params: values.append(Translate.at(each, element_ty)), row, nodes: [], depth: env.depth + 1 }
		# A path the translator wraps in a function is no field path of `each`.
		spelled = Translate.text(Translate.eval(path, inner)?)?
		if !spelled.starts_with(each) or spelled.contains("(") {
			return Ok(Scan)
		}
		given = Translate.operand(Translate.eval(value, inner)?)?
		Ok(Member("${given} IN ${spelled}"))
	}

	## Whether a tree reads fields and link ids of the parameter `k` only.
	## A link is a nominal, so its `id` field is under an `Unwrap`.
	element_path : Code.Tree, U32, Env -> Bool
	element_path = |tree, k, env| match tree {
		Param(p) => p == k
		Op({ op: Field(_), args: [inner], .. }) | Op({ op: Unwrap, args: [inner], .. }) => Translate.element_path(inner, k, env)
		Op({ op: Prim({ id, .. }), args: [inner], .. }) =>
			match Translate.form(id, env.extensions) {
				Ok(LinkId) => Translate.element_path(inner, k, env)
				_ => Bool.False
			}
		_ => Bool.False
	}

	# ------------------------------------------------------------ narrowing

	## How a write to a table that a clause reads with `rows()` reaches the
	## rows of the query, for the `LIVE` of that table
	## (`Translate.narrowings`). `table` is the table as SurrealQL spells
	## it. `Every` is each row of the query, and `Related` some of them.
	Narrow : { table : Str, reach : [Every, Related(Related)] }

	## The rows of the query whose value `node` equals the value `written`
	## of the written row, or is in it when `many` (a list). `written`
	## reads the written row as `$parent`, and `each` reads it as `$w`.
	## `fixed` says that `written` reads only the record id of the written
	## row, which a write never changes.
	Related : { node : Str, written : Str, each : Str, many : Bool, fixed : Bool }

	## Each read of a table with `rows()` in a clause, and the rows of the
	## query that a write to the table reaches. A `keep_if`, `any`,
	## `count_if` or `find_first` over the rows whose function holds an
	## equality between a value of the element and a value that does not
	## read it (`==`, or `contains` of a list of the element) is
	## `Related`. Any other read of the table is `Every`.
	narrowings : List(Extension), Code.Graph, List(Binding), (Str -> Str) -> Try(List(Narrow), Ql.Error)
	narrowings = |extensions, graph, bindings, param| {
		root = graph.root_row()
		Translate.narrow(graph.to_tree(root.id), { graph, params: bindings, row: root.id, nodes: [], param, depth: 0, random: Bool.False, view: Plain, self: Outside, extensions }, Bool.True)
	}

	## The reads of `rows()` in a tree. `top` is false in the function of a
	## list operation, where a value of the query's row may be spelled off
	## the element. A list of rows that is passed or kept is not a read:
	## where it is read is.
	narrow : Code.Tree, Env, Bool -> Try(List(Narrow), Ql.Error)
	narrow = |tree, env, top| match tree {
		Param(_) | Def(_) => Ok(Translate.every_of(Translate.eval(tree, env)?))
		Input(_) | Arg(_) | Out(_) => Ok([])
		Block(block) => {
			inner = block.defs.fold_try(
				{ env, found: [] },
				|acc, def| {
					value = Translate.eval(def.value, acc.env)?
					here = if (Translate.rows_table(value).is_ok()) [] else Translate.narrow(def.value, acc.env, top)?
					Ok({ env: { ..acc.env, nodes: acc.env.nodes.append({ id: def.id, binding: value, ty: Translate.type_of(def.value, acc.env) }) }, found: acc.found.concat(here) })
				},
			)?
			ends = match block.end {
				Value(values) => values
				_ => return Err(Unsupported("a clause cannot leave early; every branch delivers its value"))
			}
			rest = ends.map_try(|e| Translate.narrow(e, inner.env, top))?
			Ok(inner.found.concat(rest.join()))
		}
		Op({ op: Prim(found), args, .. }) => Translate.narrow_prim(tree, found, args, env, top)
		Op({ op: Call(row), args, .. }) => {
			if env.depth > 32 or env.graph.row(row).recursive {
				return Err(Unsupported("a function that calls itself has no SurrealQL form"))
			}
			values = args.map_try(|a| Translate.eval(a, env))?
			passed = List.map2(args, values, |a, v| (a, v)).map_try(|(a, v)| if (Translate.rows_table(v).is_ok()) Ok([]) else Translate.narrow(a, env, top))?
			inner = Translate.narrow(env.graph.to_tree(row), { ..env, params: values, row, nodes: [], depth: env.depth + 1 }, top)?
			Ok(passed.join().concat(inner))
		}
		Op({ op: Closure(_), .. }) | Op({ op: Lambda(_), .. }) => Err(Unsupported("a function in a clause means something only as the argument of a list operation"))
		Op({ args, .. }) => args.map_try(|a| Translate.narrow(a, env, top)).map_ok(List.join)
	}

	narrow_prim : Code.Tree, Call, List(Code.Tree), Env, Bool -> Try(List(Narrow), Ql.Error)
	narrow_prim = |tree, found, args, env, top| match (Translate.form(found.id, env.extensions), args) {
		(Ok(Rows), _) => Ok(Translate.every_of(Translate.eval(tree, env)?))
		(Ok(Builtin({ owner: "List", method })), [list, f]) | (Ok(Builtin({ owner: "Try", method })), [list, f]) if Translate.is_closure(f) => {
			source = Translate.eval(list, env)?
			inside = Translate.narrow_closure(source, f, env)?
			match Translate.rows_table(source) {
				Ok(table) => {
					narrows = ["keep_if", "any", "count_if", "find_first"].contains(method)
					Ok([{ table, reach: if (top and narrows) Translate.related(source, f, env) else Every }].concat(inside))
				}
				Err(_) => Ok(Translate.narrow(list, env, top)?.concat(inside))
			}
		}
		_ => args.map_try(|a| Translate.narrow(a, env, top)).map_ok(List.join)
	}

	## The reads of `rows()` in the function of a list operation over
	## `source`, with its element bound as `Translate.lambda` binds it.
	narrow_closure : Binding, Code.Tree, Env -> Try(List(Narrow), Ql.Error)
	narrow_closure = |source, f, env| match f {
		Op({ op: Closure(row), args: captures, .. }) => {
			element_ty = match env.graph.row(row).params.last() {
				Ok(found) => found
				Err(_) => return Err(Unsupported("a list operation takes a function of one element"))
			}
			var_name = "$v${row.to_str()}"
			element = match source {
				ListOf({ items: Records({ edge, .. }), .. }) => Binding.Row({ at: var_name, of: Ref(element_ty), edge })
				_ => Translate.at(var_name, element_ty)
			}
			values = captures.map_try(|c| Translate.eval(c, env))?
			held = List.map2(captures, values, |c, v| (c, v)).map_try(|(c, v)| if (Translate.rows_table(v).is_ok()) Ok([]) else Translate.narrow(c, env, Bool.False))?
			inner = Translate.narrow(env.graph.to_tree(row), { ..env, params: values.append(element), row, nodes: [], depth: env.depth + 1 }, Bool.False)?
			Ok(held.join().concat(inner))
		}
		_ => Err(Unsupported("a list operation takes a function the clause writes or names"))
	}

	## The rows of the query that the function `f` over the rows of a
	## table relates to the written row: a conjunct of its body that
	## compares a value of the element with a value that does not read
	## it. `Every` when no conjunct does.
	related : Binding, Code.Tree, Env -> [Every, Related(Related)]
	related = |source, f, env| {
		(row, captures) = match f {
			Op({ op: Closure(r), args: c, .. }) => (r, c)
			_ => return Every
		}
		element = (env.graph.row(row).params.len() - 1).to_u32_wrap()
		values = match captures.map_try(|c| Translate.eval(c, env)) {
			Ok(found) => found
			Err(_) => return Every
		}
		edge = match source {
			ListOf({ items: Records(r), .. }) => r.edge
			_ => Bool.False
		}
		inner = { ..env, params: values.append(Translate.document("$parent", edge)), row, nodes: [], depth: env.depth + 1 }
		# A side of the element reads no captured value.
		of_element = |t| Translate.reads_param(t, element) and !Translate.reads_below(t, element)
		spelled = |written_tree, node_tree, many| {
			on = |name| Translate.operand(Translate.eval(written_tree, { ..inner, params: values.append(Translate.document(name, edge)) })?)
			Ok({ node: Translate.operand(Translate.eval(node_tree, inner)?)?, written: on("$parent")?, each: on("$w")?, many, fixed: Translate.key_only(written_tree, element) })
		}
		one = |c| match c {
			Op({ op: Prim({ id, .. }), args: [a, b], .. }) if Translate.is_equality(id, env) =>
				if of_element(a) and !Translate.reads_param(b, element) {
					spelled(a, b, Bool.False)
				} else if of_element(b) and !Translate.reads_param(a, element) {
					spelled(b, a, Bool.False)
				} else {
					Err(Unsupported("no relation"))
				}
			Op({ op: Prim({ id, .. }), args: [list, item], .. }) if Translate.is_contains(id, env) =>
				if of_element(list) and !Translate.reads_param(item, element) spelled(list, item, Bool.True) else Err(Unsupported("no relation"))
			Op({ op: Prim({ id, .. }), args: [list, g], .. }) if Translate.is_any(id, env) => {
				scope = |name| Ok({ ..inner, params: values.append(Translate.document(name, edge)) })
				tie = Translate.nested_tie(list, g, [element], scope)?
				on = |name| {
					path_text = tie.path
					path = path_text(name)?
					Ok(Translate.flattened(path, tie.levels))
				}
				Ok({ node: tie.node, written: on("$parent")?, each: on("$w")?, many: Bool.True, fixed: Bool.False })
			}
			_ => Err(Unsupported("no relation"))
		}
		for c in Translate.conjuncts(Translate.body(env.graph.to_tree(row))) {
			match one(c) {
				Ok(r) => return Related(r)
				Err(_) => {}
			}
		}
		Every
	}

	## The relation in `xs.any(|x| ..)`, where `xs` is a path of an
	## element of `tainted` (the element of the function over the rows):
	## a conjunct of the function compares a path of `x` with a value
	## that reads no element, or is such an `any` itself. `path` spells the
	## values of the written row, `$w.stops[*].kennel`, with `scope(name)`
	## the environment of the list where the row is `name`; `levels` are
	## the list levels past the first, which `array::flatten` joins.
	nested_tie : Code.Tree, Code.Tree, List(U32), (Str -> Try(Env, Ql.Error)) -> Try({ node : Str, path : Str -> Try(Str, Ql.Error), levels : U64 }, Ql.Error)
	nested_tie = |list, f, tainted, scope| {
		none = Unsupported("no relation")
		(row, captures) = match f {
			Op({ op: Closure(r), args: c, .. }) => (r, c)
			_ => return Err(none)
		}
		owner = match tainted.last() {
			Ok(k) => k
			Err(_) => return Err(none)
		}
		if !(Translate.reads_param(list, owner) and !Translate.reads_below(list, owner)) {
			return Err(none)
		}
		base = scope("$parent")?
		graph = base.graph
		params = graph.row(row).params
		element = (params.len() - 1).to_u32_wrap()
		element_ty = match params.last() {
			Ok(found) => found
			Err(_) => return Err(none)
		}
		# A captured value that reads an element is of the element too.
		held = captures.fold({ i: 0.U32, found: [] }, |acc, c| { i: acc.i + 1, found: if (tainted.any(|t| Translate.reads_param(c, t))) acc.found.append(acc.i) else acc.found })
		marked = held.found.append(element)
		of_element = |t| marked.any(|m| Translate.reads_param(t, m))
		each_of = |name| {
			outer = scope(name)?
			list_text = match Translate.eval(list, outer)? {
				ListOf({ at: place, items: Values }) => place
				_ => return Err(none)
			}
			values = captures.map_try(|c| Translate.eval(c, outer))?
			each = "${list_text}[*]"
			Ok({ each, env: { ..outer, params: values.append(Translate.at(each, element_ty)), row, nodes: [], depth: outer.depth + 1 } })
		}
		path_at = |a| |name| {
			e = each_of(name)?
			spelled = Translate.text(Translate.eval(a, e.env)?)?
			if spelled.starts_with(e.each) and !spelled.contains("(") Ok(spelled) else Err(none)
		}
		one = |c| match c {
			Op({ op: Prim({ id, .. }), args: [a, b], .. }) if Translate.is_equality(id, base) =>
				if Translate.element_path(a, element, base) and !of_element(b) {
					Ok({ node: Translate.operand(Translate.eval(b, each_of("$parent")?.env)?)?, path: path_at(a), levels: 0 })
				} else if Translate.element_path(b, element, base) and !of_element(a) {
					Ok({ node: Translate.operand(Translate.eval(a, each_of("$parent")?.env)?)?, path: path_at(b), levels: 0 })
				} else {
					Err(none)
				}
			Op({ op: Prim({ id, .. }), args: [inner_list, g], .. }) if Translate.is_any(id, base) => {
				deeper = Translate.nested_tie(inner_list, g, marked, |name| each_of(name).map_ok(|e| e.env))?
				# A path of a path of lists is one list level more.
				Ok({ ..deeper, levels: deeper.levels + 1 })
			}
			_ => Err(none)
		}
		for c in Translate.conjuncts(Translate.body(graph.to_tree(row))) {
			match one(c) {
				Ok(found) => {
					# Each path must spell for both names of the written row.
					path_text = found.path
					match (path_text("$parent"), path_text("$w")) {
						(Ok(_), Ok(_)) => return Ok(found)
						_ => {}
					}
				}
				Err(_) => {}
			}
		}
		Err(none)
	}

	is_any : Code.PrimId, Env -> Bool
	is_any = |id, env| match Translate.form(id, env.extensions) {
		Ok(Builtin({ owner: "List", method: "any" })) => Bool.True
		_ => Bool.False
	}

	## `text` in `array::flatten` `times` times.
	flattened : Str, U64 -> Str
	flattened = |text_in, times| if (times == 0) text_in else Translate.flattened("array::flatten(${text_in})", times - 1)

	is_closure : Code.Tree -> Bool
	is_closure = |tree| match tree {
		Op({ op: Closure(_), .. }) => Bool.True
		_ => Bool.False
	}

	is_contains : Code.PrimId, Env -> Bool
	is_contains = |id, env| match Translate.form(id, env.extensions) {
		Ok(Builtin({ owner: "List", method: "contains" })) => Bool.True
		_ => Bool.False
	}

	## Whether a tree may read a parameter before `k`: a captured value of
	## a function whose element is `k`.
	reads_below : Code.Tree, U32 -> Bool
	reads_below = |tree, k| match tree {
		Param(p) => p < k
		Input(_) => Bool.False
		Op({ op: held, args, .. }) => !held.regions().is_empty() or args.any(|a| Translate.reads_below(a, k))
		_ => Bool.True
	}

	## The conjuncts of a condition: the operands of `and`, at any depth.
	## An operand is a region, a block, even with no kept definitions.
	conjuncts : Code.Tree -> List(Code.Tree)
	conjuncts = |tree| match tree {
		Op({ op: And(_), args, .. }) => args.join_map(|a| Translate.conjuncts(Translate.body(a)))
		other => [other]
	}

	## Whether a tree reads the parameter `k` only through its field `id`.
	key_only : Code.Tree, U32 -> Bool
	key_only = |tree, k| match tree {
		Op({ op: Field("id"), args: [inner], .. }) if Translate.is_param(Translate.unwrapped(inner), k) => Bool.True
		Param(p) => p != k
		Input(_) => Bool.True
		Op({ op: held, args, .. }) => held.regions().is_empty() and args.all(|a| Translate.key_only(a, k))
		_ => Bool.False
	}

	is_param : Code.Tree, U32 -> Bool
	is_param = |tree, k| match tree {
		Param(p) => p == k
		_ => Bool.False
	}

	unwrapped : Code.Tree -> Code.Tree
	unwrapped = |tree| match tree {
		Op({ op: Unwrap, args: [inner], .. }) => Translate.unwrapped(inner)
		other => other
	}

	## A read of the rows of a table, where a value is that list.
	every_of : Binding -> List(Narrow)
	every_of = |binding| match Translate.rows_table(binding) {
		Ok(table) => [{ table, reach: Every }]
		Err(_) => []
	}

	## The table of a list that is the rows of a table, `rows_at`, as
	## SurrealQL spells it.
	rows_table : Binding -> Try(Str, [NotRows])
	rows_table = |binding| match binding {
		ListOf({ at: spelled, items: Records(_) }) => {
			inside = spelled.drop_prefix("(SELECT VALUE id FROM ").drop_suffix(")")
			if spelled.starts_with("(SELECT VALUE id FROM ") and spelled.ends_with(")") and !inside.contains("(") and !inside.contains(")") and !inside.contains(" ") Ok(inside) else Err(NotRows)
		}
		_ => Err(NotRows)
	}

	## Whether a tree may read the parameter `k`. A read of a kept node or
	## a region may, as the tree does not show what it reads.
	reads_param : Code.Tree, U32 -> Bool
	reads_param = |tree, k| match tree {
		Param(p) => p == k
		Input(_) => Bool.False
		Op({ op: held, args, .. }) => !held.regions().is_empty() or args.any(|a| Translate.reads_param(a, k))
		_ => Bool.True
	}

	## A `map` or `join_map` over a graph path, as one path: the function
	## reads a path off its element, `$v1.out.owner.name`, and the path goes
	## on from the list, `->treats->patient.owner.name`. The `to` and `from`
	## of an edge are a hop to the table at that end (`->patient`, `<-vet`).
	## A graph step of a path gives a list and SurrealDB joins it, so a
	## `map` has no graph step after the hop, and a `join_map` ends at one.
	hop : Str, Graph, Str, Binding, Bool -> Try(Binding, [NotAPath])
	hop = |list_text, graph, var_name, result, joined| {
		read = match result {
			Row({ at: place, of: Ref(_), .. }) => place
			ListOf(l) => l.at
			Expr(s) | Maybe(s) => s
			_ => return Err(NotAPath)
		}
		if !read.starts_with(var_name) {
			return Err(NotAPath)
		}
		suffix = read.drop_prefix(var_name)
		if suffix.contains(var_name) {
			return Err(NotAPath)
		}
		arrows = Translate.path_steps(suffix.to_utf8(), 0)?
		step = match graph {
			Edges(ends) => Translate.end_hop(suffix, ends)
			_ => suffix
		}
		path = "${list_text}${step}"
		match (joined, result) {
			(Bool.False, Row({ of: Ref(ty), edge, .. })) if arrows == 0 => Ok(Binding.ListOf({ at: path, items: Records({ edge, row: Typed(ty), graph: Nodes }) }))
			(Bool.False, _) if arrows == 0 => Ok(Binding.ListOf({ at: path, items: Values }))
			(Bool.True, ListOf({ items: Records(r), .. })) if arrows > 0 and r.graph != Off => Ok(Binding.ListOf({ at: path, items: Records(r) }))
			_ => Err(NotAPath)
		}
	}

	## The first step of a path off an edge: its `out` is `->` the table at
	## the end, and its `in` is `<-` the table at the start.
	end_hop : Str, Ends -> Str
	end_hop = |suffix, ends| {
		table = |name| if (name == "?") "?" else Ql.ident(name)
		ends_step = |rest| rest.is_empty() or rest.starts_with(".") or rest.starts_with("->") or rest.starts_with("<-") or rest.starts_with("[")
		after_out = suffix.drop_prefix(".out")
		after_in = suffix.drop_prefix(".in")
		if suffix.starts_with(".out") and ends_step(after_out) {
			"->${table(ends.to)}${after_out}"
		} else if suffix.starts_with(".in") and ends_step(after_in) {
			"<-${table(ends.from)}${after_in}"
		} else {
			suffix
		}
	}

	## The number of graph steps of a path, which is any number of `.name`,
	## `->name`, `<-name` and `[WHERE ..]`. Anything else, such as a call
	## or an operator, is not a path.
	path_steps : List(U8), U64 -> Try(U64, [NotAPath])
	path_steps = |bytes, arrows| match bytes {
		[] => Ok(arrows)
		[46, .. as rest] => Translate.path_steps(Translate.name_end(rest)?, arrows)
		[45, 62, .. as rest] | [60, 45, .. as rest] => Translate.path_steps(Translate.name_end(rest)?, arrows + 1)
		[91, .. as rest] => Translate.path_steps(Translate.bracket_end(rest, 0, Bool.False)?, arrows)
		_ => Err(NotAPath)
	}

	## The bytes after one name: `?`, a bracketed name `⟨..⟩`, or letters,
	## digits and `_`.
	name_end : List(U8) -> Try(List(U8), [NotAPath])
	name_end = |bytes| match bytes {
		[63, .. as rest] => Ok(rest)
		[226, 159, 168, .. as rest] => Translate.bracketed_end(rest)
		_ => {
			rest = Translate.plain_end(bytes)
			if (rest.len() == bytes.len()) Err(NotAPath) else Ok(rest)
		}
	}

	## The bytes after the letters, digits and `_` at the start.
	plain_end : List(U8) -> List(U8)
	plain_end = |bytes| match bytes {
		[b, .. as rest] if (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95 => Translate.plain_end(rest)
		_ => bytes
	}

	## The bytes after the `⟩` that closes a bracketed name. `\` escapes.
	bracketed_end : List(U8) -> Try(List(U8), [NotAPath])
	bracketed_end = |bytes| match bytes {
		[226, 159, 169, .. as rest] => Ok(rest)
		[92, _, .. as rest] | [_, .. as rest] => Translate.bracketed_end(rest)
		[] => Err(NotAPath)
	}

	## The bytes after the `]` that closes a `[WHERE ..]`, past nested
	## brackets and quoted text.
	bracket_end : List(U8), U64, Bool -> Try(List(U8), [NotAPath])
	bracket_end = |bytes, depth, quoted| match bytes {
		[] => Err(NotAPath)
		[92, _, .. as rest] if quoted => Translate.bracket_end(rest, depth, quoted)
		[39, .. as rest] => Translate.bracket_end(rest, depth, !quoted)
		[_, .. as rest] if quoted => Translate.bracket_end(rest, depth, quoted)
		[91, .. as rest] => Translate.bracket_end(rest, depth + 1, quoted)
		[93, .. as rest] => if (depth == 0) Ok(rest) else Translate.bracket_end(rest, depth - 1, quoted)
		[_, .. as rest] => Translate.bracket_end(rest, depth, quoted)
	}

	## `t.map_ok(f)` on a value that may be NONE: NONE stays NONE, and any
	## other value is the closure's result.
	map_ok : Code.Tree, Code.Tree, Env -> Try(Binding, Ql.Error)
	map_ok = |m, f, env| {
		(row, captures) = match f {
			Op({ op: Closure(r), args: c, .. }) => (r, c)
			_ => return Err(Unsupported("`map_ok` takes a function the clause writes or names"))
		}
		optional = match Translate.eval(m, env)? {
			Maybe(s) => s
			_ => return Err(Unsupported("a clause maps only an optional value"))
		}
		payload_ty = match env.graph.row(row).params.last() {
			Ok(found) => found
			Err(_) => return Err(Unsupported("`map_ok` takes a function of one value"))
		}
		values = captures.map_try(|c| Translate.eval(c, env))?
		mapped = match Translate.expand(row, values.append(Translate.at(optional, payload_ty)), env)? {
			Maybe(_) => return Err(Translate.nested_try)
			other => Translate.text(other)?
		}
		Ok(Binding.Maybe(if (mapped == optional or Translate.reads_path(mapped, optional)) mapped else "(IF ${optional} IS NONE THEN NONE ELSE ${mapped} END)"))
	}

	## Whether `mapped` is a dotted path of names under `optional`, a path
	## too: `chip` and `chip.code`. A field of NONE is NONE, so the test of
	## NONE adds nothing.
	reads_path : Str, Str -> Bool
	reads_path = |mapped, optional| {
		is_path = |spelled| spelled.drop_prefix("$").split_on(".").all(|name| Ql.is_plain(name) or Translate.is_mark(name))
		mapped.starts_with("${optional}.") and is_path(mapped) and is_path(optional)
	}

	## A call to one of the application's own functions, expanded with its
	## parameters bound to what the arguments stand for.
	expand : U32, List(Binding), Env -> Try(Binding, Ql.Error)
	expand = |row, values, env| {
		if env.depth > 32 or env.graph.row(row).recursive {
			return Err(Unsupported("a function that calls itself has no SurrealQL form"))
		}
		Translate.eval(env.graph.to_tree(row), { ..env, params: values, row, nodes: [], depth: env.depth + 1 })
	}

	literal : Code.Lit -> Try(Str, Ql.Error)
	literal = |value| match value {
		Int(n, _) => Ok(n.to_str())
		Frac(f, _) => Ok(Ql.float(f))
		Fixed(d) => Ok(Ql.literal(Ql.Value.Decimal(d)))
		Bool(b) => Ok(if (b) "true" else "false")
		Str(s) => Ok(Ql.quote(s))
		Bytes(_) => Err(Unsupported("a byte literal has no SurrealQL form"))
		Numeral(n) => Ok("${Translate.numeral_text(n)}dec")
	}

	## The exact decimal text of a numeral: the sign, the digits before the
	## point, and the digits after it, as many as the source wrote. With the
	## `dec` suffix SurrealQL reads it as a decimal.
	numeral_text : Numeral -> Str
	numeral_text = |n| {
		sign = if (n.is_negative()) "-" else ""
		after_count = n.digits_after_pt_count()
		after_point =
			if after_count == 0 {
				""
			} else {
				digits = Translate.decimal_digits(n.digits_after_pt())
				".${"0".repeat(after_count - digits.count_utf8_bytes())}${digits}"
			}
		"${sign}${Translate.decimal_digits(n.digits_before_pt())}${after_point}"
	}

	## The decimal digits of a number given in base-256 digits, most
	## significant first.
	decimal_digits : List(U8) -> Str
	decimal_digits = |base256| {
		# Decimal digits, least significant first: each base-256 digit
		# multiplies what is there by 256 and adds itself.
		reversed = base256.fold(
			[0.U8],
			|digits, byte| {
				var $carry = byte.to_u32()
				var $out = []
				for digit in digits {
					value = digit.to_u32() * 256 + $carry
					$out = $out.append((value % 10).to_u8_wrap())
					$carry = value // 10
				}
				while $carry > 0 {
					$out = $out.append(($carry % 10).to_u8_wrap())
					$carry = $carry // 10
				}
				$out
			},
		)
		Str.from_utf8(reversed.rev().map(|digit| digit + 48)) ?? "0"
	}

	## `==` or `!=` between the key of the row a statement reads and a
	## value given to the statement (a text literal, a field of the
	## parameter record, a captured value), in either order, as a
	## comparison of the record id: `v.id == "tia"` is `id = vet:⟨tia⟩`,
	## and `v.id == p.key` is `id = type::record('vet', $key)`. It means
	## the same as `record::id(id) = 'tia'`, as every record of the table
	## `vet` has the table `vet`, and `type::record` keeps a text key a
	## text (verified: `type::record('vet', '123')` is `vet:⟨123⟩`, not
	## `vet:123`). A `SELECT` reads the one record for it and scans the
	## table for `record::id(id)` (`EXPLAIN`: `RecordIdScan`, `DynamicScan`).
	key_compare : Code.Tree, Code.Tree, Str, Env -> Try([Keyed(Binding), Plain], Ql.Error)
	key_compare = |lhs, rhs, symbol, env| {
		key_table = |tree| match tree {
			Op({ op: Field("id"), args: [holder], .. }) =>
				match Translate.eval(holder, env) {
					Ok(Row({ at: place, of: Doc(Of(name)), .. })) if place.is_empty() => Ok(name)
					_ => Err(NotKey)
				}
			_ => Err(NotKey)
		}
		given = |tree| match tree {
			Op({ op: Lit(Str(key)), .. }) => Literal(key)
			Input(_) => Given
			Op({ op: Field(_), args: [Param(k)], .. }) =>
				match env.params.get(k.to_u64()) {
					Ok(Params) => Given
					_ => NotGiven
				}
			_ => NotGiven
		}
		pair = match (key_table(lhs), key_table(rhs)) {
			(Ok(name), _) => Ok({ name, value: rhs })
			(_, Ok(name)) => Ok({ name, value: lhs })
			_ => Err(NotKey)
		}
		match pair {
			Ok(p) =>
				match given(p.value) {
					Literal(key) => Ok(Keyed(Binding.Infix("id ${symbol} ${Ql.record_id(p.name, key)}")))
					Given => Ok(Keyed(Binding.Infix("id ${symbol} type::record(${Ql.quote(p.name)}, ${Translate.expr(p.value, env)?})")))
					NotGiven => Ok(Plain)
				}
			Err(NotKey) => Ok(Plain)
		}
	}

	## A two-operand builtin as its SurrealQL operator. The normal form puts
	## an integer literal first in a comparison (`3 < qty`); a comparison
	## whose left operand is the only literal is written the other way round,
	## with the mirrored operator.
	binary : Str, Str, Code.Tree, Code.Tree, Env -> Try(Binding, Ql.Error)
	binary = |owner, method, lhs, rhs, env| {
		mirrored = Translate.mirror(method)
		flip = Translate.is_literal(lhs) and !Translate.is_literal(rhs) and !mirrored.is_empty()
		symbol = Translate.operator(owner, if (flip) mirrored else method)?
		arithmetic = ["plus", "minus", "times", "div_by", "div_trunc_by", "rem_by"].contains(method)
		left = Translate.whole_operand(owner, arithmetic, if (flip) rhs else lhs, env)?
		right = Translate.whole_operand(owner, arithmetic, if (flip) lhs else rhs, env)?
		Ok(Binding.Infix("${left} ${symbol} ${right}"))
	}

	## Whether a Roc integer type is a sized type of SurrealDB (`u8`), not
	## `int`.
	is_sized : Str -> Bool
	is_sized = |owner| ["Num.I8", "Num.U8", "Num.I16", "Num.U16", "Num.I32", "Num.U32", "Num.U64"].contains(owner)

	## An operand of arithmetic on a sized integer type, as an `int`
	## (`<int>age`). SurrealDB computes a sized type with an `int` in another
	## type: `u64` and `int` give a `decimal`, so `7u64 / 2` is 3.5, and Roc's
	## `7 // 2` is 3. With both as `int` the result is the one of 0.0.3. A
	## literal is an `int` already.
	whole_operand : Str, Bool, Code.Tree, Env -> Try(Str, Ql.Error)
	whole_operand = |owner, arithmetic, tree, env| {
		spelled = Translate.arg(tree, env)?
		if arithmetic and Translate.is_sized(owner) and !Translate.is_literal(tree) {
			Ok("<int>${spelled}")
		} else {
			Ok(spelled)
		}
	}

	mirror : Str -> Str
	mirror = |method| match method {
		"is_lt" => "is_gt"
		"is_gt" => "is_lt"
		"is_lte" => "is_gte"
		"is_gte" => "is_lte"
		"is_eq" => "is_eq"
		_ => ""
	}

	## Whether a tree is a constant: a literal, or a record, list or nominal
	## of them, such as an `Id` or a `Datetime` written in.
	is_literal : Code.Tree -> Bool
	is_literal = |tree| match tree {
		Op({ op: Lit(_), .. }) => Bool.True
		Op({ op: Wrap(_), args, .. }) => args.all(Translate.is_literal)
		Op({ op: Record(_), args, .. }) => args.all(Translate.is_literal)
		Op({ op: List, args, .. }) => args.all(Translate.is_literal)
		_ => Bool.False
	}

	## The SurrealQL operator of a builtin's method. SurrealDB's `/` between
	## ints truncates toward zero and its `%` follows the dividend, as Roc's
	## `//` and `%` on integers do.
	operator : Str, Str -> Try(Str, Ql.Error)
	operator = |owner, method| {
		whole = owner.starts_with("Num.I") or owner.starts_with("Num.U")
		match method {
			"plus" => Ok("+")
			"minus" => Ok("-")
			"times" => Ok("*")
			"div_by" => Ok("/")
			"div_trunc_by" =>
				if whole {
					Ok("/")
				} else {
					Err(Unsupported("`//` on `${owner}` truncates a fraction, and SurrealDB's `/` does not; divide with `/`"))
				}
			"rem_by" =>
				if whole {
					Ok("%")
				} else {
					Err(Unsupported("`%` on `${owner}` has no SurrealQL form; SurrealDB's `%` is for integers here"))
				}
			"is_lt" => Ok("<")
			"is_gt" => Ok(">")
			"is_lte" => Ok("<=")
			"is_gte" => Ok(">=")
			"is_eq" => Ok("=")
			_ => Err(Unsupported("`${owner}.${method}` has no SurrealQL form"))
		}
	}
}
