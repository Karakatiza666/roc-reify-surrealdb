# Full-text and vector search

This page shows how to search the text of a field and how to find the rows whose vector is nearest a probe. Both searches use an index that you define in the schema. Both are steps of a query, so you write them in Roc and the compiler checks them.

```
Surreal.analyzer(..) ---> Analyzer ---+
                                      v
table.text_index(path, analyzer) --> FullText(row) ---> query.search(index, terms)
                                                          rows become (row, Hit)
table.vector_index(path, shape) ---> VectorIndex(row) --> query.nearest(index, probe, knn)
                                                          rows become (row, Near)
```

The same values build the definition and the query. A search cannot name an index that you did not make, and a probe of the wrong size is refused when the query is built.

All examples use the table `chart` of `examples/search.roc`. A row is a note of a visit, with its text and a short embedding:

```roc
# Fragment: uses `import surreal.Surreal` from a script app.
Chart : { id : Str, patient : Str, body : Str, embedding : List(F64) }

charts : Surreal.Table(Chart)
charts = Surreal.table("chart")
```

From `examples/search.roc`, `Chart` and `charts`. The terms "intrinsic" and "mirror function" are in the [glossary](getting-started.md#words-used-in-these-pages).

## Analyzers

An analyzer says how a text is cut into terms. A full-text index and a search use the same analyzer. Make one with `Surreal.analyzer(name, tokenizers, filters)`. Give its `define()` to `Surreal.schema`:

```roc
# Fragment: uses `Surreal` from a script app.
clinical : Surreal.Analyzer
clinical = Surreal.analyzer("clinical", [Class], [Lowercase])

schema_text : Try(Str, Surreal.Error)
schema_text = Surreal.schema([clinical.define()])
```

From `examples/search.roc`, `clinical`. The definition from a real run:

```surql
DEFINE ANALYZER OVERWRITE clinical TOKENIZERS class FILTERS lowercase;
```

`Surreal.schema` writes the analyzers before the tables. See [Build the schema](schema.md#build-the-schema).

### Tokenizers and filters

A tokenizer cuts the text. A filter changes each term. The filters run in the order that you give.

| Tokenizer | Cuts the text |
| --- | --- |
| `Blank` | At white space |
| `Class` | Where the class of a character changes: letter, digit, white space, other |
| `Camel` | Before an upper-case letter that follows a lower-case one |
| `Punct` | At punctuation, and keeps the punctuation as terms |

| Filter | Changes each term to |
| --- | --- |
| `Lowercase`, `Uppercase` | The term in lower case or upper case |
| `Ascii` | The term with ASCII letters for accented letters |
| `Snowball(language)` | The stem of the word, for example `Snowball("english")` |
| `EdgeNgram(low, high)` | The first `low` to `high` characters |
| `Ngram(low, high)` | Every run of `low` to `high` characters |

A real run with `Surreal.analyzer("fancy", [Blank, Camel], [Lowercase, Ascii, Snowball("english"), EdgeNgram(2, 4)])` gives:

```surql
DEFINE ANALYZER OVERWRITE fancy TOKENIZERS blank,camel FILTERS lowercase,ascii,snowball(english),edgengram(2,4);
```

### The Roc meaning of an analyzer

`Analyzer.tokens(text)` and `Analyzer.matches(text, query)` run in Roc. They are the Roc meaning of a search: you can compute in a test which rows a search keeps.

| Call | Gives |
| --- | --- |
| `clinical.tokens("Rex limping, 2x")` | `["rex", "limping", ",", "2", "x"]` |
| `clinical.matches(body, "Left LEG")` | `Bool.True` when the query has a term and the text has every term of it |

This works for the tokenizers `Blank` and `Class`, the filters `Lowercase` and `Uppercase`, and ASCII text. For any other analyzer, or for a character outside ASCII, the call stops the program. Only the database can compute these. `examples/search.roc` uses `matches` in `expect` lines and in the `-- roc:` literals that `tests/check.py` compares with the server.

## Full-text indexes

Call `table.text_index(path, analyzer)` with a function that reads one `Str` field. It gives a `FullText(row)`. Give the value to `define()` with `text_index`:

```roc
# Fragment: uses `charts` and `clinical` from above.
chart_text : Surreal.FullText(Chart)
chart_text = charts.text_index(|c| c.body, clinical)

chart_def : Surreal.Defined
chart_def = charts.define().text_index(chart_text).done()
```

From `examples/search.roc`, `chart_text` and `chart_def`. That file also adds the vector index to `chart_def`. The index from a real run:

```surql
DEFINE INDEX OVERWRITE chart_body_fulltext ON chart FIELDS body FULLTEXT ANALYZER clinical BM25 HIGHLIGHTS;
```

The index name is `<table>_<path>_fulltext`. The index keeps the highlights, so `highlight` and `offsets` work. See [Indexes for search](schema.md#indexes-for-search) for the other `define()` clauses.

| Mistake | What you get |
| --- | --- |
| The path is not a `Str` field | A type error: `text_index` needs `row -> Str` |
| `Surreal.schema` does not get the analyzer | ``BadSchema("the full-text index on `chart.body` names the analyzer `clinical`, which the schema does not define: give its `define()` to `schema`")`` |

## Search

Call `query.search(index, terms)` on a query of the table of the index. It keeps the rows whose text has the terms. The row becomes a pair `(row, hit)`:

```roc
# Fragment: uses `charts` and `chart_text` from above.
Surreal.from(charts).search(chart_text, "limping").select(|(c, _)| { id: c.id })
```

From `examples/search.roc`, `search_limping`. The statement from a real run:

```surql
SELECT record::id(id) AS id FROM chart WHERE body @1@ 'limping';
```

The library numbers the search, so no clause writes the `1`. The terms go in as a quoted string literal. A text from a user cannot add SurrealQL. A real run of the terms `it's` gives `'it\'s'`.

A search keeps a row when the text has every term of the terms, as the analyzer cuts them. A query of two terms keeps the rows that have both. A query with no term keeps no row. The example runs `"Left LEG"`, which keeps `c1` and `c2`.

A `filter` before or after the search joins the `WHERE` with `AND`. Real runs:

```surql
SELECT record::id(id) AS id FROM chart WHERE (patient = 'rex') AND (body @1@ 'limping');
SELECT record::id(id) AS id FROM chart WHERE (body @1@ 'limping') AND (patient = 'rex');
```

The first is `filter` then `search`, and the second is `search` then `filter`.

### Scores, highlights and offsets

The second part of the pair is a `Hit`. Its three methods are intrinsics. SurrealDB computes them, and a clause reads them.

| Roc | SurrealQL | Gives |
| --- | --- | --- |
| `hit.score()` | `search::score(1)` | The BM25 score, an `F64` |
| `hit.highlight(before, after)` | `search::highlight(before, after, 1)` | The text, with each term between `before` and `after` |
| `hit.offsets()` | `search::offsets(1)['0'].map(..)` | A `List({ start : I64, end : I64 })`, `end` not included |

`ORDER BY` takes a column. Select the score as a column, then order by it:

```roc
# Fragment: uses `charts` and `chart_text` from above.
Ranked : { id : Str, marked : Str, score : F64 }

Surreal.from(charts)
	.search(chart_text, "limping")
	.select(|(c, hit)| { id: c.id, score: hit.score(), marked: hit.highlight("<b>", "</b>") })
	.order_by(|r| r.score, Desc)
```

From `examples/search.roc`, `search_ranked`. The statement from a real run:

```surql
SELECT record::id(id) AS id, search::highlight('<b>', '</b>', 1) AS marked, search::score(1) AS score FROM chart WHERE body @1@ 'limping' ORDER BY score DESC;
```

With `.ready()` the type of each row is `Ranked`. A session reads the rows of the reply as `List(Ranked)`. The reply of SurrealDB 4.0.1 to this statement, over the seed rows in a scratch database, read as `List(Ranked)`:

```
Ok([{ id: "c6", marked: "Bo eats well and no <b>limping</b>.", score: 0.8937065601348877 }, { id: "c2", marked: "Rex <b>limping</b> again, left leg swollen.", score: 0.8498564958572388 }, { id: "c4", marked: "Mimi has a <b>limping</b> gait, right leg sore.", score: 0.7739118337631226 }])
```

Notes on a score:

| Fact | Detail |
| --- | --- |
| A score has no fixed scale | The scale changed from SurrealDB 3.3.4 to 4.0.1. On 3.3.4 a term that half the rows or more have added 0. On 4.0.1 it adds more than 0: a term in 2 of 3 rows gave the score 0.434 |
| A filter can read a score | `filter(|(_, hit)| hit.score() > 0.8)` gives `AND (search::score(1) > 0.8f)`. A real run on 4.0.1 kept `c2` and `c6` |
| `limit` works | `.order_by(..).limit(2)` adds `LIMIT 2` |

`offsets` gives the places of each term. For `"left leg"` the example reads the offsets `[{ end: 21, start: 17 }, { end: 30, start: 27 }]` for `c1`. See [Order and page results](queries.md#order-and-page-results) for `order_by` and `limit`.

## Vector indexes

Call `table.vector_index(path, { dimension, distance })` with a function that reads a `List(F64)` or a `List(F32)` field. It gives a `VectorIndex(row)`. Give it to `define()` with `vector_index`:

```roc
# Fragment: uses `charts` from above.
chart_vectors : Surreal.VectorIndex(Chart)
chart_vectors = charts.vector_index(|c| c.embedding, { dimension: 3, distance: Cosine })

chart_def : Surreal.Defined
chart_def = charts.define().text_index(chart_text).vector_index(chart_vectors).done()
```

From `examples/search.roc`, `chart_vectors` and `chart_def`. The index from a real run:

```surql
DEFINE INDEX OVERWRITE chart_embedding_hnsw ON chart FIELDS embedding HNSW DIMENSION 3 DIST COSINE TYPE F64;
```

The index name is `<table>_<path>_hnsw`. It is an HNSW index.

| Choice | Values | SurrealQL |
| --- | --- | --- |
| `distance` | `Cosine`, `Euclidean`, `Manhattan`, `Chebyshev` | `DIST COSINE`, `DIST EUCLIDEAN`, `DIST MANHATTAN`, `DIST CHEBYSHEV` |
| Element type | `List(F64)`, `List(F32)` | `TYPE F64`, `TYPE F32` |
| `dimension` | A `U64` | `DIMENSION n` |

Another element type, such as `List(I64)`, gives ``BadSchema("a vector index of `ints` is over a `List(F64)` or a `List(F32)`, not a `List(I64)`")`` when you build the schema.

### The dimension of a write

After you define the index, SurrealDB refuses a vector of another size. A real run of `charts.create(..)` with `embedding: [1.0, 0.0]` printed:

```surql
CREATE chart:⟨c9⟩ CONTENT { body: 'Short.', embedding: [1f, 0f], patient: 'rex' } RETURN AFTER;
```

The session gave `Err(Server(Other({ kind: "Internal", message: "Incorrect vector dimension (2). Expected a vector of 3 dimension." })))`. See [Server errors](errors.md#server-errors).

## Nearest rows

Call `query.nearest(index, probe, knn)` with a `List(F64)` as the probe. The row becomes a pair `(row, near)`. The third argument is a `Knn`:

| Value | SurrealQL | What it does |
| --- | --- | --- |
| `Exact(k)` | `<\|k,COSINE\|>` | Measures every row. Gives the `k` nearest, by the distance of the index |
| `Approx({ k, ef })` | `<\|k,ef\|>` | Walks the HNSW graph with `ef` candidates. May miss a row |

```roc
# Fragment: uses `charts` and `chart_vectors` from above.
Surreal.from(charts)
	.nearest(chart_vectors, [1.0, 0.0, 0.0], Exact(3))
	.select(|(c, near)| { id: c.id, distance: near.distance() })
	.order_by(|r| r.distance, Asc)
```

From `examples/search.roc`, `nearest_exact`. The statement from a real run:

```surql
SELECT vector::distance::knn() AS distance, record::id(id) AS id FROM chart WHERE embedding <|3,COSINE|> [1f, 0f, 0f] ORDER BY distance;
```

A session read the rows as `List({ id : Str, distance : F64 })`:

```
Ok([{ distance: 0.006116265326381098, id: "c1" }, { distance: 0.07001889004944584, id: "c2" }, { distance: 0.25579159246474936, id: "c4" }])
```

`near.distance()` is an intrinsic, `vector::distance::knn()`. It uses the distance of the index. Order by the selected column, as for a score. The statement of `Approx({ k: 3, ef: 40 })` from a real run:

```surql
SELECT record::id(id) AS id FROM chart WHERE embedding <|3,40|> [1f, 0f, 0f];
```

The probe must have the dimension of the index. A probe of 2 numbers for the index above gives ``Unsupported("the probe of `nearest` has 2 numbers, and the vector index of `chart.embedding` has the dimension 3")`` when you call `prepare` or `to_surql`.

### Filters and nearest rows

A `filter` joins the `WHERE` with `AND`, before or after `nearest`. The server then takes the `k` nearest among the rows that the filters keep. A real run:

```surql
SELECT record::id(id) AS id FROM chart WHERE (patient != 'rex') AND (embedding <|2,COSINE|> [1f, 0f, 0f]);
```

The example gives `c4` and `c6`. These are the two nearest notes of the patients that are not `rex`. They are not the first two of all notes, filtered after.

### The Roc meaning of nearest rows

The Roc meaning of `Exact(k)` is: sort the rows by their distance from the probe, and take the first `k`. `examples/search.roc` does this with `Vector` functions in `nearest`, and compares the result with the server. The distance of `near.distance()` has no Roc value. The HNSW index keeps its own copy of each vector, and `TYPE F32` rounds it. To get a distance in Roc, measure the row with a `Vector` function.

## Vector functions

The functions of `Surreal.Vector` measure two vectors in a clause and in Roc. They give the same value on the server and in Roc, to the last bit. [Vector](functions.md#vector) has the table. A filter that uses one, from `examples/search.roc`, `vector_filter`:

```surql
SELECT record::id(id) AS id FROM chart WHERE vector::similarity::cosine(embedding, [0.5f, 0.25f, 0.125f]) > 0.9f;
```

The cosine distance of an index is `1 - similarity_cosine(a, b)`.

## Limits

| Limit | What to do instead |
| --- | --- |
| A query has one `search` or one `nearest`, and not both. A second one is a type error: `search` needs `FullText((Chart, Surreal.Hit))` and gets `FullText(Chart)`. The row type is already a pair | Run two queries. Join the results in Roc |
| A live query refuses a search and `nearest`: ``Unsupported("a live query has no full-text or vector search: ..")`` | Watch the rows with a `filter`. Search them when a notice comes. See [Live queries](live-queries.md#limits) |
| A search needs its index in the database. A database with no index gives the server error `There was no suitable index supporting the expression: body @1@ 'limping'` | Run the schema script before the search. See [Build the schema](schema.md#build-the-schema) |
| `Analyzer.tokens` and `matches` cover `Blank`, `Class`, `Lowercase`, `Uppercase` and ASCII text. Any other analyzer or text stops the program | Test with an analyzer of these tokenizers. Check the other analyzers on a server |
| A score, a highlight, an offset list and a KNN distance have no Roc value. `Hit` and `Near` have no value in a program. A projection that reads them cannot run on your own rows | Select them as columns. Write the expected order by hand in a test, as `examples/search.roc` does |
| `MTREE` and the form `<\|k\|>` are not available. `Knn` has two forms | Use `Exact` or `Approx` with an HNSW index |
| `search::analyze`, `search::linear` and `search::rrf` are not available. See [Functions that are not available](functions.md#functions-that-are-not-available) | Use `search` and `Analyzer.tokens` |
| A vector index takes a `List(F64)` or a `List(F32)` field. A probe is a `List(F64)` | Store the vector as one of these |
