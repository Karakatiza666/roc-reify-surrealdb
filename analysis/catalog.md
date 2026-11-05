# Feature catalog: roc-reify-surrealdb examples/main.roc and examples/monitoring.roc

Purpose: shared feature IDs for the ORM comparison (hand-written SurrealQL, Rust surql_orm, Drizzle).

## How to read this file

- Paths are relative to the repository root.
- Roc column: `examples/main.roc` or `examples/monitoring.roc`, then line numbers. A helper from `examples/clinic/Clinic.roc` is named in full.
- SurrealQL column: line numbers in `main.surql` or `monitoring.surql` (the generated scripts in the same folder as this file).
- Lines that start with `-- roc:`, `-- ordered`, `-- snapshot:`, `-- roles:` and `-- live:` blocks are test directives. They are not features.
- "Test case" column (main only): the write that the database must refuse, as `roc line -> main.surql lines`. It shows the behavior that the feature must enforce. A comparison implementation should show the same refusal.
- Generated script sections of main.surql: schema 1-72 (tables 2-8, fields 9-56, indexes 57-67, events 68-72), seeds 74-102, reads 104-216, refusals 218-312, writes and reads after writes 314-392, totals 394-400.
- Generated script sections of monitoring.surql: schema 1-21, seeds 23-46, queries 48-136, live blocks 138-351.
- Several features share one generated statement. Their SurrealQL ranges then overlap. This is expected.
- Category names: row type, schema constraint, link, edge, query-filter, projection, group-aggregate, write, live query, db function, time series, geometry, view, read row, other.

## 1. examples/main.roc (IDs M01 to M94)

### 1.1 Row types

| ID | Category | Description | Roc source | SurrealQL | Test case |
| --- | --- | --- | --- | --- | --- |
| M01 | row type | Nominal row type (`:=`) with derived encoder and parser: Owner, Medication | examples/main.roc:31-34, 48-51 | main.surql:2, 4, 9-17, 26-30 | |
| M02 | row type | Plain alias record row types: Patient, Visit, Treats, VetRow. Each Roc field type gives a SurrealDB field type | examples/main.roc:42, 65-75, 82-90, 93 | main.surql:18-25, 31-43, 44-51, 52-53 | |
| M03 | row type | Table handle bound to a table name. One table can have two row types (vets and unchecked_vets, medications and medication_forms) | examples/main.roc:95-118 | main.surql:2-8 | |
| M04 | row type | Optional field `?:` at top level, nested (zip) and as an optional record (chip) | examples/main.roc:26, 31, 73 | main.surql:12, 15-16, 33-35 | |
| M05 | row type | Default value in the type (`tags : List(Str) ?? []`, `stock : I32 ?? 0`) | examples/main.roc:31, 48 | main.surql:17, 29 | |
| M06 | row type | Nested record fields (Address, Contact) with dotted paths | examples/main.roc:26, 36, 42 | main.surql:9-12, 18-20 | |
| M07 | row type | List of scalars (tags) | examples/main.roc:31 | main.surql:17 | |
| M08 | row type | List of records (vaccines, items) with `[*]` field paths and an object key check | examples/main.roc:60, 74, 77, 87 | main.surql:39-42, 45-47 | |
| M09 | row type | Integer width gives a range ASSERT (U8 gives 0..255, I32 gives its range) | examples/main.roc:41-44, 48, 57, 69, 80 | main.surql:25, 29, 31, 38, 48 | roc 954 -> main.surql:274-276 (u8_range) |
| M10 | row type | Row type with a type parameter (`VetRow(years)`), so that one table has a checked and an unchecked row type | examples/main.roc:42-44, 101-103 | main.surql:25 | roc 954 -> main.surql:274-276 |
| M11 | row type | Decimal and datetime field types (Dec, Surreal.Datetime) | examples/main.roc:42, 55, 70, 86, 89 | main.surql:23, 30, 43, 44, 50 | |
| M12 | row type | Tag union field with unit arms and payload arms (Species, Specialty, Outcome) as a literal union type | examples/main.roc:39, 57, 80 | main.surql:24, 38, 48 | |
| M13 | row type | Write-only form row for the same table (MedicationForm leaves out the computed label and the defaulted stock) | examples/main.roc:53-55, 108-109 | main.surql:323 | |

### 1.2 Links

