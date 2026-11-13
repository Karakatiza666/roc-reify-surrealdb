app [] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.5.0/B5U2mPsWTtuxfCRMzqQxio2ecDv7CAzCoyEMENMh4FNF.tar.zst",
	internal: "../src/internal.roc",
}

import internal.Surreal
import internal.Schema
import internal.Types

# Tests of the schema builder and `Surreal.schema` on a small domain. They sit
# here because a row type comes from a reified table, and only `Surreal`
# makes one. Nothing outside this file imports it.
SchemaTest :: {}

Address : { city : Str, zip ?: Str }

Customer := { id : Str, name : Str, email : Str, address : Address, tags : List(Str), referrer ?: Surreal.Link(Customer), age : U8 }

Product : { id : Str, title : Str, label : Str, price : Dec, stock : I32 }

Item : { product : Surreal.Link(Product), qty : I64 }

Payment : [Cash, Card({ last4 : Str }), Invoice({ contact : Surreal.Link(Customer), due : Str })]

Order : {
	id : Str,
	customer : Surreal.Link(Customer),
	items : List(Item),
	payment : Payment,
	gift ?: { to : Surreal.Link(Customer), note : Str },
	wishlist : List(Surreal.Link(Product)),
	total : Dec,
	created : Surreal.Datetime,
}

Purchase : { id : Str, from : Surreal.Link(Customer), to : Surreal.Link(Product), quantity : I64 }

customers : Surreal.Table(Customer)
customers = Surreal.table("customer")

products : Surreal.Table(Product)
products = Surreal.table("product")

orders : Surreal.Table(Order)
orders = Surreal.table("order")

purchased : Surreal.Table(Purchase)
purchased = Surreal.relation("purchased", customers, products)

# The constraints are Roc functions: the schema reifies them, and Roc runs them.
positive_qty : Item -> Bool
positive_qty = |i| i.qty > 0

total_matches_items : Order -> Bool
total_matches_items = |o| o.items.is_empty() or o.total > 0

expect positive_qty({ product: products.link("pen"), qty: 2 })
expect !positive_qty({ product: products.link("pen"), qty: 0 })

customer_def : Surreal.Defined
customer_def =
	customers.define()
		.unique(|c| c.email)
		.unique(|c| { city: c.address.city, name: c.name })
		.assert(|c| c.email, |e| e.contains("@"))
		.assert(
			|c| c.address.?zip,
			|z| match z {
				Ok(s) => s.starts_with("7")
				Err(_) => Bool.True
			},
		)
		.assert_each(|c| c.tags, |t| t != "")
		.check("named", |c| c.name != "")
		.default(|c| c.tags, ["new"])
		.done()

product_def : Surreal.Defined
product_def =
	products.define()
		.default(|p| p.stock, 0)
		.readonly(|p| p.title)
		.computed(|p| p.label, |p| p.title.concat("!"))
		.done()

order_def : Surreal.Defined
order_def =
	orders.define()
		.assert_each(|o| o.items, positive_qty)
		.check("total matches items", total_matches_items)
		.check("positive total", |o| o.total >= 0)
		.assert(
			|o| o.payment,
			|p| match p {
				Invoice(i) => i.due != ""
				_ => Bool.True
			},
		)
		.on_delete(products, Reject)
		.on_delete(customers, Cascade)
		.on_delete_at(|o| o.wishlist, Unset)
		.created_now(|o| o.created)
		.index(|o| o.total)
		.comment(|o| o.total, "in euros")
		.done()

purchased_def : Surreal.Defined
purchased_def =
	purchased.define()
		.check("positive quantity", |e| e.quantity > 0)
		.check("not a gift to self", |e| e.quantity < 100 or e.from.get().name != "")
		.unique(|e| { from: e.from, to: e.to })
		.done()

script_of : List(Surreal.Defined) -> List(Str)
script_of = |defs| match Surreal.schema(defs) {
	Ok(text) => text.split_on("\n")
	Err(BadSchema(why)) => ["BadSchema: ${why}"]
	Err(Unsupported(why)) => ["Unsupported: ${why}"]
	Err(other) => ["Session: ${Str.inspect(other)}"]
}

# ------------------------------------------------- the whole script, in order

# Tables, then fields, then indexes, then row checks, then delete events,
# so no statement names a table defined after it.
expect script_of([customer_def, product_def, order_def, purchased_def]) == [
	"DEFINE TABLE OVERWRITE customer SCHEMAFULL;",
	"DEFINE TABLE OVERWRITE product SCHEMAFULL;",
	"DEFINE TABLE OVERWRITE order SCHEMAFULL;",
	"DEFINE TABLE OVERWRITE purchased TYPE RELATION IN customer OUT product ENFORCED SCHEMAFULL;",
	"DEFINE FIELD OVERWRITE address ON customer TYPE object;",
	"DEFINE FIELD OVERWRITE address.city ON customer TYPE string;",
	"DEFINE FIELD OVERWRITE address.zip ON customer TYPE option<string> ASSERT (IF $value IS NONE THEN true ELSE string::starts_with($value, '7') END);",
	"DEFINE FIELD OVERWRITE age ON customer TYPE u8;",
	"DEFINE FIELD OVERWRITE email ON customer TYPE string ASSERT string::contains($value, '@');",
	"DEFINE FIELD OVERWRITE name ON customer TYPE string ASSERT $value != '';",
	"DEFINE FIELD OVERWRITE referrer ON customer TYPE option<record<customer>> REFERENCE ON DELETE REJECT ASSERT ($value = NONE OR (record::exists($value)));",
	"DEFINE FIELD OVERWRITE tags ON customer TYPE array<string> DEFAULT ['new'] ASSERT $value.all(|$item| $item != '');",
	"DEFINE FIELD OVERWRITE label ON product TYPE string VALUE $this.title + '!';",
	"DEFINE FIELD OVERWRITE price ON product TYPE decimal;",
	"DEFINE FIELD OVERWRITE stock ON product TYPE i32 DEFAULT 0;",
	"DEFINE FIELD OVERWRITE title ON product TYPE string READONLY;",
	"DEFINE FIELD OVERWRITE created ON order TYPE datetime VALUE time::now() READONLY;",
	"DEFINE FIELD OVERWRITE customer ON order TYPE record<customer> REFERENCE ON DELETE CASCADE ASSERT record::exists($value);",
	"DEFINE FIELD OVERWRITE gift ON order TYPE option<object>;",
	"DEFINE FIELD OVERWRITE gift.note ON order TYPE string;",
	"DEFINE FIELD OVERWRITE gift.to ON order TYPE record<customer> ASSERT record::exists($value);",
	"DEFINE FIELD OVERWRITE items ON order TYPE array<{ product: record<product>, qty: int }> ASSERT ($value.len() = 0) OR ($this.total > 0.0dec);",
	"DEFINE FIELD OVERWRITE items[*].product ON order ASSERT record::exists($value);",
	"DEFINE FIELD OVERWRITE items[*].qty ON order ASSERT $value > 0;",
	"DEFINE FIELD OVERWRITE payment ON order TYPE { kind: \"Card\", last4: string } | \"Cash\" | { kind: \"Invoice\", contact: record<customer>, due: string } ASSERT ((IF $value.kind = 'Invoice' THEN record::exists($value.contact) ELSE true END)) AND ((IF $value.kind = 'Invoice' THEN $value.due != '' ELSE true END));",
	"DEFINE FIELD OVERWRITE total ON order TYPE decimal ASSERT $value >= 0.0dec COMMENT 'in euros';",
	"DEFINE FIELD OVERWRITE wishlist ON order TYPE array<record<product>> REFERENCE ON DELETE UNSET ASSERT $value.all(|$e1| record::exists($e1));",
	"DEFINE FIELD OVERWRITE quantity ON purchased TYPE int ASSERT $value > 0;",
	"DEFINE INDEX OVERWRITE customer_email_unique ON customer FIELDS email UNIQUE;",
	"DEFINE INDEX OVERWRITE customer_address_city_name_unique ON customer FIELDS address.city, name UNIQUE;",
	"DEFINE INDEX OVERWRITE order_total_index ON order FIELDS total;",
	"DEFINE INDEX OVERWRITE order_gift_to_link ON order FIELDS gift.to;",
	"DEFINE INDEX OVERWRITE order_items_product_link ON order FIELDS items[*].product;",
	"DEFINE INDEX OVERWRITE purchased_in_out_unique ON purchased FIELDS in, out UNIQUE;",
	"DEFINE EVENT OVERWRITE purchased_check_not_a_gift_to_self ON purchased WHEN $event IN ['CREATE', 'UPDATE'] THEN { IF !(($after.quantity < 100) OR ($after.in.name != '')) { THROW 'purchased: not a gift to self' } };",
	"DEFINE EVENT OVERWRITE order_gift_to_on_delete ON customer WHEN $event = 'DELETE' THEN { DELETE order WHERE gift.to = $before.id };",
	"DEFINE EVENT OVERWRITE order_items_product_on_delete ON product WHEN $event = 'DELETE' THEN { IF (SELECT VALUE id FROM order WHERE $before.id IN items[*].product LIMIT 1) != [] { THROW <string>$before.id + ' is referenced by order.items[*].product' } };",
	"DEFINE EVENT OVERWRITE order_payment_Invoice_contact_on_delete ON customer WHEN $event = 'DELETE' THEN { DELETE order WHERE (payment.kind = 'Invoice' AND payment.contact = $before.id) };",
]

## The statements of a script that contain `part`.
lines_with : List(Surreal.Defined), Str -> List(Str)
lines_with = |defs, part| script_of(defs).keep_if(|line| line.contains(part))

