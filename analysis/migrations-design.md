# Migrations: design pass (revision 2: SurrealDB 4.0 first, 3.x with no major downside)

Date: 2026-11-05. Scope: research and design only. No file of the library is changed.
Basis: the uncommitted `Surreal.migration(old, new)` in `src/Surreal.roc:1790-1845` and `Schema.migration_steps` in `src/Schema.roc:620-704`, the "Migrations" sections of `README.md:1496-1545` and `docs/schema.md:401-460`.

The user approved this shape: the Roc schema is the source of truth, a committed snapshot, reviewed versioned `.surql` files, forward only (no `down`), a history table with checksums, the `Surreal.check` expect, and one path for first setup and for updates. Revision 2 keeps that shape. It changes the statements that a plan writes, the unit of a transaction, and how the library selects the server path.

Servers tested by me on 2026-11-05 (docker, memory engine, 200k rows): `surrealdb/surrealdb:v4.0.0` (container `mig-v4`, port 8301) and `surrealdb/surrealdb:v3.3.5` (container `mig-v3`, port 8302).

## 1. Summary and recommendation

1. There is no SurrealDB 3.4.x. The 3.x line ends at 3.3.5 (2026-10-29). 4.0.0 was released on 2026-11-03. The floor is 3.3.5, which behaves as 3.3.4 for all the costs below.
2. 4.0 adds a server-side data migration: `DEFINE FIELD ... MIGRATE EXISTING ROWS AS <name> USING <expr> [FALLBACK <v>]`. It is lazy (0.1 s on 200k rows), runs once for each name, and replaces the library's `UPDATE ... SET` fill. At compatibility level 4, `REMOVE FIELD` also clears the old values, which replaces `UPDATE ... UNSET`.
3. 4.0 refuses a `DEFINE INDEX` in a transaction that also writes to or migrates the same table. Thus a migration file can no longer be one transaction. It becomes ordered sections, and each section is one transaction.
4. 4.0 does not rebuild an unchanged index on `OVERWRITE`. 3.3.5 does: the extra cost on 200k rows is about 1.3 s for a standard or a unique index, 1.7 s for a full-text index, 1.3 s for HNSW (20k rows), and 0.4 s for a view. Thus the 3.x rule is: never send an unchanged definition. The versioned design already does this, because the app runs only the files that the history does not have.
5. Recommendation: keep the approved design, and make it target-aware. `Surreal.plan(snapshot, defs, target)` writes `V4` statements (`MIGRATE EXISTING ROWS`, sections) or `V3` statements (`UPDATE` fills and unsets). The target is a constant in the app. The file header records it. `migrate!` reads `INFO FOR DB` (`compatibility` is 4, 3, or absent on 3.x) and refuses a file that the server cannot run.
6. App start: `session.migrate!(migrations)` only. Never run `Surreal.schema` at each start on 3.x. `Surreal.schema` stays the text of the snapshot and of the first migration.
7. Dev `push!` diffs against a snapshot that it keeps in the database, so it too sends only changed definitions on 3.x.

## 2. Industry survey

### 2.1 Tools

| Tool | Model | Up/down | History table | Checksums | Drift detection | Notes | Source |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Kysely | Imperative, TS files, ordered by name | `up` required, `down` optional | `kysely_migration` + `kysely_migration_lock` | No | No | Refuses out-of-order files unless `allowUnorderedMigrations`. One path for setup and updates | https://kysely.dev/docs/migrations |
| Knex | Imperative, JS files | `up` / `down` | `knex_migrations` + `knex_migrations_lock` | No | No | Batches: `rollback` undoes the last batch | https://knexjs.org/guide/migrations.html |
| Rails Active Record | Imperative Ruby DSL, `change` reverses known operations | `change` or `up` / `down` | `schema_migrations(version)` | No | `db/schema.rb` dump is committed | Guide: load the schema dump for a new database | https://guides.rubyonrails.org/active_record_migrations.html#schema-dumping-and-you |
| Django | Generated from models, Python ops | Most ops reverse automatically | `django_migrations` | No | `makemigrations --check` | `squashmigrations` with `replaces`. Asks about renames | https://docs.djangoproject.com/en/stable/topics/migrations/ |
| Alembic | Autogenerate, then edit | `upgrade` / `downgrade` | `alembic_version` | No | `alembic check` | Does not detect renames | https://alembic.sqlalchemy.org/en/latest/autogenerate.html |
| Laravel | Imperative PHP | `up` / `down` | `migrations(migration, batch)` | No | No | `schema:dump` squashes | https://laravel.com/docs/migrations |
| golang-migrate | SQL files `.up.sql` / `.down.sql` | Both | `schema_migrations(version, dirty)` | No | No | `dirty` flag after a failure. Advisory lock | https://github.com/golang-migrate/migrate |
| goose | SQL or Go files | Both | `goose_db_version` | No | No | `-- +goose NO TRANSACTION` marks a file that cannot be one transaction | https://github.com/pressly/goose |
| sqlx (Rust) | SQL files embedded at compile time | Optional reversible pairs | `_sqlx_migrations(checksum, ...)` | Yes | No | Closest to Roc `import "f" as x : Str` | https://docs.rs/sqlx/latest/sqlx/macro.migrate.html |
| Flyway | Versioned SQL, forward only | Undo is paid; docs say it does not help a partial failure or restore data | `flyway_schema_history` | Yes | Paid | `baseline` adopts an existing DB | https://documentation.red-gate.com/fd/undo-migrations-273973334.html |
| Liquibase | Changesets | `rollback` | `DATABASECHANGELOG` + `DATABASECHANGELOGLOCK` | Yes (`MD5SUM`) | `diff` | Lock row | https://docs.liquibase.com/concepts/tracking-tables/databasechangeloglock-table.html |
| Atlas | Declarative + versioned | No down by default | `atlas_schema_revisions` | `atlas.sum` | `migrate diff`, inspect | `migrate lint`; `txmode` per file | https://atlasgo.io/concepts/migration-directory-integrity , https://atlasgo.io/versioned/lint |
| Prisma Migrate | Diff of schema, SQL files committed | No down | `_prisma_migrations(checksum)` | Yes | Shadow database | `db push` for prototypes | https://www.prisma.io/docs/orm/prisma-migrate/understanding-prisma-migrate/shadow-database |
| Drizzle Kit | Diff against JSON snapshots | No down | `__drizzle_migrations(hash)` | Hash stored | `drizzle-kit check` | `generate` / `migrate` vs `push` | https://orm.drizzle.team/docs/migrations |
| skeema | Declarative, diff against live DB | No | None | No | `diff` | `push` refuses unsafe changes | https://www.skeema.io/docs/ |
| sqldef | Declarative, idempotent diff | No | None | No | `--dry-run` | Drops need `--enable-drop` | https://github.com/sqldef/sqldef |
| SurrealKit (official) | `.surql` schema files. Sync (dev) and Rollouts (shared DBs) | Rollouts: `rollback` only before `complete` | `__entity`, `__rollout`, `__seed` | Content hash | Snapshots | Rollouts: `start` (non-destructive), deploy, `complete` (destructive); resumable state machine | https://surrealdb.com/docs/manage/schema-migration , https://surrealdb.com/docs/manage/schema-migration/rollouts.md , https://surrealdb.com/docs/manage/schema-migration/sync.md |
| surrealdb-migrations | `schemas/` + `migrations/` | Optional down | `script_migration` | No | No | Archived; points to SurrealKit | https://github.com/Odonno/surrealdb-migrations |
| surreal_orm | Diff of Rust structs | Optional | Not documented | Not documented | No | `#[orm(old_name = ...)]` | https://github.com/Oyelowo/surreal_orm |

