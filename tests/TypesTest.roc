app [] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.5.0/B5U2mPsWTtuxfCRMzqQxio2ecDv7CAzCoyEMENMh4FNF.tar.zst",
	internal: "../src/internal.roc",
}

import internal.Ql
import internal.Surreal
import internal.Types

# Tests of `Types` and of the table constructors on a small domain. They sit
# here because a row type comes from a reified table, and only `Surreal`
# makes one. Nothing outside this file imports it.
TypesTest :: {}

Address : { city : Str, zip ?: Str }

Customer := { id : Str, name : Str, email : Str, address : Address, tags : List(Str), referrer ?: Surreal.Link(Customer), age : U8, born : Surreal.Datetime }

Product : { id : Str, title : Str, price : Dec, stock : I32, ratio : F64, live : Bool }

Item : { product : Surreal.Link(Product), qty : I64 }

Payment : [Cash, Card({ last4 : Str }), Invoice({ contact : Surreal.Link(Customer), due : Str }), Check(I64), Wire(Str, I64), Gift(Surreal.Link(Product))]

Order : { id : Str, customer : Surreal.Link(Customer), items : List(Item), payment : Payment, gift ?: { to : Surreal.Link(Customer), note : Str }, wishlist : List(Surreal.Link(Product)), by : Surreal.Id(Customer), placed : Surreal.Datetime }

Purchase : { id : Str, from : Surreal.Link(Customer), to : Surreal.Link(Product), since : I64 }

customers : Surreal.Table(Customer)
customers = Surreal.table("customer")

products : Surreal.Table(Product)
products = Surreal.table("product")

orders : Surreal.Table(Order)
orders = Surreal.table("order")

purchased : Surreal.Table(Purchase)
purchased = Surreal.relation("purchased", customers, products)

# The schema list, as `Surreal.schema` will build it from the tables.
# Every row of the type table, one field each.
Status := [Active, Closed]

Kitchen : {
	id : Str,
	i8 : I8,
	u8 : U8,
	i16 : I16,
	u16 : U16,
	i32 : I32,
	u32 : U32,
	i64 : I64,
	f32 : F32,
	f64 : F64,
	dec : Dec,
	flag : Bool,
	text : Str,
	at : Surreal.Datetime,
	who : Surreal.Id(Product),
	near : { x : Str, y ?: I64 },
	note ?: Str,
	names : List(Str),
	rows : List({ s : Str, n : U8 }),
	many : List(Surreal.Link(Product)),
	plain : [Red, Green],
	status : Status,
	bytes : List(U8),
	deep : List(List(I8)),
	pick : [Pad, Pair(Str, I64), Box({ w : I64 })],
	maybe ?: Surreal.Link(Product),
	re : Surreal.Regex,
	big : Surreal.BigDecimal,
	day : Surreal.Date,
	clock : Surreal.TimeOfDay,
	stamp : Surreal.Timestamp,
	span : List(Surreal.Interval),
}

kitchen : Surreal.Table(Kitchen)
kitchen = Surreal.table("kitchen")

# A list of records with a default in a member keeps the `array<object>` form.
Part := { w : I64 ?? 5, label : Str }

Crate : { id : Str, parts : List(Part) }

crates : Surreal.Table(Crate)
crates = Surreal.table("crate")

registry : Types.Registry
registry = [Surreal.Def.source(customers.define()), Surreal.Def.source(products.define()), Surreal.Def.source(orders.define()), Surreal.Def.source(purchased.define()), Surreal.Def.source(kitchen.define()), Surreal.Def.source(crates.define())]

defs_of : Str -> List(Str)
defs_of = |name| match registry.find_first(|s| s.name == name) {
	Ok(s) => match Types.field_defs(name, s.row_ty, registry) {
		Ok(defs) => defs.map(|d| "${d.path} ${d.ty} [${Str.join_with(d.asserts, " ; ")}]")
		Err(BadSchema(why)) => [why]
		Err(Unsupported(why)) => [why]
		Err(other) => [Str.inspect(other)]
	}
	Err(_) => ["not listed"]
}

