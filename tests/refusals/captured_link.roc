# refused-at: 28
# message: a captured `Link` has no SurrealQL value
app [] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.5.0/B5U2mPsWTtuxfCRMzqQxio2ecDv7CAzCoyEMENMh4FNF.tar.zst",
	internal: "../../src/internal.roc",
}

import internal.Surreal

# Must not compile (`run.sh`): a function whose chain reads a `Link` from
# around the clause. The slot type has no SurrealQL value, and the
# translator refuses it at the place that reads it (`slots_of`,
# `Code.refuse_at`): a compile error at the line of the lambda.

Vet : { id : Str, name : Str }

Pet : { id : Str, name : Str, vet : Surreal.Link(Vet) }

vets : Surreal.Table(Vet)
vets = Surreal.table("vet")

pets : Surreal.Table(Pet)
pets = Surreal.table("pet")

of_vet : Surreal.Link(Vet) -> Surreal.Prepared(List(Pet))
of_vet = |vet|
	Surreal.from(pets)
		.filter(|p| p.vet == vet)
		.ready()

expect of_vet(vets.link("ruth")).checked().is_ok()
