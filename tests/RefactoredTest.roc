# A test, not an example: it checks that refactoring does not change the
# translation. This is `examples/main.roc`, refactored by hand: the
# parameters of the functions the queries and constraints reify renamed,
# bindings added, bindings in another order, and some helpers inlined or
# extracted. As in `examples/main.roc`, the defaults of `Owner.tags` and
# `Medication.stock` are `??` defaults in their types, and the constraints
# and query fragments over visits and medications come from `Clinic.roc`
# (the `clinic` package in `examples/clinic/`). None of it changes what a
# function computes, so every description is the same, and the script this
# prints is `expected_output.surql`, byte for byte, which the `expect` at
# the end checks. `scripts/all_tests.sh` runs it with `roc test`.
#
# Read `examples/main.roc` to learn the API. This file is the same
# clinic, written differently.

app [main!] { surreal: "../src/main.roc", clinic: "../examples/clinic/main.roc" }

import surreal.Surreal
import clinic.Clinic
import "expected_output.surql" as expected_output : Str

# ------------------------------------------------------------------- rows

Address : { city : Str, line : Str, zip ?: Str }

## `referred_by` links to another owner: a row that links to its own table.
## `tags` has a default, so the schema gives the field `DEFAULT []`.
Owner := { id : Str, name : Str, email : Str, phone ?: Str, address : Address, tags : List(Str) ?? [], referred_by ?: Surreal.Link(Owner) }.{
	encoder_for : _
	parser_for : _
}

Contact : { email : Str, phone : Str }

## A vet's specialty is a union. `Surgery` carries the board that certified it.
Specialty : [General, Surgery({ board : Str }), Dental]

## The years of a vet. `U8` makes the database keep it between 0 and 255.
VetRow(years) : { id : Str, name : Str, license : Str, contact : Contact, years : years, rate : Dec, specialty : Specialty }

Vet : VetRow(U8)

## A medication starts with no stock: the default is in the type.
Medication := { id : Str, name : Str, form : Str, label : Str, unit_price : Dec, stock : I32 ?? 0 }.{
	encoder_for : _
	parser_for : _
}

## What the front desk types in. The label is computed and the stock has a
## default, so a new medication does not say either.
MedicationForm : { id : Str, name : Str, form : Str, unit_price : Dec }

Species : [Dog, Cat, Bird({ wingspan_cm : U8 }), Exotic({ latin : Str })]

## A link inside a list of records.
Vaccine : { name : Str, given : Str, vet : Surreal.Link(Vet) }

## A link inside an optional record.
Chip : { code : Str, implanted_by : Surreal.Link(Vet) }

Patient : {
	id : Str,
	name : Str,
	species : Species,
	age : U8,
	weight_kg : Dec,
	owner : Surreal.Link(Owner),
	allergies : List(Surreal.Link(Medication)),
	chip ?: Chip,
	vaccines : List(Vaccine),
}

Dose : { medication : Surreal.Link(Medication), doses : I64 }

## A link inside an arm of a union.
Outcome : [Treated, Followup({ days : U8 }), Referred({ to : Surreal.Link(Vet), reason : Str })]

Visit : {
	id : Str,
	patient : Surreal.Link(Patient),
	vet : Surreal.Link(Vet),
	seen : Surreal.Datetime,
	items : List(Dose),
	outcome : Outcome,
	fee : Dec,
}

## A graph edge from a vet to a patient.
Treats : { id : Str, from : Surreal.Link(Vet), to : Surreal.Link(Patient), since_year : I64, primary : Bool }

owners : Surreal.Table(Owner)
owners = Surreal.table("owner")

vets : Surreal.Table(Vet)
vets = Surreal.table("vet")

## The same table as `vets`, for a row whose `years` is not yet checked.
unchecked_vets : Surreal.Table(VetRow(I64))
unchecked_vets = Surreal.table("vet")

medications : Surreal.Table(Medication)
medications = Surreal.table("medication")

medication_forms : Surreal.Table(MedicationForm)
medication_forms = Surreal.table("medication")

patients : Surreal.Table(Patient)
patients = Surreal.table("patient")

visits : Surreal.Table(Visit)
visits = Surreal.table("visit")

treats : Surreal.Table(Treats)
treats = Surreal.relation("treats", vets, patients)

ruth_id : Surreal.Id(Vet)
ruth_id = vets.id("ruth")

# --------------------------------------------------- ordinary Roc functions

## Used by the database, as a constraint, and by the application.
valid_email : Str -> Bool
valid_email = |address| {
	not_first = !address.starts_with("@")
	has_at = address.contains("@")
	has_at and not_first
}

## The computed label of a medication, in the database and in the program.
label_of : Str, Str -> Str
label_of = |title, kind| "${title} (${kind})"

species_label : Species -> Str
species_label = |kind| match kind {
	Dog => "dog"
	Cat => "cat"
	Bird(_) => "bird"
	Exotic(other) => other.latin
}

outcome_text : Outcome -> Str
outcome_text = |result| match result {
	Treated => "treated"
	Followup(_) => "follow-up"
	Referred(referral) => {
		vet_name = referral.to.get().name
		"referred to ${vet_name}"
	}
}

needs_attention : Outcome -> Bool
needs_attention = |result| match result {
	Treated => Bool.False
	_ => Bool.True
}

## What a visit costs: the fee and the medication that was given.
bill : Visit -> Dec
bill = |stay| {
	given = stay.items.map(|line| line.doses.to_dec() * line.medication.get().unit_price).sum()
	stay.fee + given
}

wide_wings : Patient -> Bool
wide_wings = |pet| match pet.species {
	Bird(wings) => {
		wide = 20
		wings.wingspan_cm >= wide
	}
	_ => Bool.False
}

expect valid_email("ada@example.org")
expect !valid_email("ada.example.org")
expect label_of("Aspirin", "tablet") == "Aspirin (tablet)"
expect species_label(Bird({ wingspan_cm: 30 })) == "bird"
expect species_label(Exotic({ latin: "gecko" })) == "gecko"
expect needs_attention(Followup({ days: 7 }))
expect !needs_attention(Treated)

## The constraints are functions too. Each one is named, used in the schema,
## and tried on a bad row in Roc and in the database.
sane_outcome : Outcome -> Bool
sane_outcome = |result| match result {
	Followup(plan) => {
		started = plan.days > 0
		short = plan.days <= 90
		started and short
	}
	_ => Bool.True
}

