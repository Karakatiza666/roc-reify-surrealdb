# Gap 1: literal captures and input slots in one ORM

Question: after the gap 1 fix (`compiler-gaps.md`, R1 to R11), one Roc source can give two descriptions. A capture that is fixed at compile time (a top-level constant, a literal, a value that the block computes from them) is a literal node. A capture that exists only at run time is `Input(k)`, printed `$_k`, with a `LET`. Does this break anything in the ORM?

State: HEAD 0.0.2 (`1997451`), reify compiler `901d5f4824`, SurrealDB 3.3.5 and 4.0.0 (Docker, memory). Probes were run against the real translator through `Code.bound` (as `select_where` does today). Probe files: scratchpad, not committed. One compiler repro: `analysis/repro/union_eq_four_variants.roc`.

## Answer

Yes, in 4 places it breaks, and in 7 places it degrades. Most of the translator is already mode-blind, because the `filter_by` parameter record (`$name`) and `select_where` (`$_k`) already go through the same rules as literals. The breaks are not in the translator rules. They are in three other areas:

| # | Break | Where | Owner |
| --- | --- | --- | --- |
| B1 | A clause in a context with no parameters (schema `ASSERT`, `VALUE`, `DEFAULT`, event, permission, access, view, `DEFINE FUNCTION`) writes `$_k` into the stored text. SurrealDB stores `$_k` as text and reads it at each run from the caller's session. In a new session it is `NONE`. On 4.0.0 even the defining session does not see it. Writes fail or filters go silently wrong. | `src/Schema.roc:124-317`, `src/Surreal.roc:1249`, `1745-1746` | library (refuse) |
| B2 | A statement that renders a clause with `Translate.variable` but has no `LET`s for slots sends an unbound `$_k`. `price < NONE` is false and `price > NONE` is true, so the result is silently wrong. | `src/Surreal.roc:1333` (`insert_or_update`), `1394` (`merge`), and every builder that will take a capturing lambda | library |
| B3 | Some slot types bind to nothing. The literal form works, and the captured form fails at run time: `Duration`, `TimeKey`, a whole geometry (`Point` and others), `U128`. | `src/Translate.roc:914-968` (`captured`) | library |
| B4 | `==` between two tag union values of 4 or more variants, where neither is a constant, crashes the compiler: "normalization broke an invariant of the normal form". With a literal the derived `==` folds, so it never reaches that path. With a captured union it does. | `analysis/repro/union_eq_four_variants.roc` | compiler |

The degrades are index loss (the normal form folds a literal list or an `if` and SurrealDB then uses an index, but it cannot fold an `Input`), different but equal text (operand order), and run-time errors that can move to compile time.

To make the two modes give the same results, the library must: (1) refuse an `Input` in every context that SurrealDB stores (one check, one message); (2) carry the slots of every clause to its terminal call and emit the `LET`s there; (3) bind every slot type that has a literal form, with the same printer (`Ql.literal`) that a literal uses; (4) check slot types at compile time from `Graph.slots` and refuse with `Code.refuse_at`. The compiler must fix B4, and should extend R9 so that a key (`Id`) and a count (`limit`) outside a lambda can be a slot.

## How each mode reaches the library

| Step | Compile-time capture | Run-time capture |
| --- | --- | --- |
| Description | `Lit`, or `Wrap`/`Record`/`List` of literals, after constant folding and N17 (known lists) | `Input(k)` of type `graph.slots()[k]` (`roc-reify-normal-form.md` N18) |
| Translator | `Translate.literal` (`src/Translate.roc:3523`) and the rules that match `Lit` | `Translate.at("$_k", ty)` (`src/Translate.roc:1473-1479`), the same binding that a field of the parameter record gets (`1645`) |
| Value | in the text | `Translate.captured(ty, value)` (`914`), printed by `Ql.literal` (`src/Ql.roc:117-132`) in `LET $_k = ..;` (`src/Surreal.roc:2566`, `5077`) |
| Number format | `Ql.literal` / `Ql.float` / `numeral_text` | `Ql.literal`. Same suffixes: `0.9dec`, `2f`, `5` |
| Errors | translation errors (compile time after gap 1) | translation errors at compile time; bind errors at run time (today `bind_captured`, `src/Surreal.roc:2809-2820`) |