check_of : Types.Source, Types.Registry -> Str
check_of = |source, reg| match Types.check_table(source, reg) {
	Ok(_) => "ok"
	Err(BadSchema(why)) => why
	Err(Unsupported(why)) => why
	Err(other) => Str.inspect(other)
}

# ------------------------------------------------------------ type mapping

expect defs_of("customer") == [
	"address object []",
	"address.city string []",
	"address.zip option<string> []",
	"age int [$value >= 0 AND $value <= 255]",
	"born datetime []",
	"email string []",
	"name string []",
	"referrer option<record<customer>> [($value = NONE OR (record::exists($value)))]",
	"tags array<string> []",
]

expect defs_of("product") == [
	"live bool []",
	"price decimal []",
	"ratio float []",
	"stock int [$value >= -2147483648 AND $value <= 2147483647]",
	"title string []",
]

expect defs_of("order") == [
	"by record<customer> [record::exists($value)]",
	"customer record<customer> [record::exists($value)]",
	"gift option<object> []",
	"gift.note string []",
	"gift.to record<customer> [record::exists($value)]",
	"items array<{ product: record<product>, qty: int }> []",
	"items[*].product  [record::exists($value)]",
	"items[*].qty  []",
	"payment { kind: \"Card\", last4: string } | \"Cash\" | { kind: \"Check\", value: int } | { kind: \"Gift\", value: record<product> } | { kind: \"Invoice\", contact: record<customer>, due: string } | { kind: \"Wire\", value: [string, int] } [(IF $value.kind = 'Gift' THEN record::exists($value.value) ELSE true END) ; (IF $value.kind = 'Invoice' THEN record::exists($value.contact) ELSE true END)]",
	"placed datetime []",
	"wishlist array<record<product>> [$value.all(|$e1| record::exists($e1))]",
]

expect defs_of("purchased") == [
	"since int []",
]

expect defs_of("crate") == [
	"parts array<object> [$value.all(|$e| object::keys($e).all(|$k| $k IN ['label', 'w']))]",
	"parts[*].label string []",
	"parts[*].w int []",
]

expect defs_of("kitchen") == [
	"at datetime []",
	"big bigdecimal []",
	"bytes array<int> [$value.all(|$e1| $e1 >= 0 AND $e1 <= 255)]",
	"clock time []",
	"day date []",
	"dec decimal []",
	"deep array<array<int>> [$value.all(|$e1| $e1.all(|$e2| $e2 >= -128 AND $e2 <= 127))]",
	"f32 float []",
	"f64 float []",
	"flag bool []",
	"i16 int [$value >= -32768 AND $value <= 32767]",
	"i32 int [$value >= -2147483648 AND $value <= 2147483647]",
	"i64 int []",
	"i8 int [$value >= -128 AND $value <= 127]",
	"many array<record<product>> [$value.all(|$e1| record::exists($e1))]",
	"maybe option<record<product>> [($value = NONE OR (record::exists($value)))]",
	"names array<string> []",
	"near object []",
	"near.x string []",
	"near.y option<int> []",
	"note option<string> []",
	"pick { kind: \"Box\", w: int } | \"Pad\" | { kind: \"Pair\", value: [string, int] } []",
	"plain \"Green\" | \"Red\" []",
	"re regex []",
	"rows array<{ n: int, s: string }> []",
	"rows[*].n  [$value >= 0 AND $value <= 255]",
	"rows[*].s  []",
	"span array<interval> []",
	"stamp timestamp []",
	"status \"Active\" | \"Closed\" []",
	"text string []",
	"u16 int [$value >= 0 AND $value <= 65535]",
	"u32 int [$value >= 0 AND $value <= 4294967295]",
	"u8 int [$value >= 0 AND $value <= 255]",
	"who record<product> [record::exists($value)]",
]