problem_of : List(Surreal.Defined) -> Str
problem_of = |defs| match Surreal.schema(defs) {
	Ok(_) => "ok"
	Err(BadSchema(why)) => "BadSchema: ${why}"
	Err(Unsupported(why)) => "Unsupported: ${why}"
	Err(other) => "Session: ${Str.inspect(other)}"
}

# `Rand` gives a new value on every call: a default and a computed field may use it, a constraint may not.
expect lines_with([products.define().default_by(|p| p.label, |_| Surreal.Rand.ulid()).done()], "label ON product") == ["DEFINE FIELD OVERWRITE label ON product TYPE string DEFAULT rand::ulid();"]
expect lines_with([products.define().default_by(|p| p.label, |p| p.title.concat(Surreal.Rand.int(1, p.stock.to_i64()).to_str())).done()], "label ON product") == ["DEFINE FIELD OVERWRITE label ON product TYPE string DEFAULT $this.title + <string>rand::int(1, $this.stock);"]
expect lines_with([products.define().computed(|p| p.label, |_| Surreal.Rand.uuid()).done()], "label ON product") == ["DEFINE FIELD OVERWRITE label ON product TYPE string VALUE <string>rand::uuid();"]
expect problem_of([products.define().assert(|p| p.stock, |n| n.to_i64() > Surreal.Rand.int(0, 5)).done()]) == "Unsupported: `Surreal.Rand.int` gives a new value on every call: use it in a default, a computed field or an update"
expect problem_of([products.define().check("lucky", |p| p.stock.to_i64() > Surreal.Rand.int(0, 5)).done()]) == "Unsupported: `Surreal.Rand.int` gives a new value on every call: use it in a default, a computed field or an update"
expect problem_of([products.define().default(|p| p.stock, 0).default_by(|p| p.stock, |_| 1).done()]) == "BadSchema: `stock` has two defaults"

# A key that the server makes: a default of `id` is the definition of the
# key, so a create with no key gets one (`Table.create_new`). With none,
# the key has no definition, and SurrealDB makes a random key.
expect lines_with([products.define().default_by(|p| p.id, |_| Surreal.Rand.ulid()).done()], "OVERWRITE id ON product") == ["DEFINE FIELD OVERWRITE id ON product TYPE string DEFAULT rand::ulid();"]
expect lines_with([products.define().default_by(|p| p.id, |_| Surreal.Rand.uuid()).done()], "OVERWRITE id ON product") == ["DEFINE FIELD OVERWRITE id ON product TYPE string DEFAULT <string>rand::uuid();"]
expect lines_with([products.define().default_by(|p| p.id, |p| p.title).done()], "OVERWRITE id ON product") == ["DEFINE FIELD OVERWRITE id ON product TYPE string DEFAULT $this.title;"]
expect lines_with([products.define().default(|p| p.id, "main").done()], "OVERWRITE id ON product") == ["DEFINE FIELD OVERWRITE id ON product TYPE string DEFAULT 'main';"]
expect lines_with([products.define().done()], "OVERWRITE id ON product") == []
expect problem_of([packs.define().default_by(|p| p.id, |_| Surreal.Rand.ulid()).done()]) == "BadSchema: `id` has two defaults"

# ------------------------------------------------------- where a check goes

# One top-level field, read at any depth: that field's ASSERT, over `$value`.
expect lines_with([customers.define().check("city", |c| c.address.city != "").done()], "ASSERT") == [
	"DEFINE FIELD OVERWRITE address ON customer TYPE object ASSERT $value.city != '';",
	"DEFINE FIELD OVERWRITE referrer ON customer TYPE option<record<customer>> REFERENCE ON DELETE REJECT ASSERT ($value = NONE OR (record::exists($value)));",
]

# Through a link, still one field of this row.
expect lines_with([customers.define().done(), products.define().done(), orders.define().check("adult buyer", |o| o.customer.get().age >= 18).done()], "ON order TYPE record<customer>") == [
	"DEFINE FIELD OVERWRITE customer ON order TYPE record<customer> REFERENCE ON DELETE REJECT ASSERT (record::exists($value)) AND ($value.age >= 18);",
	"DEFINE FIELD OVERWRITE gift.to ON order TYPE record<customer> ASSERT record::exists($value);",
]

# Two fields: the `ASSERT` of the first of them, over `$value` and `$this`.
expect lines_with([customers.define().check("name in email", |c| c.email.contains(c.name)).done()], "$this") == [
	"DEFINE FIELD OVERWRITE email ON customer TYPE string ASSERT string::contains($value, $this.name);",
]

# A read-only field holds no check (its assert does not run when it does not change): the next one does.
expect lines_with([customers.define().readonly(|c| c.email).check("name in email", |c| c.email.contains(c.name)).done()], "$this") == [
	"DEFINE FIELD OVERWRITE name ON customer TYPE string ASSERT string::contains($this.email, $value);",
]

# With every field read-only, or with a field permission, it is an event over `$after`.
expect lines_with([customers.define().readonly(|c| c.email).readonly(|c| c.name).check("name in email", |c| c.email.contains(c.name)).done()], "_check_") == [
	"DEFINE EVENT OVERWRITE customer_check_name_in_email ON customer WHEN $event IN ['CREATE', 'UPDATE'] THEN { IF !(string::contains($after.email, $after.name)) { THROW 'customer: name in email' } };",
]
expect lines_with([customers.define().deny_field(|c| c.email, [Update]).deny_field(|c| c.name, [Update]).check("name in email", |c| c.email.contains(c.name)).done()], "_check_") == [
	"DEFINE EVENT OVERWRITE customer_check_name_in_email ON customer WHEN $event IN ['CREATE', 'UPDATE'] THEN { IF !(string::contains($after.email, $after.name)) { THROW 'customer: name in email' } };",
]

# An optional field holds no check (its assert does not run when it is NONE, verified): the required field does.
expect lines_with([customer_def, product_def, orders.define().check("gift needs a total", |o| o.?gift.is_err() or o.total > 0).done()], "ON order TYPE decimal") == [
	"DEFINE FIELD OVERWRITE total ON order TYPE decimal ASSERT ($this.gift IS NONE) OR ($value > 0.0dec);",
]

# A check that reads the key reads a field with no definition: an event.
expect lines_with([customers.define().check("key is name", |c| c.id != c.name).done()], "_check_") == [
	"DEFINE EVENT OVERWRITE customer_check_key_is_name ON customer WHEN $event IN ['CREATE', 'UPDATE'] THEN { IF !(record::id($after.id) != $after.name) { THROW 'customer: key is name' } };",
]

# The record key is not a field definition, so a check on it is an event.
expect lines_with([customers.define().check("key", |c| c.id != "root").done()], "_check_") == [
	"DEFINE EVENT OVERWRITE customer_check_key ON customer WHEN $event IN ['CREATE', 'UPDATE'] THEN { IF !(record::id($after.id) != 'root') { THROW 'customer: key' } };",
]

# No field: always or never true.
expect problem_of([customers.define().check("always", |_| Bool.True).done()]) == "BadSchema: the check `always` reads no field, so it is always or never true"

# An element check that reads two element fields goes on the list.
expect lines_with([customers.define().done(), products.define().done(), orders.define().assert_each(|o| o.items, |i| i.qty > 0 and i.product.get().stock > 0).done()], "ON order TYPE array<{") == [
	"DEFINE FIELD OVERWRITE items ON order TYPE array<{ product: record<product>, qty: int }> ASSERT $value.all(|$item| ($item.qty > 0) AND ($item.product.stock > 0));",
]

# ------------------------------------------------------ paths that are refused

expect problem_of([orders.define().assert(|o| o.items.map(|i| i.qty), |qs| qs.len() > 0).done()]) == "Unsupported: `assert` reads one field; for each element of a list use `assert_each`"
expect problem_of([customers.define().assert(|c| c.name.concat("x"), |n| n != "").done()]) == "Unsupported: a field path reads fields only; this one calls `Str.concat`"
expect problem_of([customers.define().assert(|c| c.id, |k| k != "").done()]) == "BadSchema: `customer.id` has no field definition to put this on; the record key and an edge's ends are SurrealDB's own"
expect problem_of([customers.define().default(|c| c.tags, []).default(|c| c.tags, ["a"]).done()]) == "BadSchema: `tags` has two defaults"
expect problem_of([customers.define().done(), products.define().done(), orders.define().on_delete(orders, Cascade).done()]) == "BadSchema: no link in `order` points at table `order`"
expect problem_of([customers.define().done(), products.define().done(), orders.define().on_delete_at(|o| o.total, Cascade).done()]) == "BadSchema: `order.total` is not a link"
expect problem_of([customers.define().done(), products.define().done(), orders.define().on_delete(customers, Unset).done()]) == "BadSchema: `order.customer` is required, so a delete cannot unset it; make it optional (`?:`) or use Reject, Cascade or Ignore"
expect problem_of([customers.define().done(), products.define().done(), orders.define().on_delete_at(|o| o.customer, Cascade).on_delete(customers, Unset).done()]) == "BadSchema: `order.gift.to`: the link is a required field, so it cannot be unset; make it optional (`?:`) or use Reject, Cascade or Ignore"

# ------------------------------------------------- one link, every shape

P : { id : Str, title : Str }

Shapes : {
	id : Str,
	root : Surreal.Link(P),
	maybe ?: Surreal.Link(P),
	many : List(Surreal.Link(P)),
	obj : { l ?: Surreal.Link(P), n : I64 },
	rows : List({ l : Surreal.Link(P), n : I64 }),
	arm : [Empty, Has({ l : Surreal.Link(P) })],
	key : Surreal.Id(P),
}