## A bird of any wingspan, or any other animal.
possible_species : Species -> Bool
possible_species = |kind| match kind {
	Bird(wings) => wings.wingspan_cm > 0
	_ => Bool.True
}

named : Str -> Bool
named = |text| text != ""

# ---------------------------------------------------------------- the data

at : Str -> Surreal.Datetime
at = |text| match Surreal.datetime(text) {
	Ok(d) => d
	Err(_) => crash "a valid datetime in the seed data"
}

ruth : Vet
ruth = { id: "ruth", name: "Ruth Okafor", license: "VET-1001", contact: { email: "ruth@paws.example", phone: "555-0101" }, years: 12, rate: 80, specialty: General }

sam : Vet
sam = { id: "sam", name: "Sam Petrov", license: "VET-1002", contact: { email: "sam@paws.example", phone: "555-0102" }, years: 8, rate: 140, specialty: Surgery({ board: "ACVS" }) }

tia : Vet
tia = { id: "tia", name: "Tia Brandt", license: "VET-1003", contact: { email: "tia@paws.example", phone: "555-0103" }, years: 3, rate: 95.5, specialty: Dental }

seed_vets : List(Vet)
seed_vets = [ruth, sam, tia]

jon : Owner
jon = { id: "jon", name: "Jon Berg", email: "jon@example.org", address: { city: "Oslo", line: "Storgata 4", zip: "0155" }, tags: ["new"] }

lena : Owner
lena = { id: "lena", name: "Lena Roux", email: "lena@example.org", phone: "555-0188", address: { city: "Lyon", line: "Rue Merciere 9" }, tags: [] }

mara : Owner
mara = { id: "mara", name: "Mara Ito", email: "mara@example.org", phone: "555-0142", address: { city: "Oslo", line: "Akersgata 12", zip: "0158" }, tags: ["vip"] }

noor : Owner
noor = { id: "noor", name: "Noor Haddad", email: "noor@example.org", address: { city: "Porto", line: "Rua das Flores 7" }, tags: ["vip", "new"], referred_by: owner_link(mara) }

seed_owners : List(Owner)
seed_owners = [jon, lena, mara, noor]

medication : Str, Str, Str, Dec, I32 -> Medication
medication = |id, name, form, unit_price, stock| { id, name, form, label: label_of(name, form), unit_price, stock }

amoxicillin : Medication
amoxicillin = medication("amoxicillin", "Amoxicillin", "tablet", 0.8, 200)

aspirin : Medication
aspirin = medication("aspirin", "Aspirin", "tablet", 0.2, 500)

gabapentin : Medication
gabapentin = medication("gabapentin", "Gabapentin", "capsule", 1.4, 40)

ivermectin : Medication
ivermectin = medication("ivermectin", "Ivermectin", "injection", 3.5, 15)

seed_medications : List(Medication)
seed_medications = [amoxicillin, aspirin, gabapentin, ivermectin]

## A link the program has the row for. In a clause, `get` is a traversal;
## here it reads the row.
vet_link : Vet -> Surreal.Link(Vet)
vet_link = |v| Surreal.fetched(vets, v)

owner_link : Owner -> Surreal.Link(Owner)
owner_link = |o| Surreal.fetched(owners, o)

medication_link : Medication -> Surreal.Link(Medication)
medication_link = |m| Surreal.fetched(medications, m)

patient_link : Patient -> Surreal.Link(Patient)
patient_link = |p| Surreal.fetched(patients, p)

bo : Patient
bo = {
	id: "bo",
	name: "Bo",
	species: Dog,
	age: 12,
	weight_kg: 31.5,
	owner: owner_link(jon),
	allergies: [],
	vaccines: [{ name: "rabies", given: "2025-05-02", vet: vet_link(ruth) }],
}

kiwi : Patient
kiwi = { id: "kiwi", name: "Kiwi", species: Bird({ wingspan_cm: 25 }), age: 2, weight_kg: 0.4, owner: owner_link(lena), allergies: [], vaccines: [] }

luna : Patient
luna = {
	id: "luna",
	name: "Luna",
	species: Cat,
	age: 3,
	weight_kg: 4.2,
	owner: owner_link(mara),
	allergies: [medication_link(aspirin)],
	chip: { code: "985-112", implanted_by: vet_link(sam) },
	vaccines: [],
}

mimi : Patient
mimi = { id: "mimi", name: "Mimi", species: Cat, age: 9, weight_kg: 5.1, owner: owner_link(noor), allergies: [], vaccines: [] }

rex : Patient
rex = {
	id: "rex",
	name: "Rex",
	species: Dog,
	age: 5,
	weight_kg: 28,
	owner: owner_link(mara),
	allergies: [medication_link(aspirin), medication_link(amoxicillin)],
	chip: { code: "985-100", implanted_by: vet_link(ruth) },
	vaccines: [
		{ name: "rabies", given: "2025-06-11", vet: vet_link(ruth) },
		{ name: "distemper", given: "2025-06-11", vet: vet_link(sam) },
	],
}

zed : Patient
zed = { id: "zed", name: "Zed", species: Exotic({ latin: "gecko" }), age: 4, weight_kg: 0.1, owner: owner_link(noor), allergies: [], vaccines: [] }

seed_patients : List(Patient)
seed_patients = [bo, kiwi, luna, mimi, rex, zed]

dose : Medication, I64 -> Dose
dose = |m, doses| { medication: medication_link(m), doses }

visit : Str, Patient, Vet, Str, List(Dose), Outcome, Dec -> Visit
visit = |id, patient, vet, seen, items, outcome, fee| {
	id,
	patient: patient_link(patient),
	vet: vet_link(vet),
	seen: at(seen),
	items,
	outcome,
	fee,
}

seed_visits : List(Visit)
seed_visits = [
	visit("v1", rex, ruth, "2026-01-10T09:00:00Z", [dose(amoxicillin, 14)], Treated, 80),
	visit("v2", rex, sam, "2026-02-03T14:30:00Z", [], Followup({ days: 14 }), 140),
	visit("v3", luna, ruth, "2026-02-20T10:15:00Z", [dose(gabapentin, 10)], Referred({ to: vet_link(tia), reason: "dental scale" }), 80),
	visit("v4", bo, ruth, "2026-03-05T11:00:00Z", [dose(amoxicillin, 7), dose(ivermectin, 1)], Treated, 80),
	visit("v5", mimi, sam, "2026-03-18T16:45:00Z", [], Treated, 140),
	visit("v6", kiwi, ruth, "2026-04-02T08:30:00Z", [dose(ivermectin, 1)], Followup({ days: 7 }), 40),
	visit("v7", zed, sam, "2026-04-11T13:00:00Z", [], Treated, 60),
]

