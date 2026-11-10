app [] {}

# Fixed on reify 0aedb1ae00: `roc test` passes (e848b71fad, 68a3fc8dfd).
# Minimal repro, reify compiler e3d46ce14f. `roc test r12_generic_value_crash.roc`:
#   panic: postcheck invariant violated: instantiation unified a record with a non-record type
#   (post-check, monotype, src/postcheck/monotype/solve.zig:7486)
# A translator takes `Code(a)` with a free `a`, and a call passes a value
# (not a function) that the program computes at run time. With a concrete
# type (`Code(U64)`) it passes.
Stage :: {}.{
	show : Code(a) -> Code.Bound(Str)
	show = |code| Code.bound(code, "x")
}

twice = |k| Stage.show(k * 2.U64)

expect twice(1).inputs() == [Int(2)]