### 2.2 SurrealDB versions

| Release | Date | Source |
| --- | --- | --- |
| 3.3.4 (tested by the library) | 2026-10-13 | https://github.com/surrealdb/surrealdb/releases/tag/v3.3.4 |
| 3.3.5 (latest 3.x; there is no 3.4.x) | 2026-10-29 | https://github.com/surrealdb/surrealdb/releases/tag/v3.3.5 , docker tags `v3`, `v3.3` |
| 4.0.0-beta.1 | 2026-10-28 | docker tag `v4.0.0-beta.1` |
| 4.0.0 | 2026-11-03 | https://surrealdb.com/releases/4.0.md , https://surrealdb.com/blog/surrealdb-4-the-database-and-memory-for-every-agent |

### 2.3 4.0 changes that matter for schema and migrations

"Verified" means that I ran it on the containers above.

| Change in 4.0 | Effect on the design | Source |
| --- | --- | --- |
| Compatibility level per database: 3 or 4. A datastore from 3.x stays at 3; a new one starts at 4. `ALTER DATABASE COMPATIBILITY 4` raises it. `INFO FOR DB` has `"compatibility": 4` (absent on 3.3.5) | The probe for the server path. Verified | https://surrealdb.com/releases/4.0.md |
| `DEFINE FIELD` / `ALTER FIELD ... MIGRATE EXISTING ROWS AS <name> USING <expr> [FALLBACK <v>]`. Rows convert on read and a background job rewrites the table. A name runs once; the same name with another transform is refused. `INFO FOR TABLE` lists them under `migrations` | Replaces the fill `UPDATE`. A plan can write a type change with a cast. Verified: 0.10 s on 200k rows; 0.11 s for a second run with the same name; error for the same name with `USING 2` | https://surrealdb.com/docs/surrealql/statements/define/field |
| At level 4, a `SCHEMAFULL` table with rows refuses a new field whose type does not accept `NONE`, and a narrower type, unless the statement has `MIGRATE EXISTING ROWS`. Widening is allowed | A `V3` fill plan fails at level 4 (safe: the transaction rolls back). Verified with the exact error text | same |
| At level 4, `REMOVE FIELD` records a removal migration (`remove old after 3`); the next write of an old row succeeds | No `UPDATE ... UNSET` at level 4. At level 3 the old error stays ("Found field 'old', but no such field exists"). Verified both | same |
| `MIGRATE EXISTING ROWS` is refused when a view selects from the table | The plan removes the view in an earlier section and defines it again in a later one. Verified | verified only |
| A blocking `DEFINE INDEX` in a transaction that wrote to the table, or that runs a migration on the table, is refused. A write after the `DEFINE INDEX` in the same transaction is refused too | A file is sections, each one transaction. Indexes go in a later section than writes and migrations on their table. Verified (three error texts) | https://surrealdb.com/docs/build/migrating/from-old-surrealdb-versions/3x-to-4x |
| An index on a table whose `ALTER TABLE ... REMOVE UNDECLARED FIELDS` migration has not finished is refused | Do not write `REMOVE UNDECLARED FIELDS`. `REMOVE FIELD` at level 4 is enough. Verified (that migration had not finished after 30 s on 1000 rows) | verified only |
| An unchanged `DEFINE INDEX OVERWRITE` keeps the index | No cost for a repeated index on 4.0. Verified: 0.00-0.02 s over the base for standard, unique, full-text, HNSW | https://surrealdb.com/releases/4.0.md |
| A blocking index build commits its definition before the build; a failed build removes it; writes to the table wait up to 60 s for a transaction that built a new index | Tested: a failed `UNIQUE` build in `BEGIN ... COMMIT` still rolled back a `DEFINE FIELD` of the same transaction. Large index builds block writers | 3x-to-4x guide |
| `DEFINE INDEX ... CONCURRENTLY` builds in the background; `INFO FOR INDEX` shows `building` | Option for large tables, out of scope for v1 | https://surrealdb.com/docs/surrealql/statements/define/indexes |
| `DEFINE ANALYZER OVERWRITE` does not reach an unchanged full-text index; run `REBUILD INDEX` | The plan writes `REBUILD INDEX` for each full-text index that uses a changed analyzer | 3x-to-4x guide |
| `REMOVE FIELD` also removes nested field definitions; a nested field needs its parent first | The removal of a nested field under a removed parent is not needed; order stays parent first | 3x-to-4x guide |
| `DEFINE FIELD OVERWRITE ... REFERENCE` on a populated field writes reference keys for old records | A new `REFERENCE` on a big table has a one-time cost. An unchanged one has none (verified 3.3.5 and 4.0) | https://surrealdb.com/releases/4.0.md |
| `DEFAULT ALWAYS`, `DEFINE TYPE`, `ALTER TYPE`, `REFERENCE ... MATERIALIZE INTO` | Not needed for migrations | same |
| `INFO ... STRUCTURE` is still "for internal use"; the `MIGRATE` clause does not show in `INFO FOR TABLE` field text | Drift keeps the shadow compare. The snapshot stores the field without the `MIGRATE` clause | https://surrealdb.com/docs/surrealql/statements/info , verified |
| 4.0 removes `DEFINE MODEL`, deprecates `MODULE`, refuses repeated `DEFINE TABLE` clauses, refuses effects in `VALUE` / `ASSERT` / `DEFAULT` | The library emits none of these. The generated `main.surql` and `monitoring.surql` give the same results on 3.3.5 and 4.0 (only ULIDs and the order of one unordered select differ) | 3x-to-4x guide, verified |