## Verdict table

Probe column: what the translator gave for `|s| ..` with a top-level constant, then with a function parameter. EXPLAIN: verified on 3.3.5 and 4.0.0 unless the row says otherwise.

### Translator rules

| Place | Compile-time literal | Run-time Input | Verdict | Fix |
| --- | --- | --- | --- | --- |
| Comparison operand order, `binary` flip (`src/Translate.roc:3627-3635`, `is_literal` `3649`) | `n >= 10` (literal moved right) | `$_1 <= n` (no flip, `Input` is not a literal) | fine. EXPLAIN: `IndexScan by_price` for `0.9dec > price`, `$p > price`, `price < $p` | optional: `is_literal` accepts `Input(_)`, so the text has one shape |
| Decimal, float, int, text values (`literal` `3523`, `captured` `935-951`) | `(d * 0.9dec) > 2.0dec`, `'it''s'` | `(d * $_1) > 2.0dec`, `LET $_1 = 0.9dec` | fine. Same printer. 4.0.0: `0.9dec = 0.9f` is false, but both modes write `dec` | keep `LET` text from `Ql.literal`. If `LET`s move to CBOR `vars`, tag `Dec` as decimal |
| Integer outside I64 | `18446744073709551615` in the text: the server refuses the whole statement ("number cannot fit within a 64bit signed integer") | `Unsupported("a captured integer outside the range ..")` (`938`) | degrade: two errors for one case | refuse the literal in `literal` with the same message |
| `U128` slot | prints when it fits | no `U128` arm in `captured`: "has no SurrealQL value" (`968`) | break | add `(_, U128(n))` with the I64 range check |
| Record id key, `key_compare` (`3587-3617`) | `id = vet:⟨tia⟩` (`3614`) | `id = type::record('vet', $_1)` (`3598`, `3615`) | fine. EXPLAIN `RecordIdScan` for both, and for `WHERE id = $id` | none |
| `t.id(k)` in a clause, `RecordOf` (`2199-2204`) | `vet:⟨ruth⟩` | `type::record('vet', $_1)` | fine | none |
| Whole captured `Id` (`captured` `918-924`) | `customer = customer:⟨ada⟩` | `customer = $_1`, `LET $_1 = customer:⟨ada⟩` | fine | none |
| `Datetime` (`wrap` `1831-1832`, `captured` `925-928`) | `at > d'2020-01-01T00:00:00Z'` | `$_1 < at`, `LET $_1 = d'..'` | fine | none |
| `Duration` (`wrap` `1836-1840`) | `time::floor(at, 1h)` | `time::floor(at, $_1)` translates, then bind refuses (`930`). Test: `tests/TranslateTest.roc:828-836` | break | bind as `Ql.duration(nanos)` (server: `LET $d = 1h` works in `time::floor`) |
| `TimeKey` (`wrap` `1843-1846`) | `[series, time]` | bind refuses (`932`) | break | bind as `Array([series, Datetime])` |
| Point (`wrap` `1847-1853`) | `<point> [1f, 2f]` | whole point: bind refuses (`933`), test `tests/TranslateTest.roc:1050-1055`. Fields only (`p.lon`): two `F64` slots, fine | break | bind as its GeoJSON object (`geojson`, `src/Surreal.roc:4153`). Server: `LET $g = { type: 'Point', coordinates: [..] }` is a geometry for `geo::distance` |
| Line, polygon, other geometry | refused (`1549`) | refused (`933`) | fine (same refusal) | the GeoJSON bind above makes the captured form work; then the literal form is the weaker one |
| `Link`, `DbFn` (`929`, `931`, `1830`, `1841`) | refused | refused | fine | none |
| Table name: `rows()`, `table_of`, `TableOf`, `RelationOf` (`1192-1193`, `2263-2266`) | literal name | `Table` is opaque (`src/Surreal.roc:1127`): the compiler refuses the capture | fine (refused), generic message | none, or a library message (rule L4) |
| Database function (`function_ref` `372-381`) | top-level, no captures | a closure with captures: "captures values; a database function is a top-level function" (`375`) | fine | none |
| Known list in `any` (N17f folds it) | `('Oslo' = text) OR ('Rome' = text)`: `UnionIndexScan` | `member_of` (`3003-3026`): `text IN $_1[*]`: `TableScan` on both versions | degrade (index lost) | in `member_of`, when the list is an `Input` and the path is the element, write `x IN $_1` (EXPLAIN: `UnionIndexScan`). For a field path, `x IN $_1.f` uses the index on 4.0.0 only |
| `List.contains` (`2338`) | `['Oslo', 'Rome'] CONTAINS text`: `TableScan` | `$_1 CONTAINS text`: `TableScan` | fine (same), both degrade | for both modes: `x IN list` when `x` reads the row (EXPLAIN: `UnionIndexScan`) |
| `if` on a captured `Bool` | folded: `n > 1` | `(IF $_1 THEN n > 1 ELSE m > 1 END)` | degrade (no index through `IF`) | document; the user can split the query in Roc |
| `match` on a captured union, `tag_test` (`1940-1958`), `bool_of` (`2126`) | folded to one arm | `(IF $_1 = 'Cash' THEN .. END)`; a field match with a captured arm value gives `IF payment = 'Cash' THEN $_1 = 'Cash' ..` | fine (correct), degrade (index) | none |
| `==` on a union, derived | `(IF payment.kind = 'Points' THEN payment.value = 3 ELSE false END)` | 3 variants or fewer: fine. 4 or more: compiler crash | break (B4) | compiler bug, repro in `analysis/repro/` |
| `==` on a record with an optional field | unset field left out | `Absent` left out of the object (`941-948`), `owner_at` (`examples/main.roc:507`) | fine | none |
| A captured `Try`, `??` or `match` | folded: `text = 'x'` | the slot is a structural `TagUnion`: `IF $_1.kind = 'Err' THEN 'none' ELSE $_1.value END`, bound `{ kind: 'Ok', value: 'x' }` | fine in probes. Latent: a slot typed `Named("Builtin.Try")` gets `Binding.Maybe` (`242`) but binds as a union object (`968` path), and then reads NONE as never | in `captured`, bind a `Named Try` as its payload or `NONE`, as `try_value` (`1866-1872`) does |
| Time series key range, `series_range` (`2785-2830`) | `kennel:⟨a⟩.chain(|$v1| (SELECT VALUE id FROM vital:[$v1, NONE]..=[$v1, ..]))` | `$_1.chain(..)` | fine. EXPLAIN `RecordIdScan` for `vital:[$k, NONE]..=[$k, ..]` | none |
| Subquery lift, `closed`, `is_variable` (`2976`, `2985`) | literal stays in place | `$_1` is a variable and is read in the subquery directly | fine | none |
| Element tests: `reads_param`, `key_only`, `reads_below` (`3310`, `3327`, `3368`) | literals are leaves | `Input` is a leaf that reads no parameter | fine | none |
| Computation on a captured value (`k = n.to_str()`, `x.with_ascii_uppercased()`, `l / 3`) | not folded either: `<string>42`, `string::split('straße', '')..`, `1.0dec / 3.0dec` | the same text over `$_1` | fine (same SurrealDB semantics in both modes) | none. Note: `Dec` `/` is SurrealDB's 28 digits in both modes, not Roc's 18 |
| Opaque type of another package (`Code.Binds`, `Encoded`, `916`) | the constant is described by its body, the extension renders it: `temp_c > 38.5dec` | its `encoder_for` in `Encode.Bind`: `LET $_1 = 38.5dec` (`tests/ExtensionTest.roc:55-90`) | fine for `Temperature`. Latent: two sources of one value (backing vs encoder) | document the contract: an extension renders a constant as the value its `encoder_for` writes |
| `Id`, `Datetime`, geometry under `Code.Binds` | work as literals | type error: their encoders write `Encode.Format`, and `Binds` needs `Encode.Bind` for every capture (`README.md:2533`) | break, if every builder takes `Code.Binds` | make the encoders of `Surreal` types generic over the format, or ask the compiler for "Binds only for slots that hold an opaque type" (as N18 says for the value) |

