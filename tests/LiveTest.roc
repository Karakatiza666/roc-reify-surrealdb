app [] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.5.0/B5U2mPsWTtuxfCRMzqQxio2ecDv7CAzCoyEMENMh4FNF.tar.zst",
	internal: "../src/internal.roc",
}

import internal.Surreal

# Tests of live queries without a server: the Mirror of the notices of each
# write, how `Watch.step` sorts a notice into changes, and the `View` they
# keep. Nothing outside this file imports it.
LiveTest :: {}

Sensor : { id : Str, label : Str, level : I64 }

Wire : { id : Str, from : Surreal.Link(Sensor), to : Surreal.Link(Sensor), live : Bool }

sensors : Surreal.Table(Sensor)
sensors = Surreal.table("sensor")

wires : Surreal.Table(Wire)
wires = Surreal.relation("wire", sensors, sensors)

Line : { label : Str, level : I64 }

## The filter and the projection of the live query the Mirror predicts for.
hot : Sensor -> Bool
hot = |s| s.level > 5

line : Sensor -> Line
line = |s| { label: s.label, level: s.level }

cold_a : Sensor
cold_a = { id: "a", label: "A", level: 1 }

hot_a : Sensor
hot_a = { ..cold_a, level: 9 }

hotter_a : Sensor
hotter_a = { ..cold_a, level: 12 }

renamed_cold_a : Sensor
renamed_cold_a = { ..cold_a, label: "A2" }

ref_a : Surreal.Ref
ref_a = match sensors.ref(cold_a) {
	Ok(r) => r
	Err(_) => crash "a row with a text key has a record id"
}

## The notices of one write, as `(action, now, row)`.
notices_of : Surreal.Edit(Sensor) -> List(([Create, Update, Delete], Bool, Try(Line, [Gone])))
notices_of = |edit| match Surreal.Mirror.notices(sensors, edit, hot, line) {
	Ok(notices) => notices.map(|n| (n.action, n.now, n.row))
	Err(_) => crash "the rows encode"
}

# ------------------------------------------------------- the Mirror of a row write

expect sensors.ref(cold_a).map_ok(|r| r.to_str()) == Ok("sensor:⟨a⟩")
expect notices_of(Create(hot_a)) == [(Create, Bool.True, Ok(line(hot_a)))]
expect notices_of(Create(cold_a)) == []
# A row that starts to match, still matches, and no longer matches: `now` tells them apart.
expect notices_of(Replace(cold_a, hot_a)) == [(Update, Bool.True, Ok(line(hot_a)))]
expect notices_of(Replace(hot_a, hotter_a)) == [(Update, Bool.True, Ok(line(hotter_a)))]
expect notices_of(Replace(hot_a, cold_a)) == [(Update, Bool.False, Ok(line(cold_a)))]
expect notices_of(Replace(cold_a, renamed_cold_a)) == []
# A write that changes no field sends nothing, also for a row in the result.
expect notices_of(Replace(hot_a, hot_a)) == []
expect notices_of(Delete(hot_a)) == [(Delete, Bool.True, Ok(line(hot_a)))]
expect notices_of(Delete(cold_a)) == []
expect Surreal.Mirror.notices(sensors, Create(hot_a), hot, line).map_ok(|ns| ns.map(|n| (n.role, n.ref))) == Ok([(Node, ref_a)])

# The `-- roc:` literal that `check.py` compares with the server's notices.
expect Surreal.Mirror.notices_literal([Surreal.Mirror.notices(sensors, Replace(cold_a, hot_a), hot, line) ?? [], []]) == Ok("[[{ action: 'UPDATE', now: true, ref: sensor:⟨a⟩, role: 'node', row: { label: 'A', level: 9 } }], []]")

# ------------------------------------------------------- the Mirror of an edge write

wire_ab : Wire
wire_ab = { id: "ab", from: sensors.link("a"), to: sensors.link("b"), live: Bool.True }

sensor_b : Sensor
sensor_b = { id: "b", label: "B", level: 0 }

## The node of a wire's `to` end with its wires after the write.
lonely : (Sensor, List(Wire)) -> Bool
lonely = |(_, ins)| ins.is_empty()

count : (Sensor, List(Wire)) -> Line
count = |(s, ins)| { label: s.label, level: ins.len().to_i64_wrap() }

