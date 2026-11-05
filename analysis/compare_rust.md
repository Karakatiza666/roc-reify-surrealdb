# Roc ORM against the Rust surreal_orm crate, feature by feature

Sources: catalog.md, roc_slices.json (Roc counts, harness and fixtures removed, reused; spot-checked M28, M62, M78, M86, N41), the port in rust/src (surreal_orm commit 089f21a9, SurrealDB 1.5), rust/NOTES.md. Same method and verdict rule as compare_surql.md and compare_js.md.

## 0. How the numbers were made

| Item | Rule |
| --- | --- |
| Roc side | Reused from roc_slices.json: code lines and tokens of the catalog ranges. Ranges overlap (M48 holds M30-M47, M78-M80 share one query), so Roc sums repeat code. |
| Rust side, lines and tokens | Own slicer (SCRATCH/fair2.py), same TOKEN regex as slice.py. A block under several `@ID` markers is split in equal parts between its IDs ('fair share'), so Rust numbers add up to the true total. `@F`, `@SETUP` and N49-N52 scenario steps are not features. |
| Fix to slice.py | slice.py treats a line that starts with `#` as a comment. Rust attributes `#[derive]`, `#[orm(..)]`, `#[serde(..)]` start with `#`, so slice.py drops them: 143 lines and 1861 tokens of feature code. fair2.py counts them. Raw slice numbers from rust_slices.json are therefore too low for structs. |
| Execute wrapper | Each Rust query sits in `pub async fn x(db: &Db) -> SurrealOrmResult<T> { .. .return_many(db.clone()).await }`. The Roc harness holds the run step, so Roc counts do not have it. For the ratio, wrapper tokens are removed from the Rust side (column Adj). Lines are not adjusted. |
| Ratio | Roc tokens / Rust Adj tokens. Below 0.8 Roc shorter (R), above 1.2 Rust shorter (S), else similar (=). A difference of 8 tokens or less is similar. |
| Star | I changed the automatic verdict after reading the code, or the shared block distorts the count (row types, constraints, group queries). The note says why. |
| n/a | No Roc code to count (M22, N49-N52 are fixture steps), or one side cannot do the feature (M44 readonly, N35 read-row check in Rust). |
| Tokens and raw strings | A raw SurrealQL string is cheap in tokens (one token). Judge Rust raw strings by the note, not by the count. |
| Rust syntax | Derive attributes, `.await?`, `db.clone()`, `SurrealOrmResult<..>`, `Field::new(..)` and type paths make Rust long by nature. The notes judge structure: duplicate logic, raw strings, unchecked names, workarounds, one-sided features. |

## 1. Summary per category

Roc l/t sums repeat shared code. Rust l/t is a true partition (fair share), so the Rust total equals the unique feature code.

| Category | Features | Roc lines | Roc tokens | Rust lines | Rust tokens | Roc shorter | Similar | Rust shorter | n/a |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| row type | 13 | 80 | 1055 | 156 | 1409 | 10 | 3 | 0 | 0 |
| link | 10 | 20 | 263 | 90 | 1063 | 8 | 1 | 0 | 1 |
| edge | 8 | 28 | 514 | 119 | 1269 | 7 | 1 | 0 | 0 |
| schema constraint | 18 | 52 | 623 | 174 | 1977 | 15 | 2 | 0 | 1 |
| other | 4 | 110 | 1379 | 71 | 713 | 2 | 0 | 2 | 0 |
| query-filter | 19 | 58 | 1111 | 141 | 1791 | 10 | 6 | 3 | 0 |
| projection | 16 | 86 | 1401 | 184 | 1809 | 5 | 8 | 3 | 0 |
| group-aggregate | 7 | 20 | 690 | 69 | 628 | 2 | 5 | 0 | 0 |
| write | 15 | 63 | 819 | 125 | 2494 | 5 | 3 | 3 | 4 |
| geometry | 5 | 16 | 291 | 38 | 489 | 3 | 1 | 1 | 0 |
| time series | 9 | 19 | 436 | 61 | 717 | 2 | 7 | 0 | 0 |
| db function | 5 | 20 | 367 | 45 | 415 | 1 | 2 | 2 | 0 |
| view | 2 | 5 | 89 | 17 | 164 | 1 | 0 | 1 | 0 |
| read row | 4 | 10 | 361 | 25 | 222 | 0 | 0 | 3 | 1 |
| live query | 11 | 40 | 837 | 101 | 1356 | 7 | 2 | 2 | 0 |
| Total (shares and overlaps counted) | 146 | 627 | 10236 | 1416 | 16516 | 78 | 41 | 20 | 7 |

surreal_orm status (NOTES.md) against verdict:

| Rust status | Features | Roc shorter | Similar | Rust shorter | n/a |
| --- | --- | --- | --- | --- | --- |
| full | 56 | 24 | 20 | 8 | 4 |
| partial | 75 | 50 | 16 | 8 | 1 |
| raw SurrealQL | 13 | 4 | 5 | 4 | 0 |
| not possible | 2 | 0 | 0 | 0 | 2 |

Reading: Roc is shorter wherever surreal_orm needs hand-written DDL (links, constraints, nested fields, unions, defaults, edges). Rust is shorter where a query needs only a typed path or an operator: field updates, optional link paths, select all, open-row fragments, and read rows. In 75 of the 146 features NOTES.md says the crate gives a partial result, in 13 raw SurrealQL, in 2 nothing.

## 2. Per-feature table

Rust l/t is the fair share. Adj is Rust tokens without the execute wrapper. Verdict: R = Roc shorter, = similar, S = Rust shorter, n/a = not compared. A star after the verdict marks a reading override.

