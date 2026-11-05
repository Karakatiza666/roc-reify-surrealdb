# Sessions and typed results

This page shows how to connect to a SurrealDB server, sign in and run prepared statements. A session sends the text of a `Prepared` and reads the reply as your Roc type. The page also covers batches, requests in flight together, transactions and the session on basic-webserver.

The words prepared statement and script app are in [Words used in these pages](getting-started.md#words-used-in-these-pages). To build a `Prepared`, see [Writing queries](queries.md#get-the-surrealql-text) and [Writing rows](writes.md). Live queries use the same session (see [Live queries](live-queries.md)).

| You want | Call | Section |
| --- | --- | --- |
| Reach the server | `Transport.websocket`, `websocket_timed`, `http` | [Choose a transport](#choose-a-transport) |
| Sign in | `Root`, `SignUp`, `SignIn`, `Token` | [Log in](#log-in) |
| Start a session | `Session.open!` | [Open a session](#open-a-session) |
| Run one statement | `session.run!(prepared)` | [Run a prepared statement](#run-a-prepared-statement) |
| Run two statements, each on its own | `a.then(b)` | [Two statements in one request](#two-statements-in-one-request) |
| Send several requests, then read the replies | `send!`, `await!` | [Requests in flight together](#requests-in-flight-together) |
| Make several writes all or nothing | `begin`, `then`, `commit` | [Transactions](#transactions) |
| Make a list of writes all or nothing | `Surreal.transaction(list)` | [A list of statements in one transaction](#a-list-of-statements-in-one-transaction) |
| Move the database to a new schema | `session.migrate!(migrations)` | [Migrations](schema.md#migrations) |
| Get `Unique` and not `Index` | `session.knowing(defs)` | [Unique errors need the schema](#unique-errors-need-the-schema) |
| Serve requests | One session for each request | [Sessions on basic-webserver](#sessions-on-basic-webserver) |

The examples are `examples/client.roc` (basic-cli, WebSocket or HTTP), `examples/server.roc` (basic-webserver) and `examples/watch.roc` (live queries). The row type in this page is `Bin` of `examples/client.roc`: `{ id : Str, label : Str }`, with a unique `label`.

## Choose a transport

A `Surreal.Transport` says how the session reaches the server. It is one type with three constructors. Nothing is sent until `Session.open!` connects it. After that, every call of the session has the same type on every transport.

| Constructor | Takes | Live queries | `next_within!` |
| --- | --- | --- | --- |
| `Transport.websocket(connect, ops, url)` | The adapter of the platform and a `ws://` URL | Yes | `Unsupported` |
| `Transport.websocket_timed(connect, ops, url)` | As `websocket`, with an adapter that has `receive_within!` | Yes | Yes |
| `Transport.http(client, url)` | A `Surreal.HttpClient` and an `http://` URL | No | `Unsupported` |

`connect` and `ops` are `WsClient.connect` and `WsClient.ops` of the adapter package. The session connects to the URL plus `/rpc` with the subprotocol `cbor`. For HTTP, each request is one `POST /rpc`.

| Platform | Adapter package | WebSocket constructor | `Http.send!` call |
| --- | --- | --- | --- |
| basic-cli 0.26.0 | roc-basic-cli-websocket 0.0.3 | `websocket_timed` | `Http.send!(request, {})` |
| basic-webserver 0.20.0 | roc-basic-webserver-websocket 0.0.2 | `websocket` | `Http.send!(request)` |

The adapter of basic-cli has `receive_within!`, so it takes either WebSocket constructor. The adapter of basic-webserver has none, so it takes only `websocket`. The package header lines are in [Add the package](getting-started.md#add-the-package). The full headers are in `examples/client.roc` and `examples/server.roc`.

```roc
# Fragment: uses `WsClient` from the adapter (`import cli_ws.WsClient`).
transport : Surreal.Transport
transport = Surreal.Transport.websocket_timed(WsClient.connect, WsClient.ops, "ws://127.0.0.1:8000")
```

From `examples/watch.roc`, `transport`.

### Use HTTP

The platform sends the post. You give the session a function for it. The function takes an `HttpRpc.Post` (the URI, the headers and the body). It gives the status and the body of the response, or a text for a post that got no response.

```roc
# Fragment: uses `import pf.Http` and `import http.Request`.
http_client : Surreal.HttpClient
http_client = {
	post!: |post| {
		request = post.headers.fold(Request.from_method(POST).with_uri(post.uri).with_body(post.body), |r, h| r.add_header(h.name, h.value))
		response = Http.send!(request, {}).map_err(Str.inspect)?
		Ok({ status: response.status(), body: response.body() })
	},
}
```

From `examples/client.roc`, `http_client`. In basic-webserver, write `Http.send!(request)`. `examples/client.roc` picks the transport from the argument: `roc examples/client.roc -- --http` runs the same app over HTTP.

Over HTTP the server keeps nothing between two posts. So each post carries who the session is:

| Login | The post carries |
| --- | --- |
| `Root` | The user and password (Basic authentication), and the namespace and database |
| `SignUp`, `SignIn` | The token that the reply gave, and the namespace and database |
| `Token` | The token. The token holds the namespace and the database |

A response with status 200 holds an RPC reply, also one with an error. Any other status is a `Server` error, such as `Denied` for a wrong password.

## Log in

`Session.open!` takes a `Surreal.Login`. The tag says who signs in.

| Login | Who the session is |
| --- | --- |
| `Root({ ns, db, user, pass })` | A system user, in the namespace and the database |
| `SignUp(login)` | A new record user. The session has a token |
| `SignIn(login)` | A record user. The session has a token |
| `Token(token)` | The user of a token that a signup or a signin gave |

```roc
# Fragment: uses `Surreal` from the header.
login : Surreal.Login
login = Root({ ns: "roc", db: "roc_surreal", user: "root", pass: "root" })
```

From `examples/client.roc`, `login`. You do not write the `login` of a record user by hand. `Access.sign_up` and `Access.sign_in` build it from a typed record (see [Sign up and sign in](access.md#sign-up-and-sign-in)).

A refused login is the error `Server(Denied(message))`. A real run with the password `wrong`:

```text
Err(Server(Denied("There was a problem with authentication")))
```

## Open a session

`Surreal.Session.open!(transport, login)` connects, signs in and gives `Try(Session, Error)`. A `Session` is a value. Each call that uses it gives the session after the call.

```roc
# Fragment: uses `transport` and `login` from above.
session = Surreal.Session.open!(transport, login).map_err(Str.inspect)?
```

| Rule | Detail |
| --- | --- |
| Use the session that the last call gave back | An older copy has an older inbox. Roc cannot check this |
| A call that fails gives no session | An `Err` means that the connection or a message failed |
| `run!` and `await!` always give a session | `result` holds the rows or any error. After a `Transport` or `WebSocket` error the connection is gone: open a new session |
| One session for all your calls | Queries, writes and watches share one session. No reply and no notice is lost |

### Other session calls

| Call | Gives |
| --- | --- |
| `session.token()` | `Try(Str, [NoToken])`. The token of a record user. A system user has none |
| `session.invalidate!()` | `Try(Session, Error)`. The session is no one. Each later request is `Denied` until you sign in again. The token stays valid until it expires |
| `session.pushes()` | `Bool`. True on a WebSocket, false over HTTP. A watch needs it |
| `session.knowing(defs)` | The session, with the schema (see [Unique errors need the schema](#unique-errors-need-the-schema)) |
| `session.kill!(lives)` | `Try(Session, Error)`. Ends a watch (see [Live queries](live-queries.md#stop-a-watch)) |

On a script app (no platform) you cannot open a session. See [Limits](#limits).

## Run a prepared statement

`session.run!(prepared)` sends the text and reads the reply as the type of the `Prepared`. It gives `{ session, result }`. The type of `result` is `Try(out, Error)`.

```roc
# Fragment: uses `session` from above and `bin_rows` from examples/client.roc.
done = session.run!(bin_rows.map_err(Str.inspect)?)
# done.result : Try(List(Bin), Surreal.Error)
# done.session : the session for the next call
```

The type `out` depends on what made the `Prepared`:

| Made by | `result` is `Ok(..)` of | Page |
| --- | --- | --- |
| `Selected.prepare`, `ready`, and `Query.prepare`, `ready` | `List(out)`, the result rows. A `Query` gives the whole rows | [Writing queries](queries.md) |
| `Selected.prepare_one`, `ready_one`, and the same on `Query` | `Try(out, [NotFound])`. A query from `table.at(id)` only | [Start a query](queries.md#start-a-query) |
| `Totals.prepare`, `ready` | `out`, one row | [Totals of all rows](queries.md#totals-of-all-rows) |
| `Write.prepare`, `ready`, `create`, `insert`, `upsert`, `replace`, `edit` | `List(row)`, the rows as stored | [Writing rows](writes.md) |
| `create_new`, `insert_new` | `List(Created(row, new))` | [Keys that the server makes](writes.md#keys-that-the-server-makes) |
| `a.then(b)` | `(Try(a), Try(b))` | [below](#two-statements-in-one-request) |
| `commit()` of a transaction | `(a, b)`, `((a, b), c)`, .. | [below](#transactions) |
| `Surreal.transaction(list)` | `List(out)`, the result of each statement | [below](#a-list-of-statements-in-one-transaction) |
| `Plan.prepare(mode)`, one for each section | `{}` | [Migrations](schema.md#the-calls) |

For a `prepare_one` the result is two `Try`s deep. A key with no row is `Ok(Err(NotFound))`:

```text
hit:  Ok(Ok({ id: "b1", label: "Top" }))
miss: Ok(Err(NotFound))
```

`prepare_one` of a query that is not from `table.at` is `Err(Unsupported(..))` when you build it. The message tells you to use `prepare`.

A statement that the server refuses is `Err(Server(error))`, typed by its kind (see [Server errors](errors.md#server-errors)). A row that does not fit the type is `Err(Decode(..))`. Every error is listed in [One error type](errors.md#one-error-type).

## Two statements in one request

`a.then(b)` joins two prepared statements into one `Prepared`. The server gets one request. Each statement runs on its own. If one fails, the other still runs, and each has its own result.

```roc
# Fragment: uses `bins`, `bin_rows` and `twin_bin` from examples/client.roc.
batch = |first, second| first?.then(second?)

twin_then_rows = batch(bins.create(twin_bin), bin_rows)
# twin_then_rows : Try(Prepared((Try(List(Bin), Error), Try(List(Bin), Error))), Error)
```

From `examples/client.roc`, `batch` and `twin_then_rows`. A real run, where `b1` has the label `Top` and the unique index refuses the twin:

```text
Ok((Ok([{ id: "b2", label: "Mid" }]), Err(Server(Unique({ fields: ["label"], .. })))))
```

The text of the request has the `LET` lines of both statements, then the statements. A name that both statements bind must have one value. With two values the build gives `Err(Unsupported("`$label` is bound to two different values in one script"))`. A request that the server refuses as a whole is one error for the whole `Prepared`.

`then` is not a transaction. A write that fails does not undo the other write. For that, use a [transaction](#transactions).

## Requests in flight together

`run!` is `send!` and then `await!`. Call them yourself to send several requests before you read the replies.

| Call | Gives |
| --- | --- |
| `session.send!(prepared)` | `Try({ session, ticket }, Error)`. Sends the request and does not wait |
| `session.await!(ticket, prepared)` | `{ session, result }`. Reads the reply of that ticket. Give the same `prepared` that you sent |

```roc
# Fragment: uses `session`, `all_bins` and `bin_b1` (two `Prepared` values) from above.
sent_one = session.send!(all_bins).map_err(Str.inspect)?
sent_two = sent_one.session.send!(bin_b1).map_err(Str.inspect)?
got_two = sent_two.session.await!(sent_two.ticket, bin_b1)
got_one = got_two.session.await!(sent_one.ticket, all_bins)
```

Each reply goes to its ticket, so you can await in any order. `examples/client.roc` does this in `pipelined!`, and `examples/watch.roc` sends two writes this way.

| Transport | What happens |
| --- | --- |
| WebSocket | Both requests are in flight together. The server runs them with no order between them |
| HTTP | `send!` posts and waits for the response. The requests run one after the other, in the order sent |

A step that needs the result of another step must not be a separate request. Put both in one request with `then`, or `await!` the first before you `send!` the second. Await each ticket once.

## Transactions

A transaction runs all its statements or none of their writes. Start with `begin()` on a `Prepared`, add statements with `then`, and end with `commit()`. `commit()` gives a `Prepared` that you run as any other.

```roc
# Fragment: uses `bins` and `bin_rows` from examples/client.roc.
atomic3 = |first, second, third| Ok(first?.begin().then(second?)?.then(third?)?.commit())

stock_up = atomic3(bins.create(side_bin), bins.insert([low_bin]), bin_rows)
# stock_up : Try(Prepared(((List(Bin), List(Bin)), List(Bin))), Error)
```

From `examples/client.roc`, `atomic3` and `stock_up`.

| Call | Gives |
| --- | --- |
| `p.begin()` | A `Transaction(out)` with `p` as its first part |
| `t.then(q)` | `Try(Transaction((a, b)), Error)`. Each `then` nests the result pair once more |
| `t.commit()` | A `Prepared(out)` for `run!`, `send!` or `then` |

The request is `BEGIN`, the statements, `COMMIT`. A real print of a create and a second create, as one transaction:

```surql
BEGIN;
CREATE bin:⟨b3⟩ CONTENT { label: 'Low' } RETURN AFTER;
CREATE bin:⟨b4⟩ CONTENT { label: 'Low' } RETURN AFTER;
COMMIT;
```

The result of the whole transaction is the nested pair of the results, or one `Aborted` error. The unique index refuses `b4`, so nothing is stored:

```text
Err(Aborted({ at: 1, error: Unique({ fields: ["label"], .. }) }))
```

| Part of the error | Meaning |
| --- | --- |
| `at` | The place of the statement that failed. `0` is the first part. The number of parts is the `COMMIT`, which fails with `Conflict` when another transaction changed the same records |
| `error` | The `ServerError` of that statement |

A transaction works the same on both transports, because it is one request. See [Errors in transactions](errors.md#errors-in-transactions).

### A list of statements in one transaction

`begin`, `then` and `commit` nest the result pair once for each statement, so the type depends on how many statements there are. When all statements give the same type, `Surreal.transaction` takes them as a list. It gives one `Prepared`, and its result is the list of the results, in order.

```roc
# Fragment: uses `bins` and `Bin` from examples/client.roc.
add_two : Bin, Bin -> Try(Surreal.Prepared(List(List(Bin))), Surreal.Error)
add_two = |first, second| Surreal.transaction([bins.create(first)?, bins.create(second)?])
```

The request is the same as the one of `begin().then(..).commit()`:

```surql
BEGIN;
CREATE bin:⟨b5⟩ CONTENT { label: 'Top' } RETURN AFTER;
CREATE bin:⟨b2⟩ CONTENT { label: 'Low' } RETURN AFTER;
COMMIT;
```

| Fact | Detail |
| --- | --- |
| Result | `Ok([[first_bin], [second_bin]])`, or one `Aborted({ at, error })`, where `at` is the place in the list. A twin of an existing label at place 1 gives `at: 1` |
| An empty list | `Err(Unsupported("a transaction needs a statement"))` |
| Statements of one type | The list has one type. For different types, use `begin`, `then` and `commit` |
| Items | Each item is a `Prepared`. `bins.create(first)?` gives one |

| Rule | Detail |
| --- | --- |
| An insert is a part of a transaction | `table.insert(rows)` runs in a transaction of its own. As a part, it joins this one. SurrealDB refuses a nested `BEGIN`, so the text has one |
| A transaction is a side of `then` | `commit()` gives a `Prepared`, so `a.then(tx)` works. Its `Aborted` is the error of that side |
| `LET` lines come first | They are before `BEGIN`. A name that two parts bind must have one value |
| No `THROW` and no `CANCEL` | The typed API does not write them. To abort on a condition, use a constraint of the schema (see [Constraints](schema.md#constraints)) |
| A part cannot read a key that another part made | See [Limits](#limits) |
| A list of parts | `Surreal.transaction([p, q, ..])` is the same transaction for statements of one result type |

## Unique errors need the schema

A unique index that fails gives a message with no field names. The session knows the fields only when you give it the schema. Call `knowing` with the definitions that you gave to `Surreal.schema`.

```roc
# Fragment: uses `opened` (a session) and `bin_def` from the scratch schema.
session = opened.knowing([bin_def])
```

`knowing` gives the session back, with no `Try`. A real run of the same `create` on both sessions:

```text
without: Err(Server(Index({ index: "bin_label_unique", record: "bin:b1", value: "'Top'", .. })))
with:    Err(Server(Unique({ fields: ["label"], index: "bin_label_unique", record: "bin:b1", table: "bin", value: "'Top'", .. })))
```

Without `knowing` the error is `Index`. With it the error is `Unique`, and you can match on the table and the fields (see [Match on an error](errors.md#match-on-an-error)). `Def.unique` makes the index (see [Unique keys and indexes](schema.md#unique-keys-and-indexes)).

## Sessions on basic-webserver

A handler on basic-webserver opens a session of its own, runs its statements and lets the session end with the request. The platform scopes a connection to the handler that opened it. Each read of the connection times out after 30 s.

| Need | What to do |
| --- | --- |
| Transport | `Transport.websocket` with `bws_ws.WsClient`. The adapter has no `receive_within!` |
| Session | Open it in the handler. Do not keep it between requests |
| Live query | Not in a handler. A watch waits for notices with no end |
| A query that runs longer than 30 s | Use `Transport.http`. A post that takes longer than 30 s is a `Transport` error |

```roc
# Fragment: uses `transport`, `login` and `readings_above` from examples/server.roc.
run! : I64 => Try(List(Reading), Str)
run! = |least| {
	prepared = readings_above(least).map_err(Str.inspect)?
	session = Surreal.Session.open!(transport, login).map_err(Str.inspect)?
	session.run!(prepared).result.map_err(Str.inspect)
}
```

From `examples/server.roc`, `run!`. The handler maps an `Err` to status 502. `examples/server.roc` has a comment with the HTTP form: the `http_client` of [Use HTTP](#use-http), with `Http.send!(request)`. For HTTP, add `import pf.Http` and `import http.Request` and drop the `bws_ws` package.

A real run on a scratch database with three readings:

```text
$ roc server.roc &
$ curl 'http://127.0.0.1:8071/readings?min_pulse=120'
kennel b at 2026-03-01T10:00:00Z: pulse 130, temp_c 39.0
kennel a at 2026-03-02T09:15:00Z: pulse 125, temp_c 38.0
```

The tables are in [Define a table](getting-started.md#define-a-table) and in `examples/monitoring.roc`.

## Limits

| Limit | What to do instead |
| --- | --- |
| A script app (no platform) cannot open a session | Print the script and load it with `curl`, or add a platform |
| Requests in flight have no order on the server | Put dependent steps in one `then`, or `await!` the first reply before the next `send!` |
| A `then` with a name bound to two values is `Unsupported` | Give the statements the same value, or run them as two requests |
| `then` is not atomic | Use a transaction |
| A part of a transaction cannot read a key that another part made in the same request | Read it in a later request |
| `THROW` and `CANCEL` are not in the typed API | Use `Def.assert` or `Def.check` in the schema |
| A transaction can fail with `Conflict` at its `COMMIT` | Run it again. The package does not retry |
| Over HTTP there is no `live!`, `next!`, `stream` or `kill!` | Use a WebSocket transport |
| `next_within!` needs `Transport.websocket_timed` and an adapter with `receive_within!` | On basic-webserver, do not wait for a watch |
| A `Transport` or `WebSocket` error ends the session | Open a new session |
| A session on basic-webserver lives for one request | Open a session in each handler |
| The inbox keeps every notice of a watch until you read it | Read the watch, or call `kill!` |