# -------------------------------------------------- rows that are not schemas

NoId : { name : Str }

IdInt : { id : I64 }

IdOptional : { id ?: Str }

Big : { id : Str, n : U64 }

Wide : { id : Str, xs : List({ q : I128 }) }

Huge : { id : Str, h : U128 }

KindArm : { id : Str, p : [A({ kind : Str }), B] }

Tuple : { id : Str, t : (I64, Str) }

Tried : { id : Str, t : Try(I64, Str) }

Mapped : { id : Str, d : Dict(Str, I64) }

Spanned : { id : Str, span : Surreal.Duration }

Orphan : { id : Str, c : Surreal.Link(Product) }

Twin : { id : Str, x : I64 }

Empty : { id : Str, e : [] }

Ref : { id : Str, c : Surreal.Link(Twin) }

WrongFrom : { id : Str, from : Surreal.Link(Product), to : Surreal.Link(Product) }

NoTo : { id : Str, from : Surreal.Link(Customer) }

IdFrom : { id : Str, from : Surreal.Id(Customer), to : Surreal.Link(Product) }

# The type of `Surreal.relation` refuses an edge row whose ends do not link
# to the two tables, so these sources are built by hand: the source of a
# table of the row, with the kind of an edge table from `customer` to
# `product`.
bad_edge : Types.Source -> Types.Source
bad_edge = |source| { ..source, kind: Types.Kind.Relation({ from: "customer", to: "product" }) }

no_id : Surreal.Table(NoId)
no_id = Surreal.table("no_id")

id_int : Surreal.Table(IdInt)
id_int = Surreal.table("id_int")

id_optional : Surreal.Table(IdOptional)
id_optional = Surreal.table("id_optional")

big : Surreal.Table(Big)
big = Surreal.table("big")

wide : Surreal.Table(Wide)
wide = Surreal.table("wide")

huge : Surreal.Table(Huge)
huge = Surreal.table("huge")

kind_arm : Surreal.Table(KindArm)
kind_arm = Surreal.table("kind_arm")

tuple : Surreal.Table(Tuple)
tuple = Surreal.table("tuple")

tried : Surreal.Table(Tried)
tried = Surreal.table("tried")

mapped : Surreal.Table(Mapped)
mapped = Surreal.table("mapped")

spanned : Surreal.Table(Spanned)
spanned = Surreal.table("spanned")

orphan : Surreal.Table(Orphan)
orphan = Surreal.table("orphan")

twin_a : Surreal.Table(Twin)
twin_a = Surreal.table("twin_a")

twin_b : Surreal.Table(Twin)
twin_b = Surreal.table("twin_b")

ref : Surreal.Table(Ref)
ref = Surreal.table("ref")

empty : Surreal.Table(Empty)
empty = Surreal.table("empty")

wrong_from : Surreal.Table(WrongFrom)
wrong_from = Surreal.table("wrong_from")

no_to : Surreal.Table(NoTo)
no_to = Surreal.table("no_to")

id_from : Surreal.Table(IdFrom)
id_from = Surreal.table("id_from")

