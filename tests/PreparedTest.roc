app [] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.5.0/B5U2mPsWTtuxfCRMzqQxio2ecDv7CAzCoyEMENMh4FNF.tar.zst",
	internal: "../src/internal.roc",
}

import internal.Surreal
import "fixtures/queries/fevers.cbor" as fevers_reply : List(U8)
import "fixtures/queries/kennel_a_rows.cbor" as kennel_a_rows_reply : List(U8)
import "fixtures/queries/busy_days.cbor" as busy_days_reply : List(U8)
import "fixtures/queries/all_totals.cbor" as all_totals_reply : List(U8)
import "fixtures/queries/no_totals.cbor" as no_totals_reply : List(U8)
import "fixtures/queries/fastest_pulses.cbor" as fastest_pulses_reply : List(U8)
import "fixtures/queries/sites_covering.cbor" as sites_covering_reply : List(U8)
import "fixtures/queries/kennel_carers.cbor" as kennel_carers_reply : List(U8)
import "fixtures/queries/create_kennel.cbor" as create_kennel_reply : List(U8)
import "fixtures/queries/create_kennel_again.cbor" as create_kennel_again_reply : List(U8)
import "fixtures/queries/relate_carer.cbor" as relate_carer_reply : List(U8)
import "fixtures/queries/relabel_then_read.cbor" as relabel_reply : List(U8)
import "fixtures/queries/insert_carers.cbor" as insert_carers_reply : List(U8)
import "fixtures/queries/create_reading.cbor" as create_reading_reply : List(U8)
import "fixtures/queries/delete_carers.cbor" as delete_carers_reply : List(U8)
import "fixtures/queries/oslo_site.cbor" as oslo_site_reply : List(U8)
import "fixtures/queries/oslo_value.cbor" as oslo_value_reply : List(U8)
import "fixtures/queries/upsert_carer.cbor" as upsert_carer_reply : List(U8)
import "fixtures/queries/insert_payments.cbor" as insert_payments_reply : List(U8)
import "fixtures/queries/payment_rows.cbor" as payment_rows_reply : List(U8)
import "fixtures/queries/payment_lines.cbor" as payment_lines_reply : List(U8)
import "fixtures/queries/twin_in_transaction.cbor" as twin_in_transaction_reply : List(U8)
import "fixtures/queries/bins_after_abort.cbor" as bins_after_abort_reply : List(U8)
import "fixtures/queries/twin_then_rows.cbor" as twin_then_rows_reply : List(U8)
import "fixtures/queries/stock_up.cbor" as stock_up_reply : List(U8)
import "fixtures/queries/twins_in_list.cbor" as twins_in_list_reply : List(U8)
import "fixtures/queries/spares_in_list.cbor" as spares_in_list_reply : List(U8)
import "fixtures/queries/unpin_labels.cbor" as unpin_labels_reply : List(U8)
import "fixtures/queries/pin_labels_again.cbor" as pin_labels_again_reply : List(U8)
import "fixtures/queries/create_shift.cbor" as create_shift_reply : List(U8)
import "fixtures/queries/insert_shifts.cbor" as insert_shifts_reply : List(U8)
import "fixtures/queries/insert_tasks.cbor" as insert_tasks_reply : List(U8)
import "fixtures/queries/relate_handover.cbor" as relate_handover_reply : List(U8)
import "fixtures/queries/shift_at_key.cbor" as shift_at_key_reply : List(U8)
import "fixtures/queries/delete_shift.cbor" as delete_shift_reply : List(U8)
import "fixtures/queries/insert_case_notes.cbor" as insert_case_notes_reply : List(U8)
import "fixtures/queries/ranked_notes.cbor" as ranked_notes_reply : List(U8)
import "fixtures/queries/close_notes.cbor" as close_notes_reply : List(U8)
import "fixtures/queries/close_coughs.cbor" as close_coughs_reply : List(U8)
import "fixtures/queries/insert_tallies.cbor" as insert_tallies_reply : List(U8)
import "fixtures/queries/insert_or_update.cbor" as insert_or_update_reply : List(U8)
import "fixtures/queries/tallies_bumped.cbor" as tallies_bumped_reply : List(U8)
import "fixtures/queries/merge_at.cbor" as merge_at_reply : List(U8)
import "fixtures/queries/upsert_merge_at.cbor" as upsert_merge_at_reply : List(U8)
import "fixtures/queries/merge_where.cbor" as merge_where_reply : List(U8)
import "fixtures/queries/patch_ops_at.cbor" as patch_ops_at_reply : List(U8)
import "fixtures/queries/patch_no_such_field.cbor" as patch_no_such_field_reply : List(U8)
import cbor.Cbor

# Tests of the typed results of plain queries and writes, without a server:
# the text of each request, and the reply to it, read as the type of the
# query. The files in `fixtures/queries/` are the replies that SurrealDB
# 4.0.1 sent to the requests of `client.roc` (`check.py --record fixtures`),
# on the rows that `check.py` leaves. Nothing outside this file imports it.

# ------------------------------------------------------- the domain of client.roc

Site : { id : Str, name : Str, location : Surreal.Point, area : Surreal.Polygon }

Kennel : { id : Str, label : Str, site : Surreal.Link(Site) }

Vital : { id : Surreal.TimeKey(Surreal.Id(Kennel)), pulse : I64, temp_c : Dec, fevered : Bool }

Carer : { id : Str, name : Str }

CaresFor : { id : Str, from : Surreal.Link(Carer), to : Surreal.Link(Kennel), lead : Bool }

CareRead : { id : Str, from : Surreal.Linked(Carer), to : Surreal.Link(Kennel), lead : Bool }

KennelRead : { id : Str, label : Str, site : Surreal.Linked(Site), cares_for : Surreal.In(CareRead) }

