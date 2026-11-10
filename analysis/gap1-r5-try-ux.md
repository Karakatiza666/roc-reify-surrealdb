# Gap 1, R5: is a top-level `Try` worth a compiler rule? (UX of S1 and S2)

Question: `ready` and the other terminal calls give `Try(Prepared(out), Error)` today (S1, Try outside). The other shape is `Prepared(out) :: Code.Bound(Try(Ready(out), Error))` (S2, Try inside, with `checked : Prepared(out) -> Try(Prepared(out), Error)`). Does a use case need S1, or S2? Is a special compiler rule for `Try(<nominal over Code.Bound>, e)` worth it?

State: library HEAD 0.0.2 (`1997451`), read only. Compiler docs from `/home/george/dev/Karakatiza666/roc` (read only). Background: `analysis/gap1-r5-option-a.md` (Q1, "Open decisions"), `analysis/compiler-gaps.md` "Gap 1: design for the compiler" (R5, R8, R12).

## Answer

| Item | Verdict |
| --- | --- |
| A use case that S1 serves and S2 does not | None found. Each S1 use has an S2 form of the same length or shorter. The nearest is "check that the query translates before I open a session" (`examples/server.roc:140`). S2 does it with `.checked()?`. |
| A use case that S2 serves and S1 does not, or serves badly | Yes, four. (1) Combinators: `then`, `begin`/`then`/`commit`, `Surreal.transaction` take a `Prepared`, so S1 users unwrap each operand with `?` and write helpers for it (`batch`, `atomic`, `atomic3`, `all_of`, `then_read`, 9 copies). (2) Lists and records of queries: S1 gives `List(Try(Prepared(a), Error))`, which needs `map_try` before `transaction`. (3) After gap 1, the outer `Try` of a root is a compile-time constant. Errors that depend on a captured value (an `I128` out of range, an id of another table through an R12 key slot) cannot go into it. They come out of `run!` in S1 too, so S1 has two error places and its `?` promises more than it gives. (4) Non-ORM translators (table below): an infallible result (`Shader.compile : Code(Vec2 -> Vec4) -> Shader.Spirv`), a result with warnings, or an own error carrier do not fit "Try outside" at all. They fit `Code.Bound(any type)`. |
| How users consume the top-level Try in this repo | About 98% of the uses do not want it there. They pass it whole to a helper that matches it back into one error channel (`examples/client.roc:703-706`: `Err(e) => { result: Err(e) }`, this is S2 written by hand), map it to `request()` text in `expect`, or crash on `Err` (`ready` helper, 17 uses). Real `?` uses: 10 lines, all in the combinator helpers above, plus 6 `map_err(Str.inspect)?` before `run!`, `live!`, `send!`. |
| Do the docs already assume S2? | Yes, in 2 places: `docs/errors.md:151` `session.run!(owners.create(owner))` and `README.md:582` `session.run!(Surreal.from(vitals)...ready())`. Both do not compile with the S1 types of today. |
| Is the special rule worth it | No. It helps only one translator shape (fallible with a builtin `Try`), it needs a new tag-union lowering in the compiler (`gap1-r5-option-a.md` Q1), and its general form ("any tag union whose payload is the nominal") is a bigger rule with open questions. The compiler's own examples already use the S2 shape: `select_where : .. -> Code.Bound(Try(Str, Error))` (`roc/docs/langref/reifying.md:537`, `roc/examples/reifying/sql/Sql.roc:391`). |

Recommendation: S2 (D1 of `gap1-r5-option-a.md`). Opt-in rule: "the root type is `Code.Bound(a)` or a nominal over it". Add `Prepared.checked`. Make `request`, `statement` give `Try(.., Error)`. Make `then`, `Transaction.then`, `Surreal.transaction` total (`Prepared, Prepared -> Prepared`), and keep the first `Err` inside.

## Q1a. ORM producers: does a top-level `Try` fit?

Line numbers are in `src/Surreal.roc` unless the row says otherwise.

