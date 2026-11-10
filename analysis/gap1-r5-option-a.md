# Gap 1, R5 option A: a nominal type backed by `Code.Bound` as the opt-in

Question: is option A of R5 (`compiler-gaps.md` "Gap 1: design for the compiler") valid, and is R5 blocked on a design question?

State: library HEAD 0.0.2 (`1997451`). Compilers: `reify` binary `debug-1c5ff3af` (`/home/george/dev/Karakatiza666/roc/zig-out/bin/roc`) and the `gap1` worktree binary `debug-384cd926` (`/home/george/dev/Karakatiza666/roc-gap1/zig-out/bin/roc`, built at `gap1` HEAD `384cd92652`). Probe files: `/tmp/claude-1000/-home-george-dev-Karakatiza666-roc-reify-surrealdb/06c145ca-6881-4ee7-9914-84594cf5f10a/scratchpad/r5/` (not committed).

## Answer

| Item | Verdict |
| --- | --- |
| Is option A valid? | Yes, with one condition: the nominal must be the type of the root itself, so the `Try` goes inside it: `Prepared(out) :: Code.Bound(Try(Ready(out), Error))`. The R5 text today says "`ready` returns `Try(Prepared(..), Error)`", with the `Try` outside. That shape is not a small change: the compiler must look into a `Try` (or into any type) for the nominal, and the site must rebuild only the `Ok` arm. |
| Compiler cost of A' (nominal is the root type) | Small and local. Two functions read the opt-in: `exprIsCodeBound` (`roc-gap1/src/check/code_roots.zig:335-351`, stops at the first nominal and checks only the builtin `Code.Bound`) and `bindInputSlots` (`roc-gap1/src/postcheck/boxy/body.zig:4481-4525`, which already unwraps every nominal layer with `structuralType`, `body.zig:9617-9621`, and only refuses a non-nominal type). Plus the reason lines that name `Code.Bound` (`src/check/report.zig:6502-6721`). |
| Library cost | Medium, and mostly needed for gap 1 anyway: every `Try(Prepared(x), Error)` becomes `Prepared(x)`; run-time combinations (`then`, `begin`, `transaction`) read `inputs()` into `lets` and build the result with `Code.Bound.of`; gap 6 renumbering. |
| Is R5 blocked on design? | Mostly no. Option A' is a queue-order item. One real design decision is open: where the `Try` sits (D1 below). If the user picks "Try inside", nothing in the compiler design is open. If the user insists on "Try outside", that is a new design (a rule for "a type that contains the nominal"), and I recommend against it. |
| Can the library start now? | Yes. Option B works on the `gap1` binary (probe B). A transparent alias `Prepared(out) : Code.Bound(..)` is accepted as the opt-in today (probe A3), but it has no methods, so it is only a stopgap. Moving the `Try` inside `Prepared` is the same change for B and A', so the library can do it now and change one type line when A' lands. |

## Probes

All on the `gap1` binary unless the row says otherwise. Each probe: a `Query` that keeps closures, two `filter` lambdas that capture `limit`, a terminal `ready` that builds its result with `Code.Bound.of`.