Daily : { kennel : Surreal.Id(Kennel), day : Surreal.Datetime, readings : I64, fevers : I64 }

sites : Surreal.Table(Site)
sites = Surreal.table("site")

kennels : Surreal.Table(Kennel)
kennels = Surreal.table("kennel")

kennel_reads : Surreal.Table(KennelRead)
kennel_reads = Surreal.table("kennel")

vitals : Surreal.Table(Vital)
vitals = Surreal.table("vital")

carers : Surreal.Table(Carer)
carers = Surreal.table("carer")

cares_for : Surreal.Table(CaresFor)
cares_for = Surreal.relation("cares_for", carers, kennels)

daily_view : Surreal.Table(Daily)
daily_view = Surreal.view("vital_daily")

fever : Dec, I64 -> Bool
fever = |temp_c, pulse| temp_c > 39.0 or pulse > 120

fever_fn : Surreal.DbFn((Dec, I64 -> Bool))
fever_fn = Surreal.db_fn("fever", fever)

moment : Str -> Surreal.Datetime
moment = |text| match Surreal.datetime(text) {
	Ok(d) => d
	Err(_) => crash "a valid datetime"
}

reading : Str, Str, I64, Dec -> Vital
reading = |kennel, at, pulse, temp_c| { id: Surreal.time_key(kennels.id(kennel), moment(at)), pulse, temp_c, fevered: fever(temp_c, pulse) }

day_start : Surreal.Datetime
day_start = moment("2026-03-01T00:00:00Z")

day_end : Surreal.Datetime
day_end = moment("2026-03-02T00:00:00Z")

VitalLine : { kennel : Surreal.Id(Kennel), at : Surreal.Datetime, pulse : I64, temp_c : Dec }

vital_line : Vital -> VitalLine
vital_line = |v| { kennel: v.id.series(), at: v.id.time(), pulse: v.pulse, temp_c: v.temp_c }

DayKey : { kennel : Surreal.Id(Kennel), day : Surreal.Datetime }

day_of : Vital -> DayKey
day_of = |v| { kennel: v.id.series(), day: Surreal.Time.floor(v.id.time(), Surreal.Time.days(1)) }

day_line : DayKey, List(Vital) -> Daily
day_line = |k, rows| { kennel: k.kennel, day: k.day, readings: rows.len().to_i64_wrap(), fevers: rows.keep_if(|v| fever_fn.call2(v.temp_c, v.pulse)).len().to_i64_wrap() }

## A prepared statement that translates.
ready : Surreal.Prepared(out) -> Surreal.Prepared(out)
ready = |prepared| match prepared.checked() {
	Ok(p) => p
	Err(_) => crash "the query of client.roc translates"
}

## The text of a request, or why there is none.
request_of : Surreal.Prepared(out) -> Try(Str, Surreal.Error)
request_of = |prepared| prepared.request()

fevers : Surreal.Prepared(List(VitalLine))
fevers = ready(Surreal.from(vitals).filter(|v| fever_fn.call2(v.temp_c, v.pulse)).select(vital_line).prepare({}))

kennel_a_rows : Surreal.Prepared(List(Vital))
kennel_a_rows = ready(Surreal.from(vitals).between(kennels.id("a"), day_start, day_end).select(|r| r).prepare({}))

daily : Surreal.Prepared(List(Daily))
daily = ready(Surreal.from(vitals).group_by(day_of).aggregate(day_line).prepare({}))

busy_days : Surreal.Prepared(List(Daily))
busy_days = ready(Surreal.from(vitals).group_by(day_of).aggregate(day_line).query().filter_by(|p, d| d.readings >= p.least).select(|r| r).prepare({ least: 2 }))

VitalTotals : { readings : I64, pulses : I64, heat : Dec, mean_pulse : F64 }

vital_totals : List(Vital) -> VitalTotals
vital_totals = |rows| { readings: rows.len().to_i64_wrap(), pulses: rows.map(|v| v.pulse).sum(), heat: rows.map(|v| v.temp_c).sum(), mean_pulse: Surreal.Math.mean(rows.map(|v| v.pulse.to_f64())) }

all_totals : Surreal.Prepared(VitalTotals)
all_totals = ready(Surreal.from(vitals).totals(vital_totals).prepare({}))

no_totals : Surreal.Prepared(VitalTotals)
no_totals = ready(Surreal.from(vitals).filter(|v| v.pulse > 1000).totals(vital_totals).prepare({}))

fastest_pulses : Surreal.Prepared(List(I64))
fastest_pulses = ready(Surreal.from(vitals).select_value(|v| v.pulse).order_by(|n| n, Desc).limit(3).filter(|n| n < 130).prepare({}))

sites_covering : Surreal.Prepared(List(Str))
sites_covering = ready(Surreal.from(sites).filter_by(|p, s| Surreal.Geo.inside(p.here.to_geometry(), s.area.to_geometry())).select_value(|s| s.id).prepare({ here: Surreal.point(10.75, 59.91) }))

oslo_site : Surreal.Prepared(Try(Site, [NotFound]))
oslo_site = ready(sites.at(sites.id("oslo")).select(|r| r).prepare_one({}))

oslo_value : Surreal.Prepared(Try(Site, [NotFound]))
oslo_value = ready(sites.at(sites.id("oslo")).select_value(|r| r).prepare_one({}))

rectangle : Surreal.Point, Surreal.Point -> Surreal.Polygon
rectangle = |sw, ne| Surreal.Polygon.({ exterior: [sw, Surreal.point(ne.lon(), sw.lat()), ne, Surreal.point(sw.lon(), ne.lat()), sw], holes: [] })

oslo : Site
oslo = { id: "oslo", name: "Oslo", location: Surreal.point(10.75, 59.91), area: rectangle(Surreal.point(10.6, 59.85), Surreal.point(10.9, 60.0)) }

