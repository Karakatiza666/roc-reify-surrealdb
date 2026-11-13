# Functions in clauses

This page tells you which functions you can call inside a clause, and what each one becomes in SurrealQL. It also shows how to define a function that the database holds. The terms "clause", "intrinsic" and "mirror function" are in the [glossary](getting-started.md#words-used-in-these-pages).

## What you can call in a clause

The translator writes SurrealQL for the calls that it knows. It refuses all other calls. Apply the rule below to each call in the clause.

```
a call in a clause
  |-- your own function, not recursive ----> read its body: apply this rule to each call in it
  |-- a Roc builtin in the tables below ----> allowed
  |-- Surreal.<Namespace>.<function> -------> allowed (see Package functions)
  |-- a method with a form of its own ------> allowed (see the last table of this section)
  `-- anything else ------------------------> Err(Unsupported(..)) when you build the statement
```

| Group | Examples | Where it is described |
| --- | --- | --- |
| Roc builtins | `starts_with`, `mod_by`, `any`, `??` | [Roc builtins](#roc-builtins), [Refused builtins](#refused-builtins) |
| Package functions | `Surreal.Text.is_email`, `Surreal.Time.floor` | [Package functions](#package-functions) |
| Your own functions | `referred`, `Clinic.bill` | The translator expands the body at the call. A function that calls itself is refused |
| Database functions | `fever_fn.call2(..)` | [Database functions](#database-functions) |

A refusal is a value. `prepare` and `to_surql` give `Err(Unsupported(why))` and the text names the clause, as `in `filter`: ..`. The program still compiles. See [Build-time errors](errors.md#build-time-errors).

Some methods have a form that this page does not list. Other pages describe them:

| Call | SurrealQL | Page |
| --- | --- | --- |
| `link.get()`, `link.id`, `id.key()` | A traversal, the record id, `record::id(id)` | [Ids, links and graph edges](links-and-graphs.md#links) |
| `table.id(key)`, `table.rows()` | A record id, the rows of a table | [Ids, links and graph edges](links-and-graphs.md#read-other-tables-in-a-clause) |
| `t.edges_from(row)`, `t.edges_to(row)` | `->t`, `<-t`: a graph path | [Graph paths](links-and-graphs.md#graph-paths) |
| `v.id.series()`, `v.id.time()` | `record::id(id)[0]`, `record::id(id)[1]` | [Row types and data types](data-types.md#time-series-keys) |
| `Surreal.point(lon, lat)`, `p.lat()`, `to_geometry()` | `<point> [lon, lat]`, `field.coordinates[1]`, the value itself | [Row types and data types](data-types.md#geometry) |
| `hit.score()`, `hit.highlight(a, b)`, `near.distance()` | `search::score(1)`, `search::highlight(a, b, 1)`, `vector::distance::knn()` | [Full-text and vector search](search.md) |

To add a form for a function of your own, see [Extend the translator](advanced.md#extend-the-translator).

### A function as a value

A call is allowed. A builtin, a mirror function or an intrinsic passed as a value is a compile error. Wrap it in a lambda.

| You write | Result |
| --- | --- |
| `o.tags.map(Str.trim)` | Compile error `cannot reify this expression`: "a builtin or a function in the translator's cut used as a value" |
| `o.tags.any(Surreal.Text.is_email)` | Compile error: "an intrinsic, a function with no Roc body, used as a value" |
| `o.tags.any(\|t\| Surreal.Text.is_email(t))` | `tags.any(\|$v1\| string::is_email($v1))` |
| `Surreal.from(owners).filter(is_vip)` with your own `is_vip` | Allowed. Your own function can be a value |

## Mirror functions and intrinsics

A package function is one of two kinds.

| Kind | Body | In a clause | In plain Roc code |
| --- | --- | --- | --- |
| Mirror function | A Roc body that gives the SurrealDB result | SurrealQL | Runs the Roc body |
| Intrinsic | None: a type only, as `is_email : Str -> Bool` | SurrealQL | Compile error `exists only in reified code` |

A mirror function works in a test and in seed data. This function runs in Roc and gives `array::distinct(tags)` in a clause:

```roc
# Fragment: uses `owners` from a script app. Owner has `tags : List(Str)`.
unique_tags : Owner -> List(Str)
unique_tags = |o| Surreal.Array.distinct(o.tags)

expect unique_tags({ id: "a", tags: ["x", "y", "x"] }) == ["x", "y"]
```

```surql
SELECT VALUE array::distinct(tags) FROM owner
```

Both the `expect` and `Surreal.from(owners).select_value(unique_tags).to_surql()` come from a real run.

SurrealDB computes an intrinsic. Roc has no value for it. A call in code that runs is a compile error, also through your own helper:

```
exists only in reified code

valid_mail calls Surreal.Text.is_email at t3.roc:6:18
Surreal.Text.is_email is an intrinsic at .../src/Surreal.roc:526:3
```

Call an intrinsic only in a function that you pass where a `Code` is expected. A helper such as `valid_mail` is fine when only clauses call it.

To list the intrinsics, run the checker with a flag:

```sh
roc check --intrinsics src/main.roc
```

```
src/Surreal.roc:526:3 Surreal.Text.is_email : Str -> Bool
src/Surreal.roc:643:3 Surreal.Auth.access : () -> Str
src/Surreal.roc:837:3 Surreal.Rand.uuid : () -> Str
```

The check lists 66 intrinsics (64 for release 0.0.1). The tables of this page mark each function as `mirror` or `intrinsic`. The list also has `Hit`, `Near`, `Table.rows`, `Table.edges_from`, `Table.edges_to` and `Table.auth`.

## Roc builtins

The builtins below have a SurrealQL form. `s` is a `Str`, `n` and `m` are integers, `d` is a `Dec`, `list` is a list. A builtin maps only when SurrealDB 4.0.1 gives the same result as Roc. Where the two differ, the translator writes a longer expression, or it refuses the call.

| Family | Roc | SurrealQL | Note |
| --- | --- | --- | --- |
| Operators | `+ - *`, `/`, `== != < <= > >=`, `and`, `or`, `!`, `if` | The same operators. `==` is `=` | `//` and `%` only on integers. `if` and `match` become `IF .. THEN .. END` |
| Str test | `s.is_empty()`, `starts_with`, `ends_with`, `contains` | `s = ''`, `string::starts_with(s, x)` and the same for the others | |
| Str join | `"${a}${b}"`, `with_prefix`, `Str.join_with(list, x)`, `repeat(n)` | `a + b`, `p + s`, `array::join(list, x)`, `string::repeat(s, n)` | |
| Str change | `with_ascii_uppercased`, `with_ascii_lowercased`, `caseless_ascii_equals` | A per-character `IF` over `a` to `z` | `string::uppercase` also changes `ß` and `é`, and Roc does not |
| Str trim | `trim`, `trim_start`, `trim_end` | `string::replace(s, /^[\s\u{200E}\u{200F}]+\|..$/, '')` | `string::trim` keeps U+200E and U+200F, and Roc removes them |
| Str cut | `drop_prefix`, `drop_suffix`, `split_on(x)`, `replace_each(a, b)` | `IF string::starts_with(..) THEN string::slice(..) ELSE s END`, `string::split`, `string::replace` | An empty `x` or `a` keeps the text, as Roc does. A literal `""` is read at translation. Another value gets an `IF x = ''` guard |
| Str size | `count_utf8_bytes()` | `bytes::len(<bytes>s)` | `string::len` counts characters |
| Number | `n.max(m)`, `min`, `pow`, `abs`, `negate` | `math::max([n, m])`, `math::min([n, m])`, `math::pow(n, m)`, `math::abs(n)`, `-n` | `max` and `min` on integers and `Dec`. `pow` on integers only |
| Integer test | `mod_by`, `is_multiple_of`, `is_even`, `is_odd` | `(((n % m) + m) % m)`, `n % m = 0`, `n % 2 = 0`, `n % 2 != 0` | `mod_by` is the floored modulus, as in Roc. A divisor that is not a non-zero literal gets an `IF m = 0` guard |
| Sign test | `is_zero`, `is_negative`, `is_positive` | `n = 0`, `n < 0`, `n > 0` | Integers and `Dec` |
| Dec round | `round`, `floor`, `ceiling`, `trunc` | `IF d >= 0 THEN math::floor(d + 0.5dec) ELSE math::ceil(d - 0.5dec) END`, `math::floor(d)`, `math::ceil(d)`, an `IF` over both | `math::round` rounds a tie to even, and Roc rounds it away from zero. SurrealDB has no `math::trunc` |
| Conversion | `to_dec`, `to_f64`, `to_f32`, `to_str` on integers | `<decimal>n`, `<float>n`, `<string>n` | |
| Widening | `to_i64`, `to_i128`, `to_u32` and other conversions with no check | `n` | An integer is an `int` already |
| Checked conversion | `to_u8_try` and the other `to_<int>_try`, `d.to_i64_try()` | `IF n >= 0 AND n <= 255 THEN n ELSE NONE END` | The result is an optional value. `to_i64_try` on `Dec` cuts the fraction, then tests the range |
| List test | `list.len()`, `is_empty()`, `contains(x)` | `list.len()`, `list.len() = 0`, `list CONTAINS x` | A captured list is `x IN $_1` |
| List walk | `any`, `all`, `map`, `join_map`, `keep_if`, `drop_if`, `count_if`, `find_first` | `list.any(\|$v1\| ..)`, `.all`, `.map`, `array::flatten(list.map(..))`, `.filter`, `.find` | `drop_if` is `.filter(\|$v1\| !(..))`. `count_if` is `.filter(..).len()`. `xs.any(\|x\| x.f == v)` over a list of records, where `v` does not read `x`, is `v IN xs[*].f`. Over the edges of a graph path, `keep_if`, `map` and `join_map` extend the path (see [Graph paths](links-and-graphs.md#graph-paths)) |
| List sum | `list.map(f).sum()` | `math::sum(list.map(\|$v1\| ..))` | Over the rows of a group it is an aggregate (see [Group rows](queries.md#group-rows)) |
| List pick | `first`, `last`, `get(i)`, `min`, `max` | `array::first(list)`, `array::last`, `array::at(list, i)`, `array::min`, `array::max` | The result is an optional value: `NONE` stands for `Err` |
| List shape | `take_first(n)`, `drop_first(n)`, `rev()`, `join()`, `concat`, `append`, `prepend`, `==` | `array::slice(list, 0, n)`, `array::slice(list, n)`, `array::reverse`, `array::flatten`, `array::concat`, `array::append`, `array::prepend`, `=` | |
| List order | `sort()`, `sort_reversed()` | `array::sort::asc(list)`, `array::sort::desc(list)` | Only for whole numbers and `Dec`. A list of `Str` does not compile: `Str` has no order |
| Optional | `t.is_ok()`, `is_err()`, `ok_or(x)`, `t ?? x`, `map_ok(f)` | `t IS NOT NONE`, `t IS NONE`, `t ?? x`, `IF t IS NONE THEN NONE ELSE f(t) END` | `t` is an optional field or a `Try` that the clause builds. `f` may not return a `Try`. `t.map_ok(\|c\| c.code) ?? d` is `t.code ?? d` when `f` reads only fields of the record in `t`. A read through a link keeps the `IF`, because the linked row can be gone |
| Datetime | `a < b`, `a == b`, `a != b` on `Surreal.Datetime` | `a < b`, `a = b`, `a != b` | Compared as datetimes, never as text. See [Datetimes and durations](data-types.md#datetimes-and-durations) |

A `Try` builtin maps only when the error has one tag. SurrealQL then gives `NONE` for it.

From a real run, with an `Owner` row that has `name`, `email`, `phone ?: Str`, `tags`, `visits : I64` and `balance : Dec`:

| Roc clause | SurrealQL |
| --- | --- |
| `.filter(\|o\| o.name.starts_with("A"))` | `WHERE string::starts_with(name, 'A')` |
| `.select_value(\|o\| "${o.name} <${o.email}>")` | `SELECT VALUE name + ' <' + email + '>' FROM owner` |
| `.filter(\|o\| o.visits.mod_by(2) == 0)` | `WHERE (((visits % 2) + 2) % 2) = 0` |
| `.select_value(\|o\| o.tags.take_first(2))` | `SELECT VALUE array::slice(tags, 0, 2) FROM owner` |
| `.filter(\|o\| o.tags.any(\|t\| t.starts_with("v")))` | `WHERE tags.any(\|$v1\| string::starts_with($v1, 'v'))` |
| `.select_value(\|o\| o.?phone ?? "none")` | `SELECT VALUE phone ?? 'none' FROM owner` |
| `.select_value(\|o\| o.balance.to_i64_try())` | `SELECT VALUE (IF balance > -9223372036854775809dec AND balance < 9223372036854775808dec THEN <int>(IF balance >= 0 THEN math::floor(balance) ELSE math::ceil(balance) END) ELSE NONE END) FROM owner` |

## Refused builtins

A refused builtin gives `Err(Unsupported(why))`. It never gives a wrong query. The reason is that Roc and SurrealDB give different results, or that SurrealDB has no function with the same meaning.

| Roc builtin | Reason | Use instead |
| --- | --- | --- |
| `from_str` on `I64`, `Dec`, `F64` | Roc accepts `1_0`, `0x1f` and `1e3`, and `<int>` raises an error | Parse in Roc and store a number |
| `to_i64`, `to_i64_wrap` on `Dec` or `F64` | Roc cuts the fraction, and `<int>` raises an error | `to_i64_try` |
| `to_str` on `Dec`, `F32`, `F64` | Roc prints `3.0`, SurrealDB prints `3` or `3f` | Compare the number |
| `pow` on `Dec`; `max`, `min`, `pow`, `to_str` and sign tests on `F32` and `F64` | Digits, `NaN` and `-0.0` differ | `Dec` or an integer |
| `//` on `Dec`, `%` on `Dec` or a float | `//` cuts the fraction and SurrealDB's `/` does not. `%` is for integers | `/` on `Dec` |
| `Str.len` | See below | `count_utf8_bytes()` or `is_empty()` |
| `replace_first`, `replace_last` | `string::replace` replaces every match | `replace_each` |
| `split_first`, `split_last`, `to_utf8`, `from_utf8`, `drop_first_bytes` | The result is a record in a `Try`, or a byte list | |
| `div_floor_by`, `div_ceil_by`, `abs_diff`, shifts, `bitwise_*`, `to_<int>_wrap` and `*_saturated` conversions (`to_i64_wrap` of an integer is allowed: it is the identity) | No SurrealQL function has the same meaning | |
| `div_try` | It has two error tags, and an optional value cannot tell them apart | |
| `sort_by`, `sort_with`, `fold`, `map_try`, `chunks_of` | No SurrealQL form | Fold in Roc after the read |

A builtin that is not in the tables above gives "`Owner.method` has no SurrealQL form". An example from a real run:

```
Unsupported("in `select_value`: `Num.I64.abs_diff` has no SurrealQL form")
```

### Why `Str.len` is refused

`Str.len` is not a length in Roc. Its type is `Str -> [LearnAboutStringsInRoc(Str)]`. It gives a text of advice and no number, because a length depends on what you count: bytes, code points or grapheme clusters. SurrealDB has no function that counts the same thing. `string::len` counts characters, and `Str.count_utf8_bytes` counts bytes.

| You write | Result |
| --- | --- |
| `.filter(\|o\| o.name.len() > 3)` | A Roc type error: the tag is not a number |
| `.select_value(\|o\| o.name.len())` | `Unsupported("in `select_value`: `Str.len` has no SurrealQL form")`, because the tag is not a number the translator can map |
| `.select_value(\|o\| o.name.count_utf8_bytes())` | `SELECT VALUE bytes::len(<bytes>name) FROM owner` |

## Package functions

SurrealDB has functions that Roc has no builtin for. The package gives them as functions of nine namespaces inside `Surreal`: `Text`, `Hash`, `Auth`, `Array`, `Time`, `Math`, `Rand`, `Vector` and `Geo`. `Id.table` is one more function, on the type `Id`. You write `Surreal.Text.is_email(s)`. The name is `Text` and not `Str`, because a nominal named `Str` shadows the builtin in the whole module.

Each table has the Roc name, the type, the SurrealQL and the kind (see [Mirror functions and intrinsics](#mirror-functions-and-intrinsics)). In the types, `Datetime` is `Surreal.Datetime`. The kinds come from `roc check --intrinsics src/main.roc` and from the bodies in `src/Surreal.roc`.

### Text

`is_alpha`, `is_alphanum` and `is_numeric` read Unicode: `abé` is alphabetic, and Arabic digits are numeric. `matches` takes Rust regex syntax, and a pattern that is not anchored finds a part of the text. The distances count characters, not bytes. `distance_normalized_levenshtein` is a similarity: 1 for equal texts.

| Roc | Type | SurrealQL | Kind |
| --- | --- | --- | --- |
| `is_email`, `is_url`, `is_domain`, `is_ip`, `is_ipv4`, `is_ipv6`, `is_uuid`, `is_ulid`, `is_semver`, `is_alpha`, `is_alphanum`, `is_numeric`, `is_latitude`, `is_longitude` | `Str -> Bool` | `string::<name>(a)`, as `string::is_email(a)` | intrinsic |
| `is_ascii`, `is_hexadecimal` | `Str -> Bool` | `string::is_ascii(a)`, `string::is_hexadecimal(a)` | mirror |
| `is_datetime`, `matches` | `Str, Str -> Bool` | `string::is_datetime(a, b)`, `string::matches(a, b)` | intrinsic |
| `similarity_jaro`, `similarity_jaro_winkler` | `Str, Str -> F64` | `string::similarity::jaro(a, b)`, `string::similarity::jaro_winkler(a, b)` | intrinsic |
| `distance_levenshtein`, `distance_damerau_levenshtein` | `Str, Str -> I64` | `string::distance::levenshtein(a, b)`, `string::distance::damerau_levenshtein(a, b)` | intrinsic |
| `distance_normalized_levenshtein` | `Str, Str -> F64` | `string::distance::normalized_levenshtein(a, b)` | intrinsic |

A real run gives `WHERE string::is_email(email)` for `.filter(|o| Surreal.Text.is_email(o.email))` and `WHERE string::matches(name, '^[A-Z]')` for `Surreal.Text.matches(o.name, "^[A-Z]")`. A constraint can use the same call, as `examples/main.roc` does in `.assert(|v| v.contact.email, |e| Surreal.Text.is_email(e))`.

### Hash

A hash is lower-case hex text.

| Roc | Type | SurrealQL | Kind |
| --- | --- | --- | --- |
| `sha256`, `blake3` | `Str -> Str` | `crypto::sha256(a)`, `crypto::blake3(a)` | mirror |
| `md5`, `sha1`, `sha512` | `Str -> Str` | `crypto::md5(a)`, `crypto::sha1(a)`, `crypto::sha512(a)` | intrinsic |
| `argon2` | `Str -> Str` | `crypto::argon2::generate(a)` | intrinsic, a new value on every call |
| `argon2_matches` | `Str, Str -> Bool` | `crypto::argon2::compare(hash, password)` | intrinsic |

`argon2` makes a new salt on each call, so it follows the rule of [Rand](#rand-and-where-it-is-allowed). Use it in a signup, a default, a computed field or an update. `argon2_matches` has no salt. A signin and a filter can call it. [Define an access method](access.md#define-an-access-method) shows both. The hashes `bcrypt`, `scrypt` and `pbkdf2` are not available (see [Functions that are not available](#functions-that-are-not-available)).

A real run gives `SELECT VALUE crypto::sha256(email) FROM owner` for `Surreal.Hash.sha256(o.email)`. In Roc, `Surreal.Hash.sha256("abc")` runs the Roc body and gives `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`.

### Array

The functions take lists of values that have `is_eq`. They keep the first place of a value, as SurrealDB does: `distinct([3, 1, 3, 2, 1])` is `[3, 1, 2]`. `complement(a, b)` gives the values of `a` that `b` has not. It is not `array::difference`, which is a symmetric difference.

| Roc | Type | SurrealQL | Kind |
| --- | --- | --- | --- |
| `distinct` | `List(a) -> List(a)` | `array::distinct(a)` | mirror |
| `union`, `intersect`, `complement` | `List(a), List(a) -> List(a)` | `array::union(a, b)`, `array::intersect(a, b)`, `array::complement(a, b)` | mirror |

A real run gives `array::union(tags, ['vip'])` for `Surreal.Array.union(o.tags, ["vip"])`.

### Time

Every part of a time is read in UTC. A `Duration` is a number of nanoseconds. It is not a column type (see [Datetimes and durations](data-types.md#datetimes-and-durations)).

| Roc | Type | SurrealQL | Kind |
| --- | --- | --- | --- |
| `nanos`, `micros`, `millis`, `secs`, `mins`, `hours`, `days`, `weeks` | `U64 -> Duration` | A literal such as `1d`, else `duration::from_nanos(N)` | Roc body, inlined |
| `now` | `() -> Datetime` | `time::now()` | intrinsic |
| `floor`, `ceil`, `round` | `Datetime, Duration -> Datetime` | `time::floor(a, b)`, `time::ceil(a, b)`, `time::round(a, b)` | mirror |
| `group` | `Datetime, [Year, Month, Day, Hour, Minute, Second] -> Datetime` | `time::group(t, 'month')` | intrinsic |
| `plus`, `minus` | `Datetime, Duration -> Datetime` | `t + d`, `t - d` | intrinsic |
| `year`, `month`, `day`, `hour`, `minute`, `second` | `Datetime -> I64` | `time::year(a)` and the same for the others | mirror |
| `wday`, `yday`, `week` | `Datetime -> I64` | `time::wday(a)`, `time::yday(a)`, `time::week(a)` | intrinsic |
| `unix`, `unix_millis`, `unix_micros`, `nano` | `Datetime -> I64` | `time::unix(a)`, `time::millis(a)`, `time::micros(a)`, `time::nano(a)` | intrinsic |
| `format` | `Datetime, Str -> Str` | `time::format(a, b)` | intrinsic |
| `from_unix` | `I64 -> Datetime` | `time::from_unix(a)` | intrinsic |

Notes:

| Topic | Rule |
| --- | --- |
| Names | `unix_millis` and `unix_micros` are not `millis` and `micros`, because those two make a `Duration` |
| Calendar | `wday` is Monday 1 to Sunday 7. `week` is the ISO week. `yday` counts from 1 |
| Spans | `floor`, `ceil` and `round` count spans from 1970-01-01T00:00:00Z, so a week starts on a Thursday. A span of zero keeps the time. A half goes up in `round`, also before 1970 |
| Unit of `group` | Write the tag in the clause, as `Month`. A tag in a variable gives `Unsupported` |
| `now` | It differs on each call. Do not compare it to itself |

A real run gives these texts. A duration with a known count is a literal in the largest units that fit (`1w`, `1d`, `1h30m`, `0ns`):

| Roc clause | SurrealQL |
| --- | --- |
| `Surreal.Time.floor(o.joined, Surreal.Time.days(1))` | `time::floor(joined, 1d)` |
| `Surreal.Time.plus(o.joined, Surreal.Time.weeks(2))` | `joined + 2w` |
| `Surreal.Time.group(o.joined, Month)` | `time::group(joined, 'month')` |
| `.filter(\|o\| o.joined < Surreal.Time.now())` | `WHERE joined < time::now()` |

### Math

The statistics take `List(F64)` and give `F64`. The result type in SurrealDB depends on the element type, and a Roc signature cannot say that. Convert an `I64` field with `to_f64()`. The translator writes `<float>`. For a `Dec`, `mean_dec` takes `List(Dec)` and gives an `F64`: the mean of `v.to_f64()` of each value. SurrealDB gives a decimal mean of decimals with 28 digits, which a `Dec` of 18 digits cannot hold, so the values go to floats first. Over the rows of a group the same call is an aggregate. The mean of a list with no value is not a number. `stddev` and `variance` are the sample values.

| Roc | Type | SurrealQL | Kind |
| --- | --- | --- | --- |
| `mean` | `List(F64) -> F64` | `math::mean(list)` | mirror |
| `mean_dec` | `List(Dec) -> F64` | `math::mean(list.map(\|$c\| <float>$c))`. Over a group's rows, `math::mean(<float>col)` | mirror |
| `median`, `stddev`, `variance` | `List(F64) -> F64` | `math::median(list)`, `math::stddev(list)`, `math::variance(list)` | intrinsic |
| `percentile` | `List(F64), F64 -> F64` | `math::percentile(list, p)` | intrinsic |

```roc
# Fragment: uses `owners` and `Owner` from a script app.
Surreal.from(owners).group_by(|o| { city: o.address.city })
	.aggregate(|k, rows| { city: k.city, mean: Surreal.Math.mean_dec(rows.map(|o| o.balance)) })
```

```surql
SELECT address.city AS city, math::mean(<float>balance) AS mean FROM owner GROUP BY city
```

`percentile` is not an aggregate in SurrealDB. Over a group it gives `Unsupported("in `aggregate`: `math::percentile` is not an aggregate in SurrealDB; use it on a list")`. Per-row use works: `Surreal.Math.percentile(s.readings, 90.0)` is `math::percentile(readings, 90f)`. A view refuses `median` over a group. [Totals of all rows](queries.md#totals-of-all-rows) says the same for `totals`.

### Rand and where it is allowed

A function that gives a new value on each call needs a rule. A query that calls `rand::int` would give other rows each time. A `check` that calls it would pass or fail by chance. A default, a computed field and an `UPDATE .. SET` want a new value.

| Roc | Type | SurrealQL | Kind |
| --- | --- | --- | --- |
| `Rand.uuid` | `() -> Str` | `<string>rand::uuid()` | intrinsic, new on each call |
| `Rand.ulid` | `() -> Str` | `rand::ulid()` | intrinsic, new on each call |
| `Rand.int` | `I64, I64 -> I64` | `rand::int(a, b)`, both ends included | intrinsic, new on each call |
| `Hash.argon2` | `Str -> Str` | `crypto::argon2::generate(a)` | intrinsic, new on each call |
| `Time.now` | `() -> Datetime` | `time::now()` | intrinsic, a clock |

A `uuid` is its own type in SurrealDB, and a `string` column refuses it, so the translator writes the cast `<string>rand::uuid()`.

| Where | `Rand.*` and `Hash.argon2` | `Time.now` |
| --- | --- | --- |
| Query clause: filter, projection, order, group key | Refused | Allowed |
| `check`, `assert` | Refused | Allowed |
| `default_by`, `computed` | Allowed | Allowed |
| `update`, `set`: the new value of a field | Allowed | Allowed |
| Signup of an access method | Allowed | Allowed |
| Signin of an access method | Refused | Allowed |

Real runs:

| Roc clause | Result |
| --- | --- |
| `.default_by(\|n\| n.id, \|_\| Surreal.Rand.ulid())` | `DEFINE FIELD OVERWRITE id ON note TYPE string DEFAULT rand::ulid();` |
| `.default_by(\|n\| n.roll, \|_\| Surreal.Rand.int(1, 6))` | `DEFINE FIELD OVERWRITE roll ON note TYPE int DEFAULT rand::int(1, 6);` |
| `.computed(\|n\| n.tag, \|_\| Surreal.Rand.uuid())` | `DEFINE FIELD OVERWRITE tag ON note TYPE string VALUE <string>rand::uuid();` |
| `notes.update(\|n\| n.roll == 0, \|n\| { ..n, roll: Surreal.Rand.int(1, 6) })` | `UPDATE note SET roll = rand::int(1, 6) WHERE roll = 0` |
| `.filter(\|o\| o.visits == Surreal.Rand.int(1, 6))` | ``Unsupported("in `filter`: `Surreal.Rand.int` gives a new value on every call: use it in a default, a computed field or an update")`` |
| `.assert(\|n\| n.roll, \|r\| r < Surreal.Rand.int(1, 6))` | The same text, with no `in `filter`:` prefix |
| `.check("fresh", \|n\| n.stamp < Surreal.Time.now())` | `DEFINE FIELD OVERWRITE stamp ON note TYPE datetime ASSERT $value < time::now();` |

[Writing rows](writes.md#random-values-in-writes) uses these calls to make keys.

### Vector

The six functions take two vectors of the same dimension. Two dimensions are an error in SurrealDB, and the Roc body stops the program. Each sum runs from the first element to the last, as the server does, so the Roc result equals the server result to the last bit. The dot product of two empty vectors is the integer `0` in SurrealDB. [Full-text and vector search](search.md) uses them with an index.

| Roc | Type | SurrealQL | Kind |
| --- | --- | --- | --- |
| `similarity_cosine` | `List(F64), List(F64) -> F64` | `vector::similarity::cosine(a, b)` | mirror. A zero vector gives `NaN` |
| `distance_euclidean`, `distance_manhattan`, `distance_chebyshev` | `List(F64), List(F64) -> F64` | `vector::distance::euclidean(a, b)` and the same for the others | mirror |
| `dot` | `List(F64), List(F64) -> F64` | `vector::dot(a, b)` | mirror |
| `magnitude` | `List(F64) -> F64` | `vector::magnitude(a)` | mirror |

A real run gives `SELECT VALUE vector::similarity::cosine(embedding, [1f, 0f]) FROM owner` for `Surreal.Vector.similarity_cosine(o.embedding, [1.0, 0.0])`. `examples/search.roc` has all six.

### Geo

`Geometry` is the union of the geometry types. Call `to_geometry()` on a `Point`, a `Polygon` and the others when a function takes a `Geometry`. See [Geometry](data-types.md#geometry).

| Roc | Type | SurrealQL | Kind |
| --- | --- | --- | --- |
| `area` | `Geometry -> F64` | `geo::area(a)` | intrinsic. Square metres |
| `bearing` | `Point, Point -> F64` | `geo::bearing(a, b)` | intrinsic. Degrees |
| `centroid` | `Geometry -> Point` | `geo::centroid(a)` | intrinsic |
| `distance` | `Point, Point -> F64` | `geo::distance(a, b)` | intrinsic. Metres |
| `hash_encode` | `Point, U8 -> Str` | `geo::hash::encode(a, n)` | intrinsic. The server refuses `n` outside 1 to 12 |
| `hash_decode` | `Str -> Point` | `geo::hash::decode(a)` | intrinsic |
| `is_valid` | `Geometry -> Bool` | `geo::is_valid(a)` | mirror. Longitude from -180 to 180, latitude from -90 to 90 |
| `contains` | `Geometry, Geometry -> Bool` | `a CONTAINS b` | intrinsic |
| `inside` | `Geometry, Geometry -> Bool` | `a INSIDE b` | intrinsic |
| `outside` | `Geometry, Geometry -> Bool` | `a OUTSIDE b` | intrinsic. No point in common |
| `intersects` | `Geometry, Geometry -> Bool` | `a INTERSECTS b` | intrinsic |

A point in a clause is `<point> [lon, lat]`. Any other geometry must be a parameter. From a real run of `examples/monitoring.roc`, `sites_covering`:

```roc
# Fragment: uses `sites` and `Site` from examples/monitoring.roc.
Surreal.from(sites).filter_by(|p, s| Surreal.Geo.inside(p.here.to_geometry(), s.area.to_geometry()))
	.select_value(|s| s.id).prepare({ here: here })
```

```surql
LET $here = { type: 'Point', coordinates: [10.75f, 59.91f] };
SELECT VALUE record::id(id) FROM site WHERE $here INSIDE area;
```

`Surreal.Geo.distance(s.location, Surreal.point(10.0, 60.0))` gives `geo::distance(location, <point> [10f, 60f])`.

### Auth

The three calls read the session on the server. They are intrinsics and exist only in a clause. [The record user in a clause](access.md#the-record-user-in-a-clause) explains them.

| Roc | Type | SurrealQL | Kind |
| --- | --- | --- | --- |
| `Surreal.Auth.access()` | `() -> Str` | `$access` | intrinsic. The access method name |
| `Surreal.Auth.expires()` | `() -> I64` | `$token.exp` | intrinsic. Seconds since 1970 |
| `table.auth()` | `Table(row) -> Id(row)` | `$auth.id` | intrinsic. The signed in record |

A real run gives `WHERE type::record('owner', record::id(id)) = $auth.id` for `.filter(|o| owners.id(o.id) == owners.auth())`.

### Id.table

| Roc | Type | SurrealQL | Kind |
| --- | --- | --- | --- |
| `id.table()` | `Id(row) -> Str` | `record::tb(id)` | mirror |

It reads the table of an id. A link that can point at several tables needs it. A real run gives `SELECT VALUE record::tb(patient) FROM visit` for `.select_value(|v| v.patient.id().table())`.

## Database functions

A database function is a Roc function that the database also holds, as `fn::name`. Make it a top-level constant with `Surreal.db_fn(name, f)`. Give it to the schema with `Surreal.function`. Call it with `call1`, `call2` or `call3`.

```roc
# Fragment: uses `vitals` from examples/monitoring.roc. Vital here has id : Str.
fever : Dec, I64 -> Bool
fever = |temp_c, pulse| temp_c > 39.0 or pulse > 120

fever_fn : Surreal.DbFn((Dec, I64 -> Bool))
fever_fn = Surreal.db_fn("fever", fever)

Surreal.schema([Surreal.function(|_| fever_fn), vital_def])
Surreal.from(vitals).filter(|v| fever_fn.call2(v.temp_c, v.pulse))
```

From `examples/monitoring.roc`, `fever_fn`. The statements from a real run:

```surql
DEFINE FUNCTION OVERWRITE fn::fever($a1: decimal, $a2: int) -> bool { RETURN ($a1 > 39.0dec) OR ($a2 > 120) };
SELECT VALUE record::id(id) FROM vital WHERE fn::fever(temp_c, pulse)
```

The call also runs in Roc: `fever_fn.call2(39.5, 80)` runs the Roc body. A constraint can call it too: `.check("calm", |v| !fever_fn.call2(v.temp_c, v.pulse))` is an event that calls `fn::fever($after.temp_c, $after.pulse)`.

| Call | Type | SurrealQL |
| --- | --- | --- |
| `Surreal.db_fn(name, f)` | `Str, f -> DbFn(f)` | A constant. Not a clause by itself |
| `Surreal.function(\|_\| fn_value)` | `Code(({} -> DbFn(f))) -> Defined` | `DEFINE FUNCTION OVERWRITE fn::name($a1: T1, ..) -> R { RETURN body };` |
| `call1`, `call2`, `call3` | `DbFn((a -> r)), a -> r`, and the same with 2 and 3 arguments | `fn::name(a, ..)` |

| Rule | Detail |
| --- | --- |
| Name | `[a-z_][a-z0-9_]*`. Else `Unsupported`, at the definition and at the call: "`Doubled` is not a database function name; use `[a-z_][a-z0-9_]*`" |
| Parameter names | `$a1`, `$a2` and so on, in order |
| Types | Each parameter and the result have the SurrealDB type of a field of the same Roc type. A link or id parameter needs the table of its row type in the schema list |
| Order | Every `DEFINE FUNCTION` comes first in the schema script, so a field or an event can call it |
| Called functions | `Surreal.function` also defines each database function that the body calls. A function that two entries reach is written once. Two different bodies with one name are a `BadSchema` |
| Captures | A function that captures a value gives `Unsupported`: "the database function `fn::capped` captures values; a database function is a top-level function". A top-level constant is not a capture. It is written into the text |
| Recursion | A call of the function in its own body is `fn::name(..)`. A recursive helper inside the body is refused, as in a clause |
| Intrinsics | The body may not call an intrinsic, also not `Rand`. The constant then does not compile (see Limits) |
| The schema | Queries and constraints that call `fn::name` need the function in the database. Load the schema script first |

A recursive function from a real run:

```surql
DEFINE FUNCTION OVERWRITE fn::sum_to($a1: int) -> int { RETURN (IF $a1 > 0 THEN $a1 + fn::sum_to($a1 - 1) ELSE 0 END) };
```

The Roc body of `sum_to` is `|n| if (n <= 0) 0 else n + sum_to(n - 1)`.

## Functions that are not available

The package leaves out these functions on purpose.

| Function | Decision |
| --- | --- |
| `array::sort`, `array::sort::asc`, `array::sort::desc` | Use `List.sort` and `List.sort_reversed` for whole numbers and `Dec`. There is no `Array.sort` |
| `array::difference` | Use `Array.complement`. `array::difference` is a symmetric difference |
| `time::millis`, `time::micros` | Called `Time.unix_millis` and `Time.unix_micros` |
| `string::similarity::fuzzy`, `smithwaterman` | Left out. Both give 0 for `('martha', 'marhta')` on SurrealDB 4.0.1 |
| `string::distance::hamming`, `osa_distance` | Left out. `hamming` is an error for texts of different length. `osa_distance` is a parse error in 4.0.1: "Invalid function/constant path" |
| `crypto::bcrypt`, `scrypt`, `pbkdf2` | Left out. A random salt makes each call differ. `argon2` is the hash that signup and signin need |
| `Datetime - Datetime` | Left out. It is an error in SurrealDB when the result is negative. Use `Time.unix(a) - Time.unix(b)` |
| `time::timezone`, `is_leap_year`, `max`, `min` | Left out |
| `vector::add`, `subtract`, `multiply`, `divide`, `scale`, `normalize`, `cross`, `project`, `angle`, and the other distances and similarities | Left out. The six `Vector` functions are the measures that a search needs |
| `search::analyze`, `search::linear`, `search::rrf` | Left out. Use `Query.search` (see [Search](search.md#search)) |
| `math::mode`, `spread`, `product`, `top`, `bottom`, `midhinge`, `trimean`, `interquartile`, `nearestrank` | Left out |
| `rand::string`, `bool`, `float`, `enum`, `time`, `guid` | Left out |
| `http::*`, `sleep`, `session::*`, `sequence::*`, `meta::*`, `value::*`, `object::*`, `parse::*`, `ml::*` | Left out: a side effect, or a different kind of clause |
| `record::id`, `record::exists`, `type::is_*` | Not needed. `Id.key` and `link.id` read the id. The schema checks that links exist. The Roc type fixes the type of a column |

For any other SurrealDB function, add a form with [Extend the translator](advanced.md#extend-the-translator), or send raw text (see [Raw SurrealQL](advanced.md#raw-surrealql)).

## Limits

| Limit | What to do instead |
| --- | --- |
| A call with no form is `Err(Unsupported(..))` at run time, not a compile error | Put `expect q.to_surql().is_ok()` in your module for each query |
| An intrinsic called in code that runs is the compile error `exists only in reified code` | Call it only in a clause. Use a mirror function when you need the value in Roc |
| A builtin, a mirror function or an intrinsic passed as a value is a compile error | Wrap it: `tags.any(\|t\| Surreal.Text.is_email(t))` |
| `List.sort` and `sort_reversed` work only for whole numbers and `Dec` | Sort in Roc, or order the result with `order_by` |
| `Math.percentile` is refused over the rows of a group | Call it on a list field of one row |
| `Math.median` is refused in a view and in `totals` | Take the median per group with `group_by` (see [Totals of all rows](queries.md#totals-of-all-rows)) |
| `Time.floor`, `ceil` and `round` stop the Roc program outside 1677-09-21 to 2262-04-11, and for a span above `I64.highest` nanoseconds. The server refuses the same times | Keep times and spans in the range |
| The unit of `Time.group` must be a tag that the clause writes | Write `Month`, not a variable |
| `Rand.*` and `Hash.argon2` are refused in a query clause, a `check`, an `assert` and a signin | Use them in `default_by`, `computed`, an update or a signup. To use a random value in a query, make it in Roc and pass it with `filter_by` |
| The body of a database function may not call an intrinsic | Call the intrinsic in the clause and pass the result as an argument |
| A database function is a top-level constant with a literal name and no captured value | Make the function top-level. Pass values as arguments |
| `Surreal.datetime(text)` cannot be called in a clause | Pass a datetime as a `filter_by` parameter (see [Datetimes and durations](data-types.md#datetimes-and-durations)) |
| `Str.len` and float arithmetic helpers (`max`, `min`, `pow`, `to_str`, sign tests) are refused | `count_utf8_bytes()`, and `Dec` or an integer |
| The `Math` functions take `List(F64)`. `mean_dec` takes `List(Dec)` | Convert an integer with `to_f64()` |
| Two vectors of different dimensions stop the Roc program and are an error on the server | Check the dimension of the index (see [Vector indexes](search.md#vector-indexes)) |
| A function that calls itself is refused in a clause | Write the loop in Roc, or use a database function |
