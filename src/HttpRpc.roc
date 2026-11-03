# SurrealDB's RPC over HTTP, as pure functions: one `POST /rpc` for each
# request, with the same CBOR message as a WebSocket frame holds. The
# server keeps no state between two posts (verified on SurrealDB 3.3.4:
# `use` and `signin` answer, and the next post has no namespace), so each
# post carries who it is from, and the namespace and the database, in its
# headers. The platform sends the post and gives the response.
import ws.Base64

HttpRpc :: {}.{

	## Who a post is from (`who`), and its namespace and database
	## (`scope`). `Basic` is a system user. `Bearer` is the token of a
	## record user (`signup`, `signin`) or of `authenticate`. `Anonymous`
	## is a post before a signup or a signin, and after `invalidate`. A
	## token holds its namespace and database, so a session of a token
	## alone sends none (`FromToken`): SurrealDB 3.3.4 runs a post with a
	## `Bearer` token and no `surreal-ns` in the token's (verified).
	Auth : { who : [Basic({ user : Str, pass : Str }), Bearer(Str), Anonymous], scope : [Scope({ ns : Str, db : Str }), FromToken] }

	## One post, as the platform sends it.
	Post : { uri : Str, headers : List({ name : Str, value : Str }), body : List(U8) }

	## The post of one RPC message to `url`, the base of the server, such
	## as `http://127.0.0.1:8000`: CBOR both ways, the authentication of
	## `auth`, and its namespace and database.
	post : Str, Auth, List(U8) -> Post
	post = |url, auth, message| {
		who = match auth.who {
			Basic({ user, pass }) => [{ name: "Authorization", value: "Basic ${Base64.encode("${user}:${pass}".to_utf8())}" }]
			Bearer(token) => [{ name: "Authorization", value: "Bearer ${token}" }]
			Anonymous => []
		}
		scope = match auth.scope {
			Scope({ ns, db }) => [{ name: "surreal-ns", value: ns }, { name: "surreal-db", value: db }]
			FromToken => []
		}
		{
			uri: "${url.drop_suffix("/")}/rpc",
			headers: [{ name: "Content-Type", value: "application/cbor" }, { name: "Accept", value: "application/cbor" }].concat(who).concat(scope),
			body: message,
		}
	}

	## The RPC reply in a response. SurrealDB answers a request with status
	## 200, also a request whose method or statement fails: the message
	## holds that error. Any other status is the server refusing the post,
	## such as 401 for a password that does not verify, with a text body:
	## the status, and the text, or `HTTP <status>` when there is none.
	reply : { status : U16, body : List(U8) } -> Try(List(U8), [Refused({ status : U16, message : Str })])
	reply = |response|
		if response.status == 200 {
			Ok(response.body)
		} else {
			text = Str.from_utf8(response.body) ?? ""
			Err(Refused({ status: response.status, message: if (text.is_empty()) "HTTP ${response.status.to_str()}" else text }))
		}
}
