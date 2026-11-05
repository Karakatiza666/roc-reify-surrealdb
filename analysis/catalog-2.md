# Feature catalog 2: roc-reify-surrealdb examples/main.roc, examples/monitoring.roc and examples/client.roc

Purpose: shared feature IDs for the ORM comparison (hand-written SurrealQL, Rust surql_orm, Drizzle). This is catalog 1 (`analysis/catalog.md`) after the examples were rewritten in a shorter style and the library gained API. The IDs M01 to M94 and N01 to N52 are the same. New IDs: M95 to M101, N53 to N55, C01 to C04. M69 is removed.

## Changes since catalog 1

Rows that are not in this table moved only to other line numbers. Their description, API and SurrealQL are the same. In the table, the Roc columns give lines of `main.roc` (M rows), `monitoring.roc` (N rows) or `client.roc` (C rows). `Clinic:` marks `examples/clinic/Clinic.roc`. The scripts are generated again. In `main.surql` the schema and the seeds moved by -2 and the reads by -2, the graph path blocks (216-228) are new, the refusals moved by +12 and the writes and totals by +16. In `monitoring.surql` the lines up to line 92 did not move, and the later lines moved by +5 (the block `busy_days_never` is new).

General API changes that touch many rows:

| API change | Effect on the examples |
| --- | --- |
| `Query.ready()` | A query with no parameters ends with `ready()`. Before: `prepare({})`. A query with parameters keeps `prepare({..})`. `ready_live(definitions)` replaces `live({}, definitions)` |
| Lambdas in queries | Many named functions and their record types are removed, and the query has a lambda. Examples: `CityParam`, `in_city`, `is_vip`, `referral_line` (as query code), `case_load`, `team_line`, `contact_line`, `linked_rows`, `refill`, `certified`, `renamed`, `moved`, `Clinic.too_old`, `site_lat` |
| `U64` counts | `rows.len()` is a `U64` field. No `to_i64_wrap`. Types: `Ledger.visits`, `Daily.readings`, `Daily.fevers`, `Unattended.carers`, `Neglected.carers` |
| `Math.mean_dec` | The mean of a list of decimals. Before: `Math.mean` of a list of `to_f64` |
| One `definitions` list | The `*_def` values are removed in both files |
| `Query.select` is optional | A whole row or a whole view row needs no `select(|r| r)` |
| Graph paths | `table.edges_from(row)` and `table.edges_to(row)` inside a clause (M95 to M97) |