| ID | Category | Description | Roc source | SurrealQL | Test case |
| --- | --- | --- | --- | --- | --- |
| M14 | link | Top-level `Link(T)` field with an automatic "target exists" assert | examples/main.roc:71, 84-85 | main.surql:37, 49, 51 | roc 956 -> main.surql:282-284 |
| M15 | link | Link in an optional record (chip.implanted_by): assert, index and a delete event on the target table | examples/main.roc:63, 73 | main.surql:33-35, 63, 69 | roc 958 -> main.surql:290-292 |
| M16 | link | Link in a list of records (vaccines[*].vet, items[*].medication): assert, index and delete events | examples/main.roc:60, 74, 77, 87 | main.surql:42, 47, 64, 66, 70-71 | roc 957, 960 -> main.surql:286-288, 298-300 |
| M17 | link | Link in an arm of a tag union (Referred.to): assert inside the union assert and a delete event | examples/main.roc:80 | main.surql:48, 72 | roc 959 -> main.surql:294-296 |
| M18 | link | Optional link to a row of the same table (referred_by) with delete policy Unset | examples/main.roc:31, 362 | main.surql:16 | |
| M19 | link | Top-level list of links (allergies) with default `[]` and a per-path delete policy Unset (`on_delete_at`) | examples/main.roc:72, 388, 392 | main.surql:32 | roc 1039 -> main.surql:352-356 (delete_medication_unsets_allergies) |
| M20 | link | Delete policy Cascade for owner to patient and patient to visit | examples/main.roc:390, 403 | main.surql:37, 49 | roc 1054 -> main.surql:364-378 |
| M21 | link | Delete policy Reject for a top-level link and for nested links (the nested ones become events) | examples/main.roc:391, 404 | main.surql:51, 56, 69-72 | roc 961-963 -> main.surql:302-312 |
| M22 | link | Link value built in application code (`Surreal.fetched`, `table.link("id")`), where `get()` reads the row in Roc | examples/main.roc:244-256, 681, 684, 687, 690, 693 | main.surql:91, 96 (record ids in the seeds) | |

### 1.3 Edges

| ID | Category | Description | Roc source | SurrealQL | Test case |
| --- | --- | --- | --- | --- | --- |
| M23 | edge | Edge table (`Surreal.relation`) with typed from and to links and extra fields | examples/main.roc:93, 117-118 | main.surql:7, 52-53 | |
| M24 | edge | Edge seeds written with `insert` (INSERT RELATION) | examples/main.roc:336-349, 935 | main.surql:99-102 | |
| M25 | edge | Check on an edge table field | examples/main.roc:410 | main.surql:53 | roc 953 -> main.surql:270-272 |
| M26 | edge | Unique index over both ends of an edge | examples/main.roc:411 | main.surql:67 | roc 952 -> main.surql:266-268 |
| M27 | edge | Create one edge (RELATE) and read the edges back with both linked names | examples/main.roc:336-337, 581-584, 745-746, 1047 | main.surql:358-362 | |
| M28 | edge | Outgoing traversal: the edges of a vet as a list, with count and filtered count | examples/main.roc:488-492, 837 | main.surql:158-160 | |
| M29 | edge | Incoming traversal: the edges at a patient, filtered, mapped through the `from` link | examples/main.roc:494-498, 843 | main.surql:162-164 | |

### 1.4 Schema constraints

| ID | Category | Description | Roc source | SurrealQL | Test case |
| --- | --- | --- | --- | --- | --- |
| M30 | schema constraint | Unique index on one field | examples/main.roc:356 | main.surql:57 | |
| M31 | schema constraint | Unique index on a composite of nested paths | examples/main.roc:357 | main.surql:58 | roc 951 -> main.surql:262-264 |
| M32 | schema constraint | Unique index on a nested path | examples/main.roc:368 | main.surql:60 | roc 949 -> main.surql:254-256 |
| M33 | schema constraint | Unique index on a composite that includes a link | examples/main.roc:384 | main.surql:61 | roc 950 -> main.surql:258-260 |
| M34 | schema constraint | Plain index (non unique), three tables | examples/main.roc:361, 389, 402 | main.surql:59, 62, 65 | |
| M35 | schema constraint | Assert from a named Roc function that the program also calls (`valid_email`) | examples/main.roc:129-131, 358 | main.surql:13 | roc 942 -> main.surql:226-228 |
| M36 | schema constraint | Assert from a lambda that uses a Roc string method (`starts_with`) | examples/main.roc:370 | main.surql:21 | |
| M37 | schema constraint | Assert from a SurrealDB function on a nested path (`Text.is_email`) | examples/main.roc:369 | main.surql:19 | roc 943 -> main.surql:230-232 |
| M38 | schema constraint | Assert on each element of a list of scalars | examples/main.roc:359 | main.surql:17 | roc 946 -> main.surql:242-244 |
| M39 | schema constraint | Assert on a field of each record in a list: a lambda and a shared open-row function | examples/main.roc:386, 398; examples/clinic/Clinic.roc:17-19 | main.surql:41, 46 | roc 947-948 -> main.surql:246-252 |
| M40 | schema constraint | Assert on a tag union with `match` (possible_species) | examples/main.roc:181-186, 385 | main.surql:38 | roc 944 -> main.surql:234-236 |
| M41 | schema constraint | Assert on a union with a wildcard arm and a value range (sane_outcome) | examples/main.roc:175-179, 399 | main.surql:48 | roc 945 -> main.surql:238-240 |
| M42 | schema constraint | Check over one field, named, from a function or lambda (becomes a field ASSERT) | examples/main.roc:188-189, 360, 372, 387, 401 | main.surql:14, 23, 43, 44 | roc 940 -> main.surql:218-220 |
| M43 | schema constraint | Check over several fields from a shared open-row function (becomes a DEFINE EVENT with THROW) | examples/main.roc:400; examples/clinic/Clinic.roc:21-24 | main.surql:68 | roc 941 -> main.surql:222-224 |
| M44 | schema constraint | Read-only field | examples/main.roc:371 | main.surql:21 | roc 955 -> main.surql:278-280 |
| M45 | schema constraint | Computed field from a Roc function that the program also calls (`label_of`) | examples/main.roc:133-135, 375-379 | main.surql:27 | |
| M46 | schema constraint | Default value from the builder (`.default(.., [])`) | examples/main.roc:388 | main.surql:32 | |
| M47 | schema constraint | Default value made by a function (`default_by`, ULID key) | examples/main.roc:1090-1098 | main.surql:54 | |
| M48 | other | Schema text built from the list of definitions (SCHEMAFULL tables, OVERWRITE, field, index and event statements) | examples/main.roc:353-412, 754-758 | main.surql:1-72 | |

