# roc-reify-surrealdb documentation

`roc-reify-surrealdb` is a SurrealDB ORM for Roc. A row is a Roc record. A table is a `Surreal.Table(row)`. Each query clause, projection and constraint is an ordinary Roc function that the package turns into SurrealQL. The package needs the `reify` fork of the Roc compiler. Stock Roc cannot build it.

This page lists every feature and links to the page that explains it. To install and run a first query, go to [Getting started](getting-started.md).

| Link | What it gives |
| --- | --- |
| [Package README](../README.md) | The pitch, the setup, the internals ("How it is built"), the design limits and the tests |
| [API docs](https://github.com/Karakatiza666/roc-reify-surrealdb/releases/download/0.0.2/package-docs.tar.gz) | `package-docs.tar.gz` of the 0.0.2 release: the signature and the doc comment of each function. Unpack it and open `index.html` |
| [Examples](../examples/README.md) | The runnable apps and the helper package that the pages cite by name |

## Start here

Read these pages in this order. Each page names the example file to read next to it.

| Step | Page | You learn to |
| --- | --- | --- |
| 1 | [Getting started](getting-started.md) | Install the compiler, add the package, print a query and run it |
| 2 | [Row types and data types](data-types.md) | Write row types that map to SurrealDB types |
| 3 | [Tables and schema](schema.md) | Define tables and print the schema script |
| 4 | [Choosing the fields to read](selecting-fields.md) | Write a projection as a Roc function |
| 5 | [Writing queries](queries.md) | Filter, order, group and reuse |
| 6 | [Writing rows](writes.md) | Create, update and delete |
| 7 | [Sessions and typed results](sessions.md) | Connect and read results as Roc types |
| 8 | [Errors](errors.md) | Match on every error |

The other pages cover one topic each: links and edges, live queries, record users, functions, search and escape hatches. The terms "clause", "intrinsic", "mirror function" and "read row" are in the [glossary](getting-started.md#words-used-in-these-pages).

## Pages

| Page | Purpose |
| --- | --- |
| [Getting started](getting-started.md) | Install the compiler, add the package, define a table, print a query, run it, and read the glossary |
| [Row types and data types](data-types.md) | Map Roc types to SurrealDB types: optional fields, defaults, unions, datetimes, time series keys and geometry |
| [Tables and schema](schema.md) | Define tables, constraints, indexes, computed fields, link policies, views, changefeeds and migrations |
| [Choosing the fields to read](selecting-fields.md) | See how a projection function becomes the column list, and how to read through links |
| [Writing queries](queries.md) | Filter, parameterize, order, page, group, total, compose and reuse queries. A query with no parameter takes `ready()` |
| [Ids, links and graph edges](links-and-graphs.md) | Use `Id`, `Link`, read rows, edge tables, graph paths and subqueries over other tables |
| [Writing rows](writes.md) | Create, insert, upsert, update, set, merge, patch and delete rows, and let the server make keys |
| [Sessions and typed results](sessions.md) | Connect over WebSocket or HTTP, run prepared statements, batch, pipeline and use transactions, also from a list |
| [Errors](errors.md) | Know when each error happens and how to match on it |
| [Live queries](live-queries.md) | Watch a query, read its changes, and know what a watch sees and what it does not |
| [Record users and permissions](access.md) | Define an access method, sign users up and in, and set table and field permissions |
| [Functions in clauses](functions.md) | Know which builtins and SurrealDB functions a clause can call, and define database functions |
| [Full-text and vector search](search.md) | Define analyzers and indexes, search, score, highlight and find the nearest rows |
| [Escape hatches and extensions](advanced.md) | Send raw SurrealQL, read every field, extend the translator and test with the Mirror |

## Features

### Connection and sessions

| Feature | Page |
| --- | --- |
| WebSocket transport, `Transport.websocket` | [sessions.md#choose-a-transport](sessions.md#choose-a-transport) |
| WebSocket transport with a read deadline, `Transport.websocket_timed` | [sessions.md#choose-a-transport](sessions.md#choose-a-transport) |
| HTTP transport, `Transport.http`, with a post function of your platform | [sessions.md#use-http](sessions.md#use-http) |
| Adapters for basic-cli and basic-webserver | [getting-started.md#add-the-package](getting-started.md#add-the-package) |
| Logins `Root`, `SignUp`, `SignIn` and `Token` | [sessions.md#log-in](sessions.md#log-in) |
| `Session.open!` and the rules for the session value | [sessions.md#open-a-session](sessions.md#open-a-session) |
| `token`, `invalidate!`, `pushes`, `knowing` and `kill!` | [sessions.md#other-session-calls](sessions.md#other-session-calls) |
| Typed results with `run!` | [sessions.md#run-a-prepared-statement](sessions.md#run-a-prepared-statement) |
| Two statements in one request, `then` | [sessions.md#two-statements-in-one-request](sessions.md#two-statements-in-one-request) |
| Requests in flight together, `send!` and `await!` | [sessions.md#requests-in-flight-together](sessions.md#requests-in-flight-together) |
| Transactions, `begin`, `then` and `commit` | [sessions.md#transactions](sessions.md#transactions) |
| A list of statements in one transaction, `Surreal.transaction` | [sessions.md#a-list-of-statements-in-one-transaction](sessions.md#a-list-of-statements-in-one-transaction) |
| Applying migration files at start, `session.migrate!`, with a history, checksums and resume by section | [schema.md#what-migrate-does](schema.md#what-migrate-does) |
| `Unique` errors with `session.knowing(defs)` | [sessions.md#unique-errors-need-the-schema](sessions.md#unique-errors-need-the-schema) |
| One session for each request on basic-webserver | [sessions.md#sessions-on-basic-webserver](sessions.md#sessions-on-basic-webserver) |
| Script apps that print SurrealQL with no platform | [getting-started.md#add-the-package](getting-started.md#add-the-package) |

### Row types and data types

| Feature | Page |
| --- | --- |
| Alias rows and nominal rows | [data-types.md#row-types](data-types.md#row-types) |
| The map from Roc types to SurrealDB types | [data-types.md#how-roc-types-map-to-surrealdb-types](data-types.md#how-roc-types-map-to-surrealdb-types) |
| Integer ranges kept as `ASSERT` | [data-types.md#how-roc-types-map-to-surrealdb-types](data-types.md#how-roc-types-map-to-surrealdb-types) |
| Optional fields, `f ?: T`, `.?f`, `??` and `is_ok` | [data-types.md#optional-fields](data-types.md#optional-fields) |
| Defaults with `??`, `default` and `default_by` | [data-types.md#default-values](data-types.md#default-values) |
| Tag unions with `kind` | [data-types.md#tag-unions](data-types.md#tag-unions) |
| `Surreal.Datetime` and `Surreal.datetime` | [data-types.md#datetimes-and-durations](data-types.md#datetimes-and-durations) |
| Conversion to unix nanoseconds, `to_unix_nanos`, `from_unix_nanos` | [data-types.md#datetimes-and-durations](data-types.md#datetimes-and-durations) |
| `Duration` and `Time.secs` and the other constructors | [data-types.md#durations](data-types.md#durations) |
| Time series keys, `TimeKey`, `time_key`, `series()` and `time()` | [data-types.md#time-series-keys](data-types.md#time-series-keys) |
| Geometry, `Point`, `Line`, `Polygon` and four more | [data-types.md#geometry](data-types.md#geometry) |
| `Surreal.point`, `lon`, `lat` and `to_geometry` | [data-types.md#geometry](data-types.md#geometry) |

### Schema

| Feature | Page |
| --- | --- |
| `Surreal.table` | [schema.md#tables-relations-and-views](schema.md#tables-relations-and-views) |
| `Surreal.relation` with typed ends | [schema.md#tables-relations-and-views](schema.md#tables-relations-and-views) |
| `Surreal.view` | [schema.md#tables-relations-and-views](schema.md#tables-relations-and-views) |
| `define()`, `done()` and the `Surreal.schema` script | [schema.md#build-the-schema](schema.md#build-the-schema) |
| Statement order and `OVERWRITE` | [schema.md#build-the-schema](schema.md#build-the-schema) |
| Checks of the whole list of definitions | [schema.md#build-the-schema](schema.md#build-the-schema) |
| `check`, `assert` and `assert_each` | [schema.md#constraints](schema.md#constraints) |
| A check over several fields as the `ASSERT` of one field, or as an event | [schema.md#constraints](schema.md#constraints) |
| `unique` and `index`, also on several fields and on edge ends | [schema.md#unique-keys-and-indexes](schema.md#unique-keys-and-indexes) |
| `computed`, `readonly`, `created_now` and `comment` | [schema.md#computed-read-only-and-timestamp-fields](schema.md#computed-read-only-and-timestamp-fields) |
| Existence checks of links and ids at any depth | [schema.md#links-and-delete-policies](schema.md#links-and-delete-policies) |
| Delete policies `Reject`, `Cascade`, `Unset` and `Ignore` | [schema.md#links-and-delete-policies](schema.md#links-and-delete-policies) |
| `on_delete` and `on_delete_at` | [schema.md#links-and-delete-policies](schema.md#links-and-delete-policies) |
| `REFERENCE` or an event, by the place of the link | [schema.md#how-each-shape-works](schema.md#how-each-shape-works) |
| Seed order and cycles of required links | [schema.md#order-of-the-rows](schema.md#order-of-the-rows) |
| Grouped views with `define_as` | [schema.md#views](schema.md#views) |
| `changefeed` | [schema.md#changefeeds](schema.md#changefeeds) |
| `define_read()` for a read row | [schema.md#read-rows](schema.md#read-rows) |
| Full-text and vector indexes in `define()` | [schema.md#indexes-for-search](schema.md#indexes-for-search) |
| `permit`, `permit_full`, `permit_field` and `deny_field` | [schema.md#permissions](schema.md#permissions) |
| Migrations: `Surreal.plan(snapshot, schema, target)` writes a reviewed `.surql` file from the committed snapshot; `V4` (`MIGRATE EXISTING ROWS`, sections) or `V3` | [schema.md#migrations](schema.md#migrations) |
| The dev tool `examples/migrate.roc`: `plan`, `check`, `squash`, `up` | [schema.md#flows](schema.md#flows) |
| `Surreal.check(snapshot, schema)` in an `expect`, for CI | [schema.md#the-calls](schema.md#the-calls) |
| A squashed file with `replaces`, and the move from SurrealDB 3 to 4 | [schema.md#move-from-surrealdb-3-to-4](schema.md#move-from-surrealdb-3-to-4) |
| `KeepData` and `DropData`, `dropped`, `warnings`, `to_file`, `snapshot` and `prepare` of a plan, `-- reify: edit` lines | [schema.md#what-a-plan-writes](schema.md#what-a-plan-writes) |

### Choosing fields

| Feature | Page |
| --- | --- |
| A projection as a Roc function, `select(f)` | [selecting-fields.md#a-projection-is-a-function](selecting-fields.md#a-projection-is-a-function) |
| Only the fields that the function reads are fetched | [selecting-fields.md#only-the-fields-you-read-are-fetched](selecting-fields.md#only-the-fields-you-read-are-fetched) |
| Nested records read by path | [selecting-fields.md#nested-records](selecting-fields.md#nested-records) |
| Optional fields in a projection | [selecting-fields.md#optional-fields](selecting-fields.md#optional-fields) |
| Later clauses read the type of the result | [selecting-fields.md#the-result-type-limits-the-next-clauses](selecting-fields.md#the-result-type-limits-the-next-clauses) |
| One value for each row, `select_value` | [selecting-fields.md#one-value-per-row](selecting-fields.md#one-value-per-row) |
| The whole row, `select(\|r\| r)` | [selecting-fields.md#the-whole-row](selecting-fields.md#the-whole-row) |
| The whole row with no `select`: `Query.prepare`, `prepare_one`, `live` and `ready` | [selecting-fields.md#the-whole-row](selecting-fields.md#the-whole-row) |
| Reads through a link with `get()`, with no `FETCH` | [selecting-fields.md#read-through-a-link](selecting-fields.md#read-through-a-link) |
| Read rows as a fetch plan | [selecting-fields.md#read-rows-as-a-fetch-plan](selecting-fields.md#read-rows-as-a-fetch-plan) |
| Ids in results | [selecting-fields.md#ids-in-results](selecting-fields.md#ids-in-results) |
| Field reads that decide what a live query watches | [selecting-fields.md#how-field-reads-decide-what-a-live-query-watches](selecting-fields.md#how-field-reads-decide-what-a-live-query-watches) |

### Queries

| Feature | Page |
| --- | --- |
| `Surreal.from` and `table.at(id)` | [queries.md#start-a-query](queries.md#start-a-query) |
| `filter` with Roc operators and your own helpers | [queries.md#filter-rows](queries.md#filter-rows) |
| A query with no parameter, `ready()`, `ready_one()` and `ready_live(defs)` | [queries.md#start-a-query](queries.md#start-a-query) |
| Parameters with `filter_by` and `prepare(params)` | [queries.md#pass-parameters](queries.md#pass-parameters) |
| Values from around the function: clauses, keys, `limit` and `start` | [queries.md#use-values-from-around-the-function](queries.md#use-values-from-around-the-function) |
| `match`, `if`, `.?` and `??` in a clause | [queries.md#match-on-unions-and-optional-fields](queries.md#match-on-unions-and-optional-fields) |
| Key comparison, and `prepare_one` for one row | [queries.md#compare-keys](queries.md#compare-keys) |
| `order_by`, `start` and `limit` with the order checked by types | [queries.md#order-and-page-results](queries.md#order-and-page-results) |
| `filter` after `select`, `limit` and `aggregate` | [queries.md#filter-the-results-of-a-projection](queries.md#filter-the-results-of-a-projection) |
| `query()`: the result rows as a new query | [queries.md#query-the-results-again](queries.md#query-the-results-again) |
| `group_by` and `aggregate` | [queries.md#group-rows](queries.md#group-rows) |
| `totals`, one row for all rows | [queries.md#totals-of-all-rows](queries.md#totals-of-all-rows) |
| `between`: a range of a time series | [queries.md#read-a-range-of-a-time-series](queries.md#read-a-range-of-a-time-series) |
| Helpers over open rows and query fragments | [queries.md#reuse-query-parts](queries.md#reuse-query-parts) |
| One complex query built in steps | [queries.md#build-a-complex-query-step-by-step](queries.md#build-a-complex-query-step-by-step) |
| `to_surql`, `statement().to_script()` and `request()` | [queries.md#get-the-surrealql-text](queries.md#get-the-surrealql-text) |

### Ids, links and graphs

| Feature | Page |
| --- | --- |
| `Id(row)`, `table.id`, `key()` and `table()` | [links-and-graphs.md#ids](links-and-graphs.md#ids) |
| `Link(row)`, `table.link` and `Surreal.fetched` | [links-and-graphs.md#links](links-and-graphs.md#links) |
| `link.id` and `link.id()` | [links-and-graphs.md#the-id-of-a-link](links-and-graphs.md#the-id-of-a-link) |
| Read rows with `Linked`, `Out` and `In` | [links-and-graphs.md#read-rows](links-and-graphs.md#read-rows) |
| Constructors `Surreal.linked`, `out_edges` and `in_edges` for test data | [links-and-graphs.md#rules-for-a-read-row](links-and-graphs.md#rules-for-a-read-row) |
| Edge tables with `Surreal.relation` | [links-and-graphs.md#edge-tables](links-and-graphs.md#edge-tables) |
| Write and query edges | [links-and-graphs.md#write-edges](links-and-graphs.md#write-edges) |
| `outgoing` and `incoming` | [links-and-graphs.md#traverse-edges](links-and-graphs.md#traverse-edges) |
| `and_outgoing` and `and_incoming` | [links-and-graphs.md#traverse-edges](links-and-graphs.md#traverse-edges) |
| Graph paths of any length, `edges_from` and `edges_to` | [links-and-graphs.md#graph-paths](links-and-graphs.md#graph-paths) |
| `keep_if`, `drop_if`, `map` and `join_map` over edges as one `->edge[WHERE ..]->table` path | [links-and-graphs.md#graph-paths](links-and-graphs.md#graph-paths) |
| `table.rows()`: correlated counts and semi joins | [links-and-graphs.md#read-other-tables-in-a-clause](links-and-graphs.md#read-other-tables-in-a-clause) |

### Writes

| Feature | Page |
| --- | --- |
| `create`, `insert`, `upsert` and `replace` | [writes.md#write-whole-rows](writes.md#write-whole-rows) |
| `edit` with `Create`, `Replace` and `Delete` | [writes.md#write-one-change-with-edit](writes.md#write-one-change-with-edit) |
| Writes on edge tables, `RELATE` and `INSERT RELATION` | [writes.md#edge-tables](writes.md#edge-tables) |
| Keys that the server makes, `create_new` and `insert_new` | [writes.md#keys-that-the-server-makes](writes.md#keys-that-the-server-makes) |
| `update`, `update_by`, `update_at` and `update_at_by` | [writes.md#update-rows](writes.md#update-rows) |
| `set`, `set_by`, `set_at` and `set_at_by` | [writes.md#set-only-some-fields](writes.md#set-only-some-fields) |
| `merge`, `merge_at` and `upsert_merge_at` | [writes.md#merge-a-record](writes.md#merge-a-record) |
| JSON Patch with `patch_at` and `patch_ops_at` | [writes.md#apply-json-patch-ops](writes.md#apply-json-patch-ops) |
| `insert_or_update` | [writes.md#insert-or-update](writes.md#insert-or-update) |
| `delete`, `delete_by` and `delete_at` | [writes.md#delete-rows](writes.md#delete-rows) |
| `Write.prepare`, `ready` and `to_surql` | [writes.md#run-a-write](writes.md#run-a-write) |
| Inline patches and conditions with `update_by`, `set_at` and `delete_by` | [writes.md#update-rows](writes.md#update-rows) |
| `Rand` in defaults, computed fields and updates | [writes.md#random-values-in-writes](writes.md#random-values-in-writes) |

### Live queries

| Feature | Page |
| --- | --- |
| `live(params, definitions)`, `ready_live(definitions)` and `session.live!` | [live-queries.md#start-a-watch](live-queries.md#start-a-watch) |
| `next!` and `Change`: `Added`, `Updated`, `Removed` | [live-queries.md#read-changes](live-queries.md#read-changes) |
| `next_within!` with a deadline | [live-queries.md#wait-with-a-deadline](live-queries.md#wait-with-a-deadline) |
| `stream` | [live-queries.md#read-as-a-stream](live-queries.md#read-as-a-stream) |
| `kill!` | [live-queries.md#stop-a-watch](live-queries.md#stop-a-watch) |
| What a watch sees: rows, edges, linked tables and `rows()` | [live-queries.md#what-a-live-query-watches](live-queries.md#what-a-live-query-watches) |
| Only the fields that the clauses read | [live-queries.md#only-the-fields-that-the-clauses-read](live-queries.md#only-the-fields-that-the-clauses-read) |
| `live_raw` and `Event` | [live-queries.md#raw-events](live-queries.md#raw-events) |
| `live_diff`, `Patch` and `DiffView` | [live-queries.md#patches-of-stored-rows](live-queries.md#patches-of-stored-rows) |
| The order of notices on SurrealDB 3.3.4 | [live-queries.md#order-of-notices](live-queries.md#order-of-notices) |
| `Surreal.Mirror` to predict notices | [live-queries.md#predict-notices-in-roc](live-queries.md#predict-notices-in-roc) |

### Record users and permissions

| Feature | Page |
| --- | --- |
| `Surreal.access` and `Access.define` | [access.md#define-an-access-method](access.md#define-an-access-method) |
| `Hash.argon2` and `argon2_matches` in a signup and a signin | [access.md#define-an-access-method](access.md#define-an-access-method) |
| `token_for` and `session_for` | [access.md#define-an-access-method](access.md#define-an-access-method) |
| `sign_up`, `sign_in`, `Token` and `invalidate!` | [access.md#sign-up-and-sign-in](access.md#sign-up-and-sign-in) |
| Table permissions, `permit` and `permit_full` | [access.md#table-permissions](access.md#table-permissions) |
| Field permissions, `permit_field` and `deny_field` | [access.md#field-permissions](access.md#field-permissions) |
| `users.auth()`, `Auth.access()` and `Auth.expires()` in a clause | [access.md#the-record-user-in-a-clause](access.md#the-record-user-in-a-clause) |
| What each user gets, from a real run | [access.md#what-happens-for-each-user](access.md#what-happens-for-each-user) |

### Functions

| Feature | Page |
| --- | --- |
| The rule for a call in a clause, and your own functions | [functions.md#what-you-can-call-in-a-clause](functions.md#what-you-can-call-in-a-clause) |
| Mirror functions and intrinsics | [functions.md#mirror-functions-and-intrinsics](functions.md#mirror-functions-and-intrinsics) |
| Roc builtins with a SurrealQL form | [functions.md#roc-builtins](functions.md#roc-builtins) |
| `Text` | [functions.md#text](functions.md#text) |
| `Hash` | [functions.md#hash](functions.md#hash) |
| `Array` | [functions.md#array](functions.md#array) |
| `Time` | [functions.md#time](functions.md#time) |
| `Math`, with `mean` and `mean_dec` | [functions.md#math](functions.md#math) |
| `Rand` and where it is allowed | [functions.md#rand-and-where-it-is-allowed](functions.md#rand-and-where-it-is-allowed) |
| `Vector` | [functions.md#vector](functions.md#vector) |
| `Geo` | [functions.md#geo](functions.md#geo) |
| `Auth` | [functions.md#auth](functions.md#auth) |
| `Id.table` | [functions.md#idtable](functions.md#idtable) |
| Database functions, `db_fn`, `function` and `call1` to `call3` | [functions.md#database-functions](functions.md#database-functions) |

### Full-text and vector search

| Feature | Page |
| --- | --- |
| Analyzers, tokenizers and filters | [search.md#analyzers](search.md#analyzers) |
| `Analyzer.tokens` and `matches` in Roc | [search.md#the-roc-meaning-of-an-analyzer](search.md#the-roc-meaning-of-an-analyzer) |
| Full-text indexes with `text_index` | [search.md#full-text-indexes](search.md#full-text-indexes) |
| `search`, `Hit`, `score`, `highlight` and `offsets` | [search.md#search](search.md#search) |
| Vector indexes with `vector_index` | [search.md#vector-indexes](search.md#vector-indexes) |
| `nearest` with `Exact` and `Approx`, and `near.distance()` | [search.md#nearest-rows](search.md#nearest-rows) |
| Vector functions in a filter | [search.md#vector-functions](search.md#vector-functions) |

### Errors

| Feature | Page |
| --- | --- |
| One error type, `Surreal.Error`, and its tags | [errors.md#one-error-type](errors.md#one-error-type) |
| `Unsupported` and `BadSchema` at build time | [errors.md#build-time-errors](errors.md#build-time-errors) |
| `ServerError` tags and the schema clause behind each | [errors.md#server-errors](errors.md#server-errors) |
| Matching on an error | [errors.md#match-on-an-error](errors.md#match-on-an-error) |
| Connection errors | [errors.md#connection-errors](errors.md#connection-errors) |
| `Decode` and `Wire` | [errors.md#decode-and-wire](errors.md#decode-and-wire) |
| `Aborted` in a transaction | [errors.md#errors-in-transactions](errors.md#errors-in-transactions) |
| `Assert` or `Check`: the place of a check over several fields | [errors.md#which-schema-clause-gives-which-error](errors.md#which-schema-clause-gives-which-error) |

### Escape hatches and extensions

| Feature | Page |
| --- | --- |
| Raw SurrealQL with `Unchecked.query!` | [advanced.md#raw-surrealql](advanced.md#raw-surrealql) |
| `Unchecked.decode` and `Unchecked.result` | [advanced.md#read-the-reply](advanced.md#read-the-reply) |
| `Unchecked.select_star` and `Unchecked.fetch` | [advanced.md#select-every-field](advanced.md#select-every-field) |
| `Unchecked.id` | [advanced.md#ids-by-table-name](advanced.md#ids-by-table-name) |
| `Surreal.extension` and `Query.filter_with` | [advanced.md#extend-the-translator](advanced.md#extend-the-translator) |
| Captured values of your own type | [advanced.md#captured-values-of-your-type](advanced.md#captured-values-of-your-type) |
| `Table.edit`, `ref`, `group_ref` and `Mirror.literal` | [advanced.md#test-with-the-mirror](advanced.md#test-with-the-mirror) |
| Check blocks for `tests/check.py` | [advanced.md#check-blocks-for-checkpy](advanced.md#check-blocks-for-checkpy) |

## Not supported

Each row links to the `Limits` table of its page. The table gives what to do instead.

| Not supported | Limits |
| --- | --- |
| Stock Roc | [getting-started.md#limits](getting-started.md#limits) |
| Opaque rows, `I128` and `U128` fields, a `Duration` as a column | [data-types.md#limits](data-types.md#limits) |
| A `kind` field in a union arm, and `??` in the record of a union arm | [data-types.md#limits](data-types.md#limits) |
| A geometry literal in a clause (other than a point), and list forms such as `CONTAINSALL` | [data-types.md#limits](data-types.md#limits) |
| A `Link` in a time series key, and `Id` access to a time series row | [data-types.md#limits](data-types.md#limits) |
| A down migration, a rename and a compare with the live database in a migration plan, and two tables with an equal row type in one schema | [schema.md#limits](schema.md#limits) |
| A unique key or an index through an optional record or a union arm | [schema.md#limits](schema.md#limits) |
| `Unset` for a required link, and a cycle of required links | [schema.md#limits](schema.md#limits) |
| A view with a range, a median, a rule or a write, and a typed read of a changefeed | [schema.md#limits](schema.md#limits) |
| A projection that builds a union payload from a whole record, or selects a self-linked read row | [selecting-fields.md#limits](selecting-fields.md#limits) |
| `SELECT *` and `FETCH` in the typed API | [selecting-fields.md#limits](selecting-fields.md#limits) |
| A clause that captures a local value, and a captured `Link` | [queries.md#limits](queries.md#limits) |
| `order_by` of more than a column, `HAVING`, `group_by(\|_\| {})` and `median` in `totals` | [queries.md#limits](queries.md#limits) |
| A per-row list sum inside `aggregate` or `totals` | [queries.md#limits](queries.md#limits) |
| More than one `between` in a query | [queries.md#limits](queries.md#limits) |
| An alias row that links to itself, and `get()` on a `Linked` | [links-and-graphs.md#limits](links-and-graphs.md#limits) |
| A write of a read row, and `and_outgoing` for three or more edge tables | [links-and-graphs.md#limits](links-and-graphs.md#limits) |
| `edges_from` and `edges_to` in plain Roc code, and a graph path through an `array::` call | [links-and-graphs.md#limits](links-and-graphs.md#limits) |
| A record update that changes the type of a field | [writes.md#limits](writes.md#limits) |
| `merge` of a union, a patch that branches around the row, and `insert_or_update` on an edge table | [writes.md#limits](writes.md#limits) |
| A part of a transaction that reads a key made by another part | [writes.md#limits](writes.md#limits) |
| `THROW` and `CANCEL` in the typed API, and a retry of `Conflict` | [sessions.md#limits](sessions.md#limits) |
| A session on a script app, and live queries over HTTP | [sessions.md#limits](sessions.md#limits) |
| Typed tests of `Parse`, `Invalid`, `Thrown` and `Timeout` | [errors.md#limits](errors.md#limits) |
| A live query with `group_by`, `order_by`, `limit`, `start`, `between`, a subquery, a search or `nearest` | [live-queries.md#limits](live-queries.md#limits) |
| A watch of the edges of a linked row, and a watch of a `LIVE` in raw text | [live-queries.md#limits](live-queries.md#limits) |
| Access methods `ON NAMESPACE`, `ON ROOT`, `JWT` and `BEARER`, and `AUTHENTICATE` | [access.md#limits](access.md#limits) |
| A token that `invalidate!` ends | [access.md#limits](access.md#limits) |
| Refused builtins, such as `Str.len`, `from_str` and `to_str` on a float | [functions.md#limits](functions.md#limits) |
| `Rand` in a query clause, a check or a signin, and an intrinsic in a database function | [functions.md#limits](functions.md#limits) |
| A function as a value, and a function that calls itself in a clause | [functions.md#limits](functions.md#limits) |
| Left-out SurrealDB functions, such as `bcrypt`, `array::sort` and `vector::add` | [functions.md#functions-that-are-not-available](functions.md#functions-that-are-not-available) |
| A search plus `nearest` in one query, a second `search`, `MTREE` and `search::analyze` | [search.md#limits](search.md#limits) |
| A score, a highlight or a distance as a Roc value | [search.md#limits](search.md#limits) |
| An extension for a column or a schema clause | [advanced.md#limits](advanced.md#limits) |
| Mirror calls for `live_diff` | [advanced.md#limits](advanced.md#limits) |