| ID | Cat | Roc l/t | Rust l/t | Adj | Ratio | Rust status | Verdict | Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| M01 | row type | 8/95 | 5/49 | 49 | 1.95 | full | R* | Rust derive Node + serde, the structs carry `#[derive]`, `#[orm]`, `#[serde]` lines (main_example.rs:28-49). Roc type is the schema; `encoder_for : _` is 4 of 8 lines. Shared block: whole structs 33 lines/302 tokens. |
| M02 | row type | 22/155 | 8/85 | 85 | 1.83 | partial | R* | Roc field type gives the DB type. Rust needs `ty = "any"`, `ty = "decimal"` on f64, `nest_object`, a serde helper per decimal and datetime (main_example.rs:67-88, 165-190). Whole structs 63/657. |
| M03 | row type | 16/135 | 12/90 | 90 | 1.49 | full | =* | Roc: handle plus annotation per table (main.roc:95-118). Rust: `Owner::table()` from the derive, but a second struct with `relax_table` for a second row type (main_example.rs:89-104). |
| M04 | row type | 3/68 | 14/129 | 129 | 0.53 | partial | R | `zip ?: Str` against `Option<String>` plus `ty = "option<string &#124; null>"` by hand: the crate writes None as NULL (derive limit). `nest_object` takes no Option, so `chip` loses its typed path. |
| M05 | row type | 2/81 | 9/70 | 70 | 1.15 | partial | R* | Roc `?? []` / `?? 0` in the type. Rust `value = ..` gives `VALUE $value OR x`, which 1.5 refuses for a missing required field: `DEFAULT 0` is a raw string (main_example.rs:467-473). |
| M06 | row type | 3/61 | 20/194 | 194 | 0.31 | partial | R | Roc nested alias is one line. Rust `nest_object` gives typed paths but no nested DEFINE FIELD: one `define_field` per nested path (main_example.rs:401-417). Derive limit. |
| M07 | row type | 1/48 | 2/19 | 19 | 2.48 | full | =* | `List(Str)` and `Vec<String>` are the same idea. Rust adds `ty = "array<string>"` and `#[serde(default)]`. |
| M08 | row type | 4/48 | 12/109 | 109 | 0.44 | partial | R | Roc list of records is one alias. Rust `nest_array` gives `array<object>` only; element fields are hand-written `vaccines.*.x` statements and there is no object-key check (derive limit). |
| M09 | row type | 6/133 | 8/78 | 78 | 1.71 | partial | R* | Roc: U8 or I32 in the type gives the range assert. Rust repeats `assert = cond(value().gte(0)).and(value().lte(255))` per field, 5 places (main_example.rs:75, 175, 465). |
| M10 | row type | 4/59 | 8/54 | 54 | 1.10 | partial | R* | Roc `VetRow(years)` is one generic row, two aliases. Rust copies the 7 fields into `UncheckedVet` with `relax_table` (main_example.rs:89-104). |
| M11 | row type | 5/64 | 32/356 | 356 | 0.18 | partial | R | Roc `Dec` and `Surreal.Datetime` map directly. Rust: `ty = "decimal"` must be `f64`, reads back as a string (helper `dec`), chrono needs a serde module `sql_datetime` (main_example.rs:263-290). |
| M12 | row type | 3/73 | 21/139 | 139 | 0.53 | partial | R | Roc tag union gives a literal union type and kind asserts. Rust: serde-tagged enum stored as `any` with one optional nested field per arm (main_example.rs:58-65, 495-499). SurrealDB 1.x has no literal union type. |
| M13 | row type | 3/35 | 5/37 | 37 | 0.95 | full | = | Both are a second struct on the same table (Roc handle `medication_forms`, Rust `MedicationForm` with `relax_table`). |
| M14 | link | 3/24 | 9/84 | 84 | 0.29 | partial | R | Roc `Link(Owner)` gives type, exists assert, index, delete rule. Rust `link_one` + `assert = link_exists()`; derive gives `record<T>` only (1.x has no record::exists, hand assert `$value.id != NONE`). |
| M15 | link | 2/20 | 13/150 | 150 | 0.13 | partial | R | Roc link inside an optional record gives assert, index and delete event. Rust: raw DEFINE FIELD with assert (main_example.rs:486), raw event, no index. |
| M16 | link | 4/48 | 20/227 | 227 | 0.21 | partial | R | Roc link in a list of records gives the same. Rust: raw `DEFINE FIELD vaccines.*.vet` and `items.*.medication` plus raw events, no index. |
| M17 | link | 1/32 | 14/176 | 176 | 0.18 | partial | R | Roc link in a union arm gives assert and event. Rust: hand OR in the outcome assert (main_example.rs:357-359); it did not refuse `vet:ghost` on 1.5.6. |
| M18 | link | 2/55 | 2/19 | 19 | 2.84 | partial | R* | Roc `?: Link(Owner)` plus `.on_delete(owners, Unset)`. Rust: `link_self` typed `record<owner>` (derive bug, refuses rows with no referral), override in `fields_definitions`, event with PATCH remove (main_example.rs:418-423, 521-527). About 12 lines. |
| M19 | link | 3/36 | 10/129 | 129 | 0.28 | raw SurrealQL | R | Roc `.default(.., [])` and `.on_delete_at(..)`. Rust: default via `value`, Unset is a raw event `allergies -= $before.id` (main_example.rs:545). |
| M20 | link | 2/14 | 8/106 | 106 | 0.13 | partial | R | Roc `Cascade` is a keyword. Rust: `define_event` + `delete().where_` per edge (main_example.rs:525-541). 1.x has no REFERENCE ON DELETE. |
| M21 | link | 2/14 | 8/106 | 106 | 0.13 | raw SurrealQL | R | Roc `Reject` is a keyword. Rust: raw event with IF + THROW (main_example.rs:543-546); `run()` returns Ok when the server THROWs, so the error is lost. |
| M22 | link | 0/0 | 3/39 | 39 | - | full | n/a | Roc cited lines are fixtures. Both sides have a link built in app code: Roc `owners.link("jon")`, Rust `LinkOne::from(id)`. `.value()` vs `get()`. Same. |
| M23 | edge | 3/53 | 8/86 | 86 | 0.62 | partial | R | Roc `Surreal.relation("treats", vets, patients)` checks both ends. Rust generic `Treats<In, Out>` + two aliases; derive default `in`/`out` is `record<any>`, so `ty = "record<vet>"` by hand. |
| M24 | edge | 1/6 | 9/103 | 92 | 0.07 | partial | R | Roc `treats.insert(rows)`. Rust `insert` takes Node rows only, so edges loop one `relate_edge` per row inside the transaction (main_example.rs:1182-1204). |
| M25 | edge | 1/15 | 6/64 | 64 | 0.24 | full | R | Roc `.check(..)` on the edge table. Rust `assert` attribute on the edge field. Same idea, Roc is one line. |
| M26 | edge | 1/20 | 6/80 | 80 | 0.25 | full | R | Roc `.unique(&#124;e&#124; { from: e.from, to: e.to })`. Rust `define_index(..).fields(arr![r#in, out]).unique()` in a `TableResources` impl (main_example.rs:579-584). Rust uses typed schema fields here. |
| M27 | edge | 4/63 | 18/225 | 180 | 0.35 | partial | R | Roc `treats.create(edge)` plus an `EdgeLine` read. Rust typed `relate(Vet::with(a).treats__(E).patient(b)).content(e)` but the read back uses raw `Field::new("in.name")`. |
| M28 | edge | 4/108 | 18/180 | 147 | 0.73 | full | R | Roc `outgoing(treats)` gives a tuple and list code (`keep_if`, `to_i64_wrap`). Rust `count!(Vet::schema().treats__(primary.eq(true)).id)`: typed hop with the edge filter inside the path. Rust is stronger in structure, Roc shorter here. |
| M29 | edge | 4/119 | 18/180 | 147 | 0.81 | full | = | Roc `incoming(treats)` and `e.from.get().name`. Rust `Patient::schema().__treats(primary.eq(true)).vet(E).name`: two typed hops, edge filter in the path. Same size, Rust path is richer. |
| M30 | schema constraint | 1/10 | 5/62 | 62 | 0.16 | full | R | Roc `.unique(&#124;o&#124; o.email)`. Rust `define_index("owner_email_unique").on_table(..).fields(arr![email]).unique().to_raw()` with a hand-chosen index name. |
| M31 | schema constraint | 1/24 | 5/62 | 62 | 0.39 | full | R | Roc `.unique(&#124;o&#124; { city: o.address.city, line: o.address.line })`. Rust composite over `address.city.clone(), address.line`: typed. |
| M32 | schema constraint | 1/12 | 6/74 | 74 | 0.16 | full | R | Same shape as M30 on a nested path. |
| M33 | schema constraint | 1/20 | 3/42 | 42 | 0.47 | full | R | Same shape as M30 over a name and a link. |
| M34 | schema constraint | 3/32 | 12/158 | 158 | 0.20 | full | R | Roc `.index(&#124;o&#124; o.address.city)` x3. Rust `define_index(..)` x3 with explicit names and `to_raw()`. |
| M35 | schema constraint | 3/37 | 8/84 | 84 | 0.44 | partial | R | Roc one function `valid_email`, used by `.assert` and by the program. Rust has two copies: `valid_email` and a Filter; `string::starts_with!` emits a 2.x name, so the Filter holds a raw `string::startsWith` (main_example.rs:297-306). |
| M36 | schema constraint | 1/20 | 2/26 | 26 | 0.77 | raw SurrealQL | = | Roc lambda with `starts_with`. Rust has a raw string `Filter::from("string::startsWith($value, 'VET-')")` inside an attribute (main_example.rs:70): works, unchecked. Name mismatch is a crate bug (2.x name). |
| M37 | schema constraint | 1/24 | 14/163 | 163 | 0.15 | partial | R | Roc `Surreal.Text.is_email(e)`. Rust `string::is::email!` works but a Function is not `Conditional`: wrapped as `Filter::from(..to_raw().build())` (main_example.rs:447). |
| M38 | schema constraint | 1/18 | 7/82 | 82 | 0.22 | partial | R | Roc `.assert_each(&#124;o&#124; o.tags, ..)`. Rust `item_assert` emits `DEFINE FIELD "tags". *` (derive bug): hand-written `tags.*` statement. |
| M39 | schema constraint | 4/58 | 7/96 | 96 | 0.60 | partial | R | Roc `assert_each` on a list of records, lambda or shared open-row function. Rust hand-written `vaccines.*.name` and `items.*.doses` statements with a shared `named_assert()`. |
| M40 | schema constraint | 6/44 | 17/170 | 170 | 0.26 | partial | R | Roc `match` in the assert function, the same function runs in the program. Rust rewrites the match as OR/AND over a hand-made path struct (`SpeciesPath`) plus a second Rust fn (main_example.rs:332-345). |
| M41 | schema constraint | 6/51 | 21/227 | 227 | 0.22 | partial | R | Same as M40 for a wildcard arm and a range. |
| M42 | schema constraint | 6/73 | 20/197 | 197 | 0.37 | full | R | Roc `.check("name", fn)` becomes a field assert. Rust `assert = named_assert` or inline `cond(value().gt(0))`: typed, shares one Filter. Rust inline condition has no Rust-callable twin. |
| M43 | schema constraint | 3/48 | 4/54 | 54 | 0.90 | raw SurrealQL | =* | Roc open-row function `fee_covers_items` (3 lines). Rust: raw event string with IF + THROW (builder `then` takes one query), logic copied into SurrealQL (main_example.rs:571-574). |
| M44 | schema constraint | 1/10 | 8/100 | 100 | 0.10 | not possible | n/a | Roc `.readonly(..)`. Rust: not possible (no builder method, SurrealDB 1.5 has no READONLY). |
| M45 | schema constraint | 7/56 | 18/181 | 181 | 0.31 | partial | R | Roc `.computed(&#124;m&#124; m.label, &#124;m&#124; label_of(m.name, m.form))` shares `label_of`. Rust `define = label_define()` with `string::concat` over `$this`, a Rust twin `label_of`, and the field type must be an option (main_example.rs:316-330). |
| M46 | schema constraint | 1/13 | 5/65 | 65 | 0.20 | partial | R | Roc `.default(&#124;p&#124; p.allergies, [])`. Rust `value = Vec::new()` gives `VALUE $value OR []`, works only when the field is sent. |
| M47 | schema constraint | 5/73 | 12/134 | 110 | 0.66 | partial | R | Roc `default_by(&#124;n&#124; n.id, &#124;_&#124; Rand.ulid())`: the server makes the key. Rust `SurrealUlid` makes the key in Rust (`Note::create_ulid()`), client side. |
| M48 | other | 60/564 | 17/164 | 142 | 3.97 | full | R* | Roc 60-line builder list holds the rules of M30-M47. Rust schema glue: impls per table, `DeletePolicies`, `Resources`, `apply_schema` (main_example.rs:395-606): 174 lines/2189 tokens against 60/564. `create_table_resources!` and the migrator CLI are in Rust only. |
| M49 | query-filter | 4/69 | 4/55 | 42 | 1.64 | full | S | Roc: `CityParam` type + `in_city` + `filter_by` + `prepare({..})`. Rust: function arguments become bound parameters (`$_param_n`), no param type. Roc checks param names and types. |
| M50 | projection | 4/86 | 10/108 | 93 | 0.92 | full | = | Roc projection fn `owner_card` renames and `record::id`. Rust `key(id)` helper (`meta::id!` AS id) and a serde struct. |
| M51 | projection | 3/74 | 7/74 | 60 | 1.22 | partial | =* | Roc `o.?phone ?? "none"` in the projection. Rust has no `??`: the default is set in a Rust loop after the read (main_example.rs:630-634). |
| M52 | query-filter | 3/41 | 8/92 | 60 | 0.68 | full | R | Roc `is_vip` with list `contains`. Rust `tags.contains("vip")` typed; Rust needs a fn wrapper and the shared `key(id)`. |
| M53 | query-filter | 1/32 | 6/73 | 56 | 0.57 | partial | R | Roc `.?referred_by.is_ok()`. Rust must test NONE and NULL both (crate writes NULL). |
| M54 | projection | 10/90 | 6/73 | 56 | 1.59 | partial | S | Roc needs a 10-line `match o.?referred_by { Ok(r) => r.get().name, Err(_) => "nobody" }`. Rust `referred_by().name` is a typed path through the optional link; the default is applied in Rust. No `?.` chain in Roc. |
| M55 | projection | 4/76 | 8/72 | 60 | 1.26 | full | =* | Roc `p.owner.get().name` in a projection, no FETCH. Rust `owner().name` typed path, but two structs (`PetRow`, `PetLine`) and a Rust map for `species_label`. |
| M56 | projection | 9/94 | 16/145 | 132 | 0.71 | partial | R* | Roc `match` on a tag union runs in the DB (IF chain) and in the program. Rust runs the match in Rust after the read: not the same feature. |
| M57 | projection | 4/109 | 18/166 | 138 | 0.79 | full | R* | Roc `by_id` is an open-row query fragment, checked. Rust `fn by_id(SelectStatement)` orders by the string `"id"`: unchecked. |
| M58 | query-filter | 3/33 | 13/118 | 85 | 0.39 | full | R | Roc `vets.at(ruth_id)`. Rust `.from(Vet::create_id("ruth"))`: typed too, but wrapped in a fn. |
| M59 | query-filter | 1/37 | 8/102 | 65 | 0.57 | full | R | Roc `v.id == p.key`. Rust `id.eq(Vet::create_thing(key))`. |
| M60 | query-filter | 6/62 | 9/94 | 77 | 0.80 | partial | = | Roc `match p.species { Bird(b) => ..}` typed. Rust reads arm payload by untyped `Field` paths (`species.kind`, `species.wingspan_cm`) in a hand-made path closure (main_example.rs:721-731). |
| M61 | projection | 3/99 | 14/208 | 143 | 0.69 | full | R | Roc `select_value(..)` with `order_by(&#124;l&#124; l, Asc)` x3 queries. Rust `select_value` refuses a Function: `past_visits` cuts the id in Rust. |
| M62 | projection | 14/106 | 17/137 | 104 | 1.02 | partial | =* | Roc needs 2 `match p.?chip` blocks (14 lines) for what SurrealQL does with `chip.code ?? ..`. Rust writes the path as raw `Field::new("chip.code")` and `Field::new("chip.implanted_by.name")`: short, unchecked, defaults in Rust. |
| M63 | projection | 4/76 | 6/69 | 52 | 1.45 | raw SurrealQL | S | Roc `p.vaccines.map(&#124;v&#124; v.vet.get().name)`, typed. Rust `Field::new("vaccines.*.vet.name")`: raw string, one line, unchecked. |
| M64 | query-filter | 3/53 | 6/69 | 52 | 1.01 | partial | = | Roc `any` over a list with a typed id compare. Rust `Field::new("vaccines.*.vet").contains(thing)`: raw path. Roc compiles to a closure scan (see compare_surql.md section 5). |
| M65 | query-filter | 10/225 | 8/81 | 65 | 3.45 | partial | S | Roc open-row fragments need long annotations: `recent : Surreal.Query({ since : .., ..p }, { seen : .., ..r }) -> ..` (Clinic.roc:26-34, 48-50). Rust `fn recent(SelectStatement, since)` with a string field name. Roc checked, Rust short. |
| M66 | projection | 7/198 | 8/67 | 52 | 3.83 | raw SurrealQL | S | Roc `bill`/`dose_cost` open-row types, 198 tokens, typed over linked rows (Clinic.roc:9-15). Rust one raw string subquery `fee + math::sum((SELECT VALUE <decimal>doses * medication.unit_price FROM $parent.items))` (main_example.rs:783). |
| M67 | query-filter | 1/40 | 4/61 | 44 | 0.90 | raw SurrealQL | = | Roc `v.seen < Surreal.Time.now()`. Rust: a datetime compares only with a Field, `time::now!()` is a Function: raw `Field::new("time::now()")`. |
| M68 | projection | 10/93 | 16/132 | 113 | 0.82 | partial | = | Roc `match` arm reads a link: `Referred(r) => r.to.get().name`. Rust raw `outcome.to.name` field and text built in Rust. |
| M69 | query-filter | 8/66 | 18/157 | 137 | 0.48 | partial | R | Roc `needs_attention` is one function for the filter and the program. Rust has the Rust fn and a `kind != "Treated"` WHERE: two copies. |
| M70 | projection | 1/20 | 3/46 | 14 | 1.43 | full | = | Roc `select_value(&#124;v&#124; v)` generates a field list. Rust `select(All)`: shorter text, both one line. |
| M71 | projection | 4/69 | 14/123 | 90 | 0.77 | full | R | Roc `patient_age` projection + `order_by(&#124;r&#124; r.age, Desc).limit(3)`. Rust struct + `order(&age).desc().limit(3)`: typed too. |
| M72 | projection | 1/39 | 10/122 | 90 | 0.43 | full | R | Roc `.order_by(..).start(2).limit(2)`. Rust the same chain; Rust orders by the string `"id"`. |
| M73 | projection | 4/89 | 17/143 | 110 | 0.81 | partial | = | Roc `p.owner.get().address.city` and list map over links. Rust `owner().address().city` typed; the list part is raw `vaccines.*.vet.name`. |
| M74 | projection | 4/83 | 14/124 | 91 | 0.91 | partial | = | Roc whole linked rows as values (`owner: p.owner.get()`) in a typed projection. Rust `FETCH owner, vaccines.*.vet` returns whole `Patient` rows, not the projection shape. |
| M75 | query-filter | 3/50 | 4/79 | 43 | 1.16 | full | = | Roc `bind_captured(select_where(..))` captures a value, 3 lines with the `Try(Prepared ..)` annotation. Rust `unit_price.lt(limit)` binds the argument. |
| M76 | query-filter | 3/56 | 5/112 | 73 | 0.77 | full | R | Roc `places.contains(o.address)`. Rust `address.inside(list)` with `sql::to_value(places)` and error mapping. |
| M77 | query-filter | 4/55 | 12/137 | 101 | 0.54 | partial | R | Roc `o.address == place`. Rust three comparisons and a Rust `match` on `zip` present or absent. |
| M78 | group-aggregate | 4/145 | 8/71 | 60 | 2.43 | full | =* | Group query M78-M80 is one query (Roc 4 lines/145 tokens, Rust 23 lines/212). Roc `rows.len().to_i64_wrap()`, `rows.map(&#124;v&#124; v.fee).sum()`; Rust `count!()`, `math::sum!(fee)`. Key through a link is typed in both. |
| M79 | group-aggregate | 2/115 | 8/71 | 60 | 1.93 | partial | =* | Roc `Math.mean(rows.map(&#124;v&#124; v.fee.to_f64()))`. Rust `math::mean!(Field::new("<float>fee"))`: typed function, raw cast. |
| M80 | group-aggregate | 1/50 | 8/71 | 60 | 0.84 | full | = | Roc `.order_by(&#124;r&#124; r.revenue, Desc).limit(2)`. Rust `.order_by(order(Field::new("revenue")).desc()).limit(2)`: raw alias name. |
| M81 | group-aggregate | 4/102 | 19/163 | 130 | 0.78 | full | R | Roc `.totals(visit_totals)`. Rust `.group_all().return_first(..)` with an `Option` result. |
| M82 | group-aggregate | 1/44 | 14/135 | 104 | 0.42 | partial | R | Roc `totals` gives one row with count 0. Rust: 1.x returns no row, the 0 is set in Rust (`unwrap_or`). |
| M83 | write | 6/36 | 6/60 | 49 | 0.73 | partial | R | Roc `table.insert(rows)` x6, one line each. Rust `begin_transaction().query(insert(..))` chain plus an edge loop; `run()` returns Ok when a statement fails. |
| M84 | write | 1/6 | 4/71 | 39 | 0.15 | full | R | Roc `patients.create(pip)`. Rust `create().content(pip).return_one(db)`. Same; Rust count holds the async wrapper. |
| M85 | write | 2/25 | 4/80 | 48 | 0.52 | full | R | Roc form row + `create`. Rust `create().content(MedicationForm{..})`. Same. |
| M86 | write | 6/94 | 6/60 | 40 | 2.38 | full | S | Roc: `RestockParam`, `refill = &#124;p, m&#124; { ..m, stock: m.stock + p.add }`, open-row `low_stock` (main.roc:544-547, Clinic.roc:40-42). Rust `.set(stock.increment_by(add)).where_(low_stock(floor))`: field operator, no whole-row patch. |
| M87 | write | 3/54 | 7/105 | 73 | 0.74 | full | R | Roc `certified` patch fn with arithmetic and a new union value. Rust `.set(vec![years.increment_by(1), specialty.equal_to(..)])`. |
| M88 | write | 3/39 | 4/80 | 48 | 0.81 | full | = | Roc `{ ..o, name: .. }` sets only name. Rust `.set(name.equal_to(..))`. |
| M89 | write | 3/67 | 7/108 | 76 | 0.88 | full | = | Roc patch record with `Err(Missing)` removes `phone`. Rust `.patch(vec![zip.patch_add(..), phone.patch_remove()])` JSON Patch ops. |
| M90 | write | 1/17 | 4/56 | 25 | 0.68 | full | = | Roc `delete_at(id)`. Rust `delete::<Owner>(id)`. Cascade is a rule/event on both. |
| M91 | write | 3/62 | 4/55 | 32 | 1.91 | full | S | Roc `too_old` open-row fn with a 2-line type plus `delete_by` (Clinic.roc:36-38). Rust `fn too_old(before) -> Filter` + `.where_(too_old(before))`. |
| M92 | write | 11/185 | 11/128 | 104 | 1.77 | partial | S | Roc: `Note` row, handle, `default_by`, `Created`, `note_line` open row, `insert_new`. Rust: `SurrealUlid` and `insert(notes)`. Roc gets a server-made key; Rust makes the ULID in the client. |
| M93 | write | 24/234 | 34/902 | 616 | 0.38 | partial | R | Roc 24 refusal writes, one per line. Rust 34 lines; in the 1.5.6 run 19 refused with a field name, 3 deletes refused but `Ok`, readonly and union-arm link not refused. |
| M94 | other | 22/511 | 14/162 | 118 | 4.33 | partial | S | Roc open-row helpers carry full structural types (Clinic.roc:9-54, 22 lines/511 tokens). Rust shares `fn(SelectStatement) -> SelectStatement` and `Filter` with no row types (checked by name strings only). |
| N01 | geometry | 1/23 | 13/118 | 87 | 0.26 | partial | R* | Roc `Surreal.Point`, `Surreal.Polygon` add a validity assert. Rust `sql::Geometry`, no `geo::is_valid` in 1.5, bad point stored; `geo` types do not deserialize back. |
| N02 | geometry | 7/91 | 4/34 | 26 | 3.46 | full | =* | Roc `rectangle` helper (7 lines). Rust `rectangle` helper with `geo::Polygon` (5 lines) + seed with `sql::Geometry`. Block is shared with fixtures. |
| N03 | link | 1/20 | 3/27 | 27 | 0.74 | partial | = | Roc `Link(Site)` gives exists assert and Reject. Rust `LinkOne<Site>` with a hand assert; no reject-on-delete event written. |
| N04 | time series | 1/29 | 6/78 | 78 | 0.37 | partial | R | Roc `TimeKey(Id(Kennel))` types the key. Rust `SurrealId<Vital, Vec<sql::Value>>`; DB id type stays `record<vital>` (no array id type in the derive). |
| N05 | time series | 3/59 | 6/71 | 63 | 0.93 | full | = | Roc `time_key(id, datetime)`. Rust `vital_id(kennel, time)` builds `Vec<sql::Value>`. |
| N06 | edge | 10/130 | 36/351 | 340 | 0.38 | partial | R | Roc two edge tables = `Surreal.relation` x2. Rust: `relate` on an edge table with `_` panics (derive bug, `__Cares For`): raw path Field and `in`/`out` types by hand. |
| N07 | other | 25/211 | 19/151 | 129 | 1.63 | full | S | Roc boilerplate `x_def : Surreal.Defined` / `x_def = x.define().done()` x5 even with no rules (monitoring.roc:103-116). Rust `impl TableResources for Site {}` is one line, plus `create_table_resources!(..)`. |
| N08 | db function | 5/76 | 10/90 | 90 | 0.85 | partial | = | Roc `db_fn("fever", fever)`: one function for DB and program. Rust `define_function!` plus a Rust twin `fever`. |
| N09 | db function | 1/36 | 8/76 | 59 | 0.61 | partial | R | Roc `fever_fn.call2(..)` in a filter. Rust: a Function is not `Conditional`, wrapped as a Field (`fevered_where`). |
| N10 | db function | 6/54 | 8/60 | 60 | 0.91 | raw SurrealQL | = | Roc `.computed(..)` with the db function. Rust raw `DEFINE FIELD .. VALUE fn::fever(temp_c, pulse)`: raw string (builder writes `$value OR ..`). |
| N11 | db function | 4/79 | 6/72 | 56 | 1.41 | full | S | Roc `FlagLine` type + fn + query. Rust `fever_fn(temp_c, 0).__as__("hot")` typed call in `select(arr![..])`. |
| N12 | db function | 4/122 | 13/117 | 90 | 1.36 | full | S | Roc `rows.keep_if(&#124;v&#124; fever_fn.call2(..)).len().to_i64_wrap()`. Rust `count!(fever_fn(temp_c, pulse))`: an aggregate call. |
| N13 | time series | 4/106 | 12/123 | 105 | 1.01 | raw SurrealQL | = | Roc `v.id.series()`, `v.id.time()` typed. Rust raw `Field::new("meta::id(id)[0]")` and `[1]`. |
| N14 | time series | 4/79 | 8/84 | 67 | 1.19 | full | = | Roc projects the whole key. Rust `meta::id!(id)`. Rust typed result is a tuple `(Thing, Utc)`. |
| N15 | time series | 1/26 | 6/64 | 24 | 1.08 | full | = | Roc `.between(kennel_a, start, end)` (time keys only, literal times). Rust `.from(vital_id(a, start)..vital_id(a, end))`: a Rust range of any id is a record range. |
| N16 | time series | 1/29 | 3/62 | 22 | 1.32 | full | = | Same as N15 with whole rows. |
| N17 | time series | 3/66 | 8/71 | 59 | 1.12 | partial | = | Roc `Time.floor(v.id.time(), Time.days(1))` typed. Rust `time::floor!` typed, key part raw `Field`. |
| N18 | time series | 1/30 | 4/67 | 32 | 0.94 | partial | = | Roc `delete_by(&#124;p, v&#124; v.id.time() < p.before)`. Rust `where_(key_time().lt(before))`, key part raw. |
| N19 | time series | 1/12 | 8/97 | 76 | 0.16 | raw SurrealQL | R* | Roc `.changefeed(Time.days(7))`. Rust has no CHANGEFEED in `define_table`: raw `DEFINE TABLE vital SCHEMAFULL CHANGEFEED 7d` replaces the table definition; the check reads INFO raw. |
| N20 | group-aggregate | 7/188 | 6/59 | 48 | 3.91 | partial | =* | Group by two derived keys (N12, N17, N20, N21 share one Rust `daily_select`, 11 lines + `Daily` struct). Roc DayKey, day_of, Daily, day_line (7 lines/188). Rust keys are aliased raw Fields. |
| N21 | view | 4/45 | 14/118 | 118 | 0.38 | partial | R | Roc `daily.define_as(query, day_line)` is the view and the query. Rust `#[orm(as_ = daily_select())]`; on 1.5.6 the view held 1 row, not 5. |
| N22 | view | 1/44 | 3/46 | 14 | 3.14 | full | S | Roc respells every field (`select(&#124;d&#124; { kennel: d.kennel, .. })`, monitoring.roc:390-394). Rust `select(All).from(VitalDaily::table())`. No rest-spread or OMIT in Roc. |
| N23 | query-filter | 1/36 | 3/55 | 23 | 1.57 | full | =* | Roc repeats the fever call inline. Rust reuses `fevered_where()` (counted under N09). |
| N24 | query-filter | 1/36 | 7/65 | 33 | 1.09 | partial | = | Roc group then filter on the result is a subquery. Rust `select(All).from(daily_select()).where_(Field::new("fevers").lt(Field::new("readings")))`: untyped outer fields. |
| N25 | query-filter | 1/46 | 5/114 | 82 | 0.56 | partial | R | Roc `select(..).order_by(..).limit(3).filter(..)` keeps order and types. Rust nested `select(All).from(subquery)` with raw outer Field. |
| N26 | query-filter | 1/47 | 5/119 | 87 | 0.54 | partial | R | Same for a scalar projection. Rust uses raw `Field::new("$this")`. |
| N27 | group-aggregate | 1/46 | 6/58 | 42 | 1.11 | partial | = | Roc `.query()` makes result rows a new query. Rust writes one SELECT by hand: no composition of a projection into a query. |
| N28 | query-filter | 1/54 | 7/63 | 27 | 2.00 | partial | S | Roc `.query().filter_by(&#124;p, d&#124; d.readings >= p.least).select(&#124;r&#124; r)` typed with param. Rust `Field::new("readings").gte(least)`: raw field, shorter. |
| N29 | geometry | 4/56 | 12/128 | 95 | 0.59 | raw SurrealQL | R | Roc `s.location.lat()`. Rust raw `Field::new("location.coordinates[1]")`. |
| N30 | geometry | 3/71 | 4/87 | 45 | 1.58 | full | S | Roc `Surreal.Geo.inside(p.here.to_geometry(), s.area.to_geometry())`: DB-only function with explicit conversions. Rust `area.contains(here)` typed. |
| N31 | geometry | 1/50 | 5/122 | 80 | 0.62 | partial | R | Roc `Geo.distance(s.location, p.here) < 50000` typed compare. Rust `geo::distance!` is a Function, not comparable: raw Field. |
| N32 | read row | 4/127 | 9/83 | 72 | 1.76 | partial | S | Roc read rows: `KennelRead`, `CareRead`, `Linked`, `In`, a handle (monitoring.roc:74-83). Rust raw graph path `Field::new("<-cares_for<-carer")` and typed `site().name`. Roc checks the paths, Rust does not. |
| N33 | read row | 3/140 | 9/83 | 72 | 1.94 | raw SurrealQL | S | Roc `In(CareRead)` with `Linked(Carer)`: whole carer rows, checked. Rust raw `<-cares_for<-carer` (also hits the N06 derive panic). |
| N34 | read row | 1/82 | 7/56 | 45 | 1.81 | raw SurrealQL | S | Roc `k.cares_for.list().keep_if(&#124;e&#124; e.lead).len()`. Rust raw `count!(Field::new("<-cares_for[WHERE lead = true]"))`. |
| N35 | read row | 2/12 | 0/0 | 0 | - | not possible | n/a | Roc `define_read()` checks a read row against the stored row. Rust: not possible (no read rows). |
| N36 | other | 3/93 | 21/236 | 201 | 0.46 | partial | R | Roc `readings_of(vitals.rows(), k)` one function for DB and program. Rust subquery in `count!`, key part raw, Rust twin `readings_of`. |
| N37 | query-filter | 3/73 | 9/145 | 113 | 0.65 | partial | R | Roc semi join `has_fever(vitals.rows(), k)`. Rust subquery as WHERE; returned [] on 1.5.6 (`$parent` in a WHERE subquery). |
| N38 | live query | 3/56 | 8/140 | 95 | 0.59 | partial | R | Roc `Watch(VitalLine)` from the same filter, with snapshot and predicted notices. Rust `live(select(..))` + SDK stream; no snapshot, no prediction. |
| N39 | live query | 3/65 | 4/89 | 53 | 1.23 | partial | S | Roc `hotter_than` with annotation, `filter_by`, `live({limit}, definitions)`. Rust `live(select(..).where_(temp_c.gt(limit)))` one call. |
| N40 | live query | 3/64 | 3/54 | 22 | 2.91 | partial | S | Roc respells the view fields again (no select-all). Rust `live(select(All).from(VitalDaily::table()))`. |
| N41 | live query | 8/129 | 10/100 | 93 | 1.39 | partial | R* | Roc `incoming` + filter + projection on a tuple, joined streams built in. Rust: two LIVE statements and the join of the streams is app code, not written (block shared with N42). |
| N42 | live query | 3/85 | 10/100 | 93 | 0.91 | partial | R* | Roc same watch through the read row `In`. Rust: same two streams, no read rows, join not written. |
| N43 | live query | 3/59 | 9/153 | 121 | 0.49 | partial | R | Roc live filter over the rows of another table. Rust: LIVE WHERE does not re-run on writes to `vital`. |
| N44 | live query | 8/173 | 31/262 | 246 | 0.70 | partial | R | Roc `and_incoming` watches two edge tables. Rust: three LIVE statements, join in app code. |
| N45 | live query | 3/64 | 13/182 | 169 | 0.38 | partial | R | Roc live projection through `Linked`: a site rename reaches the kennels. Rust: two LIVE statements, join not written. |
| N46 | live query | 2/60 | 4/94 | 62 | 0.97 | partial | = | Roc `k.site.get().name == "Oslo"`. Rust `site().name.eq("Oslo")`; the Rust LIVE does not re-run when a site is renamed. |
| N47 | live query | 2/53 | 6/119 | 72 | 0.74 | full | R | Roc `live_raw`. Rust `stream::<Notification<sql::Value>>`; the shared `watch` helper is in the count. |
| N48 | live query | 2/29 | 3/63 | 28 | 1.04 | full | = | Roc `live_diff`. Rust `live(select_diff(..))`. |
| N49 | write | 0/0 | 11/283 | 163 | - | full | n/a | Roc cited lines are scenario data (not counted). Rust has the same steps as code (`create`, `update().replace`, `delete`). |
| N50 | write | 0/0 | 9/186 | 122 | - | partial | n/a | Roc scenario data, not counted. Rust edge create is RELATE over a raw path Field (derive panic, see N06); delete is typed. |
| N51 | write | 0/0 | 6/146 | 82 | - | full | n/a | Roc scenario data. Both: SurrealDB deletes the edges of a deleted node. |
| N52 | write | 0/0 | 8/174 | 119 | - | full | n/a | Roc scenario data. Rust `update().set(name.equal_to(..)).return_none` (a Site does not read back). |
## 3. Where Roc is weaker (ranked)

