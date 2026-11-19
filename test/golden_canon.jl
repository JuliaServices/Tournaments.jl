# One text form for parsed JSON values, with object keys sorted, so a result's
# digest doesn't depend on key order. Shared by golden.jl and the script that
# wrote golden/corpus.jsonl.gz.
canon(x::AbstractDict) = "{" * join(("$(repr(String(k))):$(canon(x[k]))" for k in sort!(collect(keys(x)))), ",") * "}"
canon(x::AbstractVector) = "[" * join((canon(v) for v in x), ",") * "]"
canon(x::AbstractString) = repr(String(x))
canon(::Nothing) = "null"
canon(x::Bool) = x ? "true" : "false"
canon(x::Integer) = string(x)
