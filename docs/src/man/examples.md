# Quick Examples

## Evaluating Expressions

```julia
using NickelEval

nickel_eval("1 + 2")        # => 3
nickel_eval("true")          # => true
nickel_eval("\"hello\"")     # => "hello"
nickel_eval("null")          # => nothing
```

Integers return `Int64`, decimals return `Float64`:

```julia
nickel_eval("42")            # => 42 (Int64)
nickel_eval("3.14")          # => 3.14 (Float64)
```

## Records

Nickel records map to `Dict{String, Any}`:

```julia
config = nickel_eval("""
{
  host = "localhost",
  port = 8080,
  debug = true
}
""")

config["host"]   # => "localhost"
config["port"]   # => 8080
config["debug"]  # => true
```

Nested records work as expected:

```julia
result = nickel_eval("{ database = { host = \"localhost\", port = 5432 } }")
result["database"]["host"]  # => "localhost"
```

## Arrays

Nickel arrays map to `Vector{Any}`:

```julia
nickel_eval("[1, 2, 3]")              # => Any[1, 2, 3]
nickel_eval("[\"a\", \"b\", \"c\"]")  # => Any["a", "b", "c"]
```

Use the Nickel standard library for transformations:

```julia
nickel_eval("[1, 2, 3] |> std.array.map (fun x => x * 2)")
# => Any[2, 4, 6]
```

## Let Bindings and Functions

```julia
nickel_eval("let x = 10 in x * 2")  # => 20

nickel_eval("""
let double = fun x => x * 2 in
double 21
""")  # => 42

nickel_eval("""
let add = fun x y => x + y in
add 3 4
""")  # => 7
```

## Record Merge

Nickel's `&` operator merges records:

```julia
nickel_eval("{ a = 1 } & { b = 2 }")
# => Dict("a" => 1, "b" => 2)
```

## String Macro

The `ncl"..."` macro provides a shorthand for `nickel_eval`:

```julia
ncl"1 + 1"                  # => 2
ncl"{ x = 10 }"["x"]        # => 10
ncl"[1, 2, 3]"              # => Any[1, 2, 3]
```

## Evaluating Files

Evaluate `.ncl` files directly. Imports are resolved relative to the file's directory:

```julia
# config.ncl contains: { host = "localhost", port = 8080 }
config = nickel_eval_file("config.ncl")
config["host"]  # => "localhost"
```

## Error Handling

Invalid Nickel code throws a `NickelError`:

```julia
try
    nickel_eval("{ x = }")
catch e
    if e isa NickelError
        println(e.message)  # Nickel's formatted error message
    end
end
```
