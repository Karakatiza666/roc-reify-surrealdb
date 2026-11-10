app [] {}

# Minimal repro, reify compiler 0aedb1ae00. `roc test nominal_record_shorthand.roc`:
#   "invalid nominal type" at `Opq.({ name })` (line 14): the value has type
#   Str, so `{ name }` is read as a block that gives `name`, not as a record
#   with the field shorthand. The full form `Opq.({ name: name })` (line 12)
#   works. It may be the grammar (block or record), not a reifier bug.
Opq :: { name : Str }.{
	name_of : Opq -> Str
	name_of = |Opq.(o)| o.name
	full : Str -> Opq
	full = |name| Opq.({ name: name })
	short : Str -> Opq
	short = |name| Opq.({ name })
}

expect Opq.full("a").name_of() == "a"
expect Opq.short("a").name_of() == "a"
