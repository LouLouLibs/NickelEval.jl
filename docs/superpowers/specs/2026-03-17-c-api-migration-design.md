# NickelEval.jl: Migration to Nickel's Official C API

## Goal

Replace the custom Rust FFI wrapper (`rust/nickel-jl/`) with direct bindings to Nickel's official C API. Drop the subprocess evaluation path. Reduce maintenance burden.

## Motivation

The current implementation wraps `nickel-lang-core` v0.9 internals (`Term`, `Program`, `CBNCache`) through a custom Rust library that encodes results in a hand-rolled binary protocol. Both the Rust encoder and the Julia decoder must be maintained in lockstep. When Nickel's internal API changes, the wrapper breaks.

Nickel now ships an official C API (`nickel/src/capi.rs`, 44 functions) behind a `capi` feature flag. It provides a stable ABI with opaque types, type predicates, value extractors, and built-in serialization. A Nickel maintainer recommended this approach in [discussion #2540](https://github.com/nickel-lang/nickel/discussions/2540).

## Breaking Changes

This is a major rewrite. All previously exported subprocess functions are removed: `nickel_eval` (subprocess version), `nickel_eval_file` (subprocess version), `nickel_export`, `nickel_read`, `find_nickel_executable`, `nickel_eval_ffi`, `nickel_eval_native`, `nickel_eval_file_native`. The Nickel CLI is no longer required.

`nickel_eval` now returns `Dict{String,Any}` for records instead of `JSON.Object`. Code using dot-access (`result.name`) must switch to bracket-access (`result["name"]`).

JSON.jl is no longer a dependency. The C API handles serialization internally.

## Target Nickel Version

Pin to Nickel **v1.16.0** (Feb 2026). The C API crate is `nickel-lang` v2.0.0 within the monorepo workspace. Source: [`nickel/src/capi.rs`](https://github.com/nickel-lang/nickel/blob/1.16.0/nickel/src/capi.rs).

## What Changes

**Deleted:**
- `rust/nickel-jl/` — the entire custom Rust wrapper
- `src/subprocess.jl` — CLI-based evaluation
- The custom binary protocol (Rust encoder + Julia decoder)
- Windows and x86_64-darwin artifact targets
- `JSON.jl` dependency

**Added:**
- `src/libnickel.jl` — Clang.jl-generated `ccall` wrappers from `nickel_lang.h`
- `deps/generate_bindings.jl` — developer tool to regenerate bindings
- Build-from-source fallback in `deps/build.jl`

**Modified:**
- `src/ffi.jl` — rewritten to walk the C API's opaque tree instead of decoding a binary buffer
- `src/NickelEval.jl` — simplified exports
- `Artifacts.toml` — two platforms only (aarch64-darwin, x86_64-linux)
- `build-ffi.yml` — builds upstream `nickel-lang` crate with `--features capi`

## Project Structure

```
NickelEval/
├── src/
│   ├── NickelEval.jl          # Module, exports, types
│   ├── libnickel.jl           # Generated ccall wrappers (checked in)
│   └── ffi.jl                 # Convenience layer: eval, tree-walk, type conversion
├── deps/
│   ├── build.jl               # Build nickel-lang cdylib from source (fallback)
│   └── generate_bindings.jl   # Clang.jl: regenerate libnickel.jl from header
├── Artifacts.toml             # aarch64-darwin, x86_64-linux
├── .github/workflows/
│   ├── CI.yml
│   └── build-ffi.yml          # 2-platform artifact builds
└── test/
    └── runtests.jl
```

## Public API

```julia
# Evaluation
nickel_eval(code::String)              # Returns Julia native types
nickel_eval(code::String, ::Type{T})   # Typed conversion
nickel_eval_file(path::String)         # Evaluate .ncl file with import support

# Export to string formats (via C API built-in serialization)
nickel_to_json(code::String)  -> String
nickel_to_yaml(code::String)  -> String
nickel_to_toml(code::String)  -> String

# Utility
check_ffi_available() -> Bool

# String macro
@ncl_str                               # ncl"{ x = 1 }" sugar for nickel_eval

# Types
NickelError
NickelEnum
```

## Type Mapping

| Nickel (C API predicate) | Julia |
|--------------------------|-------|
| null (`is_null`) | `nothing` |
| bool (`is_bool`) | `Bool` |
| number, integer (`is_number`, `number_is_i64`) | `Int64` |
| number, float (`is_number`, not `number_is_i64`) | `Float64` |
| string (`is_str`) | `String` |
| array (`is_array`) | `Vector{Any}` |
| record (`is_record`) | `Dict{String,Any}` |
| enum tag (`is_enum_tag`) | `NickelEnum(:Tag, nothing)` |
| enum variant (`is_enum_variant`) | `NickelEnum(:Tag, value)` |

## Internal Flow

### `nickel_eval(code)`

1. Allocate context, expression, and error handles
2. Call `nickel_context_eval_deep(ctx, code, expr, err)`
3. Check result; on error, extract message via `nickel_error_format_as_string` and throw `NickelError`
4. Walk the expression tree recursively:
   - Test type with `nickel_expr_is_*` predicates
   - Extract scalars: `nickel_expr_as_bool`, `nickel_expr_as_str` (returns length, sets pointer), `nickel_expr_as_number` (then `nickel_number_is_i64` / `nickel_number_as_i64` / `nickel_number_as_f64`)
   - For arrays: `nickel_array_len` + `nickel_array_get` per index, recurse
   - For records: `nickel_record_len` + `nickel_record_key_value_by_index` per index, recurse
   - For enums: `nickel_expr_as_enum_tag` (simple) or `nickel_expr_as_enum_variant` (with argument, recurse on argument)
5. Free all handles in a `try/finally` block to prevent leaks on error

### `nickel_eval_file(path)`

Read the file contents in Julia, then pass to `nickel_context_eval_deep` with `nickel_context_set_source_name(ctx, path)` so that relative imports resolve correctly.

### `nickel_to_json/yaml/toml(code)`

1. Allocate context, expression, error, and output string handles
2. Evaluate with `nickel_context_eval_deep_for_export`
3. Serialize with `nickel_context_expr_to_json` / `_to_yaml` / `_to_toml`
4. Extract string from `nickel_string` handle via `nickel_string_data`
5. Free all handles in `try/finally`

### String handling

C API strings are not null-terminated. All string functions return a length and set a pointer. Use `unsafe_string(ptr, len)` in Julia.

## Binding Generation

`deps/generate_bindings.jl` uses Clang.jl to parse `nickel_lang.h` and produce `src/libnickel.jl`. This script is a developer tool, not part of the install pipeline. The generated file is checked into git so users need only the compiled `libnickel_lang` shared library.

To regenerate after a Nickel version bump:

```bash
julia --project=. deps/generate_bindings.jl
```

## Build & Artifacts

**Artifact platforms:** aarch64-darwin, x86_64-linux

**Build-from-source fallback (`deps/build.jl`):**
1. Check for `cargo` in PATH
2. Clone or fetch `nickel-lang/nickel` at a pinned tag
3. Run `cargo build --release -p nickel-lang --features capi`
4. Copy `libnickel_lang.{dylib,so}` and `nickel_lang.h` to `deps/`

**Library discovery order:**
1. Local `deps/` (dev builds, HPC overrides)
2. Artifact from `Artifacts.toml`
3. Trigger source build if neither found

## Testing

Preserve coverage from the existing `test_ffi.jl` (~300 lines). Test categories to port:

- Primitive types: null, bool, integer, float, string
- Collections: arrays (empty, nested, mixed), records (simple, nested, merged)
- Type preservation: Int64 vs Float64 distinction
- Computed values: arithmetic, let bindings, functions
- Enums: simple tags, with arguments, nested, pattern matching
- File evaluation: basic file, imports, nested imports, subdirectory imports
- Error handling: syntax errors, file not found, import not found
- Export formats: JSON, YAML, TOML output strings
- Memory safety: no handle leaks on error paths

## Risks

- **C API stability:** Pinned to Nickel v1.16.0. Breaking changes in future versions require regenerating bindings and possibly updating the tree-walk logic.
- **Rust toolchain requirement:** Needs edition 2024 / rust >= 1.89 for source builds. Users without Rust get artifacts only.
- **Clang.jl output quality:** Generated wrappers may need minor hand-editing for Julia idioms. Mitigation: review generated output before checking in.
- **File evaluation via source name:** `nickel_context_set_source_name` may not fully replicate the import resolution behavior of evaluating a file directly. Needs verification against the C API.
