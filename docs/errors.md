# Errors

This page lists every error that the package gives, when it happens, and how to match on it. Every call that can fail has one error type, `Surreal.Error`. You match on its tags with a normal `match`.

The words clause, intrinsic and prepared statement are in [Words used in these pages](getting-started.md#words-used-in-these-pages). Sessions are in [Sessions and typed results](sessions.md).

| You want | Section |
| --- | --- |
| See all tags and when each one happens | [One error type](#one-error-type) |
| Know why a statement is not built | [Build-time errors](#build-time-errors) |
| Know why the server refused a statement | [Server errors](#server-errors) |
| Write the `match` | [Match on an error](#match-on-an-error) |
| Know what a broken connection gives | [Connection errors](#connection-errors) |
| Read the error of a transaction | [Errors in transactions](#errors-in-transactions) |

The examples are `examples/client.roc` (basic-cli) and `examples/main.roc`. The row types in this page are `Owner` and `Pet` of a scratch app: `Owner` is `{ id : Str, email : Str, age : I64, city : Str }`, with a unique `email` and `assert` on `age >= 0`. `Pet` has `owner : Surreal.Link(Owner)`. Every error text in this page is from a real run on SurrealDB 3.3.4.

## One error type

`Surreal.Error` is a tag union with nine tags. The first two come when you build a statement. The next six come when a session runs it. `Migration` comes from a migration file or its runner.

| Tag | Holds | When | Section |
| --- | --- | --- | --- |
| `Unsupported(why)` | `Str` | A clause or a call has no SurrealQL form | [Build-time errors](#build-time-errors) |
| `BadSchema(why)` | `Str` | `Surreal.schema` refuses a definition | [Build-time errors](#build-time-errors) |
| `Server(error)` | `Surreal.ServerError` | The server refused a request or a statement | [Server errors](#server-errors) |
| `Aborted({ at, error })` | `at : U64`, `error : ServerError` | A statement failed a transaction | [Errors in transactions](#errors-in-transactions) |
| `Decode({ path, message })` | Two `Str` | A value of the server does not fit the Roc type | [Decode and Wire](#decode-and-wire) |
| `Wire(why)` | `Str` | A message is not what the protocol says | [Decode and Wire](#decode-and-wire) |
| `Transport(why)` | `Str` | The platform could not post over HTTP | [Connection errors](#connection-errors) |
| `WebSocket(why)` | `Closed(closure)`, `Closing` or `Adapter(Str)` | The WebSocket adapter failed | [Connection errors](#connection-errors) |
| `Migration({ name, problem })` | The file, and `Changed`, `OutOfOrder`, `Edit`, `Text(why)`, `Target({ file, server })` or `Unplanned(statements)` | `Surreal.migration`, `Surreal.check` or `session.migrate!` refuses a file or a history | [Migrations](schema.md#what-migrate-does) |

The tags come in three phases:

```
build         Unsupported  BadSchema                          no server needed
open!         Server(Denied)  Transport  WebSocket            the login
run! await!   Server  Aborted  Decode  Wire  Transport  WebSocket
```

`run!` and `await!` give `{ session, result }`, and `result` can hold any tag of the last row. `Session.open!`, `send!` and the other calls give a `Try`, and the `Err` can hold the connection tags and `Server`. After a `Transport` or `WebSocket` error the connection is gone (see [Connection errors](#connection-errors)).

## Build-time errors

`Unsupported` and `BadSchema` come from `prepare`, `prepare_one`, `to_surql`, `then` and `Surreal.schema`, before any request goes out. No server is needed to see them.

| Tag | What it means | Example text |
| --- | --- | --- |
| `Unsupported(why)` | A clause or a call has no SurrealQL form. The text names the clause | ``in `filter`: `Str.split_first` has no SurrealQL form`` |
| `BadSchema(why)` | A definition is wrong. The text names the field or the table | `` `age` has two defaults `` |

Both texts above come from a real run. The text of an `Unsupported` starts with the clause (`in `filter``, `in the condition of `delete``) when a clause caused it. A call that is not a clause gives its own text, such as a `prepare_one` of a query that is not from `table.at`.

These refusals are values, not compile errors. The program compiles. You see the `Err` when it runs. The compiler checks the types of a clause. Only the package knows which clauses have a SurrealQL form, and it finds out when it translates the clause.

A session call can also give `Unsupported` at run time, when the transport cannot do the call. `next!` and `live!` need a WebSocket (see [Choose a transport](sessions.md#choose-a-transport)). `next_within!` needs `Transport.websocket_timed`.

Match on a refusal where you build, or put one `expect` in your module for each query. The first form gives a message to the user. The second fails `roc test` when a query has no SurrealQL form.

```roc
# Fragment: uses `Surreal` from the header.
build_note = |built| match built {
	Ok(_) => "built"
	Err(Unsupported(why)) => "not built: ${why}"
	Err(BadSchema(why)) => "bad schema: ${why}"
	Err(other) => Str.inspect(other)
}
```

A real run of `build_note` on the `filter` above gives ``not built: in `filter`: `Str.split_first` has no SurrealQL form``.

An intrinsic is different. It has no Roc body, and it works only inside a clause. A call anywhere else is a compile error at the line of the call:

```text
── ✗ exists only in reified code ───────────── intr.roc:9:6
ok = Surreal.Text.is_email("a@b.c")
```

Use the function in a clause, or see [Functions in clauses](functions.md#mirror-functions-and-intrinsics).

## Server errors

`Server(error)` holds a `Surreal.ServerError`. The package reads the `kind` that SurrealDB sends with each error, and for the kind `Internal` it reads the text of the message. Every tag keeps the message of the server. `error.message()` gives it for any tag.

| Tag | Fields besides `message` | When |
| --- | --- | --- |
| `Exists` | `what`, `name` | A `create` of a key that a row already has |
| `NotFound` | `what`, `name` | A table, a record or a method does not exist, such as a table that the schema script did not make |
| `Unique` | `table`, `index`, `fields`, `value`, `record` | A unique index holds the value already, and the session knows the schema |
| `Index` | `index`, `value`, `record` | The same, when the session does not know the schema |
| `Assert` | `table`, `field`, `record`, `value`, `condition` | The `ASSERT` of a field fails, or a link points at a row that does not exist. A `check` over several fields is the `ASSERT` of one of them, so it gives `Assert` too |
| `Type` | `table`, `field`, `record`, `expected`, `found` | A value does not fit the `TYPE` of its field |
| `Check` | `table`, `name` | A `check` that is an event fails: it reads the key `id` or an edge end, or no field of it can hold an `ASSERT` (see [Constraints](schema.md#constraints)) |
| `Referenced` | `record`, `by` | A delete of a row that a link with `Reject` points at |
| `Denied` | none: it holds the message | A login or a statement that the server does not allow |
| `Parse` | none: it holds the message | The text is not SurrealQL |
| `Invalid` | none: it holds the message | Any other refusal of the text, such as a protected variable |
| `Conflict` | none: it holds the message | The `COMMIT` of a transaction found a conflict. The transaction can run again |
| `Timeout` | none: it holds the message | A statement took longer than its timeout |
| `Thrown` | `text` | A `THROW` in raw text or in an event of your own |
| `Other` | `kind` | Any other kind of error, or a message of another form |

The typed API writes its own text, so some tags need raw text to see: `Parse`, `Invalid`, `Thrown`, `Timeout` and `Type` do not come from `create`, `select` and the other typed calls. They come from `Surreal.Unchecked.query!` (see [Raw SurrealQL](advanced.md#raw-surrealql)), or from a database that you changed by hand.

A real run of each tag gives these messages:

```text
Exists:      Database record `owner:ann` already exists
NotFound:    The table 'nothing_here' does not exist
Unique:      Database index `owner_email_unique` already contains 'ann@x', with record `owner:ann`
Assert:      Found -1 for field `age`, with record `owner:bob`, but field must conform to: $value >= 0
Type:        Couldn't coerce value for field `age` of `owner:old`: Expected `int` but found `'old'`
Assert:      Found 'oslo' for field `city`, with record `owner:eli`, but field must conform to: IF $value = 'oslo' THEN string::contains($this.email, '@') ELSE true END
Check:       Error while processing event owner_check_adult_in_town: An error occurred: owner: adult in town
Referenced:  Cannot delete `owner:ann` as it is referenced by `pet:rex` with an ON DELETE REJECT clause
Denied:      There was a problem with authentication
Invalid:     'session' is a protected variable and cannot be set
Thrown:      text "boom", message "An error occurred: boom"
Timeout:     The query was not executed because it exceeded the timeout: 0ns
```

The first `Assert` line is a `check` over `city` and `email`: the check is the `ASSERT` of `city`, so the error names the field `city` and holds the condition. The `Check` line is a `check` over `age` and the key `id`: no field can hold it, so it is an event.

The `Parse` message has the line and the column of the fault, and a marked copy of the text.

`prepare_one` has its own `NotFound`. It is the tag `[NotFound]` in `Ok(Err(NotFound))`, the answer for a key with no row. It is not the `Server(NotFound(..))` above. See [Run a prepared statement](sessions.md#run-a-prepared-statement).

### Which schema clause gives which error

| Schema clause | Write that fails | Error |
| --- | --- | --- |
| `unique` | A second row with the same value | `Unique`, or `Index` without `session.knowing(defs)` |
| `assert`, `assert_each` | A value that the condition refuses | `Assert` |
| `check` of one field | The same, because the package writes it as an `ASSERT` | `Assert` |
| `check` of several fields, when one field can hold it | A row that the condition refuses. The package writes the `ASSERT` of the first required field that is not read-only | `Assert`, on that field |
| `check` of several fields, when no field can hold it (it reads `id`, `in` or `out`, or only optional, read-only or permitted fields) | A row that the condition refuses. The package writes an event | `Check` |
| A `Link` field | A link to a row that does not exist | `Assert`, on the link field |
| `on_delete` with `Reject` (the default) | A delete of a row that a link points at | `Referenced` |
| `on_delete` with `Cascade`, `Unset` or `Ignore` | A delete of a row that a link points at | None |
| Roles of a record user | A request that the role may not do, such as `INFO` | `Denied` |

[Constraints](schema.md#constraints) shows the clauses. [Links and delete policies](schema.md#links-and-delete-policies) shows `on_delete`. [Record users and permissions](access.md) shows the roles and the logins that give `Denied`. To get `Unique` and not `Index`, see [Unique errors need the schema](sessions.md#unique-errors-need-the-schema).

## Match on an error

Match on the tag you want, then give the other tags to a last pattern. A pattern can look inside: a record pattern names the fields it needs, and `..` stands for the rest. The session always comes back from `run!`, so you read `result` and keep `session`.

```roc
# Fragment: uses `owners`, `owner` (an `Owner`) and `session` (one that knows the schema).
note = match session.run!(owners.create(owner)).result {
	Ok(rows) => "stored ${rows.len().to_str()} row"
	Err(Server(Unique({ table: "owner", fields: ["email"], .. }))) => "the email is taken"
	Err(Server(Assert({ field: "age", .. }))) => "the age is not allowed"
	Err(Server(error)) => error.message()
	Err(Transport(_)) | Err(WebSocket(_)) => "the connection is gone: open a new session"
	Err(Aborted({ at, error })) => "part ${at.to_str()} failed: ${error.message()}"
	Err(other) => Str.inspect(other)
}
```

The first pattern that fits wins, so put the narrow patterns first. Real runs of this `match` on three `create` calls:

| Row | Text |
| --- | --- |
| `email: "ann@x"`, which a row has already | `the email is taken` |
| `age: -3` | `the age is not allowed` |
| `email: "n3@x", age: 3` | `stored 1 row` |

Notes for the patterns:

| Rule | Detail |
| --- | --- |
| `Unique` needs the schema | Open the session with `session.knowing(defs)`. Without it the tag is `Index` |
| A `Unique` pattern can name the fields | `fields: ["email"]` is the list of the index, in the order of the definition |
| Do not match on the text of a message | The text is the server's and can change with the server. Match on the tag and its fields |
| Keep a last `Err(other)` | A later version can add a tag |

`Prepared.then` gives a pair of results, and each side is its own `Try`. Match each side alone. See [Two statements in one request](sessions.md#two-statements-in-one-request).

## Connection errors

These errors mean that the request did not get a normal answer. `run!` gives them in `result`, and `Session.open!` and `send!` give them as the `Err`.

| Tag | Holds | When |
| --- | --- | --- |
| `Transport(why)` | The text that your `post!` function gave | The platform could not post over HTTP: no server, a refused connection, a timeout |
| `WebSocket(Closed(closure))` | A `Ws.Closure`: `code`, `reason`, `clean` and `by` | The server or the adapter ended the connection |
| `WebSocket(Closing)` | None | The connection is closing |
| `WebSocket(Adapter(text))` | A tag of the adapter, as `Str.inspect` writes it | The adapter failed, such as `Connect(ConnectionRefused)` |

A real run with nothing on port 9:

```text
Err(WebSocket(Adapter("Connect(ConnectionRefused)")))
Err(Transport("HttpErr(Other([99, 108, 105, 101, ..]))")
```

The text of `Transport` is what the `post!` function of the app returned. The example `post!` of `examples/client.roc` uses `Str.inspect`, so the text is the raw platform error (shortened above). Write the `post!` function with a text that you can read (see [Use HTTP](sessions.md#use-http)).

After a `Transport` or `WebSocket` error the connection is gone. A session that gave one cannot send again. Open a new session with `Session.open!`. A `Server` error does not end the session.

A refused login is not a connection error. It is `Server(Denied(message))`, from `Session.open!`. See [Log in](sessions.md#log-in).

### Decode and Wire

`Decode` and `Wire` come after the server has answered.

| Tag | When | Real text |
| --- | --- | --- |
| `Decode({ path, message })` | A value does not fit the Roc type that the query reads. `path` is the field, or empty when the reader names none | `the value at byte 5 (age) does not fit its Roc type`, with `path: "age"` |
| `Wire(why)` | The reply is not what the statement expects: a wrong count of results, a result that is not a list of rows, a text message | `the result of statement 1 is not an array of rows` |

For a `Decode`, compare the row type with the table. A type of the read that is not the type of the stored field is the usual cause. A real run read `age : I64` as `age : Str` and gave the `Decode` above. For a `Wire`, check that the `Prepared` is the one that made the request. A `Wire` that raw text did not cause is a bug of the package, or a server that the package does not know. Report it.

## Errors in transactions

A transaction gives `Aborted({ at, error })` when a statement fails it. Nothing of the writes stays. `error` is the `ServerError` of the statement that failed. `at` says which part of the transaction it was.

| Number | The part |
| --- | --- |
| 0 | The `Prepared` that `begin()` took, or the first of the list of `Surreal.transaction` |
| 1, 2, .. | The next `then`, or the next of the list, in order |
| The count of parts | The `COMMIT` |

A part is one `Prepared`. An insert counts as one part. A real run of three creates in one transaction, where the third has `age: -1`:

```text
Err(Aborted({ at: 2, error: Assert({ field: "age", record: "owner:t3", table: "owner", value: "-1", .. }) }))
```

The count of parts is the number of the `COMMIT`. A `Conflict` there means that another transaction changed the same records. Run the transaction again. The package does not retry.

Other statements of the transaction are rolled back or did not run. You do not see their errors. The server says `NotExecuted` for them, and the package keeps the error that failed the transaction.

Three cases are not `Aborted`:

| Case | Result |
| --- | --- |
| `table.insert(rows)` alone | `Server(error)`. It is one statement in a transaction of its own, so no part number helps. A real run with a repeated unique email gave `Err(Server(Unique({ .. })))` |
| `a.then(b)`, with no `begin` | A pair of results, each its own `Try`. A failed side does not undo the other |
| A section of a plan (`plan.prepare(mode)`) or of a migration file (`session.migrate!`) | `Server(error)` of the statement that failed. A section is one transaction, so nothing of it stays (see [Migrations](schema.md#migrations)) |

When a transaction is a side of `then`, its `Aborted` is the error of that side (see [Transactions](sessions.md#transactions)).

## Limits

| Limit | What to do instead |
| --- | --- |
| A refusal is a value, not a compile error at the line of the clause | Put an `expect` with `to_surql().is_ok()` in the module for each query |
| The server messages are the server's text, from SurrealDB 3.3.4 | Match on the tag and its fields, not on the text |
| The package reads only the message forms that it writes or that the server writes the same way each time. Another `Internal` message is `Other` | Match `Other({ kind, .. })` and read `message()` |
| `Unique` needs the schema. Without it the tag is `Index` | Open the session with `session.knowing(defs)` |
| `Parse`, `Invalid`, `Thrown` and `Timeout` come in practice only from raw text or an event of your own | Use `Surreal.Unchecked.query!` if you need to test them |
| The typed API does not write `THROW` or `CANCEL` | Use a constraint of the schema to refuse a write |
| `Conflict` is not retried | Run the transaction again in your code |
| The text of `Transport` and the `Adapter` text of `WebSocket` are the platform's and the adapter's | Match on the tag and not on the text |
| A `Transport` or `WebSocket` error ends the session | Open a new session |
| A transaction that fails gives no partial result | Fix the cause and run the whole transaction again |
