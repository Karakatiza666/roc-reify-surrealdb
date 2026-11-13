# Ids, links and graph edges

This page shows how rows point at other rows. You learn to use `Id` and `Link`, to read linked rows and edges with a read row, to define edge tables, to walk edges with `outgoing` and `incoming`, to write graph paths of any length, and to read other tables inside a clause.

The page uses the tables of `examples/main.roc` (`owners`, `vets`, `patients`, `visits`, `treats`) and of `examples/monitoring.roc` (`kennels`, `carers`, `cares_for`). The words clause, read row and captured value are in [Words used in these pages](getting-started.md#words-used-in-these-pages).

| You want | Use | Section |
| --- | --- | --- |
| The id of one row | `table.id(key)` | [Ids](#ids) |
| A field that points at a row | `Link(row)` | [Links](#links) |
| The key text of a link | `link.id.key()` | [The id of a link](#the-id-of-a-link) |
| Linked rows and edges in a result | A read row | [Read rows](#read-rows) |
| A graph edge between two tables | `Surreal.relation` | [Edge tables](#edge-tables) |
| The edges of a row in a clause | `outgoing`, `incoming` | [Traverse edges](#traverse-edges) |
| A path of several hops, with filters | `t.edges_from(row)`, `t.edges_to(row)` | [Graph paths](#graph-paths) |
| Rows of another table in a clause | `table.rows()` | [Read other tables in a clause](#read-other-tables-in-a-clause) |

## Ids

An `Id(row)` is a typed record id such as `vet:⟨ruth⟩`. It holds a table name and a text key. The type argument `row` is the row type of the table. No value holds it. It stops you from mixing the ids of two tables.

| Call | Type | In a clause |
| --- | --- | --- |
| `vets.id("ruth")` | `Id(Vet)` | `vet:⟨ruth⟩` |
| `ruth_id.key()` | `Str` | `record::id(id)` |
| `ruth_id.table()` | `Str` | `record::tb(id)` |

The same functions work in plain Roc code. With `ruth_id = vets.id("ruth")`, the call `ruth_id.key()` gives `"ruth"` and `ruth_id.table()` gives `"vet"`.

Compare a link with an id in a clause. From `examples/main.roc`, `ruth_id` and `vaccinated_by_ruth`:

```roc
# Fragment: uses `Patient`, `Vet` and `vets` from examples/main.roc.
ruth_id : Surreal.Id(Vet)
ruth_id = vets.id("ruth")

vaccinated_by_ruth : Patient -> Bool
vaccinated_by_ruth = |p| p.vaccines.any(|v| v.vet.id() == ruth_id)
```

`Surreal.from(patients).filter(vaccinated_by_ruth)` has this `WHERE` part:

```surql
WHERE vet:⟨ruth⟩ IN vaccines[*].vet
```

The test is `IN` and not `vaccines.any(..)`, because an index of `vaccines[*].vet` serves `IN`. The schema makes that index for the link (see [How each shape works](schema.md#how-each-shape-works)).

An id of another table does not compile. With `owner_id : Surreal.Id(Owner)`, the test `v.vet.id() == owner_id` gives:

```text
This expression is used in an unexpected way.

It has the type:

    Surreal.Id(Owner)

But you are trying to use it as:

    Surreal.Id(Vet)
```

An `Id` is also a field type and a parameter type. A field `by : Surreal.Id(Patient)` gets the same existence check as a link (see [Links and delete policies](schema.md#links-and-delete-policies)). A parameter record `{ vet : Surreal.Id(Vet) }` fills a `$vet`, and `prepare({ vet: vets.id("ruth") })` sends the record id `vet:⟨ruth⟩` as the var `$vet` (its readable form is `LET $vet = vet:⟨ruth⟩;`).

To start a query at one record, give the id to `table.at(id)`. `vets.at(vets.id("ruth"))` reads `FROM vet:⟨ruth⟩`. An id of another table is refused. See [Writing queries](queries.md#start-a-query).

An `Id` holds a text key. A table with a `TimeKey` has no `Id` of its rows by key (see [Row types and data types](data-types.md#time-series-keys)).

## Links

A `Link(row)` is a field that points at a row of another table. It holds the `Id` of that row. From `examples/main.roc`:

```roc
# Fragment: a short form of `Patient` in examples/main.roc.
Patient : { id : Str, name : Str, owner : Surreal.Link(Owner), allergies : List(Surreal.Link(Medication)) }
```

The schema of the field is `record<owner>`. See [Row types and data types](data-types.md#how-roc-types-map-to-surrealdb-types) and [Links and delete policies](schema.md#links-and-delete-policies).

| You want | Call | Gives |
| --- | --- | --- |
| A link to a row by key | `owners.link("jon")` | A `Link(Owner)` with no row |
| A link that holds its row | `Surreal.fetched(owners, jon)` | A `Link(Owner)` with the row `jon` |
| The row, in a clause | `p.owner.get()` | A traversal of the link |
| The row, in Roc code | `link.get()` | The held row, or a crash |

Use `owners.link("jon")` when you write a row. Use `Surreal.fetched` in seed data, where the program has the row and a function reads through the link. From `examples/main.roc`, `owner_link`:

```roc
# Fragment: uses `Owner` and `owners` from examples/main.roc.
owner_link : Owner -> Surreal.Link(Owner)
owner_link = |o| Surreal.fetched(owners, o)
```

In a clause, `p.owner.get().name` is the traversal `owner.name`. You add no `FETCH`. [Choosing the fields to read](selecting-fields.md#read-through-a-link) shows what each read becomes.

Outside a clause, `get()` works only on a link that holds its row. A link from `owners.link("jon")` or a link that a query read back has no row. Its `get()` crashes with `this link was not fetched`. The row lives in the database, so only a clause can read through such a link.

A link to the table of its own row needs a nominal row. `Owner := { .., referred_by ?: Surreal.Link(Owner) }` works. The alias `Boss : { .., boss ?: Surreal.Link(Boss) }` is the compiler error `recursive alias`.

## The id of a link

A stored `Link(r)` is the record `{ id : Id(r), fetched : [Fetched(r), NotFetched] }`. In a clause, `link.id` and `link.id()` are the same thing. Both give the record id that the link holds. The field `fetched` is the row that the program holds. The database has no such field.

| Written | Type of the link | SurrealQL | Meaning |
| --- | --- | --- | --- |
| `v.vet.id()` and `v.vet.id` | `Link(Vet)` | `vet` | The record id |
| `v.vet.id.key()` | `Link(Vet)` | `record::id(vet)` | The key text |
| `v.vet.get().id` | `Link(Vet)` | `record::id(vet)` | The key text. It reads no linked row |
| `v.id` | A row with `id : Str` | `record::id(id)` | The key text of the row itself |
| `v.vet.fetched` | `Link(Vet)` | Refused | |
| `p.owner.id` | `Linked(Owner)` | `record::id(owner)` | The key text of the linked row |

Each row is from a real run. Use `link.id` when you compare or capture an id: `v.vet.id == ruth_id` is `vet = vet:⟨ruth⟩`. Use `link.id()` when a call reads better in a chain.

A clause that reads `fetched` gives `Err(Unsupported(why))`:

```text
in `select_value`: `fetched` is the row that the program holds, and the database has no such field; read a field of the row with `link.get().field`, or use `link.id`
```

Write `link.get().field` or `link.id` instead.

## Read rows

A read row is a second row type for one table. It is for queries only. A stored row has a `Link(r)`. The read row has a `Surreal.Linked(r)` in its place. A field read through a `Linked` needs no `get()`. The read row also has a field for each edge table at the row.

| Type in a read row | Stands for | Is in SurrealQL |
| --- | --- | --- |
| `Surreal.Linked(r)` | The row that a `Link(r)` of the stored row points at | `site.name` |
| `Surreal.Out(e)` | The edges of table `e` that leave the row | `->cares_for` |
| `Surreal.In(e)` | The edges of table `e` that end at the row | `<-cares_for` |

An `Out` or `In` field has the name of its edge table. Its method `list()` gives the `List(e)` of edges. From `examples/monitoring.roc`, `KennelRead`:

```roc
# Fragment: uses `Site` and `CareRead` from examples/monitoring.roc.
KennelRead : { id : Str, label : Str, site : Surreal.Linked(Site), cares_for : Surreal.In(CareRead) }

kennel_reads : Surreal.Table(KennelRead)
kennel_reads = Surreal.table("kennel")
```

The table has the name of the stored table. `kennel_reads.define_read()` registers the read row. [Tables and schema](schema.md#read-rows) shows the call and the `BadSchema` messages that the check gives.

The check compares the read row with the stored row of the table of that name:

| Rule | Detail |
| --- | --- |
| Same fields | Each field is in both rows, with the same presence |
| `Linked` | Stands only where the stored row has a `Link`, to a row that agrees |
| `Out` and `In` | Name an edge table that starts (`Out`) or ends (`In`) at this table |
| Edge row | The row of an `Out` or `In` has every field of the stored edge row |
| Other types | Equal |

The `Linked` row can be an alias row, a nominal row or another read row.

### Read through a read row

The read row of `KennelRead` reads each carer of a kennel and the name of its site in one query. From `examples/monitoring.roc`, block `kennel_carers`:

```roc
# Fragment: uses `kennel_reads` from above.
Surreal.from(kennel_reads).select(|k| { label: k.label, site: k.site.name, carers: k.cares_for.list().map(|e| e.from), leads: k.cares_for.list().keep_if(|e| e.lead).len() })
```

```surql
SELECT <-cares_for<-?.{ id: record::id(id), name } AS carers, label AS label, <-cares_for[WHERE lead].len() AS leads, site.name AS site FROM kennel;
```

Each `Out` and `In` field is one edge walk. A `Linked` inside an edge row (`from : Linked(Carer)`) is read through the edge. `select(|k| k)` of a read row fetches every `Linked` at any depth. See [Read rows as a fetch plan](selecting-fields.md#read-rows-as-a-fetch-plan).

An `Out` field of a vet reads the same as `outgoing` does. With `treats : Surreal.Out(TreatRead)` in a read row of `vet`, `v.treats.list().len()` is `->treats.len()`. With `treats : Surreal.In(TreatRead)` in a read row of `patient`, `p.treats.list().len()` is `<-treats.len()`.

### Rules for a read row

| Rule | Detail |
| --- | --- |
| Never written | `Linked`, `Out` and `In` have no encoder. A write of a read row is a compile error. Write the stored row |
| No `get()` and no `id()` | A `Linked` has neither. Read its fields: `p.owner.name`, and `p.owner.id` for the key text |
| A read row is for Roc code too | The same functions run on values that you build |

To build a read row value for a test, use the constructors:

| Call | Gives |
| --- | --- |
| `Surreal.linked(row)` | A `Linked(r)` that holds `row` |
| `Surreal.out_edges(edges)` | An `Out(e)` that holds a `List(e)` |
| `Surreal.in_edges(edges)` | An `In(e)` that holds a `List(e)` |

With `lead = { id: "e1", from: Surreal.linked(ruth), .. }`, the value `Surreal.in_edges([lead]).list().keep_if(|e| e.primary).map(|e| e.from.name)` gives `["Ruth"]`.

## Edge tables

An edge table is a table whose rows are graph edges. Make it with `Surreal.relation(name, from, to)`. The two tables are the ends of the edge. The row type has the fields `from : Link(a)` and `to : Link(b)`. They are the `in` and `out` of SurrealDB. A Roc field cannot be named `in`, because it is a keyword. From `examples/main.roc`:

```roc
# Fragment: uses `Vet`, `Patient`, `vets` and `patients` from examples/main.roc.
Treats : { id : Str, from : Surreal.Link(Vet), to : Surreal.Link(Patient), since_year : I64, primary : Bool }

treats : Surreal.Table(Treats)
treats = Surreal.relation("treats", vets, patients)
```

An edge row can have more fields (`since_year`, `primary`). [Tables and schema](schema.md#tables-relations-and-views) shows the `DEFINE TABLE` line. The schema checks both ends when you write an edge (`ENFORCED`).

The ends are in the type. The call `Surreal.relation("treats", patients, vets)` for the row `Treats` does not compile (the message is shortened):

```text
This expression is used in an unexpected way.

It has the type:

    Surreal.Table({ from: Surreal.Link(Patient), id: Str, primary: Bool, to:
    Surreal.Link(Vet) })

But the annotation says it should be:

    Surreal.Table(Treats)
```

Two tables must have different row types for this check. With equal row types the checker cannot tell the ends apart (see [Tables and schema](schema.md#build-the-schema)).

### Write edges

Edges use the write calls of every table. See [Writing rows](writes.md#write-whole-rows). The statement for an edge is `RELATE` or `INSERT RELATION`. A link in the edge row can hold a row (`Surreal.fetched`) or only the key (`vets.link("ruth")`).

| Call | SurrealQL (from a real run) |
| --- | --- |
| `treats.create(e1)` | `RELATE vet:⟨ruth⟩->treats:⟨e1⟩->patient:⟨rex⟩ CONTENT { primary: true, since_year: 2022 } RETURN AFTER;` |
| `treats.create_new({ from, to, since_year, primary })` | `RELATE vet:⟨ruth⟩->treats->patient:⟨rex⟩ CONTENT { primary: false, since_year: 2024 } RETURN AFTER;` |
| `treats.insert([e1, e2])` | `INSERT RELATION INTO treats [{ in: vet:⟨ruth⟩, id: 'e1', .. out: patient:⟨rex⟩ }, ..] RETURN AFTER;` in a transaction |

`create_new` leaves the key to the server. See [Keys that the server makes](writes.md#keys-that-the-server-makes).

### Query an edge table

An edge table is a table. `Surreal.from(treats)` reads its rows. A read of `e.from.get().name` is `in.name`, and `e.to.get().name` is `out.name`. From `examples/main.roc`, `edge_line`:

```surql
SELECT record::id(id) AS id, out.name AS patient, in.name AS vet FROM treats ORDER BY id;
```

## Traverse edges

Call `outgoing(edge_table)` on a query to read the edges that leave each row. Call `incoming(edge_table)` for the edges that end at each row. The row becomes a pair `(row, List(edge))`. A clause takes the pair apart with a pattern.

| Method | On | Edge row must have | The row becomes |
| --- | --- | --- | --- |
| `outgoing(t)` | `Query(p, a)` | `from : Link(a)` | `(a, List(edge))`, from `->t` |
| `incoming(t)` | `Query(p, b)` | `to : Link(b)` | `(b, List(edge))`, from `<-t` |
| `and_outgoing(t)` | After `outgoing` or `incoming` | `from : Link(a)` | `(a, List(x), List(edge))` |
| `and_incoming(t)` | After `outgoing` or `incoming` | `to : Link(b)` | `(b, List(x), List(edge))` |

An edge table at the wrong end is a compile error. `Surreal.from(patients).outgoing(treats)` gives (shortened):

```text
The first argument being passed to this function has the wrong type.

This argument has the type:

    Surreal.Table({ from: Surreal.Link(Vet), id: Str, primary: Bool, to:
    Surreal.Link(Patient) })

But outgoing needs the first argument to be:

    Surreal.Table({ from: Surreal.Link(Patient), id: Str, primary: Bool, to:
    Surreal.Link(Patient) })
```

From `examples/main.roc`, `case_load`, and the block `case_load`:

```roc
# Fragment: uses `Vet`, `Treats` and `vets` from examples/main.roc.
CaseLoad : { name : Str, patients : U64, primary : U64 }

case_load : Vet, List(Treats) -> CaseLoad
case_load = |v, edges| { name: v.name, patients: edges.len(), primary: edges.keep_if(|e| e.primary).len() }

loads = Surreal.from(vets).outgoing(treats).select(|(v, edges)| case_load(v, edges))
```

```surql
SELECT name AS name, ->treats.len() AS patients, ->treats[WHERE primary].len() AS primary FROM vet;
```

The edge list is a normal `List`. Count it with `len()`, a `U64`. Filter and map it with the list functions. A `keep_if` or `drop_if` that reads only its edge is a `[WHERE ..]` of the path (see [Graph paths](#graph-paths)). A filter on the pair works too: `.filter(|(_v, edges)| edges.len() > 1)` gives `WHERE ->treats.len() > 1`.

`incoming` is the same from the other end. From `examples/main.roc`, `team_line`, `.incoming(treats)` on `patients`:

```surql
SELECT <-treats[WHERE primary]<-vet.name AS lead, name AS name, <-treats.len() AS team FROM patient;
```

Here `e.from.get().name` became the hop `<-vet.name`.

A second edge table adds a list to the row. `Surreal.from(vets).outgoing(treats).and_outgoing(notes)` gives the triple `(vet, treat_edges, note_edges)`. Each list has its own `->table` walk. For three or more edge tables, use a read row with an `Out` or `In` field for each table.

`outgoing` and `incoming` need the row of a table. After a subquery they are `Unsupported` (see [Writing queries](queries.md#filter-the-results-of-a-projection)). Call them before `select`.

## Graph paths

`t.edges_from(row)` and `t.edges_to(row)` are the edges of the edge table `t` at a record, inside a clause. The record is the row of the clause, or a row that a link points at. With them a clause writes a path of any length, with the list functions that it already has. The translator folds a chain of them into one SurrealQL path.

| Call | Gives | SurrealQL |
| --- | --- | --- |
| `treats.edges_from(v)` | `List(Treats)`: the edges that leave `v` | `->treats` |
| `treats.edges_to(p)` | `List(Treats)`: the edges that end at `p` | `<-treats` |
| `treats.edges_from(v.vet.get())` | The same, for a row that a link points at (here the link `vet` of a visit) | `vet->treats` |

The edge row has `from : Link(a)` for `edges_from` and `to : Link(b)` for `edges_to`. An edge table that leaves another table is a compile error: `edges_from` needs the first argument to be `Vet`, and a `Patient` is not.

```roc
# Fragment: uses `Treats`, `treats`, `vets` and `patients` from examples/main.roc.
owner_names : List(Treats) -> List(Str)
owner_names = |edges| edges.keep_if(|e| e.primary).map(|e| e.to.get().owner.get().name)

Surreal.from(vets).select(|v| { name: v.name, owners: owner_names(treats.edges_from(v)) }).ready()
```

```surql
SELECT name AS name, ->treats[WHERE primary]->patient.owner.name AS owners FROM vet;
```

The function `owner_names` is a plain function of the edges. A test calls it on a list of edges, and the clause gives it `treats.edges_from(v)`. The clause reads the edges in the database, and a row in the program holds no edges. So `edges_from` and `edges_to` are intrinsics: a call outside a clause is the compile error `exists only in reified code` (see [Functions in clauses](functions.md#mirror-functions-and-intrinsics)).

Each list function becomes a part of the path:

| Roc | SurrealQL | Rule |
| --- | --- | --- |
| `edges.keep_if(\|e\| e.primary)`, `drop_if` | `->treats[WHERE primary]`, `[WHERE !primary]` | The function reads nothing but its edge. A filter that reads the row or a parameter stays `.filter(\|$v1\| ..)` |
| `edges.map(\|e\| e.to.get())`, `e.from.get()` | `->patient`, `<-vet` | The table at that end, from `Surreal.relation`. For an `Out` or `In` field of a read row, or a table that is not a literal relation, it is `->?` and `<-?` (any table) |
| `edges.map(\|e\| e.to.get().owner.get().name)` | `->treats->patient.owner.name` | A `map` that reads a path of fields and links off its edge |
| `edges.join_map(\|e\| treats.edges_from(e.from.get()))` | `<-treats<-vet->treats` | A graph step gives a list for each element, and SurrealDB joins them, as `join_map` does. A `map` that ends in a graph step is a closure and not a path: its result is a list of lists |
| Any other `join_map` | `array::flatten(xs.map(\|$v1\| ..))` | |
| `rev`, `take_first`, `drop_first`, `sort` | `array::reverse(->treats)` | An `array::` call ends the path. The next function is a closure |

A path of two edge tables, from a patient to the other patients of its lead vets:

```roc
# Fragment: uses `Treats`, `treats` and `patients` from examples/main.roc.
co_patients : List(Treats) -> List(Str)
co_patients = |edges| edges.keep_if(|e| e.primary).join_map(|e| treats.edges_from(e.from.get())).map(|e| e.to.get().name)

Surreal.from(patients).select(|p| { name: p.name, others: co_patients(treats.edges_to(p)) }).ready()
```

```surql
SELECT <-treats[WHERE primary]<-vet->treats->patient.name AS others, name AS name FROM patient;
```

A path also works in a filter: `.filter(|v| owner_names(treats.edges_from(v)).contains("Oslo"))` gives `WHERE ->treats[WHERE primary]->patient.owner.name CONTAINS 'Oslo'`.

SurrealDB gives the edges of a record in the order of their record ids. A read row with `Out` and `In` fields holds its edges in the program, and the same rules give its paths. A live query that reads `edges_from` or `edges_to` of the row watches the edge table of the row. For another record, it watches the whole edge table (see [Live queries](live-queries.md#what-a-live-query-watches)).

## Read other tables in a clause

`table.rows()` is the rows of a table, inside a clause. It is a subquery: `(SELECT VALUE id FROM visit)`. Each element is a record id, so a field read is a traversal. Use the result as a list. A filter on it gives a correlated count or a semi join.

| Roc in a clause | Use |
| --- | --- |
| `rows.keep_if(f).len()` | A correlated count |
| `rows.any(f)` | A semi join: keep the row if some row of the other table matches |
| `!rows.any(f)` | An anti join |
| `rows.keep_if(f).map(g).sum()` | A per-row total, in a plain `select`. Not inside `aggregate` or `totals` (see [Writing queries](queries.md#limits)) |

Write the list function as a plain Roc function over `List(row)`. The function then also runs on seed data. From `examples/monitoring.roc`, `readings_of`, `has_fever`:

```roc
# Fragment: uses `Kennel`, `Vital`, `kennels`, `vitals` and `readings_of` from examples/monitoring.roc.
readings_of : List(Vital), Kennel -> List(Vital)
readings_of = |rows, k| rows.keep_if(|v| v.id.series() == kennels.id(k.id))

has_fever : List(Vital), Kennel -> Bool
has_fever = |rows, k| readings_of(rows, k).any(|v| v.fevered)

fevered = Surreal.from(kennels).filter(|k| has_fever(vitals.rows(), k)).select_value(|k| k.label)
```

```surql
SELECT VALUE label FROM kennel WHERE id.chain(|$v1| (SELECT VALUE id FROM vital:[$v1, NONE]..=[$v1, ..])).any(|$v2| $v2.fevered);
```

The block `kennels_fevered` of `examples/monitoring.roc` runs this. The key of a `vital` is a time series key. A `keep_if` that tests `v.id.series()` against a value that does not read `v` is a range scan of the keys of that series: `vital:[$v1, NONE]..=[$v1, ..]`. SurrealDB reads the keys of one kennel. `kennels.id(k.id)` of the row that the statement reads is its record id, `id`. A `filter` of the whole table (`(SELECT VALUE id FROM vital).filter(..)`) reads every row of `vital` for each kennel, so the range is much faster on a large series. Any other test goes into the `WHERE` of the subquery when it reads the row of the other table (see below).

The function of `keep_if`, `count_if`, `any` or `find_first` over `rows()` is cut at `and`. Each conjunct that reads the row of the other table goes into the `WHERE` of the subquery, so an index can serve it. A value of the clause that it reads is bound around the subquery with `chain`, because the subquery reads its own row. The other conjuncts stay a `filter`. From `examples/monitoring.roc`, `site_kennels`:

```roc
# Fragment: uses `sites` and `kennels` from examples/monitoring.roc.
Surreal.from(sites).select(|s| { name: s.name, kennels: kennels.rows().count_if(|k| k.site.id() == sites.id(s.id)) })
```

```surql
SELECT VALUE { name: name, kennels: id.chain(|$v1_0| (SELECT VALUE id FROM kennel WHERE site = $v1_0)).len() } FROM site;
```

| Function | Subquery |
| --- | --- |
| `keep_if` | `(SELECT VALUE id FROM t WHERE ..)`, with `ORDER BY id` when a test is not `==` (the order of the table) |
| `count_if`, `keep_if(..).len()` | `(SELECT VALUE id FROM t WHERE ..).len()` |
| `any` | `(SELECT VALUE id FROM t WHERE .. LIMIT 1) != []` |
| `find_first` | `(SELECT VALUE id FROM t WHERE .. ORDER BY id LIMIT 1)[0]`: the first row by key, as the Roc `find_first` over the rows in key order |

Measured on SurrealDB 4.0.1 with 30 sites and 30000 kennels and an index on `site`, the count above: 5.7 s with `.filter(..)` and 0.82 to 0.88 s with the `WHERE` in `chain`. The same subquery with `$parent.id` in place of `chain` took 0.06 to 0.07 s. The package does not use `$parent.id`: on 3.3.5 it was `NONE` in an `UPDATE .. WHERE` and in a view (not re-tested on 4.0.1). With `visits.rows()` and `x.vet.get().id == v.id` the test is `record::id(vet) = $v1_0`, which no index serves.

A `rows()` with no test of the row reads the whole table for each row of the query. Prefer a link or an edge when the rows are linked. A live query that reads `rows()` sends a notice, on a write to the other table, for each row of the result that the written row is related to, such as the kennel of a reading. With no such relation, it sends one for each row of the result (see [Live queries](live-queries.md#only-the-rows-that-a-write-reaches)).

## Limits

| Limit | What to do instead |
| --- | --- |
| `get()` on a link with no row crashes in Roc code | Use `Surreal.fetched` for seed data. Read through the link in a clause |
| An alias row cannot link to itself (`recursive alias`) | Make the row nominal: `Owner := { .. }` |
| Two tables with an equal row type are refused in one schema, because a link to the row would be ambiguous | Make one of the rows nominal (see [Tables and schema](schema.md#limits)) |
| A `Linked` has no `get()` and no `id()` | Read fields of it, or `p.owner.id` for the key text |
| A read row is never written | Write the stored row. `define_read()` checks that they agree |
| A read row of an edge must have every field of the stored edge row | Add the missing fields to the read row |
| A whole read row that holds a `Linked` of itself has no end | Select its fields (see [Shapes a projection cannot have](selecting-fields.md#shapes-a-projection-cannot-have)) |
| Each field read through a link is its own traversal | Return the whole linked row when you read many fields |
| After an `order_by`, `limit`, `start` or `aggregate`, a read row is a copy. Its linked rows hold the key as `id`, not a record id | Read the `id` before the step: `select(\|p\| { owner_key: p.owner.id })`, then `order_by` and `limit` |
| `and_outgoing` and `and_incoming` add one table each | For three or more tables, use a read row with an `Out` or `In` field for each |
| `outgoing` and `incoming` are refused after a subquery | Call them before the step that makes the subquery |
| The order of an edge list differs between Roc and SurrealDB | Compare as multisets, or sort in the clause |
| `rows()` reads the whole table for each row. The rows of one series of a time series are a range scan | Prefer a link or an edge. A filter over a large table is better as its own query |
| `edges_from` and `edges_to` have no Roc body: a row in the program holds no edges | Write the path as a function of a `List(Treats)`, and give the clause `treats.edges_from(v)` (see [Graph paths](#graph-paths)) |
| A path ends at an `array::` call (`rev`, `take_first`, `drop_first`, `sort`) | The next function is a closure. Put these calls last |
| A live query does not watch the `Out` or `In` edges of a `Linked` row. A live query of `edges_from` or `edges_to` of another record watches the whole edge table | Watch the edge table with its own query (see [Live queries](live-queries.md#limits)) |
