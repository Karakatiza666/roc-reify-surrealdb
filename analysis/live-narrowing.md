# Live queries: narrow `rows()` reads, test the filter once

Rows N43, N37 and "Round trip of the key" of `compare_surql-2.md`.

## Before and after

`fevered_kennels` (`examples/monitoring.roc:474`):
`Surreal.from(kennels).filter(|k| has_fever(vitals.rows(), k)).select_value(|k| k.label).ready_live(definitions)`

| Statement | Before | After |
| --- | --- | --- |
| node | `now: <t>` ... `WHERE <t> OR ($before IS NOT NONE AND <t on $before>)` | `now: true` ... `WHERE <t>` |
| read | `(SELECT VALUE { ref: id, row: label, now: <t> } FROM kennel) FROM vital` | `(SELECT .. FROM record::id($parent.id)[0]) FROM vital` |
| `<t>` | `type::record('kennel', record::id(id)).chain(..).any(..)` | `id.chain(..).any(..)` |
| Read notices per vital write, 300 kennels | 300 | 1 (3.3.5 and 4.0.0) |
| Evaluations of `<t>` per kennel write | 3 | 1 |

## What reaches what

A clause reads a table `T` with `rows()`. A write to `T` can change a row `R` of the result only when the function over `T` relates the written row to `R`. The translator looks for one conjunct of the function of a `keep_if`, `any`, `count_if` or `find_first` over `T.rows()` (`Translate.related`, `src/Translate.roc:3152`):

| Conjunct | `fixed` | Payload of the `read` statement (`Surreal.near_rows`, `near_test`) |
| --- | --- | --- |
| `x(e) == v(R)`, `x` reads only the key of `e` (`e.id.series()`) | yes | `FROM x($parent)` when `v` is `id`, else `WHERE v = x($parent)` |
| `x(e) == v(R)`, `x` reads a field of `e` | no | `FROM array::distinct([$before, $after].filter(\|$w\| $w != NONE).map(\|$w\| x($w)))`, or `WHERE v IN ..` |
| `xs(e).contains(v(R))` | no (or yes) | `WHERE v IN array::distinct(array::flatten(..))` |
| `xs(e).any(\|x\| p(x) == v(R))`, `p` a field path of `x` (`Translate.nested_tie`, `src/Translate.roc:3213`) | no | `FROM array::distinct(array::flatten(.. .map(\|$w\| $w.stops[*].kennel)))`, or `WHERE v IN ..` |
| the same with an `any` in the function of `any` (a list of lists) | no | one `array::flatten` more per level: `$w.boxes[*].items[*].product` is a list of lists |
| none of these, or a `rows()` inside the function of another list operation | | every row: `FROM <table>` (the old form) |

Rules:

1. `x` reads the element only, `v` does not read it. A captured value makes the side not of the element (`Translate.reads_below`).
2. `fixed`: `x` reads the element only through `id`. A write never changes a key, so `$parent` is enough.
3. Not `fixed`: both `$before` and `$after`. An update that moves a row from `R1` to `R2` reaches both. A create has no `$before`, a delete no `$after`; the filter drops the NONE.
4. Fallback: when one read of `T` in the clauses has no relation, the statement on `T` reads every row (`Surreal.near`). Several related reads of `T` are an `OR` of their tests.
5. Each reached row still gets `now`, so a row that leaves the result is reported.

## The filter once (problem 2)

| Change | Where | Why it is safe |
| --- | --- | --- |
| `kennels.id(k.id)` of the row that the statement reads is `id`, not `type::record('kennel', record::id(id))` | `Translate.own_record`, `src/Translate.roc:2221` | The row is a record of that table, so its id is the same record |
| A filter that reads `$before` only as `$before.id` and its edges: `WHERE <p>`, `now: true` | `Surreal.keyed_only`, `src/Surreal.roc:4272` | The id and the edges are the same before and after a write of the row, and both sides are evaluated at the same moment, so `<p on $before>` equals `<p>` |

A filter that reads any other field is still tested three times. Checked on 3.3.5 and 4.0.0: `WHERE` cannot read a projection alias (`LIVE SELECT label AS row, (label = 'x') AS now FROM kennel WHERE now` sends nothing), and `LIVE` takes no `LET`.

Other live blocks with the same change: `unattended` and `neglected` (edge filters, `now: true`, one test).

## Server checks

| Check | 3.3.5 (8501) | 4.0.0 (8502) | 3.3.4 (8000, all_tests) |
| --- | --- | --- | --- |
| `FROM record::id($parent.id)[0]` on create, update, delete; key of no kennel gives `[]` | ok | ok | |
| `array::distinct([$before, $after]..)`: move reaches old and new | ok | ok | |
| `title IN array::distinct(array::flatten(..))`: old and new tags | ok | ok | |
| check.py, all blocks (with the new `site_kennels` block) | 186/186 | 186/186 | in all_tests.sh |
| Notices per write, 300 kennels, 15 writes | 300 to 1 | 300 to 1 | |

