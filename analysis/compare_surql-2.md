# Roc ORM against hand-written SurrealQL, round 2

Method as in round 1 (compare_surql.md): Roc counts from the catalog-2 ranges with the section 3 harness removed, port counts from surql_slices.json (the port is unchanged), token rule from slice.py, verdict rule: ratio Roc/port tokens below 0.8 is R, above 1.2 is S, else similar, and a difference of 8 tokens or less is similar. Round-1 reading overrides (OV) are kept for IDs whose Roc code did not change. Code lines only.

Roc counts file: roc_counts_2.json already existed (written by another comparer with the same method). 157 of 159 entries equal my own recount (rocslice3.py). N47 and N48 differ: the shared file counts the harness `match` blocks at monitoring.roc:886-897. This report uses my values for those two (N47 2/53, N48 2/29). The shared file was not changed.

Removed IDs: M69 (needs_attention match, moved to M101 and M60). It is left out of both rounds in the totals below. Round 1 totals as published include M69 (8 lines, 66 tokens Roc; 3 lines, 50 tokens port).

Counting caveat: a lambda that moved into the query line makes that line long. When two IDs cite the same line (M49/M50, M53/M54, M62, M64) each gets the whole line. A helper kept only as reference (flag_line, hot_line) is still cited by N11, N14, N27 and counts twice. So some tokens rose although the code got shorter.

## 1. Totals, round 1 against round 2 (same 145 IDs)

| Item | Round 1 | Round 2 | Change |
| --- | --- | --- | --- |
| Roc lines, per-ID sum | 619 | 502 | -117 (-19%) |
| Roc tokens, per-ID sum | 10170 | 9355 | -815 (-9%) |
| Port lines, per-ID sum | 405 | 405 | same |
| Port tokens, per-ID sum | 7094 | 7094 | same |
| Ratio Roc/port, tokens, per-ID sum | 1.43 | 1.32 | |
| Roc unique feature lines, main (M01-M94) | 343 | 254 | -89 |
| Roc unique feature tokens, main | 4593 | 3936 | -657 |
| Roc unique feature lines, monitoring (N01-N52) | 136 | 117 | -19 |
| Roc unique feature tokens, monitoring | 2726 | 2501 | -225 |
| Roc unique, both | 479 lines / 7319 tokens | 371 lines / 6437 tokens | -108 / -882 |
| Port unique, both (fair, no N49-N52) | 258 lines / 4625 tokens | 258 lines / 4625 tokens | same |
| Ratio Roc/port, unique, lines | 1.86 | 1.44 | |
| Ratio Roc/port, unique, tokens | 1.58 | 1.39 | |
| Verdict R (Roc shorter) | 18 | 24 | +6 |
| Verdict similar | 39 | 40 | +1 |
| Verdict S (port shorter) | 76 | 69 | -7 |
| Not compared | 12 | 12 | same |

Round-1 unique numbers are copied from round 1 and include M69 (at most 8 lines, 66 tokens). Fixture code was not recounted. Per-category numbers:

| Category | Features | Roc l/t round 1 | Roc l/t round 2 | R/similar/S/n.a. round 1 | R/similar/S/n.a. round 2 |
| --- | --- | --- | --- | --- | --- |
| row type | 13 | 80/1055 | 80/1055 | 1/3/8/1 | 1/3/8/1 |
| link | 10 | 20/263 | 20/263 | 7/2/0/1 | 7/2/0/1 |
| edge | 8 | 28/514 | 20/403 | 0/2/6/0 | 0/2/6/0 |
| schema constraint | 18 | 52/623 | 47/600 | 0/9/9/0 | 0/9/9/0 |
| other | 4 | 110/1379 | 81/1181 | 0/0/1/3 | 0/0/1/3 |
| query-filter | 18 | 50/1045 | 42/1053 | 0/7/11/0 | 2/5/11/0 |
| projection | 16 | 86/1401 | 48/1262 | 0/3/13/0 | 0/4/12/0 |
| group-aggregate | 7 | 20/690 | 17/658 | 0/1/6/0 | 0/1/6/0 |
| write | 15 | 63/819 | 51/695 | 0/5/6/4 | 2/6/3/4 |
| geometry | 5 | 16/291 | 12/263 | 1/0/3/1 | 1/0/3/1 |
| time series | 9 | 19/436 | 17/439 | 2/4/2/1 | 3/3/2/1 |
| db function | 5 | 20/367 | 14/330 | 0/1/4/0 | 1/1/3/0 |
| view | 2 | 5/89 | 4/48 | 1/0/1/0 | 1/1/0/0 |
| read row | 4 | 10/361 | 9/336 | 0/0/3/1 | 0/0/3/1 |
| live query | 11 | 40/837 | 40/769 | 6/2/3/0 | 6/3/2/0 |

Verdict changes (14): M52 S>=, M53 =>S, M74 S>=, M87 S>=, M88 =>R, M89 S>R, M91 S>=, N09 =>R, N10 S>=, N16 =>R, N22 S>=, N23 =>R, N25 =>R, N40 S>=. M52, M53, N09, N16, N22, N23, N25, N40 sit near the 0.8 or 1.2 line, so a few tokens move them.

## 2. Per-feature table

