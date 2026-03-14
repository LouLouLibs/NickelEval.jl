# NickelEval.jl

Julia bindings for the [Nickel](https://nickel-lang.org/) configuration language.

Evaluate Nickel code directly from Julia with native type conversion and export to JSON/TOML/YAML.

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

**Prerequisite:** Install the Nickel CLI from https://nickel-lang.org/

## Quick Start

```julia
using NickelEval

# Simple evaluation
nickel_eval("1 + 2")  # => 3

# Records return JSON.Object with dot-access
config = nickel_eval("{ name = \"alice\", age = 30 }")
config.name  # => "alice"
config.age   # => 30

# String macro for inline Nickel
ncl"[1, 2, 3] |> std.array.map (fun x => x * 2)"
# => [2, 4, 6]
```

## Typed Evaluation

Convert Nickel values directly to Julia types:

```julia
# Typed dictionaries
nickel_eval("{ a = 1, b = 2 }", Dict{String, Int})
# => Dict{String, Int64}("a" => 1, "b" => 2)

# Symbol keys
nickel_eval("{ x = 1.5, y = 2.5 }", Dict{Symbol, Float64})
# => Dict{Symbol, Float64}(:x => 1.5, :y => 2.5)

# Typed arrays
nickel_eval("[1, 2, 3, 4, 5]", Vector{Int})
# => [1, 2, 3, 4, 5]

# NamedTuples for structured data
config = nickel_eval("""
{
  host = "localhost",
  port = 8080,
  debug = true
}
""", @NamedTuple{host::String, port::Int, debug::Bool})
# => (host = "localhost", port = 8080, debug = true)

config.port  # => 8080
```

## Export to Configuration Formats

Generate JSON, TOML, or YAML from Nickel:

```julia
# JSON
nickel_to_json("{ name = \"myapp\", port = 8080 }")
# => "{\n  \"name\": \"myapp\",\n  \"port\": 8080\n}"

# TOML
nickel_to_toml("{ name = \"myapp\", port = 8080 }")
# => "name = \"myapp\"\nport = 8080\n"

# YAML
nickel_to_yaml("{ name = \"myapp\", port = 8080 }")
# => "name: myapp\nport: 8080\n"

# Or use nickel_export with format option
nickel_export("{ a = 1 }"; format=:toml)
nickel_export("{ a = 1 }"; format=:yaml)
nickel_export("{ a = 1 }"; format=:json)
```

### Generate Config Files

```julia
# Generate a TOML config file from Nickel
config_ncl = """
{
  database = {
    host = "localhost",
    port = 5432,
    name = "mydb"
  },
  server = {
    host = "0.0.0.0",
    port = 8080
  }
}
"""

# Write TOML
write("config.toml", nickel_to_toml(config_ncl))

# Write YAML
write("config.yaml", nickel_to_yaml(config_ncl))
```

## Custom Structs

Define your own types and parse Nickel directly into them:

```julia
struct ServerConfig
    host::String
    port::Int
    workers::Int
end

config = nickel_eval("""
{
  host = "0.0.0.0",
  port = 3000,
  workers = 4
}
""", ServerConfig)
# => ServerConfig("0.0.0.0", 3000, 4)
```

## File Evaluation

```julia
# config.ncl:
# {
#   environment = "production",
#   features = ["auth", "logging", "metrics"]
# }

# Untyped (returns JSON.Object with dot-access)
config = nickel_eval_file("config.ncl")
config.environment  # => "production"

# Typed
nickel_eval_file("config.ncl", @NamedTuple{environment::String, features::Vector{String}})
# => (environment = "production", features = ["auth", "logging", "metrics"])
```

## FFI Mode (High Performance)

For repeated evaluations, use the native FFI bindings (no subprocess overhead):

```julia
# Check if FFI is available
check_ffi_available()  # => true/false

# Use FFI evaluation
nickel_eval_ffi("1 + 2")  # => 3
nickel_eval_ffi("{ x = 1 }", Dict{String, Int})  # => Dict("x" => 1)
```

### Building FFI

The FFI library requires Rust. To build:

```bash
cd rust/nickel-jl
cargo build --release
cp target/release/libnickel_jl.dylib ../../deps/  # macOS
# or libnickel_jl.so on Linux, nickel_jl.dll on Windows
```

## API Reference

### Evaluation Functions

| Function | Description |
|----------|-------------|
| `nickel_eval(code)` | Evaluate Nickel code, return `JSON.Object` |
| `nickel_eval(code, T)` | Evaluate and convert to type `T` |
| `nickel_eval_file(path)` | Evaluate a `.ncl` file |
| `nickel_eval_file(path, T)` | Evaluate file and convert to type `T` |
| `nickel_read(code, T)` | Alias for `nickel_eval(code, T)` |
| `@ncl_str` | String macro for inline evaluation |

### Export Functions

| Function | Description |
|----------|-------------|
| `nickel_to_json(code)` | Export to JSON string |
| `nickel_to_toml(code)` | Export to TOML string |
| `nickel_to_yaml(code)` | Export to YAML string |
| `nickel_export(code; format=:json)` | Export to format (`:json`, `:yaml`, `:toml`) |

### FFI Functions

| Function | Description |
|----------|-------------|
| `nickel_eval_ffi(code)` | FFI-based evaluation (faster) |
| `nickel_eval_ffi(code, T)` | FFI evaluation with type conversion |
| `check_ffi_available()` | Check if FFI bindings are available |

## Type Conversion

| Nickel Type | Julia Type |
|-------------|------------|
| Number | `Int64` or `Float64` |
| String | `String` |
| Bool | `Bool` |
| Array | `Vector{Any}` or `Vector{T}` |
| Record | `JSON.Object` (dot-access) or `Dict{K,V}` or `NamedTuple` or struct |
| Null | `nothing` |

## Error Handling

```julia
try
    nickel_eval("{ x = }")  # syntax error
catch e
    if e isa NickelError
        println("Nickel error: ", e.message)
    end
end
```

## License

MIT