expect check_of(Surreal.Def.source(no_id.define()), registry) == "table `no_id` needs a required field `id : Str` or `id : Surreal.TimeKey(..)`; it is the record key"
expect check_of(Surreal.Def.source(id_int.define()), registry) == "table `id_int` needs a required field `id : Str` or `id : Surreal.TimeKey(..)`; it is the record key"
expect check_of(Surreal.Def.source(id_optional.define()), registry) == "table `id_optional` needs a required field `id : Str` or `id : Surreal.TimeKey(..)`; it is the record key"
expect check_of(Surreal.Def.source(big.define()), registry) == "ok"
expect check_of(Surreal.Def.source(wide.define()), registry) == "field `xs[*].q`: I128 does not fit SurrealDB's `int`, which is 64-bit signed"
expect check_of(Surreal.Def.source(huge.define()), registry) == "field `h`: U128 does not fit SurrealDB's `int`, which is 64-bit signed"
expect check_of(Surreal.Def.source(kind_arm.define()), registry) == "field `p`: the arm `A` has a field named `kind`, which tells the arms apart"
expect check_of(Surreal.Def.source(tuple.define()), registry) == "field `t`: a tuple has no SurrealDB type"
expect check_of(Surreal.Def.source(tried.define()), registry) == "field `t`: `Builtin.Try` has no SurrealDB type"
expect check_of(Surreal.Def.source(mapped.define()), registry) == "field `d`: `Dict` has no SurrealDB type"
expect check_of(Surreal.Def.source(spanned.define()), registry) == "field `span`: `Surreal.Duration` has no SurrealDB type"
expect check_of(Surreal.Def.source(orphan.define()), [Surreal.Def.source(customers.define())]) == "field `c`: no table holds the row type `{ id : Str, live : Bool, price : Dec, ratio : F64, stock : I32, title : Str }`; list its table in the schema"
expect check_of(Surreal.Def.source(ref.define()), [Surreal.Def.source(twin_a.define()), Surreal.Def.source(twin_b.define())]) == "field `c`: tables `twin_a` and `twin_b` have the same row type, so a link to it is ambiguous; make one of the rows a nominal type (`:=`)"
expect check_of(Surreal.Def.source(empty.define()), registry) == "field `e`: an empty union has no values"
expect check_of(bad_edge(Surreal.Def.source(wrong_from.define())), registry) == "edge table `wrong_from` needs a required field `from` that is a `Link` to a row of table `customer`"
expect check_of(bad_edge(Surreal.Def.source(no_to.define())), registry) == "edge table `no_to` needs a required field `to` that is a `Link` to a row of table `product`"
expect check_of(bad_edge(Surreal.Def.source(id_from.define())), registry) == "edge table `id_from` needs a required field `from` that is a `Link` to a row of table `customer`"
expect check_of(Surreal.Def.source(purchased.define()), registry) == "ok"
expect check_of(Surreal.Def.source(orders.define()), registry) == "ok"

sites_of : Str -> List(Str)
sites_of = |name| match registry.find_first(|s| s.name == name) {
	Ok(s) => Types.link_sites(s.row_ty).map(
		|l| {
			table = match Types.table_for(registry, l.target) {
				Ok(t) => t
				Err(BadSchema(why)) => why
				Err(Unsupported(why)) => why
				Err(other) => Str.inspect(other)
			}
			"${l.path} top=${l.top} -> ${table} ${if (l.is_id) "id" else "link"} required=${Str.inspect(l.required)} elements=${Str.inspect(l.elements)} ${Str.inspect(l.shape)}"
		},
	)
	Err(_) => ["not listed"]
}

# --------------------------------------------------------------- link sites

expect sites_of("order") == [
	"by top=by -> customer id required=True elements=False Root",
	"customer top=customer -> customer link required=True elements=False Root",
	"gift.to top=gift -> customer link required=False elements=False InObject",
	"items[*].product top=items -> product link required=False elements=False InList",
	"payment.value top=payment -> product link required=False elements=False InUnionArm({ tag: \"Gift\" })",
	"payment.contact top=payment -> customer link required=False elements=False InUnionArm({ tag: \"Invoice\" })",
	"wishlist top=wishlist -> product link required=False elements=True RootList",
]

# The self-link of `Customer` reads back as the table `customer`.
expect sites_of("customer") == ["referrer top=referrer -> customer link required=False elements=False RootOptional"]

expect sites_of("kitchen") == [
	"many top=many -> product link required=False elements=True RootList",
	"maybe top=maybe -> product link required=False elements=False RootOptional",
	"who top=who -> product id required=True elements=False Root",
]

