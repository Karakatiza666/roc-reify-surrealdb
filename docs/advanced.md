# Escape hatches and extensions

This page shows what to do when the typed API has no form for your task. You send raw SurrealQL, read every field of a table, teach the translator a function of another package, and test a live query with the Mirror.

| You want to | Use | Section |
| --- | --- | --- |
| Send SurrealQL text | `Surreal.Unchecked.query!` | [Raw SurrealQL](#raw-surrealql) |
| Read a reply as a type of your choice | `Surreal.Unchecked.decode` | [Read the reply](#read-the-reply) |
| Read every field of a table, or use `FETCH` | `Surreal.Unchecked.select_star`, `Surreal.Unchecked.fetch` | [Select every field](#select-every-field) |
| Name a row of a table by text | `Surreal.Unchecked.id` | [Ids by table name](#ids-by-table-name) |
| Call a function of a type from another package in a clause | `Surreal.extension` | [Extend the translator](#extend-the-translator) |
| Predict the notices of a live query in a test | `Surreal.Mirror` | [Test with the Mirror](#test-with-the-mirror) |

Some tasks need no escape hatch. A time series has its own key type ([Time series keys](data-types.md#time-series-keys)) and its own range query ([Read a range of a time series](queries.md#read-a-range-of-a-time-series)). A database function has a typed form ([Database functions](functions.md#database-functions)).

The module name `Unchecked` shows in the code that uses it. A reviewer sees each place where a type does not check the text.

## Raw SurrealQL

`Surreal.Unchecked.query!(session, text)` sends one request with your text. It gives the new session and the reply:

| Part | Type | Meaning |
| --- | --- | --- |
| Argument | `Session`, `Str` | The session from `Session.open!` and any SurrealQL |
| Success | `{ session : Session, reply : List(U8) }` | The session for the next call, and the bytes of the reply |
| Failure | `Surreal.Error` | The connection or a message failed (see [Connection errors](errors.md#connection-errors)). A failed call gives no session (see [Open a session](sessions.md#open-a-session)) |

Nothing checks the text. The server answers a statement that it refuses with a reply, not with an `Err`. A syntax error gives `Ok` with the error inside the reply bytes.

Use raw text for a statement that the typed API does not have:

| Statement | Why it is raw |
| --- | --- |
| `DEFINE ACCESS` with `TYPE JWT` or `TYPE BEARER` | See the limits of [Record users and permissions](access.md#limits) |
| `SHOW CHANGES FOR TABLE` | The package has no call to read a changefeed (see [Changefeeds](schema.md#changefeeds)) |
| `REMOVE DATABASE`, `DEFINE DATABASE` | Setup and clean-up of a test database, as in `examples/watch.roc` |
| `THROW`, `CANCEL` and other statements | The typed API has no form |

### Read the reply

The reply is a CBOR message. `Surreal.Unchecked.decode(reply)` reads it as any type that you write. A value that does not fit the type is a `Decode` error with the path of the value.

A reply to a request that the server accepted has one entry for each statement, in order. Each entry has a `status` (`"OK"` or `"ERR"`) and a `result`. The `result` is the rows, or the message text when the status is `"ERR"`. The program reads only the fields that your type names.

```roc
# Fragment: uses `session`, `Surreal` and the `Owner` row from examples/main.roc.
Statements(a) : { result : List({ status : Str, result : a }) }

made = Surreal.Unchecked.query!(session, "SELECT * FROM owner;")?
rows : Try(Statements(List({ id : Surreal.Id(Owner), name : Str })), Surreal.Error)
rows = Surreal.Unchecked.decode(made.reply)
```

A real run read the row `owner:jon` as `{ id: { key: "jon", table: "owner" }, name: "Jon" }`. The field `address` of the row is not in the type, so the read ignores it.

Choose the type of `result` for the statement. A `DEFINE` statement gives no value. If you need only the statuses, name `{ result : List({ status : Str }) }` and leave `result` out.

A request that the server refuses as a whole has no `result`. The reply holds an `error` instead. With the syntax error `SELEC name FROM owner`, `decode` gave a `Decode` error (the message is ``a map has no field `result` ``). Read it as `{ error : { code : I64, message : Str } }` to get the message.

### Read a reply as a typed statement

When the text came from a `Prepared`, use `Surreal.Unchecked.result(session, prepared, reply)`. It reads the reply as `Session.run!` does and gives `Try(out, Error)`. It uses the schema that the session knows, so a unique violation reads as `Unique` (see [Unique errors need the schema](sessions.md#unique-errors-need-the-schema)). It is a pure function.

```roc
# Fragment: uses `session` and `prepared` (a `Prepared(List(Card))`).
sent = Surreal.Unchecked.query!(session, prepared.request()?)?
card_rows = Surreal.Unchecked.result(sent.session, prepared, sent.reply)
```

This is how `examples/client.roc`, `send!`, saves each reply to a file before it reads it. With the syntax error above, `result` gave `Err(Server(Parse(..)))`, and `decode` gave `Decode`. Use `result` when you have a `Prepared`. See [Server errors](errors.md#server-errors) for the tags.

### What raw text does not do

| Case | What happens |
| --- | --- |
| A `LIVE` statement in the text | The session does not watch it. The inbox drops its notices. Use `session.live!(watch)` (see [Start a watch](live-queries.md#start-a-watch)) |
| A statement of a transaction | You write `BEGIN` and `COMMIT` in the text yourself. The typed `begin()` and `commit()` do not apply |
| Other frames before the reply | They go into the inbox of the session, as for `run!` |

## Select every field

`Surreal.Unchecked.select_star(query)` reads `SELECT *`. It takes a `Query(p, row)` and gives a `Selected(p, Surreal.Unchecked.Row)`. Filters that come before it stay.

`Surreal.Unchecked.fetch(selected, path)` replaces the record ids at a column of the result with the rows they point at. The path is text, written as it is. It is a column of the result, not a field of the Roc row.

```roc
# Fragment: uses `Pet` and `pets` (a table with `owner : Surreal.Link(Owner)`).
all = Surreal.Unchecked.select_star(Surreal.from(pets).filter(|p| p.name == "Rex"))
with_owner = Surreal.Unchecked.fetch(all, "owner")
```

The SurrealQL of `all` and of `with_owner`:

```surql
SELECT * FROM pet WHERE name = 'Rex'
SELECT * FROM pet WHERE name = 'Rex' FETCH owner
```

`Unchecked.Row` has no fields in Roc and no decoder. Send the text with `query!` and read the reply with `decode` and a type of your own. A real run read the second statement as `{ id : Surreal.Id(Pet), name : Str, owner : { id : Surreal.Id(Owner), name : Str } }`. The `id` of each row is a record id, so the type of `id` is `Surreal.Id(row)`, not `Str`.

| Call after `select_star` | Result |
| --- | --- |
| `to_surql()` | The text above |
| `fetch(path, ..)` several times | One `FETCH` list: `FETCH customer, items[*].product` |
| `limit(n)`, `start(n)` | Work as for any `Selected` |
| `filter(f)`, `query()` | Work. A `filter` reads no field of the row, because the row has none. `fetch` before `query()` stays in the subquery. `select` after `query()` is `Err(Unsupported(..))`: a whole row is `Surreal.Unchecked.Row` |
| `prepare(..)` | Compile error: `Surreal.Unchecked.Row` has no `parser_for` |
| `live(..)` | `Err(Unsupported("a live query sends typed rows, and `Unchecked.select_star` has no row type; select the fields with `select`"))` |

To read fields through a link with types, use a read row ([Read rows](links-and-graphs.md#read-rows)) or `get()` ([Read through a link](selecting-fields.md#read-through-a-link)). Both need no `FETCH`.

## Ids by table name

`Surreal.Unchecked.id(table_name, key)` makes an `Id(row)` of any table, by the name of the table as text. `table.id(key)` does the same, but the table checks the name. Use `Unchecked.id` when no `Table` value is in scope, such as for an id that you read from a raw reply.

A call that takes an `Id` checks the table name when you prepare the statement. An id of another table is refused:

```roc
# Fragment: uses `owners` from examples/main.roc.
ok = owners.at(Surreal.Unchecked.id("owner", "jon")).select(|o| { name: o.name }).to_surql()
no = owners.at(Surreal.Unchecked.id("vet", "jon")).select(|o| { name: o.name }).to_surql()
```

`ok` is `Ok("SELECT name AS name FROM owner:⟨jon⟩")`. `no` is `Err(Unsupported("the id `vet:⟨jon⟩` is of the table `vet`, not of `owner`"))`.

## Extend the translator

The translator knows the Roc builtins and the functions of `Surreal`. It cannot know a function of a type from another package, such as a temperature type that hides its representation. A clause that calls such a function is refused.

An extension tells the translator the SurrealQL of those functions. Each function is named by the id that the compiler gives it, `Code.prim(f)`. The id is exact: two functions with the same name in two packages never meet. The compiler docs explain ids and extensions in [Extending a Translator](https://github.com/Karakatiza666/roc/blob/reify/docs/langref/reifying.md#extending-a-translator).

| Part | What to write |
| --- | --- |
| `Surreal.extension({ prims })` | A list of `{ prim, render }`. It gives a `Surreal.Extension` |
| `prim` | `Code.prim(Temperature.is_gt)`: the id of the function |
| `render` | `{ args : List(Str), evidence : List(Code.Evidence) } -> Try(Str, Str)`. It gets the SurrealQL of each argument and gives the SurrealQL of the call, or the reason why it has none |
| `query.filter_with([ext], f)` | Like `filter`, with your extensions. The filter can read values from around the function (see [Use values from around the function](queries.md#use-values-from-around-the-function)) |
| `Surreal.library` | The extension with the functions of `Surreal`. The package always adds it. You do not pass it |

An operator puts its own parentheses. The type `Temperature` comes from `tests/Temperature.roc`: an opaque type over `Dec` with `from_celsius`, `celsius`, `is_gt` and `is_lt`, and `encoder_for : _`. Here the extension covers `from_celsius`, `celsius` and `is_gt`:

```roc
# Fragment: uses `Temperature` from tests/Temperature.roc and `readings` (a table of `{ id, patient, temp_c : Dec }`).
temperature_surreal = Surreal.extension({ prims: [
	{ prim: Code.prim(Temperature.from_celsius), render: only },
	{ prim: Code.prim(Temperature.is_gt), render: binary(">") },
] })

fever : Temperature -> Surreal.Prepared(List(Reading))
fever = |limit| Surreal.from(readings).filter_with([temperature_surreal], |r| Temperature.from_celsius(r.temp_c) > limit).ready()
```

From `tests/ExtensionTest.roc:57`, `temperature_surreal` and `fever`. The functions `only` and `binary` are in the same file. `only` takes one operand and returns it. `binary(op)` joins two operands with `op`. The script of `fever(Temperature.from_celsius(38.5)).request()` from a real run:

```surql
LET $_1 = 38.5dec;
SELECT record::id(id) AS id, patient, temp_c FROM reading WHERE (temp_c > $_1);
```

Without the extension, or for a function that the extension does not cover, the statement holds an error. `checked()` and `request()` give it. A real run gave these two:

| Case | Result |
| --- | --- |
| `filter_with([], ..)` with `>` | `Err(Unsupported("in `filter_with`: `Temperature.is_gt` has no SurrealQL form"))` |
| The extension above with `<` | `Err(Unsupported("in `filter_with`: `Temperature.is_lt` has no SurrealQL form"))` |

`Temperature.is_gt` and `Dec.is_gt` have two ids. The extension for the first never changes the meaning of `>` on a `Dec`.

### Captured values of your type

A value of your type that the clause captures (`limit` above) is a bound value. The type needs `encoder_for : _` in its declaration. The package binds the value as the encoder writes it: a temperature is its `Dec`. The field of a captured record, such as `ward.alarm`, is one bound value too.

A captured `Surreal.Id` or `Surreal.Datetime` is a compile error in `filter_with`. Capture its text, or use `filter`.

## Test with the Mirror

`Surreal.Mirror` is the Roc model of what a live query sends. It calls the same Roc functions that the clauses use, over rows that you hold. An application does not need it. A test uses it to compare the server with Roc.

[Predict notices in Roc](live-queries.md#predict-notices-in-roc) lists `notices`, `edge_notices`, `read_notices`, `events` and `step_all`. This section covers the rest.

| Call | Gives |
| --- | --- |
| `table.edit(Create(row))`, `Replace(old, new)`, `Delete(row)` | The write itself as a `Prepared(List(row))` |
| `table.ref(row)` | The `Ref` (record id) of a row: `Try(Ref, Error)` |
| `view.group_ref(key)` | The `Ref` of a row of a view, from its group key |
| `ref.to_str()` | The record id as text |
| `Mirror.literal(value)` | A Roc value as a SurrealQL literal |
| `Mirror.notices_literal(lists)`, `Mirror.events_literal(lists)` | The expected notices or events of each write, as a literal |

With `jon : Owner` in the table `owners`, a real run gave:

| Call | Result |
| --- | --- |
| `owners.ref(jon).map_ok(\|r\| r.to_str())` | `Ok("owner:⟨jon⟩")` |
| `per_city.group_ref({ city: "Oslo" })` | `Ok("owner_per_city:['Oslo']")` |
| `owners.group_ref({ city: "Oslo" })` | `Err(Unsupported("`owner` is not a view, so its rows have no group key"))` |

`group_ref` takes the group key as a record. The key parts come in the name order of the record, which is the order of `GROUP BY`. A normal table or an edge table has no group key.

`Table.edit` gives the statement of each write:

```surql
CREATE owner:⟨jon⟩ CONTENT { address: { city: 'Oslo', line: 'Main 1' }, name: 'Jon' } RETURN AFTER;
UPDATE owner:⟨jon⟩ CONTENT { address: { city: 'Bergen', line: 'Quay 2' }, name: 'Jon' } RETURN AFTER;
DELETE owner:⟨jon⟩ RETURN BEFORE;
```

For `Create(jon)` and a filter `in_oslo`, `Mirror.notices` gave one notice with `action: Create`, `role: Node` and `now: True`. For `Replace(jon, moved)`, where `moved` lives in Bergen, it gave `action: Update` and `now: False`. The row left the result, and the filter is false after the write.

### Check blocks for check.py

`tests/check.py` runs the scripts of the examples on a server and compares each result with the Roc result. The package writes the scripts, and the Mirror writes the expected values.

| Step | Call |
| --- | --- |
| Make the reference | `Surreal.Mirror.literal(rows.keep_if(in_oslo).map(card))` |
| Make the block | `prepared.statement()?.block("-- query: in_oslo", ["-- roc: ${expected}"])` |
| Make a live block | `watch.block(header, directives, writes)?`, with `Mirror.notices_literal` in `directives`. It gives a `Try` |
| Run | `python3 tests/check.py "$ROC"` |

The block that a real run printed:

```surql
-- query: in_oslo
-- roc: [{ id: 'jon', name: 'Jon' }]
SELECT record::id(id) AS id, name AS name FROM owner WHERE address.city = 'Oslo';
```

`examples/monitoring.roc` has the full set (`block`, `vital_notices`), and the README explains the checker in [Testing](../README.md#testing). The live blocks of `examples/watch.roc` check the notices that the server sends against `Mirror.notices`.

## Limits

| Limit | What to do instead |
| --- | --- |
| `Unchecked.query!` does not check the text or the type of the reply | Read the reply with a type that matches the statement. Prefer the typed API when it has the form |
| A refused statement is in the reply, not an `Err` | Check `status`, or read the reply with `Unchecked.result` when you have a `Prepared` |
| A `LIVE` in raw text is not watched | Use `live!` |
| `select_star` has no row type: no `prepare`, no `live` | Send the text with `query!` and read it with `decode`, or select the fields with `select` |
| `fetch` takes a path as text and nothing checks it | Test the text against a server |
| Only `filter_with` takes an extension, and only for the filter of a query on whole rows | For a column or a schema clause, send raw text with `Unchecked.query!` |
| An extension gives the SurrealQL of calls only. A field of an opaque type has no SurrealDB type, so a row cannot hold one (`BadSchema`) | Store the plain type (`Dec`), and convert at the edge of the program |
| A captured `Id` or `Datetime` is a compile error in `filter_with` | Capture the text, or use `filter` |
| The Mirror has no call for `live_diff` | Compare the patches with the server |
| The Mirror is for tests. It makes no request | Run the same writes on a server and compare |
