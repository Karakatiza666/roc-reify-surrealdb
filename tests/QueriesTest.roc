app [] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.5.0/B5U2mPsWTtuxfCRMzqQxio2ecDv7CAzCoyEMENMh4FNF.tar.zst",
	internal: "../src/internal.roc",
}

import internal.Diff
import internal.Ql
import internal.Surreal
import cbor.Cbor

# Tests of the queries and writes of `Surreal` on a small domain, one for
# each kind of query and write. Nothing outside this file imports it.
QueriesTest :: {}

Address : { city : Str, zip ?: Str }

Customer : { id : Str, name : Str, address : Address, tags : List(Str) }

Product : { id : Str, title : Str, price : Dec }

Item : { product : Surreal.Link(Product), qty : I64 }

Payment : [Card({ last4 : Str }), Cash]

Order : { id : Str, customer : Surreal.Link(Customer), items : List(Item), payment : Payment, total : Dec }

Purchased : { id : Str, from : Surreal.Link(Customer), to : Surreal.Link(Product), quantity : I64 }

customers : Surreal.Table(Customer)
customers = Surreal.table("customer")

products : Surreal.Table(Product)
products = Surreal.table("product")

orders : Surreal.Table(Order)
orders = Surreal.table("order")

purchased : Surreal.Table(Purchased)
purchased = Surreal.relation("purchased", customers, products)

Reviewed : { id : Str, from : Surreal.Link(Customer), to : Surreal.Link(Product), stars : I64 }

reviewed : Surreal.Table(Reviewed)
reviewed = Surreal.relation("reviewed", customers, products)

## A crate of a shipment, and a shipment of crates: a list of lists of links.
Crate : { items : List(Item) }

Shipment : { id : Str, boxes : List(Crate) }

shipments : Surreal.Table(Shipment)
shipments = Surreal.table("shipment")

pen_id : Surreal.Id(Product)
pen_id = Surreal.Unchecked.id("product", "pen")

Params : { min_total : Dec }

# ------------------------------------------------------------- queries

expect Surreal.from(orders).filter(|o| o.customer.get().address.city == "Paris").select(|r| r).to_surql() == Ok("SELECT customer, record::id(id) AS id, items, payment, total FROM order WHERE customer.address.city = 'Paris'")
expect Surreal.from(orders).filter(|o| o.items.any(|i| i.qty > 3)).select(|r| r).to_surql() == Ok("SELECT customer, record::id(id) AS id, items, payment, total FROM order WHERE items.any(|$v1| $v1.qty > 3)")
expect Surreal.from(orders).filter(|o| o.items.any(|i| i.qty > 3)).filter(|o| o.total > 10).select(|r| r).to_surql() == Ok("SELECT customer, record::id(id) AS id, items, payment, total FROM order WHERE (items.any(|$v1| $v1.qty > 3)) AND (total > 10.0dec)")
expect Surreal.from(orders).filter(|o| o.items.any(|i| i.product.id() == pen_id)).select(|r| r).to_surql() == Ok("SELECT customer, record::id(id) AS id, items, payment, total FROM order WHERE product:⟨pen⟩ IN items[*].product")
expect Surreal.from(orders).select(|o| { who: o.customer.get().name, n: o.items.len() }).to_surql() == Ok("SELECT items.len() AS n, customer.name AS who FROM order")
expect Surreal.from(customers).select(|c| { note: c.address.?zip ?? "-" }).to_surql() == Ok("SELECT address.zip ?? '-' AS note FROM customer")
expect Surreal.from(customers).outgoing(purchased).select(|(c, bought)| { name: c.name, titles: bought.keep_if(|e| e.quantity > 2).map(|e| e.to.get().title) }).to_surql() == Ok("SELECT name AS name, ->purchased[WHERE quantity > 2]->product.title AS titles FROM customer")
expect Surreal.from(products).incoming(purchased).select(|(p, buys)| { title: p.title, buyers: buys.map(|e| e.from.get().name) }).to_surql() == Ok("SELECT <-purchased<-customer.name AS buyers, title AS title FROM product")
expect Surreal.from(customers).outgoing(purchased).filter(|(_, bought)| bought.any(|e| e.quantity > 2)).select(|(c, _)| { name: c.name }).to_surql() == Ok("SELECT name AS name FROM customer WHERE ->purchased.any(|$v1| $v1.quantity > 2)")
expect Surreal.from(orders).group_by(|o| o.customer.get().address.city).aggregate(|city, rows| { city, orders: rows.len(), revenue: rows.map(|o| o.total).sum() }).to_surql() == Ok("SELECT customer.address.city AS city, count() AS orders, math::sum(total) AS revenue FROM order GROUP BY city")
expect Surreal.from(orders).group_by(|o| o.customer.get().address.city).aggregate(|city, rows| { city, orders: rows.len(), revenue: rows.map(|o| o.total).sum() }).order_by(|r| r.revenue, Desc).start(0).limit(10).to_surql() == Ok("SELECT customer.address.city AS city, count() AS orders, math::sum(total) AS revenue FROM order GROUP BY city ORDER BY revenue DESC LIMIT 10 START 0")
# The per-group function reads a link through `Grouped`'s own cut.
expect Surreal.from(orders).group_by(|o| o.total).aggregate(|total, rows| { total, paris: rows.keep_if(|o| o.customer.get().address.city == "Paris").len() }).to_surql() == Ok("SELECT count(customer.address.city = 'Paris') AS paris, total AS total FROM order GROUP BY total")
expect Surreal.from(orders).select(|o| { id: o.id, total: o.total }).order_by(|r| r.total, Asc).order_by(|r| r.id, Desc).to_surql() == Ok("SELECT record::id(id) AS id, total AS total FROM order ORDER BY total, id DESC")
expect Surreal.from(orders).select_value(|o| o.total).order_by(|t| t, Desc).limit(2).to_surql() == Ok("SELECT VALUE total FROM order ORDER BY total DESC LIMIT 2")
expect Surreal.from(orders).select_value(|o| o.customer.get().name).to_surql() == Ok("SELECT VALUE customer.name FROM order")

# The steps run as they read. `order_by`, then `start`, then `limit`, each at
# most once: `.limit(2).order_by(..)`, `.limit(10).start(20)` and a second
# `limit` or `start` are type errors (a `Limited` and a `Started` have no such
# method). To order the rows of a limit, take them as a subquery.
expect Surreal.from(orders).select(order_line).order_by(|r| r.total, Desc).start(2).limit(2).to_surql() == Ok("SELECT total AS total, customer.name AS who FROM order ORDER BY total DESC LIMIT 2 START 2")
expect Surreal.from(orders).select(order_line).limit(2).query().select(|r| r).order_by(|r| r.total, Desc).to_surql() == Ok("SELECT total, who FROM (SELECT total AS total, customer.name AS who FROM order ORDER BY id LIMIT 2) ORDER BY total DESC")
# SurrealDB orders by a field path only. It accepts a path through a link
# or into a column and leaves the rows unordered, and refuses a call, so the
# key is one column of the result.
column_order : Surreal.Error
column_order = Unsupported("`order_by` orders by one column of the result, `|r| r.column`: SurrealDB orders by a field path only, and does not order by a path into a column or through a link (it accepts one and leaves the rows unordered). Select the value as a column of its own and order by that column")

expect Surreal.from(orders).select(|o| { id: o.id, customer: o.customer }).order_by(|r| r.customer.get().name, Asc).to_surql() == Err(column_order)
expect Surreal.from(customers).select(|c| c).order_by(|r| r.address.city, Asc).to_surql() == Err(column_order)
expect Surreal.from(customers).select(|c| c).order_by(|r| r.name.count_utf8_bytes(), Asc).to_surql() == Err(column_order)
expect Surreal.from(orders).select(|o| { id: o.id, who: o.customer.get().name }).order_by(|r| r.who, Asc).to_surql() == Ok("SELECT record::id(id) AS id, customer.name AS who FROM order ORDER BY who")
# A `select_value` is ordered by a path of the source row: the value, or a
# field of it, with no link, `id` or computed value on the way.
value_order : Surreal.Error
value_order = Unsupported("`order_by` of a `select_value` reads the value as a field path of the source row, and this value is computed, read through a link or `id`: SurrealDB orders by a field path only. Take `select` with the value as a column and order by the column")

expect Surreal.from(customers).select_value(|c| c.address).order_by(|a| a.city, Desc).to_surql() == Ok("SELECT VALUE address FROM customer ORDER BY address.city DESC")
expect Surreal.from(orders).select_value(|o| o.total * 2).order_by(|t| t, Desc).to_surql() == Err(value_order)
expect Surreal.from(orders).select_value(|o| o.customer.get().name).order_by(|n| n, Asc).to_surql() == Err(value_order)
expect Surreal.from(orders).select_value(|o| o.id).order_by(|i| i, Asc).to_surql() == Err(value_order)
# A row of values of a subquery is `$this`, not a field path.
expect Surreal.from(orders).select_value(|o| o.total).order_by(|t| t, Desc).limit(3).filter(|t| t < 100).order_by(|t| t, Asc).to_surql() == Err(value_order)
# A whole row as a value is the fields of its type, with `id` as the key.
expect Surreal.from(customers).select_value(|c| c).to_surql() == Ok("SELECT VALUE { address: address, id: record::id(id), name: name, tags: tags } FROM customer")
expect Surreal.from(customers).select_value(|c| c).order_by(|c| c.name, Asc).to_surql() == Ok("SELECT VALUE { address: address, id: record::id(id), name: name, tags: tags } FROM customer ORDER BY name")
# A group key has a part, and each part is a column of the result.
expect Surreal.from(orders).group_by(|_| {}).aggregate(|_, rows| { n: rows.len().to_i64_wrap() }).to_surql() == Err(Unsupported("`group_by(|_| {})` groups by a key of no parts, and SurrealDB has no `GROUP BY` of nothing. `GROUP ALL` is not the same: it gives one row for no rows. Take `totals`"))
expect Surreal.from(orders).group_by(|o| o.total).aggregate(|_, rows| { n: rows.len().to_i64_wrap() }).to_surql() == Err(Unsupported("the group key part `total` is not a column of the result: SurrealDB groups by a selected column only (\"Missing group idiom\"). Return the key, or its part, from the function of `aggregate`"))
expect Surreal.from(orders).totals(|rows| { n: rows.len(), revenue: rows.map(|o| o.total).sum() }).to_surql() == Ok("SELECT count() AS n, math::sum(total) AS revenue FROM order GROUP ALL")
expect Surreal.from(orders).filter(|o| o.total > 10).totals(|rows| { big: rows.keep_if(|o| o.payment == Cash).len(), mean: Surreal.Math.mean(rows.map(|o| o.total.to_f64())) }).to_surql() == Ok("SELECT count(payment = 'Cash') AS big, math::mean(<float>total) AS mean FROM order WHERE total > 10.0dec GROUP ALL")
expect Surreal.from(orders).totals(|rows| { mid: Surreal.Math.median(rows.map(|o| o.total.to_f64())) }).to_surql() == Err(Unsupported("in `totals`: `math::median` of no rows is `NONE`, not a number, and `totals` always gives one row; take the median per group with `group_by`"))
expect Surreal.from(orders).filter_by(|p, o| o.total > p.least).totals(|rows| { n: rows.len() }).prepare({ least: 2 }).request() == Ok("LET $least = 2.0dec;\nSELECT count() AS n FROM order WHERE total > $least GROUP ALL;")
# A `U64` parameter: an `int`, or a decimal above the range of an `int`.
expect Surreal.from(orders).filter_by(|p, o| o.items.len() >= p.least).select_value(|o| o.id).prepare({ least: 2 }).request() == Ok("LET $least = 2;\nSELECT VALUE record::id(id) FROM order WHERE $least <= items.len();")
expect Surreal.from(orders).filter_by(|p, o| o.items.len() >= p.least).select_value(|o| o.id).prepare({ least: 18446744073709551615 }).request() == Ok("LET $least = 18446744073709551615.0dec;\nSELECT VALUE record::id(id) FROM order WHERE $least <= items.len();")

# ------------------------------------------------------ query fragments

# A fragment takes a query over any row that has the fields it reads. Each
# clause in it is described at the row of each query that uses it, so the
# SurrealQL is the same as a clause written for that row.

## The edges that start at the customer whose key is the parameter `who`.
started_by : Surreal.Query({ who : Str, ..p }, { from : Surreal.Link({ id : Str, ..c }), ..r }) -> Surreal.Query({ who : Str, ..p }, { from : Surreal.Link({ id : Str, ..c }), ..r })
started_by = |q| q.filter_by(|params, e| e.from.get().id == params.who)

## The result rows in the order of their `id`.
by_id : Surreal.Selected(p, { id : Str, ..r }) -> Surreal.Selected(p, { id : Str, ..r })
by_id = |s| s.order_by(|r| r.id, Asc)

## A fragment that calls the two above.
edge_ids : Surreal.Query({ who : Str, ..p }, { id : Str, from : Surreal.Link({ id : Str, ..c }), ..r }) -> Surreal.Selected({ who : Str, ..p }, { id : Str })
edge_ids = |q| by_id(started_by(q).select(|e| { id: e.id }))

## The whole row of any table, ordered: its columns are those of the row
## each use gives.
whole_by_id : Surreal.Query(p, { id : Str, ..r }) -> Surreal.Selected(p, { id : Str, ..r })
whole_by_id = |q| by_id(q.select(|r| r))

expect by_id(started_by(Surreal.from(purchased)).select(|e| { id: e.id, n: e.quantity })).to_surql() == Ok("SELECT record::id(id) AS id, quantity AS n FROM purchased WHERE record::id(in) = $who ORDER BY id")
expect by_id(started_by(Surreal.from(reviewed)).select(|e| { id: e.id, stars: e.stars })).to_surql() == Ok("SELECT record::id(id) AS id, stars AS stars FROM reviewed WHERE record::id(in) = $who ORDER BY id")
expect edge_ids(Surreal.from(reviewed)).to_surql() == Ok("SELECT record::id(id) AS id FROM reviewed WHERE record::id(in) = $who ORDER BY id")

## The edges that start at the link whose id is the parameter `from`, read with the field `link.id`.
started_at : Surreal.Query({ from : Surreal.Id(c), ..p }, { from : Surreal.Link(c), ..r }) -> Surreal.Query({ from : Surreal.Id(c), ..p }, { from : Surreal.Link(c), ..r })
started_at = |q| q.filter_by(|params, e| e.from.id == params.from)

started_at_method : Surreal.Query({ from : Surreal.Id(c), ..p }, { from : Surreal.Link(c), ..r }) -> Surreal.Query({ from : Surreal.Id(c), ..p }, { from : Surreal.Link(c), ..r })
started_at_method = |q| q.filter_by(|params, e| e.from.id() == params.from)

expect started_at(Surreal.from(purchased)).select(|e| { id: e.id }).to_surql() == Ok("SELECT record::id(id) AS id FROM purchased WHERE in = $from")
expect started_at(Surreal.from(purchased)).select(|e| { id: e.id }).to_surql() == started_at_method(Surreal.from(purchased)).select(|e| { id: e.id }).to_surql()
expect whole_by_id(Surreal.from(products)).to_surql() == Ok("SELECT record::id(id) AS id, price, title FROM product ORDER BY id")
expect whole_by_id(Surreal.from(customers)).to_surql() == Ok("SELECT address, record::id(id) AS id, name, tags FROM customer ORDER BY id")

# ------------------------------------------------------ whole rows