# An edge table lists its two ends as sites too.
expect sites_of("purchased") == [
	"⟨from⟩ top=⟨from⟩ -> customer link required=True elements=False Root",
	"to top=to -> product link required=True elements=False Root",
]

# The linked rows that a whole row reads, which a live query of it
# watches: each `Linked`, with the `Linked` rows of its row after it. A
# `Link` and an `Id` are record ids. `lists` counts the lists.
whole_reads_of : Code.Ty -> List(Str)
whole_reads_of = |row_ty| Types.whole_reads(row_ty, "", 0, Ql.ident, []).map(|l| "${l.path} -> ${Types.key(l.target)} lists=${l.lists.to_str()}")

expect whole_reads_of(Surreal.Def.source(orders.define()).row_ty) == []

BoxRead : { id : Str, item : Surreal.Linked(Item), more : List(Surreal.Linked(Item)) }

box_reads : Surreal.Table(BoxRead)
box_reads = Surreal.table("box")

expect whole_reads_of(Surreal.Def.source(box_reads.define()).row_ty) == [
	"item -> {product:Link<{id:Str,live:Bool,price:Dec,ratio:F64,stock:I32,title:Str}>,qty:I64} lists=0",
	"more -> {product:Link<{id:Str,live:Bool,price:Dec,ratio:F64,stock:I32,title:Str}>,qty:I64} lists=1",
]
# Below a path, the paths go on from it.
expect Types.whole_reads(Surreal.Def.source(box_reads.define()).row_ty, "box", 1, Ql.ident, []).map(|l| (l.path, l.lists)) == [("box.item", 1), ("box.more", 2)]

# A `Linked` of a nominal row that links to its own table. Its target is
# its type argument, `Customer`, whose own link is a record id.
OrderView : { id : Str, customer : Surreal.Linked(Customer), by : Surreal.Id(Customer) }

order_views : Surreal.Table(OrderView)
order_views = Surreal.table("order")

order_view_sites : List({ path : Str, target : Code.Ty, lists : U64 })
order_view_sites = Types.whole_reads(Surreal.Def.source(order_views.define()).row_ty, "", 0, Ql.ident, [])

expect order_view_sites.map(|l| "${l.path} -> ${Types.key(l.target)}") == ["customer -> N:Customer"]
expect order_view_sites.map(|l| Types.lookup(registry, l.target)) == [Ok("customer")]

## An alias row and a nominal row with the fields of `Customer`. A `Linked`
## names its row, so each finds its own table.
CustomerCopy : { id : Str, name : Str, email : Str, address : Address, tags : List(Str), referrer ?: Surreal.Link(Customer), age : U8, born : Surreal.Datetime }

CustomerTwin := { id : Str, name : Str, email : Str, address : Address, tags : List(Str), referrer ?: Surreal.Link(Customer), age : U8, born : Surreal.Datetime }

customer_copies : Surreal.Table(CustomerCopy)
customer_copies = Surreal.table("customer_copy")

customer_twins : Surreal.Table(CustomerTwin)
customer_twins = Surreal.table("customer_twin")

LinkedCopies : { id : Str, original : Surreal.Linked(Customer), copy : Surreal.Linked(CustomerCopy), twin : Surreal.Linked(CustomerTwin) }

linked_copies : Surreal.Table(LinkedCopies)
linked_copies = Surreal.table("copies")

copies_registry : Types.Registry
copies_registry = registry.concat([Surreal.Def.source(customer_copies.define()), Surreal.Def.source(customer_twins.define())])

expect Types.check_registry(copies_registry) == Ok({})
expect Types.whole_reads(Surreal.Def.source(linked_copies.define()).row_ty, "", 0, Ql.ident, []).map(|l| (l.path, Types.lookup(copies_registry, l.target))) == [
	("copy", Ok("customer_copy")),
	("original", Ok("customer")),
	("twin", Ok("customer_twin")),
]
# A `Linked` of a row that no table holds names that row.
expect order_view_sites.map(|l| Types.lookup([Surreal.Def.source(products.define())], l.target)) == [Err("no table holds the row type `Customer`; list its table in the schema")]

