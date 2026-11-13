app [] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.4.0/EnfRKFT7uPHmd3zT5PcwAiBWUtGmBXapJqFK5166U33J.tar.zst",
	internal: "../src/internal.roc",
}

import internal.Surreal
import internal.Migrate

# Tests of migrations, with no server: what a plan writes, the file
# format, the snapshot, and what the runner does from a history.
# `tests/MigrateServer.roc` runs the files on SurrealDB 4.0.1.
MigrateTest :: {}

BinV1 : { id : Str, label : Str, code : Str }

BinV2 : { id : Str, label : Str, code : Str, size : I64 }

BinV3 : { id : Str, label : Str, code : I64, size : I64 }

Count : { label : Str, n : U64 }

bins1 : Surreal.Table(BinV1)
bins1 = Surreal.table("bin")

bins2 : Surreal.Table(BinV2)
bins2 = Surreal.table("bin")

bins3 : Surreal.Table(BinV3)
bins3 = Surreal.table("bin")

v1 : List(Surreal.Defined)
v1 = [bins1.define().done()]

## `size` is new, with a default, and has an index.
v2 : List(Surreal.Defined)
v2 = [bins2.define().default(|b| b.size, 1).index(|b| b.size).done()]

## `code` becomes a number.
v3 : List(Surreal.Defined)
v3 = [bins3.define().default(|b| b.size, 1).default(|b| b.code, 0).index(|b| b.size).done()]

## `size` with no default.
v2_bare : List(Surreal.Defined)
v2_bare = [bins2.define().index(|b| b.size).done()]

## A view over `bin`.
counts : Surreal.Table(Count)
counts = Surreal.view("bin_count")

label_of : BinV1 -> Str
label_of = |b| b.label

count_line : Str, List(BinV1) -> Count
count_line = |label, rows| { label, n: rows.len() }

count_def : Surreal.Defined
count_def = counts.define_as(Surreal.from(bins1).group_by(label_of), count_line).done()

snap1 : Str
snap1 = Surreal.schema(v1) ?? ""

plan_to : List(Surreal.Defined) -> Surreal.Plan
plan_to = |defs| match Surreal.plan(snap1, defs) {
	Ok(p) => p
	Err(_) => crash "the schemas translate"
}

# ------------------------------------------------------------- plans

# The new field converts the rows with `MIGRATE EXISTING ROWS`, and
# its index waits for section 2, since SurrealDB 4 refuses an index in the
# transaction that migrates its table. The migration name has the start
# of the hash of the snapshot.
seed : Str
seed = Str.from_utf8(Crypto.SHA256.hash(snap1.to_utf8()).to_hex().to_utf8().take_first(8)) ?? ""

expect plan_to(v2).statements(DropData) == [["DEFINE FIELD OVERWRITE size ON bin TYPE int DEFAULT 1 MIGRATE EXISTING ROWS AS m_${seed}_bin_size USING 1"], ["DEFINE INDEX OVERWRITE bin_size_index ON bin FIELDS size"]]

# A type that does not take the old values: a cast, and the default for a
# value that does not convert.
expect plan_to(v3).statements(DropData).first() == Ok(["DEFINE FIELD OVERWRITE code ON bin TYPE int DEFAULT 0 MIGRATE EXISTING ROWS AS m_${seed}_bin_code USING <int> $value FALLBACK 0", "DEFINE FIELD OVERWRITE size ON bin TYPE int DEFAULT 1 MIGRATE EXISTING ROWS AS m_${seed}_bin_size USING 1"])
expect plan_to(v3).warnings().contains(TypeChanged({ table: "bin", path: "code", from: "string", to: "int" }))

# A view over a migrated table: removed in section 1, defined in section 2.
expect
	match Surreal.plan(Surreal.schema(v1.append(count_def)) ?? "", v2.append(count_def)) {
		Ok(p) => {
			parts = p.statements(DropData)
			(parts.first().map_ok(|s| s.first()), parts.last().map_ok(|s| s.last().map_ok(|l| l.starts_with("DEFINE TABLE OVERWRITE bin_count"))), p.warnings().contains(ViewRebuilt("bin_count")))
		}
		Err(_) => (Err(ListWasEmpty), Err(ListWasEmpty), Bool.False)
	}
	== (Ok(Ok("REMOVE TABLE IF EXISTS bin_count")), Ok(Ok(Bool.True)), Bool.True)

# The same schema: no statement, no section. A plan from "" is the schema.
expect plan_to(v1).is_empty(DropData)
expect Surreal.plan("", v1).map_ok(|p| p.statements(DropData)) == Surreal.schema(v1).map_ok(|text| [text.split_on("\n").map(|l| l.drop_suffix(";"))])

# A dropped field: the plan removes its definition only, as level 4
# clears the values.
expect Surreal.plan(Surreal.schema(v2) ?? "", v2.map(|_| bins1.define().done())).map_ok(|p| p.statements(DropData)) == Ok([["REMOVE INDEX IF EXISTS bin_size_index ON bin", "REMOVE FIELD IF EXISTS size ON bin"]])