| Producer | Today | Root after gap 1? | Can it fail at the top level after R8? | Top-level Try fits? | Note |
| --- | --- | --- | --- | --- | --- |
| `Query.ready`, `ready_one`, `Selected.ready`, `Totals.ready`, `Write.ready` | `Try(Prepared(..), Error)` (`2149`, `2158`, `2228`, `2348`, `2504`, `2527`, `2552`) | Yes | Structure errors: yes today, compile errors with R8 (`Code.refuse_at`). Value errors: no, they come at bind time (Q3). | Awkward. The outer `Ok`/`Err` is fixed at compile time for all calls. | S1 needs the compiler to rebuild only the `Ok` arm. |
| `prepare(params)` (run-time `params`) | `Try(Prepared(..), Error)` | No (R9: a run-time plain argument) | Yes, encoding of `params` | Fits, but S2 fits too | Same function, two modes: one result type is better. |
| `ready_live`, `live` | `Try(Watch(..), Error)` (`2167`, `2163`, `2393`, `2425`) | `ready_live` yes | Structure: compile time with R8. `live!` can fail anyway (HTTP gives `Unsupported`, `examples/client.roc:788`). | Awkward | Two error points before a watch starts: `watch.map_err(..)?` then `live!(..).map_err(..)?` (`examples/watch.roc:557`, `594`, `docs/live-queries.md:46`). |
| `live_diff`, `live_raw` | `Try(DiffWatch(..))`, `Try(RawWatch(..))` (`2175`, `2433`) | No (take run-time `p`) | Yes | Fits, S2 fits too | Keep the same shape as `ready_live`. |
| `Table.create`, `insert`, `create_new`, `insert_new`, `edit`, `merge_at` with a run-time row | `Try(Prepared(..))` (`1265`-`1405`) | No | Yes: id of another table (`4650`), patch ops (`4904`-`4927`, `1355`) | Fits | In S2 the `Err` is inside, and `checked()` gives it at the cause. |
| `merge`, `insert_or_update` (`Code` lambda and run-time value) | `Try(Prepared(..))` (`1392`, `1326`) | Yes, and refused by R9 when the value is run time | | n/a | Same in both. |
| `Prepared.then` | `Prepared(a), Prepared(b) -> Try(Prepared((Try(a), Try(b))), Error)` (`2643`) | No, run-time join | Yes: `$name` bound to two values (`5005`) | Wrong for a combinator: it takes `Prepared`, but users hold `Try(Prepared)`. 6 helpers exist only to bridge (`examples/main.roc:710`, `examples/monitoring.roc:311`, `tests/BuiltinsTest.roc:1055`, `tests/RefactoredTest.roc:785`, `examples/client.roc:348`, `tests/PreparedTest.roc:427`). | Partial success `(Try(a), Try(b))` is in `out`. It is the same in both shapes. |
| `Transaction.then`, `commit` | `Try(Transaction((a, b)))`, `Transaction(out) -> Prepared(out)` (`2670`, `2677`) | No | Yes (`5005`) | Inconsistent: `commit` gives a bare `Prepared`, the rest a `Try`. S1 must accept both `Prepared` and `Try(Prepared)` as an opt-in. | `Ok(first?.begin().then(second?)?.commit())` (`examples/client.roc:352`, `356`). |
| `Surreal.transaction` | `List(Prepared(out)) -> Try(Prepared(List(out)), Error)` (`2685`) | No | Yes: empty list | Wrong for lists: users hold `List(Try(Prepared))`, so `map_try(\|w\| w)?` first (`examples/client.roc:375`, `tests/PreparedTest.roc:473`) | S2: `Surreal.transaction([bins.create(a), bins.create(b)])`. |
| `Plan.prepare` | `Try(List(Prepared({})), Error)` (`1888`) | No, data only | Yes: `Migration(Edit)` for the whole plan | Fits: the error is about the plan, not about one statement | Not a root, so it needs no opt-in rule. Keep `Try(List(..))` in both shapes. |
| `Surreal.schema`, `Surreal.plan` | `Try(Str, Error)`, `Try(Plan, Error)` (`1788`, `1806`) | No | Yes: `BadSchema` (`src/Types.roc:123`-`657`) | Fits | Not a `Prepared`. No change. |
| Top-level constants (`fevers`, `bin_rows`, `examples/client.roc:162`-`497`) | `Try(Surreal.Prepared(..), Surreal.Error)` | No pending site, a constant | Structure only | Noise: 17 tests unwrap them with a `crash` helper (`tests/HttpTest.roc:107`, `tests/PreparedTest.roc:136`, `tests/ErrorTest.roc:64`) | S2: `fevers : Surreal.Prepared(List(VitalLine))`. |
| A record or list of queries | `List(Try(Prepared(a)))` | Each item is a root | | Awkward (see `transaction`) | S2: `List(Prepared(a))`. |
| Generic helpers that give a query (`cheaper_than`, `readings_above`, `fever`) | `Dec -> Try(Surreal.Prepared(List(Medication)), Surreal.Error)` (`examples/main.roc:494`, `examples/server.roc:52`, `tests/ExtensionTest.roc:57`) | Yes (R7) | | Noise in every signature | S2: `Dec -> Surreal.Prepared(List(Medication))`. |
| Tests on errors (`expect .. == Err(..)`) | 62 lines (`tests/QueriesTest.roc` 35, `tests/DiffTest.roc` 12, `tests/PreparedTest.roc` 7, other 8) | | | Fits, but each test maps first: `.map_ok(\|p\| p.request())` | S2: `.request()` gives `Try(Str, Error)`. Same text, one call less. With R8 refusals these tests need a compile-fail harness in both shapes (D4 keeps `Err` in the value). |
| `Mirror` (`Surreal.Mirror.notices`) | `Try(.., Error)` over an `Edit`, not a `Prepared` | No | | n/a | No change. |
| `check.py` block printers (`block`, `plain`, `seed`, `rejects`, `live_block`) | `match prepared { Ok(p) => p.statement().block(..); Err(e) => "-- unsupported .." }` (`examples/main.roc:696`-`717`, `examples/monitoring.roc:297`, `335`, `598`, `examples/search.roc:107`, `113`) | | | Fits, same as S2 | S2: `match prepared.statement() { .. }`. Same length. |

