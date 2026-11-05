# Roc ORM against hand-written SurrealQL, feature by feature

Sources: catalog.md, roc_slices.json (Roc counts, section 3 harness removed, reused from another comparer, 5 entries checked by hand: M05, M48, M83, M93, N07), surql_slices.json (port counts via slice.py). Token rule: slice.py TOKEN regex. Code lines only.

Verdict rule: token ratio Roc/SQL below 0.8 is Roc shorter, above 1.2 is SurrealQL shorter, else similar. A difference of 8 tokens or less counts as similar. Entries marked with a changed verdict were set by reading (see the note column). The SurrealQL port has no application types, no typed results and no client code.

Warning on counts: Roc ranges overlap (one query function serves several IDs), SQL blocks under two IDs count for both. Per-ID sums therefore exceed the true totals. Unique totals are in the last section.

## 1. Summary per category

| Category | Features | Roc lines | Roc tokens | SQL lines | SQL tokens | Roc shorter | Similar | SQL shorter | Not compared |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| row type | 13 | 80 | 1055 | 48 | 744 | 1 | 3 | 8 | 1 |
| link | 10 | 20 | 263 | 49 | 1004 | 7 | 2 | 0 | 1 |
| edge | 8 | 28 | 514 | 16 | 216 | 0 | 2 | 6 | 0 |
| schema constraint | 18 | 52 | 623 | 26 | 516 | 0 | 9 | 9 | 0 |
| other | 4 | 110 | 1379 | 1 | 35 | 0 | 0 | 1 | 3 |
| query-filter | 19 | 58 | 1111 | 35 | 698 | 0 | 7 | 12 | 0 |
| projection | 16 | 86 | 1401 | 30 | 620 | 0 | 3 | 13 | 0 |
| group-aggregate | 7 | 20 | 690 | 11 | 290 | 0 | 1 | 6 | 0 |
| write | 15 | 63 | 819 | 120 | 1082 | 0 | 5 | 6 | 4 |
| geometry | 5 | 16 | 291 | 11 | 145 | 1 | 0 | 3 | 1 |
| time series | 9 | 19 | 436 | 16 | 327 | 2 | 4 | 2 | 1 |
| db function | 5 | 20 | 367 | 6 | 193 | 0 | 1 | 4 | 0 |
| view | 2 | 5 | 89 | 4 | 75 | 1 | 0 | 1 | 0 |
| read row | 4 | 10 | 361 | 3 | 150 | 0 | 0 | 3 | 1 |
| live query | 11 | 40 | 837 | 32 | 1049 | 6 | 2 | 3 | 0 |
| Total (with overlap) | 146 | 627 | 10236 | 408 | 7144 | 18 | 39 | 77 | 12 |

Reading of the table: the Roc side is shorter in link, constraint-from-type and live-query features. It is longer in every query and projection that needs a result type and a function. N49 to N52 are scenario data on the Roc side and are not compared; M13, M22, M48, M94, N02, N05, N07, N35 have no SQL counterpart or a fixture counterpart.

## 2. Per-feature table

Status: SurrealQL port status from NOTES.md. Verdict: R = Roc shorter, = similar, S = SurrealQL shorter.