### 1.5 Queries: filters and projections

| ID | Category | Description | Roc source | SurrealQL | Test case |
| --- | --- | --- | --- | --- | --- |
| M49 | query-filter | Parameter record with `filter_by` and `prepare({..})` (LET) | examples/main.roc:416-419, 765 | main.surql:104-108 | |
| M50 | projection | Projection into a named record type with a Roc function (renames, `record::id(id) AS id`), with `order_by` | examples/main.roc:421-425, 765 | main.surql:108 | |
| M51 | projection | Optional field with `??` default in a projection | examples/main.roc:423-425, 574 | main.surql:108, 344 | |
| M52 | query-filter | Filter with a named Roc function that uses list `contains` | examples/main.roc:439-440, 771 | main.surql:110-112 | |
| M53 | query-filter | Filter on the presence of an optional field (`.?field.is_ok()`) | examples/main.roc:777 | main.surql:114-116 | |
| M54 | projection | `match` on an optional link of the same table and read of the linked row | examples/main.roc:427-437, 777 | main.surql:116 | |
| M55 | projection | Link read in a projection with `get()` (no FETCH, no JOIN) | examples/main.roc:442-446, 783 | main.surql:118-121 | |
| M56 | projection | `match` on a tag union in a projection (`species_label`) | examples/main.roc:137-143, 446, 783 | main.surql:121 | |
| M57 | projection | Reusable ordering fragment over selected rows (`Clinic.by_id`) | examples/clinic/Clinic.roc:52-54; examples/main.roc:783, 819 | main.surql:121, 148 | |
| M58 | query-filter | Read one record by typed key (`table.at(id)`) | examples/main.roc:120-121, 789 | main.surql:123-125 | |
| M59 | query-filter | Filter by a key given as parameter (`v.id == p.key`) | examples/main.roc:795 | main.surql:127-130 | |
| M60 | query-filter | `match` in a filter that reads the payload of a union arm (`wide_wings`) | examples/main.roc:158-162, 801 | main.surql:132-134 | |
| M61 | projection | Scalar projection `select_value`, also with `order_by` on the value | examples/main.roc:801, 825, 858-863 | main.surql:134, 152, 176-179 | |
| M62 | projection | Two `match` calls on one optional record (chip code and chip vet name through a link) | examples/main.roc:448-462, 807 | main.surql:136-138 | |
| M63 | projection | Map over a list of records and read a link in each (`vaccines.map(\|v\| v.vet.get().name)`) | examples/main.roc:464-468, 813 | main.surql:142 | |
| M64 | query-filter | Filter with `any` over a list and comparison of a link id with a typed id (`v.vet.id() == ruth_id`) | examples/main.roc:470-471, 813 | main.surql:140-142 | |
| M65 | query-filter | Query fragment (`filter_by`) over an open row with a parameter record (`Clinic.recent`, `Clinic.seen_since`) | examples/clinic/Clinic.roc:26-34, 48-50; examples/main.roc:473, 819 | main.surql:144-148 | |
| M66 | projection | Computation over linked rows in a projection (`Clinic.bill`: decimal cast, link read inside a list `map`, `sum`) | examples/clinic/Clinic.roc:9-15; examples/main.roc:475-478 | main.surql:148 | |
| M67 | query-filter | Database clock in a filter (`Time.now()`) | examples/main.roc:825 | main.surql:150-152 | |
| M68 | projection | `match` whose arm reads a link (`Referred(r) => r.to.get().name`) | examples/main.roc:145-150, 480-483, 831 | main.surql:156 | |
| M69 | query-filter | `match` with a wildcard arm used as a filter (`needs_attention`) | examples/main.roc:152-156, 485-486, 831 | main.surql:156 | |
| M70 | projection | Whole row as one value (`select_value(\|v\| v)`) | examples/main.roc:867 | main.surql:181-183 | |
| M71 | projection | Order by with limit (top N) | examples/main.roc:505-508, 855 | main.surql:171-174 | |
| M72 | projection | Pagination: `order_by`, `start`, `limit` | examples/main.roc:873 | main.surql:185-188 | |
| M73 | projection | Fields of linked rows with no FETCH (`p.owner.get().address.city`, list map over links) | examples/main.roc:527-531, 879 | main.surql:190-192 | |
| M74 | projection | Whole linked rows as values (owner row, list of vet rows) | examples/main.roc:533-537, 885 | main.surql:194-196 | |
| M75 | query-filter | Value captured at run time, bound as a LET parameter (`bind_captured`, `select_where`) | examples/main.roc:510-513, 891 | main.surql:198-201 | |
| M76 | query-filter | Captured list of records with optional fields, matched with `contains` | examples/main.roc:515-519, 897 | main.surql:203-206 | |
| M77 | query-filter | Captured record compared with `==`, optional field present or absent | examples/main.roc:521-525, 903, 909 | main.surql:208-216 | |

