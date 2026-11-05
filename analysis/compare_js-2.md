# ORM comparison round 2: Roc reify-surrealdb and the SurrealDB JS SDK 2.2.2 (TypeScript)

Scope: the 145 features that exist in both rounds (M01-M94 without M69, N01-N52). New IDs (M95-M101, N53-N55, C01-C04) are in section 5 only and are not in any total. Removed ID: M69 (moved to M101 and M60).
Port side: unchanged (SCRATCH/adj copy of SCRATCH/js/src, same slices and counts as round 1). Roc side: catalog-2 ranges.

## 0. Method (same as round 1)

| Item | Rule |
|---|---|
| Lines, tokens, chars | Code lines only. Tokens by the round-1 token regex. Chars are non-space characters. |
| Verdict | Chars. Similar when the two values differ by 20 percent of the larger value or less. Else the smaller side is shorter. I checked this rule on round 1: it gives all 100 round-1 verdicts that have no star. A star means a manual change after reading the code. |
| Roc slices | Catalog-2 ranges, minus the harness (H) and fixture (F) ranges of catalog-2 section 3. Wrappers `block(`, `plain(`, `rejects(`, `then_read(` read-back, `Surreal.Mirror.*`, `live_block(` and the `match` wrappers of the last two live blocks (monitoring.roc:886-897) are removed by script. Same rules as round 1. Scripts: SCRATCH/jsr2/new.py (round 2) and SCRATCH/jsr2/rocslice_old.py (round 1 again, from git HEAD: it gives the same 146 round-1 slices). |
| Verdict of a Roc entry whose code did not change | Carried over from round 1 (code compared after white space is removed). 67 of 145 entries are unchanged. |
| Verdict of a changed entry | Rule above. I set 13 by reading (a star). The reasons are in the notes. |
| Spot check of roc_counts_2.json | The file is written by another comparer. I compared all 159 entries with my slices. 153 are equal. 6 differ: M48 and N07 (I keep the 5-line `schema_block` that round 1 kept), N02 and N05 (I keep the `insert(seed)` argument, which catalog-2 section 3 calls feature), N47 and N48 (their slices keep the live_block `match` wrapper lines, which are harness). Their file is not changed. |
| Round-1 Roc union chars | The round-1 report says 23136. A new run of the round-1 script gives 20913 non-space chars (479 lines, 7319 tokens, as in the report). Both rounds below use the new run. |

## 1. Totals, same feature set (145 IDs)

Sum over IDs repeats shared code (as round 1 section 1). Union counts each Roc source line once (set of file and line) and uses the JS feature union of round 1 (551 lines).

| Measure | Round 1 | Round 2 | Change |
|---|---|---|---|
| Roc lines, sum | 619 | 514 | -17 percent |
| Roc tokens, sum | 10170 | 9423 | -7 percent |
| Roc chars, sum | 28458 | 25449 | -11 percent |
| JS lines / tokens / chars, sum | 1253 / 8901 / 52952 | same | 0 |
| Ratio Roc / JS, lines | 0.49 | 0.41 | |
| Ratio Roc / JS, tokens | 1.14 | 1.06 | |
| Ratio Roc / JS, chars | 0.54 | 0.48 | |
| Roc lines, union | 472 | 383 | -19 percent |
| Roc tokens, union | 7275 | 6505 | -11 percent |
| Roc chars, union | 20742 | 18017 | -13 percent |
| JS lines / tokens / chars, union (feature code) | 551 / 4571 / 25596 | same | 0 |
| Ratio Roc / JS, union lines | 0.86 | 0.70 | |
| Ratio Roc / JS, union tokens | 1.59 | 1.42 | |
| Ratio Roc / JS, union chars | 0.81 | 0.70 | |
| Verdict: Roc shorter | 48 | 60 | +12 |
| Verdict: similar | 59 | 68 | +9 |
| Verdict: JS shorter | 36 | 15 | -21 |
| Verdict: n/a | 2 | 2 | 0 |

Source-level counts (grep of top-level lines in examples/main.roc and examples/monitoring.roc):

| Item | Round 1 | Round 2 |
|---|---|---|
| Top-level record type lines (rows, result types, parameter types) | 54 (main 34, monitoring 20) | 33 (main 18, monitoring 15) |
| `.to_i64_wrap()` | 14 | 0 |
| `.prepare({})` | 58 | 0 (`.ready()`: 62) |

Entries whose Roc code changed: 78 of 145. Verdict moves among them:

| Move | IDs |
|---|---|
| JS shorter to Roc shorter (7) | M28, M63, M71, M73, M74, M81, N34 |
| JS shorter to similar (14) | M29, M45, M50, M54, M58, M62, M68, M79, M87, M88, M89, M91, M49, M57 |
| similar to Roc shorter (6) | M70, N08, N20, N22, N28, N29 |
| Roc shorter to similar (1) | N27 (named helper moved into the query: 121 to 194 chars) |
| No move (50) | all other changed entries |

Marginal moves (difference close to the 20 percent line): M45, M58, N08, M64 (stays similar).

By category (chars are the sum over IDs). Verdicts are Roc shorter / similar / JS shorter / n/a.