KennelCarers : { label : Str, site : Str, carers : List(Surreal.Linked(Carer)), leads : I64 }

kennel_carers : Surreal.Prepared(List(KennelCarers))
kennel_carers = ready(Surreal.from(kennel_reads).select(|k| { label: k.label, site: k.site.name, carers: k.cares_for.list().map(|e| e.from), leads: k.cares_for.list().keep_if(|e| e.lead).len().to_i64_wrap() }).prepare({}))

quay : Kennel
quay = { id: "q", label: "Quay", site: sites.link("oslo") }

quay_wing : Kennel
quay_wing = { ..quay, label: "Quay wing" }

ida_quay : CaresFor
ida_quay = { id: "ida_q", from: carers.link("ida"), to: kennels.link("q"), lead: Bool.True }

new_carers : List(Carer)
new_carers = [{ id: "kim", name: "Kim" }, { id: "lea", name: "Lea" }]

kim_b : Carer
kim_b = { id: "kim", name: "Kim B" }

noon : Vital
noon = { ..reading("a", "2026-03-10T12:00:00Z", 85, 39.4), fevered: Bool.False }

KennelLine : { label : Str, carers : I64 }

relabel_write : Surreal.Prepared(List(Kennel))
relabel_write = kennels.update_by(|p, k| k.id == p.key, |p, k| { ..k, label: p.label }).prepare({ key: "q", label: "Quay wing" })

relabel_read : Surreal.Prepared(List(KennelLine))
relabel_read = Surreal.from(kennel_reads).filter_by(|p, k| k.id == p.key).select(|k| { label: k.label, carers: k.cares_for.list().len().to_i64_wrap() }).prepare({ key: "q" })

relabel : Surreal.Prepared((Try(List(Kennel), Surreal.Error), Try(List(KennelLine), Surreal.Error)))
relabel = relabel_write.then(relabel_read)

remove_carers : Surreal.Prepared(List(Carer))
remove_carers = carers.delete(|c| c.id == "kim" or c.id == "lea").prepare({})

## Each form of an arm: no payload, a record, one value, two values.
Pay : [Cash, Card({ last4 : Str }), Check(I64), Wire(Str, I64)]

Payment : { id : Str, pay : Pay }

payments : Surreal.Table(Payment)
payments = Surreal.table("payment")

paid : List(Payment)
paid = [
	{ id: "cash", pay: Cash },
	{ id: "card", pay: Card({ last4: "4242" }) },
	{ id: "check", pay: Check(7) },
	{ id: "wire", pay: Wire("eu", 9) },
]

PaymentLine : { id : Str, amount : I64 }

payment_line : Payment -> PaymentLine
payment_line = |p| {
	id: p.id,
	amount: match p.pay {
		Cash => 0
		Card(_) => 1
		Check(n) => n
		Wire(_, n) => n
	},
}

payment_rows : Surreal.Prepared(List(Payment))
payment_rows = ready(Surreal.from(payments).select(|r| r).prepare({}))

payment_lines : Surreal.Prepared(List(PaymentLine))
payment_lines = ready(Surreal.from(payments).select(payment_line).prepare({}))

## The text of a reading: a `TimeKey` has no `==`.
facts : Vital -> Str
facts = |v| "${vitals.ref(v).map_ok(|r| r.to_str()) ?? "?"} pulse ${v.pulse.to_str()} temp_c ${v.temp_c.to_str()} fevered ${Str.inspect(v.fevered)}"

# ------------------------------------------------------- the requests

# A query: the text of `prepare`, and a `LET` for each parameter.
expect request_of(fevers) == Surreal.from(vitals).filter(|v| fever_fn.call2(v.temp_c, v.pulse)).select(vital_line).prepare({}).request()
expect busy_days.request().map_ok(|t| t.starts_with("LET $least = 2;\nSELECT ")) == Ok(Bool.True)

# A write of one row returns the row as stored: after a create, a relate
# and a replace, before a delete.
expect request_of(kennels.create(quay)) == Ok("CREATE kennel:⟨q⟩ CONTENT { label: 'Quay', site: site:⟨oslo⟩ } RETURN AFTER;")
expect request_of(kennels.edit(Replace(quay, quay_wing))) == Ok("UPDATE kennel:⟨q⟩ CONTENT { label: 'Quay wing', site: site:⟨oslo⟩ } RETURN AFTER;")
expect request_of(kennels.edit(Delete(quay))) == Ok("DELETE kennel:⟨q⟩ RETURN BEFORE;")
expect request_of(cares_for.create(ida_quay)) == Ok("RELATE carer:⟨ida⟩->cares_for:⟨ida_q⟩->kennel:⟨q⟩ CONTENT { lead: true } RETURN AFTER;")

# A write by key reads the one record: the key, or the row, and no other row.
expect request_of(kennels.replace(quay_wing)) == Ok("UPDATE kennel:⟨q⟩ CONTENT { label: 'Quay wing', site: site:⟨oslo⟩ } RETURN AFTER;")
expect request_of(kennels.delete_at(kennels.id("q")).prepare({})) == Ok("DELETE kennel:⟨q⟩ RETURN BEFORE;")
expect request_of(cares_for.delete_at(cares_for.id("ida_q")).prepare({})) == Ok("DELETE cares_for:⟨ida_q⟩ RETURN BEFORE;")
expect request_of(kennels.update_at_by(kennels.id("q"), |p, k| { ..k, label: p.label }).prepare({ label: "Quay wing" })) == Ok("LET $label = 'Quay wing';\nUPDATE kennel:⟨q⟩ SET label = $label RETURN AFTER;")
expect request_of(kennels.delete_at(Surreal.Unchecked.id("site", "q")).prepare({})) == Err(Unsupported("the id `site:⟨q⟩` is not of the table `kennel`"))
expect request_of(daily_view.replace({ kennel: kennels.id("a"), day: day_start, readings: 1, fevers: 0 })) == Err(Unsupported("`vital_daily` is a view, and a view is read-only"))

