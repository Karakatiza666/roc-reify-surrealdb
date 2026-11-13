app [] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.5.0/B5U2mPsWTtuxfCRMzqQxio2ecDv7CAzCoyEMENMh4FNF.tar.zst",
	internal: "../src/internal.roc",
}

import internal.Surreal

# Tests of queries in functions that capture values (gap 1 of
# `analysis/compiler-gaps.md`): the chain up to the terminal call runs once,
# when the compiler runs, and each call gives the values of its captures,
# which the statement binds with a `LET $_k`. Nothing outside this file
# imports it.

Medication : { id : Str, name : Str, unit_price : Dec, stock : U64 }

medications : Surreal.Table(Medication)
medications = Surreal.table("medication")

Address : { city : Str, line : Str, zip ?: Str }

Owner : { id : Str, name : Str, address : Address }

owners : Surreal.Table(Owner)
owners = Surreal.table("owner")

Vet : { id : Str, name : Str }

Pet : { id : Str, name : Str, vet : Surreal.Link(Vet) }

pets : Surreal.Table(Pet)
pets = Surreal.table("pet")

script : Surreal.Prepared(out) -> Str
script = |prepared| match prepared.request() {
	Ok(text) => text
	Err(e) => "error: ${Str.inspect(e)}"
}

# One translation, two calls: the same text, and each call its own value.
# The chain runs when the compiler runs: at run time a `Code` does not
# exist, and a statement built then has no inputs, so a slot with no value
# would be the error of `ready_of`.
cheaper_than : Dec -> Surreal.Prepared(List(Medication))
cheaper_than = |limit| Surreal.from(medications).filter(|m| m.unit_price < limit).ready()

expect script(cheaper_than(0.9)) == "LET $_1 = 0.9dec;\nSELECT record::id(id) AS id, name, stock, unit_price FROM medication WHERE unit_price < $_1;"
expect script(cheaper_than(2.0)) == "LET $_1 = 2.0dec;\nSELECT record::id(id) AS id, name, stock, unit_price FROM medication WHERE unit_price < $_1;"
expect cheaper_than(0.9).checked().is_ok()

# Two lambdas of one chain capture a value each: `$_1` is in the `WHERE`,
# `$_2` in the projection, in the order the lambdas are written.
PriceLine : { name : Str, over : Dec }

dearer_than : Dec, Dec -> Surreal.Prepared(List(PriceLine))
dearer_than = |least, base| Surreal.from(medications).filter(|m| m.unit_price >= least).select(|m| { name: m.name, over: m.unit_price - base }).ready()

expect script(dearer_than(1.5, 1.0)) == "LET $_1 = 1.5dec;\nLET $_2 = 1.0dec;\nSELECT name AS name, unit_price - $_2 AS over FROM medication WHERE unit_price >= $_1;"

# A captured record with an optional field: one slot, read field by field.
# The same text as `bind_captured` gave (tests/expected_output.surql, 0.0.2).
owner_at : Address -> Surreal.Prepared(List(Owner))
owner_at = |place| Surreal.from(owners).filter(|o| o.address == place).ready()

expect script(owner_at({ city: "Oslo", line: "Storgata 4", zip: "0155" })) == "LET $_1 = { city: 'Oslo', line: 'Storgata 4', zip: '0155' };\nSELECT address, record::id(id) AS id, name FROM owner WHERE (address.city = $_1.city) AND (address.line = $_1.line) AND (address.zip = $_1.zip);"
expect script(owner_at({ city: "Lyon", line: "Rue Merciere 9" })) == "LET $_1 = { city: 'Lyon', line: 'Rue Merciere 9' };\nSELECT address, record::id(id) AS id, name FROM owner WHERE (address.city = $_1.city) AND (address.line = $_1.line) AND (address.zip = $_1.zip);"

# A patch record from a lambda with no annotated helper, and a key known
# only at run time: the key is one slot (R12), the name another.
rename : Str, Str -> Surreal.Prepared(List(Owner))
rename = |key, name| owners.set_at(owners.id(key), |_| { name: name }).ready()

expect script(rename("jon", "Jo")) == "LET $_1 = owner:⟨jon⟩;\nLET $_2 = 'Jo';\nUPDATE $_1 SET name = $_2 RETURN AFTER;"

# A key of another table is refused when its value is bound.
rename_any : Surreal.Id(Owner), Str -> Surreal.Prepared(List(Owner))
rename_any = |key, name| owners.set_at(key, |_| { name: name }).ready()

expect script(rename_any(Surreal.Unchecked.id("vet", "jon"), "Jo")) == "error: Unsupported(\"the id `vet:⟨jon⟩` is of the table `vet`, not of `owner`\")"
expect rename_any(Surreal.Unchecked.id("vet", "jon"), "Jo").checked().is_err()

