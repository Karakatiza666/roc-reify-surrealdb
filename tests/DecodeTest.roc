app [] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.5.0/B5U2mPsWTtuxfCRMzqQxio2ecDv7CAzCoyEMENMh4FNF.tar.zst",
	internal: "../src/internal.roc",
}

import internal.Ql
import internal.Surreal
import internal.Diff
import cbor.Cbor
import "fixtures/fevered/00.cbor" as fevered_reply : List(U8)
import "fixtures/fevered/01.cbor" as fevered_1 : List(U8)
import "fixtures/fevered/02.cbor" as fevered_2 : List(U8)
import "fixtures/fevered/03.cbor" as fevered_3 : List(U8)
import "fixtures/fevered/04.cbor" as fevered_4 : List(U8)
import "fixtures/fevered/05.cbor" as fevered_5 : List(U8)
import "fixtures/fevered/07.cbor" as fevered_kill_reply : List(U8)
import "fixtures/fevered/06.cbor" as fevered_killed : List(U8)
import "fixtures/unattended/00.cbor" as unattended_reply : List(U8)
import "fixtures/unattended/01.cbor" as unattended_1 : List(U8)
import "fixtures/unattended/02.cbor" as unattended_2 : List(U8)
import "fixtures/unattended/03.cbor" as unattended_3 : List(U8)
import "fixtures/unattended/04.cbor" as unattended_4 : List(U8)
import "fixtures/unattended/05.cbor" as unattended_5 : List(U8)
import "fixtures/unattended/06.cbor" as unattended_6 : List(U8)
import "fixtures/unattended/07.cbor" as unattended_7 : List(U8)
import "fixtures/unattended/08.cbor" as unattended_8 : List(U8)
import "fixtures/unattended/09.cbor" as unattended_9 : List(U8)
import "fixtures/unattended/10.cbor" as unattended_10 : List(U8)
import "fixtures/unattended/11.cbor" as unattended_11 : List(U8)
import "fixtures/kennel_sites/00.cbor" as sites_reply : List(U8)
import "fixtures/kennel_sites/01.cbor" as sites_1 : List(U8)
import "fixtures/kennel_sites/02.cbor" as sites_2 : List(U8)
import "fixtures/kennel_sites/03.cbor" as sites_3 : List(U8)
import "fixtures/kennel_sites/04.cbor" as sites_4 : List(U8)
import "fixtures/kennel_sites/05.cbor" as sites_5 : List(U8)
import "fixtures/kennel_sites/06.cbor" as sites_6 : List(U8)
import "fixtures/fever_events/00.cbor" as events_reply : List(U8)
import "fixtures/fever_events/01.cbor" as events_1 : List(U8)
import "fixtures/fever_events/02.cbor" as events_2 : List(U8)
import "fixtures/fever_events/03.cbor" as events_3 : List(U8)
import "fixtures/fever_events/04.cbor" as events_4 : List(U8)
import "fixtures/fever_events/05.cbor" as events_killed : List(U8)
import "fixtures/errors/00.cbor" as failed_statement : List(U8)
import "fixtures/errors/01.cbor" as unknown_method : List(U8)
import "fixtures/queries/create_shift.cbor" as create_shift_reply : List(U8)

# Tests of the decoding of a live session, without a server. The files in
# `fixtures/` are messages that SurrealDB 4.0.1 sent for the live blocks of
# `monitoring.roc` (`check.py --record fixtures`). Each notice decodes to the
# notice that the Roc Mirror predicts for the same write, and the changes of
# a stream of them are the changes of `Watch.step`. Nothing outside this
# file imports it.

# ------------------------------------------------------- the domain of monitoring.roc

Kennel : { id : Str, label : Str }

Vital : { id : Surreal.TimeKey(Surreal.Id(Kennel)), pulse : I64, temp_c : Dec, fevered : Bool }

Carer : { id : Str, name : Str }

CaresFor : { id : Str, from : Surreal.Link(Carer), to : Surreal.Link(Kennel), lead : Bool }