| ID | What changed | Roc before | Roc after | SurrealQL before | SurrealQL after |
| --- | --- | --- | --- | --- | --- |
| M08 | SurrealQL: typed array of objects, the `object::keys` check and the `[*].given` field are gone | 60, 74, 77, 87 | 60, 74, 77, 87 | 39-42, 45-47 | 39-41, 44-46 |
| M28 | Roc: lambda in the query, `case_load` and `CaseLoad` removed; counts are `U64` (no `to_i64_wrap`) | 488-492, 837 | 719 | 158-160 | 156-158 |
| M29 | Roc: lambda in the query, `team_line` and `TeamLine` removed; count is `U64` | 494-498, 843 | 725 | 162-164 | 160-162 |
| M43 | SurrealQL: field ASSERT on `fee` (was DEFINE EVENT with THROW, line 68 before); the refusal names `field fee`; a second refusal on update (M98) | 400; Clinic:21-24 | 380; Clinic:21-24 | 68 | 43 |
| M48 | Roc: one `definitions` list, the seven `*_def` values are removed | 353-412, 754-758 | 345-391, 633-637 | 1-72 | 1-70 |
| M49 | Roc: `filter_by(|p, o| ..)` lambda, `CityParam`, `in_city`, `owners_in_city` removed | 416-419, 765 | 644 | 104-108 | 102-106 |
| M52 | Roc: lambda in the filter, `is_vip` removed | 439-440, 771 | 650 | 110-112 | 108-110 |
| M54 | Roc: `map_ok` and `??` in a lambda (was `match` in `referral_line`); SurrealQL: `??` (was IF ... THEN) | 427-437, 777 | 653-657 | 116 | 114 |
| M62 | Roc: `map_ok` and `??` (was `match` in `chip_line`), `ChipLine` removed; SurrealQL: `??` | 448-462, 807 | 684-688 | 136-138 | 134-136 |
| M63 | Roc: lambda in the query, `vaccine_line` and `VaccineLine` removed | 464-468, 813 | 691-695 | 142 | 140 |
| M65 | Roc: `SinceParam` removed; `Clinic.seen_before` removed | Clinic:26-34, 48-50; 473, 819 | Clinic:26-31, 41-43; 701 | 144-148 | 142-146 |
| M66 | Roc: lambda in the query, `visit_line` and `VisitLine` are now only a reference helper (line 481) | Clinic:9-15; 475-478 | Clinic:9-15; 701 | 148 | 146 |
| M68 | Roc: `outcome_line` and `OutcomeLine` removed | 145-150, 480-483, 831 | 145-150, 713 | 156 | 154 |
| M69 | Roc: removed, moved to M101 and M60 | 152-156, 485-486, 831 | removed | 156 | removed |
| M70 | Roc: `select_value(|v| v)` is now `Surreal.from(vets).ready()` | 867 | 749 | 181-183 | 179-181 |
| M73 | Roc: lambda in the query, `contact_line` and `ContactLine` removed | 527-531, 879 | 761 | 190-192 | 188-190 |
| M74 | Roc: lambda in the query, `linked_rows` and `LinkedRows` removed | 533-537, 885 | 767 | 194-196 | 192-194 |
| M78 | Roc: `Ledger.visits` is `U64` and `rows.len()` has no `to_i64_wrap` | 500-503, 849 | 413-417, 731 | 166-169 | 164-167 |
| M79 | Roc: `Surreal.Math.mean_dec(rows.map(|v| v.fee))` (was `Math.mean` of `to_f64`) | 503, 849 | 417, 731 | 169 | 167 |
| M81 | Roc: lambda in `totals(..)`, `VisitTotals` removed, count is `U64`, mean is `Math.mean_dec` | 1117-1122, 1134 | 1016 | 394-396 | 410-412 |
| M82 | Roc: lambda `|rows| { visits: rows.len() }`, count is `U64` | 1140 | 1022 | 398-400 | 414-416 |
| M86 | Roc: patch is a lambda, `refill`, `RestockParam` and `refill_param` removed | 544-547, 1003; Clinic:40-42 | Clinic:33-35; 884 | 326-332 | 342-348 |
| M87 | Roc: `set_at` with a lambda patch (was `update_at` with `certified`, removed) | 554-556, 1012 | 889-895 | 334-338 | 350-354 |
| M88 | Roc: lambda patch, `renamed` removed | 558-561, 1021 | 900-906 | 340-344 | 356-360 |
| M89 | Roc: lambda patch, `moved` removed; `no_phone` gives the `Err` its type | 563-566, 1030 | 626-628, 917 | 346-350 | 362-366 |
| M91 | Roc: lambda in `delete_by`; `Clinic.too_old`, `Clinic.seen_before` and `RetentionParam` removed | Clinic:36-38; 1075 | 962 | 380-385 | 396-401 |
| M93 | Roc: 25 refusals (was 24); `check_as_event` is now `check_over_two_fields` and has an update form (M98) | 938-964 | 820-847 | 218-312 | 230-328 |
| M94 | Roc: `Clinic.roc` has 48 lines (was 55); `seen_before` and `too_old` removed, so M91 no longer uses it | Clinic:9-54 | Clinic:9-47 | same SurrealQL as the rows that use them (M39, M43, M57, M65, M66, M86, M91) | same SurrealQL as the rows that use them (M39, M43, M57, M65, M66, M86) |
| M95 | new: Graph path in a projection: `treats.edges_from(v)` gives the edges that leave a vet | - | 1029-1036, 1052 | - | 216-219 |
| M96 | new: Graph path of two edges: `treats.edges_to(p)` back to the lead vet, then `join_map` to `treats.edges_from(..)` out to all patients of that vet | - | 1058-1060 | - | 221-224 |
| M97 | new: Graph path in a filter: `primary_cities(treats.edges_from(v)).contains("Oslo")` | - | 1038-1040, 1066-1067 | - | 226-228 |
| M98 | new: The check over several fields is refused on update too: `update_at` with `{ ..v, fee: 0 }` is rejected by the field ASSERT on `fee` | - | 824 | - | 238-240 |
| M99 | new: A query with no parameters runs with `ready()` | - | 650, 749, 824, 844 | - | 108-110, 179-181, 238-240, 318-320 |
| M100 | new: Counts are `U64`: `rows.len()` is a field value with no conversion, in a projection, a group and the totals | - | 414-417, 719, 725, 1016, 1022 | - | 156-158, 160-162, 164-167, 410-416 |
| M101 | new: Filter that compares a tag union value with a unit arm (`v.outcome != Treated`) | - | 713 | - | 152-154 |
| N07 | Roc: one `definitions` list (the `*_def` values are removed) | 103-126, 306-315 | 104-121, 286-290 | 1-21 | 1-21 |
| N11 | Roc: lambda in the query (`flag_line` is now a reference helper, line 217) | 221-226, 340 | 216-218, 316 | 52-54 | 52-54 |
| N12 | Roc: `Daily.readings` and `fevers` are `U64`, no `to_i64_wrap` | 136-139, 352 | 131-134, 328 | 64-66 | 64-66 |
| N16 | Roc: `select(|r| r)` removed, `ready()` is used | 349 | 325 | 60-62 | 60-62 |
| N21 | Roc: `daily_def` removed, the call is inside `definitions` | 141-146 | 119, 136-138 | 9 | 9 |
| N22 | Roc: `select(|d| { .. })` removed, `ready()` is used | 390-394 | 372-376 | 93-95 | 98-100 |
| N27 | Roc: lambdas in the query (`hot_line` and `kennel_fevers` are now reference helpers, lines 220-224) | 378-383 | 354-359 | 84-86 | 84-86 |
| N28 | Roc: `select(|r| r)` removed | 384-389 | 360-365 | 88-91 | 88-91 |
| N29 | Roc: lambda in the query, `site_lat` and `SiteLat` removed | 274-277, 402 | 384 | 107-109 | 112-114 |
| N34 | Roc: count is `U64` | 418 | 400 | 123 | 128 |
| N38 | Roc: `ready_live(definitions)` (was `live({}, definitions)`) | 441-443, 871 | 423-425, 853 | 138-159 | 143-164 |
| N40 | Roc: `select(|d| { .. })` removed, `ready_live(definitions)` | 450-452, 873 | 432-434, 855 | 185-194 | 190-199 |
| N41 | Roc: `ready_live(definitions)`; `Unattended.carers` is `U64` | 454-466, 874-880 | 436-448, 856-862 | 196-220 | 201-225 |
| N42 | Roc: `ready_live(definitions)` | 468-471, 881-890 | 450-453, 863-872 | 222-236 | 227-241 |
| N43 | Roc: `ready_live(definitions)` | 473-476, 891 | 455-458, 873 | 238-252 | 243-257 |
| N44 | Roc: `ready_live(definitions)`; `Neglected` counts are `U64` | 478-490, 894-903 | 460-472, 876-885 | 298-319 | 303-324 |
| N45 | Roc: `Surreal.from(kennels).select(|k| { .. site: k.site.get().name })` (was `Surreal.from(kennel_reads)` with `k.site.name`) | 492-498, 820-824 | 474-480, 802-806 | 254-274 | 259-279 |
| N46 | Roc: `ready_live(definitions)` | 500-504, 826-830 | 482-486, 808-812 | 276-296 | 281-301 |
| N53 | new: A `U64` above the range of an `int` is sent as a decimal (`18446744073709551615.0dec`) and still compares | - | 366-371 | - | 93-96 |
| N54 | new: Counts are `U64` in the row types of the groups, the read rows and the live results: `Daily.readings`, `Daily.fevers`, `KennelCarers.leads`, `Unattended.carers`, `Neglected.carers` | - | 131-134, 232, 436, 460 | - | 64-66, 126-128, 201-225 |
| N55 | new: A query with no parameters runs with `ready()`, and a watch with `ready_live(definitions)` | - | 312, 372-376, 423-425, 432-434 | - | 48-50, 98-100, 143-164, 190-199 |
| C01 | new: `Surreal.transaction` of a list of writes of one type: two creates that commit, the result is the rows of each in order | - | 373-375, 377-381, 388-390, 895 | - | none |
| C02 | new: `Surreal.transaction` of a list where the second write fails (a twin of `b1` breaks the unique label) | - | 373-375, 383-386, 894 | - | none |
| C03 | new: Migration between two schemas: `Surreal.migration(old, new)` then `m.prepare(DropData)`, run as one transaction | - | 326-327, 392-399, 910-913 | - | none |
| C04 | new: The migration back defines the unique index again and fails on the twin row | - | 397-399, 914 | - | none |

## How to read this file

- Paths are relative to the repository root.
- Roc column: `examples/main.roc`, `examples/monitoring.roc` or `examples/client.roc`, then line numbers. A helper from `examples/clinic/Clinic.roc` is named in full.
- SurrealQL column: line numbers in `main.surql` or `monitoring.surql` (the generated scripts in the same folder as this file). The IDs C01 to C04 have no SurrealQL range: `client.roc` runs against a server and does not print a script.
- Lines that start with `-- roc:`, `-- ordered`, `-- snapshot:`, `-- roles:` and `-- live:` blocks are test directives. They are not features. The line `-- intrinsic: a, b` is a directive too: it names the result columns whose value reads a database-only function (`edges_from`, `edges_to`, `rows()`). The Roc reference of such a column is computed by hand.
- "Test case" column (main only): the write that the database must refuse, as `roc line -> main.surql lines`. It shows the behavior that the feature must enforce. A comparison implementation should show the same refusal.
- Generated script sections of main.surql: schema 1-70 (tables 2-8, fields 9-55, indexes 56-66, events 67-70), seeds 72-100, reads 102-214, graph paths 216-228, refusals 230-328, writes and reads after writes 330-408, totals 410-416.
- Generated script sections of monitoring.surql: schema 1-21, seeds 23-46, queries 48-137, refused point 139-141, live blocks 143-356.
- Several features share one generated statement. Their SurrealQL ranges then overlap. This is expected.
- Category names: row type, schema constraint, link, edge, query-filter, projection, group-aggregate, write, live query, db function, time series, geometry, view, read row, other.