# ------------------------------------------------------------- files

expect
	plan_to(v2).to_file("0002_size", DropData)
	== "-- reify-surrealdb migration 0002_size target V4 from ${Crypto.SHA256.hash(snap1.to_utf8()).to_hex()}\nDEFINE FIELD OVERWRITE size ON bin TYPE int DEFAULT 1 MIGRATE EXISTING ROWS AS m_${seed}_bin_size USING 1;\n-- reify: commit\nDEFINE INDEX OVERWRITE bin_size_index ON bin FIELDS size;\n"

# With no default, the plan cannot pick the value: an edit line and a
# placeholder, a warning, and `migration` refuses the file.
bare_file : Str
bare_file = plan_to(v2_bare).to_file("0002_size", DropData)

expect bare_file.contains("\n-- reify: edit write the value that the rows of `bin` get for `size` in place of NONE; then remove this line\nDEFINE FIELD OVERWRITE size ON bin TYPE int MIGRATE EXISTING ROWS AS m_${seed}_bin_size USING NONE;\n")
expect bare_file.contains("\n-- warning: `bin.size` has no DEFAULT: write the value for the rows that are there\n")
expect Surreal.migration("0002_size", bare_file).map_ok(|m| m.name()) == Err(Migration({ name: "0002_size", problem: Edit }))

# After the edit, the file reads.
edited : Str
edited = bare_file.split_on("\n").keep_if(|l| !l.starts_with("-- reify: edit")).map(|l| l.replace_each("USING NONE", "USING 5")) |> Str.join_with("\n")

expect Surreal.migration("0002_size", edited).map_ok(|m| (m.sections(), m.checksum())) == Ok((2, Crypto.SHA256.hash(edited.to_utf8()).to_hex()))

# The header names the file and has `target V4`; a `BEGIN`, and an index
# with a write on its table in one section, are refused.
expect Surreal.migration("0003_other", edited).is_err()
expect Surreal.migration("0002_size", "DEFINE TABLE x;").is_err()
expect Surreal.migration("0002_size", "-- reify-surrealdb migration 0002_size\nDEFINE TABLE x;").is_err()
expect Surreal.migration("0002_size", "-- reify-surrealdb migration 0002_size target V4\nBEGIN;\nDEFINE TABLE x;\nCOMMIT;") == Err(Migration({ name: "0002_size", problem: Text("a file has no BEGIN, COMMIT or CANCEL: the runner makes each section one transaction") }))
expect
	match Surreal.migration("0002_size", "-- reify-surrealdb migration 0002_size target V4\nupdate Bin:1 SET size = 2;\nDEFINE INDEX OVERWRITE i ON Bin FIELDS size;") {
		Err(Migration({ problem: Text(why), .. })) => why.starts_with("section 1 defines an index on `Bin` and writes to it")
		_ => Bool.False
	}
expect Surreal.migration("0002_size", "-- reify-surrealdb migration 0002_size target V4\nUPDATE bin:1 SET size = 2;\n-- reify: commit\nDEFINE INDEX OVERWRITE i ON bin FIELDS size;").map_ok(|m| m.sections()) == Ok(2)
expect Surreal.migration("0002_size", "-- reify-surrealdb migration 0002_size from x\nDEFINE TABLE x;") == Err(Migration({ name: "0002_size", problem: Text("the header has no `target V4`") }))

# A file of 0.0.3 or before for SurrealDB 3 (`target V3`) is refused,
# also with no statement that SurrealDB 4 refuses.
expect Surreal.migration("0002_size", "-- reify-surrealdb migration 0002_size target V3 from x\nDEFINE TABLE x;") == Err(Migration({ name: "0002_size", problem: Legacy }))
expect Surreal.migration("0002_size", "-- reify-surrealdb migration 0002_size target V3\nUPDATE bin:1 SET size = 2;\nDEFINE INDEX OVERWRITE i ON bin FIELDS size;") == Err(Migration({ name: "0002_size", problem: Legacy }))
# A file of 0.0.2 or 0.0.3 for SurrealDB 4 reads as it is, with its checksum.
expect Surreal.migration("0001_init", "-- reify-surrealdb migration 0001_init target V4 from x\nDEFINE TABLE x;").map_ok(|m| m.checksum()) == Ok(Crypto.SHA256.hash("-- reify-surrealdb migration 0001_init target V4 from x\nDEFINE TABLE x;".to_utf8()).to_hex())

# A squashed file names what it replaces.
expect Surreal.plan("", v2).map_ok(|p| p.replacing(["0001_init", "0002_size"]).to_file("0003_base", DropData).split_on("\n").first() ?? "") == Ok("-- reify-surrealdb migration 0003_base target V4 from ${Crypto.SHA256.hash([]).to_hex()} replaces 0001_init 0002_size")
expect Surreal.plan("", v2).map_ok(|p| Surreal.migration("0003_base", p.replacing(["0001_init", "0002_size"]).to_file("0003_base", DropData)).map_ok(|m| m.replaces())) == Ok(Ok(["0001_init", "0002_size"]))

