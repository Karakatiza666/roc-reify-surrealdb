#!/usr/bin/env python3
"""Writes an app with N prepared queries for scripts/build_budget.sh.

Each query is a function of run-time values, in one of four shapes from
tests/CapturedTest.roc, and main! calls each one once and prints its
script. Usage: gen_budget.py N OUT.roc INTERNAL (INTERNAL: the path of
src/internal.roc, as the app header names it)."""
import sys

n = int(sys.argv[1])
out = sys.argv[2]
internal = sys.argv[3]
cbor = "https://github.com/Karakatiza666/roc-cbor/releases/download/0.5.1/38XQEgbABvGrHkqPVDVMsabgXcBHouMQde1vz4cLchxT.tar.zst"
header = f'''app [main!] {{
	cbor: "{cbor}",
	internal: "{internal}",
}}

import internal.Surreal

Medication : {{ id : Str, name : Str, unit_price : Dec, stock : U64 }}

medications : Surreal.Table(Medication)
medications = Surreal.table("medication")

PriceLine : {{ name : Str, over : Dec }}

script : Surreal.Prepared(out) -> Str
script = |prepared| match prepared.request().map_ok(|r| r.to_script()) {{
	Ok(text) => text
	Err(e) => "error: ${{Str.inspect(e)}}"
}}
'''
shapes = [
    ("Dec -> Surreal.Prepared(List(Medication))",
     lambda i: f"|limit| Surreal.from(medications).filter(|m| m.unit_price < limit and m.stock > {i}).ready()", "d"),
    ("Dec, Dec -> Surreal.Prepared(List(PriceLine))",
     lambda i: f"|least, base| Surreal.from(medications).filter(|m| m.unit_price >= least and m.stock != {i}).select(|m| {{ name: m.name, over: m.unit_price - base }}).ready()", "d, d"),
    ("U64, U64 -> Surreal.Prepared(List(Medication))",
     lambda i: f"|skip, size| Surreal.from(medications).filter(|m| m.stock > {i}).select(|m| m).order_by(|m| m.name, Asc).start(skip).limit(size).ready()", "u, u"),
    ("Str -> Surreal.Prepared(List(Medication))",
     lambda i: f"|nm| Surreal.from(medications).filter(|m| m.name == nm or m.stock == {i}).ready()", "s"),
]
lines = [header]
calls = []
for i in range(n):
    ty, body, args = shapes[i % len(shapes)]
    lines += [f"q{i} : {ty}", f"q{i} = {body(i)}", ""]
    calls.append(f"\techo!(script(q{i}({args})))")
lines += ["main! = |args| {", "\tu = args.len()", "\td = u.to_dec()", "\ts = u.to_str()"]
lines += calls + ["\tOk({})", "}", ""]
with open(out, "w") as f:
    f.write("\n".join(lines))