## 1. examples/main.roc (IDs M01 to M101)

### 1.1 Row types

| ID | Category | Description | Roc source | SurrealQL | Test case |
| --- | --- | --- | --- | --- | --- |
| M01 | row type | Nominal row type (`:=`) with derived encoder and parser: Owner, Medication | examples/main.roc:31-34, 48-51 | main.surql:2, 4, 9-17, 26-30 |  |
| M02 | row type | Plain alias record row types: Patient, Visit, Treats, VetRow. Each Roc field type gives a SurrealDB field type | examples/main.roc:42, 65-75, 82-90, 93 | main.surql:18-25, 31-42, 43-50, 51-52 |  |
| M03 | row type | Table handle bound to a table name. One table can have two row types (vets and unchecked_vets, medications and medication_forms) | examples/main.roc:95-118 | main.surql:2-8 |  |
| M04 | row type | Optional field `?:` at top level, nested (zip) and as an optional record (chip) | examples/main.roc:26, 31, 73 | main.surql:12, 15-16, 33-35 |  |
| M05 | row type | Default value in the type (`tags : List(Str) ?? []`, `stock : I32 ?? 0`) | examples/main.roc:31, 48 | main.surql:17, 29 |  |
| M06 | row type | Nested record fields (Address, Contact) with dotted paths | examples/main.roc:26, 36, 42 | main.surql:9-12, 18-20 |  |
| M07 | row type | List of scalars (tags) | examples/main.roc:31 | main.surql:17 |  |
| M08 | row type | List of records (vaccines, items) with `[*]` field paths. The list type is now `array<{..}>` with typed members, with no object key check | examples/main.roc:60, 74, 77, 87 | main.surql:39-41, 44-46 |  |
| M09 | row type | Integer width gives a range ASSERT (U8 gives 0..255, I32 gives its range) | examples/main.roc:41-44, 48, 57, 69, 80 | main.surql:25, 29, 31, 38, 47 | roc 837 -> main.surql:290-292 (u8_range) |
| M10 | row type | Row type with a type parameter (`VetRow(years)`), so that one table has a checked and an unchecked row type | examples/main.roc:42-44, 101-103 | main.surql:25 | roc 837 -> main.surql:290-292 |
| M11 | row type | Decimal and datetime field types (Dec, Surreal.Datetime) | examples/main.roc:42, 55, 70, 86, 89 | main.surql:23, 30, 42, 43, 49 |  |
| M12 | row type | Tag union field with unit arms and payload arms (Species, Specialty, Outcome) as a literal union type | examples/main.roc:39, 57, 80 | main.surql:24, 38, 47 |  |
| M13 | row type | Write-only form row for the same table (MedicationForm leaves out the computed label and the defaulted stock) | examples/main.roc:53-55, 108-109 | main.surql:339 |  |

### 1.2 Links

| ID | Category | Description | Roc source | SurrealQL | Test case |
| --- | --- | --- | --- | --- | --- |
| M14 | link | Top-level `Link(T)` field with an automatic "target exists" assert | examples/main.roc:71, 84-85 | main.surql:37, 48, 50 | roc 839 -> main.surql:298-300 |
| M15 | link | Link in an optional record (chip.implanted_by): assert, index and a delete event on the target table | examples/main.roc:63, 73 | main.surql:33-35, 62, 67 | roc 841 -> main.surql:306-308 |
| M16 | link | Link in a list of records (vaccines[*].vet, items[*].medication): assert, index and delete events | examples/main.roc:60, 74, 77, 87 | main.surql:41, 46, 63, 65, 68-69 | roc 840, 843 -> main.surql:302-304, 314-316 |
| M17 | link | Link in an arm of a tag union (Referred.to): assert inside the union assert and a delete event | examples/main.roc:80 | main.surql:47, 70 | roc 842 -> main.surql:310-312 |
| M18 | link | Optional link to a row of the same table (referred_by) with delete policy Unset | examples/main.roc:31, 354 | main.surql:16 |  |
| M19 | link | Top-level list of links (allergies) with default `[]` and a per-path delete policy Unset (`on_delete_at`) | examples/main.roc:72, 371, 375 | main.surql:32 | roc 926 -> main.surql:368-372 (delete_medication_unsets_allergies) |
| M20 | link | Delete policy Cascade for owner to patient and patient to visit | examples/main.roc:373, 383 | main.surql:37, 48 | roc 941 -> main.surql:380-394 |
| M21 | link | Delete policy Reject for a top-level link and for nested links (the nested ones become events) | examples/main.roc:374, 384 | main.surql:50, 55, 67-70 | roc 844-846 -> main.surql:318-328 |
| M22 | link | Link value built in application code (`Surreal.fetched`, `table.link("id")`), where `get()` reads the row in Roc | examples/main.roc:236-248, 555, 558, 561, 564, 567 | main.surql:89, 94 (record ids in the seeds) |  |

### 1.3 Edges

| ID | Category | Description | Roc source | SurrealQL | Test case |
| --- | --- | --- | --- | --- | --- |
| M23 | edge | Edge table (`Surreal.relation`) with typed from and to links and extra fields | examples/main.roc:93, 117-118 | main.surql:7, 51-52 |  |
| M24 | edge | Edge seeds written with `insert` (INSERT RELATION) | examples/main.roc:328-341, 817 | main.surql:97-100 |  |
| M25 | edge | Check on an edge table field | examples/main.roc:387 | main.surql:52 | roc 836 -> main.surql:286-288 |
| M26 | edge | Unique index over both ends of an edge | examples/main.roc:388 | main.surql:66 | roc 835 -> main.surql:282-284 |
| M27 | edge | Create one edge (RELATE) and read the edges back with both linked names | examples/main.roc:328-329, 451-454, 619-620, 934 | main.surql:374-378 |  |
| M28 | edge | Outgoing traversal: the edges of a vet as a list, with count and filtered count. The projection is now a lambda in the query, and the counts are `U64` | examples/main.roc:719 | main.surql:156-158 |  |
| M29 | edge | Incoming traversal: the edges at a patient, filtered, mapped through the `from` link. The projection is now a lambda in the query | examples/main.roc:725 | main.surql:160-162 |  |

### 1.4 Schema constraints