Change column: round-1 verdict > round-2 verdict, or `same`. Roc l/t is round 1 > round 2 when the count moved. Note: first words of the catalog-2 change entry; `range re-cut` means catalog 2 cites a different line set for the same feature.

| ID | Cat | Roc l/t r1 > r2 | Port l/t | Verdict change | Note |
| --- | --- | --- | --- | --- | --- |
| M01 | row type | 8/95 | 4/26 | S |  |
| M02 | row type | 22/155 | 10/91 | S |  |
| M03 | row type | 16/135 | 6/30 | S |  |
| M04 | row type | 3/68 | 5/100 | = |  |
| M05 | row type | 2/81 | 2/50 | S |  |
| M06 | row type | 3/61 | 2/39 | S |  |
| M07 | row type | 1/48 | 1/30 | S |  |
| M08 | row type | 4/48 | 2/48 | = |  |
| M09 | row type | 6/133 | 4/68 | S |  |
| M10 | row type | 4/59 | 1/17 | S |  |
| M11 | row type | 5/64 | 6/97 | = |  |
| M12 | row type | 3/73 | 5/148 | R |  |
| M13 | row type | 3/35 | 0/0 | n/a |  |
| M14 | link | 3/24 | 5/123 | R |  |
| M15 | link | 2/20 | 5/92 | R |  |
| M16 | link | 4/48 | 10/200 | R |  |
| M17 | link | 1/32 | 4/122 | R |  |
| M18 | link | 2/55 | 1/27 | = |  |
| M19 | link | 3/36 | 4/67 | = |  |
| M20 | link | 2/14 | 6/113 | R |  |
| M21 | link | 2/14 | 10/220 | R |  |
| M22 | link | 0/0 | 0/0 | n/a |  |
| M23 | edge | 3/53 | 1/12 | S |  |
| M24 | edge | 1/6 | 1/4 | = |  |
| M25 | edge | 1/15 | 1/14 | = |  |
| M26 | edge | 1/20 | 1/11 | S |  |
| M27 | edge | 4/63 | 2/51 | S |  |
| M28 | edge | 4/108 > 1/59 | 1/33 | S | Roc: lambda in the query, `case_load` and `CaseLoad` removed; counts are `U64` (no `to_i64_wrap`) |
| M29 | edge | 4/119 > 1/71 | 1/31 | S | Roc: lambda in the query, `team_line` and `TeamLine` removed; count is `U64` |
| M30 | schema constraint | 1/10 | 1/9 | = |  |
| M31 | schema constraint | 1/24 | 1/15 | S |  |
| M32 | schema constraint | 1/12 | 1/11 | = |  |
| M33 | schema constraint | 1/20 | 1/11 | S |  |
| M34 | schema constraint | 3/32 | 3/26 | = |  |
| M35 | schema constraint | 3/37 | 1/25 | S |  |
| M36 | schema constraint | 1/20 | 1/17 | = |  |
| M37 | schema constraint | 1/24 | 1/17 | = |  |
| M38 | schema constraint | 1/18 | 1/30 | = |  |
| M39 | schema constraint | 4/58 | 2/33 | S |  |
| M40 | schema constraint | 6/44 | 2/49 | = |  |
| M41 | schema constraint | 6/51 | 2/79 | = |  |
| M42 | schema constraint | 6/73 | 3/64 | = |  |
| M43 | schema constraint | 3/48 | 1/36 | S |  |
| M44 | schema constraint | 1/10 | 1/17 | S |  |
| M45 | schema constraint | 7/56 > 3/40 | 1/22 | S | range re-cut or shared line (same code) |
| M46 | schema constraint | 1/13 | 2/40 | S |  |
| M47 | schema constraint | 5/73 > 4/66 | 1/15 | S | range re-cut or shared line (same code) |
| M48 | other | 60/564 > 46/521 | 0/0 | n/a | Roc: one `definitions` list, the seven `*_def` values are removed |
| M49 | query-filter | 4/69 > 1/51 | 2/38 | S | range re-cut or shared line (same code) |
| M50 | projection | 4/86 > 4/100 | 2/38 | S | range re-cut or shared line (same code) |
| M51 | projection | 3/74 > 4/80 | 2/38 | S | range re-cut or shared line (same code) |
| M52 | query-filter | 3/41 > 1/30 | 1/26 | S > = | Roc: lambda in the filter, `is_vip` removed |
| M53 | query-filter | 1/32 > 1/63 | 1/24 | = > S | range re-cut or shared line (same code) |
| M54 | projection | 10/90 > 1/63 | 1/24 | S | Roc: `map_ok` and `??` in a lambda (was `match` in `referral_line`); SurrealQL: `??` (was IF ... THEN) |
| M55 | projection | 4/76 > 4/74 | 1/32 | S | range re-cut or shared line (same code) |
| M56 | projection | 9/94 > 9/92 | 4/86 | = | range re-cut or shared line (same code) |
| M57 | projection | 4/109 > 4/149 | 1/32 | S | range re-cut or shared line (same code) |
| M58 | query-filter | 3/33 > 3/31 | 1/19 | S | range re-cut or shared line (same code) |
| M59 | query-filter | 1/37 | 2/32 | = |  |
| M60 | query-filter | 6/62 > 6/60 | 1/13 | S | range re-cut or shared line (same code) |
| M61 | projection | 3/99 > 3/93 | 2/22 | S | range re-cut or shared line (same code) |
| M62 | projection | 14/106 > 1/70 | 1/33 | S | Roc: `map_ok` and `??` (was `match` in `chip_line`), `ChipLine` removed; SurrealQL: `??` |
| M63 | projection | 4/76 > 1/51 | 1/29 | S | Roc: lambda in the query, `vaccine_line` and `VaccineLine` removed |
| M64 | query-filter | 3/53 > 3/82 | 1/29 | S | range re-cut or shared line (same code) |
| M65 | query-filter | 10/225 > 7/226 | 4/75 | S | Roc: `SinceParam` removed; `Clinic.seen_before` removed |
| M66 | projection | 7/198 > 5/203 | 4/75 | S | Roc: lambda in the query, `visit_line` and `VisitLine` are now only a reference helper (line 481) |
| M67 | query-filter | 1/40 > 1/38 | 1/21 | S | range re-cut or shared line (same code) |
| M68 | projection | 10/93 > 7/79 | 3/50 | S | Roc: `outcome_line` and `OutcomeLine` removed |
| M70 | projection | 1/20 > 1/10 | 1/15 | = | range re-cut or shared line (same code) |
| M71 | projection | 4/69 > 1/47 | 1/21 | S | range re-cut or shared line (same code) |
| M72 | projection | 1/39 > 1/37 | 1/36 | = | range re-cut or shared line (same code) |
| M73 | projection | 4/89 > 1/60 | 1/29 | S | Roc: lambda in the query, `contact_line` and `ContactLine` removed |
| M74 | projection | 4/83 > 1/54 | 4/60 | S > = | Roc: lambda in the query, `linked_rows` and `LinkedRows` removed |
| M75 | query-filter | 3/50 | 2/27 | S |  |
| M76 | query-filter | 3/56 | 2/50 | = |  |
| M77 | query-filter | 4/55 | 4/72 | = |  |
| M78 | group-aggregate | 4/145 > 4/135 | 2/47 | S | Roc: `Ledger.visits` is `U64` and `rows.len()` has no `to_i64_wrap` |
| M79 | group-aggregate | 2/115 > 2/105 | 2/47 | S | range re-cut or shared line (same code) |
| M80 | group-aggregate | 1/50 > 1/48 | 2/47 | = | range re-cut or shared line (same code) |
| M81 | group-aggregate | 4/102 > 1/65 | 1/34 | S | Roc: lambda in `totals(..)`, `VisitTotals` removed, count is `U64`, mean is `Math.mean_dec` |
| M82 | group-aggregate | 1/44 > 1/38 | 1/16 | S | range re-cut or shared line (same code) |
| M83 | write | 6/36 | 8/23 | = |  |
| M84 | write | 1/6 | 2/37 | = |  |
| M85 | write | 2/25 | 2/25 | = |  |
| M86 | write | 6/94 > 3/80 | 4/46 | S | Roc: patch is a lambda, `refill`, `RestockParam` and `refill_param` removed |
| M87 | write | 3/54 > 1/39 | 2/42 | S > = | Roc: `set_at` with a lambda patch (was `update_at` with `certified`, removed) |
| M88 | write | 3/39 > 1/28 | 2/43 | = > R | Roc: lambda patch, `renamed` removed |
| M89 | write | 3/67 > 1/38 | 2/49 | S > R | Roc: lambda patch, `moved` removed; `no_phone` gives the `Err` its type |
| M90 | write | 1/17 > 1/15 | 2/10 | = | range re-cut or shared line (same code) |
| M91 | write | 3/62 > 1/26 | 3/31 | S > = | Roc: lambda in `delete_by`; `Clinic.too_old`, `Clinic.seen_before` and `RetentionParam` removed |
| M92 | write | 11/185 > 9/148 | 2/14 | S | range re-cut or shared line (same code) |
| M93 | write | 24/234 > 25/254 | 24/140 | S | Roc: 25 refusals (was 24); `check_as_event` is now `check_over_two_fields` and has an update form (M98) |
| M94 | other | 22/511 > 18/434 | 0/0 | n/a | Roc: `Clinic.roc` has 48 lines (was 55); `seen_before` and `too_old` removed, so M91 no longer uses it |
| N01 | geometry | 1/23 | 5/58 | R |  |
| N02 | geometry | 7/91 > 6/85 | 1/3 | n/a | range re-cut or shared line (same code) |
| N03 | link | 1/20 | 4/40 | R |  |
| N04 | time series | 1/29 | 4/39 | R |  |
| N05 | time series | 3/59 > 2/53 | 1/3 | n/a | range re-cut or shared line (same code) |
| N06 | edge | 10/130 > 8/116 | 8/60 | S | range re-cut or shared line (same code) |
| N07 | other | 25/211 > 14/139 | 0/0 | n/a | Roc: one `definitions` list (the `*_def` values are removed) |
| N08 | db function | 5/76 > 5/56 | 1/35 | S | range re-cut or shared line (same code) |
| N09 | db function | 1/36 > 1/34 | 1/43 | = > R | range re-cut or shared line (same code) |
| N10 | db function | 6/54 > 1/26 | 1/24 | S > = | range re-cut or shared line (same code) |
| N11 | db function | 4/79 > 3/102 | 1/27 | S | Roc: lambda in the query (`flag_line` is now a reference helper, line 217) |
| N12 | db function | 4/122 > 4/112 | 2/64 | S | Roc: `Daily.readings` and `fevers` are `U64`, no `to_i64_wrap` |
| N13 | time series | 4/106 > 4/104 | 1/43 | S | range re-cut or shared line (same code) |
| N14 | time series | 4/79 > 3/102 | 1/27 | S | range re-cut or shared line (same code) |
| N15 | time series | 1/26 > 1/24 | 2/52 | R | range re-cut or shared line (same code) |
| N16 | time series | 1/29 > 1/19 | 1/34 | = > R | range re-cut or shared line (same code) |
| N17 | time series | 3/66 | 2/64 | = |  |
| N18 | time series | 1/30 | 3/57 | = |  |
| N19 | time series | 1/12 | 1/8 | = |  |
| N20 | group-aggregate | 7/188 > 7/178 | 2/64 | S | range re-cut or shared line (same code) |
| N21 | view | 4/45 > 3/38 | 3/68 | R | Roc: `daily_def` removed, the call is inside `definitions` |
| N22 | view | 1/44 > 1/10 | 1/7 | S > = | range re-cut or shared line (same code) |
| N23 | query-filter | 1/36 > 1/34 | 1/43 | = > R | range re-cut or shared line (same code) |
| N24 | query-filter | 1/36 > 1/34 | 1/11 | S | range re-cut or shared line (same code) |
| N25 | query-filter | 1/46 > 1/44 | 1/57 | = > R | range re-cut or shared line (same code) |
| N26 | query-filter | 1/47 > 1/45 | 1/27 | S | range re-cut or shared line (same code) |
| N27 | group-aggregate | 1/46 > 1/89 | 1/35 | S | Roc: lambdas in the query (`hot_line` and `kennel_fevers` are now reference helpers, lines 220-224) |
| N28 | query-filter | 1/54 > 1/46 | 2/19 | S | range re-cut or shared line (same code) |
| N29 | geometry | 4/56 > 1/34 | 1/22 | S | Roc: lambda in the query, `site_lat` and `SiteLat` removed |
| N30 | geometry | 3/71 | 2/27 | S |  |
| N31 | geometry | 1/50 | 2/35 | S |  |
| N32 | read row | 4/127 > 4/121 | 1/50 | S | range re-cut or shared line (same code) |
| N33 | read row | 3/140 > 3/134 | 1/50 | S | range re-cut or shared line (same code) |
| N34 | read row | 1/82 > 1/76 | 1/50 | S | Roc: count is `U64` |
| N35 | read row | 2/12 > 1/5 | 0/0 | n/a | range re-cut or shared line (same code) |
| N36 | other | 3/93 > 3/87 | 1/35 | S | range re-cut or shared line (same code) |
| N37 | query-filter | 3/73 > 3/71 | 4/65 | = | range re-cut or shared line (same code) |
| N38 | live query | 3/56 > 3/53 | 2/82 | R | Roc: `ready_live(definitions)` (was `live({}, definitions)`) |
| N39 | live query | 3/65 | 3/101 | R |  |
| N40 | live query | 3/64 > 3/29 | 2/25 | S > = | range re-cut or shared line (same code) |
| N41 | live query | 8/129 > 8/122 | 3/122 | = | Roc: `ready_live(definitions)`; `Unattended.carers` is `U64` |
| N42 | live query | 3/85 > 3/78 | 3/122 | R | Roc: `ready_live(definitions)` |
| N43 | live query | 3/59 > 3/56 | 6/125 | R | Roc: `ready_live(definitions)` |
| N44 | live query | 8/173 > 8/162 | 5/277 | R | Roc: `ready_live(definitions)`; `Neglected` counts are `U64` |
| N45 | live query | 3/64 > 3/65 | 3/63 | = | range re-cut or shared line (same code) |
| N46 | live query | 2/60 > 2/57 | 3/82 | R | Roc: `ready_live(definitions)` |
| N47 | live query | 2/53 | 1/44 | S |  |
| N48 | live query | 2/29 | 1/6 | S |  |
| N49 | write | 0/0 | 38/407 | n/a |  |
| N50 | write | 0/0 | 11/125 | n/a |  |
| N51 | write | 0/0 | 4/20 | n/a |  |
| N52 | write | 0/0 | 14/70 | n/a |  |
## 3. Where Roc is still weaker (ranked)