| ID | Cat | Roc l/t | SQL l/t | SQL status | Verdict | Note |
| --- | --- | --- | --- | --- | --- | --- |
| M01 | row type | 8/95 | 4/26 | full | S | Roc: 4 of 8 lines are `encoder_for : _` / `parser_for : _` (main.roc:32-33, 49-50). Gives typed rows, encoder, parser. SQL has no types. |
| M02 | row type | 22/155 | 10/91 | full | S | Roc row types (Patient, Visit, Treats) are the field list. SQL repeats the same names with DEFINE FIELD. Roc also gives a client type. |
| M03 | row type | 16/135 | 6/30 | not needed | S | Roc: handle plus annotation per table (main.roc:95-118), 2 lines each. SQL: DEFINE TABLE only. Roc allows 2 row types per table (unchecked_vets). |
| M04 | row type | 3/68 | 5/100 | full | = | `zip ?: Str` in Roc vs `option<string>` in SQL. Same size. SQL slice shared with M14 asserts. |
| M05 | row type | 2/81 | 2/50 | full | S | `?? []` in the type (main.roc:31). SQL: DEFAULT [] in the field. Roc inside the type, SQL inside the field line. |
| M06 | row type | 3/61 | 2/39 | full | S | Nested record is one alias line in Roc. SQL one literal object type per field. Same. |
| M07 | row type | 1/48 | 1/30 | full | S | `List(Str)` vs `array<string>`. Same idea, Roc shared line. |
| M08 | row type | 4/48 | 2/48 | full | = | Roc list of records. SQL literal `array<{..}>` refuses extra keys by type. Generated needs an object::keys assert (see G4). |
| M09 | row type | 6/133 | 4/68 | full | S | Roc: U8, I32 give ranges (main.roc:41-44). SQL: 5 hand written ASSERT ranges. Roc counts include the whole VetRow line. Roc is better on repetition. |
| M10 | row type | 4/59 | 1/17 | not needed | S | `VetRow(years)` (main.roc:42-44, 101-103) gives a checked and an unchecked row for one table. SQL has one schema, so no use for it. Roc ceremony for tests only. |
| M11 | row type | 5/64 | 6/97 | full | = | `Dec`, `Surreal.Datetime` vs decimal, datetime. Same. |
| M12 | row type | 3/73 | 5/148 | full | R | Roc tag unions (3 lines) become literal union types; SQL writes the union plus kind asserts (M40, M41). |
| M13 | row type | 3/35 | 0/0 | not needed | n/a | Roc: a second row type (MedicationForm) + handle for write-only fields (main.roc:53-55, 108-109). SQL needs nothing. |
| M14 | link | 3/24 | 5/123 | full | R | Roc: a `Surreal.Link(T)` field type gives type, REFERENCE and exists-assert. SQL: ASSERT record::exists in 10 places. |
| M15 | link | 2/20 | 5/92 | full | R | Roc: link inside optional record gives assert, index and delete event from the type. SQL: 4 hand written statements. |
| M16 | link | 4/48 | 10/200 | full | R | Roc: link in list of records gives assert, index, event. SQL: 3 statements per path. |
| M17 | link | 1/32 | 4/122 | full | R | Roc: link in a union arm gives assert and event from the type. SQL: event by hand. |
| M18 | link | 2/55 | 1/27 | full | = | Roc: `.on_delete(owners, Unset)` (main.roc:362). SQL: REFERENCE ON DELETE UNSET in the field. Same size. |
| M19 | link | 3/36 | 4/67 | full | = | Roc: `.default` + `.on_delete_at` (main.roc:388, 392). SQL: DEFAULT [] REFERENCE ON DELETE UNSET (SQL slice has read-back SELECTs, inflated). |
| M20 | link | 2/14 | 6/113 | full | R | Roc: one `.on_delete(x, Cascade)` line. SQL: keyword in field line. SQL slice includes read-back SELECTs, so counts overstate SQL. |
| M21 | link | 2/14 | 10/220 | full | R | Roc: 2 lines give REJECT on top-level links and 4 events for nested links. SQL: 1 keyword + 4 events by hand. Real Roc win. |
| M22 | link | 0/0 | 0/0 | not possible | n/a | Roc: Link has two meanings, `get()` reads the row in the program (main.roc:244-256). SQL: not possible, needs a second query. |
| M23 | edge | 3/53 | 1/12 | full | S | Roc: row type + handle + `Surreal.relation("treats", vets, patients)` (main.roc:93, 117-118) = 3 lines. SQL: 1 line. Roc edge ends are typed. |
| M24 | edge | 1/6 | 1/4 | full | = | `treats.insert(..)` vs INSERT RELATION. Same. |
| M25 | edge | 1/15 | 1/14 | full | = | `.check("since a real year", |e| ..)` vs ASSERT in the field. Same. |
| M26 | edge | 1/20 | 1/11 | full | S | `.unique(|e| { from: e.from, to: e.to })` vs `DEFINE INDEX .. in, out UNIQUE`. SQL names the index by hand; Roc names it. Roc a little longer. |
| M27 | edge | 4/63 | 2/51 | full | S | Roc: EdgeLine type, line fn using `e.from.get().name`, create call. SQL: RELATE + path `in.name`. Roc more ceremony. |
| M28 | edge | 4/108 | 1/33 | full | S | Roc: CaseLoad type, 1-line fn with `to_i64_wrap`, from/outgoing/select/prepare (main.roc:488-492, 837). SQL: 1 line. Roc checks edge direction at compile time. |
| M29 | edge | 4/119 | 1/31 | full | S | Roc: TeamLine type + fn + chain (main.roc:494-498, 843). SQL: 1 line with `<-treats[WHERE primary].in.name`. |
| M30 | schema constraint | 1/10 | 1/9 | full | = | `.unique(|o| o.email)` vs DEFINE INDEX ... UNIQUE. Same. Roc names index itself. |
| M31 | schema constraint | 1/24 | 1/15 | full | S | Composite unique with a record lambda vs a field list. Roc a bit longer. |
| M32 | schema constraint | 1/12 | 1/11 | full | = | Same. |
| M33 | schema constraint | 1/20 | 1/11 | full | S | Same, Roc record lambda longer. |
| M34 | schema constraint | 3/32 | 3/26 | full | = | `.index(|o| ..)` vs DEFINE INDEX. Roc a bit longer. |
| M35 | schema constraint | 3/37 | 1/25 | partial | S | Roc: one function `valid_email` for the DB assert and for the program (main.roc:129-131). SQL: assert only; program needs its own copy. |
| M36 | schema constraint | 1/20 | 1/17 | partial | = | `.assert(|v| v.license, |l| l.starts_with("VET-"))` vs ASSERT in the field. Roc has no Roc-side reuse here. |
| M37 | schema constraint | 1/24 | 1/17 | full | = | `Surreal.Text.is_email` has no Roc body (database only) vs string::is_email. Same size. |
| M38 | schema constraint | 1/18 | 1/30 | full | = | `.assert_each` vs `$value.all(|$t| ..)`. Same. |
| M39 | schema constraint | 4/58 | 2/33 | full | S | `.assert_each(|p| p.vaccines, ..)` vs `DEFINE FIELD vaccines[*].name ON patient ASSERT`. Roc count includes 4 lines of shared helper Clinic.positive_doses (Clinic.roc:17-19). Roc helper is reusable on any row. |
| M40 | schema constraint | 6/44 | 2/49 | full | = | Roc: match function (6 lines, main.roc:181-186) reused by program. SQL: one ASSERT line. Roc checks the match is exhaustive. |
| M41 | schema constraint | 6/51 | 2/79 | full | = | Roc: `sane_outcome` 6 lines (main.roc:175-179). SQL: IF chain in one ASSERT, inside the union field line. Similar size. |
| M42 | schema constraint | 6/73 | 3/64 | full | = | `.check("named", ..)` x4 vs ASSERT in field. Roc gives check names; SQL port loses the name. |
| M43 | schema constraint | 3/48 | 1/36 | full | S | Roc: `.check("items need a fee", Clinic.fee_covers_items)` + 3-line helper (Clinic.roc:21-24). SQL: field ASSERT reading $this.items. Generated uses an event (G7). |
| M44 | schema constraint | 1/10 | 1/17 | full | S | Roc: `.readonly(|v| v.license)` (main.roc:371) vs one keyword READONLY in the field. SQL shorter. |
| M45 | schema constraint | 7/56 | 1/22 | partial | S | Roc: `label_of` fn + `.computed(..)` (7 lines, main.roc:133-135, 375-379). SQL: VALUE clause in the field. Roc fn is callable by the program. |
| M46 | schema constraint | 1/13 | 2/40 | full | S | Roc: `.default(|p| p.allergies, [])` (main.roc:388) vs `DEFAULT []`. Note M05 uses `?? []` in the type; two ways in Roc. |
| M47 | schema constraint | 5/73 | 1/15 | full | S | Roc: Note row type + handle + definition + `default_by` (main.roc:1090-1098) just to say DEFAULT rand::ulid(). SQL 1 line. |
| M48 | other | 60/564 | 0/0 | not needed | n/a | Roc: 60 lines of `x.define()...done()` blocks (main.roc:353-412). These lines hold M30-M47 builders: overlap. SQL: no counterpart (the .surql file is the schema). |
| M49 | query-filter | 4/69 | 2/38 | full | S | Roc: param type, filter fn, select, order_by, prepare (main.roc:416-419, 765). SQL: LET + SELECT. Roc: typed parameter. |
| M50 | projection | 4/86 | 2/38 | full | S | Roc: OwnerCard type + fn (main.roc:421-425). SQL: aliases. Roc gives a typed result. |
| M51 | projection | 3/74 | 2/38 | full | S | `o.?phone ?? "none"` vs `phone ?? "none"`. Same idea. |
| M52 | query-filter | 3/41 | 1/26 | full | S | `filter(is_vip)` with `tags.contains` becomes `tags CONTAINS`. Roc adds a named fn (2 lines). |
| M53 | query-filter | 1/32 | 1/24 | full | = | `o.?referred_by.is_ok()` vs `referred_by != NONE`. Same. |
| M54 | projection | 10/90 | 1/24 | full | S | Roc: 10-line match on Option (main.roc:427-437). SQL: `referred_by.name` path, 1 line. Roc verbose. |
| M55 | projection | 4/76 | 1/32 | full | S | Roc: PetLine type, fn, by_id fragment (main.roc:442-446, 783). SQL: 1 line. Roc: `p.owner.get().name`, compile-checked. |
| M56 | projection | 9/94 | 4/86 | full | = | Roc: `species_label` match (7 lines, main.roc:137-143) reused in program. SQL: DEFINE FUNCTION IF chain, same size. |
| M57 | projection | 4/109 | 1/32 | not needed | S | Roc: `Clinic.by_id` open-row fragment (Clinic.roc:52-54) reused by 2 queries. SQL: `ORDER BY id` is one clause, no fragment is needed. SQL shorter for one use. |
| M58 | query-filter | 3/33 | 1/19 | full | S | Roc: `vets.at(ruth_id)` + id value (main.roc:120-121, 789). SQL: FROM vet:ruth. Roc id is typed. |
| M59 | query-filter | 1/37 | 2/32 | full | = | `filter_by(|p, v| v.id == p.key)` vs `FROM type::record(...)`. Same size. Generated is a WHERE form (G12). |
| M60 | query-filter | 6/62 | 1/13 | full | S | Roc: 5-line match to test a union arm (main.roc:158-162). SQL: `species.wingspan_cm >= 20` (missing field is false). Roc safer, longer. |
| M61 | projection | 3/99 | 2/22 | full | S | Roc range holds 3 queries. Per query: `select_value(|p| p.name)` chain about 3x tokens of SELECT VALUE. SQL slice shares lines. |
| M62 | projection | 14/106 | 1/33 | full | S | Roc: 14-line ChipLine fn, 2 matches on `p.?chip` (main.roc:448-462). SQL: 1 line with `??`. Roc worst case of option handling. |
| M63 | projection | 4/76 | 1/29 | full | S | Roc: VaccineLine type + fn (main.roc:464-468). SQL: `vaccines.vet.name`. Roc compile-checked. |
| M64 | query-filter | 3/53 | 1/29 | full | S | Roc: `p.vaccines.any(|v| v.vet.id() == ruth_id)` vs `vaccines.vet CONTAINS vet:ruth`. Generated uses a closure (G2). |
| M65 | query-filter | 10/225 | 4/75 | partial | S | Roc: 5 helpers in Clinic (Clinic.roc:26-34, 48-50) reused by M86, M91. SQL: LET + inline filter. Counts shared with M86 and M91. Roc is reuse, SQL is shorter for one use. |
| M66 | projection | 7/198 | 4/75 | full | S | Roc: `Clinic.bill` is one Roc fn for program and projection (Clinic.roc:9-15). SQL: inline expression with `.map(|$i| ..)`. SQL cannot share it with the app. |
| M67 | query-filter | 1/40 | 1/21 | full | S | `Surreal.Time.now()` vs time::now(). Roc count is the whole chain. |
| M68 | projection | 10/93 | 3/50 | full | S | Roc: outcome_text match + line fn (main.roc:145-150, 480-483). SQL: IF chain. Roc exhaustive. |
| M69 | query-filter | 8/66 | 3/50 | full | S | Roc: needs_attention + needs_follow_up (8 lines, main.roc:152-156, 485-486). SQL: `outcome != "Treated"`. Roc verbose (wildcard match for a negation). |
| M70 | projection | 1/20 | 1/15 | full | = | `select_value(|v| v)` vs `SELECT *, record::id(id) AS id`. Same. |
| M71 | projection | 4/69 | 1/21 | full | S | Roc: PatientAge type + fn + chain (main.roc:505-508, 855). SQL: 1 line. |
| M72 | projection | 1/39 | 1/36 | full | = | `.order_by(..).start(2).limit(2)` vs ORDER BY LIMIT START. Same size. Roc checks clause order. |
| M73 | projection | 4/89 | 1/29 | full | S | Roc: ContactLine type + fn. SQL: 2 paths. |
| M74 | projection | 4/83 | 4/60 | full | S | Roc: `p.owner.get()` returns the whole Owner with string ids (main.roc:533-537). SQL: 2 subselects with $parent. Roc is simpler to write. |
| M75 | query-filter | 3/50 | 2/27 | full | S | Roc: `Surreal.bind_captured(Surreal.select_where(..))` and a `Try(Prepared(..))` annotation (main.roc:510-513). SQL: LET + SELECT. Awkward Roc API. |
| M76 | query-filter | 3/56 | 2/50 | full | = | `places.contains(o.address)` vs `address IN $addresses`. Same. |
| M77 | query-filter | 4/55 | 4/72 | full | = | `o.address == place` vs `address = $addr`. Same size. Generated uses 3 conditions (G11). |
| M78 | group-aggregate | 4/145 | 2/47 | full | S | Roc: Ledger type + `ledger_line` fn with `.to_i64_wrap()`, `.to_f64()` (main.roc:500-503, 849). SQL: 1 SELECT with count(), math::sum. Roc verbose aggregates. |
| M79 | group-aggregate | 2/115 | 2/47 | full | S | Same statement as M78. Roc: `Surreal.Math.mean(rows.map(|v| v.fee.to_f64()))` vs `math::mean(<float>fee)`. |
| M80 | group-aggregate | 1/50 | 2/47 | full | = | `.order_by(|r| r.revenue, Desc).limit(2)` vs ORDER BY LIMIT. Same. |
| M81 | group-aggregate | 4/102 | 1/34 | full | S | Roc: VisitTotals + fn + totals (main.roc:1117-1122, 1134). SQL: GROUP ALL, 1 line. |
| M82 | group-aggregate | 1/44 | 1/16 | full | S | `.totals(|rows| { visits: rows.len().to_i64_wrap() })` vs `count() ... GROUP ALL`. Roc 2.7x tokens. |
| M83 | write | 6/36 | 8/23 | full | = | 6 insert calls (rows are typed values in F) vs BEGIN/6 INSERT/COMMIT. Roc has fewer lines, more tokens. |
| M84 | write | 1/6 | 2/37 | full | = | `patients.create(pip)` vs `CREATE patient:pip CONTENT` (payload in F). Same. SQL slice has a read-back SELECT. |
| M85 | write | 2/25 | 2/25 | full | = | Roc: MedicationForm row (M13) lets the user type only the form fields. SQL: CREATE with the same fields. Same. |
| M86 | write | 6/94 | 4/46 | full | S | Roc: RestockParam, refill, Clinic.low_stock (main.roc:544-547, Clinic.roc:40-42). SQL: `UPDATE .. SET stock += $add WHERE stock < $floor`. SQL expresses a delta; Roc writes the whole row (`{ ..m, stock: m.stock + p.add }`). |
| M87 | write | 3/54 | 2/42 | full | S | Roc: `{ ..v, years: v.years + 1, specialty: .. }` (main.roc:554-556). SQL: SET list. Similar; Roc typed. |
| M88 | write | 3/39 | 2/43 | full | = | Roc: `{ ..o, name: .. }` patch fn. SQL: SET name. Same. |
| M89 | write | 3/67 | 2/49 | full | S | Roc: `set_at` with an Err(Missing) type for NONE (main.roc:563-566). SQL: `SET phone = NONE`. Roc checks patch fields at compile time. |
| M90 | write | 1/17 | 2/10 | full | = | `owners.delete_at(..)` vs DELETE. Same. |
| M91 | write | 3/62 | 3/31 | full | S | Roc: Clinic.too_old helper (Clinic.roc:36-38). SQL: DELETE .. WHERE seen < $before. Shared helper. |
| M92 | write | 11/185 | 2/14 | full | S | Roc: Note row type, handle, definition, NoteLine, line fn (main.roc:1083-1108), 11 lines for an insert without id. SQL: 2 lines. Roc inflated by type ceremony. |
| M93 | write | 24/234 | 24/140 | full | S | 24 refusals. Roc: one create/update/delete call per refusal. SQL: heads only, payloads in F. SQL slice has 24 lines for 24 calls. Roc tokens higher from handle names. |
| M94 | other | 22/511 | 0/0 | partial | n/a | Roc: Clinic.roc (22 code lines): open-row helpers reused by M39, M43, M65, M66, M86, M91. SQL: fn:: takes any object but no clause fragment is possible. |
| N01 | geometry | 1/23 | 5/58 | full | R | Roc: `location : Surreal.Point, area : Surreal.Polygon` (monitoring.roc:42) gives geometry type and the geo::is_valid assert. SQL: 2 DEFINE FIELDs with assert by hand. |
| N02 | geometry | 7/91 | 1/3 | full | n/a | Roc: `rectangle` builder (monitoring.roc:150-164). SQL: GeoJSON literal in F. Not comparable (SQL side is fixture). |
| N03 | link | 1/20 | 4/40 | full | R | Roc: `site : Surreal.Link(Site)` gives REFERENCE REJECT + exists assert. SQL: 3 lines (table, field, seed head). |
| N04 | time series | 1/29 | 4/39 | full | R | Roc: `TimeKey(Surreal.Id(Kennel))` for the compound id and CHANGEFEED in N19. SQL: `[record<kennel>, datetime]` type. |
| N05 | time series | 3/59 | 1/3 | full | n/a | Roc: `reading` seed builder. SQL: seed head only. Not comparable (fixture). |
| N06 | edge | 10/130 | 8/60 | full | S | Roc: 2 edge types, 2 handles, 2 `_def` lines (monitoring.roc:51-54, 68-72, 112-116) = 10 lines. SQL: 2 tables + 2 fields. Boilerplate in Roc. |
| N07 | other | 25/211 | 0/0 | not needed | n/a | Roc: 9 `x_def : Surreal.Defined; x_def = x.define().done()` pairs + `definitions` list (monitoring.roc:103-126, 306-315). SQL: no counterpart. Pure ceremony for 5 tables with no rules. |
| N08 | db function | 5/76 | 1/35 | partial | S | Roc: `fever` fn + `Surreal.db_fn` + `definitions` entry (monitoring.roc:90-99, 309), the same fn runs in Roc tests. SQL: 1-line DEFINE FUNCTION. |
| N09 | db function | 1/36 | 1/43 | full | = | `fever_fn.call2(v.temp_c, v.pulse)` vs `fn::fever(temp_c, pulse)`. Same. |
| N10 | db function | 6/54 | 1/24 | full | S | Roc: `.computed(|v| v.fevered, ..)` with `.changefeed` in one builder (monitoring.roc:121-126). SQL: VALUE clause. |
| N11 | db function | 4/79 | 1/27 | full | S | Roc: FlagLine type + fn. SQL: 1 SELECT. |
| N12 | db function | 4/122 | 2/64 | full | S | Roc: Daily type + day_line fn with `keep_if(..).len().to_i64_wrap()`. SQL: `count(fn::fever(..))`. |
| N13 | time series | 4/106 | 1/43 | full | S | Roc: VitalLine type + fn with `.series()`, `.time()` accessors (monitoring.roc:216-219). SQL: `record::id(id)[0]`. Roc is readable. |
| N14 | time series | 4/79 | 1/27 | full | S | Same statement as N11. |
| N15 | time series | 1/26 | 2/52 | full | R | Roc: `.between(kennel_a, day_start, day_end)` typed range. SQL: array-key range literal repeated. Roc wins. |
| N16 | time series | 1/29 | 1/34 | full | = | Same as N15 with whole row. |
| N17 | time series | 3/66 | 2/64 | full | = | Roc: day_of with `Surreal.Time.floor(.., days(1))`. SQL: `time::floor(.., 1d)`. Same size. Generated: G14. |
| N18 | time series | 1/30 | 3/57 | full | = | `vitals.delete_by(|p, v| v.id.time() < p.before)` vs DELETE WHERE. Same. |
| N19 | time series | 1/12 | 1/8 | full | = | `.changefeed(Surreal.Time.days(7))` vs `CHANGEFEED 1w`. Same. |
| N20 | group-aggregate | 7/188 | 2/64 | full | S | Roc: DayKey + day_of + Daily + day_line (monitoring.roc:130-139, 352). SQL: 1 SELECT with GROUP BY. Roc 3x tokens. |
| N21 | view | 4/45 | 3/68 | full | R | Roc: view built from the same query and line fn (monitoring.roc:141-146): no second SQL text. SQL: repeats the SELECT. |
| N22 | view | 1/44 | 1/7 | full | S | Roc: respells 4 fields `{ kennel: d.kennel, day: d.day, ..}` (monitoring.roc:390-394). SQL: `SELECT * OMIT id`. No OMIT or rest spread. |
| N23 | query-filter | 1/36 | 1/43 | full | = | Same. |
| N24 | query-filter | 1/36 | 1/11 | full | S | Roc: group, aggregate, filter in one chain (monitoring.roc:360-366). SQL hand-written reads the view; Roc recomputes the group. Different source, so counts do not compare. |
| N25 | query-filter | 1/46 | 1/57 | full | = | Roc: select, order_by, limit, filter: limit before filter in order. SQL uses array `.filter` on the subquery. Same size. |
| N26 | query-filter | 1/47 | 1/27 | full | S | Roc: scalar version. 1.7x tokens. |
| N27 | group-aggregate | 1/46 | 1/35 | full | S | Roc: `.select(hot_line).query().filter(..).group_by(..)` (monitoring.roc:378-383). SQL: one SELECT with WHERE and GROUP BY. `.query()` is a mode switch. |
| N28 | query-filter | 1/54 | 2/19 | full | S | Roc: `.query().filter_by(..).select(|r| r)` after aggregate (monitoring.roc:384-389). SQL reads the view. Different source. |
| N29 | geometry | 4/56 | 1/22 | full | S | Roc: SiteLat type + fn with `s.location.lat()`. SQL: `location.coordinates[1]`. |
| N30 | geometry | 3/71 | 2/27 | full | S | Roc: `.to_geometry()` conversions on both sides (monitoring.roc:408). SQL: `$here INSIDE area`. Geo.inside has no Roc body. |
| N31 | geometry | 1/50 | 2/35 | full | S | `Surreal.Geo.distance` (no Roc body) vs geo::distance. Same. |
| N32 | read row | 4/127 | 1/50 | full | S | Roc: KennelRead, CareRead read rows (second row types) + select (monitoring.roc:74-83, 418). SQL: path in the SELECT. Roc: no hand traversal, compile-checked. One statement shared N32-N34. |
| N33 | read row | 3/140 | 1/50 | full | S | Same statement as N32. Edge traversal `<-cares_for<-carer.{..}` in SQL vs `k.cares_for.list().map(|e| e.from)`. |
| N34 | read row | 1/82 | 1/50 | full | S | Same statement as N32. Count of lead edges. |
| N35 | read row | 2/12 | 0/0 | not needed | n/a | Roc: `kennel_reads.define_read()` checks the read row against the stored row (monitoring.roc:118-119). SQL: no read rows. |
| N36 | other | 3/93 | 1/35 | full | S | Roc: `readings_of(vitals.rows(), k).len()` plain list code (monitoring.roc:262-264, 422-426). SQL: correlated subselect with $parent.id. Roc shorter to read; generated is worse (G16). |
| N37 | query-filter | 3/73 | 4/65 | full | = | Roc: has_fever on a list, reused by N43. SQL: DEFINE FUNCTION + use. Same size. Generated: G17. |
| N38 | live query | 3/56 | 2/82 | full | R | Roc: Watch type, `.live({}, definitions)` (monitoring.roc:441-443). SQL: LIVE with `$before` term + snapshot + client code (not counted). SQL needs ~40 lines of client for items 1-7 (NOTES.md). |
| N39 | live query | 3/65 | 3/101 | full | R | Roc: parameter in `live({limit: limit}, ..)`. SQL: LET + LIVE + snapshot. Client code not counted. |
| N40 | live query | 3/64 | 2/25 | full | S | Roc respells 4 fields of the view (monitoring.roc:450-452). SQL: field list is also 4 names. Roc has the Try(Watch(..)) annotation. |
| N41 | live query | 8/129 | 3/122 | full | = | Roc: `.incoming(cares_for).filter(no_carer)` and the edge-side live is derived (monitoring.roc:454-466). SQL: 2 LIVE statements, client merges. Counts close, Roc does the merge. |
| N42 | live query | 3/85 | 3/122 | not needed | R | Roc: read row version (monitoring.roc:468-471). SQL: same statements as N41. |
| N43 | live query | 3/59 | 6/125 | full | R | Roc: `has_fever(vitals.rows(), k)` in a live filter, 1 line. SQL: DEFINE FUNCTION + 2 LIVE. Generated sends all kennels (G18). |
| N44 | live query | 8/173 | 5/277 | full | R | Roc: `.and_incoming(checks)` gives 3 LIVE statements (monitoring.roc:478-490). SQL: 3 LIVE by hand, long WHERE repeated. |
| N45 | live query | 3/64 | 3/63 | full | = | Roc: live over a read row (monitoring.roc:492-498). SQL: 2 LIVE + snapshot. Same size. |
| N46 | live query | 2/60 | 3/82 | full | R | `k.site.get().name == "Oslo"` in the filter. SQL: 2 LIVE with `$before.site.name` term. Roc derives site stream. |
| N47 | live query | 2/53 | 1/44 | full | S | `live_raw` (RawWatch) vs plain LIVE SELECT. Same. |
| N48 | live query | 2/29 | 1/6 | full | S | Roc: `Try(Surreal.DiffWatch(Vital), Surreal.Error)` annotation + `live_diff({})`. SQL: `LIVE SELECT DIFF FROM vital`. Roc has the typed patch. |
| N49 | write | 0/0 | 38/407 | full | n/a | Scenario writes are F on the Roc side (monitoring.roc:523-531, 597-626). SQL slice counts statement heads only. Excluded. |
| N50 | write | 0/0 | 11/125 | full | n/a | Scenario edge writes. Same as N49. Excluded. |
| N51 | write | 0/0 | 4/20 | full | n/a | Scenario deletes. Excluded. |
| N52 | write | 0/0 | 14/70 | full | n/a | Scenario site writes. Excluded. |