kennels : Surreal.Table(Kennel)
kennels = Surreal.table("kennel")

vitals : Surreal.Table(Vital)
vitals = Surreal.table("vital")

carers : Surreal.Table(Carer)
carers = Surreal.table("carer")

cares_for : Surreal.Table(CaresFor)
cares_for = Surreal.relation("cares_for", carers, kennels)

fever : Dec, I64 -> Bool
fever = |temp_c, pulse| temp_c > 39.0 or pulse > 120

fever_fn : Surreal.DbFn((Dec, I64 -> Bool))
fever_fn = Surreal.db_fn("fever", fever)

VitalLine : { kennel : Surreal.Id(Kennel), at : Surreal.Datetime, pulse : I64, temp_c : Dec }

vital_line : Vital -> VitalLine
vital_line = |v| { kennel: v.id.series(), at: v.id.time(), pulse: v.pulse, temp_c: v.temp_c }

is_fever : Vital -> Bool
is_fever = |v| fever(v.temp_c, v.pulse)

Unattended : { label : Str, carers : I64 }

no_carer : (Kennel, List(CaresFor)) -> Bool
no_carer = |(_, edges)| edges.len() == 0

unattended_line : (Kennel, List(CaresFor)) -> Unattended
unattended_line = |(k, edges)| { label: k.label, carers: edges.len().to_i64_wrap() }

moment : Str -> Surreal.Datetime
moment = |text| match Surreal.datetime(text) {
	Ok(d) => d
	Err(_) => crash "a valid datetime"
}

reading : Str, Str, I64, Dec -> Vital
reading = |kennel, at, pulse, temp_c| { id: Surreal.time_key(kennels.id(kennel), moment(at)), pulse, temp_c, fevered: fever(temp_c, pulse) }

## The writes of the block `fevered` (`vital_edits` in `monitoring.roc`).
fevered_edits : List(Surreal.Edit(Vital))
fevered_edits = {
	hot = reading("a", "2026-03-03T08:00:00Z", 80, 39.6)
	cool = reading("a", "2026-03-03T09:00:00Z", 80, 38.2)
	cooled = { ..hot, temp_c: 38.2, fevered: Bool.False }
	heated = { ..cool, temp_c: 39.8, fevered: Bool.True }
	calmer = { ..heated, pulse: 90 }
	[Create(hot), Create(cool), Replace(hot, cooled), Replace(cool, heated), Replace(heated, calmer), Replace(cooled, cooled), Delete(calmer), Delete(cooled)]
}

fevered : Surreal.Watch(VitalLine)
fevered = match Surreal.from(vitals).filter(|v| fever_fn.call2(v.temp_c, v.pulse)).select(vital_line).live({}, []).checked() {
	Ok(w) => w
	Err(_) => crash "the watch of monitoring.roc translates"
}

unattended : Surreal.Watch(Unattended)
unattended = match Surreal.from(kennels).incoming(cares_for).filter(no_carer).select(unattended_line).live({}, []).checked() {
	Ok(w) => w
	Err(_) => crash "the watch of monitoring.roc translates"
}

## The read row of a kennel of `monitoring.roc`, for the block `kennel_sites`.
Site : { id : Str, name : Str }

CareRead : { id : Str, from : Surreal.Linked(Carer), to : Surreal.Link(Kennel), lead : Bool }

KennelRead : { id : Str, label : Str, site : Surreal.Linked(Site), cares_for : Surreal.In(CareRead) }

sites : Surreal.Table(Site)
sites = Surreal.table("site")

kennel_reads : Surreal.Table(KennelRead)
kennel_reads = Surreal.table("kennel")

KennelSite : { label : Str, site : Str }

kennel_sites : Surreal.Watch(KennelSite)
kennel_sites = match Surreal.from(kennel_reads).select(|k| { label: k.label, site: k.site.name }).live({}, [sites.define().done()]).checked() {
	Ok(w) => w
	Err(_) => crash "the watch of monitoring.roc translates"
}