### Builders and terminal calls

| Place | Compile-time literal | Run-time Input | Verdict | Fix |
| --- | --- | --- | --- | --- |
| Builders that render with `Translate.variable` and return no `LET`s: `insert_or_update` (`src/Surreal.roc:1333`), `merge` (`1394`) | text is complete | `$_k` with no `LET`: `NONE` | break (B2) | every builder that takes a lambda carries `slots` and `first_slot`; the terminal emits the `LET`s; a builder that cannot refuses non-empty `slots` |
| Key outside a lambda: `at`, `update_at`, `set_at`, `delete_at` (`1140`, `1503-1520`) | `UPDATE vet:⟨ruth⟩`: `Iterate Record` | R9 refuses a run-time `Id`. The user writes `set(\|o\| o.id == key, ..)`: `UPDATE .. WHERE id = ..` is `Iterate Table` on 3.3.5 | degrade (full scan of the table for each keyed write) | compiler: extend R9 so a non-`Code` argument of a fixed shape is a slot. Server: `UPDATE $id SET ..` and `UPDATE type::record('med', $k)` are `Iterate Record` on 3.3.5, `RecordIdScan` on 4.0.0. Library fallback: a key lambda, `set_at_key(\|_\| key, patch)` |
| `limit`, `start` (`2324`, `2486`), `order_by` direction (`2270`), `search` text | literal | refused by R9 | degrade | same R9 extension |
| `order_by` key with a captured flag | `if` folds to a path | not a path: refused | degrade (refusal) | document |
| Gap 1 goal example `owners.set_at(owners.id(key), ..)` (`compiler-gaps.md:30`) | works | refused by R9 of the same document | break of the design text | fix the example, or the R9 extension |

