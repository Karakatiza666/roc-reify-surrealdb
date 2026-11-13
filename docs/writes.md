# Writing rows

This page shows how to create, update and delete rows. Each write is a method of a table. It gives a `Prepared` that you run on a session, as a query does. The result is the rows as stored.

The words clause, parameter record and prepared statement are in [Words used in these pages](getting-started.md#words-used-in-these-pages). The row types are `Owner` and `Medication` of `examples/main.roc`, `Tally` and `Shift` of `examples/client.roc`, and `Treats` of `examples/main.roc`. The SurrealQL is real output. It comes from a scratch app, and the statements ran on SurrealDB 3.3.4. In the scratch app, `Owner` is an alias row without the `tags` default and without `referred_by`.

| You want | Call | Section |
| --- | --- | --- |
| Store a whole row | `create`, `insert`, `upsert`, `replace`, `edit` | [Write whole rows](#write-whole-rows) |
| Let the server make the key | `create_new`, `insert_new` | [Keys that the server makes](#keys-that-the-server-makes) |
| Change fields with a function | `update`, `update_by`, `update_at`, `update_at_by` | [Update rows](#update-rows) |
| Change only some fields | `set`, `set_by`, `set_at`, `set_at_by` | [Set only some fields](#set-only-some-fields) |
| Merge a partial record | `merge`, `merge_at`, `upsert_merge_at` | [Merge a record](#merge-a-record) |
| Replay JSON Patch ops | `patch_at`, `patch_ops_at` | [Apply JSON Patch ops](#apply-json-patch-ops) |
| Insert, or change the row that exists | `insert_or_update` | [Insert or update](#insert-or-update) |
| Remove rows | `delete`, `delete_by`, `delete_at` | [Delete rows](#delete-rows) |

A write takes the row type of the table. The row type needs the derived encoder and reader. An alias row has them. A nominal row has them when it states `encoder_for : _` and `parser_for : _` (see [Row types](data-types.md#row-types)).

## Write whole rows

These calls take a whole row. The `id` field is the record key. Each call gives `Prepared(List(row))`.

| Call | Statement | A row with the key exists | No row with the key |
| --- | --- | --- | --- |
| `table.create(row)` | `CREATE` | Server error `Exists` | The row is made |
| `table.insert(rows)` | `INSERT`, in a transaction | Server error `Exists`, and nothing is stored | The rows are made |
| `table.upsert(row)` | `UPSERT .. CONTENT` | The row is replaced | The row is made |
| `table.replace(row)` | `UPDATE .. CONTENT` | The row is replaced | Nothing happens |
| `table.edit(change)` | One of `CREATE`, `UPDATE .. CONTENT`, `DELETE` | See below | See below |

```roc
# Fragment: uses `owners`, `jon`, `mara` and `lena` of examples/main.roc.
made = owners.create(jon)
seeded = owners.insert([mara, lena])
```

The statements:

```surql
CREATE owner:⟨jon⟩ CONTENT { address: { city: 'Oslo', line: 'Torggata 1' }, email: 'jon@example.org', name: 'Jon Berg', phone: '555-0101', tags: [] } RETURN AFTER;
BEGIN;
INSERT INTO owner [{ address: { city: 'Oslo', line: 'Kirkeveien 8' }, email: 'mara@example.org', id: 'mara', name: 'Mara Ito', tags: ['vip'] }, { address: { city: 'Lyon', line: 'Rue Merciere 9' }, email: 'lena@example.org', id: 'lena', name: 'Lena Roux', phone: '555-0188', tags: [] }] RETURN AFTER;
COMMIT;
```

An optional field with no value (`mara` has no `phone`) is a key that the statement leaves out. The reply is read as `List(Owner)`: the rows as stored, in the order that you wrote them.

Real results of running `create` twice, and `replace` for a key that has no row:

```text
create:        Ok([{ id: "jon", name: "Jon Berg", .. }])
create again:  Err(Server(Exists({ message: "Database record `owner:jon` already exists", name: "owner:jon", what: "Record" })))
replace, no row: Ok([])
```

`insert` runs `BEGIN`, the `INSERT` and `COMMIT` in one request. If one row fails, no row is stored. With a duplicate key the error is `Exists`. With a repeated value of a unique index it is `Index`, or `Unique` when the session knows the schema (see [Errors](errors.md#server-errors)).

### Write one change with `edit`

`edit` takes an `Edit(row)`, the change as a value. The Mirror uses the same type (see [Test with the Mirror](advanced.md#test-with-the-mirror)).

| Tag | Statement | Result |
| --- | --- | --- |
| `Create(row)` | `CREATE`, or `RELATE` for an edge | The row after |
| `Replace(old, new)` | `UPDATE .. CONTENT` with `new` | The row after, or `[]` for a key with no row. The statement does not use `old` |
| `Delete(row)` | `DELETE` of the key of `row` | The row before, or `[]` for a key with no row |

```roc
# Fragment: uses `owners` and `jon` of examples/main.roc.
owners.edit(Replace(jon, { ..jon, name: "Jonas" }))
```

### Edge tables

An edge table takes the same calls. `create` gives `RELATE`, and `insert` gives `INSERT RELATION`. The fields `from` and `to` become `in` and `out`.

```surql
RELATE vet:⟨ruth⟩->treats:⟨e1⟩->patient:⟨rex⟩ CONTENT { primary: true, since_year: 2022 } RETURN AFTER;
BEGIN;
INSERT RELATION INTO treats [{ in: vet:⟨sam⟩, id: 'e2', primary: false, since_year: 2024, out: patient:⟨rex⟩ }] RETURN AFTER;
COMMIT;
```

The schema checks both ends (`ENFORCED`). Write the vets and patients first. An edge to a row that does not exist gives `Err(Server(NotFound({ .. what: "Record" })))`. See [Edge tables](links-and-graphs.md#edge-tables).

A view is read-only. Every write on a view is refused when you build it: ``Unsupported("`reading_roll` is a view, and a view is read-only")``.

## Keys that the server makes

A row type keeps `id : Str`. When a row is new, leave the `id` out. `create_new` and `insert_new` take the row without its `id`. The server makes the key.

| Call | Takes | Gives |
| --- | --- | --- |
| `table.create_new(new)` | The row without `id` | `Prepared(List(Created(row, new)))` |
| `table.insert_new(list)` | A list of such rows | The same, in the order that you wrote the rows |

A `Created(row, new)` is the record `{ id : Id(row), fields : new }`. The `id` is the key that the server made, as an `Id` of the table. The `fields` are the other fields as stored. Use `created.id` for `table.at`, `update_at`, `delete_at` and `table.link`. Real output:

```surql
CREATE shift CONTENT { label: 'Early' } RETURN AFTER;
BEGIN;
INSERT INTO shift [{ label: 'Late' }, { label: 'Night' }] RETURN AFTER;
COMMIT;
```

```roc
# Fragment: uses `Shift` and `shifts` of examples/client.roc.
early_label : List(Surreal.Created(Shift, { label : Str })) -> Str
early_label = |made| match made {
	[one, ..] => "${one.fields.label} at ${one.id.key()}"
	[] => "none"
}
```

For the three rows above the keys were `01M6MCEY0QCEA5NZH2BJZ5AXXK`, `01M6MCEY0Q5YBFEJ0K3XVP445B` and `01M6MCEY0QN3RD1GW48C6169EM`.

The schema says how the key is made. It is the default of the `id` field. Real keys from `create_new` on each schema:

| Schema | `DEFINE FIELD` | Key |
| --- | --- | --- |
| No default | None | A random key of 20 lower-case letters and digits: `plain_t:4dlest84ftshvux7uuxk` |
| `.default_by(\|r\| r.id, \|_\| Surreal.Rand.ulid())` | `id ON ulid_t TYPE string DEFAULT rand::ulid()` | A ULID: `ulid_t:01M6MCKE9ZX6CNWC3HSBS8RG3K` |
| `.default_by(\|r\| r.id, \|_\| Surreal.Rand.uuid())` | `.. TYPE string DEFAULT <string>rand::uuid()` | A UUID as text: ``uuid_t:`01a1a8c9-b93f-75f0-ad26-e7ad746b1935` `` |
| `.default_by(\|r\| r.id, \|r\| r.title)` | `.. DEFAULT $this.title` | A key from the content: `content_t:Feed` |
| `.default(\|r\| r.id, "main")` | `.. DEFAULT 'main'` | One key. A second `create_new` gives `Exists` |

All of these keys are text, so `Id` holds them and every call by key works. The shape of `default_by` is in [Default values](data-types.md#default-values). `Rand` is described in [Random values in writes](#random-values-in-writes).

An edge table can leave its key to the server too. `RELATE` has no key then:

```surql
RELATE shift:⟨01M6MCGSHX62HAS9B4RYMEYCDV⟩->handover->shift:⟨01M6MCGSHX28N2TY8JDGNCAQZD⟩ CONTENT { notes: 'n' } RETURN AFTER;
```

To link to a row that has a server key, wait for the result of its write. Then call `shifts.link(created.id.key())`. A transaction cannot do it: each part is built before the request runs (see [Limits](#limits)).

## Update rows

`update` changes the rows that a condition keeps. Its patch is a function from the row to the row. Write the row with a record update, `{ ..o, f: x }`. Each field that differs from `o` becomes a `SET` item.

| Call | Where it writes | Takes |
| --- | --- | --- |
| `table.update(cond, f)` | Each row that `cond` keeps | `Code(row -> Bool)`, `Code(row -> row)` |
| `table.update_by(cond, f)` | The same | `cond` and `f` take the parameter record first |
| `table.update_at(id, f)` | The one row with this `Id` | `Id(row)`, `Code(row -> row)` |
| `table.update_at_by(id, f)` | The same | `f` takes the parameter record first |

Each call gives a `Write(p, row)`. [Run a write](#run-a-write) shows how to run it. The result is the rows after the update.

```roc
# Fragment: uses `Owner`, `Address` and `owners` of examples/main.roc.
renamed = owners.update_at(owners.id("jon"), |o| { ..o, name: "Jon B. Berg" }).ready()
shorter = owners.update_at(owners.id("jon"), |o| { ..o, address: { ..o.address, city: "Rome" } }).ready()
```

```surql
UPDATE owner:⟨jon⟩ SET name = 'Jon B. Berg' RETURN AFTER;
UPDATE owner:⟨jon⟩ SET address.city = 'Rome' RETURN AFTER;
```

The patch is an inline function here. Name it, with a type annotation, when a test or another write reuses it. `renamed` gives the first statement. Fields that the function does not change are not in the statement, also the optional ones (`phone`). A nested record update sets the nested path (`address.city`).

For a condition with a parameter, use `update_by`. The condition and the patch both read the parameter record. The record type comes from the fields that the functions read, so no type is written:

```roc
# Fragment: uses `medications` of examples/main.roc.
restock = medications.update_by(|p, m| m.stock < p.floor, |p, m| { ..m, stock: m.stock + p.add })
```

`restock.prepare({ floor: 10, add: 25 })` gives:

```surql
LET $add = 25i32;
LET $floor = 10i32;
UPDATE medication SET stock = <int>stock + <int>$add WHERE stock < $floor RETURN AFTER;
```

`stock` is an `I32`, so the parameters are `i32` literals. The sum is done as `int`, and the `i32` field converts it back (see [The CBOR v2 types](data-types.md#the-cbor-v2-types)).

The patch reads the row as it was before the update. A swap works as it does in Roc. `{ ..t, hits: t.meta.a, meta: { ..t.meta, a: t.hits } }` gives `SET hits = meta.a, meta.a = hits`. On a row with `hits: 6` and `meta.a: 1` the server stored `hits: 1` and `meta.a: 6`.

To branch, branch inside the field: `{ ..t, label: if (t.hits > 5) "big" else "small" }` gives `SET label = (IF hits > 5 THEN 'big' ELSE 'small' END)`. A branch around the whole row is refused:

```text
Unsupported("in the patch of `update_at`: an update patch builds one row; a branch around the row has no `SET` form, so branch inside each field that changes: `|o| { ..o, f: if .. }`")
```

A key with no row changes nothing. `update_at` gives `Ok([])` for it.

## Set only some fields

A record update must have the type of its base row. `set` takes a patch that is a record of only the fields to change. It has the calls `set(cond, f)`, `set_by`, `set_at(id, f)` and `set_at_by`. They have the types of the `update` calls, with a patch type of their own.

```roc
# Fragment: uses `Owner`, `Address` and `owners` of examples/main.roc.
moved : Owner -> { address : Address, phone : Try(Str, [Missing]) }
moved = |o| { address: { ..o.address, zip: "69002" }, phone: Err(Missing) }

lena_moved = owners.set_at(owners.id("lena"), moved)
```

```surql
UPDATE owner:⟨lena⟩ SET address.zip = '69002', phone = NONE RETURN AFTER;
```

| Patch field | What it does |
| --- | --- |
| A value of the field type | Sets the field |
| `Ok(value)` for an optional field | Sets the field |
| `Err(Missing)` for an optional field | Removes the field: `SET phone = NONE` |
| A record built with `..` | Sets each changed path: `address.zip` |

An optional field of a patch has the type `Try(Str, [Missing])`. This is not the type of `o.?phone`, which is `Try(Str, [MissingField])`.

Write the type annotation of the patch function. Roc cannot type a record of some of the row's fields. The annotation fixes the patch type. A function with a short body also works with `|_|`:

```roc
# Fragment: uses `Owner` and `owners` of examples/main.roc.
forget_phone : Owner -> { phone : Try(Str, [Missing]) }
forget_phone = |_| { phone: Err(Missing) }

forgotten = owners.set_at(owners.id("jon"), forget_phone)
```

This gives `UPDATE owner:⟨jon⟩ SET phone = NONE RETURN AFTER;`. The row stored had no `phone` after the run. If you write the lambda inline, with no annotation, the type is an open tag union. The call gives `BadSchema`:

```text
BadSchema("the patch's `phone` is `[Err([Missing])]`, and the row's `phone` is `Str`")
```

A patch with no `Err(Missing)` can be inline: `owners.set_at(owners.id("jon"), |_| { name: "Jon B. Berg" })` gives `UPDATE owner:⟨jon⟩ SET name = 'Jon B. Berg' RETURN AFTER;`.

The compiler does not check the fields of a `set` patch. The package checks them when you build the statement:

| Patch | Result |
| --- | --- |
| `{ nmae: "x" }` | ``BadSchema("the row has no field `nmae`, so a patch cannot set it; it has `address`, `email`, `id`, `name`, `phone`, `tags`")`` |
| `{ hits: 5 }` for an `I64` field | ``BadSchema("the patch's `hits` is `Dec`, and the row's `hits` is `I64`; a number literal without a suffix is a `Dec`, so write `1.I64`")`` |
| `{ hits: t.hits + 5.I64 }` | `SET hits = hits + 5` |

To change a union field, use `set_at` or `update`. They write `SET`. A `MERGE` keeps the keys of the old arm (see [Merge a record](#merge-a-record)).

## Merge a record

`merge_at` takes a record of the fields to change and writes it as one `MERGE`. The record is a value of your app. An object in it is merged into the stored object, key by key.

| Call | Statement | Takes |
| --- | --- | --- |
| `table.merge_at(id, partial)` | `UPDATE t:⟨k⟩ MERGE { .. }` | `Id(row)`, a record |
| `table.upsert_merge_at(id, partial)` | `UPSERT t:⟨k⟩ MERGE { .. }` | The same. The row is made when the key has none, so the record holds every field that the schema needs |
| `table.merge(cond, partial)` | `UPDATE t MERGE { .. } WHERE ..` | `Code(row -> Bool)`, a record |

```roc
# Fragment: uses `tallies` of examples/client.roc.
retitle : { label : Str, meta : { a : I64 } }
retitle = { label: "Merged", meta: { a: 9 } }

merged = tallies.merge_at(tallies.id("t1"), retitle)
hot = tallies.merge(|t| t.hits > 10, { tags: ["hot"] })
```

```surql
UPDATE tally:⟨t1⟩ MERGE { label: 'Merged', meta: { a: 9 } } RETURN AFTER;
UPDATE tally MERGE { tags: ['hot'] } WHERE hits > 10 RETURN AFTER;
```

On a tally with `meta: { a: 1, b: 2 }`, the merge stored `meta: { a: 9, b: 2 }`. The key `b` stays.

| Rule | Detail |
| --- | --- |
| The server checks the fields | The record type is free, so a wrong field is not a compile error. A field that the table does not have, such as `{ nope: "y" }`, gives `Err(Server(Other({ kind: "Internal", message: "Found field 'nope', but no such field exists for table 'tally'" })))` |
| `id` is refused | ``Unsupported("a merge cannot change `id`, the record key")`` when you build it |
| Do not merge a union field | A merged union keeps the keys of its old arm. Use `set_at` |
| To remove an optional field | Use `set_at` with `Err(Missing)` |

## Apply JSON Patch ops

A client can replay what another client saw. `patch_at(id, patches)` takes the `Patch` values of a `live_diff` watch. `patch_ops_at(id, ops)` takes `Op` values that your app made. Both write `UPDATE .. PATCH [..]` on the one row. A `/` in a key is written as `~1` and a `~` as `~0` (RFC 6901), as SurrealDB 4.0.1 reads them: the key `a/b` of `meta` is `/meta/a~1b`.

```roc
# Fragment: uses `tallies` of examples/client.roc and `import cbor.Cbor`.
patch_ops : List(Surreal.Op)
patch_ops = [Replace(["label"], Cbor.Value.Text("Patched")), Add(["tags", "-"], Cbor.Value.Text("p"))]

patched = tallies.patch_ops_at(tallies.id("t3"), patch_ops)
```

```surql
UPDATE tally:⟨t3⟩ PATCH [{ op: 'replace', path: '/label', value: 'Patched' }, { op: 'add', path: '/tags/-', value: 'p' }] RETURN AFTER;
```

The server stored `label: "Patched"` and `tags: ["p"]`. The `Patch` type is in [Patches of stored rows](live-queries.md#patches-of-stored-rows).

These cases are refused when you build the statement:

| Case | Error |
| --- | --- |
| An op at `/id` | ``Unsupported("a patch cannot change `id`, the record key (the op is at `/id`)")`` |
| A patch of another row (`patch_at`) | `Unsupported("a patch is of another row than ..")` |
| A patch of a delete | ``Unsupported("a patch of a delete: delete the row with `delete_at`")`` |
| A `Change` op | ``Unsupported("a `change` op is a text diff, and the ORM reads it and does not write it; replay the field with a `replace`")`` |

A path that the row does not have is the error of the server (`no such field`).

## Insert or update

`insert_or_update(rows, patch)` inserts each row. When a row with the same key exists, the patch changes the stored row instead. The patch takes the new row and the stored row.

```roc
# Fragment: uses `Tally` and `tallies` of examples/client.roc.
bump : Tally, Tally -> Tally
bump = |new, old| { ..old, label: new.label, hits: old.hits + new.hits }

counted = tallies.insert_or_update([tally("t1", "Uno", 5), tally("t3", "Three", 3)], bump)
```

```surql
BEGIN;
INSERT INTO tally [{ hits: 5, id: 't1', label: 'Uno', meta: { a: 1, b: 2 }, tags: [] }, { hits: 3, id: 't3', label: 'Three', meta: { a: 1, b: 2 }, tags: [] }] ON DUPLICATE KEY UPDATE hits = hits + $input.hits, label = $input.label RETURN AFTER;
COMMIT;
```

In the patch, the new row is `$input`. SurrealDB 4.0.1 runs the clause only for a row that is stored. The call is one transaction, as `insert` is. With a stored `t1` of 1 hit and no `t3`, the result was `t1` with 6 hits and the label `Uno`, and `t3` with 3 hits.

A duplicate is the same key. A row that repeats only the value of a unique index gives the error `Index` or `Unique`, as for `insert`. A relation table is refused: ``Unsupported("`insert_or_update` is not defined for the relation table `treats`")``.

## Delete rows

| Call | Statement | Takes |
| --- | --- | --- |
| `table.delete(cond)` | `DELETE t WHERE ..` | `Code(row -> Bool)` |
| `table.delete_by(cond)` | The same, with a parameter record | `Code((p, row -> Bool))` |
| `table.delete_at(id)` | `DELETE t:⟨k⟩` | `Id(row)` |

```roc
# Fragment: uses `owners` and `visits` of examples/main.roc.
gone = owners.delete_at(owners.id("jon")).ready()
too_old = visits.delete_by(|p, v| v.seen < p.cutoff).prepare({ cutoff: cutoff })
```

```surql
DELETE owner:⟨jon⟩ RETURN BEFORE;
LET $before = d'2026-01-01T00:00:00Z';
DELETE visit WHERE seen < $before RETURN BEFORE;
```

The result is the rows as they were before the delete. A key with no row gives `Ok([])`. The delete policies of the links apply: a row that another row links to is refused with `Reject`, and it is removed with `Cascade`. See [Links and delete policies](schema.md#links-and-delete-policies).

## Run a write

A write that takes a clause (`update`, `set`, `delete` and the `_by` and `_at` forms) is a `Write(p, row)`. It is not a `Prepared` yet. Two methods finish it:

| Call | Gives |
| --- | --- |
| `write.to_surql()` | `Try(Str, Error)`. The statement with a `$name` for each parameter |
| `write.prepare(params)` | `Prepared(List(row))`. A `LET` for each field of `params`, then the statement |
| `write.ready()` | The same as `prepare({})`, for a write with no parameter record |

Use `ready()` when the write has no parameter record. `prepare({})` is the same call. A `Write` gives the rows after an update and the rows before a delete (`RETURN AFTER`, `RETURN BEFORE`). The calls of [Write whole rows](#write-whole-rows) and the calls for merge, patch and key already give a `Prepared`.

Run the `Prepared` with `session.run!`. The result is a `List(row)`, or a `List(Created(row, new))` for the `_new` calls. A failed write gives an `Err` in `result`, and the session goes on:

```roc
# Fragment: uses `session`, `owners` and `renamed` from above.
built = renamed?
out = session.run!(built)
# out.result : Try(List(Owner), Surreal.Error)
```

To run several writes as one unit, join them with `begin` and `then`, or give a list of them to `Surreal.transaction`. See [Transactions](sessions.md#transactions).

To write one row by its key, use the `_at` calls. They take a typed `Id` of the table.

## Random values in writes

`Surreal.Rand` makes a value on every call. It is allowed where the server makes a value once per write: a `default_by` of the schema, a `computed` field and a patch of `update`. A patch that calls `Surreal.Rand.ulid()` gives `SET label = rand::ulid()`.

A filter cannot use it. A condition that calls `Rand` is refused when you build it:

```text
Unsupported("in the condition of `delete`: `Surreal.Rand.ulid` gives a new value on every call: use it in a default, a computed field or an update")
```

The functions of `Rand` are in [Rand and where it is allowed](functions.md#rand-and-where-it-is-allowed).

## Limits

| Limit | What to do instead |
| --- | --- |
| A record update has the type of its base row, so `{ ..v, years: 300 }` cannot set a `U8` field to a value of another row type | Write the whole row and use `create`, `replace` or `upsert`. See `old_vet` in `examples/main.roc` |
| The fields of a `set` patch are checked when you build the statement, not by the compiler | Test each write with `.ready().is_ok()` in an `expect` |
| The fields of a `merge` record are checked by the server | Prefer `set_at` when a typo must be a build error |
| A merged union keeps the keys of its old arm | Change a union with `set_at` or `update` |
| An update patch that branches around the whole row is refused | Branch inside the field: `{ ..o, f: if c x else o.f }` |
| `_at` calls take an `Id(row)`, and an `Id` holds a text key | Delete a row with a `TimeKey` through `edit(Delete(row))` |
| `create_new` and `insert_new` need a row type with `id : Str`. A row with a `TimeKey` key is a type error | Give the row type a text key, or write the key yourself |
| The README says a nominal row is refused by `create_new`. The compiler `local-reify-2026-11-03-1708298` accepts it, and no test covers it | Use an alias row with `id : Str` to stay in the tested path |
| A part of a transaction cannot read a key that another part made. Each part is built before the request runs | Write the rows that link to the new key after you read its result |
| A write to a view is `Unsupported` | Write the source table |
| `insert_or_update` is refused on a relation table | Use `create`, `upsert` or `replace` for the edge |
| `patch_at` refuses a patch of another row, a patch of a delete, an op at `/id` and a `change` op | Use `delete_at`, and replay a `change` op as a `replace` |
| `Rand` is refused in a filter | Use it in `default_by`, `computed` or the patch of an update |
