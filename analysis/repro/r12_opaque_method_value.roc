app [] {}

# Fixed on reify 0aedb1ae00: `roc test` passes (e848b71fad, 68a3fc8dfd).
# Minimal repro, reify compiler e3d46ce14f. `roc test r12_opaque_method_value.roc`:
#   cannot compute this value (lines 34 and 35)
# A fixed value at a `Code(a)` place that a method of an opaque type (`::`)
# computes cannot be made a literal, also when the value's own type is not
# opaque. The same method on a transparent nominal (`:=`) works (lines 36 and 37).
# The ORM case: `vets.at(vets.id("tia"))`, where `Table` is opaque and
# `at` takes `Code(Id(row))` (R12). Every top-level keyed query hits it.
MyId := { table : Str, key : Str }

Opq :: { name : Str }.{
	id : Opq, Str -> MyId
	id = |Opq.(t), key| MyId.({ table: t.name, key })
}

Tr := { name : Str }.{
	id : Tr, Str -> MyId
	id = |Tr.(t), key| MyId.({ table: t.name, key })
}

Stage :: {}.{
	key : Code(MyId) -> Code.Bound(Str)
	key = |code| Code.bound(code, Str.inspect(code.graph().root_row().body))
}

opq : Opq
opq = Opq.({ name: "vet" })
tr : Tr
tr = Tr.({ name: "vet" })
ruth_o = opq.id("ruth")
ruth_t = tr.id("ruth")

a = Stage.key(ruth_o)
fa = |_x| Stage.key(opq.id("ruth"))
b = Stage.key(ruth_t)
fb = |_x| Stage.key(tr.id("ruth"))

expect a.inputs() == [] and fa(0).inputs() == [] and b.inputs() == [] and fb(0).inputs() == []
