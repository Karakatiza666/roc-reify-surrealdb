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
| 6 | Two statements that capture both name their values `$_1`, `$_2`. | Done on branch `gap1`: `then` and transactions renumber the slots of the second statement. | Library side: renumber per statement. Not a compiler gap. |
| 7 | Fixed in roc `reify` 1c5ff3af3d (the cut is now an edge in the definition identities; CACHE_VERSION 235). Cache crash: `roc test` with the cache after an edit to `Surreal.roc` once gave "a transplanted compile-time root differs from its evaluation". `--no-cache` avoided it. | Flaky local builds. | A bug report. |
| 8 | Fixed in roc `reify` 4ee22e3e48 (debug audits now expand aliases). A record with two different `Linked(X)` fields (for example `Linked(Site)` and `Linked(Carer)`) that must be `Cbor.Readable` crashes the compiler: "checked generated codec structural call disagreed". One `Linked`, the same one twice, or a projection of fields works. Present at HEAD ba5e2cb too. | A whole read row with two links cannot be read as a result (`.prepare({})`, `.ready()`, `select(\|k\| k)`). Workaround: select the fields. | A bug report. Repro with no library code: `analysis/repro/two_linked_readable.roc` (`roc test` on it). |
| 9 | Fixed in roc `reify` a58a97f64c (split results share their argument in uniqueness inference). In a `--opt=speed` build, `Str.with_ascii_uppercased` on a part of a text (from `split_on` or `trim`) changed the original text. The interpreter and `--opt=dev` were correct. | `replaces` names of a migration header came back in capitals, so a squashed file ran and was not recorded. The workaround `Migrate.upper` is removed (fix in `2bca002367`). | A bug report: an in-place change of a string slice that shares its buffer. Details: `migrations-design.md` 9.3. |

| 10 | Fixed on roc `e3d46ce14f` (the repro passes, and `paid_with` in `tests/CapturedTest.roc` compiles). Derived `==` between two union values that are not constants crashes the reifier when the union has 4 or more variants: "code reifier invariant: normalization broke an invariant of the normal form". With 3 variants, or with a literal on one side, it passes. | After gap 1, a filter that compares a field with a captured union (`\|o\| o.pay == p`) stops the build. Today `o.pay == o.other` crashes already. | A bug report. Repro: `analysis/repro/union_eq_four_variants.roc` (`roc test`, compiler `901d5f4824`). |

## Gap 1: design for the compiler

See also `gap1-capture-modes.md`: what changes in the library when the same lambda can capture a compile-time literal or a run-time slot (4 breaks, 7 degrades, the library and compiler rules that make both modes give the same result).

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
| R5 | The user must not see `Code.Bound`. The opt-in is the root's whole type (read through aliases) when it is `Code.Bound(a)` or a nominal type (`::` or `:=`) whose backing chain, through aliases and further nominals, reaches `Code.Bound(a)`. Example: `Prepared(out) :: Code.Bound(Try(Ready(out), Error))`. A type that only holds the nominal (`Try(Prepared(out), Error)`, a record, a list) is not an opt-in: a translator that can fail puts the `Try` inside, as section 10.1 already does. The site fills the `inputs` of the `Code.Bound` inside the nominal. The reason line of a refused capture names "a call that returns `Code.Bound`, or a type built on it", and the type the chain ended in. | Users see only `Prepared(out)` and write `session.run!(q)`. Small change: one stop test in root selection (`exprIsCodeBound`), one relaxed invariant in `bindInputSlots`, no new lowering. Try outside was rejected: after gap 1 the outer `Try` is fixed at compile time, so errors that depend on a captured value come out of `run!` anyway; many translators (shaders that cannot fail, codecs, results with warnings or partial success) have no top-level `Try`. Details: `gap1-r5-option-a.md`, `gap1-r5-try-ux.md`. |
| R6 | Types in the root are closed at the root, so a record literal from a lambda (`\|_\| { name: name }`) is fixed by the chain. | Removes gap 4. |
| R7 | A root in a generic function: one root per instantiation (monomorphic, as sites are now). A generic function can still refuse if this is costly, but then say so in the reason line. | Removes gap 5: query fragments over open rows. |
| R8 | A `Code.refuse` from any builder in the root stops the build, and the report points at the node in the user's lambda, as it does for top-level values today. | Errors move from run time to compile time for queries in functions. |
| R9 | A run-time value in a plain builder argument (not typed `Code`) stays refused. The reason line says to type that parameter as `Code(a)` (R12) or to read the value in a lambda. | Keeps the root fixed with no hidden boundary. |
| R10 | A root whose shape depends on a run-time branch (`if flag then q.filter(a) else q`) is refused, or each branch is its own root. | Same reason as R9. |
| R11 | The same function body called twice gives one root and one stored result. Each call fills its own `inputs`. | Cost: one translation per site, not per call. |
| R12 | Value slots. A parameter typed `Code(a)`, where `a` is not a function type, takes any expression of type `a`. The description is one node: a literal when the value is fixed at compile time (`limit(10)`, a top-level key), or one input slot that holds the whole value when it is not (`limit(page * size)`, `owners.id(key)`). The expression tree is not described: the program computes the value and sends it in the slot. An expression that reaches an intrinsic (a declaration with no body, such as `Text.lowercase`) cannot be computed by the program, fixed or not. The existing rule "exists only in reified code" (`docs/langref/reifying.md` "Code That Exists Only in Reified Code") already reports it at compile time. Its reason line can add: to evaluate it on the server, use a lambda. There is no exception for an expression made only of intrinsics: a value position always means the program's value (option A). Describing value expressions as trees (option B: a value as a lambda with no input) is a possible later extension of A, not part of it. A value slot follows the slot rules of section 10.1 (types, `Code.Binds` for opaque types). | Keys (`at`, `set_at`, `update_at`, `delete_at`), `limit`, `start` and parameter records in functions, with no `\|_\|` and no table scan. Roc is pure, so the described value and the evaluated value are the same. Whoever wants an expression tree (server-side evaluation) writes a lambda. |