fever_events : Surreal.RawWatch(VitalLine)
fever_events = match Surreal.from(vitals).filter(|v| fever_fn.call2(v.temp_c, v.pulse)).select(vital_line).live_raw({}) {
	Ok(w) => w
	Err(_) => crash "the watch of monitoring.roc translates"
}

## The live queries and the snapshot of a reply that reads.
started : Surreal.Watch(out), List(U8) -> { live : Surreal.Live(out), view : Surreal.View(out) } where [out.Cbor.Readable(errs)]
started = |watch, reply| match watch.start(reply) {
	Ok(s) => s
	Err(_) => crash "the recorded reply reads"
}

fevered_start : { live : Surreal.Live(VitalLine), view : Surreal.View(VitalLine) }
fevered_start = started(fevered, fevered_reply)

unattended_start : { live : Surreal.Live(Unattended), view : Surreal.View(Unattended) }
unattended_start = started(unattended, unattended_reply)

sites_start : { live : Surreal.Live(KennelSite), view : Surreal.View(KennelSite) }
sites_start = started(kennel_sites, sites_reply)

line_at : Str, Str, I64, Dec -> VitalLine
line_at = |kennel, at, pulse, temp_c| { kennel: kennels.id(kennel), at: moment(at), pulse, temp_c }

ref_of_kennel : Str -> Surreal.Ref
ref_of_kennel = |key| match kennels.ref({ id: key, label: "" }) {
	Ok(r) => r
	Err(_) => crash "a row with a text key has a record id"
}

# ------------------------------------------------------- the reply to the request

expect fevered_start.live.lives().map(|l| l.role) == [Node]
expect unattended_start.live.lives().map(|l| l.role) == [Node, Edge]
expect sites_start.live.lives().map(|l| l.role) == [Node, Read]
expect sites_start.view.rows() == [{ label: "North", site: "Oslo" }, { label: "South", site: "Bergen" }]

# The snapshot: datetimes (tag 12), a fraction of a second, record ids (tag 8)
# and decimals (tag 10, as text).
expect
	fevered_start.view.rows()
		== [
			line_at("a", "2026-03-01T14:30:00Z", 90, 39.5),
			line_at("a", "2026-03-02T09:15:00Z", 125, 38.0),
			line_at("b", "2026-03-01T23:59:59.5Z", 130, 38.0),
			line_at("b", "2026-03-02T11:00:00Z", 121, 39.1),
		]

expect unattended_start.view.rows() == [{ label: "South", carers: 0 }]
expect unattended_start.view.members().contains(ref_of_kennel("b"))

# A refused statement and a refused request.
expect fevered.start(failed_statement).map_ok(|_| {}) == Err(Server(NotFound({ what: "Table", name: "nothing_here", message: "The table 'nothing_here' does not exist" })))
expect fevered.start(unknown_method).map_ok(|_| {}) == Err(Server(NotFound({ what: "Method", name: "unknown", message: "Method not found" })))

# A reply of another request has fewer results.
expect unattended.start(fevered_reply).map_ok(|_| {}) == Err(Wire("a reply of 2 results to 3 statements"))

# ------------------------------------------------------- notices

## The notice of a message that is one notice of the watch.
notice_of : Surreal.Watch(out), Surreal.Lives, List(U8) -> Try(Surreal.Notice(out), Surreal.Error) where [out.Cbor.Readable(errs)]
notice_of = |watch, lives, bytes| match watch.notice(lives, bytes)? {
	Mine([n]) => Ok(n)
	_ => Err(Wire("not one notice of the watch"))
}

# Each notice of `fevered` is the notice that the Mirror predicts for its write.
expect {
	mirror = fevered_edits.map_try(|e| Surreal.Mirror.notices(vitals, e, is_fever, vital_line)).map_ok(|lists| lists.join())
	decoded = [fevered_1, fevered_2, fevered_3, fevered_4, fevered_5].map_try(|bytes| notice_of(fevered, fevered_start.live.lives(), bytes))
	decoded == mirror and mirror.map_ok(|ns| ns.len()) == Ok(5)
}

