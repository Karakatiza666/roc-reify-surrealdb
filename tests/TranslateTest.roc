app [] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.4.0/EnfRKFT7uPHmd3zT5PcwAiBWUtGmBXapJqFK5166U33J.tar.zst",
	internal: "../src/internal.roc",
}

import internal.Ql
import internal.Surreal
import internal.Translate

# Tests of `Translate` on a small domain: each clause is reified through a
# helper below, which declares `Surreal`'s cut, and translated. Nothing
# outside this file imports it. The cut stays a literal list here: the
# compiler reads a list, or a constant of this module that is one, and not
# `Surreal.code_primitives` from another module.
TranslateTest :: {}.{
	code_primitives = [Code.prim(Surreal.Link.get), Code.prim(Surreal.Link.id), Code.prim(Surreal.Id.is_eq), Code.prim(Surreal.Id.key), Code.prim(Surreal.Id.table), Code.prim(Surreal.Datetime.is_lt), Code.prim(Surreal.Datetime.is_lte), Code.prim(Surreal.Text.is_ascii), Code.prim(Surreal.Text.is_hexadecimal), Code.prim(Surreal.Hash.sha256), Code.prim(Surreal.Hash.blake3), Code.prim(Surreal.Array.distinct), Code.prim(Surreal.Array.union), Code.prim(Surreal.Array.intersect), Code.prim(Surreal.Array.complement), Code.prim(Surreal.Time.floor), Code.prim(Surreal.Time.ceil), Code.prim(Surreal.Time.round), Code.prim(Surreal.Time.year), Code.prim(Surreal.Time.month), Code.prim(Surreal.Time.day), Code.prim(Surreal.Time.hour), Code.prim(Surreal.Time.minute), Code.prim(Surreal.Time.second), Code.prim(Surreal.Math.mean), Code.prim(Surreal.DbFn.call1), Code.prim(Surreal.DbFn.call2), Code.prim(Surreal.DbFn.call3), Code.prim(Surreal.TimeKey.series), Code.prim(Surreal.TimeKey.time), Code.prim(Surreal.Geo.is_valid), Code.prim(Surreal.Vector.similarity_cosine), Code.prim(Surreal.Vector.distance_euclidean), Code.prim(Surreal.Vector.distance_manhattan), Code.prim(Surreal.Vector.distance_chebyshev), Code.prim(Surreal.Vector.dot), Code.prim(Surreal.Vector.magnitude)]

	## The graph of a clause over rows of the list's element type.
	describe1 : List(row), Code(row -> out) -> Code.Graph
	describe1 = |_, code| code.graph()

	## The graph of an update patch, which returns the row.
	describe_patch : List(row), Code(row -> row) -> Code.Graph
	describe_patch = |_, code| code.graph()

	describe2 : List(p), List(row), Code((p, row -> out)) -> Code.Graph
	describe2 = |_, _, code| code.graph()

	describe_group : List(k), List(row), Code((k, List(row) -> out)) -> Code.Graph
	describe_group = |_, _, code| code.graph()

	describe_pair : List(row), List(e), Code((row, List(e)) -> out) -> Code.Graph
	describe_pair = |_, _, code| code.graph()

	## A clause that reads values captured from around it, with each captured
	## value as its variable.
	describe_bound : List(row), Code(row -> Bool) -> Code.Bound(Try(Str, Ql.Error))
	describe_bound = |_, code| Code.bound(code, Translate.render([Surreal.library], code.graph(), [Translate.document("", Bool.False)], Translate.variable))
}

Address : { city : Str, zip ?: Str }

Customer : { id : Str, name : Str, address : Address, tags : List(Str), born : Surreal.Datetime }

Product : { id : Str, title : Str, price : Dec }

Item : { product : Surreal.Link(Product), qty : I64 }

Payment : [Card({ last4 : Str }), Cash, Invoice({ contact : Surreal.Link(Customer), due : Str }), Points(I64), Split(I64, I64)]

Order : { id : Str, customer : Surreal.Link(Customer), items : List(Item), payment : Payment, total : Dec }

Purchased : { id : Str, from : Surreal.Link(Customer), to : Surreal.Link(Product), quantity : I64 }

customers : List(Customer)
customers = []

orders : List(Order)
orders = []

purchases : List(Purchased)
purchases = []

Sample : { id : Str, text : Str, other : Str, n : I64, m : I64, d : Dec, f : F64, nums : List(I64), grid : List(List(I64)), words : List(Str), opt ?: Str, email : Str, at : Surreal.Datetime, scores : List(F64), times : List(Surreal.Datetime), ranks : List(Rank), decs : List(Dec) }

# A number with an order of its own: the reverse of the number's.
Rank := I64.{
	parser_for : _
	encoder_for : _
	order_relative_to : Rank, Rank -> [Before, Same, After]
	order_relative_to = |Rank.(a), Rank.(b)| b.order_relative_to(a)
}

samples : List(Sample)
samples = []

ada_id : Surreal.Id(Customer)
ada_id = Surreal.Id.({ table: "customer", key: "ada" })

pen_id : Surreal.Id(Product)
pen_id = Surreal.Id.({ table: "product", key: "pen" })

new_year : Surreal.Datetime
new_year = Surreal.Datetime.({ iso: "2020-01-01T00:00:00Z" })

half_second : Surreal.Datetime
half_second = Surreal.Datetime.({ iso: "2026-03-04T05:06:07.5Z" })

row : Translate.Binding
row = Translate.document("", Bool.False)

where_ : Code.Graph -> Try(Str, Ql.Error)
where_ = |graph| Translate.render([Surreal.library], graph, [row], Translate.variable)

selected : Code.Graph -> Try(List({ name : Str, surql : Str }), Ql.Error)
selected = |graph| Translate.columns([Surreal.library], graph, [row], Translate.variable)

line_total : Item -> I64
line_total = |i| i.qty * 2

same : Surreal.Datetime, Surreal.Datetime -> Bool
same = |a, b| a == b

iso_of : Surreal.Datetime -> Str
iso_of = |Surreal.Datetime.(d)| d.iso

hour_of : Sample -> Surreal.Datetime
hour_of = |s| Surreal.Time.floor(s.at, Surreal.Time.hours(1))

depth : I64 -> I64
depth = |n| if (n <= 0) 0 else depth(n - 1) + 1

# Queries, row by row.
expect where_(TranslateTest.describe1(orders, |o| o.customer.get().address.city == "Paris")) == Ok("customer.address.city = 'Paris'")
expect where_(TranslateTest.describe1(orders, |o| o.items.any(|i| i.qty > 3))) == Ok("items.any(|$v1| $v1.qty > 3)")
expect where_(
	TranslateTest.describe1(
		orders,
		|o| match o.payment {
			Card(c) => c.last4 == "4242"
			_ => Bool.False
		},
	),
) == Ok("(IF payment.kind = 'Card' THEN payment.last4 = '4242' ELSE false END)")
expect Translate.render([Surreal.library], TranslateTest.describe2([{ min_total: 0 }], orders, |p, o| o.total >= p.min_total), [Translate.Binding.Params, row], Translate.variable) == Ok("total >= $min_total")
expect where_(TranslateTest.describe1(orders, |o| o.customer.id() == ada_id)) == Ok("customer = customer:⟨ada⟩")
expect where_(TranslateTest.describe1(orders, |o| o.customer.id == ada_id)) == Ok("customer = customer:⟨ada⟩")
# `link.id` (the field) and `link.id()` (the method) are the same, and `fetched` has no SurrealQL form.
expect where_(TranslateTest.describe1(orders, |o| o.customer.id.key() == "ada")) == Ok("record::id(customer) = 'ada'")
expect where_(TranslateTest.describe1(orders, |o| Surreal.Id.table(o.customer.id) == "customer")) == Ok("record::tb(customer) = 'customer'")
expect where_(TranslateTest.describe1(orders, |o| o.items.any(|i| i.product.id == pen_id))) == Ok("items.any(|$v1| $v1.product = product:⟨pen⟩)")
expect selected(TranslateTest.describe1(orders, |o| { who: o.customer.id })) == Ok([{ name: "who", surql: "customer" }])
expect selected(TranslateTest.describe1(orders, |o| { who: o.customer.id() })) == Ok([{ name: "who", surql: "customer" }])
expect where_(TranslateTest.describe1(orders, |o| o.customer.fetched == NotFetched)) == Err(Unsupported("`fetched` is the row that the program holds, and the database has no such field; read a field of the row with `link.get().field`, or use `link.id`"))
expect where_(TranslateTest.describe1(orders, |o| o.customer.get().id == "ada")) == Ok("record::id(customer) = 'ada'")
expect selected(TranslateTest.describe1(orders, |o| { who: o.customer.get().name, n: o.items.len() })) == Ok([{ name: "n", surql: "items.len()" }, { name: "who", surql: "customer.name" }])
expect selected(TranslateTest.describe1(orders, |o| { customer: o.customer.get(), total: o.total })) == Ok([{ name: "customer", surql: "customer.{ address, born, id: record::id(id), name, tags }" }, { name: "total", surql: "total" }])
expect selected(TranslateTest.describe1(customers, |c| { note: c.address.?zip ?? "-" })) == Ok([{ name: "note", surql: "address.zip ?? '-'" }])
expect {
	graph = TranslateTest.describe_pair(customers, purchases, |(c, bought)| { name: c.name, titles: bought.keep_if(|e| e.quantity > 2).map(|e| e.to.get().title) })
	Translate.columns([Surreal.library], graph, [Translate.Binding.WithEdges(row, [Translate.outgoing("", "purchased")])], Translate.variable)
		== Ok([{ name: "name", surql: "name" }, { name: "titles", surql: "->purchased.filter(|$v1| $v1.quantity > 2).map(|$v2| $v2.out.title)" }])
}
expect {
	key = Translate.evaluate([Surreal.library], TranslateTest.describe1(orders, |o| o.customer.get().address.city), [row], Translate.variable)
	graph = TranslateTest.describe_group([""], orders, |city, rows| { city, orders: rows.len(), revenue: rows.map(|o| o.total).sum() })
	match key {
		Ok(k) => Translate.columns([Surreal.library], graph, [k, Translate.Binding.Group(row)], Translate.variable) == Ok([{ name: "city", surql: "customer.address.city" }, { name: "orders", surql: "count()" }, { name: "revenue", surql: "math::sum(total)" }])
		Err(_) => Bool.False
	}
}

# A filter on the row before a write, as a live query reads it: every path
# starts at `$before`, also through a link, a union, a key and the edges.
before : Translate.Binding
before = Translate.document("$before", Bool.False)

expect Translate.render([Surreal.library], TranslateTest.describe1(orders, |o| o.customer.get().address.city == "Paris"), [before], Translate.variable) == Ok("$before.customer.address.city = 'Paris'")
expect Translate.render([Surreal.library], TranslateTest.describe1(orders, |o| o.items.any(|i| i.qty > 3)), [before], Translate.variable) == Ok("$before.items.any(|$v1| $v1.qty > 3)")
expect Translate.render([Surreal.library], 
	TranslateTest.describe1(
		orders,
		|o| match o.payment {
			Card(c) => c.last4 == "4242"
			_ => Bool.False
		},
	),
	[before],
	Translate.variable,
) == Ok("(IF $before.payment.kind = 'Card' THEN $before.payment.last4 = '4242' ELSE false END)")
expect Translate.render([Surreal.library], TranslateTest.describe1(orders, |o| o.id == "a1"), [before], Translate.variable) == Ok("record::id($before.id) = 'a1'")
expect {
	graph = TranslateTest.describe_pair(customers, purchases, |(_, bought)| bought.len() == 0)
	Translate.render([Surreal.library], graph, [Translate.Binding.WithEdges(before, [Translate.outgoing("$before", "purchased")])], Translate.variable) == Ok("$before->purchased.len() = 0")
}

