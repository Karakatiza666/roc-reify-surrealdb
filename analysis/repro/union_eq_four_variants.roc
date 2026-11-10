app [] {}

# Minimal repro, reify compiler 901d5f4824 (passes on e3d46ce14f). `roc test union_eq_four_variants.roc`:
#   panic: code reifier invariant: normalization broke an invariant of the normal form
# A described lambda compares two tag union values with the derived `==`,
# and neither value is a constant. The union has 4 or more variants. With
# 3 variants, or with one side a literal (`o.pay == A`), it passes. A
# captured run-time value (`|p| .. |o| o.pay == p`) gives the same crash,
# so after gap 1 a query that compares a field with a captured union stops
# the build (see analysis/gap1-capture-modes.md).
Pay : [A, B, C, D]

Order : { pay : Pay, other : Pay }

T :: {}.{
	rows : Code(Order -> Bool) -> U64
	rows = |code| code.graph().rows().len()
}

expect T.rows(|o| o.pay == o.other) > 0