| Category | IDs | Roc chars r1 | Roc chars r2 | JS chars | Verdicts r1 | Verdicts r2 |
|---|---|---|---|---|---|---|
| row type | 13 | 3089 | 3089 | 11460 | 7/5/1/0 | 7/5/1/0 |
| link | 10 | 749 | 749 | 9439 | 6/4/0/0 | 6/4/0/0 |
| edge | 8 | 1446 | 1079 | 2569 | 2/4/2/0 | 3/5/0/0 |
| schema constraint | 18 | 1632 | 1527 | 3245 | 5/12/1/0 | 5/13/0/0 |
| other | 4 | 3885 | 3198 | 1044 | 0/1/3/0 | 0/1/3/0 |
| query-filter | 18 | 2939 | 2827 | 3316 | 7/8/3/0 | 8/9/1/0 |
| projection | 16 | 3628 | 3043 | 3871 | 1/5/10/0 | 6/9/1/0 |
| group-aggregate | 7 | 1747 | 1587 | 1885 | 2/2/3/0 | 3/3/1/0 |
| write | 15 | 2578 | 2167 | 4451 | 4/4/6/1 | 4/8/2/1 |
| geometry | 5 | 736 | 669 | 1559 | 1/3/1/0 | 2/2/1/0 |
| time series | 9 | 1186 | 1192 | 2714 | 4/5/0/0 | 4/5/0/0 |
| db function | 5 | 1067 | 867 | 1232 | 0/4/1/0 | 1/3/1/0 |
| view | 2 | 270 | 156 | 487 | 1/1/0/0 | 2/0/0/0 |
| read row | 4 | 958 | 857 | 799 | 0/0/3/1 | 1/0/2/1 |
| live query | 11 | 2548 | 2442 | 4881 | 8/1/2/0 | 8/1/2/0 |

## 2. Per feature

Columns: Roc round 1 and round 2 and JS as lines/tokens/chars. Round 1 and Round 2 are the verdicts. Change is shown only when the Roc code of the ID changed. The JS port and its counts are the same in both rounds. Notes name the cause of the change. Many entries moved because a `.prepare({})` became `.ready()` or a named function became a lambda.