### Contexts with no parameters

Server test: `LET $x = 5;` then `DEFINE ..` in one session, writes in a new session.

| Context | Library | 3.3.5 | 4.0.0 | Verdict | Fix |
| --- | --- | --- | --- | --- | --- |
| Field `ASSERT` | `src/Schema.roc:263`, `275` | stored as `$value < $x`. Same session: passes. New session: every write fails | every write fails, also in the same session | break | refuse |
| Field `VALUE`, `DEFAULT` | `Schema.roc:303-317` | `m = 5` in the defining session, `NONE` after | the same | break | refuse |
| `DEFINE EVENT ... WHEN` | `Schema.roc:124`, `143` | stored as text, `$x` read per write | the same | break | refuse |
| Permissions `WHERE` | `Schema.roc:193`, `242` | stored as text | the same | break | refuse |
| View (`define_as`) | `src/Surreal.roc:1249` | `$x` read from the writer's session: `n > NONE` is true, so the view counts every row | the same | break | refuse (the dropped patch had this message, `w4-dropped.patch` line 230) |
| `DEFINE FUNCTION` | `Translate.function_ref` | `$x` read from the caller's session (dynamic scope) | caller's `$x` not seen: `NONE` | break | already refused (`src/Translate.roc:375`) |
| Access signup and signin | `src/Surreal.roc:1745-1746` | stored as text | the same | break | refuse |
| Index | field paths only | not applicable | not applicable | fine | none |

All of these are compile-time values in practice (top-level schema). After gap 1 a schema built in a function with a captured value is refused by the compiler only if no opt-in root encloses it (R1). The message then names `Code.Bound`, which says nothing to the user. So the schema terminal should be an opt-in root too, and refuse any slot with its own message (rule L3).

### Live queries

| Place | Compile-time literal | Run-time Input | Verdict | Fix |
| --- | --- | --- | --- | --- |
| `LIVE SELECT .. WHERE n > $x` (`src/Surreal.roc:2394-2422`) | literal | `LET $x` before the `LIVE`. Server (WebSocket): `$x` is fixed at `LIVE` time. A later `LET $x = 1` in the writer's session does not change it | fine on both versions | none (`README.md:2585` already says it) |
| Live projection and its subquery | literal | `{ x: $x, sub: (SELECT .. WHERE n > $x) }` sees `$x = 5` | fine on both versions | none |
| Read statements of `Near` (`near_rows` `4384`, `near_test` `4396`, `[Near(r)] if r.node == "id"` `4348`) | `node` is a literal | `node` is `$_k` | fine. `distinct` (`4340`) may keep two equal tests that differ only by slot name | none |
| `keyed_only` (`4271-4282`) | text scan for `$before`; a text literal that holds `$before` can fool it | `$_k` holds no `$before` | fine (the Input form is safer) | none |
| `Translate.narrowings`, `related` (`3065`, `3152-3200`) | equality with a literal | equality with an `Input`, which reads no element | fine | none |
| `Surreal.Mirror` (`3744-3800`) | runs the Roc closure | runs the same Roc closure with the captured value | fine | none |