Line numbers: m = examples/main.roc, n = examples/monitoring.roc. Port lines: surql/main.surql, surql/monitoring.surql. Token numbers are Roc/port for the ID named.

| Rank | Weakness | Round-1 status now | IDs | Roc now | SurrealQL |
| --- | --- | --- | --- | --- | --- |
| 1 | A projection still pays for a type, a lambda, a select call and a terminal call. The lambda in the query removed 10 named types, so lines fell by 44% in the projection category, but a long Roc line is still 1.5 to 2 times the SELECT | Partly fixed (rank 1 in round 1). S verdicts 76 > 69 | M28, M29, M50, M55, M57, M61, M64, M71, M73, M74, M78, N11, N13, N14, N27 | m:719 `Surreal.from(vets).outgoing(treats).select(\|(v, edges)\| { name: v.name, patients: edges.len(), primary: edges.keep_if(\|e\| e.primary).len() }).ready()` (59/33 for M28). Still named: `owner_card` m:398-402, `pet_line` m:405-408, `vital_line` n:208-211 | `SELECT name, ->treats.len() AS patients, ->treats[WHERE primary].len() AS primary FROM vet;` (port main.surql:269 form) |
| 2 | Option and union values need `map_ok`, `??` or a `match` where a path walks through NONE | Partly fixed (rank 2). M54 10/90 > 1/63, M62 14/106 > 1/70, M69 gone. `wide_wings` still a 6-line match | M54, M60, M62, M101 | m:657 `.select(\|o\| { id: o.id, by: o.?referred_by.map_ok(\|r\| r.get().name) ?? "nobody" })`; m:152-156 `wide_wings` match (60/13 for M60) | `referred_by.name ?? 'nobody' AS by`; `species.wingspan_cm >= 20` |
| 3 | Aggregates are list code with Roc functions | Partly fixed (rank 3). `to_i64_wrap`, `to_f64` are gone (U64 counts, `Math.mean_dec`). Still 135/47 for M78 | M78, M79, M81, M82, N12, N20 | m:417 `ledger_line = \|vet, rows\| { vet, visits: rows.len(), revenue: rows.map(\|v\| v.fee).sum(), avg_fee: Surreal.Math.mean_dec(rows.map(\|v\| v.fee)) }` | `count() AS visits, math::sum(fee) AS revenue, math::mean(<float>fee) AS avg_fee ... GROUP BY vet` |
| 4 | Per-table boilerplate: handle plus annotation, `encoder_for : _` and `parser_for : _`, one `definitions` list | Partly fixed (rank 4). The seven `*_def` values and the `Defined` pairs are gone: N07 25/211 > 14/139, M48 60/564 > 46/521. M01, M03, M23, M47 unchanged | M01, M03, M23, M47, N06, N07 | m:32-33 `encoder_for : _` / `parser_for : _`; m:95-118 handles; n:104-121 `definitions` | `DEFINE TABLE owner SCHEMAFULL;` |
| 5 | Second row types for one table: form rows, a table only to carry a default, read rows | Still there (rank 5). M92 11/185 > 9/148 only | M10, M13, M47, M92, N32, N33, N34 | m:53-55 `MedicationForm`; m:977-992 `Note`; n:74-83 `CareRead`, `KennelRead` | `DEFINE FIELD id ON note TYPE string DEFAULT rand::ulid();` |
| 6 | Constraint builders are longer than the keyword they replace. Defaults have two spellings | Still there (rank 6). Counts of M26, M31, M33, M34, M44, M46 did not change | M26, M31, M33, M34, M44, M46 | m:360 `.readonly(\|v\| v.license)`; m:371 `.default(\|p\| p.allergies, [])` | `READONLY`; `DEFAULT []` |
| 7 | Captured values and parameter records use a second API | Partly fixed (rank 8). `CityParam` and `in_city` are gone (M49 4/69 > 1/51). Captured queries (M75-M77) are unchanged | M75, M76, M77 | m:419-434 `cheaper_than : Dec -> Try(Surreal.Prepared(List(Medication)), Surreal.Error)` with `Surreal.bind_captured(Surreal.select_where(..))` | `LET $max = 0.9dec; SELECT ... WHERE unit_price < $max;` |
| 8 | Updates by predicate still write the whole row and compute the delta in Roc | Partly fixed (rank 9). `set_at` with a patch lambda lists only the changed fields (M87 54/42 > 39/42 similar; M88, M89 now R). `update_by` still `{ ..m, stock: m.stock + p.add }` (80/46) | M86 | m:884 `medications.update_by(Clinic.low_stock, \|p, m\| { ..m, stock: m.stock + p.add }).prepare({ floor: 60, add: 100 })` | `UPDATE medication SET stock += $add WHERE stock < $floor;` |
| 9 | Database-only functions have no Roc body, so one function cannot run on both sides. New: graph paths and `rows()` are database only too, and the Roc reference is written by hand | Still there (rank 10), larger | M37, M95, M96, M97, N19, N30, N31, N36 | m:1029-1040 `owners_of_primary(edges)` takes `treats.edges_from(v)` and runs in memory only on a hand-made edge list `edges_of_vet`; n:255-257 `Geo.inside` | `->treats[WHERE primary]->patient.owner.name` is one path (22 tokens against 86 for M95) |
| 10 | Graph paths read longer than the SurrealQL arrow path | New | M95, M96, M97 | m:1052 `Surreal.from(vets).select(\|v\| { name: v.name, owners: owners_of_primary(treats.edges_from(v)) }).ready()` (86/22) | `SELECT name, ->treats[WHERE primary]->patient.owner.name AS owners FROM vet;` |
| 11 | Two terminal spellings: `ready()` for no parameters, `prepare({..})` with parameters, `ready_live` and `live({..}, ..)` | New (from M99, N55) | M49, M99, N39, N55 | m:644 `...prepare({ city: "Oslo" })` against m:650 `...ready()` | `LET $city = 'Oslo';` then the same SELECT |