# A whole row has the fields of its Roc type, with `id` as the key.
expect Surreal.from(customers).select(|r| r).to_surql() == Ok("SELECT address, record::id(id) AS id, name, tags FROM customer")
expect Surreal.from(purchased).select(|r| r).to_surql() == Ok("SELECT in AS ⟨from⟩, record::id(id) AS id, quantity, out AS to FROM purchased")
expect Surreal.from(customers).outgoing(purchased).select(|r| r).to_surql() == Err(Unsupported("in `select`: a pair of a row and its edges is not a record; select its columns with `select(|(row, edges)| { .. })`"))
# A whole linked row is a destructure of the same fields: a link, a link in a list of records, an edge end, an edge.
expect Surreal.from(orders).select(|o| { customer: o.customer.get(), total: o.total }).to_surql() == Ok("SELECT customer.{ address, id: record::id(id), name, tags } AS customer, total AS total FROM order")
expect Surreal.from(orders).select_value(|o| o.customer.get()).to_surql() == Ok("SELECT VALUE customer.{ address, id: record::id(id), name, tags } FROM order")
expect Surreal.from(orders).select(|o| { products: o.items.map(|i| i.product.get()) }).to_surql() == Ok("SELECT items.map(|$v1| $v1.product.{ id: record::id(id), price, title }) AS products FROM order")
expect Surreal.from(purchased).select(|e| { buyer: e.from.get(), id: e.id }).to_surql() == Ok("SELECT in.{ address, id: record::id(id), name, tags } AS buyer, record::id(id) AS id FROM purchased")
expect Surreal.from(customers).outgoing(purchased).select(|(c, bought)| { name: c.name, edges: bought.map(|e| e) }).to_surql() == Ok("SELECT ->purchased.{ from: in, id: record::id(id), quantity, to: out } AS edges, name AS name FROM customer")

# A whole row through an optional link: a `Try`, NONE for `Err`.
Member : { id : Str, sponsor ?: Surreal.Link(Customer) }

members : Surreal.Table(Member)
members = Surreal.table("member")

SponsorLine : { id : Str, sponsor : Try(Customer, [NoSponsor]) }

sponsor_line : Member -> SponsorLine
sponsor_line = |m| {
	id: m.id,
	sponsor: match m.?sponsor {
		Ok(s) => Ok(s.get())
		Err(_) => Err(NoSponsor)
	},
}

expect Surreal.from(members).select(sponsor_line).to_surql() == Ok("SELECT record::id(id) AS id, (IF sponsor IS NONE THEN NONE ELSE sponsor.{ address, id: record::id(id), name, tags } END) AS sponsor FROM member")
expect Surreal.from(members).select(|m| { sponsor: m.?sponsor.map_ok(|s| s.get()) }).to_surql() == Ok("SELECT (IF sponsor IS NONE THEN NONE ELSE sponsor.{ address, id: record::id(id), name, tags } END) AS sponsor FROM member")
expect Surreal.from(members).select(|m| { name: m.?sponsor.map_ok(|s| s.get().name) ?? "none" }).to_surql() == Ok("SELECT sponsor.name ?? 'none' AS name FROM member")
expect Surreal.from(members).select(|m| { zip: m.?sponsor.map_ok(|s| s.get().address.?zip) }).to_surql() == Err(Unsupported("in `select`: a `Try` that holds a `Try` has no SurrealQL form; NONE stands for the error of both"))
# Without the annotation, `Ok` and `Err` are tags of a union.
expect Surreal.from(members).select(
	|m| {
		sponsor: match m.?sponsor {
			Ok(s) => Ok(s.get())
			Err(_) => Err(NoSponsor)
		},
	},
).to_surql() == Err(Unsupported("in `select`: the payload of `Ok` is a record the clause does not build field by field; annotate the value as a `Try`, whose `Err` is NONE"))

# An optional record: a path of fields folds the test of NONE (a field of NONE
# is NONE). A call, or a link traversal in a `match`, keeps it.
Tagged : { id : Str, chip ?: { code : Str, vet : Surreal.Link(Customer) } }

tagged : Surreal.Table(Tagged)
tagged = Surreal.table("tagged")

expect Surreal.from(tagged).select_value(|t| t.?chip.map_ok(|c| c.code) ?? "none").to_surql() == Ok("SELECT VALUE chip.code ?? 'none' FROM tagged")
expect Surreal.from(tagged).select_value(|t| t.?chip.map_ok(|c| c.code)).to_surql() == Ok("SELECT VALUE chip.code FROM tagged")
expect Surreal.from(tagged).select_value(|t| t.?chip.map_ok(|c| c.code == "x") ?? Bool.False).to_surql() == Ok("SELECT VALUE (IF chip IS NONE THEN NONE ELSE chip.code = 'x' END) ?? false FROM tagged")
expect Surreal.from(tagged).select_value(
	|t| match t.?chip {
		Ok(c) => c.code
		Err(_) => "none"
	},
).to_surql() == Ok("SELECT VALUE chip.code ?? 'none' FROM tagged")
expect Surreal.from(tagged).select_value(
	|t| match t.?chip {
		Ok(c) => c.vet.get().name
		Err(_) => "none"
	},
).to_surql() == Ok("SELECT VALUE (IF chip IS NONE THEN 'none' ELSE chip.vet.name END) FROM tagged")

# ------------------------------------------------------ result rows

OrderLine : { who : Str, total : Dec }

order_line : Order -> OrderLine
order_line = |o| { who: o.customer.get().name, total: o.total }

# A filter of a projection reads its fields over the source row, in the same `WHERE`.
expect Surreal.from(orders).select(order_line).filter(|r| r.who == "Ada").to_surql() == Ok("SELECT total AS total, customer.name AS who FROM order WHERE customer.name = 'Ada'")
expect Surreal.from(orders).filter(|o| o.total > 10).select(order_line).filter(|r| r.who != "").to_surql() == Ok("SELECT total AS total, customer.name AS who FROM order WHERE (total > 10.0dec) AND (customer.name != '')")
# An order does not change which rows a filter keeps, so the filter stays in the one `SELECT`.
expect Surreal.from(orders).select(order_line).order_by(|r| r.total, Desc).filter(|r| r.who == "Ada").to_surql() == Ok("SELECT total AS total, customer.name AS who FROM order WHERE customer.name = 'Ada' ORDER BY total DESC")
expect Surreal.from(orders).select_value(|o| o.total).filter(|t| t < 100).to_surql() == Ok("SELECT VALUE total FROM order WHERE total < 100.0dec")
expect Surreal.from(orders).select(|r| r).filter(|o| o.total > 5).to_surql() == Ok("SELECT customer, record::id(id) AS id, items, payment, total FROM order WHERE total > 5.0dec")
# After a group, a limit or a start, a filter reads a subquery. After a group, that is `HAVING`.
expect Surreal.from(orders).group_by(|o| o.customer.get().address.city).aggregate(|city, rows| { city, revenue: rows.map(|o| o.total).sum() }).filter(|r| r.revenue > 100).to_surql() == Ok("SELECT city, revenue FROM (SELECT customer.address.city AS city, math::sum(total) AS revenue FROM order GROUP BY city) WHERE revenue > 100.0dec")
expect Surreal.from(orders).select(order_line).order_by(|r| r.total, Desc).limit(3).filter(|r| r.who != "Ada").to_surql() == Ok("SELECT total, who FROM (SELECT total AS total, customer.name AS who FROM order ORDER BY total DESC LIMIT 3) WHERE who != 'Ada'")
expect Surreal.from(orders).select(order_line).start(1).filter(|r| r.who != "Ada").to_surql() == Ok("SELECT total, who FROM (SELECT total AS total, customer.name AS who FROM order ORDER BY id START 1) WHERE who != 'Ada'")
expect Surreal.from(orders).select(|r| r).limit(2).filter(|o| o.total > 5).to_surql() == Ok("SELECT customer, id, items, payment, total FROM (SELECT customer, record::id(id) AS id, items, payment, total FROM order ORDER BY id LIMIT 2) WHERE total > 5.0dec")
# A row of values is `$this` in the outer query.
expect Surreal.from(orders).select_value(|o| o.total).order_by(|t| t, Desc).limit(3).filter(|t| t < 100).to_surql() == Ok("SELECT VALUE $this FROM (SELECT VALUE total FROM order ORDER BY total DESC LIMIT 3) WHERE $this < 100.0dec")
expect Surreal.from(orders).select(|o| { t: o.total }).limit(1).query().select_value(|r| r).to_surql() == Ok("SELECT VALUE $this FROM (SELECT total AS t FROM order ORDER BY id LIMIT 1)")
# `query` makes the result rows the rows of a new query: one `SELECT` after a projection.
expect Surreal.from(orders).select(|o| { who: o.customer.get().name, city: o.customer.get().address.city }).query().filter(|r| r.city == "Paris").select(|r| { who: r.who }).to_surql() == Ok("SELECT customer.name AS who FROM order WHERE customer.address.city = 'Paris'")
expect Surreal.from(orders).select(|o| { city: o.customer.get().address.city }).query().group_by(|r| r.city).aggregate(|city, rows| { city, n: rows.len() }).to_surql() == Ok("SELECT customer.address.city AS city, count() AS n FROM order GROUP BY city")
expect Surreal.from(orders).select(|o| { who: o.customer.get().name, owner: o.customer.get() }).query().select(|r| r).to_surql() == Ok("SELECT customer.{ address, id: record::id(id), name, tags } AS owner, customer.name AS who FROM order")
expect Surreal.from(orders).select_value(|o| o.customer.get()).limit(1).query().select_value(|c| c.address.city).to_surql() == Ok("SELECT VALUE address.city FROM (SELECT VALUE customer.{ address, id: record::id(id), name, tags } FROM order ORDER BY id LIMIT 1)")
# A parameter of a filter over a subquery is a `LET`, as anywhere.
expect Surreal.from(orders).group_by(|o| o.customer.get().address.city).aggregate(|city, rows| { city, n: rows.len().to_i64_wrap() }).query().filter_by(|p, r| r.n >= p.least).select(|r| r).prepare({ least: 2 }).request() == Ok("LET $least = 2;\nSELECT city, n FROM (SELECT customer.address.city AS city, count() AS n FROM order GROUP BY city) WHERE $least <= n;")
# A row of the table keeps its edges after a projection of the whole row. A row of a subquery has none.
expect Surreal.from(customers).select(|r| r).query().outgoing(purchased).select(|(c, bought)| { name: c.name, n: bought.len() }).to_surql() == Ok("SELECT ->purchased.len() AS n, name AS name FROM customer")
expect Surreal.from(customers).select(|r| r).limit(2).query().outgoing(purchased).select(|(c, bought)| { name: c.name, n: bought.len() }).to_surql() == Err(Unsupported("only a row of a table has edges; take `outgoing` or `incoming` before `select`"))
expect Surreal.from(orders).select(order_line).limit(2).query().group_by(|r| r.who).aggregate(|who, rows| { who, n: rows.len() }).to_surql() == Ok("SELECT count() AS n, who AS who FROM (SELECT total AS total, customer.name AS who FROM order ORDER BY id LIMIT 2) GROUP BY who")

# ------------------------------------------------------ unchecked

# `SELECT *` and `FETCH` are outside the types: the row has no Roc fields.
expect Surreal.Unchecked.select_star(Surreal.from(orders)).to_surql() == Ok("SELECT * FROM order")
expect Surreal.Unchecked.fetch(Surreal.Unchecked.select_star(Surreal.from(orders)), "customer").to_surql() == Ok("SELECT * FROM order FETCH customer")
expect Surreal.Unchecked.fetch(Surreal.Unchecked.fetch(Surreal.Unchecked.select_star(Surreal.from(orders).filter(|o| o.total > 10)), "customer"), "items[*].product").limit(5).to_surql() == Ok("SELECT * FROM order WHERE total > 10.0dec ORDER BY id LIMIT 5 FETCH customer, items[*].product")
# A filter after a fetch reads the source row. A query after it reads a subquery, which keeps the `FETCH`.
expect Surreal.Unchecked.fetch(Surreal.Unchecked.select_star(Surreal.from(orders)), "customer").filter(|_| Bool.True).to_surql() == Ok("SELECT * FROM order WHERE true FETCH customer")
expect Surreal.Unchecked.select_star(Surreal.Unchecked.fetch(Surreal.Unchecked.select_star(Surreal.from(orders)), "customer").query()).to_surql() == Ok("SELECT * FROM (SELECT * FROM order FETCH customer)")

# ------------------------------------------------------ parameters

by_min : Surreal.Selected(Params, Order)
by_min = Surreal.from(orders).filter_by(|p, o| o.total >= p.min_total).select(|r| r)

expect by_min.to_surql() == Ok("SELECT customer, record::id(id) AS id, items, payment, total FROM order WHERE total >= $min_total")
expect by_min.prepare({ min_total: 20 }).statement().map_ok(|st| st.surql) == Ok("SELECT customer, record::id(id) AS id, items, payment, total FROM order WHERE total >= $min_total")
expect by_min.prepare({ min_total: 20 }).statement().map_ok(|st| st.inlined) == Ok("SELECT customer, record::id(id) AS id, items, payment, total FROM order WHERE total >= 20.0dec")
expect by_min.prepare({ min_total: 20 }).statement().map_ok(|st| st.lets.map(|l| (l.name, Ql.literal(l.value)))) == Ok([("min_total", "20.0dec")])
expect by_min.prepare({ min_total: 20 }).request() == Ok("LET $min_total = 20.0dec;\nSELECT customer, record::id(id) AS id, items, payment, total FROM order WHERE total >= $min_total;")
expect by_min.prepare({ min_total: 20 }).statement().map_ok(|st| st.block("-- query: big_orders", ["-- ordered"])) == Ok("-- query: big_orders\n-- ordered\nLET $min_total = 20.0dec;\nSELECT customer, record::id(id) AS id, items, payment, total FROM order WHERE total >= $min_total;")
expect Surreal.from(orders).select(|r| r).prepare({}).request() == Ok("SELECT customer, record::id(id) AS id, items, payment, total FROM order;")

# A parameter that is a record, a list or an id is bound whole.
Window : { lo : Dec, tags : List(Str), who : Surreal.Id(Product) }

windowed : Surreal.Selected(Window, Order)
windowed = Surreal.from(orders).filter_by(|p, o| o.total >= p.lo and o.items.any(|i| i.product.id() == p.who)).select(|r| r)

expect windowed.prepare({ lo: 1, tags: ["a"], who: Surreal.Unchecked.id("product", "pen") }).statement().map_ok(|st| st.inlined) == Ok("SELECT customer, record::id(id) AS id, items, payment, total FROM order WHERE (total >= 1.0dec) AND (product:⟨pen⟩ IN items[*].product)")

# SurrealDB sets `$auth`, `$token`, `$session` and `$access` itself.
Locked : { session : Str }

locked : Surreal.Selected(Locked, Order)
locked = Surreal.from(orders).filter_by(|p, o| o.id == p.session).select(|r| r)

expect locked.prepare({ session: "x" }).statement().map_ok(|st| st.surql) == Err(Unsupported("`$session` is a protected variable in SurrealDB; name the parameter otherwise"))

## The request of a raw or a diff watch, or why it has none.
live_text = |built| match built {
	Ok(watch) => watch.request()
	Err(e) => Err(e)
}

# Values captured from the function around the clause.
orders_over : Dec, Surreal.Id(Product) -> Surreal.Prepared(List(Order))
orders_over = |min, pen| Surreal.from(orders).filter(|o| o.total >= min and o.items.any(|i| i.product.id() == pen)).ready()

expect orders_over(5, Surreal.Unchecked.id("product", "pen")).statement().map_ok(|st| st.inlined) == Ok("SELECT customer, record::id(id) AS id, items, payment, total FROM order WHERE (total >= 5.0dec) AND (product:⟨pen⟩ IN items[*].product)")
expect orders_over(5, Surreal.Unchecked.id("product", "pen")).request() == Ok("LET $_1 = 5.0dec;\nLET $_2 = product:⟨pen⟩;\nSELECT customer, record::id(id) AS id, items, payment, total FROM order WHERE (total >= $_1) AND ($_2 IN items[*].product);")

# ------------------------------------------------------------ writes

pen : Product
pen = { id: "pen", title: "Pen", price: 1.5 }

mug : Product
mug = { id: "mug", title: "O'Mug", price: 4 }

edge1 : Edge
edge1 = { id: "e1", from: customers.link("ada"), to: products.link("pen"), quantity: 2 }

Edge : Purchased