# The row of one key: `FROM` the record, read as the row or `NotFound`.
expect oslo_site.request() == Ok("SELECT area, record::id(id) AS id, location, name FROM site:⟨oslo⟩;")
expect oslo_value.request() == Ok("SELECT VALUE { area: area, id: record::id(id), location: location, name: name } FROM site:⟨oslo⟩;")
expect request_of(Surreal.from(sites).select(|r| r).prepare_one({})) == Err(Unsupported("`prepare_one` reads the row of one key, a query from `Table.at`; this query can return several rows: take `prepare`"))

expect request_of(carers.upsert(kim_b)) == Ok("UPSERT carer:⟨kim⟩ CONTENT { name: 'Kim B' } RETURN AFTER;")

# An insert is one transaction.
expect request_of(carers.insert(new_carers)) == Ok("BEGIN;\nINSERT INTO carer [{ id: 'kim', name: 'Kim' }, { id: 'lea', name: 'Lea' }] RETURN AFTER;\nCOMMIT;")

# An update and a delete of the rows that a clause keeps.
expect request_of(remove_carers) == Ok("DELETE carer WHERE (IF record::id(id) = 'kim' THEN true ELSE record::id(id) = 'lea' END) RETURN BEFORE;")

# Two statements in one request: the `LET`s of both, each name once.
expect request_of(relabel) == Ok("LET $key = 'q';\nLET $label = 'Quay wing';\nUPDATE kennel SET label = $label WHERE id = type::record('kennel', $key) RETURN AFTER;\nSELECT <-cares_for.len() AS carers, label AS label FROM kennel WHERE id = type::record('kennel', $key);")

# A tag union: the arm in `kind`, one payload in `value`, two in the array `value`.
expect request_of(payments.insert(paid)) == Ok("BEGIN;\nINSERT INTO payment [{ id: 'cash', pay: 'Cash' }, { id: 'card', pay: { kind: 'Card', last4: '4242' } }, { id: 'check', pay: { kind: 'Check', value: 7 } }, { id: 'wire', pay: { kind: 'Wire', value: ['eu', 9] } }] RETURN AFTER;\nCOMMIT;")
expect payment_lines.request() == Ok("SELECT (IF pay.kind = 'Card' THEN 1 ELSE IF pay = 'Cash' THEN 0 ELSE IF pay.kind = 'Check' THEN pay.value ELSE pay.value[1] END) AS amount, record::id(id) AS id FROM payment;")

# A view is read-only, for a delete too.
expect daily_view.edit(Delete({ kennel: kennels.id("a"), day: day_start, readings: 1, fevers: 0 })).checked().map_ok(|_| {}) == Err(Unsupported("`vital_daily` is a view, and a view is read-only"))

# ------------------------------------------------------- the replies

## The rows read, and the rows of Roc, are the same multiset of texts.
same_rows : Try(List(a), Surreal.Error), List(a) -> Bool
same_rows = |got, want| match got {
	Ok(rows) => {
		have = rows.map(Str.inspect)
		need = want.map(Str.inspect)
		have.len() == need.len() and need.all(|w| have.count_if(|h| h == w) == need.count_if(|n| n == w))
	}
	Err(_) => Bool.False
}

## The rows of the readings that the retention write keeps.
kept_vitals : List(Vital)
kept_vitals = [
	reading("a", "2026-03-01T00:00:00Z", 82, 38.4),
	reading("a", "2026-03-01T08:00:00Z", 80, 38.5),
	reading("a", "2026-03-01T14:30:00Z", 90, 39.5),
	reading("a", "2026-03-02T00:00:00Z", 85, 38.6),
	reading("a", "2026-03-02T09:15:00Z", 125, 38.0),
	reading("b", "2026-03-01T10:00:00Z", 120, 39.0),
	reading("b", "2026-03-01T23:59:59.5Z", 130, 38.0),
	reading("b", "2026-03-02T11:00:00Z", 121, 39.1),
]

rollup : List(Vital) -> List(Daily)
rollup = |rows| {
	keys = rows.map(day_of).fold([], |seen, k| if (seen.contains(k)) seen else seen.append(k))
	keys.map(|k| day_line(k, rows.keep_if(|v| day_of(v) == k)))
}

# Result rows: record ids (tag 8), datetimes (tag 12), decimals (tag 10).
expect same_rows(fevers.result(fevers_reply), kept_vitals.keep_if(|v| fever(v.temp_c, v.pulse)).map(vital_line))

# The whole rows, with the key as the array `[kennel, time]`.
expect kennel_a_rows.result(kennel_a_rows_reply).map_ok(|rows| rows.map(facts)) == Ok(kept_vitals.keep_if(|v| v.id.within(kennels.id("a"), day_start, day_end)).map(facts))

# The `LET` has a result, which is not read.
expect same_rows(busy_days.result(busy_days_reply), rollup(kept_vitals).keep_if(|d| d.readings >= 2))

# `GROUP ALL`: the row itself, not a list. For no rows it is the row of
# the server's values: 0 and `NaN` (CBOR half float 0x7e00).
expect all_totals.result(all_totals_reply).map_ok(Str.inspect) == Ok(Str.inspect(vital_totals(kept_vitals)))
expect no_totals.result(no_totals_reply).map_ok(Str.inspect) == Ok(Str.inspect(vital_totals([])))
expect no_totals.result(no_totals_reply).map_ok(|t| t.readings) == Ok(0)
expect no_totals.result(no_totals_reply).map_ok(|t| t.mean_pulse != t.mean_pulse) == Ok(Bool.True)