| ID | Category | Description | Roc source | SurrealQL | Test case |
| --- | --- | --- | --- | --- | --- |
| M30 | schema constraint | Unique index on one field | examples/main.roc:348 | main.surql:56 |  |
| M31 | schema constraint | Unique index on a composite of nested paths | examples/main.roc:349 | main.surql:57 | roc 834 -> main.surql:278-280 |
| M32 | schema constraint | Unique index on a nested path | examples/main.roc:357 | main.surql:59 | roc 832 -> main.surql:270-272 |
| M33 | schema constraint | Unique index on a composite that includes a link | examples/main.roc:367 | main.surql:60 | roc 833 -> main.surql:274-276 |
| M34 | schema constraint | Plain index (non unique), three tables | examples/main.roc:353, 372, 382 | main.surql:58, 61, 64 |  |
| M35 | schema constraint | Assert from a named Roc function that the program also calls (`valid_email`) | examples/main.roc:129-131, 350 | main.surql:13 | roc 825 -> main.surql:242-244 |
| M36 | schema constraint | Assert from a lambda that uses a Roc string method (`starts_with`) | examples/main.roc:359 | main.surql:21 |  |
| M37 | schema constraint | Assert from a SurrealDB function on a nested path (`Text.is_email`) | examples/main.roc:358 | main.surql:19 | roc 826 -> main.surql:246-248 |
| M38 | schema constraint | Assert on each element of a list of scalars | examples/main.roc:351 | main.surql:17 | roc 829 -> main.surql:258-260 |
| M39 | schema constraint | Assert on a field of each record in a list: a lambda and a shared open-row function | examples/main.roc:369, 378; examples/clinic/Clinic.roc:17-19 | main.surql:40, 45 | roc 830-831 -> main.surql:262-268 |
| M40 | schema constraint | Assert on a tag union with `match` (possible_species) | examples/main.roc:173-178, 368 | main.surql:38 | roc 827 -> main.surql:250-252 |
| M41 | schema constraint | Assert on a union with a wildcard arm and a value range (sane_outcome) | examples/main.roc:167-171, 379 | main.surql:47 | roc 828 -> main.surql:254-256 |
| M42 | schema constraint | Check over one field, named, from a function or lambda (becomes a field ASSERT) | examples/main.roc:180-181, 352, 361, 370, 381 | main.surql:14, 23, 42, 43 | roc 822 -> main.surql:230-232 |
| M43 | schema constraint | Check over several fields from a shared open-row function. It now becomes a field ASSERT on `fee` that reads `$this.items`, with no DEFINE EVENT. The write is refused on create and on update | examples/main.roc:380; examples/clinic/Clinic.roc:21-24 | main.surql:43 | roc 823-824 -> main.surql:234-240 |
| M44 | schema constraint | Read-only field | examples/main.roc:360 | main.surql:21 | roc 838 -> main.surql:294-296 |
| M45 | schema constraint | Computed field from a Roc function that the program also calls (`label_of`) | examples/main.roc:133-135, 364 | main.surql:27 |  |
| M46 | schema constraint | Default value from the builder (`.default(.., [])`) | examples/main.roc:371 | main.surql:32 |  |
| M47 | schema constraint | Default value made by a function (`default_by`, ULID key) | examples/main.roc:390, 977-982 | main.surql:53 |  |
| M48 | other | Schema text built from the list of definitions (SCHEMAFULL tables, OVERWRITE, field, index and event statements). The definitions are now one list `definitions`, with no `*_def` values | examples/main.roc:345-391, 633-637 | main.surql:1-70 |  |

### 1.5 Queries: filters and projections

| ID | Category | Description | Roc source | SurrealQL | Test case |
| --- | --- | --- | --- | --- | --- |
| M49 | query-filter | Parameter record with `filter_by` over a lambda `|p, o|` and `prepare({..})` (LET). `CityParam` and `in_city` are removed | examples/main.roc:644 | main.surql:102-106 |  |
| M50 | projection | Projection into a named record type with a Roc function (renames, `record::id(id) AS id`), with `order_by` | examples/main.roc:398-402, 644 | main.surql:106 |  |
| M51 | projection | Optional field with `??` default in a projection | examples/main.roc:400-402, 448-449 | main.surql:106, 360 |  |
| M52 | query-filter | Filter with a lambda that uses list `contains`, run with `ready()` | examples/main.roc:650 | main.surql:108-110 |  |
| M53 | query-filter | Filter on the presence of an optional field (`.?field.is_ok()`) | examples/main.roc:657 | main.surql:112-114 |  |
| M54 | projection | Optional link of the same table read with `.?referred_by.map_ok(|r| r.get().name) ?? "nobody"`. It was a `match`; the SurrealQL is now `referred_by.name ?? 'nobody'` | examples/main.roc:653-657 | main.surql:114 |  |
| M55 | projection | Link read in a projection with `get()` (no FETCH, no JOIN) | examples/main.roc:405-408, 663 | main.surql:116-119 |  |
| M56 | projection | `match` on a tag union in a projection (`species_label`) | examples/main.roc:137-143, 408, 663 | main.surql:119 |  |
| M57 | projection | Reusable ordering fragment over selected rows (`Clinic.by_id`) | examples/clinic/Clinic.roc:45-47; examples/main.roc:663, 701 | main.surql:119, 146 |  |
| M58 | query-filter | Read one record by typed key (`table.at(id)`) | examples/main.roc:120-121, 669 | main.surql:121-123 |  |
| M59 | query-filter | Filter by a key given as parameter (`v.id == p.key`) | examples/main.roc:675 | main.surql:125-128 |  |
| M60 | query-filter | `match` in a filter that reads the payload of a union arm and has a wildcard arm (`wide_wings`) | examples/main.roc:152-156, 681 | main.surql:130-132 |  |
| M61 | projection | Scalar projection `select_value`, also with `order_by` on the value | examples/main.roc:681, 707, 743 | main.surql:132, 150, 174-177 |  |
| M62 | projection | Two `.?chip.map_ok(..) ??` calls on one optional record (chip code and chip vet name through a link). They were two `match` calls; the query is now a lambda | examples/main.roc:684-688 | main.surql:134-136 |  |
| M63 | projection | Map over a list of records and read a link in each (`vaccines.map(|v| v.vet.get().name)`), in a lambda of the query | examples/main.roc:691-695 | main.surql:140 |  |
| M64 | query-filter | Filter with `any` over a list and comparison of a link id with a typed id (`v.vet.id() == ruth_id`) | examples/main.roc:410-411, 695 | main.surql:138-140 |  |
| M65 | query-filter | Query fragment (`filter_by`) over an open row with a parameter record (`Clinic.recent`, `Clinic.seen_since`) | examples/clinic/Clinic.roc:26-31, 41-43; examples/main.roc:701 | main.surql:142-146 |  |
| M66 | projection | Computation over linked rows in a projection (`Clinic.bill`: decimal cast, link read inside a list `map`, `sum`), in a lambda of the query | examples/clinic/Clinic.roc:9-15; examples/main.roc:701 | main.surql:146 |  |
| M67 | query-filter | Database clock in a filter (`Time.now()`) | examples/main.roc:707 | main.surql:148-150 |  |
| M68 | projection | `match` whose arm reads a link (`Referred(r) => r.to.get().name`), called from a lambda of the query | examples/main.roc:145-150, 713 | main.surql:154 |  |
| M69 | query-filter | removed: the `match` with a wildcard arm as a filter (`needs_attention`). The function and its two `expect` lines are gone. The follow_ups query filters with `v.outcome != Treated` (M101). A `match` with a wildcard arm in a filter stays in `wide_wings` (M60) | removed | removed (the follow_ups statement is main.surql:152-154, see M101) |  |
| M70 | projection | Whole row as the result: `ready()` on a table query, with no `select` | examples/main.roc:749 | main.surql:179-181 |  |
| M71 | projection | Order by with limit (top N) | examples/main.roc:737 | main.surql:169-172 |  |
| M72 | projection | Pagination: `order_by`, `start`, `limit` | examples/main.roc:755 | main.surql:183-186 |  |
| M73 | projection | Fields of linked rows with no FETCH (`p.owner.get().address.city`, list map over links), in a lambda of the query | examples/main.roc:761 | main.surql:188-190 |  |
| M74 | projection | Whole linked rows as values (owner row, list of vet rows), in a lambda of the query | examples/main.roc:767 | main.surql:192-194 |  |
| M75 | query-filter | Value captured at run time, bound as a LET parameter (`bind_captured`, `select_where`) | examples/main.roc:419-422, 773 | main.surql:196-199 |  |
| M76 | query-filter | Captured list of records with optional fields, matched with `contains` | examples/main.roc:424-428, 779 | main.surql:201-204 |  |
| M77 | query-filter | Captured record compared with `==`, optional field present or absent | examples/main.roc:430-434, 785, 791 | main.surql:206-214 |  |

