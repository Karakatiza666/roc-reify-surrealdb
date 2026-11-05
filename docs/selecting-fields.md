# Choosing the fields to read

This page shows how you choose the columns of a query. You do not write a column list. You write a Roc function that reads fields of the row and builds a record. The fields that the function reads, and the record that it builds, are the `SELECT` list. The type of that record is the type of each result row.

```
row -> projection function -> record it builds
            |                      |
   fields it reads           fields it has
            |                      |
       SELECT expressions     AS column names  --> each result row has type `out`
```

The terms "clause", "read row" and "reified" are in the [glossary](getting-started.md#words-used-in-these-pages).

## A projection is a function

Call `select(f)` on a query. The type is `select : Query(p, row), Code(row -> out) -> Selected(p, out)`. You pass an ordinary function of type `row -> out`.

| Part of `f` | Becomes |
| --- | --- |
| Each field of the record that `f` builds | One column, with the field name as its alias |
| The expression of that field | The SurrealQL expression of the column |
| The type `out` | The type of each result row. The compiler checks it |

```roc
# Fragment: uses `Owner` and `owners` from examples/main.roc.
OwnerCard : { id : Str, name : Str, phone : Str }

owner_card : Owner -> OwnerCard
owner_card = |o| { id: o.id, name: o.name, phone: o.?phone ?? "none" }

cards = Surreal.from(owners).select(owner_card)
```

From `examples/main.roc`, `owner_card`. `cards.to_surql()` gives:

```surql
SELECT record::id(id) AS id, name AS name, phone ?? 'none' AS phone FROM owner
```

A prepared `cards` gives a `Prepared(List(OwnerCard))`. You do not write a decoder. The row type of the reply is `OwnerCard`, because `owner_card` returns it.

The function stays a Roc function. `examples/main.roc` calls it on its seed rows, and `owner_card(jon).phone == "none"` is an `expect` there. The query and your own code use one definition.

When only this query uses the function, write it inline: `select(|o| { name: o.name })`. The compiler still checks it, and the type of each result row is the record that it builds. Name the function, with a type annotation, when a test or another query reuses it.

## Only the fields you read are fetched

The translator reads the body of the function. Each field access becomes a path. Each other expression becomes an expression column. A field that the function does not read is not in the `SELECT` list, so the server does not send it.

| You write in the record | Column (from a real run) |
| --- | --- |
| `name: o.name` | `name AS name` |
| `city: o.address.city` | `address.city AS city` |
| `address: o.address` | `address AS address` (the whole object) |
| `zip: o.address.?zip ?? "-"` | `address.zip ?? '-' AS zip` |
| `phone: o.?phone ?? "none"` | `phone ?? 'none' AS phone` |
| `id: o.id` | `record::id(id) AS id` (the key as text, see [Ids in results](#ids-in-results)) |

The column name is the field name of the record you build, not the name of the field you read. So `{ zone: o.address.city }` gives `address.city AS zone`. The columns come out in name order, not in the order you write them:

```surql
SELECT name AS all, email AS mail, address.city AS zone FROM owner
```

That is `select(|o| { zone: o.address.city, all: o.name, mail: o.email })`. The order of the columns does not change the result. Each row is a record, read by field name.

### Nested records

A record field of the row is an object in SurrealDB. Read one field of it with a path (`o.address.city`), or the whole object (`o.address`). The type of the result field follows: `Str` for the path, `Address` for the object.

### Optional fields

An optional field `phone ?: Str` gives `o.?phone : Try(Str, [MissingField])`. Each field of the record that you build is required, so turn the `Try` into a value:

| Form | Result field | Column |
| --- | --- | --- |
| `o.?phone ?? "none"` | `Str` | `phone ?? 'none'` |
| `p.?chip.map_ok(\|c\| c.code) ?? "none"` | `Str` | `chip.code ?? 'none'` |
| `match p.?chip { Ok(c) => c.code, Err(_) => "none" }` | `Str` | `chip.code ?? 'none'` |
| `match p.?chip { Ok(c) => c.implanted_by.get().name, Err(_) => "nobody" }` | `Str` | `(IF chip IS NONE THEN 'nobody' ELSE chip.implanted_by.name END)` |

The `map_ok(..) ?? d` form is the short one, and `chip_line` in `examples/main.roc` uses it. The two `match` rows are written for this page. When the `Ok` arm reads only fields of the optional record, the translator writes the path with `??`, because the field of a missing record is `NONE`. When the arm reads through a link, the row may be gone, so the test of `NONE` stays. [Writing queries](queries.md#match-on-unions-and-optional-fields) shows `match`, `is_ok` and `??` in more detail. [Row types and data types](data-types.md#optional-fields) shows how an optional field is stored.

### The result type limits the next clauses

After `select`, the rows are of type `out`. A later `filter`, `order_by` or `group_by` reads `out`, not the table row. A read of a field that the projection did not keep is a compile error:

```roc
# Fragment: uses `owners` from examples/main.roc.
Surreal.from(owners).select(|o| { id: o.id, name: o.name }).filter(|c| c.email != "")
```

`roc check` reports `This record does not have a field named email.` Add the field to the projection, or filter before `select`.

A filter after `select` still reads the source row. The translator puts the projection expression in the `WHERE`. For `select(owner_card).filter(|c| c.phone != "none")`:

```surql
SELECT record::id(id) AS id, name AS name, phone ?? 'none' AS phone FROM owner WHERE (phone ?? 'none') != 'none'
```

[Writing queries](queries.md#filter-the-results-of-a-projection) covers the other clauses after `select`.

## One value per row

Call `select_value(f)` when each result is one value, not a record. The type is `select_value : Query(p, row), Code(row -> v) -> Selected(p, v)`. A prepared query gives a `List(v)`.

| Roc | SurrealQL | Result |
| --- | --- | --- |
| `select_value(\|o\| o.name)` | `SELECT VALUE name FROM owner` | `List(Str)` |
| `select_value(\|v\| v.contact)` | `SELECT VALUE contact FROM vet` | `List(Contact)` |

The same rules apply: the fields that `f` reads are the fields that the server sends. `order_by` after `select_value` has its own rules. See [Writing queries](queries.md#order-and-page-results).

## The whole row

Return the row itself to read every field of its type: `select(|r| r)` or `select_value(|r| r)`. Each field of the Roc type is one column. A field that the database has and the type does not is not read.

| Roc | SurrealQL |
| --- | --- |
| `Surreal.from(owners).select(\|o\| o)` | `SELECT address, email, record::id(id) AS id, name, phone, referred_by, tags FROM owner` |
| `Surreal.from(vets).select_value(\|v\| v)` | `SELECT VALUE { contact: contact, id: record::id(id), license: license, name: name, rate: rate, specialty: specialty, years: years } FROM vet` |

A query that has no `select` at all reads the whole rows too. `Query` has the calls that `Selected` has, with the row as the result:

| Call | Same as | Gives |
| --- | --- | --- |
| `Surreal.from(owners).prepare(params)` | `.select(\|r\| r).prepare(params)` | `Try(Prepared(List(Owner)), Error)` |
| `Surreal.from(owners).ready()` | `.prepare({})` | The same, for a query with no parameter |
| `owners.at(id).prepare_one(params)`, `.ready_one()` | `.select(\|r\| r).prepare_one(params)` | `Try(Prepared(Try(Owner, [NotFound])), Error)` |
| `query.live(params, definitions)`, `.ready_live(definitions)` | `.select(\|r\| r).live(params, definitions)` | `Try(Watch(Owner), Error)` |

The text is the same as the text of `select(|r| r)`. Write `select(|r| r)` only when a later clause needs a `Selected`, such as `order_by`.

The key comes out as `record::id(id) AS id`, so `id` is text, as the row type says. An optional field (`phone`) is selected, and a row with no value for it reads back with the field absent. The result type is the row type, so the whole row works for alias rows and nominal rows.

The whole row also works for an object (`|v| v.contact`) and for a linked row (`|p| p.owner.get()`). The next sections show linked rows.

### Read through a link

A `Link(r)` field holds the id of a row in another table. In a clause, `link.get()` is the linked row. A field read through it is a traversal of the link. You do not add `FETCH`.

```roc
# Fragment: uses `Patient` and `patients` from examples/main.roc.
ContactLine : { id : Str, city : Str, vets : List(Str) }

contact_line : Patient -> ContactLine
contact_line = |p| { id: p.id, city: p.owner.get().address.city, vets: p.vaccines.map(|v| v.vet.get().name) }
```

`contact_line` is from `examples/main.roc`, the query `linked_fields`. `Surreal.from(patients).select(contact_line)` gives:

```surql
SELECT owner.address.city AS city, record::id(id) AS id, vaccines.map(|$v1| $v1.vet.name) AS vets FROM patient
```

| Roc | SurrealQL | What the server reads |
| --- | --- | --- |
| `p.owner.get().name` | `owner.name` | One field of the linked owner |
| `p.owner.get()` | `owner.{ address, email, id: record::id(id), name, .. }` | Each field of the `Owner` type |
| `p.vaccines.map(\|v\| v.vet.get().name)` | `vaccines.map(\|$v1\| $v1.vet.name)` | One field of each linked vet in a list of records |
| `match p.?chip { Ok(c) => c.implanted_by.get().name, .. }` | `(IF chip IS NONE THEN 'nobody' ELSE chip.implanted_by.name END)` | A link in an optional record |

To read whole linked rows, return them. From `examples/main.roc`, `linked_rows`:

```roc
# Fragment: uses `Patient`, `Owner` and `Vet` from examples/main.roc.
LinkedRows : { id : Str, owner : Owner, vets : List(Vet) }

linked_rows : Patient -> LinkedRows
linked_rows = |p| { id: p.id, owner: p.owner.get(), vets: p.vaccines.map(|v| v.vet.get()) }
```

The column for `owner` is `owner.{ address, email, id: record::id(id), name, phone, referred_by, tags } AS owner`. A link inside the linked row (`referred_by`) stays an id. Add another `.get()` to read through it.

Each read through a link is a traversal of its own. Two fields of one link are two traversals. A whole linked row is one. If you read many fields of one linked row, return the whole row.

[Ids, links and graph edges](links-and-graphs.md#links) explains `Link` and `get()`. `get()` outside a clause works only on a link that holds a fetched row.

### Read rows as a fetch plan

A read row is a second row type for one table, for queries only. It has a `Surreal.Linked(r)` field where the stored row has a `Link(r)`, and it can have `Surreal.Out(e)` and `Surreal.In(e)` fields for edge tables. A field read through a `Linked` needs no `.get()`.

```roc
# Fragment: uses `Site`, `CareRead` and `kennel_reads` from examples/monitoring.roc.
KennelRead : { id : Str, label : Str, site : Surreal.Linked(Site), cares_for : Surreal.In(CareRead) }

site_names = Surreal.from(kennel_reads).select(|k| { label: k.label, site: k.site.name })
```

`site_names` gives `SELECT label AS label, site.name AS site FROM kennel`.

The whole read row is a fetch plan. `select(|k| k)` reads each `Linked` as the fields of its row, at any depth, and each `Out` or `In` field as its edges:

```surql
SELECT <-cares_for.{ from: in.{ id: record::id(id), name }, id: record::id(id), lead, to: out } AS cares_for, record::id(id) AS id, label, site.{ id: record::id(id), name } AS site FROM kennel
```

So the type of the read row says how deep the query reads. A `Linked` reads the linked row. A `Link` stays an id (`to: out` above). [Ids, links and graph edges](links-and-graphs.md#read-rows) shows how to define a read row and how `define_read()` checks it.

## Ids in results

The key and the links read as follows:

| Roc | Result type | SurrealQL | Value |
| --- | --- | --- | --- |
| `c.id` (the row key) | `Str` | `record::id(id)` | The key text, such as `"jon"` |
| `p.owner.id` or `p.owner.id()` | `Surreal.Id(Owner)` | `owner` | The record id that the link holds |
| `p.owner.id.key()` | `Str` | `record::id(owner)` | The key text of the link |
| `p.owner.get().id` | `Str` | `record::id(owner)` | The same key text. It reads no linked row |
| `p.owner` in a whole row | `Surreal.Link(Owner)` | `owner` | A link that holds the id and no fetched row |

The whole row `Surreal.from(patients).select(|p| p)` gives `SELECT age, chip, record::id(id) AS id, name, owner, vaccines FROM patient`. Its `owner` is a record id, not the owner row. To get the owner row, return `p.owner.get()` or use a read row with `owner : Linked(Owner)`.

[Ids, links and graph edges](links-and-graphs.md#the-id-of-a-link) explains `link.id`, `link.id()` and why `link.fetched` is refused.

## Shapes a projection cannot have

The function compiles, but `to_surql` and `prepare` give `Err(Unsupported(why))`. The text is from a real run.

| Shape | Message (`why`) | Write instead |
| --- | --- | --- |
| A union payload built from a whole record: `{ k: Full(s.crate) }` | ``in `select`: the payload of `Full` is a record the clause does not build field by field`` | `Full({ a: s.crate.a, b: s.crate.b })`, which gives `{ kind: 'Full', a: crate.a, b: crate.b }` |
| The whole read row, when it holds a `Linked` of itself (`sponsor ?: Linked(PatronLoop)` in `PatronLoop`) | ``in `select`: a whole read row that holds a `Linked` of itself has no finite fetch plan: each `Linked` of it fetches the row again, with no last hop; select its fields, or make the link a `Linked` of the stored row (`Linked(Owner)` for a stored `Owner`), whose own links are `Link` `` | Select its fields, or use `Linked(Owner)` of the stored row |
| A whole value that holds a `Linked` in a union or in a list of lists (`shifts : List(List(Linked(Carer)))`) | ``in `select`: a whole value that holds a `Linked` in a union or in a list of lists has no SurrealQL form; select its fields`` | Select its fields |

A field read through a self-linked read row works at any depth: `m.?sponsor.map_ok(|s| s.name) ?? "-"` is a traversal. Only the whole row has no end.

An `if` or `match` whose arms return records works. `{ c: match v.specialty { General => v.contact, _ => { email: "-", phone: "-" } } }` gives `(IF specialty = 'General' THEN contact ELSE { email: '-', phone: '-' } END) AS c`.

[Errors](errors.md#build-time-errors) shows how to match on `Unsupported`.

## How field reads decide what a live query watches

A live query watches what the clauses read, not the whole row type. The same field reads that pick the columns also pick the watched tables and fields.

| The clauses read | The live query watches |
| --- | --- |
| Fields of the row | The table of the query |
| A field through a link, `k.site.get().name` | Also the linked table, and only the field `name` of it |
| A link that no clause reads through | Not its table. A write there sends nothing |

For `Surreal.from(kennels).select(|k| { label: k.label, site: k.site.get().name }).ready_live(definitions)`, the second statement watches `site` with `WHERE $before IS NONE OR $after IS NONE OR $before.name != $after.name`. An update of a site that does not change `name` sends no notice. Without the `site` field in the projection, the watch has no statement on `site`.

[Live queries](live-queries.md#what-a-live-query-watches) lists every case.

## Limits

| Limit | What to do instead |
| --- | --- |
| A union payload built from a whole record is refused | Build the payload field by field |
| A whole read row that holds a `Linked` of itself is refused | Select its fields, or use a `Linked` of the stored row |
| A whole value with a `Linked` in a union or a list of lists is refused | Select its fields |
| A later clause reads only the fields of `out` | Keep the field in the projection, or filter before `select` |
| Each field read through a link is its own traversal | Return the whole linked row when you read many of its fields |
| A `Link` in a whole row is an id, not the row | Use `.get()`, or a read row with `Linked` |
| `SELECT *` and `FETCH` are not in the typed API | Use `Unchecked.select_star` and `Unchecked.fetch` (see [Escape hatches](advanced.md#select-every-field)) |
| The order of an edge list differs between Roc and SurrealDB | Compare as multisets, or sort in the clause |
| After an order, a limit, a start or a group, a read row is a copy: its linked rows hold the key as `id`, not a record id | Read the `id` before the order (see [Ids, links and graph edges](links-and-graphs.md#limits)) |