### Statement identity and composition

| Place | Compile-time literal | Run-time Input | Verdict | Fix |
| --- | --- | --- | --- | --- |
| `Code` `==` and `to_hash` | the literal is in the graph | `slots` are in the graph, values are not | fine: no library code compares or hashes `Code` (searched `src/`) | none |
| `Prepared.then`, `Transaction.then` (`2643-2673`, `then_statement` `5001-5017`) | no names | two statements both use `$_1`: "bound to two different values" (`5003`) | break (gap 6) | renumber the slots of the second statement, in `surql`, `lets` and `inlined` |
| `Statement.inlined` (`2819`) | the text | `replace_each("$_k", literal)`, last name first. A text literal that holds `$_1` is replaced too | degrade (debug text only; `inlined` is read by tests) | after gap 1 the translator does not run at run time, so keep a substitution, but make it skip quoted text, or let the translator emit a marker that `Ql.quote` cannot produce |
| `-- roc:` blocks and `tests/check.py` | compare results | compare results | fine | none |
| Golden script (`tests/expected_output.surql`, `scripts/all_tests.sh` diff) | text | text | fine: a mode change changes the text and the diff fails. Nothing changes silently | none |

### Tests, examples and docs that rely on a form

| Item | Today | After gap 1 | Verdict |
| --- | --- | --- | --- |
| Code that captures a top-level constant | literal | literal (fixed captures stay literal) | no change |
| Code that captures a parameter in `filter` etc. | refused | compiles | new code only |
| `select_where` users: `examples/main.roc:495-507`, `tests/RefactoredTest.roc:545-564`, `tests/QueriesTest.roc:300-307`, `723-739`, `tests/TranslateTest.roc:499-515`, `834`, `1053`, `1075`, `tests/ExtensionTest.roc:55-90` | `$_k` | rewritten to the chain; the golden text changes, the diff shows it | expected change |
| `tests/TranslateTest.roc:836` and `1055` expect a refusal of a captured `Duration` and `Point` | refusal | must change when B3 is fixed | expected change |
| `docs/getting-started.md:275`, `docs/README.md:144`, `README.md:538-539`, `2420`, `2533`, `2581` name `select_where` | current | rewrite | doc work |

No test or example depends on a literal form that would change without a failing test.

## Server evidence (EXPLAIN)

| Query | 3.3.5 | 4.0.0 |
| --- | --- | --- |
| `WHERE price < 0.9dec`, `0.9dec > price`, `price < $p`, `$p > price` | `IndexScan by_price` (all 4) | `IndexScan by_price` (all 4) |
| `WHERE city IN ['Oslo', 'Rome']`, `IN $l`, `city = 'Oslo' OR city = 'Rome'` | `UnionIndexScan` | `UnionIndexScan` |
| `WHERE city IN $l[*]`, `IN ['Oslo', 'Rome'][*]` | `TableScan` | `TableScan` |
| `WHERE city IN $l.c` | `TableScan` | `UnionIndexScan` |
| `WHERE ['Oslo', 'Rome'] CONTAINS city`, `$l CONTAINS city` | `TableScan` | `TableScan` |
| `FROM med:a`, `FROM $id`, `WHERE id = med:a`, `WHERE id = $id`, `WHERE id = type::record('med', $k)` | `RecordIdScan` | `RecordIdScan` |
| `FROM vital:[kennel:a, NONE]..=[kennel:a, ..]`, `FROM vital:[$k, NONE]..=[$k, ..]` | `RecordIdScan` | `RecordIdScan` |
| `UPDATE med:a`, `UPDATE $id`, `UPDATE type::record('med', $k)` | `Iterate Record` | `RecordIdScan` (`type::record` form: `WriteOperator` only) |
| `UPDATE med .. WHERE id = med:a`, `WHERE id = $id`, `DELETE med WHERE id = med:a` | `Iterate Table` | `RecordIdScan` |

