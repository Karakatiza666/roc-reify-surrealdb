# Live queries: narrow `rows()` reads, test the filter once

Rows N43, N37 and "Round trip of the key" of `compare_surql-2.md`.

## Before and after

`fevered_kennels` (`examples/monitoring.roc:459`):
`Surreal.from(kennels).filter(|k| has_fever(vitals.rows(), k)).select_value(|k| k.label).ready_live(definitions)`

| Statement | Before | After |
| --- | --- | --- |
| node | `now: <t>` ... `WHERE <t> OR ($before IS NOT NONE AND <t on $before>)` | `now: true` ... `WHERE <t>` |
| read | `(SELECT VALUE { ref: id, row: label, now: <t> } FROM kennel) FROM vital` | `(SELECT .. FROM record::id($parent.id)[0]) FROM vital` |
| `<t>` | `type::record('kennel', record::id(id)).chain(..).any(..)` | `id.chain(..).any(..)` |
| Read notices per vital write, 300 kennels | 300 | 1 (3.3.5 and 4.0.0) |
| Evaluations of `<t>` per kennel write | 3 | 1 |

## What reaches what

A clause reads a table `T` with `rows()`. A write to `T` can change a row `R` of the result only when the function over `T` relates the written row to `R`. The translator looks for one conjunct of the function of a `keep_if`, `any`, `count_if` or `find_first` over `T.rows()` (`Translate.related`, `src/Translate.roc:2968`):

| Conjunct | `fixed` | Payload of the `read` statement (`Surreal.near_rows`, `near_test`) |
| --- | --- | --- |
| `x(e) == v(R)`, `x` reads only the key of `e` (`e.id.series()`) | yes | `FROM x($parent)` when `v` is `id`, else `WHERE v = x($parent)` |
| `x(e) == v(R)`, `x` reads a field of `e` | no | `FROM array::distinct([$before, $after].filter(\|$w\| $w != NONE).map(\|$w\| x($w)))`, or `WHERE v IN ..` |
| `xs(e).contains(v(R))` | no (or yes) | `WHERE v IN array::distinct(array::flatten(..))` |
| none of these, or the read is inside the function of another list operation | | every row: `FROM <table>` (the old form) |

Rules:

1. `x` reads the element only, `v` does not read it. A captured value makes the side not of the element (`Translate.reads_below`).
2. `fixed`: `x` reads the element only through `id`. A write never changes a key, so `$parent` is enough.
3. Not `fixed`: both `$before` and `$after`. An update that moves a row from `R1` to `R2` reaches both. A create has no `$before`, a delete no `$after`; the filter drops the NONE.
4. Fallback: when one read of `T` in the clauses has no relation, the statement on `T` reads every row (`Surreal.near`). Several related reads of `T` are an `OR` of their tests.
5. Each reached row still gets `now`, so a row that leaves the result is reported.

## The filter once (problem 2)

| Change | Where | Why it is safe |
| --- | --- | --- |
| `kennels.id(k.id)` of the row that the statement reads is `id`, not `type::record('kennel', record::id(id))` | `Translate.own_record`, `src/Translate.roc:2220` | The row is a record of that table, so its id is the same record |
| A filter that reads `$before` only as `$before.id` and its edges: `WHERE <p>`, `now: true` | `Surreal.keyed_only`, `src/Surreal.roc:4271` | The id and the edges are the same before and after a write of the row, and both sides are evaluated at the same moment, so `<p on $before>` equals `<p>` |

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

## Not done

- `o.items.any(|i| i.product.id() == products.id(p.id))` (a relation inside a nested list operation) falls back to every row.
- `record::id(x) = record::id(id)` (a key compared with a key, `o.customer.get().id == c.id`) narrows with `WHERE record::id(id) IN ..`, a scan of the result's table per write, not `FROM <record>`.