### Library side, after the compiler change

| Change | Where |
| --- | --- |
| Builders keep their `Code` argument and remember `first_slot` and the slot types | `src/Surreal.roc` (`Query`, `Selected`, `Write`) |
| Arguments that can be run-time values take `Code(..)` (R12): the keys of `at`, `set_at`, `update_at`, `delete_at`, and `limit`, `start` | `src/Surreal.roc` |
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
| A captured value in `.limit(n)` | Refused, and the reason line names the lambda form. Superseded by R12: `limit` takes `Code(U64)`, and the value is a slot. |
| A refusal in the translator for a lambda in a function | Compile error at the lambda's source line. |

### Status of the library side (branch `gap1`, compiler `0aedb1ae00`)

| Change | Status | Where |
| --- | --- | --- |
| R5: `Prepared(out) :: Code.Bound(Try(Ready(out), Error))`, `Watch(out)` the same | Done. `checked()` gives the error early. `then`, `Transaction.then` and `Surreal.transaction` keep the first error. `send!` puts it in the ticket, `run!` and `await!` in the result | `src/Surreal.roc` (`Prepared`, `Watch`, `Ticket`) |
| Slots from `first_slot()` and the global index; `LET`s from `inputs()` at the terminal call | Done | `src/Surreal.roc` (`binds_of`, `ready_of`, `resolved`) |
| `then` and transactions renumber the slots of the second statement (gap 6) | Done. Slot marks in the text, `shifted` renumbers them. A quoted `'$_1'` is not a mark | `src/Translate.roc` (`slot_mark`), `src/Surreal.roc` (`shifted`, `join_statements`) |
| R12: keys of `at`, `set_at`, `update_at`, `update_at_by`, `delete_at` are `Code(Id(row))`; `limit` and `start` are `Code(U64)` | Done. A key slot of another table is an error in the statement | `src/Surreal.roc` (`key_of`, `count_text`) |
| `x IN $_k` for a list slot (L7) | Done. A list slot is `x IN $_1`. A list in the clause stays `list CONTAINS x`. The golden script changes in one line (`owners_at`), and check.py agrees | `src/Translate.roc` (`List.contains`) |
| B1: a slot in a schema clause | A compile error. The compiler refuses the capture, because the chain ends in `Defined`. `stored_graph` also refuses a slot with `Code.refuse_at` | `tests/refusals/schema_capture.roc` |
| B3: bind `Duration`, `TimeKey`, the geometries, `U128` | Done. Verified on SurrealDB 3.3.4 | `src/Translate.roc` (`captured`, `geojson`), `tests/TranslateTest.roc` |
| B4: `==` on a captured union of 4 variants | Holds on `e3d46ce14f`. Verified on SurrealDB 3.3.4 | `tests/CapturedTest.roc` (`paid_with`) |
| L4: slot types checked at compile time | Done for `Link`, a database function, a function, an opaque type without `Code.Binds` | `src/Surreal.roc` (`keyed_slots`), `tests/refusals/captured_link.roc` |
| Remove `select_where`, `select_where_with`, `bind_captured` | Done. `Query.filter_with(exts, f)` replaces `select_where_with` | `src/Surreal.roc` |

