# Getting started

This page takes you from an empty folder to a typed query that runs on a SurrealDB server. You install the compiler, add the package, define a table, print the SurrealQL of a query, and run it.

## What the package does

A row is a Roc record. A table is a `Surreal.Table(row)` over that record type. A query clause is an ordinary Roc function over the row. You pass the function to a builder method such as `filter` or `select`. The package turns it into SurrealQL. You also call the same function on your own rows.

```
Roc function --> Code(f) --> translator --> SurrealQL --> server --> typed Roc rows
 (clause)      (compiler)    (package)       (text)      (SurrealDB)   (your types)
```

| Step | Who does it | What happens |
| --- | --- | --- |
| Write the function | You | A normal function, such as `in_city : CityParam, Owner -> Bool` |
| Pass it to a builder method | You | The method takes it as `Code(f)`. The compiler describes the function and checks it as usual |
| Translate | The package | The description becomes SurrealQL text when you call `prepare` or `to_surql` |
| Run | A session | `session.run!(prepared)` sends the text and reads the reply as your Roc type |

The function stays a Roc function. A test, a seed list and your own code can call it on records.

## Requirements

| Need | Value |
| --- | --- |
| Compiler | The `reify` branch of [Karakatiza666/roc](https://github.com/Karakatiza666/roc), at the commit in `.roc-version` (`reify-0aedb1ae0046480f8442c97cf9138534659e8ab2` from release 0.0.3) |
| Zig, to build the compiler | 0.17.0 |
| Database, to run queries | SurrealDB 3.3.4 |

Stock Roc has no `Code` type. The package does not compile with it. The compiler feature is described in [reifying.md](https://github.com/Karakatiza666/roc/blob/reify/docs/langref/reifying.md) of the compiler repository.

Build the compiler and point `ROC` at it:

```sh
git clone https://github.com/Karakatiza666/roc.git
cd roc
git checkout 0aedb1ae0046480f8442c97cf9138534659e8ab2
zig build roc
export ROC=$PWD/zig-out/bin/roc
```

To start a local server:

```sh
docker run --rm -d --name surreal-roc -p 8000:8000 surrealdb/surrealdb:v3.3.4 start --user root --pass root memory
```

## Add the package

Name the package in the header of your app. Only the module `Surreal` is public.

| Where | What to write |
| --- | --- |
| Release | `surreal: "https://github.com/Karakatiza666/roc-reify-surrealdb/releases/download/0.0.2/<hash>.tar.zst"` |
| Checkout | `surreal: "/path/to/roc-reify-surrealdb/src/main.roc"` |

The release notes of each [release](https://github.com/Karakatiza666/roc-reify-surrealdb/releases) show the full URL with its hash. `scripts/bundle.sh 0.0.1` prints it too.

The package brings roc-cbor and roc-websocket. Name roc-cbor in your own header only if your code uses `Cbor`.

An app with no platform can print SurrealQL and needs no server. It is a script app:

```roc
app [main!] { surreal: "/path/to/roc-reify-surrealdb/src/main.roc" }

import surreal.Surreal
```

To run a query, the app needs a platform and the WebSocket adapter of that platform:

| Platform | Adapter package | Transport constructor |
| --- | --- | --- |
| basic-cli 0.27.0 | roc-basic-cli-websocket 0.0.4 | `Surreal.Transport.websocket_timed` |
| basic-webserver 0.21.0 | roc-basic-webserver-websocket 0.0.3 | `Surreal.Transport.websocket` |

The full headers are in `examples/client.roc` (basic-cli) and `examples/server.roc` (basic-webserver). [Sessions](sessions.md#choose-a-transport) explains the transports.

## Define a table

Write the row type as a record. Make the table with `Surreal.table(name)` and give it a type annotation. The annotation fixes the row type.

```roc
# Fragment: uses `import surreal.Surreal` from a script app.
Address : { city : Str, line : Str }

Owner : { id : Str, name : Str, phone ?: Str, address : Address }

owners : Surreal.Table(Owner)
owners = Surreal.table("owner")
```

From `examples/main.roc`, `owners`. The example `Owner` has more fields.

A field `phone ?: Str` is optional. The key of a row is the field `id : Str`.

Call `define()` on the table to describe its schema. Each clause is a Roc function over the row. End with `done()`:

```roc
# Fragment: uses `owners` from above.
owner_def : Surreal.Defined
owner_def =
	owners.define()
		.unique(|o| o.name)
		.assert(|o| o.name, |n| n != "")
		.done()

schema_text : Try(Str, Surreal.Error)
schema_text = Surreal.schema([owner_def])
```

`owner_def` in `examples/main.roc` has more clauses. `Surreal.schema` takes the list of every definition and gives the script. The script from a real run:

```surql
DEFINE TABLE OVERWRITE owner SCHEMAFULL;
DEFINE FIELD OVERWRITE address ON owner TYPE object;
DEFINE FIELD OVERWRITE address.city ON owner TYPE string;
DEFINE FIELD OVERWRITE address.line ON owner TYPE string;
DEFINE FIELD OVERWRITE name ON owner TYPE string ASSERT $value != '';
DEFINE FIELD OVERWRITE phone ON owner TYPE option<string>;
DEFINE INDEX OVERWRITE owner_name_unique ON owner FIELDS name UNIQUE;
```

The record types give the `DEFINE FIELD` lines. The clauses give `ASSERT` and `UNIQUE`. See [Tables and schema](schema.md) and [Row types and data types](data-types.md).

## Build a query

Start from the table with `Surreal.from`. Add clauses. Each one is a function that you can name and test.

| Call | Takes | Gives |
| --- | --- | --- |
| `Surreal.from(table)` | A `Table(row)` | A `Query(p, row)` |
| `filter(f)` | `row -> Bool` | A `Query(p, row)` |
| `filter_by(f)` | `p, row -> Bool` | A `Query(p, row)` with a parameter record `p` |
| `select(f)` | `row -> out` | A `Selected(p, out)`. The fields of the record that `f` builds are the columns |
| `order_by(f, Asc)` | `out -> key`, `Asc` or `Desc` | A `Selected(p, out)` |
| `prepare(params)` | A value of type `p` | `Prepared(List(out))` |
| `ready()` | Nothing. For a query with no parameter | The same as `prepare({})` |

```roc
# Fragment: uses `Owner` and `owners` from above.
CityParam : { city : Str }

in_city : CityParam, Owner -> Bool
in_city = |p, o| o.address.city == p.city

OwnerCard : { id : Str, name : Str, phone : Str }

owner_card : Owner -> OwnerCard
owner_card = |o| { id: o.id, name: o.name, phone: o.?phone ?? "none" }

owners_in_city = Surreal.from(owners).filter_by(in_city).select(owner_card).order_by(|r| r.id, Asc)
```

`CityParam`, `in_city` and `owner_card` are from `examples/main.roc`. The type `OwnerCard` is the type of each result row. The compiler checks it.

### Print the SurrealQL

You have two ways to get the text:

| Call | Gives | Parameters |
| --- | --- | --- |
| `selected.to_surql()` | `Try(Str, Error)` | A `$name` for each one |
| `prepared.request()` | `Try(Str, Error)` | A `LET $name = value;` line for each one, then the statement |

`prepare({ city: "Oslo" })` gives the `Prepared`. `request()` gives its text. A query that reads no parameter takes `ready()` in place of `prepare({})`. Real output of the second way:

```surql
LET $city = 'Oslo';
SELECT record::id(id) AS id, name AS name, phone ?? 'none' AS phone FROM owner WHERE address.city = $city ORDER BY id;
```

The first way prints the same `SELECT` with no `LET` line and no final `;`.

A script app prints it. Both `to_surql` and `request` give a `Try`, so match on it:

```roc
# Fragment: uses `owners_in_city` from above.
main! = |_args| {
	match owners_in_city.prepare({ city: "Oslo" }).request() {
		Ok(text) => echo!("${text}\n")
		Err(why) => echo!("not built: ${Str.inspect(why)}\n")
	}
	Ok({})
}
```

The functions run on your own rows as well. With `jon : Owner`, the call `owner_card(jon)` gives `{ id: "jon", name: "Jon", phone: "none" }`. [Choosing the fields to read](selecting-fields.md) and [Writing queries](queries.md) cover the rest of the query API.

## Run it on a server

Run a query in four steps:

| Step | Call | Gives |
| --- | --- | --- |
| 1 | Make a `Surreal.Transport` from the platform adapter | The way to reach the server |
| 2 | Make a `Surreal.Login` | The user and the namespace |
| 3 | `Surreal.Session.open!(transport, login)` | `Try(Session, Error)` |
| 4 | `session.run!(prepared)` | `{ session, result : Try(out, Error) }` |

`run!` always gives the session back. Use that session for the next call. For a `Prepared(List(OwnerCard))`, `result` holds a `List(OwnerCard)`.

```roc
# Fragment: uses `WsClient` from the platform adapter and `owners_in_city` from above.
login : Surreal.Login
login = Root({ ns: "roc", db: "roc_surreal", user: "root", pass: "root" })

transport : Surreal.Transport
transport = Surreal.Transport.websocket_timed(WsClient.connect, WsClient.ops, "ws://127.0.0.1:8000")

run! : Str => Try(List(OwnerCard), Str)
run! = |city| {
	prepared = owners_in_city.prepare({ city: city }).map_err(Str.inspect)?
	session = Surreal.Session.open!(transport, login).map_err(Str.inspect)?
	session.run!(prepared).result.map_err(Str.inspect)
}
```

The server must hold the tables first. Load the script of `Surreal.schema` once. A fresh server needs the namespace and the database:

```sh
curl -s -u root:root -H 'surreal-ns: roc' --data 'DEFINE NAMESPACE IF NOT EXISTS roc; DEFINE DATABASE IF NOT EXISTS roc_surreal;' http://127.0.0.1:8000/sql
curl -s -u root:root -H 'surreal-ns: roc' -H 'surreal-db: roc_surreal' --data-binary @schema.surql http://127.0.0.1:8000/sql
```

Here `schema.surql` holds the printed schema script. Load it once, for a first try. An app does not load it at each start: it applies migration files with `session.migrate!` (see [Migrations](schema.md#migrations)). Write rows with `owners.insert(rows)` (see [Writing rows](writes.md)).

[Sessions and typed results](sessions.md) covers logins, batches and transactions. A session on basic-webserver lives for one request. Live queries need a WebSocket. [Live queries](live-queries.md) covers them.

## When a statement is not built

Every call that makes SurrealQL gives a `Try`. The error type is `Surreal.Error`. Two tags matter when you build:

| Tag | When |
| --- | --- |
| `Unsupported(why)` | A clause has no SurrealQL form. `why` names the clause, such as ``in `filter`: `Str.split_first` has no SurrealQL form`` |
| `BadSchema(why)` | `Surreal.schema` refuses a definition, such as the text `` `name` has two defaults `` |

A refusal is not a compile error. The program compiles. You see the `Err` when it calls `to_surql`, `prepare` or `schema`. Match on it:

```roc
# Fragment: uses `Surreal` from the header.
describe : Try(Str, Surreal.Error) -> Str
describe = |built| match built {
	Ok(text) => text
	Err(Unsupported(why)) => "not built: ${why}"
	Err(other) => Str.inspect(other)
}
```

Put one `expect` in your module for each query so that a refusal fails at `roc test`:

```roc
# Fragment: uses `owners_in_city` from above.
expect owners_in_city.to_surql().is_ok()
```

An intrinsic called outside a clause is different. It is a compile error (see the glossary). [Errors](errors.md#build-time-errors) lists every error.

## Words used in these pages

| Term | Meaning |
| --- | --- |
| row type | A Roc record type for the rows of one table, such as `Owner`. An alias row is `Owner : { .. }`. A nominal row is `Owner := { .. }`. |
| table | A `Surreal.Table(row)`. It holds a name and a kind. The row type comes from the annotation. |
| clause | A Roc function that you pass to a builder method: a filter, a projection, a constraint, a key. |
| `Code(f)` | The type of the description of a function of type `f`. A builder method takes it. You pass an ordinary function. |
| reified | Said of a function that stands where the type says `Code(f)`. The compiler makes a description of it. The function stays an ordinary function. |
| translator | The part of the package that reads a description and writes SurrealQL. |
| intrinsic | A package function with a type and no body, such as `Surreal.Text.is_email`. SurrealDB computes it. It works only in a clause. A call elsewhere is the compile error `exists only in reified code`. `roc check --intrinsics src/main.roc` lists them. |
| mirror function | A package function with a Roc body that gives the SurrealDB result, such as `Surreal.Array.distinct`. It works in a clause (as SurrealQL) and in plain Roc code. |
| `Surreal.Mirror` | The Roc model of the notices that a live query sends. Tests use it. Written "the Mirror". It is not a mirror function. |
| read row | A row type for reading linked rows and edges in one query. Its fields can be `Linked(r)`, `Out(e)` and `In(e)`. A `define_read()` entry checks it. |
| parameter record | The record `p` that a `filter_by` clause reads and that `prepare(p)` fills. Each field becomes a `$name`. |
| captured value | A run-time value from around a clause, in a function whose result is a `Prepared` or a `Watch`. It is a `$_1` slot in the text. |
| prepared statement | A `Surreal.Prepared(out)`. It holds the statement text and the reader that turns the reply into `out`. |
| script app | An app header with no platform. It can print SurrealQL. It cannot open a session. |

## Where to go next

Read the pages in this order. The last column names an example file to read next to each page.

| Page | You learn to | Example |
| --- | --- | --- |
| [Row types and data types](data-types.md) | Map Roc types to SurrealDB types | `examples/main.roc` |
| [Tables and schema](schema.md) | Add constraints, indexes, links and views | `examples/main.roc` |
| [Choosing the fields to read](selecting-fields.md) | Write projections | `examples/main.roc` |
| [Writing queries](queries.md) | Filter, order, group and reuse | `examples/main.roc`, `examples/clinic/Clinic.roc` |
| [Ids, links and graph edges](links-and-graphs.md) | Follow links and edges | `examples/main.roc` |
| [Writing rows](writes.md) | Create, update and delete | `examples/main.roc` |
| [Sessions and typed results](sessions.md) | Connect and run | `examples/client.roc`, `examples/server.roc` |
| [Errors](errors.md) | Match on errors | `examples/client.roc` |
| [Live queries](live-queries.md) | Watch a query | `examples/watch.roc` |
| [Record users and permissions](access.md) | Sign users in | `examples/client.roc` |
| [Functions in clauses](functions.md) | Call builtins and SurrealDB functions | `examples/monitoring.roc` |
| [Full-text and vector search](search.md) | Search text and vectors | `examples/search.roc` |
| [Escape hatches and extensions](advanced.md) | Send raw SurrealQL | `examples/main.roc` |

The [overview](README.md) lists every feature.

## Limits

| Limit | What to do instead |
| --- | --- |
| Stock Roc cannot build the package | Use the compiler of `.roc-version` |
| A script app has no platform, so it cannot open a session | Print the script and load it with `curl`, or add a platform |
| A clause with no SurrealQL form is `Err(Unsupported(..))` at run time | Test each query with `to_surql().is_ok()` in an `expect` |
| A live query needs a WebSocket | Use `Transport.websocket` or `Transport.websocket_timed` |
