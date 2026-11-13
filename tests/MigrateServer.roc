# Migrations on a live SurrealDB 4: `Session.migrate!` runs the files that
# `Surreal.plan` writes, at compatibility level 4, and refuses a database
# at level 3. `tests/check.py` runs it; it makes the databases of
# namespace `roc_mig` empty first.
#
#   roc tests/MigrateServer.roc -- --url 127.0.0.1:8000 --case all
#   roc tests/MigrateServer.roc -- --url 127.0.0.1:8000 --case race
#
# `all` prints a line for each check: `ok` or `FAIL`. `race` runs the files
# of `race_files` once, on the database `race`: `check.py` starts two at once
# and checks that each section ran one time. Each message that a session
# sends prints `     sent`; `check.py` checks that the second run of `all`
# sends one request (between `mark: again` and `mark: done`).
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.27.0/9yjxqdGTP4xSpSEmDazwTmRsehfRZzA19pwEKkR6fj1g.tar.zst",
	cli_ws: "https://github.com/Karakatiza666/roc-basic-cli-websocket/releases/download/0.0.4/B5j45zNdyW8Qxq6GpQ6ZVNmcPC5hwx3TxPRW4cq8wiLV.tar.zst",
	surreal: "../src/main.roc",
}

import pf.Stdout
import cli_ws.WsClient
import surreal.Surreal

# ------------------------------------------------------------- the schemas

BinV1 : { id : Str, label : Str, code : Str }

BinV2 : { id : Str, label : Str, code : Str, size : I64 }

BinV3 : { id : Str, label : Str, code : I64, size : I64 }

bins1 : Surreal.Table(BinV1)
bins1 = Surreal.table("bin")

bins2 : Surreal.Table(BinV2)
bins2 = Surreal.table("bin")

bins3 : Surreal.Table(BinV3)
bins3 = Surreal.table("bin")

v1 : List(Surreal.Defined)
v1 = [bins1.define().done()]

## A new field with a default, and an index on it: two sections.
v2 : List(Surreal.Defined)
v2 = [bins2.define().default(|b| b.size, 1).index(|b| b.size).done()]

## `code` becomes a number: a cast in `MIGRATE EXISTING ROWS`.
v3 : List(Surreal.Defined)
v3 = [bins3.define().default(|b| b.size, 1).default(|b| b.code, 0).index(|b| b.size).done()]

# ------------------------------------------------------------- the files

## A file as `Surreal.plan` writes it, from the snapshot `from`, and the
## snapshot after it.
planned : Str, List(Surreal.Defined), Str -> Try({ file : Surreal.Migration, text : Str, snapshot : Str }, Str)
planned = |from, defs, name| {
	p = Surreal.plan(from, defs).map_err(Str.inspect)?
	text = p.to_file(name, DropData)
	file = Surreal.migration(name, text).map_err(Str.inspect)?
	Ok({ file, text, snapshot: p.snapshot(DropData) })
}

## A file that a person writes.
hand : Str, Str -> Try(Surreal.Migration, Str)
hand = |name, body| Surreal.migration(name, "-- reify-surrealdb migration ${name} target V4\n${body}\n").map_err(Str.inspect)

## The files of `race`: two quick steps, then a file with two sections
## that take a while. Each step adds 1 to a counter.
race_files : {} -> Try(List(Surreal.Migration), Str)
race_files = |{}| {
	init = planned("", v1, "0001_init")?
	a = hand("0002_a", "UPSERT counter:c SET a += 1;")?
	b = hand("0003_b", "UPSERT counter:c SET b += 1;")?
	slow = hand("0004_slow", "UPSERT counter:c SET n += 1;\nSLEEP 1s;\n-- reify: commit\nUPSERT counter:c SET m += 1;\nSLEEP 500ms;")?
	Ok([init.file, a, b, slow])
}

# ------------------------------------------------------------- the server

## The WebSocket, with a line `     sent` for each message the session
## sends: `check.py` counts them between two `mark` lines.
transport : Str -> Surreal.Transport
transport = |host| Surreal.Transport.websocket_timed(WsClient.connect, { ..WsClient.ops, send!: |c, m| sent!(c, m) }, "ws://${host}")

sent! = |c, m| {
	_ = Stdout.line!("     sent")
	c.send!(m)
}

