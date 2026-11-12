app [] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.4.0/EnfRKFT7uPHmd3zT5PcwAiBWUtGmBXapJqFK5166U33J.tar.zst",
	internal: "../src/internal.roc",
}

import internal.Diff
import internal.Surreal
import cbor.Cbor
import "fixtures/vital_patches/00.cbor" as patches_reply : List(U8)
import "fixtures/vital_patches/01.cbor" as patch_create : List(U8)
import "fixtures/vital_patches/02.cbor" as patch_update : List(U8)
import "fixtures/vital_patches/03.cbor" as patch_delete : List(U8)

# Tests of `LIVE SELECT DIFF`: the text patches, the paths, each op applied
# to a stored row, the view of the stored rows and the typed read of a
# field. Each text patch below is one that SurrealDB 3.3.4 sent for an
# update of the text `naive cafe x the end`, and the ops of the last part
# are the patches of the live block `vital_patches` of `monitoring.roc`
# (`fixtures/vital_patches`). Nothing outside this file imports it.
DiffTest :: {}

base : Str
base = "naive cafe x the end"

## The text after the patch, or the error.
patched : Str, Str -> Try(Str, [BadPatch(Str), Mismatch(U64)])
patched = |patch, text| {
	parsed = Diff.TextPatch.parse(patch)?
	parsed.apply(text).map_err(|Mismatch(at)| Mismatch(at))
}

# ------------------------------------------------------------ text patches

# ASCII: one hunk with a keep, a delete, an insert and a keep.
expect patched("@@ -3,18 +3,18 @@\n ive \n-cafe x the\n+CAFE x THE\n  end\n", base) == Ok("naive CAFE x THE end")
# Positions count Unicode scalar values, not bytes: `ï` and `é` are two bytes, the emoji four.
expect patched("@@ -1,14 +1,14 @@\n na\n-i\n+%C3%AF\n ve \n-cafe\n+CAFE\n  x t\n", base) == Ok("naïve CAFE x the end")
expect patched("@@ -6,15 +6,15 @@\n  caf\n-e\n+%C3%A9\n  x th\n-e\n+%C3%A9\n  end\n", base) == Ok("naive café x thé end")
expect patched("@@ -8,9 +8,9 @@\n afe \n-x\n+%F0%9F%90%95\n  the\n", base) == Ok("naive cafe 🐕 the end")
# A hunk after a non-ASCII value starts at its scalar position, not at its byte position.
expect patched("@@ -6,15 +6,15 @@\n  caf\n-e\n+%C3%A9\n  x th\n-e\n+%C3%A9\n  end\n", "naïve cafe x the end") == Ok("naïve café x thé end")
# A new line and a `%` are escaped.
expect patched("@@ -5,16 +5,16 @@\n e cafe x\n- \n+%0A\n the end\n", base) == Ok("naive cafe x\nthe end")
expect patched("@@ -3,12 +3,12 @@\n ive \n-cafe\n+100%25\n  x t\n", base) == Ok("naive 100% x the end")
# Two hunks: the second starts where it is in the text after the first.
expect patched("@@ -1,8 +1,10 @@\n+XX\n naive ca\n@@ -15,8 +15,11 @@\n  the end\n+ YY\n", base) == Ok("XXnaive cafe x the end YY")
expect patched("@@ -13,8 +13,59 @@\n  the end\n+, then more text to make a long tail here and there\n", base) == Ok("naive cafe x the end, then more text to make a long tail here and there")
# The base must hold what the patch keeps and deletes, where it says.
expect patched("@@ -3,18 +3,18 @@\n ive \n-cafe x the\n+CAFE x THE\n  end\n", "naive CAFE x THE end") == Err(Mismatch(2))
expect patched("@@ -3,18 +3,18 @@\n ive \n-cafe x the\n+CAFE x THE\n  end\n", "naive") == Err(Mismatch(2))
expect patched("@@ -1,14 +1,14 @@\n na\n-i\n+%C3%AF\n ve \n-cafe\n+CAFE\n  x t\n", "naïve cafe x the end") == Err(Mismatch(0))
# The header: a length of 1 is left out, and a length of 0 counts from 0.
expect Diff.TextPatch.parse("@@ -2 +2 @@\n-a\n+b\n").map_ok(|p| p.hunks()) == Ok([{ at: 1, before: 1, after: 1, parts: [Delete("a"), Insert("b")] }])
expect Diff.TextPatch.parse("@@ -0,0 +1,2 @@\n+ab\n").map_ok(|p| p.hunks()) == Ok([{ at: 0, before: 0, after: 2, parts: [Insert("ab")] }])
expect patched("@@ -0,0 +1,2 @@\n+ab\n", "") == Ok("ab")
# A patch that is not well formed is refused, never applied in part.
expect Diff.TextPatch.parse("@@ -3,18 +3,17 @@\n ive \n-cafe x the\n+CAFE x THE\n  end\n").map_ok(|p| p.hunks()) == Err(BadPatch("a hunk at 3 has 18 old and 18 new values, and its header says 18 and 17"))
expect Diff.TextPatch.parse(" ive \n").map_ok(|p| p.hunks()) == Err(BadPatch(" ive "))
expect Diff.TextPatch.parse("@@ -3,18 @@\n").map_ok(|p| p.hunks()) == Err(BadPatch("@@ -3,18 @@"))
expect Diff.TextPatch.parse("@@ -0 +1 @@\n").map_ok(|p| p.hunks()) == Err(BadPatch("@@ -0 +1 @@"))
expect Diff.TextPatch.parse("@@ -1 +1 @@\n*a\n").map_ok(|p| p.hunks()) == Err(BadPatch("*a"))
expect Diff.TextPatch.parse("@@ -1 +1 @@\n %4\n").map_ok(|p| p.hunks()) == Err(BadPatch(" %4"))
expect Diff.TextPatch.parse("@@ -1 +1 @@\n %FF\n").map_ok(|p| p.hunks()) == Err(BadPatch(" %FF"))