# The ref of a time series key: the record id with its array key.
expect notice_of(fevered, fevered_start.live.lives(), fevered_1).map_ok(|n| n.ref.to_str()) == Ok("vital:[kennel:⟨a⟩, d'2026-03-03T08:00:00Z']")

# An edge notice: its ref is the node, and its row the node after the write.
expect notice_of(unattended, unattended_start.live.lives(), unattended_2) == Ok({ action: Create, role: Edge, ref: ref_of_kennel("c"), row: Ok({ label: "East", carers: 1 }), now: Bool.False })

# The delete of an edge whose node is gone: `node` is `NULL`.
expect notice_of(unattended, unattended_start.live.lives(), unattended_8) == Ok({ action: Delete, role: Edge, ref: ref_of_kennel("c"), row: Err(Gone), now: Bool.False })

# The other messages of a session.
expect fevered.notice(fevered_start.live.lives(), fevered_kill_reply) == Ok(Reply({ id: 4, result: Cbor.Value.Null }))
expect fevered.notice(fevered_start.live.lives(), fevered_killed) == Ok(Killed(fevered_start.live.lives().first().map_ok(|l| l.id) ?? crash "one live query"))
expect fevered.notice(fevered_start.live.lives(), unknown_method) == Ok(ReplyError({ id: 4, error: NotFound({ what: "Method", name: "unknown", message: "Method not found" }) }))
expect fevered.notice(unattended_start.live.lives(), fevered_1) == Ok(Other)

# ------------------------------------------------------- changes

## The changes of a list of messages, from the watch that starts with the
## snapshot, as `Live.receive` gives them: an error is passed on, and
## `Ended` ends.
changes_of : Surreal.Watch(out), { live : Surreal.Live(out), view : Surreal.View(out) }, List(List(U8)) -> List(Try(Surreal.Change(out), Surreal.Error)) where [out.Cbor.Readable(errs)]
changes_of = |_watch, start, messages| {
	done = messages.fold_until(
		{ live: start.live, out: [] },
		|acc, bytes| match acc.live.receive(bytes) {
			Ok(Got(next)) => Continue({ live: next.live, out: acc.out.concat(next.item.map(|c| Ok(c))) })
			Ok(Skip(later)) => Continue({ ..acc, live: later })
			Ok(Ended) => Break(acc)
			Err(e) => Continue({ ..acc, out: acc.out.append(Err(e)) })
		},
	)
	done.out
}

# A kennel comes, its carer comes and goes, its label changes, carers come
# and go, and the kennel is deleted. The edge notice of a node that is gone
# gives nothing, and so does the delete of a node that is not in the result.
# The reply to `kill` is skipped, and `KILLED` ends the changes.
expect {
	c = ref_of_kennel("c")
	changes_of(unattended, unattended_start, [unattended_1, unattended_2, unattended_3, unattended_4, unattended_5, unattended_6, unattended_7, unattended_8, unattended_9, unattended_10, unattended_11, unattended_1])
		== [
			Ok(Added(c, { label: "East", carers: 0 })),
			Ok(Removed(c, { label: "East", carers: 1 })),
			Ok(Added(c, { label: "East wing", carers: 0 })),
			Ok(Updated(c, { label: "Annex", carers: 0 })),
			Ok(Removed(c, { label: "Annex", carers: 1 })),
			Ok(Added(c, { label: "Annex", carers: 0 })),
			Ok(Removed(c, { label: "Annex", carers: 1 })),
		]
}

# A message of a `Read` statement: a notice for each row it gives, and
# none for a write that reaches no row.
expect kennel_sites.notice(sites_start.live.lives(), sites_1) == Ok(Mine([{ action: Update, role: Read, ref: ref_of_kennel("a"), row: Ok({ label: "North", site: "Oslo centre" }), now: Bool.True }]))
expect kennel_sites.notice(sites_start.live.lives(), sites_3) == Ok(Mine([]))
expect kennel_sites.notice(sites_start.live.lives(), sites_4) == Ok(Mine([]))