open! : Str, Str => Try(Surreal.Session, Str)
open! = |host, db| Surreal.Session.open!(transport(host), Root({ ns: "roc_mig", db, user: "root", pass: "root" })).map_err(Str.inspect)

## The last result of a request, as a list of numbers.
ints! : Surreal.Session, Str => Try({ session : Surreal.Session, value : List(I64) }, Str)
ints! = |session, text| {
	done = Surreal.Unchecked.query!(session, text).map_err(Str.inspect)?
	reply : Try({ result : List({ status : Str, result : List(I64) }) }, Surreal.Error)
	reply = Surreal.Unchecked.decode(done.reply)
	match reply.map_ok(|r| r.result.last()) {
		Ok(Ok(last)) if last.status == "OK" => Ok({ session: done.session, value: last.result })
		other => Err("${text}: ${Str.inspect(other)}")
	}
}

## Runs statements whose results are not read.
exec! : Surreal.Session, Str => Try(Surreal.Session, Str)
exec! = |session, text| {
	done = Surreal.Unchecked.query!(session, text).map_err(Str.inspect)?
	reply : Try({ result : List({ status : Str }) }, Surreal.Error)
	reply = Surreal.Unchecked.decode(done.reply)
	match reply {
		Ok(r) if r.result.all(|s| s.status == "OK") => Ok(done.session)
		other => Err("${text}: ${Str.inspect(other)}")
	}
}

migrate! : Surreal.Session, List(Surreal.Migration) => Try({ session : Surreal.Session, applied : Surreal.Applied }, Str)
migrate! = |session, files| session.migrate!(files).map_err(Str.inspect)

# ------------------------------------------------------------- the checks

say! : Str => Try({}, Str)
say! = |line| Stdout.line!(line).map_err(Str.inspect)

## `ok` when `got` is `want`, else `FAIL`: the count of failures after it.
same! : U64, Str, a, a => Try(U64, Str) where [a.is_eq : a, a -> Bool]
same! = |failures, name, got, want|
	if got == want {
		say!("ok   ${name}")?
		Ok(failures)
	} else {
		say!("FAIL ${name}: got ${Str.inspect(got)}, expected ${Str.inspect(want)}")?
		Ok(failures + 1)
	}

