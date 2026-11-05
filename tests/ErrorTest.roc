app [] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.4.0/EnfRKFT7uPHmd3zT5PcwAiBWUtGmBXapJqFK5166U33J.tar.zst",
	internal: "../src/internal.roc",
}

import internal.Surreal
import internal.Schema
import "fixtures/errors/schema.surql" as schema_text : Str
import "fixtures/errors/exists.cbor" as exists_reply : List(U8)
import "fixtures/errors/unique.cbor" as unique_reply : List(U8)
import "fixtures/errors/unique_pair.cbor" as unique_pair_reply : List(U8)
import "fixtures/errors/assert.cbor" as assert_reply : List(U8)
import "fixtures/errors/type.cbor" as type_reply : List(U8)
import "fixtures/errors/check.cbor" as check_reply : List(U8)
import "fixtures/errors/check_assert.cbor" as check_assert_reply : List(U8)
import "fixtures/errors/referenced.cbor" as referenced_reply : List(U8)
import "fixtures/errors/referenced_nested.cbor" as referenced_nested_reply : List(U8)
import "fixtures/errors/transaction.cbor" as transaction_reply : List(U8)
import "fixtures/errors/not_found.cbor" as not_found_reply : List(U8)
import "fixtures/errors/parse.cbor" as parse_reply : List(U8)
import "fixtures/errors/invalid.cbor" as invalid_reply : List(U8)
import "fixtures/errors/thrown.cbor" as thrown_reply : List(U8)
import "fixtures/errors/timeout.cbor" as timeout_reply : List(U8)
import "fixtures/errors/conflict.cbor" as conflict_reply : List(U8)
import "fixtures/errors/denied.cbor" as denied_reply : List(U8)

# Tests of the typed errors of the server. The schema is the one that
# `Surreal.schema` writes for the tables below, and `check.py` defines it
# from `fixtures/errors/schema.surql` in a database of its own, then saves
# the reply to each request that fails as `fixtures/errors/<name>.cbor`.
# Nothing outside this file imports it.

Owner : { id : Str, email : Str, city : Str, age : I64 }

Pet : { id : Str, name : Str, owner : Surreal.Link(Owner) }

Visit : { id : Str, by : { vet : Surreal.Link(Owner) } }

owners : Surreal.Table(Owner)
owners = Surreal.table("owner")

pets : Surreal.Table(Pet)
pets = Surreal.table("pet")

visits : Surreal.Table(Visit)
visits = Surreal.table("visit")

defs : List(Surreal.Defined)
defs = [
	owners.define()
		.unique(|o| o.email)
		.unique(|o| { city: o.city, age: o.age })
		.assert(|o| o.age, |a| a >= 0)
		.check("adult in town", |o| o.age >= 18 or o.id != "kid")
		.check("oslo needs a mail", |o| o.city != "oslo" or o.email.contains("@"))
		.done(),
	pets.define().done(),
	visits.define().done(),
]

# The schema that `check.py` defines is the one the library writes.
expect Surreal.schema(defs) == Ok(schema_text.trim_end())

ready : Try(Surreal.Prepared(out), Surreal.Error) -> Surreal.Prepared(out)
ready = |prepared| match prepared {
	Ok(p) => p
	Err(_) => crash "the test statement prepares"
}

## A write of the domain, whose reply each fixture is read as: the error
## comes before the count of the results is checked.
create_bob : Surreal.Prepared(List(Owner))
create_bob = ready(owners.create({ id: "bob", email: "bob@x", city: "oslo", age: 30 }))

## The error of a reply, as `Prepared.result` reads it: with no schema.
plain : List(U8) -> Try({}, Surreal.Error)
plain = |bytes| create_bob.result(bytes).map_ok(|_| {})

## The same, as a session that knows `defs` reads it (`Session.knowing`).
knowing : List(U8) -> Try({}, Surreal.Error)
knowing = |bytes| create_bob.result_in(bytes, Schema.unique_indexes(defs)).map_ok(|_| {})

# --------------------------------------------- the kinds of the server

expect plain(exists_reply) == Err(Server(Exists({ what: "Record", name: "owner:ann", message: "Database record `owner:ann` already exists" })))
expect plain(not_found_reply) == Err(Server(NotFound({ what: "Table", name: "nothing_here", message: "The table 'nothing_here' does not exist" })))
expect plain(denied_reply) == Err(Server(Denied("IAM error: Not enough permissions to perform this action")))
expect plain(parse_reply) == Err(Server(Parse("Parse error: Unexpected end of file, expected an expression\n --> [1:13]\n  |\n1 | SELECT * FROM\n  |             ^\n")))
expect plain(invalid_reply) == Err(Server(Invalid("'session' is a protected variable and cannot be set")))
expect plain(thrown_reply) == Err(Server(Thrown({ text: "boom", message: "An error occurred: boom" })))
expect plain(timeout_reply) == Err(Server(Timeout("The query was not executed because it exceeded the timeout: 0ns")))