expect products.insert([pen, mug]).statement().map_ok(|st| st.surql) == Ok("BEGIN;\nINSERT INTO product [{ id: 'pen', price: 1.5dec, title: 'Pen' }, { id: 'mug', price: 4.0dec, title: 'O\\'Mug' }] RETURN AFTER;\nCOMMIT")
expect products.insert([pen]).request() == Ok("BEGIN;\nINSERT INTO product [{ id: 'pen', price: 1.5dec, title: 'Pen' }] RETURN AFTER;\nCOMMIT;")
expect products.insert([]).statement().map_ok(|st| st.surql) == Ok("BEGIN;\nINSERT INTO product [] RETURN AFTER;\nCOMMIT")
expect purchased.insert([edge1]).statement().map_ok(|st| st.surql) == Ok("BEGIN;\nINSERT RELATION INTO purchased [{ in: customer:⟨ada⟩, id: 'e1', quantity: 2, out: product:⟨pen⟩ }] RETURN AFTER;\nCOMMIT")
expect products.create(pen).statement().map_ok(|st| st.surql) == Ok("CREATE product:⟨pen⟩ CONTENT { price: 1.5dec, title: 'Pen' } RETURN AFTER")
expect products.upsert(mug).statement().map_ok(|st| st.surql) == Ok("UPSERT product:⟨mug⟩ CONTENT { price: 4.0dec, title: 'O\\'Mug' } RETURN AFTER")
expect purchased.create(edge1).statement().map_ok(|st| st.surql) == Ok("RELATE customer:⟨ada⟩->purchased:⟨e1⟩->product:⟨pen⟩ CONTENT { quantity: 2 } RETURN AFTER")

# Rows whose keys the server makes: each row without its `id`, and the
# rows of the result are `Created`, with the key that the server gave.
expect products.create_new({ title: "Pen", price: 1.5 }).statement().map_ok(|st| st.surql) == Ok("CREATE product CONTENT { price: 1.5dec, title: 'Pen' } RETURN AFTER")
expect products.insert_new([{ title: "Pen", price: 1.5 }, { title: "O'Mug", price: 4 }]).statement().map_ok(|st| st.surql) == Ok("BEGIN;\nINSERT INTO product [{ price: 1.5dec, title: 'Pen' }, { price: 4.0dec, title: 'O\\'Mug' }] RETURN AFTER;\nCOMMIT")
expect purchased.create_new({ from: customers.link("ada"), to: products.link("01K8Z3"), quantity: 2 }).statement().map_ok(|st| st.surql) == Ok("RELATE customer:⟨ada⟩->purchased->product:⟨01K8Z3⟩ CONTENT { quantity: 2 } RETURN AFTER")
expect purchased.insert_new([{ from: customers.link("ada"), to: products.link("pen"), quantity: 2 }]).statement().map_ok(|st| st.surql) == Ok("BEGIN;\nINSERT RELATION INTO purchased [{ in: customer:⟨ada⟩, quantity: 2, out: product:⟨pen⟩ }] RETURN AFTER;\nCOMMIT")
expect orders.update(|o| o.total > 100, |o| { ..o, total: o.total * 0.9, payment: Cash }).to_surql() == Ok("UPDATE order SET payment = 'Cash', total = total * 0.9dec WHERE total > 100.0dec")
expect orders.update(|o| o.total > 100, |o| o).to_surql() == Err(Unsupported("in the patch of `update`: this update changes no field"))
expect orders.update(|o| o.total > 100, |o| { ..o, id: "x" }).to_surql() == Err(Unsupported("in the patch of `update`: an update cannot change `id`, the record key"))
expect orders.delete(|o| o.items.is_empty()).to_surql() == Ok("DELETE order WHERE items.len() = 0")
expect customers.update(|c| c.name == "", |c| { ..c, name: Surreal.Rand.ulid() }).to_surql() == Ok("UPDATE customer SET name = rand::ulid() WHERE name = ''")
expect orders.update(|o| o.total > 100, |o| { ..o, payment: Card({ last4: o.customer.id().key() }) }).to_surql() == Ok("UPDATE order SET payment = { kind: 'Card', last4: record::id(customer) } WHERE total > 100.0dec")
expect customers.update(|c| c.name != "", |c| { ..c, tags: [c.name] }).to_surql() == Ok("UPDATE customer SET tags = [name] WHERE name != ''")
expect customers.update(|c| c.name == Surreal.Rand.ulid(), |c| { ..c, name: "x" }).to_surql() == Err(Unsupported("in the condition of `update`: `Surreal.Rand.ulid` gives a new value on every call: use it in a default, a computed field or an update"))

# An update of a record field with an optional field: `..c.address` is a
# presence switch on `zip`, and the patch sets the one field it changes.
expect customers.update(|c| c.name == "Ada", |c| { ..c, address: { ..c.address, city: "Rome" } }).to_surql() == Ok("UPDATE customer SET address.city = 'Rome' WHERE name = 'Ada'")

# A patch of only the fields it sets.
expect orders.set(|o| o.total > 100, |o| { total: o.total * 0.9, payment: Cash }).to_surql() == Ok("UPDATE order SET payment = 'Cash', total = total * 0.9dec WHERE total > 100.0dec")
expect customers.set(|c| c.name == "Ada", |_| { tags: ["vip"] }).to_surql() == Ok("UPDATE customer SET tags = ['vip'] WHERE name = 'Ada'")
expect customers.set(|c| c.name == "Ada", |_| { nmae: "typo" }).to_surql() == Err(BadSchema("the row has no field `nmae`, so a patch cannot set it; it has `address`, `id`, `name`, `tags`"))
expect orders.set(|o| o.total > 100, |_| { id: "x" }).to_surql() == Err(Unsupported("in the patch of `set`: an update cannot change `id`, the record key"))
expect daily.set(|d| d.readings > 0, |_| { high: 0 }).to_surql() == Err(Unsupported("`reading_daily` is a view, and a view is read-only"))

Rename : { key : Str, name : Str }

rename : Surreal.Write(Rename, Customer)
rename = customers.set_by(|p, c| c.id == p.key, |p, _| { name: p.name })

expect rename.prepare({ key: "ada", name: "Ada L." }).request() == Ok("LET $key = 'ada';\nLET $name = 'Ada L.';\nUPDATE customer SET name = $name WHERE id = type::record('customer', $key) RETURN AFTER;")

# A key compared with a value given to the statement is the record id, which
# SurrealDB reads as one record (`RecordIdScan`), where `record::id(id)` scans
# the table. A key compared with a field of the row stays `record::id(id)`.
expect Surreal.from(customers).filter(|c| c.id == "ada").select(|c| { name: c.name }).to_surql() == Ok("SELECT name AS name FROM customer WHERE id = customer:⟨ada⟩")
expect Surreal.from(customers).filter(|c| "ada" != c.id).select(|c| { name: c.name }).to_surql() == Ok("SELECT name AS name FROM customer WHERE id != customer:⟨ada⟩")
expect Surreal.from(customers).filter(|c| c.id == "o'neil⟩").select(|c| { name: c.name }).to_surql() == Ok("SELECT name AS name FROM customer WHERE id = customer:⟨o'neil\\u{27E9}⟩")
expect Surreal.from(customers).filter_by(|p, c| c.id == p.key).select(|c| { name: c.name }).to_surql() == Ok("SELECT name AS name FROM customer WHERE id = type::record('customer', $key)")
expect Surreal.from(customers).filter(|c| c.id == c.name).select(|c| { name: c.name }).to_surql() == Ok("SELECT name AS name FROM customer WHERE record::id(id) = name")
expect Surreal.from(purchased).filter(|e| e.id == "p1").select(|e| { n: e.quantity }).to_surql() == Ok("SELECT quantity AS n FROM purchased WHERE id = purchased:⟨p1⟩")
expect Surreal.from(customers).outgoing(purchased).filter(|(c, _)| c.id == "ada").select(|(c, _)| { name: c.name }).to_surql() == Ok("SELECT name AS name FROM customer WHERE id = customer:⟨ada⟩")
expect customers.delete(|c| c.id == "ada").to_surql() == Ok("DELETE customer WHERE id = customer:⟨ada⟩")
# The row before a write is not the row the statement reads: no record id.
expect request_of(Surreal.from(customers).filter(|c| c.id == "ada").select_value(|c| c.name).live({}, [])) == Ok("LIVE SELECT VALUE { row: name, now: true } FROM customer WHERE id = customer:⟨ada⟩;\nSELECT VALUE { ref: id, row: name } FROM customer WHERE id = customer:⟨ada⟩;")

# By key: the record of one key, written as an escaped record id, so any
# text is one key. SurrealDB reads and writes the one record.
ada : Surreal.Id(Customer)
ada = customers.id("ada")

expect customers.at(ada).select(|c| { name: c.name }).to_surql() == Ok("SELECT name AS name FROM customer:⟨ada⟩")
expect customers.at(Surreal.Unchecked.id("customer", "x⟩; DELETE customer")).select(|c| { name: c.name }).to_surql() == Ok("SELECT name AS name FROM customer:⟨x\\u{27E9}; DELETE customer⟩")
expect customers.at(ada).filter(|c| c.name != "").select_value(|c| c.name).to_surql() == Ok("SELECT VALUE name FROM customer:⟨ada⟩ WHERE name != ''")
expect customers.at(Surreal.Unchecked.id("order", "ada")).select(|c| { name: c.name }).to_surql() == Err(Unsupported("the id `order:⟨ada⟩` is not of the table `customer`"))
expect customers.at(ada).select_value(|c| c.name).live({}, []).request() == Err(Unsupported("a live query reads a whole table, not the record of one key; filter on `v.id`"))
expect Surreal.from(readings).select_value(|r| r.level).prepare_one({}).request() == Err(Unsupported("`prepare_one` reads the row of one key, a query from `Table.at`; this query can return several rows: take `prepare`"))
expect customers.at(ada).select_value(|c| c.name).prepare_one({}).request() == Ok("SELECT VALUE name FROM customer:⟨ada⟩;")

# No parameter: `ready` is `prepare({})`. A `Query` has the whole rows, so
# `prepare` and `live` need no `select(|r| r)`.
request_text : Surreal.Prepared(out) -> Try(Str, Surreal.Error)
request_text = |prepared| prepared.request()

expect request_text(Surreal.from(customers).select(|c| { name: c.name }).ready()) == Ok("SELECT name AS name FROM customer;")
expect request_text(Surreal.from(customers).select(|c| { name: c.name }).limit(2).ready()) == Ok("SELECT name AS name FROM customer ORDER BY id LIMIT 2;")
expect request_text(Surreal.from(customers).select(|c| { name: c.name }).start(1).ready()) == Ok("SELECT name AS name FROM customer ORDER BY id START 1;")
expect request_text(customers.update_at(ada, |c| { ..c, name: "Ada L." }).ready()) == Ok("UPDATE customer:⟨ada⟩ SET name = 'Ada L.' RETURN AFTER;")
expect request_text(customers.delete_at(ada).ready()) == Ok("DELETE customer:⟨ada⟩ RETURN BEFORE;")
expect request_text(Surreal.from(orders).totals(|rows| { n: rows.len() }).ready()) == Ok("SELECT count() AS n FROM order GROUP ALL;")
expect request_text(customers.at(ada).select_value(|c| c.name).ready_one()) == Ok("SELECT VALUE name FROM customer:⟨ada⟩;")
expect request_text(Surreal.from(readings).select_value(|r| r.level).ready_one()) == Err(Unsupported("`prepare_one` reads the row of one key, a query from `Table.at`; this query can return several rows: take `prepare`"))

# The whole rows of a `Query` are those of `select(|r| r)`.
expect request_text(Surreal.from(orders).ready()) == request_text(Surreal.from(orders).select(|r| r).ready())
expect request_text(Surreal.from(orders).ready()) == Ok("SELECT customer, record::id(id) AS id, items, payment, total FROM order;")
expect request_text(Surreal.from(orders).filter(|o| o.total > 10).ready()) == request_text(Surreal.from(orders).filter(|o| o.total > 10).select(|r| r).ready())
expect request_text(Surreal.from(orders).filter_by(|p, o| o.total > p.min_total).prepare({ min_total: 2 })) == request_text(Surreal.from(orders).filter_by(|p, o| o.total > p.min_total).select(|r| r).prepare({ min_total: 2 }))
expect request_text(Surreal.from(orders).filter_by(|p, o| o.total > p.min_total).prepare({ min_total: 2 })) == Ok("LET $min_total = 2.0dec;\nSELECT customer, record::id(id) AS id, items, payment, total FROM order WHERE total > $min_total;")
expect request_text(customers.at(ada).ready_one()) == request_text(customers.at(ada).select(|r| r).ready_one())
expect request_text(customers.at(ada).prepare_one({})) == Ok("SELECT address, record::id(id) AS id, name, tags FROM customer:⟨ada⟩;")
expect request_text(Surreal.from(orders).ready_one()) == Err(Unsupported("`prepare_one` reads the row of one key, a query from `Table.at`; this query can return several rows: take `prepare`"))
expect request_of(Surreal.from(customers).filter(|c| c.name == "x").ready_live([])) == request_of(Surreal.from(customers).filter(|c| c.name == "x").select(|r| r).live({}, []))
expect request_of(Surreal.from(customers).filter_by(|p, c| c.name == p.name).live({ name: "x" }, [])) == request_of(Surreal.from(customers).filter_by(|p, c| c.name == p.name).select(|r| r).live({ name: "x" }, []))
expect request_of(Surreal.from(customers).ready_live([])) == Ok("LIVE SELECT VALUE { row: { address: address, id: record::id(id), name: name, tags: tags }, now: true } FROM customer;\nSELECT VALUE { ref: id, row: { address: address, id: record::id(id), name: name, tags: tags } } FROM customer;")
expect customers.update_at(ada, |c| { ..c, name: "Ada L." }).to_surql() == Ok("UPDATE customer:⟨ada⟩ SET name = 'Ada L.'")
expect customers.update_at(ada, |c| { ..c, id: "x" }).to_surql() == Err(Unsupported("in the patch of `update_at`: an update cannot change `id`, the record key"))
expect customers.update_at_by(ada, |p, c| { ..c, name: p.name }).prepare({ name: "Ada L." }).request() == Ok("LET $name = 'Ada L.';\nUPDATE customer:⟨ada⟩ SET name = $name RETURN AFTER;")
expect customers.set_at(ada, |_| { tags: ["vip"] }).to_surql() == Ok("UPDATE customer:⟨ada⟩ SET tags = ['vip']")
expect customers.set_at(ada, |_| { nmae: "typo" }).to_surql() == Err(BadSchema("the row has no field `nmae`, so a patch cannot set it; it has `address`, `id`, `name`, `tags`"))
expect customers.set_at_by(ada, |p, _| { name: p.name }).prepare({ name: "Ada L." }).statement().map_ok(|st| st.inlined) == Ok("UPDATE customer:⟨ada⟩ SET name = 'Ada L.' RETURN AFTER")
expect customers.delete_at(ada).to_surql() == Ok("DELETE customer:⟨ada⟩")
expect purchased.delete_at(Surreal.Unchecked.id("purchased", "p1")).to_surql() == Ok("DELETE purchased:⟨p1⟩")
expect daily.delete_at(Surreal.Unchecked.id("reading_daily", "x")).to_surql() == Err(Unsupported("`reading_daily` is a view, and a view is read-only"))
expect customers.replace({ id: "ada", name: "Ada", address: { city: "Rome" }, tags: [] }).request() == Ok("UPDATE customer:⟨ada⟩ CONTENT { address: { city: 'Rome' }, name: 'Ada', tags: [] } RETURN AFTER;")
# `insert_or_update`: the patch reads the new row at `$input` and the stored row by its fields.
expect products.insert_or_update([pen, mug], |new, old| { ..old, price: old.price + new.price, title: new.title }).statement().map_ok(|st| st.surql) == Ok("BEGIN;\nINSERT INTO product [{ id: 'pen', price: 1.5dec, title: 'Pen' }, { id: 'mug', price: 4.0dec, title: 'O\\'Mug' }] ON DUPLICATE KEY UPDATE price = price + $input.price, title = $input.title RETURN AFTER;\nCOMMIT")
expect products.insert_or_update([pen], |_, old| { ..old, price: old.price * 2 }).statement().map_ok(|st| st.surql) == Ok("BEGIN;\nINSERT INTO product [{ id: 'pen', price: 1.5dec, title: 'Pen' }] ON DUPLICATE KEY UPDATE price = price * 2.0dec RETURN AFTER;\nCOMMIT")
expect products.insert_or_update([pen], |_, old| { ..old, id: "x" }).statement().map_ok(|st| st.surql) == Err(Unsupported("in the patch of `insert_or_update`: an update cannot change `id`, the record key"))
expect purchased.insert_or_update([edge1], |_, old| { ..old, quantity: 1 }).statement().map_ok(|st| st.surql) == Err(Unsupported("`insert_or_update` is not defined for the relation table `purchased`"))
expect daily.insert_or_update([], |_, old| old).statement().map_ok(|st| st.surql) == Err(Unsupported("`reading_daily` is a view, and a view is read-only"))
# `merge_at`: a record of the app with only the fields to change.
expect customers.merge_at(ada, { name: "Ada L.", address: { city: "Rome" } }).statement().map_ok(|st| st.surql) == Ok("UPDATE customer:⟨ada⟩ MERGE { address: { city: 'Rome' }, name: 'Ada L.' } RETURN AFTER")
expect customers.merge_at(ada, { tags: ["vip"] }).request() == Ok("UPDATE customer:⟨ada⟩ MERGE { tags: ['vip'] } RETURN AFTER;")
expect customers.merge_at(ada, { id: "x" }).statement().map_ok(|st| st.surql) == Err(Unsupported("a merge cannot change `id`, the record key"))
expect customers.merge_at(Surreal.Unchecked.id("order", "ada"), { name: "x" }).statement().map_ok(|st| st.surql) == Err(Unsupported("the id `order:⟨ada⟩` is of the table `order`, not of `customer`"))
expect daily.merge_at(Surreal.Unchecked.id("reading_daily", "x"), { level: 1 }).statement().map_ok(|st| st.surql) == Err(Unsupported("`reading_daily` is a view, and a view is read-only"))
expect customers.upsert_merge_at(ada, { name: "Ada" }).statement().map_ok(|st| st.surql) == Ok("UPSERT customer:⟨ada⟩ MERGE { name: 'Ada' } RETURN AFTER")
expect customers.merge(|c| c.name == "Ada", { tags: ["vip"] }).statement().map_ok(|st| st.surql) == Ok("UPDATE customer MERGE { tags: ['vip'] } WHERE name = 'Ada' RETURN AFTER")
a_change : Diff.Op
a_change = match Diff.TextPatch.parse("@@ -1 +1 @@\n-a\n+b\n") {
	Ok(text_patch) => Change(["name"], text_patch)
	Err(_) => crash "a text patch"
}