| Probe | Shape of `ready`'s result | Result |
| --- | --- | --- |
| `B.roc` | `Code.Bound(Try(Stmt(U64), Error))` (option B) | Works: `SELECT * FROM meds WHERE [0+1] AND [1+1] inputs [11, 11]`, then `inputs [31, 31]` for the second call. One statement text, two input lists. |
| `B.roc` on `reify` (`1c5ff3af`) | same | Refused before gap 1 logic: "Code.Bound.of does not exist", "`first_slot` missing". Gap 1 is only on the `gap1` branch. |
| `B_phantom.roc` | `Code.Bound(Try(Stmt(x), Error))`, generic in `x`, used at `U64` and `Str` | Works (R7: one root per instantiation of a type parameter of the result). |
| `B_generic.roc` | the query `q` is a run-time parameter | Refused: "cannot bind inputs in a generic function". The cause is the run-time `q` (R9), not R5. |
| `A1.roc` | `Prepared(out) :: Code.Bound(Try(..))` (opaque nominal, Try inside) | Refused: "reified function captures a value ... no call in it returns a Code.Bound". Type checking passes. Expected: A' is not implemented. |
| `A4.roc` | `Prepared(out) := Code.Bound(..)` (transparent nominal) | Same refusal as A1. |
| `A2.roc` | `Try(Prepared(U64), Error)`, `Prepared :: Code.Bound({..})` (Try outside) | Same refusal. |
| `A3.roc` | `Prepared(out) : Code.Bound(Try(..))` (transparent alias) | Works, as B. `exprIsCodeBound` reads through aliases. No methods can be attached to an alias, so users would call `value()` and `inputs()`. |
| `A1_noroot.roc` | A1 type, no root: a top-level constant and a join made at run time with `Code.Bound.of` | Works. `inputs []`. `Str.inspect` gives `<opaque>`. |
| `eq.roc` | `P :: Code.Bound(Str).{ is_eq : _ }` | Refused at the use: "type does not support equality". `Code.Bound` has no `is_eq` (`roc-gap1/src/build/roc/Builtin.roc:24644-24661`). |
| `eq2.roc` | the same with a hand-written `is_eq` over `value()` and `inputs()` | Works (`Code.Value` has `is_eq` and `to_hash`, `Builtin.roc:24608-24625`). |

## Q1. Where the nominal sits

Today the `Try` is outside `Prepared` in every terminal call.

| Producer | Today (`src/Surreal.roc`) |
| --- | --- |
| `Query.ready`, `ready_one` | `2149`, `2158`: `Try(Prepared(List(row)), Error)` |
| `Totals.ready` | `2228`: `Try(Prepared(out), Error)` |
| `Selected.ready`, `Started.ready`, `Limited.ready` | `2348`, `2504`, `2527` |
| `Write.ready` | `2552` |
| `Query.ready_live`, `Selected.ready_live` | `2167`, `2425`: `Try(Watch(row), Error)` |
| `Prepared.then` | `2643`: `Prepared(a), Prepared(b) -> Try(Prepared(..), Error)` |
| `Transaction.commit` | `2677`: `Transaction(out) -> Prepared(out)` (no `Try`) |
| `Surreal.transaction` | `2685`: `List(Prepared(out)) -> Try(Prepared(List(out)), Error)` |
| `Plan.prepare` | `1888`: `Try(List(Prepared({})), Error)` |
| `Session.run!` | `3672`: `Session, Prepared(out) => { session, result : Try(out, Error) }` |

Two shapes for option A:

| | S1: Try outside, `Try(Prepared(out), Error)`, `Prepared :: Code.Bound(Ready(out))` | S2: Try inside, `Prepared(out) :: Code.Bound(Try(Ready(out), Error))` |
| --- | --- | --- |
| Opt-in rule | "A type that contains the nominal". Needs extra rules: which positions (only `Try`? any tag payload, record field, list item?), and what to do with two of them (`(Prepared(a), Prepared(b))`, `List(Prepared(a))`). | "The root type is the nominal" (after aliases). One check, as today. |
| Root selection (R1) | `exprIsCodeBound` must walk into the tag union. The call stays the root. | Unchanged walk. Only the stop test changes. |
| Site lowering | `bindInputSlots` must emit a `match` on the tag: rebuild the `Ok` payload's backing with the inputs, pass `Err` through. A new kind of lowering (tag union rebuild) in a debug-asserted invariant path. | `bindInputSlots` already unwraps nominals with `structuralType`. Only the invariant "did not return a nominal Code.Bound" (`body.zig:4489`) must accept a nominal whose backing chain reaches `Code.Bound`. |
| Generic roots (R7, Boxy bound requirements) | The requirement worker returns a `Try`, and its `bind_root_inputs` task must rebuild through the tag. | Same as `Code.Bound` today: the type parameter `out` sits inside the backing. |
| User: run it | `session.run!(cheaper_than(0.9)?)` or `.map_err(..)?` (as `examples/server.roc:140`). | `session.run!(cheaper_than(0.9))`. The translation error comes back as `result`. This is the line R5 promises; today it does not compile (it needs `?`). |
| User: `?` and `match` | `?` and `match` on the call, as today. | `cheaper_than(0.9).checked()?` (proposed method `checked : Prepared(out) -> Try(Prepared(out), Error)`) gives the same flow. `match prepared.checked() { .. }` in place of `match prepared { .. }`. |
| User: types | `Try(Surreal.Prepared(List(Med)), Surreal.Error)` in every signature (`examples/main.roc:494`, `500`, `506`, `703`, `710`, `716`). | `Surreal.Prepared(List(Med))`. Shorter. |
| Errors made at run time (`Table.create` with a run-time row, `then` with a name clash) | `Err` outside, as today. | `Err` inside: `Prepared.(Code.Bound.of(Err(e)))` (probe `A1_noroot.roc`). `then`, `begin`, `transaction` keep the first `Err`. |