ps : Surreal.Table(P)
ps = Surreal.table("p")

shapes : Surreal.Table(Shapes)
shapes = Surreal.table("h")

## The statements a policy gives the links of `h`.
policy_lines : Surreal.Defined -> List(Str)
policy_lines = |holder| script_of([ps.define().done(), holder]).keep_if(|line| line.contains("REFERENCE") or line.contains("ON p WHEN") or line.contains("_link"))

shapes_with : [Reject, Unset, Cascade, Ignore] -> List(Str)
shapes_with = |policy| policy_lines(shapes.define().on_delete(ps, policy).done())

Unsettable : { id : Str, maybe ?: Surreal.Link(P), many : List(Surreal.Link(P)), obj : { l ?: Surreal.Link(P), n : I64 }, rows : List({ l : Surreal.Link(P), n : I64 }) }

unsettable : Surreal.Table(Unsettable)
unsettable = Surreal.table("h")

# The sites `Schema` walks are the ones `Types.link_sites` lists, with the same shapes.
expect {
	source = Surreal.Def.source(shapes.define())
	mine = match Schema.sites(source) {
		Ok(sites) => sites.map(|s| (Schema.site_path(s.hops), Schema.shape(s)))
		Err(_) => []
	}
	theirs = Types.link_sites(source.row_ty).map(|s| (s.path, s.shape))
	mine == theirs and mine.len() == 7
}

expect shapes_with(Reject) == [
	"DEFINE FIELD OVERWRITE key ON h TYPE record<p> REFERENCE ON DELETE REJECT ASSERT record::exists($value);",
	"DEFINE FIELD OVERWRITE many ON h TYPE array<record<p>> REFERENCE ON DELETE REJECT ASSERT $value.all(|$e1| record::exists($e1));",
	"DEFINE FIELD OVERWRITE maybe ON h TYPE option<record<p>> REFERENCE ON DELETE REJECT ASSERT ($value = NONE OR (record::exists($value)));",
	"DEFINE FIELD OVERWRITE root ON h TYPE record<p> REFERENCE ON DELETE REJECT ASSERT record::exists($value);",
	"DEFINE INDEX OVERWRITE h_obj_l_link ON h FIELDS obj.l;",
	"DEFINE INDEX OVERWRITE h_rows_l_link ON h FIELDS rows[*].l;",
	"DEFINE EVENT OVERWRITE h_arm_Has_l_on_delete ON p WHEN $event = 'DELETE' THEN { IF (SELECT VALUE id FROM h WHERE (arm.kind = 'Has' AND arm.l = $before.id) LIMIT 1) != [] { THROW <string>$before.id + ' is referenced by h.arm.l' } };",
	"DEFINE EVENT OVERWRITE h_obj_l_on_delete ON p WHEN $event = 'DELETE' THEN { IF (SELECT VALUE id FROM h WHERE obj.l = $before.id LIMIT 1) != [] { THROW <string>$before.id + ' is referenced by h.obj.l' } };",
	"DEFINE EVENT OVERWRITE h_rows_l_on_delete ON p WHEN $event = 'DELETE' THEN { IF (SELECT VALUE id FROM h WHERE $before.id IN rows[*].l LIMIT 1) != [] { THROW <string>$before.id + ' is referenced by h.rows[*].l' } };",
]

expect shapes_with(Cascade) == [
	"DEFINE FIELD OVERWRITE key ON h TYPE record<p> REFERENCE ON DELETE CASCADE ASSERT record::exists($value);",
	"DEFINE FIELD OVERWRITE many ON h TYPE array<record<p>> REFERENCE ON DELETE CASCADE ASSERT $value.all(|$e1| record::exists($e1));",
	"DEFINE FIELD OVERWRITE maybe ON h TYPE option<record<p>> REFERENCE ON DELETE CASCADE ASSERT ($value = NONE OR (record::exists($value)));",
	"DEFINE FIELD OVERWRITE root ON h TYPE record<p> REFERENCE ON DELETE CASCADE ASSERT record::exists($value);",
	"DEFINE INDEX OVERWRITE h_obj_l_link ON h FIELDS obj.l;",
	"DEFINE INDEX OVERWRITE h_rows_l_link ON h FIELDS rows[*].l;",
	"DEFINE EVENT OVERWRITE h_arm_Has_l_on_delete ON p WHEN $event = 'DELETE' THEN { DELETE h WHERE (arm.kind = 'Has' AND arm.l = $before.id) };",
	"DEFINE EVENT OVERWRITE h_obj_l_on_delete ON p WHEN $event = 'DELETE' THEN { DELETE h WHERE obj.l = $before.id };",
	"DEFINE EVENT OVERWRITE h_rows_l_on_delete ON p WHEN $event = 'DELETE' THEN { DELETE h WHERE $before.id IN rows[*].l };",
]

# Ignore: native `IGNORE` at the root, and no event or index below it.
expect shapes_with(Ignore) == [
	"DEFINE FIELD OVERWRITE key ON h TYPE record<p> REFERENCE ON DELETE IGNORE ASSERT record::exists($value);",
	"DEFINE FIELD OVERWRITE many ON h TYPE array<record<p>> REFERENCE ON DELETE IGNORE ASSERT $value.all(|$e1| record::exists($e1));",
	"DEFINE FIELD OVERWRITE maybe ON h TYPE option<record<p>> REFERENCE ON DELETE IGNORE ASSERT ($value = NONE OR (record::exists($value)));",
	"DEFINE FIELD OVERWRITE root ON h TYPE record<p> REFERENCE ON DELETE IGNORE ASSERT record::exists($value);",
]

# Unset: an optional field is set to NONE; a link, or an object that holds
# one, leaves its list.
expect policy_lines(unsettable.define().on_delete(ps, Unset).done()) == [
	"DEFINE FIELD OVERWRITE many ON h TYPE array<record<p>> REFERENCE ON DELETE UNSET ASSERT $value.all(|$e1| record::exists($e1));",
	"DEFINE FIELD OVERWRITE maybe ON h TYPE option<record<p>> REFERENCE ON DELETE UNSET ASSERT ($value = NONE OR (record::exists($value)));",
	"DEFINE INDEX OVERWRITE h_obj_l_link ON h FIELDS obj.l;",
	"DEFINE INDEX OVERWRITE h_rows_l_link ON h FIELDS rows[*].l;",
	"DEFINE EVENT OVERWRITE h_obj_l_on_delete ON p WHEN $event = 'DELETE' THEN { UPDATE h SET obj.l = NONE WHERE obj.l = $before.id };",
	"DEFINE EVENT OVERWRITE h_rows_l_on_delete ON p WHEN $event = 'DELETE' THEN { UPDATE h SET rows = rows.filter(|$e1| !($e1.l = $before.id)) WHERE $before.id IN rows[*].l };",
]

# Unset is refused where nothing can be unset: a required root, an arm.
expect problem_of([ps.define().done(), shapes.define().on_delete(ps, Unset).done()]) == "BadSchema: `h.arm.l`: an arm of a union cannot be unset; use Reject, Cascade or Ignore"
expect problem_of([ps.define().done(), shapes.define().on_delete(ps, Unset).on_delete_at(|h| h.root, Cascade).done()]) == "BadSchema: `h.arm.l`: an arm of a union cannot be unset; use Reject, Cascade or Ignore"

# `on_delete_at` wins over `on_delete` for its one path.
expect policy_lines(unsettable.define().on_delete(ps, Cascade).on_delete_at(|h| h.rows.map(|r| r.l), Ignore).on_delete_at(|h| h.many, Unset).done()) == [
	"DEFINE FIELD OVERWRITE many ON h TYPE array<record<p>> REFERENCE ON DELETE UNSET ASSERT $value.all(|$e1| record::exists($e1));",
	"DEFINE FIELD OVERWRITE maybe ON h TYPE option<record<p>> REFERENCE ON DELETE CASCADE ASSERT ($value = NONE OR (record::exists($value)));",
	"DEFINE INDEX OVERWRITE h_obj_l_link ON h FIELDS obj.l;",
	"DEFINE EVENT OVERWRITE h_obj_l_on_delete ON p WHEN $event = 'DELETE' THEN { DELETE h WHERE obj.l = $before.id };",
]

# ------------------------------------------------------------------ cycles

A := { id : Str, b : Surreal.Link(B) }

B := { id : Str, a : Surreal.Link(A) }

C := { id : Str, d ?: Surreal.Link(D) }

D := { id : Str, c : Surreal.Link(C) }

Boss := { id : Str, boss : Surreal.Link(Boss) }

a_rows : Surreal.Table(A)
a_rows = Surreal.table("a")

b_rows : Surreal.Table(B)
b_rows = Surreal.table("b")

c_rows : Surreal.Table(C)
c_rows = Surreal.table("c")

d_rows : Surreal.Table(D)
d_rows = Surreal.table("d")

bosses : Surreal.Table(Boss)
bosses = Surreal.table("boss")

expect problem_of([a_rows.define().done(), b_rows.define().done()]) == "BadSchema: required links form a cycle (a.b -> b.a -> a), so no row of it can be written first; make one of them optional (`?:`)"
expect problem_of([bosses.define().done()]) == "BadSchema: required links form a cycle (boss.boss -> boss), so no row of it can be written first; make one of them optional (`?:`)"

# Through an optional field or a union arm a cycle can be filled.
expect problem_of([c_rows.define().done(), d_rows.define().done()]) == "ok"
expect problem_of([customers.define().done()]) == "ok"

