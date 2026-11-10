app [main!] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.4.0/EnfRKFT7uPHmd3zT5PcwAiBWUtGmBXapJqFK5166U33J.tar.zst",
	internal: "../src/internal.roc",
}

import internal.Surreal
import "fixtures/mux/start/00.cbor" as start_a : List(U8)
import "fixtures/mux/a/00.cbor" as a_0 : List(U8)
import "fixtures/mux/a/01.cbor" as a_1 : List(U8)
import "fixtures/mux/a/02.cbor" as a_2 : List(U8)
import "fixtures/mux/a/03.cbor" as a_3 : List(U8)
import "fixtures/mux/a/04.cbor" as a_4 : List(U8)
import "fixtures/mux/a/05.cbor" as a_5 : List(U8)
import "fixtures/mux/a/06.cbor" as a_6 : List(U8)

# Tests of `Session.next_within!` without a server: a session over a scripted
# adapter, which gives the frames that SurrealDB 3.3.4 sent (`fixtures/mux/`)
# and the silences between them, and answers `receive_within!` of 50 ms
# with `TimedOut` at a silence. `roc test` runs the expects, and
# `roc tests/DeadlineTest.roc` runs the session (`main!`) and prints an
# `ok` or `FAIL` line for each check, with the exit code 1 when one fails.
# Nothing outside this file imports it.

Row : { id : Str, v : I64 }

mux_a : Surreal.Table(Row)
mux_a = Surreal.table("mux_a")

watch_a : Surreal.Watch(Row)
watch_a = match Surreal.from(mux_a).select(|r| r).live({}, []).checked() {
	Ok(w) => w
	Err(_) => crash "a watch of a whole row translates"
}

ref : Str -> Surreal.Ref
ref = |key| match mux_a.ref({ id: key, v: 0 }) {
	Ok(r) => r
	Err(_) => crash "a row with a text key has a ref"
}

added : Str, I64 -> Surreal.Change(Row)
added = |key, v| Added(ref(key), { id: key, v })

live_a : Surreal.Live(Row)
live_a = match watch_a.start(start_a) {
	Ok(started) => started.live
	Err(_) => crash "the recorded reply to the watch of mux_a reads"
}

# ------------------------------------------------------------- the frames

## The replies to `signin` (1) and `use` (2): `{ id, result: null }`.
reply_1 : List(U8)
reply_1 = [162, 98, 105, 100, 1, 102, 114, 101, 115, 117, 108, 116, 246]

reply_2 : List(U8)
reply_2 = [162, 98, 105, 100, 2, 102, 114, 101, 115, 117, 108, 116, 246]

## The notices of the watch of the recording, in their order: the creates of
## `k1` and `k2`.
notices : List(List(U8))
notices = [a_0, a_1, a_2, a_3, a_4, a_5, a_6].keep_if(|f| Surreal.Inbox.key_of(f) == Ok(Notice({ live: live_one, killed: Bool.False })))

live_one : Surreal.Uuid
live_one = match live_a.lives() {
	[one] => one.id
	_ => crash "a watch with no link has one live query"
}

notice_1 : List(U8)
notice_1 = match notices {
	[first, ..] => first
	[] => crash "the recording holds two notices"
}

notice_2 : List(U8)
notice_2 = match notices {
	[_, second, ..] => second
	_ => crash "the recording holds two notices"
}

expect notices.len() == 2

# ------------------------------------------------------------- the adapter

## What the scripted server does next: sends a frame, or stays silent.
Step : [Frame(List(U8)), Quiet]

Conn : List(Step)

## The adapter over a script. `receive!` waits with no end, which a script
## cannot do: at a silence or at its end it gives `Closing`. `receive_within!`
## gives `TimedOut` at a silence and at its end, and only for 50 ms.
connect_over = |steps| { connect!: |_| Ok({ conn: steps, protocol: "cbor", extensions: NotReported }) }

ops = {
	send!: |c, _| Ok(c),
	receive!: |c| match c {
		[Frame(bytes), .. as rest] => Ok((rest, Binary(bytes)))
		_ => Err(Closing)
	},
	receive_within!: |c, ms| match (ms, c) {
		(50, [Frame(bytes), .. as rest]) => Ok((rest, Message(Binary(bytes))))
		(50, [Quiet, .. as rest]) => Ok((rest, TimedOut))
		(50, []) => Ok((c, TimedOut))
		_ => Err(Closing)
	},
}