# The order of the server.
expect fastest_pulses.result(fastest_pulses_reply) == Ok([125, 121])
expect sites_covering.result(sites_covering_reply) == Ok(["oslo"])

# Geometries: a point (tag 88) and a polygon (tag 90).
expect oslo_site.result(oslo_site_reply) == Ok(Ok(oslo))
# The same row through `select_value`: `id` is the key, not the record id.
expect oslo_value.result(oslo_value_reply) == Ok(Ok(oslo))

# A read row: a linked row in a list of edges.
expect same_rows(kennel_carers.result(kennel_carers_reply), [{ label: "North", site: "Oslo", carers: [Surreal.linked({ id: "ida", name: "Ida" })], leads: 1 }, { label: "South", site: "Bergen", carers: [], leads: 0 }])

# A stored row: the record id is its key, and a link is not fetched.
expect ready(kennels.create(quay)).result(create_kennel_reply) == Ok([quay])

# The ends of a stored edge are `in` and `out`, and the Roc row's `from` and `to`.
expect ready(cares_for.create(ida_quay)).result(relate_carer_reply) == Ok([ida_quay])

# The database computes `fevered` of the row that it returns.
expect ready(vitals.create(noon)).result(create_reading_reply).map_ok(|rows| rows.map(facts)) == Ok([facts({ ..noon, fevered: Bool.True })])

# An insert: the rows are the result of the second of three statements.
expect ready(carers.insert(new_carers)).result(insert_carers_reply) == Ok(new_carers)

# A delete returns the rows before it.
expect ready(carers.upsert(kim_b)).result(upsert_carer_reply) == Ok([kim_b])
expect same_rows(ready(remove_carers).result(delete_carers_reply), [kim_b, { id: "lea", name: "Lea" }])

# Two `LET`s, then the results of two statements, each read as its type.
expect ready(relabel).result(relabel_reply) == Ok((Ok([quay_wing]), Ok([{ label: "Quay wing", carers: 1 }])))

# Rows with a tag union, in the form that the ORM writes: a row of each
# form of an arm, read as `Pay`.
expect ready(payments.insert(paid)).result(insert_payments_reply) == Ok(paid)
expect same_rows(payment_rows.result(payment_rows_reply), paid)
expect same_rows(payment_lines.result(payment_lines_reply), paid.map(payment_line))

# A statement that fails is a `Server` error with the message of the server.
expect ready(kennels.create(quay)).result(create_kennel_again_reply) == Err(Server(Exists({ what: "Record", name: "kennel:q", message: "Database record `kennel:q` already exists" })))

# A reply to another request: the count of the results differs.
expect daily.result(busy_days_reply) == Err(Wire("a reply of 2 results to 1 statements"))

# Rows that do not fit the type. A row is read on its own (`Surreal.row_of`),
# so the place is in the row: a map where an `I64` must be.
expect fastest_pulses.result(fevers_reply).map_ok(|_| {}) == Err(Decode({ path: "", message: "the value at byte 0 does not fit its Roc type" }))

# ---------------------------------------------- transactions and batches

Bin : { id : Str, label : Str }

bins : Surreal.Table(Bin)
bins = Surreal.table("bin")

stock : List(Bin)
stock = [{ id: "b1", label: "Top" }]

twin_bin : Bin
twin_bin = { id: "b2", label: "Top" }

side_bin : Bin
side_bin = { id: "b3", label: "Side" }

low_bin : Bin
low_bin = { id: "b4", label: "Low" }

bin_rows : Surreal.Prepared(List(Bin))
bin_rows = Surreal.from(bins).select(|r| r).prepare({})

batch : Surreal.Prepared(a), Surreal.Prepared(b) -> Surreal.Prepared((Try(a, Surreal.Error), Try(b, Surreal.Error)))
batch = |first, second| first.then(second)

atomic : Surreal.Prepared(a), Surreal.Prepared(b) -> Surreal.Prepared((a, b))
atomic = |first, second| first.begin().then(second).commit()

atomic3 : Surreal.Prepared(a), Surreal.Prepared(b), Surreal.Prepared(c) -> Surreal.Prepared(((a, b), c))
atomic3 = |first, second, third| first.begin().then(second).then(third).commit()

twin_in_transaction : Surreal.Prepared((List(Bin), List(Bin)))
twin_in_transaction = atomic(bins.create(side_bin), bins.insert([low_bin, twin_bin]))

twin_then_rows : Surreal.Prepared((Try(List(Bin), Surreal.Error), Try(List(Bin), Surreal.Error)))
twin_then_rows = batch(bins.create(twin_bin), bin_rows)

stock_up : Surreal.Prepared(((List(Bin), List(Bin)), List(Bin)))
stock_up = atomic3(bins.create(side_bin), bins.insert([low_bin]), bin_rows)

## The error of the unique index on `bin.label`, with no schema known.
label_taken : Surreal.ServerError
label_taken = Index({ index: "bin_label_unique", value: "'Top'", record: "bin:b1", message: "Database index `bin_label_unique` already contains 'Top', with record `bin:b1`" })

# A transaction is one `BEGIN`, the statements of each part, one `COMMIT`:
# the insert, a transaction of its own, has none of its own in it.
expect request_of(twin_in_transaction) == Ok("BEGIN;\nCREATE bin:⟨b3⟩ CONTENT { label: 'Side' } RETURN AFTER;\nINSERT INTO bin [{ id: 'b4', label: 'Low' }, { id: 'b2', label: 'Top' }] RETURN AFTER;\nCOMMIT;")
expect request_of(bins.insert([low_bin])) == Ok("BEGIN;\nINSERT INTO bin [{ id: 'b4', label: 'Low' }] RETURN AFTER;\nCOMMIT;")
expect request_of(twin_then_rows) == Ok("CREATE bin:⟨b2⟩ CONTENT { label: 'Top' } RETURN AFTER;\nSELECT record::id(id) AS id, label FROM bin;")