edge : Str, Vet, Patient, I64, Bool -> Treats
edge = |id, v, p, since_year, primary| { id, from: vet_link(v), to: patient_link(p), since_year, primary }

seed_treats : List(Treats)
seed_treats = [
	edge("e1", ruth, rex, 2022, Bool.True),
	edge("e2", sam, rex, 2024, Bool.False),
	edge("e3", ruth, bo, 2020, Bool.True),
	edge("e4", sam, luna, 2025, Bool.True),
	edge("e5", tia, luna, 2025, Bool.False),
	edge("e6", ruth, kiwi, 2026, Bool.True),
	edge("e7", sam, mimi, 2023, Bool.True),
	edge("e8", ruth, zed, 2026, Bool.True),
]

# ------------------------------------------------------------------ schema

owner_def : Surreal.Defined
owner_def =
	owners.define()
		.unique(|who| who.email)
		.unique(|who| { line: who.address.line, city: who.address.city })
		.assert(|who| who.email, valid_email)
		.assert_each(|who| who.tags, |tag| tag != "")
		.check("named", |who| who.name != "")
		.index(|who| who.address.city)
		.on_delete(owners, Unset)
		.done()

vet_def : Surreal.Defined
vet_def =
	vets.define()
		.unique(|doc| doc.contact.email)
		.assert(|doc| doc.contact.email, |address| Surreal.Text.is_email(address))
		.assert(|doc| doc.license, |code| code.starts_with("VET-"))
		.readonly(|doc| doc.license)
		.check("positive rate", |doc| doc.rate > 0)
		.done()

medication_def : Surreal.Defined
medication_def =
	medications.define()
		.computed(|med| med.label, |med| label_of(med.name, med.form))
		.done()

## The weight rule, extracted from the schema into a function of its own.
has_weight : Patient -> Bool
has_weight = |pet| pet.weight_kg > 0

patient_def : Surreal.Defined
patient_def =
	patients.define()
		.unique(|pet| { owner: pet.owner, name: pet.name })
		.assert(|pet| pet.species, possible_species)
		.assert_each(|pet| pet.vaccines, |shot| named(shot.name))
		.check("weight above zero", has_weight)
		.default(|pet| pet.allergies, [])
		.index(|pet| pet.age)
		.on_delete(owners, Cascade)
		.on_delete(vets, Reject)
		.on_delete_at(|pet| pet.allergies, Unset)
		.done()

visit_def : Surreal.Defined
visit_def =
	visits.define()
		.assert_each(|stay| stay.items, Clinic.positive_doses)
		.assert(|stay| stay.outcome, sane_outcome)
		.check("items need a fee", Clinic.fee_covers_items)
		.check("fee not negative", |stay| stay.fee >= 0)
		.index(|stay| stay.seen)
		.on_delete(patients, Cascade)
		.on_delete(medications, Reject)
		.done()

treats_def : Surreal.Defined
treats_def =
	treats.define()
		.check("since a real year", |link| link.since_year >= 1990)
		.unique(|link| { to: link.to, from: link.from })
		.done()

# ---------------------------------------------------------------- queries

CityParam : { city : Str }

in_city : CityParam, Owner -> Bool
in_city = |param, who| {
	wanted = param.city
	who.address.city == wanted
}

OwnerCard : { id : Str, name : Str, phone : Str }

## An optional field has a say in the query too: `??` is the same in both.
owner_card : Owner -> OwnerCard
owner_card = |who| {
	phone = who.?phone ?? "none"
	{ phone, name: who.name, id: who.id }
}

## A link to a row of the same table, read through `.?`.
ReferralLine : { id : Str, by : Str }

referral_line : Owner -> ReferralLine
referral_line = |who| {
	by = match who.?referred_by {
		Err(_) => "nobody"
		Ok(friend) => friend.get().name
	}
	{ by, id: who.id }
}

is_vip : Owner -> Bool
is_vip = |who| {
	tag = "vip"
	who.tags.contains(tag)
}

## A traversal through the owner link, and a `match` on the union.
PetLine : { id : Str, kind : Str, owner : Str }

pet_line : Patient -> PetLine
pet_line = |pet| {
	owner_name = pet.owner.get().name
	{ owner: owner_name, kind: species_label(pet.species), id: pet.id }
}

## A link inside an optional record: the chip's vet, or nobody.
ChipLine : { id : Str, chip : Str, by : Str }

chip_line : Patient -> ChipLine
chip_line = |pet| {
	by = match pet.?chip {
		Ok(implant) => implant.implanted_by.get().name
		Err(_) => "nobody"
	}
	code = match pet.?chip {
		Ok(implant) => implant.code
		Err(_) => "none"
	}
	{ by, chip: code, id: pet.id }
}

## Links inside a list of records.
VaccineLine : { id : Str, vets : List(Str) }

vaccine_line : Patient -> VaccineLine
vaccine_line = |pet| {
	names = pet.vaccines.map(|shot| shot.vet.get().name)
	{ vets: names, id: pet.id }
}

vaccinated_by_ruth : Patient -> Bool
vaccinated_by_ruth = |pet| pet.vaccines.any(|shot| shot.vet.id() == ruth_id)

SinceParam : { since : Surreal.Datetime }

VisitLine : { id : Str, patient : Str, vet : Str, bill : Dec }

visit_line : Visit -> VisitLine
visit_line = |stay| {
	cost = bill(stay)
	{ vet: stay.vet.get().name, patient: stay.patient.get().name, id: stay.id, bill: cost }
}

OutcomeLine : { id : Str, text : Str }

outcome_line : Visit -> OutcomeLine
outcome_line = |stay| {
	text = outcome_text(stay.outcome)
	{ text, id: stay.id }
}

needs_follow_up : Visit -> Bool
needs_follow_up = |stay| needs_attention(stay.outcome)

## Edges leaving a vet: how many patients, and how many are the vet's own.
CaseLoad : { name : Str, patients : I64, primary : I64 }