# A transaction that fails: each statement that did not run is
# `NotExecuted`, and the error is the one that failed it.
expect plain(conflict_reply) == Err(Server(Conflict("Cannot COMMIT: Transaction conflict: Write conflict, retry the transaction. This transaction can be retried")))
expect plain(transaction_reply) == Err(Server(Assert({ table: "owner", field: "age", record: "owner:eve", value: "-2", condition: "$value >= 0", message: "Found -2 for field `age`, with record `owner:eve`, but field must conform to: $value >= 0" })))

## The two writes of a transaction, as `Transaction.commit` reads the
## reply: the place of the statement that failed it, and its error.
in_transaction : List(U8) -> Try({}, Surreal.Error)
in_transaction = |bytes| create_bob.begin().then(create_bob).map_ok(|t| t.commit().result(bytes).map_ok(|_| {})) ?? Err(Unsupported("the transaction joins"))

# The second create fails the transaction; a conflict fails its `COMMIT`,
# the place after the last part.
expect in_transaction(transaction_reply) == Err(Aborted({ at: 1, error: Assert({ table: "owner", field: "age", record: "owner:eve", value: "-2", condition: "$value >= 0", message: "Found -2 for field `age`, with record `owner:eve`, but field must conform to: $value >= 0" }) }))
expect in_transaction(conflict_reply) == Err(Aborted({ at: 2, error: Conflict("Cannot COMMIT: Transaction conflict: Write conflict, retry the transaction. This transaction can be retried") }))

# ----------------------------------------- the constraints of the schema

# A unique index names its fields when the schema is known.
expect knowing(unique_reply) == Err(Server(Unique({ table: "owner", index: "owner_email_unique", fields: ["email"], value: "'ann@x'", record: "owner:ann", message: "Database index `owner_email_unique` already contains 'ann@x', with record `owner:ann`" })))
expect knowing(unique_pair_reply) == Err(Server(Unique({ table: "owner", index: "owner_age_city_unique", fields: ["age", "city"], value: "[30, 'oslo']", record: "owner:ann", message: "Database index `owner_age_city_unique` already contains [30, 'oslo'], with record `owner:ann`" })))
expect plain(unique_reply) == Err(Server(Index({ index: "owner_email_unique", value: "'ann@x'", record: "owner:ann", message: "Database index `owner_email_unique` already contains 'ann@x', with record `owner:ann`" })))

expect plain(assert_reply) == Err(Server(Assert({ table: "owner", field: "age", record: "owner:bob", value: "-1", condition: "$value >= 0", message: "Found -1 for field `age`, with record `owner:bob`, but field must conform to: $value >= 0" })))
expect plain(type_reply) == Err(Server(Type({ table: "owner", field: "age", record: "owner:bob", expected: "int", found: "'old'", message: "Couldn't coerce value for field `age` of `owner:bob`: Expected `int` but found `'old'`" })))
expect plain(check_reply) == Err(Server(Check({ table: "owner", name: "adult in town", message: "Error while processing event owner_check_adult_in_town: An error occurred: owner: adult in town" })))
# A check over two fields is the assert of one, and `Assert` is its error, with the condition.
expect plain(check_assert_reply) == Err(Server(Assert({ table: "owner", field: "city", record: "owner:eli", value: "'oslo'", condition: "IF $value = 'oslo' THEN string::contains($this.email, '@') ELSE true END", message: "Found 'oslo' for field `city`, with record `owner:eli`, but field must conform to: IF $value = 'oslo' THEN string::contains($this.email, '@') ELSE true END" })))
expect plain(referenced_reply) == Err(Server(Referenced({ record: "owner:ann", by: "pet:rex", message: "Cannot delete `owner:ann` as it is referenced by `pet:rex` with an ON DELETE REJECT clause" })))
expect plain(referenced_nested_reply) == Err(Server(Referenced({ record: "owner:cat", by: "visit.by.vet", message: "Error while processing event visit_by_vet_on_delete: An error occurred: owner:cat is referenced by visit.by.vet" })))

# The message of every error is the server's.
expect plain(check_reply).map_err(
	|e| match e {
		Server(s) => s.message()
		_ => ""
	},
) == Err("Error while processing event owner_check_adult_in_town: An error occurred: owner: adult in town")

# --------------------------------------------- messages, without a server

# A table and a key that SurrealDB escapes are in backticks (verified).
expect Schema.violation("m", "Found 'x' for field `a.city`, with record ``my t`:k3`, but field must conform to: $value != 'x'", []) == Assert({ table: "my t", field: "a.city", record: "`my t`:k3", value: "'x'", condition: "$value != 'x'", message: "m" })
expect Schema.violation("m", "Database index `my t_n_unique` already contains ['o', 1], with record ``my t`:`k:1``", []) == Index({ index: "my t_n_unique", value: "['o', 1]", record: "`my t`:`k:1`", message: "m" })
# A check whose name has `: ` is found by its event.
expect Schema.violation("m", "Error while processing event e_check_a_b: An error occurred: e: a: b", []) == Check({ table: "e", name: "a: b", message: "m" })
# A `THROW` in an event of the app's own is `Thrown`, and any other
# message is `Other`.
expect Schema.violation("m", "Error while processing event mine: An error occurred: no", []) == Thrown({ text: "no", message: "m" })
expect Schema.violation("m", "Found field 'extra', but no such field exists for table 'vet'", []) == Other({ kind: "Internal", message: "m" })
