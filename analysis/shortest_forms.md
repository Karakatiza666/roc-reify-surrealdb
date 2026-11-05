# Verbosity claims: real API limits or example style

Source: repository at commit ba5e2cb, copied to shortest/. Rewritten examples: examples/main_short.roc, examples/monitoring_short3.roc. tests/check.py on SurrealDB 3.3.4: 112/112 blocks agree, live blocks included. Counts: `cd examples && python3 ../count.py` (17 flagged features: 95 lines / 1468 tokens before, 17 lines / 980 tokens after).

| # | Claim | IDs | Original (l/t) | Shortest working Roc | Status | Error or src/ location | Proposal |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1a | Named type and function per projection | M49, M50, M71, N11 | eldest 4/69, owners_in_city 7/120 | `Surreal.from(patients).select(\|p\| { id: p.id, age: p.age }).order_by(\|r\| r.age, Desc).limit(3).prepare({})` 1/50 | style only | none | name a function only when it is reused |
| 1b | `.select` needed for whole rows | M70, N22 | `.select(\|r\| r)` 15 uses | none | real (small) | "does not have a method named prepare ... Surreal.Query(p, Vet)"; src/Surreal.roc:1802-1978 | Query.prepare / prepare_one / live |
| 1c | `.prepare({})` on each query with no parameter | all | 96 uses | none | real (largest total) | Session.run! takes only Prepared (src/Surreal.roc:3417); Selected.prepare needs p (2140) | Selected.ready, or run! over Selected({}, out) |
| 2 | Optional values need match | M53, M54, M62 | chips 14/109, referrals 10/92 | `chip: p.?chip.map_ok(\|c\| c.code) ?? "none"` 1/75 | style only | output is `(IF chip IS NONE THEN NONE ELSE chip.code END) ?? 'none'`, src/Translate.roc:2172 | fold `map_ok(..) ?? d` into `path ?? d` |
| 3 | Unions need named match functions | M40, M41, M56, M60, M68, M69 | needs_attention 8/63 | `filter(\|v\| v.outcome != Treated)` 1/31 | style for unit tags; payload arms need match (language) | none | none |
| 4a | to_i64_wrap in aggregates | M78, M81, M82, N12, N20, N34 | 19 uses | `rows.len()` as a U64 field | style only | typed decode of U64 not run in a session | none |
| 4b | Mean needs to_f64 | M79, M81 | main.roc:503, 1122 | same | real (small) | mean : List(F64) -> F64, src/Surreal.roc:807 | Dec mean |
| 5 | Writes need a param type, a patch fn and an open-row predicate | M86-M89, M91 | restock 4/55, certify 3/57, rename 3/45 | `owners.set_at(owners.id("jon"), \|_\| { name: "Jon B. Berg" })` 1/34 | style only | none | none |
| 6a | x_def = x.define().done() | M01, M03, N06, N07 | 12/117 | inline in the definitions list 1/67 | partly real | `BadSchema("no table holds the row type ...; list its table in the schema")`, src/Types.roc:328 | Table.plain(t) |
| 6b | encoder_for/parser_for | M01, M47 | main.roc:31-34, 48-51 | none with `??` | partly real (language) | "default not allowed in structural record" | none |
| 6c | Form row for create | M13, M85 | 6/100 | `create({ .., label: "", .. })` 1/62 | style only (one dummy value) | none | optional Table.create_partial |
| 6d | Read rows | N32-N35 | 7/171 | `incoming(cares_for).select(\|(k, edges)\| { .. })` 1/84 | style only | none | none |
| 7a | No OMIT for view rows | N22, N28, N40 | 1/45 | `select(\|d\| d)` 1/21 | style only | dropping a field needs a 2nd type (language) | none |
| 7b | Captured values need bind_captured | M75-M77 | 3/52 | `filter_by(\|p, m\| m.unit_price < p.max)` 1/42 | partly real | "reified function captures a value ... limit"; src/Surreal.roc:2509, 2523 | Code.Bound in all clause builders |
| 7c | .readonly / .default | M44, M46 | main.roc:371, 388 | same | style only | none | none |