case_load : Vet, List(Treats) -> CaseLoad
case_load = |doc, links| {
	own = links.keep_if(|link| link.primary).len().to_i64_wrap()
	all = links.len().to_i64_wrap()
	{ primary: own, patients: all, name: doc.name }
}

## Edges arriving at a patient: the lead vet, if any.
TeamLine : { name : Str, team : I64, lead : List(Str) }

team_line : Patient, List(Treats) -> TeamLine
team_line = |pet, links| {
	lead = links.keep_if(|link| link.primary).map(|link| link.from.get().name)
	{ team: links.len().to_i64_wrap(), name: pet.name, lead }
}

Ledger : { vet : Str, visits : I64, revenue : Dec, avg_fee : F64 }

ledger_line : Str, List(Visit) -> Ledger
ledger_line = |who, stays| {
	revenue = stays.map(|stay| stay.fee).sum()
	avg_fee = Surreal.Math.mean(stays.map(|stay| stay.fee.to_f64()))
	{ visits: stays.len().to_i64_wrap(), vet: who, revenue, avg_fee }
}

PatientAge : { id : Str, age : U8 }

patient_age : Patient -> PatientAge
patient_age = |pet| { age: pet.age, id: pet.id }

## A query written inside a function. The price limit exists only when the
## program runs, so the statement takes it as a `LET`.
cheaper_than : Dec -> Try(Surreal.Prepared(List(Medication)), Surreal.Error)
cheaper_than = |ceiling| {
	cheap = Surreal.select_where(medications, |med| med.unit_price < ceiling)
	Surreal.bind_captured(cheap)
}

## A query over captured records with an optional field. An address with
## no `zip` arrives with `Code.Value.Absent` for the field, and its object
## leaves the field out, as the stored owner rows do.
owners_at : List(Address) -> Try(Surreal.Prepared(List(Owner)), Surreal.Error)
owners_at = |addresses| {
	living = Surreal.select_where(owners, |owner| addresses.contains(owner.address))
	Surreal.bind_captured(living)
}

## The same query over one captured address, compared with `==`. The
## comparison checks if the `zip` is present, then its value. An address with
## no `zip` matches only the rows that hold none.
owner_at : Address -> Try(Surreal.Prepared(List(Owner)), Surreal.Error)
owner_at = |address| {
	living = Surreal.select_where(owners, |owner| owner.address == address)
	Surreal.bind_captured(living)
}

ContactLine : { id : Str, city : Str, vets : List(Str) }

## Reads fields of the owner and of the vaccinating vets through their links.
contact_line : Patient -> ContactLine
contact_line = |pet| {
	city = pet.owner.get().address.city
	{ vets: pet.vaccines.map(|shot| shot.vet.get().name), city, id: pet.id }
}

## Whole linked rows: the owner, and the vet of each vaccine.
LinkedRows : { id : Str, owner : Owner, vets : List(Vet) }

linked_rows : Patient -> LinkedRows
linked_rows = |pet| {
	owner = pet.owner.get()
	{ vets: pet.vaccines.map(|shot| shot.vet.get()), owner, id: pet.id }
}

StockLine : { id : Str, label : Str, stock : I32 }

stock_line : Medication -> StockLine
stock_line = |med| { stock: med.stock, label: med.label, id: med.id }

RestockParam : { floor : I32, add : I32 }

refill : RestockParam, Medication -> Medication
refill = |param, med| {
	topped_up = med.stock + param.add
	{ ..med, stock: topped_up }
}

SpecialtyLine : { id : Str, years : U8, specialty : Specialty }

specialty_line : Vet -> SpecialtyLine
specialty_line = |doc| { specialty: doc.specialty, years: doc.years, id: doc.id }

## Tia passes her surgery boards.
certified : Vet -> Vet
certified = |doc| {
	older = doc.years + 1
	{ ..doc, specialty: Surgery({ board: "ECVS" }), years: older }
}

## Jon goes by his middle initial. `Owner` has optional fields, so `..o`
## keeps each one as it is: the update sets `name` alone.
renamed : Owner -> Owner
renamed = |o| { ..o, name: "Jon B. Berg" }

## Lena's address gets its zip, and she has no phone now. A patch of only
## the fields it sets; a `Try` sets an optional field, and `Err` removes it.
moved : Owner -> { address : Address, phone : Try(Str, [Missing]) }
moved = |o| { address: { ..o.address, zip: "69002" }, phone: Err(Missing) }

lena_moved : Owner
lena_moved = { id: "lena", name: "Lena Roux", email: "lena@example.org", address: { city: "Lyon", line: "Rue Merciere 9", zip: "69002" }, tags: [] }

ReachLine : { id : Str, name : Str, phone : Str, zip : Str }

reach_line : Owner -> ReachLine
reach_line = |o| { id: o.id, name: o.name, phone: o.?phone ?? "none", zip: o.address.?zip ?? "none" }

AllergyLine : { id : Str, allergies : List(Str) }

allergy_line : Patient -> AllergyLine
allergy_line = |pet| {
	names = pet.allergies.map(|med| med.get().name)
	{ allergies: names, id: pet.id }
}

EdgeLine : { id : Str, vet : Str, patient : Str }

edge_line : Treats -> EdgeLine
edge_line = |link| { patient: link.to.get().name, vet: link.from.get().name, id: link.id }

RetentionParam : { before : Surreal.Datetime }

# ------------------- the reference results: the seed rows, filtered in Roc

# Helpers for the `-- roc:` lines of the script. Each one computes a query's
# result in Roc from the seed rows, and `check.py` compares it with the result
# the database returns.

owners_in_city : Str -> List(OwnerCard)
owners_in_city = |city| seed_owners.keep_if(|o| in_city({ city: city }, o)).map(owner_card)

edges_of_vet : Vet -> List(Treats)
edges_of_vet = |v| seed_treats.keep_if(|e| e.from.get().id == v.id)

edges_of_patient : Patient -> List(Treats)
edges_of_patient = |p| seed_treats.keep_if(|e| e.to.get().id == p.id)

visit_names : List(Str)
visit_names = seed_visits.map(|v| v.vet.get().name).fold([], |seen, name| if (seen.contains(name)) seen else seen.append(name))

ledger_in_memory : List(Ledger)
ledger_in_memory = visit_names.map(|name| ledger_line(name, seed_visits.keep_if(|v| v.vet.get().name == name)))