# The insert, the second part, fails the transaction: the error is its
# own, at its place, and the create before it is rolled back.
expect ready(twin_in_transaction).result(twin_in_transaction_reply) == Err(Aborted({ at: 1, error: label_taken }))
expect ready(bin_rows).result(bins_after_abort_reply) == Ok(stock)

# On their own, each statement keeps its result: the create fails, and
# the read after it has the rows.
expect ready(twin_then_rows).result(twin_then_rows_reply) == Ok((Err(Server(label_taken)), Ok(stock)))

# A transaction that commits: the result of each part, nested as the
# `then`s nest.
expect ready(stock_up).result(stock_up_reply) == Ok((([side_bin], [low_bin]), List.concat(stock, [side_bin, low_bin])))

# A transaction is one part of a batch: its failure is the error of its side.
expect batch(twin_in_transaction, bin_rows).request() == Ok("BEGIN;\nCREATE bin:⟨b3⟩ CONTENT { label: 'Side' } RETURN AFTER;\nINSERT INTO bin [{ id: 'b4', label: 'Low' }, { id: 'b2', label: 'Top' }] RETURN AFTER;\nCOMMIT;\nSELECT record::id(id) AS id, label FROM bin;")

# A list of writes of one type as one transaction (`Surreal.transaction`).
all_of : List(Surreal.Prepared(a)) -> Surreal.Prepared(List(a))
all_of = |writes| Surreal.transaction(writes)

spare_bin : Bin
spare_bin = { id: "b5", label: "Spare" }

rack_bin : Bin
rack_bin = { id: "b6", label: "Rack" }

twins_in_list : Surreal.Prepared(List(List(Bin)))
twins_in_list = all_of([bins.create(spare_bin), bins.create(twin_bin)])

expect request_of(twins_in_list) == Ok("BEGIN;\nCREATE bin:⟨b5⟩ CONTENT { label: 'Spare' } RETURN AFTER;\nCREATE bin:⟨b2⟩ CONTENT { label: 'Top' } RETURN AFTER;\nCOMMIT;")
expect Surreal.transaction([]).request() == Err(Unsupported("a transaction needs a statement"))

# The second create fails all: the error is at its place. When all commit,
# the result is the result of each, in order.
expect ready(twins_in_list).result(twins_in_list_reply) == Err(Aborted({ at: 1, error: label_taken }))
expect ready(all_of([bins.create(spare_bin), bins.create(rack_bin)])).result(spares_in_list_reply) == Ok([[spare_bin], [rack_bin]])

# A section of a migration is one transaction with no result: the removal
# of the unique index applies, and the index again, over two bins with one
# label, fails with the error of the index.
migrate : List(Surreal.Defined), List(Surreal.Defined) -> Surreal.Prepared({})
migrate = |old, new| match Surreal.plan(Surreal.schema(old) ?? "", new).map_ok(|p| p.prepare(DropData)) {
	Ok(Ok([one])) => one
	_ => crash "the schemas of client.roc translate, and each migration is one section"
}

pinned : List(Surreal.Defined)
pinned = [bins.define().unique(|b| b.label).done()]

loose : List(Surreal.Defined)
loose = [bins.define().done()]

expect migrate(pinned, loose).request() == Ok("BEGIN;\nREMOVE INDEX IF EXISTS bin_label_unique ON bin;\nCOMMIT;")
expect migrate(pinned, loose).result(unpin_labels_reply) == Ok({})
expect migrate(loose, pinned).result(pin_labels_again_reply) == Err(Server(label_taken))

# A migration with no statement has no section, so nothing is sent.
expect Surreal.plan(Surreal.schema(loose) ?? "", loose).map_ok(|p| p.prepare(DropData).map_ok(|all| all.len())) == Ok(Ok(0))

# ------------------------------------------- keys that the server makes

Shift : { id : Str, label : Str }

Task : { id : Str, title : Str, shift : Surreal.Link(Shift) }

Handover : { id : Str, from : Surreal.Link(Shift), to : Surreal.Link(Shift), notes : Str }

shifts : Surreal.Table(Shift)
shifts = Surreal.table("shift")

tasks : Surreal.Table(Task)
tasks = Surreal.table("task")

handovers : Surreal.Table(Handover)
handovers = Surreal.relation("handover", shifts, shifts)

## The keys that SurrealDB gave in the recorded replies: ULIDs of the
## shifts, from `DEFAULT rand::ulid()` on `id`.
early : Surreal.Id(Shift)
early = shifts.id("01M7911XWVP2307M56XCDKCQWS")

late : Surreal.Id(Shift)
late = shifts.id("01M7911XWWTBV4SZQC1QV464QD")

night : Surreal.Id(Shift)
night = shifts.id("01M7911XWX4QRHBARKWT9D3V0F")

feed : { title : Str, shift : Surreal.Link(Shift) }
feed = { title: "Feed", shift: shifts.link(early.key()) }

walk : { title : Str, shift : Surreal.Link(Shift) }
walk = { title: "Walk", shift: shifts.link(late.key()) }

handover : { from : Surreal.Link(Shift), to : Surreal.Link(Shift), notes : Str }
handover = { from: shifts.link(early.key()), to: shifts.link(late.key()), notes: "keys" }

# A write of a row with no `id` has no key in its text.
expect request_of(shifts.create_new({ label: "Early" })) == Ok("CREATE shift CONTENT { label: 'Early' } RETURN AFTER;")
expect request_of(shifts.insert_new([{ label: "Late" }, { label: "Night" }])) == Ok("BEGIN;\nINSERT INTO shift [{ label: 'Late' }, { label: 'Night' }] RETURN AFTER;\nCOMMIT;")
expect request_of(handovers.create_new(handover)) == Ok("RELATE shift:⟨01M7911XWVP2307M56XCDKCQWS⟩->handover->shift:⟨01M7911XWWTBV4SZQC1QV464QD⟩ CONTENT { notes: 'keys' } RETURN AFTER;")