# A self-link read through `.?`, in a check over two fields.
not_self_referred : Customer -> Bool
not_self_referred = |c| match c.?referrer {
	Ok(r) => r.get().name != c.name
	Err(_) => Bool.True
}

expect lines_with([customers.define().check("not self-referred", not_self_referred).done()], "$this") == [
	"DEFINE FIELD OVERWRITE name ON customer TYPE string ASSERT (IF $this.referrer IS NONE THEN true ELSE $this.referrer.name != $value END);",
]

# Database functions: one `DEFINE FUNCTION` for each, before the tables. A parameter has the type of a field,
# so a union and a link are written as in a field. A function the body calls is defined too, and once.
settled : Payment, Dec -> Bool
settled = |p, total| match p {
	Cash => Bool.True
	Card(c) => c.last4 != "" and total > 0
	Invoice(_) => Bool.False
}

settled_fn : Surreal.DbFn((Payment, Dec -> Bool))
settled_fn = Surreal.db_fn("settled", settled)

named_by : Surreal.Link(Customer), Str -> Bool
named_by = |c, name| c.get().name == name

named_by_fn : Surreal.DbFn((Surreal.Link(Customer), Str -> Bool))
named_by_fn = Surreal.db_fn("named_by", named_by)

sum_to : I64 -> I64
sum_to = |n| if (n <= 0) 0 else n + sum_to(n - 1)

sum_to_fn : Surreal.DbFn((I64 -> I64))
sum_to_fn = Surreal.db_fn("sum_to", sum_to)

twice_sum : I64 -> I64
twice_sum = |n| sum_to_fn.call1(n) * 2 + sum_to_fn.call1(1)

twice_sum_fn : Surreal.DbFn((I64 -> I64))
twice_sum_fn = Surreal.db_fn("twice_sum", twice_sum)

other_sum_fn : Surreal.DbFn((I64 -> I64))
other_sum_fn = Surreal.db_fn("sum_to", |n| n + 1)

expect sum_to_fn.call1(4) == 10
expect twice_sum_fn.call1(4) == 21
expect settled_fn.call2(Card({ last4: "1" }), 2)
expect lines_with([Surreal.function(|_| settled_fn), customer_def], "FUNCTION") == ["DEFINE FUNCTION OVERWRITE fn::settled($a1: { kind: \"Card\", last4: string } | \"Cash\" | { kind: \"Invoice\", contact: record<customer>, due: string }, $a2: decimal) -> bool { RETURN (IF $a1.kind = 'Card' THEN (IF $a1.last4 = '' THEN false ELSE $a2 > 0.0dec END) ELSE IF $a1 = 'Cash' THEN true ELSE false END) };"]
expect lines_with([Surreal.function(|_| named_by_fn), customer_def], "FUNCTION") == ["DEFINE FUNCTION OVERWRITE fn::named_by($a1: record<customer>, $a2: string) -> bool { RETURN $a1.name = $a2 };"]
expect script_of([customer_def, Surreal.function(|_| twice_sum_fn), Surreal.function(|_| sum_to_fn)]).take_first(3) == [
	"DEFINE FUNCTION OVERWRITE fn::twice_sum($a1: int) -> int { RETURN (fn::sum_to($a1) * 2) + fn::sum_to(1) };",
	"DEFINE FUNCTION OVERWRITE fn::sum_to($a1: int) -> int { RETURN (IF $a1 > 0 THEN $a1 + fn::sum_to($a1 - 1) ELSE 0 END) };",
	"DEFINE TABLE OVERWRITE customer SCHEMAFULL;",
]
expect problem_of([Surreal.function(|_| twice_sum_fn), Surreal.function(|_| other_sum_fn)]) == "BadSchema: two database functions are named `fn::sum_to` and have different bodies"
expect problem_of([Surreal.function(|_| named_by_fn)]) == "BadSchema: in `fn::named_by`: no table holds the row type `Customer`; list its table in the schema"
expect lines_with([orders.define().check("settled", |o| settled_fn.call2(o.payment, o.total)).done(), customer_def, product_def, Surreal.function(|_| settled_fn)], "fn::settled($value") == ["DEFINE FIELD OVERWRITE payment ON order TYPE { kind: \"Card\", last4: string } | \"Cash\" | { kind: \"Invoice\", contact: record<customer>, due: string } ASSERT ((IF $value.kind = 'Invoice' THEN record::exists($value.contact) ELSE true END)) AND (fn::settled($value, $this.total));"]

# ------------------------------------------------------------ time series

Reading : { id : Surreal.TimeKey(Surreal.Id(Product)), level : I64, warm : Bool }

readings : Surreal.Table(Reading)
readings = Surreal.table("reading")

hot : I64 -> Bool
hot = |level| level > 5

hot_fn : Surreal.DbFn((I64 -> Bool))
hot_fn = Surreal.db_fn("hot", hot)

DayKey : { product : Surreal.Id(Product), day : Surreal.Datetime }

day_of : Reading -> DayKey
day_of = |r| { product: r.id.series(), day: Surreal.Time.floor(r.id.time(), Surreal.Time.days(1)) }

DayLine : { product : Surreal.Id(Product), day : Surreal.Datetime, readings : I64, hot : I64 }

day_line : DayKey, List(Reading) -> DayLine
day_line = |k, rows| { product: k.product, day: k.day, readings: rows.len().to_i64_wrap(), hot: rows.keep_if(|r| hot_fn.call1(r.level)).len().to_i64_wrap() }

daily : Surreal.Table(DayLine)
daily = Surreal.view("reading_daily")

reading_def : Surreal.Defined
reading_def = readings.define().changefeed(Surreal.Time.days(7)).done()

# Functions, tables, views, then fields: a view that calls a function needs it
# defined first (verified). The key of a time series is `[series, time]`.
expect script_of([Surreal.function(|_| hot_fn), product_def, reading_def, daily.define_as(Surreal.from(readings).group_by(day_of), day_line).done()]) == [
	"DEFINE FUNCTION OVERWRITE fn::hot($a1: int) -> bool { RETURN $a1 > 5 };",
	"DEFINE TABLE OVERWRITE product SCHEMAFULL;",
	"DEFINE TABLE OVERWRITE reading SCHEMAFULL CHANGEFEED 1w;",
	"DEFINE TABLE OVERWRITE reading_daily TYPE NORMAL AS SELECT time::floor(record::id(id)[1], 1d) AS day, count(fn::hot(level)) AS hot, record::id(id)[0] AS product, count() AS readings FROM reading GROUP BY day, product;",
	"DEFINE FIELD OVERWRITE label ON product TYPE string VALUE $this.title + '!';",
	"DEFINE FIELD OVERWRITE price ON product TYPE decimal;",
	"DEFINE FIELD OVERWRITE stock ON product TYPE i32 DEFAULT 0;",
	"DEFINE FIELD OVERWRITE title ON product TYPE string READONLY;",
	"DEFINE FIELD OVERWRITE id ON reading TYPE [record<product>, datetime];",
	"DEFINE FIELD OVERWRITE level ON reading TYPE int;",
	"DEFINE FIELD OVERWRITE warm ON reading TYPE bool;",
]

# A changefeed on an edge table, and two changefeeds.
expect lines_with([customer_def, product_def, purchased.define().changefeed(Surreal.Time.hours(1)).done()], "TABLE OVERWRITE purchased") == ["DEFINE TABLE OVERWRITE purchased TYPE RELATION IN customer OUT product ENFORCED SCHEMAFULL CHANGEFEED 1h;"]
expect problem_of([product_def, readings.define().changefeed(Surreal.Time.days(1)).changefeed(Surreal.Time.days(2)).done()]) == "BadSchema: `reading` has two changefeeds"

# A view is read-only: it takes no rule.
expect problem_of([product_def, reading_def, daily.define_as(Surreal.from(readings).group_by(day_of), day_line).index(|d| d.day).done()]) == "BadSchema: `reading_daily` is a view, and a view is read-only, so it takes no rule"
expect problem_of([product_def, reading_def, daily.define_as(Surreal.from(readings).group_by(day_of), day_line).changefeed(Surreal.Time.days(1)).done()]) == "BadSchema: `reading_daily` is a view, and a view is read-only, so it takes no rule"

# SurrealDB keeps fewer aggregates in a view (verified): no median, and the
# sum of an `int` column is a `float`. The same columns are fine in a query.
MedianLine : { product : Surreal.Id(Product), mid : F64 }

median_view : Surreal.Table(MedianLine)
median_view = Surreal.view("reading_median")

SumLine : { product : Surreal.Id(Product), total : I64 }

sum_view : Surreal.Table(SumLine)
sum_view = Surreal.view("reading_sum")

FloatSumLine : { product : Surreal.Id(Product), total : F64 }

float_sum_view : Surreal.Table(FloatSumLine)
float_sum_view = Surreal.view("reading_float_sum")