Removed weakness: "No rest-spread or OMIT in a projection" (round-1 rank 7) is fixed: `select` is optional, so `Surreal.from(daily).ready()` (n:372-376) gives the whole view row. N22 44 > 10 tokens against 7 in the port (S > similar), N40 64 > 29 (S > similar), M70 20 > 10 (similar).

## 4. Where Roc is stronger (short)

| Rank | Strength | IDs | Round-2 change |
| --- | --- | --- | --- |
| 1 | A link type gives type, REFERENCE, exists-assert, index and delete rule | M14-M17, M19-M21, N03 | Unchanged. 7 R verdicts |
| 2 | One function is the constraint, computed field, projection and program code | M35, M40, M41, M43, M45, M66, N08-N12 | M43 now a field ASSERT, so the refusal names the field and fires on update (M98) |
| 3 | Live queries from one filter: Watch type, edge and join streams, snapshot | N38-N46, N48 | `ready_live(definitions)`. N45 no longer needs a read row. 6 R verdicts |
| 4 | Types give ranges, defaults and `U64` counts. A `U64` above `int` is sent as a decimal (N53) | M05, M09, M100, N53 | New: no count conversion in the rows |
| 5 | Compile-time checks: field names, clause order, edge direction, patch fields | M28, M40, M41, M72, M87, M89, M95 | Patch fields of `set_at` are checked; `edges_from` needs an edge table that leaves the row |
| 6 | Views and queries share one definition. The view is read with `Surreal.from(daily).ready()` | N21, N22 | N21 45 > 38 tokens, N22 now 10 tokens |
| 7 | A list of writes is one transaction, and a migration between two schema values is one transaction. The port has no schema diff: it needs the index name and the removal statement by hand, and a client to read the rows of each write | C01-C04 | New |
| 8 | Typed key ranges and compound ids | N04, N13, N15, N16 | N15 and N16 now R |
| 9 | Reuse of query fragments over any row | M57, M65, M91, M94 | Clinic.roc 22 > 18 lines. M91 now an inline lambda (62 > 26 tokens, similar) |
| 10 | Generated schema keeps `OVERWRITE`, so the script re-runs. The generated record equality (M77) uses the composite unique index, the hand `address = $addr` does not (tested, section 6) | M77 | New |