### 2.4 Cost of a repeated definition (measured, 200k rows unless noted)

Time over a `RETURN 1` request (3.3.5 base 0.45 s, 4.0 base 0.10 s through `surreal sql` in the container). The manager measured 1.2-1.8 s for `DEFINE INDEX OVERWRITE` on 3.3.4; 3.3.5 agrees.

| Statement, run again with no change | 3.3.5 | 4.0.0 |
| --- | --- | --- |
| `DEFINE INDEX OVERWRITE` (standard) | +1.0 to +1.5 s | +0.00 s |
| `DEFINE INDEX OVERWRITE ... UNIQUE` | +1.3 s | +0.00 s |
| `DEFINE INDEX OVERWRITE ... FULLTEXT ANALYZER .. BM25 HIGHLIGHTS` | +1.7 s | +0.00 s |
| `DEFINE INDEX OVERWRITE ... HNSW` (20k rows, 4 dimensions) | +1.3 s | +0.00 s |
| `DEFINE INDEX IF NOT EXISTS` (any kind) | +0.00 s | +0.00 s |
| `DEFINE TABLE OVERWRITE ... AS SELECT .. GROUP BY` (view) | +0.4 s | +0.08 s |
| `DEFINE FIELD OVERWRITE` with `ASSERT`, with `REFERENCE` | +0.00 s | +0.00 s |
| `DEFINE TABLE OVERWRITE` (normal), `DEFINE EVENT OVERWRITE`, `DEFINE ANALYZER OVERWRITE` | +0.00 s | +0.00 s |

One-time costs of a change (not repeated, because the history records the file):

| Change, 200k rows | 3.3.5 (`V3` plan) | 4.0.0 level 4 (`V4` plan) |
| --- | --- | --- |
| New required field with a value for old rows | `DEFINE FIELD` + `UPDATE .. SET .. WHERE .. IS NONE`: +1.2 s, in the transaction | `MIGRATE EXISTING ROWS AS .. USING 1`: +0.00 s, lazy |
| Dropped field | `REMOVE FIELD` + `UPDATE .. UNSET`: +0.9 s | `REMOVE FIELD`: +0.00 s, lazy |
| Narrowed type (`string` to `int`) | No server help: hand `UPDATE` with a cast | `MIGRATE .. USING <int> $value FALLBACK 0`: +0.00 s |

## 3. Consensus and disagreements

### 3.1 Consensus