# A new name of a site is an update of the kennel at it, and the old name another.
expect
	changes_of(kennel_sites, sites_start, [sites_1, sites_2, sites_3, sites_4, sites_5, sites_6])
		== [
			Ok(Updated(ref_of_kennel("a"), { label: "North", site: "Oslo centre" })),
			Ok(Updated(ref_of_kennel("b"), { label: "South", site: "Bergen sentrum" })),
			Ok(Updated(ref_of_kennel("a"), { label: "North", site: "Oslo" })),
			Ok(Updated(ref_of_kennel("b"), { label: "South", site: "Bergen" })),
		]

# A message that does not read is an error, and the changes go on.
expect changes_of(unattended, unattended_start, [[1, 2, 3], unattended_1]).map(|c| c.is_ok()) == [Bool.False, Bool.True]

# The view after the changes.
expect {
	changes = changes_of(unattended, unattended_start, [unattended_1, unattended_2, unattended_3])
	view = changes.fold(
		unattended_start.view,
		|v, c| match c {
			Ok(change) => v.apply(change)
			Err(_) => v
		},
	)
	view.rows() == [{ label: "South", carers: 0 }, { label: "East wing", carers: 0 }]
}

# ------------------------------------------------------- raw events

events_lives : Surreal.Lives
events_lives = match fever_events.start(events_reply) {
	Ok(s) => s.live.lives()
	Err(_) => crash "the recorded reply reads"
}

## The ref of a reading of kennel `a`.
vital_ref : Str -> Surreal.Ref
vital_ref = |at| match vitals.ref(reading("a", at, 0, 0)) {
	Ok(r) => r
	Err(_) => crash "a time series key has a record id"
}

## The events of a list of messages, as `RawWatch.events` gives them.
events_of : List(List(U8)) -> List(Try(Surreal.Event(VitalLine), Surreal.Error))
events_of = |messages| {
	done = messages.fold_until(
		[],
		|acc, bytes| match fever_events.event(events_lives, bytes) {
			Ok(Mine(event)) => Continue(acc.append(Ok(event)))
			Ok(Killed(_)) => Break(acc)
			Ok(_) => Continue(acc)
			Err(e) => Continue(acc.append(Err(e)))
		},
	)
	done
}

# The writes of `fevered` on another day. The row that no longer matches
# sends nothing, and the row that starts to match is `Updated`.
expect {
	hot = line_at("a", "2026-03-05T08:00:00Z", 80, 39.6)
	heated = line_at("a", "2026-03-05T09:00:00Z", 80, 39.8)
	calmer = { ..heated, pulse: 90 }
	events_of([events_1, events_2, events_3, events_4, events_killed, events_1]) == [Ok(Created(vital_ref("2026-03-05T08:00:00Z"), hot)), Ok(Updated(vital_ref("2026-03-05T09:00:00Z"), heated)), Ok(Updated(vital_ref("2026-03-05T09:00:00Z"), calmer)), Ok(Deleted(vital_ref("2026-03-05T09:00:00Z"), calmer))]
}

# ------------------------------------------------------- the values of SurrealDB

## A value from the bytes of a `Cbor.Value`.
read : Cbor.Value -> Try(a, Surreal.Error) where [a.Cbor.Readable(errs)]
read = |value| Surreal.Unchecked.decode(Cbor.encode(value))

tag : U64, List(Cbor.Value) -> Cbor.Value
tag = |number, items| Cbor.Value.Tag(number, Cbor.Value.Array(items))

int : I64 -> Cbor.Value
int = |n| Cbor.Value.Int(Cbor.IntValue.from_i64(n))

# A datetime: `[seconds, nanoseconds]`, the nanoseconds left out when 0, before 1970 too.
expect read(tag(12, [int(1772375400)])) == Ok(moment("2026-03-01T14:30:00Z"))
expect read(tag(12, [int(-315619200), int(250000000)])) == Ok(moment("1960-01-01T00:00:00.25Z"))
expect {
	wrong : Try(Surreal.Datetime, Surreal.Error)
	wrong = read(tag(13, [int(0)]))
	wrong == Err(Decode({ path: "", message: "the value at byte 0 does not fit its Roc type" }))
}

