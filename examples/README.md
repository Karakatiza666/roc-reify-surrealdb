# Examples

Run each one from the repository root. `roc` is the fork's compiler.

SurrealDB 4.0.1 for the apps that talk to a server:

```sh
docker run --rm -d --name surreal-roc -p 8000:8000 surrealdb/surrealdb:v4.0.1 start --user root --pass root memory
```

| File | Platform | What it shows | How to run it |
| --- | --- | --- | --- |
| `main.roc` | none | A veterinary clinic. Rows as Roc records, the schema with its constraints, links and edges, queries with filters, projections, graph paths, groups and totals, writes, and the SurrealQL that each one becomes. The best place to learn the query API. | `roc examples/main.roc` prints the script. No server needed. |
| `clinic/` | none | `Clinic.roc`: helper functions and query fragments that `main.roc` uses, written over open rows. A package, so that `tests/RefactoredTest.roc` imports the same file. | Not run by itself. |
| `monitoring.roc` | none | Database functions made from Roc functions, a time series keyed by kennel and time, a daily view, geometry, read rows that follow links and edges, and live queries with the notices that the Roc Mirror predicts. | `roc examples/monitoring.roc` prints the script. No server needed. |
| `search.roc` | none | Full-text and vector search: an analyzer, a full-text index, a vector index, scores, highlights and nearest-neighbour queries. | `roc examples/search.roc` prints the script. No server needed. |
| `client.roc` | basic-cli | Connecting to SurrealDB, over a WebSocket (`Transport.websocket_timed`, through roc-basic-cli-websocket 0.0.3) or, with `-- --http`, over HTTP. Plain queries and writes, each result read as a Roc type. Sign-up and sign-in of record users. | `roc examples/client.roc`, or `roc examples/client.roc -- --http`. SurrealDB must run on 127.0.0.1:8000, with the tables of `monitoring.roc` loaded (see below). |
| `watch.roc` | basic-cli | Live queries on a session (`Transport.websocket_timed`). Starting a watch, making writes, reading the changes with `next_within!` and a limit of 60 s (a change that does not come is a `FAIL`), and comparing them with what the Roc Mirror predicts. | `roc examples/watch.roc`. Same requirements as `client.roc`. |
| `migrate.roc` | basic-cli | Migrations: the dev tool to copy into an app. `plan NAME` writes the next migration file from the snapshot `db/schema.surql` and the Roc schema, `check` compares them, `squash NAME` writes one file in place of all, `up` applies the files with `session.migrate!`. `db/` holds the snapshot and the files it wrote. | `roc examples/migrate.roc -- plan 0003_name`, `-- check`, `-- up 127.0.0.1:8000`. `up` needs a database at compatibility level 4. `roc test examples/migrate.roc` checks that the snapshot is the schema. |
| `server.roc` | basic-webserver | A web server that runs a typed query on SurrealDB for each request, over a WebSocket (`Transport.websocket`, through roc-basic-webserver-websocket 0.0.2, which has no `receive_within!`). `GET /readings?min_pulse=N`. | `roc examples/server.roc &`, then `curl 'http://127.0.0.1:8001/readings?min_pulse=120'`. Same requirements as `client.roc`. It listens on port 8001. |

## Start here

1. `main.roc`, for the schema and query API. Read the Roc code and the script it prints.
2. `client.roc`, to connect from basic-cli and read typed results.
3. `server.roc`, to do the same on basic-webserver.
4. `watch.roc`, for live queries.
5. `monitoring.roc` and `search.roc`, for database functions, time series, geometry and search.

## The `-- roc:` lines and `ok` / `FAIL` lines

These files also serve as tests. `tests/check.py` runs them:

- `main.roc`, `monitoring.roc` and `search.roc` print blocks of SurrealQL. Lines that start with `--` are directives for `tests/check.py`. A `-- roc:` line holds the result that Roc computes with the same functions, which the database must return too. You can skip them when reading.
- `client.roc` and `watch.roc` print one line per check: `ok` when the result from the database agrees with the result that Roc computes, `FAIL` when it does not. They exit with 1 on a `FAIL`.

## The tables of `monitoring.roc`

`client.roc`, `watch.roc` and `server.roc` read the tables that the script of `monitoring.roc` defines. `tests/check.py` loads them into the namespace `roc`, database `roc_surreal`, and leaves them there. To load them:

```sh
python3 tests/check.py "$ROC"
```

It also runs the three apps and checks them. It needs port 8001 free.

## Files that moved to `tests/`

Some files only serve the tests, so they are in `tests/`: `BuiltinsTest.roc` (a coverage table of the builtin mappings), `RefactoredTest.roc` (checks that refactoring `main.roc` does not change its script) and `expected_output.surql` (the script of `main.roc`).