# A count known only at run time (R12): `LIMIT $_k`, `START $_k`.
first_page : U64, U64 -> Surreal.Prepared(List(Medication))
first_page = |skip, size| Surreal.from(medications).select(|m| m).order_by(|m| m.name, Asc).start(skip).limit(size).ready()

expect script(first_page(20, 10)) == "LET $_1 = 20u64;\nLET $_2 = 10u64;\nSELECT record::id(id) AS id, name, stock, unit_price FROM medication ORDER BY name LIMIT <int>$_2 START <int>$_1;"

# A count the program fixes is a literal.
expect script(Surreal.from(medications).select(|m| m).limit(3).ready()) == "SELECT record::id(id) AS id, name, stock, unit_price FROM medication ORDER BY id LIMIT 3;"

# Two statements that both capture: the second's slots come after the
# first's, so each name has one value.
both : Dec, Dec -> Surreal.Prepared((Try(List(Medication), Surreal.Error), Try(List(Medication), Surreal.Error)))
both = |a, b| cheaper_than(a).then(cheaper_than(b))

expect script(both(0.9, 2.0)) == "LET $_1 = 0.9dec;\nLET $_2 = 2.0dec;\nSELECT record::id(id) AS id, name, stock, unit_price FROM medication WHERE unit_price < $_1;\nSELECT record::id(id) AS id, name, stock, unit_price FROM medication WHERE unit_price < $_2;"

# The same in a transaction, three times over.
all_three : Surreal.Prepared(List(List(Medication)))
all_three = Surreal.transaction([cheaper_than(1.0), cheaper_than(2.0), cheaper_than(3.0)])

expect script(all_three) == "LET $_1 = 1.0dec;\nLET $_2 = 2.0dec;\nLET $_3 = 3.0dec;\nBEGIN;\nSELECT record::id(id) AS id, name, stock, unit_price FROM medication WHERE unit_price < $_1;\nSELECT record::id(id) AS id, name, stock, unit_price FROM medication WHERE unit_price < $_2;\nSELECT record::id(id) AS id, name, stock, unit_price FROM medication WHERE unit_price < $_3;\nCOMMIT;"

# A text that holds `$_1` is not a slot: the second statement's slot is
# numbered again, and the quoted text stays as it is.
named : Str -> Surreal.Prepared(List(Medication))
named = |n| Surreal.from(medications).filter(|m| m.name == n or m.name == "$_1").ready()

expect script(named("a").then(named("b"))) == "LET $_1 = 'a';\nLET $_2 = 'b';\nSELECT record::id(id) AS id, name, stock, unit_price FROM medication WHERE (name = $_1) OR (name = '$_1');\nSELECT record::id(id) AS id, name, stock, unit_price FROM medication WHERE (name = $_2) OR (name = '$_1');"

# A statement that cannot be built makes a combination hold its error.
expect script(rename_any(Surreal.Unchecked.id("vet", "x"), "a").then(cheaper_than(1.0))) == "error: Unsupported(\"the id `vet:⟨x⟩` is of the table `vet`, not of `owner`\")"

# B4: `==` between a field and a captured union of four variants. Both
# sides are not constants, so the derived `==` does not fold; the compiler
# `901d5f4824` crashed here (`analysis/repro/union_eq_four_variants.roc`).
Pay : [Cash, Card(Str), Points(U64), Voucher({ code : Str })]

Order : { id : Str, pay : Pay }

orders : Surreal.Table(Order)
orders = Surreal.table("order")

paid_with : Pay -> Surreal.Prepared(List(Order))
paid_with = |pay| Surreal.from(orders).filter(|o| o.pay == pay).ready()

# Verified on SurrealDB 3.3.4: with rows of each variant, `Points(3)`
# finds only the row of `Points(3)`, `Cash` the row of `Cash`, and a
# voucher the row of its code.
expect script(paid_with(Points(3))) == "LET $_1 = { kind: 'Points', value: 3u64 };\nSELECT record::id(id) AS id, pay FROM order WHERE (IF pay.kind = 'Card' THEN (IF $_1.kind = 'Card' THEN pay.value = $_1.value ELSE false END) ELSE IF pay = 'Cash' THEN $_1 = 'Cash' ELSE IF pay.kind = 'Points' THEN (IF $_1.kind = 'Points' THEN pay.value = $_1.value ELSE false END) ELSE (IF $_1.kind = 'Voucher' THEN pay.code = $_1.code ELSE false END) END);"
expect script(paid_with(Cash)) == "LET $_1 = 'Cash';\nSELECT record::id(id) AS id, pay FROM order WHERE (IF pay.kind = 'Card' THEN (IF $_1.kind = 'Card' THEN pay.value = $_1.value ELSE false END) ELSE IF pay = 'Cash' THEN $_1 = 'Cash' ELSE IF pay.kind = 'Points' THEN (IF $_1.kind = 'Points' THEN pay.value = $_1.value ELSE false END) ELSE (IF $_1.kind = 'Voucher' THEN pay.code = $_1.code ELSE false END) END);"
