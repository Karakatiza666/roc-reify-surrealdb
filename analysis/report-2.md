# ORM comparison 2: after the changes

Date: 2026-11-05. State: commit ba5e2cb plus the uncommitted working tree. Round 1: `report-1.md`. Catalog: `catalog-2.md` (M01-M101, N01-N55, C01-C04; M69 removed). Per-feature tables: `compare_surql-2.md`, `compare_js-2.md`, `compare_rust-2.md`. The ports did not change; only the Roc side was recounted, with the round-1 method. Totals are over the 145 IDs present in both rounds.

Summary: the Roc feature code is 12 to 13 percent smaller in tokens and 22 to 23 percent smaller in lines. Against hand-written SurrealQL the token ratio goes from 1.58 to 1.39. Against the JS SDK, Roc is now shorter or similar in 128 of 145 features (was 107). Against surreal_orm, it is shorter in 89 (was 77). The generated SurrealQL lost its two costly problems. What remains is mostly the price of types: a projection is still a typed lambda, and open-row helpers need long annotations.

## 1. Size

| Against | Measure | Round 1 | Round 2 |
| --- | --- | --- | --- |
| all | Roc unique feature code, lines / tokens | 479 / 7319 | 371 / 6437 |
| SurrealQL | Roc / SurrealQL, unique tokens | 1.58 | 1.39 |
| SurrealQL | Roc / SurrealQL, unique lines | 1.86 | 1.44 |
| JS SDK | Roc / JS, characters (union) | 0.81 | 0.70 |
| surreal_orm | Roc / Rust, unique tokens | 0.47 | 0.41 |

| Verdicts (Roc shorter / similar / other shorter / n.a.) | Round 1 | Round 2 |
| --- | --- | --- |
| vs SurrealQL | 18 / 39 / 76 / 12 | 24 / 40 / 69 / 12 |
| vs JS SDK | 48 / 59 / 36 / 2 | 60 / 68 / 15 / 2 |
| vs surreal_orm | 77 / 41 / 20 / 7 | 89 / 34 / 15 / 7 |

## 2. Round-1 items: status

| Round-1 item | Status | How |
| --- | --- | --- |
| `.prepare({})` on each query with no parameter | fixed | `.ready()`, `.ready_one()`, `.ready_live(defs)`: 58 uses removed from the two examples |
| `.select(\|r\| r)` for whole rows | fixed | `prepare` / `ready` / `live` on `Query` |
| `Math.mean` only for `F64` | fixed | `Math.mean_dec : List(Dec) -> F64` (the server mean of decimals has 28 digits and NaN for no rows, so the result stays `F64`) |
| `to_i64_wrap` in counts | fixed | `U64` in results, parameters and stored fields (`encode_u64`; values over the `int` range are sent as decimals) |
| Graph paths are one hop | fixed for clauses | `t.edges_from(row)` / `t.edges_to(row)`; `keep_if` / `map` / `join_map` chains become `->treats[WHERE primary]->patient.owner.name`. No Roc body: the Roc reference passes the edges in |
| No transaction block | was wrong | a block form existed; `Surreal.transaction([..])` adds the list form with `Aborted` at the failed statement |
| No migrations | partly | `Surreal.migration(old, new)`; a redesign is planned (`migrations-design.md`) |
| Captures only in `select_where` | not merged | the compiler binds captures only at a call that returns `Code.Bound`; see `compiler-gaps.md` (rows 1-6) |
| A plain table must be listed (`Table.plain`) | not done, by decision | |
| Example style (named types, `match` on optionals, unit tags, inline writes) | fixed in the examples | inline lambdas, `map_ok(..) ?? d`, `!= Treated`, inline `update_by` / `set_at`; named functions stay where the app, the database and the Mirror share them |

## 3. Generated SurrealQL: status

| Round-1 issue | Status | Now |
| --- | --- | --- |
| N36, N37, N43 whole time series per kennel | fixed | key range `vital:[$v1, NONE]..=[$v1, ..]`: 0.27 s against 18.6 s on 20000 readings |
| M16, M17 delete events with `.any(..)` | fixed | `$before.id IN vaccines[*].vet`: IndexScan (the indexes already existed) |
| M63 `any` over a list | fixed | `vet:ruth IN vaccines[*].vet`: uses the index |
| M43 check over two fields as an event | fixed | an ASSERT on the first required field; the refusal is an `Assert` error, not a named `Check` (decision) |
| M08, M39 extra `object::keys` assert | fixed | literal `array<{ .. }>` type |
| M62 `(IF chip IS NONE ..) ?? 'none'` | fixed | `chip.code ?? 'none'` |
| Unit tag test `(IF outcome = 'Treated' ..)` | fixed | `outcome != 'Treated'` |
| Duration text `duration::from_nanos(..)`, `604800000000000ns` | fixed | `1d`, `1w` |
| N43 every kennel sent again on each vital write | still there | narrowing it changes the Mirror contract |
| The `fever` test 3 times per live notice | still there | LIVE SELECT has no LET |
| N24, N28 regroup instead of reading the view | still there | the Roc query does not read the view |
| Dead `$value = NONE OR` guard, redundant union asserts, long index names, `{row, now}` envelope | still there | low impact |
| M77 record equality as 3 ANDs | not a problem | it uses the composite unique index; the hand form `address = $addr` is a TableScan |

## 4. What remains weaker than the alternatives

| # | Weakness | IDs | Example |
| --- | --- | --- | --- |
| 1 | A projection is a typed lambda plus `select` and a terminal call: 1.5 to 2 times the SELECT | M28, M78 | M28 59 tokens against 33 |
| 2 | Open-row helpers need full structural annotations | M65, M66, M94 | M94 434 tokens; Rust `fn(SelectStatement)` |
| 3 | Payload union arms need `match`; aggregates are list code | M60, M78 | `wide_wings` 6 lines; M78 135 tokens against 47 |
| 4 | Whole-row patches; no field operators (`increment`, `append`, `remove`) | M86 | 80 tokens against 40 in Rust |
| 5 | Per-table ceremony: type, handle, `define()...done()`, `encoder_for` / `parser_for` for a nominal row; second row types for read rows and forms | M13, M48, N07, N32, N33 | |
| 6 | Database-only functions (`Geo.*`, `edges_from`, `rows()`) have no Roc body, so the Roc reference needs another input | M95-M97, N-geo | |
| 7 | No id ranges for keys other than a TimeKey (`between`) | | surreal_orm has `id1..id2` |

## 5. Still stronger

| Capability | SurrealQL | JS SDK | surreal_orm | Roc ORM |
| --- | --- | --- | --- | --- |
| One function for the constraint, the query and the app | no | written twice | written twice | yes |
| Live notices predicted (Mirror) | no | by hand | no | yes |
| Names checked at compile time | no | strings | yes | yes |
| SurrealDB 3.x features (REFERENCE, literal unions, closures, time keys) | yes | strings | no (1.x) | yes |
| Schema from types, with link asserts, indexes and delete rules | by hand | strings | partly, with bugs | yes |
| Typed errors with the failed statement | no | one error class | lost at run time | yes |

## 6. Open work

| Item | Where |
| --- | --- |
| Migration redesign for SurrealDB 4.0 with a 3.x floor of 3.3.5 | `migrations-design.md`, section 8 has the decisions |
| Captured values in all clauses | compiler: `compiler-gaps.md` rows 1-5 |
| Read row with two different `Linked` fields crashes the compiler | `compiler-gaps.md` row 8, `repro/two_linked_readable.roc` |
| Field operators, id ranges, aggregates over function results | candidates from section 4 |