edge_notices_of : Surreal.Edit(Wire), Try((Sensor, List(Wire)), [Gone]) -> List(([Create, Update, Delete], Bool, Try(Line, [Gone])))
edge_notices_of = |edit, state| match Surreal.Mirror.edge_notices(wires, edit, |w| w.to, |_| state, lonely, count) {
	Ok(notices) => notices.map(|n| (n.action, n.now, n.row))
	Err(_) => crash "the rows encode"
}

# One notice for each edge write, the node after the write, in the result or not.
expect edge_notices_of(Create(wire_ab), Ok((sensor_b, [wire_ab]))) == [(Create, Bool.False, Ok({ label: "B", level: 1 }))]
expect edge_notices_of(Delete(wire_ab), Ok((sensor_b, []))) == [(Delete, Bool.True, Ok({ label: "B", level: 0 }))]
expect edge_notices_of(Replace(wire_ab, { ..wire_ab, live: Bool.False }), Ok((sensor_b, [wire_ab]))) == [(Update, Bool.False, Ok({ label: "B", level: 1 }))]
expect edge_notices_of(Replace(wire_ab, wire_ab), Ok((sensor_b, [wire_ab]))) == []
# The node was deleted, and its edges with it.
expect edge_notices_of(Delete(wire_ab), Err(Gone)) == [(Delete, Bool.False, Err(Gone))]
expect Surreal.Mirror.edge_notices(wires, Create(wire_ab), |w| w.to, |_| Ok((sensor_b, [wire_ab])), lonely, count).map_ok(|ns| ns.map(|n| (n.role, n.ref.to_str()))) == Ok([(Edge, "sensor:⟨b⟩")])
# A node that is gone has no row and no `now` in the literal, as the server sends `node: NULL`.
expect Surreal.Mirror.notices_literal([Surreal.Mirror.edge_notices(wires, Delete(wire_ab), |w| w.to, |_| Err(Gone), lonely, count) ?? []]) == Ok("[[{ action: 'DELETE', ref: sensor:⟨b⟩, role: 'edge' }]]")

# ------------------------------------------------------- the Mirror of a read table

## A sensor reads a gauge through a link: a write to a gauge reaches the
## sensors that link to it.
Gauge : { id : Str, unit : Str }

gauges : Surreal.Table(Gauge)
gauges = Surreal.table("gauge")

celsius : Gauge
celsius = { id: "c", unit: "C" }

kelvin : Gauge
kelvin = { ..celsius, unit: "K" }

## The sensors that a write of a gauge reaches, after the write.
reached : List({ ref : Surreal.Ref, row : Sensor })
reached = [{ ref: ref_a, row: hot_a }, { ref: ref_b, row: sensor_b }]

## A probe names its sensor by key. A clause that reads the probes with
## `rows()` and this equality reaches only the sensors that a write names.
Probe : { id : Str, sensor : Str }

on_probe : Probe, Sensor -> Bool
on_probe = |p, s| p.sensor == s.id

probe_a : Probe
probe_a = { id: "p", sensor: "a" }

probe_b : Probe
probe_b = { ..probe_a, sensor: "b" }

related_refs : Surreal.Edit(Probe) -> List(Surreal.Ref)
related_refs = |edit| Surreal.Mirror.related(edit, reached, on_probe).map(|r| r.ref)

expect related_refs(Create(probe_a)) == [ref_a]
# A probe that moves reaches its old sensor and its new one.
expect related_refs(Replace(probe_a, probe_b)) == [ref_a, ref_b]
expect related_refs(Delete(probe_b)) == [ref_b]
expect related_refs(Create({ id: "q", sensor: "z" })) == []

read_notices_of : Surreal.Edit(Gauge), List({ ref : Surreal.Ref, row : Sensor }) ->List(([Create, Update, Delete], Surreal.Ref, Bool, Try(Line, [Gone])))
read_notices_of = |edit, rows| match Surreal.Mirror.read_notices(gauges, edit, rows, hot, line) {
	Ok(notices) => notices.map(|n| (n.action, n.ref, n.now, n.row))
	Err(_) => crash "the rows encode"
}