# The writes that read a clause.
expect Translate.assignments([Surreal.library], TranslateTest.describe1(orders, |o| { ..o, total: o.total * 0.9, payment: Cash }), [row], Translate.variable) == Ok([{ name: "payment", surql: "'Cash'" }, { name: "total", surql: "total * 0.9dec" }])
expect where_(TranslateTest.describe1(orders, |o| o.items.is_empty())) == Ok("items.len() = 0")
expect Translate.assignments([Surreal.library], TranslateTest.describe1(orders, |o| { ..o, payment: Card({ last4: "1" }) }), [row], Translate.variable) == Ok([{ name: "payment", surql: "{ kind: 'Card', last4: '1' }" }])
expect Translate.assignments([Surreal.library], TranslateTest.describe1(orders, |o| { ..o, payment: Split(1, 2) }), [row], Translate.variable) == Ok([{ name: "payment", surql: "{ kind: 'Split', value: [1, 2] }" }])
expect Translate.assignments([Surreal.library], TranslateTest.describe1(orders, |o| o), [row], Translate.variable) == Err(Unsupported("this update changes no field"))

# A union payload is spread next to `kind` only when its type is a record,
# also a nominal of the app over one. A geometry, a link and a datetime are
# `value`, as `Encode.tagged` writes them.
Shelf := { aisle : Str, bin : I64 }

Spot : { id : Str, owner : Surreal.Link(Customer), at : Surreal.Datetime, aisle : Str, slot : I64, shelf : Shelf, place : [Away, At(Surreal.Point), Kept(Surreal.Link(Customer)), Since(Surreal.Datetime), Shelved(Shelf), Pair(I64, I64)] }

spots : List(Spot)
spots = []

expect Translate.assignments([Surreal.library], TranslateTest.describe1(spots, |s| { ..s, place: At(Surreal.point(1, 2)) }), [row], Translate.variable) == Ok([{ name: "place", surql: "{ kind: 'At', value: <point> [1f, 2f] }" }])
expect Translate.assignments([Surreal.library], TranslateTest.describe1(spots, |s| { ..s, place: Since(Surreal.Time.now()) }), [row], Translate.variable) == Ok([{ name: "place", surql: "{ kind: 'Since', value: time::now() }" }])
expect Translate.assignments([Surreal.library], TranslateTest.describe1(spots, |s| { ..s, place: Shelved(Shelf.({ aisle: "b", bin: 4 })) }), [row], Translate.variable) == Ok([{ name: "place", surql: "{ kind: 'Shelved', aisle: 'b', bin: 4 }" }])
expect selected(TranslateTest.describe1(spots, |s| { place: Kept(s.owner) })) == Ok([{ name: "place", surql: "{ kind: 'Kept', value: owner }" }])
expect selected(TranslateTest.describe1(spots, |s| { place: Since(s.at) })) == Ok([{ name: "place", surql: "{ kind: 'Since', value: at }" }])

# An update whose new value reads a field that `..s` keeps. The patch reads
# that field twice, so it is a kept definition of the patch.
expect Translate.assignments([Surreal.library], TranslateTest.describe1(spots, |s| { ..s, place: Since(s.at) }), [row], Translate.variable) == Ok([{ name: "place", surql: "{ kind: 'Since', value: at }" }])
expect Translate.assignments([Surreal.library], TranslateTest.describe1(spots, |s| { ..s, place: Kept(s.owner) }), [row], Translate.variable) == Ok([{ name: "place", surql: "{ kind: 'Kept', value: owner }" }])
expect Translate.assignments([Surreal.library], TranslateTest.describe1(spots, |s| { ..s, place: Shelved(Shelf.({ aisle: s.aisle, bin: s.slot })) }), [row], Translate.variable) == Ok([{ name: "place", surql: "{ kind: 'Shelved', aisle: aisle, bin: slot }" }])
expect Translate.assignments([Surreal.library], TranslateTest.describe1(spots, |s| { ..s, place: Pair(s.slot, s.slot + 1) }), [row], Translate.variable) == Ok([{ name: "place", surql: "{ kind: 'Pair', value: [slot, slot + 1] }" }])
expect Translate.assignments([Surreal.library], TranslateTest.describe1(customers, |c| { ..c, tags: [c.name], address: { city: c.name, zip: c.name } }), [row], Translate.variable) == Ok([{ name: "address.city", surql: "name" }, { name: "address.zip", surql: "name" }, { name: "tags", surql: "[name]" }])
expect Translate.assignments([Surreal.library], TranslateTest.describe1(spots, |s| { ..s, slot: s.slot + s.slot }), [row], Translate.variable) == Ok([{ name: "slot", surql: "slot + slot" }])

# A row with optional fields. `..m` over an optional field is a presence
# switch on it with the row in each arm, so the patch that keeps the field
# changes the same fields in both arms. One the patch sets is set in both, an
# optional field the patch's row leaves out is NONE, and a field that each
# arm sets to another value is an `IF` on the presence.
Patron : { id : Str, name : Str, phone ?: Str, address : Address, visits : I64 }

patrons : List(Patron)
patrons = []

# A record that leaves out an optional field needs its type, so these
# patches are annotated.
without_phone : Patron -> Patron
without_phone = |m| { id: m.id, name: m.name, address: m.address, visits: m.visits }

without_zip : Patron -> Patron
without_zip = |m| { ..m, address: { city: m.address.city } }

phone_or_none : Patron -> Patron
phone_or_none = |m| match m.?phone {
	Ok(_) => m
	Err(_) => { ..m, phone: "none" }
}

expect Translate.assignments([Surreal.library], TranslateTest.describe_patch(patrons, |m| { ..m, name: "Jonny" }), [row], Translate.variable) == Ok([{ name: "name", surql: "'Jonny'" }])
expect Translate.assignments([Surreal.library], TranslateTest.describe_patch(patrons, |m| { ..m, phone: "555", visits: m.visits + 1 }), [row], Translate.variable) == Ok([{ name: "phone", surql: "'555'" }, { name: "visits", surql: "visits + 1" }])
expect Translate.assignments([Surreal.library], TranslateTest.describe_patch(patrons, |m| { ..m, name: m.?phone ?? m.name }), [row], Translate.variable) == Ok([{ name: "name", surql: "phone ?? name" }])
expect Translate.assignments([Surreal.library], TranslateTest.describe_patch(patrons, |m| { ..m, address: { ..m.address, city: "Rome" } }), [row], Translate.variable) == Ok([{ name: "address.city", surql: "'Rome'" }])
expect Translate.assignments([Surreal.library], TranslateTest.describe_patch(patrons, without_phone), [row], Translate.variable) == Ok([{ name: "phone", surql: "NONE" }])
expect Translate.assignments([Surreal.library], TranslateTest.describe_patch(patrons, without_zip), [row], Translate.variable) == Ok([{ name: "address.zip", surql: "NONE" }])
expect Translate.assignments([Surreal.library], TranslateTest.describe_patch(patrons, phone_or_none), [row], Translate.variable) == Ok([{ name: "phone", surql: "(IF phone IS NONE THEN 'none' ELSE phone END)" }])
expect Translate.assignments([Surreal.library], TranslateTest.describe_patch(patrons, |m| m), [row], Translate.variable) == Err(Unsupported("this update changes no field"))
expect Translate.assignments([Surreal.library], TranslateTest.describe_patch(patrons, |m| { ..m, id: "x" }), [row], Translate.variable) == Err(Unsupported("an update cannot change `id`, the record key"))
expect Translate.assignments([Surreal.library], TranslateTest.describe_patch(patrons, |m| if (m.visits > 3) { ..m, name: "a" } else m), [row], Translate.variable) == Err(Unsupported("an update patch builds one row; a branch around the row has no `SET` form, so branch inside each field that changes: `|o| { ..o, f: if .. }`"))

# A patch of only the fields it sets. Roc has no type for a record of some
# of the row's fields, so each field is checked against the row here: its
# name, and its type. An optional field takes its value or a `Try` of it.
expect Translate.patch_assignments([Surreal.library], TranslateTest.describe1(patrons, |m| { name: "Jonny", visits: m.visits + 1 }), [row], Translate.variable) == Ok([{ name: "name", surql: "'Jonny'" }, { name: "visits", surql: "visits + 1" }])
expect Translate.patch_assignments([Surreal.library], TranslateTest.describe1(patrons, |_| { phone: "555" }), [row], Translate.variable) == Ok([{ name: "phone", surql: "'555'" }])
expect Translate.patch_assignments([Surreal.library], TranslateTest.describe1(patrons, clear_phone), [row], Translate.variable) == Ok([{ name: "phone", surql: "NONE" }])
expect Translate.patch_assignments([Surreal.library], TranslateTest.describe1(patrons, |m| { address: { ..m.address, city: "Rome" } }), [row], Translate.variable) == Ok([{ name: "address.city", surql: "'Rome'" }])
expect Translate.patch_assignments([Surreal.library], TranslateTest.describe1(patrons, |_| { nmae: "typo" }), [row], Translate.variable) == Err(BadSchema("the row has no field `nmae`, so a patch cannot set it; it has `address`, `id`, `name`, `phone`, `visits`"))
expect Translate.patch_assignments([Surreal.library], TranslateTest.describe1(patrons, |_| { visits: 5 }), [row], Translate.variable) == Err(BadSchema("the patch's `visits` is `Dec`, and the row's `visits` is `I64`; a number literal without a suffix is a `Dec`, so write `1.I64`"))
expect Translate.patch_assignments([Surreal.library], TranslateTest.describe1(patrons, |_| { name: 5.I64 }), [row], Translate.variable) == Err(BadSchema("the patch's `name` is `I64`, and the row's `name` is `Str`"))
expect Translate.patch_assignments([Surreal.library], TranslateTest.describe1(patrons, |_| { id: "x" }), [row], Translate.variable) == Err(Unsupported("an update cannot change `id`, the record key"))
expect Translate.patch_assignments([Surreal.library], TranslateTest.describe1(patrons, |m| { name: m.name }), [row], Translate.variable) == Err(Unsupported("this patch changes no field"))
expect Translate.patch_assignments([Surreal.library], TranslateTest.describe1(patrons, |m| m.name), [row], Translate.variable) == Err(Unsupported("a patch is a record of the fields it sets, as `|o| { field: .. }`; this one is `Str`"))

clear_phone : Patron -> { phone : Try(Str, [Missing]) }
clear_phone = |_| { phone: Err(Missing) }

# The `Unwrap` of a nominal row is a kept definition of the patch.
Bay := { id : Str, aisle : Str, slot : I64 }

bays : List(Bay)
bays = []

expect Translate.assignments([Surreal.library], TranslateTest.describe1(bays, |b| { ..b, slot: 1 }), [row], Translate.variable) == Ok([{ name: "slot", surql: "1" }])
expect Translate.assignments([Surreal.library], TranslateTest.describe1(bays, |b| { ..b, aisle: b.id, slot: b.slot }), [row], Translate.variable) == Ok([{ name: "aisle", surql: "record::id(id)" }])

# The type of a payload decides its form, also when a kept definition holds
# it. A record payload that the clause does not build field by field is
# refused, not written at `value`.
expect selected(TranslateTest.describe1(spots, |s| { place: Shelved(s.shelf), shelf: s.shelf })) == Err(Unsupported("the payload of `Shelved` is a record the clause does not build field by field"))