# A duration: `[]`, `[seconds]` or `[seconds, nanoseconds]` (verified with `0ns`, `2s`, `1ns`).
expect read(tag(14, [])) == Ok(Surreal.Time.nanos(0))
expect read(tag(14, [int(5400)])) == Ok(Surreal.Time.mins(90))
expect read(tag(14, [int(0), int(1)])) == Ok(Surreal.Time.nanos(1))

# A decimal is text in tag 10, in the exponent form too. NONE is tag 6 and `null`.
expect read(Cbor.Value.Tag(10, Cbor.Value.Text("4E+1"))) == Ok(40.0.Dec)
expect {
	row : Try({ n : I64, gone ?: Str }, Surreal.Error)
	row = read(Diff.vmap([(Cbor.Value.Text("n"), int(1)), (Cbor.Value.Text("gone"), Cbor.Value.Tag(6, Cbor.Value.Null))]))
	row.map_ok(|r| r.?gone) == Ok(Err(MissingField))
}

# The bytes that SurrealDB sent for geometries: each point is a tag 88 of f16 floats.
expect {
	point : Try(Surreal.Point, Surreal.Error)
	point = Surreal.Unchecked.decode([216, 88, 130, 249, 62, 0, 249, 64, 0])
	point == Ok(Surreal.point(1.5, 2))
}

expect {
	polygon : Try(Surreal.Polygon, Surreal.Error)
	polygon = Surreal.Unchecked.decode([216, 90, 129, 216, 89, 132, 216, 88, 130, 249, 0, 0, 249, 0, 0, 216, 88, 130, 249, 60, 0, 249, 0, 0, 216, 88, 130, 249, 60, 0, 249, 60, 0, 216, 88, 130, 249, 0, 0, 249, 0, 0])
	corner = |lon, lat| Surreal.point(lon, lat)
	polygon == Ok(Surreal.Polygon.({ exterior: [corner(0, 0), corner(1, 0), corner(1, 1), corner(0, 0)], holes: [] }))
}

expect {
	collection : Try(Surreal.Geometry, Surreal.Error)
	collection = Surreal.Unchecked.decode([216, 94, 129, 216, 88, 130, 249, 60, 0, 249, 64, 0])
	collection == Ok(Surreal.Geometry.Collection(Surreal.Collection.([Surreal.Geometry.Point(Surreal.point(1, 2))])))
}

# A record id: an `Id` with a text key, a `Link` that is not fetched.
expect read(tag(8, [Cbor.Value.Text("kennel"), Cbor.Value.Text("a")])) == Ok(kennels.id("a"))
expect read(tag(8, [Cbor.Value.Text("kennel"), Cbor.Value.Text("a")])) == Ok(kennels.link("a"))

# A key of a kind that the ORM does not write is refused.
expect {
	ref : Try(Surreal.Ref, Surreal.Error)
	ref = read(tag(8, [Cbor.Value.Text("t"), tag(14, [int(1)])]))
	ref == Err(Decode({ path: "", message: "the value at byte 0 does not fit its Roc type" }))
}

# A key that the server made: a ULID, from `DEFAULT rand::ulid()` on `id`
# (`client.roc`, the reply to the create of the shift). It is
# a text key, so it reads as an `Id` and a `Link`.
Shift : { id : Str, label : Str }

shifts : Surreal.Table(Shift)
shifts = Surreal.table("shift")

expect {
	reply : Try({ result : List({ result : List({ id : Surreal.Id(Shift), label : Str }) }) }, Surreal.Error)
	reply = Surreal.Unchecked.decode(create_shift_reply)
	reply.map_ok(|r| r.result.join_map(|one| one.result)) == Ok([{ id: shifts.id("01M7911XWVP2307M56XCDKCQWS"), label: "Early" }])
}
expect read(tag(8, [Cbor.Value.Text("shift"), Cbor.Value.Text("01M7911XWVP2307M56XCDKCQWS")])) == Ok(shifts.link("01M7911XWVP2307M56XCDKCQWS"))