expect problem_of([product_def, reading_def, median_view.define_as(Surreal.from(readings).group_by(|r| r.id.series()), |product, rows| { product, mid: Surreal.Math.median(rows.map(|r| r.level.to_f64())) }).done()]) == "Unsupported: in `aggregate`: SurrealDB does not keep `math::median` in a view; compute it in a query"
expect problem_of([product_def, reading_def, sum_view.define_as(Surreal.from(readings).group_by(|r| r.id.series()), |product, rows| { product, total: rows.map(|r| r.level).sum() }).done()]) == "Unsupported: in `aggregate`: `math::sum` of an integer column is a float in a view; convert it with `to_f64()`"
expect lines_with([product_def, reading_def, float_sum_view.define_as(Surreal.from(readings).group_by(|r| r.id.series()), |product, rows| { product, total: rows.map(|r| r.level.to_f64()).sum() }).done()], "reading_float_sum") == ["DEFINE TABLE OVERWRITE reading_float_sum TYPE NORMAL AS SELECT record::id(id)[0] AS product, math::sum(<float>level) AS total FROM reading GROUP BY product;"]
expect Surreal.from(readings).group_by(|r| r.id.series()).aggregate(|product, rows| { product, total: rows.map(|r| r.level).sum() }).to_surql() == Ok("SELECT record::id(id)[0] AS product, math::sum(level) AS total FROM reading GROUP BY product")

# A view reads a whole table, not a range: SurrealDB refuses a range (verified).
ranged_view : Surreal.Table(SumLine)
ranged_view = Surreal.view("reading_ranged")

expect problem_of([product_def, reading_def, ranged_view.define_as(Surreal.from(readings).between(Surreal.Unchecked.id("product", "pen"), Surreal.Datetime.({ iso: "2026-03-01T00:00:00Z" }), Surreal.Datetime.({ iso: "2026-03-02T00:00:00Z" })).group_by(|r| r.id.series()), |product, rows| { product, total: rows.len().to_i64_wrap() }).done()]) == "Unsupported: the view `reading_ranged` reads a range; a view reads a whole table"

# ------------------------------------------------------------ geometry

Site : { id : Str, location : Surreal.Point, area : Surreal.Polygon, home ?: Surreal.Geometry }

sites : Surreal.Table(Site)
sites = Surreal.table("site")

# A geometry is its `geometry<kind>`, and asserts that its coordinates are in
# range: SurrealDB stores a point out of range (verified). A check may call
# `geo::` functions and read the coordinates of a point.
expect script_of([sites.define().assert(|s| s.location, |l| l.lat() > 0).check("small", |s| Surreal.Geo.area(s.area.to_geometry()) < 1000).done()]) == [
	"DEFINE TABLE OVERWRITE site SCHEMAFULL;",
	"DEFINE FIELD OVERWRITE area ON site TYPE geometry<polygon> ASSERT (geo::is_valid($value)) AND (geo::area($value) < 1000f);",
	"DEFINE FIELD OVERWRITE home ON site TYPE option<geometry> ASSERT ($value = NONE OR (geo::is_valid($value)));",
	"DEFINE FIELD OVERWRITE location ON site TYPE geometry<point> ASSERT (geo::is_valid($value)) AND ($value.coordinates[1] > 0f);",
]

# ------------------------------------------------------------ definitions

# A view takes its query with `define_as`, and only a view does.
not_a_view : Surreal.Table(DayLine)
not_a_view = Surreal.table("reading_daily")

expect problem_of([product_def, reading_def, daily.define().done()]) == "Unsupported: `reading_daily` is a view: give its query with `define_as`"
expect problem_of([product_def, reading_def, not_a_view.define_as(Surreal.from(readings).group_by(day_of), day_line).done()]) == "Unsupported: `reading_daily` is not a view: make it with `Surreal.view`"

# ------------------------------------------------------------ read rows

# Read rows of `order`, `product` and `customer`: a `Linked` for a `Link`
# to an alias row (`Product`) or to a nominal row (`Customer`), and the edges
# of `purchased` as a field with its name. A link may stay a `Link`.
ItemRead : { product : Surreal.Linked(Product), qty : I64 }

OrderRead : {
	id : Str,
	customer : Surreal.Linked(Customer),
	items : List(ItemRead),
	payment : Payment,
	gift ?: { to : Surreal.Linked(Customer), note : Str },
	wishlist : List(Surreal.Linked(Product)),
	total : Dec,
	created : Surreal.Datetime,
}

ProductRead : { id : Str, title : Str, label : Str, price : Dec, stock : I32, purchased : Surreal.In({ id : Str, from : Surreal.Link(Customer), to : Surreal.Linked(Product), quantity : I64 }) }

order_reads : Surreal.Table(OrderRead)
order_reads = Surreal.table("order")

product_reads : Surreal.Table(ProductRead)
product_reads = Surreal.table("product")

## `Customer` links to its own table, and the read row reads that link as
## a `Linked` of the stored row.
CustomerRead : { id : Str, name : Str, email : Str, address : Address, tags : List(Str), referrer ?: Surreal.Linked(Customer), age : U8 }

customer_reads : Surreal.Table(CustomerRead)
customer_reads = Surreal.table("customer")

stored_defs : List(Surreal.Defined)
stored_defs = [customer_def, product_def, order_def, purchased_def]

# A read row writes no statement.
expect script_of(stored_defs.concat([order_reads.define_read(), product_reads.define_read(), customer_reads.define_read()])) == script_of(stored_defs)

# Each read row that does not agree with its stored row is a `BadSchema`.
OtherTarget : { id : Str, title : Str }

ShortItems : { id : Str, customer : Surreal.Link(Customer), items : List({ product : Surreal.Linked(OtherTarget), qty : I64 }), payment : Payment, gift ?: { to : Surreal.Link(Customer), note : Str }, wishlist : List(Surreal.Linked(Product)), total : Dec, created : Surreal.Datetime }

short_items : Surreal.Table(ShortItems)
short_items = Surreal.table("order")

LinkedTotal : { id : Str, customer : Surreal.Link(Customer), items : List(Item), payment : Payment, gift ?: { to : Surreal.Link(Customer), note : Str }, wishlist : List(Surreal.Link(Product)), total : Surreal.Linked(Product), created : Surreal.Datetime }

linked_total : Surreal.Table(LinkedTotal)
linked_total = Surreal.table("order")

NoGift : { id : Str, customer : Surreal.Link(Customer), items : List(Item), payment : Payment, wishlist : List(Surreal.Link(Product)), total : Dec, created : Surreal.Datetime }

no_gift : Surreal.Table(NoGift)
no_gift = Surreal.table("order")

## `purchased` ends at `product`, so it is not an `Out` of `product`.
WrongEnd : { id : Str, title : Str, label : Str, price : Dec, stock : I32, purchased : Surreal.Out(Purchase) }

wrong_end : Surreal.Table(WrongEnd)
wrong_end = Surreal.table("product")

NotEdges : { id : Str, title : Str, label : Str, price : Dec, stock : I32, order : Surreal.In(Purchase) }

not_edges : Surreal.Table(NotEdges)
not_edges = Surreal.table("product")

ShortEdge : { id : Str, title : Str, label : Str, price : Dec, stock : I32, purchased : Surreal.In({ id : Str, from : Surreal.Link(Customer), to : Surreal.Link(Product) }) }

short_edge : Surreal.Table(ShortEdge)
short_edge = Surreal.table("product")

## A read row that holds a `Linked` of itself. It agrees with its stored
## row when its fields agree, if the `Linked` of itself agrees: the pair
## is on the way when the comparison meets it again at `referrer.referrer`.
CustomerLoop := { id : Str, name : Str, email : Str, address : Address, tags : List(Str), referrer ?: Surreal.Linked(CustomerLoop), age : U8 }

customer_loops : Surreal.Table(CustomerLoop)
customer_loops = Surreal.table("customer")

## The same, with a field the stored row does not have.
CustomerLoopExtra := { id : Str, name : Str, email : Str, address : Address, tags : List(Str), referrer ?: Surreal.Linked(CustomerLoopExtra), age : U8, nick : Str }

customer_loop_extras : Surreal.Table(CustomerLoopExtra)
customer_loop_extras = Surreal.table("customer")

## An order whose `customer` is a `Linked` of the order read row itself:
## the link points at `customer`, so the fields do not agree.
OrderLoop := { id : Str, customer : Surreal.Linked(OrderLoop), items : List(Item), payment : Payment, gift ?: { to : Surreal.Link(Customer), note : Str }, wishlist : List(Surreal.Link(Product)), total : Dec, created : Surreal.Datetime }

order_loops : Surreal.Table(OrderLoop)
order_loops = Surreal.table("order")

expect problem_of(stored_defs.append(short_items.define_read())) == "BadSchema: the read row of `order` has the fields id, title at `items[*].product`, and its stored row id, label, price, stock, title"
expect problem_of(stored_defs.append(linked_total.define_read())) == "BadSchema: the read row of `order` does not agree with its stored row at `total`: a `Linked` stands where the stored row has no `Link`"
expect problem_of(stored_defs.append(no_gift.define_read())) == "BadSchema: the read row of `order` has the fields created, customer, id, items, payment, total, wishlist, and its stored row created, customer, gift?, id, items, payment, total, wishlist"
expect problem_of(stored_defs.append(wrong_end.define_read())) == "BadSchema: the read row of `product`: the field `purchased` names edges that start at `customer`, not at `product`"
expect problem_of(stored_defs.append(not_edges.define_read())) == "BadSchema: the read row of `product`: the field `order` names `order`, which is not an edge table"
expect problem_of(stored_defs.append(short_edge.define_read())) == "BadSchema: the read row of `product` has the fields from, id, to at `purchased`, and its stored row from, id, quantity, to"
expect script_of(stored_defs.append(customer_loops.define_read())) == script_of(stored_defs)
expect problem_of(stored_defs.append(customer_loop_extras.define_read())) == "BadSchema: the read row of `customer` has the fields address, age, email, id, name, nick, referrer?, tags, and its stored row address, age, email, id, name, referrer?, tags"
expect problem_of(stored_defs.append(order_loops.define_read())) == "BadSchema: the read row of `order` has the fields created, customer, gift?, id, items, payment, total, wishlist at `customer`, and its stored row address, age, email, id, name, referrer?, tags"
expect problem_of([order_reads.define_read()]) == "BadSchema: the read row of `order` has no stored table of that name; list the table in the schema"