## The steps of a session up to its watch, with a notice before the reply
## to the watch: `Session.live!` holds it in the inbox.
opening : List(Step)
opening = [Frame(reply_1), Frame(reply_2), Frame(notice_1), Frame(start_a)]

timed : List(Step) -> Surreal.Transport
timed = |steps| Surreal.Transport.websocket_timed(connect_over(steps), ops, "ws://scripted")

plain : List(Step) -> Surreal.Transport
plain = |steps| Surreal.Transport.websocket(connect_over(steps), ops, "ws://scripted")

login : Surreal.Login
login = Root({ ns: "roc", db: "roc_surreal", user: "root", pass: "root" })

# ------------------------------------------------------------- the checks

## A line for a check: `ok` when `agrees`.
Verdict : { name : Str, agrees : Bool, text : Str }

verdict : Str, Bool, Str -> Verdict
verdict = |name, agrees, text| { name, agrees, text }

## What `next_within!` gave, as text.
shown : { session : Surreal.Session, live : Surreal.Live(Row), next : [Got(List(Surreal.Change(Row))), Ended, Unread(Surreal.Error), TimedOut] } -> Str
shown = |got| match got.next {
	Got(changes) => "Got ${Str.inspect(changes)}"
	Ended => "Ended"
	Unread(e) => "Unread ${Str.inspect(e)}"
	TimedOut => "TimedOut"
}

## `next_within!` of 50 ms, four times, on a session over `Transport.websocket_timed`.
timed_checks! : {} => Try(List(Verdict), Surreal.Error)
timed_checks! = |{}| {
	opened = Surreal.Session.open!(timed(opening.concat([Quiet, Frame(notice_2)])), login)?
	started = opened.live!(watch_a)?
	# The notice that the inbox holds comes first, with no read: the script is
	# at its silence, and a read would give `TimedOut`.
	first = started.session.next_within!(started.live, 50)?
	second = first.session.next_within!(first.live, 50)?
	third = second.session.next_within!(second.live, 50)?
	fourth = third.session.next_within!(third.live, 50)?
	Ok([
		verdict("buffered notice before any wait", shown(first) == "Got ${Str.inspect([added("k1", 1)])}", shown(first)),
		verdict("a silence is TimedOut", shown(second) == "TimedOut", shown(second)),
		verdict("a notice after the silence", shown(third) == "Got ${Str.inspect([added("k2", 2)])}", shown(third)),
		verdict("the end of the script is TimedOut", shown(fourth) == "TimedOut", shown(fourth)),
	])
}

## `next_within!` on a session over `Transport.websocket`: an `Unsupported`
## error that names `websocket_timed`, with the notice still in the inbox.
plain_checks! : {} => Try(List(Verdict), Surreal.Error)
plain_checks! = |{}| {
	opened = Surreal.Session.open!(plain(opening), login)?
	started = opened.live!(watch_a)?
	waited = started.session.next_within!(started.live, 50)
	read = started.session.next!(started.live)?
	Ok([
		verdict("NoDeadline is an Unsupported error", unsupported_timed(waited), text_of(waited)),
		verdict("next! still gives the notice", shown_next(read) == "Got ${Str.inspect([added("k1", 1)])}", shown_next(read)),
	])
}

text_of : Try(a, Surreal.Error) -> Str
text_of = |got| match got {
	Err(e) => Str.inspect(e)
	Ok(_) => "a result"
}

unsupported_timed : Try(a, Surreal.Error) -> Bool
unsupported_timed = |got| match got {
	Err(Unsupported(why)) => why.contains("Transport.websocket_timed")
	_ => Bool.False
}

shown_next : { session : Surreal.Session, live : Surreal.Live(Row), next : [Got(List(Surreal.Change(Row))), Ended, Unread(Surreal.Error)] } -> Str
shown_next = |got| match got.next {
	Got(changes) => "Got ${Str.inspect(changes)}"
	Ended => "Ended"
	Unread(e) => "Unread ${Str.inspect(e)}"
}

main! = |_args| {
	checks = match (timed_checks!({}), plain_checks!({})) {
		(Ok(a), Ok(b)) => a.concat(b)
		(Err(e), _) | (_, Err(e)) => [verdict("the session runs", Bool.False, Str.inspect(e))]
	}
	for check in checks {
		echo!("${if (check.agrees) "ok  " else "FAIL"} ${check.name}: ${check.text}\n")
	}
	if checks.all(|c| c.agrees) Ok({}) else Err(Exit(1))
}