# The prim table.
expect where_(TranslateTest.describe1(orders, |o| o.customer.id().key() == "ada")) == Ok("record::id(customer) = 'ada'")
expect where_(TranslateTest.describe1(customers, |c| c.id != "bob")) == Ok("record::id(id) != 'bob'")
# The row of a named table: a key compared with a literal is the record id.
expect Translate.render([Surreal.library], TranslateTest.describe1(customers, |c| c.id != "bob"), [Translate.table_row("customer", Bool.False)], Translate.variable) == Ok("id != customer:⟨bob⟩")
expect Translate.render([Surreal.library], TranslateTest.describe1(customers, |c| "bob" == c.id), [Translate.table_row("customer", Bool.False)], Translate.variable) == Ok("id = customer:⟨bob⟩")
expect Translate.render([Surreal.library], TranslateTest.describe1(customers, |c| c.id.starts_with("b")), [Translate.table_row("customer", Bool.False)], Translate.variable) == Ok("string::starts_with(record::id(id), 'b')")
expect Translate.render([Surreal.library], TranslateTest.describe1(customers, |c| c.id == c.name), [Translate.table_row("customer", Bool.False)], Translate.variable) == Ok("record::id(id) = name")
expect where_(TranslateTest.describe1(orders, |o| o.customer.get().id == "ada")) == Ok("record::id(customer) = 'ada'")
expect where_(TranslateTest.describe1(orders, |o| (o.total + 1) * 2 - o.total / 4 < 10)) == Ok("(((total + 1.0dec) * 2.0dec) - (total / 4.0dec)) < 10.0dec")
expect where_(TranslateTest.describe1(orders, |o| o.items.any(|i| i.qty // 2 == 1 and i.qty % 2 == 0))) == Ok("items.any(|$v1| (($v1.qty / 2) = 1) AND (($v1.qty % 2) = 0))")
expect where_(TranslateTest.describe1(orders, |o| o.total // 2 > 1)) == Err(Unsupported("`//` on `Num.Dec` truncates a fraction, and SurrealDB's `/` does not; divide with `/`"))
expect where_(TranslateTest.describe1(orders, |o| o.items.any(|i| i.qty.to_dec() > o.total))) == Ok("items.any(|$v1| <decimal>$v1.qty > total)")
expect where_(TranslateTest.describe1(orders, |o| o.items.len().to_i64_wrap() > 1)) == Ok("items.len() > 1")
expect where_(TranslateTest.describe1(customers, |c| "${c.name}!${c.address.city}" == "Ada!Paris")) == Ok("(name + '!' + address.city) = 'Ada!Paris'")
expect where_(TranslateTest.describe1(customers, |c| c.name.starts_with("A") or c.name.ends_with("a") or c.name.contains("d"))) == Ok("string::starts_with(name, 'A') OR string::ends_with(name, 'a') OR string::contains(name, 'd')")
expect where_(TranslateTest.describe1(customers, |c| c.tags.contains("vip") and !c.tags.is_empty())) == Ok("(tags CONTAINS 'vip') AND (!(tags.len() = 0))")
expect where_(TranslateTest.describe1(orders, |o| o.items.all(|i| i.qty > 0))) == Ok("items.all(|$v1| $v1.qty > 0)")
expect where_(TranslateTest.describe1(orders, |o| o.items.map(|i| i.qty).sum() > 5)) == Ok("math::sum(items.map(|$v1| $v1.qty)) > 5")
expect where_(TranslateTest.describe1(orders, |o| o.items.find_first(|i| i.qty > 1).is_ok())) == Ok("items.find(|$v1| $v1.qty > 1) IS NOT NONE")
expect where_(TranslateTest.describe1(orders, |o| o.items.map(|i| i.product.get().price).sum() > o.total)) == Ok("math::sum(items.map(|$v1| $v1.product.price)) > total")
expect where_(TranslateTest.describe1(customers, |c| c.born < new_year)) == Ok("born < d'2020-01-01T00:00:00Z'")
expect where_(TranslateTest.describe1(customers, |c| c.born == new_year)) == Ok("born = d'2020-01-01T00:00:00Z'")
expect where_(TranslateTest.describe1(customers, |c| c.address.?zip.is_err())) == Ok("address.zip IS NONE")
expect where_(TranslateTest.describe1(customers, |c| c.name.is_empty())) == Ok("name = ''")

# Unions, guards and optional values.
expect where_(
	TranslateTest.describe1(
		orders,
		|o| match o.payment {
			Points(n) => n > 3
			Cash => Bool.True
			_ => Bool.False
		},
	),
) == Ok("(IF payment = 'Cash' THEN true ELSE IF payment.kind = 'Points' THEN payment.value > 3 ELSE false END)")
expect where_(
	TranslateTest.describe1(
		orders,
		|o| match o.payment {
			Split(a, b) => a + b > 3
			_ => Bool.False
		},
	),
) == Ok("(IF payment.kind = 'Split' THEN (payment.value[0] + payment.value[1]) > 3 ELSE false END)")
expect where_(
	TranslateTest.describe1(
		orders,
		|o| match o.payment {
			Invoice({ contact, due }) if due != "" => contact.get().name == "Ada"
			_ => Bool.False
		},
	),
) == Ok("(IF payment.kind = 'Invoice' THEN (IF payment.due = '' THEN false ELSE payment.contact.name = 'Ada' END) ELSE false END)")
expect selected(TranslateTest.describe1(customers, |c| { z: if (c.name == "Ada") "a" else "b" })) == Ok([{ name: "z", surql: "(IF name = 'Ada' THEN 'a' ELSE 'b' END)" }])
expect selected(
	TranslateTest.describe1(
		customers,
		|c| {
			z: match c.address.?zip {
				Ok(z) => "${z}!"
				Err(_) => "none"
			},
		},
	),
) == Ok([{ name: "z", surql: "(IF address.zip IS NONE THEN 'none' ELSE address.zip + '!' END)" }])

# Edges as a relation table's own rows.
expect Translate.render([Surreal.library], TranslateTest.describe1(purchases, |e| e.from.get().name != e.to.get().title), [Translate.document("", Bool.True)], Translate.variable) == Ok("in.name != out.title")

# Helpers: one called twice is expanded twice, one that recurses is refused.
expect where_(TranslateTest.describe1(orders, |o| o.items.any(|i| line_total(i) > 4) or o.items.all(|i| line_total(i) < 100))) == Ok("items.any(|$v1| ($v1.qty * 2) > 4) OR items.all(|$v3| ($v3.qty * 2) < 100)")
expect where_(TranslateTest.describe1(orders, |o| depth(o.items.map(|i| i.qty).sum()) > 2)) == Err(Unsupported("a function that calls itself has no SurrealQL form"))

# Field paths for the schema builder.
expect Translate.path_of(TranslateTest.describe1(orders, |o| o.items.map(|i| i.qty))).map_ok(Translate.spell) == Ok("items[*].qty")
expect Translate.path_of(TranslateTest.describe1(customers, |c| c.address.?zip)).map_ok(Translate.spell) == Ok("address.zip")
expect Translate.paths_of(TranslateTest.describe1(customers, |c| { a: c.name, b: c.address.city })).map_ok(|ps| ps.map(Translate.spell)) == Ok(["name", "address.city"])
expect Translate.path_of(TranslateTest.describe1(orders, |o| o.customer.get().name)) == Err(Unsupported("a field path reads fields only; this one calls `Surreal.Link.get`"))

# Captured values.
expect Translate.captured(Named("Surreal.Id", [Str], Record([{ name: "key", ty: Str, presence: Required }, { name: "table", ty: Str, presence: Required }])), Wrap(Record([Str("ada"), Str("customer")]))).map_ok(Ql.literal) == Ok("customer:⟨ada⟩")
expect Translate.captured(Dec, Dec(2.5)).map_ok(Ql.literal) == Ok("2.5dec")

# More list operations, a union inside a closure, and records the clause builds.
Kinded : { id : Str, kinds : List([Big(I64), Small]) }

kinded : List(Kinded)
kinded = []

expect where_(
	TranslateTest.describe1(
		kinded,
		|k| k.kinds.any(
			|x| match x {
				Big(n) => n > 5
				Small => Bool.False
			},
		),
	),
) == Ok("kinds.any(|$v1| (IF $v1.kind = 'Big' THEN $v1.value > 5 ELSE false END))")
expect where_(TranslateTest.describe1(orders, |o| o.items.drop_if(|i| i.qty > 1).len() > 0)) == Ok("items.filter(|$v1| !($v1.qty > 1)).len() > 0")
expect where_(TranslateTest.describe1(orders, |o| o.items.count_if(|i| i.qty > 1) > 0)) == Ok("items.filter(|$v1| $v1.qty > 1).len() > 0")
expect where_(TranslateTest.describe1(customers, |c| ["Paris", "Rome"].contains(c.address.city))) == Ok("['Paris', 'Rome'] CONTAINS address.city")
expect where_(
	TranslateTest.describe1(
		orders,
		|o| match o.payment {
			Invoice(i) => i.contact.id() == ada_id
			_ => Bool.False
		},
	),
) == Ok("(IF payment.kind = 'Invoice' THEN payment.contact = customer:⟨ada⟩ ELSE false END)")
expect selected(TranslateTest.describe1(customers, |c| { place: { town: c.address.city }, first: c.born <= new_year })) == Ok([{ name: "first", surql: "born <= d'2020-01-01T00:00:00Z'" }, { name: "place", surql: "{ town: address.city }" }])
expect {
	graph = TranslateTest.describe_group([""], orders, |_, rows| { big: rows.keep_if(|o| o.total > 10).len() })
	Translate.columns([Surreal.library], graph, [Translate.Binding.Expr("k"), Translate.Binding.Group(row)], Translate.variable) == Ok([{ name: "big", surql: "count(total > 10.0dec)" }])
}
expect Translate.render([Surreal.library], TranslateTest.describe1(orders, |o| o.total > 1), [Translate.document("$after", Bool.False)], Translate.variable) == Ok("$after.total > 1.0dec")
expect Translate.render([Surreal.library], TranslateTest.describe1(["x"], |s| s.contains("@")), [Translate.at("$value", Str)], Translate.variable) == Ok("string::contains($value, '@')")
expect where_(TranslateTest.describe1(orders, |o| o.items.any(|i| i.qty < 0) and o.items.len() > 3 and o.total != 0)) == Ok("items.any(|$v1| $v1.qty < 0) AND (items.len() > 3) AND (total != 0.0dec)")

# A captured `Id` binds whatever its row holds: the row is a type argument of
# the `Named`, and the value holds only the table and the key. `Member` has an
# optional field and a `Set` field.
at_least : Dec, Surreal.Id(Product) -> Code.Bound(Try(Str, Ql.Error))
at_least = |min, pen| TranslateTest.describe_bound(orders, |o| o.total >= min and o.items.any(|i| i.product.id() == pen))

expect {
	bound = at_least(5, Surreal.Id.({ table: "product", key: "pen" }))
	bound.value() == Ok("(total >= $_1) AND items.any(|$v1| $v1.product = $_2)") and bound.inputs().len() == 2
}

Member : { id : Str, name : Str, nick ?: Str, labels : Set(Str) }

Ticket : { id : Str, owner : Surreal.Link(Member), watchers : List(Surreal.Link(Member)) }

tickets : List(Ticket)
tickets = []

of_owner : Surreal.Id(Member) -> Code.Bound(Try(Str, Ql.Error))
of_owner = |who| TranslateTest.describe_bound(tickets, |t| t.owner.id() == who)

of_owners : List(Surreal.Id(Member)) -> Code.Bound(Try(Str, Ql.Error))
of_owners = |many| TranslateTest.describe_bound(tickets, |t| many.contains(t.owner.id()))

of_customer : Surreal.Id(Customer) -> Code.Bound(Try(Str, Ql.Error))
of_customer = |who| TranslateTest.describe_bound(orders, |o| o.customer.id() == who)

expect {
	bound = of_owner(Surreal.Id.({ table: "member", key: "ada" }))
	bound.value() == Ok("owner = $_1") and bound.inputs().len() == 1
}
expect {
	bound = of_owners([Surreal.Id.({ table: "member", key: "ada" }), Surreal.Id.({ table: "member", key: "bob" })])
	bound.value() == Ok("$_1 CONTAINS owner") and bound.inputs().len() == 1
}
expect {
	bound = of_customer(ada_id)
	bound.value() == Ok("customer = $_1") and bound.inputs().len() == 1
}
# A captured record with an optional field binds. An address with no `zip`
# holds `Absent` for it, and its object leaves the field out.
at_places : List(Address) -> Code.Bound(Try(Str, Ql.Error))
at_places = |places| TranslateTest.describe_bound(customers, |c| places.contains(c.address))

expect {
	bound = at_places([{ city: "Paris" }, { city: "Rome", zip: "00100" }])
	bound.value() == Ok("$_1 CONTAINS address") and bound.inputs() == [List([Record([Str("Paris"), Absent]), Record([Str("Rome"), Str("00100")])])]
}
customer_table : Surreal.Table(Customer)
customer_table = Surreal.table("customer")

customers_at : List(Address) -> Try(Surreal.Prepared(List(Customer)), Surreal.Error)
customers_at = |places| Surreal.bind_captured(Surreal.select_where(customer_table, |c| places.contains(c.address)))

expect customers_at([{ city: "Paris" }, { city: "Rome", zip: "00100" }]).map_ok(|s| s.statement().to_script()) == Ok("LET $_1 = [{ city: 'Paris' }, { city: 'Rome', zip: '00100' }];\nSELECT address, born, record::id(id) AS id, name, tags FROM customer WHERE $_1 CONTAINS address;")

# A direct `==` over a captured address compares the optional `zip` by
# presence, then by value. The compiler gives that as a switch on each
# presence. SurrealDB reads an absent field as NONE and `NONE = NONE` is
# true, so the translator prints the comparison alone. `!=` is the same.
# The captured address is one input, and its fields are `$_1.city` and `$_1.zip`.
customer_at : Address -> Try(Surreal.Prepared(List(Customer)), Surreal.Error)
customer_at = |place| Surreal.bind_captured(Surreal.select_where(customer_table, |c| c.address == place))

expect customer_at({ city: "Rome", zip: "00100" }).map_ok(|s| s.statement().to_script()) == Ok("LET $_1 = { city: 'Rome', zip: '00100' };\nSELECT address, born, record::id(id) AS id, name, tags FROM customer WHERE (address.city = $_1.city) AND (address.zip = $_1.zip);")
expect customer_at({ city: "Paris" }).map_ok(|s| s.statement().to_script()) == Ok("LET $_1 = { city: 'Paris' };\nSELECT address, born, record::id(id) AS id, name, tags FROM customer WHERE (address.city = $_1.city) AND (address.zip = $_1.zip);")

customer_not_at : Address -> Try(Surreal.Prepared(List(Customer)), Surreal.Error)
customer_not_at = |place| Surreal.bind_captured(Surreal.select_where(customer_table, |c| c.address != place))

expect customer_not_at({ city: "Paris" }).map_ok(|s| s.statement().to_script()) == Ok("LET $_1 = { city: 'Paris' };\nSELECT address, born, record::id(id) AS id, name, tags FROM customer WHERE (address.city != $_1.city) OR (address.zip != $_1.zip);")
expect where_(TranslateTest.describe1(customers, |c| c.born > new_year)) == Ok("born > d'2020-01-01T00:00:00Z'")
# A constant read twice is a kept definition, so it stays where the normal
# form puts it, on the left.
expect where_(TranslateTest.describe1(customers, |c| c.born > new_year and c.born >= new_year)) == Ok("(d'2020-01-01T00:00:00Z' < born) AND (d'2020-01-01T00:00:00Z' <= born)")

# Builtins on `Str`. The ASCII case change works per character, because `string::uppercase` also changes letters outside ASCII.
upper : Str -> Str
upper = |x| "array::join(string::split(${x}, '').map(|$ch| IF $ch >= 'a' AND $ch <= 'z' THEN string::uppercase($ch) ELSE $ch END), '')"

lower : Str -> Str
lower = |x| "array::join(string::split(${x}, '').map(|$ch| IF $ch >= 'A' AND $ch <= 'Z' THEN string::lowercase($ch) ELSE $ch END), '')"

expect where_(TranslateTest.describe1(samples, |s| s.text.with_ascii_uppercased() == "ADA")) == Ok("${upper("text")} = 'ADA'")
expect where_(TranslateTest.describe1(samples, |s| s.text.with_ascii_lowercased() == "ada")) == Ok("${lower("text")} = 'ada'")
expect where_(TranslateTest.describe1(samples, |s| s.text.caseless_ascii_equals(s.other))) == Ok("${lower("text")} = ${lower("other")}")
expect where_(TranslateTest.describe1(samples, |s| s.text.trim() == "x")) == Ok("string::replace(text, /^[\\s\\u{200E}\\u{200F}]+|[\\s\\u{200E}\\u{200F}]+$/, '') = 'x'")
expect where_(TranslateTest.describe1(samples, |s| s.text.trim_start() == "x")) == Ok("string::replace(text, /^[\\s\\u{200E}\\u{200F}]+/, '') = 'x'")
expect where_(TranslateTest.describe1(samples, |s| s.text.trim_end() == "x")) == Ok("string::replace(text, /[\\s\\u{200E}\\u{200F}]+$/, '') = 'x'")
expect where_(TranslateTest.describe1(samples, |s| s.text.repeat(2) == "xx")) == Ok("string::repeat(text, 2) = 'xx'")
expect where_(TranslateTest.describe1(samples, |s| s.text.with_prefix("a") == "ax")) == Ok("('a' + text) = 'ax'")
expect where_(TranslateTest.describe1(samples, |s| s.text.drop_prefix("a") == "x")) == Ok("(IF string::starts_with(text, 'a') THEN string::slice(text, string::len('a')) ELSE text END) = 'x'")
expect where_(TranslateTest.describe1(samples, |s| s.text.drop_suffix("a") == "x")) == Ok("(IF string::ends_with(text, 'a') THEN string::slice(text, 0, string::len(text) - string::len('a')) ELSE text END) = 'x'")
expect where_(TranslateTest.describe1(samples, |s| s.text.split_on(",").len() == 2)) == Ok("string::split(text, ',').len() = 2")
expect where_(TranslateTest.describe1(samples, |s| s.text.split_on("").len() == 1)) == Ok("[text].len() = 1")
expect where_(TranslateTest.describe1(samples, |s| s.text.split_on(s.other).len() == 2)) == Ok("(IF other = '' THEN [text] ELSE string::split(text, other) END).len() = 2")
expect where_(TranslateTest.describe1(samples, |s| Str.join_with(s.words, ",") == "a,b")) == Ok("array::join(words, ',') = 'a,b'")
expect where_(TranslateTest.describe1(samples, |s| s.text.replace_each("a", "b") == "x")) == Ok("string::replace(text, 'a', 'b') = 'x'")
expect where_(TranslateTest.describe1(samples, |s| s.text.replace_each("", "b") == "x")) == Ok("text = 'x'")
expect where_(TranslateTest.describe1(samples, |s| s.text.replace_each(s.other, "b") == "x")) == Ok("(IF other = '' THEN text ELSE string::replace(text, other, 'b') END) = 'x'")
expect where_(TranslateTest.describe1(samples, |s| s.text.count_utf8_bytes() > 3)) == Ok("bytes::len(<bytes>text) > 3")
expect where_(TranslateTest.describe1(samples, |s| s.text.to_str() == "x")) == Ok("text = 'x'")
expect where_(TranslateTest.describe1(samples, |s| I64.from_str(s.text).is_ok())) == Err(Unsupported("`from_str` accepts more forms than SurrealDB casts; parse in Roc and store a number"))
expect where_(TranslateTest.describe1(samples, |s| s.text.split_first(",").is_ok())) == Err(Unsupported("`Str.split_first` has no SurrealQL form"))

# Builtins on integers and `Dec`.
expect where_(TranslateTest.describe1(samples, |s| s.n.max(3) > 3)) == Ok("math::max([n, 3]) > 3")
expect where_(TranslateTest.describe1(samples, |s| s.n.min(s.m) > 3)) == Ok("math::min([n, m]) > 3")
expect where_(TranslateTest.describe1(samples, |s| s.f.max(1) > 0)) == Err(Unsupported("`max` on `Num.F64` differs from SurrealDB for NaN, -0.0 and how a float prints; use `Dec` or an integer"))
expect where_(TranslateTest.describe1(samples, |s| s.n.pow(2) > 3)) == Ok("math::pow(n, 2) > 3")
expect where_(TranslateTest.describe1(samples, |s| s.d.pow(2) > 3)) == Err(Unsupported("`pow` on `Dec` keeps 18 digits in Roc and 28 in SurrealDB; the two differ"))
expect where_(TranslateTest.describe1(samples, |s| s.n.mod_by(3) == 1)) == Ok("(((n % 3) + 3) % 3) = 1")
expect where_(TranslateTest.describe1(samples, |s| s.n.is_multiple_of(3))) == Ok("n % 3 = 0")
expect where_(TranslateTest.describe1(samples, |s| s.n.is_multiple_of(s.m))) == Ok("(IF m = 0 THEN n = 0 ELSE n % m = 0 END)")
expect where_(TranslateTest.describe1(samples, |s| s.n.is_multiple_of(0))) == Ok("(IF 0 = 0 THEN n = 0 ELSE n % 0 = 0 END)")
expect where_(TranslateTest.describe1(samples, |s| s.n.is_zero())) == Ok("n = 0")
expect where_(TranslateTest.describe1(samples, |s| s.n.is_negative())) == Ok("n < 0")
expect where_(TranslateTest.describe1(samples, |s| s.n.is_positive())) == Ok("n > 0")
expect where_(TranslateTest.describe1(samples, |s| s.d.is_negative())) == Ok("d < 0")
expect where_(TranslateTest.describe1(samples, |s| s.f.is_zero())) == Err(Unsupported("`is_zero` on `Num.F64` differs from SurrealDB for NaN, -0.0 and how a float prints; use `Dec` or an integer"))
expect where_(TranslateTest.describe1(samples, |s| s.n.is_even())) == Ok("n % 2 = 0")
expect where_(TranslateTest.describe1(samples, |s| s.n.is_odd())) == Ok("n % 2 != 0")
expect where_(TranslateTest.describe1(samples, |s| s.n.to_str() == "3")) == Ok("<string>n = '3'")
expect where_(TranslateTest.describe1(samples, |s| s.d.to_str() == "3")) == Err(Unsupported("`to_str` on `Dec` prints differently: Roc `3.0`, SurrealDB `3`; compare the number"))
expect where_(TranslateTest.describe1(samples, |s| s.d.round() == 3)) == Ok("(IF d >= 0 THEN math::floor(d + 0.5dec) ELSE math::ceil(d - 0.5dec) END) = 3.0dec")
expect where_(TranslateTest.describe1(samples, |s| s.d.floor() == 1)) == Ok("math::floor(d) = 1.0dec")
expect where_(TranslateTest.describe1(samples, |s| s.d.ceiling() == 1)) == Ok("math::ceil(d) = 1.0dec")
expect where_(TranslateTest.describe1(samples, |s| s.d.trunc() == 1)) == Ok("(IF d >= 0 THEN math::floor(d) ELSE math::ceil(d) END) = 1.0dec")

# Conversions between numbers. A conversion of a `Dec` that cuts a fraction is refused.
expect where_(TranslateTest.describe1(samples, |s| s.n.to_i128() > 1)) == Ok("n > 1")
expect where_(TranslateTest.describe1(samples, |s| s.n.to_i64_wrap() > 3)) == Ok("n > 3")
expect where_(TranslateTest.describe1(samples, |s| s.d.to_i64_wrap() > 3)) == Err(Unsupported("`to_i64_wrap` on `Num.Dec` cuts the fraction, and SurrealDB's `<int>` raises an error on one; use `to_i64_try`"))
expect where_(TranslateTest.describe1(samples, |s| s.f.to_i64_wrap() > 3)) == Err(Unsupported("`to_i64_wrap` on `Num.F64` cuts the fraction, and SurrealDB's `<int>` raises an error on one; use `to_i64_try`"))
expect where_(TranslateTest.describe1(samples, |s| s.n.to_u8_try().is_ok())) == Ok("(IF n >= 0 AND n <= 255 THEN n ELSE NONE END) IS NOT NONE")
expect where_(TranslateTest.describe1(samples, |s| s.n.to_i32_try().is_ok())) == Ok("(IF n >= -2147483648 AND n <= 2147483647 THEN n ELSE NONE END) IS NOT NONE")
expect where_(TranslateTest.describe1(samples, |s| s.n.to_u64_try().is_ok())) == Ok("(IF n >= 0 THEN n ELSE NONE END) IS NOT NONE")
expect where_(TranslateTest.describe1(samples, |s| s.n.to_i128().to_i64_try().is_ok())) == Ok("n IS NOT NONE")
expect where_(TranslateTest.describe1(samples, |s| (s.n.to_u8_try() ?? 0) > 1)) == Ok("((IF n >= 0 AND n <= 255 THEN n ELSE NONE END) ?? 0) > 1")
expect where_(TranslateTest.describe1(samples, |s| s.d.to_i64_try().is_ok())) == Ok("(IF d > -9223372036854775809dec AND d < 9223372036854775808dec THEN <int>(IF d >= 0 THEN math::floor(d) ELSE math::ceil(d) END) ELSE NONE END) IS NOT NONE")

# `Try` and `List` builtins. A `Try` is `NONE` when it is an `Err`.
expect where_(TranslateTest.describe1(samples, |s| s.?opt.ok_or("x") == "y")) == Ok("(opt ?? 'x') = 'y'")
expect where_(TranslateTest.describe1(samples, |s| s.nums.first().ok_or(0) > 1)) == Ok("(array::first(nums) ?? 0) > 1")
expect where_(TranslateTest.describe1(samples, |s| s.nums.last().is_ok())) == Ok("array::last(nums) IS NOT NONE")
expect where_(TranslateTest.describe1(samples, |s| s.nums.get(1).is_ok())) == Ok("array::at(nums, 1) IS NOT NONE")
expect where_(TranslateTest.describe1(samples, |s| s.nums.max().is_err())) == Ok("array::max(nums) IS NONE")
expect where_(TranslateTest.describe1(samples, |s| s.nums.min().is_ok())) == Ok("array::min(nums) IS NOT NONE")
expect where_(
	TranslateTest.describe1(
		samples,
		|s| match s.nums.first() {
			Ok(x) => x > 1
			Err(_) => Bool.False
		},
	),
) == Ok("(IF array::first(nums) IS NONE THEN false ELSE array::first(nums) > 1 END)")
expect where_(TranslateTest.describe1(samples, |s| s.nums.take_first(2).len() == 2)) == Ok("array::slice(nums, 0, 2).len() = 2")
expect where_(TranslateTest.describe1(samples, |s| s.nums.drop_first(2).len() == 1)) == Ok("array::slice(nums, 2).len() = 1")
expect where_(TranslateTest.describe1(samples, |s| s.nums.concat(s.nums).len() > 1)) == Ok("array::concat(nums, nums).len() > 1")
expect where_(TranslateTest.describe1(samples, |s| s.nums.append(1).len() > 1)) == Ok("array::append(nums, 1).len() > 1")
expect where_(TranslateTest.describe1(samples, |s| s.nums.prepend(1).len() > 1)) == Ok("array::prepend(nums, 1).len() > 1")
expect where_(TranslateTest.describe1(samples, |s| s.nums.rev().len() > 1)) == Ok("array::reverse(nums).len() > 1")
expect where_(TranslateTest.describe1(samples, |s| s.grid.join().len() > 1)) == Ok("array::flatten(grid).len() > 1")

# A sort is `array::sort` only when its evidence names the order of a whole number or a `Dec`. Roc has no
# default order for `Str` or a float. A type with an order of its own and a sort by a function are refused.
expect where_(TranslateTest.describe1(samples, |s| s.nums.sort().first().ok_or(0) > 1)) == Ok("(array::first(array::sort::asc(nums)) ?? 0) > 1")
expect where_(TranslateTest.describe1(samples, |s| s.nums.sort_reversed().first().ok_or(0) > 1)) == Ok("(array::first(array::sort::desc(nums)) ?? 0) > 1")
expect where_(TranslateTest.describe1(samples, |s| s.decs.sort_reversed().len() > 1)) == Ok("array::sort::desc(decs).len() > 1")
expect where_(TranslateTest.describe1(samples, |s| s.ranks.sort().len() > 1)) == sort_error("sort")
expect where_(TranslateTest.describe1(samples, |s| s.nums.sort_with(|a, b| b.order_relative_to(a)).len() > 1)) == Err(Unsupported("`List.sort_with` has no SurrealQL form"))
expect where_(TranslateTest.describe1(samples, |s| s.nums == [1, 2])) == Ok("nums = [1, 2]")
# The edges of a relation keep their kind through `rev`, and give no single element.
expect {
	graph = TranslateTest.describe_pair(customers, purchases, |(_, bought)| { titles: bought.rev().map(|e| e.to.get().title) })
	Translate.columns([Surreal.library], graph, [Translate.Binding.WithEdges(row, [Translate.outgoing("", "purchased")])], Translate.variable) == Ok([{ name: "titles", surql: "array::reverse(->purchased).map(|$v1| $v1.out.title)" }])
}
expect {
	graph = TranslateTest.describe_pair(customers, purchases, |(_, bought)| { first: bought.first().is_ok() })
	Translate.columns([Surreal.library], graph, [Translate.Binding.WithEdges(row, [Translate.outgoing("", "purchased")])], Translate.variable) == Err(Unsupported("the edges of a relation take `keep_if`, `map`, `any`, `all` and `len`"))
}

# The functions of `Surreal.Text`: one SurrealQL function of the same arguments.
expect where_(TranslateTest.describe1(samples, |s| Surreal.Text.is_email(s.text))) == Ok("string::is_email(text)")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Text.is_url(s.text))) == Ok("string::is_url(text)")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Text.is_domain(s.text))) == Ok("string::is_domain(text)")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Text.is_ip(s.text))) == Ok("string::is_ip(text)")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Text.is_ipv4(s.text))) == Ok("string::is_ipv4(text)")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Text.is_ipv6(s.text))) == Ok("string::is_ipv6(text)")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Text.is_uuid(s.text))) == Ok("string::is_uuid(text)")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Text.is_ulid(s.text))) == Ok("string::is_ulid(text)")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Text.is_semver(s.text))) == Ok("string::is_semver(text)")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Text.is_alpha(s.text))) == Ok("string::is_alpha(text)")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Text.is_alphanum(s.text))) == Ok("string::is_alphanum(text)")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Text.is_numeric(s.text))) == Ok("string::is_numeric(text)")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Text.is_latitude(s.text))) == Ok("string::is_latitude(text)")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Text.is_longitude(s.text))) == Ok("string::is_longitude(text)")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Text.is_ascii(s.text))) == Ok("string::is_ascii(text)")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Text.is_hexadecimal(s.text))) == Ok("string::is_hexadecimal(text)")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Text.is_datetime(s.text, "%Y"))) == Ok("string::is_datetime(text, '%Y')")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Text.matches(s.text, "^a"))) == Ok("string::matches(text, '^a')")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Text.similarity_jaro(s.text, s.other) > 0.8)) == Ok("string::similarity::jaro(text, other) > 0.8f")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Text.similarity_jaro_winkler(s.text, s.other) > 0.8)) == Ok("string::similarity::jaro_winkler(text, other) > 0.8f")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Text.distance_levenshtein(s.text, s.other) < 2)) == Ok("string::distance::levenshtein(text, other) < 2")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Text.distance_damerau_levenshtein(s.text, s.other) < 2)) == Ok("string::distance::damerau_levenshtein(text, other) < 2")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Text.distance_normalized_levenshtein(s.text, s.other) < 0.5)) == Ok("string::distance::normalized_levenshtein(text, other) < 0.5f")

