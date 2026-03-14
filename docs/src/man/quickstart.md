# Quick Start

## Installation

### From LouLouLibs Registry (Recommended)

```julia
using Pkg
Pkg.Registry.add(url="https://github.com/LouLouLibs/loulouJL")
Pkg.add("NickelEval")
```

### From GitHub URL

```julia
using Pkg
Pkg.add(url="https://github.com/LouLouLibs/NickelEval.jl")
```

Make sure you have the Nickel CLI installed:
- macOS: `brew install nickel`
- Other: See [nickel-lang.org](https://nickel-lang.org/)

## Basic Usage

```julia
using NickelEval

# Evaluate simple expressions
nickel_eval("1 + 2")      # => 3
nickel_eval("true")       # => true
nickel_eval("\"hello\"")  # => "hello"
```

## Working with Records

Nickel records become `JSON.Object` with dot-access:

```julia
config = nickel_eval("""
{
  database = {
    host = "localhost",
    port = 5432
  },
  debug = true
}
""")

config.database.host  # => "localhost"
config.database.port  # => 5432
config.debug          # => true
```

## Let Bindings and Functions

```julia
# Let bindings
nickel_eval("let x = 10 in x * 2")  # => 20

# Functions
nickel_eval("""
let double = fun x => x * 2 in
double 21
""")  # => 42
```

## Arrays

```julia
nickel_eval("[1, 2, 3]")  # => [1, 2, 3]

# Array operations with std library
nickel_eval("[1, 2, 3] |> std.array.map (fun x => x * 2)")
# => [2, 4, 6]
```

## Record Merge

```julia
nickel_eval("{ a = 1 } & { b = 2 }")
# => JSON.Object with a=1, b=2
```

## String Macro

For inline Nickel code:

```julia
ncl"1 + 1"  # => 2

config = ncl"{ host = \"localhost\" }"
config.host  # => "localhost"
```

## File Evaluation

```julia
# Evaluate a .ncl file
config = nickel_eval_file("config.ncl")
```

## Error Handling

```julia
try
    nickel_eval("{ x = }")  # syntax error
catch e
    if e isa NickelError
        println("Error: ", e.message)
    end
end
```