expect owners_in_city("Oslo").map(|c| c.id) == ["jon", "mara"]
expect owner_card(lena).phone == "555-0188"
expect owner_card(jon).phone == "none"
expect referral_line(noor) == { id: "noor", by: "Mara Ito" }
expect referral_line(jon).by == "nobody"
expect pet_line(rex) == { id: "rex", kind: "dog", owner: "Mara Ito" }
expect chip_line(rex) == { id: "rex", chip: "985-100", by: "Ruth Okafor" }
expect chip_line(bo) == { id: "bo", chip: "none", by: "nobody" }
expect vaccine_line(rex).vets == ["Ruth Okafor", "Sam Petrov"]
expect wide_wings(kiwi) and !wide_wings(rex)
expect seed_patients.keep_if(vaccinated_by_ruth).map(|p| p.id) == ["bo", "rex"]
expect bill(visit_of("v4")).to_str() == "89.1"
expect case_load(ruth, edges_of_vet(ruth)) == { name: "Ruth Okafor", patients: 4, primary: 4 }
expect team_line(luna, edges_of_patient(luna)) == { name: "Luna", team: 2, lead: ["Sam Petrov"] }
expect ledger_in_memory.map(|l| l.vet) == ["Ruth Okafor", "Sam Petrov"]
expect outcome_line(visit_of("v3")).text == "referred to Tia Brandt"

visit_of : Str -> Visit
visit_of = |id| match seed_visits.find_first(|v| v.id == id) {
	Ok(v) => v
	Err(_) => crash "no such visit in the seed data"
}

# ----------------------------------------------------------- the constraints

## A visit that gives medication for free.
free_medication : Visit
free_medication = { ..visit_of("v1"), id: "v8", fee: 0 }

zero_doses : Dose
zero_doses = dose(amoxicillin, 0)

expect !Clinic.fee_covers_items(free_medication)
expect Clinic.fee_covers_items(visit_of("v1"))
expect !Clinic.positive_doses(zero_doses)
expect Clinic.positive_doses(dose(amoxicillin, 3))
expect !sane_outcome(Followup({ days: 0 }))
expect !possible_species(Bird({ wingspan_cm: 0 }))
expect !named("")

## Rows the database must refuse, one for each constraint. Where a Roc
## function states the rule, `expect` tries it on the same row.
light_patient : Patient
light_patient = { ..bo, id: "bad", name: "Featherweight", weight_kg: 0 }

blank_tag_owner : Owner
blank_tag_owner = { ..jon, id: "bad", name: "Blank", email: "blank@example.org", address: { city: "Nowhere", line: "1 Main St" }, tags: [""] }

bad_email_owner : Owner
bad_email_owner = { ..jon, id: "bad", name: "Mailless", email: "mailless.example.org", address: { city: "Nowhere", line: "2 Main St" } }

shared_email_vet : Vet
shared_email_vet = { ..sam, id: "bad", license: "VET-9001" }

twin_patient : Patient
twin_patient = { ..rex, id: "rex2" }

neighbour : Owner
neighbour = { ..mara, id: "bad", name: "Twin", email: "twin@example.org" }

## In full, not `{ ..ruth, years: 300 }`: a record update has the type of
## its base, and this row's `years` is an `I64`.
old_vet : VetRow(I64)
old_vet = { id: "bad", name: "Methuselah", license: "VET-9002", contact: { email: "old@paws.example", phone: "1" }, years: 300, rate: 50, specialty: General }

wingless_bird : Patient
wingless_bird = { ..kiwi, id: "bad", name: "Wingless", species: Bird({ wingspan_cm: 0 }) }

endless_followup : Visit
endless_followup = { ..visit_of("v2"), id: "bad", outcome: Followup({ days: 0 }) }

ghost_owner_patient : Patient
ghost_owner_patient = { ..bo, id: "bad", name: "Stray", owner: owners.link("nobody") }

ghost_medication_visit : Visit
ghost_medication_visit = { ..visit_of("v1"), id: "bad", items: [{ medication: medications.link("ghost"), doses: 1 }] }

ghost_chip_patient : Patient
ghost_chip_patient = { ..bo, id: "bad", name: "Chipped", chip: { code: "000-000", implanted_by: vets.link("ghost") } }

ghost_referral_visit : Visit
ghost_referral_visit = { ..visit_of("v2"), id: "bad", outcome: Referred({ to: vets.link("ghost"), reason: "who" }) }

ghost_vaccine_patient : Patient
ghost_vaccine_patient = { ..bo, id: "bad", name: "Jabbed", vaccines: [{ name: "rabies", given: "2025-01-01", vet: vets.link("ghost") }] }

blank_vaccine_patient : Patient
blank_vaccine_patient = { ..bo, id: "bad", name: "Unnamed", vaccines: [{ name: "", given: "2025-01-01", vet: vet_link(ruth) }] }

early_edge : Treats
early_edge = edge("e10", tia, kiwi, 1980, Bool.False)

repeated_edge : Treats
repeated_edge = edge("e11", ruth, rex, 2026, Bool.False)

expect !valid_email(bad_email_owner.email)
expect !possible_species(wingless_bird.species)
expect !sane_outcome(endless_followup.outcome)
expect blank_tag_owner.tags == [""]
expect light_patient.weight_kg == 0

# --------------------------------------------------------------- the script

## One block: the statement, then the Roc result for the same question.
block : Str, List(Str), Try(Surreal.Prepared(out), Surreal.Error), Try(Str, Surreal.Error) -> Str
block = |header, flags, prepared, reference| match (prepared, reference) {
	(Ok(p), Ok(literal)) => p.statement().block(header, flags.append("-- roc: ${literal}"))
	(Err(e), _) | (_, Err(e)) => "-- unsupported ${header}: ${Str.inspect(e)}"
}

## A block that has no Roc result: seeds and writes the database must refuse.
plain : Str, List(Str), Try(Surreal.Prepared(out), Surreal.Error) -> Str
plain = |header, flags, prepared| match prepared {
	Ok(p) => p.statement().block(header, flags)
	Err(e) => "-- unsupported ${header}: ${Str.inspect(e)}"
}

## A write, then the rows it changed.
then_read : Try(Surreal.Prepared(a), Surreal.Error), Try(Surreal.Prepared(b), Surreal.Error) -> Try(Surreal.Prepared((Try(a, Surreal.Error), Try(b, Surreal.Error))), Surreal.Error)
then_read = |first, second| match (first, second) {
	(Ok(a), Ok(b)) => a.then(b)
	(Err(e), _) | (_, Err(e)) => Err(e)
}

