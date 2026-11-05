# ORM comparison: Roc reify-surrealdb and the SurrealDB JS SDK 2.2.2 (TypeScript)

Scope: 146 features, M01-M94 (examples/main.roc) and N01-N52 (examples/monitoring.roc). Roc source is the repo. JS source is the port in SCRATCH/js/src.

## How the numbers were made

| Item | Rule |
|---|---|
| Lines | Code lines only (no blank, no comment). |
| Tokens | Same rule as slice.py. A backtick or quoted string is one token. A SurrealQL query in a template is therefore 1 token. Tokens undercount JS raw SQL. |
| Chars | Non-space characters of the code. Used for the verdict, because tokens hide JS strings. |
| Verdict | Chars, within 20 percent = similar. A star after the verdict means I changed the automatic verdict after reading the code. |
| Roc side | Catalog ranges, minus the harness (H) and fixture (F) ranges of catalog.md section 3. In M ranges the wrappers `block(`, `plain(`, `rejects(`, `then_read(` read-back, `Surreal.Mirror.*` and `live_block(` are removed by script (SCRATCH/rocslice2.py). Closing braces count as lines. |
| JS side | Slices by `@ID` (SCRATCH/slice_noF.py on SCRATCH/adj/*.ts, a copy of the port). Changes to the copy: blocks that only read back a write for the check are removed; `ck.refused("name", () => ...)` wrappers are removed and refusal lines count only under M93; the `INFO FOR DB` check is not N19; blocks tagged `@F` count as fixture only. The port folder is not changed. |
| Raw JS slices | Raw JS counts differ in 48 IDs (shared read-backs, refusal lines). Raw numbers are in SCRATCH/js_slices.json. |

Warnings about the counts:

| Distortion | IDs | Effect |
|---|---|---|
| JS schema strings sit under many IDs (one DEFINE FIELD carries type, default, assert, reference) | M02-M21, M31-M47, N01-N06, N09-N14, N17-N21 | JS lines and chars repeat for each ID. Roc auto verdict looks too good. I read each one. |
| Roc range overlaps | M48 (353-412 holds M30-M47), M78-M80 (one query line), M53-M54, M09 (type lines), M85 and M13 (MedicationForm) | Roc counts repeat. Verdict by reading. |
| Roc range holds read-back row types | M27 (EdgeLine), M92 (note_line), M19, M20 | Roc is charged for code that JS keeps in harness. Noted per ID. |
| Roc count is 0 | M22, N49-N52 | Cited lines are fixture. Verdict by reading. |
| JS reuses an earlier function | N42 | JS count is 2 lines because the N41 function is reused. |
| Token metric | All raw SQL IDs | JS tokens are low (1 token per query string). Use chars or lines. |

## 1. Summary per category

| Category | Features | Roc lines | Roc tokens | Roc chars | JS lines | JS tokens | JS chars | Roc shorter | similar | JS shorter | n/a |
|---|---|---|---|---|---|---|---|---|---|---|---|
| row type | 13 | 80 | 1055 | 3089 | 374 | 1972 | 11460 | 7 | 5 | 1 | 0 |
| link | 10 | 20 | 263 | 749 | 219 | 846 | 9439 | 6 | 4 | 0 | 0 |
| edge | 8 | 28 | 514 | 1446 | 59 | 464 | 2569 | 2 | 4 | 2 | 0 |
| schema constraint | 18 | 52 | 623 | 1632 | 49 | 83 | 3245 | 5 | 12 | 1 | 0 |
| other | 4 | 110 | 1379 | 3885 | 18 | 205 | 1044 | 0 | 1 | 3 | 0 |
| query-filter | 19 | 58 | 1111 | 3187 | 73 | 800 | 3577 | 7 | 8 | 4 | 0 |
| projection | 16 | 86 | 1401 | 3628 | 96 | 657 | 3871 | 1 | 5 | 10 | 0 |
| group-aggregate | 7 | 20 | 690 | 1747 | 33 | 289 | 1885 | 2 | 2 | 3 | 0 |
| write | 15 | 63 | 819 | 2578 | 112 | 1369 | 4451 | 4 | 4 | 6 | 1 |
| geometry | 5 | 16 | 291 | 736 | 29 | 420 | 1559 | 1 | 3 | 1 | 0 |
| time series | 9 | 19 | 436 | 1186 | 50 | 620 | 2714 | 4 | 5 | 0 | 0 |
| db function | 5 | 20 | 367 | 1067 | 27 | 243 | 1232 | 0 | 4 | 1 | 0 |
| view | 2 | 5 | 89 | 270 | 11 | 74 | 487 | 1 | 1 | 0 | 0 |
| read row | 4 | 10 | 361 | 958 | 21 | 144 | 799 | 0 | 0 | 3 | 1 |
| live query | 11 | 40 | 837 | 2548 | 89 | 745 | 4881 | 8 | 1 | 2 | 0 |
| all (IDs overlap, sums repeat shared code) | 146 | 627 | 10236 | 28706 | 1260 | 8931 | 53213 | 48 | 59 | 37 | 2 |

Sums repeat shared code, so they are larger than the unique counts in sections 3 and 6. Read the verdict counts, not the sums.

JS status (NOTES.md) against verdict:

| JS status | Features | Roc shorter | similar | JS shorter | n/a |
|---|---|---|---|---|---|
| partial | 24 | 10 | 9 | 5 | 0 |
| full | 30 | 10 | 12 | 7 | 1 |
| raw SurrealQL string | 91 | 28 | 38 | 25 | 0 |
| not possible | 1 | 0 | 0 | 0 | 1 |

## 2. Per feature

Columns: Roc l/t = lines/tokens, JS l/t = lines/tokens (adjusted copy), chars used for the verdict, JS status from NOTES.md.

| ID | Category | Roc l/t | JS l/t | Chars Roc/JS | JS status | Verdict | Note |
|---|---|---|---|---|---|---|---|
| M01 | row type | 8/95 | 22/99 | 245/329 | partial | similar* | Roc: `:=` rows need `.{ encoder_for : _ parser_for : _ }` (main.roc:32-34, 49-51); aliases need none. JS: bare type, reply is a cast. Roc parses the reply; JS trusts it. [JS block shared] |
| M02 | row type | 22/155 | 73/431 | 469/1697 | partial | Roc shorter | Roc field type is also the DB field type. JS writes every field in a TS type and again in DEFINE FIELD (main.ts:87-340). JS block is shared with 20 IDs. [JS block shared] |
| M03 | row type | 16/135 | 16/131 | 541/772 | full | similar* | Roc: annotation line + definition line per table (main.roc:95-118). JS: one `new Table<"owner", Owner>("owner")` line (main.ts:129). Both 2 handles for 2 tables (vets, forms). [JS block shared] |
| M04 | row type | 3/68 | 41/194 | 161/1191 | partial | Roc shorter | `zip ?: Str` once. JS: `zip?:` in TS and `option<string>` in DEFINE FIELD. [JS block shared] |
| M05 | row type | 2/81 | 19/85 | 193/470 | partial | similar* | Roc: `?? []` in the type, but needs a nominal row with encoder/parser ceremony. JS: DEFAULT in schema text only; TS row must still supply the field. [JS block shared] |
| M06 | row type | 3/61 | 26/88 | 165/897 | partial | Roc shorter | Nested alias type. JS adds dotted DEFINE FIELD lines by hand (main.ts:155-160). [JS block shared] |
| M07 | row type | 1/48 | 15/51 | 115/598 | partial | similar* | `List(Str)` vs `string[]` plus `array<string>`. Marginal cost is small on both sides. [JS block shared] |
| M08 | row type | 4/48 | 40/229 | 140/1382 | partial | Roc shorter | `List(Vaccine)`. JS: `array<object>`, `[*]` field paths and an object-key ASSERT by hand (main.ts:213-217, 229-233). [JS block shared] |
| M09 | row type | 6/133 | 23/61 | 339/1173 | partial | Roc shorter | `U8`/`I32` is one token. JS: `number` plus a hand-written range ASSERT per field (5 fields). TS has no integer widths. [JS block shared] |
| M10 | row type | 4/59 | 12/76 | 190/323 | partial | similar* | Both use a type parameter (`VetRow(years)` / `VetRow<Years>`). In JS both instantiations are `number`, so the "checked" row is not checked. [JS block shared] |
| M11 | row type | 5/64 | 37/212 | 197/979 | full | Roc shorter | `Dec`, `Surreal.Datetime`: one declaration. JS: class in TS plus `TYPE decimal` in DEFINE FIELD, and `new Decimal("80")` for every literal. [JS block shared] |
| M12 | row type | 3/73 | 40/248 | 188/1374 | partial | Roc shorter | `[General, Surgery({ board : Str }), Dental]` once. JS: TS union with `{kind:}` convention plus a literal-union type string. [JS block shared] |
| M13 | row type | 3/35 | 10/67 | 146/275 | full | JS shorter* | JS: `Pick<Medication, ...>` (main.ts:75). Roc has no Pick/Omit: the form row lists fields again (main.roc:53-55) plus a second table handle (108-109). [JS block shared] |
| M14 | link | 3/24 | 22/131 | 75/860 | raw SurrealQL string | Roc shorter | `Link(Owner)` gives type and "target exists" ASSERT. JS: `record<owner>` plus `ASSERT record::exists($value)` per link, and TS `RecordId<"owner">` is unchecked. [JS block shared] |
| M15 | link | 2/20 | 40/131 | 56/1694 | raw SurrealQL string | Roc shorter | Link in optional record: Roc derives ASSERT, INDEX and delete event. JS: ASSERT, INDEX and DEFINE EVENT with THROW by hand (main.ts:200-204, 255-257, 275-278). [JS block shared] |
| M16 | link | 4/48 | 49/146 | 140/2316 | raw SurrealQL string | Roc shorter | Link in list of records: same, derived. JS: ASSERT, INDEX and 2 events by hand (about 20 lines). [JS block shared] |
| M17 | link | 1/32 | 35/108 | 81/1487 | raw SurrealQL string | Roc shorter | Link in union arm: derived. JS: ASSERT nested in union ASSERT plus an event by hand. [JS block shared] |
| M18 | link | 2/55 | 11/49 | 139/290 | raw SurrealQL string | similar* | `.on_delete(owners, Unset)` (main.roc:362) vs `REFERENCE ON DELETE UNSET` inside the field line. Same size. [JS block shared] |
| M19 | link | 3/36 | 20/136 | 102/594 | raw SurrealQL string | similar* | `.default(..)` + `.on_delete_at(|p| p.allergies, Unset)` vs one DEFAULT/REFERENCE/ASSERT string. Roc is checked, JS is not. [JS block shared] |
| M20 | link | 2/14 | 3/15 | 54/259 | raw SurrealQL string | similar* | `.on_delete(owners, Cascade)` vs `REFERENCE ON DELETE CASCADE` on the field line. [JS block shared] |
| M21 | link | 2/14 | 20/8 | 53/1123 | raw SurrealQL string | Roc shorter | `.on_delete(vets, Reject)` also gives events for nested links. JS: REJECT on top-level fields plus 4 hand-written DEFINE EVENT blocks (main.ts:275-293). [JS block shared] |
| M22 | link | 0/0 | 9/47 | 0/160 | partial | similar* | Roc count is 0: the cited lines are fixture. `table.link("id")` ~ `new RecordId(table, "id")`. Roc extra: `get()` reads the row in the program; JS RecordId holds no row. [JS block shared] |
| M23 | edge | 3/53 | 15/44 | 166/488 | raw SurrealQL string | similar* | Roc: `Surreal.relation("treats", vets, patients)` and typed `from`/`to` links. JS: `TYPE RELATION IN vet OUT patient` plus `in`/`out` RecordIds. Direction is type-checked only in Roc. [JS block shared] |
| M24 | edge | 1/6 | 10/83 | 26/292 | full | similar* | `treats.insert(rows)` knows it is an edge table; JS needs the `.relation()` call. JS count includes the transaction wrapper (shared with M83). [JS block shared] |
| M25 | edge | 1/15 | 1/2 | 46/80 | raw SurrealQL string | Roc shorter | `.check("since a real year", |e| e.since_year >= 1990)` vs DEFINE FIELD with ASSERT. Roc needs a check name string. |
| M26 | edge | 1/20 | 1/2 | 33/74 | raw SurrealQL string | Roc shorter | `.unique(|e| { from: e.from, to: e.to })` vs `DEFINE INDEX ... FIELDS in, out UNIQUE`. Roc names fields as lambda paths. |
| M27 | edge | 4/63 | 1/30 | 154/97 | partial | similar* | Write is 1 line on both sides (`treats.create(e)` / `db.relate(...)`). Roc range also holds the read-back row type EdgeLine (main.roc:581-584); JS read-back is stripped as harness. |
| M28 | edge | 4/108 | 3/34 | 288/192 | raw SurrealQL string | JS shorter | Roc: CaseLoad type + `case_load` fn + `.outgoing(treats)` (main.roc:488-492, 837). JS: `array::len(->treats[WHERE primary])` inline. Roc is typed and direction-checked. |
| M29 | edge | 4/119 | 3/36 | 294/180 | raw SurrealQL string | JS shorter | Same pattern: TeamLine type + fn + `.incoming(treats)` vs `<-treats[WHERE primary].in.name`. |
| M30 | schema constraint | 1/10 | 1/2 | 19/72 | raw SurrealQL string | Roc shorter | `.unique(|o| o.email)` vs `DEFINE INDEX OVERWRITE owner_email ON owner FIELDS email UNIQUE`. |
| M31 | schema constraint | 1/24 | 1/2 | 53/94 | raw SurrealQL string | Roc shorter | `.unique(|o| { city: ..., line: ... })` vs index with dotted paths. |
| M32 | schema constraint | 1/12 | 1/2 | 27/76 | raw SurrealQL string | Roc shorter | `.unique(|v| v.contact.email)`: path checked by the compiler. |
| M33 | schema constraint | 1/20 | 1/2 | 39/86 | raw SurrealQL string | Roc shorter | Composite with a link: record literal lambda vs index string. |
| M34 | schema constraint | 3/32 | 3/2 | 58/170 | raw SurrealQL string | Roc shorter | 3 x `.index(|x| x.field)` vs 3 DEFINE INDEX lines. |
| M35 | schema constraint | 3/37 | 2/2 | 116/128 | raw SurrealQL string | similar | Roc: `valid_email` fn (3 lines) + `.assert`. JS: one ASSERT string. JS needs a second TS copy if the program also checks (NOTES). Roc: one function, two uses. |
| M36 | schema constraint | 1/20 | 1/2 | 46/107 | raw SurrealQL string | similar* | `|l| l.starts_with("VET-")` vs `string::starts_with($value, ...)`. Roc runs the lambda in Roc too. [JS block shared] |
| M37 | schema constraint | 1/24 | 3/2 | 55/187 | raw SurrealQL string | similar* | `Surreal.Text.is_email(e)` vs `string::is_email($value)`. Roc has no Roc body for it (database only), so the program cannot call it. [JS block shared] |
| M38 | schema constraint | 1/18 | 1/2 | 32/102 | raw SurrealQL string | similar* | `.assert_each(|o| o.tags, |t| t != "")` vs `$value.all(|$t| $t != '')`. [JS block shared] |
| M39 | schema constraint | 4/58 | 9/4 | 153/649 | raw SurrealQL string | similar* | Roc: lambda + shared open-row fn `Clinic.positive_doses` (Clinic.roc:17-19). JS: ASSERT per `[*]` field, no sharing. Roc is longer for one use, shorter for two. [JS block shared] |
| M40 | schema constraint | 6/44 | 3/2 | 144/216 | raw SurrealQL string | similar* | Roc: `possible_species` match fn, 5 lines (main.roc:181-186) + 1 line. JS: IF chain in the field ASSERT, 1-2 lines. Roc is exhaustive-checked and reusable. [JS block shared] |
| M41 | schema constraint | 6/51 | 4/2 | 142/285 | raw SurrealQL string | similar* | Roc: `sane_outcome` fn, 5 lines (main.roc:175-179). JS: 2 IF terms inside the union ASSERT. [JS block shared] |
| M42 | schema constraint | 6/73 | 4/8 | 179/268 | raw SurrealQL string | similar* | `.check("name", |o| ...)` x 5 vs 5 ASSERT clauses. Roc requires a name string per check. [JS block shared] |
| M43 | schema constraint | 3/48 | 3/2 | 147/174 | raw SurrealQL string | similar | Roc: shared open-row fn (Clinic.roc:21-24); the library picks EVENT because 2 fields are read. JS: DEFINE EVENT + THROW + negated condition by hand. |
| M44 | schema constraint | 1/10 | 1/2 | 23/107 | raw SurrealQL string | similar* | `.readonly(|v| v.license)` vs `READONLY` keyword on the field line. [JS block shared] |
| M45 | schema constraint | 7/56 | 1/2 | 179/98 | raw SurrealQL string | JS shorter | Roc: `label_of` (3 lines) + `.computed(...)` (main.roc:133-135, 375-379) vs one VALUE clause. Roc side runs in the program too; JS needs a TS copy for that. |
| M46 | schema constraint | 1/13 | 3/4 | 27/244 | raw SurrealQL string | similar* | `.default(|p| p.allergies, [])` vs `DEFAULT []` in the field line. [JS block shared] |
| M47 | schema constraint | 5/73 | 7/39 | 193/182 | raw SurrealQL string | similar | Roc: Note row, handle, `default_by(|n| n.id, |_| Surreal.Rand.ulid())`. JS: Note type, handle, `DEFAULT rand::ulid()`. [JS block shared] |
| M48 | other | 60/564 | 2/23 | 1611/87 | raw SurrealQL string | JS shorter | Roc ceremony: `x_def : Surreal.Defined` + `x.define()...done()` per table, 3 lines each (main.roc:352-409) and `Surreal.schema([...])` (754-758). JS: array of strings and a loop. Roc range 353-412 overlaps M30-M47. |
| M49 | query-filter | 4/69 | 9/40 | 187/212 | raw SurrealQL string | JS shorter* | Roc: param type + predicate fn + `.filter_by(..).prepare({ city: "Oslo" })` (main.roc:416-419). JS: `${"Oslo"}` bound in the template. JS block is shared with M50-M51. [JS block shared] |
| M50 | projection | 4/86 | 9/40 | 225/212 | raw SurrealQL string | JS shorter* | Roc: result type + projection fn (main.roc:421-425). JS: `AS` aliases inline, result type is a cast. [JS block shared] |
| M51 | projection | 3/74 | 9/40 | 170/212 | raw SurrealQL string | similar | `o.?phone ?? "none"` vs `phone ?? 'none'`. [JS block shared] |
| M52 | query-filter | 3/41 | 3/75 | 116/192 | partial | Roc shorter | Roc filter runs in the DB with `tags.contains("vip")` and reuses `owner_card`. JS builder cannot alias or default, so the default runs in TS (main.ts:~455-460). |
| M53 | query-filter | 1/32 | 4/34 | 88/158 | raw SurrealQL string | similar* | `.filter(|o| o.?referred_by.is_ok())` vs `WHERE referred_by != NONE`. Roc range is the whole query line. [JS block shared] |
| M54 | projection | 10/90 | 4/34 | 234/158 | raw SurrealQL string | JS shorter | Roc: 5-line `match o.?referred_by { Ok(r) => r.get().name  Err(_) => "nobody" }` (main.roc:427-437). JS: `referred_by.name`. No optional chaining through a link. [JS block shared] |
| M55 | projection | 4/76 | 12/72 | 201/497 | raw SurrealQL string | similar* | `p.owner.get().name` vs `owner.name`. Both one expression. JS block shared with M56-M57. [JS block shared] |
| M56 | projection | 9/94 | 8/34 | 257/269 | raw SurrealQL string | similar | Roc: `species_label` match, 7 lines (main.roc:137-143), exhaustive. JS: IF chain with `string::lowercase(species)` for unit arms (main.ts:444-446). Chars equal, JS is a hack. [JS block shared] |
| M57 | projection | 4/109 | 13/80 | 281/524 | partial | JS shorter* | Roc: `Clinic.by_id` with open-row annotation `Selected(p, { id : Str, ..r })` (Clinic.roc:52-54). JS: `raw("ORDER BY id")` (main.ts:404), unchecked. [JS block shared] |
| M58 | query-filter | 3/33 | 2/21 | 97/77 | full | JS shorter | Roc: `vets.at(ruth_id).select(specialty_line)` + result type. JS: `db.select(ruth).fields("id","specialty","years")`, field names are unchecked strings. |
| M59 | query-filter | 1/37 | 2/31 | 91/99 | full | similar | `filter_by(|p, v| v.id == p.key)` vs `where(eq("id", ruth))`. |
| M60 | query-filter | 6/62 | 2/45 | 170/153 | full | similar | Roc: `wide_wings` match fn, 5 lines (main.roc:158-162). JS: `and(eq("species.kind","Bird"), gte("species.wingspan_cm", 20))`, strings unchecked. [JS block shared] |
| M61 | projection | 3/99 | 4/67 | 249/245 | partial | similar | Roc `select_value(..).order_by(..)`. JS `.value("name")` has a wrong result type and needs `as unknown as string[]` (main.ts:469); ORDER BY needs raw SQL. [JS block shared] |
| M62 | projection | 14/106 | 3/34 | 245/185 | raw SurrealQL string | JS shorter | Roc: 14 lines, two `match p.?chip` blocks (main.roc:448-462). JS: `chip.code ?? 'none'`, `chip.implanted_by.name ?? 'nobody'`, 1 line. Worst case of no optional chaining. |
| M63 | projection | 4/76 | 3/32 | 216/172 | raw SurrealQL string | JS shorter | Roc: VaccineLine type + fn with `p.vaccines.map(|v| v.vet.get().name)`. JS: `vaccines.vet.name`. Marginal (20.4%). [JS block shared] |
| M64 | query-filter | 3/53 | 3/32 | 174/172 | raw SurrealQL string | similar | `p.vaccines.any(|v| v.vet.id() == ruth_id)` vs `vaccines.vet CONTAINS ${ruth}`. [JS block shared] |
| M65 | query-filter | 10/225 | 9/113 | 629/557 | partial | similar | Roc: open-row fragments with long annotations (Clinic.roc:26-34, 48-50). JS: `gte("seen", since)` (main.ts:396) but "seen" is an unchecked string. [JS block shared] |
| M66 | projection | 7/198 | 5/46 | 454/331 | partial | JS shorter | Roc: `dose_cost` + `bill` with open-row annotations, 7 lines (Clinic.roc:9-15). JS: one `raw(...)` string (main.ts:401), unchecked, not callable in TS. [JS block shared] |
| M67 | query-filter | 1/40 | 2/38 | 91/128 | partial | Roc shorter | `v.seen < Time.now()` vs `raw("seen < time::now()")` plus a cast `as unknown as RecordId[]` (main.ts:502). |
| M68 | projection | 10/93 | 7/30 | 337/261 | raw SurrealQL string | JS shorter | Roc: `outcome_text` match (6 lines) + OutcomeLine + fn (main.roc:145-150, 480-483). JS: inline IF chain. [JS block shared] |
| M69 | query-filter | 8/66 | 7/30 | 248/261 | raw SurrealQL string | JS shorter* | Roc: 5-line wildcard match `needs_attention` + wrapper (main.roc:152-156, 485-486) for a `!=` test. JS: `WHERE outcome != 'Treated'`. [JS block shared] |
| M70 | projection | 1/20 | 2/12 | 49/45 | full | similar | `select_value(|v| v)` vs `db.select(vets)`. |
| M71 | projection | 4/69 | 3/30 | 178/137 | raw SurrealQL string | JS shorter | Roc: PatientAge type + fn + `.order_by(..).limit(3)`. JS: `ORDER BY age DESC LIMIT 3` inline. |
| M72 | projection | 1/39 | 8/34 | 91/281 | raw SurrealQL string | Roc shorter | Roc reuses `pet_line` and chains `.start(2).limit(2)` (1 line). JS repeats the whole 8-line SELECT because it has no named select. [JS block shared] |
| M73 | projection | 4/89 | 3/36 | 230/177 | raw SurrealQL string | JS shorter | Roc: ContactLine type + fn. JS: `owner.address.city`, `vaccines.vet.name` inline. |
| M74 | projection | 4/83 | 3/36 | 211/165 | raw SurrealQL string | JS shorter | Roc: LinkedRows type + fn (`p.owner.get()`). JS: `FETCH owner, vets`. Roc result is typed. |
| M75 | query-filter | 3/50 | 3/30 | 186/104 | full | JS shorter | Roc: `Try(Surreal.Prepared(List(Medication)), Surreal.Error)` annotation + `bind_captured(select_where(..))` (main.roc:510-513). JS: `db.select(medications).where(lt("unit_price", limit))`. |
| M76 | query-filter | 3/56 | 3/55 | 192/179 | full | similar | Roc: `bind_captured(select_where(.., |o| places.contains(o.address)))` with long annotation. JS: `inside("address", places)`. |
| M77 | query-filter | 4/55 | 5/77 | 193/264 | full | Roc shorter | Roc: one fn `o.address == place`, compares field by field. JS: 2 queries with `eq("address", ..)`, compares the whole object (NOTES). |
| M78 | group-aggregate | 4/145 | 4/38 | 355/247 | raw SurrealQL string | JS shorter | Roc: Ledger type + `ledger_line` fn with `to_i64_wrap()` + `group_by(..).aggregate(..)` (main.roc:500-503, 849). JS: 3-line `GROUP BY vet`. Roc aggregate is plain Roc and runs in memory. [JS block shared] |
| M79 | group-aggregate | 2/115 | 4/38 | 269/247 | raw SurrealQL string | JS shorter* | Roc: `Surreal.Math.mean(rows.map(|v| v.fee.to_f64()))`. JS: `math::mean(<float>fee)`. [JS block shared] |
| M80 | group-aggregate | 1/50 | 4/38 | 122/247 | raw SurrealQL string | similar* | `.order_by(|r| r.revenue, Desc).limit(2)` vs `ORDER BY revenue DESC LIMIT 2`. Roc range is the whole query line, shared with M78-M79. [JS block shared] |
| M81 | group-aggregate | 4/102 | 3/34 | 278/197 | raw SurrealQL string | JS shorter | Roc: VisitTotals type + fn + `.totals(visit_totals)`. JS: `... GROUP ALL`. |
| M82 | group-aggregate | 1/44 | 3/26 | 102/133 | raw SurrealQL string | Roc shorter | `.filter(..).totals(|rows| { visits: rows.len().to_i64_wrap() })` 1 line vs 3-line SELECT with bound decimal. |
| M83 | write | 6/36 | 10/83 | 166/292 | full | similar* | 6 `table.insert(rows)` calls vs 6 `tx.insert` calls. JS adds an explicit transaction (begin, commit); Roc has no transaction API in this file. [JS block shared] |
| M84 | write | 1/6 | 1/19 | 20/70 | full | Roc shorter | `patients.create(pip)`: id is inside the row. JS: `db.create(new RecordId(patients, "pip")).content(pip)`: id repeated outside the row. |
| M85 | write | 2/25 | 1/19 | 95/93 | full | similar | `medication_forms.create(form)` vs `db.create(rid).content(form)`. Roc range holds the MedicationForm type (see M13). [JS block shared] |
| M86 | write | 6/94 | 1/9 | 256/110 | raw SurrealQL string | JS shorter | Roc: RestockParam type + `refill` fn + `Clinic.low_stock` + `update_by(..).prepare(..)`, 6 lines (main.roc:544-547, Clinic.roc:40-42). JS: one `UPDATE ... SET stock = stock + ${add} WHERE ...` line (main.ts:748). [JS block shared] |
| M87 | write | 3/54 | 1/9 | 138/102 | raw SurrealQL string | JS shorter | Roc: `certified` fn + `update_at`. JS: `UPDATE ${tia} SET specialty = ..., years += 1` (raw string; SDK merge cannot use the old value). |
| M88 | write | 3/39 | 1/20 | 107/68 | full | JS shorter | Roc: `renamed = |o| { ..o, name: ".." }` + `update_at` (main.roc:558-561). JS: `merge({ name })` 1 line (main.ts:766). Roc: the compiler checks the field. |
| M89 | write | 3/67 | 4/41 | 168/126 | partial | JS shorter | Roc: `moved` fn, `Try(Str, [Missing])` for removal. JS: `patch([{ op, path: "/address/zip" }])`, paths unchecked (main.ts:775). |
| M90 | write | 1/17 | 2/22 | 47/81 | full | similar* | `delete_at(table.id("x")).prepare({})` vs `db.delete(rid)`. Roc cites 1 delete, JS 2. [JS block shared] |
| M91 | write | 3/62 | 1/9 | 171/69 | raw SurrealQL string | JS shorter | Roc: `Clinic.too_old` open-row fn + `delete_by(..).prepare({ before })`. JS: `DELETE visit WHERE ${tooOld(cutoff)}` (main.ts:824); SDK delete has no where(). [JS block shared] |
| M92 | write | 11/185 | 6/37 | 492/121 | full | JS shorter | Roc: Note row, handle, define, `new_notes` row type written out without `id` (main.roc:1099-1100), `insert_new`. JS: `Omit<Note, "id">` and `db.insert`. Roc range includes the read-back `note_line`. [JS block shared] |
| M93 | write | 24/234 | 24/398 | 918/1374 | full | Roc shorter | `patients.create(light_patient)`, id in the row. JS: `db.create(new RecordId(patients, "bad")).content(x)`. Both 24 refusals; JS has 1 error class, only the text tells rules apart. |
| M94 | other | 22/511 | 11/129 | 1227/674 | partial | JS shorter | Roc: 22 lines of open-row annotations (Clinic.roc:9-54). JS: 3 one-line `Expr` helpers plus 2 `raw` strings (main.ts:396-404). JS field names are unchecked; Roc names are checked. [JS block shared] |
| N01 | geometry | 1/23 | 6/73 | 66/453 | partial | Roc shorter | `Surreal.Point`/`Polygon` and the validity ASSERT is derived. JS: GeometryPoint in TS plus `geo::is_valid` ASSERT by hand (monitoring.ts:~58-60). [JS block shared] |
| N02 | geometry | 7/91 | 16/237 | 221/712 | full | similar* | Roc `rectangle` 7 lines vs JS `rectangle` 4 lines with nested `GeometryPolygon([GeometryLine([GeometryPoint..` constructors. [JS block shared] |
| N03 | link | 1/20 | 10/75 | 49/656 | raw SurrealQL string | Roc shorter | `site : Surreal.Link(Site)` derives type, REJECT and ASSERT. JS: DEFINE FIELD with `REFERENCE ON DELETE REJECT ASSERT record::exists($value)`. [JS block shared] |
| N04 | time series | 1/29 | 5/102 | 80/401 | partial | Roc shorter | `Surreal.TimeKey(Surreal.Id(Kennel))`. JS: key type string `[record<kennel>, datetime]`, tuple type, `vitalId` helper with a cast `as VitalKey`. [JS block shared] |
| N05 | time series | 3/59 | 11/113 | 172/394 | full | Roc shorter | `Surreal.time_key(kennels.id(k), moment(at))` in 3 lines. JS: `vitalId` + `reading` helpers, `new RecordId("vital", [..])` cast. [JS block shared] |
| N06 | edge | 10/130 | 25/233 | 439/1166 | raw SurrealQL string | similar* | Two edge tables: Roc 10 lines (types, handles, defs). JS ~11 lines (2 types, 2 handles, 2 DEFINE TABLE, 3 DEFINE FIELD). [JS block shared] |
| N07 | other | 25/211 | 2/23 | 818/93 | raw SurrealQL string | JS shorter | Roc ceremony: `site_def : Surreal.Defined` + `sites.define().done()` for tables with no constraint (monitoring.roc:100-110), `definitions` list (306-309), `Surreal.function(|_| fever_fn)`. JS: array of strings + loop. |
| N08 | db function | 5/76 | 6/51 | 270/260 | raw SurrealQL string | similar | Roc: `fever` + `db_fn` (5 lines); the function runs in Roc and in the DB. JS: DEFINE FUNCTION in SurrealQL + `db.run("fn::fever", [..])`; a TS copy is needed to run it locally. |
| N09 | db function | 1/36 | 4/41 | 95/180 | raw SurrealQL string | similar* | `filter(|v| fever_fn.call2(v.temp_c, v.pulse))` vs `WHERE fn::fever(temp_c, pulse)`. Roc range is the whole query line. [JS block shared] |
| N10 | db function | 6/54 | 7/36 | 149/335 | raw SurrealQL string | similar* | `.computed(|v| v.fevered, |v| fever_fn.call2(..))` vs `VALUE fn::fever($this.temp_c, $this.pulse)`. Roc range includes vital_def scaffolding. [JS block shared] |
| N11 | db function | 4/79 | 8/75 | 217/325 | raw SurrealQL string | similar* | Roc: FlagLine type + fn. JS: `fn::fever(temp_c, 0) AS hot` inline. [JS block shared] |
| N12 | db function | 4/122 | 2/40 | 336/132 | raw SurrealQL string | JS shorter | Roc: `day_line` fn with `rows.keep_if(|v| fever_fn.call2(..)).len().to_i64_wrap()` (monitoring.roc:136-139). JS: `count(fn::fever(temp_c, pulse))`, but written twice (view and query). [JS block shared] |
| N13 | time series | 4/106 | 9/150 | 281/530 | raw SurrealQL string | similar* | Roc: VitalLine type + `vital_line` using `v.id.series()`, `v.id.time()`. JS: `record::id(id)[1]` const string (monitoring.ts:182). Roc accessors are typed. [JS block shared] |
| N14 | time series | 4/79 | 5/39 | 217/243 | raw SurrealQL string | similar | FlagLine with `id : TimeKey(..)` vs `record::id(id) AS id`. [JS block shared] |
| N15 | time series | 1/26 | 5/112 | 87/317 | full | Roc shorter | `.between(kennel_a, day_start, day_end)` vs `RecordIdRange` with `BoundIncluded`/`BoundExcluded` and manual row mapping. [JS block shared] |
| N16 | time series | 1/29 | 3/44 | 81/168 | full | Roc shorter | `between(..).select(|r| r)` vs RecordIdRange + `db.select<Vital>(range)`. |
| N17 | time series | 3/66 | 10/49 | 164/504 | raw SurrealQL string | similar* | Roc `day_of` fn once (monitoring.roc:130-134). JS `time::floor(record::id(id)[1], 1d)` as text, written in 2 places (view DDL and DAY_ROWS). [JS block shared] |
| N18 | time series | 1/30 | 1/9 | 71/87 | raw SurrealQL string | similar | `delete_by(|p, v| v.id.time() < p.before).prepare(..)` vs `DELETE vital WHERE record::id(id)[1] < ${dayStart}`. |
| N19 | time series | 1/12 | 1/2 | 33/70 | raw SurrealQL string | similar* | `.changefeed(Surreal.Time.days(7))` vs `CHANGEFEED 1w` in DEFINE TABLE. |
| N20 | group-aggregate | 7/188 | 11/82 | 500/619 | raw SurrealQL string | similar | Roc: DayKey + `day_of` + Daily + `day_line`, 7 lines. JS: DAY_ROWS string (monitoring.ts:184) used in the view and in the query. [JS block shared] |
| N21 | view | 4/45 | 9/51 | 164/392 | raw SurrealQL string | Roc shorter | `daily.define_as(from(vitals).group_by(day_of), day_line)`: view built from the Roc grouping. JS: the same SELECT in DDL (monitoring.ts:98-105) and again in DAY_ROWS. [JS block shared] |
| N22 | view | 1/44 | 2/23 | 106/95 | full | similar | Roc lists the 4 fields again in `select(|d| { kennel: d.kennel, .. })` (monitoring.roc:392). JS `.fields("day", ..)` with unchecked names. |
| N23 | query-filter | 1/36 | 4/41 | 95/180 | raw SurrealQL string | Roc shorter | Filter after projection in one line: `.select(vital_line).filter(|l| ..)`. JS: second copy of the SELECT with a cast row type. |
| N24 | query-filter | 1/36 | 2/26 | 100/141 | raw SurrealQL string | Roc shorter | HAVING as `.aggregate(..).filter(|d| d.fevers < d.readings)`; the library makes the subquery. JS: manual subquery text around DAY_ROWS. |
| N25 | query-filter | 1/46 | 4/41 | 109/225 | raw SurrealQL string | Roc shorter | `.order_by(..).limit(3).filter(..)` keeps the order; JS writes `FROM (SELECT .. ORDER BY .. LIMIT 3) WHERE` by hand. |
| N26 | query-filter | 1/47 | 2/21 | 103/145 | raw SurrealQL string | Roc shorter | Same on a scalar projection, 1 line. |
| N27 | group-aggregate | 1/46 | 4/33 | 121/195 | raw SurrealQL string | Roc shorter | `.select(hot_line).query().filter(..).group_by(..).aggregate(..)` vs one SELECT string. |
| N28 | query-filter | 1/54 | 4/28 | 133/151 | raw SurrealQL string | similar | Roc `.query().filter_by(|p, d| d.readings >= p.least)`. JS needs `raw(DAY_ROWS)`: a plain string is bound as a string and returns no rows without an error. |
| N29 | geometry | 4/56 | 3/48 | 136/123 | partial | similar | Roc: `s.location.lat()` in the DB. JS: reads `location.coordinates[1]` in TS (NOTES: partial). |
| N30 | geometry | 3/71 | 2/40 | 189/130 | full | JS shorter | Roc: `Surreal.Geo.inside(p.here.to_geometry(), s.area.to_geometry())` with explicit conversions (monitoring.roc:270-272, 404-408). JS: `where(contains("area", here))`. Roc has no Roc body for Geo.inside. |
| N31 | geometry | 1/50 | 2/22 | 124/141 | raw SurrealQL string | similar | `Surreal.Geo.distance(s.location, p.here) < 50000` vs `geo::distance(location, ${here}) < 50000`. |
| N32 | read row | 4/127 | 7/48 | 347/260 | raw SurrealQL string | JS shorter | Roc: second row type `KennelRead` + `CareRead` + handle `kennel_reads` + `define_read()` (monitoring.roc:74-86, 112-116). JS: `site.name AS site` inline. Roc counts cover the types only. [JS block shared] |
| N33 | read row | 3/140 | 7/48 | 351/260 | raw SurrealQL string | JS shorter | Roc: `k.cares_for.list().map(|e| e.from)` via the `In` field, needs the read row. JS: `<-cares_for.in.{ id: record::id(id), name }` inline. [JS block shared] |
| N34 | read row | 1/82 | 7/48 | 187/260 | raw SurrealQL string | JS shorter* | Roc: `k.cares_for.list().keep_if(|e| e.lead).len().to_i64_wrap()`. JS: `array::len(<-cares_for[WHERE lead])`. [JS block shared] |
| N35 | read row | 2/12 | 0/0 | 73/19 | not possible | n/a* | `kennel_reads.define_read()` checks the read row against the stored row at schema time. JS: not possible (NOTES). Roc only. |
| N36 | other | 3/93 | 3/30 | 229/190 | raw SurrealQL string | similar | Roc: `readings_of` fn (also runs in Roc) + `vitals.rows()`. JS: subquery with `$parent.id` as text, second copy needed for TS. |
| N37 | query-filter | 3/73 | 3/22 | 185/179 | raw SurrealQL string | similar | Roc: `has_fever` fn + `.filter(|k| has_fever(vitals.rows(), k))`. JS: `array::len(SELECT .. $parent.id AND fevered) > 0`. |
| N38 | live query | 3/56 | 11/88 | 170/542 | raw SurrealQL string | Roc shorter | Roc: 3-line watch, snapshot and leave/enter handled. JS: hand-written LIVE SELECT with `$before` branch, a `{ row, now }` VALUE and a separate snapshot query (monitoring.ts:378-384). [JS block shared] |
| N39 | live query | 3/65 | 12/104 | 200/583 | raw SurrealQL string | Roc shorter | Roc: `hotter_than(limit)` 3 lines. JS: same text pattern plus bindings object (monitoring.ts:386-392). [JS block shared] |
| N40 | live query | 3/64 | 4/114 | 186/294 | full | Roc shorter | Roc: `Surreal.from(daily).select(..).live({}, definitions)`. JS: `db.live<Daily>(daily).fields(..)` is also short, plus a separate snapshot select. |
| N41 | live query | 8/129 | 12/59 | 410/592 | raw SurrealQL string | Roc shorter | Roc: `.incoming(cares_for).filter(no_carer).select(..).live(..)` and the second LIVE on the edge is generated. JS: 2 LIVE SELECT by hand + snapshot, filter repeated for `$before` (monitoring.ts:463-475). |
| N42 | live query | 3/85 | 2/9 | 250/45 | raw SurrealQL string | similar* | Roc: 3-line watch through the read row. JS: reuses the N41 function, so only 2 lines are counted; the traversal text is the same. |
| N43 | live query | 3/59 | 7/61 | 189/550 | raw SurrealQL string | Roc shorter | Roc: `.filter(|k| has_fever(vitals.rows(), k))` 3 lines. JS: 2 LIVE SELECT, one on `vital` returning all kennels, and a HAS_FEVER builder (monitoring.ts:515-525). |
| N44 | live query | 8/173 | 12/83 | 511/725 | raw SurrealQL string | Roc shorter | Roc: `.incoming(cares_for).and_incoming(checks)`. JS: 3 LIVE SELECT by hand (monitoring.ts:~540-560). |
| N45 | live query | 3/64 | 8/63 | 192/480 | raw SurrealQL string | Roc shorter | Roc: watch over a `Linked` read row; the LIVE on `site` is generated. JS: second LIVE SELECT on `site` with SITE_CHANGED text. [JS block shared] |
| N46 | live query | 2/60 | 17/122 | 167/911 | raw SurrealQL string | Roc shorter | Roc: `k.site.get().name == "Oslo"` in the filter; enter/leave on a site rename is generated. JS: 2 LIVE SELECT with `$before.site.name` branches. [JS block shared] |
| N47 | live query | 2/53 | 2/23 | 168/95 | partial | JS shorter | Roc: annotation `Try(Surreal.RawWatch(VitalLine), Surreal.Error)` + def. JS: `db.live<Vital>(vitals).where(raw(..))` 1 line. Both are escape hatches. Roc range 904-915 is wrapper only. |
| N48 | live query | 2/29 | 2/19 | 105/64 | full | JS shorter | Roc: `Try(Surreal.DiffWatch(Vital), Surreal.Error)` + `live_diff({})`. JS: `db.live<Vital>(vitals).diff()`. |
| N49 | write | 0/0 | 13/160 | 0/371 | full | Roc shorter* | Roc count 0: scenario data is fixture. `table.edit(Create/Replace/Delete)` is built in. JS needs `create`/`replace`/`remove` helpers that split `id` from the row (monitoring.ts:395-403). Roc `Replace(old, new)` needs the old row. [JS block shared] |
| N50 | write | 0/0 | 13/160 | 0/371 | full | Roc shorter* | Roc count 0 (fixture). `cares_for.edit(Create(e))` same API as nodes. JS needs a separate `relate` helper that splits `in`/`out` (monitoring.ts:405-408). [JS block shared] |
| N51 | write | 0/0 | 13/160 | 0/371 | full | similar* | Both: delete of the node removes the edges in the server. `kennels.edit(Delete(k))` vs `remove(id)`. Roc count 0 (fixture). [JS block shared] |
| N52 | write | 0/0 | 21/223 | 0/832 | full | n/a | Roc count 0: the writes are scenario data (monitoring.roc:780-800). JS count is shared helpers. Roc `Replace(oslo, centre)` needs both rows; JS `replace(centre)` needs one. [JS block shared] |

## 3. Unique code per area (no double counting)

Section 1 sums repeat shared code. This table counts each Roc source line once and each JS code line once (set of lines). Chars are non-space characters.

| Area | Roc lines | Roc chars | JS lines | JS chars | Reading |
|---|---|---|---|---|---|
| main: schema M01-M48 | 154 | 4848 | 184 | 8803 | Roc stronger: chars 55 percent of JS |
| main: queries M49-M82 | 133 | 5904 | 67 | 4018 | Roc weaker: 2.0x lines, 1.5x chars |
| main: writes M83-M93 | 63 | 2578 | 51 | 2362 | similar |
| main: shared helpers M94 | 22 | 1227 | 11 | 661 | Roc weaker: open-row annotations |
| monitoring: schema, db fn (N01-N12, N19, N21) | 61 | 2666 | 68 | 3657 | Roc stronger |
| monitoring: queries (N13-N18, N20, N22-N37) | 46 | 3365 | 45 | 3015 | similar |
| monitoring: live (N38-N48) | 40 | 2548 | 56 | 3909 | Roc stronger |
| monitoring: writes (N49-N52) | 0 | 0 | 18 | 787 | Roc count is 0 because the scenario is fixture |

## 4. Where Roc is weaker (ranked by size and by number of IDs)

Rank 1. Every projection needs a named result type, a named function, `.select(f)` and `.prepare(..)`.

| Item | Detail |
|---|---|
| IDs | M49, M50, M54, M56, M62, M63, M68, M71, M73, M74, M81, N11, N12 (and M28, M29, M78 for edges and groups) |
| Area result | Queries M49-M82: Roc 133 lines, JS 67 lines (section 3) |
| Roc | examples/main.roc:448-462 (`ChipLine` type, `chip_line` with two `match p.?chip` blocks, 14 lines), then `Surreal.from(patients).select(chip_line).prepare({})` at :807 |
| JS | examples/../js/src/main.ts:476-477: SELECT record::id(id) AS id, chip.code ?? 'none' AS chip, chip.implanted_by.name ?? 'nobody' AS by FROM patient |
| Fair note | The Roc reply is typed and the function also runs in memory (Mirror). The JS reply is a cast: `db.query<[{ id: string; chip: string; by: string }[]]>` |

Rank 2. No optional chaining through an optional link or record.

| Item | Detail |
|---|---|
| IDs | M54, M62, M53 |
| Roc | main.roc:427-437: match o.?referred_by { Ok(r) => r.get().name  Err(_) => "nobody" } (5 lines for one path) |
| JS | main.ts:434: `referred_by.name AS \`by\`` (the filter `WHERE referred_by != NONE` removes the empty case) |
| Fair note | `??` works only for a field with a default value (`o.?phone ?? "none"`, main.roc:423-425). A path through a link needs `match` |

Rank 3. Updates and deletes need a parameter type, a patch function and an open-row predicate.

| Item | Detail |
|---|---|
| IDs | M86, M87, M88, M89, M91 (M90 similar) |
| Roc | main.roc:544-547 `RestockParam`, `refill = \|p, m\| { ..m, stock: m.stock + p.add }`; Clinic.roc:40-42 `low_stock`; main.roc:1003 `medications.update_by(Clinic.low_stock, refill).prepare(refill_param)` |
| JS | main.ts:748: UPDATE medication SET stock = stock + ${refill.add} WHERE ${lowStock(refill.floor)} |
| Also | M88: `renamed = \|o\| { ..o, name: ".." }` (main.roc:558-561) against `db.update(id).merge({ name })` (main.ts:766). M89: `moved` with `Try(Str, [Missing])` (main.roc:563-566) against `patch([{ op: "remove", path: "/phone" }])` (main.ts:775) |
| Fair note | JS strings and patch paths are not checked. The SDK merge cannot read the old value, so M86 and M87 are raw SurrealQL in JS |

Rank 4. Tag unions are handled by named `match` functions.

| Item | Detail |
|---|---|
| IDs | M40, M41, M56, M60, M68, M69 |
| Roc | main.roc:137-143 `species_label` (7 lines), :145-150 `outcome_text` (6), :152-156 `needs_attention` (5, only to say `!= Treated`), :181-186 `possible_species` |
| JS | main.ts:444-446: IF species.kind = 'Bird' THEN 'bird' ELSE IF species.kind = 'Exotic' THEN species.latin ELSE string::lowercase(species) END |
| Fair note | The Roc `match` is checked for all arms and is reused by the constraint, the projection and the program. The JS IF chain is a text hack (lowercase of the unit arms) and is not checked |

Rank 5. Open-row helpers carry long annotations.

| Item | Detail |
|---|---|
| IDs | M94, M57, M65, M66, M39, M43 |
| Area result | M94: Roc 22 lines and 1227 chars, JS 11 lines and 661 chars |
| Roc | examples/clinic/Clinic.roc:13 `bill : { fee : Dec, items : List({ doses : I64, medication : Surreal.Link({ unit_price : Dec, ..m }), ..d }), ..r } -> Dec`; :52-54 `by_id : Surreal.Selected(p, { id : Str, ..r }) -> ...` |
| JS | main.ts:401 `const bill = raw("fee + math::sum(items.map(\|$d\| <decimal>$d.doses * $d.medication.unit_price))")`; :404 `const byId = raw("ORDER BY id")` |
| Fair note | JS helpers are unchecked strings and `bill` cannot run in TS. Roc helpers are type-checked and run in memory |

Rank 6. Schema ceremony.

| Item | Detail |
|---|---|
| IDs | M48, N07, M03 |
| Roc | main.roc:352-409: each table has `x_def : Surreal.Defined`, `x_def = x.define()...done()` (3 lines of frame). monitoring.roc:100-110: five tables with no constraint still need `site_def = sites.define().done()`. monitoring.roc:306-309: a `definitions` list of 9 values. Each table also needs a type line and a value line (main.roc:95-118) |
| JS | main.ts:143-150: one `DEFINE TABLE` statement for 7 tables; :129-135 one `new Table<"owner", Owner>("owner")` line per table |
| Fair note | M48 and N07 counts overlap constraint IDs in Roc, so I judged by reading |

Rank 7. No Pick or Omit: a second row type is written out.

| Item | Detail |
|---|---|
| IDs | M13, M85, M92, N05 |
| Roc | main.roc:53-55 `MedicationForm` lists 4 fields again, :108-109 a second table handle; :1099-1100 `new_notes : List({ vet : Surreal.Link(Vet), text : Str })`; seeds of computed fields need a placeholder (monitoring.roc:196 `fevered: Bool.False`) |
| JS | main.ts:75 `Pick<Medication, "name" \| "form" \| "unit_price">`; :832 `Omit<Note, "id">[]`; seeds use `Omit<Vital, "fevered">` |

Rank 8. A read row is a second row type plus a second table handle plus a schema check.

| Item | Detail |
|---|---|
| IDs | N32, N33, N34 |
| Roc | monitoring.roc:77-83 `CareRead`, `KennelRead`; :112-116 `kennel_reads` handle and `define_read()`; query :418 reads `k.cares_for.list().keep_if(\|e\| e.lead).len().to_i64_wrap()` |
| JS | monitoring.ts:325-330: `site.name AS site`, `<-cares_for.in.{ id: record::id(id), name } AS carers`, `array::len(<-cares_for[WHERE lead]) AS leads` |
| Fair note | The Roc read row is checked against the stored row at schema time (N35). JS cannot check this |

Rank 9. Integer conversion after each count.

| Item | Detail |
|---|---|
| IDs | M28, M29, M78, M81, M82, N12, N20, N34, N41, N44 |
| Roc | `.len().to_i64_wrap()` occurs 14 times: main.roc:492, 498, 503, 1122, 1140; monitoring.roc:139, 237, 256, 418, 424, 461, 471, 485 |
| JS | `array::len(..)` and `count()` need no conversion; the TS type says `number` |

Rank 10. Annotations for captured queries and watches.

| Item | Detail |
|---|---|
| IDs | M75, M76, M77, N47, N48, and each live ID (N38-N46) |
| Roc | main.roc:510 `cheaper_than : Dec -> Try(Surreal.Prepared(List(Medication)), Surreal.Error)`; monitoring.roc:507-512 `Try(Surreal.RawWatch(VitalLine), Surreal.Error)`, `Try(Surreal.DiffWatch(Vital), Surreal.Error)`; each `.live({}, definitions)` takes the `definitions` list |
| JS | main.ts:598 `db.select(medications).where(lt("unit_price", limit))`; monitoring.ts:635 `db.live<Vital>(vitals).diff()` |

Rank 11. Functions that exist in the database only, and conversions.

| Item | Detail |
|---|---|
| IDs | N30, N31, M37, N19 |
| Roc | monitoring.roc:270-272 `Surreal.Geo.inside(p.here.to_geometry(), s.area.to_geometry())`. `Geo.inside`, `Geo.distance` and `Text.is_email` have no Roc body (catalog section 4, item 12), so the reference result is typed by hand in the harness. The changefeed check is raw SurrealQL (monitoring.roc:396) |
| JS | monitoring.ts:310 `where(contains("area", here))` (needs a cast `as unknown as RecordId[]`) |

Rank 12. Edit values need the old row.

| Item | Detail |
|---|---|
| IDs | N49, N50, N52 |
| Roc | monitoring.roc:524-531: `Replace(hot, cooled)`, `Replace(cool, heated)`: the old and the new row |
| JS | monitoring.ts:395-403 `replace(cooled)`: only the new row, but 4 helper functions are needed to split `id`, `in`, `out` from a row |

Rank 13 (scope, not a feature). The Roc examples print a SurrealQL script (`main!` only echoes it, main.roc:1110-1113). They have no connection, auth or transaction code. JS has 51 setup lines and a managed connection. The Roc examples have no feature written as raw SurrealQL. The SDK can send any statement (NOTES, "No gap in SurrealQL").

## 5. Where Roc is stronger

| Rank | Area and IDs | Roc | JS |
|---|---|---|---|
| 1 | Schema from types: M02, M04-M12, N01, N03, N04 (section 3: schema chars 4848 against 8803) | `Owner := { .., tags : List(Str) ?? [], referred_by ?: Surreal.Link(Owner) }` (main.roc:31) gives type, DEFAULT, optional and link | The same row is a TS type (main.ts:40-48) and DEFINE FIELD strings (main.ts:154-170). Nothing keeps them equal (NOTES) |
| 2 | Links: M14-M17, M21 | `owner : Surreal.Link(Owner)` (main.roc:71). ASSERT, INDEX and the delete event for nested links are derived | ASSERT per link (main.ts:207, 217), 3 INDEX lines (main.ts:264-266), 4 DEFINE EVENT with THROW (main.ts:275-293) |
| 3 | One function for constraint and program: M35, M43, M45, N08, N36, N37 | `valid_email` (main.roc:129-131) is used by `.assert(|o| o.email, valid_email)` (:358) and by `expect` | ASSERT text in the schema and a second TS function if the program needs the rule (NOTES, "Rules that a TS developer writes twice") |
| 4 | Live queries: N38-N46 (live area: 40 lines against 56) | `fevered = Surreal.from(vitals).filter(..).select(vital_line).live({}, definitions)` (monitoring.roc:441-443). Enter and leave, the snapshot and the edge LIVE are generated | LIVE SELECT text with a `$before` branch, a `{ row, now }` VALUE, a second query for the snapshot, a second LIVE SELECT for edges and links (monitoring.ts:378-392, 463-475, 515-525, 541-560) |
| 5 | Time series keys: N04, N05, N13, N15, N16 | `.between(kennel_a, day_start, day_end)` (monitoring.roc:343), `v.id.series()`, `v.id.time()` | `new RecordIdRange("vital", new BoundIncluded([kennelA, dayStart]), new BoundExcluded([kennelA, dayEnd]))` (monitoring.ts:206), `record::id(id)[1]` text |
| 6 | Views, HAVING and subqueries: N21, N23-N27 | `daily.define_as(Surreal.from(vitals).group_by(day_of), day_line)` (monitoring.roc:141-146); `.aggregate(..).filter(\|d\| d.fevers < d.readings)` makes the subquery | The SELECT is written twice: view DDL (monitoring.ts:98-105) and DAY_ROWS (:184); the subquery text is wrapped by hand; a plain string bound as a subquery returns no rows (NOTES) |
| 7 | Checked names and types: M30-M34, M58-M60, M65, M67, N22 | Field paths are lambdas: `.unique(\|v\| v.contact.email)`. Result type is the Roc type of the projection | Field names are strings: `eq("species.kind", "Bird")`, `fields("id", "specialty")`. Casts: `as unknown as string[]` (main.ts:469, 502; monitoring.ts:310) |
| 8 | Integer width and the read row check: M09, N35 | `U8` is the range 0-255. `define_read()` checks a read row against the stored row | A range ASSERT per field; `number` only. N35 is not possible (NOTES) |
| 9 | Writes with the id in the row: M84, M93 | `patients.create(light_patient)` | `db.create(new RecordId(patients, "bad")).content(lightPatient)`: id is repeated outside the row |
| 10 | Clause reuse: M72, M82 | `.select(pet_line).order_by(..).start(2).limit(2)` reuses a named select | The whole 8-line SELECT is written again (main.ts:568-575) |
| 11 | Decimal and datetime literals (fixture, not counted) | `rate: 80` | `rate: dec("80")` for every value (main.ts:310-312) |

## 6. Totals

Feature code. Roc is the union of the catalog lines (each line once). JS is the adjusted copy (read-backs, refusal wrappers, `@F` blocks and the changefeed check removed). The raw JS value is in brackets.

| Part | Roc lines | Roc tokens | Roc chars | JS lines | JS tokens | JS chars |
|---|---|---|---|---|---|---|
| Feature code | 479 | 7319 | 23136 | 551 (raw 592) | 4571 (raw 5324) | 25596 (raw 28506) |
| Fixture and scenario data | 272 (+87 mixed with harness) | 3345 | 10799 | 206 | 3637 | 10906 |
| Setup (app header, imports, connection) | 6 | not counted | not counted | 51 | 265 | 1115 |
| Feature + fixture + setup | 757 | | | 808 | | |
| Check and harness | 611 (+87 mixed) | not counted | not counted | 164 in the 2 ports (raw 193), plus 150 in harness.ts | 1505, plus 1802 | 4432, plus 4834 |
| All code lines in the files | 1455 (main 843, monitoring 587, Clinic 25) | | | 1192 (feature, fixture, setup, check in main.ts and monitoring.ts, plus 150 in harness.ts) | | |

Notes on the totals:

| Note | Detail |
|---|---|
| Token undercount | JS has 25596 feature chars in 4571 tokens. Roc has 23136 chars in 7319 tokens. Tokens favor JS because a SQL string is 1 token. By chars, the two sides are within 10 percent. By lines, Roc has 13 percent fewer feature lines |
| NOTES.md convention | NOTES.md counts a block tagged `@F @M13` as feature. It reports 376 + 289 = 665 feature lines and 106 + 27 = 133 fixture lines. I count a block with `@F` as fixture, so my raw JS feature value is 592 and my fixture value is 206 |
| Roc fixture | Pure fixture ranges: main.roc 180 code lines, monitoring.roc 92. The write scenario blocks at monitoring.roc:597-734 hold 87 code lines that mix fixture (`write:`) and harness (`notices:`) |
| Roc harness | The Roc harness holds the Mirror reference results. The JS check holds the comparison with the Roc output. They are not the same work |
| What Roc counts hide | Roc counts exclude the Mirror (it predicts live notices from the same functions). JS has no such predictor: the notices of the JS live tests are compared with the Roc output |
| Roc 0 counts | M22 and N49-N52 are 0 in Roc because the cited lines are fixture. Verdicts are by reading |

## 7. Short answer

| Question | Answer |
|---|---|
| Where is Roc less expressive or more verbose? | Queries: named result types, no optional chaining, match functions for unions, annotations for open rows, updates and deletes with parameters (ranks 1-5). Also schema frame, no Pick or Omit, read rows, `to_i64_wrap` (ranks 6-9) |
| Where is Roc better? | Schema, links, constraints from one source (areas schema and live), single function for DB and program, time series keys, live queries and views, checked names and types (section 5) |
| Verdict counts | 48 Roc shorter, 59 similar, 37 JS shorter, 2 n/a (146 features, section 1) |