# ------------------------------------------------------------ pointers

expect Diff.pointer("") == Ok([])
expect Diff.pointer("/temp") == Ok(["temp"])
expect Diff.pointer("/meta/y/z") == Ok(["meta", "y", "z"])
expect Diff.pointer("/arr/0/a") == Ok(["arr", "0", "a"])
# RFC 6901 escapes: `~1` is `/` and `~0` is `~` in a part. SurrealDB 4.0.1
# sent `/m/a~1b`, `/m/c~0d` and `/x~1y` for the keys `a/b` and `c~d` of
# `m`, and `x/y`. `~01` is `~1`: `~1` is read first.
expect Diff.pointer("/m/a~1b") == Ok(["m", "a/b"])
expect Diff.pointer("/m/c~0d") == Ok(["m", "c~d"])
expect Diff.pointer("/x~1y") == Ok(["x/y"])
expect Diff.pointer("/~01") == Ok(["~1"])
expect Diff.pointer("temp") == Err(BadPointer("temp"))

# ------------------------------------------------------------ ops on a row

text : Str -> Cbor.Value
text = |t| Cbor.Value.Text(t)

int : I128 -> Cbor.Value
int = |n| Cbor.Value.Int(n)

## `{ s: 'naive cafe x the end', meta: { y: { z: 1 } }, arr: [{ a: 1 }, 2], tags: ['a', 'b'] }`
row : Cbor.Value
row = Cbor.Value.Map([
	(text("s"), text(base)),
	(text("meta"), Cbor.Value.Map([(text("y"), Cbor.Value.Map([(text("z"), int(1))]))])),
	(text("arr"), Cbor.Value.Array([Cbor.Value.Map([(text("a"), int(1))]), int(2)])),
	(text("tags"), Cbor.Value.Array([text("a"), text("b")])),
])

## The row after the ops that the server sends as `{ op, path, value }`.
ops_on : Cbor.Value, List({ op : Str, path : Str, value : Try(Cbor.Value, [Missing]) }) -> Try(Cbor.Value, [BadOp(Str), BadPath(List(Str)), Mismatch(U64)])
ops_on = |start, raw| {
	ops = raw.map_try(Diff.op_of)?
	ops.fold_try(
		start,
		|value, op| Diff.apply(value, op).map_err(
			|e| match e {
				BadPath(p) => BadPath(p)
				Mismatch(at) => Mismatch(at)
			},
		),
	)
}