## 3. Where Roc is weaker (ranked)

Rank is by how many features it touches and by how much extra text it adds. Roc line numbers are in examples/main.roc (m) or examples/monitoring.roc (n).

| Rank | Weakness | IDs | Roc | SurrealQL |
| --- | --- | --- | --- | --- |
| 1 | Every projection needs a result type, a typed function and a select/prepare chain. A one-line SELECT becomes 4 lines. This is the largest source of SQL-shorter verdicts (most of the 77 SQL-shorter verdicts). The type buys typed results, but a one-off query pays the full price. | M28, M29, M49-M51, M55, M63, M71, M73, M78, M81, N11-N14, N20, N29 | m:505-508 `PatientAge : {..}` / `patient_age : Patient -> PatientAge` / `patient_age = \|p\| { id: p.id, age: p.age }` / m:855 `Surreal.from(patients).select(patient_age).order_by(\|r\| r.age, Desc).limit(3).prepare({})` | `SELECT record::id(id) AS id, age FROM patient ORDER BY age DESC LIMIT 3;` (port main.surql:279) |
| 2 | Option and tag-union values need a `match` where a path walks through NONE. 10 to 14 lines against one path. | M54, M60, M62, M69 | m:448-462 `chip_line` with two `match p.?chip { Ok(c) => .., Err(_) => .. }` | `chip.code ?? 'none' AS chip, chip.implanted_by.name ?? 'nobody' AS by` (port main.surql:249) |
| 3 | Aggregates are written as list code with numeric conversions, not as aggregate calls. | M78, M79, M81, M82, N12, N20 | m:503 `{ vet, visits: rows.len().to_i64_wrap(), revenue: rows.map(\|v\| v.fee).sum(), avg_fee: Surreal.Math.mean(rows.map(\|v\| v.fee.to_f64())) }` | `count() AS visits, math::sum(fee) AS revenue, math::mean(<float>fee) AS avg_fee ... GROUP BY vet` |
| 4 | Per-table boilerplate: handle plus annotation, `x_def : Surreal.Defined` plus `.define().done()` even with no rules, `encoder_for : _` and `parser_for : _`, and a `definitions` list. | M01, M03, M23, M47, N06, N07 | n:103-116 `site_def : Surreal.Defined` / `site_def = sites.define().done()` x5; m:32-33 `encoder_for : _` / `parser_for : _`; m:95-118 16 lines of handles | `DEFINE TABLE site SCHEMAFULL;` (port monitoring.surql:2) |
| 5 | Second row types for one table: read rows, form rows, a table only to carry a default. Each needs a type and often a handle. | M10, M13, M47, M92, N32-N35 | n:74-83 `CareRead`, `KennelRead`, `kennel_reads`; m:1090-1098 `Note` row to say `rand::ulid()` | `DEFINE FIELD id ON note TYPE string DEFAULT rand::ulid();` |
| 6 | Constraint builders are longer than the keyword they replace, and defaults have two spellings (`?? []` in the type, `.default(..)` in the builder). | M26, M31, M33, M34, M44, M46 | m:371 `.readonly(\|v\| v.license)`; m:388 `.default(\|p\| p.allergies, [])` | `READONLY`; `DEFAULT []` |
| 7 | No rest-spread or OMIT in a projection: a view row is respelled field by field. | N22, N40, N28 | n:390-394 `select(\|d\| { kennel: d.kennel, day: d.day, readings: d.readings, fevers: d.fevers })` | `SELECT * OMIT id FROM vital_daily;` |
| 8 | Parameterised prepared queries have an awkward second API with a `Try(Prepared(..))` annotation. | M75, M76, M77 | m:510-513 `cheaper_than : Dec -> Try(Surreal.Prepared(List(Medication)), Surreal.Error)` / `Surreal.bind_captured(Surreal.select_where(medications, \|m\| m.unit_price < limit))` | `LET $max = 0.9dec; SELECT ... WHERE unit_price < $max;` |
| 9 | Updates write the whole row and compute the delta in Roc. SQL can say `+=`. | M86, M87 | m:546 `refill = \|p, m\| { ..m, stock: m.stock + p.add }` | `UPDATE medication SET stock += $add WHERE stock < $floor;` |
| 10 | Several functions have no Roc body (database only), so the one-function claim does not hold: `Geo.inside`, `Geo.distance`, `Text.is_email`. The changefeed check needs raw SurrealQL in the harness. | M37, N30, N31, N19 | m:369 `Surreal.Text.is_email(e)`; n:408 `Surreal.Geo.inside(p.here.to_geometry(), s.area.to_geometry())` | `string::is_email($value)`; `$here INSIDE area` |