### Results of the acceptance tests

| Test | Result | Where |
| --- | --- | --- |
| `cheaper_than(0.9)` and `cheaper_than(2.0)` | Pass. The same text, `LET $_1 = 0.9dec` and `LET $_1 = 2.0dec`. The proof of one translation is the text; there is no translator counter | `tests/CapturedTest.roc:46` |
| Two sites in one chain | Pass. `$_1` in `WHERE`, `$_2` in the projection | `tests/CapturedTest.roc:55` |
| A captured record with an optional field | Pass. The same text as `bind_captured` gave | `tests/CapturedTest.roc:64` |
| `set_at` with `\|_\| { name: name }` | Pass, with no annotated helper | `tests/CapturedTest.roc:70` |
| A captured value in `.limit(n)` | Changed by R12: it works, `LIMIT $_2 START $_1` | `tests/CapturedTest.roc:83` |
| A refusal in the translator for a lambda in a function | Pass. A compile error at the line of the lambda | `tests/refusals/run.sh` |

### Compiler bugs found during the library work

Compiler `0aedb1ae00` (branch `reify`). All workarounds in this table are removed from the library, except where the table says "Kept".

| Bug | Status | Workaround | Repro |
| --- | --- | --- | --- |
| A generic `Code(a)` with a run-time value crashes the compiler | Fixed in `e848b71fad` and `68a3fc8dfd` (R7: one instance per closing type) | None was needed. The library has no generic `Code(a)` parameter | `analysis/repro/r12_generic_value_crash.roc` passes |
| A literal key in place in a top-level value (`vets.at(vets.id("tia"))`) is "cannot bind this value" | Fixed in `e848b71fad` and `34e49ded42` | Removed: the constants `Surreal.Id.({ table, key })` in `examples/main.roc`, `examples/client.roc`, `tests/PreparedTest.roc`, `tests/QueriesTest.roc`, `tests/RefactoredTest.roc`. The golden script is the same | `analysis/repro/r12_inline_literal.roc` passes |
| A key from a method of an opaque type (`vets.id("tia")`) is "cannot compute this value" | Fixed in `e848b71fad` | Removed, as above | `analysis/repro/r12_opaque_method_value.roc` passes |
| A fold with a nested closure in `Surreal.transaction` panics: "instantiation unified a primitive type with a non-primitive type" | Fixed in `4cdaae9e6b` (upstream monotype bug, roc #12936) | Removed: the top-level helpers `appended`, `joined_parts`, `pair_of`. `tests/CapturedTest.roc` (`all_three`), `HttpTest` and `ErrorTest` pass | The CLI test `RestoredClosureOfGeneralizedLocal` in the compiler |
| The `NativeProcCompiler.zig:356` panic (`putNoClobber`) in `examples/monitoring.roc` and `tests/QueriesTest.roc` | Fixed in `ede4a2e442` (upstream layout bug, roc #12927) | None. `QueriesTest` (544 tests) and `monitoring.roc` (check.py) pass | The CLI test `RecursionBoxBesideExplicitBox` in the compiler |
| `Opq.({ name })` gives "invalid nominal type": `{ name }` is read as a block of type `Str`, not as a record | Open. It may be the grammar, not the reifier | Kept: write `Opq.({ name: name })` | `analysis/repro/nominal_record_shorthand.roc` |
| A chain in place in an effectful body (`main!`) cannot read a value of that body: "reified function captures a value" | Open (as documented in `docs/queries.md`) | Kept: a function of its own, as `shift_at` in `examples/client.roc` | Change `shift_at(first.id)` to `shifts.at(first.id).ready_one()` in `examples/client.roc` |
| Gap 9: `Str.with_ascii_uppercased` on a part of a text changed the whole text with `--opt=speed` | Fixed: the squash `2bca002367` holds all of `a58a97f64c` (only the SHA is not an ancestor). A `--opt=speed` probe of `Surreal.migration` with `replaces` gives the names unchanged on `0aedb1ae00` | Removed: `Migrate.upper` | None on this compiler |

### Test results on `0aedb1ae00`

| Run | Result |
| --- | --- |
| `scripts/all_tests.sh` (MemoryMax=16G) | Pass, exit 0. No run hit the memory cap |
| `roc test`, 20 files (`src/main.roc`, `examples/migrate.roc`, 18 `tests/*Test.roc`) | 5202 tests pass |
| `tests/refusals/run.sh` | 2 of 2 refused at the expected line |
| `tests/check.py` on SurrealDB 3.3.4 | 194/194 blocks agree |