### 1.6 Group and aggregate

| ID | Category | Description | Roc source | SurrealQL | Test case |
| --- | --- | --- | --- | --- | --- |
| M78 | group-aggregate | GROUP BY a key read through a link, with count and sum (`group_by(|v| v.vet.get().name).aggregate(..)`). The count is `U64` | examples/main.roc:413-417, 731 | main.surql:164-167 |  |
| M79 | group-aggregate | Statistic over a group: `Math.mean_dec` over a list of decimals. SurrealQL still casts to float | examples/main.roc:417, 731 | main.surql:167 |  |
| M80 | group-aggregate | Order by an aggregate value, descending, with limit | examples/main.roc:731 | main.surql:167 |  |
| M81 | group-aggregate | Totals of all matching rows as one row (GROUP ALL): count, sum, mean. The row is a lambda in the query | examples/main.roc:1016 | main.surql:410-412 |  |
| M82 | group-aggregate | Totals of no rows: one row with count 0 | examples/main.roc:1022 | main.surql:414-416 |  |

### 1.7 Writes

| ID | Category | Description | Roc source | SurrealQL | Test case |
| --- | --- | --- | --- | --- | --- |
| M83 | write | Seed rows with the derived encoder: `insert` in a transaction (INSERT INTO and INSERT RELATION) | examples/main.roc:810-818 | main.surql:72-100 |  |
| M84 | write | Create one row (CREATE ... CONTENT) | examples/main.roc:610-611, 871 | main.surql:330-334 |  |
| M85 | write | Create through a form row that leaves out computed and defaulted fields | examples/main.roc:53-55, 613-614, 877 | main.surql:336-340 |  |
| M86 | write | Update by predicate with a parameter record and a patch lambda (`update_by(Clinic.low_stock, |p, m| ..)`) | examples/clinic/Clinic.roc:33-35; examples/main.roc:884 | main.surql:342-348 |  |
| M87 | write | Update by key with a patch of only the listed fields: arithmetic and a new union value (`set_at`). It was `update_at` with a whole-row function | examples/main.roc:889-895 | main.surql:350-354 |  |
| M88 | write | Update with a spread over optional fields (`{ ..o, name: ".." }` sets only `name`), in a lambda | examples/main.roc:900-906 | main.surql:356-360 |  |
| M89 | write | Patch of only the listed fields in a lambda; an optional field is removed with `Err` (`set_at`, `no_phone`) | examples/main.roc:626-628, 917 | main.surql:362-366 |  |
| M90 | write | Delete by key | examples/main.roc:941 | main.surql:380-384 |  |
| M91 | write | Delete by predicate with a parameter (retention), in a lambda `|p, v| v.seen < p.before` | examples/main.roc:962 | main.surql:396-401 |  |
| M92 | write | Create rows without a key, the server makes the key (`insert_new`, open-row projection over keyed and keyless rows) | examples/main.roc:977-992, 970 | main.surql:403-408 |  |
| M93 | write | Refused writes: each constraint refuses a bad row and the error names the field. The refused rows are given in the Test case column of each constraint row | examples/main.roc:820-847 | main.surql:230-328 | all |

### 1.8 Other

| ID | Category | Description | Roc source | SurrealQL | Test case |
| --- | --- | --- | --- | --- | --- |
| M94 | other | Open-row helper functions and query fragments that serve several tables and rows (any record that has the fields) | examples/clinic/Clinic.roc:9-47 | same SurrealQL as the rows that use them (M39, M43, M57, M65, M66, M86) |  |

### 1.9 Added since catalog 1

| ID | Category | Description | Roc source | SurrealQL | Test case |
| --- | --- | --- | --- | --- | --- |
| M95 | edge | Graph path in a projection: `treats.edges_from(v)` gives the edges that leave a vet. A filter of the edges, a hop to the patient and a link to the owner make `->treats[WHERE primary]->patient.owner.name`. The function takes the edges, so Roc runs it over the seed edges too. An intrinsic column (`-- intrinsic: owners`) | examples/main.roc:1029-1036, 1052 | main.surql:216-219 |  |
| M96 | edge | Graph path of two edges: `treats.edges_to(p)` back to the lead vet, then `join_map` to `treats.edges_from(..)` out to all patients of that vet. An intrinsic column | examples/main.roc:1058-1060 | main.surql:221-224 |  |
| M97 | edge | Graph path in a filter: `primary_cities(treats.edges_from(v)).contains("Oslo")` | examples/main.roc:1038-1040, 1066-1067 | main.surql:226-228 |  |
| M98 | schema constraint | The check over several fields is refused on update too: `update_at` with `{ ..v, fee: 0 }` is rejected by the field ASSERT on `fee` | examples/main.roc:824 | main.surql:238-240 | roc 824 -> main.surql:238-240 |
| M99 | other | A query with no parameters runs with `ready()`. A query with parameters keeps `prepare({..})` (M49). `ready()` also ends an update or a delete by key | examples/main.roc:650, 749, 824, 844 | main.surql:108-110, 179-181, 238-240, 318-320 |  |
| M100 | projection | Counts are `U64`: `rows.len()` is a field value with no conversion, in a projection, a group and the totals | examples/main.roc:414-417, 719, 725, 1016, 1022 | main.surql:156-158, 160-162, 164-167, 410-416 |  |
| M101 | query-filter | Filter that compares a tag union value with a unit arm (`v.outcome != Treated`). This replaces the `match` of `needs_attention` (M69) | examples/main.roc:713 | main.surql:152-154 |  |

## 2. examples/monitoring.roc (IDs N01 to N55)

### 2.1 Row types, schema, links, edges

| ID | Category | Description | Roc source | SurrealQL |
| --- | --- | --- | --- | --- |
| N01 | geometry | Point and Polygon fields; a validity assert is added. A point out of range is refused (test: roc 414-418 -> monitoring.surql:139-141) | examples/monitoring.roc:43 | monitoring.surql:10-11 |
| N02 | geometry | Geometry values made in app code (`Surreal.point`, ring of a polygon, `rectangle` helper) and seeded | examples/monitoring.roc:142-156, 301 | monitoring.surql:23-26 |
| N03 | link | Link in a row (kennel.site), default Reject policy and exists assert | examples/monitoring.roc:45, 158-162 | monitoring.surql:13-14, 28-31 |
| N04 | time series | Record key as a time series key over a typed id (`TimeKey(Id(Kennel))`, key type `[record<kennel>, datetime]`) | examples/monitoring.roc:47 | monitoring.surql:18 |
| N05 | time series | Seeds with composed keys (`time_key(id, datetime)`); the computed field is given a placeholder | examples/monitoring.roc:180-182, 188-204, 305 | monitoring.surql:43-46 |
| N06 | edge | Two edge tables between the same pair of tables (cares_for with a flag, checks with a note) | examples/monitoring.roc:52, 55, 69-73, 113-114, 164-172 | monitoring.surql:6-7, 16-17, 33-41 |
| N07 | other | Schema text from a list of definitions: functions, tables, view, read row check. The list is the one `definitions` value | examples/monitoring.roc:104-121, 286-290 | monitoring.surql:1-21 |

