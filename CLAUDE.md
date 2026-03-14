# NickelEval.jl Development Guide

## Project Overview

NickelEval.jl provides Julia bindings for the [Nickel](https://nickel-lang.org/) configuration language. It supports both subprocess-based evaluation (using the Nickel CLI) and native FFI evaluation (using a Rust wrapper around nickel-lang-core).

## Architecture

```
NickelEval/
├── src/
│   ├── NickelEval.jl    # Main module
│   ├── subprocess.jl    # CLI-based evaluation
│   └── ffi.jl           # Native FFI bindings
├── rust/
│   └── nickel-jl/       # Rust FFI wrapper
│       ├── Cargo.toml
│       └── src/lib.rs
├── deps/
│   └── build.jl         # Build script for FFI
├── Artifacts.toml       # Pre-built FFI library URLs/hashes
├── .github/workflows/
│   ├── CI.yml           # Julia tests
│   ├── Documentation.yml
│   └── build-ffi.yml    # Cross-platform FFI builds
└── test/
    └── test_subprocess.jl
```

## Key Design Decisions

### 1. Use JSON.jl 1.0 (not JSON3.jl)

JSON.jl 1.0 provides:
- Native typed parsing with `JSON.parse(json, T)`
- `JSON.Object` return type with dot-access for records
- Better Julia integration

### 2. Types from Nickel FFI, Not JSON

The Rust FFI returns a binary protocol with native type information:
- Type tags: 0=Null, 1=Bool, 2=Int64, 3=Float64, 4=String, 5=Array, 6=Record, 7=Enum
- Direct memory encoding without JSON serialization overhead
- Preserves integer vs float distinction
- Enum variants preserved as `NickelEnum(tag, arg)`

### 3. Avoid `unwrap()` in Rust

Use proper error handling:
```rust
// Bad
let f = value.to_f64().unwrap();

// Good
let f = f64::try_from(value).map_err(|e| format!("Error: {:?}", e))?;
```

For number conversion, use malachite's `RoundingFrom` trait to handle inexact conversions:
```rust
use malachite::rounding_modes::RoundingMode;
use malachite::num::conversion::traits::RoundingFrom;

let (f, _) = f64::rounding_from(&rational, RoundingMode::Nearest);
```

## Building

### Rust FFI Library

```bash
cd rust/nickel-jl
cargo build --release
cp target/release/libnickel_jl.dylib ../../deps/  # macOS
# or libnickel_jl.so on Linux, nickel_jl.dll on Windows
```

### Running Tests

```bash
# Rust tests
cd rust/nickel-jl
cargo test

# Julia tests (requires Nickel CLI installed)
julia --project=. -e 'using Pkg; Pkg.test()'
```

## Release Process

**Before tagging a new version, ALL CI workflows must pass:**

1. Run tests locally: `julia --project=. -e 'using Pkg; Pkg.test()'`
2. Push changes to main
3. Wait for CI to complete and verify all workflows pass (both CI and Documentation)
4. Only then tag and register the new version

```bash
# Check CI status before tagging
gh run list --repo LouLouLibs/NickelEval.jl --limit 5

# All workflows should show "success" before proceeding with:
git tag -a vX.Y.Z -m "vX.Y.Z: Description"
git push origin vX.Y.Z
```

### Version Bumping Checklist

1. Update `version` in `Project.toml`
2. Update `## Current Version` in `TODO.md`
3. Commit these changes
4. Wait for CI to pass
5. Tag the release
6. If FFI changed, build and upload new artifacts (see FFI Artifact Release below)
7. Update loulouJL registry with correct tree SHA

### FFI Artifact Release

When the Rust FFI code changes, new pre-built binaries must be released:

1. **Trigger the build workflow:**
   ```bash
   gh workflow run build-ffi.yml --ref main
   ```

2. **Download built artifacts** from the workflow run (4 platforms: aarch64-darwin, x86_64-darwin, x86_64-linux, x86_64-windows)

3. **Create GitHub Release** and upload the `.tar.gz` files

4. **Calculate tree hashes** for each artifact:
   ```bash
   # For each tarball:
   tar -xzf libnickel_jl-PLATFORM.tar.gz
   julia -e 'using Pkg; println(Pkg.GitTools.tree_hash("."))'
   ```

5. **Update Artifacts.toml** with new SHA256 checksums and tree hashes

### Artifacts.toml Format

Use the `[[artifact_name]]` array format with platform properties:

```toml
[[libnickel_jl]]
arch = "aarch64"
git-tree-sha1 = "TREE_HASH_HERE"
os = "macos"
lazy = true

    [[libnickel_jl.download]]
    url = "https://github.com/LouLouLibs/NickelEval.jl/releases/download/vX.Y.Z/libnickel_jl-aarch64-apple-darwin.tar.gz"
    sha256 = "SHA256_HASH_HERE"
```

Platform values:
- `os`: "macos", "linux", "windows"
- `arch`: "aarch64", "x86_64"

### Documentation Requirements

Any new exported function must be added to `docs/src/lib/public.md` in the appropriate section to avoid documentation build failures.

### Registry (loulouJL)

Location: `/Users/loulou/Dropbox/projects_code/julia_packages/loulouJL/N/NickelEval/`

**Files to update:**

1. **Versions.toml** - Add new version entry:
   ```toml
   ["X.Y.Z"]
   git-tree-sha1 = "TREE_SHA_HERE"
   ```
   Get tree SHA: `git rev-parse vX.Y.Z^{tree}`

2. **Deps.toml** - If dependencies changed, add new version range:
   ```toml
   ["X.Y-0"]
   Artifacts = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"
   JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
   LazyArtifacts = "4af54fe1-eca0-43a8-85a7-787d91b784e3"
   ```
   **Important:** Version ranges must not overlap. Use `"X.Y-Z.W"` for ranges.

3. **Compat.toml** - If compat bounds changed:
   ```toml
   ["X.Y-0"]
   JSON = ["0.21", "1"]
   ```
   Use arrays for multiple compatible versions: `["0.21", "1"]`

**Registry format rules:**
- Section headers must be quoted: `["0.5"]` not `[0.5]`
- Version ranges: `"0.4-0.5"` (from 0.4 to 0.5), `"0.5-0"` (from 0.5 to end of 0.x)
- No spaces in ranges
- Ranges must not overlap for the same dependency

## Binary Protocol Specification

The FFI uses a binary protocol for native type encoding:

| Type Tag | Encoding |
|----------|----------|
| 0 (Null) | Just the tag byte |
| 1 (Bool) | Tag + 1 byte (0=false, 1=true) |
| 2 (Int64) | Tag + 8 bytes (little-endian i64) |
| 3 (Float64) | Tag + 8 bytes (little-endian f64) |
| 4 (String) | Tag + 4 bytes length + UTF-8 bytes |
| 5 (Array) | Tag + 4 bytes count + elements |
| 6 (Record) | Tag + 4 bytes field count + (key_len, key, value)* |
| 7 (Enum) | Tag + 4 bytes tag_len + tag_bytes + 1 byte has_arg + [arg_value] |

## API Functions

### Evaluation (Subprocess - requires Nickel CLI)

- `nickel_eval(code)` - Evaluate to `JSON.Object`
- `nickel_eval(code, T)` - Evaluate and convert to type `T`
- `nickel_eval_file(path)` - Evaluate a `.ncl` file

### Evaluation (Native FFI - no CLI needed)

- `nickel_eval_ffi(code)` - FFI evaluation via JSON (supports typed parsing)
- `nickel_eval_ffi(code, T)` - FFI evaluation with type conversion
- `nickel_eval_native(code)` - FFI with binary protocol (preserves types)
- `nickel_eval_file_native(path)` - Evaluate file with import support
- `check_ffi_available()` - Check if FFI library is loaded

### Export

- `nickel_to_json(code)` - Export to JSON string
- `nickel_to_toml(code)` - Export to TOML string
- `nickel_to_yaml(code)` - Export to YAML string
- `nickel_export(code; format=:json)` - Export to any format

## Type Conversion

| Nickel Type | Julia Type (FFI native) | Julia Type (JSON) |
|-------------|-------------------------|-------------------|
| Null | `nothing` | `nothing` |
| Bool | `Bool` | `Bool` |
| Number (integer) | `Int64` | `Int64` |
| Number (float) | `Float64` | `Float64` |
| String | `String` | `String` |
| Array | `Vector{Any}` | `JSON.Array` |
| Record | `Dict{String,Any}` | `JSON.Object` |
| Enum | `NickelEnum(tag, arg)` | N/A (JSON export) |

## Nickel Language Reference

Common patterns used in tests:

```nickel
# Let bindings
let x = 1 in x + 2

# Functions
let double = fun x => x * 2 in double 21

# Records
{ name = "test", value = 42 }

# Record merge
{ a = 1 } & { b = 2 }

# Arrays
[1, 2, 3]

# Array operations
[1, 2, 3] |> std.array.map (fun x => x * 2)

# Nested structures
{ outer = { inner = 42 } }
```

## Dependencies

### Julia
- JSON.jl >= 0.21 or >= 1.0
- Artifacts (stdlib)
- LazyArtifacts (stdlib)

### Rust (for building FFI locally)
- nickel-lang-core = "0.9"
- malachite = "0.4"
- serde_json = "1.0"

## Future Improvements

1. Complete Julia-side binary protocol decoder
2. Support for Nickel contracts/types in Julia
3. Streaming evaluation for large configs
4. REPL integration
