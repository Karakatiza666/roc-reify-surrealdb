# Live queries

A live query keeps the result of a query current. You start a watch. SurrealDB then sends a notice for each write that changes the result. The package turns each notice into a change of the result: a row was added, updated or removed.

```
Selected --live(params, definitions)--> Watch(out)
                                           |  session.live!(watch)
                                           v
                     { session, live : Live(out), view : View(out) }
                                           |
           session.next!(live)    session.next_within!(live, ms)    session.kill!(live.lives())
              Got(changes)              Got | TimedOut                    Ended
```

The terms "clause", "Mirror" and "read row" are in the [glossary](getting-started.md#words-used-in-these-pages). A live query needs a WebSocket session (see [Choose a transport](sessions.md#choose-a-transport)). The example app is `examples/watch.roc`.

## Start a watch

Call `live(params, definitions)` where you would call `prepare(params)`. It takes the same clauses and gives the same refusals. It gives `Watch(out)` in place of a `Prepared`. A query with no parameter takes `ready_live(definitions)`, which is `live({}, definitions)`. A `Query` has both too, and its watch holds the whole rows (see [The whole row](selecting-fields.md#the-whole-row)).

| Argument | Meaning |
| --- | --- |
| `params` | The parameter record of `filter_by`. Use `ready_live` when there is none. The values are fixed when the watch starts |
| `definitions` | The list that `Surreal.schema` takes. A link of the row finds its table there |

```roc
# Fragment: uses `vitals`, `VitalLine`, `vital_line` and `definitions` from examples/watch.roc.
fevered : Surreal.Watch(VitalLine)
fevered = Surreal.from(vitals).filter(|v| v.temp_c > 39.0).select(vital_line).ready_live(definitions)
```

From `examples/watch.roc`, `fevered`. The example calls a database function in the filter. This fragment uses a plain comparison. `watch.request()` gives the text that goes to the server, from a real run:

```surql
LIVE SELECT VALUE { row: { at: record::id(id)[1], kennel: record::id(id)[0], pulse: pulse, temp_c: temp_c }, now: temp_c > 39.0dec } FROM vital WHERE (temp_c > 39.0dec) OR ($before IS NOT NONE AND ($before.temp_c > 39.0dec));
SELECT VALUE { ref: id, row: { at: record::id(id)[1], kennel: record::id(id)[0], pulse: pulse, temp_c: temp_c } } FROM vital WHERE temp_c > 39.0dec;
```

The first statement is the watch. It reads the filter on the row after the write and on `$before`, the row before the write. So a row that leaves the filter is reported. The second statement is the snapshot: the rows in the result now. The `LIVE` comes first, so no write between the two is lost. A parameter gives a `LET $min = 39.0dec;` line before them.

Start the watch on a session:

```roc
# Fragment: uses `transport` and `login` from examples/watch.roc, and `fevered` from above.
session = Surreal.Session.open!(transport, login).map_err(Str.inspect)?
started = session.live!(fevered).map_err(Str.inspect)?
```

`live!` gives `{ session, live, view }`.

| Field | Type | Use |
| --- | --- | --- |
| `session` | `Session` | The session for your next call |
| `live` | `Live(out)` | The state of the watch. Pass it to `next!`, `next_within!`, `stream` and `kill!` |
| `view` | `View(out)` | The snapshot, by record |

A `View` has `rows()` (the rows), `members()` and `apply(change)`. Call `view.apply(change)` for each change to keep your copy of the result current. The Roc `View` has no order. Sort the rows yourself.

A session over HTTP cannot watch. `live!`, `next!`, `stream` and `kill!` give `Err(Unsupported(..))` with the text `a watch reads the messages that the server pushes, and this session's connection gives none`. `session.pushes()` tells you before you try.

There are three kinds of watch:

| Call | Gives | Reports | Section |
| --- | --- | --- | --- |
| `selected.live(params, definitions)` | `Watch(out)` | Changes of the result, with the clauses applied | This page |
| `selected.live_raw(params)` | `RawWatch(out)` | The events that the server sends, as they are | [Raw events](#raw-events) |
| `query.live_diff(params)` | `DiffWatch(row)` | The patches of each write to a stored row | [Patches of stored rows](#patches-of-stored-rows) |

## Read changes

Call `session.next!(live)`. It waits for the next notice that changes the result. It gives `{ session, live, next }`.

| `next` | Holds | When |
| --- | --- | --- |
| `Got(changes)` | `List(Change(out))` | A notice that changes the result |
| `Ended` | | The watch is stopped (see [Stop a watch](#stop-a-watch)) |
| `Unread(error)` | `Error` | A notice does not read as `out`. The watch goes on |
| `TimedOut` | | `next_within!` only: no message came in time |

A `Change(out)` is one of three tags. Each has the `Ref` of the record and the row.

| Tag | Meaning |
| --- | --- |
| `Added(ref, row)` | The row enters the result |
| `Updated(ref, row)` | A row of the result changes |
| `Removed(ref, row)` | The row leaves the result. `row` is the last row: the old row of a delete, the new row of a row that no longer matches |

`ref.to_str()` gives the record id, such as `vital:[kennel:⟨a⟩, d'2026-03-09T10:00:00Z']`.

```roc
# Fragment: uses `started` from above. `Stdout` is `import pf.Stdout`.
got = started.session.next!(started.live).map_err(Str.inspect)?
match got.next {
	Got(changes) => Stdout.line!("${changes.len().to_str()} changes").map_err(Str.inspect)?
	Ended => Stdout.line!("ended").map_err(Str.inspect)?
	Unread(e) => Stdout.line!(Str.inspect(e)).map_err(Str.inspect)?
}
# the next call uses got.session and got.live
```

Each call gives the session and the watch after it. Use those two for the next call. An old copy has an older inbox.

### Wait with a deadline

`next!` waits with no end. The server pings the session every 5 s, so the read timeout of the adapter does not end the wait. Call `session.next_within!(live, ms)` to bound it. It gives the same result with the tag `TimedOut`.

| Rule | Detail |
| --- | --- |
| Transport | `Transport.websocket_timed`, over an adapter with `receive_within!` (roc-basic-cli-websocket has one) |
| Other transports | `Transport.websocket` (basic-webserver) and HTTP give `Err(Unsupported(..))` before anything is read |
| Notices already received | The inbox gives them first, with no wait |
| `TimedOut` | Nothing is lost. Use the session and the watch that the call gave back |
| What `ms` bounds | The wait for one message. A message that gives no change (a reply, a notice of another watch) starts the wait again. A ping does not count |

[Choose a transport](sessions.md#choose-a-transport) shows how to build `websocket_timed`.

### Read as a stream

`session.stream(live)` gives a `Stream(Try({ item, session, live }, Error))` for any kind of watch. Each item holds the session and the watch after it, so you can stop and use that session. The stream ends when the watch ends. It waits as `next!` does, with no deadline.

### A real run

The app starts `fevered` on a scratch database that holds one fever reading. A second session writes from another connection. Each line is printed after one call of `next_within!`.

```text
snapshot: 1 rows
TimedOut after 500 ms
Got Added vital:[kennel:⟨a⟩, d'2026-03-09T10:00:00Z'] pulse 90 temp_c 40.1
Got Removed vital:[kennel:⟨a⟩, d'2026-03-09T08:00:00Z'] pulse 80 temp_c 38.0
TimedOut after 500 ms
Ended
```

| Step | Write | Result |
| --- | --- | --- |
| 1 | None | `TimedOut` after 500 ms |
| 2 | Session A creates a reading of 40.1 | `Added` |
| 3 | Session B changes the fever reading to 38.0 | `Removed`, with the new row: it leaves the filter |
| 4 | Session B creates a reading of 38.2 | `TimedOut`: it is not in the result and does not match |
| 5 | `kill!`, then a write of a reading of 41.0 | `Ended` |

A write from `curl` to `/sql` gives the same notice. The watch sees every write to the table, from any client.

## Stop a watch

Call `session.kill!(live.lives())`. It gives `Try(Session, Error)`.

```roc
# Fragment: uses `got` from above.
stopped = got.session.kill!(got.live.lives()).map_err(Str.inspect)?
```

From `examples/watch.roc`, `check_watch!`. `live.lives()` is the list of the live queries of the watch: one for the table, and one for each other table that the clauses read. `kill!` ends each of them.

| After `kill!` | What happens |
| --- | --- |
| The queued notices of the watch | The inbox drops them |
| A notice that comes later | The inbox drops it |
| `next!` and `next_within!` on that watch | `Ended` |
| The notices of other watches on the session | They stay |

The inbox keeps each notice of a watch until you read it or call `kill!`. It has no limit. Call `kill!` on a watch that you no longer read.

## What a live query watches

A watch has a `LIVE SELECT` on the table of the query. It has one more `LIVE SELECT` for each other table that the clauses read. The fields and links that the clauses read decide this, not the row type. [Choosing the fields to read](selecting-fields.md#how-field-reads-decide-what-a-live-query-watches) gives the short rule. This section gives every case.

| The clauses read | Statement (role) | A write there sends |
| --- | --- | --- |
| Fields of the row, and its filter | The table of the query (`Node`) | One notice with the row and `now` |
| An edge table: `outgoing`, `incoming`, `and_outgoing`, `and_incoming`, `edges_from` or `edges_to` of the row, or an `Out` or `In` field of a read row | The edge table (`Edge`) | One notice for each edge write, with the node at the end of the edge after the write |
| A table that a link points at, read through `.get()` or a `Linked` field, at any hop | The linked table (`Read`) | One notice for each row of the result that links to the written record |
| A table of `rows()` in a filter or a projection | The other table (`Read`) | One notice for each row of the result that the written row is related to, before or after the write (see [Only the rows that a write reaches](#only-the-rows-that-a-write-reaches)). One notice for each row of the result when the clause gives no relation |
| The edge table of `edges_from` or `edges_to` of a record other than the row | The edge table (`Read`) | One notice for each row of the result |

The links of read rows are in [Ids, links and graph edges](links-and-graphs.md#read-rows). Edges are in [Traverse edges](links-and-graphs.md#traverse-edges). `rows()` is in [Read other tables in a clause](links-and-graphs.md#read-other-tables-in-a-clause).

Each notice has `now`: the filter after the write. The package keeps the set of records in the result (`live.members()`, set by the snapshot). It sorts each notice into a change:

| Notice | In the result | `now` | Change |
| --- | --- | --- | --- |
| A delete of the row | yes | | `Removed`, with the old row |
| A delete of the row | no | | none |
| Any other | no | true | `Added` |
| Any other | yes | true | `Updated` |
| Any other | yes | false | `Removed`, with the new row |
| Any other | no | false | none |

A write between the `LIVE` and the snapshot comes again as a notice. It gives `Updated`, not a second `Added`. A notice of an edge whose node is deleted gives nothing: the delete of the node comes next.

### Only the fields that the clauses read

A statement on a linked table tests the fields that the clauses read. An update that changes none of them sends nothing. A create and a delete always send. For this watch:

```roc
# Fragment: uses `kennels` and `definitions` from examples/watch.roc.
Surreal.from(kennels).select(|k| { label: k.label, site: k.site.get().name }).ready_live(definitions)
```

From `examples/watch.roc`, `kennel_sites`. The second statement is, from a real run:

```surql
LIVE SELECT VALUE (SELECT VALUE { ref: id, row: { label: label, site: site.name }, now: true } FROM kennel WHERE site = $parent.id) FROM site WHERE $before IS NONE OR $after IS NONE OR $before.name != $after.name;
```

`$parent` is the written site. The payload is the kennels that link to it. So one write to a site sends one notice for each kennel at the site, or none. Two links to one table are one statement, and so are two fields of it. A second hop (`b.kennel.get().site.get().name`) is one statement for each table, with a test such as `kennel.site = $parent.id`.

### Only the rows that a write reaches

A clause that reads a table with `rows()` and keeps, finds or counts its rows with an equality to a value of the row gives a relation. A write to that table then sends a notice only for the rows of the result that the written row is related to. For this watch:

```roc
# Fragment: uses `kennels`, `vitals`, `has_fever` and `definitions` from examples/monitoring.roc.
Surreal.from(kennels).filter(|k| has_fever(vitals.rows(), k)).select_value(|k| k.label).ready_live(definitions)
```

From `examples/monitoring.roc`, `fevered_kennels`. `has_fever` reads `rows.keep_if(|v| v.id.series() == kennels.id(k.id))`. The two statements are:

```surql
LIVE SELECT VALUE { row: label, now: true } FROM kennel WHERE id.chain(|$v1| (SELECT VALUE id FROM vital:[$v1, NONE]..=[$v1, ..])).any(|$v2| $v2.fevered);
LIVE SELECT VALUE (SELECT VALUE { ref: id, row: label, now: id.chain(..).any(..) } FROM record::id($parent.id)[0]) FROM vital;
```

A write to a reading sends one notice, for the kennel of its key. Before, it sent one for each kennel (300 notices for each write with 300 kennels; now 1, on SurrealDB 3.3.5 and 4.0.0).

| The function over the rows of `rows()` | Rows of the result that a write reaches | Payload of the `read` statement |
| --- | --- | --- |
| `x == v` where `x` reads only the key of the element (`v.id.series()`, `v.id`) and `v` is a value of the row | The row that the written key names. A write never changes a key | `FROM <x of $parent>`, or `WHERE <v> = <x of $parent>` when `v` is not the record id of the row |
| `x == v` where `x` reads a field of the element (`o.customer.id()`) | The rows that the written row names before the write and after it. A row that moves from one row of the result to another reaches both | `FROM array::distinct([$before, $after].filter(..).map(\|$w\| <x of $w>))`, or `WHERE <v> IN ..` |
| `xs.contains(v)` where `xs` is a list of the element (`c.tags`) | The rows whose value is in the list, before or after the write | `WHERE <v> IN array::distinct(array::flatten(..))` |
| `xs.any(\|x\| x.f == v)` where `xs` is a list of the element (`r.stops`), and `x.f` a path of `x`; also an `any` in that function | The rows that the list names, before or after the write | `FROM array::distinct(array::flatten(..map(\|$w\| $w.stops[*].kennel)))`. A list of lists has one `array::flatten` more for each level |
| Any other function, or one more read of the same table without a relation | Every row of the result's table | `FROM <table>` |

The relation is a conjunct of the function: `|o| o.customer.id() == customers.id(c.id) and o.total > 10` has one. `Surreal.Mirror.related` gives the same rows in Roc.

From `examples/monitoring.roc`, `kennel_rounds` counts the rounds whose list of stops links to the kennel:

```roc
# Fragment: uses `kennels`, `rounds` and `definitions` from examples/monitoring.roc.
Surreal.from(kennels).select(|k| { label: k.label, rounds: rounds.rows().count_if(|r| r.stops.any(|st| st.kennel.id() == kennels.id(k.id))) }).ready_live(definitions)
```

```surql
LIVE SELECT VALUE (SELECT VALUE { ref: id, row: { label: label, rounds: $this.chain(|$v1_0| (SELECT VALUE id FROM round WHERE $v1_0.id IN stops[*].kennel)).len() }, now: true } FROM array::distinct(array::flatten([$before, $after].filter(|$w| $w != NONE).map(|$w| $w.stops[*].kennel)))) FROM round;
```

A write to a round sends a notice for each kennel that it stops at, before or after the write. With 300 kennels and 15 writes, it sent 300 notices for each write before, and now 1 to 3 (SurrealDB 3.3.5 and 4.0.0).

### A filter that reads only the record id

A filter that reads the row only through its record id and its edges (`id`, `<-cares_for`) has the same value before and after a write of the row. The node statement then tests it once, and each notice has `now: true`:

```surql
LIVE SELECT VALUE { row: { carers: <-cares_for.len(), label: label }, now: true } FROM kennel WHERE <-cares_for.len() = 0;
```

A filter that reads another field of the row is tested three times on each write: in `now`, in `WHERE`, and on `$before`. SurrealDB 3.3.5 and 4.0.0 do not let `WHERE` read a projection alias or a `LET` in a `LIVE SELECT`.

### What is not watched

A real run on a scratch database, with the watches `label_only` (`{ label: k.label }`) and `kennel_sites` above, one kennel at one site:

| Write | `label_only` | `kennel_sites` |
| --- | --- | --- |
| New name of the site | nothing | `Updated`, with the new name |
| New `region` of the site, which no clause reads | nothing | nothing |
| New label of the kennel | `Updated` | `Updated` |

| Case | What happens | What to do |
| --- | --- | --- |
| A link that no clause reads through | Its table is not watched. A write there sends nothing | Read a field through the link, such as `k.site.get().name` |
| A link read as an id: `k.site.id.key()` or `link.id` | No statement on `site`: the request has only the `LIVE` on `kennel` | Read through `.get()` if the linked row matters |
| The length of a list of links: `t.sites.len()` | No element is read, so no statement on the linked table | Read a field of the elements |
| An `Id` field | Not watched, by design. A clause cannot read the row of an `Id` | Use a `Link` and `.get()` |
| A linked row that a `map` returns, such as `t.sites.map(\|s\| s.get())` | The row is read whole. The statement has no field test, so an update of any field of it sends a notice. This holds when a later step reads one field of it | Read the field inside the `map`: `t.sites.map(\|s\| s.get().name)` |
| An `Out` or `In` field of a linked row | The edges are not watched. This is a gap that a later version can close | Watch the edge table with a query of its own |
| `edges_from` or `edges_to` of a linked row, or of a row that a `map` reads | The statement is on the whole edge table. A write of any edge of it sends a notice for each row of the result | Watch the edge table with a query of its own |
| A write that changes no field | Nothing, on every statement | None |
| A filter that raises an error in SurrealDB | The notice is dropped. The guard `$before IS NOT NONE` keeps a filter that reads the old row from failing on a create | Test the filter on rows with missing values |
| A table that is not in `definitions` | `live` gives `BadSchema` | List the table of each link of the row |

For a link whose table is not listed, `live` gives:

```text
BadSchema("a live query watches the table of each link of its row, and the tables it takes do not name the one at `site`: no table holds the row type `{ id : Str, name : Str }`; list its table in the schema")
```

## Raw events

`live_raw(params)` is on `Selected`. It gives a `RawWatch(out)`. It reports what the server sends, with no snapshot and no `now`. Start it with `session.live!` as any watch. `view` is `{}`. `next!` and `next_within!` give `Got(event)`.

| `Event(out)` | Meaning |
| --- | --- |
| `Created(ref, row)` | A row is created and matches the filter |
| `Updated(ref, row)` | A row that matches is updated. A row that starts to match is `Updated`, not `Created` |
| `Deleted(ref, row)` | A row that matches is deleted |

The request is one `LIVE SELECT` (from a real run, for `filter(|v| v.temp_c > 39.0).select(vital_line)`):

```surql
LIVE SELECT VALUE { at: record::id(id)[1], kennel: record::id(id)[0], pulse: pulse, temp_c: temp_c } FROM vital WHERE temp_c > 39.0dec;
```

A real run of four writes to one reading:

| Write | Event |
| --- | --- |
| Create a reading of 39.6 | `Created` |
| Change it to 38.0 | nothing in 700 ms: a row that leaves sends nothing |
| Change it back to 39.6 | `Updated` |
| Delete it | `Deleted` |

A raw watch reports the table only. A write to an edge table, or to a table that the rows read, sends nothing. Use `live` when you need the leave, the edges or the links.

## Patches of stored rows

`live_diff(params)` is on `Query`, before `select`. It takes filters and no projection. It gives a `DiffWatch(row)`. Each write sends a `Patch(row)`: the JSON Patch ops that the write made to the stored row.

| Call | Gives |
| --- | --- |
| `patch.ref()` | The `Ref` of the record |
| `patch.action()` | `Create`, `Update` or `Delete` |
| `patch.ops()` | The list of `Op` values |
| `patch.field(\|v\| v.temp_c)` | `Try([Untouched, Set(a), Unset, Inside], Error)`: what the patch did to one field |

A create replaces the whole row. A delete replaces it with `NULL`. `field` reads the last op that reaches the field. `Inside` means an op below the field, or a text change.

`DiffView(row)` keeps the stored rows as values. Make it with `Surreal.DiffView.empty({})` or take `view` from `live!`.

| Call | Gives |
| --- | --- |
| `view.apply(patch)` | `Try(DiffView(row), [UnknownRef(Ref), BadPath(Pointer), Mismatch(U64)])`. A create adds the row, a delete removes it |
| `view.get(ref)` | `Try(row, [UnknownRef(Ref), Unreadable(Error)])` |
| `view.rows()` | `Try(List(row), Error)` |
| `view.refs()` | The `Ref` of each row |

```roc
# Fragment: uses `vitals` and `Vital` from examples/watch.roc. `view` starts as `Surreal.DiffView.empty({})`.
vital_patches : Try(Surreal.DiffWatch(Vital), Surreal.Error)
vital_patches = Surreal.from(vitals).live_diff({})

# for each Got(patch):
#   view = view.apply(patch)?
#   temp = patch.field(|v| v.temp_c)?
```

From `examples/watch.roc`, `vital_patches` and `check_patches!`. The request is `LIVE SELECT DIFF FROM vital WHERE temp_c > 39.0dec;` for the filter above. A real run of a create, an update and a delete of one reading:

```text
Create vital:[kennel:⟨a⟩, d'2026-03-09T08:00:00Z'] temp_c Set(39.6)
Update vital:[kennel:⟨a⟩, d'2026-03-09T08:00:00Z'] temp_c Set(40.5)
Delete vital:[kennel:⟨a⟩, d'2026-03-09T08:00:00Z'] temp_c Unset
```

The view held one row after the create and the update, and none after the delete. To replay patches on another database, see [Apply JSON Patch ops](writes.md#apply-json-patch-ops).

`live_diff` has no `now` and no snapshot. A row that leaves the filter sends nothing. A row that enters sends only the ops of its write, so `apply` gives `UnknownRef` for it. It refuses edges: `a DIFF live query has no edges`. It reports the table only.

## Order of notices

SurrealDB 3.3.4 can deliver the notices of two writes in the wrong order. This can happen when both writes come from one client, also when the second write is sent after the reply to the first. It is upstream issue [surrealdb/surrealdb#7603](https://github.com/surrealdb/surrealdb/issues/7603). A maintainer says SurrealDB 4.0 fixes it.

| Fact | What to do |
| --- | --- |
| A notice can come before or after the reply to its write | Do not use the reply to order notices |
| Notices of two writes to the same records can swap | Read the changes of a write before you send the next write to the same records. `examples/watch.roc` does this |
| Requests in flight have no order (see [Requests in flight together](sessions.md#requests-in-flight-together)) | Write records that do not depend on each other in one group |
| A write made at about the same time as the `LIVE SELECT` can be missing from the snapshot and from the notices (upstream issue [#6983](https://github.com/surrealdb/surrealdb/issues/6983)) | Start the watch before the writes that you need |

A `View` is correct only when notices come in order. The rule above keeps it so.

## Predict notices in Roc

`Surreal.Mirror` is the Roc model of the notices of a live query (the Mirror). It computes what the server sends for a write, from the same functions that the clauses use. A test can then compare the real changes with the predicted ones. An application does not need it.

```roc
# Fragment: uses `vitals`, `is_fever`, `vital_line` and `hot` (a `Vital`) from examples/watch.roc.
notices = Surreal.Mirror.notices(vitals, Create(hot), is_fever, vital_line)?
step = Surreal.Mirror.step_all(Surreal.Members.empty({}), notices)
# step.changes : List(Surreal.Change(VitalLine)), step.members : the new members
```

From `examples/watch.roc`, `vital_step` and `expected`. A real run of `Create(hot)`, `Replace(hot, cooled)` and `Delete(cooled)` gave `Added`, `Removed` (with the row at 38.0) and nothing. The server gave the same first two changes in the run above.

| Function | Predicts |
| --- | --- |
| `Table.edit(Create(r))`, `Replace(a, b)`, `Delete(r)` | Is the write itself, as a `Prepared` |
| `Mirror.notices(table, edit, keep, show)` | The notices of the table statement. `keep` is the filter and `show` the projection |
| `Mirror.edge_notices(table, edit, node_of, state, keep, show)` | The notices of an edge statement |
| `Mirror.read_notices(table, edit, reached, keep, show)` | The notices of a statement on a linked table or a table of `rows()`. `reached` are the rows of the result that the write reaches |
| `Mirror.related(edit, rows, relates)` | The rows that a write to a table of `rows()` reaches: each of `rows` that `relates` holds for with the written row, before or after the write. Give the result to `read_notices` as `reached` |
| `Mirror.events(table, edit, keep, show)` | The events of `live_raw` |
| `Mirror.step_all(members, notices)` | The changes of the notices, in order |

[Escape hatches and extensions](advanced.md#test-with-the-mirror) shows how `tests/check.py` uses the Mirror.

## Limits

| Limit | What to do instead |
| --- | --- |
| No `group_by`: `a live query has no GROUP BY` | Define the group as a view (see [Views](schema.md#views)) and watch the view |
| No `order_by`, `limit` or `start`: `SurrealDB refuses ORDER BY, LIMIT and START in a live query` | Order the rows of the `View` yourself. `Limited` and `Started` have no `live`: a type error |
| No `between` and no subquery (`Selected.query()`) | Filter on `v.id.time()`. Filter before `group_by`, `order_by` and `limit` |
| No full-text search and no `nearest` | Watch the rows with a `filter`. Search them when a notice comes |
| No `Unchecked.select_star` | Select the fields with `select` |
| The parameters are fixed when the watch starts | Start a new watch for a new value |
| The edge statement sends one notice for each edge write | The package drops a notice of a record that is not in the result and does not match |
| An `Out` or `In` field of a linked row is not watched. `edges_from` and `edges_to` of another record watch the whole edge table | Watch the edge table with its own query |
| `live_raw` and `live_diff` report the table only. A leave sends nothing | Use `live` for leaves, edges and links |
| `live_diff` has no edges and no projection | Use `live` |
| A field name with `/` or `~` gives a patch pointer that is not exact | Roc field names have neither |
| A `LIVE` in the text of `Unchecked.query!` is not watched. The inbox drops its notices | Use `live!` (see [Raw SurrealQL](advanced.md#raw-surrealql)) |
| The notices of two writes can come in the wrong order on SurrealDB 3.3.4 | Read the changes of a write before the next write to the same records |
| The inbox keeps every notice of a watch until you read it | Read the watch or call `kill!` |
| `next_within!` needs `Transport.websocket_timed` | On basic-webserver, do not wait for a watch (see [Sessions on basic-webserver](sessions.md#sessions-on-basic-webserver)) |
| HTTP has no live queries | Use a WebSocket transport |
