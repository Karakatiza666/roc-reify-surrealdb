# Writing queries

This page shows how to filter, parameterize, order, page, group and total the rows of a table, and how to put these steps together into one complex query. Each step is a builder method. Each clause is a Roc function over the row.

```
Table(row)
  | Surreal.from(table), table.at(id)
  v
Query(p, row) --group_by--> Grouped(p, row, k) --aggregate--+
  |  filter, filter_by, between                             |
  |--totals--> Totals(p, out) --prepare(p), ready()--> Prepared(out) |
  |  select, select_value                                   |
  v                                                         |
Selected(p, out) <------------------------------------------+
  |  order_by, filter, query() (back to a Query)
  |--start--> Started(p, out) --limit--> Limited(p, out)
  |--limit--> Limited(p, out)
  |  prepare(p) or ready(), also on Started and Limited
  v
Prepared(List(out))
```

`p` is the parameter record. `row` is the row that the clauses read. `out` is the type of each result row. [Choosing the fields to read](selecting-fields.md) explains `select` and `select_value`. The terms "clause", "parameter record" and "captured value" are in the [glossary](getting-started.md#words-used-in-these-pages).

To see all the steps in one query, go to [Build a complex query step by step](#build-a-complex-query-step-by-step).

## Start a query

| Call | Type | SurrealQL |
| --- | --- | --- |
| `Surreal.from(table)` | `Table(row) -> Query(p, row)` | `FROM visit` |
| `table.at(id)` | `Table(row), Id(row) -> Query(p, row)` | `FROM vet:⟨ruth⟩` (the one record) |

A query is a value. You can name it, pass it to a function and add more clauses later. Nothing goes to the server until you prepare it and run it in a session (see [Sessions and typed results](sessions.md#run-a-prepared-statement)).

The type variable `p` stays open until a `filter_by` reads a field of it, or until `prepare(params)` fixes it. A query with no parameters takes `ready()` in place of `prepare({})`:

| Call | On | Gives |
| --- | --- | --- |
| `prepare(params)` | `Selected`, `Started`, `Limited`, `Totals`, `Write` and `Query` (whole rows) | `Prepared(List(out))`. `Totals` gives `Prepared(out)` |
| `ready()` | The same, when `p` is `{}` | The same as `prepare({})` |
| `prepare_one(params)`, `ready_one()` | `Selected` and `Query` of `table.at(id)` | `Prepared(Try(out, [NotFound]))` |
| `live(params, definitions)`, `ready_live(definitions)` | `Selected` and `Query` | `Watch(out)` (see [Live queries](live-queries.md#start-a-watch)) |

`ready()` is a compile error for a query that reads a parameter: its `p` is not `{}`. A `Query` also has `prepare`, `ready` and the other calls, for the whole rows (see [The whole row](selecting-fields.md#the-whole-row)).

## Filter rows

Call `filter(f)` with `f : row -> Bool`. It becomes the `WHERE` of the statement. In the function you can use:

| Roc | SurrealQL (from a real run) |
| --- | --- |
| `\|o\| o.tags.contains("vip")` | `WHERE tags CONTAINS 'vip'` |
| `\|v\| v.items.len() > 0 or v.outcome != Treated` | `WHERE (items.len() > 0) OR (outcome != 'Treated')` |
| `\|p\| p.vaccines.any(\|v\| v.vet.id() == ruth_id)` | `WHERE vet:⟨ruth⟩ IN vaccines[*].vet` |
| `\|v\| v.seen < Surreal.Time.now()` | `WHERE seen < time::now()` |

Each call to `filter` adds one condition. The conditions are joined with `AND`:

```roc
# Fragment: uses `visits` from examples/main.roc.
Surreal.from(visits).filter(|v| v.fee > 50).filter(|v| v.items.len() > 0 or v.outcome != Treated)
```

```surql
SELECT VALUE record::id(id) FROM visit WHERE (fee > 50.0dec) AND ((items.len() > 0) OR (outcome != 'Treated'))
```

Use `==` and `!=` on a tag with no payload. A tag with a payload needs a `match` (see [Match on unions and optional fields](#match-on-unions-and-optional-fields)).

A filter can call your own functions, such as `Clinic.bill`. The translator reads the body of each function that a clause calls, so the function must also have a SurrealQL form. A top-level constant, such as `ruth_id = vets.id("ruth")`, is written into the text as a literal.

`xs.any(|x| x.f == v)` over a list of records, where `v` does not read `x`, is `v IN xs[*].f`. An index of `xs[*].f` serves `IN`, and `any` reads the whole table. A closure that reads more than fields and link ids of the element stays `any`. [Functions in clauses](functions.md#what-you-can-call-in-a-clause) lists the builtins and package functions that you can call.

## Pass parameters

Call `filter_by(f)` with `f : p, row -> Bool`. The first argument is the parameter record. Each field that the function reads becomes a `$name`. `prepare(params)` writes one `LET` for each field.

```roc
# Fragment: uses `Owner`, `owners` and `owner_card` from examples/main.roc.
in_city : { city : Str }, Owner -> Bool
in_city = |p, o| o.address.city == p.city

Surreal.from(owners).filter_by(in_city).select(owner_card).prepare({ city: "Oslo" })
```

`in_city` and `owner_card` are from `examples/main.roc`. The script:

```surql
LET $city = 'Oslo';
SELECT record::id(id) AS id, name AS name, phone ?? 'none' AS phone FROM owner WHERE address.city = $city;
```

The parameter record is typed by field name. If two clauses read `p.since` and `p.least`, the record is `{ least : .., since : .. }`, and `prepare` takes exactly that record. A wrong name or a wrong type is a compile error.

Use a parameter for each value that changes between runs. A prepared statement keeps the text the same and only the `LET` values change. A live query also takes the parameter record (see [Live queries](live-queries.md#start-a-watch)).

## Use values from around the function

A chain in a function whose result is a `Prepared` or a `Watch` can read the values of that function. The compiler gives each value a `$_1`, `$_2`, .. slot. The statement fills the slots with `LET` lines when it runs:

```roc
# Fragment: uses `Medication` and `medications` from examples/main.roc.
cheaper_than : Dec -> Surreal.Prepared(List(Medication))
cheaper_than = |limit| Surreal.from(medications).filter(|m| m.unit_price < limit).ready()
```

From `examples/main.roc:528`. With `limit = 0.9`:

```surql
LET $_1 = 0.9dec;
SELECT form, record::id(id) AS id, label, name, stock, unit_price FROM medication WHERE unit_price < $_1;
```

The text is the same for each value. Only the `LET` values change.

| Where a value can go | Example | Text |
| --- | --- | --- |
| A clause of any step: `filter`, `select`, `order_by`, `group_by` and the others | `.filter(\|m\| m.unit_price >= least).select(\|m\| { over: m.unit_price - base })` | `WHERE unit_price >= $_1`, `unit_price - $_2 AS over` |
| The key of `at`, `set_at`, `update_at`, `update_at_by` and `delete_at` | `owners.set_at(key, \|_\| { name: name })` with `key : Surreal.Id(Owner)` | `LET $_1 = owner:⟨jon⟩; UPDATE $_1 SET name = $_2` |
| `limit` and `start` | `.start(skip).limit(size)` | `LIMIT $_2 START $_1` |

`tests/CapturedTest.roc` has each of these.

| | Parameter (`filter_by`, `prepare`) | Value from around the function |
| --- | --- | --- |
| Where the value comes from | The record you give to `prepare` | A value of the function around the chain |
| Name in the text | `$` and the field name | `$_1`, `$_2`, .. |
| Records with optional fields | Yes | Yes. An absent field is left out of the object |
| A `Link` | Yes | Refused: ``a captured `Link` has no SurrealQL value; capture its `id()` `` |
| A schema clause (`define`, `field`, an index, an event) | Not applicable | A compile error. A schema has no `LET` |

A chain written in place in the body of an effectful function, as an argument of a call, cannot read a value of that body. `roc check` reports `reified function captures a value`. Move the chain to a function of its own, as `shift_at` in `examples/client.roc:450`, and call it with the value.

A key from around the function must be of the table. A key of another table is an error in the statement: ``the id `vet:⟨jon⟩` is of the table `vet`, not of `owner` ``.

A key that the program fixes, as `owners.id("jon")` in a top-level value, is a constant of the statement: `owners.delete_at(owners.id("noor"))` gives `DELETE owner:⟨noor⟩`.

`Query.filter_with(query, [ext], f)` also takes values of another package's types (see [Escape hatches](advanced.md#extend-the-translator)).

### A statement that cannot be built

A `Prepared` holds its statement, or the error that stops it: a clause with no SurrealQL form, or a value with no SurrealQL value. `session.run!` gives that error as its result. `checked` gives it before a session:

| Call | Result |
| --- | --- |
| `prepared.checked()` | `Try(Prepared(out), Error)` |
| `prepared.statement()` | `Try(Statement, Error)` |
| `prepared.request()` | `Try(Str, Error)` |
| `first.then(second)`, `Surreal.transaction([..])` | A `Prepared` that keeps the first error |
| `session.send!(prepared)` | A ticket that holds the error. `await!` gives it |
| `watch.checked()`, `watch.request()` | The same for a `Watch` |

## Match on unions and optional fields

A clause can use `match`, `if`, `.?field`, `??` and `==` on a union. The translator writes `IF .. THEN .. ELSE .. END`. [Row types and data types](data-types.md#tag-unions) shows how a union is stored.

| Roc | SurrealQL (from a real run) |
| --- | --- |
| `match p.species { Bird(b) => b.wingspan_cm >= 20, _ => Bool.False }` | `(IF species.kind = 'Bird' THEN species.wingspan_cm >= 20 ELSE false END)` |
| `v.specialty == Dental` | `specialty = 'Dental'` |
| `v.specialty == Surgery({ board: "ACVS" })` | `(IF specialty.kind = 'Surgery' THEN specialty.board = 'ACVS' ELSE false END)` |
| `if v.fee >= 100 "large" else "small"` | `(IF fee >= 100.0dec THEN 'large' ELSE 'small' END)` |
| `o.?phone.is_ok()` | `phone IS NOT NONE` |
| `(o.?phone ?? "") != ""` | `(phone ?? '') != ''` |
| `match o.?referred_by { Ok(r) => r.get().name, Err(_) => "nobody" }` | `(IF referred_by IS NONE THEN 'nobody' ELSE referred_by.name END)` |

`o.?phone` has the type `Try(Str, [MissingField])`. Turn it into a value with `??`, `is_ok` or a `match` on `Ok` and `Err`. A `match` can read a link in an arm, such as `Referred(r) => "referred to ${r.to.get().name}"`.

A tag with no payload needs no `match`: `v.outcome != Treated` is enough. Use `match` for a tag with a payload, and put it in a named helper when two clauses need it. From `examples/main.roc`:

```roc
# Fragment: uses `Visit` from examples/main.roc.
referred : Visit -> Bool
referred = |v| match v.outcome {
	Referred(_) => Bool.True
	_ => Bool.False
}
```

## Compare keys

Compare the `id` of a row with a key to read one record. The translator writes a record id, so SurrealDB reads the one record and does not scan the table.

| Roc | SurrealQL |
| --- | --- |
| `.filter(\|v\| v.id == "ruth")` | `WHERE id = vet:⟨ruth⟩` |
| `.filter_by(\|p, v\| v.id == p.key)` | `WHERE id = type::record('vet', $key)` |
| `.filter(\|v\| v.vet.id == ruth_id)` (a link) | `WHERE vet = vet:⟨ruth⟩` |
| `vets.at(vets.id("ruth"))` | `FROM vet:⟨ruth⟩` |

For one row by key, prefer `table.at(id)`. `prepare_one(params)` on that query, or `ready_one()` when it has no parameter, gives `Prepared(Try(out, [NotFound]))`: the row, or `NotFound`. `prepare_one` on any other query is `Unsupported`. [Ids, links and graph edges](links-and-graphs.md#ids) explains `Id`.

## Order and page results

After a projection, call `order_by(key, Asc)` or `order_by(key, Desc)`. The key is one column of the result row: `|r| r.revenue`. For several keys, call `order_by` again. The first call is the first key.

```roc
# Fragment: uses `visits` from examples/main.roc.
Surreal.from(visits).select(|v| { id: v.id, vet: v.vet.get().name }).order_by(|r| r.vet, Asc).order_by(|r| r.id, Desc)
```

```surql
SELECT record::id(id) AS id, vet.name AS vet FROM visit ORDER BY vet, id DESC
```

SurrealDB orders by a field path only. A key that is not one column of the result, such as `|r| r.name.count_utf8_bytes()` or a path into a column, is `Unsupported`. Select the value as a column of its own, then order by that column.

Call `start(n)` to skip rows and `limit(n)` to keep at most `n` rows. The types allow only the order in which SurrealDB runs the clauses: `order_by` any number of times, then `start` at most once, then `limit` at most once.

| Chain | Result |
| --- | --- |
| `.order_by(\|r\| r.id, Asc).start(2).limit(2)` | `ORDER BY id LIMIT 2 START 2` |
| `.limit(2).order_by(..)` | Compile error: `Surreal.Limited(p, VisitLine)` has no method `order_by` |
| `.limit(10).start(20)`, `.limit(2).limit(5)` | Compile error. A `Limited` has no `start` or `limit` |
| `.start(1).start(2)` | Compile error. A `Started` has no `start` |

To order the rows of a limit, read them again with `query()` (see [Query the results again](#query-the-results-again)).

After `select_value`, the key reads the value. The value and the key together must be a path of fields of the source row. `select_value(|m| m.label).order_by(|l| l, Asc)` gives `SELECT VALUE label FROM medication ORDER BY label`. A computed value, a value read through a link, or `id` is `Unsupported`: ``"`order_by` of a `select_value` reads the value as a field path of the source row, and this value is computed, read through a link or `id` .."``. Use `select` with the value as a column.

## Filter the results of a projection

`filter(f)` also works after `select`, `order_by`, `start`, `limit` and `aggregate`. The function reads the result row `out`. A read of a field that the projection did not keep is a compile error.

| Before the filter | SurrealQL form |
| --- | --- |
| `select`, `select_value` | One `SELECT`. The filter reads the projection expressions in the same `WHERE` (see [Choosing the fields to read](selecting-fields.md#the-result-type-limits-the-next-clauses)) |
| `order_by` | One `SELECT`. An order does not change which rows a filter keeps |
| `start` or `limit` | A subquery: `SELECT .. FROM (SELECT .. LIMIT n) WHERE ..` |
| `aggregate` | A subquery. This is the `HAVING` of SQL, which SurrealDB 3.3.4 does not have |

After a limit, the filter keeps the rows of the limit only:

```roc
# Fragment: uses `visits` and `visit_line` from examples/main.roc.
Surreal.from(visits).select(visit_line).order_by(|r| r.id, Asc).limit(3).filter(|r| r.vet == "Ruth Okafor")
```

```surql
SELECT bill, id, patient, vet FROM (SELECT fee + math::sum(items.map(|$v1| <decimal>$v1.doses * $v1.medication.unit_price)) AS bill, record::id(id) AS id, patient.name AS patient, vet.name AS vet FROM visit ORDER BY id LIMIT 3) WHERE vet = 'Ruth Okafor'
```

The outer query keeps the order of the inner one. For a filter after a group, see [Build a complex query step by step](#build-a-complex-query-step-by-step).

## Query the results again

`query()` makes the result rows the rows of a new `Query(p, out)`. Every `Query` method then reads the type `out`: `filter`, `filter_by`, `select`, `group_by`, `totals`.

| The result before `query()` | The new query |
| --- | --- |
| A projection with no order, limit or start | The same `SELECT`. A clause reads the projection's fields over the source row |
| Any other | A subquery: `FROM (SELECT ..)` |

This orders the three most recent visits by vet:

```roc
# Fragment: uses `visits` and `visit_line` from examples/main.roc.
Surreal.from(visits).select(visit_line).order_by(|r| r.id, Desc).limit(3)
	.query().select(|r| { id: r.id, vet: r.vet }).order_by(|r| r.vet, Asc)
```

```surql
SELECT id AS id, vet AS vet FROM (SELECT fee + math::sum(..) AS bill, record::id(id) AS id, patient.name AS patient, vet.name AS vet FROM visit ORDER BY id DESC LIMIT 3) ORDER BY vet
```

A row of a subquery is a copy, not a stored record. So `outgoing`, `incoming`, `between` and `live` are `Unsupported` after a subquery.

To read another table inside a clause, use `table.rows()`. It is a subquery in the clause, such as a semi join: `.filter(|v| visits.rows().any(|x| x.vet.get().id == v.id))` on `vets` gives `WHERE record::id(id).chain(|$v1_0| (SELECT VALUE id FROM visit WHERE record::id(vet) = $v1_0 LIMIT 1)) != []`. The tests of the function that read the row of `visits` go into the `WHERE` of the subquery, and a value of the clause is bound around it with `chain`. The rows of one series of a time series are a range scan of the keys (see [Read other tables in a clause](links-and-graphs.md#read-other-tables-in-a-clause)). See [Ids, links and graph edges](links-and-graphs.md#read-other-tables-in-a-clause).

## Group rows

Call `group_by(key)`, then `aggregate(f)`. The key function gives a value or a record of values. The per-group function `f : k, List(row) -> out` gets the key and the rows of the group, and builds one result row.

```roc
# Fragment: uses `Visit` and `visits` from examples/main.roc.
Ledger : { vet : Str, visits : U64, revenue : Dec, avg_fee : F64 }

ledger_line : Str, List(Visit) -> Ledger
ledger_line = |vet, rows| { vet, visits: rows.len(), revenue: rows.map(|v| v.fee).sum(), avg_fee: Surreal.Math.mean_dec(rows.map(|v| v.fee)) }

Surreal.from(visits).group_by(|v| v.vet.get().name).aggregate(ledger_line).order_by(|r| r.revenue, Desc).limit(2).ready()
```

From `examples/main.roc`, `ledger_line`. The statement:

```surql
SELECT math::mean(<float>fee) AS avg_fee, math::sum(fee) AS revenue, vet.name AS vet, count() AS visits FROM visit GROUP BY vet ORDER BY revenue DESC LIMIT 2
```

| In the per-group function | SurrealQL |
| --- | --- |
| `rows.len()` | `count()` |
| `rows.keep_if(referred).len()` | `count(<condition>)` |
| `rows.map(\|v\| v.fee).sum()` | `math::sum(fee)` |
| `Surreal.Math.mean_dec(rows.map(\|v\| v.fee))` | `math::mean(<float>fee)` |
| `Surreal.Math.mean(rows.map(\|v\| v.rate.to_f64()))` | `math::mean(<float>rate)` |

A count is a `U64` field of the result row, as above. An `I64` field takes `rows.len().to_i64_wrap()`. A parameter record can hold a `U64`, so a clause can compare a count with a parameter (`d.readings >= p.least`). [Functions in clauses](functions.md#math) lists the other statistics.

Each part of the key must be a column of the result. SurrealDB groups by a selected column only. So return the key, or each part of it, from the per-group function. Otherwise the query is `Unsupported`: ``the group key part `vet.name` is not a column of the result ..``. A record key gives one column per part: `group_by(|v| { vet: v.vet.get().name, seen_by: v.patient.get().name })` gives `GROUP BY seen_by, vet`.

`group_by(|_| {})` is refused, because SurrealDB has no `GROUP BY` of nothing. Use `totals`.

After `aggregate` you have a `Selected`. You can call `order_by`, `limit`, `filter` and `query()` on it. A filter after a group is a subquery (see [Filter the results of a projection](#filter-the-results-of-a-projection)). A grouped query that the server keeps up to date is a view (see [Tables and schema](schema.md#views)).

## Totals of all rows

Call `totals(f)` with `f : List(row) -> out` to get one row for all the rows that the filters keep. It is `GROUP ALL`. The function uses the same aggregates as `aggregate`.

```roc
# Fragment: uses `Visit` and `visits` from examples/main.roc. `VisitTotals` and `visit_totals` are new here.
VisitTotals : { visits : U64, revenue : Dec, avg_fee : F64 }

visit_totals : List(Visit) -> VisitTotals
visit_totals = |rows| { visits: rows.len(), revenue: rows.map(|v| v.fee).sum(), avg_fee: Surreal.Math.mean_dec(rows.map(|v| v.fee)) }

Surreal.from(visits).totals(visit_totals).ready()
```

```surql
SELECT math::mean(<float>fee) AS avg_fee, math::sum(fee) AS revenue, count() AS visits FROM visit GROUP ALL
```

| Fact | Detail |
| --- | --- |
| Result type | `Totals.prepare(params)` and `Totals.ready()` give `Prepared(out)`, one row, not a list |
| No rows | One row: a count and a sum are 0, a mean, a standard deviation and a variance are `NaN`. `visit_totals([])` in Roc gives the same values |
| `Math.median` | Refused: ``in `totals`: `math::median` of no rows is `NONE` ..``. Take the median per group with `group_by` |
| Methods | `to_surql`, `prepare` and `ready` only. No `filter`, `order_by`, `limit` or `live` |

## Read a range of a time series

For a table whose `id` is a `Surreal.TimeKey(s)`, call `between(series, from, to)`. It reads the keys of one series with `from <= time < to`. SurrealDB reads a range of keys, not the whole table. [Row types and data types](data-types.md#time-series-keys) shows how to define the key.

```roc
# Fragment: uses `vitals`, `kennel_a`, `day_start`, `day_end` and `vital_line` from examples/monitoring.roc.
Surreal.from(vitals).between(kennel_a, day_start, day_end).filter(|v| v.pulse > 100).select(vital_line)
```

```surql
SELECT record::id(id)[1] AS at, record::id(id)[0] AS kennel, pulse AS pulse, temp_c AS temp_c FROM vital:[kennel:⟨a⟩, d'2026-03-01T00:00:00Z']..[kennel:⟨a⟩, d'2026-03-02T00:00:00Z'] WHERE pulse > 100
```

A query takes one `between`. A second one is ``Unsupported("a query takes one `between`")``. The series and the times are literals in the text, not parameters.

To bucket the readings by day, group by `Surreal.Time.floor(v.id.time(), Surreal.Time.days(1))`. This is `day_of` in `examples/monitoring.roc`. `.between(..).group_by(day_of).aggregate(day_line)` gives `.. FROM vital:[..]..[..] GROUP BY day, kennel`.

## Reuse query parts

Write a helper with an open row type, `{ seen : Surreal.Datetime, ..r }`. It then works on every row that has the fields it reads. A helper can call another helper. From `examples/clinic/Clinic.roc`:

```roc
# Fragment: from examples/clinic/Clinic.roc, inside `Clinic :: {}.{ .. }`.
seen_from : { seen : Surreal.Datetime, ..r }, Surreal.Datetime -> Bool
seen_from = |v, at| v.seen >= at

seen_since : { since : Surreal.Datetime, ..p }, { seen : Surreal.Datetime, ..r } -> Bool
seen_since = |p, v| Clinic.seen_from(v, p.since)
```

`filter_by(Clinic.seen_since)` on `visits` gives `WHERE $since <= seen`. The same helper also works in a constraint, a write and your own Roc code. `Clinic.bill` is a helper of a projection. It is used in `visit_line` and runs in Roc on the seed rows.

A query fragment is a function from a query to a query. It adds clauses:

```roc
# Fragment: from examples/clinic/Clinic.roc.
recent : Surreal.Query({ since : Surreal.Datetime, ..p }, { seen : Surreal.Datetime, ..r }) -> Surreal.Query({ since : Surreal.Datetime, ..p }, { seen : Surreal.Datetime, ..r })
recent = |q| q.filter_by(Clinic.seen_since)

by_id : Surreal.Selected(p, { id : Str, ..r }) -> Surreal.Selected(p, { id : Str, ..r })
by_id = |s| s.order_by(|r| r.id, Asc)
```

`Clinic.by_id(Clinic.recent(Surreal.from(visits)).select(visit_line))` gives `.. FROM visit WHERE $since <= seen ORDER BY id`.

A fragment needs its type annotation. Without it, the compiler does not know the type of `q` when it checks the lambda that `q.order_by` takes. Then the lambda is a plain function and not a `Code`. `roc check` reports `type mismatch` with the hint `One of these types takes a Code where the other takes a function`. Annotate the fragment with open rows, as above.

## Build a complex query step by step

This section builds one report from the clinic in `examples/main.roc`: for each vet, the visits since a date that need a follow-up, the revenue of those visits and how many were referred. It keeps the vets with at least `least` such visits, and gives the three with the most revenue.

Write the per-group function first. It uses a helper with a `match`, because the arm `Referred` has a payload. Its counts are `I64`, because the parameter `least` below is an `I64`:

```roc
# Fragment: uses `Visit` from examples/main.roc.
FollowUps : { vet : Str, visits : I64, revenue : Dec, referred : I64 }

referred : Visit -> Bool
referred = |v| match v.outcome {
	Referred(_) => Bool.True
	_ => Bool.False
}

follow_ups : Str, List(Visit) -> FollowUps
follow_ups = |vet, rows| { vet, visits: rows.len().to_i64_wrap(), revenue: rows.map(|v| v.fee).sum(), referred: rows.keep_if(referred).len().to_i64_wrap() }
```

Then make two fragments: a filter of groups with a parameter, and the top three by revenue:

```roc
# Fragment: uses `import surreal.Surreal`.
busy : Surreal.Selected({ least : I64, ..p }, { visits : I64, ..r }) -> Surreal.Selected({ least : I64, ..p }, { visits : I64, ..r })
busy = |s| s.query().filter_by(|p, l| l.visits >= p.least).select(|r| r)

top_three : Surreal.Selected(p, { revenue : Dec, ..r }) -> Surreal.Limited(p, { revenue : Dec, ..r })
top_three = |s| s.order_by(|r| r.revenue, Desc).limit(3)
```

Now put the steps together. Each line adds one clause:

```roc
# Fragment: uses `visits`, `at` and `Clinic` from examples/main.roc.
ledger =
	Clinic.recent(Surreal.from(visits))
		.filter(|v| v.outcome != Treated)
		.group_by(|v| v.vet.get().name)
		.aggregate(follow_ups)

report = top_three(busy(ledger))
prepared = report.prepare({ since: at("2026-01-01T00:00:00Z"), least: 1 })
```

What each step adds to the statement:

| Step | Roc | SurrealQL that it adds |
| --- | --- | --- |
| 1 | `Surreal.from(visits)` | `FROM visit` |
| 2 | `Clinic.recent(..)` (a parameter) | `WHERE $since <= seen` |
| 3 | `.filter(\|v\| v.outcome != Treated)` | `AND (outcome != 'Treated')` |
| 4 | `.group_by(..).aggregate(follow_ups)` | `count(..) AS referred, math::sum(fee) AS revenue, vet.name AS vet, count() AS visits .. GROUP BY vet` |
| 5 | `busy(..)` (a parameter after a group) | `SELECT referred, revenue, vet, visits FROM (..) WHERE $least <= visits` |
| 6 | `top_three(..)` | `ORDER BY revenue DESC LIMIT 3` |
| 7 | `prepare({ since: .., least: 1 })` | `LET $least = 1;` and `LET $since = ..;` |

The parameter record is `{ least : I64, since : Surreal.Datetime }`. Its two fields come from two fragments, and the compiler joins them. `prepared` is a `Surreal.Prepared(List(FollowUps))`. Its script, from a real run:

```surql
LET $least = 1;
LET $since = d'2026-01-01T00:00:00Z';
SELECT referred, revenue, vet, visits FROM (SELECT count((IF outcome.kind = 'Referred' THEN true ELSE false END)) AS referred, math::sum(fee) AS revenue, vet.name AS vet, count() AS visits FROM visit WHERE ($since <= seen) AND (outcome != 'Treated') GROUP BY vet) WHERE $least <= visits ORDER BY revenue DESC LIMIT 3;
```

On SurrealDB 3.3.4 with the seed rows of `examples/main.roc`, the result is two rows: `{ vet: "Sam Petrov", visits: 1, revenue: 140, referred: 0 }` and `{ vet: "Ruth Okafor", visits: 2, revenue: 120, referred: 1 }`.

To check a step, print `to_surql()` of the query at that step. A query is a value, so `ledger.to_surql()` shows steps 1 to 4.

For the totals of the same rows, end the chain with `totals` in place of the group: `Clinic.recent(Surreal.from(visits)).filter(|v| v.outcome != Treated).totals(..)` gives `.. WHERE ($since <= seen) AND (..) GROUP ALL`.

## Get the SurrealQL text

| Call | Gives | Parameters in the text |
| --- | --- | --- |
| `query.to_surql()` on a `Selected`, `Started`, `Limited` or `Totals` | `Try(Str, Error)` | `$name`, with no `LET` |
| `prepared.statement()` and then `to_script()` | `Try(Str, Error)` | One `LET $name = value;` line for each parameter and each value from around the function, then the statement with a final `;` |
| `prepared.request()` | `Try(Str, Error)` | The same text as `statement().map_ok(Statement.to_script)`. This is the text that a session sends |

`to_surql`, `statement`, `request` and `checked` give `Err(Unsupported(why))` when a clause has no SurrealQL form. Put one `expect prepared.checked().is_ok()` for each query in your module, so that `roc test` finds a refusal. [Getting started](getting-started.md#print-the-surrealql) shows a script app that prints a query.

## Limits

| Limit | What to do instead |
| --- | --- |
| A captured `Link` is refused | Capture `link.id()` |
| A clause cannot call `Surreal.datetime` | Give the datetime as a parameter or a captured value |
| `order_by` takes one column of the result | Select the value as a column, then order by it |
| `limit` and `start` come after `order_by`, in that order | Use `query()` to order or page the rows of a limit again |
| Each group key part must be a result column | Return the key from the per-group function |
| `group_by(\|_\| {})` is refused | Use `totals` |
| SurrealDB 3.3.4 has no `HAVING` | A filter after `aggregate` is a subquery. This is automatic |
| `totals` refuses `Math.median` | Take the median per group |
| A per-row list `sum` inside `aggregate` or `totals`, such as `rows.map(\|v\| Clinic.bill(v)).sum()`, is built, but SurrealDB 3.3.4 refuses the statement: "Nested aggregate functions are not supported" | Sum a field of the row in the group. Compute the per-row value in a projection without a group |
| One `between` per query, with literal times | Make one query for each range |
| `outgoing`, `incoming`, `between` and `live` are refused after a subquery | Put them before the step that makes the subquery |
| `table.rows()` in a clause reads the whole table for each row. The rows of one series of a time series are a range scan | Prefer a link or an edge when the rows are linked |
| A query fragment with no type annotation does not compile | Annotate it with open rows, as `Clinic.recent` is |
| A refusal is a value at run time, not a compile error | Test each query with `expect q.to_surql().is_ok()` |