# A read row that holds a `Linked` of itself. The `Linked` names the read
# row, so its table is the one that lists that read row (`define_read`),
# and the whole read stops there, as the translator refuses it. The read
# row agrees with the row of `customer` when the `Linked` of itself is
# assumed to agree.
CustomerLoop := { id : Str, name : Str, email : Str, address : Address, tags : List(Str), referrer ?: Surreal.Linked(CustomerLoop), age : U8, born : Surreal.Datetime }

customer_loops : Surreal.Table(CustomerLoop)
customer_loops = Surreal.table("customer")

loop_sites : List({ path : Str, target : Code.Ty, lists : U64 })
loop_sites = Types.whole_reads(Surreal.Def.source(customer_loops.define()).row_ty, "", 0, Ql.ident, [])

expect loop_sites.map(|l| "${l.path} -> ${Types.key(l.target)}") == ["referrer -> N:CustomerLoop"]
expect loop_sites.map(|l| Types.lookup(registry.append(Surreal.Def.source(customer_loops.define())), l.target)) == [Ok("customer")]
expect loop_sites.map(|l| Types.lookup(registry, l.target).is_err()) == [Bool.True]
expect Types.check_read("customer", Surreal.Def.source(customer_loops.define()).row_ty, registry) == Ok({})
# The key of a `Linked` is the key of its row.
expect Types.key(Named("Surreal.Linked", [Named("N", [], Str)], Record([{ name: "n", ty: Str, presence: Required }]))) == "Linked<N:N>"

# The ends of an edge are `in` and `out`, as the row of a statement spells them.
PurchaseRead : { id : Str, from : Surreal.Link(Customer), to : Surreal.Linked(Product), since : I64 }

purchase_reads : Surreal.Table(PurchaseRead)
purchase_reads = Surreal.table("purchased")

expect Types.whole_reads(Surreal.Def.source(purchase_reads.define()).row_ty, "", 0, |name| if (name == "from") "in" else if (name == "to") "out" else name, []).map(|l| l.path) == ["out"]

# ---------------------------------------------------------- the registry

expect Types.check_registry(registry) == Ok({})
expect Types.check_registry([Surreal.Def.source(twin_a.define()), Surreal.Def.source(twin_b.define())]) == Err(BadSchema("tables `twin_a` and `twin_b` have the same row type, so a link to it is ambiguous; make one of the rows a nominal type (`:=`)"))
expect Types.check_registry([Surreal.Def.source(twin_a.define()), Surreal.Def.source(twin_a.define())]) == Err(BadSchema("two tables are named `twin_a`"))

# A link finds its table whether it reaches the row as a nominal or as a record.
expect Types.table_for(registry, Surreal.Def.source(customers.define()).row_ty) == Ok("customer")
expect Types.table_for(registry, Surreal.Def.source(products.define()).row_ty) == Ok("product")
expect Types.table_for([Surreal.Def.source(products.define())], Surreal.Def.source(customers.define()).row_ty).is_err()

# The key is the same for the type however it was reached.
expect Types.key(Surreal.Def.source(customers.define()).row_ty) == "N:Customer"
expect Types.key(Surreal.Def.source(products.define()).row_ty) == "{id:Str,live:Bool,price:Dec,ratio:F64,stock:I32,title:Str}"

# ------------------------------------------------------------ time series

Reading : { id : Surreal.TimeKey(Surreal.Id(Product)), level : U8 }

Probe : { id : Surreal.TimeKey({ site : Str, sensor : I64 }), level : I64 }

LinkedReading : { id : Surreal.TimeKey(Surreal.Link(Product)), level : I64 }

Nested : { id : Surreal.TimeKey({ site : Str, by : Surreal.Link(Customer) }), level : I64 }

