app [] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.5.0/B5U2mPsWTtuxfCRMzqQxio2ecDv7CAzCoyEMENMh4FNF.tar.zst",
	internal: "../src/internal.roc",
}

import internal.Surreal
import "fixtures/mux/start/00.cbor" as start_a : List(U8)
import "fixtures/mux/start/01.cbor" as start_b : List(U8)
import "fixtures/mux/a/00.cbor" as a_0 : List(U8)
import "fixtures/mux/a/01.cbor" as a_1 : List(U8)
import "fixtures/mux/a/02.cbor" as a_2 : List(U8)
import "fixtures/mux/a/03.cbor" as a_3 : List(U8)
import "fixtures/mux/a/04.cbor" as a_4 : List(U8)
import "fixtures/mux/a/05.cbor" as a_5 : List(U8)
import "fixtures/mux/a/06.cbor" as a_6 : List(U8)
import "fixtures/mux/b/00.cbor" as b_0 : List(U8)
import "fixtures/mux/b/01.cbor" as b_1 : List(U8)
import "fixtures/mux/b/02.cbor" as b_2 : List(U8)
import "fixtures/mux/c/00.cbor" as c_0 : List(U8)
import "fixtures/mux/c/01.cbor" as c_1 : List(U8)
import "fixtures/mux/two/00.cbor" as two_0 : List(U8)
import "fixtures/mux/two/01.cbor" as two_1 : List(U8)
import "fixtures/mux/two/02.cbor" as two_2 : List(U8)
import "fixtures/mux/two/03.cbor" as two_3 : List(U8)
import "fixtures/mux/two/04.cbor" as two_4 : List(U8)
import "fixtures/mux/e/00.cbor" as e_0 : List(U8)
import "fixtures/mux/e/01.cbor" as e_1 : List(U8)
import "fixtures/mux/e/02.cbor" as e_2 : List(U8)
import "fixtures/mux/e/03.cbor" as e_3 : List(U8)
import "fixtures/mux/e/04.cbor" as e_4 : List(U8)
import "fixtures/mux/e/05.cbor" as e_5 : List(U8)

# Tests of the `Inbox` of a session, without a server. The files in
# `fixtures/mux/` are the frames of one session that SurrealDB 4.0.1 sent,
# in the order they came (`check.py --record fixtures`, `record_mux`): two
# watches, requests in flight, and writes that send notices. The order of
# the frames of one case can differ between two recordings, so a test
# reads them in their order and checks what does not depend on it, except
# where a `SLEEP` in the request fixes the order. Nothing outside this file
# imports it.

Row : { id : Str, v : I64 }

mux_a : Surreal.Table(Row)
mux_a = Surreal.table("mux_a")

mux_b : Surreal.Table(Row)
mux_b = Surreal.table("mux_b")

watch_a : Surreal.Watch(Row)
watch_a = match Surreal.from(mux_a).select(|r| r).live({}, []).checked() {
	Ok(w) => w
	Err(_) => crash "a watch of a whole row translates"
}

watch_b : Surreal.Watch(Row)
watch_b = match Surreal.from(mux_b).select(|r| r).live({}, []).checked() {
	Ok(w) => w
	Err(_) => crash "a watch of a whole row translates"
}

# The recorder sends these texts (`MUX_WATCH` in `check.py`).
expect watch_a.request() == Ok("LIVE SELECT VALUE { row: { id: record::id(id), v: v }, now: true } FROM mux_a;\nSELECT VALUE { ref: id, row: { id: record::id(id), v: v } } FROM mux_a;")
expect watch_b.request() == Ok("LIVE SELECT VALUE { row: { id: record::id(id), v: v }, now: true } FROM mux_b;\nSELECT VALUE { ref: id, row: { id: record::id(id), v: v } } FROM mux_b;")

live_a : Surreal.Live(Row)
live_a = match watch_a.start(start_a) {
	Ok(started) => started.live
	Err(_) => crash "the recorded reply to the watch of mux_a reads"
}

live_b : Surreal.Live(Row)
live_b = match watch_b.start(start_b) {
	Ok(started) => started.live
	Err(_) => crash "the recorded reply to the watch of mux_b reads"
}

## An inbox that watches both watches, as `Session.live!` leaves it.
watching : Surreal.Inbox
watching = Surreal.Inbox.empty({}).watch(live_a.lives()).watch(live_b.lives())