# The result is each row that the write made: the key that the server gave
# it, as an `Id` of the table, and its other fields, in the order written.
expect ready(shifts.create_new({ label: "Early" })).result(create_shift_reply) == Ok([{ id: early, fields: { label: "Early" } }])
expect ready(shifts.insert_new([{ label: "Late" }, { label: "Night" }])).result(insert_shifts_reply) == Ok([{ id: late, fields: { label: "Late" } }, { id: night, fields: { label: "Night" } }])

# A link to a row with a key from the server, and a UUID key, as text.
expect ready(tasks.insert_new([feed, walk])).result(insert_tasks_reply) == Ok([{ id: tasks.id("01a1d210-f79e-77e0-b588-1324ffd4dc5a"), fields: feed }, { id: tasks.id("01a1d210-f79e-77e0-b588-13259488a7ac"), fields: walk }])

# An edge with SurrealDB's random key: its ends are `from` and `to`.
expect ready(handovers.create_new(handover)).result(relate_handover_reply) == Ok([{ id: handovers.id("956wn0p4gj5ik7k4a6er"), fields: handover }])

# The `Id` of a row that the server keyed reads and deletes it by key. As
# in `client.roc`, the key is the argument of a function, so the request
# binds it with a `LET` and its reply has two results.
shift_at : Surreal.Id(Shift) -> Surreal.Prepared(Try(Shift, [NotFound]))
shift_at = |key| shifts.at(key).ready_one()

delete_shift : Surreal.Id(Shift) -> Surreal.Prepared(List(Shift))
delete_shift = |key| shifts.delete_at(key).ready()

expect ready(shift_at(early)).result(shift_at_key_reply) == Ok(Ok({ id: early.key(), label: "Early" }))
expect ready(delete_shift(early)).result(delete_shift_reply) == Ok([{ id: early.key(), label: "Early" }])

# A reply to a write of another table: the key is of `shift`, not `task`.
expect ready(tasks.create_new(feed)).result(create_shift_reply).map_ok(|rows| rows.map(|r| r.id)) == Err(Wire("a row that a write of `task` made has no text key of `task`"))

# A create and an insert of rows with no key, in one transaction.
expect atomic(shifts.create_new({ label: "Early" }), shifts.insert_new([{ label: "Late" }])).request() == Ok("BEGIN;\nCREATE shift CONTENT { label: 'Early' } RETURN AFTER;\nINSERT INTO shift [{ label: 'Late' }] RETURN AFTER;\nCOMMIT;")

# ------------------------------------------------ full-text and vector search

CaseNote : { id : Str, body : Str, embedding : List(F64) }

case_notes : Surreal.Table(CaseNote)
case_notes = Surreal.table("case_note")

case_terms : Surreal.Analyzer
case_terms = Surreal.analyzer("case_terms", [Blank, Class], [Lowercase])

case_text : Surreal.FullText(CaseNote)
case_text = case_notes.text_index(|n| n.body, case_terms)

case_vectors : Surreal.VectorIndex(CaseNote)
case_vectors = case_notes.vector_index(|n| n.embedding, { dimension: 2, distance: Euclidean })

seed_case_notes : List(CaseNote)
seed_case_notes = [
	{ id: "n1", body: "Coughing at night, mild fever.", embedding: [0.0, 1.0] },
	{ id: "n2", body: "Fever gone, eating well.", embedding: [1.0, 1.0] },
	{ id: "n3", body: "Night cough again; X-ray booked.", embedding: [0.2, 0.9] },
	{ id: "n4", body: "Booster given.", embedding: [3.0, 0.0] },
	{ id: "n5", body: "Nail trim, no signs of pain.", embedding: [2.0, 2.0] },
]

cough : List(F64)
cough = [0.1, 0.8]

ranked_notes : Surreal.Prepared(List({ id : Str, score : F64, marked : Str }))
ranked_notes = Surreal.from(case_notes).search(case_text, "fever").select(|(n, hit)| { id: n.id, score: hit.score(), marked: hit.highlight("*", "*") }).order_by(|r| r.score, Desc).prepare({})

close_notes : Surreal.Prepared(List({ id : Str, distance : F64 }))
close_notes = Surreal.from(case_notes).nearest(case_vectors, cough, Exact(2)).select(|(n, near)| { id: n.id, distance: near.distance() }).order_by(|r| r.distance, Asc).prepare({})

close_coughs : Surreal.Prepared(List(Str))
close_coughs = Surreal.from(case_notes).filter(|n| n.id != "n3").nearest(case_vectors, cough, Approx({ k: 1, ef: 40 })).select_value(|(n, _)| n.id).prepare({})

expect request_of(ranked_notes) == Ok("SELECT record::id(id) AS id, search::highlight('*', '*', 1) AS marked, search::score(1) AS score FROM case_note WHERE body @1@ 'fever' ORDER BY score DESC;")
expect request_of(close_notes) == Ok("SELECT vector::distance::knn() AS distance, record::id(id) AS id FROM case_note WHERE embedding <|2,EUCLIDEAN|> [0.1f, 0.8f] ORDER BY distance;")
expect request_of(close_coughs) == Ok("SELECT VALUE record::id(id) FROM case_note WHERE (id != case_note:⟨n3⟩) AND (embedding <|1,40|> [0.1f, 0.8f]);")

# The notes as stored, with their embeddings.
expect ready(case_notes.insert(seed_case_notes)).result(insert_case_notes_reply) == Ok(seed_case_notes)