rejects : Str, Str, Try(Surreal.Prepared(out), Surreal.Error) -> Str
rejects = |name, why, prepared| plain("-- rejects: ${name}", ["-- error: ${why}"], prepared)

pip : Patient
pip = { id: "pip", name: "Pip", species: Dog, age: 1, weight_kg: 6.5, owner: owner_link(jon), allergies: [], vaccines: [] }

meloxicam_form : MedicationForm
meloxicam_form = { id: "meloxicam", name: "Meloxicam", form: "liquid", unit_price: 2.5 }

meloxicam : Medication
meloxicam = medication("meloxicam", "Meloxicam", "liquid", 2.5, 0)

new_edge : Treats
new_edge = edge("e9", tia, rex, 2026, Bool.False)

refill_param : RestockParam
refill_param = { floor: 60, add: 100 }

cutoff : Surreal.Datetime
cutoff = at("2026-02-15T00:00:00Z")

schema_block : Str
schema_block = match Surreal.schema([owner_def, vet_def, medication_def, patient_def, visit_def, treats_def, note_def]) {
	Ok(text) => "-- schema\n${text}"
	Err(e) => "-- bad schema: ${Str.inspect(e)}"
}

reads : List(Str)
reads = [
	block(
		"-- query: owners_in_city",
		["-- ordered"],
		Surreal.from(owners).filter_by(in_city).select(owner_card).order_by(|r| r.id, Asc).prepare({ city: "Oslo" }),
		Surreal.Mirror.literal(owners_in_city("Oslo")),
	),
	block(
		"-- query: vip_owners",
		[],
		Surreal.from(owners).filter(is_vip).select(owner_card).prepare({}),
		Surreal.Mirror.literal(seed_owners.keep_if(is_vip).map(owner_card)),
	),
	block(
		"-- query: referrals",
		[],
		Surreal.from(owners).filter(|who| who.?referred_by.is_ok()).select(referral_line).prepare({}),
		Surreal.Mirror.literal(seed_owners.keep_if(|who| who.?referred_by.is_ok()).map(referral_line)),
	),
	block(
		"-- query: pet_roster",
		["-- ordered"],
		Clinic.by_id(Surreal.from(patients).select(pet_line)).prepare({}),
		Surreal.Mirror.literal(seed_patients.map(pet_line)),
	),
	block(
		"-- query: vet_at_key",
		[],
		vets.at(ruth_id).select(specialty_line).prepare({}),
		Surreal.Mirror.literal([specialty_line(ruth)]),
	),
	block(
		"-- query: vet_by_key",
		[],
		Surreal.from(vets).filter_by(|given, doc| doc.id == given.key).select(specialty_line).prepare({ key: "ruth" }),
		Surreal.Mirror.literal([specialty_line(ruth)]),
	),
	block(
		"-- query: wide_winged",
		[],
		Surreal.from(patients).filter(wide_wings).select_value(|pet| pet.name).prepare({}),
		Surreal.Mirror.literal(seed_patients.keep_if(wide_wings).map(|p| p.name)),
	),
	block(
		"-- query: chips",
		[],
		Surreal.from(patients).select(chip_line).prepare({}),
		Surreal.Mirror.literal(seed_patients.map(chip_line)),
	),
	block(
		"-- query: vaccinated_by_ruth",
		[],
		Surreal.from(patients).filter(vaccinated_by_ruth).select(vaccine_line).prepare({}),
		Surreal.Mirror.literal(seed_patients.keep_if(vaccinated_by_ruth).map(vaccine_line)),
	),
	block(
		"-- query: recent_visits",
		["-- ordered"],
		Clinic.by_id(Clinic.recent(Surreal.from(visits)).select(visit_line)).prepare({ since: at("2026-03-01T00:00:00Z") }),
		Surreal.Mirror.literal(seed_visits.keep_if(|v| Clinic.seen_since({ since: at("2026-03-01T00:00:00Z") }, v)).map(visit_line)),
	),
	block(
		"-- query: past_visits",
		[],
		Surreal.from(visits).filter(|stay| stay.seen < Surreal.Time.now()).select_value(|stay| stay.id).prepare({}),
		Surreal.Mirror.literal(seed_visits.map(|stay| stay.id)),
	),
	block(
		"-- query: follow_ups",
		[],
		Surreal.from(visits).filter(needs_follow_up).select(outcome_line).prepare({}),
		Surreal.Mirror.literal(seed_visits.keep_if(needs_follow_up).map(outcome_line)),
	),
	block(
		"-- query: case_load",
		[],
		Surreal.from(vets).outgoing(treats).select(|(doc, links)| case_load(doc, links)).prepare({}),
		Surreal.Mirror.literal(seed_vets.map(|v| case_load(v, edges_of_vet(v)))),
	),
	block(
		"-- query: teams",
		[],
		Surreal.from(patients).incoming(treats).select(|(pet, links)| team_line(pet, links)).prepare({}),
		Surreal.Mirror.literal(seed_patients.map(|p| team_line(p, edges_of_patient(p)))),
	),
	block(
		"-- query: ledger",
		["-- ordered"],
		Surreal.from(visits).group_by(|stay| stay.vet.get().name).aggregate(ledger_line).order_by(|line| line.revenue, Desc).limit(2).prepare({}),
		Surreal.Mirror.literal(ledger_in_memory.sort_by_reversed(|l| l.revenue).take_first(2)),
	),
	block(
		"-- query: eldest",
		["-- ordered"],
		Surreal.from(patients).select(patient_age).order_by(|r| r.age, Desc).limit(3).prepare({}),
		Surreal.Mirror.literal(seed_patients.map(patient_age).sort_by_reversed(|r| r.age).take_first(3)),
	),
	block(
		"-- query: labels",
		["-- ordered"],
		Surreal.from(medications).select_value(|med| med.label).order_by(|l| l, Asc).prepare({}),
		Surreal.Mirror.literal(seed_medications.map(|m| m.label)),
	),
	block(
		"-- query: whole_vets",
		[],
		Surreal.from(vets).select_value(|vet| vet).prepare({}),
		Surreal.Mirror.literal(seed_vets),
	),
	block(
		"-- query: second_page",
		["-- ordered"],
		Surreal.from(patients).select(pet_line).order_by(|r| r.id, Asc).start(2).limit(2).prepare({}),
		Surreal.Mirror.literal(seed_patients.map(pet_line).drop_first(2).take_first(2)),
	),
	block(
		"-- query: linked_fields",
		[],
		Surreal.from(patients).select(contact_line).prepare({}),
		Surreal.Mirror.literal(seed_patients.map(contact_line)),
	),
	block(
		"-- query: linked_rows",
		[],
		Surreal.from(patients).select(linked_rows).prepare({}),
		Surreal.Mirror.literal(seed_patients.map(linked_rows)),
	),
	block(
		"-- query: cheaper_than",
		[],
		cheaper_than(0.9),
		Surreal.Mirror.literal(seed_medications.keep_if(|m| m.unit_price < 0.9)),
	),
	block(
		"-- query: owners_at",
		[],
		owners_at(at_places),
		Surreal.Mirror.literal(seed_owners.keep_if(|o| at_places.contains(o.address))),
	),
	block(
		"-- query: owner_at, with a zip",
		[],
		owner_at(oslo_place),
		Surreal.Mirror.literal(seed_owners.keep_if(|o| o.address == oslo_place)),
	),
	block(
		"-- query: owner_at, with no zip",
		[],
		owner_at(lyon_place),
		Surreal.Mirror.literal(seed_owners.keep_if(|o| o.address == lyon_place)),
	),
]

