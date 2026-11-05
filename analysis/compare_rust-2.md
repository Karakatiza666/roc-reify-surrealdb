# Roc ORM against the Rust surreal_orm crate, round 2

Round 2 repeats analysis/compare_rust.md after the Roc ORM and its examples changed (catalog-2.md). Same method, same verdict rule, same Rust port (surreal_orm commit 089f21a9, SurrealDB 1.5, not changed). Only the Roc side is counted again.

## 0. Method and corrections

| Item | Rule |
| --- | --- |
| Roc side | roc_counts_2.json (recount from the catalog-2 ranges, harness and fixtures removed). Spot-checked: M28, M62, M86, M48, N41 (ranges and code agree with examples/main.roc:719, 684-688, Clinic.roc:33-35 and 884, 345-391 and 633-637). |
| Rust side | Unchanged: fair-share counts from fair2.py (attributes counted, shared blocks split), Adj = tokens without the execute wrapper. |
| Verdict rule | Roc tokens / Adj. Below 0.8 R, above 1.2 S, else =. A difference of 8 tokens or less is =. A star is a reading override. Round-1 stars were kept, except M62 (the Roc code is now one line, so the plain rule applies). I checked that the round-1 rule reproduces every round-1 verdict without a star. |
| Fix 1 | The recount of N47 and N48 took 8 and 4 lines of harness (the `match` that builds the literal). I used the round-1 counts (2/53 and 2/29): the feature code did not change. |
| Fix 2 | N11 and N14 range 216-218 holds the helper `flag_line`, which is now only a reference for the Mirror (catalog-2). I counted the query line only (1 line, 43 tokens). |
| Counting shift | A lambda that moved into the query moves its tokens from the helper ID to the query ID. M64 (helper `vaccine_line` was counted in M63) and N27 (helpers were not in the range) show a worse verdict only for this reason. The code did not grow. |
| Same feature set | M69 is removed. Round 1 and round 2 are compared on the 145 IDs present in both. Rust totals drop the M69 fair share (18 lines, 157 tokens). |
| Rust syntax | Same caution as round 1: derive attributes, `.await?`, type paths make Rust long. The notes judge structure. |

## 1. Totals

Roc sums repeat shared code (overlap counted). Rust is a true partition.

| Item | Round 1 (146 IDs) | Round 1 (145 common IDs) | Round 2 (145 common IDs) | Round 2 against round 1 |
| --- | --- | --- | --- | --- |
| Roc lines, per-ID sum | 627 | 619 | 498 | -121 (-20%) |
| Roc tokens, per-ID sum | 10236 | 10170 | 9237 | -933 (-9%) |
| Rust lines, per-ID sum | 1416 | 1398 | 1398 | 0 |
| Rust tokens, per-ID sum | 16516 | 16359 | 16359 | 0 |
| Rust Adj tokens (no wrapper) | - | 13406 | 13406 | 0 |
| Roc/Rust tokens | 0.62 | 0.62 | 0.56 | |
| Roc/Rust Adj tokens | - | 0.76 | 0.69 | |
| Roc lines, unique, main (M, with Clinic.roc) | 343 | 343 | 254 | -89 |
| Roc tokens, unique, main | 4593 | 4593 | 3936 | -657 |
| Roc lines, unique, monitoring (N) | 136 | 136 | 115 | -21 |
| Roc tokens, unique, monitoring | 2726 | 2726 | 2442 | -284 |
| Roc unique lines / tokens, both | 479 / 7319 | 479 / 7319 | 369 / 6378 | -23% / -13% |
| Rust unique lines / tokens, both (fair, N49-N52 left out) | 1389 / 15762 | 1371 / 15605 | 1371 / 15605 | 0 |
| Roc/Rust unique, lines / tokens | 0.34 / 0.46 | 0.35 / 0.47 | 0.27 / 0.41 | |
| Verdict: Roc shorter (R) | 78 | 77 | 89 | +12 |
| Verdict: similar (=) | 41 | 41 | 34 | -7 |
| Verdict: Rust shorter (S) | 20 | 20 | 15 | -5 |
| Verdict: n/a | 7 | 7 | 7 | 0 |

The unique Roc numbers use the union of cited lines of the common IDs (file and line), so they are comparable to round 1 section 6. Rust unique drops the M69 share only. The Roc file grew by new features (M95-M101, N53-N55, C01-C04); they are not in these totals (section 5).

Verdict changes (22 IDs, M62 also lost its star):

| Direction | IDs |
| --- | --- |
| Better for Roc | M29 (=->R), M54 (S->=), M60 (=->R), M62 (=->R), M63 (S->=), M68 (=->R), M73 (=->R), M74 (=->R), M88 (=->R), M89 (=->R), M90 (=->R), M91 (S->=), N07 (S->=), N08 (=->R), N10 (=->R), N11 (S->R), N14 (=->R), N22 (S->=), N40 (S->=) |
| Worse for Roc | M53 (R->=), M64 (=->S), N27 (=->S) |

Removed ID: M69 (needs_attention as filter and program function). Its filter part is now M101 (`v.outcome != Treated`) and its match part is M60. The Rust code stays in the port; I use it for M101 in section 5.

Per category (Roc sums repeat shared code). Verdict columns: R / = / S, round 1 then round 2; n/a ignored.