## The value at a path of maps and arrays, for a check.
at : Cbor.Value, List(Str) -> Cbor.Value
at = |value, path| match (path, value) {
	([], _) => value
	([key, .. as rest], Map(entries)) => at(entries.find_first(|(k, _)| k == text(key)).map_ok(|(_, v)| v) ?? Cbor.Value.Undefined, rest)
	([key, .. as rest], Array(items)) => at(items.get(U64.from_str(key) ?? 99) ?? Cbor.Value.Undefined, rest)
	_ => Cbor.Value.Undefined
}

# Replace a value, nested and in an array.
expect ops_on(row, [{ op: "replace", path: "/meta/y/z", value: Ok(int(2)) }]).map_ok(|v| at(v, ["meta", "y", "z"])) == Ok(int(2))
expect ops_on(row, [{ op: "replace", path: "/arr/0/a", value: Ok(int(5)) }]).map_ok(|v| at(v, ["arr", "0", "a"])) == Ok(int(5))
# Add a new field, and an item of an array before an index and at its end.
expect ops_on(row, [{ op: "add", path: "/new", value: Ok(Cbor.Value.Array([])) }]).map_ok(|v| at(v, ["new"])) == Ok(Cbor.Value.Array([]))
expect ops_on(row, [{ op: "add", path: "/tags/1", value: Ok(text("x")) }]).map_ok(|v| at(v, ["tags"])) == Ok(Cbor.Value.Array([text("a"), text("x"), text("b")]))
expect ops_on(row, [{ op: "add", path: "/tags/-", value: Ok(text("x")) }]).map_ok(|v| at(v, ["tags"])) == Ok(Cbor.Value.Array([text("a"), text("b"), text("x")]))
# Remove a field and an item. The ops apply in order: the index of the second is after the first.
expect ops_on(row, [{ op: "remove", path: "/meta", value: Err(Missing) }]).map_ok(|v| at(v, ["meta"])) == Ok(Cbor.Value.Undefined)
expect ops_on(row, [{ op: "remove", path: "/arr/0", value: Err(Missing) }, { op: "remove", path: "/arr/0", value: Err(Missing) }]).map_ok(|v| at(v, ["arr"])) == Ok(Cbor.Value.Array([]))
# A string edited in place, in a field and in an array.
expect ops_on(row, [{ op: "change", path: "/s", value: Ok(text("@@ -3,18 +3,18 @@\n ive \n-cafe x the\n+CAFE x THE\n  end\n")) }]).map_ok(|v| at(v, ["s"])) == Ok(text("naive CAFE x THE end"))
expect ops_on(row, [{ op: "change", path: "/tags/1", value: Ok(text("@@ -1 +1 @@\n-b\n+c\n")) }]).map_ok(|v| at(v, ["tags", "1"])) == Ok(text("c"))
# A pointer the row does not have, a text patch that does not fit, an unknown op.
expect ops_on(row, [{ op: "replace", path: "/none/x", value: Ok(int(1)) }]) == Err(BadPath(["none", "x"]))
expect ops_on(row, [{ op: "remove", path: "/arr/5", value: Err(Missing) }]) == Err(BadPath(["arr", "5"]))
expect ops_on(row, [{ op: "change", path: "/meta", value: Ok(text("@@ -1 +1 @@\n-b\n+c\n")) }]) == Err(BadPath(["meta"]))
expect ops_on(row, [{ op: "change", path: "/s", value: Ok(text("@@ -1 +1 @@\n-x\n+c\n")) }]) == Err(Mismatch(0))
expect ops_on(row, [{ op: "move", path: "/s", value: Err(Missing) }]) == Err(BadOp("the op `move`"))
# The whole row: a create replaces `""`, and a delete replaces it with `NULL`.
expect ops_on(Cbor.Value.Null, [{ op: "replace", path: "", value: Ok(row) }]) == Ok(row)
expect ops_on(row, [{ op: "replace", path: "", value: Err(Missing) }]) == Ok(Cbor.Value.Null)

# ------------------------------------------------------------ the patches of a watch

Kennel : { id : Str, label : Str }

Vital : { id : Surreal.TimeKey(Surreal.Id(Kennel)), pulse : I64, temp_c : Dec, fevered : Bool }

kennels : Surreal.Table(Kennel)
kennels = Surreal.table("kennel")

vitals : Surreal.Table(Vital)
vitals = Surreal.table("vital")