SurrealDB puts the parameter value in before it plans (EXPLAIN prints `price < 0.9dec` for `price < $p`), so a `$_k` never loses an index that the literal in the same place has. Index loss comes only from a different shape of the text (folding, `[*]`).

## Recommended rules

| # | Rule | Owner |
| --- | --- | --- |
| L1 | Every translator rule that accepts a literal of type `t` also accepts an `Input` of type `t`, and both give the same value in SurrealDB. Test each rule in both modes (A1 below). | library |
| L2 | Every slot type that has a literal form has a bind form, made by the same encoding: `Duration` as `Ql.duration`, `TimeKey` as an array, geometry as GeoJSON, `U128` with a range check, `Named Try` as the payload or `NONE`. Best: one function from (`Code.Ty`, `Code.Value`) to `Ql.Value` that follows `Encode.Format`, so `filter_by` parameters, literals and slots cannot drift. | library |
| L3 | Contexts with no parameters (schema rules, events, permissions, access, views, database functions) refuse an `Input` with `Code.refuse_at` at the node: "`<context>` is stored in the database and runs with no parameters, so it cannot read `<name>`, a value that exists only when the program runs. Use a top-level constant." | library |
| L4 | Check slot types at compile time from `Graph.slots` and refuse what L2 cannot bind (`Link`, `DbFn`, `Table`, a function), with the advice that `captured` gives today. No bind error is left for run time. | library |
| L5 | Every builder that takes a lambda carries `slots` and `first_slot` to the terminal call, and every terminal emits one `LET` per slot. A builder with no terminal that can emit `LET`s refuses slots (L3). | library |
| L6 | `LET` values stay `Ql.literal` text, the printer of literals, so types and suffixes match (`0.9dec`, `2f`, `d'..'`). No extra cast is needed. If `LET`s move to CBOR `vars`, encode `Dec` as a decimal and `Datetime` as a datetime tag. | library |
| L7 | Prefer index-friendly shapes for both modes: `x IN $_k` and `x IN [..]` for `contains` and for `any` over a list of values, never `[*]` on a list of values. | library |
| L8 | Renumber slots per statement in `then` and in transactions (gap 6), in `surql`, `lets` and `inlined`. | library |
| L9 | `is_literal` treats `Input(_)` as a constant, so operand order is the same in both modes. | library (cosmetic) |
| C1 | Fix the crash of derived `==` between two non-constant unions of 4 or more variants (B4). | compiler |
| C2 | Extend R9: a non-`Code` argument of a builder in the root (an `Id` key, a `U64` count, a search text) can be a slot. It keeps keyed writes at `Iterate Record` and fixes the goal example `set_at(owners.id(key), ..)`. | compiler |
| C3 | `Code.Binds` asks for a format encoder only for slots whose type holds an opaque type (N18 already says the value is structural for the others), so `Id` and `Datetime` captures do not become type errors under `Binds`. Or the library makes its encoders generic over the format. | compiler or library |

## Acceptance tests to add

| # | Test | Expect |
| --- | --- | --- |
| A1 | For each translator rule in `tests/TranslateTest.roc`, a twin with the value captured: compare `bound.value()` with `$_k` put back by `Ql.literal(captured(..))` against the literal output, modulo operand order. On the server (`check.py`), the two forms give the same rows. | equal results |
| A2 | Captured `Duration`, `TimeKey`, `Point`, `U128`, `Named Try` | bind and run; replace `tests/TranslateTest.roc:836`, `1055` |
| A3 | A view, an `ASSERT` and an event built in a function with a capture | compile error at the lambda, message of L3 |
| A4 | `Prepared.then` of two statements with `$_1` each | `$_1` and `$_2`, both `LET`s |
| A5 | `any` over a captured list of texts on an indexed field | `EXPLAIN` gives `UnionIndexScan` |
| A6 | `analysis/repro/union_eq_four_variants.roc` | passes after C1 |

Validate each new test by reverting the fix it covers and checking that the test fails.
