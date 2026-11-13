# Tables and schema

This page shows how to define tables and how each clause of `define()` becomes a `DEFINE` statement. You learn to add constraints, unique keys, indexes, computed fields, link policies, views and changefeeds, and to move a database from one schema to the next with a migration.

The row type gives the `DEFINE FIELD` lines (see [Row types and data types](data-types.md)). The clauses on this page add the rest. Terms such as clause and read row are in [Words used in these pages](getting-started.md#words-used-in-these-pages).

## Tables, relations and views

Three functions of `Surreal` make a table:

| Make | Call | Type | Statement |
| --- | --- | --- | --- |
| Table | `Surreal.table(name)` | `Table(row)` | `DEFINE TABLE OVERWRITE name SCHEMAFULL` |
| Edge table | `Surreal.relation(name, from, to)` | `Table({ from : Link(a), to : Link(b), ..r })` | `.. TYPE RELATION IN a OUT b ENFORCED SCHEMAFULL` |
| View | `Surreal.view(name)` | `Table(row)` | `.. TYPE NORMAL AS SELECT ..` (see [Views](#views)) |

A table holds a name and a kind. It holds no row. The row type comes from the type annotation of the binding, so always write the annotation.

```roc
# Fragment: uses the rows `Vet`, `Patient` and `Treats` and the table `patients` of examples/main.roc.
vets : Surreal.Table(Vet)
vets = Surreal.table("vet")

treats : Surreal.Table(Treats)
treats = Surreal.relation("treats", vets, patients)
```

From `examples/main.roc`, `vets` and `treats`. An edge row has the fields `from` and `to`. They are the `in` and `out` of SurrealDB. A Roc field cannot be named `in`, because it is a keyword. The schema writes `in` and `out`:

```surql
DEFINE TABLE OVERWRITE treats TYPE RELATION IN vet OUT patient ENFORCED SCHEMAFULL;
```

The ends are typed. Take a row `Back` with `from : Link(Patient)` and `to : Link(Vet)`. With the call above, the code does not compile (the message is shortened):

```text
This expression is used in an unexpected way.
    wrong = Surreal.relation("treats", vets, patients)
It has the type:
    Surreal.Table({ from: Surreal.Link(Vet), id: Str, to: Surreal.Link(Patient) })
But the annotation says it should be:
    Surreal.Table(Back)
```

Every table is `SCHEMAFULL`. A row can hold only the fields of its type. See [Ids, links and graph edges](links-and-graphs.md#edge-tables) to write and read edges.

## Build the schema

Call `define()` on a table to get a `Def(row)`. Each clause is a method that takes a Roc function and gives a new `Def(row)`. Call `done()` at the end to get a `Surreal.Defined`. `Surreal.schema` takes the list of every `Defined` and gives the script:

```
t.define() --> clause --> clause --> done() --> Defined
Surreal.schema(list of Defined) --> Try(Str, Error)
```

| Entry in the list | Made by | Page |
| --- | --- | --- |
| Table | `t.define()....done()` | This page |
| Read row | `t.define_read()` | [Read rows](#read-rows) |
| View | `view.define_as(..)....done()` | [Views](#views) |
| Database function | `Surreal.function(\|_\| f)` | [Functions in clauses](functions.md#database-functions) |
| Analyzer | `analyzer.define()` | [Full-text and vector search](search.md#analyzers) |
| Access method | `access.define(..).done()` | [Record users and permissions](access.md#define-an-access-method) |

`Surreal.schema` writes the statements in this order, so that no statement names a function or a table that comes later:

```
functions, analyzers, tables, views, fields, indexes, check events, delete events, access methods
```

Tables and fields keep the order of the list. The fields of one table are in name order. Here are some lines of the script for a list that starts with `visit_def` and `patient_def`. The lines of other statements are left out:

```surql
DEFINE TABLE OVERWRITE visit SCHEMAFULL;
DEFINE TABLE OVERWRITE patient SCHEMAFULL;
DEFINE FIELD OVERWRITE fee ON visit TYPE decimal;
DEFINE FIELD OVERWRITE seen ON visit TYPE datetime;
DEFINE FIELD OVERWRITE name ON patient TYPE string;
DEFINE INDEX OVERWRITE treats_in_out_unique ON treats FIELDS in, out UNIQUE;
DEFINE EVENT OVERWRITE patient_vaccines_vet_on_delete ON vet WHEN $event = 'DELETE' THEN { IF (SELECT VALUE id FROM patient WHERE $before.id IN vaccines[*].vet LIMIT 1) != [] { THROW <string>$before.id + ' is referenced by patient.vaccines[*].vet' } };
```

Each statement has `OVERWRITE`, so you can load the script again on a database that has the tables. `OVERWRITE` does not remove what the new schema leaves out, and on SurrealDB 4.0.1 it fills each view again. To set up and update a database, use [migrations](#migrations).

`done()` never fails. A clause that has no SurrealQL form, or a wrong definition, is kept. `Surreal.schema` gives the first one as `Err(Unsupported(..))` or `Err(BadSchema(..))`. See [Errors](errors.md#build-time-errors).

`Surreal.schema` also checks the list as a whole:

| Problem | Result |
| --- | --- |
| A link to a table that is not in the list | ``BadSchema("no table holds the row type `..`; list its table in the schema")`` |
| Two tables with one name | ``BadSchema("two tables are named `patient`")`` |
| Two tables with an equal row type | ``BadSchema("tables `a` and `b` have the same row type, so a link to it is ambiguous; make one of the rows a nominal type (`:=`)")`` |
| A clause on a path that has no field line, such as `id` | ``BadSchema("`owner.id` has no field definition to put this on; the record key and an edge's ends are SurrealDB's own")`` |
| Two generated statements with one name | ``BadSchema("two generated statements are named `pet_name_index`; rename a field or a check")`` |

## Constraints

A constraint is a Roc function that returns `Bool`. Write it once. The database enforces it on each write, and your program calls it on records. Use it in an `expect` too.

| Clause | Takes | Result |
| --- | --- | --- |
| `check(name, f)` | `row -> Bool` | The `ASSERT` of a field that `f` reads. If `f` reads several fields, the `ASSERT` of one of them, or an event (see the table below) |
| `assert(path, f)` | `row -> v`, `v -> Bool` | The `ASSERT` of the field at `path` |
| `assert_each(path, f)` | `row -> List(v)`, `v -> Bool` | `$value.all(..)` over the list. For a list of records that reads one field, the `ASSERT` of `list[*].field` |

```roc
# Fragment: uses `owners`, `visits` and `valid_email` of examples/main.roc and `Clinic.fee_covers_items` of examples/clinic/Clinic.roc.
owner_def : Surreal.Defined
owner_def =
	owners.define()
		.assert(|o| o.email, valid_email)
		.assert_each(|o| o.tags, |t| t != "")
		.check("named", |o| o.name != "")
		.done()

visit_def : Surreal.Defined
visit_def = visits.define().check("items need a fee", Clinic.fee_covers_items).done()
```

These clauses are in `owner_def` and `visit_def` in `examples/main.roc`. Each of the first three clauses reads one field, so each is a field `ASSERT`:

```surql
DEFINE FIELD OVERWRITE email ON owner TYPE string ASSERT string::contains($value, '@') AND (!string::starts_with($value, '@'));
DEFINE FIELD OVERWRITE name ON owner TYPE string ASSERT $value != '';
DEFINE FIELD OVERWRITE tags ON owner TYPE array<string> ASSERT $value.all(|$item| $item != '');
```

`fee_covers_items` reads `items` and `fee`. A check on several fields is the `ASSERT` of the first field that can hold it. In an `ASSERT`, `$value` is the new value of the field, and `$this` is the row with the new values of all fields. So the other fields that the check reads are `$this.<field>`:

```surql
DEFINE FIELD OVERWRITE fee ON visit TYPE decimal ASSERT ($this.items.len() = 0) OR ($value > 0.0dec);
```

The `check` gives the `ASSERT` to the first field, in name order, that the check reads and that is:

| Condition of the field | Why |
| --- | --- |
| Required, not optional | SurrealDB runs the `ASSERT` of a required field on each write |
| Not `readonly` | SurrealDB does not run the `ASSERT` of a read-only field that does not change |
| Has no field permission | An event has no field permission, so the `ASSERT` would not run for every user |

A check that has no such field stays an event over `$after`. This is the case when the check reads only the key `id`, or an edge end (`from`, `to`), or when all fields that it reads are optional, read-only or have a permission. The event name is `<table>_check_<name>`. A name with spaces gets `_` in the event name:

```surql
DEFINE EVENT OVERWRITE note_check_id_is_long ON note WHEN $event IN ['CREATE', 'UPDATE'] THEN { IF !(bytes::len(<bytes>record::id($after.id)) < $after.a) { THROW 'note: id is long' } };
```

| The check reads | Result | Error of a refused write |
| --- | --- | --- |
| One field | The `ASSERT` of the field | `Assert` |
| Several fields, one of them can hold it | The `ASSERT` of the first such field | `Assert` |
| Several fields, none can hold it. Or `id`, `in` or `out` | A `DEFINE EVENT` | `Check` |
| No field | `BadSchema` | None |

For `notes.define().check("a below b", |n| n.a < n.b).readonly(|n| n.a)` the field `a` is read-only, so the `ASSERT` moves to `b`: `DEFINE FIELD OVERWRITE b ON note TYPE int ASSERT $this.a < $value;`.

A read through `.?` gives a `Try` to the function. Match on it, as in a filter:

```roc
# Fragment: uses `owners` and the optional field `zip` of `Address` from examples/main.roc.
zip_def : Surreal.Defined
zip_def =
	owners.define()
		.assert(|o| o.address.?zip, |z| match z { Ok(s) => s.starts_with("0"), Err(_) => Bool.True })
		.done()
```

```surql
DEFINE FIELD OVERWRITE address.zip ON owner TYPE option<string> ASSERT (IF $value IS NONE THEN true ELSE string::starts_with($value, '0') END);
```

A check that reads no field is refused: ``BadSchema("the check `always` reads no field, so it is always or never true")``.

A failed write gives a `ServerError` tag that depends on the constraint (see [Errors](errors.md#server-errors)):

| Constraint | Tag |
| --- | --- |
| `assert`, `assert_each`, a `check` on one field, a `check` on several fields that one field can hold, an integer range, a link that must exist | `Assert` |
| A `check` on several fields that is an event (it reads `id`, `in` or `out`, or no field can hold it) | `Check` |
| `unique` | `Unique`, if the session knows the schema (see [Sessions](sessions.md#unique-errors-need-the-schema)). Otherwise `Index` |
| A delete that a link policy rejects | `Referenced` |

## Unique keys and indexes

`unique` and `index` take a function that reads a path. A record of paths gives one index over all of them. The index name is `<table>_<paths>_unique` or `<table>_<paths>_index`.

| You write | Statement |
| --- | --- |
| `.unique(\|o\| o.email)` | `DEFINE INDEX OVERWRITE owner_email_unique ON owner FIELDS email UNIQUE;` |
| `.unique(\|o\| { city: o.address.city, line: o.address.line })` | `DEFINE INDEX OVERWRITE owner_address_city_address_line_unique ON owner FIELDS address.city, address.line UNIQUE;` |
| `.index(\|o\| o.address.city)` | `DEFINE INDEX OVERWRITE owner_address_city_index ON owner FIELDS address.city;` |
| `.unique(\|e\| { from: e.from, to: e.to })` on `treats` | `DEFINE INDEX OVERWRITE treats_in_out_unique ON treats FIELDS in, out UNIQUE;` |

These clauses are in `owner_def` and `treats_def` in `examples/main.roc`. The last row keeps one edge between two rows. The ends `from` and `to` are written as `in` and `out`.

An optional field at the end of a path is allowed: `.unique(|p| p.?zip)`. A path that goes through an optional record or a union arm is a branch. It is refused: ``Unsupported("a field path reads fields only; this one calls `a branch`")``. You can index the whole optional record, `.index(|p| p.?chip)`, or a whole union field.

## Computed, read-only and timestamp fields

| Clause | Statement part | What it does |
| --- | --- | --- |
| `computed(path, f)` | `VALUE <expression>` | The server computes the field from the row on each write. The expression may call `Rand` (see [Functions in clauses](functions.md#rand-and-where-it-is-allowed)) |
| `readonly(path)` | `READONLY` | The server refuses an update that changes the field |
| `created_now(path)` | `VALUE time::now() READONLY` | The field holds the time of the first write. Later writes keep it. The field type is `Surreal.Datetime` |
| `comment(path, text)` | `COMMENT '<text>'` | Puts a comment on the field |

`default` and `default_by` also work here (see [Default values](data-types.md#default-values)).

```roc
# Fragment: uses `medications`, `label_of` and `Medication` of examples/main.roc. `Medication` here has one more field, `added : Surreal.Datetime`.
medication_def : Surreal.Defined
medication_def =
	medications.define()
		.computed(|m| m.label, |m| label_of(m.name, m.form))
		.created_now(|m| m.added)
		.comment(|m| m.name, "trade name")
		.done()
```

```surql
DEFINE FIELD OVERWRITE added ON medication TYPE datetime VALUE time::now() READONLY;
DEFINE FIELD OVERWRITE label ON medication TYPE string VALUE $this.name + ' (' + $this.form + ')';
DEFINE FIELD OVERWRITE name ON medication TYPE string COMMENT 'trade name';
```

`label_of` is an ordinary function. Your program calls it on a record, and the database runs the same text. A `computed` clause can also call a database function (see [Database functions](functions.md#database-functions)), as `examples/monitoring.roc` does for `fevered`.

A `readonly` field looks like this: `vets.define().readonly(|v| v.license)` gives `DEFINE FIELD OVERWRITE license ON vet TYPE string READONLY;`.

## Links and delete policies

Every `Link` and `Id` in a row, at any depth, must point at a row that exists when you write. The schema adds the existence check. Each link also has a policy for the delete of the row it points at.

| Policy | A delete of the target does this to the row that holds the link |
| --- | --- |
| `Reject` | The delete fails. This is the default |
| `Cascade` | The row that holds the link is deleted |
| `Unset` | The link is removed: the field becomes `NONE`, or the element leaves the list |
| `Ignore` | Nothing. The row keeps a link to a row that is gone |

Two clauses set a policy:

| Clause | Scope |
| --- | --- |
| `on_delete(table, policy)` | Every link from this table to rows of `table` |
| `on_delete_at(path, policy)` | The one link at `path`. It wins over `on_delete`. Use `.?` for an optional link: `\|p\| p.?buddy` |

```roc
# Fragment: uses `patients`, `owners` of examples/main.roc.
patient_def : Surreal.Defined
patient_def =
	patients.define()
		.on_delete(owners, Cascade)
		.on_delete_at(|p| p.allergies, Unset)
		.done()
```

These clauses are in `patient_def` in `examples/main.roc`. The result for the two links:

```surql
DEFINE FIELD OVERWRITE allergies ON patient TYPE array<record<medication>> REFERENCE ON DELETE UNSET ASSERT $value.all(|$e1| record::exists($e1));
DEFINE FIELD OVERWRITE owner ON patient TYPE record<owner> REFERENCE ON DELETE CASCADE ASSERT record::exists($value);
```

A policy for a table that no link points at is refused: ``BadSchema("no link in `patient` points at table `vet`")``. A path that is not a link gives ``BadSchema("`order.total` is not a link")``.

### How each shape works

The package picks the mechanism from the place of the link in the row:

| Place of the link | Example | Mechanism | `Unset` |
| --- | --- | --- | --- |
| Root field, required | `owner` | `REFERENCE ON DELETE` on the field | Refused: the field is required |
| Root field, optional | `referred_by ?:` | `REFERENCE ON DELETE` | The field becomes `NONE` |
| Root list | `allergies` | `REFERENCE ON DELETE` | The element leaves the list |
| In a record | `chip.implanted_by` | Event on the target table, and an index | The field must be optional. It becomes `NONE` |
| In a list of records | `vaccines[*].vet` | Event on the target table, and an index | The element leaves the list |
| In a union arm | `outcome`, arm `Referred` | Event on the target table | Refused: an arm field cannot be unset |

SurrealDB accepts `REFERENCE` on a root field only. For the other places the package writes an event on the target table, named `<table>_<path>_on_delete`, and an index named `<table>_<path>_link`. With `Ignore` the package writes no event and no index. Real output for a link in an optional record, when the link field is optional (`implanted_by ?:`) and the policy is `Unset`:

```surql
DEFINE EVENT OVERWRITE patient_chip_implanted_by_on_delete ON vet WHEN $event = 'DELETE' THEN { UPDATE patient SET chip.implanted_by = NONE WHERE chip.implanted_by = $before.id };
```

A link in a list of records, such as `vaccines[*].vet`, is found with `IN` and not with `any`, so that the index `<table>_<path>_link` serves the event. A delete of a vet then reads the index and not the whole table of patients:

```surql
DEFINE EVENT OVERWRITE patient_vaccines_vet_on_delete ON vet WHEN $event = 'DELETE' THEN { IF (SELECT VALUE id FROM patient WHERE $before.id IN vaccines[*].vet LIMIT 1) != [] { THROW <string>$before.id + ' is referenced by patient.vaccines[*].vet' } };
```

Both mechanisms give a `Referenced` error for `Reject`. The text differs: the field says `Cannot delete .. as it is referenced by ..`, and the event throws `.. is referenced by visit.items[*].medication`.

An `Unset` that cannot work is a `BadSchema` that names the link: ``BadSchema("`patient.vet` is required, so a delete cannot unset it; make it optional (`?:`) or use Reject, Cascade or Ignore")``.

### Order of the rows

The server checks each link when it writes a row. Write the target rows first. In `examples/main.roc` the seeds go in this order: vets, owners, medications, patients, visits, edges.

Links that are all required and form a loop can never be filled, so `Surreal.schema` refuses them:

```text
BadSchema("required links form a cycle (boss.boss -> boss), so no row of it can be written first; make one of them optional (`?:`)")
```

Make one link optional (`?:`).

## Views

A view is a table that SurrealDB fills from a grouped query. Each write to the source table updates it. Make it with `Surreal.view`, and give its query to `define_as`:

```roc
# Fragment: uses `Vital`, `vitals`, `Kennel` and `fever_fn` of examples/monitoring.roc.
DayKey : { kennel : Surreal.Id(Kennel), day : Surreal.Datetime }

day_of : Vital -> DayKey
day_of = |v| { kennel: v.id.series(), day: Surreal.Time.floor(v.id.time(), Surreal.Time.days(1)) }

Daily : { kennel : Surreal.Id(Kennel), day : Surreal.Datetime, readings : I64, fevers : I64 }

day_line : DayKey, List(Vital) -> Daily
day_line = |k, rows| { kennel: k.kennel, day: k.day, readings: rows.len().to_i64_wrap(), fevers: rows.keep_if(|v| fever_fn.call2(v.temp_c, v.pulse)).len().to_i64_wrap() }

daily : Surreal.Table(Daily)
daily = Surreal.view("vital_daily")

daily_def : Surreal.Defined
daily_def = daily.define_as(Surreal.from(vitals).group_by(day_of), day_line).done()
```

From `examples/monitoring.roc`. The first function of `group_by` gives the key. The second function of `define_as` gives the row of the view from the key and the rows of the group. The row type of the view is its result. The statement:

```surql
DEFINE TABLE OVERWRITE vital_daily TYPE NORMAL AS SELECT time::floor(record::id(id)[1], 1d) AS day, count(fn::fever(temp_c, pulse)) AS fevers, record::id(id)[0] AS kennel, count() AS readings FROM vital GROUP BY day, kennel;
```

Read the view as any table: `Surreal.from(daily)`. To get notices when it changes, watch it (see [Live queries](live-queries.md)). See [Writing queries](queries.md#group-rows) for `group_by` and the aggregates.

| Rule | What happens otherwise |
| --- | --- |
| The query is grouped. `define_as` takes the result of `group_by` | A plain projection is a type error |
| A filter before `group_by` is allowed. It becomes `WHERE` | |
| The query reads a whole table | A range, a key or a subquery gives ``Unsupported("the view `x` reads a range; a view reads a whole table")`` |
| A view is read-only. It takes no rule | ``BadSchema("`reading_daily` is a view, and a view is read-only, so it takes no rule")`` |
| A write to a view is refused | ``Unsupported("`patient_names` is a view, and a view is read-only")`` |
| `define()` on a view is refused | ``Unsupported("`reading_stats` is a view: give its query with `define_as`")`` |
| A sum of an integer column is a float in a view | ``Unsupported("in `aggregate`: `math::sum` of an integer column is a float in a view; convert it with `to_f64()`")`` |
| A median is not kept in a view | ``Unsupported("in `aggregate`: SurrealDB does not keep `math::median` in a view; compute it in a query")`` |

A count, a `Math.mean` and a sum of `Dec` or float values work in a view.

## Changefeeds

A changefeed keeps the history of a table. Call `changefeed` with a `Duration`. The statement has the duration as a literal in the largest units that fit (`1w`, `1d`, `1h30m`):

```roc
# Fragment: uses `Vital` and `vitals` of examples/monitoring.roc.
vital_def : Surreal.Defined
vital_def = vitals.define().changefeed(Surreal.Time.days(7)).done()
```

```surql
DEFINE TABLE OVERWRITE vital SCHEMAFULL CHANGEFEED 1w;
```

A table has at most one changefeed: ``BadSchema("`reading` has two changefeeds")``. The package has no typed call to read the history. Send `SHOW CHANGES FOR TABLE` as raw text (see [Escape hatches](advanced.md#raw-surrealql)).

## Read rows

A read row is a row type that reads linked rows and edges in one query. It writes no statement. Register it with `define_read()` so that `Surreal.schema` checks it against the stored row of the table with the same name:

```roc
# Fragment: uses `Site`, `Kennel` and `CareRead` of examples/monitoring.roc.
KennelRead : { id : Str, label : Str, site : Surreal.Linked(Site), cares_for : Surreal.In(CareRead) }

kennel_reads : Surreal.Table(KennelRead)
kennel_reads = Surreal.table("kennel")

kennel_read_def : Surreal.Defined
kennel_read_def = kennel_reads.define_read()
```

From `examples/monitoring.roc`. Put the stored table in the same list. A read row that does not agree with its stored row is a `BadSchema` that names the field:

```text
BadSchema("the read row of `patient` does not agree with its stored row at `name`: a `Linked` stands where the stored row has no `Link`")
BadSchema("the read row of `patient` has no stored table of that name; list the table in the schema")
```

See [Ids, links and graph edges](links-and-graphs.md#read-rows) for the types `Linked`, `Out` and `In`, and [Choosing the fields to read](selecting-fields.md#read-rows-as-a-fetch-plan) for how queries use them.

## Indexes for search

A full-text index and a vector index are clauses of `define()` too: `Def.text_index` and `Def.vector_index`. They take a value that `t.text_index(..)` or `t.vector_index(..)` makes. The index names are `<table>_<path>_fulltext` and `<table>_<path>_hnsw`. A full-text index needs its analyzer in the list. See [Full-text and vector search](search.md).

## Permissions

`permit`, `permit_full`, `permit_field` and `deny_field` set the table and field permissions for record users. They are clauses of `define()`. See [Record users and permissions](access.md#table-permissions).

## Migrations

The Roc schema is the source of truth. A migration is a `.surql` file that `Surreal.plan` writes, that you review and commit, and that the app applies one time with `session.migrate!`. The first setup of a database and each update take the same path.

Do not run `Surreal.schema` at each start of the app. Run `session.migrate!(migrations)`. On SurrealDB 4.0.1, a `DEFINE TABLE OVERWRITE` of a view that did not change fills the view again: 0.16 to 0.26 s for a view over 20000 rows. An index that did not change is not built again on 4.0.1 (on SurrealDB 3.x it was: 1 to 1.7 s for each index on 200k rows). A migration file has only the statements that changed, and it runs one time.

| Part | What it is | Where it is |
| --- | --- | --- |
| Schema | `List(Surreal.Defined)`, as for `Surreal.schema` | A module of the app |
| Server | SurrealDB 4 with the database at compatibility level 4. Each file header says `target V4` | The header of each file |
| Snapshot | The text of `Surreal.schema` that the migrations make | `db/schema.surql`, committed |
| Migration file | A header, warnings as comments, and sections. Each section is one transaction | `db/migrations/0002_bin_size.surql`, committed, embedded with `import` |
| History | One record for each file, with its checksum and the count of its sections that ran | The table `_reify_migration` in the database |

### Flows

| Stage | What you do |
| --- | --- |
| Dev | Change the schema. Run `roc examples/migrate.roc -- plan 0002_bin_size` (copy `examples/migrate.roc` into your app). It writes the file and the new snapshot. Read the warnings. Write each value that a `-- reify: edit` line asks for, and remove the line. Add the `import` line and the file to `migrations` |
| CI | `roc test` runs `expect Surreal.check(snapshot, schema).is_ok()`: it fails when the schema has a change that no file has. Then apply all files to an empty database |
| Deploy, and the first setup | The app runs `session.migrate!(migrations)` at start. A fresh database runs every file; a database with history runs only the new ones |

```roc
# Fragment: from examples/migrate.roc. `schema` is the list of `Surreal.Defined`.
import "db/schema.surql" as snapshot : Str
import "db/migrations/0001_init.surql" as m0001_init : Str
import "db/migrations/0002_bin_size.surql" as m0002_bin_size : Str

migrations : Try(List(Surreal.Migration), Surreal.Error)
migrations = [("0001_init", m0001_init), ("0002_bin_size", m0002_bin_size)].map_try(|(name, text)| Surreal.migration(name, text))

expect Surreal.check(snapshot, schema).is_ok()
expect migrations.is_ok()

# At start:
done = session.migrate!(migrations?)?
```

`done.applied.ran` names the files that ran.

### A migration file

`Surreal.plan(snapshot, schema).to_file("0002_bin_size", KeepData)`, when `bin` gets a field `size` with the default 1 and an index on it (`examples/db/migrations/0002_bin_size.surql`):

```surql
-- reify-surrealdb migration 0002_bin_size target V4 from c2cc81affaaa4cba5d88661913e404a736ddc7f2de38392a34861a60e857f4e7
DEFINE FIELD OVERWRITE size ON bin TYPE int DEFAULT 1 MIGRATE EXISTING ROWS AS m_c2cc81af_bin_size USING 1;
-- reify: commit
DEFINE INDEX OVERWRITE bin_size_index ON bin FIELDS size;
```

| Line | Meaning |
| --- | --- |
| `-- reify-surrealdb migration <name> target V4 from <hash> [replaces <name> ..]` | The header. `name` must be the name that the app gives. `target V4` is the only target; the word stays for a later target. A file with `target V3` (0.0.3 and before) is `Legacy`, and a header with no `target V4` is a `Text` error. `from` is the SHA-256 of the snapshot that the plan started from. `replaces` is in a squashed file only |
| `-- warning: ..` | A change to read before the file runs |
| `-- reify: commit` | The end of a section. Each section is one transaction |
| `-- reify: edit ..` | The plan cannot pick a value. Write it in place of the placeholder on the next line, and remove this line. `migrate!` and `Surreal.migration` refuse a file that has one |

A file has no `BEGIN`, `COMMIT` or `CANCEL`: the runner makes each section a transaction. You can add your own statements, for example to copy data. Keep a write to a table and a `DEFINE INDEX` on that table in different sections: SurrealDB 4 refuses them in one transaction, and `Surreal.migration` refuses that file.

### What a plan writes

| Change | Statement | Section |
| --- | --- | --- |
| A definition that did not change | Nothing | |
| A new or changed table, field, event, function, analyzer, access method | `DEFINE .. OVERWRITE` | 1 |
| An index, event, function, analyzer, access method or view that the schema removed | `REMOVE .. IF EXISTS` | 1 |
| A new field that is not optional, on a table that was there | `DEFINE FIELD .. MIGRATE EXISTING ROWS AS .. USING <default>` | 1 |
| A field type that does not take every old value (`string` to `int`) | `MIGRATE EXISTING ROWS .. USING <int> $value FALLBACK <default>` | 1 |
| A wider field type (`int` to `option<int>`, `int` to `int \| string`) | `DEFINE FIELD OVERWRITE` | 1 |
| A field that the schema removed, with `DropData` | `REMOVE FIELD` (level 4 clears the old values) | 1 |
| A table that the schema removed, with `DropData` | `REMOVE TABLE` | 1 |
| A new or changed index on a table that section 1 writes to or migrates | `DEFINE INDEX OVERWRITE` | 2 |
| A view over a table that section 1 migrates | `REMOVE TABLE` of the view, then its `DEFINE TABLE` in section 2 | 1 and 2 |
| A changed analyzer | `DEFINE ANALYZER OVERWRITE`, then `REBUILD INDEX` of each full-text index that uses it | 1 and 2 |

A value that the plan cannot pick gets a `-- reify: edit` line: a new required field with no default, a type with no cast (a record, a list), a value that does not cast with no default, and a `REFERENCE` field (SurrealDB 4 refuses `MIGRATE EXISTING ROWS` on it).

`mode` is `KeepData` or `DropData`. With `KeepData`, a table or a field that the schema removed stays in the database and in the snapshot, so a later file can drop it. Drop data one release after the code stops using it.

### The calls

| Call | Gives |
| --- | --- |
| `Surreal.plan(snapshot, schema)` | `Try(Plan, Error)`: the diff from the snapshot (`""` for an empty database) to the schema |
| `plan.statements(mode)` | `List(List(Str))`: the statements of each section, with no `;` |
| `plan.to_file(name, mode)` | `Str`: the migration file |
| `plan.snapshot(mode)` | `Str`: the snapshot after the file. Write it to `db/schema.surql` |
| `plan.warnings()` | `List(Surreal.Warning)`: `TypeChanged`, `MaybeRenamed`, `UniqueAdded`, `AssertAdded`, `NoDefault`, `Rewritten`, `ViewRebuilt`, `Dropped` |
| `plan.dropped()` | `List(Str)`: the tables, and the fields as `table.path`, that the schema removed |
| `plan.is_empty(mode)` | `Bool`: the plan has no statement |
| `plan.replacing(names)` | `Plan`: a squashed file that replaces the files `names` |
| `plan.prepare(mode)` | `Try(List(Prepared({})), Error)`: each section as a transaction, for `session.run!` in a test. A plan that needs an edit is an error |
| `Surreal.migration(name, text)` | `Try(Migration, Error)`: a file, read. `name()`, `sections()`, `checksum()`, `replaces()` |
| `Surreal.check(snapshot, schema)` | `Ok({ pending_drops })` when the snapshot is the schema. Else `Migration({ problem: Unplanned(statements) })` |
| `session.migrate!(migrations)` | `Try({ session, applied }, Error)`. `applied` is `{ ran, adopted, ahead }` |

### What `migrate!` does

| Rule | Detail |
| --- | --- |
| First request | `DEFINE .. IF NOT EXISTS` of `_reify_migration`, the compatibility level from `INFO FOR DB`, and the history. When every file ran, this is the only request |
| Order | The order of the list. A file that did not run, before one that ran, is `OutOfOrder` |
| Checksum | A file that ran and whose text changed is `Changed`. Fix a mistake with a new file |
| Sections | Section 1 creates the record of the file and runs in the same transaction; each later section moves the record on. After a crash between sections, the next run goes on at the next section |
| Two runners at once | The record of a file is created once. The second runner fails on it, reads the history again and goes on. No section runs two times (tested on SurrealDB 4.0.1) |
| Level | A database below compatibility level 4 is `Migration({ name: "", problem: Level({ found }) })`, and nothing runs. A SurrealDB 3 datastore that was upgraded to SurrealDB 4 stays at level 3 until `ALTER DATABASE COMPATIBILITY 4`. A server with no level (SurrealDB 3) is a `Wire` error |
| History table | `_reify_migration` keeps the field `target`. A new database defines it as `'V4'`; a database of 0.0.x keeps `'V3' \| 'V4'`, which takes `'V4'` |
| Squash | A file with `replaces` is recorded and does not run when the database ran all the files it replaces. A fresh database runs it. A database that ran only some of them is an error |
| `ahead` | Records of the history that no file of the list has: a newer version of the app ran them. It is not an error |

There is no down migration. To undo a change, write a new file.

### Upgrade from 0.0.x

This version runs on SurrealDB 4 at compatibility level 4 only. `Surreal.MigrationTarget`, the `V3` plans and `Surreal.raise_compatibility` are removed, and `Surreal.plan` takes no target.

1. If any file has `target V3`, do this with 0.0.3 first: raise the database to level 4 (`ALTER DATABASE COMPATIBILITY 4`, the body of `Surreal.raise_compatibility`), set `db_target = V4`, then squash: `roc examples/migrate.roc -- squash 0005_base` writes one `V4` file that `replaces` the older files. Put it in place of the old files in `migrations`, and run `migrate!`: a database that ran all the old files records it and does not run it. This version refuses a `target V3` file with `Legacy`.
2. A file with `target V4` keeps working as it is. Its checksum does not change.
3. A SurrealDB 3.x datastore that was upgraded to SurrealDB 4.0.1 stays at level 3. Raise it with `ALTER DATABASE COMPATIBILITY 4` before `migrate!` runs, or `migrate!` refuses it with `Level`.
4. SurrealDB 4 refuses a token made before the server upgrade. Sign in again to get a new token.
5. Remove `db_target` and the third argument of `Surreal.plan` from the app.

## Limits

| Limit | What to do instead |
| --- | --- |
| A path through an optional record or a union arm cannot be indexed or made unique | Use an optional field at the end of a path, the whole optional record, or a field outside it |
| `REFERENCE` works only on root fields, so other links use events and an index | Accept the extra index. The event name is `<table>_<path>_on_delete` |
| A plan does not find renames, and does not compare with the live database. `INFO FOR DB` gives the text of the server, which is not the text of `Surreal.schema` | A rename is a drop and a new field (warning `MaybeRenamed`): copy the data in a statement of your own, in the file, before the drop. Keep the snapshot committed, and run `Surreal.check` in CI |
| An index build blocks writes to its table until it ends. `DEFINE INDEX .. CONCURRENTLY` is not used | Plan large indexes for a quiet time |
| Two tables with an equal row type are refused in one list, because a link to the row type is then ambiguous | Make one of the rows a nominal type (`:=`) |
| A table name can appear once in the list | Define one stored row for each name. Use `define_read()` for a read row |
| A view is grouped, takes no rule, no range and no median. A sum of integers is refused | Convert with `to_f64()`. Compute the median in a query |
| `created_now` replaces a value that a create gives | Do not set the field in a seed. Do not select it in a test that compares values |
| A table has one changefeed. There is no typed call to read it | Send `SHOW CHANGES` with `Unchecked.query!` |
| A cycle of required links cannot be filled | Make one link optional |
| `Unset` is refused for a required link and for a link in a union arm | Use `Reject`, `Cascade` or `Ignore`, or make the field optional |