### 1.6 Group and aggregate

| ID | Category | Description | Roc source | SurrealQL | Test case |
| --- | --- | --- | --- | --- | --- |
| M78 | group-aggregate | GROUP BY a key read through a link, with count and sum (`group_by(\|v\| v.vet.get().name).aggregate(..)`) | examples/main.roc:500-503, 849 | main.surql:166-169 | |
| M79 | group-aggregate | Statistic over a group (`Math.mean` of a float cast) | examples/main.roc:503, 849 | main.surql:169 | |
| M80 | group-aggregate | Order by an aggregate value, descending, with limit | examples/main.roc:849 | main.surql:169 | |
| M81 | group-aggregate | Totals of all matching rows as one row (GROUP ALL): count, sum, mean | examples/main.roc:1117-1122, 1134 | main.surql:394-396 | |
| M82 | group-aggregate | Totals of no rows: one row with count 0 | examples/main.roc:1140 | main.surql:398-400 | |

### 1.7 Writes

| ID | Category | Description | Roc source | SurrealQL | Test case |
| --- | --- | --- | --- | --- | --- |
| M83 | write | Seed rows with the derived encoder: `insert` in a transaction (INSERT INTO and INSERT RELATION) | examples/main.roc:928-936 | main.surql:74-102 | |
| M84 | write | Create one row (CREATE ... CONTENT) | examples/main.roc:736-737, 990 | main.surql:314-318 | |
| M85 | write | Create through a form row that leaves out computed and defaulted fields | examples/main.roc:53-55, 739-740, 996 | main.surql:320-324 | |
| M86 | write | Update by predicate with a parameter record and a patch function (`update_by`) | examples/main.roc:544-547, 1003; examples/clinic/Clinic.roc:40-42 | main.surql:326-332 | |
| M87 | write | Update by key: patch with arithmetic and a new union value (`update_at`) | examples/main.roc:554-556, 1012 | main.surql:334-338 | |
| M88 | write | Update with a spread over optional fields (`{ ..o, name: ".." }` sets only `name`) | examples/main.roc:558-561, 1021 | main.surql:340-344 | |
| M89 | write | Patch of only the listed fields; an optional field is removed with `Err` (`set_at`) | examples/main.roc:563-566, 1030 | main.surql:346-350 | |
| M90 | write | Delete by key | examples/main.roc:1054 | main.surql:364-368 | |
| M91 | write | Delete by predicate with a parameter (retention) | examples/clinic/Clinic.roc:36-38; examples/main.roc:1075 | main.surql:380-385 | |
| M92 | write | Create rows without a key, the server makes the key (`insert_new`, open-row projection over keyed and keyless rows) | examples/main.roc:1090-1108, 1083 | main.surql:387-392 | |
| M93 | write | Refused writes: each constraint refuses a bad row and the error names the field. The refused rows are given in the Test case column of each constraint row | examples/main.roc:938-964 | main.surql:218-312 | all |

### 1.8 Other