vital_patches : Surreal.DiffWatch(Vital)
vital_patches = match Surreal.from(vitals).live_diff({}) {
	Ok(w) => w
	Err(_) => crash "the watch of monitoring.roc translates"
}

lives : Surreal.Lives
lives = match vital_patches.start(patches_reply) {
	Ok(s) => s.live.lives()
	Err(_) => crash "the recorded reply reads"
}

## The patch of a message of the watch.
patch_of : List(U8) -> Surreal.Patch(Vital)
patch_of = |bytes| match vital_patches.patch(lives, bytes) {
	Ok(Mine(p)) => p
	_ => crash "a recorded patch reads"
}

## The reading that the block writes, as the database stores it.
hot : Vital
hot = match Surreal.datetime("2026-03-06T08:00:00Z") {
	Ok(time) => { id: Surreal.time_key(kennels.id("a"), time), pulse: 80, temp_c: 39.6, fevered: Bool.True }
	Err(_) => crash "a valid datetime"
}

cooled : Vital
cooled = { ..hot, temp_c: 38.2, fevered: Bool.False }

hot_ref : Surreal.Ref
hot_ref = match vitals.ref(hot) {
	Ok(r) => r
	Err(_) => crash "a time series key has a record id"
}

expect patch_of(patch_create).ref() == hot_ref
expect patch_of(patch_create).action() == Create
expect patch_of(patch_update).ops().map(Diff.path_of) == [["fevered"], ["temp_c"]]

## The view after the patches of these messages, from an empty one.
view_after : List(List(U8)) -> Try(Surreal.DiffView(Vital), [UnknownRef(Surreal.Ref), BadPath(List(Str)), Mismatch(U64)])
view_after = |messages| messages.fold_try(Surreal.DiffView.empty({}), |view, bytes| view.apply(patch_of(bytes)))

# The stored row after the create and after the update, read as `Vital`
# (its `id` a time series key), and no row after the delete.
## A reading as text: its record id and its fields. A `TimeKey` has no `==`.
facts : Vital -> Str
facts = |v| "${vitals.ref(v).map_ok(|r| r.to_str()) ?? "?"} ${v.pulse.to_str()} ${v.temp_c.to_str()} ${Str.inspect(v.fevered)}"

expect view_after([patch_create]).map_ok(|v| v.get(hot_ref).map_ok(facts)) == Ok(Ok(facts(hot)))
expect view_after([patch_create, patch_update]).map_ok(|v| v.get(hot_ref).map_ok(facts)) == Ok(Ok(facts(cooled)))
expect view_after([patch_create, patch_update]).map_ok(|v| v.rows().map_ok(|rows| rows.map(facts))) == Ok(Ok([facts(cooled)]))
expect view_after([patch_create, patch_update, patch_delete]).map_ok(|v| v.refs()) == Ok([])

# An update of a row that the view does not hold: the row entered the filter.
expect Surreal.DiffView.empty({}).apply(patch_of(patch_update)).map_ok(|v| v.refs()) == Err(UnknownRef(hot_ref))

# What each patch did to a field.
expect patch_of(patch_create).field(|v| v.temp_c) == Ok(Set(39.6))
expect patch_of(patch_update).field(|v| v.temp_c) == Ok(Set(38.2))
expect patch_of(patch_update).field(|v| v.pulse) == Ok(Untouched)
expect patch_of(patch_delete).field(|v| v.temp_c) == Ok(Unset)

# ------------------------------------------------------------ the replay of patches

kennel_patches : Surreal.DiffWatch(Kennel)
kennel_patches = match Surreal.from(kennels).live_diff({}) {
	Ok(w) => w
	Err(_) => crash "the watch translates"
}

kennel_lives : Surreal.Lives
kennel_lives = match kennel_patches.start(patches_reply) {
	Ok(s) => s.live.lives()
	Err(_) => crash "the recorded reply reads"
}

