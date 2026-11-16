app [] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.5.1/38XQEgbABvGrHkqPVDVMsabgXcBHouMQde1vz4cLchxT.tar.zst",
	internal: "../src/internal.roc",
}

# The public names of the types that are private top-level types behind a
# public alias (the 11-14 compiler warns when a member of a nested type has
# the name of a member of the module): Diff.TextPatch, Surreal.Access,
# Surreal.Query and Surreal.Grouped. Surreal.Auth and Surreal.Patch are in
# TranslateTest and DiffTest. Each
# public name works in an annotation, and each method works as a qualified
# call and as a method call.

import internal.Diff
import internal.Surreal

Row : { id : Str, n : U64 }

expect {
	parsed : Try(Diff.TextPatch, _)
	parsed = Diff.TextPatch.parse("@@ -0,0 +1,2 @@\n+ab\n")
	match parsed {
		Ok(p) => p.hunks() == Diff.TextPatch.hunks(p) and p.apply("") == Ok("ab") and Diff.TextPatch.apply(p, "") == Ok("ab")
		Err(_) => Bool.False
	}
}

expect {
	a : Surreal.Access({ user : Str }, { user : Str })
	a = Surreal.access("users")
	db = { ns: "n", db: "d" }
	Str.inspect(a.sign_in(db, { user: "x" })) == Str.inspect(Surreal.Access.sign_in(a, db, { user: "x" }))
}

expect {
	t : Surreal.Table(Row)
	t = Surreal.table("rows")
	q : Surreal.Query({}, Row)
	q = Surreal.from(t)
	g : Surreal.Grouped({}, Row, U64)
	g = q.group_by(|r| r.n)
	h : Surreal.Grouped({}, Row, U64)
	h = Surreal.Query.group_by(q, |r| r.n)
	Str.inspect(g.aggregate(|k, rows| { n: k, c: rows.len() })) == Str.inspect(Surreal.Grouped.aggregate(h, |k, rows| { n: k, c: rows.len() }))
}
