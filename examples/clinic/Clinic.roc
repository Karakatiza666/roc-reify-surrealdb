import surreal.Surreal

# Predicates, costs and query fragments that `main.roc` uses, each over any
# row that has the fields it reads. Each annotation has an open row (`..r`), and some call
# another one. A clause that takes one is described at the row of its table,
# so the SurrealQL is the same as for a function over that row.
Clinic :: {}.{

	## The cost of one line of medication: the doses times the unit price.
	dose_cost : { doses : I64, medication : Surreal.Link({ unit_price : Dec, ..m }), ..d } -> Dec
	dose_cost = |d| d.doses.to_dec() * d.medication.get().unit_price

	## What a visit costs: the fee and the medication that was given.
	bill : { fee : Dec, items : List({ doses : I64, medication : Surreal.Link({ unit_price : Dec, ..m }), ..d }), ..r } -> Dec
	bill = |v| v.fee + v.items.map(|d| Clinic.dose_cost(d)).sum()

	## A line of medication gives at least one dose.
	positive_doses : { doses : I64, ..d } -> Bool
	positive_doses = |d| d.doses > 0

	## A visit that gave medication has a fee. It reads two fields, so it is
	## an event, not a field constraint.
	fee_covers_items : { fee : Dec, items : List(item), ..r } -> Bool
	fee_covers_items = |v| v.items.is_empty() or v.fee > 0

	seen_from : { seen : Surreal.Datetime, ..r }, Surreal.Datetime -> Bool
	seen_from = |v, at| v.seen >= at

	seen_before : { seen : Surreal.Datetime, ..r }, Surreal.Datetime -> Bool
	seen_before = |v, at| v.seen < at

	## Seen at or after the parameter `since`.
	seen_since : { since : Surreal.Datetime, ..p }, { seen : Surreal.Datetime, ..r } -> Bool
	seen_since = |p, v| Clinic.seen_from(v, p.since)

	## Seen before the parameter `cutoff`: past the retention time.
	too_old : { cutoff : Surreal.Datetime, ..p }, { seen : Surreal.Datetime, ..r } -> Bool
	too_old = |p, v| Clinic.seen_before(v, p.cutoff)

	## Less stock than the parameter `floor`.
	low_stock : { floor : I32, ..p }, { stock : I32, ..r } -> Bool
	low_stock = |p, m| m.stock < p.floor

	# Query fragments: each one takes a query over any row that has the
	# fields it reads, and adds a clause. The clause is described at the
	# row of each query that uses the fragment.

	## The rows seen at or after the parameter `since`.
	recent : Surreal.Query({ since : Surreal.Datetime, ..p }, { seen : Surreal.Datetime, ..r }) -> Surreal.Query({ since : Surreal.Datetime, ..p }, { seen : Surreal.Datetime, ..r })
	recent = |q| q.filter_by(Clinic.seen_since)

	## The result rows in the order of their `id`.
	by_id : Surreal.Selected(p, { id : Str, ..r }) -> Surreal.Selected(p, { id : Str, ..r })
	by_id = |s| s.order_by(|r| r.id, Asc)
}