## Mirror contract

| | Before | After |
| --- | --- | --- |
| `Mirror.read_notices(table, edit, reached, keep, show)` | `reached` for `rows()` was every row | `reached` is the related rows; the signature is the same |
| `Mirror.related(edit, rows, relates)` | | New: the rows that `relates` holds for with the written row before or after the write |
| Notice shape | | Not changed. A write that reaches no row sends an empty list, which is zero notices |

The test in Roc writes `relates` as the same equality as the clause (`|v, k| v.id.series() == kennels.id(k.id)`); check.py compares it with the server.

## A relation in a list of the element

`kennel_rounds` (`examples/monitoring.roc:514`): `rounds.rows().count_if(|r| r.stops.any(|st| st.kennel.id() == kennels.id(k.id)))`.

| Statement | Before | After |
| --- | --- | --- |
| read | `(SELECT .. FROM kennel) FROM round` | `(SELECT .. FROM array::distinct(array::flatten([$before, $after].filter(..).map(\|$w\| $w.stops[*].kennel)))) FROM round` |
| Read rows per round write, 300 kennels, 2000 rounds, 15 writes (create 2 stops, move to 1, delete) | 300 each, 4500 in all, 84 s (3.3.5), 41 s (4.0.0) | 2, 3, 1 each, 30 in all, under 1 s (3.3.5 and 4.0.0) |

The path must be fields of `x` (`Translate.element_path`), and `v` must read no element: a captured value that reads an element is of the element too. `Mirror.related` takes the same function: `stops_at(r, k)`. The check.py block `live: kennel_rounds` compares it with the server (188/188 blocks on 3.3.5 and 4.0.0).

## Count and filter with `WHERE` (problem 3)

`site_kennels` read every kennel for each site: `(SELECT VALUE id FROM kennel).filter(|$v1| $v1.site = id).len()`. Now each conjunct of a `keep_if`, `count_if`, `any` or `find_first` over `T.rows()` that reads the row of `T` goes into the `WHERE` of the subquery (`Translate.where_of`, `src/Translate.roc:2839`). A value of the clause in the conjunct becomes a kept node (`Translate.lift`), bound around the subquery with `chain`:

`id.chain(|$v1_0| (SELECT VALUE id FROM kennel WHERE site = $v1_0)).len()`

| Form (30 sites, 30000 kennels, index on `site`) | 3.3.5 | 4.0.0 | Valid in `UPDATE .. WHERE` and a view |
| --- | --- | --- | --- |
| `(SELECT VALUE id FROM kennel).filter(..).len()` (before) | 6.7 s | 4.4 s | yes |
| `(SELECT VALUE id FROM kennel WHERE site = $parent.id).len()`, `count(..)` the same | 0.9 s, `TableScan` | 0.04 s, `TableScan` | no on 3.3.5: `$parent` is NONE there, every count is 0 |
| `id.chain(\|$x\| (SELECT VALUE id FROM kennel WHERE site = $x)).len()` (after) | 0.11 s, `Iterate Index` | 0.6 s, `TableScan` | yes |

No form makes 4.0.0 use an index in a correlated subquery; a constant does (`WHERE site = site:1`, `IndexScan`). `chain` is the one form that is correct in every statement and fast on 3.3.x. It also works in `LIVE SELECT` and in the narrowed read subquery (check.py blocks `site_kennels`, `kennel_rounds`).

| Rule | Why |
| --- | --- |
| A conjunct that does not read the row stays a `filter` | It is no test of the row |
| A `$` parameter of the statement (`$min_total`) is read in place, not bound | The subquery sees it; `$this` and `$parent` are not read in place, as they name the subquery's row |
| A whole row of the clause is bound as `$this.chain(\|$v1_0\| ..)` | `kennels.id(k.id)` then reads `$v1_0.id` |
| `keep_if` and `find_first` with a test other than `==` read `ORDER BY id` | An index gives the rows in the order of the index; the table gives them by id |
| `any` is `(.. LIMIT 1) != []`, `find_first` `(.. LIMIT 1)[0]` | One row is enough |
| `keep_if(f).len()` is `count_if(f)` | A count needs no order |
| `drop_if`, `all`, `map` are not changed | No `WHERE` gives them |

## Not done

- A `rows()` read inside the function of another list operation still falls back to every row.
- `record::id(x) = record::id(id)` (a key compared with a key, `o.customer.get().id == c.id`) narrows with `WHERE record::id(id) IN ..`, a scan of the result's table per write, not `FROM <record>`. In the `WHERE` of `rows()` it is `record::id(customer) = $v1_0`, which no index serves.
- `t.rows()` kept as a definition (read twice in one clause) is not a key range (`series_range` reads the tree of `rows()`), so it is `WHERE record::id(id)[0] = $v1_0`.