# One notice for each row that the write reaches, with the action of the write, in the result or not.
expect read_notices_of(Replace(celsius, kelvin), reached) == [(Update, ref_a, Bool.True, Ok(line(hot_a))), (Update, ref_b, Bool.False, Ok(line(sensor_b)))]
expect read_notices_of(Create(celsius), reached) == [(Create, ref_a, Bool.True, Ok(line(hot_a))), (Create, ref_b, Bool.False, Ok(line(sensor_b)))]
expect read_notices_of(Delete(celsius), []) == []
# A write that changes no field sends nothing.
expect read_notices_of(Replace(celsius, celsius), reached) == []
expect Surreal.Mirror.read_notices(gauges, Replace(celsius, kelvin), reached, hot, line).map_ok(|ns| ns.map(|n| n.role)) == Ok([Read, Read])
expect Surreal.Mirror.notices_literal([Surreal.Mirror.read_notices(gauges, Replace(celsius, kelvin), [{ ref: ref_a, row: hot_a }], hot, line) ?? []]) == Ok("[[{ action: 'UPDATE', now: true, ref: sensor:⟨a⟩, role: 'read', row: { label: 'A', level: 9 } }]]")

# ------------------------------------------------------- the Mirror of the raw events

events_of : Surreal.Edit(Sensor) -> List(Surreal.Event(Line))
events_of = |edit| match Surreal.Mirror.events(sensors, edit, hot, line) {
	Ok(events) => events
	Err(_) => crash "the rows encode"
}

expect events_of(Create(hot_a)) == [Created(ref_a, line(hot_a))]
expect events_of(Create(cold_a)) == []
# A row that starts to match is an update, and a row that no longer matches sends nothing.
expect events_of(Replace(cold_a, hot_a)) == [Updated(ref_a, line(hot_a))]
expect events_of(Replace(hot_a, cold_a)) == []
expect events_of(Replace(hot_a, hot_a)) == []
expect events_of(Delete(hot_a)) == [Deleted(ref_a, line(hot_a))]
expect Surreal.Mirror.events_literal([events_of(Create(hot_a))]) == Ok("[[{ action: 'CREATE', ref: sensor:⟨a⟩, row: { label: 'A', level: 9 } }]]")

# ------------------------------------------------------- from notice to change

ref_b : Surreal.Ref
ref_b = match sensors.ref(sensor_b) {
	Ok(r) => r
	Err(_) => crash "a row with a text key has a record id"
}

## A notice of the row statement.
node : [Create, Update, Delete], Surreal.Ref, Bool -> Surreal.Notice(Line)
node = |action, ref, now| { action, role: Node, ref, row: Ok(line(hot_a)), now }

## A notice of the edge statement.
edge : [Create, Update, Delete], Surreal.Ref, Bool -> Surreal.Notice(Line)
edge = |action, ref, now| { action, role: Edge, ref, row: Ok(line(hot_a)), now }

## The changes of one notice, from a result that holds `refs`.
step_of : List(Surreal.Ref), Surreal.Notice(Line) -> List(Surreal.Change(Line))
step_of = |refs, notice| {
	members = Surreal.View.of_rows(refs.map(|r| { ref: r, row: line(cold_a) })).members()
	Surreal.Watch.step(members, notice).changes
}

