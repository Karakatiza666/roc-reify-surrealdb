# ORM comparison 1: is the Roc ORM less expressive or more verbose?

Date: 2026-11-05. Repository commit: ba5e2cb. Examples: `examples/main.roc` and `examples/monitoring.roc`, 146 features (`catalog.md`).
Ports: hand-written SurrealQL 3.3.4, the official SurrealDB JS SDK 2.2.2, Rust surreal_orm (GitHub 089f21a9). Per-feature tables: `compare_surql.md`, `compare_js.md`, `compare_rust.md`. Shortest working Roc forms: `shortest_forms.md`.

Summary: the Roc ORM is not less expressive. It covers every feature, and no other option covers as many. It is more verbose than hand-written SurrealQL. Most of that verbosity comes from the style of the examples, not from limits of the API. There are a few small real API limits, and three real problems in the generated SurrealQL.

## 1. Size and coverage

Feature code only: no fixtures, no test harness, unique lines.

| Implementation | Lines | Tokens | Roc tokens / this one | Coverage |
| --- | --- | --- | --- | --- |
| Roc ORM (examples as written) | 479 | 7319 | 1.00 | 146 of 146 |
| Hand-written SurrealQL 3.3.4 | 258 | 4625 | 1.58 | 131 full, 6 partial, 1 not possible, 8 not needed. No types, no typed results, no client code |
| JS SDK 2.2.2 | 551 | (characters: Roc 0.90x) | about 0.9 | 91 of 146 are raw SurrealQL strings |
| surreal_orm (Rust) | 1389 | 15762 | 0.46 | 56 full, 75 partial, 13 raw, 2 not possible. SurrealDB 1.x only, 12 derive bugs |

| Against | Roc shorter | Similar | Other shorter |
| --- | --- | --- | --- |
| SurrealQL | 18 | 39 | 77 |
| JS SDK | 48 | 59 | 37 |
| surreal_orm | 78 | 41 | 20 |

## 2. Most of the verbosity is example style

The shortest working forms pass `tests/check.py` on SurrealDB 3.3.4 (112 of 112 blocks). On the 17 flagged features, tokens go from 1468 to 980 (minus 33%).

| Claim | Shortest form that works |
| --- | --- |
| Each projection needs a named type and function | `.select(\|p\| { id: p.id, age: p.age })` |
| Optional values need `match` | `p.?chip.map_ok(\|c\| c.code) ?? "none"` |
| Unit-tag tests need a named `match` function | `filter(\|v\| v.outcome != Treated)` |
| `to_i64_wrap` in counts | a `U64` field: `patients: edges.len()` |
| Writes need a param type, a patch function, a predicate | inline `update_by`, `set_at` |
| Read rows, form rows | `incoming(..)` with `.get()`; `create` with a dummy `label` |
| No OMIT for view rows | `select(\|d\| d)` |
| No field operators | `{ ..m, stock: m.stock + p.add }` gives `SET stock = stock + $add` |

## 3. Real API limits

| # | Limit | Cost | Location | Proposal |
| --- | --- | --- | --- | --- |
| 1 | `.prepare({})` on each query with no parameter | 96 uses | src/Surreal.roc:3417, 2140 | `Selected.ready`, or `run!` over `Selected({}, out)` |
| 2 | `Query` has no `prepare`; whole rows need `.select(\|r\| r)` | 15 uses | src/Surreal.roc:1802-1978 | `Query.prepare`, `prepare_one`, `live` |
| 3 | A plain table must be listed as `t.define().done()` | 11 tables | src/Types.roc:328 | `Table.plain(t)` |
| 4 | Captures only in `select_where`/`bind_captured` | M75-M77 | src/Surreal.roc:2509, 2523 | `Code.Bound` in all clause builders |
| 5 | Graph paths are one hop; edge filters are list code | M28, M29 | `outgoing`/`incoming` | typed multi-hop path |
| 6 | `Math.mean` takes only `F64` | 2 uses | src/Surreal.roc:807 | `Dec` mean |
| 7 | No migrations, no user transaction block | not in examples | | ideas from surreal_orm |

Language rules, not fixable in the ORM: a `??` default needs a nominal row; a union arm with a payload needs `match`; no field removal from a record type.

## 4. Generated SurrealQL problems

| IDs | Generated | Hand-written | Effect |
| --- | --- | --- | --- |
| N36, N37, N43 | `(SELECT VALUE id FROM vital).filter(..)` per kennel, 3 times in one LIVE SELECT | key range `vital:[kennel, ..]` | whole time series read per kennel; notices for every kennel on each vital write |
| M16, M17 | delete events with `.any(\|$e1\| ..)`, no index | `CONTAINS` with an index on `vaccines[*].vet` | whole table read on each delete |
| M43 | `DEFINE EVENT` after the write | one field ASSERT with `$this` | one more statement |
| M08, M39 | extra `object::keys` ASSERT | literal object types refuse extra keys | redundant work per write |
| M62 (short form) | `(IF chip IS NONE THEN NONE ELSE chip.code END) ?? 'none'` | `chip.code ?? 'none'` | readability |
| N17-N21 | `duration::from_nanos(86400000000000)` | `1d` | readability |

## 5. What the others cannot do

| Capability | SurrealQL | JS SDK | surreal_orm |
| --- | --- | --- | --- |
| One function for constraint and application | no | written twice | written twice |
| Live notices predicted (Mirror) | no | by hand | no |
| Field names checked at compile time | no | unchecked strings | yes |
| Leave notices on live queries | `$before` by hand | `$before` by hand | no |
| SurrealDB 3.x | yes | yes | no |
