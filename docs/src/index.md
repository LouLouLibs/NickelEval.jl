# NickelEval.jl

Julia bindings for the [Nickel](https://nickel-lang.org/) configuration language.

## Features

- **Evaluate Nickel code** directly from Julia
- **Native type conversion** to Julia types (`Dict`, `NamedTuple`, custom structs)
- **Export to multiple formats** (JSON, TOML, YAML)
- **High-performance C API** using the official Nickel C API — no CLI needed

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

No external tools are required. The Nickel evaluator is bundled as a pre-built native library.

## Quick Example

```julia
using NickelEval

# Simple evaluation
nickel_eval("1 + 2")  # => 3

# Records return Dict{String, Any}
config = nickel_eval("{ host = \"localhost\", port = 8080 }")
config["host"]  # => "localhost"
config["port"]  # => 8080

# Typed evaluation
nickel_eval("{ x = 1, y = 2 }", Dict{String, Int})
# => Dict{String, Int64}("x" => 1, "y" => 2)

# Export to TOML
nickel_to_toml("{ name = \"myapp\", version = \"1.0\" }")
# => "name = \"myapp\"\nversion = \"1.0\"\n"
```

## Why Nickel?

[Nickel](https://nickel-lang.org/) is a configuration language designed to be:

- **Programmable**: Functions, let bindings, and standard library
- **Typed**: Optional contracts for validation
- **Mergeable**: Combine configurations with `&`
- **Safe**: No side effects, pure functional

NickelEval.jl lets you leverage Nickel's power directly in your Julia workflows.