| ID | Category | Description | Roc source | SurrealQL | Test case |
| --- | --- | --- | --- | --- | --- |
| M94 | other | Open-row helper functions and query fragments that serve several tables and rows (any record that has the fields) | examples/clinic/Clinic.roc:9-54 | same SurrealQL as the rows that use them (M39, M43, M57, M65, M66, M86, M91) | |

## 2. examples/monitoring.roc (IDs N01 to N52)

### 2.1 Row types, schema, links, edges

| ID | Category | Description | Roc source | SurrealQL |
| --- | --- | --- | --- | --- |
| N01 | geometry | Point and Polygon fields; a validity assert is added. A point out of range is refused (test: roc 432-436 -> monitoring.surql:134-136) | examples/monitoring.roc:42 | monitoring.surql:10-11 |
| N02 | geometry | Geometry values made in app code (`Surreal.point`, ring of a polygon, `rectangle` helper) and seeded | examples/monitoring.roc:150-164, 326 | monitoring.surql:23-26 |
| N03 | link | Link in a row (kennel.site), default Reject policy and exists assert | examples/monitoring.roc:44, 166-170 | monitoring.surql:13-14, 28-31 |
| N04 | time series | Record key as a time series key over a typed id (`TimeKey(Id(Kennel))`, key type `[record<kennel>, datetime]`) | examples/monitoring.roc:46 | monitoring.surql:18 |
| N05 | time series | Seeds with composed keys (`time_key(id, datetime)`); the computed field is given a placeholder | examples/monitoring.roc:188-190, 196-212, 330 | monitoring.surql:43-46 |
| N06 | edge | Two edge tables between the same pair of tables (cares_for with a flag, checks with a note) | examples/monitoring.roc:51, 54, 68-72, 112-116, 172-180 | monitoring.surql:6-7, 16-17, 33-41 |
| N07 | other | Schema text from a list of definitions: functions, tables, view, read row check | examples/monitoring.roc:103-126, 306-315 | monitoring.surql:1-21 |

### 2.2 Database functions

| ID | Category | Description | Roc source | SurrealQL |
| --- | --- | --- | --- | --- |
| N08 | db function | Roc function becomes a database function (`db_fn`, `Surreal.function`) and Roc can still call it (`call2`) | examples/monitoring.roc:90-99, 309 | monitoring.surql:2 |
| N09 | db function | Database function in a filter | examples/monitoring.roc:337 | monitoring.surql:48-50 |
| N10 | db function | Database function in a computed field | examples/monitoring.roc:121-126 | monitoring.surql:19 |
| N11 | db function | Database function in a projection (with a literal argument) | examples/monitoring.roc:221-226, 340 | monitoring.surql:52-54 |
| N12 | db function | Database function inside an aggregate (count of calls per group) | examples/monitoring.roc:136-139, 352 | monitoring.surql:64-66 |

### 2.3 Time series

| ID | Category | Description | Roc source | SurrealQL |
| --- | --- | --- | --- | --- |
| N13 | time series | Read the parts of a key in a projection (`id.series()`, `id.time()`) | examples/monitoring.roc:216-219, 337 | monitoring.surql:48-50 |
| N14 | time series | Whole key as a projected value (the array `[kennel, time]`) | examples/monitoring.roc:221-226, 340 | monitoring.surql:52-54 |
| N15 | time series | Range query between two times for one series (lower bound inclusive, upper bound exclusive) | examples/monitoring.roc:300-304, 343 | monitoring.surql:56-58 |
| N16 | time series | Range query that returns whole rows (`select(\|r\| r)`) | examples/monitoring.roc:349 | monitoring.surql:60-62 |
| N17 | time series | Bucket by day with `Time.floor` and `Time.days`, from the key time | examples/monitoring.roc:130-134 | monitoring.surql:66 |
| N18 | time series | Delete by key time with a parameter (retention) | examples/monitoring.roc:397-401 | monitoring.surql:101-105 |
| N19 | time series | Changefeed with a duration | examples/monitoring.roc:125 | monitoring.surql:8 |

### 2.4 Views, groups and result-row filters

| ID | Category | Description | Roc source | SurrealQL |
| --- | --- | --- | --- | --- |
| N20 | group-aggregate | GROUP BY two derived keys (kennel and day) with count and a filtered count | examples/monitoring.roc:130-139, 352 | monitoring.surql:64-66 |
| N21 | view | View defined from a grouped query (`define_as`) | examples/monitoring.roc:141-146 | monitoring.surql:9 |
| N22 | view | Read the view as a table | examples/monitoring.roc:390-394 | monitoring.surql:93-95 |
| N23 | query-filter | Filter on result rows after a projection (same WHERE, reads the projected fields) | examples/monitoring.roc:355-359 | monitoring.surql:68-70 |
| N24 | query-filter | Filter on groups (HAVING) as a subquery | examples/monitoring.roc:360-366 | monitoring.surql:72-74 |
| N25 | query-filter | Filter after order and limit (subquery keeps the order) | examples/monitoring.roc:367-372 | monitoring.surql:76-78 |
| N26 | query-filter | Same, on a scalar projection | examples/monitoring.roc:373-377 | monitoring.surql:80-82 |
| N27 | group-aggregate | Result rows of a projection as rows of a new query (`.query()`), then filter, group, aggregate in one SELECT | examples/monitoring.roc:378-383 | monitoring.surql:84-86 |
| N28 | query-filter | Parameter in a filter over a subquery | examples/monitoring.roc:384-389 | monitoring.surql:88-91 |