# The notes of the term, the best first, each with a score above 0 and
# the term marked. The rows are the ones the analyzer keeps in Roc.
expect
	ready(ranked_notes).result(ranked_notes_reply).map_ok(|rows| rows.map(|r| { id: r.id, marked: r.marked }))
	== Ok([{ id: "n2", marked: "*Fever* gone, eating well." }, { id: "n1", marked: "Coughing at night, mild *fever*." }])
expect
	match ready(ranked_notes).result(ranked_notes_reply) {
		Ok([first, second]) => first.score > second.score and second.score > 0
		_ => Bool.False
	}
expect seed_case_notes.keep_if(|n| case_terms.matches(n.body, "fever")).map(|n| n.id) == ["n1", "n2"]

# By `EUCLIDEAN` over `F64`, the distance of each row is the Roc distance.
expect ready(close_notes).result(close_notes_reply) == Ok([{ id: "n3", distance: Surreal.Vector.distance_euclidean([0.2, 0.9], cough) }, { id: "n1", distance: Surreal.Vector.distance_euclidean([0.0, 1.0], cough) }])
expect ready(close_coughs).result(close_coughs_reply) == Ok(["n1"])

# ------------------------------------------- merge, patch, insert or update

Tally : { id : Str, label : Str, hits : I64, meta : { a : I64, b : I64 }, tags : List(Str) }

tallies : Surreal.Table(Tally)
tallies = Surreal.table("tally")

tally : Str, Str, I64 -> Tally
tally = |id, label, hits| { id, label, hits, meta: { a: 1, b: 2 }, tags: [] }

seed_tallies : List(Tally)
seed_tallies = [tally("t1", "One", 1), tally("t2", "Two", 20)]

bump : Tally, Tally -> Tally
bump = |new, old| { ..old, label: new.label, hits: old.hits + new.hits }

incoming : List(Tally)
incoming = [tally("t1", "Uno", 5), tally("t3", "Three", 3)]

bumped_t1 : Tally
bumped_t1 = { ..tally("t1", "Uno", 6), meta: { a: 1, b: 2 } }

four : Tally
four = { id: "t4", label: "Four", hits: 12, meta: { a: 3, b: 4 }, tags: ["new"] }

patch_ops : List(Surreal.Op)
patch_ops = [Replace(["label"], Cbor.Value.Text("Patched")), Add(["tags", "-"], Cbor.Value.Text("p")), Replace(["meta", "b"], Cbor.Value.Int(7))]

expect request_of(tallies.insert_or_update(incoming, bump)) == Ok("BEGIN;\nINSERT INTO tally [{ hits: 5, id: 't1', label: 'Uno', meta: { a: 1, b: 2 }, tags: [] }, { hits: 3, id: 't3', label: 'Three', meta: { a: 1, b: 2 }, tags: [] }] ON DUPLICATE KEY UPDATE hits = hits + $input.hits, label = $input.label RETURN AFTER;\nCOMMIT;")
expect request_of(tallies.merge_at(tallies.id("t1"), { label: "Merged", meta: { a: 9.I64 } })) == Ok("UPDATE tally:⟨t1⟩ MERGE { label: 'Merged', meta: { a: 9 } } RETURN AFTER;")
expect request_of(tallies.upsert_merge_at(tallies.id("t4"), { label: four.label, hits: four.hits, meta: four.meta, tags: four.tags })) == Ok("UPSERT tally:⟨t4⟩ MERGE { hits: 12, label: 'Four', meta: { a: 3, b: 4 }, tags: ['new'] } RETURN AFTER;")
expect request_of(tallies.merge(|t| t.hits > 10, { tags: ["hot"] })) == Ok("UPDATE tally MERGE { tags: ['hot'] } WHERE hits > 10 RETURN AFTER;")
expect request_of(tallies.patch_ops_at(tallies.id("t3"), patch_ops)) == Ok("UPDATE tally:⟨t3⟩ PATCH [{ op: 'replace', path: '/label', value: 'Patched' }, { op: 'add', path: '/tags/-', value: 'p' }, { op: 'replace', path: '/meta/b', value: 7 }] RETURN AFTER;")

# The rows as stored, read as `Tally`.
expect ready(tallies.insert(seed_tallies)).result(insert_tallies_reply) == Ok(seed_tallies)
expect ready(tallies.insert_or_update(incoming, bump)).result(insert_or_update_reply) == Ok([bumped_t1, tally("t3", "Three", 3)])
expect ready(tallies.merge_at(tallies.id("t1"), { label: "Merged", meta: { a: 9.I64 } })).result(merge_at_reply) == Ok([{ ..bumped_t1, label: "Merged", meta: { a: 9, b: 2 } }])
expect ready(tallies.upsert_merge_at(tallies.id("t4"), { label: four.label, hits: four.hits, meta: four.meta, tags: four.tags })).result(upsert_merge_at_reply) == Ok([four])
expect ready(tallies.merge(|t| t.hits > 10, { tags: ["hot"] })).result(merge_where_reply) == Ok([{ ..tally("t2", "Two", 20), tags: ["hot"] }, { ..four, tags: ["hot"] }])
expect ready(tallies.patch_ops_at(tallies.id("t3"), patch_ops)).result(patch_ops_at_reply) == Ok([{ ..tally("t3", "Three", 3), label: "Patched", tags: ["p"], meta: { a: 1, b: 7 } }])
# A path that the row does not have is the server's error.
expect
	match ready(tallies.patch_ops_at(tallies.id("t3"), [Replace(["nope"], Cbor.Value.Int(1))])).result(patch_no_such_field_reply) {
		Err(Server(e)) => e.message().contains("no such field")
		_ => Bool.False
	}
expect ready(Surreal.from(tallies).select(|r| r).prepare({})).result(tallies_bumped_reply).map_ok(|rows| rows.map(|t| t.id)) == Ok(["t1", "t2", "t3"])