# The hashes of `Surreal.Hash`, and the table of an id.
expect where_(TranslateTest.describe1(samples, |s| Surreal.Hash.sha256(s.text) == "x")) == Ok("crypto::sha256(text) = 'x'")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Hash.blake3(s.text) == "x")) == Ok("crypto::blake3(text) = 'x'")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Hash.md5(s.text) == "x")) == Ok("crypto::md5(text) = 'x'")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Hash.sha1(s.text) == "x")) == Ok("crypto::sha1(text) = 'x'")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Hash.sha512(s.text) == "x")) == Ok("crypto::sha512(text) = 'x'")
expect where_(TranslateTest.describe1(orders, |o| Surreal.Id.table(o.customer.id()) == "customer")) == Ok("record::tb(customer) = 'customer'")

# The hash of a password: a new salt on every call, so not in a query,
# and the compare, as a `SIGNIN` checks a password.
expect where_(TranslateTest.describe1(samples, |s| Surreal.Hash.argon2_matches(s.text, s.other))) == Ok("crypto::argon2::compare(text, other)")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Hash.argon2(s.text) == s.other)) == Err(Unsupported("`Surreal.Hash.argon2` gives a new value on every call: use it in a default, a computed field or an update"))

# The values of the session: the record user, as an `Id` of its table,
# the access method and the expiry of the token.
expect where_(TranslateTest.describe1(orders, |o| o.customer.id() == customer_table.auth())) == Ok("customer = $auth.id")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Auth.access() == s.text)) == Ok("$access = text")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Auth.expires() > s.n)) == Ok("n < $token.exp")