a_frames : List(List(U8))
a_frames = [a_0, a_1, a_2, a_3, a_4, a_5, a_6]

b_frames : List(List(U8))
b_frames = [b_0, b_1, b_2]

c_frames : List(List(U8))
c_frames = [c_0, c_1]

two_frames : List(List(U8))
two_frames = [two_0, two_1, two_2, two_3, two_4]

e_frames : List(List(U8))
e_frames = [e_0, e_1, e_2, e_3, e_4, e_5]

# ------------------------------------------------------------- the helpers

## The inbox after each frame, in order.
fed : Surreal.Inbox, List(List(U8)) -> Try(Surreal.Inbox, Surreal.Error)
fed = |inbox, frames| frames.fold_try(inbox, |acc, bytes| acc.accept(bytes))

## The position of the reply to `id` in the frames.
reply_at : List(List(U8)), U64 -> Try(U64, [NotFound])
reply_at = |frames, id| frames.find_first_index(|f| Surreal.Inbox.key_of(f) == Ok(Reply(id)))

## Whether the inbox gives the reply to `id`, and that reply has the id.
gives_reply : Try(Surreal.Inbox, Surreal.Error), U64 -> Bool
gives_reply = |inbox, id| match inbox {
	Ok(i) =>
		match i.take_reply(id) {
			Taken(t) => Surreal.Inbox.key_of(t.bytes) == Ok(Reply(id)) and !t.inbox.replies().contains(id)
			Waiting => Bool.False
		}
	Err(_) => Bool.False
}

## The inbox after the reply to `id` is taken.
without_reply : Try(Surreal.Inbox, Surreal.Error), U64 -> Try(Surreal.Inbox, Surreal.Error)
without_reply = |inbox, id| match inbox?.take_reply(id) {
	Taken(t) => Ok(t.inbox)
	Waiting => Err(Wire("no reply ${id.to_str()}"))
}

## Each queued notice of a watch, taken and applied in turn: the watch and
## the inbox after them, the changes, and what the inbox says then.
Drained : { live : Surreal.Live(Row), inbox : Surreal.Inbox, changes : List(Surreal.Change(Row)), last : [Waiting, Ended] }

drained : Surreal.Live(Row), Try(Surreal.Inbox, Surreal.Error) -> Try(Drained, Surreal.Error)
drained = |live, inbox| drain_from({ live, inbox: inbox?, changes: [], last: Waiting })

drain_from : Drained -> Try(Drained, Surreal.Error)
drain_from = |state| match state.inbox.take_notice(state.live.lives()) {
	Taken(t) =>
		match state.live.receive(t.bytes)? {
			Got(c) => drain_from({ live: c.live, inbox: t.inbox, changes: state.changes.concat(c.item), last: Waiting })
			Skip(later) => drain_from({ live: later, inbox: t.inbox, changes: state.changes, last: Waiting })
			Ended => Ok({ ..state, inbox: t.inbox, last: Ended })
		}
	Waiting => Ok({ ..state, last: Waiting })
	Ended => Ok({ ..state, last: Ended })
}

## The frames, read into the inbox that a case before left.
fed_after : Try(Drained, Surreal.Error), List(List(U8)) -> Try(Surreal.Inbox, Surreal.Error)
fed_after = |before, frames| fed(before?.inbox, frames)

## The notices of the watch that a case before left.
drained_after : Try(Drained, Surreal.Error), Try(Surreal.Inbox, Surreal.Error) -> Try(Drained, Surreal.Error)
drained_after = |before, inbox| drained(before?.live, inbox)

## The reply is not in the inbox yet.
waits : [Taken({ bytes : List(U8), inbox : Surreal.Inbox }), Waiting] -> Bool
waits = |took| match took {
	Taken(_) => Bool.False
	Waiting => Bool.True
}

## No notice of the watch is queued, and none comes again.
ends : [Taken({ bytes : List(U8), inbox : Surreal.Inbox }), Waiting, Ended] -> Bool
ends = |took| match took {
	Ended => Bool.True
	Taken(_) | Waiting => Bool.False
}

## The same changes, in any order.
same_changes : List(Surreal.Change(Row)), List(Surreal.Change(Row)) -> Bool
same_changes = |got, want| got.len() == want.len() and want.all(|w| got.contains(w))