Recommendation: S2. Rule text is in "Proposed R5 text". S2 is simpler for the compiler (no new lowering) and for users (no `?` before `run!`), and the shape is the same for option B, so the library change is not wasted.

## Q2. Values that no root makes

| Value | How it is made | Inputs |
| --- | --- | --- |
| Top-level chain with no run-time capture (`everything = meds.ready()`) | A compile-time constant. No pending site, so no root that binds inputs (`code_roots.zig:121-150`). | `[]`. Probe `A1_noroot.roc`. |
| Chain in a function with no capture | Hoisted as a constant, as today. | `[]` |
| `Table.create(t, row)`, `insert`, `merge_at` with a run-time value outside a lambda | Runs at run time (no lambda site, so no root). Builds `Prepared.(Code.Bound.of(..))`. | `[]`. Values in `Statement.lets` as today. |
| `Prepared.then`, `Prepared.begin`, `Transaction.then`, `Transaction.commit`, `Surreal.transaction` | Library code at run time. | Must be `[]` in the result: the only constructors are `Code.Bound.of : a -> Bound(a)` and `Code.bound : Code(_fn), a -> Bound(a)` (`roc-gap1/src/build/roc/Builtin.roc:24660`, `24697`), and both give `inputs: []`. No function makes a `Bound` with inputs. So the join must turn each operand's `inputs()` into `lets` (by `Ql.literal` of `Translate.captured(slot type, value)`) and store them in the value. |
| `Plan.prepare`, migration statements, schema | Data only. L3 (`gap1-capture-modes.md`) refuses slots there. | `[]` |

Joining and renumbering (gap 6):

| Step | Rule |
| --- | --- |
| Slot names | Each root numbers its slots from 0 (`first_slot`, `Builtin.roc` "first_slot" doc). Two roots both write `$_1`. `then_statement` (`src/Surreal.roc:5000-5019`) refuses two values under one name. |
| Proposal | Keep the statement text of a root as a template: `List([Text(Str), Slot(U64)])`, made by the translator at compile time. `Prepared` holds the template, the slot types (`Code.Ty` from `graph.slots()`), and the `lets` already resolved. |
| Resolve | `statement()` renders `Slot(k)` as `$_{k + offset}` and adds one `LET` per input. A value from a root has `offset = 0`. |
| Join | `then(a, b)`: render `a` with offset 0, `b` with offset `slots(a)`, concatenate `lets`, build `Prepared.(Code.Bound.of(..))` with no inputs. No text replace, so no risk from a quoted `$_1` (`gap1-capture-modes.md`, "Statement.inlined" row). |
| Invariant | `inputs()` is non-empty only on a value fresh from a root. Every method of `Prepared` reads both `inputs()` and the stored `lets`, so a joined value and a root value behave the same. |

## Q3. An opaque nominal over the builtin opaque `Code.Bound`

