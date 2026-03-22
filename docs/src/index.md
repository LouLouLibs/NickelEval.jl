# NickelEval.jl

Julia bindings for the [Nickel](https://nickel-lang.org/) configuration language, using the official Nickel C API.

Evaluate Nickel code directly from Julia and get back native Julia types — no CLI, no intermediate files, no serialization overhead.

## Features

- **Direct evaluation** of Nickel expressions and files via the C API
- **Native type mapping** — records become `Dict`, arrays become `Vector`, enums become `NickelEnum`
- **Typed evaluation** — request results as `Dict{String,Int}`, `Vector{Float64}`, `NamedTuple`, etc.
- **Export to JSON, TOML, YAML** — serialize Nickel configurations to standard formats
- **File evaluation with imports** — evaluate `.ncl` files that reference other Nickel files

## Documentation

```@contents
Pages = [
    "man/examples.md",
    "man/detailed.md",
    "lib/public.md",
]
Depth = 1
```

## Installation

### From the LouLouLibs Registry

```julia
using Pkg
Pkg.Registry.add(url="https://github.com/LouLouLibs/loulouJL")
Pkg.add("NickelEval")
```

### From GitHub

```julia
using Pkg
Pkg.add(url="https://github.com/LouLouLibs/NickelEval.jl")
```

Pre-built native libraries are provided for **macOS (Apple Silicon)** and **Linux (x86\_64)**. On supported platforms, the library downloads automatically when first needed.

### Building from Source

If the pre-built binary doesn't work on your system — or if no binary is available for your platform — you can build the Nickel C API library from source. This requires [Rust](https://rustup.rs/).

```julia
using NickelEval
build_ffi()
```

This clones the Nickel repository, compiles the C API library with `cargo`, and installs it into the package's `deps/` directory. The FFI is re-initialized automatically — no Julia restart needed.

You can also trigger the build during package installation:

```julia
ENV["NICKELEVAL_BUILD_FFI"] = "true"
using Pkg
Pkg.build("NickelEval")
```

### Older Linux Systems (glibc Compatibility)

The pre-built Linux binary is compiled against a relatively recent version of glibc. On older distributions — CentOS 7, older Ubuntu LTS, or many HPC clusters — you may see an error like:

```
/lib64/libm.so.6: version `GLIBC_2.29' not found
```

The fix is to build from source:

```julia
using NickelEval
build_ffi()
```

This compiles Nickel against your system's glibc, producing a compatible binary. The only requirement is a working Rust toolchain (`cargo`), which can be installed without root access via [rustup](https://rustup.rs/):

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

After installing Rust, restart your Julia session and run `build_ffi()`.