Rank is by the number of features touched and by what the user must write. Roc paths are examples/main.roc (m), examples/monitoring.roc (n), examples/clinic/Clinic.roc (c). Rust paths are SCRATCH/rust/src/main_example.rs (rm) and monitoring_example.rs (rn).

| Rank | Weakness | IDs | Roc | surreal_orm |
| --- | --- | --- | --- | --- |
| 1 | Typed edge traversal is one hop, and the edge filter is list code after the hop. A path cannot hold a filter or a second hop. | M28, M29, N32-N34, N41 | m:491-492 `case_load = \|v, edges\| { .., primary: edges.keep_if(\|e\| e.primary).len().to_i64_wrap() }` with `Surreal.from(vets).outgoing(treats)` (m:837) | rm:865 `count!(Vet::schema().treats__(primary.eq(true)).id)`; rm:885 `Patient::schema().__treats(primary.eq(true)).vet(E).name` |
| 2 | No field-level write operators. A patch is a whole-row function (the generated text is a field SET, `stock = stock + $add`, main.surql:331). | M86, M87, M89 | m:547 `refill = \|p, m\| { ..m, stock: m.stock + p.add }` plus `RestockParam` and open-row `low_stock` (c:40-42) | rm:1225 `.set(stock.increment_by(add)).where_(low_stock(floor))`; rm:1251 `.patch(vec![zip.patch_add(..), phone.patch_remove()])` |
| 3 | Open-row fragments need the full structural type. 198 and 225 tokens for what Rust writes as `fn(SelectStatement)`. Rust names the field by a string, so Roc is checked and Rust is not, but the cost is real. | M65, M66, M91, M94 | c:26-34 `recent : Surreal.Query({ since : Surreal.Datetime, ..p }, { seen : Surreal.Datetime, ..r }) -> ..`; c:9-15 `bill`, `dose_cost` | rm:779 `pub fn recent(statement: SelectStatement, since: DateTime<Utc>) -> SelectStatement`; rm:783 `fn bill() -> Alias` (raw string) |
| 4 | Optional values and optional links need `match`. A path that crosses NONE is one line in SurrealQL and in surreal_orm. | M54, M62 | m:448-462 two `match p.?chip { Ok(c) => .., Err(_) => .. }` blocks, 14 lines; m:431-437 `match o.?referred_by`, 10 lines | rm:656 `Owner::schema().referred_by().name.__as__("by")`; rm:744 `Field::new("chip.code").__as__("chip")` |
| 5 | No select-all, rest-spread or OMIT in a projection. A view or table row is respelled field by field, in each query and each live query. | N22, N40, N28, M70 | n:390-394 `select(\|d\| { kennel: d.kennel, day: d.day, readings: d.readings, fevers: d.fevers })` | rn:407 `select(All).from(VitalDaily::table())`; rn:550 `live(select(All).from(VitalDaily::table()))` |
| 6 | Per-table ceremony: `encoder_for : _` / `parser_for : _`, a handle plus annotation per table, an empty `x_def` per table. | M01, M03, N07, N06 | m:32-33 `encoder_for : _` `parser_for : _`; n:103-116 `site_def : Surreal.Defined` / `site_def = sites.define().done()` x5 | rn:172 `impl TableResources for Site {}`; `create_table_resources!(Site, Kennel, ..)` (rn:170) |
| 7 | Aggregates are list code with numeric conversions. No aggregate call over a function result. | M78, M79, N12, N20 | m:503 `{ visits: rows.len().to_i64_wrap(), revenue: rows.map(\|v\| v.fee).sum(), avg_fee: Surreal.Math.mean(rows.map(\|v\| v.fee.to_f64())) }`; n:139 `rows.keep_if(\|v\| fever_fn.call2(..)).len().to_i64_wrap()` | rm:904-907 `count!()`, `math::sum!(fee)`, `math::mean!(..)`; rn:193 `count!(fever_fn(temp_c, pulse))` |
| 8 | Database-only functions need explicit conversions and a point value. | N30, N31, M37 | n:270-272 `Surreal.Geo.inside(p.here.to_geometry(), s.area.to_geometry())` | rn:441 `area.contains(here)` |
| 9 | Record ranges: only `between(series, from, to)` on a TimeKey, one per query, literal times. | N15, N16, N18 | n:343 `.between(kennel_a, day_start, day_end)` | rn:340 `.from(vital_id("a", start)..vital_id("a", end))`; README: `id1..=id2` for any id type |
| 10 | Captured-value queries have a second API with a `Try(Prepared(..))` annotation. | M75, M76, M77, N39 | m:510-513 `cheaper_than : Dec -> Try(Surreal.Prepared(List(Medication)), Surreal.Error)` | rm:993 `fn cheaper_than(db, limit: f64)`: a function argument is the bound parameter |
| 11 | Server-made keys cost a row type, a handle and a `default_by`. This buys a key made by the server, which Rust does not do. | M92, M47 | m:1090-1098 `Note` + `notes` + `note_def` + `Created` | rm:251-262 `SurrealUlid` and `Note::create_ulid()` (client side) |
| 12 | Escape hatches are fewer. `Raw::new(..)` and `Field::new(..)` are accepted almost everywhere in surreal_orm. In Roc `Unchecked` exists (Surreal.roc:2454) but a raw statement is not accepted in a schema or a clause. | M15-M17, M43, N10, N19 | no raw DEFINE inside `define()` | rm:486 `Raw::new("DEFINE FIELD chip.implanted_by ..")` in `fields_definitions` |