### 2.5 Geometry queries

| ID | Category | Description | Roc source | SurrealQL |
| --- | --- | --- | --- | --- |
| N29 | geometry | Read a coordinate of a point (`location.lat()`) | examples/monitoring.roc:274-277, 402 | monitoring.surql:107-109 |
| N30 | geometry | Area contains a point given as parameter (`Geo.inside`) | examples/monitoring.roc:270-272, 404-408 | monitoring.surql:111-114 |
| N31 | geometry | Distance below a limit (`Geo.distance`), point as parameter | examples/monitoring.roc:409-413 | monitoring.surql:116-119 |

### 2.6 Read rows and rows of other tables

| ID | Category | Description | Roc source | SurrealQL |
| --- | --- | --- | --- | --- |
| N32 | read row | Read row with a `Linked` field: read the site name with no `get()` | examples/monitoring.roc:77-83, 416-418 | monitoring.surql:121-123 |
| N33 | read row | Read row with an `In` field: the edges at a row, with each carer as a whole linked row | examples/monitoring.roc:74-75, 80, 418 | monitoring.surql:121-123 |
| N34 | read row | Filter and count over the `In` list (`keep_if`, `len`) | examples/monitoring.roc:418 | monitoring.surql:123 |
| N35 | read row | Schema check that the read row agrees with the stored row (`define_read`) | examples/monitoring.roc:118-119 | none (a schema error if it does not agree) |
| N36 | other | Rows of another table in a clause: correlated count (`vitals.rows()`), with a Roc function that the program also calls (`readings_of`) | examples/monitoring.roc:262-264, 422-426 | monitoring.surql:125-128 |
| N37 | query-filter | Semi join: filter with `any` over the rows of another table (`has_fever`) | examples/monitoring.roc:266-268, 427-431 | monitoring.surql:130-132 |

### 2.7 Live queries

Each live block has one or more LIVE statements and one snapshot SELECT. The `-- roles:` line shows the statements (node, edge, read, raw, diff).

| ID | Category | Description | Roc source | SurrealQL |
| --- | --- | --- | --- | --- |
| N38 | live query | Live filter with a database function (roles: node) | examples/monitoring.roc:441-443, 871 | monitoring.surql:138-159 |
| N39 | live query | Live filter with a parameter fixed when the watch starts | examples/monitoring.roc:445-448, 872 | monitoring.surql:161-183 |
| N40 | live query | Live on a view | examples/monitoring.roc:450-452, 873 | monitoring.surql:185-194 |
| N41 | live query | Kennels with no carer: `incoming` edges, filter and projection on a tuple (roles: node, edge) | examples/monitoring.roc:454-466, 874-880 | monitoring.surql:196-220 |
| N42 | live query | Same watch through the read row `In` field (roles: node, edge) | examples/monitoring.roc:468-471, 881-890 | monitoring.surql:222-236 |
| N43 | live query | Live filter that reads the rows of another table (roles: node, read) | examples/monitoring.roc:473-476, 891 | monitoring.surql:238-252 |
| N44 | live query | Live on two edge tables (`and_incoming`, roles: node, edge, edge) | examples/monitoring.roc:478-490, 894-903 | monitoring.surql:298-319 |
| N45 | live query | Live projection through a `Linked` read row; a write to the linked site reaches the kennels (roles: node, read) | examples/monitoring.roc:492-498, 820-824 | monitoring.surql:254-274 |
| N46 | live query | Live filter on a link read with `get()`; a write to the linked site makes kennels enter or leave (roles: node, read) | examples/monitoring.roc:500-504, 826-830 | monitoring.surql:276-296 |
| N47 | live query | Raw live events (escape hatch, roles: raw) | examples/monitoring.roc:506-508, 904-911 | monitoring.surql:321-340 |
| N48 | live query | Live diff of patches on a table (escape hatch, roles: diff) | examples/monitoring.roc:510-512, 912-915 | monitoring.surql:342-351 |

### 2.8 Writes that drive the live blocks