| Item | Finding | Evidence |
| --- | --- | --- |
| Construct and read inside the library | `Prepared.(Code.Bound.of(x))`, `\|Prepared.(b)\| b.value()`, `b.inputs()` all type check and run. | `A1_noroot.roc` |
| Derived `is_eq`, `to_hash` | Not possible: `Code.Bound` derives nothing. `Prepared` has none today either (it holds `read`, a function, `src/Surreal.roc:2605`). A hand-written `is_eq` over `value()` and `inputs()` works when the value has `is_eq`. | `eq.roc`, `eq2.roc` |
| `Str.inspect` | `<opaque>`. Same as `Prepared` today (opaque, `::`). | `A1_noroot.roc` |
| CBOR encode and decode | `Prepared` has no `encoder_for` or `parser_for` today (`grep` of `src/Surreal.roc`). Not needed: a `Prepared` is not sent or stored as data. | `src/Surreal.roc:2605-2655` |
| `where` clauses on `out` | They are on the producing functions (`ready ... where [row.Cbor.Readable(errs)]`, `2149`), not on the type. No change. | `src/Surreal.roc:2149` |
| Opacity to users | A user cannot call `Code.Bound.value` on `Prepared`: `::` hides the backing. The user sees `Surreal.Prepared(out)` only. | Roc rules for `::` |
| Opacity to the compiler | The check and the lowering read the backing of a nominal from another module (`structuralType` unwraps all layers). To verify in A': the check side reads the backing var of an imported `::` nominal in `exprIsCodeBound`. | `body.zig:9617-9621` |

## Q4. Watches and writes

| Producer | Today | With A', S2 |
| --- | --- | --- |
| `ready_live` (`2167`, `2425`) | `Try(Watch(row), Error)`, `Watch(out) :: { lets, lives, snapshot }` (`2932`) | `Watch(out) :: Code.Bound(Try(Live(out), Error))`. Same rule: the root type is a nominal backed by `Code.Bound`. `start` and `request` turn `inputs()` into `lets` before the `LIVE` (the server fixes `$x` at `LIVE` time, `gap1-capture-modes.md` "Live queries"). |
| `live_raw`, `live_diff` (`2433`, `2175`) | `Try(RawWatch(out), Error)`, `Try(DiffWatch(row), Error)` | The same, if they get a `ready_*` form. They take a run-time `p` today, so they are not roots (R9) until R12. |
| `Write.ready` (`2552`) and `set_at`, `update_at`, `delete_at` chains | `Try(Prepared(List(row)), Error)` | `Prepared(List(row))`. The keys need R12 (`Code(Id(row))`), not R5. |
| `Totals.ready` (`2228`) | `Try(Prepared(out), Error)` | `Prepared(out)` |
| `Table.merge`, `insert_or_update` (`1392`, `1326`) | take a `Code` lambda and a run-time value, return `Try(Prepared(..))` | They return the opt-in type, so a capturing lambda there makes the call a root, and the run-time `partial` or `rows` makes the compiler refuse it (R9 reason line). This is the correct outcome. The reason line should name the user's type (D3). |

## Q5. Other requirements

| Req | Effect of option A' | Note |
| --- | --- | --- |
| R1 root selection | Only the stop test changes: "a nominal whose backing, through aliases and nominals, is `Code.Bound`". | A user type that wraps `Surreal.Prepared` is then an opt-in too. That is correct: its backing is `Code.Bound`. |
| R2 slot order across sites | None. The nominal is a carrier. | Slots still go in source order of the sites, from 0 per root. |
| R4 stored result holds a function | None new. `Prepared` holds `read` as today (gap1 commit `395cd8d1d0`). | Cost from the gap1 docs (commit `759d668027`, `docs/langref/reifying.md`): a root result that holds a function is not reused from the cache after an edit of the module. Same for B. |
| R7 generic functions | None new. The type parameter `out` sits inside the backing, as `a` in `Code.Bound(a)`. | `B_phantom.roc` works with a generic `out`. |
| R8 refusals | None. | Optional: a translator error in a root can also be `Code.refuse_at`, so it is a compile error (D4). |
| R11 one stored result per site | None. Each call fills its own `inputs`. | `B.roc`: one text, inputs `[11, 11]` and `[31, 31]`. |
| Equality and cache keys | None. `Code` `==` and `to_hash` ignore `first_slot` and the values. `Prepared` has no `==`. | `Builtin.roc` `is_eq` of `Code` |