# `patch_ops_at`: JSON Patch ops, the paths and values written as text.
expect customers.patch_ops_at(ada, [Replace(["name"], Cbor.Value.Text("Ada L.")), Add(["tags", "-"], Cbor.Value.Text("vip")), Remove(["address", "zip"])]).statement().map_ok(|st| st.surql) == Ok("UPDATE customer:⟨ada⟩ PATCH [{ op: 'replace', path: '/name', value: 'Ada L.' }, { op: 'add', path: '/tags/-', value: 'vip' }, { op: 'remove', path: '/address/zip' }] RETURN AFTER")
expect customers.patch_ops_at(ada, []).statement().map_ok(|st| st.surql) == Ok("UPDATE customer:⟨ada⟩ PATCH [] RETURN AFTER")
# A `/` or a `~` in a key is escaped in the path (RFC 6901), as SurrealDB 4 reads it.
expect customers.patch_ops_at(ada, [Replace(["notes", "a/b"], Cbor.Value.Int(1)), Remove(["notes", "c~d"]), Remove(["~1"])]).statement().map_ok(|st| st.surql) == Ok("UPDATE customer:⟨ada⟩ PATCH [{ op: 'replace', path: '/notes/a~1b', value: 1 }, { op: 'remove', path: '/notes/c~0d' }, { op: 'remove', path: '/~01' }] RETURN AFTER")
expect customers.patch_ops_at(ada, [Replace(["id"], Cbor.Value.Text("x"))]).statement().map_ok(|st| st.surql) == Err(Unsupported("a patch cannot change `id`, the record key (the op is at `/id`)"))
expect customers.patch_ops_at(ada, [Replace([], Cbor.Value.Null)]).statement().map_ok(|st| st.surql) == Err(Unsupported("a patch of a delete: delete the row with `delete_at`"))
expect customers.patch_ops_at(ada, [a_change]).statement().map_ok(|st| st.surql) == Err(Unsupported("a `change` op is a text diff, and the ORM reads it and does not write it; replay the field with a `replace`"))

Raise : { by : Dec, floor : Dec }

raise : Surreal.Write(Raise, Order)
raise = orders.update_by(|p, o| o.total < p.floor, |p, o| { ..o, total: o.total + p.by })

expect raise.to_surql() == Ok("UPDATE order SET total = total + $by WHERE total < $floor")
expect raise.prepare({ by: 5, floor: 10 }).request() == Ok("LET $by = 5.0dec;\nLET $floor = 10.0dec;\nUPDATE order SET total = total + $by WHERE total < $floor RETURN AFTER;")
expect raise.prepare({ by: 5, floor: 10 }).statement().map_ok(|st| st.inlined) == Ok("UPDATE order SET total = total + 5.0dec WHERE total < 10.0dec RETURN AFTER")

Cap : { max : Dec }

cap : Surreal.Write(Cap, Order)
cap = orders.delete_by(|p, o| o.total > p.max)

expect cap.prepare({ max: 1000 }).statement().map_ok(|st| st.inlined) == Ok("DELETE order WHERE total > 1000.0dec RETURN BEFORE")

# A write, then the rows it changed: one block.
expect {
	write = orders.update(|o| o.total > 100, |o| { ..o, payment: Cash }).prepare({})
	read = Surreal.from(orders).select(|r| r).prepare({})
	write.then(read).request() == Ok("UPDATE order SET payment = 'Cash' WHERE total > 100.0dec RETURN AFTER;\nSELECT customer, record::id(id) AS id, items, payment, total FROM order;")
}

# An optional parameter that is absent has no `LET`, so SurrealDB reads it as
# NONE, and the inlined text keeps its name.
Bounds : { lo : Dec, hi ?: Dec }

bounded : Surreal.Selected(Bounds, Order)
bounded = Surreal.from(orders).filter_by(|p, o| o.total >= p.lo and o.total <= (p.?hi ?? 1000)).select(|r| r)

expect bounded.prepare({ lo: 1 }).statement().map_ok(|st| st.lets.len()) == Ok(1)
expect bounded.prepare({ lo: 1, hi: 9 }).statement().map_ok(|st| st.lets.len()) == Ok(2)
expect bounded.prepare({ lo: 1 }).statement().map_ok(|st| st.inlined.contains("$hi")) == Ok(Bool.True)
expect bounded.prepare({ lo: 1, hi: 9 }).statement().map_ok(|st| st.inlined.contains("$hi")) == Ok(Bool.False)

# ------------------------------------------------------------ time series

Reading : { id : Surreal.TimeKey(Surreal.Id(Product)), level : I64 }

readings : Surreal.Table(Reading)
readings = Surreal.table("reading")

moment : Str -> Surreal.Datetime
moment = |text| match Surreal.datetime(text) {
	Ok(d) => d
	Err(_) => crash "a valid datetime"
}

morning : Reading
morning = { id: Surreal.time_key(pen_id, moment("2026-03-01T08:00:00Z")), level: 3 }

# The key is the array `[series, time]` in a write and in the record id.
expect readings.insert([morning]).statement().map_ok(|st| st.surql) == Ok("BEGIN;\nINSERT INTO reading [{ id: [product:⟨pen⟩, d'2026-03-01T08:00:00Z'], level: 3 }] RETURN AFTER;\nCOMMIT")
expect readings.create(morning).statement().map_ok(|st| st.surql) == Ok("CREATE reading:[product:⟨pen⟩, d'2026-03-01T08:00:00Z'] CONTENT { level: 3 } RETURN AFTER")
expect readings.upsert(morning).statement().map_ok(|st| st.surql) == Ok("UPSERT reading:[product:⟨pen⟩, d'2026-03-01T08:00:00Z'] CONTENT { level: 3 } RETURN AFTER")

# A range of keys of one series.
expect Surreal.from(readings).between(pen_id, moment("2026-03-01T00:00:00Z"), moment("2026-03-02T00:00:00Z")).select(|r| { at: r.id.time(), level: r.level }).to_surql() == Ok("SELECT record::id(id)[1] AS at, level AS level FROM reading:[product:⟨pen⟩, d'2026-03-01T00:00:00Z']..[product:⟨pen⟩, d'2026-03-02T00:00:00Z']")
expect Surreal.from(readings).between(pen_id, moment("2026-03-01T00:00:00Z"), moment("2026-03-02T00:00:00Z")).filter(|r| r.level > 2).select(|r| r).to_surql() == Ok("SELECT record::id(id) AS id, level FROM reading:[product:⟨pen⟩, d'2026-03-01T00:00:00Z']..[product:⟨pen⟩, d'2026-03-02T00:00:00Z'] WHERE level > 2")
expect Surreal.from(readings).between(pen_id, moment("2026-03-01T00:00:00Z"), moment("2026-03-02T00:00:00Z")).between(pen_id, moment("2026-03-01T00:00:00Z"), moment("2026-03-02T00:00:00Z")).select(|r| r).to_surql() == Err(Unsupported("a query takes one `between`"))
expect Surreal.from(readings).filter_by(|p, r| r.id.time() < p.before).select_value(|r| r.id.series()).prepare({ before: moment("2026-03-02T00:00:00Z") }).statement().map_ok(|st| st.inlined) == Ok("SELECT VALUE record::id(id)[0] FROM reading WHERE record::id(id)[1] < d'2026-03-02T00:00:00Z'")
expect readings.delete_by(|p, r| r.id.time() < p.before).to_surql() == Ok("DELETE reading WHERE record::id(id)[1] < $before")

# A key part that a column projects is grouped by the column's alias, so a
# call is never after `GROUP BY` ("Missing group idiom").
DayKey : { product : Surreal.Id(Product), day : Surreal.Datetime }

day_of : Reading -> DayKey
day_of = |r| { product: r.id.series(), day: Surreal.Time.floor(r.id.time(), Surreal.Time.days(1)) }

DayLine : { product : Surreal.Id(Product), day : Surreal.Datetime, readings : I64, high : I64 }

day_line : DayKey, List(Reading) -> DayLine
day_line = |k, rows| { product: k.product, day: k.day, readings: rows.len().to_i64_wrap(), high: rows.keep_if(|r| r.level > 5).len().to_i64_wrap() }

expect Surreal.from(readings).group_by(day_of).aggregate(day_line).to_surql() == Ok("SELECT time::floor(record::id(id)[1], 1d) AS day, count(level > 5) AS high, record::id(id)[0] AS product, count() AS readings FROM reading GROUP BY day, product")
# A part that no column projects is refused: SurrealDB says "Missing group idiom" (verified).
expect Surreal.from(readings).group_by(day_of).aggregate(|k, rows| { day: k.day, n: rows.len().to_i64_wrap() }).to_surql() == Err(Unsupported("the group key part `record::id(id)[0]` is not a column of the result: SurrealDB groups by a selected column only (\"Missing group idiom\"). Return the key, or its part, from the function of `aggregate`"))

# A view: its query is in the schema, and a write to it is refused.
daily : Surreal.Table(DayLine)
daily = Surreal.view("reading_daily")

expect daily.insert([]).statement().map_ok(|st| st.surql) == Err(Unsupported("`reading_daily` is a view, and a view is read-only"))
expect daily.create({ product: pen_id, day: moment("2026-03-01T00:00:00Z"), readings: 1, high: 0 }).statement().map_ok(|st| st.surql) == Err(Unsupported("`reading_daily` is a view, and a view is read-only"))
expect daily.delete(|d| d.readings > 0).to_surql() == Err(Unsupported("`reading_daily` is a view, and a view is read-only"))
expect daily.update(|d| d.readings > 0, |d| { ..d, high: 0 }).to_surql() == Err(Unsupported("`reading_daily` is a view, and a view is read-only"))
expect Surreal.from(daily).filter(|d| d.high > 0).select(|d| { day: d.day, high: d.high }).to_surql() == Ok("SELECT day AS day, high AS high FROM reading_daily WHERE high > 0")

# ------------------------------------------------------ geometry

Site : { id : Str, name : Str, location : Surreal.Point, area : Surreal.Polygon }

sites : Surreal.Table(Site)
sites = Surreal.table("site")

unit_square : Surreal.Polygon
unit_square = Surreal.Polygon.({ exterior: [Surreal.point(0, 0), Surreal.point(1, 0), Surreal.point(1, 1), Surreal.point(0, 0)], holes: [] })

# A geometry parameter is a `LET` of its GeoJSON object, which SurrealDB reads as a geometry.
expect Surreal.from(sites).filter_by(|p, s| Surreal.Geo.inside(s.location.to_geometry(), p.area.to_geometry())).select_value(|s| s.name).prepare({ area: unit_square }).request() == Ok("LET $area = { type: 'Polygon', coordinates: [[[0f, 0f], [1f, 0f], [1f, 1f], [0f, 0f]]] };\nSELECT VALUE name FROM site WHERE location INSIDE $area;")
# A row with a geometry writes its GeoJSON object.
expect sites.create({ id: "home", name: "Home", location: Surreal.point(10.75, 59.91), area: unit_square }).statement().map_ok(|st| st.surql) == Ok("CREATE site:⟨home⟩ CONTENT { area: { type: 'Polygon', coordinates: [[[0f, 0f], [1f, 0f], [1f, 1f], [0f, 0f]]] }, location: { type: 'Point', coordinates: [10.75f, 59.91f] }, name: 'Home' } RETURN AFTER")

# ------------------------------------------------------ live queries

## The tables of the shop, where a link of a watched row finds its table.
shop_tables : List(Surreal.Defined)
shop_tables = [customers.define().done(), products.define().done(), orders.define().done()]

## The request of a watch: the `LET`s, the `LIVE`s, then the snapshot.
request_of : Surreal.Watch(out) -> Try(Str, Surreal.Error)
request_of = |watch| watch.request()

high : I64 -> Bool
high = |level| level > 5

high_fn : Surreal.DbFn((I64 -> Bool))
high_fn = Surreal.db_fn("high", high)

ReadingLine : { product : Surreal.Id(Product), level : I64 }

reading_line : Reading -> ReadingLine
reading_line = |r| { product: r.id.series(), level: r.level }