# A read row is not stored: as the definition of a table it is a `BadSchema`.
expect problem_of([customer_def, product_def, order_reads.define().done()]) == "BadSchema: field `customer`: `Surreal.Linked` is a field of a read row, which is not stored; the stored row holds a `Link`, and a read row is checked with `define_read`"

# A link in an arm with two payloads is an item of the array `value`.
Transfer : { id : Str, via : [Direct, Agent(Str, Surreal.Link(Customer))] }

transfers : Surreal.Table(Transfer)
transfers = Surreal.table("transfer")

expect lines_with([customer_def, transfers.define().on_delete(customers, Cascade).done()], "transfer") == [
	"DEFINE TABLE OVERWRITE transfer SCHEMAFULL;",
	"DEFINE FIELD OVERWRITE via ON transfer TYPE { kind: \"Agent\", value: [string, record<customer>] } | \"Direct\" ASSERT (IF $value.kind = 'Agent' THEN record::exists($value.value[1]) ELSE true END);",
	"DEFINE EVENT OVERWRITE transfer_via_Agent_value_1_on_delete ON customer WHEN $event = 'DELETE' THEN { DELETE transfer WHERE (via.kind = 'Agent' AND via.value[1] = $before.id) };",
]

# ------------------------------------------------- defaults from the type

# A `??` default that is a literal is the `DEFAULT` of its field, at any
# depth, the record key too (verified on SurrealDB 3.3.4: a create that
# leaves a field out gets the default, and one that leaves out `id` gets
# `pack:main`). A union arm has no field definition, so a default in it is
# not in the schema.
made : {} -> Str
made = |_| "made"

Grade := [Basic, Gold]

Crate := { w : I64 ?? 1, label : Str ?? "crate" }

Pack := {
	id : Str ?? "main",
	stock : I32 ?? 0,
	price : Dec ?? 2.5,
	ratio : F64 ?? 0.5,
	note : Str ?? "none",
	tags : List(Str) ?? ["new"],
	grade : Grade ?? Gold,
	size : Crate,
	crates : List(Crate),
	made_at ?: Str,
	shape : [Flat({ w : I64 }), Crated(Crate)],
}

packs : Surreal.Table(Pack)
packs = Surreal.table("pack")

expect script_of([packs.define().done()]) == [
	"DEFINE TABLE OVERWRITE pack SCHEMAFULL;",
	"DEFINE FIELD OVERWRITE id ON pack TYPE string DEFAULT 'main';",
	"DEFINE FIELD OVERWRITE crates ON pack TYPE array<object> ASSERT $value.all(|$e| object::keys($e).all(|$k| $k IN ['label', 'w']));",
	"DEFINE FIELD OVERWRITE crates[*].label ON pack TYPE string DEFAULT 'crate';",
	"DEFINE FIELD OVERWRITE crates[*].w ON pack TYPE int DEFAULT 1;",
	"DEFINE FIELD OVERWRITE grade ON pack TYPE \"Basic\" | \"Gold\" DEFAULT 'Gold';",
	"DEFINE FIELD OVERWRITE made_at ON pack TYPE option<string>;",
	"DEFINE FIELD OVERWRITE note ON pack TYPE string DEFAULT 'none';",
	"DEFINE FIELD OVERWRITE price ON pack TYPE decimal DEFAULT 2.5dec;",
	"DEFINE FIELD OVERWRITE ratio ON pack TYPE float DEFAULT 0.5f;",
	"DEFINE FIELD OVERWRITE shape ON pack TYPE { kind: \"Crated\", label: string, w: int } | { kind: \"Flat\", w: int };",
	"DEFINE FIELD OVERWRITE size ON pack TYPE object;",
	"DEFINE FIELD OVERWRITE size.label ON pack TYPE string DEFAULT 'crate';",
	"DEFINE FIELD OVERWRITE size.w ON pack TYPE int DEFAULT 1;",
	"DEFINE FIELD OVERWRITE stock ON pack TYPE i32 DEFAULT 0;",
	"DEFINE FIELD OVERWRITE tags ON pack TYPE array<string> DEFAULT ['new'];",
]

# A default in the type and a `default` clause on one field are two defaults.
expect problem_of([packs.define().default(|p| p.stock, 1).done()]) == "BadSchema: `stock` has two defaults"

# A default that is not a literal (`DefaultComputed`) is refused where it is,
# with or without a `default_by` clause: the type does not carry its value.
Stamp := { id : Str, label : Str ?? made({}) }

Outer := { id : Str, inner : { x : I64, stamp : Stamp } }

KeyMade := { id : Str ?? made({}), n : I64 }

stamps : Surreal.Table(Stamp)
stamps = Surreal.table("stamp")

outers : Surreal.Table(Outer)
outers = Surreal.table("outer")

key_mades : Surreal.Table(KeyMade)
key_mades = Surreal.table("key_made")

expect problem_of([stamps.define().done()]) == "BadSchema: field `label` has a `??` default that is not a literal, so the type does not carry its value; give it a literal default, or remove the `??` and use `.default_by(|r| r.label, |_| ..)`"
expect problem_of([stamps.define().default_by(|s| s.label, |_| "x").done()]) == "BadSchema: field `label` has a `??` default that is not a literal, so the type does not carry its value; give it a literal default, or remove the `??` and use `.default_by(|r| r.label, |_| ..)`"
expect problem_of([outers.define().done()]) == "BadSchema: field `inner.stamp.label` has a `??` default that is not a literal, so the type does not carry its value; give it a literal default, or remove the `??` and use `.default_by(|r| r.inner.stamp.label, |_| ..)`"
expect problem_of([key_mades.define().done()]) == "BadSchema: table `key_made`: field `id` has a `??` default that is not a literal, so the type does not carry its value; give it a literal default, or remove the `??` and use `.default_by(|r| r.id, |_| ..)`"

# ------------------------------------------------- access and permissions

# A record access method over a table of users, and a table whose rows
# each user reads and writes by its owner. `Surreal.Hash.argon2` makes a
# new salt on every call, so it is allowed in the signup, which is a
# write; the signin compares, as a filter does.
User : { id : Str, email : Str, pass : Str }

Memo : { id : Str, owner : Surreal.Link(User), text : Str, shared : Bool }

Credentials : { email : Str, pass : Str }

users : Surreal.Table(User)
users = Surreal.table("user")

memos : Surreal.Table(Memo)
memos = Surreal.table("memo")

accounts : Surreal.Access(Credentials, Credentials)
accounts = Surreal.access("account")

account_def : Surreal.Defined
account_def =
	accounts.define(users, |v| { email: v.email, pass: Surreal.Hash.argon2(v.pass) }, |v, u| u.email == v.email and Surreal.Hash.argon2_matches(u.pass, v.pass))
		.token_for(Surreal.Time.hours(1))
		.session_for(Surreal.Time.hours(12))
		.done()

user_def : Surreal.Defined
user_def = users.define().unique(|u| u.email).permit([Select], |u| users.id(u.id) == users.auth()).deny_field(|u| u.pass, [Select]).done()

memo_def : Surreal.Defined
memo_def =
	memos.define()
		.permit([Select], |m| m.owner.id() == users.auth() or m.shared)
		.permit([Create, Update, Delete], |m| m.owner.id() == users.auth())
		.permit_field(|m| m.text, [Update], |m| !m.shared)
		.on_delete(users, Cascade)
		.done()

# A table with a permission names each action: the ones no permission
# names are `NONE`, SurrealDB's default for a table. A field names only
# its own, and the rest are `FULL`. The record user is `$auth.id`.
expect script_of([user_def, memo_def, account_def]) == [
	"DEFINE TABLE OVERWRITE user SCHEMAFULL PERMISSIONS FOR select WHERE id = $auth.id, FOR create, update, delete NONE;",
	"DEFINE TABLE OVERWRITE memo SCHEMAFULL PERMISSIONS FOR select WHERE (owner = $auth.id) OR shared, FOR create, update, delete WHERE owner = $auth.id;",
	"DEFINE FIELD OVERWRITE email ON user TYPE string;",
	"DEFINE FIELD OVERWRITE pass ON user TYPE string PERMISSIONS FOR select NONE;",
	"DEFINE FIELD OVERWRITE owner ON memo TYPE record<user> REFERENCE ON DELETE CASCADE ASSERT record::exists($value);",
	"DEFINE FIELD OVERWRITE shared ON memo TYPE bool;",
	"DEFINE FIELD OVERWRITE text ON memo TYPE string PERMISSIONS FOR update WHERE !shared;",
	"DEFINE INDEX OVERWRITE user_email_unique ON user FIELDS email UNIQUE;",
	"DEFINE ACCESS OVERWRITE account ON DATABASE TYPE RECORD SIGNUP (CREATE user CONTENT { email: $email, pass: crypto::argon2::generate($pass) }) SIGNIN (SELECT * FROM user WHERE (email = $email) AND crypto::argon2::compare(pass, $pass)) DURATION FOR TOKEN 1h, FOR SESSION 12h;",
]