| ID | Category | Roc r1 l/t/c | Roc r2 l/t/c | JS l/t/c | Round 1 | Round 2 | Change | Note |
|---|---|---|---|---|---|---|---|---|
| M01 | row type | 8/95/245 | 8/95/245 | 22/99/329 | similar* | similar* | - |  |
| M02 | row type | 22/155/469 | 22/155/469 | 73/431/1697 | Roc shorter | Roc shorter | - |  |
| M03 | row type | 16/135/541 | 16/135/541 | 16/131/772 | similar* | similar* | - |  |
| M04 | row type | 3/68/161 | 3/68/161 | 41/194/1191 | Roc shorter | Roc shorter | - |  |
| M05 | row type | 2/81/193 | 2/81/193 | 19/85/470 | similar* | similar* | - |  |
| M06 | row type | 3/61/165 | 3/61/165 | 26/88/897 | Roc shorter | Roc shorter | - |  |
| M07 | row type | 1/48/115 | 1/48/115 | 15/51/598 | similar* | similar* | - |  |
| M08 | row type | 4/48/140 | 4/48/140 | 40/229/1382 | Roc shorter | Roc shorter | - |  |
| M09 | row type | 6/133/339 | 6/133/339 | 23/61/1173 | Roc shorter | Roc shorter | - |  |
| M10 | row type | 4/59/190 | 4/59/190 | 12/76/323 | similar* | similar* | - |  |
| M11 | row type | 5/64/197 | 5/64/197 | 37/212/979 | Roc shorter | Roc shorter | - |  |
| M12 | row type | 3/73/188 | 3/73/188 | 40/248/1374 | Roc shorter | Roc shorter | - |  |
| M13 | row type | 3/35/146 | 3/35/146 | 10/67/275 | JS shorter* | JS shorter* | - |  |
| M14 | link | 3/24/75 | 3/24/75 | 22/131/860 | Roc shorter | Roc shorter | - |  |
| M15 | link | 2/20/56 | 2/20/56 | 40/131/1694 | Roc shorter | Roc shorter | - |  |
| M16 | link | 4/48/140 | 4/48/140 | 49/146/2316 | Roc shorter | Roc shorter | - |  |
| M17 | link | 1/32/81 | 1/32/81 | 35/108/1487 | Roc shorter | Roc shorter | - |  |
| M18 | link | 2/55/139 | 2/55/139 | 11/49/290 | similar* | similar* | - |  |
| M19 | link | 3/36/102 | 3/36/102 | 20/136/594 | similar* | similar* | - |  |
| M20 | link | 2/14/54 | 2/14/54 | 3/15/259 | similar* | similar* | - |  |
| M21 | link | 2/14/53 | 2/14/53 | 20/8/1123 | Roc shorter | Roc shorter | - |  |
| M22 | link | 0/0/0 | 0/0/0 | 9/47/160 | similar* | similar* | - |  |
| M23 | edge | 3/53/166 | 3/53/166 | 15/44/488 | similar* | similar* | - |  |
| M24 | edge | 1/6/26 | 1/6/26 | 10/83/292 | similar* | similar* | - |  |
| M25 | edge | 1/15/46 | 1/15/46 | 1/2/80 | Roc shorter | Roc shorter | - |  |
| M26 | edge | 1/20/33 | 1/20/33 | 1/2/74 | Roc shorter | Roc shorter | - |  |
| M27 | edge | 4/63/154 | 4/63/154 | 1/30/97 | similar* | similar* | - |  |
| M28 | edge | 4/108/288 | 1/59/139 | 3/34/192 | JS shorter | Roc shorter | JS shorter -> Roc shorter | Lambda in the query; `CaseLoad`, `case_load` removed; `U64`. |
| M29 | edge | 4/119/294 | 1/71/156 | 3/36/180 | JS shorter | similar | JS shorter -> similar | Lambda; `TeamLine`, `team_line` removed; `U64`. |
| M30 | schema constraint | 1/10/19 | 1/10/19 | 1/2/72 | Roc shorter | Roc shorter | - |  |
| M31 | schema constraint | 1/24/53 | 1/24/53 | 1/2/94 | Roc shorter | Roc shorter | - |  |
| M32 | schema constraint | 1/12/27 | 1/12/27 | 1/2/76 | Roc shorter | Roc shorter | - |  |
| M33 | schema constraint | 1/20/39 | 1/20/39 | 1/2/86 | Roc shorter | Roc shorter | - |  |
| M34 | schema constraint | 3/32/58 | 3/32/58 | 3/2/170 | Roc shorter | Roc shorter | - |  |
| M35 | schema constraint | 3/37/116 | 3/37/116 | 2/2/128 | similar | similar | - |  |
| M36 | schema constraint | 1/20/46 | 1/20/46 | 1/2/107 | similar* | similar* | - |  |
| M37 | schema constraint | 1/24/55 | 1/24/55 | 3/2/187 | similar* | similar* | - |  |
| M38 | schema constraint | 1/18/32 | 1/18/32 | 1/2/102 | similar* | similar* | - |  |
| M39 | schema constraint | 4/58/153 | 4/58/153 | 9/4/649 | similar* | similar* | - |  |
| M40 | schema constraint | 6/44/144 | 6/44/144 | 3/2/216 | similar* | similar* | - |  |
| M41 | schema constraint | 6/51/142 | 6/51/142 | 4/2/285 | similar* | similar* | - |  |
| M42 | schema constraint | 6/73/179 | 6/73/179 | 4/8/268 | similar* | similar* | - |  |
| M43 | schema constraint | 3/48/147 | 3/48/147 | 3/2/174 | similar | similar | - |  |
| M44 | schema constraint | 1/10/23 | 1/10/23 | 1/2/107 | similar* | similar* | - |  |
| M45 | schema constraint | 7/56/179 | 3/40/107 | 1/2/98 | JS shorter | similar | JS shorter -> similar | named fn or type replaced by a lambda; no `*_def` frame |
| M46 | schema constraint | 1/13/27 | 1/13/27 | 3/4/244 | similar* | similar* | - |  |
| M47 | schema constraint | 5/73/193 | 4/66/160 | 7/39/182 | similar | similar | same | no `*_def` frame |
| M48 | other | 60/564/1611 | 51/549/1434 | 2/23/87 | JS shorter | JS shorter | same | One `definitions` list; the 7 `*_def` values are gone (main.roc:345-391). JS: one DEFINE TABLE line counted. |
| M49 | query-filter | 4/69/187 | 1/51/123 | 9/40/212 | JS shorter* | similar* | JS shorter* -> similar* | Roc is 1 line (`filter_by(|p, o| ..)`). JS block is shared with M50, M51 (type, SELECT, bound city). |
| M50 | projection | 4/86/225 | 4/100/245 | 9/40/212 | JS shorter* | similar | JS shorter* -> similar | other lines only |
| M51 | projection | 3/74/170 | 4/80/197 | 9/40/212 | similar | similar | same | other lines only |
| M52 | query-filter | 3/41/116 | 1/30/81 | 3/75/192 | Roc shorter | Roc shorter | same | Lambda; `is_vip` removed. |
| M53 | query-filter | 1/32/88 | 1/63/135 | 4/34/158 | similar* | similar | similar* -> similar | `ready()`; lambda `map_ok(..) ?? "nobody"` is inline. |
| M54 | projection | 10/90/234 | 1/63/135 | 4/34/158 | JS shorter | similar | JS shorter -> similar | `match` function `referral_line` (10 lines) is now `map_ok(..) ?? "nobody"` in a lambda (main.roc:653-657). |
| M55 | projection | 4/76/201 | 4/74/197 | 12/72/497 | similar* | similar* | same | JS block shared with M56-M57. |
| M56 | projection | 9/94/257 | 9/92/253 | 8/34/269 | similar | similar | same | `ready()` |
| M57 | projection | 4/109/281 | 4/149/349 | 13/80/524 | JS shorter* | similar* | JS shorter* -> similar* | Roc: `Clinic.by_id` annotation (Clinic.roc:45-47). JS block holds the CASE text that Roc counts under M40/M60. |
| M58 | query-filter | 3/33/97 | 3/31/93 | 2/21/77 | JS shorter | similar | JS shorter -> similar | `ready()` |
| M59 | query-filter | 1/37/91 | 1/37/91 | 2/31/99 | similar | similar | - |  |
| M60 | query-filter | 6/62/170 | 6/60/166 | 2/45/153 | similar | similar | same | `ready()` |
| M61 | projection | 3/99/249 | 3/93/237 | 4/67/245 | similar | similar | same | `ready()` |
| M62 | projection | 14/106/245 | 1/70/148 | 3/34/185 | JS shorter | similar | JS shorter -> similar | `chip_line` (14 lines) is now `map_ok` and `??` in a lambda. |
| M63 | projection | 4/76/216 | 1/51/119 | 3/32/172 | JS shorter | Roc shorter | JS shorter -> Roc shorter | Lambda; `VaccineLine`, `vaccine_line` removed. |
| M64 | query-filter | 3/53/174 | 3/82/211 | 3/32/172 | similar | similar | same | Marginal: 211 against 172 chars (22 percent of the larger). |
| M65 | query-filter | 10/225/629 | 7/226/577 | 9/113/557 | similar | similar | same | `SinceParam` and `seen_before` removed. |
| M66 | projection | 7/198/454 | 5/203/471 | 5/46/331 | JS shorter | JS shorter | same | `visit_line` is a reference helper only. |
| M67 | query-filter | 1/40/91 | 1/38/87 | 2/38/128 | Roc shorter | Roc shorter | same | `ready()` |
| M68 | projection | 10/93/337 | 7/79/254 | 7/30/261 | JS shorter | similar | JS shorter -> similar | `outcome_line` removed; `outcome_text` stays (main.roc:146). |
| M70 | projection | 1/20/49 | 1/10/26 | 2/12/45 | similar | Roc shorter | similar -> Roc shorter | `select_value(|v| v)` is `Surreal.from(vets).ready()`. |
| M71 | projection | 4/69/178 | 1/47/94 | 3/30/137 | JS shorter | Roc shorter | JS shorter -> Roc shorter | Lambda select in the query. |
| M72 | projection | 1/39/91 | 1/37/87 | 8/34/281 | Roc shorter | Roc shorter | same | `ready()` |
| M73 | projection | 4/89/230 | 1/60/124 | 3/36/177 | JS shorter | Roc shorter | JS shorter -> Roc shorter | Lambda; `ContactLine` removed. |
| M74 | projection | 4/83/211 | 1/54/107 | 3/36/165 | JS shorter | Roc shorter | JS shorter -> Roc shorter | Lambda; `LinkedRows` removed. |
| M75 | query-filter | 3/50/186 | 3/50/186 | 3/30/104 | JS shorter | JS shorter | - |  |
| M76 | query-filter | 3/56/192 | 3/56/192 | 3/55/179 | similar | similar | - |  |
| M77 | query-filter | 4/55/193 | 4/55/193 | 5/77/264 | Roc shorter | Roc shorter | - |  |
| M78 | group-aggregate | 4/145/355 | 4/135/332 | 4/38/247 | JS shorter | JS shorter | same | `U64` count, no `to_i64_wrap`. |
| M79 | group-aggregate | 2/115/269 | 2/105/246 | 4/38/247 | JS shorter* | similar | JS shorter* -> similar | `Math.mean_dec`. |
| M80 | group-aggregate | 1/50/122 | 1/48/118 | 4/38/247 | similar* | similar* | same | Roc range is the whole query line shared with M78-M79. |
| M81 | group-aggregate | 4/102/278 | 1/65/145 | 3/34/197 | JS shorter | Roc shorter | JS shorter -> Roc shorter | Lambda in `totals(..)`, `VisitTotals` removed, `U64`. |
| M82 | group-aggregate | 1/44/102 | 1/38/84 | 3/26/133 | Roc shorter | Roc shorter | same | Lambda, `U64`. |
| M83 | write | 6/36/166 | 6/36/166 | 10/83/292 | similar* | similar* | - |  |
| M84 | write | 1/6/20 | 1/6/20 | 1/19/70 | Roc shorter | Roc shorter | - |  |
| M85 | write | 2/25/95 | 2/25/95 | 1/19/93 | similar | similar | - |  |
| M86 | write | 6/94/256 | 3/80/175 | 1/9/110 | JS shorter | JS shorter | same | Patch is a lambda; `RestockParam`, `refill` removed. |
| M87 | write | 3/54/138 | 1/39/90 | 1/9/102 | JS shorter | similar | JS shorter -> similar | `set_at` with a lambda patch. |
| M88 | write | 3/39/107 | 1/28/68 | 1/20/68 | JS shorter | similar | JS shorter -> similar | Lambda patch; `renamed` removed. |
| M89 | write | 3/67/168 | 1/38/94 | 4/41/126 | JS shorter | similar* | JS shorter -> similar* | Roc patch is one lambda; `no_phone` (main.roc:626-628, fixture, not counted) types the `Err`. JS: 2 patch ops. |
| M90 | write | 1/17/47 | 1/15/43 | 2/22/81 | similar* | similar* | same | JS block holds 2 deletes. |
| M91 | write | 3/62/171 | 1/26/63 | 1/9/69 | JS shorter | similar | JS shorter -> similar | Lambda in `delete_by`; `Clinic.too_old` removed. |
| M92 | write | 11/185/492 | 9/148/395 | 6/37/121 | JS shorter | JS shorter | same | named fn or type replaced by a lambda; no `*_def` frame |
| M93 | write | 24/234/918 | 25/254/958 | 24/398/1374 | Roc shorter | Roc shorter | same | 25 refusals (was 24); M98 adds the update form. |
| M94 | other | 22/511/1227 | 18/434/1024 | 11/129/674 | JS shorter | JS shorter | same | Clinic.roc is 48 lines (was 55); `seen_before`, `too_old` removed. |
| N01 | geometry | 1/23/66 | 1/23/66 | 6/73/453 | Roc shorter | Roc shorter | - |  |
| N02 | geometry | 7/91/221 | 7/91/221 | 16/237/712 | similar* | similar* | - |  |
| N03 | link | 1/20/49 | 1/20/49 | 10/75/656 | Roc shorter | Roc shorter | - |  |
| N04 | time series | 1/29/80 | 1/29/80 | 5/102/401 | Roc shorter | Roc shorter | - |  |
| N05 | time series | 3/59/172 | 3/59/172 | 11/113/394 | Roc shorter | Roc shorter | - |  |
| N06 | edge | 10/130/439 | 8/116/359 | 25/233/1166 | similar* | similar* | same | JS block is shared. |
| N07 | other | 25/211/818 | 19/167/529 | 2/23/93 | JS shorter | JS shorter | same | One `definitions` list (monitoring.roc:104-121). JS: 1 statement counted. |
| N08 | db function | 5/76/270 | 5/56/165 | 6/51/260 | similar | Roc shorter | similar -> Roc shorter | other lines only |
| N09 | db function | 1/36/95 | 1/34/91 | 4/41/180 | similar* | similar* | same | JS block is shared. |
| N10 | db function | 6/54/149 | 1/26/59 | 7/36/335 | similar* | similar* | same | JS block is shared. |
| N11 | db function | 4/79/217 | 3/102/248 | 8/75/325 | similar* | similar* | same | Roc cited `flag_line` is a reference helper now (monitoring.roc:216-218); the query has the lambda. |
| N12 | db function | 4/122/336 | 4/112/304 | 2/40/132 | JS shorter | JS shorter | same | `U64` counts, no `to_i64_wrap`. |
| N13 | time series | 4/106/281 | 4/104/277 | 9/150/530 | similar* | similar* | same | JS block is shared. |
| N14 | time series | 4/79/217 | 3/102/248 | 5/39/243 | similar | similar | same | `ready()` |
| N15 | time series | 1/26/87 | 1/24/83 | 5/112/317 | Roc shorter | Roc shorter | same | `ready()` |
| N16 | time series | 1/29/81 | 1/19/64 | 3/44/168 | Roc shorter | Roc shorter | same | `select(|r| r)` removed. |
| N17 | time series | 3/66/164 | 3/66/164 | 10/49/504 | similar* | similar* | - |  |
| N18 | time series | 1/30/71 | 1/30/71 | 1/9/87 | similar | similar | - |  |
| N19 | time series | 1/12/33 | 1/12/33 | 1/2/70 | similar* | similar* | - |  |
| N20 | group-aggregate | 7/188/500 | 7/178/468 | 11/82/619 | similar | Roc shorter | similar -> Roc shorter | no to_i64_wrap; `ready()` |
| N21 | view | 4/45/164 | 3/38/129 | 9/51/392 | Roc shorter | Roc shorter | same | `daily_def` removed. |
| N22 | view | 1/44/106 | 1/10/27 | 2/23/95 | similar | Roc shorter | similar -> Roc shorter | `select(|d| ..)` removed, `ready()`. |
| N23 | query-filter | 1/36/95 | 1/34/91 | 4/41/180 | Roc shorter | Roc shorter | same | `ready()` |
| N24 | query-filter | 1/36/100 | 1/34/96 | 2/26/141 | Roc shorter | Roc shorter | same | `ready()` |
| N25 | query-filter | 1/46/109 | 1/44/105 | 4/41/225 | Roc shorter | Roc shorter | same | `ready()` |
| N26 | query-filter | 1/47/103 | 1/45/99 | 2/21/145 | Roc shorter | Roc shorter | same | `ready()` |
| N27 | group-aggregate | 1/46/121 | 1/89/194 | 4/33/195 | Roc shorter | similar | Roc shorter -> similar | Lambdas inline; helpers `hot_line`, `kennel_fevers` are reference only. |
| N28 | query-filter | 1/54/133 | 1/46/120 | 4/28/151 | similar | Roc shorter | similar -> Roc shorter | `select(|r| r)` removed. |
| N29 | geometry | 4/56/136 | 1/34/69 | 3/48/123 | similar | Roc shorter | similar -> Roc shorter | Lambda; `site_lat` removed. |
| N30 | geometry | 3/71/189 | 3/71/189 | 2/40/130 | JS shorter | JS shorter | - |  |
| N31 | geometry | 1/50/124 | 1/50/124 | 2/22/141 | similar | similar | - |  |
| N32 | read row | 4/127/347 | 4/121/329 | 7/48/260 | JS shorter | JS shorter | same | no to_i64_wrap; `ready()` |
| N33 | read row | 3/140/351 | 3/134/333 | 7/48/260 | JS shorter | JS shorter | same | no to_i64_wrap; `ready()` |
| N34 | read row | 1/82/187 | 1/76/169 | 7/48/260 | JS shorter* | Roc shorter | JS shorter* -> Roc shorter | `U64`, no `to_i64_wrap` (old JS shorter* reason is gone). |
| N35 | read row | 2/12/73 | 1/5/26 | 0/0/19 | n/a* | n/a* | same | JS: not possible. Roc: `define_read()`. |
| N36 | other | 3/93/229 | 3/87/211 | 3/30/190 | similar | similar | same | no to_i64_wrap; `ready()` |
| N37 | query-filter | 3/73/185 | 3/71/181 | 3/22/179 | similar | similar | same | `ready()` |
| N38 | live query | 3/56/170 | 3/53/173 | 11/88/542 | Roc shorter | Roc shorter | same | `ready_live(definitions)`. |
| N39 | live query | 3/65/200 | 3/65/200 | 12/104/583 | Roc shorter | Roc shorter | - |  |
| N40 | live query | 3/64/186 | 3/29/114 | 4/114/294 | Roc shorter | Roc shorter | same | `ready_live`; `select(|d| ..)` removed. |
| N41 | live query | 8/129/410 | 8/122/399 | 12/59/592 | Roc shorter | Roc shorter | same | `ready_live`; `U64`. |
| N42 | live query | 3/85/250 | 3/78/239 | 2/9/45 | similar* | similar* | same | JS reuses the N41 function (2 lines). |
| N43 | live query | 3/59/189 | 3/56/192 | 7/61/550 | Roc shorter | Roc shorter | same | `ready_live` |
| N44 | live query | 8/173/511 | 8/162/486 | 12/83/725 | Roc shorter | Roc shorter | same | `ready_live`; `U64`. |
| N45 | live query | 3/64/192 | 3/65/196 | 8/63/480 | Roc shorter | Roc shorter | same | `ready_live` |
| N46 | live query | 2/60/167 | 2/57/170 | 17/122/911 | Roc shorter | Roc shorter | same | `ready_live` |
| N47 | live query | 2/53/168 | 2/53/168 | 2/23/95 | JS shorter | JS shorter | - |  |
| N48 | live query | 2/29/105 | 2/29/105 | 2/19/64 | JS shorter | JS shorter | - |  |
| N49 | write | 0/0/0 | 0/0/0 | 13/160/371 | Roc shorter* | Roc shorter* | - |  |
| N50 | write | 0/0/0 | 0/0/0 | 13/160/371 | Roc shorter* | Roc shorter* | - |  |
| N51 | write | 0/0/0 | 0/0/0 | 13/160/371 | similar* | similar* | - |  |
| N52 | write | 0/0/0 | 0/0/0 | 21/223/832 | n/a | n/a | - |  |