## The message of a notice on the watch of `patches_reply`, as the server
## sends it: the action, the record `kennel:⟨key⟩` and the ops.
notice : Str, Str, List({ op : Str, path : Str, value : Try(Cbor.Value, [Missing]) }) -> List(U8)
notice = |action, key, ops| {
	op_map = |o| {
		given = match o.value {
			Ok(v) => [(text("value"), v)]
			Err(_) => []
		}
		Cbor.Value.Map(List.concat([(text("op"), text(o.op)), (text("path"), text(o.path))], given))
	}
	uuid = Cbor.Value.Tag(37, Cbor.Value.Bytes([0x56, 0x24, 0x0b, 0xb5, 0xb2, 0x49, 0x42, 0xf8, 0x9a, 0x71, 0xab, 0xdf, 0xad, 0x08, 0x95, 0xaf]))
	record = Cbor.Value.Tag(8, Cbor.Value.Array([text("kennel"), text(key)]))
	Cbor.encode(Cbor.Value.Map([(text("result"), Cbor.Value.Map([(text("action"), text(action)), (text("id"), uuid), (text("record"), record), (text("result"), Cbor.Value.Array(ops.map(op_map)))]))]))
}

kennel_patch : Str, Str, List({ op : Str, path : Str, value : Try(Cbor.Value, [Missing]) }) -> Surreal.Patch(Kennel)
kennel_patch = |action, key, ops| match kennel_patches.patch(kennel_lives, notice(action, key, ops)) {
	Ok(Mine(p)) => p
	_ => crash "a built notice reads"
}

relabel : Surreal.Patch(Kennel)
relabel = kennel_patch("UPDATE", "q", [{ op: "replace", path: "/label", value: Ok(Cbor.Value.Text("Quay wing")) }])

reopened : Surreal.Patch(Kennel)
reopened = kennel_patch("UPDATE", "q", [{ op: "add", path: "/site", value: Ok(Cbor.Value.Text("oslo")) }, { op: "remove", path: "/note", value: Err(Missing) }])

created : Surreal.Patch(Kennel)
created = kennel_patch("CREATE", "q", [{ op: "replace", path: "", value: Ok(Cbor.Value.Map([(Cbor.Value.Text("label"), Cbor.Value.Text("Quay"))])) }])

deleted : Surreal.Patch(Kennel)
deleted = kennel_patch("DELETE", "q", [{ op: "replace", path: "", value: Err(Missing) }])

changed : Surreal.Patch(Kennel)
changed = kennel_patch("UPDATE", "q", [{ op: "change", path: "/label", value: Ok(Cbor.Value.Text("@@ -1 +1 @@\n-Q\n+q\n")) }])

quay : Surreal.Id(Kennel)
quay = kennels.id("q")

patch_script : Surreal.Id(Kennel), List(Surreal.Patch(Kennel)) -> Try(Str, Surreal.Error)
patch_script = |id, patches| kennels.patch_at(id, patches).statement().map_ok(|st| st.surql)

# The ops of the patches are one `PATCH`, in order, on the row of the key.
expect patch_script(quay, [relabel]) == Ok("UPDATE kennel:⟨q⟩ PATCH [{ op: 'replace', path: '/label', value: 'Quay wing' }] RETURN AFTER")
expect patch_script(quay, [relabel, reopened]) == Ok("UPDATE kennel:⟨q⟩ PATCH [{ op: 'replace', path: '/label', value: 'Quay wing' }, { op: 'add', path: '/site', value: 'oslo' }, { op: 'remove', path: '/note' }] RETURN AFTER")
expect patch_script(quay, []) == Ok("UPDATE kennel:⟨q⟩ PATCH [] RETURN AFTER")
# The patch of a create replaces the whole row (`""`).
expect patch_script(quay, [created]) == Ok("UPDATE kennel:⟨q⟩ PATCH [{ op: 'replace', path: '', value: { label: 'Quay' } }] RETURN AFTER")
# Refused when it is built: a patch of another row, of a delete, and a text diff.
expect patch_script(kennels.id("a"), [relabel]) == Err(Unsupported("a patch is of another row than `kennel:⟨a⟩`"))
expect patch_script(quay, [deleted]) == Err(Unsupported("a patch of a delete: delete the row with `delete_at`"))
expect patch_script(quay, [changed]) == Err(Unsupported("a `change` op is a text diff, and the ORM reads it and does not write it; replay the field with a `replace`"))
# The key of a time series is not a text key, so its patch is of no `Id`.
expect vitals.patch_at(Surreal.Unchecked.id("vital", "x"), [patch_of(patch_update)]).statement().map_ok(|st| st.surql) == Err(Unsupported("a patch is of another row than `vital:⟨x⟩`"))