Fairness note: surreal_orm gets rows 1, 4, 5, 8, 9 partly by unchecked or raw paths (`Field::new("<-cares_for<-carer")`, `Field::new("chip.code")`). Rank 1 and 2 are typed in surreal_orm (generated path structs and field operators), so they are real gaps in design, not only in tokens. Rank 3 is the price of checking.

Statement coverage that surreal_orm has and Roc does not (checked in src/Surreal.roc and src/Schema.roc): standalone IF/ELSE, FOR and THROW builders, `DEFINE PARAM`, `INFO`, `SLEEP`, a general transaction block (Roc has one transaction per `insert` or `update`, not a user block). NOTES.md says surreal_orm itself loses errors in `run()` for a transaction and for a THROW, so the larger surface is not always reliable.

## 4. Where Roc is stronger

| Rank | Strength | IDs | Roc | surreal_orm |
| --- | --- | --- | --- | --- |
| 1 | One function for the database and the program. Constraints, computed fields, filters, `match` projections and database functions are written once. | M35, M40, M41, M45, M56, M69, N08, N36 | m:129-131 `valid_email` used by `.assert(\|o\| o.email, valid_email)` and by program code | rm:297-306 `valid_email` (Rust) and `valid_email_assert` (Filter): two copies. Same for M40, M41, M45, M56, M69, N08, N36 |
| 2 | Links as a type: type, exists assert, index, delete rule from `Link(T)`. Nested links (optional record, list, union arm) work the same. | M14-M21, N03 | m:71 `owner : Surreal.Link(Owner)` | 10 hand asserts, raw events, no index (rm:484-527); 3 delete rejections returned `Ok` |
| 3 | Constraints in the row type: ranges from U8/I32, defaults, tag unions with kind asserts, nested record fields. | M05-M12 | m:41-44 `Vet : VetRow(U8)` | `assert = cond(value().gte(0)).and(value().lte(255))` per field; `nest_object` without nested DEFINE FIELD; unions as `any` + optional fields |
| 4 | Live queries: one filter gives the Watch type, snapshot, leave notices and joins over edges and linked rows. | N38-N46 | n:443 `fevered = Surreal.from(vitals).filter(..).select(vital_line).live({}, definitions)` | `live(select(..))` + SDK stream; no snapshot, no prediction, joins of streams are app code |
| 5 | Checked names and types in clauses (field names, clause order, edge ends, patch fields, match exhaustiveness). | M57, M60, M62-M66, N13, N17, N28-N34 | `p.vaccines.map(\|v\| v.vet.get().name)` | `Field::new("vaccines.*.vet.name")`, `Field::new("meta::id(id)[0]")`: strings, a typo gives NONE |
| 6 | Function results compose. A db function is a value in a filter, projection, group and computed field. | N09-N12 | n:90-99 `Surreal.db_fn("fever", fever)` then `fever_fn.call2(..)` anywhere | A `Function` is not `Conditional` or `Operatable`: raw Field in WHERE (rn:124), raw `geo::distance`, raw `time::now()` |
| 7 | Time series keys and views from the same definitions. | N04, N13, N21 | n:46 `TimeKey(Id(Kennel))`; n:146 `daily.define_as(query, day_line)` | `SurrealId<Vital, Vec<sql::Value>>`; view held 1 row instead of 5 on 1.5.6 |
| 8 | Read rows: `Linked`, `In`, `Out` and `define_read` check a second row type against the stored row. | N32-N35 | n:74-83 | N35 not possible; N33/N34 raw graph paths (and the N06 derive panic) |
| 9 | Server-made keys, `OVERWRITE` schema, errors that name the field. | M47, M92, M93 | m:1094 `default_by(.., Rand.ulid())` | client ULID; `run()` hides THROW |
| 10 | Newer SurrealDB: Roc targets 3.x features (REFERENCE ON DELETE, TYPE RELATION ENFORCED, literal unions, record::exists, READONLY). surreal_orm talks to 1.x only. | M14-M21, M25, M44 | Schema.roc:657 `TYPE RELATION IN .. OUT .. ENFORCED` | rm:1202 `relate(..)`, hand asserts at rm:486; M44 not possible |