| ID | Category | Description | Roc source | SurrealQL |
| --- | --- | --- | --- | --- |
| N49 | write | Typed writes from edit values (Create, Replace old to new, Delete) on node tables, with a time series key | examples/monitoring.roc:523-531, 546-551 | monitoring.surql:144-159, 168-183, 191-194, 325-340, 346-351 |
| N50 | write | Same on edge tables (create and delete an edge) | examples/monitoring.roc:591-595, 611-626, 631-644 | monitoring.surql:203-220, 229-236 |
| N51 | write | Delete of a node row that also deletes its edges (carer, kennel) | examples/monitoring.roc:622, 625, 643 | monitoring.surql:215-220, 235-236, 312-319 |
| N52 | write | Update of a linked row (site rename) and a write that changes nothing | examples/monitoring.roc:780-800 | monitoring.surql:261-274, 283-296 |

## 3. Test harness line ranges

Type codes: H is harness only (exclude from LOC). F is fixture or scenario data that every implementation also needs (count it apart from the ORM code). M is mixed: only the named part is harness.

### 3.1 examples/main.roc

| Lines | Type | Reason |
| --- | --- | --- |
| 1-17 | H | Header comment |
| 164-170 | H | `expect` tests of Roc helpers |
| 193-197 | F | `at` helper that parses seed datetimes |
| 199-349 | F | Seed rows: vets, owners, medications, patients, visits, edges (needed by every implementation) |
| 588-630 | H | Reference results for `-- roc:` lines: `owners_in_city`, `edges_of_vet`, `edges_of_patient`, `visit_names`, `ledger_in_memory`, `expect` lines, `visit_of` |
| 568-569 | H | `lena_moved`, the expected row after `moved` |
| 632-639 | F | Bad rows for refusal tests: `free_medication`, `zero_doses` |
| 641-647 | H | `expect` tests of constraints |
| 649-702 | F | Bad rows for refusal tests (one for each constraint) |
| 704-708 | H | `expect` tests of constraints |
| 710-734 | H | `block`, `plain`, `then_read`, `rejects`: script assembly |
| 736-752 | F | Inputs of the writes: pip, meloxicam_form, meloxicam, new_edge, refill_param, cutoff |
| 754-758 | M | `schema_block`: the `Surreal.schema([..])` call is feature (M48), the `-- schema` header is harness |
| 760-912 | M | `reads`: in each `block(` call only the prepared-query argument is feature code. The lines `block(`, the header string, the flags list, `Surreal.Mirror.literal(..)` and `),` are harness |
| 914-923 | F | Captured address inputs for M76 and M77 |
| 925-926 | H | `script`: joins the blocks |
| 928-936 | M | `seeds`: the `insert(..)` argument is feature (M83), the `plain(..)` wrapper is harness |
| 938-964 | M | `refusals`: the write argument is feature (M93), the `rejects(..)` wrapper and the error text are harness |
| 966-983 | H | Reference state after the writes: `patients_now`, `medications_now`, `without_aspirin`, `owned_by_noor`, `visits_now`, and `expect` lines 978-980 |
| 985-1086 | M | `writes`: only the prepared write and read arguments are feature code. `block(`, header, flags, `then_read(` and `Surreal.Mirror.literal(..)` are harness |
| 1110-1113 | H | `main!` prints the script |
| 1119-1128 | H | Comments about the Roc reference of the totals (lines 1117 and 1121-1122 are feature code) |
| 1129-1143 | M | `totals_blocks`: same rule as `reads` |

Feature code that sits among the harness (do not exclude): 1090-1108 (Note, notes, note_def, new_notes, note_line), 1117-1122 (VisitTotals, visit_totals), 416-586 (query functions, patch functions and line types), 129-162 and 175-189 (shared functions), 353-412 (definitions), 24-121 (rows and tables).

### 3.2 examples/clinic/Clinic.roc

All 55 lines are feature code (shared functions and fragments). No harness.

### 3.3 examples/monitoring.roc

