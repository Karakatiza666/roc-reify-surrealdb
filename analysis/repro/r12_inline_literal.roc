app [] {}

# Fixed on reify 0aedb1ae00: `roc test` passes (e848b71fad, 68a3fc8dfd).
# Minimal repro, reify compiler e3d46ce14f. `roc test r12_inline_literal.roc`:
#   cannot bind this value: "This value exists only when the program runs" (lines 20 and 21)
# A text or a record literal written at a `Code(a)` place in a top-level
# definition is taken as a run-time value. docs/langref/reifying.md
# "Values at a Code Place" says that such a value is described as a literal.
# A number literal works (line 19). The same literal through a top-level name
# works (line 23), and so does the literal inside a function (line 24).
Stage :: {}.{
	num : Code(U64) -> Code.Bound(Str)
	num = |code| Code.bound(code, Str.inspect(code.graph().root_row().body))
	text : Code(Str) -> Code.Bound(Str)
	text = |code| Code.bound(code, Str.inspect(code.graph().root_row().body))
	rec : Code({ table : Str, key : Str }) -> Code.Bound(Str)
	rec = |code| Code.bound(code, Str.inspect(code.graph().root_row().body))
}

n1 = Stage.num(10)
t1 = Stage.text("ruth")
r1 = Stage.rec({ table: "vet", key: "ruth" })
ruth = "ruth"
t2 = Stage.text(ruth)
t3 = |_x| Stage.text("ruth")

expect n1.inputs() == [] and t1.inputs() == [] and r1.inputs() == [] and t2.inputs() == [] and t3(0).inputs() == []