## 5. New features (not in the round-1 totals)

Roc counts: catalog-2 ranges with the harness removed (C rows: client.roc lines as cited, they include the `check!` lines). Port column: idiomatic equivalent written by me, not run, only SurrealQL text (no client code). Verdict by the same rule.

| ID | Feature | Roc l/t | Port l/t | Verdict | Port equivalent |
| --- | --- | --- | --- | --- | --- |
| M95 | Graph path in a projection | 3/86 | 1/22 | S | `SELECT name, ->treats[WHERE primary]->patient.owner.name AS owners FROM vet;` |
| M96 | Graph path of two edges | 1/78 | 1/26 | S | `SELECT name, <-treats[WHERE primary]<-vet->treats->patient.name AS patients FROM patient;` |
| M97 | Graph path in a filter | 3/93 | 1/25 | S | `SELECT VALUE name FROM vet WHERE ->treats[WHERE primary]->patient.owner.address.city CONTAINS 'Oslo';` |
| M98 | Check over several fields refused on update | 1/28 | 1/10 | S | `UPDATE visit:v1 SET fee = 0dec;` (refusal head, payload is fixture) |
| M99 | Query with no parameters ends with `ready()` | 4/83 (shared lines) | 0/0 | n/a | A plain statement, no terminal call. Cost sits in the lines of the queries |
| M100 | `U64` counts, no conversion | 7/320 (shared lines) | 0/0 | n/a | `count()`, no cast. Shared with M28, M29, M78, M81, M82 |
| M101 | Filter with a unit arm (`!= Treated`) | 1/46 | 3/50 | similar | `SELECT record::id(id) AS id, IF outcome.kind = 'Followup' { 'follow-up' } ELSE IF outcome.kind = 'Referred' { 'referred to ' + outcome.to.name } ELSE { 'treated' } AS text FROM visit WHERE outcome != 'Treated';` |
| N53 | `U64` above `int` sent as a decimal | 1/46 | 2/20 | S | `LET $least = 18446744073709551615dec; SELECT * OMIT id FROM vital_daily WHERE readings >= $least;` |
| N54 | `U64` in group, read and live rows | 5/118 (shared lines) | 0/0 | n/a | `count()`, no cast |
| N55 | `ready()` and `ready_live(definitions)` | 6/124 (shared lines) | 0/0 | n/a | Plain SELECT and LIVE SELECT |
| C01 | Transaction of a list of writes, rows of each in order | 9/182 | 4/26 | S | `BEGIN; CREATE bin:b5 CONTENT { label: 'Spare' }; CREATE bin:b6 CONTENT { label: 'Rack' }; COMMIT;` and a client to read each result |
| C02 | Transaction where the second write fails: all rolled back | 5/120 | 4/26 | S | Same text with a second row that breaks the unique label. The server rolls back |
| C03 | Migration to a schema without the unique label, one transaction | 8/178 | 3/10 | S | `BEGIN; REMOVE INDEX bin_label ON bin; COMMIT;` The index name and the diff are by hand |
| C04 | Migration back fails on the twin row, nothing stays | 3/85 | 3/13 | S | `BEGIN; DEFINE INDEX bin_label ON bin FIELDS label UNIQUE; COMMIT;` |

