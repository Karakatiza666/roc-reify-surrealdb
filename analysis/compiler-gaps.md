# Compiler gaps found during the ORM work

Source: an implementation attempt of "captured values in all clause builders" (limit 4 of `report-1.md`), on the reify compiler at `e9b1b93db7`. The attempt added `_bound` twins of 11 builders (`filter_bound(Surreal.bind(|m| m.unit_price < limit))`). It worked, but the decision was to not merge it and to fix the compiler instead. The patch is kept at the path below for reference.

Patch: `/tmp/claude-1000/-home-george-dev-Karakatiza666-roc-reify-surrealdb/06c145ca-6881-4ee7-9914-84594cf5f10a/scratchpad/w4-dropped.patch` (temporary folder; copy it if needed).

| # | Gap | Effect on the library | What the compiler would need |
| --- | --- | --- | --- |
| 1 | Captures are bound only at the call that takes the lambda, and only when that call returns a `Code.Bound`. That call runs at compile time, so its other arguments must be fixed then. | `filter`, `select`, `update_by` etc. cannot take a lambda that captures a value: "reified function captures a value". | The chain root: see "Gap 1: design for the compiler" below. |
| 2 | The result of a binding call may hold no function type, even a phantom one: `Bound(Cap(U16 -> U16))` is refused, `Cap(Arrow(U16, U16))` works. | A `Query` holds closures, so `filter` cannot return a `Code.Bound(Query)`. | Allow phantom function types in a bound result, or gap 1. |
| 3 | `Code.Bound` is a builtin with no methods. | A builder that returns it breaks the method chain. | Gap 1 makes this moot. |
| 4 | A record literal returned from a bound lambda keeps an open type: `Surreal.bind(\|_\| { name: n })` fails with "a translator result whose type the call does not fix" (`rootContainsIdentityVariables`, `src/check/checked_artifact.zig:41349`). | A patch with captures needs an annotated helper function. | Close the record type at the binding call, as a plain `Code` place does. |
| 5 | A generic function cannot bind inputs: "cannot bind inputs in a generic function". | Query fragments over open rows cannot capture values. | Binding in generic functions, or gap 1. |
| 6 | Two statements that capture both name their values `$_1`, `$_2`. | `Prepared.then` and transactions refuse two different values under one name (as `bind_captured` already does). | Library side: renumber per statement. Not a compiler gap. |
| 7 | Cache crash: `roc test` with the cache after an edit to `Surreal.roc` once gave "a transplanted compile-time root differs from its evaluation". `--no-cache` avoided it. | Flaky local builds. | A bug report. |
| 8 | A record with two different `Linked(X)` fields (for example `Linked(Site)` and `Linked(Carer)`) that must be `Cbor.Readable` crashes the compiler: "checked generated codec structural call disagreed". One `Linked`, the same one twice, or a projection of fields works. Present at HEAD ba5e2cb too. | A whole read row with two links cannot be read as a result (`.prepare({})`, `.ready()`, `select(\|k\| k)`). Workaround: select the fields. | A bug report. Repro with no library code: `analysis/repro/two_linked_readable.roc` (`roc test` on it). |
| 9 | In a `--opt=speed` build, `Str.with_ascii_uppercased` on a part of a text (from `split_on` or `trim`) changed the original text. The interpreter and `--opt=dev` were correct. | `replaces` names of a migration header came back in capitals, so a squashed file ran and was not recorded. Workaround: `Migrate.upper` builds a new string (`src/Migrate.roc`). | A bug report: an in-place change of a string slice that shares its buffer. Details: `migrations-design.md` 9.3. |

## Gap 1: design for the compiler

Status: proposal for the compiler agent. Compiler terms are from `roc-reify-proposal.md` section 10.1 and `docs/reifying-overview.md` lines 114-126 in the compiler repository.

### Goal

```roc
cheaper_than = |limit| Surreal.from(medications).filter(|m| m.unit_price < limit).ready()

readings_above = |least| Surreal.from(vitals).filter(|v| v.pulse >= least).select(|v| { pulse: v.pulse, note: "high" }).order_by(|r| r.pulse, Desc).ready()

rename = |key, name| owners.set_at(owners.id(key), |_| { name: name }).ready()
```

| Stage | Work |
| --- | --- |
| Compile time, once per site | The whole chain runs. Each builder reads its lambda's graph. The translator writes `SELECT .. WHERE unit_price < $_1`, with one placeholder per slot. |
| Run time, each call | The program collects the captured values (`limit`) as `Code.Value`s. The library binds them as `LET $_1 = ..`. No translation runs. |

This is the capture-at-reify rule of today, with the root moved from "the call that takes the lambda" to "the chain that ends in the opt-in".

### Today and the change