# The functions of `Surreal.Array`.
expect where_(TranslateTest.describe1(samples, |s| Surreal.Array.distinct(s.nums).len() > 1)) == Ok("array::distinct(nums).len() > 1")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Array.union(s.nums, s.nums).len() > 1)) == Ok("array::union(nums, nums).len() > 1")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Array.intersect(s.nums, s.nums).len() > 1)) == Ok("array::intersect(nums, nums).len() > 1")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Array.complement(s.nums, s.nums).len() > 1)) == Ok("array::complement(nums, nums).len() > 1")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Array.distinct(s.words).contains("a"))) == Ok("array::distinct(words) CONTAINS 'a'")

# The functions of `Surreal.Time`. A duration is built in the clause.
expect where_(TranslateTest.describe1(samples, |s| s.at < Surreal.Time.now())) == Ok("at < time::now()")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.floor(s.at, Surreal.Time.hours(1)) < s.at)) == Ok("time::floor(at, duration::from_nanos(3600000000000)) < at")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.ceil(s.at, Surreal.Time.hours(1)) < s.at)) == Ok("time::ceil(at, duration::from_nanos(3600000000000)) < at")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.round(s.at, Surreal.Time.hours(1)) < s.at)) == Ok("time::round(at, duration::from_nanos(3600000000000)) < at")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.floor(s.at, Surreal.Time.mins(90)) < s.at)) == Ok("time::floor(at, duration::from_nanos(5400000000000)) < at")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.floor(s.at, Surreal.Time.nanos(7)) < s.at)) == Ok("time::floor(at, duration::from_nanos(7)) < at")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.floor(s.at, Surreal.Time.weeks(1)) < s.at)) == Ok("time::floor(at, duration::from_nanos(604800000000000)) < at")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.floor(s.at, Surreal.Time.hours(s.nums.len())) < s.at)) == Ok("time::floor(at, duration::from_nanos(nums.len() * 3600000000000)) < at")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.group(s.at, Year) < s.at)) == Ok("time::group(at, 'year') < at")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.group(s.at, Month) < s.at)) == Ok("time::group(at, 'month') < at")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.group(s.at, Day) < s.at)) == Ok("time::group(at, 'day') < at")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.group(s.at, Hour) < s.at)) == Ok("time::group(at, 'hour') < at")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.group(s.at, Minute) < s.at)) == Ok("time::group(at, 'minute') < at")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.group(s.at, Second) < s.at)) == Ok("time::group(at, 'second') < at")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.plus(s.at, Surreal.Time.days(1)) > s.at)) == Ok("at < (at + duration::from_nanos(86400000000000))")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.minus(s.at, Surreal.Time.days(1)) < s.at)) == Ok("(at - duration::from_nanos(86400000000000)) < at")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.wday(s.at) == 7)) == Ok("time::wday(at) = 7")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.yday(s.at) == 7)) == Ok("time::yday(at) = 7")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.week(s.at) == 7)) == Ok("time::week(at) = 7")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.unix(s.at) == 7)) == Ok("time::unix(at) = 7")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.nano(s.at) == 7)) == Ok("time::nano(at) = 7")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.unix_millis(s.at) == 7)) == Ok("time::millis(at) = 7")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.unix_micros(s.at) == 7)) == Ok("time::micros(at) = 7")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.year(s.at) == 3)) == Ok("time::year(at) = 3")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.month(s.at) == 3)) == Ok("time::month(at) = 3")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.day(s.at) == 3)) == Ok("time::day(at) = 3")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.hour(s.at) == 3)) == Ok("time::hour(at) = 3")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.minute(s.at) == 3)) == Ok("time::minute(at) = 3")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.second(s.at) == 3)) == Ok("time::second(at) = 3")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.format(s.at, "%Y") == "2026")) == Ok("time::format(at, '%Y') = '2026'")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.from_unix(s.n) < s.at)) == Ok("time::from_unix(n) < at")

