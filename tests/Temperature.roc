# A body temperature in degrees Celsius, as a package of its own would
# declare it. It knows nothing of SurrealDB: the type hides its
# representation, so a clause that reifies a function over it names its
# operations, and `ExtensionTest.roc` tells the translator what they are in
# SurrealQL.
Temperature :: Dec.{
	from_celsius : Dec -> Temperature
	from_celsius = |degrees| Temperature.(degrees)

	celsius : Temperature -> Dec
	celsius = |Temperature.(degrees)| degrees

	is_gt : Temperature, Temperature -> Bool
	is_gt = |Temperature.(a), Temperature.(b)| a > b

	is_lt : Temperature, Temperature -> Bool
	is_lt = |Temperature.(a), Temperature.(b)| a < b

	## Written with whatever format the caller names: the Surreal package
	## binds a captured temperature in `Encode.Bind`, as its `Dec`.
	encoder_for : _
}