Reading: the new graph-path and transaction rows are S in lines, because the Roc side counts types and the call chain and the port is one statement. Roc adds a check (edge direction, schema diff, `Unique` error names the field) that the port text does not have.

## 6. Generated output issues

Generated: $SCRATCH/v2/main.surql (gm) and v2/monitoring.surql (gn). Hand-written: surql/main.surql (hm), surql/monitoring.surql (hn). Round-1 generated files: main.surql, monitoring.surql in $SCRATCH. I ran EXPLAIN on SurrealDB v3.3.5 (own container, port 8399, stopped after) for the rows marked tested.

### 6.1 Round-1 table, row by row

| ID | Round-1 issue | Status | New generated snippet | Note |
| --- | --- | --- | --- | --- |
| M15-M17 | Delete rule scans with a closure | Fixed | gm:68 `... WHERE $before.id IN vaccines[*].vet LIMIT 1`; gm:67 `WHERE chip.implanted_by = $before.id LIMIT 1` | Tested: `vet:ruth IN vaccines[*].vet` gives IndexScan on patient_vaccines_vet_link (the closure form gave TableScan). Same for items[*].medication. The outcome event is a TableScan in both the generated and the hand version (no index on outcome.to) |
| M63, M64 | Closure in queries | Partly | gm:140 `SELECT record::id(id) AS id, vaccines.map(\|$v1\| $v1.vet.name) AS vets FROM patient WHERE vet:ruth IN vaccines[*].vet;` | The filter is fixed (index). The projection still has `.map(closure)` (also gm:190, gm:372). Low: text only |
| M28, M29 | Edge filter as closure | Fixed | gm:158 `->treats[WHERE primary].len()`; gm:162 `<-treats[WHERE primary]<-vet.name` | Same as the hand form |
| M08, M39 | Object key check on every write | Fixed | gm:39 `TYPE array<{ given: string, name: string, vet: record<vet> }>` | No `object::keys` assert any more |
| M42, M43 | Multi-field check is an EVENT | Fixed | gm:43 `DEFINE FIELD OVERWRITE fee ON visit TYPE decimal ASSERT (($this.items.len() = 0) OR ($value > 0.0dec)) AND ($value >= 0.0dec);` | Same meaning as hm:102. Refusal names field `fee`, also on update (gm:240) |
| M12, M09 | Redundant union asserts | Still there | gm:38 `ASSERT ((IF $value.kind = 'Bird' THEN $value.wingspan_cm >= 0 AND $value.wingspan_cm <= 255 ELSE true END)) AND ((IF $value.kind = 'Bird' THEN $value.wingspan_cm > 0 ELSE true END))`; gm:47 has 3 IFs, two on 'Followup' (`days >= 0 AND <= 255`, then `> 0 AND <= 90`) | Low: longer text, same result. Hand: hm:69, hm:111 |
| M04, M14 | `$value = NONE OR` guard | Still there | gm:16 `ASSERT ($value = NONE OR (record::exists($value)))` | Tested: with `option<record<o>>` an ASSERT is skipped for NONE, so the guard is dead. Low |
| M54, M62 | Dead IF branches | Fixed | gm:114 `referred_by.name ?? 'nobody' AS by`; gm:136 `chip.implanted_by.name ?? 'nobody' AS by, chip.code ?? 'none' AS chip` | Same as hm:233, hm:249 |
| M70 | Whole row as a field list | Partly | gm:181 `SELECT contact, record::id(id) AS id, license, name, rate, specialty, years FROM vet;` | The `VALUE { .. }` form is gone. A field list instead of `*`. Same result for SCHEMAFULL. Low |
| M77 | Record equality as 3 ANDs | Still there, not a problem | gm:209 `WHERE (address.city = $_1.city) AND (address.line = $_1.line) AND (address.zip = $_1.zip)` | Tested: IndexScan on owner_address_city_address_line_unique plus a Filter on zip. The hand `address = $addr` (hm:309) is a TableScan. Round-1 impact "can not use an index" was wrong. Generated is better |
| M59 | Key lookup as WHERE | Still there, not a problem | gm:128 `FROM vet WHERE id = type::record('vet', $key)` | Tested: RecordIdScan for both forms; the WHERE form adds a residual predicate. Text only |
| N17, N20, N21, N12 | Duration as nanos | Fixed | gn:9, gn:66 `time::floor(record::id(id)[1], 1d)` | Same as the hand text |
| N19 | Changefeed in nanoseconds | Fixed | gn:8 `CHANGEFEED 1w` | |
| N24, N28 | Group then filter recomputes the group | Still there | gn:74 `SELECT day, fevers, kennel, readings FROM (SELECT time::floor(..) .. GROUP BY day, kennel) WHERE fevers < readings;` gn:91, gn:96 (N53) the same with `$least` | Medium. Follows the Roc query (n:336-342, n:360-365 group the vitals). The Roc user can read the view: n:372-376 `Surreal.from(daily).ready()` gives gn:100 |
| N36 | Correlated count copies all ids | Fixed, better than hand | gn:133 `type::record('kennel', record::id(id)).chain(\|$v1\| (SELECT VALUE id FROM vital:[$v1, NONE]..=[$v1, ..])).len()` | Tested: RecordIdScan over the key range of the kennel. The hand form (`WHERE record::id(id)[0] = $parent.id`, hn:148) is a TableScan of vital per kennel |
| N37 | `any` over all rows, no LIMIT 1 | Partly | gn:137 `WHERE type::record('kennel', record::id(id)).chain(\|$v1\| (SELECT VALUE id FROM vital:[$v1, NONE]..=[$v1, ..])).any(\|$v2\| $v2.fevered)` | Scan is now the key range of one kennel (tested). No early exit: it reads every row of the range. Hand `fn::has_fever` (hn:46) exits at the first hit but its WHERE is a TableScan of vital (tested). Trade-off, no clear loser |
| N43 | Live: vital stream re-emits all kennels, test text inlined 3 times | Still there | gn:248 `LIVE SELECT VALUE (SELECT VALUE { ref: id, row: label, now: type::record('kennel', record::id(id)).chain(..).any(..) } FROM kennel) FROM vital;` and gn:247 with the same text in `now`, WHERE and `$before` | High: O(kennels) notices per vital write. Hand: hn:284 `... FROM ONLY $parent.id.id()[0]` sends the changed kennel only |
| N38-N46 | Notice envelope `{ row, now }` | Still there | gn:194 `LIVE SELECT VALUE { row: { day: day, fevers: fevers, kennel: kennel, readings: readings }, now: true } FROM vital_daily;` gn:263 | Low: more bytes per notice |
| M-all | Long derived names | Still there | gm:57 `DEFINE INDEX OVERWRITE owner_address_city_address_line_unique ON owner FIELDS address.city, address.line UNIQUE;` | Low. `OVERWRITE` is still a benefit |