# One row of the table of `Watch.step` each.
expect step_of([ref_a], node(Delete, ref_a, Bool.True)) == [Removed(ref_a, line(hot_a))]
expect step_of([], node(Delete, ref_a, Bool.True)) == []
expect step_of([ref_a], { ..edge(Delete, ref_a, Bool.False), row: Err(Gone) }) == []
expect step_of([], node(Create, ref_a, Bool.True)) == [Added(ref_a, line(hot_a))]
expect step_of([], node(Update, ref_a, Bool.True)) == [Added(ref_a, line(hot_a))]
expect step_of([ref_a], node(Update, ref_a, Bool.True)) == [Updated(ref_a, line(hot_a))]
expect step_of([ref_a], node(Update, ref_a, Bool.False)) == [Removed(ref_a, line(hot_a))]
expect step_of([], node(Update, ref_a, Bool.False)) == []
# An edge write: the same rule, whatever the edge action.
expect step_of([], edge(Delete, ref_b, Bool.True)) == [Added(ref_b, line(hot_a))]
expect step_of([ref_b], edge(Create, ref_b, Bool.False)) == [Removed(ref_b, line(hot_a))]
expect step_of([ref_b], edge(Update, ref_b, Bool.True)) == [Updated(ref_b, line(hot_a))]
expect step_of([], edge(Create, ref_b, Bool.False)) == []
# A notice of a read table: the same rule, whatever the action of the write.
expect step_of([ref_a], { ..node(Delete, ref_a, Bool.True), role: Read }) == [Updated(ref_a, line(hot_a))]
expect step_of([], { ..node(Update, ref_b, Bool.True), role: Read }) == [Added(ref_b, line(hot_a))]
expect step_of([ref_a], { ..node(Update, ref_a, Bool.False), role: Read }) == [Removed(ref_a, line(hot_a))]
# The notices of one message of a read table, in turn: the members follow each.
expect Surreal.Mirror.step_all(Surreal.Members.empty({}), [{ ..node(Update, ref_a, Bool.True), role: Read }, { ..node(Update, ref_b, Bool.False), role: Read }, { ..node(Update, ref_a, Bool.True), role: Read }]).changes == [Added(ref_a, line(hot_a)), Updated(ref_a, line(hot_a))]
# The notices of an update and a delete of one row: the notices of two
# writes in their order, then in the other order, as SurrealDB can send
# them (`watch.roc`, `check_watch!`). `Watch.step` reads each notice with
# the members, in the order that the notices came. The other order gives
# other changes, so the app reads the changes of a write before it sends
# the next write.
expect {
	update = node(Update, ref_a, Bool.True)
	delete = node(Delete, ref_a, Bool.True)
	members = Surreal.View.of_rows([{ ref: ref_a, row: line(cold_a) }]).members()
	in_order = Surreal.Mirror.step_all(members, [update, delete]).changes
	other_order = Surreal.Mirror.step_all(members, [delete, update]).changes
	in_order == [Updated(ref_a, line(hot_a)), Removed(ref_a, line(hot_a))] and other_order == [Removed(ref_a, line(hot_a)), Added(ref_a, line(hot_a))]
}
# A write between the `LIVE` and the snapshot is in the snapshot and comes again: an update, not a second add.
expect step_of([ref_a], node(Create, ref_a, Bool.True)) == [Updated(ref_a, line(hot_a))]
# The members follow the changes.
expect {
	start = Surreal.Members.empty({})
	added = Surreal.Watch.step(start, node(Create, ref_a, Bool.True)).members
	removed = Surreal.Watch.step(added, node(Update, ref_a, Bool.False)).members
	added.contains(ref_a) and !removed.contains(ref_a) and !start.contains(ref_a)
}

# ------------------------------------------------------- the view

expect {
	view = Surreal.View.of_rows([{ ref: ref_a, row: line(cold_a) }])
	after = [Added(ref_b, line(sensor_b)), Updated(ref_a, line(hot_a)), Removed(ref_b, line(sensor_b))].fold(view, |v, c| v.apply(c))
	after.rows() == [line(hot_a)] and after.members().contains(ref_a) and !after.members().contains(ref_b)
}
expect Surreal.View.of_rows([{ ref: ref_a, row: line(cold_a) }]).apply(Removed(ref_a, line(cold_a))).rows() == []

# ------------------------------------------------------- a read row that holds a `Linked` of itself

## A chain links to its own table. Its read row holds a `Linked` of itself,
## so a field read may go any number of hops along `next`.
Chain := { id : Str, label : Str, next ?: Surreal.Link(Chain) }

ChainRead := { id : Str, label : Str, next ?: Surreal.Linked(ChainRead) }

chains : Surreal.Table(Chain)
chains = Surreal.table("chain")

chain_reads : Surreal.Table(ChainRead)
chain_reads = Surreal.table("chain")

## The label two hops along `next`.
two_hops : ChainRead -> Str
two_hops = |c| c.?next.map_ok(|n| n.?next.map_ok(|m| m.label) ?? "-") ?? "-"

# The live query watches each hop that the clause reads: a write to a
# chain reaches the rows whose `next` is that chain, and the rows two hops
# before it, whose `next.next` is, when it changes `next` or `label`, the
# fields that the clause reads. The `Linked(ChainRead)` finds its table by
# the read row, which `define_read` lists.
expect Surreal.from(chain_reads).select_value(two_hops).live({}, [chains.define().done(), chain_reads.define_read()]).request() == Ok("LIVE SELECT VALUE { row: (IF next IS NONE THEN NONE ELSE next.next.label ?? '-' END) ?? '-', now: true } FROM chain;\nLIVE SELECT VALUE (SELECT VALUE { ref: id, row: (IF next IS NONE THEN NONE ELSE next.next.label ?? '-' END) ?? '-', now: true } FROM chain WHERE next = $parent.id OR next.next = $parent.id) FROM chain WHERE $before IS NONE OR $after IS NONE OR $before.next != $after.next OR $before.label != $after.label;\nSELECT VALUE { ref: id, row: (IF next IS NONE THEN NONE ELSE next.next.label ?? '-' END) ?? '-' } FROM chain;")