# The statistics of `Surreal.Math` over a list, and over the rows of a group.
expect where_(TranslateTest.describe1(samples, |s| Surreal.Math.mean(s.scores) > 2.5)) == Ok("math::mean(scores) > 2.5f")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Math.median(s.scores) > 2.5)) == Ok("math::median(scores) > 2.5f")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Math.stddev(s.scores) > 1)) == Ok("math::stddev(scores) > 1f")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Math.variance(s.scores) > 1)) == Ok("math::variance(scores) > 1f")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Math.percentile(s.scores, 90) > 3)) == Ok("math::percentile(scores, 90f) > 3f")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Math.mean(s.nums.map(|n| n.to_f64())) > 2)) == Ok("math::mean(nums.map(|$v1| <float>$v1)) > 2f")
expect {
	graph = TranslateTest.describe_group([""], orders, |_, rows| { avg: Surreal.Math.mean(rows.map(|o| o.total.to_f64())) })
	Translate.columns([Surreal.library], graph, [Translate.Binding.Expr("k"), Translate.Binding.Group(row)], Translate.variable) == Ok([{ name: "avg", surql: "math::mean(<float>total)" }])
}
expect {
	graph = TranslateTest.describe_group([""], orders, |_, rows| { mid: Surreal.Math.median(rows.map(|o| o.total.to_f64())) })
	Translate.columns([Surreal.library], graph, [Translate.Binding.Expr("k"), Translate.Binding.Group(row)], Translate.variable) == Ok([{ name: "mid", surql: "math::median(<float>total)" }])
}
expect {
	graph = TranslateTest.describe_group([""], orders, |_, rows| { sd: Surreal.Math.stddev(rows.map(|o| o.total.to_f64())) })
	Translate.columns([Surreal.library], graph, [Translate.Binding.Expr("k"), Translate.Binding.Group(row)], Translate.variable) == Ok([{ name: "sd", surql: "math::stddev(<float>total)" }])
}
expect {
	graph = TranslateTest.describe_group([""], orders, |_, rows| { spread: Surreal.Math.variance(rows.map(|o| o.total.to_f64())) })
	Translate.columns([Surreal.library], graph, [Translate.Binding.Expr("k"), Translate.Binding.Group(row)], Translate.variable) == Ok([{ name: "spread", surql: "math::variance(<float>total)" }])
}
expect {
	graph = TranslateTest.describe_group([""], orders, |_, rows| { p: Surreal.Math.percentile(rows.map(|o| o.total.to_f64()), 90) })
	Translate.columns([Surreal.library], graph, [Translate.Binding.Expr("k"), Translate.Binding.Group(row)], Translate.variable) == Err(Unsupported("`math::percentile` is not an aggregate in SurrealDB; use it on a list"))
}

# One `rows.map(f)` read by several aggregates: each aggregate writes its own expression.
expect {
	graph = TranslateTest.describe_group(
		[""],
		orders,
		|_, rows| {
			totals = rows.map(|o| o.total.to_f64())
			{ avg: Surreal.Math.mean(totals), mid: Surreal.Math.median(totals), spread: Surreal.Math.stddev(totals) }
		},
	)
	Translate.columns([Surreal.library], graph, [Translate.Binding.Expr("k"), Translate.Binding.Group(row)], Translate.variable)
		== Ok([{ name: "avg", surql: "math::mean(<float>total)" }, { name: "mid", surql: "math::median(<float>total)" }, { name: "spread", surql: "math::stddev(<float>total)" }])
}
expect {
	graph = TranslateTest.describe_group([""], orders, |_, rows| { low: Surreal.Math.mean(rows.map(|o| o.total.to_f64())), high: Surreal.Math.variance(rows.map(|o| o.total.to_f64())) })
	Translate.columns([Surreal.library], graph, [Translate.Binding.Expr("k"), Translate.Binding.Group(row)], Translate.variable) == Ok([{ name: "high", surql: "math::variance(<float>total)" }, { name: "low", surql: "math::mean(<float>total)" }])
}
expect {
	graph = TranslateTest.describe_group(
		[""],
		orders,
		|_, rows| {
			totals = rows.map(|o| o.total)
			{ sum: totals.sum(), sum_again: totals.sum() }
		},
	)
	Translate.columns([Surreal.library], graph, [Translate.Binding.Expr("k"), Translate.Binding.Group(row)], Translate.variable) == Ok([{ name: "sum", surql: "math::sum(total)" }, { name: "sum_again", surql: "math::sum(total)" }])
}
expect {
	graph = TranslateTest.describe_group(
		[""],
		orders,
		|_, rows| {
			totals = rows.map(|o| o.total.to_f64())
			{ avg: Surreal.Math.mean(totals), p: Surreal.Math.percentile(totals, 90) }
		},
	)
	Translate.columns([Surreal.library], graph, [Translate.Binding.Expr("k"), Translate.Binding.Group(row)], Translate.variable) == Err(Unsupported("`math::percentile` is not an aggregate in SurrealDB; use it on a list"))
}
expect {
	graph = TranslateTest.describe_group([""], orders, |_, rows| { n: rows.map(|o| o.total).len() })
	Translate.columns([Surreal.library], graph, [Translate.Binding.Expr("k"), Translate.Binding.Group(row)], Translate.variable) == Err(Unsupported("a group's rows take `len`, `keep_if(..).len()` and `map(..).sum()`"))
}

# `Rand` gives a new value on every call. A default, a computed field and an update may use it, a query may not.
random_error : Str -> Try(Str, Ql.Error)
random_error = |name| Err(Unsupported("`${name}` gives a new value on every call: use it in a default, a computed field or an update"))

sort_error : Str -> Try(Str, Ql.Error)
sort_error = |method| Err(Unsupported("`List.${method}` orders by `order_relative_to`, and only the order of whole numbers and `Dec` is the order of `array::sort`; sort a list of numbers, or sort in Roc"))

random_text : Code.Graph -> Try(Str, Ql.Error)
random_text = |graph| Translate.row_value([Surreal.library], graph, [row], Translate.variable)

salted : Sample -> Str
salted = |s| s.text.concat(Surreal.Rand.int(1, s.n).to_str())

expect where_(TranslateTest.describe1(samples, |s| Surreal.Rand.int(1, 6) > s.n)) == random_error("Surreal.Rand.int")
expect where_(TranslateTest.describe1(samples, |s| salted(s) == s.text)) == random_error("Surreal.Rand.int")
expect where_(TranslateTest.describe1(samples, |s| s.words.any(|w| w == Surreal.Rand.uuid()))) == random_error("Surreal.Rand.uuid")
expect selected(TranslateTest.describe1(samples, |_s| { r: Surreal.Rand.ulid() })) == Err(Unsupported("`Surreal.Rand.ulid` gives a new value on every call: use it in a default, a computed field or an update"))
expect random_text(TranslateTest.describe1(samples, |_s| Surreal.Rand.ulid())) == Ok("rand::ulid()")
expect random_text(TranslateTest.describe1(samples, |_s| Surreal.Rand.uuid())) == Ok("<string>rand::uuid()")
expect random_text(TranslateTest.describe1(samples, |s| Surreal.Rand.int(1, s.n))) == Ok("rand::int(1, n)")
expect random_text(TranslateTest.describe1(samples, |s| salted(s))) == Ok("text + <string>rand::int(1, n)")
expect Translate.assignments([Surreal.library], TranslateTest.describe1(customers, |c| { ..c, name: Surreal.Rand.ulid() }), [row], Translate.variable) == Ok([{ name: "name", surql: "rand::ulid()" }])

# `==` on datetimes compares the datetimes, also when one is a function result, is read twice or is a parameter.
# SurrealDB prints a fraction with 3, 6 or 9 digits and Roc without trailing zeros, so their texts differ.
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.floor(s.at, Surreal.Time.hours(1)) == new_year)) == Ok("time::floor(at, duration::from_nanos(3600000000000)) = d'2020-01-01T00:00:00Z'")
expect where_(TranslateTest.describe1(samples, |s| Surreal.Time.floor(s.at, Surreal.Time.hours(1)) == s.at)) == Ok("time::floor(at, duration::from_nanos(3600000000000)) = at")
expect where_(TranslateTest.describe1(samples, |s| new_year == Surreal.Time.floor(s.at, Surreal.Time.hours(1)))) == Ok("time::floor(at, duration::from_nanos(3600000000000)) = d'2020-01-01T00:00:00Z'")
expect where_(TranslateTest.describe1(samples, |s| same(s.at, hour_of(s)))) == Ok("at = time::floor(at, duration::from_nanos(3600000000000))")
expect where_(TranslateTest.describe1(samples, |s| s.times.any(|t| t == s.at))) == Ok("times.any(|$v1| $v1 = at)")
expect where_(TranslateTest.describe1(samples, |s| s.at == half_second)) == Ok("at = d'2026-03-04T05:06:07.5Z'")
expect where_(TranslateTest.describe1(samples, |s| s.at != new_year)) == Ok("at != d'2020-01-01T00:00:00Z'")
expect where_(TranslateTest.describe1(samples, |s| new_year != s.at)) == Ok("at != d'2020-01-01T00:00:00Z'")
expect where_(TranslateTest.describe1(samples, |s| s.times.any(|t| t != s.at))) == Ok("times.any(|$v1| $v1 != at)")
expect where_(TranslateTest.describe1(samples, |s| iso_of(s.at) == s.text)) == Err(Unsupported("the text of a datetime is compared with a datetime or a literal; SurrealDB prints a fraction with 3, 6 or 9 digits, so other texts differ"))
expect where_(TranslateTest.describe1(samples, |s| s.text == iso_of(s.at))) == Err(Unsupported("the text of a datetime is compared with a datetime or a literal; SurrealDB prints a fraction with 3, 6 or 9 digits, so other texts differ"))

# A `Duration` cannot be a captured value. A table with one has no column for it (see `TypesTest.roc`).
sample_table : Surreal.Table(Sample)
sample_table = Surreal.table("sample")

floor_by : Surreal.Duration -> Try(Surreal.Prepared(List(Sample)), Ql.Error)
floor_by = |span| Surreal.bind_captured(Surreal.select_where(sample_table, |s| Surreal.Time.floor(s.at, span) < s.at))

expect floor_by(Surreal.Time.hours(1)).map_ok(|_| "bound") == Err(Unsupported("a captured `Duration` has no SurrealQL value; build it in the clause, as `Time.hours(1)`"))

# The mirrors run in Roc. Each value below is what SurrealDB 3.3.4 gives for the same input.
moment : Str -> Surreal.Datetime
moment = |text| match Surreal.datetime(text) {
	Ok(d) => d
	Err(_) => crash "a valid datetime"
}