# `FULL`, and an access method with SurrealDB's default durations.
expect lines_with([user_def, memos.define().permit_full([Select]).permit([Create], |m| !m.shared).done()], "TABLE OVERWRITE memo") == ["DEFINE TABLE OVERWRITE memo SCHEMAFULL PERMISSIONS FOR select FULL, FOR create WHERE !shared, FOR update, delete NONE;"]
expect lines_with([accounts.define(users, |v| { email: v.email, pass: v.pass }, |v, u| u.email == v.email).done()], "ACCESS") == ["DEFINE ACCESS OVERWRITE account ON DATABASE TYPE RECORD SIGNUP (CREATE user CONTENT { email: $email, pass: $pass }) SIGNIN (SELECT * FROM user WHERE email = $email);"]

# A signup is a write, so it may hash with a new salt; the signin is a
# filter, which may not.
expect problem_of([accounts.define(users, |v| { email: v.email, pass: v.pass }, |v, u| u.email == v.email and u.pass == Surreal.Hash.argon2(v.pass)).done()]) == "Unsupported: in the signin of `account`: `Surreal.Hash.argon2` gives a new value on every call: use it in a default, a computed field or an update"

# An action in two permissions, a field's `delete`, and a field that the
# table does not define are refused.
expect problem_of([user_def, memos.define().permit([Select], |m| m.shared).permit([Select, Update], |m| !m.shared).done()]) == "BadSchema: `memo` has two permissions for `select`"
expect problem_of([user_def, memos.define().deny_field(|m| m.text, [Select]).deny_field(|m| m.text, [Select]).done()]) == "BadSchema: `text` has two permissions for `select`"
expect problem_of([memos.define().deny_field(|m| m.text, [Delete]).done()]) == "BadSchema: `memo.text`: a field has no `delete` permission; the table's decides"
expect problem_of([users.define().deny_field(|u| u.id, [Select]).done()]) == "BadSchema: `user.id` has no field definition to put this on; the record key and an edge's ends are SurrealDB's own"

# ------------------------------------------------- full-text and vector indexes

Note : { id : Str, body : Str, title : { text : Str }, tags : List(Str), embedding : List(F32), exact : List(F64) }

notes : Surreal.Table(Note)
notes = Surreal.table("note")

## Another table of the same row type.
drafts : Surreal.Table(Note)
drafts = Surreal.table("draft")

terms : Surreal.Analyzer
terms = Surreal.analyzer("terms", [Blank, Class], [Lowercase, Ascii, Snowball("english"), EdgeNgram(2, 5)])

note_text : Surreal.FullText(Note)
note_text = notes.text_index(|n| n.body, terms)

note_vectors : Surreal.VectorIndex(Note)
note_vectors = notes.vector_index(|n| n.embedding, { dimension: 4, distance: Euclidean })

# The analyzer comes before the tables, and each index after the fields.
# A `List(F32)` is indexed as `F32`, a `List(F64)` as `F64`, and a path
# into an object is a full-text index too.
expect script_of(
	[
		terms.define(),
		notes.define().text_index(note_text).text_index(notes.text_index(|n| n.title.text, terms)).vector_index(note_vectors).vector_index(notes.vector_index(|n| n.exact, { dimension: 2, distance: Manhattan })).done(),
	],
)
	== [
		"DEFINE ANALYZER OVERWRITE terms TOKENIZERS blank,class FILTERS lowercase,ascii,snowball(english),edgengram(2,5);",
		"DEFINE TABLE OVERWRITE note SCHEMAFULL;",
		"DEFINE FIELD OVERWRITE body ON note TYPE string;",
		"DEFINE FIELD OVERWRITE embedding ON note TYPE array<f32>;",
		"DEFINE FIELD OVERWRITE exact ON note TYPE array<float>;",
		"DEFINE FIELD OVERWRITE tags ON note TYPE array<string>;",
		"DEFINE FIELD OVERWRITE title ON note TYPE object;",
		"DEFINE FIELD OVERWRITE title.text ON note TYPE string;",
		"DEFINE INDEX OVERWRITE note_body_fulltext ON note FIELDS body FULLTEXT ANALYZER terms BM25 HIGHLIGHTS;",
		"DEFINE INDEX OVERWRITE note_title_text_fulltext ON note FIELDS title.text FULLTEXT ANALYZER terms BM25 HIGHLIGHTS;",
		"DEFINE INDEX OVERWRITE note_embedding_hnsw ON note FIELDS embedding HNSW DIMENSION 4 DIST EUCLIDEAN TYPE F32;",
		"DEFINE INDEX OVERWRITE note_exact_hnsw ON note FIELDS exact HNSW DIMENSION 2 DIST MANHATTAN TYPE F64;",
	]

# An analyzer with no tokenizer or no filter leaves the word out.
expect lines_with([Surreal.analyzer("whole", [], [Uppercase]).define(), Surreal.analyzer("split", [Punct, Camel], []).define()], "ANALYZER") == ["DEFINE ANALYZER OVERWRITE whole FILTERS uppercase;", "DEFINE ANALYZER OVERWRITE split TOKENIZERS punct,camel;"]

# The analyzer of a full-text index must be in the schema, an index is of
# its own table, and a vector index is of a list of numbers.
expect problem_of([notes.define().text_index(note_text).done()]) == "BadSchema: the full-text index on `note.body` names the analyzer `terms`, which the schema does not define: give its `define()` to `schema`"
expect problem_of([terms.define(), drafts.define().text_index(note_text).done()]) == "BadSchema: the index is of the table `note`, and this definition is of `draft`"
expect problem_of([notes.define().vector_index(notes.vector_index(|n| n.tags, { dimension: 2, distance: Cosine })).done()]) == "BadSchema: a vector index of `note` is over a `List(F64)` or a `List(F32)`, not a `List(Str)`"

# The Roc meaning of an analyzer: the terms of the tokenizers `Blank` and
# `Class` and the filters `Lowercase` and `Uppercase` over ASCII text, as
# `search::analyze` gives them on SurrealDB 3.3.4.
expect Surreal.analyzer("a", [Class], [Lowercase]).tokens("a+b$c x!+y (q)[1] e_f\tG42") == ["a", "+", "b", "$", "c", "x", "!+", "y", "(", "q", ")[", "1", "]", "e", "_", "f", "g", "42"]
expect Surreal.analyzer("a", [Blank], [Uppercase]).tokens(" Hello, world!  dog42 ") == ["HELLO,", "WORLD!", "DOG42"]
expect Surreal.analyzer("a", [], [Lowercase]).tokens("Ab Cd") == ["ab cd"]
expect Surreal.analyzer("a", [Class], [Lowercase]).matches("Rex limping again, left leg.", "LEFT leg")
expect !Surreal.analyzer("a", [Class], [Lowercase]).matches("Rex limping again, left leg.", "leg, right")
expect !Surreal.analyzer("a", [Class], [Lowercase]).matches("Rex limping again, left leg.", " ")

# ------------------------------------------------------------- migrations

# A statement of the script by what it defines.
expect Schema.entry("DEFINE FIELD OVERWRITE address.city ON owner TYPE string;") == { kind: "FIELD", name: "address.city", on: "owner", line: "DEFINE FIELD OVERWRITE address.city ON owner TYPE string;" }
expect Schema.entry("DEFINE FUNCTION OVERWRITE fn::fever($a1: decimal) -> bool { RETURN $a1 > 39 };").name == "fn::fever"
expect Schema.entry("DEFINE FUNCTION OVERWRITE fn::fever($a1: decimal) -> bool { RETURN $a1 > 39 };").on == ""
expect Schema.entry("DEFINE INDEX OVERWRITE ⟨a b⟩ ON ⟨my table⟩ FIELDS x;").name == "⟨a b⟩"
expect Schema.entry("DEFINE INDEX OVERWRITE ⟨a b⟩ ON ⟨my table⟩ FIELDS x;").on == "⟨my table⟩"
expect Schema.entry("DEFINE ACCESS OVERWRITE users ON DATABASE TYPE RECORD;").on == "DATABASE"
expect Schema.is_view("DEFINE TABLE OVERWRITE daily TYPE NORMAL AS SELECT count() FROM vital GROUP ALL;")
expect !Schema.is_view("DEFINE TABLE OVERWRITE vital SCHEMAFULL;")

# The type of a field, up to the next clause, and whether a new type
# takes every old value.
expect Schema.field_type("DEFINE FIELD OVERWRITE s ON vet TYPE \"Dental\" | { kind: \"Surgery\", board: string } ASSERT $value != '';") == "\"Dental\" | { kind: \"Surgery\", board: string }"
expect Schema.field_type("DEFINE FIELD OVERWRITE vaccines[*].vet ON patient ASSERT record::exists($value);") == ""
expect Schema.widens("int", "option<int>")
expect Schema.widens("option<int>", "option<int | string>")
expect Schema.widens("int", "number")
expect !Schema.widens("option<int>", "int")
expect !Schema.widens("string", "int")
expect !Schema.widens("{ a: int | string }", "{ a: int }")
# A sized number type widens to a type that holds each of its values
# (verified on 4.0.1), and to `number`. A narrower type, or a float for an
# integer, is a change of type.
expect Schema.widens("u8", "i16") and Schema.widens("u8", "u64") and Schema.widens("u32", "int") and Schema.widens("i32", "int")
expect Schema.widens("option<u16>", "option<i32>") and Schema.widens("f32", "float") and Schema.widens("u64", "number")
expect !Schema.widens("int", "u8") and !Schema.widens("i8", "u8") and !Schema.widens("u64", "int") and !Schema.widens("i16", "u16")
expect !Schema.widens("float", "f32") and !Schema.widens("u8", "float") and !Schema.widens("u16", "i16")

