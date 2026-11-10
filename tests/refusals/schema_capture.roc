# refused-at: 27
# message: reified function captures a value
app [] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.4.0/EnfRKFT7uPHmd3zT5PcwAiBWUtGmBXapJqFK5166U33J.tar.zst",
	internal: "../../src/internal.roc",
}

import internal.Surreal

# Must not compile (`run.sh`): a schema rule that reads a value from
# around the clause. SurrealDB stores the text of a rule and runs it with
# no parameters, so a value of run time has no place in it: a compile
# error at the line of the lambda. The chain ends in `Defined`, which is
# not built on `Code.Bound`, so the compiler refuses the capture itself.
# `stored_graph` in `src/Surreal.roc` refuses a slot in a schema clause
# too (`Code.refuse_at`), for a chain that the compiler would run.

Vet : { id : Str, name : Str, age : I64 }

vets : Surreal.Table(Vet)
vets = Surreal.table("vet")

limited : I64 -> Surreal.Defined
limited = |most|
	vets
		.define()
		.check("young", |v| v.age < most)
		.done()

expect Surreal.schema([limited(9)]).is_ok()