Several errors or warnings beside success: no ORM producer needs them today. `Error` holds one cause, and `then` keeps the first. If a later version wants all refusals of a chain, S2 can put a `Try(Ready(out), List(Error))` or a record with diagnostics inside the `Code.Bound` with no compiler change. S1 would need the rule to match that new shape.

## Q1b. Other translators built on reify

The rule under review is a compiler rule, so every translator would live with it. Sources: `roc/roc-reify-proposal.md:206-210` (`Shader.compile`), `roc/docs/langref/reifying.md:454` (refusals: `Err` or `Code.refuse_at`), `roc/examples/reifying/` (`hello`, `glsl`, `dbsp`, `sql`).

| Translator kind | Natural result shape | Fits Try outside (S1 rule) | Fits Try inside (S2, `Code.Bound(any type)`) | Note |
| --- | --- | --- | --- | --- |
| GPU shader (`Shader.compile`, `glsl/Glsl.roc:147` `fragment_330`) | `Shader.Spirv`, infallible: refusals are `Code.refuse_at`, compile errors. Captures are uniforms. | No. A `Try` with an `Err` arm that never happens, or the special rule does not apply and the user sees `Code.Bound`. | Yes: `Spirv :: Code.Bound(Module)`, inputs are the uniform values. | The proposal's own headline example is infallible. |
| PTX or compute kernel | `Kernel` with a launch config; maybe `Try` for an unsupported op | Only for the fallible variant | Yes | Same as a shader. |
| Regex or parser generator | `Regex` or `Parser(a)`. Grammar conflicts are a list of errors; ambiguity can be a warning beside a working parser. | Poor: `Try(Parser, List(Conflict))` loses the warnings, and `List` is not the builtin `Error` carrier the rule names. | Yes: `Code.Bound({ parser : Parser(a), warnings : List(Warning) })` or `Code.Bound(Try(Parser(a), List(Conflict)))` | Warnings beside success are not `Try`. |
| Dataflow or streaming plan (DBSP, Feldera; `dbsp/Dbsp.roc:78` `circuit : List(View) -> Try(Str, Error)`) | A circuit: a list of views, each with its own status; a plan with optimizer notes | Poor: a whole-circuit `Try` hides which view failed, and partial success (some views lowered) has no place | Yes: `Code.Bound({ views : List(Try(View, Error)), notes : List(Str) })` | Captures would be run-time parameters of the circuit. |
| Build or config DSL | A config value, often total; validation gives many errors at once | Poor: many errors | Yes | Users want all errors in one pass. |
| Serialization codec | `Codec(a)`: encoder and decoder functions, total for a supported type, unsupported types refused at compile time | No: infallible after `refuse_at` | Yes | Holds functions (R4). |
| GraphQL, Datalog | Query text plus variables; Datalog may give a list of rules (strata) | Fits for one query; poor for a list of strata (`List(Try(..))` vs `Try(List(..))`, as `transaction` above) | Yes | Same as the ORM. |
| UI template | A view tree or HTML; bindings are captures; usually total, with accessibility lints as warnings | No: total plus warnings | Yes | Lints are not errors. |
| A lazy thunk (translate on first use) | `Lazy(a)` with the `Try` only when it is forced | No: the error is not known at build | Yes, the `Try` is in the forced value | |
| A list of results (one root, many outputs) | `List(Shader)`, `List(Statement)` | Only if the rule also looks into `List` | Yes, with a nominal over `Code.Bound(List(..))` | |
| The ORM (this repo) | One statement, maybe a translator error | Yes | Yes | See Q1a and Q2. |