Fairness note: the SurrealQL port has no application types, no typed results, no client code and no live merge code (a 40 line Node script, NOTES.md). Rank 1 and 3 partly pay for typed results. Rank 4 and 5 do not.

## 4. Where Roc is stronger

| Rank | Strength | IDs | Roc | SurrealQL |
| --- | --- | --- | --- | --- |
| 1 | A link type gives type, REFERENCE, exists-assert, index and delete rule. Nested links give the event by themselves. | M14-M17, M19-M21, N03 | m:71 `owner : Surreal.Link(Owner)` | 10 asserts, 4 indexes, 4 events by hand (port main.surql:118-127) |
| 2 | One function is the DB constraint, computed field, projection and program code. | M35, M40, M41, M43, M45, M66, N08-N12 | m:129-131 `valid_email` used by `.assert(\|o\| o.email, valid_email)` and by the program | Assert only; the app writes a copy |
| 3 | Live queries: Watch type, leave notices, edge and join streams and the snapshot come from one filter. | N38-N46, N48 | n:441-443 `fevered = Surreal.from(vitals).filter(..).select(vital_line).live({}, definitions)` | `$before` term, 2 to 3 LIVE statements, snapshot, client merge |
| 4 | Types give ranges and defaults: U8, I32 become range asserts. | M05, M09 | m:41-44 `Vet : VetRow(U8)` | 5 hand written `ASSERT $value IN 0..=255` |
| 5 | Compile-time checks: field names, clause order, edge direction, patch fields, match exhaustiveness. A read typo gives NONE in SQL. | M28, M40, M41, M72, M89 | m:563-566 `moved` patch | no check |
| 6 | Links read as rows in the program (`get()`), and as a path in a clause. | M22, M55, M74 | m:533-537 `owner: p.owner.get()` returns the whole Owner | 2 subselects with `$parent` (port main.surql:295) |
| 7 | Views and queries share one definition. | N21 | n:141-146 `daily.define_as(Surreal.from(vitals).group_by(day_of), day_line)` | The SELECT is written twice (view and query) |
| 8 | Typed key ranges and compound ids. | N04, N13, N15, N16 | n:343 `.between(kennel_a, day_start, day_end)` | `vital:[kennel:a, d'..']..[kennel:a, d'..']` |
| 9 | Reuse of query fragments over any row. | M57, M65, M91, M94 | Clinic.roc:26-34, 48-50 | no fragment type |
| 10 | Type-derived schema: no drift between type and DEFINE FIELD. Union types give the field type and the kind assert. | M12, M48 | m:39,57,80 | 3 literal union types plus 2 IF-chain asserts |

