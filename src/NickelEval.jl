module NickelEval

export nickel_eval, nickel_eval_file, @ncl_str, NickelError, NickelEnum
export nickel_to_json, nickel_to_yaml, nickel_to_toml
export check_ffi_available

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