## Q6. What can be tested now

| Test | Status |
| --- | --- |
| Option B end to end | Works on `gap1` (`B.roc`, and the compiler's own `test/cli/StagedBoundChainQuery.roc`). |
| Option B on today's `reify` binary | Not possible: `Code.Bound.of` and `first_slot` do not exist there. |
| Nominal as the opt-in (A') | Refused on `gap1` with the expected message (`A1.roc`, `A4.roc`). The library code type checks, so the change is in the compiler only. |
| Try outside (S1) | Refused (`A2.roc`). |
| Transparent alias | Accepted as the opt-in today (`A3.roc`), no methods. A possible stopgap: `Prepared(out) : Code.Bound(Try(Ready(out), Error))` plus free functions. Not recommended for the release API. |
| Run-time joins with `Code.Bound.of` | Work (`A1_noroot.roc`). |

## Proposed R5 text

Replace the R5 row in `compiler-gaps.md` with:

| # | Requirement | Why |
| --- | --- | --- |
| R5 | The user must not see `Code.Bound`. The opt-in is the root's solved type, read through transparent aliases, when it is the builtin `Code.Bound(a)` or a nominal type (`:=` or `::`) whose backing, read through aliases and further nominals, is `Code.Bound(a)`. Example: `Prepared(out) :: Code.Bound(Try(Ready(out), Error))`. The nominal is the whole root type: a type that only holds the nominal (`Try(Prepared(out), Error)`, a record, a list) is not an opt-in. A library that can fail puts the `Try` inside the backing. The site fills `inputs` of the `Code.Bound` inside the nominal (the layout is the same). The reason line of a refused capture names the opt-in as "a call that returns `Code.Bound`, or a type built on it". The library builds such values with `Nominal.(Code.Bound.of(x))`, and a value built at run time has no inputs. | Users write `session.run!(cheaper_than(0.9))` with no `?`, and see only `Prepared(out)`. One stop test in root selection (`exprIsCodeBound`) and one relaxed invariant in the site lowering (`bindInputSlots`), with no new lowering. |

## Open decisions for the user

| # | Decision | Options | Recommendation |
| --- | --- | --- | --- |
| D1 | Where the `Try` sits | S1 outside (`Try(Prepared(out), Error)`, needs a new compiler rule) or S2 inside (`Prepared(out) :: Code.Bound(Try(..))`) | S2. It is the only shape that keeps A' a small compiler change, and it gives `run!(cheaper_than(0.9))`. Add `Prepared.checked : Prepared(out) -> Try(Prepared(out), Error)` for code that wants `?` or `match`. |
| D2 | Which nominals are an opt-in | Any nominal whose backing chain reaches `Code.Bound`; or only one layer (`X :: Code.Bound(..)`) | Any chain. The lowering already unwraps all layers, and a user type over `Surreal.Prepared` then works. |
| D3 | Reason line | Name `Code.Bound` only; or name the type that the chain ended in, and say that a type built on `Code.Bound` is also accepted | Name both. A user who never sees `Code.Bound` needs the hint "end the chain with `.ready()`". |
| D4 | Translator errors in a root | `Err` in the stored value (run time, as today); or `Code.refuse_at` (compile error, R8) | Keep `Err` in the value (tests in `tests/` assert errors with `expect`, and the same functions run at run time for `prepare(params)`). Add compile-time refusal later, per rule, if wanted. |
| D5 | Gap 6 renumbering | Text replace of `$_k`; or a template of text and slot parts | Template (`List([Text(Str), Slot(U64)])`). It is library work, not a compiler question. |
| D6 | What to do before A' lands | Wait; or move to S2 with option B now (`Code.Bound(Try(..))` as the result type, `Session.run!` takes it) | Move the `Try` inside now with B. When A' lands, change one type line (`Prepared(out) :: Code.Bound(..)`) and the users' signatures lose `Code.Bound`. |

Conclusion: R5 is blocked only on D1. With D1 = S2, option A' has no open compiler design: it is queue order.
