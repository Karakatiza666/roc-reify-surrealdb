app [] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.4.0/EnfRKFT7uPHmd3zT5PcwAiBWUtGmBXapJqFK5166U33J.tar.zst",
}

# Minimal repro, reify compiler c1e6af27a2. `roc test compiler_repro.roc`:
#   panic: checked artifact invariant violated: checked generated codec
#   structural call disagreed with its nested derivation types
# A record holds two different instances of a parameterized nominal type that
# derives `parser_for` (the library's `Surreal.Linked`). A constraint
# `row.Cbor.Readable(errs)` is solved for the record. With one instance, with the
# same instance twice, or with `Wrap({ a : Str })` and `Wrap({ b : Str })`, it passes.
import cbor.Cbor

Wrap(row) := { ..row }.{
	parser_for : _
}

Site : { id : Str, name : Str }
Carer : { id : Str, name : Str }
Row : { site : Wrap(Site), carer : Wrap(Carer) }

Holder(row) :: { name : Str }

rows : Holder(Row)
rows = Holder.({ name: "row" })

needs_readable : Holder(row) -> Bool where [row.Cbor.Readable(errs)]
needs_readable = |_| Bool.True

expect needs_readable(rows)