## 5. Generated output issues

Generated script: main.surql, monitoring.surql in the scratch folder (g). Hand-written: surql/main.surql, surql/monitoring.surql (h). Source: src/ files of the repo.

| ID | Issue | Generated | Hand-written | Impact | src/ |
| --- | --- | --- | --- | --- | --- |
| M15-M17 | Delete rule scans with a closure instead of an indexed CONTAINS (NOTES.md: EXPLAIN shows TableScan for the closure form) | g main.surql:70 `WHERE vaccines.any(\|$e1\| $e1.vet = $before.id)` | h main.surql:121 `WHERE vaccines.vet CONTAINS $before.id` | High: a table scan per vet or medication delete, although the index patient_vaccines_vet_link exists | Schema.roc:422-432 (`mentions`, `.any(..)` at 430) |
| M63, M64 | Same closure shape in queries | g main.surql:142 `WHERE vaccines.any(\|$v1\| $v1.vet = vet:ruth)` and `vaccines.map(\|$v1\| $v1.vet.name)` | h main.surql:252 `vaccines.vet CONTAINS vet:ruth`, `vaccines.vet.name` | Medium: no index use (index use for this form not tested here), longer text | Translate.roc:2181-2184, 2528-2534 |
| M28, M29 | Edge filter as closure | g main.surql:160 `->treats.filter(\|$v1\| $v1.primary).len()` | h `array::len(->treats[WHERE primary])` | Low: builds the edge list first | Translate.roc:2532, 2434 |
| M08, M39 | Extra key check assert on every write of a list of objects | g main.surql:39 `ASSERT $value.all(\|$e\| object::keys($e).all(\|$k\| $k IN ['given','name','vet']))` | h `TYPE array<{ name: string, given: string, vet: record<vet> }>` (type refuses extras) | Medium: per element cost on every write, 2 asserts | Types.roc:715 (`key_check`) |
| M42, M43 | Multi-field check is an EVENT, so it runs after the write and on every UPDATE, and the error names the event, not the field | g main.surql:68 `DEFINE EVENT .. WHEN $event IN ['CREATE','UPDATE'] THEN { IF !(..) { THROW .. } }` | h `DEFINE FIELD fee ON visit .. ASSERT $value >= 0dec AND (array::len($this.items) = 0 OR $value > 0dec)` | Medium: later failure point, different error text | Schema.roc:627 |
| M12, M09 | Redundant asserts: the union ASSERT repeats `IF $value.kind = 'Bird'` twice; ranges as two comparisons | g main.surql:38, 48 | h `ASSERT $value.kind != 'Bird' OR $value.wingspan_cm IN 1..=255` | Low: longer text, same result | Types.roc:680, 708 |
| M04, M14 | Optional link assert has `$value = NONE OR` guard that the field assert does not need | g main.surql:16 `ASSERT ($value = NONE OR (record::exists($value)))` | h `ASSERT record::exists($value)` | Low | Types.roc:616, 680, 708 |
| M54, M62 | Dead or longer branches: `IF referred_by IS NONE THEN 'nobody'` after a filter that removes NONE; `IF chip IS NONE` instead of `??` | g main.surql:116, 138 | h `referred_by.name`; `chip.code ?? 'none'` | Low: longer text, same result | Translate.roc:1885, 2171 |
| M70 | Whole row as a field list | g main.surql:183 `SELECT VALUE { contact: contact, id: record::id(id), .. }` | h `SELECT *, record::id(id) AS id` | Low | Surreal.roc (select_value of row) |
| M77 | Record equality becomes 3 AND conditions | g main.surql:211 `WHERE (address.city = $_1.city) AND (address.line = $_1.line) AND (address.zip = $_1.zip)` | h `WHERE address = $addr` | Medium: can not use an index on address; longer | Translate.roc (record `==` lowering) |
| M59 | Key lookup as WHERE, not FROM | g main.surql:130 `FROM vet WHERE id = type::record('vet', $key)` | h `FROM type::record('vet', $key)` | Low to medium: depends on planner (not tested here) | Surreal.roc:2161 |
| N17, N20, N21, N12 | Duration as nanos | g monitoring.surql:66 `time::floor(record::id(id)[1], duration::from_nanos(86400000000000))` | h `time::floor(record::id(id)[1], 1d)` | Low: function call and unreadable text; the view definition holds it too (monitoring.surql:9) | Translate.roc:1780 |
| N19 | Changefeed in nanoseconds | g monitoring.surql:8 `CHANGEFEED 604800000000000ns` | h `CHANGEFEED 1w` | Low: text only | Schema.roc:656 |
| N24, N28 | Group then filter is a subquery that recomputes the group; the hand version reads the view table | g monitoring.surql:74 `SELECT day, fevers, kennel, readings FROM (SELECT time::floor(..) .. GROUP BY day, kennel) WHERE fevers < readings` | h `SELECT * OMIT id FROM vital_daily WHERE fevers < readings` | Medium: full regroup per call. This is the Roc query as written (it does not read the view), so a Roc user can fix it with `Surreal.from(daily)` | Translate.roc:2528-2534 |
| N36 | Correlated count copies the whole id list of the table for each kennel and filters in memory | g monitoring.surql:128 `(SELECT VALUE id FROM vital).filter(\|$v1\| record::id($v1)[0] = type::record('kennel', record::id(id))).len()` | h monitoring.surql:148 `array::len(SELECT VALUE id FROM vital WHERE record::id(id)[0] = $parent.id)` | High: K x V work, memory per row; the WHERE form lets the planner push down | Surreal.roc:1142 (`rows` as `(SELECT VALUE id FROM t)`), Translate.roc:2532 |
| N37 | `any` over the whole list, no LIMIT 1; hand form stops at the first hit | g monitoring.surql:132 `WHERE (SELECT VALUE id FROM vital).filter(..).any(\|$v2\| $v2.fevered)` | h monitoring.surql:45-47 `fn::has_fever`: `(SELECT VALUE id FROM vital WHERE record::id(id)[0] = $k AND fevered LIMIT 1) != []` | High: scan of vital per kennel without early exit | same as N36 |
| N43 | Live notices: the vital stream re-emits every kennel on each vital event; the whole `has_fever` text is inlined 3 times in one LIVE SELECT (WHERE, `now`, `$before`) | g monitoring.surql:242-243 `LIVE SELECT VALUE (SELECT VALUE {..} FROM kennel) FROM vital;` | h monitoring.surql:284 `LIVE SELECT VALUE (SELECT id, label, fn::has_fever(id) AS now FROM ONLY $parent.id.id()[0]) FROM vital;` (only the changed kennel) | High: O(kennels) notices and O(kennels x vitals) work per vital write (NOTES.md) | Surreal.roc:2165-2180 (live), Surreal.roc:1832-1850 |
| N38-N46 | Notices carry an envelope `{ row, now }` even when `now` is the constant `true` | g monitoring.surql:189 `LIVE SELECT VALUE { row: {..}, now: true } FROM vital_daily` | h `LIVE SELECT day, kennel, readings, fevers FROM vital_daily` | Low: more bytes per notice (NOTES.md: flag not sent when always true) | Surreal.roc:2165-2180 |
| M-all | Schema: names derived and long, OVERWRITE on every statement. The long names are a cost; OVERWRITE is a benefit (re-runnable) | g main.surql:58 `owner_address_city_address_line_unique` | h `owner_address` | Low | Schema.roc:598 |