# The value that a new field gives the rows that are there: its default
# as the schema value holds it, or `NoDefault`.
fields_of_a : List(Schema.FieldInfo)
fields_of_a = [
	{ table: "a", path: "w", ty: "int", default: Ok("7") },
	{ table: "a", path: "x", ty: "string", default: Err(NoDefault) },
	{ table: "a", path: "o", ty: "option<string>", default: Err(NoDefault) },
	{ table: "a", path: "p.q", ty: "string", default: Err(NoDefault) },
]

expect Schema.fill_value(Schema.entry("DEFINE FIELD OVERWRITE w ON a TYPE int DEFAULT 7;"), fields_of_a) == Ok(Ok("7"))
expect Schema.fill_value(Schema.entry("DEFINE FIELD OVERWRITE x ON a TYPE string;"), fields_of_a) == Ok(Err(NoDefault))
expect Schema.fill_value(Schema.entry("DEFINE FIELD OVERWRITE o ON a TYPE option<string>;"), fields_of_a) == Err(NoFill)
expect Schema.fill_value(Schema.entry("DEFINE FIELD OVERWRITE p.q ON a TYPE string;"), fields_of_a) == Err(NoFill)

# What `old` has and `new` does not goes first, from the last; what is on a
# dropped table goes with it; a view is removed, not dropped. A field whose
# new type does not take the old values is a `Retype`.
expect
	Schema.migration_steps(
		[
			"DEFINE FUNCTION OVERWRITE fn::f() -> int { RETURN 1 };",
			"DEFINE TABLE OVERWRITE a SCHEMAFULL;",
			"DEFINE TABLE OVERWRITE b SCHEMAFULL;",
			"DEFINE TABLE OVERWRITE v TYPE NORMAL AS SELECT * FROM a;",
			"DEFINE FIELD OVERWRITE x ON a TYPE int;",
			"DEFINE FIELD OVERWRITE y ON a TYPE int;",
			"DEFINE FIELD OVERWRITE z ON b TYPE int;",
			"DEFINE INDEX OVERWRITE a_y ON a FIELDS y;",
			"DEFINE INDEX OVERWRITE b_z ON b FIELDS z;",
		],
		[
			"DEFINE TABLE OVERWRITE a SCHEMAFULL;",
			"DEFINE FIELD OVERWRITE x ON a TYPE string;",
			"DEFINE FIELD OVERWRITE w ON a TYPE int DEFAULT 7;",
		],
		fields_of_a,
	)
	== [
		Remove("REMOVE INDEX IF EXISTS a_y ON a"),
		DropField({ table: "a", path: "y" }),
		Remove("REMOVE TABLE IF EXISTS v"),
		DropTable("b"),
		Remove("REMOVE FUNCTION IF EXISTS fn::f"),
		Retype({ line: "DEFINE FIELD OVERWRITE x ON a TYPE string", table: "a", path: "x", from: "int", to: "string", value: Err(NoDefault) }),
		Fill({ line: "DEFINE FIELD OVERWRITE w ON a TYPE int DEFAULT 7", table: "a", path: "w", value: Ok("7") }),
	]

# A new table gets no fill: it has no rows. A wider type is a define.
expect Schema.migration_steps([], ["DEFINE TABLE OVERWRITE a SCHEMAFULL;", "DEFINE FIELD OVERWRITE x ON a TYPE int;"], fields_of_a) == [Define("DEFINE TABLE OVERWRITE a SCHEMAFULL"), Define("DEFINE FIELD OVERWRITE x ON a TYPE int")]
expect Schema.migration_steps(["DEFINE TABLE OVERWRITE a SCHEMAFULL;", "DEFINE FIELD OVERWRITE x ON a TYPE string;"], ["DEFINE TABLE OVERWRITE a SCHEMAFULL;", "DEFINE FIELD OVERWRITE x ON a TYPE string | int;"], fields_of_a) == [Define("DEFINE FIELD OVERWRITE x ON a TYPE string | int")]
# A narrower type that takes `NONE` is a `Retype` too.
expect Schema.migration_steps(["DEFINE TABLE OVERWRITE a SCHEMAFULL;", "DEFINE FIELD OVERWRITE o ON a TYPE option<int>;"], ["DEFINE TABLE OVERWRITE a SCHEMAFULL;", "DEFINE FIELD OVERWRITE o ON a TYPE option<string>;"], fields_of_a) == [Retype({ line: "DEFINE FIELD OVERWRITE o ON a TYPE option<string>", table: "a", path: "o", from: "option<int>", to: "option<string>", value: Err(NoDefault) })]

ProductV2 : { id : Str, title : Str, price : Dec, stock : I32, sku : Str }

products_v2 : Surreal.Table(ProductV2)
products_v2 = Surreal.table("product")

## The plan from the snapshot of `old` to `new`.
plan_of : List(Surreal.Defined), List(Surreal.Defined) -> Try(Surreal.Plan, Surreal.Error)
plan_of = |old, new| Surreal.plan(Surreal.schema(old)?, new)

## The start of the hash of the snapshot of `old`: the name of a `MIGRATE`.
seed_of : List(Surreal.Defined) -> Str
seed_of = |old| Str.from_utf8(Crypto.SHA256.hash((Surreal.schema(old) ?? "").to_utf8()).to_hex().to_utf8().take_first(8)) ?? ""

## The customer loses its unique email and its check; the product loses
## `label` and `readonly`, and gets `sku`.
moved_old : List(Surreal.Defined)
moved_old = [customers.define().unique(|c| c.email).check("named", |c| c.name != "").done(), products.define().default(|p| p.stock, 0).readonly(|p| p.title).computed(|p| p.label, |p| p.title.concat("!")).done()]

moved_new : List(Surreal.Defined)
moved_new = [customers.define().done(), products_v2.define().default(|p| p.stock, 0).done()]

moved : Try(Surreal.Plan, Surreal.Error)
moved = plan_of(moved_old, moved_new)

expect moved.map_ok(|m| m.dropped()) == Ok(["product.label"])
expect moved.map_ok(|m| m.statements(DropData)) == Ok([["REMOVE INDEX IF EXISTS customer_email_unique ON customer", "REMOVE FIELD IF EXISTS label ON product", "DEFINE FIELD OVERWRITE name ON customer TYPE string", "DEFINE FIELD OVERWRITE sku ON product TYPE string MIGRATE EXISTING ROWS AS m_${seed_of(moved_old)}_product_sku USING NONE", "DEFINE FIELD OVERWRITE title ON product TYPE string"]])

# `sku` has no default: the plan cannot pick its value, so `prepare` refuses it.
expect moved.map_ok(|m| m.prepare(DropData).is_err()) == Ok(Bool.True)

# `KeepData` keeps the field and its data.
expect moved.map_ok(|m| m.statements(KeepData)) == Ok([["REMOVE INDEX IF EXISTS customer_email_unique ON customer", "DEFINE FIELD OVERWRITE name ON customer TYPE string", "DEFINE FIELD OVERWRITE sku ON product TYPE string MIGRATE EXISTING ROWS AS m_${seed_of(moved_old)}_product_sku USING NONE", "DEFINE FIELD OVERWRITE title ON product TYPE string"]])

# A dropped table takes its fields, indexes and events with it, and the
# same schema gives no statement and no section.
expect plan_of([customer_def, product_def, order_def, purchased_def], [customer_def, product_def, order_def]).map_ok(|m| (m.dropped(), m.statements(KeepData), m.statements(DropData))) == Ok((["purchased"], [], [["REMOVE TABLE IF EXISTS purchased"]]))
expect plan_of([customer_def, product_def], [customer_def, product_def]).map_ok(|m| (m.statements(DropData), m.is_empty(DropData))) == Ok(([], Bool.True))
expect plan_of([customer_def, product_def], [customer_def, product_def]).map_ok(|m| m.prepare(DropData).map_ok(|all| all.len())) == Ok(Ok(0))
expect plan_of([customer_def, product_def, order_def, purchased_def], [customer_def, product_def, order_def]).map_ok(|m| m.prepare(DropData).map_ok(|all| all.map(|p| p.request() ?? ""))) == Ok(Ok(["BEGIN;\nREMOVE TABLE IF EXISTS purchased;\nCOMMIT;"]))

# A schema that does not translate is its error.
expect plan_of([customer_def], [orders.define().done()]).is_err()

# A default is taken from the schema value, not from the text: a text
# with clause words in it and a record are whole.
Meta : { a : I64, b : Str }

Tag0 : { id : Str }

Tag1 := { id : Str, note : Str ?? "x ASSERT y DEFAULT z", meta : Meta }.{
	encoder_for : _
	parser_for : _
}

tags0 : Surreal.Table(Tag0)
tags0 = Surreal.table("tag")

tags1 : Surreal.Table(Tag1)
tags1 = Surreal.table("tag")

expect plan_of([tags0.define().done()], [tags1.define().default(|t| t.meta, { a: 1, b: "q VALUE r" }).done()]).map_ok(|m| m.statements(KeepData).join().keep_if(|l| l.contains("MIGRATE")).map(|l| l.split_first(" USING ").map_ok(|p| p.after) ?? "")) == Ok(["{ a: 1, b: 'q VALUE r' }", "'x ASSERT y DEFAULT z'"])

# A `U64` is an `int` that is not negative: a value above the range of an
# `int` is a decimal, and the type refuses it.
Count : { id : Str, n : U64, more : List(U64) }

counts : Surreal.Table(Count)
counts = Surreal.table("count")

expect Surreal.schema([counts.define().done()]) == Ok("DEFINE TABLE OVERWRITE count SCHEMAFULL;\nDEFINE FIELD OVERWRITE more ON count TYPE array<u64>;\nDEFINE FIELD OVERWRITE n ON count TYPE u64;")