| Category | IDs | Roc l/t round 1 | Roc l/t round 2 | Rust l/t | R/=/S round 1 | R/=/S round 2 |
| --- | --- | --- | --- | --- | --- | --- |
| row type | 13 | 80/1055 | 80/1055 | 156/1409 | 10/3/0 | 10/3/0 |
| link | 10 | 20/263 | 20/263 | 90/1063 | 8/1/0 | 8/1/0 |
| edge | 8 | 28/514 | 20/403 | 119/1269 | 7/1/0 | 8/0/0 |
| schema constraint | 18 | 52/623 | 47/600 | 174/1977 | 15/2/0 | 15/2/0 |
| other | 4 | 110/1379 | 81/1181 | 71/713 | 2/0/2 | 2/1/1 |
| query-filter | 18 | 50/1045 | 42/1053 | 123/1634 | 9/6/3 | 9/5/4 |
| projection | 16 | 86/1401 | 48/1262 | 184/1809 | 5/8/3 | 9/6/1 |
| group-aggregate | 7 | 20/690 | 17/658 | 69/628 | 2/5/0 | 2/4/1 |
| write | 15 | 63/819 | 51/695 | 125/2494 | 5/3/3 | 8/1/2 |
| geometry | 5 | 16/291 | 12/263 | 38/489 | 3/1/1 | 3/1/1 |
| time series | 9 | 19/436 | 15/380 | 61/717 | 2/7/0 | 3/6/0 |
| db function | 5 | 20/367 | 12/271 | 45/415 | 1/2/2 | 4/0/1 |
| view | 2 | 5/89 | 4/48 | 17/164 | 1/0/1 | 1/1/0 |
| read row | 4 | 10/361 | 9/336 | 25/222 | 0/0/3 | 0/0/3 |
| live query | 11 | 40/837 | 40/769 | 101/1356 | 7/2/2 | 7/3/1 |

surreal_orm status (NOTES.md) against the round-2 verdict:

| Rust status | IDs | R | = | S | n/a |
| --- | --- | --- | --- | --- | --- |
| full | 56 | 30 | 18 | 4 | 4 |
| partial | 74 | 54 | 11 | 8 | 1 |
| raw SurrealQL | 13 | 5 | 5 | 3 | 0 |
| not possible | 2 | 0 | 0 | 0 | 2 |

Reading: the Roc total fell by 9% in tokens and 20% in lines, mostly in projections (-139 tokens), write (-124), db function (-96), edge (-111) and other (-198). Inline lambdas removed named functions and their record types. Roc is now shorter in 89 IDs (was 77), Rust in 15 (was 20). The largest remaining Rust lead is still in open-row fragments (M65, M66, M94), select-by-name helpers (M49) and the one-field write (M86).

## 2. Per-feature table

Roc l/t r1 and r2 are the round-1 and round-2 counts. Rust l/t is the fair share, Adj is without the wrapper. Ratio is Roc r2 tokens / Adj. Change shows a verdict change, and for a changed Roc count the new token count and the catalog-2 reason. A dash means the Roc code and the verdict did not change in a way the rule sees (token change of 3 or less is not shown). Round-1 notes still apply to Rust.

