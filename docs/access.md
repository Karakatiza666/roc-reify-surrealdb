# Record users and permissions

This page shows how people sign up and sign in to your database, and how table and field permissions limit what each person reads and writes. A person who signs in is a record user: one row of a table, such as `user`. A system user (the `Root` login) is not a record user.

The page uses the example of `examples/client.roc`: a `user` table, a `memo` table with an `owner` link, and the access method `account`. The words clause and mirror function are in [Words used in these pages](getting-started.md#words-used-in-these-pages).

| You want | Call | Section |
| --- | --- | --- |
| Let people sign up and sign in | `Surreal.access(name)`, then `define(..).done()` | [Define an access method](#define-an-access-method) |
| Open a session as a record user | `accounts.sign_up(..)`, `accounts.sign_in(..)`, `Token(..)` | [Sign up and sign in](#sign-up-and-sign-in) |
| Limit the rows of a table | `permit`, `permit_full` | [Table permissions](#table-permissions) |
| Limit one field | `permit_field`, `deny_field` | [Field permissions](#field-permissions) |
| Read the signed in user in a clause | `users.auth()`, `Surreal.Auth.access()` | [The record user in a clause](#the-record-user-in-a-clause) |
| See what each user gets | A table of real results | [What happens for each user](#what-happens-for-each-user) |

## Define an access method

An access method says how a record user signs up and signs in. You write three things: the variables of each login, the signup, and the signin. All three are typed Roc.

```roc
# Fragment: uses `users` (a `Surreal.Table(User)`) from examples/client.roc.
Credentials : { email : Str, pass : Str }

accounts : Surreal.Access(Credentials, Credentials)
accounts = Surreal.access("account")
```

The type `Surreal.Access(up, on)` holds two records. `up` is the variables of a signup. `on` is the variables of a signin. The annotation fixes them, as the annotation of a table fixes its row type.

`accounts.define(users, signup, signin)` makes the definition. You give the table of the users and two functions.

| Argument | Type | What it is |
| --- | --- | --- |
| `signup` | `up -> new` | The new row without its `id`. It becomes `CREATE user CONTENT { .. }` |
| `signin` | `on, row -> Bool` | A condition over the variables and the row, as `filter_by`. It becomes `SELECT * FROM user WHERE ..` |

Each variable is a `$name` of the same name. The compiler checks both functions against the row type. A variable that the function reads and the record does not have is a type error. The signup must give every field of the row except `id`. This includes the optional fields.

The signup can call `Surreal.Hash.argon2` to store a hash and not the password. The signin calls `Surreal.Hash.argon2_matches(hash, password)`. See [Hash](functions.md#hash). `Hash.argon2` makes a new salt on each call, so only a signup, a default, a computed field or an update can call it. A signin that calls it gives `Unsupported`.

Two calls set how long a login lasts. Both take a `Duration` such as `Surreal.Time.hours(1)`. `done()` gives a `Defined` for the list of `Surreal.schema`.

| Call | SurrealQL | Without the call |
| --- | --- | --- |
| `token_for(d)` | `DURATION FOR TOKEN 1h` | SurrealDB gives a token of 1 hour |
| `session_for(d)` | `DURATION FOR SESSION 12h` | A session has no end |

The duration is a literal in the largest units that fit (`1h`, `12h`, `1d`, `1h30m`).

```roc
# Fragment: uses `users` and `accounts` from above.
accounts.define(users, |v| { email: v.email, pass: Surreal.Hash.argon2(v.pass) }, |v, u| u.email == v.email and Surreal.Hash.argon2_matches(u.pass, v.pass))
	.token_for(Surreal.Time.hours(1))
	.done()
```

From `examples/client.roc`, `account_schema`. A real run prints:

```surql
DEFINE ACCESS OVERWRITE account ON DATABASE TYPE RECORD SIGNUP (CREATE user CONTENT { email: $email, pass: crypto::argon2::generate($pass) }) SIGNIN (SELECT * FROM user WHERE (email = $email) AND crypto::argon2::compare(pass, $pass)) DURATION FOR TOKEN 1h;
```

The server runs the signup and the signin as a system user. The permissions of the table do not apply to them. Define the access method in the same `Surreal.schema` call as its table (see [Build the schema](schema.md#build-the-schema)).

## Sign up and sign in

`accounts.sign_up(scope, vars)` and `accounts.sign_in(scope, vars)` make a `Surreal.Login`. `scope` is the record `{ ns, db }`. `vars` is a record of the type `up` or `on`. Each field is written as a parameter of a query is, so a field may be a `Dec`, an `Id`, a `Datetime` or any other type that a row may hold. The names that a parameter may not have are refused. Give the login to `Session.open!` (see [Log in](sessions.md#log-in)).

```roc
# Fragment: uses `accounts`, `scope`, `transport` from examples/client.roc.
ann : Credentials
ann = { email: "ann@roc", pass: "ann's secret" }

session = Surreal.Session.open!(transport, accounts.sign_up(scope, ann)).map_err(Str.inspect)?
```

From `examples/client.roc`, `ann`. A signup makes the row and signs in as it. A signin signs in as an existing row. Both give a session with a token.

| Call | Gives | Use |
| --- | --- | --- |
| `session.token()` | `Try(Str, [NoToken])` | The token of a record user. A system user has no token |
| `Token(token)` | A `Login` | Open a new session for the user of a token (for example in the next run of an app) |
| `session.invalidate!()` | `Try(Session, Error)` | End the session as that user |

After `invalidate!`, the session is no one. Each request is refused with `Denied` until you open a new session. The token stays valid until it expires: SurrealDB keeps no list of tokens, so `invalidate!` cannot end a token. Do not hand a token to code that you do not trust.

The calls give the same results on a WebSocket and over HTTP. A WebSocket signs in once and the server keeps the login of the socket. Over HTTP each post carries the token (see [Use HTTP](sessions.md#use-http)).

A refused login is `Err(Server(Denied(message)))` from `Session.open!` (see [Server errors](errors.md#server-errors)). The server does not say why, so every cause is `Denied`:

| Cause | The message of `Denied` in a real run |
| --- | --- |
| Wrong password, or no such user | `No record was returned` |
| A signup that the `SIGNUP` query refuses, such as an email that a unique index holds | `The record access signup query failed` |
| A token that does not verify | `There was a problem with authentication` |
| Any request after `invalidate!` | `Anonymous access not allowed: Not enough permissions to perform this action` |

Match on the tag, not on the text.

## Table permissions

A table permission says which rows a record user may read and write. Add it to the `define()` of the table.

| Call | Takes | SurrealQL |
| --- | --- | --- |
| `permit(actions, cond)` | A list of `Select`, `Create`, `Update`, `Delete`, and `row -> Bool` | `FOR select, update WHERE ..` |
| `permit_full(actions)` | A list of actions | `FOR select FULL` |

The condition is a clause: a Roc function that you can also call on your own rows. It reads the row and the signed in user (see [The record user in a clause](#the-record-user-in-a-clause)).

```roc
# Fragment: uses `memos` and `users` from examples/client.roc.
memos.define()
	.permit([Select], |m| m.owner.id() == users.auth() or m.shared)
	.permit([Create, Update, Delete], |m| m.owner.id() == users.auth())
	.done()
```

From `examples/client.roc`, `account_schema`. The result in SurrealQL:

```surql
DEFINE TABLE OVERWRITE memo SCHEMAFULL PERMISSIONS FOR select WHERE (owner = $auth.id) OR shared, FOR create, update, delete WHERE owner = $auth.id;
```

| Rule | Detail |
| --- | --- |
| No permission in the schema | The table keeps the default of SurrealDB. The other examples have no permission, so their scripts do not change |
| Some permission in the schema | The package names every action. An action that no permission names is `NONE`. A record user cannot do it |
| An action in two permissions | `Err(BadSchema("`memo` has two permissions for `select`"))` |
| A system user | Not checked. A `Root` session ignores every permission |

A write that the permission refuses is not an error. The statement leaves out the rows that its permission does not keep, and gives the rest. See [What happens for each user](#what-happens-for-each-user).

## Field permissions

A field permission limits one field. A field with no permission is `FULL`, the default of SurrealDB for a field.

| Call | Takes | SurrealQL |
| --- | --- | --- |
| `permit_field(path, actions, cond)` | A field, a list of actions, `row -> Bool` | `PERMISSIONS FOR update WHERE ..` on the field |
| `deny_field(path, actions)` | A field, a list of actions | `PERMISSIONS FOR select NONE` on the field |

`path` is a function such as `|m| m.text`. It must read one field. A field takes `Select`, `Create` and `Update`. `Delete` gives `BadSchema` with the message that the table decides. A field permission does not change the permission of the table.

```roc
# Fragment: uses `users` and `memos` from examples/client.roc.
users.define().deny_field(|u| u.pass, [Select]).done()
memos.define().permit_field(|m| m.text, [Update], |m| !m.shared).done()
```

From `examples/client.roc`, `account_schema`. The SurrealQL:

```surql
DEFINE FIELD OVERWRITE pass ON user TYPE string PERMISSIONS FOR select NONE;
DEFINE FIELD OVERWRITE text ON memo TYPE string PERMISSIONS FOR update WHERE !shared;
```

A field that a select may not read is not in the row. Reading it as a required field fails. A real run of `Surreal.from(users).select(|u| u)` as a record user gives:

```text
Err(Decode({ message: "a map has no field `pass`", path: "" }))
```

Do one of two things. Select the other fields (`select(|u| { email: u.email })`). Or declare the field optional (`pass ?: Str`). The row then reads with the field left out, and the denied field is `<missing>`. Read an optional field in the path with `.?`, as in `deny_field(|u| u.?pass, [Select])`. A real run of the whole row as Ann gives `{ email: "ann@roc", id: "..", pass: <missing> }`.

## The record user in a clause

Three intrinsics read the session on the server. They work in a table permission, and in a query, a write or a live query that a record user runs. They exist only inside a clause (see [Mirror functions and intrinsics](functions.md#mirror-functions-and-intrinsics)). Outside a clause they are a compile error.

| Call | Type | SurrealQL | Value |
| --- | --- | --- | --- |
| `users.auth()` | `Id(User)` | `$auth.id` | The row of the signed in user. A system user gives `NONE` |
| `Surreal.Auth.access()` | `Str` | `$access` | The name of the access method. `NONE` for a system user |
| `Surreal.Auth.expires()` | `I64` | `$token.exp` | When the token ends, in seconds since 1970 |

`users.auth()` is an `Id` of the table. A link compares with it (`m.owner.id() == users.auth()`), and so does the key of a row (`users.id(u.id) == users.auth()`). See [Ids](links-and-graphs.md#ids). The three calls are also in [Auth](functions.md#auth).

```roc
# Fragment: uses `memos` and `users` from examples/client.roc.
mine = Surreal.from(memos).filter(|m| m.owner.id() == users.auth()).select_value(|m| m.id).ready()
```

From `examples/client.roc`, `mine`. The SurrealQL:

```surql
SELECT VALUE record::id(id) FROM memo WHERE owner = $auth.id;
```

A system user has no `$access`. A query that reads `Surreal.Auth.access()` as `Str` gives `Decode` for a `Root` session, because `NONE` is not text.

## What happens for each user

A real run on SurrealDB 4.0.1 with the schema of `examples/client.roc`. Ann and Bob signed up. Ann owns `ann_note` (private) and `ann_board` (shared). Bob owns `bob_note`. The run is the same on a WebSocket and over HTTP.

| Step | Result |
| --- | --- |
| Ann selects `memo` | `ann_board` and `ann_note` |
| Bob selects `memo` | `ann_board` and `bob_note`. The permission leaves out `ann_note`. No error |
| Bob updates or deletes `ann_board` | `Ok([])`. Bob may read it and may not write it. No error |
| Bob creates a memo whose `owner` is Ann | `Server(Assert({ table: "memo", field: "owner", .. }))`: the `record::exists` check of the link runs as Bob, and Bob cannot read Ann's row of `user` |
| Ann updates the text of `ann_board` | `Ok` with the row and the old text. The field permission leaves the field out of the update |
| Ann updates the text of `ann_note` | `Ok` with the new text |
| Bob creates a `notice`, a table with `permit_full([Select])` only | `Ok([])`. The `create` is `NONE` |
| Bob sends `DEFINE TABLE x` as raw text | The statement has status `ERR`: `IAM error: Not enough permissions to perform this action` |
| Ann selects `Surreal.Auth.access()` | `["account", "account"]`, one value for each row |
| Ann signs in with a wrong password | `Server(Denied("No record was returned"))` |
| Ann signs up again with her email | `Server(Denied("The record access signup query failed"))` |
| Any statement after `invalidate!` | `Server(Denied("Anonymous access not allowed: .."))`, also a write |
| `Token(token)` of Ann, after her session ended | A session of Ann. It reads her two memos |
| `Token("nonsense")` | `Server(Denied("There was a problem with authentication"))` |

A write that a permission refuses gives no row and no error. Check the rows that come back. If you need an error, make the refusal an `Assert` or a `Check` (see [Constraints](schema.md#constraints)).

## Limits

| Limit | What to do instead |
| --- | --- |
| No access method `ON NAMESPACE` or `ON ROOT`, no `TYPE JWT`, no `TYPE BEARER`, no `WITH JWT` keys, no `AUTHENTICATE` clause | Send the `DEFINE ACCESS` text with `Surreal.Unchecked.query!` (see [Raw SurrealQL](advanced.md#raw-surrealql)) |
| The signup is one `CREATE` of one row, and it gives every field of the row except `id` | Give a value for each optional field, or keep optional fields out of the users table |
| The signin may not call `Hash.argon2` | Use `Hash.argon2_matches` to compare |
| A write that a permission refuses gives no row and no error | Read the result rows. Use `assert` or `check` for an error |
| `invalidate!` does not end the token | Use a short `token_for` |
| A field that a select may not read breaks a required field | Mark it `?:` or do not select it |
| A system user is not checked by permissions | Test permissions with a record user session |
| `users.auth()` and the `Surreal.Auth` calls exist only in a clause | Call them in a clause, not in plain Roc code |
