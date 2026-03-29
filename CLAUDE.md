# NickelEval.jl Development Guide

## Project Overview

NickelEval.jl provides Julia bindings for the [Nickel](https://nickel-lang.org/) configuration language using the official Nickel C API.

## Architecture

```
NickelEval/
├── src/
│   ├── NickelEval.jl    # Main module
│   ├── libnickel.jl     # Generated ccall wrappers (Clang.jl from nickel_lang.h)
│   └── ffi.jl           # High-level Julia API (nickel_eval, tree-walk, etc.)
├── deps/
│   ├── build.jl         # Build nickel-lang from source (fallback)
│   ├── generate_bindings.jl  # Clang.jl binding regeneration (dev tool)
│   └── nickel_lang.h    # C header from cbindgen
├── Artifacts.toml       # Pre-built library URLs/hashes (aarch64-darwin, x86_64-linux)
├── .github/workflows/
│   ├── CI.yml           # Julia tests
│   ├── Documentation.yml
│   └── build-ffi.yml    # Cross-platform FFI builds
└── test/
    └── runtests.jl
```

## Key Design Decisions

### 1. Official Nickel C API

NickelEval uses the official C API exposed by the `nickel-lang` crate (v2.0.0+) built with `--features capi`. This provides:
- A stable, supported interface to the Nickel evaluator
- Tree-walk value extraction without a custom binary protocol
- No Nickel CLI dependency

### 2. Types via C API Tree-Walk

The C API is walked recursively on the Julia side using `ccall`. Values are converted to Julia native types:
- Records → `Dict{String, Any}`
- Arrays → `Vector{Any}`
- Integers → `Int64`, Floats → `Float64`
- Enums → `NickelEnum(tag, arg)`

### 3. Avoid `unwrap()` in Rust

Use proper error handling in any Rust glue code:
```rust
// Bad
let f = value.to_f64().unwrap();

// Good
let f = f64::try_from(value).map_err(|e| format!("Error: {:?}", e))?;
```

## Building

### Nickel C API Library

```bash
cd rust/nickel-lang
cargo build -p nickel-lang --features capi --release
cp target/release/libnickel_lang.dylib ../../deps/  # macOS
# or libnickel_lang.so on Linux
```

### Running Tests

```bash
# Julia tests
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
2. Commit these changes
4. Wait for CI to pass
5. Tag the release
6. If FFI changed, build and upload new artifacts (see FFI Artifact Release below)
7. Update loulouJL registry with correct tree SHA

### FFI Artifact Release

When the C API library changes, new pre-built binaries must be released:

1. **Trigger the build workflow:**
   ```bash
   gh workflow run build-ffi.yml --ref main
   ```

2. **Download built artifacts** from the workflow run (2 platforms: aarch64-darwin, x86_64-linux)

3. **Create GitHub Release** and upload the `.tar.gz` files

4. **Calculate tree hashes** for each artifact:
   ```bash
   # For each tarball:
   tar -xzf libnickel_lang-PLATFORM.tar.gz
   julia -e 'using Pkg; println(Pkg.GitTools.tree_hash("."))'
   ```

5. **Update Artifacts.toml** with new SHA256 checksums and tree hashes

### Artifacts.toml Format

Use the `[[artifact_name]]` array format with platform properties:

```toml
[[libnickel_lang]]
arch = "aarch64"
git-tree-sha1 = "TREE_HASH_HERE"
os = "macos"
lazy = true

    [[libnickel_lang.download]]
    url = "https://github.com/LouLouLibs/NickelEval.jl/releases/download/vX.Y.Z/libnickel_lang-aarch64-apple-darwin.tar.gz"
    sha256 = "SHA256_HASH_HERE"
```

Platform values:
- `os`: "macos", "linux"
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
   LazyArtifacts = "4af54fe1-eca0-43a8-85a7-787d91b784e3"
   ```
   **Important:** Version ranges must not overlap. Use `"X.Y-Z.W"` for ranges.

3. **Compat.toml** - If compat bounds changed, update accordingly.

**Registry format rules:**
- Section headers must be quoted: `["0.5"]` not `[0.5]`
- Version ranges: `"0.4-0.5"` (from 0.4 to 0.5), `"0.5-0"` (from 0.5 to end of 0.x)
- No spaces in ranges
- Ranges must not overlap for the same dependency

## API Functions

### Evaluation

- `nickel_eval(code)` - Evaluate Nickel code, returns Julia-native types
- `nickel_eval(code, T)` - Evaluate and convert to type `T`
- `nickel_eval_file(path)` - Evaluate a `.ncl` file (supports imports)
- `check_ffi_available()` - Check if the C API library is loaded

### Export

- `nickel_to_json(code)` - Export to JSON string
- `nickel_to_toml(code)` - Export to TOML string
- `nickel_to_yaml(code)` - Export to YAML string

### String Macro

- `ncl"..."` / `@ncl_str` - Evaluate inline Nickel code

## Type Conversion

| Nickel Type | Julia Type |
|-------------|------------|
| Null | `nothing` |
| Bool | `Bool` |
| Number (integer) | `Int64` |
| Number (float) | `Float64` |
| String | `String` |
| Array | `Vector{Any}` |
| Record | `Dict{String, Any}` |
| Enum | `NickelEnum(tag, arg)` |

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
- Artifacts (stdlib)
- LazyArtifacts (stdlib)

### Rust (for building C API library locally)
- nickel-lang = "2.0.0" with `--features capi`

## Future Improvements

1. Support for Nickel contracts/types in Julia
2. Streaming evaluation for large configs
3. REPL integration