| ID | Cat | Roc r1 l/t | Roc r2 l/t | Rust l/t | Adj | Ratio | Rust status | Verdict r1 -> r2 | Change |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| M01 | row type | 8/95 | 8/95 | 5/49 | 49 | 1.94 | full | R* -> R* | - |
| M02 | row type | 22/155 | 22/155 | 8/85 | 85 | 1.82 | partial | R* -> R* | - |
| M03 | row type | 16/135 | 16/135 | 12/90 | 90 | 1.50 | full | =* -> =* | - |
| M04 | row type | 3/68 | 3/68 | 14/129 | 129 | 0.53 | partial | R -> R | - |
| M05 | row type | 2/81 | 2/81 | 9/70 | 70 | 1.16 | partial | R* -> R* | - |
| M06 | row type | 3/61 | 3/61 | 20/194 | 194 | 0.31 | partial | R -> R | - |
| M07 | row type | 1/48 | 1/48 | 2/19 | 19 | 2.53 | full | =* -> =* | - |
| M08 | row type | 4/48 | 4/48 | 12/109 | 109 | 0.44 | partial | R -> R | - |
| M09 | row type | 6/133 | 6/133 | 8/78 | 78 | 1.71 | partial | R* -> R* | - |
| M10 | row type | 4/59 | 4/59 | 8/54 | 54 | 1.09 | partial | R* -> R* | - |
| M11 | row type | 5/64 | 5/64 | 32/356 | 356 | 0.18 | partial | R -> R | - |
| M12 | row type | 3/73 | 3/73 | 21/139 | 139 | 0.53 | partial | R -> R | - |
| M13 | row type | 3/35 | 3/35 | 5/37 | 37 | 0.95 | full | = -> = | - |
| M14 | link | 3/24 | 3/24 | 9/84 | 84 | 0.29 | partial | R -> R | - |
| M15 | link | 2/20 | 2/20 | 13/150 | 150 | 0.13 | partial | R -> R | - |
| M16 | link | 4/48 | 4/48 | 20/227 | 227 | 0.21 | partial | R -> R | - |
| M17 | link | 1/32 | 1/32 | 14/176 | 176 | 0.18 | partial | R -> R | - |
| M18 | link | 2/55 | 2/55 | 2/19 | 19 | 2.89 | partial | R* -> R* | - |
| M19 | link | 3/36 | 3/36 | 10/129 | 129 | 0.28 | raw SurrealQL | R -> R | - |
| M20 | link | 2/14 | 2/14 | 8/106 | 106 | 0.13 | partial | R -> R | - |
| M21 | link | 2/14 | 2/14 | 8/106 | 106 | 0.13 | raw SurrealQL | R -> R | - |
| M22 | link | 0/0 | 0/0 | 3/39 | 39 | - | full | n/a -> n/a | - |
| M23 | edge | 3/53 | 3/53 | 8/86 | 86 | 0.62 | partial | R -> R | - |
| M24 | edge | 1/6 | 1/6 | 9/103 | 92 | 0.07 | partial | R -> R | - |
| M25 | edge | 1/15 | 1/15 | 6/64 | 64 | 0.23 | full | R -> R | - |
| M26 | edge | 1/20 | 1/20 | 6/80 | 80 | 0.25 | full | R -> R | - |
| M27 | edge | 4/63 | 4/63 | 18/225 | 180 | 0.35 | partial | R -> R | - |
| M28 | edge | 4/108 | 1/59 | 18/180 | 147 | 0.40 | full | R -> R | tokens 108 -> 59; lambda in the query, `case_load` and `CaseLoad` removed; counts are `U64` (no `to_i64_wrap`) |
| M29 | edge | 4/119 | 1/71 | 18/180 | 147 | 0.48 | full | = -> R | = -> R ; tokens 119 -> 71; lambda in the query, `team_line` and `TeamLine` removed; count is `U64` |
| M30 | schema constraint | 1/10 | 1/10 | 5/62 | 62 | 0.16 | full | R -> R | - |
| M31 | schema constraint | 1/24 | 1/24 | 5/62 | 62 | 0.39 | full | R -> R | - |
| M32 | schema constraint | 1/12 | 1/12 | 6/74 | 74 | 0.16 | full | R -> R | - |
| M33 | schema constraint | 1/20 | 1/20 | 3/42 | 42 | 0.48 | full | R -> R | - |
| M34 | schema constraint | 3/32 | 3/32 | 12/158 | 158 | 0.20 | full | R -> R | - |
| M35 | schema constraint | 3/37 | 3/37 | 8/84 | 84 | 0.44 | partial | R -> R | - |
| M36 | schema constraint | 1/20 | 1/20 | 2/26 | 26 | 0.77 | raw SurrealQL | = -> = | - |
| M37 | schema constraint | 1/24 | 1/24 | 14/163 | 163 | 0.15 | partial | R -> R | - |
| M38 | schema constraint | 1/18 | 1/18 | 7/82 | 82 | 0.22 | partial | R -> R | - |
| M39 | schema constraint | 4/58 | 4/58 | 7/96 | 96 | 0.60 | partial | R -> R | - |
| M40 | schema constraint | 6/44 | 6/44 | 17/170 | 170 | 0.26 | partial | R -> R | - |
| M41 | schema constraint | 6/51 | 6/51 | 21/227 | 227 | 0.22 | partial | R -> R | - |
| M42 | schema constraint | 6/73 | 6/73 | 20/197 | 197 | 0.37 | full | R -> R | - |
| M43 | schema constraint | 3/48 | 3/48 | 4/54 | 54 | 0.89 | raw SurrealQL | =* -> =* | - |
| M44 | schema constraint | 1/10 | 1/10 | 8/100 | 100 | - | not possible | n/a -> n/a | - |
| M45 | schema constraint | 7/56 | 3/40 | 18/181 | 181 | 0.22 | partial | R -> R | tokens 56 -> 40 |
| M46 | schema constraint | 1/13 | 1/13 | 5/65 | 65 | 0.20 | partial | R -> R | - |
| M47 | schema constraint | 5/73 | 4/66 | 12/134 | 110 | 0.60 | partial | R -> R | tokens 73 -> 66 |
| M48 | other | 60/564 | 46/521 | 17/164 | 142 | 3.67 | full | R* -> R* | tokens 564 -> 521; one `definitions` list, the seven `*_def` values are removed |
| M49 | query-filter | 4/69 | 1/51 | 4/55 | 42 | 1.21 | full | S -> S | tokens 69 -> 51 |
| M50 | projection | 4/86 | 4/100 | 10/108 | 93 | 1.08 | full | = -> = | tokens 86 -> 100 |
| M51 | projection | 3/74 | 4/80 | 7/74 | 60 | 1.33 | partial | =* -> =* | tokens 74 -> 80 |
| M52 | query-filter | 3/41 | 1/30 | 8/92 | 60 | 0.50 | full | R -> R | tokens 41 -> 30; lambda in the filter, `is_vip` removed |
| M53 | query-filter | 1/32 | 1/63 | 6/73 | 56 | 1.12 | partial | R -> = | R -> = ; tokens 32 -> 63 |
| M54 | projection | 10/90 | 1/63 | 6/73 | 56 | 1.12 | partial | S -> = | S -> = ; tokens 90 -> 63; `map_ok` and `??` in a lambda (was `match` in `referral_line`); SurrealQL: `??` (was IF ... .. |
| M55 | projection | 4/76 | 4/74 | 8/72 | 60 | 1.23 | full | =* -> =* | - |
| M56 | projection | 9/94 | 9/92 | 16/145 | 132 | 0.70 | partial | R* -> R* | - |
| M57 | projection | 4/109 | 4/149 | 18/166 | 138 | 1.08 | full | R* -> R* | tokens 109 -> 149 |
| M58 | query-filter | 3/33 | 3/31 | 13/118 | 85 | 0.36 | full | R -> R | - |
| M59 | query-filter | 1/37 | 1/37 | 8/102 | 65 | 0.57 | full | R -> R | - |
| M60 | query-filter | 6/62 | 6/60 | 9/94 | 77 | 0.78 | partial | = -> R | = -> R ; tokens 62 -> 60 |
| M61 | projection | 3/99 | 3/93 | 14/208 | 143 | 0.65 | full | R -> R | tokens 99 -> 93 |
| M62 | projection | 14/106 | 1/70 | 17/137 | 104 | 0.67 | partial | =* -> R | =* -> R ; tokens 106 -> 70; `map_ok` and `??` (was `match` in `chip_line`), `ChipLine` removed; SurrealQL: `??` |
| M63 | projection | 4/76 | 1/51 | 6/69 | 52 | 0.98 | raw SurrealQL | S -> = | S -> = ; tokens 76 -> 51; lambda in the query, `vaccine_line` and `VaccineLine` removed |
| M64 | query-filter | 3/53 | 3/82 | 6/69 | 52 | 1.58 | partial | = -> S | = -> S ; tokens 53 -> 82 |
| M65 | query-filter | 10/225 | 7/226 | 8/81 | 65 | 3.48 | partial | S -> S | - |
| M66 | projection | 7/198 | 5/203 | 8/67 | 52 | 3.90 | raw SurrealQL | S -> S | tokens 198 -> 203; lambda in the query, `visit_line` and `VisitLine` are now only a reference helper (line 481) |
| M67 | query-filter | 1/40 | 1/38 | 4/61 | 44 | 0.86 | raw SurrealQL | = -> = | - |
| M68 | projection | 10/93 | 7/79 | 16/132 | 113 | 0.70 | partial | = -> R | = -> R ; tokens 93 -> 79; `outcome_line` and `OutcomeLine` removed |
| M70 | projection | 1/20 | 1/10 | 3/46 | 14 | 0.71 | full | = -> = | tokens 20 -> 10 |
| M71 | projection | 4/69 | 1/47 | 14/123 | 90 | 0.52 | full | R -> R | tokens 69 -> 47 |
| M72 | projection | 1/39 | 1/37 | 10/122 | 90 | 0.41 | full | R -> R | - |
| M73 | projection | 4/89 | 1/60 | 17/143 | 110 | 0.55 | partial | = -> R | = -> R ; tokens 89 -> 60; lambda in the query, `contact_line` and `ContactLine` removed |
| M74 | projection | 4/83 | 1/54 | 14/124 | 91 | 0.59 | partial | = -> R | = -> R ; tokens 83 -> 54; lambda in the query, `linked_rows` and `LinkedRows` removed |
| M75 | query-filter | 3/50 | 3/50 | 4/79 | 43 | 1.16 | full | = -> = | - |
| M76 | query-filter | 3/56 | 3/56 | 5/112 | 73 | 0.77 | full | R -> R | - |
| M77 | query-filter | 4/55 | 4/55 | 12/137 | 101 | 0.54 | partial | R -> R | - |
| M78 | group-aggregate | 4/145 | 4/135 | 8/71 | 60 | 2.25 | full | =* -> =* | tokens 145 -> 135; `Ledger.visits` is `U64` and `rows.len()` has no `to_i64_wrap` |
| M79 | group-aggregate | 2/115 | 2/105 | 8/71 | 60 | 1.75 | partial | =* -> =* | tokens 115 -> 105 |
| M80 | group-aggregate | 1/50 | 1/48 | 8/71 | 60 | 0.80 | full | = -> = | - |
| M81 | group-aggregate | 4/102 | 1/65 | 19/163 | 130 | 0.50 | full | R -> R | tokens 102 -> 65; lambda in `totals(..)`, `VisitTotals` removed, count is `U64`, mean is `Math.mean_dec` |
| M82 | group-aggregate | 1/44 | 1/38 | 14/135 | 104 | 0.37 | partial | R -> R | tokens 44 -> 38 |
| M83 | write | 6/36 | 6/36 | 6/60 | 49 | 0.73 | partial | R -> R | - |
| M84 | write | 1/6 | 1/6 | 4/71 | 39 | 0.15 | full | R -> R | - |
| M85 | write | 2/25 | 2/25 | 4/80 | 48 | 0.52 | full | R -> R | - |
| M86 | write | 6/94 | 3/80 | 6/60 | 40 | 2.00 | full | S -> S | tokens 94 -> 80; patch is a lambda, `refill`, `RestockParam` and `refill_param` removed |
| M87 | write | 3/54 | 1/39 | 7/105 | 73 | 0.53 | full | R -> R | tokens 54 -> 39; `set_at` with a lambda patch (was `update_at` with `certified`, removed) |
| M88 | write | 3/39 | 1/28 | 4/80 | 48 | 0.58 | full | = -> R | = -> R ; tokens 39 -> 28; lambda patch, `renamed` removed |
| M89 | write | 3/67 | 1/38 | 7/108 | 76 | 0.50 | full | = -> R | = -> R ; tokens 67 -> 38; lambda patch, `moved` removed; `no_phone` gives the `Err` its type |
| M90 | write | 1/17 | 1/15 | 4/56 | 25 | 0.60 | full | = -> R | = -> R ; tokens 17 -> 15 |
| M91 | write | 3/62 | 1/26 | 4/55 | 32 | 0.81 | full | S -> = | S -> = ; tokens 62 -> 26; lambda in `delete_by`; `Clinic.too_old`, `Clinic.seen_before` and `RetentionParam` removed |
| M92 | write | 11/185 | 9/148 | 11/128 | 104 | 1.42 | partial | S -> S | tokens 185 -> 148 |
| M93 | write | 24/234 | 25/254 | 34/902 | 616 | 0.41 | partial | R -> R | tokens 234 -> 254; 25 refusals (was 24); `check_as_event` is now `check_over_two_fields` and has an update .. |
| M94 | other | 22/511 | 18/434 | 14/162 | 118 | 3.68 | partial | S -> S | tokens 511 -> 434; `Clinic.roc` has 48 lines (was 55); `seen_before` and `too_old` removed, so M91 no longer .. |
| N01 | geometry | 1/23 | 1/23 | 13/118 | 87 | 0.26 | partial | R* -> R* | - |
| N02 | geometry | 7/91 | 6/85 | 4/34 | 26 | 3.27 | full | =* -> =* | tokens 91 -> 85 |
| N03 | link | 1/20 | 1/20 | 3/27 | 27 | 0.74 | partial | = -> = | - |
| N04 | time series | 1/29 | 1/29 | 6/78 | 78 | 0.37 | partial | R -> R | - |
| N05 | time series | 3/59 | 2/53 | 6/71 | 63 | 0.84 | full | = -> = | tokens 59 -> 53 |
| N06 | edge | 10/130 | 8/116 | 36/351 | 340 | 0.34 | partial | R -> R | tokens 130 -> 116 |
| N07 | other | 25/211 | 14/139 | 19/151 | 129 | 1.08 | full | S -> = | S -> = ; tokens 211 -> 139; one `definitions` list (the `*_def` values are removed) |
| N08 | db function | 5/76 | 5/56 | 10/90 | 90 | 0.62 | partial | = -> R | = -> R ; tokens 76 -> 56 |
| N09 | db function | 1/36 | 1/34 | 8/76 | 59 | 0.58 | partial | R -> R | - |
| N10 | db function | 6/54 | 1/26 | 8/60 | 60 | 0.43 | raw SurrealQL | = -> R | = -> R ; tokens 54 -> 26 |
| N11 | db function | 4/79 | 1/43 | 6/72 | 56 | 0.77 | full | S -> R | S -> R ; tokens 79 -> 43; lambda in the query (`flag_line` is now a reference helper, line 217) |
| N12 | db function | 4/122 | 4/112 | 13/117 | 90 | 1.24 | full | S -> S | tokens 122 -> 112; `Daily.readings` and `fevers` are `U64`, no `to_i64_wrap` |
| N13 | time series | 4/106 | 4/104 | 12/123 | 105 | 0.99 | raw SurrealQL | = -> = | - |
| N14 | time series | 4/79 | 1/43 | 8/84 | 67 | 0.64 | full | = -> R | = -> R ; tokens 79 -> 43 |
| N15 | time series | 1/26 | 1/24 | 6/64 | 24 | 1.00 | full | = -> = | - |
| N16 | time series | 1/29 | 1/19 | 3/62 | 22 | 0.86 | full | = -> = | tokens 29 -> 19 |
| N17 | time series | 3/66 | 3/66 | 8/71 | 59 | 1.12 | partial | = -> = | - |
| N18 | time series | 1/30 | 1/30 | 4/67 | 32 | 0.94 | partial | = -> = | - |
| N19 | time series | 1/12 | 1/12 | 8/97 | 76 | 0.16 | raw SurrealQL | R* -> R* | - |
| N20 | group-aggregate | 7/188 | 7/178 | 6/59 | 48 | 3.71 | partial | =* -> =* | tokens 188 -> 178 |
| N21 | view | 4/45 | 3/38 | 14/118 | 118 | 0.32 | partial | R -> R | tokens 45 -> 38; `daily_def` removed, the call is inside `definitions` |
| N22 | view | 1/44 | 1/10 | 3/46 | 14 | 0.71 | full | S -> = | S -> = ; tokens 44 -> 10 |
| N23 | query-filter | 1/36 | 1/34 | 3/55 | 23 | 1.48 | full | =* -> =* | - |
| N24 | query-filter | 1/36 | 1/34 | 7/65 | 33 | 1.03 | partial | = -> = | - |
| N25 | query-filter | 1/46 | 1/44 | 5/114 | 82 | 0.54 | partial | R -> R | - |
| N26 | query-filter | 1/47 | 1/45 | 5/119 | 87 | 0.52 | partial | R -> R | - |
| N27 | group-aggregate | 1/46 | 1/89 | 6/58 | 42 | 2.12 | partial | = -> S | = -> S ; tokens 46 -> 89; lambdas in the query (`hot_line` and `kennel_fevers` are now reference helpers, lines 220-224) |
| N28 | query-filter | 1/54 | 1/46 | 7/63 | 27 | 1.70 | partial | S -> S | tokens 54 -> 46 |
| N29 | geometry | 4/56 | 1/34 | 12/128 | 95 | 0.36 | raw SurrealQL | R -> R | tokens 56 -> 34; lambda in the query, `site_lat` and `SiteLat` removed |
| N30 | geometry | 3/71 | 3/71 | 4/87 | 45 | 1.58 | full | S -> S | - |
| N31 | geometry | 1/50 | 1/50 | 5/122 | 80 | 0.62 | partial | R -> R | - |
| N32 | read row | 4/127 | 4/121 | 9/83 | 72 | 1.68 | partial | S -> S | tokens 127 -> 121 |
| N33 | read row | 3/140 | 3/134 | 9/83 | 72 | 1.86 | raw SurrealQL | S -> S | tokens 140 -> 134 |
| N34 | read row | 1/82 | 1/76 | 7/56 | 45 | 1.69 | raw SurrealQL | S -> S | tokens 82 -> 76; count is `U64` |
| N35 | read row | 2/12 | 1/5 | 0/0 | 0 | - | not possible | n/a -> n/a | tokens 12 -> 5 |
| N36 | other | 3/93 | 3/87 | 21/236 | 201 | 0.43 | partial | R -> R | tokens 93 -> 87 |
| N37 | query-filter | 3/73 | 3/71 | 9/145 | 113 | 0.63 | partial | R -> R | - |
| N38 | live query | 3/56 | 3/53 | 8/140 | 95 | 0.56 | partial | R -> R | - |
| N39 | live query | 3/65 | 3/65 | 4/89 | 53 | 1.23 | partial | S -> S | - |
| N40 | live query | 3/64 | 3/29 | 3/54 | 22 | 1.32 | partial | S -> = | S -> = ; tokens 64 -> 29 |
| N41 | live query | 8/129 | 8/122 | 10/100 | 93 | 1.31 | partial | R* -> R* | tokens 129 -> 122; `ready_live(definitions)`; `Unattended.carers` is `U64` |
| N42 | live query | 3/85 | 3/78 | 10/100 | 93 | 0.84 | partial | R* -> R* | tokens 85 -> 78; `ready_live(definitions)` |
| N43 | live query | 3/59 | 3/56 | 9/153 | 121 | 0.46 | partial | R -> R | - |
| N44 | live query | 8/173 | 8/162 | 31/262 | 246 | 0.66 | partial | R -> R | tokens 173 -> 162; `ready_live(definitions)`; `Neglected` counts are `U64` |
| N45 | live query | 3/64 | 3/65 | 13/182 | 169 | 0.38 | partial | R -> R | - |
| N46 | live query | 2/60 | 2/57 | 4/94 | 62 | 0.92 | partial | = -> = | - |
| N47 | live query | 2/53 | 2/53 | 6/119 | 72 | 0.74 | full | R -> R | - |
| N48 | live query | 2/29 | 2/29 | 3/63 | 28 | 1.04 | full | = -> = | - |
| N49 | write | 0/0 | 0/0 | 11/283 | 163 | - | full | n/a -> n/a | - |
| N50 | write | 0/0 | 0/0 | 9/186 | 122 | - | partial | n/a -> n/a | - |
| N51 | write | 0/0 | 0/0 | 6/146 | 82 | - | full | n/a -> n/a | - |
| N52 | write | 0/0 | 0/0 | 8/174 | 119 | - | full | n/a -> n/a | - |
## 3. Where Roc is still weaker

Ranked as in round 1 (by IDs touched and by what the user writes). Paths: m = examples/main.roc, n = examples/monitoring.roc, c = examples/clinic/Clinic.roc, rm and rn = the Rust port. Status is the change since round 1.

| Rank r1 | Weakness | Status | IDs now | Roc now (file:line) | surreal_orm |
| --- | --- | --- | --- | --- | --- |
| 1 | Typed edge traversal with a filter and more hops | Mostly fixed in clauses. Still there for `outgoing` and `incoming`. | M28, M29 (R now), M95-M97 (= in section 5), N32-N34 (S, unchanged) | m:1032-1033, 1052 `owners_of_primary(treats.edges_from(v))` is read as `->treats[WHERE primary]->patient.owner.name` (main.surql:219). m:719 `outgoing(treats).select(\|(v, edges)\| { .., primary: edges.keep_if(\|e\| e.primary).len() })` is still a tuple and list code. The path is list code (`keep_if`, `map`), not a path value. | rm:852 `count!(Vet::schema().treats__(primary.eq(true)).id)` |
| 2 | No field-level write operators | Partly fixed | M86 (S, 80 against 40) | m:884 `medications.update_by(Clinic.low_stock, \|p, m\| { ..m, stock: m.stock + p.add })`, c:33-35. `RestockParam` and `refill` are gone, but the patch is still a whole-row record, and `low_stock` still needs an open-row type. M87-M90 are now R. No `append` or `remove` for a list field. | rm:1225 `.set(stock.increment_by(add)).where_(low_stock(floor))` |
| 3 | Open-row fragments need a full structural type | Partly fixed (Clinic.roc 55 -> 48 lines, `seen_before`, `too_old` removed, M91 now =) | M65 (226 tokens), M66 (203), M94 (434), M49 | c:26-31 `recent : Surreal.Query({ since : Surreal.Datetime, ..p }, { seen : Surreal.Datetime, ..r }) -> ..`; c:9-15 `dose_cost`, `bill` | rm:779 `fn recent(SelectStatement, since)`; a string field name, unchecked |
| 4 | Optional values and links need `match` | Fixed | M54 (S -> =), M62 (= -> R) | m:653-657 `o.?referred_by.map_ok(\|r\| r.get().name) ?? "nobody"`; m:684-688 `p.?chip.map_ok(\|c\| c.code) ?? "none"` (one line, was 10 and 14 lines). Still a call chain, not a `.name` path. | rm:656 `referred_by().name`; defaults applied in Rust after the read |
| 5 | No select-all or rest-spread | Fixed for whole rows. OMIT and spread are not there. | M70 (=), N22 (S -> =), N40 (S -> =), N28 (still S, 46 against 27) | m:749 `Surreal.from(vets).ready()`; n:372-376 view read with `ready()` | rn:407 `select(All)` |
| 6 | Per-table ceremony | Partly fixed | N07 (S -> =, 211 -> 139 tokens), M01, M03 (stars), N06 | n:104-121 one `definitions` list, no `x_def` values. Still `encoder_for : _` and `parser_for : _` at m:32-33, 49-50, and a handle plus annotation per table. | rn:172 `impl TableResources for Site {}` |
| 7 | Aggregates are list code | Partly fixed (no conversions). No aggregate call over a function result. | M78 (S*), M79 (=*), N12 (S, 112 against 90), N20 | m:417 `{ visits: rows.len(), revenue: rows.map(\|v\| v.fee).sum(), avg_fee: Surreal.Math.mean_dec(rows.map(\|v\| v.fee)) }`, `rows.len()` is `U64`. n:133 `rows.keep_if(\|v\| fever_fn.call2(..)).len()` | rm:904-907 `count!()`, `math::sum!(fee)`; rn:193 `count!(fever_fn(temp_c, pulse))` |
| 8 | Database-only functions need conversions | Still there | N30 (S), N31 (R) | n:388 `Surreal.Geo.inside(p.here.to_geometry(), s.area.to_geometry())`; n:393 `Geo.distance(s.location, p.here) < 50000` | rn:441 `area.contains(here)` |
| 9 | Record ranges only for a TimeKey | Still there | N15, N16, N18 (all =) | n:319 `.between(kennel_a, day_start, day_end)`; src/Surreal.roc:1981 `between : Query(p, { id : TimeKey(s), .. }), s, Datetime, Datetime`. A query takes one `between`. | rn:340 `.from(vital_id(a, start)..vital_id(a, end))` for any id |
| 10 | Captured-value queries need a second API | Still there | M75-M77, N39 (S, 65 against 53) | m:421-422 `cheaper_than : Dec -> Try(Surreal.Prepared(List(Medication)), Surreal.Error)` with `bind_captured` | rm:993 a function argument is the parameter |
| 11 | Server-made keys cost a row type, a handle, `default_by` | Still there (smaller: 185 -> 148 tokens) | M92 (S), M47 (R) | m:977-992 `Note`, `notes`, `new_notes`, `note_line` | rm:251-262 `SurrealUlid` (client side) |
| 12 | Fewer escape hatches | Still there | M15-M17, M43, N10, N19 | `Surreal.Unchecked` exists (src/Surreal.roc:2609), no raw DEFINE inside `define()` | rm:486 `Raw::new(..)` |

New or changed weak points in round 2:

| Point | Detail |
| --- | --- |
| Path written as list code | m:1058-1060 `treats.edges_to(p).keep_if(\|e\| e.primary).join_map(\|e\| treats.edges_from(e.from.get())).map(\|e\| e.to.get().name)` is 78 tokens for a two-hop path. Rust writes the same as one typed chain (rm:852-885 style, about 95 tokens counting `let` lines). Similar size, but Roc needs `join_map` and `.get()` at each hop. |
| Inline lambda repeats | A lambda in a query has no name, so a row shape used twice is written twice. See M64 and N27 (both S) in section 2. |
| Statement builders | IF, FOR, THROW, PARAM, INFO, SLEEP: not found in the examples, not re-checked in src/Surreal.roc. The user transaction block is now there (section 5). |

## 4. Where Roc is stronger

| Strength (round-1 rank) | IDs | Round 2 |
| --- | --- | --- |
| One function for DB and program (1) | M35, M40, M41, M45, M56, N08, N36 | Same. M69 is gone, M101 and M60 keep the idea. N08 and N10 are now R (`db_fn` and `.computed` in one line, n:56 tokens and 26). |
| Links as a type (2) | M14-M21, N03 | Same, all R. |
| Constraints in the row type (3) | M05-M12 | Same. M43 is now a field ASSERT on `fee` (main.surql:43), so the refusal names `field fee`, and it also refuses an update (M98). |
| Live queries (4) | N38-N46 | Same, 7 R of 11. `ready_live(definitions)` replaces `live({}, definitions)`. |
| Checked names and types (5) | M57, M60, M62-M66, N13, N17 | Same. M62, M60, M68, M73, M74 moved from = to R. |
| Function results compose (6) | N09-N12 | N10, N11 moved to R. |
| Time series and views (7), read rows (8), server keys and errors (9), newer SurrealDB (10) | N04, N13, N21, N32-N35, M47, M93 | Same. Error reporting is stronger than in round 1: `Surreal.transaction` reports `Aborted` with the statement place (src/Surreal.roc:2557-2562), where Rust `run()` gives `Ok` for a failed transaction. |
| Writes by lambda (new) | M87-M90 | A lambda patch removed the named patch functions: M87 39 tokens (was 54), M88 28, M89 38 (was 67), M90 15. All R now (were = or R). |
| Tuple-free counts (new) | M28, M29, M100 | `rows.len()` and `edges.len()` are `U64`, no `to_i64_wrap`. M28 108 -> 59 tokens, M29 119 -> 71. |

## 5. New features (not in the totals)

The port has no code for these IDs. The Rust column is my idiomatic sketch, not run (SurrealDB 1.5 only; things I could not check are named). Counts: same TOKEN regex, no execute wrapper, no fixtures in either side. Roc counts for C01-C04 leave out the `$run = check!(..)` test line and the fixture rows `spare_bin`, `rack_bin`.

| ID | Feature | Roc l/t | Rust l/t (sketch) | Ratio | Verdict | Rust sketch and note |
| --- | --- | --- | --- | --- | --- | --- |
| M95 | Graph path in a projection | 3/86 | 7/90 | 0.96 | = | `Vet::schema().treats__(primary.eq(true)).patient(E).owner(E).name.__as__("owners")` inside `select(arr![name, ..])`. Typed, edge filter in the path. Roc needs a helper `owners_of_primary` and `keep_if`, `map`, `.get()`. |
| M96 | Path of two edges, back then out | 1/78 | 7/95 | 0.82 | = | `Patient::schema().__treats(primary.eq(true)).vet(E).treats__(E).patient(E).name`. In round 1 the derive panicked on `relate` with `_` for the cares_for edge (N06); treats works. |
| M97 | Graph path in a filter | 3/93 | 5/95 | 0.98 | = | `.where_(Vet::schema().treats__(primary.eq(true)).patient(E).owner(E).address.city.contains("Oslo"))`. Not run: `contains` on a path result may need `Raw`. |
| M98 | Check over fields refused on update | 1/28 | 3/48 | 0.58 | R | `update::<Visit>(id).set(fee.equal_to(0))`. The rule is the raw event of M43 (rm:571-574). The THROW is lost, `run()` gives `Ok` (NOTES.md). |
| M99 | `ready()` for a query with no parameters | 0 own lines | 0 | - | n/a | Roc: 4 lines of other IDs end in `ready()`, 3 tokens shorter than `prepare({})`. Rust has no prepare step. |
| M100 | `U64` counts | 7/320 (shared lines) | 4/74 | - | =* | Rust: a `u64` field in each of the four row structs (`pub visits: u64`). `count!()` returns a number. The Roc count holds whole queries that other IDs share, so I do not use the ratio. |
| M101 | Filter on a union unit arm | 1/46 | 3/45 (round 1: M69 share 18/157 with the Rust twin `needs_attention`) | 1.02 | = | `.where_(Field::new("outcome.kind").not_equal("Treated"))`: a raw path, one copy in SurrealQL and one in Rust (rm:388-391). Roc: `v.outcome != Treated`, checked. |
| N53 | `U64` above `int` is sent as decimal | 1/46 | 3/59 | 0.78 | R | `.where_(Field::new("readings").greater_than_or_equal(u64::MAX))`. Not run: I do not know if the 1.x `sql::Number` wraps a `u64` above `i64::MAX`. |
| N54 | `U64` in group, read and live row types | 5/118 | 3/57 | 2.07 | =* | Rust: `u64` fields in `Daily`, `Unattended`, `Neglected`. The Roc count includes the function `day_line` (shared with N12), so the verdict is a reading, not the ratio. |
| N55 | `ready()` and `ready_live(definitions)` | 6/124 | n/a | - | n/a | Rust has `live(select(All).from(..))`, a statement builder. No runner, no snapshot, no notices (NOTES.md). Roc lines include the whole query. |
| C01 | `Surreal.transaction` of creates | 4/71 (all_of 2 lines, `spares_in_list` 2 lines) | 5/40 | 1.78 | S | `begin_transaction().query(create().content(spare_bin)).query(create().content(rack_bin)).commit_transaction().run(db)`. Rust does not give typed rows back and has no `all_of`. The Roc helper `all_of` is general (2 lines, once). |
| C02 | Transaction fails, all rolls back | 2/46 (`twins_in_list`, `all_of` shared with C01) | 5/40 | 1.15 | = | Same Rust code as C01 with `twin_bin`. `run()` returns `Ok` for a failed statement (NOTES.md), so Rust cannot report the failure. Roc gives `Aborted(1, ..)` (src/Surreal.roc:2557-2562). |
| C03 | `Surreal.migration(old, new)` with `DropData` | 6/131 | 4/34 | 3.85 | S* | Rust: `begin_transaction().query(remove_index("bin_label_unique").on_table(Bin::table())).commit_transaction().run(db)`, written by hand. Roc counts both schemas (`place_defs`, `loose_defs`) and `migrate`; Rust gets the old schema from the migrator CLI files (diff, up, down). Roc diffs two schema lists and drops data only with `DropData`. |
| C04 | Migration back fails on the twin row | 2/59 | 4/47 | 1.26 | = | `define_index(..).on_table(Bin::table()).fields(arr![label]).unique()` in a transaction. Again `run()` hides the error. |

Verdicts of the 14 new IDs: R 2 (M98, N53), = 8 (M95, M96, M97, M100, M101, N54, C02, C04), S 2 (C01, C03), n/a 2 (M99, N55). Not added to section 1.

## 6. Ideas from surreal_orm: status in round 2

| Idea (round 1) | Status | Evidence | What is left |
| --- | --- | --- | --- |
| Typed multi-hop traversal with an edge filter | Done for clauses | `Table.edges_from`, `Table.edges_to` (src/Surreal.roc:1155-1171). A filter and a next hop are in the path: `->treats[WHERE primary]->patient.owner.name` (main.surql:219, 226-228), in a projection (m:1052), a two-edge path (m:1058-1060) and a filter (m:1066-1067). | `outgoing`, `incoming` still give a tuple (m:719, 725). The path is list code, not a path value. No `count!(path)` call. |
| Typed aggregates | Partly done | `U64` counts (m:414-417), `Surreal.Math.mean_dec` (m:417). No `to_i64_wrap`, no `to_f64`. | No `Surreal.count(..)`, `sum`, `mean` call over a function result. N12 still S (n:133). |
| Migrations | Done in part | `Surreal.migration(old, new)` (src/Surreal.roc:1795), `Migration.prepare(DropData)`, one transaction, steps in src/Schema.roc. Test in client.roc:326-327, 392-399, 910-914: unpin a unique index, add it again, the second fails on a twin row. | No history table, no numbered up/down files, no snapshot text. analysis/migrations-design.md only designs these. |
| Transactions | Done | `Surreal.transaction : List(Prepared(out)) -> Try(Prepared(List(out)), Error)` (src/Surreal.roc:2581-2584), `Transaction.then`, `commit` (2567-2577). Rollback verified, error `Aborted` with the place. client.roc:373-390. | A transaction of different result types needs the `then` chain (nested pairs), not a list. |
| Record ranges of any id | Not done | Only `between(series, from, to)` on a TimeKey (src/Surreal.roc:1981, m:319 monitoring). | `id1..id2` for any `Id` type, inclusive and exclusive. |
| Field-level write operators | Partly done | Lambda patch with a literal `{ ..v, years: v.years + 1 }` (m:889-895). The DB text was already a field SET. | No `append`, `remove` for lists; `update_by` still needs the open-row `low_stock`. |
| Select all | Done for whole rows | `Query.select` is optional (m:749). | No OMIT. |
| Raw escape inside builders | Not done | `Surreal.Unchecked` (src/Surreal.roc:2609). | `Unchecked.expr` in `define()` and clauses. |
| Permissions in the examples | Not done | No `permit` in examples/main.roc or monitoring.roc (grep). The API exists (src/Surreal.roc:1690). | An example and a test. |
| Statement builders IF, FOR, THROW, PARAM | Not done | Not found. User transactions are done. | |
| Per-field attributes in the type | Not done (style) | Rules stay in one `definitions` list (m:345-391). | |