### 2.2 Database functions

| ID | Category | Description | Roc source | SurrealQL |
| --- | --- | --- | --- | --- |
| N08 | db function | Roc function becomes a database function (`db_fn`, `Surreal.function`) and Roc can still call it (`call2`) | examples/monitoring.roc:91-100, 109 | monitoring.surql:2 |
| N09 | db function | Database function in a filter, run with `ready()` | examples/monitoring.roc:312 | monitoring.surql:48-50 |
| N10 | db function | Database function in a computed field | examples/monitoring.roc:116 | monitoring.surql:19 |
| N11 | db function | Database function in a projection (with a literal argument), in a lambda of the query | examples/monitoring.roc:216-218, 316 | monitoring.surql:52-54 |
| N12 | db function | Database function inside an aggregate (count of calls per group). The counts are `U64` | examples/monitoring.roc:131-134, 328 | monitoring.surql:64-66 |

### 2.3 Time series

| ID | Category | Description | Roc source | SurrealQL |
| --- | --- | --- | --- | --- |
| N13 | time series | Read the parts of a key in a projection (`id.series()`, `id.time()`) | examples/monitoring.roc:208-211, 312 | monitoring.surql:48-50 |
| N14 | time series | Whole key as a projected value (the array `[kennel, time]`) | examples/monitoring.roc:216-218, 316 | monitoring.surql:52-54 |
| N15 | time series | Range query between two times for one series (lower bound inclusive, upper bound exclusive) | examples/monitoring.roc:280-284, 319 | monitoring.surql:56-58 |
| N16 | time series | Range query that returns whole rows: `ready()` after `between`, with no `select` | examples/monitoring.roc:325 | monitoring.surql:60-62 |
| N17 | time series | Bucket by day with `Time.floor` and `Time.days`, from the key time | examples/monitoring.roc:125-129 | monitoring.surql:66 |
| N18 | time series | Delete by key time with a parameter (retention) | examples/monitoring.roc:379-383 | monitoring.surql:106-110 |
| N19 | time series | Changefeed with a duration | examples/monitoring.roc:117 | monitoring.surql:8 |

### 2.4 Views, groups and result-row filters

| ID | Category | Description | Roc source | SurrealQL |
| --- | --- | --- | --- | --- |
| N20 | group-aggregate | GROUP BY two derived keys (kennel and day) with count and a filtered count | examples/monitoring.roc:125-134, 328 | monitoring.surql:64-66 |
| N21 | view | View defined from a grouped query (`define_as`), as an entry of `definitions` | examples/monitoring.roc:119, 136-138 | monitoring.surql:9 |
| N22 | view | Read the view as a table: `ready()` on the view, with no `select` | examples/monitoring.roc:372-376 | monitoring.surql:98-100 |
| N23 | query-filter | Filter on result rows after a projection (same WHERE, reads the projected fields) | examples/monitoring.roc:329-335 | monitoring.surql:68-70 |
| N24 | query-filter | Filter on groups (HAVING) as a subquery | examples/monitoring.roc:336-342 | monitoring.surql:72-74 |
| N25 | query-filter | Filter after order and limit (subquery keeps the order) | examples/monitoring.roc:343-348 | monitoring.surql:76-78 |
| N26 | query-filter | Same, on a scalar projection | examples/monitoring.roc:349-353 | monitoring.surql:80-82 |
| N27 | group-aggregate | Result rows of a projection as rows of a new query (`.query()`), then filter, group, aggregate in one SELECT. The projection and the aggregate are now lambdas in the query | examples/monitoring.roc:354-359 | monitoring.surql:84-86 |
| N28 | query-filter | Parameter in a filter over a subquery, with no `select(|r| r)` at the end | examples/monitoring.roc:360-365 | monitoring.surql:88-91 |

### 2.5 Geometry queries

| ID | Category | Description | Roc source | SurrealQL |
| --- | --- | --- | --- | --- |
| N29 | geometry | Read a coordinate of a point (`location.lat()`), in a lambda of the query | examples/monitoring.roc:384 | monitoring.surql:112-114 |
| N30 | geometry | Area contains a point given as parameter (`Geo.inside`) | examples/monitoring.roc:255-257, 386-390 | monitoring.surql:116-119 |
| N31 | geometry | Distance below a limit (`Geo.distance`), point as parameter | examples/monitoring.roc:391-395 | monitoring.surql:121-124 |

### 2.6 Read rows and rows of other tables

| ID | Category | Description | Roc source | SurrealQL |
| --- | --- | --- | --- | --- |
| N32 | read row | Read row with a `Linked` field: read the site name with no `get()` | examples/monitoring.roc:78-84, 396-400 | monitoring.surql:126-128 |
| N33 | read row | Read row with an `In` field: the edges at a row, with each carer as a whole linked row | examples/monitoring.roc:75-76, 81, 400 | monitoring.surql:126-128 |
| N34 | read row | Filter and count over the `In` list (`keep_if`, `len`). The count is `U64` | examples/monitoring.roc:400 | monitoring.surql:128 |
| N35 | read row | Schema check that the read row agrees with the stored row (`define_read`, the last entry of `definitions`) | examples/monitoring.roc:120 | none (a schema error if it does not agree) |
| N36 | other | Rows of another table in a clause: correlated count (`vitals.rows()`), with a Roc function that the program also calls (`readings_of`). An intrinsic column (`-- intrinsic: readings`) | examples/monitoring.roc:247-249, 403-408 | monitoring.surql:130-133 |
| N37 | query-filter | Semi join: filter with `any` over the rows of another table (`has_fever`) | examples/monitoring.roc:251-253, 409-413 | monitoring.surql:135-137 |

### 2.7 Live queries

Each live block has one or more LIVE statements and one snapshot SELECT. The `-- roles:` line shows the statements (node, edge, read, raw, diff).