# The filter is read on the row after the write and, with a guard, on `$before`.
expect request_of(Surreal.from(readings).filter(|r| high_fn.call1(r.level)).select(reading_line).live({}, [])) == Ok("LIVE SELECT VALUE { row: { level: level, product: record::id(id)[0] }, now: fn::high(level) } FROM reading WHERE fn::high(level) OR ($before IS NOT NONE AND fn::high($before.level));\nSELECT VALUE { ref: id, row: { level: level, product: record::id(id)[0] } } FROM reading WHERE fn::high(level);")
# An infix filter is put in parentheses, so SurrealDB's precedence does not matter.
expect request_of(Surreal.from(readings).filter(|r| r.level > 5).select_value(|r| r.level).live({}, [])) == Ok("LIVE SELECT VALUE { row: level, now: level > 5 } FROM reading WHERE (level > 5) OR ($before IS NOT NONE AND ($before.level > 5));\nSELECT VALUE { ref: id, row: level } FROM reading WHERE level > 5;")
expect request_of(Surreal.from(readings).filter(|r| r.level > 5).filter(|r| r.level < 9).select(|r| r).live({}, [])) == Ok("LIVE SELECT VALUE { row: { id: record::id(id), level: level }, now: (level > 5) AND (level < 9) } FROM reading WHERE ((level > 5) AND (level < 9)) OR ($before IS NOT NONE AND (($before.level > 5) AND ($before.level < 9)));\nSELECT VALUE { ref: id, row: { id: record::id(id), level: level } } FROM reading WHERE (level > 5) AND (level < 9);")
# No filter: every write is in the result.
expect request_of(Surreal.from(readings).select(reading_line).live({}, [])) == Ok("LIVE SELECT VALUE { row: { level: level, product: record::id(id)[0] }, now: true } FROM reading;\nSELECT VALUE { ref: id, row: { level: level, product: record::id(id)[0] } } FROM reading;")
# A parameter is a `LET` before the statements, fixed when the query starts.
expect request_of(Surreal.from(readings).filter_by(|p, r| r.level > p.least).select(reading_line).live({ least: 4 }, [])) == Ok("LET $least = 4;\nLIVE SELECT VALUE { row: { level: level, product: record::id(id)[0] }, now: $least < level } FROM reading WHERE ($least < level) OR ($before IS NOT NONE AND ($least < $before.level));\nSELECT VALUE { ref: id, row: { level: level, product: record::id(id)[0] } } FROM reading WHERE $least < level;")
expect request_of(Surreal.from(readings).filter_by(|p, r| r.level > p.session).select(reading_line).live({ session: 4 }, [])) == Err(Unsupported("`$session` is a protected variable in SurrealDB; name the parameter otherwise"))
# A filter of a projection reads the source row through it, on `$before` too: one `SELECT`.
# A link that a clause reads adds a `LIVE` on its table: a write to a
# customer reaches the orders that link to it, one notice for each. The
# clauses read no product, so a write to a product sends nothing, and they
# read the `name` of a customer, so an update of a customer that keeps
# its name sends nothing either (the `WHERE` on `customer`).
expect request_of(Surreal.from(orders).select(order_line).filter(|r| r.who == "Ada").live({}, shop_tables)) == Ok("LIVE SELECT VALUE { row: { total: total, who: customer.name }, now: customer.name = 'Ada' } FROM order WHERE (customer.name = 'Ada') OR ($before IS NOT NONE AND ($before.customer.name = 'Ada'));\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: { total: total, who: customer.name }, now: customer.name = 'Ada' } FROM order WHERE customer = $parent.id) FROM customer WHERE $before IS NONE OR $after IS NONE OR $before.name != $after.name;\nSELECT VALUE { ref: id, row: { total: total, who: customer.name } } FROM order WHERE customer.name = 'Ada';")
expect Surreal.from(orders).select(order_line).live({}, shop_tables).block("-- live: orders", ["-- roc: []"], []) == Ok("-- live: orders\n-- roles: node, read\n-- roc: []\nLIVE SELECT VALUE { row: { total: total, who: customer.name }, now: true } FROM order;\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: { total: total, who: customer.name }, now: true } FROM order WHERE customer = $parent.id) FROM customer WHERE $before IS NONE OR $after IS NONE OR $before.name != $after.name;\nSELECT VALUE { ref: id, row: { total: total, who: customer.name } } FROM order;")
# A link finds its table in the definitions that `live` takes, as in the schema.
expect request_of(Surreal.from(orders).select(order_line).live({}, [])) == Err(BadSchema("a live query watches the table of each link of its row, and the tables it takes do not name the one at `customer`: no table holds the row type `{ address : { city : Str, zip : Str }, id : Str, name : Str, tags : List(Str) }`; list its table in the schema"))
# The links that the clauses read decide, not the row type: a filter that
# reads the products of the items watches `product` and not `customer`.
expect request_of(Surreal.from(orders).filter(|o| o.items.any(|i| i.product.get().title == "pen")).select_value(|o| o.total).live({}, shop_tables)) == Ok("LIVE SELECT VALUE { row: total, now: items.any(|$v1| $v1.product.title = 'pen') } FROM order WHERE items.any(|$v1| $v1.product.title = 'pen') OR ($before IS NOT NONE AND $before.items.any(|$v1| $v1.product.title = 'pen'));\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: total, now: items.any(|$v1| $v1.product.title = 'pen') } FROM order WHERE $parent.id IN items[*].product) FROM product WHERE $before IS NONE OR $after IS NONE OR $before.title != $after.title;\nSELECT VALUE { ref: id, row: total } FROM order WHERE items.any(|$v1| $v1.product.title = 'pen');")
# A whole row holds its links as record ids, so it reads no linked row.
expect request_of(Surreal.from(orders).select(|o| o).live({}, shop_tables)) == Ok("LIVE SELECT VALUE { row: { customer: customer, id: record::id(id), items: items, payment: payment, total: total }, now: true } FROM order;\nSELECT VALUE { ref: id, row: { customer: customer, id: record::id(id), items: items, payment: payment, total: total } } FROM order;")
# The `id` of a linked row is the record id that the link holds: no hop.
expect request_of(Surreal.from(orders).select_value(|o| o.customer.get().id).live({}, [])) == Ok("LIVE SELECT VALUE { row: record::id(customer), now: true } FROM order;\nSELECT VALUE { ref: id, row: record::id(customer) } FROM order;")
# A link of an edge row: the edges are at `->purchased`, and the test reads
# the links of each, `$parent.id IN ->purchased.out`.
expect request_of(Surreal.from(customers).outgoing(purchased).select(|(c, bought)| { name: c.name, titles: bought.map(|e| e.to.get().title) }).live({}, shop_tables)) == Ok("LIVE SELECT VALUE { row: { name: name, titles: ->purchased->product.title }, now: true } FROM customer;\nLIVE SELECT VALUE { ref: in, node: (SELECT VALUE { row: { name: name, titles: ->purchased->product.title }, now: true } FROM ONLY $parent.in) } FROM purchased;\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: { name: name, titles: ->purchased->product.title }, now: true } FROM customer WHERE $parent.id IN ->purchased.out) FROM product WHERE $before IS NONE OR $after IS NONE OR $before.title != $after.title;\nSELECT VALUE { ref: id, row: { name: name, titles: ->purchased->product.title } } FROM customer;")
# `edges_from` of the row is watched as `outgoing` is. Edges of a linked row are watched as `rows()`: a write of an edge reaches every row.
expect request_of(Surreal.from(customers).select(|c| { name: c.name, titles: purchased.edges_from(c).map(|e| e.to.get().title) }).live({}, shop_tables)) == Ok("LIVE SELECT VALUE { row: { name: name, titles: ->purchased->product.title }, now: true } FROM customer;\nLIVE SELECT VALUE { ref: in, node: (SELECT VALUE { row: { name: name, titles: ->purchased->product.title }, now: true } FROM ONLY $parent.in) } FROM purchased;\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: { name: name, titles: ->purchased->product.title }, now: true } FROM customer WHERE $parent.id IN ->purchased.out) FROM product WHERE $before IS NONE OR $after IS NONE OR $before.title != $after.title;\nSELECT VALUE { ref: id, row: { name: name, titles: ->purchased->product.title } } FROM customer;")
expect request_of(Surreal.from(customers).select(|c| { name: c.name, n: purchased.edges_from(c).join_map(|e| purchased.edges_to(e.to.get())).len().to_i64_wrap() }).live({}, [])) == Ok("LIVE SELECT VALUE { row: { n: ->purchased->product<-purchased.len(), name: name }, now: true } FROM customer;\nLIVE SELECT VALUE { ref: in, node: (SELECT VALUE { row: { n: ->purchased->product<-purchased.len(), name: name }, now: true } FROM ONLY $parent.in) } FROM purchased;\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: { n: ->purchased->product<-purchased.len(), name: name }, now: true } FROM customer) FROM purchased;\nSELECT VALUE { ref: id, row: { n: ->purchased->product<-purchased.len(), name: name } } FROM customer;")
expect request_of(Surreal.from(products).incoming(purchased).filter(|(_, buys)| buys.any(|e| e.from.get().name == "Ada")).select_value(|(p, _)| p.title).live({}, shop_tables)) == Ok("LIVE SELECT VALUE { row: title, now: true } FROM product WHERE <-purchased.any(|$v1| $v1.in.name = 'Ada');\nLIVE SELECT VALUE { ref: out, node: (SELECT VALUE { row: title, now: <-purchased.any(|$v1| $v1.in.name = 'Ada') } FROM ONLY $parent.out) } FROM purchased;\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: title, now: <-purchased.any(|$v1| $v1.in.name = 'Ada') } FROM product WHERE $parent.id IN <-purchased.in) FROM customer WHERE $before IS NONE OR $after IS NONE OR $before.name != $after.name;\nSELECT VALUE { ref: id, row: title } FROM product WHERE <-purchased.any(|$v1| $v1.in.name = 'Ada');")
# A link of a row of `rows()`: the test reads the links of every row of
# the other table, whatever the row of the result.
expect request_of(Surreal.from(customers).filter(|c| orders.rows().any(|o| o.customer.get().id == c.id and o.items.any(|i| i.product.get().title == "pen"))).select_value(|c| c.name).live({}, shop_tables)) == Ok("LIVE SELECT VALUE { row: name, now: true } FROM customer WHERE record::id(id).chain(|$v1_0| (SELECT VALUE id FROM order WHERE (record::id(customer) = $v1_0) AND items.any(|$v2| $v2.product.title = 'pen') LIMIT 1)) != [];\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: name, now: record::id(id).chain(|$v1_0| (SELECT VALUE id FROM order WHERE (record::id(customer) = $v1_0) AND items.any(|$v2| $v2.product.title = 'pen') LIMIT 1)) != [] } FROM customer WHERE $parent.id IN array::flatten((SELECT VALUE id FROM order).items[*].product)) FROM product WHERE $before IS NONE OR $after IS NONE OR $before.title != $after.title;\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: name, now: record::id(id).chain(|$v1_0| (SELECT VALUE id FROM order WHERE (record::id(customer) = $v1_0) AND items.any(|$v2| $v2.product.title = 'pen') LIMIT 1)) != [] } FROM customer WHERE record::id(id) IN array::distinct([$before, $after].filter(|$w| $w != NONE).map(|$w| record::id($w.customer)))) FROM order;\nSELECT VALUE { ref: id, row: name } FROM customer WHERE record::id(id).chain(|$v1_0| (SELECT VALUE id FROM order WHERE (record::id(customer) = $v1_0) AND items.any(|$v2| $v2.product.title = 'pen') LIMIT 1)) != [];")
# A row and its edges: one `LIVE` on the edge table more, whose payload is the node after the write.
expect request_of(Surreal.from(products).incoming(purchased).filter(|(_, buys)| buys.len() == 0).select(|(p, buys)| { title: p.title, buyers: buys.len().to_i64_wrap() }).live({}, [])) == Ok("LIVE SELECT VALUE { row: { buyers: <-purchased.len(), title: title }, now: true } FROM product WHERE <-purchased.len() = 0;\nLIVE SELECT VALUE { ref: out, node: (SELECT VALUE { row: { buyers: <-purchased.len(), title: title }, now: <-purchased.len() = 0 } FROM ONLY $parent.out) } FROM purchased;\nSELECT VALUE { ref: id, row: { buyers: <-purchased.len(), title: title } } FROM product WHERE <-purchased.len() = 0;")
# A second edge table: the row and both edge lists, and a `LIVE` on each edge table.
expect Surreal.from(products).incoming(purchased).and_incoming(reviewed).filter(|(_, buys, stars)| buys.len() > 0 and stars.len() == 0).select(|(p, buys, stars)| { title: p.title, buyers: buys.len().to_i64_wrap(), reviews: stars.len().to_i64_wrap() }).to_surql() == Ok("SELECT <-purchased.len() AS buyers, <-reviewed.len() AS reviews, title AS title FROM product WHERE (<-purchased.len() > 0) AND (<-reviewed.len() = 0)")
expect Surreal.from(customers).outgoing(purchased).and_outgoing(reviewed).select(|(c, bought, rated)| { name: c.name, rated: rated.keep_if(|e| e.stars > 3).map(|e| e.to.get().title), n: bought.len().to_i64_wrap() }).to_surql() == Ok("SELECT ->purchased.len() AS n, name AS name, ->reviewed[WHERE stars > 3]->product.title AS rated FROM customer")
expect request_of(Surreal.from(products).incoming(purchased).and_incoming(reviewed).filter(|(_, buys, stars)| buys.len() > 0 and stars.len() == 0).select(|(p, buys, stars)| { title: p.title, buyers: buys.len().to_i64_wrap(), reviews: stars.len().to_i64_wrap() }).live({}, [])) == Ok("LIVE SELECT VALUE { row: { buyers: <-purchased.len(), reviews: <-reviewed.len(), title: title }, now: true } FROM product WHERE (<-purchased.len() > 0) AND (<-reviewed.len() = 0);\nLIVE SELECT VALUE { ref: out, node: (SELECT VALUE { row: { buyers: <-purchased.len(), reviews: <-reviewed.len(), title: title }, now: (<-purchased.len() > 0) AND (<-reviewed.len() = 0) } FROM ONLY $parent.out) } FROM purchased;\nLIVE SELECT VALUE { ref: out, node: (SELECT VALUE { row: { buyers: <-purchased.len(), reviews: <-reviewed.len(), title: title }, now: (<-purchased.len() > 0) AND (<-reviewed.len() = 0) } FROM ONLY $parent.out) } FROM reviewed;\nSELECT VALUE { ref: id, row: { buyers: <-purchased.len(), reviews: <-reviewed.len(), title: title } } FROM product WHERE (<-purchased.len() > 0) AND (<-reviewed.len() = 0);")
expect request_of(Surreal.from(customers).outgoing(purchased).select(|(c, bought)| { name: c.name, n: bought.len().to_i64_wrap() }).live({}, [])) == Ok("LIVE SELECT VALUE { row: { n: ->purchased.len(), name: name }, now: true } FROM customer;\nLIVE SELECT VALUE { ref: in, node: (SELECT VALUE { row: { n: ->purchased.len(), name: name }, now: true } FROM ONLY $parent.in) } FROM purchased;\nSELECT VALUE { ref: id, row: { n: ->purchased.len(), name: name } } FROM customer;")
# A view is a table: a write to its source table updates a row of it.
expect request_of(Surreal.from(daily).select(|d| { day: d.day, high: d.high }).live({}, [])) == Ok("LIVE SELECT VALUE { row: { day: day, high: high }, now: true } FROM reading_daily;\nSELECT VALUE { ref: id, row: { day: day, high: high } } FROM reading_daily;")

# What SurrealDB refuses in a live query is refused when the watch is made.
expect request_of(Surreal.from(readings).group_by(day_of).aggregate(day_line).live({}, [])) == Err(Unsupported("a live query has no GROUP BY: SurrealDB refuses it. Define the group as a view with `Surreal.view` and watch the view"))
expect request_of(Surreal.from(readings).select(reading_line).order_by(|r| r.level, Desc).live({}, [])) == Err(Unsupported("SurrealDB refuses ORDER BY, LIMIT and START in a live query; order the rows of a `View`"))
# `limit` and `start` give a `Limited` and a `Started`, which have no `live`: a type error.
expect request_of(Surreal.from(readings).between(pen_id, moment("2026-03-01T00:00:00Z"), moment("2026-03-02T00:00:00Z")).select(reading_line).live({}, [])) == Err(Unsupported("a live query reads a whole table, not a range of keys; filter on `v.id.time()`"))
# A filter after a group, an order with a limit, or a start reads a subquery.
subquery_refusal : Surreal.Error
subquery_refusal = Unsupported("a live query is one `SELECT`, and this query reads a subquery (`FROM (SELECT ..)`), which SurrealDB refuses in a `LIVE SELECT`; filter before `group_by`, `order_by`, `limit` and `start`, or watch a view (`Surreal.view`)")

expect request_of(Surreal.from(readings).group_by(day_of).aggregate(day_line).filter(|d| d.high > 0).live({}, [])) == Err(subquery_refusal)
expect request_of(Surreal.from(readings).select(reading_line).limit(3).filter(|r| r.level > 1).live({}, [])) == Err(subquery_refusal)
# `SELECT *` has no row type, so it has no live form, also with `FETCH`.
expect request_of(Surreal.Unchecked.select_star(Surreal.from(orders)).live({}, [])) == Err(Unsupported("a live query sends typed rows, and `Unchecked.select_star` has no row type; select the fields with `select`"))
expect request_of(Surreal.Unchecked.fetch(Surreal.Unchecked.select_star(Surreal.from(orders)), "customer").live({}, [])) == Err(Unsupported("a live query sends typed rows, and `Unchecked.select_star` has no row type; select the fields with `select`"))