Does the special rule generalize?

| Rule | Translators served | Compiler cost | Open questions |
| --- | --- | --- | --- |
| S2: the root type is `Code.Bound(a)` or a nominal whose backing reaches it | All rows above | One stop test in `exprIsCodeBound`, one relaxed invariant in `bindInputSlots` (`gap1-r5-option-a.md` Q1) | None |
| S1 narrow: `Try(<nominal over Code.Bound>, e)` | Fallible ORM and GraphQL style translators with one builtin `Try` | New: root selection walks into `Try`; site lowering emits a `match` and rebuilds the `Ok` payload; same in the R7 requirement worker | `Try` is a nominal in `Builtin`, so the rule singles out one library type in the compiler |
| S1 general: any tag union whose payload holds the nominal | Adds own error unions (`[Ok(P), Partial(P, List(W)), Failed(List(E))]`) | Larger: a rebuild for each tag that holds the nominal, at any payload position; rules for two nominals in one value (`(Prepared(a), Prepared(b))`), for records and lists that hold it, and for a nominal under a nominal under a tag | Which positions count, what to do with two or with none at run time, and how the reason line names them. In the end this is "look anywhere in the type", which also makes root selection less clear to users (R1: "stop at the first expression whose type is the opt-in") |

Result: the narrow rule does not generalize. The general rule is a type-directed search with several new design points. S2 needs neither, because a translator puts any shape it wants inside `Code.Bound`.

## Q2. How the top-level Try is consumed in this repo

Counts are from `grep` over `examples/`, `tests/`, `docs/`, `README.md` (lines with a call, so about).