| Item | Today (section 10.1) | Needed |
| --- | --- | --- |
| Compile-time root | The call that takes the lambda, when its declared result is `Code.Bound(a)` | The smallest enclosing expression whose type is the opt-in (`Code.Bound(a)`, or see R5). In the goal it is the whole chain up to `.ready()`. |
| Values inside the root | Not applicable: the root is one call | Any value, functions included (a `Query` holds closures). They exist only while the compiler evaluates the root. |
| Sites per root | One. Two give "a call that binds the inputs of two sites" | Many: `filter`, `select` and `set_at` lambdas in one chain, each with its own slots |
| Other arguments | Must be fixed at compile time | The same rule for each call in the chain: every argument outside a lambda description is fixed (`medications`, `Desc`, a literal). Only lambda captures are slots. |
| Stored result | Holds no function | R4 |

### Requirements

| # | Requirement | Why |
| --- | --- | --- |
| R1 | Root selection: walk out from the lambda site through the calls that take its result as an argument, or as the receiver of a method call, and stop at the first expression whose type is the opt-in. Refuse when there is none, with a reason line that names the opt-in. | Builders keep their plain types (`Query -> Query`). Only the terminal call is marked. |
| R2 | One root can hold many sites. Number the slots across the root, in a fixed and documented order (proposal: source order of the sites, then the slot order of each site). Give each `Code` value its first slot index, for example `code.first_slot() : U64`. This value is not part of `==` or `to_hash`, so the cache key stays the same. `Code.Bound.inputs()` gives the slots of all sites in that order. | The library writes `$_{k}` with the global index, and the values must line up with it. |
| R3 | One captured name read in two sites (`limit` in `filter` and in `select`) can be two slots. Merging them into one slot is optional. | Simple first. |
| R4 | The stored root result may hold a function when the function is fixed at compile time: a top-level function, or a lambda whose captures are all fixed. Today `Prepared(out)` holds `read : List(Outcome) -> Try(out, Error)`, a decoder of fixed shape. If this is too hard, the library can return data only (statement text, count, slot types) and build `read` at run time from the result type. Then R4 is not needed. | `Prepared` is the natural root result. |
| R5 | The user must not see `Code.Bound`. Option A: the opt-in also accepts a nominal type whose backing is `Code.Bound(a)`, for example `Prepared(out) :: Code.Bound(..)`, so `ready` returns `Try(Prepared(..), Error)`. Option B: `ready` returns `Code.Bound(Try(Prepared(..), Error))` and `Session.run!` takes it. Option A is preferred. | Users write `session.run!(cheaper_than(0.9))` as they do now. |
| R6 | Types in the root are closed at the root, so a record literal from a lambda (`\|_\| { name: name }`) is fixed by the chain. | Removes gap 4. |
| R7 | A root in a generic function: one root per instantiation (monomorphic, as sites are now). A generic function can still refuse if this is costly, but then say so in the reason line. | Removes gap 5: query fragments over open rows. |
| R8 | A `Code.refuse` from any builder in the root stops the build, and the report points at the node in the user's lambda, as it does for top-level values today. | Errors move from run time to compile time for queries in functions. |
| R9 | A run-time value outside a lambda (for example `.limit(n)` or `.prepare({ least })` with a parameter `n`) stays refused, with a reason line that says to read it in a lambda. A later extension can make such an argument a slot too. | Keeps the root's shape fixed. |
| R10 | A root whose shape depends on a run-time branch (`if flag then q.filter(a) else q`) is refused, or each branch is its own root. | Same reason as R9. |
| R11 | The same function body called twice gives one root and one stored result. Each call fills its own `inputs`. | Cost: one translation per site, not per call. |

### Library side, after the compiler change

| Change | Where |
| --- | --- |
| Builders keep their `Code` argument and remember `first_slot` and the slot types | `src/Surreal.roc` (`Query`, `Selected`, `Write`) |
| `ready`, `prepare`, `live` and the writes' terminal calls return the opt-in type (R5) | `src/Surreal.roc:2149`, `2228`, `2348` and the write terminals |
| `$_{k}` from the global slot index; `LET`s from `inputs()`, as `bind_captured` does now | `src/Surreal.roc:2798` |
| Remove `select_where`, `select_where_with` and `bind_captured` | `src/Surreal.roc:2754-2798` |
| `Prepared.then` and transactions renumber the slots of the second statement | gap 6 |

### Acceptance tests

| Test | Expect |
| --- | --- |
| `cheaper_than(0.9)` and `cheaper_than(2.0)` | The same stored statement text. Inputs `[Dec(0.9)]` and `[Dec(2.0)]`. The translator runs once (count it in a test translator). |
| Two sites in one chain, each with a capture | `$_1` in WHERE and `$_2` in the projection. The inputs are in that order. |
| A captured record with an optional field (`owner_at(place)`, today `examples/main.roc:434`) | Same output as `bind_captured` gives today. |
| `set_at` with `\|_\| { name: name }` | Compiles with no annotated helper. |
| A captured value in `.limit(n)` | Refused, and the reason line names the lambda form. |
| A refusal in the translator for a lambda in a function | Compile error at the lambda's source line. |