ref : Surreal.Table(Row), Str -> Surreal.Ref
ref = |table, key| match table.ref({ id: key, v: 0 }) {
	Ok(r) => r
	Err(_) => crash "a row with a text key has a ref"
}

added : Surreal.Table(Row), Str, I64 -> Surreal.Change(Row)
added = |table, key, v| Added(ref(table, key), { id: key, v })

updated : Surreal.Table(Row), Str, I64 -> Surreal.Change(Row)
updated = |table, key, v| Updated(ref(table, key), { id: key, v })

removed : Surreal.Table(Row), Str, I64 -> Surreal.Change(Row)
removed = |table, key, v| Removed(ref(table, key), { id: key, v })

## The uuids of the queued notices.
queued : Try(Surreal.Inbox, Surreal.Error) -> List(Surreal.Uuid)
queued = |inbox| match inbox {
	Ok(i) => i.notices().map(|n| n.live)
	Err(_) => []
}

uuid_of : Surreal.Live(Row) -> Surreal.Uuid
uuid_of = |live| match live.lives() {
	[one] => one.id
	_ => crash "a watch with no link has one live query"
}

# ------------------------------------------------------------- case A

# Five requests in flight: 10 sleeps, 11 and 13 create rows. The replies
# come out of order, and each is kept by its id until a call takes it.
a_inbox : Try(Surreal.Inbox, Surreal.Error)
a_inbox = fed(watching, a_frames)

expect (reply_at(a_frames, 11) ?? 9) < (reply_at(a_frames, 10) ?? 0)
expect reply_at(a_frames, 10) == Ok(6)
expect a_inbox.map_ok(|i| i.replies().len()) == Ok(5)
expect [10, 11, 12, 13, 14].all(|id| gives_reply(a_inbox, id))

# Before its reply comes, the call that waits for 10 reads on.
expect match fed(watching, a_frames.drop_last(1)) {
	Ok(i) => waits(i.take_reply(10))
	Err(_) => Bool.False
}

# The notices of the two creates are kept while the replies come.
a_drained : Try(Drained, Surreal.Error)
a_drained = drained(live_a, a_inbox)

expect a_drained.map_ok(|d| same_changes(d.changes, [added(mux_a, "k1", 1), added(mux_a, "k2", 2)])) == Ok(Bool.True)
expect a_drained.map_ok(|d| d.last) == Ok(Waiting)

# A notice of a uuid that no watch of the session opened is dropped.
expect fed(Surreal.Inbox.empty({}), a_frames).map_ok(|i| i.notices().len()) == Ok(0)
expect fed(Surreal.Inbox.empty({}), a_frames).map_ok(|i| i.replies().len()) == Ok(5)

# ------------------------------------------------------------- case B

# A write over HTTP while request 20 sleeps: both notices come before the
# reply, and stay in the inbox.
b_inbox : Try(Surreal.Inbox, Surreal.Error)
b_inbox = fed_after(a_drained, b_frames)

expect reply_at(b_frames, 20) == Ok(2)
expect match fed_after(a_drained, b_frames.take_first(2)) {
	Ok(i) => waits(i.take_reply(20)) and i.notices().len() == 2
	Err(_) => Bool.False
}
expect gives_reply(b_inbox, 20)

b_drained : Try(Drained, Surreal.Error)
b_drained = drained_after(a_drained, without_reply(b_inbox, 20))

expect b_drained.map_ok(|d| d.changes == [added(mux_a, "k3", 3), removed(mux_a, "k1", 1)]) == Ok(Bool.True)

# ------------------------------------------------------------- case C

# A create and a `RETURN` in one request. The notice of the create can
# come after the reply to the request that made it: the inbox keeps it.
c_inbox : Try(Surreal.Inbox, Surreal.Error)
c_inbox = fed_after(b_drained, c_frames)

expect gives_reply(c_inbox, 30)

c_drained : Try(Drained, Surreal.Error)
c_drained = drained_after(b_drained, without_reply(c_inbox, 30))

expect c_drained.map_ok(|d| d.changes == [added(mux_a, "k4", 4)]) == Ok(Bool.True)

# ------------------------------------------------------------- two watches

# One request writes to both tables. The notices of one watch are taken,
# and the notices of the other stay, in their order.
two_inbox : Try(Surreal.Inbox, Surreal.Error)
two_inbox = without_reply(fed_after(c_drained, two_frames), 41)