## Lena's address has no `zip`, and Jon's has one.
at_places : List(Address)
at_places = [{ city: "Lyon", line: "Rue Merciere 9" }, { city: "Oslo", line: "Storgata 4", zip: "0155" }]

## Jon's address has a `zip`, and Lena's has none.
oslo_place : Address
oslo_place = { city: "Oslo", line: "Storgata 4", zip: "0155" }

lyon_place : Address
lyon_place = { city: "Lyon", line: "Rue Merciere 9" }

script : Str
script = Str.join_with([schema_block].concat(seeds).concat(reads).concat(refusals).concat(writes).concat(totals_blocks), "\n\n")

seeds : List(Str)
seeds = [
	plain("-- seed: vet", [], vets.insert(seed_vets)),
	plain("-- seed: owner", [], owners.insert(seed_owners)),
	plain("-- seed: medication", [], medications.insert(seed_medications)),
	plain("-- seed: patient", [], patients.insert(seed_patients)),
	plain("-- seed: visit", [], visits.insert(seed_visits)),
	plain("-- seed: treats", [], treats.insert(seed_treats)),
]

refusals : List(Str)
refusals = [
	rejects("check_as_assert", "field `weight_kg`", patients.create(light_patient)),
	rejects("check_as_event", "visit: items need a fee", visits.create(free_medication)),
	rejects("assert_email", "field `email`", owners.create(bad_email_owner)),
	rejects("assert_on_nested_path", "field `contact.email`", vets.create({ ..shared_email_vet, contact: { email: "no-at-sign", phone: "1" } })),
	rejects("assert_on_union", "field `species`", patients.create(wingless_bird)),
	rejects("assert_on_outcome", "field `outcome`", visits.create(endless_followup)),
	rejects("assert_each_tag", "field `tags`", owners.create(blank_tag_owner)),
	rejects("assert_each_dose", "field `items.*.doses`", visits.create({ ..visit_of("v1"), id: "bad", items: [zero_doses] })),
	rejects("assert_each_vaccine", "field `vaccines.*.name`", patients.create(blank_vaccine_patient)),
	rejects("unique_nested_path", "already contains", vets.create(shared_email_vet)),
	rejects("unique_composite_with_link", "already contains", patients.create(twin_patient)),
	rejects("unique_composite_address", "already contains", owners.create(neighbour)),
	rejects("unique_edge_ends", "already contains", treats.create(repeated_edge)),
	rejects("check_on_edge", "field `since_year`", treats.create(early_edge)),
	rejects("u8_range", "field `years`", unchecked_vets.create(old_vet)),
	rejects("readonly_license", "field is readonly", vets.update_at(vets.id("ruth"), |v| { ..v, license: "VET-2000" }).prepare({})),
	rejects("link_exists_root", "field `owner`", patients.create(ghost_owner_patient)),
	rejects("link_exists_in_list_of_records", "field `items.*.medication`", visits.create(ghost_medication_visit)),
	rejects("link_exists_in_optional_record", "field `chip.implanted_by`", patients.create(ghost_chip_patient)),
	rejects("link_exists_in_union_arm", "field `outcome`", visits.create(ghost_referral_visit)),
	rejects("link_exists_in_vaccines", "field `vaccines.*.vet`", patients.create(ghost_vaccine_patient)),
	rejects("delete_vet_with_visits", "ON DELETE REJECT", vets.delete_at(vets.id("ruth")).prepare({})),
	rejects("delete_vet_in_a_referral", "is referenced by visit.outcome.to", vets.delete_at(vets.id("tia")).prepare({})),
	rejects("delete_medication_in_a_visit", "is referenced by visit.items[*].medication", medications.delete_at(medications.id("amoxicillin")).prepare({})),
]

patients_now : List(Patient)
patients_now = [bo, kiwi, luna, mimi, pip, rex, zed]

medications_now : List(Medication)
medications_now = seed_medications.append(meloxicam)

without_aspirin : Patient -> Patient
without_aspirin = |p| { ..p, allergies: p.allergies.keep_if(|a| a.get().id != "aspirin") }

owned_by_noor : Patient -> Bool
owned_by_noor = |p| p.owner.get().id == "noor"

expect without_aspirin(rex).allergies.map(|a| a.get().id) == ["amoxicillin"]
expect refill(refill_param, { ..ivermectin, stock: 10 }).stock == 110
expect certified(tia).years == 4

visits_now : List(Visit)
visits_now = seed_visits.keep_if(|v| !owned_by_noor(v.patient.get()))

