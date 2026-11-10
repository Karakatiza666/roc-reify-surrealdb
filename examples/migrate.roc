# Migrations for an app on basic-cli: copy this file, set `folder`, and put
# your schema in `schema`. The Roc schema is the source of truth. The folder
# `db/` holds the snapshot (`schema.surql`, the text of the schema that the
# migrations make) and the migration files, which you review and commit.
#
#   roc examples/migrate.roc -- plan 0003_name           write the next file (KeepData)
#   roc examples/migrate.roc -- plan 0003_name --drop    the same, and drop removed data
#   roc examples/migrate.roc -- check                    exit 1 when the schema has changes that no file has
#   roc examples/migrate.roc -- squash 0004_base         one file in place of all the files
#   roc examples/migrate.roc -- up [127.0.0.1:8000]      apply the files (what an app does at start)
#   roc test examples/migrate.roc                        the expects: snapshot and schema agree
#
# After `plan`, read the warnings, write each value that a `-- reify: edit`
# line asks for and remove the line, then add the `import` line that `plan`
# prints and the file to `migrations`. Run each `roc` from the repository root.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.27.0/9yjxqdGTP4xSpSEmDazwTmRsehfRZzA19pwEKkR6fj1g.tar.zst",
	cli_ws: "https://github.com/Karakatiza666/roc-basic-cli-websocket/releases/download/0.0.4/B5j45zNdyW8Qxq6GpQ6ZVNmcPC5hwx3TxPRW4cq8wiLV.tar.zst",
	surreal: "../src/main.roc",
}

import pf.Path
import pf.Stdout
import cli_ws.WsClient
import surreal.Surreal
import "db/schema.surql" as snapshot : Str
import "db/migrations/0001_init.surql" as m0001_init : Str
import "db/migrations/0002_bin_size.surql" as m0002_bin_size : Str

# ------------------------------------------------------------- the schema

Bin : { id : Str, label : Str, size : I64 }

bins : Surreal.Table(Bin)
bins = Surreal.table("bin")

schema : List(Surreal.Defined)
schema = [bins.define().default(|b| b.size, 1).index(|b| b.size).done()]

# ------------------------------------------------------------- the files

## The server that the files are for: `V4` for SurrealDB 4 at compatibility
## level 4, `V3` for SurrealDB 3.3.
db_target : Surreal.MigrationTarget
db_target = V4

## The folder of `snapshot` and of the files, from where `roc` runs.
folder : Str
folder = "examples/db"

## The files, in order. Add each new one here and as an `import`.
migrations : Try(List(Surreal.Migration), Surreal.Error)
migrations = [("0001_init", m0001_init), ("0002_bin_size", m0002_bin_size)].map_try(|(name, text)| Surreal.migration(name, text))

expect Surreal.check(snapshot, schema).is_ok()
expect migrations.is_ok()

# ------------------------------------------------------------- dev

## Writes the next file and the new snapshot.
plan! : Str, [KeepData, DropData] => Try({}, Str)
plan! = |name, mode| {
	planned = Surreal.plan(snapshot, schema, db_target).map_err(Str.inspect)?
	if planned.is_empty(mode) {
		return say!("The snapshot is the schema: no file to write.")
	}
	file = "${folder}/migrations/${name}.surql"
	if Path.unix(file).exists!().map_err(Str.inspect)? {
		return Err("${file} exists")
	}
	Path.unix(file).write_utf8!(planned.to_file(name, mode)).map_err(Str.inspect)?
	Path.unix("${folder}/schema.surql").write_utf8!(planned.snapshot(mode)).map_err(Str.inspect)?
	planned.warnings().for_each!(|w| Stdout.line!("warning: ${Str.inspect(w)}") ?? {})
	say!("Wrote ${file} and ${folder}/schema.surql. Review the file, then add:")?
	say!("    import \"db/migrations/${name}.surql\" as m${name} : Str")?
	say!("and (\"${name}\", m${name}) to `migrations`.")
}

## Whether the snapshot is the schema.
check! : {} => Try({}, Str)
check! = |{}| say!(checked(Surreal.check(snapshot, schema))?)

checked : Try({ pending_drops : List(Str) }, Surreal.Error) -> Try(Str, Str)
checked = |result| match result {
	Ok(agreed) if agreed.pending_drops.is_empty() => Ok("ok: the snapshot is the schema")
	Ok(agreed) => Ok("ok: the snapshot is the schema; kept and not in the schema: ${Str.join_with(agreed.pending_drops, ", ")}")
	Err(Migration({ problem: Unplanned(statements), .. })) => Err("the schema has changes that no file has; run `plan`:\n${Str.join_with(statements, "\n")}")
	Err(e) => Err(Str.inspect(e))
}

## One file in place of all the files: a database that applied them
## records it, an empty one runs it.
squash! : Str => Try({}, Str)
squash! = |name| {
	names = migrations.map_err(Str.inspect)?.map(|m| m.name())
	base = Surreal.plan("", schema, db_target).map_err(Str.inspect)?
	file = "${folder}/migrations/${name}.surql"
	Path.unix(file).write_utf8!(base.replacing(names).to_file(name, DropData)).map_err(Str.inspect)?
	Path.unix("${folder}/schema.surql").write_utf8!(base.snapshot(DropData)).map_err(Str.inspect)?
	say!("Wrote ${file}. Remove the imports of ${Str.join_with(names, ", ")} and put ${name} in their place.")
}

# ------------------------------------------------------------- deploy

## What an app does at start: apply the files that the database does not
## have. Never run `Surreal.schema` at each start.
up! : Str => Try({}, Str)
up! = |host| {
	files = migrations.map_err(Str.inspect)?
	session = Surreal.Session.open!(Surreal.Transport.websocket_timed(WsClient.connect, WsClient.ops, "ws://${host}"), Root({ ns: "roc", db: "migrate_example", user: "root", pass: "root" })).map_err(Str.inspect)?
	done = session.migrate!(files).map_err(Str.inspect)?
	say!("ran ${Str.inspect(done.applied.ran)}, recorded ${Str.inspect(done.applied.adopted)}, newer ${Str.inspect(done.applied.ahead)}")
}

say! : Str => Try({}, Str)
say! = |line| Stdout.line!(line).map_err(Str.inspect)

main! = |args| {
	texts = args.keep_oks(
		|arg| match arg {
			Utf8(text) => Ok(text)
			UnixBytes(bytes) => Str.from_utf8(bytes)
			WindowsU16s(_) => Err(NotText)
		},
	).drop_first(1)
	done = match texts {
		["plan", name] => plan!(name, KeepData)
		["plan", name, "--drop"] => plan!(name, DropData)
		["check"] => check!({})
		["squash", name] => squash!(name)
		["up", host] => up!(host)
		["up"] | [] => up!("127.0.0.1:8000")
		_ => Err("usage: plan NAME [--drop] | check | squash NAME | up [HOST:PORT]")
	}
	match done {
		Ok({}) => Ok({})
		Err(problem) => {
			Stdout.line!("error: ${problem}")?
			Err(Exit(1))
		}
	}
}