## 5. Ideas from surreal_orm worth taking

Each row: what surreal_orm does, what the Roc ORM has now (checked in src/Surreal.roc, src/Schema.roc, docs/schema.md), the gap.

| Idea | surreal_orm | Roc now | Gap | Value |
| --- | --- | --- | --- | --- |
| Typed multi-hop traversal with an edge filter in the path | `Vet::schema().treats__(primary.eq(true)).patient(E).name`; `->a->b->(c, d WHERE ..)` composes as one typed value; `count!(path)` (rm:864-885) | `Query.outgoing(edge_table)`, `incoming`, `and_outgoing`, `and_incoming` (Surreal.roc:1822-1848): one level, tuple `(row, List(edge))`; hop 2 only through a read row `Out`/`In` (docs/links-and-graphs.md:123-188); edge filter is list code `edges.keep_if(..)` | A path value `v.treats(\|e\| e.primary).to.owner.name` that translates to `->treats[WHERE primary]->patient->owner.name`. Edge filter inside the path. Second hop without a read row. | High: removes the tuple, `to_i64_wrap` and closure scans (compare_surql.md section 5, M28) |
| Field-level write operators | `increment_by`, `decrement_by`, `append`, `remove`, `patch_add`, `patch_replace`, `patch_change` (rm:1225, 1235, 1251) | `update` / `set` with a patch function over the row (Surreal.roc:1411-1449); `patch_at`, `patch_ops_at` take JSON Patch ops (Surreal.roc:1315-1338) | The patch fn is already read as `SET stock = stock + $add` (main.surql:331), so the DB side is right. The gap is the source: the user writes a whole-row function and a param type. No `append` or `remove` form for list fields. | Medium: M86, M87 are the largest write gap |
| Permissions on tables and fields | `permissions = for_permission([Select, Update]).where_(..)` on the model and on fields (define_model.rs:45-49) | `Def.permit`, `permit_full`, `permit_field`, `deny_field`, `Access.define`, `Table.auth` (Surreal.roc:1648-1690, 1693-1757) | Roc has it, and the filter is a Roc function (`.permit([Select], \|m\| m.owner.id() == users.auth())`). Not in the examples main.roc or monitoring.roc. Gap is a test in the examples only. | Low |
| Migrations | Migrator CLI and embedded migrations: init, generate (diff), up, down, reset, prune from `DbResources` (README "Migration") | `Surreal.schema(..)` text with `OVERWRITE`; no history, no diff, no down (docs/schema.md:378, docs/getting-started.md:308: "no migration tool"). A removed field stays in the DB. | A diff between two `Defined` lists (REMOVE FIELD, REMOVE INDEX) and a numbered up/down script. The one-function constraints give a stable text to diff. | Medium: production use |
| Record ranges of any id | `from(id1..id2)`, `from(id1..=id2)` with `Id` types (rn:340) | `Query.between(series, from, to)` on TimeKey only, one per query (docs/queries.md:303, 443) | A range of a typed `Id` or of a compound key with inclusive and exclusive ends, usable in `filter` too. | Medium |
| Typed edge insert and `relate` path | `relate(Vet::with(a).treats__(E).patient(b)).content(e)` | `table.create(edge)` / `insert` for an edge table (RELATE, INSERT RELATION) | None for the base case. Surreal_orm path form also works for a second edge hop. | Low |
| Statement builders: IF/ELSE, FOR, THROW, LET, PARAM, transaction block | `if_`, `throw`, `begin_transaction().query(..)`, `query_turbo!`, `block!` | Roc writes IF, LET and THROW only inside generated text (Schema.roc:627, 867). No user transaction block. | A `Surreal.transaction([..])` of prepared writes. Atomic multi-table writes are needed for any real app. | Medium |
| Raw escape inside typed builders | `Raw::new(..)` and `Field::new(..)` almost everywhere; `query!` with named bindings | `Surreal.Unchecked.select_star`, `fetch` (Surreal.roc:2454-2472), `live_raw` | A typed-hole `Surreal.Unchecked.expr("..")` usable in `define()` and in a clause, marked by name so a reviewer sees it. | Low to medium |
| Aggregate functions as typed calls | `count!(x)`, `math::sum!(x)`, `math::mean!(x)` over any Field or Function | List code in `aggregate` (`rows.len()`, `rows.map(..).sum()`) | `Surreal.count(pred)`, `Surreal.sum(f)`, `Surreal.mean(f)` inside `aggregate` that skip `to_i64_wrap` and `to_f64`. | Medium (M78, M79, N12, N20) |
| Select all with a path-checked OMIT | `select(All)` | `select(\|r\| r)`, `Unchecked.select_star` | `select_all()` that keeps the row type; `omit(.id)` to drop a field. | Low (N22, N40) |
| Derive from the type with per-field attributes | `#[orm(ty, assert, value, define)]` on the struct field | Builder `.assert(\|o\| o.email, ..)` after the type | Rust keeps field and rule together. Roc keeps the rule in one list (m:353-412), which is easy to read but far from the field. A `Def` that takes `.on(field, [rules])` could group. | Low, style |