writes : List(Str)
writes = [
	block(
		"-- write: admit_patient",
		["-- ordered"],
		then_read(patients.create(pip), Surreal.from(patients).select(pet_line).order_by(|r| r.id, Asc).prepare({})),
		Surreal.Mirror.literal(patients_now.map(pet_line)),
	),
	block(
		"-- write: add_medication",
		["-- ordered"],
		then_read(medication_forms.create(meloxicam_form), Clinic.by_id(Surreal.from(medications).select(stock_line)).prepare({})),
		Surreal.Mirror.literal(medications_now.map(stock_line)),
	),
	block(
		"-- write: restock",
		["-- ordered"],
		then_read(
			medications.update_by(Clinic.low_stock, refill).prepare(refill_param),
			Surreal.from(medications).select(stock_line).order_by(|r| r.id, Asc).prepare({}),
		),
		Surreal.Mirror.literal(medications_now.map(|m| if (Clinic.low_stock(refill_param, m)) refill(refill_param, m) else m).map(stock_line)),
	),
	block(
		"-- write: certify_vet",
		["-- ordered"],
		then_read(
			vets.update_at(vets.id("tia"), certified).prepare({}),
			Surreal.from(vets).select(specialty_line).order_by(|r| r.id, Asc).prepare({}),
		),
		Surreal.Mirror.literal(seed_vets.map(|v| if (v.id == "tia") certified(v) else v).map(specialty_line)),
	),
	block(
		"-- write: rename_owner",
		["-- ordered"],
		then_read(
			owners.update_at(owners.id("jon"), renamed).prepare({}),
			Surreal.from(owners).select(reach_line).order_by(|r| r.id, Asc).prepare({}),
		),
		Surreal.Mirror.literal(seed_owners.map(|o| if (o.id == "jon") renamed(o) else o).map(reach_line)),
	),
	block(
		"-- write: move_owner",
		["-- ordered"],
		then_read(
			owners.set_at(owners.id("lena"), moved).prepare({}),
			Surreal.from(owners).select(reach_line).order_by(|r| r.id, Asc).prepare({}),
		),
		Surreal.Mirror.literal(seed_owners.map(|o| if (o.id == "jon") renamed(o) else if (o.id == "lena") lena_moved else o).map(reach_line)),
	),
	block(
		"-- write: delete_medication_unsets_allergies",
		["-- ordered"],
		then_read(
			medications.delete_at(medications.id("aspirin")).prepare({}),
			Surreal.from(patients).select(allergy_line).order_by(|r| r.id, Asc).prepare({}),
		),
		Surreal.Mirror.literal(patients_now.map(without_aspirin).map(allergy_line)),
	),
	block(
		"-- write: relate_vet",
		["-- ordered"],
		then_read(treats.create(new_edge), Surreal.from(treats).select(edge_line).order_by(|r| r.id, Asc).prepare({})),
		Surreal.Mirror.literal(seed_treats.append(new_edge).map(edge_line)),
	),
	block(
		"-- write: delete_owner_cascades_to_patients",
		["-- ordered"],
		then_read(
			owners.delete_at(owners.id("noor")).prepare({}),
			Surreal.from(patients).select(|p| { id: p.id }).order_by(|r| r.id, Asc).prepare({}),
		),
		Surreal.Mirror.literal(patients_now.keep_if(|p| !owned_by_noor(p)).map(|p| { id: p.id })),
	),
	block(
		"-- query: visits_left_by_the_cascade",
		["-- ordered"],
		Surreal.from(visits).select(|v| { id: v.id }).order_by(|r| r.id, Asc).prepare({}),
		Surreal.Mirror.literal(visits_now.map(|v| { id: v.id })),
	),
	block(
		"-- query: edges_left_by_the_cascade",
		["-- ordered"],
		Surreal.from(treats).select(edge_line).order_by(|r| r.id, Asc).prepare({}),
		Surreal.Mirror.literal(seed_treats.append(new_edge).keep_if(|e| !owned_by_noor(e.to.get())).map(edge_line)),
	),
	block(
		"-- write: retention",
		["-- ordered"],
		then_read(
			visits.delete_by(Clinic.too_old).prepare({ before: cutoff }),
			Surreal.from(visits).select(|v| { id: v.id }).order_by(|r| r.id, Asc).prepare({}),
		),
		Surreal.Mirror.literal(visits_now.keep_if(|v| !Clinic.too_old({ before: cutoff }, v)).map(|v| { id: v.id })),
	),
	block(
		"-- write: add_notes",
		[],
		then_read(notes.insert_new(new_notes), Surreal.from(notes).select(note_line).prepare({})),
		Surreal.Mirror.literal(new_notes.map(note_line)),
	),
]

expect "${script}\n" == expected_output

# ------------------------------------------------ keys that the server makes

Note : { id : Str, vet : Surreal.Link(Vet), text : Str }

notes : Surreal.Table(Note)
notes = Surreal.table("note")

note_def : Surreal.Defined
note_def = notes.define().default_by(|entry| entry.id, |_| Surreal.Rand.ulid()).done()

new_notes : List({ vet : Surreal.Link(Vet), text : Str })
new_notes = {
	booster = { vet: vet_link(ruth), text: "Rex is due a booster" }
	gauze = { vet: vet_link(sam), text: "Order gauze" }
	[booster, gauze]
}

NoteLine : { vet : Str, text : Str }

note_line : { vet : Surreal.Link(Vet), text : Str, ..r } -> NoteLine
note_line = |entry| {
	author = entry.vet.get()
	{ vet: author.name, text: entry.text }
}

main! = |_args| {
	echo!("${script}\n")
	Ok({})
}

# ------------------------------------------- GROUP ALL, after the writes

VisitTotals : { visits : I64, revenue : Dec, avg_fee : F64 }

visit_totals : List(Visit) -> VisitTotals
visit_totals = |rows| {
	fees = rows.map(|v| v.fee)
	{ visits: rows.len().to_i64_wrap(), revenue: fees.sum(), avg_fee: Surreal.Math.mean(rows.map(|v| v.fee.to_f64())) }
}

totals_blocks : List(Str)
totals_blocks = {
	kept = visits_now.keep_if(|v| !Clinic.too_old({ before: cutoff }, v))
	costly = Surreal.from(visits).filter(|v| v.fee > 1000)
	[
		block(
			"-- query: visit_totals",
			[],
			Surreal.from(visits).totals(visit_totals).prepare({}),
			Surreal.Mirror.literal([visit_totals(kept)]),
		),
		block(
			"-- query: no_visit_totals",
			[],
			costly.totals(|rows| { visits: rows.len().to_i64_wrap() }).prepare({}),
			Surreal.Mirror.literal([{ visits: visit_totals([]).visits }]),
		),
	]
}