| Lines | Type | Reason |
| --- | --- | --- |
| 1-36 | H | Header comment |
| 97-99 | H | `expect` tests of `fever_fn` |
| 158-186, 196-212 | F | Seed rows and the `moment` helper |
| 192-194 | H | `stored`: runs the computed field in Roc for the reference |
| 239-241 | H | `fastest`: reference helper |
| 245-258 | H | `KennelCarers`, `kennel_carers`: reference |
| 260 | H | `KennelReadings` type (not used by a query) |
| 279-284 | H | `block`: script assembly |
| 286-291 | H | `rollup`: reference of the daily groups |
| 293-298 | H | `then_read`: script assembly |
| 300-304 | F | `day_start`, `day_end` inputs of N15 and N18 |
| 311-322 | M | `schema_block` and `seed`: the schema call is feature (N07), the header text and wrappers are harness |
| 324-331 | M | `seed_blocks`: the `insert(..)` arguments are feature, the `seed(..)` wrapper is harness |
| 333-437 | M | `queries`: same rule as `reads` in main.roc. Line 396 is a raw SurrealQL check of the changefeed (harness). Lines 433-436 wrap the refused point (feature argument at 433) |
| 514-517 | H | `kept_vitals` reference state |
| 519-531 | F | `vital_edits`: the write scenario of the live blocks of readings |
| 533-559 | H | `vital_snapshot`, `vital_notices`, `text_of`, `vital_writes`, `live_block`: Mirror and script assembly |
| 561-580 | H | `late_fever` (F), `daily_notices`, `daily_snapshot`: Mirror references |
| 582-596 | F | Kennel and edge fixtures for the unattended scenario |
| 597-626 | M | `kennel_step`, `care_step` and `notices:` fields are harness (Mirror). The `write:` fields and `# case:` comments are scenario data (F) |
| 628-644 | M | Same rule: `west`, `ida_west` fixtures (F), `notices:` harness |
| 646-686 | M | Fevered kennels scenario: `north`, `north_wing`, `fevered_edits`, `south_fever` (F). Snapshot, `fever_reach`, notices (H). `fevered_kennels_writes` (F) |
| 688-734 | M | Neglected scenario: fixtures and `write:` fields (F). Mirror closures and `neglected_snapshot` (H) |
| 736-738 | H | `both_seen`: Mirror helper |
| 740-767 | F | `oslo`, `bergen`, `trondheim` fixtures (F). `kennels_at` (H) |
| 769-818 | M | `site_step`, `site_snapshot`, `site_notices`, `site_label`, `is_oslo`, `kennel_label`: Mirror (H). `site_writes` 780-800 is scenario data (F) |
| 820-830 | M | `kennel_sites_block`, `oslo_kennels_block`: wrappers and Mirror calls (H). The write list is `site_writes` (F) |
| 832-850 | H | `both`, `unattended_notices`, `unattended_snapshot`: Mirror references |
| 852-863 | H | `patch_edits` (F) and `patches_literal` (H, hand-written expected patches) |
| 865-867 | H | `is_fever`: keep function for the Mirror |
| 869-916 | M | `live_blocks`: the watch values (`fevered`, `hotter_than(..)`, ...) are feature. `live_block(..)` wrapper, snapshots, notices, `Mirror.events` are harness |
| 918-924 | H | `script` and `main!` |

Feature code that sits among the harness (do not exclude): 42-95 (rows, tables, read rows, ids), 90-95 (fever, db_fn), 103-146 (definitions, day_of, view), 216-237 (query line types and functions), 262-277 (`readings_of`, `has_fever`, `here`, `site_lat`), 306-309 (`definitions`), 439-512 (watch definitions, `no_carer`, `no_one`, line functions).

## 4. Roc-specific benefits to keep in mind

| No | Benefit | Related IDs |
| --- | --- | --- |
| 1 | One Roc function is the DB constraint and the application code (`valid_email`, `named`, `sane_outcome`, `fee_covers_items`) | M35, M40, M41, M43 |
| 2 | One Roc function is the projection, the computed field, the DB function and the in-memory code (`label_of`, `fever`, `Clinic.bill`) | M45, M66, N08-N12 |
| 3 | The row types are the seed data, the function arguments and the test inputs. The encoder and parser are derived | M01, M83 |
| 4 | Defaults and numeric ranges are part of the Roc type (`?? []`, `U8`, `I32`) | M05, M09 |
| 5 | Open-row helpers and query fragments (`Clinic.*`) work over any row that has the fields, and give the same SurrealQL on each row | M39, M57, M65, M94 |
| 6 | Tag unions with `match` become literal union types and IF chains. Roc checks that the `match` is exhaustive | M12, M40, M56, M60 |
| 7 | A link has two meanings: `get()` in a clause is a traversal, in the program it reads the row (`Surreal.fetched`) | M22, M55 |
| 8 | Compile-time checks: a patch field is checked against the row, the order of clauses after `select` is typed, an edge table in the wrong direction is a type error | M89, M72, M28 |
| 9 | Typed results: a prepared query reads its reply as the Roc type of the projection | all queries |
| 10 | The Mirror predicts the live notices, snapshots and raw events from the same Roc functions. The reference result of each query (`-- roc:`) comes from the same functions over the same rows | N38-N48 |
| 11 | Read rows are checked against the stored row at schema time (`define_read`) and give link and edge reads with no `get()` or `incoming` | N32-N35 |
| 12 | Limits that a comparison must note: `Geo.inside`, `Geo.distance` and `Text.is_email` have no Roc body (database only); the changefeed check uses raw SurrealQL; an optional field patch with `..` is a switch on presence | N30, N31, M37, N19 |