Derive bugs and gaps in surreal_orm found by the port (NOTES.md). They are not counted against its verbosity.

| Bug or gap | Effect |
| --- | --- |
| `item_assert` emits `DEFINE FIELD "tags". *` | Invalid SurrealQL, a hand statement is needed (M38). |
| `relate` on an edge table with `_` panics (`__Cares For`) | No typed traversal for `cares_for` (N06, N33, N34, N50). |
| Edge `in`/`out` default to `record<any>` | SurrealDB 1.5 reads it as table `any`: `ty = "record<vet>"` by hand (M23). |
| `link_self` is typed `record<T>`, not optional | Rows with no referral are refused: override (M18). |
| Nested object fields get no DEFINE FIELD; `nest_object` takes no Option | One statement per nested path; `chip` loses its typed path (M04, M06, M08). |
| `value = x` becomes `VALUE $value OR x` | Not a DEFAULT on 1.5, not a computed field (M05, M45, M46, N10). |
| `string::starts_with!` emits a 2.x name | 1.5 refuses it: raw `string::startsWith` (M35, M36). |
| `None` is written as NULL | `option<T>` refuses NULL: `option<T \| null>` by hand, filters test both (M04, M53). |
| `ty = "decimal"` needs `f64`; decimals read back as strings; chrono as string; `geo` types as plain structs | Helpers `dec`, `sql_datetime`; `sql::Geometry` does not read back (M11, N01, N02). |
| `run()` does not return statement errors | A failed transaction and an event THROW give `Ok` (M21, M83, M93). |
| `select_value` refuses a Function; a Function is not `Conditional` | Raw Fields for `fn::..`, `geo::distance`, `time::now()` (M61, M67, N09, N31). |
| 1.x server only | No REFERENCE ON DELETE, TYPE RELATION ENFORCED, literal unions, record::exists, READONLY, geo::is_valid, closures, `??` (M05, M14, M20, M44, N01). |