# A `-- live:` block for `check.py`: the roles of the `LIVE`s, the directives, the request, then each write.
expect Surreal.from(readings).filter(|r| r.level > 5).select_value(|r| r.level).live({}, []).block("-- live: high", ["-- roc: [[]]"], readings.edit(Delete(morning)).statement().map_ok(|st| [st]) ?? []) == Ok("-- live: high\n-- roles: node\n-- roc: [[]]\nLIVE SELECT VALUE { row: level, now: level > 5 } FROM reading WHERE (level > 5) OR ($before IS NOT NONE AND ($before.level > 5));\nSELECT VALUE { ref: id, row: level } FROM reading WHERE level > 5;\n-- write\nDELETE reading:[product:⟨pen⟩, d'2026-03-01T08:00:00Z'] RETURN BEFORE;")

# The raw events: the projection is the payload, and there is no `$before`.
expect live_text(Surreal.from(readings).filter(|r| high_fn.call1(r.level)).select(reading_line).live_raw({})) == Ok("LIVE SELECT VALUE { level: level, product: record::id(id)[0] } FROM reading WHERE fn::high(level);")
expect live_text(Surreal.from(products).incoming(purchased).select(|(p, buys)| { title: p.title, buyers: buys.len().to_i64_wrap() }).live_raw({})) == Ok("LIVE SELECT VALUE { buyers: <-purchased.len(), title: title } FROM product;")
expect live_text(Surreal.from(readings).select(reading_line).order_by(|r| r.level, Desc).live_raw({})) == Err(Unsupported("SurrealDB refuses ORDER BY, LIMIT and START in a live query; order the rows of a `View`"))

# Patches of the stored rows: no projection, no edges.
expect live_text(Surreal.from(readings).live_diff({})) == Ok("LIVE SELECT DIFF FROM reading;")
expect live_text(Surreal.from(readings).filter_by(|p, r| r.level > p.least).live_diff({ least: 4 })) == Ok("LET $least = 4;\nLIVE SELECT DIFF FROM reading WHERE $least < level;")
expect live_text(Surreal.from(products).incoming(purchased).live_diff({})) == Err(Unsupported("a DIFF live query has no edges: its patches are of the stored row; watch the edges with `live`"))
expect live_text(Surreal.from(orders).select(order_line).query().live_diff({})) == Err(Unsupported("`live_diff` sends patches of the stored row, so it reads a table: take it on `Surreal.from(table)` with filters only"))
expect live_text(Surreal.from(readings).between(pen_id, moment("2026-03-01T00:00:00Z"), moment("2026-03-02T00:00:00Z")).live_diff({})) == Err(Unsupported("a live query reads a whole table, not a range of keys; filter on `v.id.time()`"))

# The writes of the Mirror: one statement for each kind of `Edit`.
expect readings.edit(Create(morning)).statement().map_ok(|st| st.surql) == Ok("CREATE reading:[product:⟨pen⟩, d'2026-03-01T08:00:00Z'] CONTENT { level: 3 } RETURN AFTER")
expect readings.edit(Replace(morning, { ..morning, level: 4 })).statement().map_ok(|st| st.surql) == Ok("UPDATE reading:[product:⟨pen⟩, d'2026-03-01T08:00:00Z'] CONTENT { level: 4 } RETURN AFTER")
expect readings.edit(Delete(morning)).statement().map_ok(|st| st.surql) == Ok("DELETE reading:[product:⟨pen⟩, d'2026-03-01T08:00:00Z'] RETURN BEFORE")
expect purchased.edit(Create({ id: "p1", from: customers.link("ada"), to: products.link("pen"), quantity: 2 })).statement().map_ok(|st| st.surql) == Ok("RELATE customer:⟨ada⟩->purchased:⟨p1⟩->product:⟨pen⟩ CONTENT { quantity: 2 } RETURN AFTER")
expect daily.edit(Delete({ product: pen_id, day: moment("2026-03-01T00:00:00Z"), readings: 1, high: 0 })).statement().map_ok(|st| st.surql) == Err(Unsupported("`reading_daily` is a view, and a view is read-only"))
# The record of a row, and of a row of a view: its group key in name order.
expect readings.ref(morning).map_ok(|r| r.to_str()) == Ok("reading:[product:⟨pen⟩, d'2026-03-01T08:00:00Z']")
expect daily.group_ref({ product: pen_id, day: moment("2026-03-01T00:00:00Z") }).map_ok(|r| r.to_str()) == Ok("reading_daily:[d'2026-03-01T00:00:00Z', product:⟨pen⟩]")
expect readings.group_ref({ product: pen_id }).map_ok(|r| r.to_str()) == Err(Unsupported("`reading` is not a view, so its rows have no group key"))

# ------------------------------------------------ the rows of a table in a clause

# A table holds no `Code` value, so a clause reads it: its rows are record ids,
# and a field read off one is a traversal. A correlated count and a semi join.
# A conjunct that reads the row of the table and values of the clause goes
# into the `WHERE` of the subquery; each value is bound around it with `chain`.
expect Surreal.from(customers).select(|c| { name: c.name, orders: orders.rows().keep_if(|o| o.customer.get().id == c.id).len().to_i64_wrap() }).to_surql() == Ok("SELECT name AS name, record::id(id).chain(|$v1_0| (SELECT VALUE id FROM order WHERE record::id(customer) = $v1_0)).len() AS orders FROM customer")
expect Surreal.from(customers).filter(|c| orders.rows().any(|o| o.customer.get().id == c.id and o.total > 10)).select_value(|c| c.name).to_surql() == Ok("SELECT VALUE name FROM customer WHERE record::id(id).chain(|$v1_0| (SELECT VALUE id FROM order WHERE (record::id(customer) = $v1_0) AND (total > 10.0dec) LIMIT 1)) != []")
# A row of the list is a record: its `id` is the key, and the whole row has the fields of its type.
expect Surreal.from(customers).select(|c| { ids: orders.rows().keep_if(|o| o.customer.get().id == c.id).map(|o| o.id) }).to_surql() == Ok("SELECT record::id(id).chain(|$v1_0| (SELECT VALUE id FROM order WHERE record::id(customer) = $v1_0)).map(|$v2| record::id($v2)) AS ids FROM customer")
expect Surreal.from(customers).select(|_| { all: products.rows() }).to_surql() == Ok("SELECT (SELECT VALUE id FROM product).{ id: record::id(id), price, title } AS all FROM customer")
# The rows of an edge table are edges: `from` and `to` are `in` and `out`.
expect Surreal.from(products).select(|p| { buyers: purchased.rows().keep_if(|e| e.to.get().id == p.id).map(|e| e.from.get().name) }).to_surql() == Ok("SELECT record::id(id).chain(|$v1_0| (SELECT VALUE id FROM purchased WHERE record::id(out) = $v1_0)).map(|$v2| $v2.in.name) AS buyers FROM product")
# The rows of a time series with the series of the row: a range scan of the keys, in either order.
expect Surreal.from(products).select(|p| { n: readings.rows().keep_if(|r| r.id.series() == products.id(p.id)).len().to_i64_wrap() }).to_surql() == Ok("SELECT id.chain(|$v1| (SELECT VALUE id FROM reading:[$v1, NONE]..=[$v1, ..])).len() AS n FROM product")
expect Surreal.from(products).filter(|p| readings.rows().keep_if(|r| products.id(p.id) == r.id.series()).any(|r| r.level > 3)).select_value(|p| p.title).to_surql() == Ok("SELECT VALUE title FROM product WHERE id.chain(|$v1| (SELECT VALUE id FROM reading:[$v1, NONE]..=[$v1, ..])).any(|$v2| $v2.level > 3)")
# A test of a field of the row only: the `WHERE`, with no `chain`.
expect Surreal.from(products).select(|_| { n: readings.rows().keep_if(|r| r.level > 3).len().to_i64_wrap() }).to_surql() == Ok("SELECT (SELECT VALUE id FROM reading WHERE level > 3).len() AS n FROM product")
# Only the conjuncts that read the row go into the `WHERE`; the others stay a `filter`.
expect Surreal.from(customers).select(|c| { big: orders.rows().keep_if(|o| o.customer.id() == customers.id(c.id) and o.total > o.items.len().to_dec()).len() }).to_surql() == Ok("SELECT id.chain(|$v1_0| (SELECT VALUE id FROM order WHERE (customer = $v1_0) AND (total > <decimal>items.len()))).len() AS big FROM customer")
expect Surreal.from(customers).select(|c| { n: orders.rows().count_if(|o| o.customer.id() == customers.id(c.id) and c.name != "") }).to_surql() == Ok("SELECT id.chain(|$v1_0| (SELECT VALUE id FROM order WHERE customer = $v1_0)).filter(|$v1| name != '').len() AS n FROM customer")
# A find reads one row, in the order of the table when the test is not `==`.
expect Surreal.from(customers).select(|c| { first: orders.rows().find_first(|o| o.customer.id() == customers.id(c.id)).map_ok(|o| o.total) ?? 0 }).to_surql() == Ok("SELECT (IF id.chain(|$v1_0| (SELECT VALUE id FROM order WHERE customer = $v1_0 ORDER BY id LIMIT 1))[0] IS NONE THEN NONE ELSE id.chain(|$v1_0| (SELECT VALUE id FROM order WHERE customer = $v1_0 ORDER BY id LIMIT 1))[0].total END) ?? 0.0dec AS first FROM customer")
expect Surreal.from(customers).select(|_| { big: orders.rows().keep_if(|o| o.total > 100).map(|o| o.total) }).to_surql() == Ok("SELECT (SELECT VALUE id FROM order WHERE total > 100.0dec ORDER BY id).map(|$v2| $v2.total) AS big FROM customer")
# A parameter of the statement is read in place.
expect Surreal.from(customers).filter_by(|p, c| orders.rows().any(|o| o.total > p.min_total and o.customer.id() == customers.id(c.id))).select_value(|c| c.name).to_surql() == Ok("SELECT VALUE name FROM customer WHERE id.chain(|$v1_1| (SELECT VALUE id FROM order WHERE (total > $min_total) AND (customer = $v1_1) LIMIT 1)) != []")
expect Surreal.from(customers).select(|_| { first: orders.rows().first() }).to_surql() == Err(Unsupported("in `select`: the rows of a table take `keep_if`, `map`, `any`, `all` and `len`"))
# The id of a row of a table, by its key.
expect Surreal.from(orders).filter(|o| o.items.any(|i| i.product.id() == products.id("pen"))).select_value(|o| o.id).to_surql() == Ok("SELECT VALUE record::id(id) FROM order WHERE product:⟨pen⟩ IN items[*].product")
expect Surreal.from(orders).filter(|o| o.customer.id() == customers.id(o.id)).select_value(|o| o.id).to_surql() == Ok("SELECT VALUE record::id(id) FROM order WHERE customer = type::record('customer', record::id(id))")
# The id of a link is a field, `link.id`, or the method `link.id()`. Both give the record id the link holds, and one clause can use both.
ada_id : Surreal.Id(Customer)
ada_id = Surreal.Unchecked.id("customer", "ada")

expect Surreal.from(orders).filter(|o| o.items.any(|i| i.product.id == pen_id)).select_value(|o| o.id).to_surql() == Ok("SELECT VALUE record::id(id) FROM order WHERE product:⟨pen⟩ IN items[*].product")
expect Surreal.from(orders).filter(|o| o.customer.id == customers.id(o.id)).select_value(|o| o.id).to_surql() == Ok("SELECT VALUE record::id(id) FROM order WHERE customer = type::record('customer', record::id(id))")
expect Surreal.from(orders).filter(|o| o.customer.id == ada_id).select_value(|o| o.id).to_surql() == Surreal.from(orders).filter(|o| o.customer.id() == ada_id).select_value(|o| o.id).to_surql()
expect Surreal.from(orders).filter(|o| o.customer.id == ada_id or o.customer.id() == customers.id("bob")).select_value(|o| o.id).to_surql() == Ok("SELECT VALUE record::id(id) FROM order WHERE (customer = customer:⟨ada⟩) OR (customer = customer:⟨bob⟩)")
expect Surreal.from(orders).select(|o| { who: o.customer.id }).to_surql() == Ok("SELECT customer AS who FROM order")
expect Surreal.from(orders).select(|o| { who: o.customer.id() }).to_surql() == Ok("SELECT customer AS who FROM order")
expect Surreal.from(orders).select_value(|o| o.customer.id).to_surql() == Ok("SELECT VALUE customer FROM order")
expect Surreal.from(orders).select_value(|o| o.customer.id()).to_surql() == Ok("SELECT VALUE customer FROM order")
expect Surreal.from(orders).select(|o| { who: o.customer.id, total: o.total }).order_by(|r| r.who, Asc).to_surql() == Surreal.from(orders).select(|o| { who: o.customer.id(), total: o.total }).order_by(|r| r.who, Asc).to_surql()
expect Surreal.from(orders).group_by(|o| o.customer.id).aggregate(|who, rows| { who, n: rows.len() }).to_surql() == Surreal.from(orders).group_by(|o| o.customer.id()).aggregate(|who, rows| { who, n: rows.len() }).to_surql()
expect orders.update(|o| o.customer.id == ada_id, |o| { ..o, payment: Card({ last4: o.customer.id.key() }) }).to_surql() == Ok("UPDATE order SET payment = { kind: 'Card', last4: record::id(customer) } WHERE customer = customer:⟨ada⟩")
expect orders.update(|o| o.customer.id() == ada_id, |o| { ..o, payment: Card({ last4: o.customer.id().key() }) }).to_surql() == Ok("UPDATE order SET payment = { kind: 'Card', last4: record::id(customer) } WHERE customer = customer:⟨ada⟩")
expect Surreal.from(purchased).filter(|e| e.from.id == ada_id).select_value(|e| e.to.id).to_surql() == Ok("SELECT VALUE out FROM purchased WHERE in = customer:⟨ada⟩")
expect Surreal.from(purchased).filter(|e| e.from.id() == ada_id).select_value(|e| e.to.id()).to_surql() == Ok("SELECT VALUE out FROM purchased WHERE in = customer:⟨ada⟩")
expect Surreal.from(customers).outgoing(purchased).select(|(_, bought)| { ends: bought.map(|e| e.to.id) }).to_surql() == Surreal.from(customers).outgoing(purchased).select(|(_, bought)| { ends: bought.map(|e| e.to.id()) }).to_surql()
expect request_of(Surreal.from(orders).filter(|o| o.customer.id == ada_id).select(|o| { who: o.customer.id }).live({}, [])) == request_of(Surreal.from(orders).filter(|o| o.customer.id() == ada_id).select(|o| { who: o.customer.id() }).live({}, []))
# The field `fetched` is the row that the program holds, so a clause refuses it.
expect Surreal.from(orders).filter(|o| o.customer.fetched == NotFetched).select_value(|o| o.id).to_surql() == Err(Unsupported("in `filter`: `fetched` is the row that the program holds, and the database has no such field; read a field of the row with `link.get().field`, or use `link.id`"))
# A captured id and a captured list of ids, read with the field form.
orders_of : Surreal.Id(Customer) -> Surreal.Prepared(List(Order))
orders_of = |who| Surreal.from(orders).filter(|o| o.customer.id == who).ready()

## A captured key is a `$_1` too, and the record id is built from it.
customer_at : Str -> Surreal.Prepared(List(Customer))
customer_at = |key| Surreal.from(customers).filter(|c| c.id == key).ready()

expect customer_at("ada").request() == Ok("LET $_1 = 'ada';\nSELECT address, record::id(id) AS id, name, tags FROM customer WHERE id = type::record('customer', $_1);")

orders_of_method : Surreal.Id(Customer) -> Surreal.Prepared(List(Order))
orders_of_method = |who| Surreal.from(orders).filter(|o| o.customer.id() == who).ready()

orders_of_any : List(Surreal.Id(Customer)) -> Surreal.Prepared(List(Order))
orders_of_any = |many| Surreal.from(orders).filter(|o| many.contains(o.customer.id)).ready()