| Practice | Reason |
| --- | --- |
| Commit the migration text that runs in production, and review it | Generated text can be wrong (renames, data loss). A tool upgrade must not change what runs |
| A history table, one row for each applied migration | The runner knows what to apply |
| A checksum for each applied file | Git and production must agree |
| Forward only; fix with a new file | A down script is seldom tested, cannot restore dropped data, and does not help a partial failure (Flyway docs; https://github.com/rust-db/refinery/issues/121) |
| Expand, then contract | Old and new app versions run together during a deploy (https://martinfowler.com/bliki/ParallelChange.html; SurrealKit `start` / `complete`) |
| Push mode for local development only | Fast, but it leaves no record |
| Lint destructive and data-dependent changes | Atlas `migrate lint`, skeema `--allow-unsafe` |
| CI checks that code schema and migrations agree | Django, Prisma shadow DB, Drizzle `check` |
| One runner at a time | Every tool has a lock |
| A file that cannot be one transaction is marked | goose `NO TRANSACTION`, Atlas `txmode`. 4.0 makes this a need for SurrealDB |

### 3.2 Disagreements

| Question | Side A | Side B | Assessment |
| --- | --- | --- | --- |
| `down` | Kysely, Knex, Rails, Laravel, golang-migrate, Liquibase | Flyway, Prisma, Drizzle, Atlas | No `down` (approved) |
| Fresh DB | Replay all files | Load the schema dump (Rails) | Replay (approved). Squash at the change of target from `V3` to `V4` |
| Diff at deploy time | skeema, sqldef | Prisma, Drizzle, SurrealKit rollouts | Generate at dev time |
| Checksum strictness | Flyway, sqlx: refuse | Kysely, Django: none | Refuse |
| Unit of a transaction | The whole file (Postgres tools) | Statement or file marked non-transactional (MySQL tools, goose) | A section. A file has one or more sections; the history records each finished section |

## 4. Options for this library

The approved option is (d). The table now adds the server columns.

| Aspect | (a) Runtime diff of two Roc schemas (today) | (a2) Runtime diff against a stored snapshot | (b) Committed `.surql` files | (c) Steps as Roc values | (d) Hybrid: (b) + push for dev + pure `check` (approved) |
| --- | --- | --- | --- | --- | --- |
| Old schema | Copies of old modules | Stored by the last run | Text snapshot | Old types are gone, so text again | Text snapshot |
| Review of exact text | No | No | Yes | No | Yes |
| History, checksum | No | Hash only | Yes | Text depends on library version | Yes |
| 3.x: repeated definitions | Only changes, but no record | Only changes | Never | Never | Never |
| 4.0: indexes need their own transaction | Fails today when a fill and an index meet a table | Same | Needs sections in the file | Same | Sections, written by the plan |
| 4.0: `MIGRATE EXISTING ROWS` | No | No | Yes, written by the plan | Yes | Yes, written by the plan |
| Server path | One text for all | One text for all | Target in the header | Target per run | Target constant, header, probe |
| Matches industry | No | SurrealKit Sync (dev) | Prisma, Atlas, SurrealKit rollouts | Kysely without `down` | Yes |

## 5. Recommended design

### 5.1 Concepts

| Concept | What it is | Where it lives |
| --- | --- | --- |
| Schema | `List(Surreal.Defined)` from Roc types and clauses | App module |
| Target | `V4` (SurrealDB 4.0 at compatibility level 4) or `V3` (3.3.x, and 4.0 at level 3). A constant of the app | App module, header of each file |
| Snapshot | The text that the migrations make, in the format of `Surreal.schema`, without `MIGRATE` clauses, with kept items for a later contract | `db/schema.surql`, committed |
| Plan | The diff from a snapshot to a schema for a target | Roc value |
| Section | Statements that run as one transaction. A file has one or more, split by the line `-- reify: commit` | In the file |
| Migration | A name and the text of one file, embedded at compile time | `db/migrations/NNNN_name.surql` |
| History | One record for each migration, with the count of finished sections | `_reify_migration` |

### 5.2 What a plan writes, by target

| Change | `V3` (3.3.x, 4.0 level 3) | `V4` (4.0 level 4) | Section |
| --- | --- | --- | --- |
| Unchanged definition | Nothing | Nothing | |
| New or changed table, field, event, function, analyzer, access, param | `DEFINE .. OVERWRITE` | `DEFINE .. OVERWRITE` | 1 |
| Removed index, event, function, analyzer, access, view | `REMOVE .. IF EXISTS` | `REMOVE .. IF EXISTS` | 1 |
| New field, type does not accept `NONE`, table existed | `DEFINE FIELD` then `UPDATE t SET f = <default> WHERE f IS NONE` | `DEFINE FIELD .. MIGRATE EXISTING ROWS AS m<NNNN>_<path> USING <default>` | 1 |
| New required field with no default | `= NONE`: fails at once on a table with rows (as today) | Marker line `-- reify: edit USING ..`; the runner refuses the file until a person writes the value | 1 |
| Narrowed or changed type | Warning and marker: the person writes an `UPDATE` with a cast | `MIGRATE .. USING <cast> $value FALLBACK <default>`; with no default, a marker | 1 |
| Widened type (for example `option<int>` to `option<int \| string>`, `int` to `option<int>`) | `DEFINE FIELD OVERWRITE` | `DEFINE FIELD OVERWRITE` | 1 |
| Dropped field (`DropData`) | `REMOVE FIELD IF EXISTS` then `UPDATE t UNSET f` | `REMOVE FIELD IF EXISTS` (the server clears old values) | 1 |
| Dropped table (`DropData`) | `REMOVE TABLE IF EXISTS` | `REMOVE TABLE IF EXISTS` | 1 |
| View over a table that section 1 migrates | Nothing extra | `REMOVE TABLE` of the view in section 1, `DEFINE TABLE .. AS SELECT` in section 2 | 1 and 2 |
| New or changed index | `DEFINE INDEX OVERWRITE` | `DEFINE INDEX OVERWRITE` | 2, when section 1 writes to or migrates its table; else 1 |
| Changed analyzer | `DEFINE ANALYZER OVERWRITE` (3.x rebuilds indexes on `OVERWRITE` of the index) | `DEFINE ANALYZER OVERWRITE`, then `REBUILD INDEX` for each full-text index that uses it | 1, rebuild in 2 |
| Hand data step | Where the person puts it | Not in a section that defines an index on the same table; the runner checks this from the text | Any |

The `V3` plan uses the same sections. A section split costs nothing on 3.x and keeps one file format.

### 5.3 How the library selects the path

| Step | Rule |
| --- | --- |
| Dev, plan | `Surreal.plan(snapshot, defs, target)`: the target is an app constant, for example `db_target = V4`. The plan does not read a server |
| File header | `-- reify-surrealdb migration 0003_bin_size target V4 from <sha256 of snapshot>` |
| Deploy, probe | `migrate!` sends `INFO FOR DB` once. No `compatibility` key: 3.x. `3` or `4`: 4.0 at that level |
| Deploy, check | `V4` file on 3.x: refused before it is sent (3.3.5 cannot parse `MIGRATE`: verified). `V4` file at level 3: runs, but a dropped field keeps its values, so the runner refuses with "raise the level first". `V3` file at level 4: runs; a fill on a table with rows fails in its transaction (safe), and the error says "squash to a `V4` baseline" |
| Change of server 3.x to 4.0 | 1. Upgrade the server; the database stays at level 3; `V3` files still run. 2. Add a migration file with `ALTER DATABASE COMPATIBILITY 4` (`Surreal.raise_compatibility()` gives the text). 3. Change the constant to `V4`. 4. Squash the older files into a `V4` baseline with `replaces`, so a fresh database (level 4) does not replay `V3` fills |

### 5.4 API (signatures in the library's style)

Pure, in `Surreal`:

```roc
Target : [V3, V4]

## The diff from the snapshot `from` ("" for an empty database) to the
## schema `to`, written for `target`.
plan : Str, List(Defined), Target -> Try(Plan, Error)

Plan :: { steps : List(Schema.Step), target : Target, warnings : List(Warning) }.{
	statements : Plan, [KeepData, DropData] -> List(List(Str))  # one list for each section
	dropped : Plan -> List(Str)
	warnings : Plan -> List(Warning)
	is_empty : Plan, [KeepData, DropData] -> Bool
	## The file: header, warnings as comments, the sections split by
	## `-- reify: commit`, and `-- reify: edit` where a person must write a value.
	to_file : Plan, [KeepData, DropData] -> Str
	## The snapshot after the plan, without `MIGRATE` clauses. With
	## `KeepData` the dropped tables and fields stay in it.
	snapshot : Plan, [KeepData, DropData] -> Str
	prepare : Plan, [KeepData, DropData] -> List(Prepared({}))  # one for each section; for tests and push
}

Warning : [
	TypeChanged({ table : Str, path : Str, from : Str, to : Str }),
	MaybeRenamed({ table : Str, from : Str, to : Str }),
	UniqueAdded({ table : Str, index : Str }),
	AssertAdded({ table : Str, path : Str }),
	NoDefault({ table : Str, path : Str }),
	Rewritten({ indexes : List(Str) }),   # changed text only (for example after a library upgrade): on 3.x each one rebuilds once
	ViewRebuilt(Str),
	Dropped(Str),
]

check : Str, List(Defined) -> Try({ pending_drops : List(Str) }, [Unplanned(Plan), ..])

Migration :: { name : Str, text : Str, checksum : Str, target : Target, replaces : List(Str) }
migration : Str, Str -> Try(Migration, Error)      # reads the header; refuses `-- reify: edit` and `BEGIN` / `COMMIT`
squashed : Str, Str, List(Str) -> Try(Migration, Error)   # name, text, the names it replaces
raise_compatibility : {} -> Str                    # "ALTER DATABASE COMPATIBILITY 4;"
```

Effectful, on `Session`:

```roc
migrate! : Session, List(Migration) => Try(Applied, Error)
Applied : { ran : List(Str), ahead : List(Str), server : [V3x, V4x(U8)] }

baseline! : Session, List(Migration) => Try({}, Error)

## Dev only. Diffs against the snapshot that the last push stored in
## `_reify_schema:current`, or against the names of `INFO` when there is
## none. Sends only changed definitions. Refuses a database with history.
push! : Session, List(Defined), [KeepData, DropData] => Try(Plan, Error)

drift! : Session, Str, [Names, Shadow(Session)] => Try(List(Drift), Error)
```

New `Error` tags: `MigrationChanged`, `MigrationOutOfOrder`, `MigrationText({ name, reason })` (an edit marker, `BEGIN`, or a data step next to an index of its table), `MigrationTarget({ name, file : Target, server : Str })`, `HasHistory`.

### 5.5 History table

```surql
DEFINE TABLE IF NOT EXISTS _reify_migration SCHEMAFULL PERMISSIONS NONE;
DEFINE FIELD IF NOT EXISTS checksum   ON _reify_migration TYPE string;
DEFINE FIELD IF NOT EXISTS target     ON _reify_migration TYPE "V3" | "V4";
DEFINE FIELD IF NOT EXISTS sections   ON _reify_migration TYPE int;
DEFINE FIELD IF NOT EXISTS done       ON _reify_migration TYPE int;
DEFINE FIELD IF NOT EXISTS applied_at ON _reify_migration TYPE option<datetime>;
DEFINE FIELD IF NOT EXISTS library    ON _reify_migration TYPE string;
DEFINE FIELD IF NOT EXISTS kind       ON _reify_migration TYPE "run" | "baseline" | "squash";
```

All fields are optional-safe for an empty table, so these `DEFINE` statements are cheap on both lines (`IF NOT EXISTS`).

| Point | Choice | Reason |
| --- | --- | --- |
| Record id | `_reify_migration:⟨0003_bin_size⟩` | Unique id, so the `CREATE` is the lock |
| Sections | Section 1: `CREATE` with `done: 1`, then its statements. Section k: `UPDATE .. SET done = k`, then its statements. `applied_at` is set in the last | A crash between sections resumes at `done + 1`. Each section commits with its own progress |
| Partly applied file | `done < sections`: the runner goes on from `done + 1`. The file checksum must still match | SurrealKit `__rollout` resumes in the same way |
| Order, unknown names | As revision 1: list order, `MigrationOutOfOrder`; names in the history but not in the list are `ahead` (an older binary), not an error | |

### 5.6 Concurrency

| Case | What happens |
| --- | --- |
| Two instances start together | Both send section 1 of `0003`. The `CREATE` of one fails (record exists, or `Conflict` at `COMMIT`); all of its section rolls back. It reads the history again and goes on |
| Section k > 1 | `UPDATE _reify_migration:⟨0003⟩ SET done = k WHERE done = k - 1`, and the runner checks that one row changed; else it stops and reads again |
| 4.0 blocking index build | Writes to that table wait up to 60 s. Large tables: `CONCURRENTLY` later (out of scope) |
| To verify | A test with two sessions on 3.3.5 and 4.0. Revert the record-id `CREATE` to see it fail |

### 5.7 App start, dev, CI, deploy

| Stage | Steps |
| --- | --- |
| App start (any server) | `session.migrate!(migrations)`. Nothing else. It sends the bootstrap `IF NOT EXISTS` statements and the unapplied sections only. An app with no new files sends one `INFO FOR DB` and one `SELECT` of the history |
| Dev loop | `push!` on a local DB. On 3.x it sends only changed definitions, because it keeps its own snapshot |
| Dev finish | `tools/plan.roc` writes the file and the snapshot. The person resolves each `-- reify: edit`, reads the warnings, adds one `import` line |
| CI | `roc test` (`check`, golden plans). Then, for each supported server image (`v3.3.5`, `v4.0.0`): replay all files into an empty database, apply `db/schema.surql` into a second one, `drift!` with `Shadow` is empty. Then an upgrade test on seeded rows |
| Deploy | The new binary runs `migrate!`. Contract files ship one release later |

Example app:

```roc
import "db/schema.surql" as snapshot : Str
import "db/migrations/0001_init.surql" as m0001 : Str
import "db/migrations/0002_bin_size.surql" as m0002 : Str

db_target : Surreal.Target
db_target = V4

migrations : Try(List(Surreal.Migration), Surreal.Error)
migrations = [("0001_init", m0001), ("0002_bin_size", m0002)].map_try(|(name, text)| Surreal.migration(name, text))

expect Surreal.check(snapshot, App.schema).is_ok()
expect migrations.is_ok()

main! = |_| {
	session = Session.open!(...)?
	_applied = session.migrate!(migrations?)?
	...
}
```

A generated `V4` file (bin gets a required `size`, has an index on `size`, loses `note`):

```surql
-- reify-surrealdb migration 0002_bin_size target V4 from 3fa1c2..
-- warning: Dropped(note)
REMOVE TABLE IF EXISTS note;
DEFINE FIELD OVERWRITE size ON bin TYPE int DEFAULT 1 MIGRATE EXISTING ROWS AS m0002_size USING 1;
-- reify: commit
DEFINE INDEX OVERWRITE bin_size ON bin FIELDS size;
```

The `V3` file of the same plan has `UPDATE bin SET size = 1 WHERE size IS NONE RETURN NONE;` in place of the `MIGRATE` clause.

### 5.8 Out of scope for v1

| Item | Reason |
| --- | --- |
| `down` files, automatic renames, typed data steps | As revision 1 |
| `DEFINE INDEX .. CONCURRENTLY` | The result of a build comes later; the runner must poll `INFO FOR INDEX` |
| `ALTER TABLE .. REMOVE UNDECLARED FIELDS` | Not needed at level 4; its background job blocked a later index in my test |
| Wait for a 4.0 background migration to finish | An index in the next section worked at once in my test (5k and 50k rows). The runner reads `INFO FOR TABLE .. migrations` only to report |
| A level-3 `V4` variant | One extra target for a short transition. Raise the level instead |

## 6. Changes to the current implementation

| Item | Location | Action | Reason |
| --- | --- | --- | --- |
| Diff engine, key (kind, name, table), removals in reverse, `IF EXISTS` | `src/Schema.roc:626-656` | Keep | Correct; the old side is already text |
| Only changed statements are emitted | same (`changed` keeps lines whose text differs) | Keep. It is the 3.x guarantee | Measured costs in 2.4 |
| `Step` type | `src/Schema.roc:620` | Add `Migrate({ table, path, using, fallback })`, `Rebuild(index)`, `Commit` (a section split), `Edit(Str)` (a marker) | 4.0 statements and sections |
| `Fill` and `UPDATE .. UNSET` | `src/Surreal.roc` `statements` | Keep for `V3`; for `V4` write `MIGRATE` and no unset | 2.3 |
| One transaction for all steps | `src/Surreal.roc` `prepare`, `README.md:1539` | Change to one transaction for each section | 4.0 refuses an index with writes or migrations on its table in one transaction (verified) |
| Index after a fill in the same transaction | today's order: define, fill, later defines | Move indexes on touched tables to section 2 | Today's order fails on 4.0 when a migration adds a filled field and an index on one table |
| `Surreal.migration(old : List(Defined), new)` | `src/Surreal.roc:1795` | Change to `Surreal.plan(snapshot : Str, new, target)` | No old modules; the target |
| `Migration` (the diff) | same | Rename to `Plan`; `Migration` becomes the named file | |
| `to_script` with `BEGIN` / `COMMIT` | same | Change to `to_file` with sections; the runner adds the transactions | |
| `Surreal.schema` | `src/Surreal.roc:1787` | Keep the text (`DEFINE .. OVERWRITE`): it is the snapshot and the body of `0001_init`. Docs: do not run it at each start; on 3.x every run rebuilds every index and view | 2.4 |
| Docs and examples that run the schema at start | `examples/client.roc` `script!` calls, README | Keep in tests (fresh databases); add `migrate!` to an example | |
| Warnings | `migration_steps` | Add the list in 5.4 | Lint |
| History, runner, probe | new | Add `migrate!`, `baseline!`, `_reify_migration`, the `INFO FOR DB` probe | 5.3, 5.5 |
| `push!`, `drift!` | new | Add; `push!` keeps `_reify_schema:current` | 3.x cost rule in dev too |
| "A down migration is `Surreal.migration(new, old)`" | `docs/schema.md:460`, `README.md:1542` | Remove | |
| "Keep the old list in a module" | `docs/schema.md:403`, `:468`, `README.md:1501` | Remove; explain the snapshot | |
| Test servers | `tests/` fixtures recorded on 3.3.4 | Add 4.0.0 recordings for the migration tests; keep 3.3.5 as the floor | Both lines are supported |

## 7. Open questions for the user

| # | Question | Default |
| --- | --- | --- |
| 1 | Is the target an explicit app constant (`V3` / `V4`), checked against the server at `migrate!`, and not found by a probe at plan time? | Yes. The plan is pure and the file is reviewed for one target. Default constant in examples: `V4` |
| 2 | `Surreal.schema` keeps its `DEFINE .. OVERWRITE` text (snapshot and first migration), with docs that forbid it at each start on 3.x? Or print plain `DEFINE`, so that a second run fails and not rebuilds? | Keep `OVERWRITE`; the docs and `migrate!` lead users away from the start-time run |
| 3 | On 4.0, blocking index builds in v1 (writes wait up to 60 s), with `CONCURRENTLY` later? | Yes, blocking in v1 |
| 4 | Squash with `replaces` in v1, because the move from `V3` to `V4` needs a `V4` baseline for fresh databases? | Yes, in v1 |
| 5 | A plan that cannot pick a value (required field with no default, a narrowed type with no default) writes `-- reify: edit` and the runner refuses the file until a person edits it? | Yes |

## 8. Decisions (user, 2026-11-05)

| # | Question | Decision |
| --- | --- | --- |
| 1 | How the app picks the dialect of generated files | An app constant, default `V4`. Each file records it in its header. `migrate!` reads the server level once with `INFO FOR DB` and refuses a file the server cannot run. |
| 2 | `Surreal.schema` with OVERWRITE | Keep it as the snapshot format and the first migration. Docs say: do not run it at each start; run only `migrate!`. |
| 3 | Index builds | Blocking in v1. `CONCURRENTLY` later. (Manager default, agent default.) |
| 4 | Squash | In v1, with a `replaces` list in the baseline header. |
| 5 | A value the plan cannot pick | The plan writes a `-- reify: edit` marker with a placeholder; `migrate!` refuses a file that still has one. |

Measured by the manager on 3.3.4, 200k rows: `DEFINE INDEX OVERWRITE` 1.2-1.8 s per run, `DEFINE INDEX IF NOT EXISTS` 0.02-0.04 s.

## 9. Implementation notes

Date: 2026-11-05. Servers: `surrealdb/surrealdb:v4.0.0` (port 8401) and `v3.3.5` (port 8402), memory engine. Code: `src/Migrate.roc` (pure: sections, file format, runner decisions), `src/Schema.roc` (`migration_steps`, `field_type`, `widens`), `src/Surreal.roc` (`plan`, `Plan`, `check`, `migration`, `Migration`, `Session.migrate!`), `examples/migrate.roc` (dev tool), `tests/MigrateTest.roc`, `tests/MigrateServer.roc`.

### 9.1 Server behavior re-checked

| Claim | 4.0.0 | 3.3.5 |
| --- | --- | --- |
| `(INFO FOR DB).compatibility` | `4`; `3` after `ALTER DATABASE COMPATIBILITY 3` or `DEFINE DATABASE x COMPATIBILITY 3` | `NONE`. The probe is `RETURN <string> ((INFO FOR DB).compatibility ?? 'none')` |
| `MIGRATE EXISTING ROWS AS m USING 1` after `DEFAULT`, `ASSERT`, `PERMISSIONS`, `COMMENT`, `READONLY` | OK, rows read 1 | Not run (`V3` files only) |
| `USING <int> $value FALLBACK 7` | `'5'` is 5, `'zz'` is 7 | |
| `DEFINE INDEX` in a transaction with `MIGRATE` on its table | Refused: "Cannot define an index on table `bin` in the transaction that runs migration `m_w`" | Allowed |
| `DEFINE INDEX` in a transaction with `REMOVE FIELD` of its table | Refused too: `REMOVE FIELD` runs migration "remove note after 5" | Allowed |
| `MIGRATE` on a table that a view reads | Refused: "the view `v` selects from the table" | |
| `REMOVE FIELD` on a table that a view reads | Allowed | |
| `REMOVE INDEX` in a transaction with `MIGRATE` | Allowed | |
| `MIGRATE` on a `REFERENCE` field | Refused: "a REFERENCE field's backlinks hold its stored values". A later narrowing to a required `record<..>` is refused too | |
| `CREATE _m:⟨x⟩` in two concurrent transactions (`SLEEP` inside) | One commits, the other: "Transaction conflict: Write conflict" at `COMMIT` | Same |
| `IF (SELECT VALUE done FROM ONLY _m:⟨x⟩) != 1 { THROW .. }` in a transaction | Cancels it ("An error occurred: .."); concurrent: write conflict | Same |
| `ALTER DATABASE COMPATIBILITY 4` in `BEGIN .. COMMIT` | OK, level 3 to 4 | |
| `REBUILD INDEX IF EXISTS i ON t` | OK | OK |

### 9.2 What differs from section 5, and why

| Item | Design | Built | Reason |
| --- | --- | --- | --- |
| Name of the target type | `Surreal.Target` | `Surreal.MigrationTarget` (`Migrate.Target`) | `Surreal` already has an internal `Target` (the source of a query) |
| `migrate!` result | `Try(Applied, Error)` | `Try({ session, applied }, Error)`; `Applied` also has `adopted`; `server : [V3x, V4x(U64)]` | A session is a value that each request changes (`next_id`) |
| Error tags | Five tags | One tag `Migration({ name, problem })`, `problem : [Changed, OutOfOrder, Edit, Text(Str), Target({ file, server }), Unplanned(List(Str))]` | Fewer breaks of exhaustive matches; `check` uses `Unplanned` |
| `squashed(name, text, replaces)` | A function | `Plan.replacing(names)` writes `replaces` into the header; `migration` reads it | Decision 4 puts `replaces` in the header, so one reader is enough |
| `push!`, `drift!`, `baseline!` | In the API | Not built | Not needed for the required flows. A database that an app set up with `Surreal.schema` at each start adopts the files by running `0001_init` once: it is only `DEFINE .. OVERWRITE` (one rebuild, then never again). Left for later |
| `library` field of the history | In the table | Not stored | The package has no version constant |
| Migration name | `m<NNNN>_<path>` | `m_<first 8 hex of the snapshot hash>_<table>_<path>` | The plan does not know the file name; the snapshot hash differs for each file |
| `V3` type change | Marker, a person writes the `UPDATE` | `UPDATE t SET f = <type> f WHERE f IS NOT NONE` for a scalar type, a marker for others | A value that does not cast fails the section, which rolls back |
| `V3` required field with no default | `= NONE`, fails at once | A `-- reify: edit` line, as on `V4` | Decision 5 |
| `REFERENCE` field that needs a value on `V4` | `MIGRATE` | A `-- reify: edit` line | 4.0 refuses `MIGRATE` on it (9.1) |
| Tables that move an index to section 2 on `V4` | Writes and migrations | Also a dropped field (`REMOVE FIELD`) | 9.1 |
| Changed analyzer | `REBUILD INDEX` on `V4` | `REBUILD INDEX` (section 2) on both targets | It exists on 3.3.5, and an unchanged index is not sent again |
| Probe after `ALTER DATABASE COMPATIBILITY 4` | Not said | `decide` takes a file that has the statement as raising the level for the later files | One probe, and the check of all targets before anything runs |
| `V3` file that fails at level 4 | Error says "squash" | The plain `Server` error of the section | The runner cannot tell this failure from others |
| Two runners | Retry on conflict | After a failed section, the runner reads the history: when it shows the section done, it goes on; else the error stands. The bootstrap request is tried up to 3 times on `Conflict` | Each failure caused by another runner comes after that runner committed, so the re-read always sees it |
| Index and write in one section | "the runner checks this from the text" | `Surreal.migration` checks it for `V4` files by the first words of each line (keywords in any case, table names as written) | A statement over several lines is checked by its first line only |
| `Plan.prepare` | `List(Prepared({}))` | `Try(List(Prepared({})), Error)`; a plan with no statement has no section | A plan with a `-- reify: edit` placeholder must not run |

### 9.3 Compiler issue found

`Str.with_ascii_uppercased` on a part of a text (`split_on`, `trim`) changed the whole text in a build with `--opt=speed` (roc nightly in use, 2026-11): the `replaces` names of a header came back in capitals, so a squashed file was run and not recorded. The interpreter and `--opt=dev` were correct. The fix is in roc `reify` `2bca002367`, so `Migrate.upper` is removed. The checksum is still computed before any other work on the text.

### 9.4 Tests, and the breaks that each one catches

`tests/MigrateTest.roc` (pure) and `tests/MigrateServer.roc` (run by `tests/check.py`, also with `--migrations` for one server). Each break below was applied to `src/Migrate.roc`, the test failed, and the code was restored.

| Break | Caught by |
| --- | --- |
| Index of a migrated table in section 1 | 14 unit expects; on 4.0 the file is refused by `Surreal.migration` (index and write in one section) |
| `V4` fill written as a `V3` `UPDATE` | 5 unit expects; on 4.0 the server refuses the field ("add MIGRATE EXISTING ROWS") |
| No cast for a type change | 2 unit expects; on 4.0 the file has an edit line and is refused |
| No `-- reify: edit` refusal, no `BEGIN` refusal, no index-and-write check | 1 unit expect each |
| No checksum check, no out-of-order check, no resume from `done + 1` | 1 unit expect each |
| No adopt of a squashed file | 3 unit expects; server: "squash: 0005_base recorded, not run" |
| No target check | 2 unit expects; server on 4.0 at level 3: "level: a V4 file is refused" |
| Applied files run again from section 1 | 3 unit expects; server: the second run sent 9 messages, not 1 (each message prints `sent`, `check.py` counts them between two marks) |
| `KeepData` snapshot without the dropped field | 1 unit expect |
| No lock (`UPSERT` for `CREATE`, `RETURN` for `THROW`) | Race on 4.0: counter `b` was 2. On 3.3.5 the same break passed once: the race depends on timing, so the test can miss it |
