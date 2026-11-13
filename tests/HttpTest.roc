app [] {
	cbor: "https://github.com/Karakatiza666/roc-cbor/releases/download/0.5.0/B5U2mPsWTtuxfCRMzqQxio2ecDv7CAzCoyEMENMh4FNF.tar.zst",
	internal: "../src/internal.roc",
}

import internal.HttpRpc
import internal.Surreal
import "fixtures/http/fastest_pulses.cbor" as fastest_pulses_http : List(U8)
import "fixtures/http/sites_covering.cbor" as sites_covering_http : List(U8)
import "fixtures/http/create_kennel_again.cbor" as create_kennel_again_http : List(U8)
import "fixtures/queries/fastest_pulses.cbor" as fastest_pulses_ws : List(U8)
import "fixtures/queries/sites_covering.cbor" as sites_covering_ws : List(U8)
import "fixtures/http/twin_in_transaction.cbor" as twin_in_transaction_http : List(U8)
import "fixtures/queries/twin_in_transaction.cbor" as twin_in_transaction_ws : List(U8)
import "fixtures/http/stock_up.cbor" as stock_up_http : List(U8)
import "fixtures/http/insert_shifts.cbor" as insert_shifts_http : List(U8)
import "fixtures/http/twins_in_list.cbor" as twins_in_list_http : List(U8)
import "fixtures/queries/twins_in_list.cbor" as twins_in_list_ws : List(U8)
import "fixtures/http/spares_in_list.cbor" as spares_in_list_http : List(U8)
import "fixtures/http/unpin_labels.cbor" as unpin_labels_http : List(U8)
import "fixtures/http/pin_labels_again.cbor" as pin_labels_again_http : List(U8)
import "fixtures/queries/pin_labels_again.cbor" as pin_labels_again_ws : List(U8)

# Tests of a session over HTTP, without a server: the post of a message,
# the reply in a response, and the replies that SurrealDB 4.0.1 sent over
# HTTP to the requests of `client.roc -- --http` (`check.py --record
# fixtures` saves them in `fixtures/http/`), read as the type of each
# query, and through the `Inbox` in another order than they were sent, as
# `await!` reads them after two `send!`s. Nothing outside this file imports
# it.
HttpTest :: {}

# ------------------------------------------------------------- the post

url : Str
url = "http://127.0.0.1:8000"

root : HttpRpc.Auth
root = { who: Basic({ user: "root", pass: "root" }), scope: Scope({ ns: "roc", db: "roc_surreal" }) }

message : List(U8)
message = [161, 98, 105, 100, 1]

cbor_headers : List({ name : Str, value : Str })
cbor_headers = [{ name: "Content-Type", value: "application/cbor; v=2" }, { name: "Accept", value: "application/cbor; v=2" }]

expect HttpRpc.post(url, root, message).uri == "http://127.0.0.1:8000/rpc"
expect HttpRpc.post("https://db.example/", root, message).uri == "https://db.example/rpc"
expect HttpRpc.post(url, root, message).body == message
expect
	HttpRpc.post(url, root, message).headers
		== cbor_headers.concat(
			[
				{ name: "Authorization", value: "Basic cm9vdDpyb290" },
				{ name: "surreal-ns", value: "roc" },
				{ name: "surreal-db", value: "roc_surreal" },
			],
		)

# A record user: the token that `signup` or `signin` gave, as a `Bearer`.
# SurrealDB 3.3.4 runs a post with the token and no `surreal-ns` in the
# token's namespace and database (verified), so a session of a token
# alone sends none.
expect HttpRpc.post(url, { who: Bearer("eyJ.a.b"), scope: Scope({ ns: "roc", db: "roc_surreal" }) }, message).headers == cbor_headers.concat([{ name: "Authorization", value: "Bearer eyJ.a.b" }, { name: "surreal-ns", value: "roc" }, { name: "surreal-db", value: "roc_surreal" }])
expect HttpRpc.post(url, { who: Bearer("eyJ.a.b"), scope: FromToken }, message).headers == cbor_headers.append({ name: "Authorization", value: "Bearer eyJ.a.b" })

# A signup or a signin is anonymous, and so is a post after `invalidate`.
expect HttpRpc.post(url, { who: Anonymous, scope: Scope({ ns: "roc", db: "roc_surreal" }) }, message).headers == cbor_headers.concat([{ name: "surreal-ns", value: "roc" }, { name: "surreal-db", value: "roc_surreal" }])
expect HttpRpc.post(url, { who: Anonymous, scope: FromToken }, message).headers == cbor_headers

# The login of a record user holds the variables of its access method,
# each written as a parameter of a query is: one map entry for each field.
accounts : Surreal.Access({ email : Str, pass : Str }, { email : Str, pass : Str })
accounts = Surreal.access("account")

expect
	accounts.sign_in({ ns: "roc", db: "roc_surreal" }, { email: "ann@roc", pass: "secret" })
		== SignIn({ access: "account", ns: "roc", db: "roc_surreal", vars: Ok([(Text("email"), Text("ann@roc")), (Text("pass"), Text("secret"))]) })