expect ["", "abé", "a\nb", "😀", "A", "\u(7f)"].map(Surreal.Text.is_ascii) == [Bool.False, Bool.False, Bool.True, Bool.False, Bool.True, Bool.True]
expect ["", "FF0a", "0xff", "g", "ＦＦ", "abcdefABCDEF", "٣", "9a"].map(Surreal.Text.is_hexadecimal) == [Bool.False, Bool.True, Bool.False, Bool.False, Bool.False, Bool.True, Bool.False, Bool.True]
expect Surreal.Hash.sha256("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
expect Surreal.Hash.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
expect Surreal.Hash.sha256("é") == "4a99557e4033c3539de2eb65472017cad5f9557f7a0625a09f1c3f6e2ba69c4c"
expect Surreal.Hash.sha256("😀") == "f0443a342c5ef54783a111b51ba56c938e474c32324d90c3a60c9c8e3a37e2d9"
expect Surreal.Hash.sha256(Str.repeat("a", 1000)) == "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3"
expect Surreal.Hash.blake3("") == "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262"
expect Surreal.Hash.blake3("abc") == "6437b3ac38465133ffb63b75273a8db548c558465d79db03fd359c6cd5bd9d85"
expect Surreal.Hash.blake3("é") == "46d0ec742ceaad149f9a3d109d1bd9e9ece7858161b43cf0008906478418e807"
expect Surreal.Hash.blake3("😀") == "728105475d1a9e2f0164862a43e44bea39fa5d8b73d484f9137b8ae65a66dd7a"
expect Surreal.Hash.blake3(Str.repeat("a", 1000)) == "9957a9014733dd6b6e2f6abcbe7b259a6da1aa0b0e184cd7bf1810e5c425f405"
expect Surreal.Id.table(ada_id) == "customer"

expect Surreal.Array.distinct([3.I64, 1, 3, 2, 1]) == [3, 1, 2]
expect Surreal.Array.distinct(List.repeat(1.I64, 0)) == []
expect Surreal.Array.distinct(["b", "a", "b", "é"]) == ["b", "a", "é"]
expect Surreal.Array.distinct([[1.I64], [1], [2, 3]]) == [[1], [2, 3]]
expect Surreal.Array.distinct([1.5.F64, 1.5, 0.0, -0.0, 0.0]) == [1.5, 0.0]
expect Surreal.Array.union([3.I64, 1], [2, 3, 1]) == [3, 1, 2]
expect Surreal.Array.union([1.I64, 1, 2], [2, 3, 3]) == [1, 2, 3]
expect Surreal.Array.union(["b", "a", "b", "é"], ["é", "c"]) == ["b", "a", "é", "c"]
expect Surreal.Array.union(List.repeat(1.I64, 0), [1]) == [1]
expect Surreal.Array.intersect([3.I64, 1, 3, 2, 1], [2, 3]) == [3, 2]
expect Surreal.Array.intersect([1.I64, 1, 2], [1, 2, 2]) == [1, 2]
expect Surreal.Array.intersect([1.I64, 1, 2], [2, 3, 3]) == [2]
expect Surreal.Array.intersect([1.I64, 2], List.repeat(1, 0)) == []
expect Surreal.Array.intersect(["b", "a", "b", "é"], ["é", "c"]) == ["é"]
expect Surreal.Array.complement([3.I64, 1, 2, 3], [2]) == [3, 1, 3]
expect Surreal.Array.complement([3.I64, 1, 3, 2, 1], [2, 3]) == [1, 1]
expect Surreal.Array.complement([1.I64, 1, 2], [2, 3, 3]) == [1, 1]
expect Surreal.Array.complement([1.I64, 1], [1]) == []
expect Surreal.Array.complement(["b", "a", "b", "é"], ["é", "c"]) == ["b", "a", "b"]
expect Surreal.Array.complement([1.5.F64, 0.0, -0.0], [0.0]) == [1.5]

expect {
	parts = |d| [Surreal.Time.year(d), Surreal.Time.month(d), Surreal.Time.day(d), Surreal.Time.hour(d), Surreal.Time.minute(d), Surreal.Time.second(d)]
	parts(moment("2026-03-04T05:06:07Z")) == [2026, 3, 4, 5, 6, 7] and parts(moment("2026-03-04T05:06:07.5Z")) == [2026, 3, 4, 5, 6, 7] and parts(moment("0000-01-01T00:00:00Z")) == [0, 1, 1, 0, 0, 0] and parts(moment("2024-02-29T23:59:59.999999999Z")) == [2024, 2, 29, 23, 59, 59] and parts(moment("9999-12-31T23:59:59Z")) == [9999, 12, 31, 23, 59, 59]
}
expect Surreal.Time.hours(1) == Surreal.Duration.({ nanos: 3600000000000 })
expect Surreal.Time.weeks(2) == Surreal.Duration.({ nanos: 1209600000000000 })
expect Surreal.Time.nanos(5) == Surreal.Duration.({ nanos: 5 })

expect Surreal.Math.mean([1.0, 2.0, 3.0, 4.0]) == 2.5
expect Surreal.Math.mean([0.1, 0.2, 0.3]) == 0.20000000000000004
expect Surreal.Math.mean([0.1, 0.7, 0.2, 0.4, 0.9]) == 0.45999999999999996
expect Surreal.Math.mean([1e16, 1.0, -1e16]) == 0.0
expect Surreal.Math.mean([5.0]) == 5.0
expect Surreal.Math.mean([1e308, 1e308]).is_infinite()
expect Surreal.Math.mean(List.repeat(1.0, 0)).is_nan()

# The nanoseconds since 1970 of `time::nano`, both ways.
expect moment("2026-03-04T05:06:07.123456789Z").to_unix_nanos() == 1772600767123456789
expect moment("1970-01-01T00:00:00Z").to_unix_nanos() == 0
expect moment("1969-12-31T23:59:59.5Z").to_unix_nanos() == -500000000
expect moment("2024-02-29T12:00:00.000000001Z").to_unix_nanos() == 1709208000000000001
expect moment("1900-03-01T00:00:00Z").to_unix_nanos() == -2203891200000000000
expect moment("2100-12-31T23:59:59.1Z").to_unix_nanos() == 4133980799100000000
expect Surreal.Datetime.from_unix_nanos(1772600767123456789) == Ok(moment("2026-03-04T05:06:07.123456789Z"))
expect Surreal.Datetime.from_unix_nanos(-1500000000) == Ok(moment("1969-12-31T23:59:58.5Z"))
expect Surreal.Datetime.from_unix_nanos(951868799000000000) == Ok(moment("2000-02-29T23:59:59Z"))
expect Surreal.Datetime.from_unix_nanos(-8000000000000000000) == Ok(moment("1716-06-28T09:46:40Z"))
expect Surreal.Datetime.from_unix_nanos(moment("0000-01-01T00:00:00Z").to_unix_nanos()) == Ok(moment("0000-01-01T00:00:00Z"))
expect Surreal.Datetime.from_unix_nanos(moment("9999-12-31T23:59:59.999999999Z").to_unix_nanos()) == Ok(moment("9999-12-31T23:59:59.999999999Z"))
expect Surreal.Datetime.from_unix_nanos(moment("9999-12-31T23:59:59.999999999Z").to_unix_nanos() + 1) == Err(BadDatetime)
expect Surreal.Datetime.from_unix_nanos(moment("0000-01-01T00:00:00Z").to_unix_nanos() - 1) == Err(BadDatetime)
expect ["0000-02-29T00:00:00Z", "0000-03-01T00:00:00Z", "1600-02-29T23:59:59.000001Z", "1899-12-31T23:59:59Z", "1969-12-31T23:59:59.999999999Z", "2000-03-01T00:00:00Z", "2038-01-19T03:14:07Z", "9999-01-31T10:20:30.5Z"].all(|text| Surreal.Datetime.from_unix_nanos(moment(text).to_unix_nanos()) == Ok(moment(text)))

# Database functions. A call is `fn::name(..)`, and the same call in Roc runs the Roc body.
feverish : Dec, I64 -> Bool
feverish = |d, n| d > 39.0 or n > 120

feverish_fn : Surreal.DbFn((Dec, I64 -> Bool))
feverish_fn = Surreal.db_fn("feverish", feverish)

in_paris : Address -> Bool
in_paris = |a| a.city == "Paris"

in_paris_fn : Surreal.DbFn((Address -> Bool))
in_paris_fn = Surreal.db_fn("in_paris", in_paris)

doubled : I64 -> I64
doubled = |n| n * 2

doubled_fn : Surreal.DbFn((I64 -> I64))
doubled_fn = Surreal.db_fn("doubled", doubled)

badly_named_fn : Surreal.DbFn((I64 -> I64))
badly_named_fn = Surreal.db_fn("Doubled", doubled)

expect feverish_fn.call2(39.5, 80)
expect !feverish_fn.call2(38.5, 80)
expect doubled_fn.call1(doubled_fn.call1(3)) == 12
expect where_(TranslateTest.describe1(samples, |s| feverish_fn.call2(s.d, s.n))) == Ok("fn::feverish(d, n)")
expect where_(TranslateTest.describe1(customers, |c| in_paris_fn.call1(c.address))) == Ok("fn::in_paris(address)")
expect where_(TranslateTest.describe1(samples, |s| doubled_fn.call1(doubled_fn.call1(s.n)) > 4)) == Ok("fn::doubled(fn::doubled(n)) > 4")
expect selected(TranslateTest.describe1(samples, |s| { twice: doubled_fn.call1(s.n), hot: feverish_fn.call2(s.d, 0) })) == Ok([{ name: "hot", surql: "fn::feverish(d, 0)" }, { name: "twice", surql: "fn::doubled(n)" }])
expect Translate.render([Surreal.library], TranslateTest.describe1(samples, |s| feverish_fn.call2(s.d, s.n)), [before], Translate.variable) == Ok("fn::feverish($before.d, $before.n)")
expect where_(TranslateTest.describe1(samples, |s| badly_named_fn.call1(s.n) > 0)) == Err(Unsupported("`Doubled` is not a database function name; use `[a-z_][a-z0-9_]*`"))
expect where_(TranslateTest.describe1(samples, |s| Surreal.db_fn(s.text, doubled).call1(s.n) > 0)) == Err(Unsupported("a database function is a top-level constant made with Surreal.db_fn"))
expect where_(TranslateTest.describe1(samples, |s| Surreal.db_fn("plus_m", |n| n + s.m).call1(s.n) > 0)) == Err(Unsupported("the database function `fn::plus_m` captures values; a database function is a top-level function"))

# Time series: the key `[series, time]` is `record::id(id)`, and its parts are
# `[0]` and `[1]`.
Reading : { id : Surreal.TimeKey(Surreal.Id(Customer)), level : I64 }

Probe : { id : Surreal.TimeKey({ site : Str, sensor : I64 }), level : I64 }

readings : List(Reading)
readings = []

probes : List(Probe)
probes = []

expect where_(TranslateTest.describe1(readings, |r| r.id.time() < new_year)) == Ok("record::id(id)[1] < d'2020-01-01T00:00:00Z'")
expect where_(TranslateTest.describe1(readings, |r| r.id.series() == ada_id)) == Ok("record::id(id)[0] = customer:⟨ada⟩")
expect Translate.render([Surreal.library], TranslateTest.describe1(readings, |r| r.id.time() < new_year), [before], Translate.variable) == Ok("record::id($before.id)[1] < d'2020-01-01T00:00:00Z'")
expect where_(TranslateTest.describe1(probes, |p| p.id.series().site == "north")) == Ok("record::id(id)[0].site = 'north'")
expect selected(TranslateTest.describe1(readings, |r| { key: r.id, hour: Surreal.Time.hour(r.id.time()) })) == Ok([{ name: "hour", surql: "time::hour(record::id(id)[1])" }, { name: "key", surql: "record::id(id)" }])
expect where_(TranslateTest.describe1(readings, |r| Surreal.time_key(ada_id, new_year).time() == r.id.time())) == Ok("[customer:⟨ada⟩, d'2020-01-01T00:00:00Z'][1] = record::id(id)[1]")

# `Time.floor`, `ceil` and `round` are Mirrors: spans count from 1970, a week
# starts on a Thursday, a half goes up also before 1970, and a span of zero
# keeps the time. Each case was compared with SurrealDB 3.3.4.
floor_of : Str, Surreal.Duration -> Surreal.Datetime
floor_of = |text, span| Surreal.Time.floor(moment(text), span)

ceil_of : Str, Surreal.Duration -> Surreal.Datetime
ceil_of = |text, span| Surreal.Time.ceil(moment(text), span)

round_of : Str, Surreal.Duration -> Surreal.Datetime
round_of = |text, span| Surreal.Time.round(moment(text), span)

expect floor_of("2026-03-04T05:06:07Z", Surreal.Time.weeks(1)) == moment("2026-02-26T00:00:00Z")
expect floor_of("2026-03-04T05:06:07Z", Surreal.Time.hours(7)) == moment("2026-03-04T03:00:00Z")
expect floor_of("1969-12-31T23:30:00Z", Surreal.Time.hours(1)) == moment("1969-12-31T23:00:00Z")
expect floor_of("1965-03-04T05:06:07Z", Surreal.Time.secs(13)) == moment("1965-03-04T05:06:01Z")
expect floor_of("2026-03-04T05:06:07.5Z", Surreal.Time.nanos(0)) == moment("2026-03-04T05:06:07.5Z")
expect ceil_of("2026-03-04T05:00:00Z", Surreal.Time.hours(1)) == moment("2026-03-04T05:00:00Z")
expect ceil_of("2026-03-04T05:00:00.5Z", Surreal.Time.hours(1)) == moment("2026-03-04T06:00:00Z")
expect ceil_of("1969-12-31T23:30:00Z", Surreal.Time.hours(7)) == moment("1970-01-01T00:00:00Z")
expect ceil_of("1965-03-04T05:06:07Z", Surreal.Time.secs(13)) == moment("1965-03-04T05:06:14Z")
expect round_of("2026-03-04T05:30:00Z", Surreal.Time.hours(1)) == moment("2026-03-04T06:00:00Z")
expect round_of("2026-03-04T05:29:59.999999999Z", Surreal.Time.hours(1)) == moment("2026-03-04T05:00:00Z")
expect round_of("1969-12-31T22:30:00Z", Surreal.Time.hours(1)) == moment("1969-12-31T23:00:00Z")
expect round_of("1969-12-28T12:00:00Z", Surreal.Time.weeks(1)) == moment("1970-01-01T00:00:00Z")
expect round_of("1969-12-31T23:59:59.999999998Z", Surreal.Time.nanos(3)) == moment("1969-12-31T23:59:59.999999997Z")
expect round_of("2026-03-04T05:06:07Z", Surreal.Time.nanos(0)) == moment("2026-03-04T05:06:07Z")

# ------------------------------------------------------------ geometry

Site : { id : Str, location : Surreal.Point, area : Surreal.Polygon, path : Surreal.Line, near ?: Surreal.Point }

sites : List(Site)
sites = []

Here : { here : Surreal.Point, area : Surreal.Polygon }

heres : List(Here)
heres = []

with_params : Code.Graph -> Try(Str, Ql.Error)
with_params = |graph| Translate.render([Surreal.library], graph, [Translate.Binding.Params, row], Translate.variable)

oslo : Surreal.Point
oslo = Surreal.point(10.75, 59.91)

# A geometry of a row or a parameter is the value itself, and `to_geometry()` keeps it.
expect with_params(TranslateTest.describe2(heres, sites, |p, s| Surreal.Geo.inside(s.location.to_geometry(), p.area.to_geometry()))) == Ok("location INSIDE $area")
expect with_params(TranslateTest.describe2(heres, sites, |p, s| Surreal.Geo.contains(s.area.to_geometry(), p.here.to_geometry()))) == Ok("area CONTAINS $here")
expect where_(TranslateTest.describe1(sites, |s| Surreal.Geo.outside(s.path.to_geometry(), s.area.to_geometry()))) == Ok("path OUTSIDE area")
expect where_(TranslateTest.describe1(sites, |s| Surreal.Geo.intersects(s.path.to_geometry(), s.area.to_geometry()) and s.id != "x")) == Ok("(path INTERSECTS area) AND (record::id(id) != 'x')")
expect with_params(TranslateTest.describe2(heres, sites, |p, s| Surreal.Geo.distance(s.location, p.here) < 50000)) == Ok("geo::distance(location, $here) < 50000f")
# A point of any numbers is a cast of its pair, in parentheses as an operand.
expect where_(TranslateTest.describe1(sites, |s| Surreal.Geo.distance(s.location, Surreal.point(s.location.lon() + 1, 1.5)) < 10)) == Ok("geo::distance(location, <point> [location.coordinates[0] + 1f, 1.5f]) < 10f")
expect where_(TranslateTest.describe1(sites, |s| Surreal.Geo.distance(s.location, oslo) < 10)) == Ok("geo::distance(location, <point> [10.75f, 59.91f]) < 10f")
expect where_(TranslateTest.describe1(sites, |s| Surreal.Geo.inside(Surreal.point(1, 2).to_geometry(), s.area.to_geometry()))) == Ok("(<point> [1f, 2f]) INSIDE area")
expect where_(TranslateTest.describe1(sites, |s| Surreal.point(1, 2).lat() < s.location.lat())) == Ok("(<point> [1f, 2f]).coordinates[1] < location.coordinates[1]")
# `lon` and `lat` are the coordinates of the GeoJSON point.
expect selected(TranslateTest.describe1(sites, |s| { id: s.id, lat: s.location.lat(), lon: s.location.lon() })) == Ok([{ name: "id", surql: "record::id(id)" }, { name: "lat", surql: "location.coordinates[1]" }, { name: "lon", surql: "location.coordinates[0]" }])
expect where_(
	TranslateTest.describe1(
		sites,
		|s| match s.?near {
			Ok(n) => n.lat() > 1
			Err(_) => Bool.False
		},
	),
) == Ok("(IF near IS NONE THEN false ELSE near.coordinates[1] > 1f END)")
# The `geo::` functions are one call each.
expect selected(TranslateTest.describe1(sites, |s| { a: Surreal.Geo.area(s.area.to_geometry()), b: Surreal.Geo.bearing(s.location, oslo), c: Surreal.Geo.centroid(s.path.to_geometry()), h: Surreal.Geo.hash_encode(s.location, 5), d: Surreal.Geo.hash_decode(s.id), v: Surreal.Geo.is_valid(s.area.to_geometry()) })) == Ok([{ name: "a", surql: "geo::area(area)" }, { name: "b", surql: "geo::bearing(location, <point> [10.75f, 59.91f])" }, { name: "c", surql: "geo::centroid(path)" }, { name: "d", surql: "geo::hash::decode(record::id(id))" }, { name: "h", surql: "geo::hash::encode(location, 5)" }, { name: "v", surql: "geo::is_valid(area)" }])
expect where_(TranslateTest.describe1(sites, |s| Surreal.Geo.distance(Surreal.Geo.centroid(s.area.to_geometry()), s.location) < 1)) == Ok("geo::distance(geo::centroid(area), location) < 1f")

# A geometry other than a point has no SurrealQL literal: it is a parameter.
square : Surreal.Polygon
square = Surreal.Polygon.({ exterior: [Surreal.point(0, 0), Surreal.point(1, 0), Surreal.point(1, 1), Surreal.point(0, 0)], holes: [] })

expect where_(TranslateTest.describe1(sites, |s| Surreal.Geo.inside(s.location.to_geometry(), square.to_geometry()))) == Err(Unsupported("a `Polygon` in a clause has no SurrealQL form; pass a geometry as a parameter with `filter_by` and `prepare`"))
expect where_(TranslateTest.describe1(sites, |s| Surreal.Geo.intersects(s.area.to_geometry(), Surreal.Line.([s.location, oslo]).to_geometry()))) == Err(Unsupported("a `Line` in a clause has no SurrealQL form; pass a geometry as a parameter with `filter_by` and `prepare`"))

# A captured geometry is refused with the same advice.
site_table : Surreal.Table(Site)
site_table = Surreal.table("site")

near_to : Surreal.Point -> Try(Surreal.Prepared(List(Site)), Ql.Error)
near_to = |here| Surreal.bind_captured(Surreal.select_where(site_table, |s| Surreal.Geo.distance(s.location, here) < 10))

expect near_to(oslo).map_ok(|_| "bound") == Err(Unsupported("a `Point` in a clause has no SurrealQL form; pass a geometry as a parameter with `filter_by` and `prepare`"))

# ------------------------------------------------------------------ vectors

Embedded : { id : Str, vec : List(F64), other : List(F64) }

embeddeds : List(Embedded)
embeddeds = []

embedded_table : Surreal.Table(Embedded)
embedded_table = Surreal.table("embedded")

# Each `Vector` function is its `vector::` function, over fields, a list
# literal and a parameter.
expect where_(TranslateTest.describe1(embeddeds, |e| Surreal.Vector.similarity_cosine(e.vec, e.other) > 0.5)) == Ok("vector::similarity::cosine(vec, other) > 0.5f")
expect where_(TranslateTest.describe1(embeddeds, |e| Surreal.Vector.distance_euclidean(e.vec, [1, 0]) < Surreal.Vector.distance_manhattan(e.vec, [0, 1]))) == Ok("vector::distance::euclidean(vec, [1f, 0f]) < vector::distance::manhattan(vec, [0f, 1f])")
expect with_params(TranslateTest.describe2([{ probe: [1.0, 2.0] }], embeddeds, |p, e| Surreal.Vector.distance_chebyshev(e.vec, p.probe) + Surreal.Vector.dot(e.vec, p.probe) < Surreal.Vector.magnitude(e.other))) == Ok("(vector::distance::chebyshev(vec, $probe) + vector::dot(vec, $probe)) < vector::magnitude(other)")

## A probe that the program reads at run time, captured.
similar_to : List(F64) -> Try(Surreal.Prepared(List(Embedded)), Ql.Error)
similar_to = |probe| Surreal.bind_captured(Surreal.select_where(embedded_table, |e| Surreal.Vector.similarity_cosine(e.vec, probe) > 0.9))

expect similar_to([0.5, 0.5]).map_ok(|p| p.request()) == Ok("LET $_1 = [0.5f, 0.5f];\nSELECT record::id(id) AS id, other, vec FROM embedded WHERE vector::similarity::cosine(vec, $_1) > 0.9f;")

# The Roc meanings: the sums run from the first element, as SurrealDB's
# do, so the results are the server's to the bit (`search.roc`,
# `vector_measures`).
expect Surreal.Vector.similarity_cosine([0.1, 0.2, 0.3], [0.3, 0.7, 0.11]) == 0.7050736581150044
expect Surreal.Vector.distance_euclidean([0.1, 0.2, 0.3], [0.3, 0.7, 0.11]) == 0.5710516614107694
expect Surreal.Vector.distance_manhattan([0.1, 0.2, 0.3], [0.3, 0.7, 0.11]) == 0.8899999999999999
expect Surreal.Vector.distance_chebyshev([0.1, 0.2, 0.3], [0.3, 0.7, 0.11]) == 0.49999999999999994
expect Surreal.Vector.dot([0.1, 0.2, 0.3], [0.3, 0.7, 0.11]) == 0.20299999999999999
expect Surreal.Vector.magnitude([0.1, 0.2, 0.3]) == 0.37416573867739417
expect Surreal.Vector.similarity_cosine([0, 0], [1, 1]).is_nan()

# A literal of a type with its own `from_numeral` reifies as a `Numeral`
# literal, which the translator writes as an exact `dec` literal.
Written := [Written(Numeral)].{
	from_numeral : Numeral -> Try(Written, [InvalidNumeral(Str)])
	from_numeral = |n| Ok(Written(n))
}

written : Written -> Code.Lit
written = |value| match value {
	Written(n) => Numeral(n)
}

expect Translate.literal(written(300.Written)) == Ok("300dec")
expect Translate.literal(written(0.050.Written)) == Ok("0.050dec")
expect Translate.literal(written(12345678901234567890123.25.Written)) == Ok("12345678901234567890123.25dec")

# The edge cases of the exact decimal text. Each one Dec holds reads back as
# the `Dec` that `Dec.from_numeral` makes of its numeral.
numeral : Written -> Numeral
numeral = |value| match value {
	Written(n) => n
}

## Whether the decimal text of `value` parses as the `Dec` its numeral converts to.
reads_as_dec : Written -> Bool
reads_as_dec = |value| {
	n = numeral(value)
	match (Dec.from_str(Translate.numeral_text(n)), Dec.from_numeral(n)) {
		(Ok(text), Ok(converted)) => text == converted
		_ => Bool.False
	}
}

negative : Written
negative = -2.5

negative_whole : Written
negative_whole = -7

# Zero, with no point and with one.
expect Translate.literal(written(0.Written)) == Ok("0dec")
expect reads_as_dec(0.Written)
expect Translate.literal(written(0.0.Written)) == Ok("0.0dec")
expect reads_as_dec(0.0.Written)
# Leading zeros after the point.
expect reads_as_dec(0.050.Written)
expect Translate.literal(written(0.000001.Written)) == Ok("0.000001dec")
expect reads_as_dec(0.000001.Written)
# Negative numbers.
expect Translate.literal(written(negative)) == Ok("-2.5dec")
expect reads_as_dec(negative)
expect Translate.literal(written(negative_whole)) == Ok("-7dec")
expect reads_as_dec(negative_whole)
# Digit bytes that carry in base 256, before the point and after it.
expect Translate.literal(written(255.Written)) == Ok("255dec")
expect reads_as_dec(255.Written)
expect Translate.literal(written(256.Written)) == Ok("256dec")
expect reads_as_dec(256.Written)
expect Translate.literal(written(65_535.Written)) == Ok("65535dec")
expect reads_as_dec(65_535.Written)
expect Translate.literal(written(65_536.Written)) == Ok("65536dec")
expect reads_as_dec(65_536.Written)
expect Translate.literal(written(0.256.Written)) == Ok("0.256dec")
expect reads_as_dec(0.256.Written)
# More than 20 digits: one Dec holds, and two it does not.
expect Translate.literal(written(100.000000000000000001.Written)) == Ok("100.000000000000000001dec")
expect reads_as_dec(100.000000000000000001.Written)
expect Translate.literal(written(340282366920938463463374607431768211456.Written)) == Ok("340282366920938463463374607431768211456dec")
expect Translate.literal(written(0.0000000000000000000000000001.Written)) == Ok("0.0000000000000000000000000001dec")
# Integers with no point.
expect reads_as_dec(300.Written)
expect Translate.literal(written(18446744073709551616.Written)) == Ok("18446744073709551616dec")
expect reads_as_dec(18446744073709551616.Written)