## 3. Where Roc is still weaker

Ranked by the number of IDs that stay "JS shorter" and by the gap in chars. Status is for the round-1 weakness of the same topic. Round-1 rank is in brackets.

| Rank | Topic and IDs | Roc (round 2) | JS | Status |
|---|---|---|---|---|
| 1 | Open-row helpers with long annotations. M94 1024 chars against 674, M66 471 against 331 (M57 is now similar*). (r1 rank 5) | examples/clinic/Clinic.roc:14 `bill : { fee : Dec, items : List({ doses : I64, medication : Surreal.Link({ unit_price : Dec, ..m }), ..d }), ..r } -> Dec`; :45-47 `by_id : Surreal.Selected(p, { id : Str, ..r }) -> ..`. Clinic.roc is 48 lines (55) | main.ts:401 `const bill = raw("fee + math::sum(..)")`; :404 `const byId = raw("ORDER BY id")` | Partly fixed. `seen_before`, `too_old` and the `RetentionParam` types are gone. The annotations stay. JS helpers are unchecked strings. |
| 2 | Schema frame and table handles. M48 1434 chars (JS 87 counts one DEFINE TABLE statement), N07 529 against 93, M03 similar*. (r1 rank 6) | examples/main.roc:345-391 one `definitions` list, still one `x.define()...done()` chain per table; :95-118 a type line and a handle line per table; monitoring.roc:104-121 | main.ts:143-150 one DEFINE TABLE statement for 7 tables; :129-135 one `new Table<..>` line per table | Partly fixed. The 7 `*_def : Surreal.Defined` values and their 3-line frame are gone (M48 1611 to 1434 chars, N07 818 to 529, M45 loses 4 lines). JS count is small because its DEFINE text is shared by all constraint IDs, so this rank overstates the gap. |
| 3 | A read row is a second row type, a second handle and a schema check. N32 329 against 260, N33 333 against 260. (r1 rank 8) | examples/monitoring.roc:76-84 `CareRead`, `KennelRead`, `kennel_reads`; :120 `kennel_reads.define_read()` | monitoring.ts:325-330 `<-cares_for.in.{ id: record::id(id), name } AS carers` | Partly fixed. N34 is now Roc shorter (no `to_i64_wrap`, one lambda line). The two types and the handle stay. N35 stays n/a (JS cannot check). |
| 4 | No Pick or Omit. M13 146 against 275 (JS shorter*), M92 395 against 121. (r1 rank 7) | examples/main.roc:53-55 `MedicationForm` lists 4 fields again; :108-109 second handle; :977-992 `Note`, `new_notes : List({ vet : .., text : Str })` | main.ts:75 `Pick<Medication, ..>`; :832 `Omit<Note, "id">[]` | Partly fixed for M92 (492 to 395: `note_def` frame gone). M13 unchanged. |
| 5 | Updates and deletes with a parameter. M86 175 against 110. (r1 rank 3) | examples/main.roc:884 `medications.update_by(Clinic.low_stock, \|p, m\| { ..m, stock: m.stock + p.add }).prepare({ floor: 60, add: 100 })` | main.ts:748 `UPDATE medication SET stock = stock + ${refill.add} WHERE ${lowStock(refill.floor)}` | Mostly fixed. `RestockParam` and `refill` are gone. M87, M88, M89, M91 move from JS shorter to similar (lambda patches at :895, :917, :962). M86 stays JS shorter. M89 still needs `no_phone` (main.roc:626-628, fixture, not counted). |
| 6 | Captured queries and watches need annotations. N47 168 against 95, N48 105 against 64, M75 186 against 104. (r1 rank 10) | examples/monitoring.roc:488-494 `Try(Surreal.RawWatch(VitalLine), Surreal.Error)`, `.live_raw({})`, `Try(Surreal.DiffWatch(Vital), Surreal.Error)`, `.live_diff({})`; main.roc:421 `cheaper_than : Dec -> Try(Surreal.Prepared(List(Medication)), Surreal.Error)` | monitoring.ts:635 `db.live<Vital>(vitals).diff()`; main.ts:598 `db.select(medications).where(lt("unit_price", limit))` | Still there. `ready_live(definitions)` (monitoring.roc:425-486) replaced `live({}, definitions)` for 8 watches. The live entries keep their verdicts: 8 Roc shorter, 1 similar (N42), 2 JS shorter (N47, N48). The raw and diff forms did not change. |
| 7 | Group and aggregate need a result type. M78 332 against 247, N12 304 against 132. (r1 rank 9 for the count part) | examples/main.roc:413-417 `Ledger : { vet : Str, visits : U64, .. }` and `ledger_line`; monitoring.roc:125-134 `DayKey`, `day_of`, `Daily`, `day_line` | main.ts GROUP BY text; JS `number` types | Partly fixed. `U64` counts need no conversion. The record type of the group stays. M79, M80, M81, M82 are now similar or Roc shorter. |
| 8 | Functions that run only in the database. N30 189 against 130. (r1 rank 11) | examples/monitoring.roc:388 `Surreal.Geo.inside(p.here.to_geometry(), s.area.to_geometry())`; the reference result is typed by hand | monitoring.ts:310 `where(contains("area", here))` with a cast | Still there. Not changed. |
| 9 | Named projection types and functions. Remaining named result types: OwnerCard, PetLine, StockLine, SpecialtyLine, ReachLine, EdgeLine. (r1 rank 1) | examples/main.roc:398-402, 405-409, 436, 441, 446, 451. A lambda is now inline where used once: main.roc:657 `.select(\|o\| { id: o.id, by: o.?referred_by.map_ok(\|r\| r.get().name) ?? "nobody" })` | main.ts:434, 476-477 inline `AS` aliases and a cast | Mostly fixed. 10 projection entries were JS shorter, now 1 (M66). Top-level record types 54 to 33. A reused projection still needs a name. |
| 10 | Tag unions need `match` functions. M40, M41, M56, M60, M68. (r1 rank 4) | examples/main.roc:137-143 `species_label` (7 lines), :145-150 `outcome_text`, :152-156 `wide_wings` | main.ts:444-446 IF chain (unchecked) | Partly fixed. `needs_attention` is gone: M101 is `v.outcome != Treated` (main.roc:713). The other match functions are the same. |
| 11 | Edit values need the old row. N49, N50, N52 (n/a). (r1 rank 12) | examples/monitoring.roc:512 `Replace(hot, cooled)` | monitoring.ts:395-403 `replace(cooled)` plus 4 helpers | Still there. Not changed. Counts are 0 (fixture). |
| 12 | Scope: no connection code in the two examples. (r1 rank 13) | examples/main.roc:994-997 and monitoring.roc: `main!` echoes a script. examples/client.roc:637-653 has `Session.open!` over WebSocket or HTTP, and C01-C04 | 51 setup lines in the port | Partly fixed. A client example now exists with transport, transactions and migrations. The two feature examples are still script printers. |
| 13 | Optional chaining through a link. M53, M54, M62. (r1 rank 2) | examples/main.roc:657 `o.?referred_by.map_ok(\|r\| r.get().name) ?? "nobody"` | main.ts:434 `referred_by.name AS by` | Mostly fixed. One line (was a 10-line `match` in `referral_line`, 14 lines in `chip_line`). `map_ok` and `get()` are still more words than `referred_by.name`. M54 and M62 move to similar. |
| 14 | Integer conversion after each count. (r1 rank 9) | `rows.len()` is a `U64` field: main.roc:414-417, 719, 725, 1016, 1022; monitoring.roc:131-134, 436, 460 | none | Fixed. `to_i64_wrap` 14 times to 0. |