# A `Dec` is a decimal (tag 10 and its text), and an `Id` a record id (tag
# 8), as in a query. The derived encoder of roc-cbor wrote a `Dec` as tag
# 4, which SurrealDB refuses ("unknown CBOR tag").
wallets : Surreal.Access({ email : Str, credit : Dec, site : Surreal.Id(Site) }, { email : Str })
wallets = Surreal.access("wallet")

expect
	wallets.sign_up({ ns: "roc", db: "roc_surreal" }, { email: "ann@roc", credit: 2.5, site: sites.id("oslo") })
		== SignUp({ access: "wallet", ns: "roc", db: "roc_surreal", vars: Ok([(Text("credit"), Tag(10, Text("2.5"))), (Text("email"), Text("ann@roc")), (Text("site"), Tag(8, Array([Text("site"), Text("oslo")])))]) })
# A name that SurrealDB protects is refused before the login is sent.
guarded : Surreal.Access({ auth : Str }, { auth : Str })
guarded = Surreal.access("guarded")

expect guarded.sign_in({ ns: "roc", db: "roc_surreal" }, { auth: "x" }) == SignIn({ access: "guarded", ns: "roc", db: "roc_surreal", vars: Err(Unsupported("`$auth` is a protected variable in SurrealDB; name the parameter otherwise")) })

# ------------------------------------------------------------ the response

# Status 200 holds the RPC reply, also one with an error. Any other status
# is the server refusing the post; SurrealDB 3.3.4 answers a password that
# does not verify with 401 and this text (verified).
expect HttpRpc.reply({ status: 200, body: message }) == Ok(message)
expect HttpRpc.reply({ status: 401, body: "The password did not verify".to_utf8() }) == Err(Refused({ status: 401, message: "The password did not verify" }))
expect HttpRpc.reply({ status: 503, body: [] }) == Err(Refused({ status: 503, message: "HTTP 503" }))

# ------------------------------------------------------- the replies over HTTP

Site : { id : Str, name : Str, location : Surreal.Point, area : Surreal.Polygon }

Kennel : { id : Str, label : Str, site : Surreal.Link(Site) }

Vital : { id : Surreal.TimeKey(Surreal.Id(Kennel)), pulse : I64, temp_c : Dec, fevered : Bool }

sites : Surreal.Table(Site)
sites = Surreal.table("site")

kennels : Surreal.Table(Kennel)
kennels = Surreal.table("kennel")

vitals : Surreal.Table(Vital)
vitals = Surreal.table("vital")

## A prepared statement that translates.
ready : Surreal.Prepared(out) -> Surreal.Prepared(out)
ready = |prepared| match prepared.checked() {
	Ok(p) => p
	Err(_) => crash "the query of client.roc translates"
}

fastest_pulses : Surreal.Prepared(List(I64))
fastest_pulses = ready(Surreal.from(vitals).select_value(|v| v.pulse).order_by(|n| n, Desc).limit(3).filter(|n| n < 130).prepare({}))

sites_covering : Surreal.Prepared(List(Str))
sites_covering = ready(Surreal.from(sites).filter_by(|p, s| Surreal.Geo.inside(p.here.to_geometry(), s.area.to_geometry())).select_value(|s| s.id).prepare({ here: Surreal.point(10.75, 59.91) }))

quay : Kennel
quay = { id: "q", label: "Quay", site: sites.link("oslo") }

# A reply over HTTP is the message that a WebSocket frame holds: it reads
# as the same result.
expect fastest_pulses.result(fastest_pulses_http) == Ok([125, 121])
expect fastest_pulses.result(fastest_pulses_http) == fastest_pulses.result(fastest_pulses_ws)
expect sites_covering.result(sites_covering_http) == Ok(["oslo"])
expect sites_covering.result(sites_covering_http) == sites_covering.result(sites_covering_ws)
expect ready(kennels.create(quay)).result(create_kennel_again_http) == Err(Server(Exists({ what: "Record", name: "kennel:q", message: "Database record `kennel:q` already exists" })))

Bin : { id : Str, label : Str }

bins : Surreal.Table(Bin)
bins = Surreal.table("bin")

## The transactions of `client.roc`: a create and an insert of a second
## `Top`, and a create, an insert and a read that commit.
twin_in_transaction : Surreal.Prepared((List(Bin), List(Bin)))
twin_in_transaction = {
	create = bins.create({ id: "b3", label: "Side" })
	insert = bins.insert([{ id: "b4", label: "Low" }, { id: "b2", label: "Top" }])
	ready(create.begin().then(insert).commit())
}

stock_up : Surreal.Prepared(((List(Bin), List(Bin)), List(Bin)))
stock_up = ready(atomic3(bins.create({ id: "b3", label: "Side" }), bins.insert([{ id: "b4", label: "Low" }]), Surreal.from(bins).select(|r| r).prepare({})))

atomic3 : Surreal.Prepared(a), Surreal.Prepared(b), Surreal.Prepared(c) -> Surreal.Prepared(((a, b), c))
atomic3 = |first, second, third| first.begin().then(second).then(third).commit()