## 6. Totals

Code lines and tokens, comments and blank lines left out. Roc unique numbers are from compare_surql.md section 6. Rust numbers are from fair2.py with attribute lines counted.

| Item | Roc lines | Roc tokens | Rust lines | Rust tokens | Note |
| --- | --- | --- | --- | --- | --- |
| Feature code, main (M01-M94), unique | 343 | 4593 | 971 | 10918 | Roc = 321 in main.roc + 22 in Clinic.roc |
| Feature code, monitoring (N01-N52), unique | 136 | 2726 | 450 | 5592 | Rust holds 32 lines / 748 tokens of N49-N52 scenario steps |
| Feature code, monitoring without N49-N52 | 136 | 2726 | 418 | 4844 | Fair compare |
| Feature code, both, fair | 479 | 7319 | 1389 | 15762 | Roc is 0.34 of Rust in lines and 0.46 in tokens |
| Rust execute wrappers inside the Rust count | 0 | 0 | about 76 fns | about 2700 | Without them Roc is about 0.56 of Rust in tokens |
| Rust attribute lines (dropped by slice.py) | | | 143 | 1861 | `#[derive]`, `#[orm]`, `#[serde]` |
| Fixture code, main | 180 | 2182 | 147 | 2760 | `@F` blocks |
| Fixture code, monitoring | 85 to 187 | 1004 to 3196 | 76 | 924 | |
| Setup (imports, Db alias) | 6 | not counted | 29 | 254 | |
| Per-ID sums (overlap counted) | 627 | 10236 | 1416 | 16516 | Rust sum is a partition. Roc sum repeats code |

