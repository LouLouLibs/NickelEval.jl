# NickelEval.jl

Julia bindings for the [Nickel](https://nickel-lang.org/) configuration language, using the official Nickel C API.

Evaluate Nickel code directly from Julia with native type conversion and export to JSON/TOML/YAML. No Nickel CLI required.

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

Pre-built binaries are downloaded automatically on supported platforms (macOS Apple Silicon, Linux x86_64). For other platforms, build from source:

```bash
NICKELEVAL_BUILD_FFI=true julia -e 'using Pkg; Pkg.build("NickelEval")'
```

## Quick Start

```julia
using NickelEval

# Simple evaluation
nickel_eval("1 + 2")  # => 3

# Records return Dict{String, Any}
config = nickel_eval("{ name = \"alice\", age = 30 }")
config["name"]  # => "alice"
config["age"]   # => 30

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

## Enums

Nickel enum types are preserved:

```julia
result = nickel_eval("'Some 42")
result.tag   # => :Some
result.arg   # => 42
result == :Some  # => true

nickel_eval("'None").tag  # => :None
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
```

### Generate Config Files

```julia
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

write("config.toml", nickel_to_toml(config_ncl))
write("config.yaml", nickel_to_yaml(config_ncl))
```

## File Evaluation

Evaluate `.ncl` files with full import support:

```julia
# config.ncl:
# let shared = import "shared.ncl" in
# { name = shared.project_name, version = "1.0" }

config = nickel_eval_file("config.ncl")
config["name"]  # => "MyProject"

# Typed
nickel_eval_file("config.ncl", @NamedTuple{name::String, version::String})
```

Import paths are resolved relative to the file's directory.

## Building from Source

Pre-built binaries are downloaded automatically on macOS Apple Silicon and Linux x86_64. On other platforms (or if `check_ffi_available()` returns `false`), build from source:

```bash
# Requires Rust (https://rustup.rs/)
NICKELEVAL_BUILD_FFI=true julia -e 'using Pkg; Pkg.build("NickelEval")'
```

### HPC / Slurm Clusters

The pre-built Linux binary may fail on clusters with an older glibc. Build from source:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env
NICKELEVAL_BUILD_FFI=true julia -e 'using Pkg; Pkg.build("NickelEval")'
```

Restart Julia after building.

## API Reference

### Evaluation

| Function | Description |
|----------|-------------|
| `nickel_eval(code)` | Evaluate Nickel code, return Julia native types |
| `nickel_eval(code, T)` | Evaluate and convert to type `T` |
| `nickel_eval_file(path)` | Evaluate a `.ncl` file with import support |
| `@ncl_str` | String macro for inline evaluation |
| `check_ffi_available()` | Check if the C API library is loaded |

### Export

| Function | Description |
|----------|-------------|
| `nickel_to_json(code)` | Export to JSON string |
| `nickel_to_toml(code)` | Export to TOML string |
| `nickel_to_yaml(code)` | Export to YAML string |

## Type Conversion

| Nickel Type | Julia Type |
|-------------|------------|
| Number (integer) | `Int64` |
| Number (float) | `Float64` |
| String | `String` |
| Bool | `Bool` |
| Array | `Vector{Any}` (or `Vector{T}` with typed eval) |
| Record | `Dict{String, Any}` (or `NamedTuple` / `Dict{K,V}` with typed eval) |
| Null | `nothing` |
| Enum | `NickelEnum(tag, arg)` |

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