# ------------------------------------------------------------- snapshot

# The snapshot is the schema: `check` agrees, and the old snapshot does not.
expect Surreal.check(plan_to(v2).snapshot(DropData), v2) == Ok({ pending_drops: [] })
expect
	match Surreal.check(snap1, v2) {
		Err(Migration({ problem: Unplanned(statements), .. })) => statements.len()
		_ => 0
	}
	== 2

# `KeepData` keeps the dropped field in the snapshot: `check` names it.
expect Surreal.plan(Surreal.schema(v2) ?? "", v2.map(|_| bins1.define().done())).map_ok(|p| Surreal.check(p.snapshot(KeepData), v1)) == Ok(Ok({ pending_drops: ["bin.size"] }))
expect Surreal.plan(Surreal.schema(v2) ?? "", v2.map(|_| bins1.define().done())).map_ok(|p| Surreal.check(p.snapshot(DropData), v1)) == Ok(Ok({ pending_drops: [] }))

# ------------------------------------------------------------- runner

file : Str, Str -> Migrate.File
file = |name, text| match Migrate.parse(name, text) {
	Ok(f) => f
	Err(_) => crash "the test files read"
}

init : Migrate.File
init = file("0001_init", "-- reify-surrealdb migration 0001_init target V4\nDEFINE TABLE OVERWRITE bin SCHEMAFULL;")

size : Migrate.File
size = file("0002_size", edited)

base : Migrate.File
base = file("0003_base", "-- reify-surrealdb migration 0003_base target V4 replaces 0001_init 0002_size\nDEFINE TABLE OVERWRITE bin SCHEMAFULL;")

later : Migrate.File
later = file("0004_later", "-- reify-surrealdb migration 0004_later target V4\nDEFINE TABLE OVERWRITE tag SCHEMAFULL;")

done : Migrate.File -> Migrate.Row
done = |f| { name: f.name, checksum: f.checksum, sections: f.sections.len(), done: f.sections.len() }

level4 : U64
level4 = 4

# A fresh database runs every file from its first section; a database that
# has them all runs nothing.
expect Migrate.decide([], [init, size], level4) == Ok({ actions: [Run({ name: "0001_init", from: 1 }), Run({ name: "0002_size", from: 1 })], ahead: [] })
expect Migrate.decide([done(init), done(size)], [init, size], level4) == Ok({ actions: [], ahead: [] })

# A file that stopped after section 1 goes on at section 2.
expect Migrate.decide([done(init), { ..done(size), done: 1 }], [init, size], level4) == Ok({ actions: [Run({ name: "0002_size", from: 2 })], ahead: [] })

# A changed text, a file before an applied one, two files with one name.
expect Migrate.decide([{ ..done(init), checksum: "x" }], [init, size], level4) == Err(Migration({ name: "0001_init", problem: Changed }))
expect Migrate.decide([done(size)], [init, size], level4) == Err(Migration({ name: "0001_init", problem: OutOfOrder }))
expect Migrate.decide([], [init, init], level4).is_err()

# A record that no file has: a newer app applied it.
expect Migrate.decide([done(init), done(later)], [init], level4) == Ok({ actions: [], ahead: ["0004_later"] })

# A database below level 4 is refused, also with no file to run.
expect Migrate.decide([], [init], 3) == Err(Migration({ name: "", problem: Level({ found: 3 }) }))
expect Migrate.decide([done(init)], [init], 3) == Err(Migration({ name: "", problem: Level({ found: 3 }) }))

# A squashed file: recorded on a database that applied what it replaces,
# run on a fresh one, refused over a part of its files.
expect Migrate.decide([done(init), done(size)], [base, later], level4) == Ok({ actions: [Adopt("0003_base"), Run({ name: "0004_later", from: 1 })], ahead: [] })
expect Migrate.decide([], [base, later], level4) == Ok({ actions: [Run({ name: "0003_base", from: 1 }), Run({ name: "0004_later", from: 1 })], ahead: [] })
expect Migrate.decide([done(init)], [base, later], level4).is_err()
expect Migrate.decide([done(init), { ..done(size), done: 1 }], [base], level4).is_err()

# The request of a section marks it in the history in the same transaction.
expect Migrate.request(init, 1) == "BEGIN;\nCREATE _reify_migration:⟨0001_init⟩ CONTENT { checksum: '${init.checksum}', target: 'V4', sections: 1, done: 1, kind: 'run', applied_at: time::now() } RETURN NONE;\nDEFINE TABLE OVERWRITE bin SCHEMAFULL;\n;\nCOMMIT;"
expect Migrate.request(size, 2).starts_with("BEGIN;\nIF (SELECT VALUE done FROM ONLY _reify_migration:⟨0002_size⟩) != 1 { THROW 'reify: another runner applied section 2 of 0002_size' };\nUPDATE _reify_migration:⟨0002_size⟩ SET done = 2, applied_at = time::now() RETURN NONE;\nDEFINE INDEX")
expect Migrate.level_of("4") == Ok(4)
expect Migrate.level_of("none").is_err()