Rust by area (main_example.rs, unique):

| Area | Lines | Tokens | Roc counterpart |
| --- | --- | --- | --- |
| Row types (rm:19-262) | 196 | 1703 | m:31-118, 80 lines / 1055 tokens (sum over M01-M13) |
| Rust copies of rules (rm:263-394): `valid_email`, `possible_species`, asserts as Filters, serde helpers | 93 | 942 | none: Roc reifies the one function |
| Schema glue (rm:395-606) | 174 | 2189 | m:353-412, 60 lines / 564 tokens (M48) |
| Reads (rm:607-1059) | 375 | 3831 | m:416-540, query ranges of M49-M82 |
| Writes (rm:1182-1313) | 99 | 1351 | M83-M92 |
| Refusals (rm:1314-1377) | 34 | 902 | M93, 24 lines / 234 tokens |

Verdict counts (146 features):

| Verdict | Count |
| --- | --- |
| Roc shorter | 78 |
| Similar | 41 |
| Rust shorter | 20 |
| n/a | 7 (M22, M44, N35, N49-N52) |

Rust shorter (S): M49, M54, M63, M65, M66, M86, M91, M92, M94, N07, N11, N12, N22, N28, N30, N32, N33, N34, N39, N40.

Short answer: Roc is shorter in 78 features and Rust in 20. Roc wins on everything that is a rule of the schema (types, links, constraints, defaults, unions) because the type and one function carry the rule, and on single-source logic (M35-M45, M56, M69, N08, N36) and live queries. surreal_orm wins on typed edge paths with filters and hops, field operators in writes, aggregate calls, select-all, id ranges, a migrator and a wider statement surface. Rust needs hand-written raw SurrealQL or second copies of the logic in 75 partial and 13 raw features.