| Category | Count | Example (file:line) | S1 code today | S2 code | S2 is |
| --- | --- | --- | --- | --- | --- |
| Passed whole to a helper that takes a `Try` and merges the error into the result | 89 calls of `check!`, `kept!`, `as!`, `pipelined!` (`examples/client.roc`); 7 of `check_watch!` (`examples/watch.roc`) | `examples/client.roc:702-708` | `sent = match prepared { Ok(one) => send!(run, name, one)?; Err(e) => { session: run.session, result: Err(e) } }` | `sent = send!(run, name, prepared)?` | Better: the helper did S2 by hand |
| Passed whole to a `check.py` block printer | about 300 calls (`examples/main.roc` 88, `tests/RefactoredTest.roc` 88, `tests/BuiltinsTest.roc` 58, `examples/monitoring.roc` 44, other 36) | `examples/main.roc:703-707` | `plain = \|header, flags, prepared\| match prepared { Ok(p) => p.statement().block(header, flags); Err(e) => "-- unsupported .." }` | `match prepared.statement() { Ok(s) => s.block(header, flags); Err(e) => "-- unsupported .." }` | Same |
| `map_ok` to text, in `expect` or a helper | about 113 | `tests/QueriesTest.roc:392`, `386` | `expect q.prepare_one({}).map_ok(\|p\| p.request()) == Err(Unsupported(..))` | `expect q.prepare_one({}).request() == Err(Unsupported(..))` | Better (shorter); `request_text`, `request_of`, `script`, `inlined`, `text_of` helpers go |
| `expect .. == Err(..)` on a query | 62 | `tests/QueriesTest.roc:385`-`387` | as above | as above | Better |
| `?` to feed a combinator | 10 | `examples/client.roc:348`, `352`, `356`, `402`; `tests/PreparedTest.roc:431`, `434`; `docs/sessions.md:221` | `atomic3 = \|f, s, t\| Ok(f?.begin().then(s?)?.then(t?)?.commit())` | `f.begin().then(s).then(t).commit()`, no helper | Better: the helpers `batch`, `atomic`, `atomic3`, `all_of`, `then_read` (9 copies) go |
| `match` on two `Try` to join | 6 (`then_read` copies, `pipelined!`) | `examples/main.roc:710-714` | `match (first, second) { (Ok(a), Ok(b)) => a.then(b); (Err(e), _) \| (_, Err(e)) => Err(e) }` | `first.then(second)` | Better |
| `map_try` to turn a list of `Try` into a list | 2 | `examples/client.roc:375` | `Surreal.transaction(writes.map_try(\|w\| w)?)` | `Surreal.transaction(writes)` | Better |
| `map_err(Str.inspect)?` before `run!`, `live!`, `send!` | 6 | `examples/server.roc:140`, `examples/watch.roc:468`, `557`, `594`, `docs/sessions.md:137`, `docs/live-queries.md:46` | `prepared = readings_above(least).map_err(Str.inspect)?` then `session.run!(prepared).result.map_err(Str.inspect)` | `session.run!(readings_above(least)).result.map_err(Str.inspect)`; or keep `readings_above(least).checked().map_err(Str.inspect)?` to fail before `Session.open!` | Better; same when the early check is wanted |
| `crash` on `Err` to get a bare `Prepared` | 17 calls, 3 copies of `ready` | `tests/HttpTest.roc:107`, `tests/PreparedTest.roc:136`, `tests/ErrorTest.roc:64` | `fastest_pulses = ready(Surreal.from(vitals)...prepare({}))` | `fastest_pulses = Surreal.from(vitals)...prepare({})` | Better. The test loses "crash at load"; the error shows in the test's result instead |
| `match` on a watch to test `live!` | 1 | `examples/client.roc:785-792` | `match carer_watch { Ok(watch) => match run.session.live!(watch) {..}; Err(e) => .. }` | `match run.session.live!(carer_watch) {..}` | Better |
| Ignored | 0 | | | | |

Signatures: 154 lines in `examples/`, `tests/`, `docs/`, `README.md` spell `Try(Surreal.Prepared(..), Surreal.Error)` or `Try(Surreal.Watch(..), ..)`. S2 removes the wrapper from each. Worst case today: `examples/client.roc:233` `Try(Surreal.Prepared((Try(List(Kennel), Surreal.Error), Try(List(KennelLine), Surreal.Error))), Surreal.Error)`.

Is the top-level Try valuable to see? Only in the 6 `map_err(..)?` lines, and there only for "fail before I open a session". `checked()` keeps that. In the other uses the user merges the two errors (helpers) or strips the wrapper (`map_ok`, `crash`, `map_try`).

## Q3. Which errors stay at run time, and where each shape puts them

With R8, a root's structural refusals (`src/Translate.roc`, most of its 128 `Err` lines; `prepare_one` on a non-key query, `src/Surreal.roc:2359`; live query forms, `5088`-`5109`) can be compile errors. These stay at run time:

| Error | Source | Depends on | S1 place | S2 place |
| --- | --- | --- | --- | --- |
| Captured integer out of the SurrealDB int range | `src/Translate.roc:938` | Captured value | At bind (`statement`, `run!`): the outer `Try` of a root is fixed at compile time | At `run!` (or `checked()`) |
| Captured tag outside its union, encoded bytes not from `Encode.Bind` | `src/Translate.roc:957`, `913` | Captured value | At bind | At `run!` |
| Id of another table (R12 key slot, `Unchecked.id`) | `src/Surreal.roc:4650` | Key value | At bind for a root; at the call for a run-time `create` | At `run!` or `checked()` |
| Probe of `nearest` with the wrong dimension (R12 slot) | `src/Surreal.roc:2055` | Probe length | At bind | At `run!` |
| `$name` bound to two values in one script | `src/Surreal.roc:5005` (`then_statement`) | `prepare(params)` values | At `then` (`Try` outside) | Inside the joined value: at `run!` or `checked()` |
| Empty `Surreal.transaction` | `src/Surreal.roc:2685` doc | List length | At `transaction` | Inside |
| Patch ops of `edit`, `Mirror` | `src/Surreal.roc:4904`-`4927`, `1355` | Run-time `Edit` | At the call | Inside |
| `BadSchema` of definitions | `src/Types.roc:123`-`657` | Definitions (usually constants) | `Surreal.schema` `Try` | Same (not a `Prepared`) |
| `Migration(Edit)` of a plan | `src/Surreal.roc:1891` | Old schema text | `Plan.prepare` `Try` | Same (not a root) |
| Server errors, `Transport`, `WebSocket`, `Decode` | `src/Ql.roc:26` | The server | `run!` `result` | Same |

Who handles it: in every example the code that runs the query handles both kinds in one `match` (`docs/errors.md:150-157`, `examples/client.roc:686-706`, `examples/server.roc:131-141`). S1 does not put value errors near the cause either: after gap 1 they can only show at bind. S1 is nearer only for values made at run time (`create`, `then`), and `checked()` gives the same in S2.

## Q4. Precedent in other query libraries

| Library | Build step | Where build errors surface | Where run errors surface | Shape |
| --- | --- | --- | --- | --- |
| sqlx `query!` (Rust) | Macro checks SQL against a database at compile time | Compile error | `.fetch_*(..).await` gives `Result` (bind, encode, server) | Build is total: S2 |
| Diesel (Rust) | Typed DSL | Type errors at compile time | `.load(conn)` gives `QueryResult` | S2 |
| Ecto (Elixir) | `from` macro | Some at compile time; `Ecto.QueryError` and cast errors raise at `Repo.all` | `Repo.insert` gives `{:error, changeset}`; a changeset holds its errors inside | S2 (errors inside the value) |
| Kysely (TypeScript) | Typed builder, `compile()` | Type errors | `execute()` rejects | S2 |
| SurrealDB JS SDK | None (text) | n/a | `db.query(..)` rejects | S2 |

No library found gives a fallible value at build that the user must unwrap before execute.

## Recommendation

| # | Item |
| --- | --- |
| 1 | D1 = S2. Do not add a compiler rule for `Try(<nominal over Code.Bound>, e)`, narrow or general. |
| 2 | R5 text as proposed in `gap1-r5-option-a.md` "Proposed R5 text". Add one line: "A translator puts any shape in the backing (a `Try`, a record with warnings, a total value)". |
| 3 | Library: `Prepared.checked : Prepared(out) -> Try(Prepared(out), Error)`; `request`, `statement`, `Watch.request` give `Try(.., Error)`; `then`, `Transaction.then`, `Surreal.transaction` become total and keep the first `Err`; `Session.send!` puts a translation `Err` in the ticket, so `await!` gives it as `result` (as `run!`). |
| 4 | Keep `Try` outside for values that are not a `Prepared`: `Plan.prepare`, `Surreal.schema`, `Surreal.plan`, `Mirror`. |
| 5 | Docs: `docs/errors.md:151` and `README.md:582` then compile as written. `docs/sessions.md:137` and `docs/live-queries.md:46` drop `map_err(..)?`. |