| ID | Category | Description | Roc source | SurrealQL |
| --- | --- | --- | --- | --- |
| N38 | live query | Live filter with a database function (roles: node), started with `ready_live(definitions)` | examples/monitoring.roc:423-425, 853 | monitoring.surql:143-164 |
| N39 | live query | Live filter with a parameter fixed when the watch starts (`live({ limit }, definitions)`) | examples/monitoring.roc:427-430, 854 | monitoring.surql:166-188 |
| N40 | live query | Live on a view, with `ready_live(definitions)` and no `select` | examples/monitoring.roc:432-434, 855 | monitoring.surql:190-199 |
| N41 | live query | Kennels with no carer: `incoming` edges, filter and projection on a tuple (roles: node, edge) | examples/monitoring.roc:436-448, 856-862 | monitoring.surql:201-225 |
| N42 | live query | Same watch through the read row `In` field (roles: node, edge) | examples/monitoring.roc:450-453, 863-872 | monitoring.surql:227-241 |
| N43 | live query | Live filter that reads the rows of another table (roles: node, read) | examples/monitoring.roc:455-458, 873 | monitoring.surql:243-257 |
| N44 | live query | Live on two edge tables (`and_incoming`, roles: node, edge, edge) | examples/monitoring.roc:460-472, 876-885 | monitoring.surql:303-324 |
| N45 | live query | Live projection through a link read with `get()` on the kennel table; a write to the linked site reaches the kennels (roles: node, read). It no longer uses the `Linked` read row | examples/monitoring.roc:474-480, 802-806 | monitoring.surql:259-279 |
| N46 | live query | Live filter on a link read with `get()`; a write to the linked site makes kennels enter or leave (roles: node, read) | examples/monitoring.roc:482-486, 808-812 | monitoring.surql:281-301 |
| N47 | live query | Raw live events (escape hatch, roles: raw) | examples/monitoring.roc:488-490, 886-893 | monitoring.surql:326-345 |
| N48 | live query | Live diff of patches on a table (escape hatch, roles: diff) | examples/monitoring.roc:492-494, 894-897 | monitoring.surql:347-356 |

### 2.8 Writes that drive the live blocks

| ID | Category | Description | Roc source | SurrealQL |
| --- | --- | --- | --- | --- |
| N49 | write | Typed writes from edit values (Create, Replace old to new, Delete) on node tables, with a time series key | examples/monitoring.roc:505-513, 528-533 | monitoring.surql:149-164, 173-188, 196-199, 330-345, 351-356 |
| N50 | write | Same on edge tables (create and delete an edge) | examples/monitoring.roc:573-577, 593-608, 613-626 | monitoring.surql:208-225, 234-241 |
| N51 | write | Delete of a node row that also deletes its edges (carer, kennel) | examples/monitoring.roc:604, 607, 625 | monitoring.surql:220-225, 240-241, 317-324 |
| N52 | write | Update of a linked row (site rename) and a write that changes nothing | examples/monitoring.roc:762-782 | monitoring.surql:266-279, 288-301 |

### 2.9 Added since catalog 1

| ID | Category | Description | Roc source | SurrealQL |
| --- | --- | --- | --- | --- |
| N53 | query-filter | A `U64` above the range of an `int` is sent as a decimal (`18446744073709551615.0dec`) and still compares. The query returns no rows | examples/monitoring.roc:366-371 | monitoring.surql:93-96 |
| N54 | projection | Counts are `U64` in the row types of the groups, the read rows and the live results: `Daily.readings`, `Daily.fevers`, `KennelCarers.leads`, `Unattended.carers`, `Neglected.carers`. No `to_i64_wrap` | examples/monitoring.roc:131-134, 232, 436, 460 | monitoring.surql:64-66, 126-128, 201-225 |
| N55 | other | A query with no parameters runs with `ready()`, and a watch with `ready_live(definitions)`. A query with parameters keeps `prepare({..})` (N28) and `live({..}, definitions)` (N39) | examples/monitoring.roc:312, 372-376, 423-425, 432-434 | monitoring.surql:48-50, 98-100, 143-164, 190-199 |

## 2b. examples/client.roc (IDs C01 to C04)

These features appear only in `client.roc`. `client.roc` sends statements to a server and checks the replies, so it has no range in `main.surql` or `monitoring.surql`. The checks are in `run!` of `client.roc`. The fixtures `tests/fixtures/http/*.cbor` and `tests/fixtures/queries/*.cbor` hold the recorded replies of `twins_in_list`, `spares_in_list`, `unpin_labels` and `pin_labels_again`.

| ID | Category | Description | Roc source | SurrealQL |
| --- | --- | --- | --- | --- |
| C01 | write | `Surreal.transaction` of a list of writes of one type: two creates that commit, the result is the rows of each in order | examples/client.roc:373-375, 377-381, 388-390, 895 | none (client.roc runs against a server, no script line) |
| C02 | write | `Surreal.transaction` of a list where the second write fails (a twin of `b1` breaks the unique label). The first write is rolled back and the error names the part (`aborted(1, ..)`) | examples/client.roc:373-375, 383-386, 894 | none |
| C03 | other | Migration between two schemas: `Surreal.migration(old, new)` then `m.prepare(DropData)`, run as one transaction. The new schema has no unique label, so a twin of `b1` can be written after it | examples/client.roc:326-327, 392-399, 910-913 | none |
| C04 | other | The migration back defines the unique index again and fails on the twin row. The migration is one transaction, so nothing of it stays and the error names `Unique` on `bin.label` | examples/client.roc:397-399, 914 | none |
## 3. Test harness line ranges

Type codes: H is harness only (exclude from LOC). F is fixture or scenario data that every implementation also needs (count it apart from the ORM code). M is mixed: only the named part is harness.

### 3.1 examples/main.roc

| Lines | Type | Reason |
| --- | --- | --- |
| 1-17 | H | Header comment |
| 158-162 | H | `expect` tests of Roc helpers |
| 185-189 | F | `at` helper that parses seed datetimes |
| 191-341 | F | Seed rows: vets, owners, medications, patients, visits, edges (needed by every implementation). The link helpers 236-248 are also feature code (M22) |
| 456-504 | H | Reference results for `-- roc:` lines: `edges_of_vet`, `edges_of_patient`, `visit_names`, `ledger_in_memory`, `referral_line`, `chip_line`, `visit_line`, `expect` lines, `visit_of` |
| 508-513 | F | Bad rows for refusal tests: `free_medication`, `zero_doses` |
| 515-521 | H | `expect` tests of constraints |
| 523-576 | F | Bad rows for refusal tests (one for each constraint) |
| 578-582 | H | `expect` tests of constraints |
| 586-608 | H | `block`, `plain`, `then_read`, `rejects`: script assembly |
| 610-620 | F | Inputs of the writes: pip, meloxicam_form, meloxicam, new_edge |
| 622-624 | H | `lena_moved`, the expected row after `move_owner` |
| 626-628 | F | `no_phone`: the removed field of the `move_owner` patch (M89) |
| 630-631 | F | `cutoff`: input of the retention write |
| 633-637 | M | `schema_block`: the `Surreal.schema([..])` call is feature (M48), the `-- schema` header is harness |
| 639-794 | M | `reads`: in each `block(` call only the prepared-query argument is feature code. The lines `block(`, the header string, the flags list, `Surreal.Mirror.literal(..)` and `),` are harness |
| 796-805 | F | Captured address inputs for M76 and M77 |
| 807-808 | H | `script`: joins the blocks |
| 810-818 | M | `seeds`: the `insert(..)` argument is feature (M83), the `plain(..)` wrapper is harness |
| 820-847 | M | `refusals`: the write argument is feature (M93), the `rejects(..)` wrapper and the error text are harness |
| 849-864 | H | Reference state after the writes: `patients_now`, `medications_now`, `without_aspirin`, `owned_by_noor`, `visits_now`, and the `expect` line 861 |
| 866-973 | M | `writes`: only the prepared write and read arguments are feature code. `block(`, header, flags, `then_read(` and `Surreal.Mirror.literal(..)` are harness |
| 994-997 | H | `main!` prints the script |
| 999-1010 | H | Reference of the totals: `visit_totals` (a copy of the lambda of M81 for the Mirror) and the comments about it |
| 1011-1025 | M | `totals_blocks`: same rule as `reads` |
| 1042-1044 | H | `lead_patients_in_memory`: Roc reference of M96 |
| 1046-1070 | M | `path_blocks`: same rule as `reads`. The comment lines inside the blocks (1058-1059, 1066) explain the feature |