Counts: 8 fixed, 3 partly, 6 still there, 2 re-rated as no problem (M77, M59). Two round-1 claims were wrong and are corrected above: M77 (generated is better) and the hand `has_fever` (also a TableScan).

### 6.2 New issues (statement by statement against the hand file)

Every statement of gm (schema, reads, graph paths, refusals, writes, totals) and gn (schema, queries, live blocks) was compared with the hand text. Statements not listed give the same meaning and the same or a better plan. Better in the generated text: gm:194 `owner.{ address, email, .. }` avoids the subselect of hm:295; gn:264 and gn:286 site stream `WHERE $before IS NONE OR $after IS NONE OR $before.name != $after.name` also covers a created or deleted site; gn:205 keeps the `$before` term that hn:235 leaves out.

| Where | Issue | Generated | Hand-written | Impact |
| --- | --- | --- | --- | --- |
| gm:70 | Extra guard on the union event: the `outcome.kind = 'Referred'` test is redundant, `outcome.to` is NONE for other arms | `WHERE (outcome.kind = 'Referred' AND outcome.to = $before.id) LIMIT 1` | hm:124 `WHERE outcome.to = $before.id LIMIT 1` | Low: both are a TableScan |
| gm:9-12, gm:33-35 | Object fields split in one DEFINE FIELD each | `address TYPE object` + 3 `address.*` fields; `chip TYPE option<object>` + 2 | hm:11 `TYPE { city: string, line: string, zip: option<string> }` | Low: 4 statements for 1. Same meaning |
| gm:106, gm:110 and more | Redundant alias | `name AS name`, `specialty AS specialty` | `name`, `specialty` | Low: text |
| gm:119, gm:186 | Union match inlined twice | `(IF species.kind = 'Bird' THEN 'bird' ELSE IF species = 'Cat' ...)` | hm:236 `fn::species_label(species)` | Low: text. The Roc `species_label` is a Roc function, not a database function |
| gm:132 | Union arm test as IF | `WHERE (IF species.kind = 'Bird' THEN species.wingspan_cm >= 20 ELSE false END)` | hm:246 `WHERE species.wingspan_cm >= 20` | Low: same result (M60) |
| gm:372 | Closure in a read-back | `allergies.map(\|$v1\| $v1.name)` | `allergies.name` | Low: text |
| gn:45 | Seed rows carry a placeholder for the computed field | `{ fevered: false, id: [kennel:a, ..], pulse: 70, .. }` | hn:75 no `fevered` | Low: the VALUE clause overwrites it |
| gn:128 | Edge source as wildcard | `<-cares_for<-?.{ id: record::id(id), name }` | hn:145 `<-cares_for<-carer.{ .. }` | Low: same rows, the edge table is typed ENFORCED |
| gn:133, gn:137, gn:247, gn:248 | Round trip of the key | `type::record('kennel', record::id(id))` where `id` is already the kennel record | `$parent.id`, `fn::has_fever(id)` | Low: extra function calls per row |
| gn:147, gn:171 | The test is evaluated 3 times per notice (`now`, WHERE, `$before`) | `now: fn::fever(temp_c, pulse) ... WHERE fn::fever(temp_c, pulse) OR ($before IS NOT NONE AND fn::fever($before.temp_c, $before.pulse))` | hn:162 `fevered OR $before.fevered` (stored field) | Low to medium: 3 function calls against 0. The Roc filter is written with `fever_fn.call2`; `v.fevered` would give the cheap form |
| gn:100 | View read as a field list | `SELECT day, fevers, kennel, readings FROM vital_daily;` | hn:125 `SELECT * OMIT id FROM vital_daily;` | Low: text. No redundancy otherwise |

No new issue changes the meaning of a statement. No statement became less efficient than in round 1.