Checks that the generated side does well (no issue): M52 `tags CONTAINS 'vip'` equals the hand form; M76 `$_1 CONTAINS address` equals `IN`; N25 and N26 use a subquery with `LIMIT` before `WHERE`, which is the correct order; nested link events and indexes exist for every path.

## 6. Totals

Code lines and tokens, comments and blank lines left out. Unique means each source line counted once, even if several IDs use it.

| Item | Roc lines | Roc tokens | SQL lines | SQL tokens | Note |
| --- | --- | --- | --- | --- | --- |
| Feature code, main (M01-M94), unique | 343 | 4593 | 175 | 2709 | Roc = 321 in main.roc + 22 in examples/clinic/Clinic.roc |
| Feature code, monitoring (N01-N52), unique | 136 | 2726 | 150 | 2538 | SQL includes 67 lines / 622 tokens of N49-N52 statement heads that are scenario data |
| Feature code, monitoring without N49-N52 | 136 | 2726 | 83 | 1916 | Fair compare |
| Feature code, both, fair | 479 | 7319 | 258 | 4625 | Roc is 1.86x in lines and 1.58x in tokens |
| Fixture code, main | 180 | 2182 | 69 | 2117 | Roc: seed rows and bad rows as typed values. SQL: seed payloads |
| Fixture code, monitoring | 85 to 187 | 1004 to 3196 | 68 | 955 | Roc low end: pure F ranges. High end: includes scenario data inside the mixed ranges (monitoring.roc:597-734, 780-800) |
| Per-ID sums (overlap counted) | 627 | 10236 | 408 | 7144 | Not a true total |
| Whole files | main.roc 843, monitoring.roc 587, Clinic.roc 25 | | main.surql 244, monitoring.surql 218 | | Roc rest = harness (Mirror, expect, script assembly), not compared |

Reading of the totals: Roc feature code is about 1.6 to 1.9 times the SurrealQL text for the same features. The gap comes from rank 1 to 5 above (result types, handles, definitions, second row types). The SurrealQL port has no application types, no typed results and no client code. Roc fixtures are larger in lines (typed rows, one field per line) and similar in tokens.