readings : Surreal.Table(Reading)
readings = Surreal.table("reading")

probes : Surreal.Table(Probe)
probes = Surreal.table("probe")

linked_readings : Surreal.Table(LinkedReading)
linked_readings = Surreal.table("linked_reading")

nested : Surreal.Table(Nested)
nested = Surreal.table("nested")

series_registry : Types.Registry
series_registry = registry.concat([Surreal.Def.source(readings.define()), Surreal.Def.source(probes.define()), Surreal.Def.source(linked_readings.define()), Surreal.Def.source(nested.define())])

series_defs : Str -> List(Str)
series_defs = |name| match series_registry.find_first(|s| s.name == name) {
	Ok(s) => match Types.field_defs(name, s.row_ty, series_registry) {
		Ok(defs) => defs.map(|d| "${d.path} ${d.ty} [${Str.join_with(d.asserts, " ; ")}]")
		Err(BadSchema(why)) => [why]
		Err(Unsupported(why)) => [why]
		Err(other) => [Str.inspect(other)]
	}
	Err(_) => ["not listed"]
}

# The key of a time series is `[series, time]`, and its `TYPE` comes first.
# An `Id` series is not checked for existence: a key has no delete policy.
expect series_defs("reading") == ["id [record<product>, datetime] []", "level int [$value >= 0 AND $value <= 255]"]
expect series_defs("probe") == ["id [{ sensor: int, site: string }, datetime] []", "level int []"]
expect series_defs("linked_reading") == ["table `linked_reading`: the series of `id` holds a `Link`; a key holds an `Id`, because a key has no delete policy"]
expect series_defs("nested") == ["table `nested`: the series of `id` holds a `Link`; a key holds an `Id`, because a key has no delete policy"]
# The `Id` in a key is not a link site, so no delete event reads it.
expect Types.link_sites(Surreal.Def.source(readings.define()).row_ty).is_empty()

# ------------------------------------------------------------ geometry

Shape : {
	id : Str,
	at : Surreal.Point,
	path : Surreal.Line,
	area : Surreal.Polygon,
	stops : Surreal.MultiPoint,
	routes : Surreal.MultiLine,
	zones : Surreal.MultiPolygon,
	parts : Surreal.Collection,
	any : Surreal.Geometry,
	near ?: Surreal.Point,
	marks : List(Surreal.Point),
}

shapes : Surreal.Table(Shape)
shapes = Surreal.table("shape")

shape_defs : List(Str)
shape_defs = match Types.field_defs("shape", Surreal.Def.source(shapes.define()).row_ty, [Surreal.Def.source(shapes.define())]) {
	Ok(defs) => defs.map(|d| "${d.path} ${d.ty} [${Str.join_with(d.asserts, " ; ")}]")
	Err(BadSchema(why)) | Err(Unsupported(why)) => [why]
}

# Each geometry type is its `geometry<kind>`, and asserts that its coordinates are in range.
expect shape_defs == [
	"any geometry [geo::is_valid($value)]",
	"area geometry<polygon> [geo::is_valid($value)]",
	"at geometry<point> [geo::is_valid($value)]",
	"marks array<geometry<point>> [$value.all(|$e1| geo::is_valid($e1))]",
	"near option<geometry<point>> [($value = NONE OR (geo::is_valid($value)))]",
	"parts geometry<collection> [geo::is_valid($value)]",
	"path geometry<line> [geo::is_valid($value)]",
	"routes geometry<multiline> [geo::is_valid($value)]",
	"stops geometry<multipoint> [geo::is_valid($value)]",
	"zones geometry<multipolygon> [geo::is_valid($value)]",
]