Feature code that sits among the harness (do not exclude): 977-992 (Note, notes, new_notes, note_line), 1029-1040 (`owners_of_primary`, `primary_cities` and their comments), 398-454 (query functions and line types, including the captured queries 419-434), 129-156 and 164-181 (shared functions), 345-391 (definitions), 24-121 (rows and tables).

### 3.2 examples/clinic/Clinic.roc

All 48 lines are feature code (shared functions and fragments). No harness.

### 3.3 examples/monitoring.roc

| Lines | Type | Reason |
| --- | --- | --- |
| 1-37 | H | Header comment |
| 98-100 | H | `expect` tests of `fever_fn` |
| 150-178, 188-204 | F | Seed rows and the `moment` helper |
| 184-186 | H | `stored`: runs the computed field in Roc for the reference |
| 226-228 | H | `fastest`: reference helper |
| 232-245 | H | `KennelCarers`, `kennel_carers`: reference |
| 259-264 | H | `block`: script assembly |
| 266-271 | H | `rollup`: reference of the daily groups |
| 273-278 | H | `then_read`: script assembly |
| 280-284 | F | `day_start`, `day_end` inputs of N15 and N18 |
| 286-297 | M | `schema_block` and `seed`: the schema call is feature (N07), the header text and wrappers are harness |
| 299-306 | M | `seed_blocks`: the `insert(..)` arguments are feature, the `seed(..)` wrapper is harness |
| 308-419 | M | `queries`: same rule as `reads` in main.roc. Line 378 is a raw SurrealQL check of the changefeed (harness). Lines 414-418 wrap the refused point (feature argument at 415, the comment at 414 explains it) |
| 496-499 | H | `kept_vitals` reference state |
| 501-513 | F | `vital_edits`: the write scenario of the live blocks of readings |
| 515-541 | H | `vital_snapshot`, `vital_notices`, `text_of`, `vital_writes`, `live_block`: Mirror and script assembly |
| 543-562 | H | `late_fever` (F), `daily_notices`, `daily_snapshot`: Mirror references |
| 564-577 | F | Kennel and edge fixtures for the unattended scenario |
| 579-608 | M | `kennel_step`, `care_step` and `notices:` fields are harness (Mirror). The `write:` fields and `# case:` comments are scenario data (F) |
| 610-626 | M | Same rule: `west`, `ida_west` fixtures (F), `notices:` harness |
| 628-668 | M | Fevered kennels scenario: `north`, `north_wing`, `fevered_edits`, `south_fever` (F). Snapshot, `fever_reach`, notices (H). `fevered_kennels_writes` (F) |
| 670-716 | M | Neglected scenario: fixtures and `write:` fields (F). Mirror closures and `neglected_snapshot` (H) |
| 718-720 | H | `both_seen`: Mirror helper |
| 722-749 | M | `oslo`, `bergen`, `trondheim` fixtures (F, 722-736). `KennelAt` and `kennels_at` (H, 738-749) |
| 751-800 | M | `site_step`, `site_snapshot`, `site_notices`, `site_label`, `is_oslo`, `kennel_label`: Mirror (H). `site_writes` 762-782 is scenario data (F) |
| 802-812 | M | `kennel_sites_block`, `oslo_kennels_block`: wrappers and Mirror calls (H). The write list is `site_writes` (F) |
| 814-832 | H | `both`, `unattended_notices`, `unattended_snapshot`: Mirror references |
| 834-845 | M | `patch_edits` 834-842 (F) and `patches_literal` 844-845 (H, hand-written expected patches) |
| 847-849 | H | `is_fever`: keep function for the Mirror |
| 851-898 | M | `live_blocks`: the watch values (`fevered`, `hotter_than(..)`, ...) are feature. `live_block(..)` wrapper, snapshots, notices, `Mirror.events` are harness |
| 900-906 | H | `script` and `main!` |

Feature code that sits among the harness (do not exclude): 43-96 (rows, tables, read rows, ids, `fever`, `fever_fn`), 104-138 (definitions, `day_of`, view), 142-148 (`rectangle`), 180-182 (`reading`), 208-224 (query line types and functions), 247-257 (`readings_of`, `has_fever`, `here`), 423-494 (watch definitions, `no_carer`, `no_one`, line functions).

## 4. Roc-specific benefits to keep in mind

| No | Benefit | Related IDs |
| --- | --- | --- |
| 1 | One Roc function is the DB constraint and the application code (`valid_email`, `named`, `sane_outcome`, `fee_covers_items`) | M35, M40, M41, M43 |
| 2 | One Roc function is the projection, the computed field, the DB function and the in-memory code (`label_of`, `fever`, `Clinic.bill`, `owners_of_primary`) | M45, M66, M95, N08-N12 |
| 3 | The row types are the seed data, the function arguments and the test inputs. The encoder and parser are derived | M01, M83 |
| 4 | Defaults, numeric ranges and counts are part of the Roc type (`?? []`, `U8`, `I32`, `U64`). A `U64` above the range of an `int` is sent as a decimal | M05, M09, M100, N53, N54 |
| 5 | Open-row helpers and query fragments (`Clinic.*`) work over any row that has the fields, and give the same SurrealQL on each row | M39, M43, M57, M65, M94 |
| 6 | Tag unions with `match` become literal union types and IF chains. Roc checks that the `match` is exhaustive. A unit arm also compares with `!=` | M12, M40, M56, M60, M101 |
| 7 | A link has two meanings: `get()` in a clause is a traversal, in the program it reads the row (`Surreal.fetched`). A graph path is an edge list in a clause: `edges_from(v)` and `edges_to(p)`, with `keep_if`, `map` and `join_map` | M22, M55, M95-M97 |
| 8 | Compile-time checks: a patch field is checked against the row, the order of clauses after `select` is typed, an edge table in the wrong direction is a type error, the edge list of `edges_from` needs an edge table that leaves the row | M89, M87, M72, M28, M95 |
| 9 | Typed results: a prepared query reads its reply as the Roc type of the projection. `ready()` needs no parameter record, and `select` is optional for whole rows | all queries, M99, M70 |
| 10 | The Mirror predicts the live notices, snapshots and raw events from the same Roc functions. The reference result of each query (`-- roc:`) comes from the same functions over the same rows | N38-N48 |
| 11 | Read rows are checked against the stored row at schema time (`define_read`) and give link and edge reads with no `get()` or `incoming` | N32-N35 |
| 12 | Limits that a comparison must note: `Geo.inside`, `Geo.distance` and `Text.is_email` have no Roc body (database only); `edges_from`, `edges_to` and `rows()` are database only too (the `-- intrinsic:` columns, with a hand-made Roc reference); the changefeed check uses raw SurrealQL; an optional field patch with `..` is a switch on presence | N30, N31, M37, M95-M97, N36, N19 |
| 13 | One transaction for a list of writes, and a migration as one transaction: both are all or none. They are shown in `client.roc` only | C01-C04 |
