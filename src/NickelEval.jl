module NickelEval

export nickel_eval, nickel_eval_file, @ncl_str, NickelError, NickelEnum
export nickel_to_json, nickel_to_yaml, nickel_to_toml
export check_ffi_available, build_ffi
export nickel_open, NickelValue, NickelSession, nickel_kind

"""
    NickelError <: Exception

Exception thrown when Nickel evaluation fails.

# Fields
- `message::String`: The error message from Nickel

# Examples
```julia
try
    nickel_eval("{ x = }")  # syntax error
catch e
    if e isa NickelError
        println("Nickel error: ", e.message)
    end
end
```
"""
struct NickelError <: Exception
    message::String
end

Base.showerror(io::IO, e::NickelError) = print(io, "NickelError: ", e.message)

"""
    NickelEnum

Represents a Nickel enum value.

# Fields
- `tag::Symbol`: The enum variant name
- `arg::Any`: The argument (nothing for simple enums)

# Examples
```julia
result = nickel_eval("let x = 'Some 42 in x")
result.tag   # => :Some
result.arg   # => 42
result == :Some  # => true

result = nickel_eval("let x = 'None in x")
result.tag   # => :None
result.arg   # => nothing
```
"""
struct NickelEnum
    tag::Symbol
    arg::Any
end

# Convenience: compare enum to symbol
Base.:(==)(e::NickelEnum, s::Symbol) = e.tag == s
Base.:(==)(s::Symbol, e::NickelEnum) = e.tag == s

# Pretty printing
function Base.show(io::IO, e::NickelEnum)
    if e.arg === nothing
        print(io, "'", e.tag)
    else
        print(io, "'", e.tag, " ", repr(e.arg))
    end
end

# ── Lazy evaluation types ─────────────────────────────────────────────────────

"""
    NickelSession

Owns a Nickel evaluation context for lazy (shallow) evaluation.
Tracks all allocated expressions and frees them on `close`.

Not thread-safe. All access must occur on a single thread.
"""
mutable struct NickelSession
    ctx::Ptr{Cvoid}                  # Ptr{LibNickel.nickel_context} — Cvoid avoids forward ref
    exprs::Vector{Ptr{Cvoid}}        # tracked allocations, freed on close
    closed::Bool
end

"""
    NickelValue

A lazy reference to a Nickel expression. Accessing fields (`.field` or `["field"]`)
evaluates only the requested sub-expression. Use `collect` to materialize the
full subtree into plain Julia types.

# Examples
```julia
nickel_open("{ x = 1, y = { z = 2 } }") do cfg
    cfg.x        # => 1
    cfg.y.z      # => 2
    collect(cfg)  # => Dict("x" => 1, "y" => Dict("z" => 2))
end
```
"""
struct NickelValue
    session::NickelSession
    expr::Ptr{Cvoid}                 # Ptr{LibNickel.nickel_expr}
end

"""
    @ncl_str -> Any

String macro for inline Nickel evaluation.

# Examples
```julia
julia> ncl"1 + 1"
2

julia> ncl"{ x = 10 }"["x"]
10
```
"""
macro ncl_str(code)
    :(nickel_eval($code))
end

include("ffi.jl")

function __init__()
    __init_ffi__()
end

end # module