## 4. Where Roc is stronger

| Area | Round 1 | Round 2 |
|---|---|---|
| Schema from types (M02, M04-M12) | Roc 55 percent of JS chars | Same. Row-type (7 Roc shorter), link (6) and time-series (4) entries are unchanged |
| Links (M14-M17, M21) | Roc shorter (6 of 10) | Same |
| Live queries (N38-N46) | 8 Roc shorter | Same 8. Roc chars 2548 to 2442. `ready_live(definitions)` |
| Projections (16 IDs) | 1 Roc shorter, 10 JS shorter | 6 Roc shorter, 9 similar, 1 JS shorter. Lambdas in the query removed the named functions |
| Group and aggregate (7 IDs) | 2 Roc shorter, 3 JS shorter | 3 Roc shorter, 3 similar, 1 JS shorter |
| Writes (15 IDs) | 4 Roc shorter, 6 JS shorter | 4 Roc shorter, 8 similar, 2 JS shorter |
| Views and db functions | N21 Roc shorter | N21, N22 and N08 Roc shorter |
| Counts | `to_i64_wrap` needed | `U64` is a plain field (M100, N54) |
| One function for constraint and program (`label_of`, `fever`, `Clinic.bill`, `owners_of_primary`) | yes | yes, and M95 and M96 run the path over the seed rows too |