two_b : Try(Drained, Surreal.Error)
two_b = drained(live_b, two_inbox)

expect two_b.map_ok(|d| d.changes == [added(mux_b, "k1", 1), updated(mux_b, "k1", 2)]) == Ok(Bool.True)
expect queued(two_b.map_ok(|d| d.inbox)) == [uuid_of(live_a), uuid_of(live_a)]

two_a : Try(Drained, Surreal.Error)
two_a = drained_after(c_drained, two_b.map_ok(|d| d.inbox))

expect two_a.map_ok(|d| d.changes == [added(mux_a, "k5", 5), updated(mux_a, "k5", 6)]) == Ok(Bool.True)
expect queued(two_a.map_ok(|d| d.inbox)) == []

# ------------------------------------------------------------- case E

# 50 creates a row; after its reply, `kill` of the watch of mux_a (51) and
# a create on mux_b (52). `kill!` unwatches mux_a when it sends 51. Its
# `KILLED` came before or after the reply to 51 (both seen): the frames are
# also read with the two swapped. The notice of the create can come before
# or after the reply to 50: the frames are also read with that notice
# first, so that it is queued when `kill!` unwatches. In each order, the
# watch of mux_a ends with no notice queued, and the notice of mux_b stays.
e_swapped : List(List(U8))
e_swapped = {
	killed_at = e_frames.find_first_index(|f| Surreal.Inbox.key_of(f) == Ok(Notice({ live: uuid_of(live_a), killed: Bool.True }))) ?? 0
	reply_51 = reply_at(e_frames, 51) ?? 0
	e_frames.swap(killed_at, reply_51) ?? []
}

e_notice_first : List(List(U8))
e_notice_first = {
	created = Ok(Notice({ live: uuid_of(live_a), killed: Bool.False }))
	e_frames.keep_if(|f| Surreal.Inbox.key_of(f) == created).concat(e_frames.drop_if(|f| Surreal.Inbox.key_of(f) == created))
}

## The frames up to the reply to 50, then `unwatch`, then the rest.
killed_inbox : List(List(U8)) -> Try(Surreal.Inbox, Surreal.Error)
killed_inbox = |frames| {
	upto = (reply_at(frames, 50) ?? 0) + 1
	sent = fed(watching, frames.take_first(upto))?.unwatch(live_a.lives())
	fed(sent, frames.drop_first(upto))
}

expect e_swapped != e_frames
expect e_notice_first.len() == e_frames.len() and reply_at(e_notice_first, 50) == Ok(1)
expect [e_frames, e_swapped, e_notice_first].all(
	|frames| {
		inbox = killed_inbox(frames)
		ended = match inbox {
			Ok(i) => ends(i.take_notice(live_a.lives()))
			Err(_) => Bool.False
		}
		ended and queued(inbox) == [uuid_of(live_b)] and [50, 51, 52].all(|id| gives_reply(inbox, id))
	},
)

# With no `kill!` on this session, `KILLED` is a notice of the watch: the
# watch reads its notices, then ends.
e_drained : Try(Drained, Surreal.Error)
e_drained = drained(live_a, fed(watching, e_frames))

expect e_drained.map_ok(|d| d.changes == [added(mux_a, "k6", 6)]) == Ok(Bool.True)
expect e_drained.map_ok(|d| d.last) == Ok(Ended)
expect e_drained.map_ok(|d| ends(d.inbox.take_notice(live_a.lives()))) == Ok(Bool.True)

# ------------------------------------------------------------- a watch that starts

# A notice can come before the reply to the request of its watch. While a
# watch starts, a notice of a uuid that is not known yet is held; `watch`
# keeps the notices of the new uuids and drops the others. `c_0` is the
# notice of case `c` (SurrealDB 4.0.1 sent it before the reply).
expect fed(Surreal.Inbox.empty({}), [c_0]).map_ok(|i| i.notices().len()) == Ok(0)
expect fed(Surreal.Inbox.empty({}).start(), [c_0]).map_ok(|i| i.notices().len()) == Ok(0)
expect queued(fed(Surreal.Inbox.empty({}).start(), [c_0]).map_ok(|i| i.watch(live_a.lives()))) == [uuid_of(live_a)]
expect queued(fed(Surreal.Inbox.empty({}).start(), two_frames).map_ok(|i| i.watch(live_b.lives()))) == [uuid_of(live_b), uuid_of(live_b)]