## The checks of one server.
all! : Str => Try(U64, Str)
all! = |host| {
	probe = migrate!(open!(host, "flow")?, [])?
	var $failures = 0

	# The first file, from an empty snapshot, then two rows.
	f1 = planned("", v1, "0001_init")?
	first = migrate!(probe.session, [f1.file])?
	$failures = same!($failures, "fresh: ran 0001_init", first.applied.ran, ["0001_init"])?
	session1 = exec!(first.session, "CREATE bin:1 CONTENT { label: 'a', code: '5' }; CREATE bin:2 CONTENT { label: 'b', code: 'zz' };")?

	# A field with a default fills the rows; its index is in section 2.
	f2 = planned(f1.snapshot, v2, "0002_size")?
	$failures = same!($failures, "fill: 0002_size has two sections", f2.file.sections(), 2)?
	second = migrate!(session1, [f1.file, f2.file])?
	$failures = same!($failures, "fill: ran 0002_size", second.applied.ran, ["0002_size"])?
	sizes = ints!(second.session, "RETURN [bin:1.size, bin:2.size];")?
	$failures = same!($failures, "fill: the rows have size 1", sizes.value, [1, 1])?
	indexes = ints!(sizes.session, "RETURN [object::len((INFO FOR TABLE bin).indexes), _reify_migration:⟨0002_size⟩.done];")?
	$failures = same!($failures, "fill: the index, and both sections in the history", indexes.value, [1, 2])?

	# A step that a person writes, then a second run: it sends no section.
	f3 = hand("0003_count", "UPSERT counter:c SET n += 1;")?
	third = migrate!(indexes.session, [f1.file, f2.file, f3])?
	$failures = same!($failures, "hand: ran 0003_count", third.applied.ran, ["0003_count"])?
	say!("     mark: again")?
	again = migrate!(third.session, [f1.file, f2.file, f3])?
	say!("     mark: done")?
	$failures = same!($failures, "again: ran nothing", again.applied.ran, [])?
	count = ints!(again.session, "RETURN [counter:c.n];")?
	$failures = same!($failures, "again: the step ran once", count.value, [1])?

	# A type change with a cast; a value that does not cast gets the default.
	f4 = planned(f2.snapshot, v3, "0004_code")?
	fourth = migrate!(count.session, [f1.file, f2.file, f3, f4.file])?
	$failures = same!($failures, "cast: ran 0004_code", fourth.applied.ran, ["0004_code"])?
	codes = ints!(fourth.session, "RETURN [bin:1.code, bin:2.code];")?
	$failures = same!($failures, "cast: '5' is 5, 'zz' is the default 0", codes.value, [5, 0])?
	cast = { session: codes.session, files: [f1.file, f2.file, f3, f4.file], schema: v3 }

	# A squash: the database that applied the files records it, and runs
	# only the file after it.
	names = cast.files.map(|f| f.name())
	base_plan = Surreal.plan("", cast.schema).map_err(Str.inspect)?
	base = Surreal.migration("0005_base", base_plan.replacing(names).to_file("0005_base", DropData)).map_err(Str.inspect)?
	after = hand("0006_after", "DEFINE TABLE OVERWRITE tag SCHEMAFULL;")?
	squashed = migrate!(cast.session, [base, after])?
	$failures = same!($failures, "squash: 0005_base recorded, not run", (squashed.applied.adopted, squashed.applied.ran), (["0005_base"], ["0006_after"]))?

	# A fresh database runs the squashed file.
	fresh = migrate!(open!(host, "fresh")?, [base, after])?
	$failures = same!($failures, "squash, fresh: ran 0005_base and 0006_after", (fresh.applied.adopted, fresh.applied.ran), ([], ["0005_base", "0006_after"]))?
	tables = ints!(fresh.session, "RETURN [object::len((INFO FOR TABLE bin).fields), object::len((INFO FOR TABLE bin).indexes)];")?
	$failures = same!($failures, "squash, fresh: bin has 3 fields and 1 index", tables.value, [3, 1])?

	# A fresh database replays the files.
	replay = migrate!(open!(host, "replay")?, [f1.file, f2.file, f3])?
	$failures = same!($failures, "replay: ran all", replay.applied.ran, ["0001_init", "0002_size", "0003_count"])?

	# A database at level 3 (a SurrealDB 3 datastore after the upgrade) is
	# refused, and no file runs.
	level = open!(host, "level")?
	lowered = exec!(level, "ALTER DATABASE COMPATIBILITY 3;")?
	refused = lowered.migrate!([f1.file])
	$failures = same!($failures, "level: level 3 is refused", refused.map_ok(|_| {}), Err(Migration({ name: "", problem: Level({ found: 3 }) })))?
	raised = exec!(open!(host, "level")?, "ALTER DATABASE COMPATIBILITY 4;")?
	at_four = migrate!(raised, [f1.file])?
	$failures = same!($failures, "level: after the raise to 4, ran 0001_init", at_four.applied.ran, ["0001_init"])?
	Ok($failures)
}

## One runner of `race`.
race! : Str => Try(U64, Str)
race! = |host| {
	session = open!(host, "race")?
	probe = migrate!(session, [])?
	files = race_files({})?
	done = migrate!(probe.session, files)?
	say!("ok   race: ran ${Str.join_with(done.applied.ran, " ")}")?
	Ok(0)
}

## The text after `flag` in the arguments.
option : List(Str), Str -> Str
option = |texts, flag| match texts.find_first_index(|t| t == flag) {
	Ok(at) => texts.get(at + 1) ?? ""
	Err(_) => ""
}

main! = |args| {
	texts = args.keep_oks(
		|arg| match arg {
			Utf8(text) => Ok(text)
			UnixBytes(bytes) => Str.from_utf8(bytes)
			WindowsU16s(_) => Err(NotText)
		},
	)
	host = match option(texts, "--url") {
		"" => "127.0.0.1:8000"
		given => given
	}
	run = match option(texts, "--case") {
		"race" => race!(host)
		_ => all!(host)
	}
	match run {
		Ok(0) => Ok({})
		Ok(_) => Err(Exit(1))
		Err(problem) => {
			Stdout.line!("FAIL ${problem}")?
			Err(Exit(1))
		}
	}
}