expect orders_of(ada_id).statement().map_ok(|st| st.inlined) == orders_of_method(ada_id).statement().map_ok(|st| st.inlined)
expect orders_of(ada_id).statement().map_ok(|st| st.inlined) == Ok("SELECT customer, record::id(id) AS id, items, payment, total FROM order WHERE customer = customer:⟨ada⟩")
expect orders_of_any([ada_id]).statement().map_ok(|st| st.inlined) == Ok("SELECT customer, record::id(id) AS id, items, payment, total FROM order WHERE customer IN [customer:⟨ada⟩]")
# A whole record as the result row: a linked row and an object.
expect Surreal.from(orders).select(|o| o.customer.get()).to_surql() == Ok("SELECT customer.address AS address, record::id(customer) AS id, customer.name AS name, customer.tags AS tags FROM order")
expect Surreal.from(customers).select(|c| c.address).to_surql() == Ok("SELECT address.city AS city, address.zip AS zip FROM customer")
# A semi join in a live query: the filter reads the other table, on `$before` too.
# A write to the orders reaches the customers that the order names, before and after the write.
expect request_of(Surreal.from(customers).filter(|c| orders.rows().any(|o| o.customer.get().id == c.id)).select_value(|c| c.name).live({}, [])) == Ok("LIVE SELECT VALUE { row: name, now: true } FROM customer WHERE record::id(id).chain(|$v1_0| (SELECT VALUE id FROM order WHERE record::id(customer) = $v1_0 LIMIT 1)) != [];\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: name, now: record::id(id).chain(|$v1_0| (SELECT VALUE id FROM order WHERE record::id(customer) = $v1_0 LIMIT 1)) != [] } FROM customer WHERE record::id(id) IN array::distinct([$before, $after].filter(|$w| $w != NONE).map(|$w| record::id($w.customer)))) FROM order;\nSELECT VALUE { ref: id, row: name } FROM customer WHERE record::id(id).chain(|$v1_0| (SELECT VALUE id FROM order WHERE record::id(customer) = $v1_0 LIMIT 1)) != [];")
# The read of a time series by the key of the row: a write of a reading reaches the one row its key names.
expect request_of(Surreal.from(products).filter(|p| readings.rows().keep_if(|r| r.id.series() == products.id(p.id)).any(|r| r.level > 3)).select_value(|p| p.title).live({}, [])) == Ok("LIVE SELECT VALUE { row: title, now: true } FROM product WHERE id.chain(|$v1| (SELECT VALUE id FROM reading:[$v1, NONE]..=[$v1, ..])).any(|$v2| $v2.level > 3);\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: title, now: id.chain(|$v1| (SELECT VALUE id FROM reading:[$v1, NONE]..=[$v1, ..])).any(|$v2| $v2.level > 3) } FROM record::id($parent.id)[0]) FROM reading;\nSELECT VALUE { ref: id, row: title } FROM product WHERE id.chain(|$v1| (SELECT VALUE id FROM reading:[$v1, NONE]..=[$v1, ..])).any(|$v2| $v2.level > 3);")
# A link that a write can change: the rows it names before and after the write.
expect request_of(Surreal.from(customers).select(|c| { name: c.name, n: orders.rows().count_if(|o| o.customer.id() == customers.id(c.id)) }).live({}, [])) == Ok("LIVE SELECT VALUE { row: { n: id.chain(|$v1_0| (SELECT VALUE id FROM order WHERE customer = $v1_0)).len(), name: name }, now: true } FROM customer;\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: { n: id.chain(|$v1_0| (SELECT VALUE id FROM order WHERE customer = $v1_0)).len(), name: name }, now: true } FROM array::distinct([$before, $after].filter(|$w| $w != NONE).map(|$w| $w.customer))) FROM order;\nSELECT VALUE { ref: id, row: { n: id.chain(|$v1_0| (SELECT VALUE id FROM order WHERE customer = $v1_0)).len(), name: name } } FROM customer;")
# A list of the read row that holds a value of the row: the rows whose value is in it, before or after the write.
expect request_of(Surreal.from(products).select(|p| { title: p.title, n: customers.rows().count_if(|c| c.tags.contains(p.title)) }).live({}, [])) == Ok("LIVE SELECT VALUE { row: { n: title.chain(|$v1_0| (SELECT VALUE id FROM customer WHERE tags CONTAINS $v1_0)).len(), title: title }, now: true } FROM product;\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: { n: title.chain(|$v1_0| (SELECT VALUE id FROM customer WHERE tags CONTAINS $v1_0)).len(), title: title }, now: true } FROM product WHERE title IN array::distinct(array::flatten([$before, $after].filter(|$w| $w != NONE).map(|$w| $w.tags)))) FROM customer;\nSELECT VALUE { ref: id, row: { n: title.chain(|$v1_0| (SELECT VALUE id FROM customer WHERE tags CONTAINS $v1_0)).len(), title: title } } FROM product;")
# No equality with a value of the row: every row.
expect request_of(Surreal.from(products).select(|p| { title: p.title, n: readings.rows().keep_if(|r| r.level > 3).len() }).live({}, [])) == Ok("LIVE SELECT VALUE { row: { n: (SELECT VALUE id FROM reading WHERE level > 3).len(), title: title }, now: true } FROM product;\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: { n: (SELECT VALUE id FROM reading WHERE level > 3).len(), title: title }, now: true } FROM product) FROM reading;\nSELECT VALUE { ref: id, row: { n: (SELECT VALUE id FROM reading WHERE level > 3).len(), title: title } } FROM product;")
# One read of the table without a relation: every row.
expect request_of(Surreal.from(products).select(|p| { a: readings.rows().count_if(|r| r.id.series() == products.id(p.id)), b: readings.rows().count_if(|r| r.level > 3) }).live({}, [])) == Ok("LIVE SELECT VALUE { row: { a: id.chain(|$v1_0| (SELECT VALUE id FROM reading WHERE record::id(id)[0] = $v1_0)).len(), b: (SELECT VALUE id FROM reading WHERE level > 3).len() }, now: true } FROM product;\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: { a: id.chain(|$v1_0| (SELECT VALUE id FROM reading WHERE record::id(id)[0] = $v1_0)).len(), b: (SELECT VALUE id FROM reading WHERE level > 3).len() }, now: true } FROM product) FROM reading;\nSELECT VALUE { ref: id, row: { a: id.chain(|$v1_0| (SELECT VALUE id FROM reading WHERE record::id(id)[0] = $v1_0)).len(), b: (SELECT VALUE id FROM reading WHERE level > 3).len() } } FROM product;")
# A link in a list of the row of the other table: the rows that the list names before and after the write.
expect request_of(Surreal.from(products).select(|p| { title: p.title, n: orders.rows().count_if(|o| o.items.any(|i| i.product.id() == products.id(p.id))) }).live({}, [])).map_ok(|text| text.contains("FROM array::distinct(array::flatten([$before, $after].filter(|$w| $w != NONE).map(|$w| $w.items[*].product)))) FROM order;")) == Ok(Bool.True)
# A list of lists: each list level more is one `array::flatten` more.
expect request_of(Surreal.from(products).select(|p| { title: p.title, n: shipments.rows().count_if(|s| s.boxes.any(|b| b.items.any(|i| i.product.id() == products.id(p.id)))) }).live({}, [])).map_ok(|text| text.contains("FROM array::distinct(array::flatten([$before, $after].filter(|$w| $w != NONE).map(|$w| array::flatten($w.boxes[*].items[*].product))))) FROM shipment;")) == Ok(Bool.True)
# A value of the row in the list test: the list test is no relation, so every row.
expect request_of(Surreal.from(products).select(|p| { title: p.title, n: orders.rows().count_if(|o| o.items.any(|i| i.qty.to_dec() > p.price)) }).live({}, [])).map_ok(|text| text.contains("FROM product) FROM order;")) == Ok(Bool.True)
# The same after a projection: a filter of the result rows reads the orders.
expect request_of(Surreal.from(customers).select(|c| { name: c.name }).filter(|r| orders.rows().any(|o| o.total > 100 and r.name != "")).live({}, [])).map_ok(|text| text.contains("FROM customer) FROM order;")) == Ok(Bool.True)

# ------------------------------------------------------------ read rows

# A read row has a `Linked` for each `Link`, so a field read is a traversal
# with no `.get()`, and `Out` and `In` fields for the edges at the row.
ItemRead : { product : Surreal.Linked(Product), qty : I64 }

OrderRead : { id : Str, customer : Surreal.Linked(Customer), items : List(ItemRead), payment : Payment, total : Dec }

PurchasedRead : { id : Str, from : Surreal.Link(Customer), to : Surreal.Linked(Product), quantity : I64 }

CustomerRead : { id : Str, name : Str, address : Address, tags : List(Str), purchased : Surreal.Out(PurchasedRead) }

ProductRead : { id : Str, title : Str, price : Dec, purchased : Surreal.In(PurchasedRead) }

order_reads : Surreal.Table(OrderRead)
order_reads = Surreal.table("order")

customer_reads : Surreal.Table(CustomerRead)
customer_reads = Surreal.table("customer")

product_reads : Surreal.Table(ProductRead)
product_reads = Surreal.table("product")

expect Surreal.from(order_reads).select(|o| { who: o.customer.name, key: o.customer.id, city: o.customer.address.city }).to_surql() == Ok("SELECT customer.address.city AS city, record::id(customer) AS key, customer.name AS who FROM order")
expect Surreal.from(order_reads).filter(|o| o.items.any(|i| i.product.price > 2)).select(|o| { titles: o.items.map(|i| i.product.title) }).to_surql() == Ok("SELECT items.map(|$v1| $v1.product.title) AS titles FROM order WHERE items.any(|$v1| $v1.product.price > 2.0dec)")
# A whole read row is the fetch plan: each `Linked` is the fields of its row.
expect Surreal.from(order_reads).select(|o| o).to_surql() == Ok("SELECT customer.{ address, id: record::id(id), name, tags } AS customer, record::id(id) AS id, items.{ product: product.{ id: record::id(id), price, title }, qty } AS items, payment, total FROM order")
expect Surreal.from(order_reads).select(|o| { customer: o.customer }).to_surql() == Ok("SELECT customer.{ address, id: record::id(id), name, tags } AS customer FROM order")
# An `Out` field is the edges that leave the row, an `In` field those that end at it.
expect Surreal.from(customer_reads).select(|c| { name: c.name, titles: c.purchased.list().map(|e| e.to.title), n: c.purchased.list().len().to_i64_wrap() }).to_surql() == Ok("SELECT ->purchased.len() AS n, name AS name, ->purchased->?.title AS titles FROM customer")
expect Surreal.from(product_reads).filter(|p| p.purchased.list().any(|e| e.quantity > 2)).select_value(|p| p.title).to_surql() == Ok("SELECT VALUE title FROM product WHERE <-purchased.any(|$v1| $v1.quantity > 2)")
expect Surreal.from(customer_reads).select(|c| c).to_surql() == Ok("SELECT address, record::id(id) AS id, name, ->purchased.{ from: in, id: record::id(id), quantity, to: out.{ id: record::id(id), price, title } } AS purchased, tags FROM customer")
# A live query of a read row watches the edge table of each `Out` and `In`
# field that a clause reads, as it does for `outgoing` and `incoming`. A
# count of the edges reads no linked row of an edge.
expect request_of(Surreal.from(product_reads).select(|p| { title: p.title, n: p.purchased.list().len().to_i64_wrap() }).live({}, [])) == Ok("LIVE SELECT VALUE { row: { n: <-purchased.len(), title: title }, now: true } FROM product;\nLIVE SELECT VALUE { ref: out, node: (SELECT VALUE { row: { n: <-purchased.len(), title: title }, now: true } FROM ONLY $parent.out) } FROM purchased;\nSELECT VALUE { ref: id, row: { n: <-purchased.len(), title: title } } FROM product;")
expect request_of(Surreal.from(customer_reads).filter(|c| c.purchased.list().len() > 0).select_value(|c| c.name).live({}, [])) == Ok("LIVE SELECT VALUE { row: name, now: true } FROM customer WHERE ->purchased.len() > 0;\nLIVE SELECT VALUE { ref: in, node: (SELECT VALUE { row: name, now: ->purchased.len() > 0 } FROM ONLY $parent.in) } FROM purchased;\nSELECT VALUE { ref: id, row: name } FROM customer WHERE ->purchased.len() > 0;")
# A `Linked` of a read row that a clause reads adds a `LIVE` on its table, as a `Link` does, at its path.
expect request_of(Surreal.from(order_reads).select(|o| { who: o.customer.name }).live({}, shop_tables)) == Ok("LIVE SELECT VALUE { row: { who: customer.name }, now: true } FROM order;\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: { who: customer.name }, now: true } FROM order WHERE customer = $parent.id) FROM customer WHERE $before IS NONE OR $after IS NONE OR $before.name != $after.name;\nSELECT VALUE { ref: id, row: { who: customer.name } } FROM order;")
# A `Linked` of an edge row of an `Out` field, read or whole.
expect request_of(Surreal.from(customer_reads).select(|c| { titles: c.purchased.list().map(|e| e.to.title) }).live({}, shop_tables)) == Ok("LIVE SELECT VALUE { row: { titles: ->purchased->?.title }, now: true } FROM customer;\nLIVE SELECT VALUE { ref: in, node: (SELECT VALUE { row: { titles: ->purchased->?.title }, now: true } FROM ONLY $parent.in) } FROM purchased;\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: { titles: ->purchased->?.title }, now: true } FROM customer WHERE $parent.id IN ->purchased.out) FROM product WHERE $before IS NONE OR $after IS NONE OR $before.title != $after.title;\nSELECT VALUE { ref: id, row: { titles: ->purchased->?.title } } FROM customer;")
expect request_of(Surreal.from(customer_reads).select(|c| c).live({}, shop_tables)) == Ok("LIVE SELECT VALUE { row: { address: address, id: record::id(id), name: name, purchased: ->purchased.{ from: in, id: record::id(id), quantity, to: out.{ id: record::id(id), price, title } }, tags: tags }, now: true } FROM customer;\nLIVE SELECT VALUE { ref: in, node: (SELECT VALUE { row: { address: address, id: record::id(id), name: name, purchased: ->purchased.{ from: in, id: record::id(id), quantity, to: out.{ id: record::id(id), price, title } }, tags: tags }, now: true } FROM ONLY $parent.in) } FROM purchased;\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: { address: address, id: record::id(id), name: name, purchased: ->purchased.{ from: in, id: record::id(id), quantity, to: out.{ id: record::id(id), price, title } }, tags: tags }, now: true } FROM customer WHERE $parent.id IN ->purchased.out) FROM product;\nSELECT VALUE { ref: id, row: { address: address, id: record::id(id), name: name, purchased: ->purchased.{ from: in, id: record::id(id), quantity, to: out.{ id: record::id(id), price, title } }, tags: tags } } FROM customer;")
# A whole read row reads each `Linked` of it; a field read reads its own.
expect request_of(Surreal.from(order_reads).select(|o| o).live({}, shop_tables)) == Ok("LIVE SELECT VALUE { row: { customer: customer.{ address, id: record::id(id), name, tags }, id: record::id(id), items: items.{ product: product.{ id: record::id(id), price, title }, qty }, payment: payment, total: total }, now: true } FROM order;\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: { customer: customer.{ address, id: record::id(id), name, tags }, id: record::id(id), items: items.{ product: product.{ id: record::id(id), price, title }, qty }, payment: payment, total: total }, now: true } FROM order WHERE customer = $parent.id) FROM customer;\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: { customer: customer.{ address, id: record::id(id), name, tags }, id: record::id(id), items: items.{ product: product.{ id: record::id(id), price, title }, qty }, payment: payment, total: total }, now: true } FROM order WHERE $parent.id IN items[*].product) FROM product;\nSELECT VALUE { ref: id, row: { customer: customer.{ address, id: record::id(id), name, tags }, id: record::id(id), items: items.{ product: product.{ id: record::id(id), price, title }, qty }, payment: payment, total: total } } FROM order;")
# The ends of the edges are a graph path (`->?`, as the read row does not name the table), so
# a later `map` reads the records, and a whole one is shaped once.
expect Surreal.from(customer_reads).select(|c| { bought: c.purchased.list().map(|e| e.to) }).to_surql() == Ok("SELECT ->purchased->?.{ id: record::id(id), price, title } AS bought FROM customer")
expect Surreal.from(customer_reads).select(|c| { ids: c.purchased.list().map(|e| e.to).map(|p| p.id) }).to_surql() == Ok("SELECT ->purchased->?.map(|$v2| record::id($v2)) AS ids FROM customer")