## A unit square with a square hole.
square : Surreal.Polygon
square = Surreal.Polygon.(
	{
		exterior: [Surreal.point(0, 0), Surreal.point(1, 0), Surreal.point(1, 1), Surreal.point(0, 1), Surreal.point(0, 0)],
		holes: [[Surreal.point(0.25, 0.25), Surreal.point(0.5, 0.25), Surreal.point(0.25, 0.5), Surreal.point(0.25, 0.25)]],
	},
)

# A value is its GeoJSON object, which SurrealDB reads as a geometry.
expect Surreal.Mirror.literal(Surreal.point(10.75, -59.5)) == Ok("{ type: 'Point', coordinates: [10.75f, -59.5f] }")
expect Surreal.Mirror.literal(square) == Ok("{ type: 'Polygon', coordinates: [[[0f, 0f], [1f, 0f], [1f, 1f], [0f, 1f], [0f, 0f]], [[0.25f, 0.25f], [0.5f, 0.25f], [0.25f, 0.5f], [0.25f, 0.25f]]] }")
expect Surreal.Mirror.literal(Surreal.Line.([Surreal.point(0, 0), Surreal.point(1, 2)])) == Ok("{ type: 'LineString', coordinates: [[0f, 0f], [1f, 2f]] }")
expect Surreal.Mirror.literal(Surreal.MultiPoint.([Surreal.point(0, 0)])) == Ok("{ type: 'MultiPoint', coordinates: [[0f, 0f]] }")
expect Surreal.Mirror.literal(Surreal.MultiLine.([Surreal.Line.([Surreal.point(0, 0), Surreal.point(1, 2)])])) == Ok("{ type: 'MultiLineString', coordinates: [[[0f, 0f], [1f, 2f]]] }")
expect Surreal.Mirror.literal(Surreal.MultiPolygon.([square])) == Ok("{ type: 'MultiPolygon', coordinates: [[[[0f, 0f], [1f, 0f], [1f, 1f], [0f, 1f], [0f, 0f]], [[0.25f, 0.25f], [0.5f, 0.25f], [0.25f, 0.5f], [0.25f, 0.25f]]]] }")
expect Surreal.Mirror.literal(Surreal.Collection.([Surreal.point(1, 2).to_geometry(), Surreal.Collection.([]).to_geometry()])) == Ok("{ type: 'GeometryCollection', geometries: [{ type: 'Point', coordinates: [1f, 2f] }, { type: 'GeometryCollection', geometries: [] }] }")
# A polygon with no point is the ring `[]`, which SurrealDB reads as a polygon (verified).
expect Surreal.Mirror.literal(Surreal.Polygon.({ exterior: [], holes: [] })) == Ok("{ type: 'Polygon', coordinates: [[]] }")

# The Mirror of `geo::is_valid`, at the edges of the ranges (each verified on SurrealDB 3.3.4).
valid_at : F64, F64 -> Bool
valid_at = |lon, lat| Surreal.Geo.is_valid(Surreal.point(lon, lat).to_geometry())

expect valid_at(180, 90)
expect valid_at(-180, -90)
expect !valid_at(180.0000001, 0)
expect !valid_at(-180.0000001, 0)
expect !valid_at(0, 90.0000001)
expect !valid_at(0, -90.0000001)
expect !valid_at(F64.nan, 0)
expect !valid_at(F64.infinity, 0)
expect Surreal.Geo.is_valid(square.to_geometry())
expect !Surreal.Geo.is_valid(Surreal.Collection.([Surreal.point(0, 0).to_geometry(), Surreal.point(0, 91).to_geometry()]).to_geometry())
expect !Surreal.Geo.is_valid(Surreal.MultiPolygon.([square, Surreal.Polygon.({ exterior: [Surreal.point(0, 0)], holes: [[Surreal.point(200, 0)]] })]).to_geometry())
expect Surreal.Geo.is_valid(Surreal.Collection.([]).to_geometry())
expect Surreal.Geo.is_valid(Surreal.Line.([]).to_geometry())

# A table that is not listed has no definitions.
expect defs_of("missing") == ["not listed"]
