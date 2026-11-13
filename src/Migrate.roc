import Ql
import Schema

# Migrations, pure: the statements of a plan, in sections; the
# text of a migration file and what the runner reads from it; and what the
# runner does for each file, from the history. `Surreal` runs it.
Migrate :: {}.{

	## What a plan does with a table or a field that the schema dropped.
	Mode : [KeepData, DropData]

	## The diff from the snapshot `from` (its statements `old`) to the
	## statements `new` of a schema. `replaces` names the files that a
	## squashed file takes the place of.
	Plan : { steps : List(Schema.Step), old : List(Str), new : List(Str), from : Str, replaces : List(Str) }

	## A statement of a section, and what a person must write in it first.
	Item : { line : Str, edit : Try(Str, [NoEdit]) }

	## What a person reads before a migration file runs.
	Warning : [
		TypeChanged({ table : Str, path : Str, from : Str, to : Str }),
		MaybeRenamed({ table : Str, from : Str, to : Str }),
		UniqueAdded({ table : Str, index : Str }),
		AssertAdded({ table : Str, path : Str }),
		NoDefault({ table : Str, path : Str }),
		Rewritten(List(Str)),
		ViewRebuilt(Str),
		Dropped(Str),
	]

	## A migration file as the runner reads it: each section is the text
	## between two `-- reify: commit` lines.
	File : { name : Str, replaces : List(Str), sections : List(Str), checksum : Str }

	## A record of the history table `_reify_migration`.
	Row : { name : Str, checksum : Str, sections : U64, done : U64 }

	## What the runner does with a file: run its sections from `from`
	## (counted from 1), or record a squashed file whose replaced files
	## the database applied (`Adopt`).
	Action : [Run({ name : Str, from : U64 }), Adopt(Str)]

	# ------------------------------------------------------------ plans

	## The statements of a snapshot: its `DEFINE` lines.
	lines : Str -> List(Str)
	lines = |text| text.split_on("\n").map(Str.trim).keep_if(|l| l.starts_with("DEFINE "))

	## The SHA-256 of a text, as hex.
	hash : Str -> Str
	hash = |text| Crypto.SHA256.hash(text.to_utf8()).to_hex()

	## The sections of a plan. Section 1 has every step. Section 2 has
	## what SurrealDB 4 refuses in a transaction that writes to or
	## migrates a table: an index on such a table, a view over a table
	## that a `MIGRATE` converts (removed in section 1), and a `REBUILD
	## INDEX` for each full-text index of a changed analyzer. A plan with
	## no statement has no section.
	sections : Migrate.Plan, Migrate.Mode -> List(List(Migrate.Item))
	sections = |p, mode| {
		drop = mode == DropData
		moved = Migrate.migrated(p)
		touched = moved.concat(
			p.steps.keep_oks(
				|s| match s {
					DropField(f) if drop => Ok(f.table)
					_ => Err(NoTable)
				},
			),
		)
		views = Migrate.rebuilt_views(p)
		deferred = |line| {
			e = Schema.entry(line)
			(e.kind == "INDEX" and touched.contains(e.on)) or (e.kind == "TABLE" and views.contains(e.name))
		}
		seed = Migrate.hash(p.from).to_utf8().take_first(8)
		context = { drop, seed: Str.from_utf8(seed) ?? "" }
		existed = p.old.map(Schema.entry)
		removed_views = views.keep_if(|v| existed.any(|e| e.kind == "TABLE" and e.name == v)).map(|v| Migrate.plain("REMOVE TABLE IF EXISTS ${v}"))
		first = removed_views.concat(
			p.steps.join_map(
				|s| match s {
					Define(line) if deferred(line) => []
					_ => Migrate.items(s, context)
				},
			),
		)
		indexes = p.steps.keep_oks(
			|s| match s {
				Define(line) if deferred(line) and Schema.entry(line).kind == "INDEX" => Ok(Migrate.plain(line))
				_ => Err(NotDeferred)
			},
		)
		view_lines = p.new.keep_if(|l| views.contains(Schema.entry(l).name) and Schema.is_view(l)).map(|l| Migrate.plain(l.drop_suffix(";")))
		second = indexes.concat(view_lines).concat(Migrate.rebuilds(p).map(Migrate.plain))
		[first, second].keep_if(|part| !part.is_empty())
	}

	plain : Str -> Migrate.Item
	plain = |line| { line, edit: Err(NoEdit) }

	## The tables that a `MIGRATE` converts.
	migrated : Migrate.Plan -> List(Str)
	migrated = |p| p.steps.keep_oks(
		|s| match s {
			Fill(f) => Ok(f.table)
			Retype(r) => Ok(r.table)
			_ => Err(NoTable)
		},
	)

	## The views over a table that a plan migrates: SurrealDB 4 refuses
	## `MIGRATE EXISTING ROWS` on such a table (verified).
	rebuilt_views : Migrate.Plan -> List(Str)
	rebuilt_views = |p| {
		moved = Migrate.migrated(p)
		p.new.map(Schema.entry).keep_if(|e| e.kind == "TABLE" and Schema.is_view(e.line) and moved.contains(Migrate.view_source(e.line))).map(|e| e.name)
	}

	## The table after the first `FROM` of a view.
	view_source : Str -> Str
	view_source = |line| {
		words = Schema.words(line.drop_suffix(";"))
		match words.find_first_index(|w| w == "FROM") {
			Ok(at) => (words.get(at + 1) ?? "").drop_suffix(",")
			Err(_) => ""
		}
	}

	## `REBUILD INDEX` for each full-text index whose analyzer changed and
	## whose own text did not: a changed analyzer does not reach the index
	## that is there (SurrealDB 4 upgrade guide).
	rebuilds : Migrate.Plan -> List(Str)
	rebuilds = |p| {
		defined = p.steps.keep_oks(
			|s| match s {
				Define(line) => Ok(Schema.entry(line))
				_ => Err(NotDefine)
			},
		)
		before = p.old.map(Schema.entry)
		changed = defined.keep_if(|e| e.kind == "ANALYZER" and before.any(|b| b.kind == "ANALYZER" and b.name == e.name)).map(|e| e.name)
		p.new.map(Schema.entry).keep_if(
			|e| {
				words = Schema.words(e.line.drop_suffix(";"))
				uses = match words.find_first_index(|w| w == "ANALYZER") {
					Ok(at) => changed.contains(words.get(at + 1) ?? "")
					Err(_) => Bool.False
				}
				e.kind == "INDEX" and uses and !defined.any(|d| d.kind == "INDEX" and d.name == e.name and d.on == e.on)
			},
		).map(|e| "REBUILD INDEX IF EXISTS ${e.name} ON ${e.on}")
	}

	## The statements of one step.
	items : Schema.Step, { drop : Bool, seed : Str } -> List(Migrate.Item)
	items = |step, c| match step {
		Define(line) | Remove(line) => [Migrate.plain(line)]
		# Level 4 clears the old values itself (verified).
		DropField(f) if c.drop => [Migrate.plain("REMOVE FIELD IF EXISTS ${f.path} ON ${f.table}")]
		DropTable(t) if c.drop => [Migrate.plain("REMOVE TABLE IF EXISTS ${t}")]
		DropField(_) | DropTable(_) => []
		Fill(f) => {
			value = f.value ?? "NONE"
			edit = match f.value {
				Ok(_) => Err(NoEdit)
				Err(NoDefault) => Ok("write the value that the rows of `${f.table}` get for `${f.path}` in place of NONE")
			}
			[{ line: Migrate.migrating(f.line, c.seed, f.table, f.path, "USING ${value}"), edit: Migrate.referenced(f.line, edit) }]
		}
		Retype(r) => {
			to = Schema.unwrapped(r.to)
			cast = Migrate.castable(to.inner)
			convert = "write how an old value of `${r.table}.${r.path}` (${r.from}) becomes a ${r.to}"
			fallback = match r.value {
				Ok(v) => Ok(v)
				Err(_) if to.optional => Ok("NONE")
				Err(_) => Err(NoValue)
			}
			using = if (cast) "<${to.inner}> $value" else "$value"
			edit = match (cast, fallback) {
				(Bool.False, _) => Ok("${convert}, in place of $value")
				(_, Err(_)) => Ok("write the value of `${r.table}.${r.path}` for a row whose old value does not convert, in place of the NONE after FALLBACK")
				_ => Err(NoEdit)
			}
			[{ line: Migrate.migrating(r.line, c.seed, r.table, r.path, "USING ${using} FALLBACK ${fallback ?? "NONE"}"), edit: Migrate.referenced(r.line, edit) }]
		}
	}

	## A `DEFINE FIELD` with `MIGRATE EXISTING ROWS`: a name of its own,
	## since SurrealDB 4 runs each name once.
	migrating : Str, Str, Str, Str, Str -> Str
	migrating = |line, seed, table, path, using| {
		clean = |s| Str.from_utf8(s.to_utf8().map(|b| if ((b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or (b >= '0' and b <= '9')) b else '_')) ?? "x"
		"${line} MIGRATE EXISTING ROWS AS m_${seed}_${clean(table)}_${clean(path)} ${using}"
	}

	## SurrealDB 4 refuses `MIGRATE EXISTING ROWS` on a `REFERENCE` field
	## (verified): such a field needs steps that a person writes.
	referenced : Str, Try(Str, [NoEdit]) -> Try(Str, [NoEdit])
	referenced = |line, edit| if (line.contains(" REFERENCE ")) Ok("SurrealDB 4 does not migrate a REFERENCE field: write the steps for the rows that are there") else edit

	## A type that a cast `<type>` converts to.
	castable : Str -> Bool
	castable = |ty| ["int", "float", "decimal", "number", "string", "bool", "datetime", "duration", "uuid"].contains(ty)

	## The snapshot after the plan: the statements of the schema. With
	## `KeepData` the dropped tables and fields stay, so that a later plan
	## drops them.
	snapshot : Migrate.Plan, Migrate.Mode -> Str
	snapshot = |p, mode| {
		kept = match mode {
			DropData => []
			KeepData => {
				tables = p.steps.keep_oks(
					|s| match s {
						DropTable(t) => Ok(t)
						_ => Err(NotDropped)
					},
				)
				fields = p.steps.keep_oks(
					|s| match s {
						DropField(f) => Ok(f)
						_ => Err(NotDropped)
					},
				)
				p.old.keep_if(
					|l| {
						e = Schema.entry(l)
						(e.kind == "TABLE" and tables.contains(e.name)) or tables.contains(e.on) or (e.kind == "FIELD" and fields.contains({ table: e.on, path: e.name }))
					},
				)
			}
		}
		Str.join_with(p.new.concat(kept), "\n").concat("\n")
	}

	## The tables and the fields (`table.path`) that the schema dropped.
	dropped : Migrate.Plan -> List(Str)
	dropped = |p| p.steps.keep_oks(
		|s| match s {
			DropField(f) => Ok("${f.table}.${f.path}")
			DropTable(t) => Ok(t)
			_ => Err(Kept)
		},
	)

	## What a person reads before the file runs.
	warnings : Migrate.Plan -> List(Migrate.Warning)
	warnings = |p| {
		before = p.old.map(Schema.entry)
		tables = before.keep_if(|b| b.kind == "TABLE").map(|b| b.name)
		previous = |e| before.find_first(|b| b.kind == e.kind and b.name == e.name and b.on == e.on)
		assert_of = |line| match line.drop_suffix(";").split_first(" ASSERT ") {
			Ok(parts) => parts.after
			Err(_) => ""
		}
		per_step = p.steps.join_map(
			|s| match s {
				DropField(f) => [Dropped("${f.table}.${f.path}")]
				DropTable(t) => [Dropped(t)]
				Fill(f) =>
					match f.value {
						Ok(_) => []
						Err(_) => [NoDefault({ table: f.table, path: f.path })]
					}
				Retype(r) => [TypeChanged({ table: r.table, path: r.path, from: r.from, to: r.to })]
				Remove(_) => []
				Define(line) => {
					e = Schema.entry(line)
					was = previous(e)
					match e.kind {
						"INDEX" if line.ends_with(" UNIQUE") and tables.contains(e.on) and !(was.map_ok(|b| b.line.ends_with(" UNIQUE;")) ?? Bool.False) => [UniqueAdded({ table: e.on, index: e.name })]
						"FIELD" if tables.contains(e.on) and assert_of(line) != "" and assert_of(line) != (was.map_ok(|b| assert_of(b.line)) ?? "") => [AssertAdded({ table: e.on, path: e.name })]
						_ => []
					}
				}
			},
		)
		rewritten = p.steps.keep_oks(
			|s| match s {
				Define(line) => {
					e = Schema.entry(line)
					if (e.kind == "INDEX" and previous(e).is_ok()) Ok(e.name) else Err(New)
				}
				_ => Err(New)
			},
		)
		added = p.steps.keep_oks(
			|s| match s {
				Fill(f) => Ok({ table: f.table, path: f.path, line: f.line })
				Define(line) => {
					e = Schema.entry(line)
					if (e.kind == "FIELD" and previous(e).is_err()) Ok({ table: e.on, path: e.name, line }) else Err(Old)
				}
				_ => Err(Old)
			},
		)
		renamed = p.steps.join_map(
			|s| match s {
				DropField(f) => {
					was = before.find_first(|b| b.kind == "FIELD" and b.name == f.path and b.on == f.table).map_ok(|b| Schema.field_type(b.line)) ?? ""
					added.keep_if(|a| a.table == f.table and Schema.field_type(a.line) == was).map(|a| MaybeRenamed({ table: f.table, from: f.path, to: a.path }))
				}
				_ => []
			},
		)
		views = Migrate.rebuilt_views(p).map(|v| ViewRebuilt(v))
		per_step.concat(renamed).concat(if (rewritten.is_empty()) [] else [Rewritten(rewritten)]).concat(views)
	}

	## A warning as the comment of a file.
	warning_text : Migrate.Warning -> Str
	warning_text = |w| match w {
		TypeChanged(t) => "the type of `${t.table}.${t.path}` changes from ${t.from} to ${t.to}: the old values are converted"
		MaybeRenamed(r) => "`${r.table}.${r.from}` is dropped and `${r.table}.${r.to}` is new: for a rename, copy the values in a step before the drop"
		UniqueAdded(u) => "the unique index `${u.index}` on `${u.table}` fails when two rows that are there have the same values"
		AssertAdded(a) => "the ASSERT of `${a.table}.${a.path}` is new or changed: the rows that are there are not checked until their next write"
		NoDefault(n) => "`${n.table}.${n.path}` has no DEFAULT: write the value for the rows that are there"
		Rewritten(names) => "the text of the indexes ${Str.join_with(names.map(|n| "`${n}`"), ", ")} changed: SurrealDB builds each again"
		ViewRebuilt(v) => "the view `${v}` is removed and defined again, because SurrealDB 4 does not migrate a table that a view reads"
		Dropped(name) => "`${name}` is not in the schema: DropData removes it and its data, KeepData keeps both"
	}

	## The text of a migration file: the header, the warnings as
	## comments, then the sections, split by `-- reify: commit`. A
	## statement that needs a value has a `-- reify: edit` line before it.
	## The header names the target `V4`, SurrealDB 4 at compatibility
	## level 4: the one target there is, kept in the text for a later one.
	file : Str, Migrate.Plan, Migrate.Mode -> Str
	file = |name, p, mode| {
		replaces = if (p.replaces.is_empty()) "" else " replaces ${Str.join_with(p.replaces, " ")}"
		header = "-- reify-surrealdb migration ${name} target V4 from ${Migrate.hash(p.from)}${replaces}"
		warns = Migrate.warnings(p).map(|w| "-- warning: ${Migrate.warning_text(w)}")
		body = Migrate.sections(p, mode).map(
			|part| part.join_map(
				|i| match i.edit {
					Ok(e) => ["-- reify: edit ${e}; then remove this line", "${i.line};"]
					Err(_) => ["${i.line};"]
				},
			),
		)
		Str.join_with([header].concat(warns).concat(body.intersperse(["-- reify: commit"]).join()), "\n").concat("\n")
	}

	# ------------------------------------------------------------ files

	## A migration file, read: the header, the sections, the checksum.
	## A `-- reify: edit` line, a `BEGIN`, `COMMIT` or `CANCEL`, and an
	## index and a write on one table in one section are refused. The
	## header must have `target V4`. A file with `target V3` (written by
	## 0.0.3 and before, for SurrealDB 3) is `Legacy`.
	parse : Str, Str -> Try(Migrate.File, Ql.Error)
	parse = |name, text| {
		fail = |problem| Err(Migration({ name, problem }))
		checksum = Migrate.hash(text)
		all = text.split_on("\n")
		words = (all.first() ?? "").trim().split_on(" ").keep_if(|w| w != "")
		if !Migrate.is_name(name) {
			return fail(Text("a name has only letters, digits, `_`, `-` and `.`"))
		}
		rest = match words {
			["--", "reify-surrealdb", "migration", named, .. as others] if named == name => others
			["--", "reify-surrealdb", "migration", named, ..] => return fail(Text("the header names `${named}`"))
			_ => return fail(Text("the first line is not `-- reify-surrealdb migration ${name} target V4`"))
		}
		after = |key| match rest.find_first_index(|w| w == key) {
			Ok(at) => rest.drop_first(at + 1)
			Err(_) => []
		}
		match after("target").first() {
			Ok("V4") => {}
			Ok("V3") => return fail(Legacy)
			_ => return fail(Text("the header has no `target V4`"))
		}
		replaces = after("replaces")
		if !replaces.all(Migrate.is_name) {
			return fail(Text("a name after `replaces` is not a name"))
		}
		body = all.drop_first(1)
		if body.any(|l| l.trim().starts_with("-- reify: edit")) {
			return fail(Edit)
		}
		first_word = |l| (l.trim().with_ascii_uppercased().split_on(" ").first() ?? "").drop_suffix(";")
		if body.any(|l| ["BEGIN", "COMMIT", "CANCEL"].contains(first_word(l))) {
			return fail(Text("a file has no BEGIN, COMMIT or CANCEL: the runner makes each section one transaction"))
		}
		parts = body.fold(
			[[]],
			|acc, l| if (l.trim() == "-- reify: commit") acc.append([]) else acc.drop_last(1).append((acc.last() ?? []).append(l)),
		)
		for (part, k) in parts.map_with_index(|p, k| (p, k)) {
			match Migrate.index_with_writes(part) {
				Ok(t) => return fail(Text("section ${(k + 1).to_str()} defines an index on `${t}` and writes to it or migrates it: SurrealDB 4 refuses that in one transaction, so put the index in a later section"))
				Err(_) => {}
			}
		}
		Ok({ name, replaces, sections: parts.map(|p| Str.join_with(p, "\n")), checksum })
	}

	## Letters, digits, `_`, `-` and `.`: a key of a record id as it is.
	is_name : Str -> Bool
	is_name = |name| !name.is_empty() and name.to_utf8().all(|b| (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or (b >= '0' and b <= '9') or b == '_' or b == '-' or b == '.')

	## A table that the lines of a section define an index on and also
	## write to or migrate, by the first words of each line.
	index_with_writes : List(Str) -> Try(Str, [NotFound])
	index_with_writes = |rows| {
		table = |w| (w.split_first(":").map_ok(|p| p.before) ?? w).drop_suffix(";")
		facts = rows.map(
			|l| {
				# The keywords in capitals; a table name as it is written.
				given = l.trim().split_on(" ").keep_if(|w| w != "")
				words = given.map(Str.with_ascii_uppercased)
				name_at = |k| table(given.get(k) ?? "")
				on = match words.find_first_index(|w| w == "ON") {
					Ok(at) => name_at(at + 1)
					Err(_) => ""
				}
				match words {
					["DEFINE", "INDEX", ..] => { index: on, write: "" }
					["DEFINE", "FIELD", ..] if words.contains("MIGRATE") => { index: "", write: on }
					["REMOVE", "FIELD", ..] => { index: "", write: on }
					["DELETE", "FROM", _, ..] | ["INSERT", "INTO", _, ..] => { index: "", write: name_at(2) }
					["INSERT", "RELATION", "INTO", _, ..] | ["INSERT", "IGNORE", "INTO", _, ..] => { index: "", write: name_at(3) }
					["UPDATE", _, ..] | ["UPSERT", _, ..] | ["CREATE", _, ..] | ["DELETE", _, ..] => { index: "", write: name_at(1) }
					_ => { index: "", write: "" }
				}
			},
		)
		writes = facts.map(|f| f.write).keep_if(|w| w != "")
		facts.map(|f| f.index).keep_if(|i| i != "" and writes.contains(i)).first().map_err(|_| NotFound)
	}

	# ------------------------------------------------------------ runner

	## What the runner does, from the history and the compatibility level
	## of the database, which must be 4 (else `Level`): each file
	## that is not applied runs, a partly applied one goes on from its
	## next section, and a squashed file whose replaced files the
	## database applied is recorded only. `ahead` names the records of the
	## history that no file of the list has or replaces: a newer app
	## applied them.
	decide : List(Migrate.Row), List(Migrate.File), U64 -> Try({ actions : List(Migrate.Action), ahead : List(Str) }, Ql.Error)
	decide = |history, files, level| {
		fail = |name, problem| Err(Migration({ name, problem }))
		if level < 4 {
			return fail("", Level({ found: level }))
		}
		names = files.map(|f| f.name)
		match names.find_first(|n| names.keep_if(|m| m == n).len() > 1) {
			Ok(n) => return fail(n, Text("two files of the list have this name"))
			Err(_) => {}
		}
		known = names.concat(files.join_map(|f| f.replaces))
		ahead = history.keep_if(|h| !known.contains(h.name)).map(|h| h.name)
		row = |n| history.find_first(|h| h.name == n)
		applied = history.map(|h| h.name)
		complete = history.keep_if(|h| h.done >= h.sections).map(|h| h.name)
		var $actions = []
		for (f, at) in files.map_with_index(|f, at| (f, at)) {
			match row(f.name) {
				Ok(h) => {
					if h.checksum != f.checksum {
						return fail(f.name, Changed)
					}
					if h.done < h.sections {
						$actions = $actions.append(Run({ name: f.name, from: h.done + 1 }))
					}
				}
				Err(_) =>
					if f.replaces.any(|r| applied.contains(r)) {
						if !f.replaces.all(|r| complete.contains(r)) {
							return fail(f.name, Text("the database applied only a part of the files that this file replaces"))
						}
						$actions = $actions.append(Adopt(f.name))
					} else {
						later = files.drop_first(at + 1).any(|g| applied.contains(g.name) or g.replaces.any(|r| applied.contains(r)))
						if later {
							return fail(f.name, OutOfOrder)
						}
						$actions = $actions.append(Run({ name: f.name, from: 1 }))
					}
			}
		}
		Ok({ actions: $actions, ahead })
	}

	## The record of a file in the history.
	record : Str -> Str
	record = |name| "_reify_migration:⟨${name}⟩"

	## The request of section `k` (from 1) of a file: one transaction that
	## first marks the section in the history, then runs it. Section 1
	## creates the record, so a second runner fails on it; a later
	## section first checks that the record is at the section before.
	request : Migrate.File, U64 -> Str
	request = |f, k| {
		count = f.sections.len()
		last = k == count
		mark = if k == 1 {
			applied = if (last) ", applied_at: time::now()" else ""
			"CREATE ${Migrate.record(f.name)} CONTENT { checksum: '${f.checksum}', target: 'V4', sections: ${count.to_str()}, done: 1, kind: 'run'${applied} } RETURN NONE;"
		} else {
			applied = if (last) ", applied_at = time::now()" else ""
			"IF (SELECT VALUE done FROM ONLY ${Migrate.record(f.name)}) != ${(k - 1).to_str()} { THROW 'reify: another runner applied section ${k.to_str()} of ${f.name}' };\nUPDATE ${Migrate.record(f.name)} SET done = ${k.to_str()}${applied} RETURN NONE;"
		}
		# The `;` ends a last statement that has none.
		"BEGIN;\n${mark}\n${f.sections.get(k - 1) ?? ""}\n;\nCOMMIT;"
	}

	## The record of a squashed file whose replaced files the database applied.
	adopt : Migrate.File -> Str
	adopt = |f| {
		count = f.sections.len().to_str()
		"CREATE ${Migrate.record(f.name)} CONTENT { checksum: '${f.checksum}', target: 'V4', sections: ${count}, done: ${count}, kind: 'squash', applied_at: time::now() } RETURN NONE;"
	}

	## The history table, the level of the server and the history, in one
	## request. Each `DEFINE` is `IF NOT EXISTS`, so it costs nothing after
	## the first run. The last two results are the level and the rows. A
	## history of 0.0.3 or before keeps its `target` type, `'V3' | 'V4'`,
	## which takes the `'V4'` that the runner writes.
	bootstrap : Str
	bootstrap =
		\\DEFINE TABLE IF NOT EXISTS _reify_migration SCHEMAFULL PERMISSIONS NONE;
		\\DEFINE FIELD IF NOT EXISTS checksum ON _reify_migration TYPE string;
		\\DEFINE FIELD IF NOT EXISTS target ON _reify_migration TYPE 'V4';
		\\DEFINE FIELD IF NOT EXISTS sections ON _reify_migration TYPE int;
		\\DEFINE FIELD IF NOT EXISTS done ON _reify_migration TYPE int;
		\\DEFINE FIELD IF NOT EXISTS kind ON _reify_migration TYPE 'run' | 'squash';
		\\DEFINE FIELD IF NOT EXISTS applied_at ON _reify_migration TYPE option<datetime>;
		\\RETURN <string> ((INFO FOR DB).compatibility ?? 'none');
		\\SELECT record::id(id) AS name, checksum, sections, done FROM _reify_migration;

	## The compatibility level that `bootstrap` reads. SurrealDB 3 has no
	## level: `none`, and the error says that it is not SurrealDB 4.
	level_of : Str -> Try(U64, Ql.Error)
	level_of = |level| match U64.from_str(level) {
		Ok(n) => Ok(n)
		Err(_) => Err(Wire("INFO FOR DB has no compatibility level (`${level}`): the server is not SurrealDB 4"))
	}
}