# A transaction is one request on HTTP too: it fails as a whole, and it
# commits as a whole.
expect twin_in_transaction.result(twin_in_transaction_http) == twin_in_transaction.result(twin_in_transaction_ws)
expect twin_in_transaction.result(twin_in_transaction_http).map_err(
	|e| match e {
		Aborted(a) => a.at
		_ => 99
	},
) == Err(1)
expect stock_up.result(stock_up_http).map_ok(|((created, inserted), rows)| (created.len(), inserted.len(), rows.len())) == Ok((1, 1, 3))

# A list of writes (`Surreal.transaction`) and a migration are one
# request on HTTP too, with the result that a WebSocket gives.
twins_in_list : Surreal.Prepared(List(List(Bin)))
twins_in_list = {
	spare = bins.create({ id: "b5", label: "Spare" })
	twin = bins.create({ id: "b2", label: "Top" })
	ready(Surreal.transaction([spare, twin]))
}

spares_in_list : Surreal.Prepared(List(List(Bin)))
spares_in_list = {
	spare = bins.create({ id: "b5", label: "Spare" })
	rack = bins.create({ id: "b6", label: "Rack" })
	ready(Surreal.transaction([spare, rack]))
}

expect twins_in_list.result(twins_in_list_http) == twins_in_list.result(twins_in_list_ws)
expect twins_in_list.result(twins_in_list_http).map_err(
	|e| match e {
		Aborted(a) => a.at
		_ => 99
	},
) == Err(1)
expect spares_in_list.result(spares_in_list_http) == Ok([[{ id: "b5", label: "Spare" }], [{ id: "b6", label: "Rack" }]])

migrate : List(Surreal.Defined), List(Surreal.Defined) -> Surreal.Prepared({})
migrate = |old, new| match Surreal.plan(Surreal.schema(old) ?? "", new).map_ok(|p| p.prepare(DropData)) {
	Ok(Ok([one])) => one
	_ => crash "the schemas of client.roc translate, and each migration is one section"
}

expect migrate([bins.define().unique(|b| b.label).done()], [bins.define().done()]).result(unpin_labels_http) == Ok({})
expect migrate([bins.define().done()], [bins.define().unique(|b| b.label).done()]).result(pin_labels_again_http) == migrate([bins.define().done()], [bins.define().unique(|b| b.label).done()]).result(pin_labels_again_ws)
expect migrate([bins.define().done()], [bins.define().unique(|b| b.label).done()]).result(pin_labels_again_http).is_err()

Shift : { id : Str, label : Str }

shifts : Surreal.Table(Shift)
shifts = Surreal.table("shift")

# Rows whose keys the server made, over HTTP: the keys of the reply.
expect ready(shifts.insert_new([{ label: "Late" }, { label: "Night" }])).result(insert_shifts_http) == Ok([{ id: shifts.id("01M79122QHG33QKJFYM5PCVZ35"), fields: { label: "Late" } }, { id: shifts.id("01M79122QHZJY72A5QEQEXRGJ7"), fields: { label: "Night" } }])

# Two `send!`s over HTTP put both replies into the inbox, in the order of
# the posts. `await!` takes the second first, then the first.
sent : Try(Surreal.Inbox, Surreal.Error)
sent = match Surreal.Inbox.empty({}).accept(fastest_pulses_http) {
	Ok(inbox) => inbox.accept(sites_covering_http)
	Err(e) => Err(e)
}

## The reply to the request `id`, read by `prepared`, and the inbox after it.
awaited : Try(Surreal.Inbox, Surreal.Error), U64, Surreal.Prepared(out) -> Try({ result : Try(out, Surreal.Error), inbox : Surreal.Inbox }, [Waiting, Failed(Surreal.Error)])
awaited = |inbox, id, prepared| match inbox {
	Ok(i) =>
		match i.take_reply(id) {
			Taken(t) => Ok({ result: prepared.result(t.bytes), inbox: t.inbox })
			Waiting => Err(Waiting)
		}
	Err(e) => Err(Failed(e))
}

## The ids of the two replies, in the order of the posts.
ids : List(U64)
ids = sent.map_ok(|i| i.replies()).map_ok(|r| r.sort()) ?? []

expect ids.len() == 2

expect {
	(first, second) = match ids {
		[a, b] => (a, b)
		_ => (0, 0)
	}
	match awaited(sent, second, sites_covering) {
		Ok(got_second) =>
			match awaited(Ok(got_second.inbox), first, fastest_pulses) {
				Ok(got_first) => got_second.result == Ok(["oslo"]) and got_first.result == Ok([125, 121]) and got_first.inbox.replies().is_empty()
				Err(_) => Bool.False
			}
		Err(_) => Bool.False
	}
}

# A reply is taken once: the inbox holds no second copy, so a ticket that
# is awaited again finds none, which `await!` over HTTP reports.
expect {
	first = ids.first() ?? 0
	match awaited(sent, first, fastest_pulses) {
		Ok(got) => awaited(Ok(got.inbox), first, fastest_pulses).map_ok(|_| {}) == Err(Waiting)
		Err(_) => Bool.False
	}
}
