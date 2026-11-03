import cbor.Cbor

# The ops of a `LIVE SELECT DIFF` patch: the path of an op, the text patch
# of a `change` op, and each op applied to a stored row as a `Cbor.Value`.
#
# A DIFF notice is a list of ops over the stored row. A `change` op edits a
# string in place with a patch in the diff-match-patch text format, not a
# JSON Patch value (verified on SurrealDB 3.3.4):
#
# `{ op: 'change', path: '/s', value: '@@ -3,12 +3,12 @@\n ive \n-cafe\n+100%25\n  x t\n' }`
Diff :: {}.{

	## A JSON Pointer, split on `/`: `/meta/y/z` is `["meta", "y", "z"]`,
	## and `""` is the whole row. SurrealDB does not escape a `/` or a `~`
	## in a field name (verified), so a part is the text between two `/`.
	Pointer : List(Str)

	## The parts of a pointer. A pointer other than `""` starts with `/`.
	pointer : Str -> Try(Pointer, [BadPointer(Str)])
	pointer = |text|
		if text.is_empty() {
			Ok([])
		} else if text.starts_with("/") {
			Ok(text.drop_prefix("/").split_on("/"))
		} else {
			Err(BadPointer(text))
		}

	## One op of a patch, in the order of the patch. `Change` edits a
	## string in place with a text patch.
	Op : [Add(Pointer, Cbor.Value), Remove(Pointer), Replace(Pointer, Cbor.Value), Change(Pointer, TextPatch)]

	## An op as the server sends it: `{ op, path, value }`. A `value` of
	## `NULL` is no key in the map, and is `Cbor.Value.Null` here.
	op_of : { op : Str, path : Str, value : Try(Cbor.Value, [Missing]) } -> Try(Op, [BadOp(Str)])
	op_of = |raw| {
		path = Diff.pointer(raw.path).map_err(|_| BadOp("the path `${raw.path}`"))?
		value = raw.value ?? Cbor.Value.Null
		match (raw.op, value) {
			("add", _) => Ok(Add(path, value))
			("remove", _) => Ok(Remove(path))
			("replace", _) => Ok(Replace(path, value))
			("change", Text(text)) => Ok(Change(path, TextPatch.parse(text).map_err(|_| BadOp("the text patch of `${raw.path}`"))?))
			(other, _) => Err(BadOp("the op `${other}`"))
		}
	}

	## The pointer of an op.
	path_of : Op -> Pointer
	path_of = |op| match op {
		Add(path, _) | Remove(path) | Replace(path, _) | Change(path, _) => path
	}

	## The value after the op. A part of a pointer is a key of a map, or an
	## index of an array; `-` is the end of an array for `Add`. `Add` puts
	## a value in an array before the index, and in a map sets the key.
	## `BadPath` is a pointer that the value does not have, and `Mismatch`
	## a text patch that does not fit the string.
	apply : Cbor.Value, Op -> Try(Cbor.Value, [BadPath(Pointer), Mismatch(U64)])
	apply = |value, op| match op {
		Add(path, v) => Diff.edit(value, path, path, Insert(v))
		Remove(path) => Diff.edit(value, path, path, Drop)
		Replace(path, v) => Diff.edit(value, path, path, Put(v))
		Change(path, patch) => Diff.edit(value, path, path, Patched(patch))
	}

	## What an op does at the end of its pointer.
	Edit : [Insert(Cbor.Value), Put(Cbor.Value), Drop, Patched(TextPatch)]

	## The value with `edit` done at `rest`, the part of `path` that is left.
	edit : Cbor.Value, Pointer, Pointer, Edit -> Try(Cbor.Value, [BadPath(Pointer), Mismatch(U64)])
	edit = |value, rest, path, what| match (rest, what) {
		([], Insert(v)) | ([], Put(v)) => Ok(v)
		([], Patched(patch)) =>
			match value {
				Text(text) => patch.apply(text).map_ok(|t| Cbor.Value.Text(t))
				_ => Err(BadPath(path))
			}
		([], Drop) => Err(BadPath(path))
		([key], Insert(_)) | ([key], Put(_)) | ([key], Drop) =>
			match value {
				Map(entries) => Ok(Cbor.Value.Map(Diff.set_key(entries, key, what)))
				Array(items) => Diff.at_index(items, key, path, what).map_ok(|done| Cbor.Value.Array(done))
				_ => Err(BadPath(path))
			}
		([key, .. as deeper], _) =>
			match value {
				Map(entries) =>
					match entries.find_first(|(k, _)| k == Cbor.Value.Text(key)) {
						Ok((_, child)) => {
							changed = Diff.edit(child, deeper, path, what)?
							Ok(Cbor.Value.Map(Diff.set_key(entries, key, Put(changed))))
						}
						Err(_) => Err(BadPath(path))
					}
				Array(items) =>
					match Diff.index_of(key, items.len()) {
						Ok(i) =>
							match items.get(i) {
								Ok(child) => {
									changed = Diff.edit(child, deeper, path, what)?
									Ok(Cbor.Value.Array(Diff.replace_at(items, i, changed)))
								}
								Err(_) => Err(BadPath(path))
							}
						Err(_) => Err(BadPath(path))
					}
				_ => Err(BadPath(path))
			}
	}

	## The entries of a map with `key` set (`Insert`, `Put`) or removed
	## (`Drop`). A new key goes at the end.
	set_key : List((Cbor.Value, Cbor.Value)), Str, Edit -> List((Cbor.Value, Cbor.Value))
	set_key = |entries, key, what| {
		name = Cbor.Value.Text(key)
		kept = entries.drop_if(|(k, _)| k == name)
		match what {
			Insert(v) | Put(v) =>
				if kept.len() == entries.len() {
					entries.append((name, v))
				} else {
					entries.map(|(k, old)| if (k == name) (k, v) else (k, old))
				}
			Drop | Patched(_) => kept
		}
	}

	## The items of an array with the edit at the index `key`.
	at_index : List(Cbor.Value), Str, Pointer, Edit -> Try(List(Cbor.Value), [BadPath(Pointer), Mismatch(U64)])
	at_index = |items, key, path, what| match what {
		Insert(v) =>
			if key == "-" {
				Ok(items.append(v))
			} else {
				i = Diff.index_of(key, items.len() + 1).map_err(|_| BadPath(path))?
				Ok(items.take_first(i).append(v).concat(items.drop_first(i)))
			}
		Put(v) => {
			i = Diff.index_of(key, items.len()).map_err(|_| BadPath(path))?
			Ok(Diff.replace_at(items, i, v))
		}
		Drop => {
			i = Diff.index_of(key, items.len()).map_err(|_| BadPath(path))?
			Ok(items.take_first(i).concat(items.drop_first(i + 1)))
		}
		Patched(_) => Err(BadPath(path))
	}

	## The items with the one at `i` replaced.
	replace_at : List(Cbor.Value), U64, Cbor.Value -> List(Cbor.Value)
	replace_at = |items, i, v| items.take_first(i).append(v).concat(items.drop_first(i + 1))

	## An index below `size`, written in ASCII digits.
	index_of : Str, U64 -> Try(U64, [BadIndex])
	index_of = |key, size| match Diff.digits(key) {
		Ok(i) if i < size => Ok(i)
		_ => Err(BadIndex)
	}

	## One part of a hunk: text that both versions have, or that only the
	## new or only the old one has.
	Part : [Keep(Str), Insert(Str), Delete(Str)]

	## One hunk of a text patch. `at` is where it starts in the text after
	## the hunks before it, in Unicode scalar values from 0. `before` and
	## `after` are the lengths of the old and the new text it covers.
	Hunk : { at : U64, before : U64, after : U64, parts : List(Part) }

	## A text patch: the hunks, in order.
	TextPatch := List(Hunk).{

		## The hunks of a patch in the diff-match-patch text format: a header
		## `@@ -a,b +c,d @@` per hunk, then one line per part, which starts
		## with ` ` (keep), `-` (delete) or `+` (insert). A position counts
		## Unicode scalar values from 1, and a length of 0 counts from 0. A
		## length of 1 is left out of the header. The text of a part is UTF-8
		## with `%XX` escapes (`%0A` is a new line, `%25` is `%`).
		parse : Str -> Try(TextPatch, [BadPatch(Str)])
		parse = |text| {
			lines = text.split_on("\n")
			hunks = lines.fold_try([], |acc, line| Diff.read_line(acc, line))?
			hunks.map_try(Diff.checked).map_ok(|checked| TextPatch.(checked))
		}

		## The text with each hunk applied, in order. The text must hold the
		## kept and the deleted parts of each hunk where the hunk starts:
		## `Mismatch(at)` gives that position when it does not.
		apply : TextPatch, Str -> Try(Str, [Mismatch(U64)])
		apply = |TextPatch.(hunks), text| {
			result = hunks.fold_try(Diff.scalars(text), Diff.apply_hunk)?
			match Str.from_utf8(result.join()) {
				Ok(s) => Ok(s)
				Err(_) => crash "whole scalars of valid UTF-8 are valid UTF-8"
			}
		}

		hunks : TextPatch -> List(Hunk)
		hunks = |TextPatch.(all)| all
	}

	## One line of a patch, added to the hunks read so far.
	read_line : List(Hunk), Str -> Try(List(Hunk), [BadPatch(Str)])
	read_line = |hunks, line| match line.to_utf8() {
		[] => Ok(hunks)
		[64, 64, 32, ..] => Ok(hunks.append(Diff.header(line)?))
		[sign, .. as rest] => {
			part_text = Diff.unescape(rest).map_err(|_| BadPatch(line))?
			part = match sign {
				32 => Keep(part_text)
				45 => Delete(part_text)
				43 => Insert(part_text)
				_ => return Err(BadPatch(line))
			}
			match hunks.last() {
				Ok(last) => Ok(hunks.drop_last(1).append({ ..last, parts: last.parts.append(part) }))
				Err(_) => Err(BadPatch(line))
			}
		}
	}

	## The header `@@ -a,b +c,d @@` of a hunk, with no parts yet.
	header : Str -> Try(Hunk, [BadPatch(Str)])
	header = |line| match line.split_on(" ") {
		["@@", old, new, "@@"] if old.starts_with("-") and new.starts_with("+") => {
			(_, before) = Diff.range(old.drop_prefix("-")).map_err(|_| BadPatch(line))?
			(at, after) = Diff.range(new.drop_prefix("+")).map_err(|_| BadPatch(line))?
			Ok({ at, before, after, parts: [] })
		}
		_ => Err(BadPatch(line))
	}

	## `a,b` as a start from 0 and a length: `a` alone has length 1, and a
	## length of 0 has its start from 0 already.
	range : Str -> Try((U64, U64), [BadRange])
	range = |text| match text.split_on(",") {
		[start] => {
			s = Diff.digits(start)?
			if (s == 0) Err(BadRange) else Ok((s - 1, 1))
		}
		[start, length] => {
			s = Diff.digits(start)?
			n = Diff.digits(length)?
			if n == 0 {
				Ok((s, 0))
			} else if s == 0 {
				Err(BadRange)
			} else {
				Ok((s - 1, n))
			}
		}
		_ => Err(BadRange)
	}

	## A number of ASCII digits only.
	digits : Str -> Try(U64, [BadRange])
	digits = |text| match text.to_utf8() {
		[] => Err(BadRange)
		bytes => bytes.fold_try(0, |acc, b| if (b >= 48 and b <= 57) Ok(acc * 10 + (b - 48).to_u64()) else Err(BadRange))
	}

	## A hunk whose parts have the lengths of its header.
	checked : Hunk -> Try(Hunk, [BadPatch(Str)])
	checked = |hunk| {
		old = Diff.old_text(hunk.parts).len()
		new = Diff.new_text(hunk.parts).len()
		if old == hunk.before and new == hunk.after {
			Ok(hunk)
		} else {
			Err(BadPatch("a hunk at ${(hunk.at + 1).to_str()} has ${old.to_str()} old and ${new.to_str()} new values, and its header says ${hunk.before.to_str()} and ${hunk.after.to_str()}"))
		}
	}

	## The scalars a hunk covers in the old text: what it keeps and deletes.
	old_text : List(Part) -> List(List(U8))
	old_text = |parts| parts.join_map(
		|p| match p {
			Keep(t) | Delete(t) => Diff.scalars(t)
			Insert(_) => []
		},
	)

	## The scalars a hunk gives in the new text: what it keeps and inserts.
	new_text : List(Part) -> List(List(U8))
	new_text = |parts| parts.join_map(
		|p| match p {
			Keep(t) | Insert(t) => Diff.scalars(t)
			Delete(_) => []
		},
	)

	## The UTF-8 bytes of each Unicode scalar value of a text: a scalar
	## starts at each byte that is not `10xxxxxx`.
	scalars : Str -> List(List(U8))
	scalars = |text| text.to_utf8().fold(
		[],
		|acc, b|
			if b >= 128 and b < 192 {
				match acc.last() {
					Ok(last) => acc.drop_last(1).append(last.append(b))
					Err(_) => crash "valid UTF-8 starts with a lead byte"
				}
			} else {
				acc.append([b])
			},
	)

	## One hunk applied to the scalars of the text.
	apply_hunk : List(List(U8)), Hunk -> Try(List(List(U8)), [Mismatch(U64)])
	apply_hunk = |text, hunk| {
		old = Diff.old_text(hunk.parts)
		new = Diff.new_text(hunk.parts)
		if hunk.at + old.len() <= text.len() and text.sublist({ start: hunk.at, len: old.len() }) == old {
			Ok(text.take_first(hunk.at).concat(new).concat(text.drop_first(hunk.at + old.len())))
		} else {
			Err(Mismatch(hunk.at))
		}
	}

	## The text of a part: `%XX` is the byte `XX`, and the bytes are UTF-8.
	unescape : List(U8) -> Try(Str, [BadEscape])
	unescape = |bytes| {
		decoded = Diff.unescape_bytes(bytes, [])?
		Str.from_utf8(decoded).map_err(|_| BadEscape)
	}

	unescape_bytes : List(U8), List(U8) -> Try(List(U8), [BadEscape])
	unescape_bytes = |bytes, done| match bytes {
		[] => Ok(done)
		[37, high, low, .. as rest] => Diff.unescape_bytes(rest, done.append(Diff.hex(high)? * 16 + Diff.hex(low)?))
		[37, ..] => Err(BadEscape)
		[b, .. as rest] => Diff.unescape_bytes(rest, done.append(b))
	}

	hex : U8 -> Try(U8, [BadEscape])
	hex = |b|
		if b >= 48 and b <= 57 {
			Ok(b - 48)
		} else if b >= 65 and b <= 70 {
			Ok(b - 55)
		} else if b >= 97 and b <= 102 {
			Ok(b - 87)
		} else {
			Err(BadEscape)
		}
}