Union totals: Roc is now 0.70 of the JS feature code by lines and by chars (round 1: 0.86 and 0.81). In tokens Roc is still above JS (1.42 against 1.59) because a JS SQL string is one token.

## 5. New features (not in any total above)

Roc counts are the catalog-2 ranges without the `check!` lines of client.roc and without comments. Port code is my own idiomatic equivalent, not run. JS uses the SDK 2.2.2 (`db.query` with `surql`, `beginTransaction`). Verdict rule as above.

| ID | Feature | Roc l/t/c | Port l/t/c | Verdict | Port equivalent and note |
|---|---|---|---|---|---|
| M95 | Graph path in a projection, `treats.edges_from(v)` | 3/86/227 | 2/31/140 | JS shorter | `const [owners] = await db.query<[{ name: string; owners: string[] }[]]>(surql\`SELECT name, ->treats[WHERE primary]->patient.owner.name AS owners FROM vet\`)`. Roc count includes the helper `owners_of_primary` (main.roc:1029-1031) because Roc runs it over the seed edges. JS has no such reference. |
| M96 | Graph path of two edges, `edges_to` then `edges_from` | 1/78/174 | 2/31/153 | similar | `... surql\`SELECT name, <-treats[WHERE primary]<-vet->treats->patient.name AS patients FROM patient\``. One Roc lambda line against one SQL line. |
| M97 | Graph path in a filter | 3/93/246 | 2/21/138 | JS shorter | `... surql\`SELECT VALUE name FROM vet WHERE ->treats[WHERE primary]->patient.owner.address.city CONTAINS 'Oslo'\``. Roc includes `primary_cities` (main.roc:1038-1040). |
| M98 | Check over several fields refused on update | 1/28/56 | 1/23/57 | similar | `await db.update(new RecordId("visit", "v1")).merge({ fee: 0 })`. Roc sends the whole row `{ ..v, fee: 0 }`. |
| M99 | `ready()` for a query with no parameters | 4/83/202 | 0/0/0 | n/a* | No code. JS has no `prepare({})` step. The Roc gain is against round 1 (58 `.prepare({})` to 0). Roc count is the 4 whole statements that cite it. |
| M100 | `U64` counts, `rows.len()` with no conversion | 7/320/738 | 0/0/0 | n/a* | No code. JS types the count as `number`. A count above 2^53 loses digits in JS and the type does not say so. |
| M101 | Filter against a unit arm, `v.outcome != Treated` | 1/46/108 | 1/5/23 | similar* | `WHERE outcome != 'Treated'` (the filter only: 23 chars against 33 chars of `.filter(|v| v.outcome != Treated)`). The Roc count is the whole query line. |
| N53 | `U64` above the `int` range sent as a decimal | 1/46/139 | 2/21/123 | similar | `... WHERE readings >= ${new Decimal("18446744073709551615")}` on the `DAY_ROWS` query of the port. The port needs the explicit `Decimal`. Roc picks the decimal form from the value. |
| N54 | `U64` counts in group, read-row and live row types | 5/118/315 | 0/0/0 | n/a* | No code. `readings: number` in the existing JS types. Roc count is 5 type and function lines. |
| N55 | `ready()` and `ready_live(definitions)` | 6/124/388 | 0/0/0 | n/a* | No code. JS has `db.live<T>(table)` with no definitions list. Roc needs `definitions` for a watch (a link of a watched row finds its table there). |
| C01 | `Surreal.transaction` of a list of writes, all commit | 8/125/379 | 4/63/181 | JS shorter* | `const tx = await db.beginTransaction(); await tx.create(new RecordId("bin","b5")).content({ label: "Spare" }); await tx.create(..b6..); await tx.commit();`. JS writes the rows inline. Roc counts `all_of`, `spare_bin`, `rack_bin` (client.roc:373-381) and the list at :388-390. The helper `all_of` is reused by C02. |
| C02 | A list where the second write fails, all rolled back | 4/97/288 | 9/82/220 | JS shorter | Same, with `try { .. await tx.commit() } catch (e) { await tx.cancel(); throw e }`. Roc gives the failed part (`aborted(1, ..)`, checked in the harness). JS gets the server error only. |
| C03 | Migration between two schemas, `Surreal.migration(old, new)` | 6/131/369 | 1/8/56 | JS shorter* | `await db.query("BEGIN; REMOVE INDEX bin_label ON bin; COMMIT")`. JS has no diff of two schemas: the developer writes the DDL of the change by hand and keeps it equal to the schema text. Roc counts `place_defs`, `loose_defs` and `migrate` (client.roc:326-327, 392-399). |
| C04 | The migration back fails on the twin row, nothing stays | 2/59/166 | 1/8/73 | JS shorter* | `await db.query("BEGIN; DEFINE INDEX bin_label ON bin FIELDS label UNIQUE; COMMIT")`. Same hand-written DDL. The server rejects the index while the twin row exists, and the transaction keeps the schema as it was. Roc counts `migrate` again (shared with C03). |

Reading of the new features:

| Point | Detail |
|---|---|
| Graph paths (M95-M97) | Edge reads no longer need `outgoing` and a tuple (M28 is Roc shorter, M29 similar). A path is a typed lambda. JS is shorter by chars because the path is one SQL string. JS cannot run the path in TS. |
| Counts (M99, M100, N54, N55) | These are API clean-ups. They lower the Roc totals of section 1. JS has no equal step to count. |
| Client features (C01-C04) | JS is shorter in lines. The SDK has `beginTransaction` and no migration diff. Roc adds the typed list result, the part number of a failure, and a migration that is computed from two schema lists. |