# A read row of a nominal row that links to its own table. A `Linked` of
# `Patron` is the fields of the stored row, so its own `sponsor` is a `Link`.
Patron := { id : Str, name : Str, address : Address, sponsor ?: Surreal.Link(Patron) }.{
	encoder_for : _
}

Card : { id : Str, holder : Surreal.Link(Patron) }

CardRead : { id : Str, holder : Surreal.Linked(Patron) }

PatronRead : { id : Str, name : Str, address : Address, sponsor ?: Surreal.Linked(Patron) }

patrons : Surreal.Table(Patron)
patrons = Surreal.table("patron")

cards : Surreal.Table(Card)
cards = Surreal.table("card")

card_reads : Surreal.Table(CardRead)
card_reads = Surreal.table("card")

patron_reads : Surreal.Table(PatronRead)
patron_reads = Surreal.table("patron")

club_tables : List(Surreal.Defined)
club_tables = [patrons.define().done(), cards.define().done()]

expect Surreal.from(card_reads).select(|c| { who: c.holder.name, city: c.holder.address.city }).to_surql() == Ok("SELECT holder.address.city AS city, holder.name AS who FROM card")
expect Surreal.from(card_reads).select(|c| c).to_surql() == Ok("SELECT holder.{ address, id: record::id(id), name, sponsor } AS holder, record::id(id) AS id FROM card")
expect Surreal.from(patron_reads).select(
	|m| {
		name: m.name,
		by: match m.?sponsor {
			Ok(s) => s.name
			Err(_) => "-"
		},
	},
).to_surql() == Ok("SELECT (IF sponsor IS NONE THEN '-' ELSE sponsor.name END) AS by, name AS name FROM patron")
expect Surreal.from(patron_reads).filter(|m| m.?sponsor.map_ok(|s| s.address.city == m.address.city) ?? Bool.False).select_value(|m| m.name).to_surql() == Ok("SELECT VALUE name FROM patron WHERE (IF sponsor IS NONE THEN NONE ELSE sponsor.address.city = address.city END) ?? false")
# A live query finds the table of a `Linked(Patron)` by its row, `Patron`.
# The clause reads no `sponsor`, so `holder.sponsor` is not watched.
expect request_of(Surreal.from(card_reads).select(|c| { who: c.holder.name }).live({}, club_tables)) == Ok("LIVE SELECT VALUE { row: { who: holder.name }, now: true } FROM card;\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: { who: holder.name }, now: true } FROM card WHERE holder = $parent.id) FROM patron WHERE $before IS NONE OR $after IS NONE OR $before.name != $after.name;\nSELECT VALUE { ref: id, row: { who: holder.name } } FROM card;")

# A second hop: `.get()`, then `.get()` of a link of that row, at the path
# of both links, `holder.sponsor`.
expect request_of(Surreal.from(cards).select_value(|c| c.holder.get().?sponsor.map_ok(|s| s.get().name) ?? "-").live({}, club_tables)) == Ok("LIVE SELECT VALUE { row: holder.sponsor.name ?? '-', now: true } FROM card;\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: holder.sponsor.name ?? '-', now: true } FROM card WHERE holder = $parent.id OR holder.sponsor = $parent.id) FROM patron WHERE $before IS NONE OR $after IS NONE OR $before.sponsor != $after.sponsor OR $before.name != $after.name;\nSELECT VALUE { ref: id, row: holder.sponsor.name ?? '-' } FROM card;")

# A read row that holds a `Linked` of itself: a field read goes on through it,
# and the whole row has no finite fetch plan. A live query watches each
# hop that a clause reads: a write to the row at `sponsor` or at
# `sponsor.sponsor` reaches the row.
PatronLoop := { id : Str, name : Str, address : Address, sponsor ?: Surreal.Linked(PatronLoop) }

patron_loops : Surreal.Table(PatronLoop)
patron_loops = Surreal.table("patron")

CardLoop : { id : Str, holder : Surreal.Linked(PatronLoop) }

card_loops : Surreal.Table(CardLoop)
card_loops = Surreal.table("card")

# The table of a `Linked(PatronLoop)` is the one that lists that read row.
loop_tables : List(Surreal.Defined)
loop_tables = club_tables.append(patron_loops.define_read())

expect Surreal.from(patron_loops).select_value(|m| m.?sponsor.map_ok(|s| s.?sponsor.map_ok(|t| t.name) ?? "-") ?? "-").to_surql() == Ok("SELECT VALUE (IF sponsor IS NONE THEN NONE ELSE sponsor.sponsor.name ?? '-' END) ?? '-' FROM patron")
expect Surreal.from(patron_loops).select(|m| m).to_surql() == Err(Unsupported("in `select`: a whole read row that holds a `Linked` of itself has no finite fetch plan: each `Linked` of it fetches the row again, with no last hop; select its fields, or make the link a `Linked` of the stored row (`Linked(Owner)` for a stored `Owner`), whose own links are `Link`"))
expect Surreal.from(patron_loops).select(|m| { name: m.name, by: m.?sponsor.map_ok(|s| s.name) ?? "-" }).to_surql() == Ok("SELECT sponsor.name ?? '-' AS by, name AS name FROM patron")
expect request_of(Surreal.from(patron_loops).select_value(|m| m.?sponsor.map_ok(|s| s.?sponsor.map_ok(|t| t.name) ?? "-") ?? "-").live({}, loop_tables)) == Ok("LIVE SELECT VALUE { row: (IF sponsor IS NONE THEN NONE ELSE sponsor.sponsor.name ?? '-' END) ?? '-', now: true } FROM patron;\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: (IF sponsor IS NONE THEN NONE ELSE sponsor.sponsor.name ?? '-' END) ?? '-', now: true } FROM patron WHERE sponsor = $parent.id OR sponsor.sponsor = $parent.id) FROM patron WHERE $before IS NONE OR $after IS NONE OR $before.sponsor != $after.sponsor OR $before.name != $after.name;\nSELECT VALUE { ref: id, row: (IF sponsor IS NONE THEN NONE ELSE sponsor.sponsor.name ?? '-' END) ?? '-' } FROM patron;")
# A `Linked` of a read row that holds a `Linked` of itself finds its table
# by that read row, which `define_read` lists. Field reads go
# through it, the whole row is refused, and a live query watches `holder`,
# and `holder.sponsor` when a clause reads it.
expect Surreal.from(card_loops).select(|c| { who: c.holder.name, by: c.holder.?sponsor.map_ok(|s| s.name) ?? "-" }).to_surql() == Ok("SELECT holder.sponsor.name ?? '-' AS by, holder.name AS who FROM card")
expect Surreal.from(card_loops).select(|c| c).to_surql() == Err(Unsupported("in `select`: a whole read row that holds a `Linked` of itself has no finite fetch plan: each `Linked` of it fetches the row again, with no last hop; select its fields, or make the link a `Linked` of the stored row (`Linked(Owner)` for a stored `Owner`), whose own links are `Link`"))
expect request_of(Surreal.from(card_loops).select(|c| { who: c.holder.name }).live({}, loop_tables)) == Ok("LIVE SELECT VALUE { row: { who: holder.name }, now: true } FROM card;\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: { who: holder.name }, now: true } FROM card WHERE holder = $parent.id) FROM patron WHERE $before IS NONE OR $after IS NONE OR $before.name != $after.name;\nSELECT VALUE { ref: id, row: { who: holder.name } } FROM card;")
expect request_of(Surreal.from(card_loops).select(|c| { by: c.holder.?sponsor.map_ok(|s| s.name) ?? "-" }).live({}, loop_tables)) == Ok("LIVE SELECT VALUE { row: { by: holder.sponsor.name ?? '-' }, now: true } FROM card;\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: { by: holder.sponsor.name ?? '-' }, now: true } FROM card WHERE holder = $parent.id OR holder.sponsor = $parent.id) FROM patron WHERE $before IS NONE OR $after IS NONE OR $before.sponsor != $after.sponsor OR $before.name != $after.name;\nSELECT VALUE { ref: id, row: { by: holder.sponsor.name ?? '-' } } FROM card;")
expect request_of(Surreal.from(card_loops).select(|c| { who: c.holder.name }).live({}, club_tables)) == Err(BadSchema("a live query watches the table of each link of its row, and the tables it takes do not name the one at `holder`: no table holds the row type `PatronLoop`; list its table in the schema"))

# ------------------------------------------------- the session's record user

# A query, a write and a live query that a record user runs read the
# session: `customers.auth()` is `$auth.id`, an `Id` of the table, so a
# link compares with it, and so does the key of the row as an `Id`.
expect Surreal.from(orders).filter(|o| o.customer.id() == customers.auth()).select(|o| { total: o.total }).to_surql() == Ok("SELECT total AS total FROM order WHERE customer = $auth.id")
expect Surreal.from(customers).filter(|c| customers.id(c.id) == customers.auth()).select_value(|c| c.name).to_surql() == Ok("SELECT VALUE name FROM customer WHERE id = $auth.id")
expect orders.update(|o| o.customer.id() == customers.auth(), |o| { ..o, total: 0 }).to_surql() == Ok("UPDATE order SET total = 0.0dec WHERE customer = $auth.id")
expect orders.delete(|o| o.customer.id() != customers.auth() and Surreal.Auth.access() == "shop").to_surql() == Ok("DELETE order WHERE (customer != $auth.id) AND ($access = 'shop')")
expect request_of(Surreal.from(orders).filter(|o| o.customer.id() == customers.auth()).select(|o| { total: o.total }).live({}, [])) == Ok("LIVE SELECT VALUE { row: { total: total }, now: customer = $auth.id } FROM order WHERE (customer = $auth.id) OR ($before IS NOT NONE AND ($before.customer = $auth.id));\nSELECT VALUE { ref: id, row: { total: total } } FROM order WHERE customer = $auth.id;")

# ------------------------------------------------ full-text and vector search

Review : { id : Str, product : Surreal.Link(Product), text : Str, vec : List(F64) }

reviews : Surreal.Table(Review)
reviews = Surreal.table("review")

## Another table of the same row type.
old_reviews : Surreal.Table(Review)
old_reviews = Surreal.table("old_review")

words : Surreal.Analyzer
words = Surreal.analyzer("words", [Class], [Lowercase])

review_text : Surreal.FullText(Review)
review_text = reviews.text_index(|r| r.text, words)

review_vectors : Surreal.VectorIndex(Review)
review_vectors = reviews.vector_index(|r| r.vec, { dimension: 2, distance: Euclidean })

# A search is `@1@`: the library numbers it, and the hit of the pair reads
# its score, highlights and offsets. A filter before it is `AND`ed, and
# the terms are one quoted text.
expect Surreal.from(reviews).search(review_text, "it's sturdy").select_value(|(r, _)| r.id).to_surql() == Ok("SELECT VALUE record::id(id) FROM review WHERE text @1@ 'it\\'s sturdy'")
expect
	Surreal.from(reviews)
		.filter(|r| r.product.id == pen_id)
		.search(review_text, "sturdy")
		.select(|(r, hit)| { id: r.id, score: hit.score(), marked: hit.highlight("[", "]"), at: hit.offsets() })
		.order_by(|h| h.score, Desc)
		.limit(3)
		.to_surql()
	== Ok("SELECT search::offsets(1)['0'].map(|$o| { end: $o.e, start: $o.s }) AS at, record::id(id) AS id, search::highlight('[', ']', 1) AS marked, search::score(1) AS score FROM review WHERE (product = product:⟨pen⟩) AND (text @1@ 'sturdy') ORDER BY score DESC LIMIT 3")

# A search reads the rows of the table of its index.
expect Surreal.from(old_reviews).search(review_text, "sturdy").select_value(|(r, _)| r.id).to_surql() == Err(Unsupported("the index is of the table `review`, and this query reads `old_review`"))
expect Surreal.from(reviews).select(|r| { id: r.id, text: r.text, product: r.product, vec: r.vec }).query().search(review_text, "sturdy").select_value(|(r, _)| r.id).to_surql() == Err(Unsupported("a search reads the rows of the table of its index, and this query reads the rows of a subquery"))

# `nearest`: `<|k,ef|>` through the HNSW graph, `<|k,DISTANCE|>` over every
# row, with the distance of the index, and the distance of each row.
expect Surreal.from(reviews).nearest(review_vectors, [1.5, -2], Approx({ k: 4, ef: 64 })).select(|(r, near)| { id: r.id, far: near.distance() }).to_surql() == Ok("SELECT vector::distance::knn() AS far, record::id(id) AS id FROM review WHERE vec <|4,64|> [1.5f, -2f]")
expect Surreal.from(reviews).filter(|r| r.text != "").nearest(review_vectors, [1, 0], Exact(2)).select_value(|(r, _)| r.id).to_surql() == Ok("SELECT VALUE record::id(id) FROM review WHERE (text != '') AND (vec <|2,EUCLIDEAN|> [1f, 0f])")

# A probe of another dimension than the index's is refused.
expect Surreal.from(reviews).nearest(review_vectors, [1, 0, 0], Exact(2)).select_value(|(r, _)| r.id).to_surql() == Err(Unsupported("the probe of `nearest` has 3 numbers, and the vector index of `review.vec` has the dimension 2"))

# A live query has no search.
expect Surreal.from(reviews).search(review_text, "sturdy").select_value(|(r, _)| r.id).live({}, []).request() == Err(Unsupported("a live query has no full-text or vector search: a search reads its index, and a notice is of one written row; watch the rows with a `filter`, and search them when a notice comes"))
expect Surreal.from(reviews).nearest(review_vectors, [1, 0], Exact(2)).select_value(|(r, _)| r.id).live({}, []).request() == Err(Unsupported("a live query has no full-text or vector search: a search reads its index, and a notice is of one written row; watch the rows with a `filter`, and search them when a notice comes"))

# A prepared search, with a parameter of another filter.
expect Surreal.from(reviews).search(review_text, "sturdy").filter_by(|p, (r, _)| r.product.id == p.product).select_value(|(r, _)| r.id).prepare({ product: pen_id }).request() == Ok("LET $product = product:⟨pen⟩;\nSELECT VALUE record::id(id) FROM review WHERE (text @1@ 'sturdy') AND (product = $product);")

# The types of CBOR v2 in a clause. `==` and `<` compare the fields of the
# backing, so a `date` is its days and a `time` its nanoseconds; a captured
# one is bound as that number. The other types have no expression for each
# field, and are refused.
Kinds : { id : Str, day : Surreal.Date, at : Surreal.TimeOfDay, span : Surreal.Interval }

kinds : Surreal.Table(Kinds)
kinds = Surreal.table("kinds")

kinds_on : Surreal.Date -> Try(Str, Surreal.Error)
kinds_on = |day| Surreal.from(kinds).filter(|k| k.day == day).select_value(|k| k.id).ready().request()

expect kinds_on(Surreal.Date.from_days(5)) == Ok("LET $_1 = 5;\nSELECT VALUE record::id(id) FROM kinds WHERE (day - <date>'1970-01-01') = $_1;")
expect Surreal.from(kinds).filter(|k| k.day < Surreal.Date.from_days(0)).select_value(|k| k.id).ready().request() == Ok("SELECT VALUE record::id(id) FROM kinds WHERE (day - <date>'1970-01-01') < 0;")
expect Surreal.from(kinds).filter_by(|p, k| k.at == p.at).select_value(|k| k.id).prepare({ at: Surreal.TimeOfDay.from_nanos(1) ?? crash "valid" }).request() == Ok("LET $at = <time>'00:00:00.000000001';\nSELECT VALUE record::id(id) FROM kinds WHERE duration::nanos(<duration>at) = duration::nanos(<duration>$at);")
expect Surreal.from(kinds).filter_by(|p, k| k.span == p.span).select_value(|k| k.id).prepare({ span: Surreal.Interval.from_parts({ months: 1, days: 0, micros: 0 }) }).request() == Err(Unsupported("in `filter_by`: a `interval` in a clause has no SurrealQL form for its parts; compare it in Roc after the read"))
