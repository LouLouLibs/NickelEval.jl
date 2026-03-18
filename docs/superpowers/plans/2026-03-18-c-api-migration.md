# C API Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the custom Rust FFI wrapper with direct Julia bindings to Nickel's official C API, and drop the subprocess evaluation path.

**Architecture:** Build the upstream `nickel-lang` crate (with `--features capi`) as a cdylib. Use Clang.jl to generate `ccall` wrappers from `nickel_lang.h`. Write a thin Julia convenience layer that allocates C API handles, evaluates, walks the result tree, and frees handles in `try/finally`. Library discovery: local `deps/` first, then artifacts, then build from source.

**Tech Stack:** Julia, Nickel C API (v1.16.0 / `nickel-lang` crate v2.0.0), Clang.jl (dev tool), Artifacts.jl

**Spec:** `docs/superpowers/specs/2026-03-17-c-api-migration-design.md`

---

### Task 1: Build Nickel C API library locally and generate bindings

This task gets the cdylib built on your machine and produces the generated `ccall` wrappers. Everything else depends on this.

**Files:**
- Create: `deps/generate_bindings.jl`
- Create: `deps/generator.toml`
- Create: `deps/Project.toml` (isolated env for Clang.jl)
- Create: `src/libnickel.jl` (generated output)

- [ ] **Step 1: Verify Nickel v1.16.0 exists, then clone and build**

```bash
# Verify the tag exists first
git ls-remote --tags https://github.com/nickel-lang/nickel.git 1.16.0
# If tag doesn't exist, find the latest release with capi support (>= 1.15.1)
# and update NICKEL_VERSION accordingly throughout the plan

cd /tmp
git clone --depth 1 --branch 1.16.0 https://github.com/nickel-lang/nickel.git nickel-capi
cd nickel-capi
cargo build --release -p nickel-lang --features capi
```

Verify: a `libnickel_lang.dylib` (macOS) or `libnickel_lang.so` (Linux) exists in `target/release/`.

- [ ] **Step 2: Generate the C header**

```bash
cd /tmp/nickel-capi/nickel
cargo install cbindgen
cbindgen --config cbindgen.toml --crate nickel-lang --output /tmp/nickel_lang.h
```

Verify: `/tmp/nickel_lang.h` exists and contains `nickel_context_alloc`, `nickel_expr_is_bool`, etc.

- [ ] **Step 3: Document actual C API signatures**

Read `/tmp/nickel_lang.h` and verify the function signatures match our plan's assumptions. Key functions to check:

- `nickel_context_eval_deep` — what args does it take? Does it accept `const char*` for source code?
- `nickel_expr_as_str` — does it return length and take an out-pointer for the string data?
- `nickel_expr_as_number` — does it return a `nickel_number*`?
- `nickel_record_key_value_by_index` — what are the exact out-pointer types?
- `nickel_context_eval_deep_for_export` — does this exist with the same signature as `eval_deep`?
- `nickel_context_expr_to_json/yaml/toml` — what args?
- `nickel_error_format_as_string` — what args?
- `nickel_context_set_source_name` — does this exist?
- `nickel_result` enum — what are the actual values?

If any signatures differ from the plan, note them. The `_walk_expr` code in Task 2 must be adapted to match the real signatures. The logic (predicate -> extract -> recurse) stays the same; only types and arg positions may change.

- [ ] **Step 4: Copy library and header to deps/**

```bash
cp /tmp/nickel-capi/target/release/libnickel_lang.dylib deps/  # or .so on Linux
cp /tmp/nickel_lang.h deps/
```

- [ ] **Step 5: Create isolated Clang.jl environment**

Create `deps/Project.toml` for the binding generator (keeps Clang.jl out of the main project):

```toml
[deps]
Clang = "40e3b903-d033-50b4-a0cc-940c62c95e31"
```

- [ ] **Step 6: Write `deps/generate_bindings.jl`**

```julia
#!/usr/bin/env julia
# Developer tool: regenerate src/libnickel.jl from deps/nickel_lang.h
# Usage: julia --project=deps/ deps/generate_bindings.jl

using Clang
using Clang.Generators

cd(@__DIR__)

header = joinpath(@__DIR__, "nickel_lang.h")
if !isfile(header)
    error("deps/nickel_lang.h not found. Build the Nickel C API first.")
end

options = load_options(joinpath(@__DIR__, "generator.toml"))
ctx = create_context([header], get_default_args(), options)
build!(ctx)

println("Bindings generated at src/libnickel.jl")
```

Also create `deps/generator.toml`:

```toml
[general]
library_name = "libnickel_lang"
output_file_path = "../src/libnickel.jl"
module_name = "LibNickel"
jll_pkg_name = ""
export_symbol_prefixes = ["nickel_"]

[codegen]
use_ccall_macro = true
```

- [ ] **Step 7: Run generation and review output**

```bash
julia --project=deps/ -e 'using Pkg; Pkg.instantiate()'
julia --project=deps/ deps/generate_bindings.jl
```

Review the generated `src/libnickel.jl`:
- All ~44 C API functions present
- Return types and argument types reasonable (opaque pointers as `Ptr{Cvoid}` or typed structs)
- Library reference is parameterized (not hardcoded) — if hardcoded to `"libnickel_lang"`, edit to use `LIB_PATH` constant (defined later in `ffi.jl`)

- [ ] **Step 8: Commit**

```bash
git add deps/generate_bindings.jl deps/generator.toml deps/Project.toml src/libnickel.jl
git commit -m "feat: add Clang.jl binding generator and generated C API wrappers"
```

---

### Task 2: Delete old code and rewrite `src/ffi.jl` — core tree-walk logic

Delete `subprocess.jl` first to avoid name collision with the new `nickel_eval`, then replace the binary protocol decoder with a tree-walker.

**Files:**
- Delete: `src/subprocess.jl`
- Delete: `rust/nickel-jl/` (entire directory)
- Rewrite: `src/ffi.jl`
- Rewrite: `src/NickelEval.jl` (remove subprocess include)

**Depends on:** Task 1 (need `src/libnickel.jl` and library in `deps/`)

- [ ] **Step 1: Delete old code and update module to prevent name collision**

```bash
git rm src/subprocess.jl
git rm -r rust/nickel-jl/
```

Then rewrite `src/NickelEval.jl` — this must happen now because both `subprocess.jl` and the new `ffi.jl` define `nickel_eval(code::String)`:

```julia
module NickelEval

export nickel_eval, nickel_eval_file, @ncl_str, NickelError, NickelEnum
export nickel_to_json, nickel_to_yaml, nickel_to_toml
export check_ffi_available

struct NickelError <: Exception
    message::String
end
Base.showerror(io::IO, e::NickelError) = print(io, "NickelError: ", e.message)

struct NickelEnum
    tag::Symbol
    arg::Any
end
Base.:(==)(e::NickelEnum, s::Symbol) = e.tag == s
Base.:(==)(s::Symbol, e::NickelEnum) = e.tag == s
function Base.show(io::IO, e::NickelEnum)
    if e.arg === nothing
        print(io, "'", e.tag)
    else
        print(io, "'", e.tag, " ", repr(e.arg))
    end
end

macro ncl_str(code)
    :(nickel_eval($code))
end

include("ffi.jl")

end # module
```

Also update `Project.toml`: remove JSON from `[deps]` and `[compat]`, bump version to `0.6.0`.

- [ ] **Step 2: Commit the deletion**

```bash
git add src/NickelEval.jl Project.toml
git commit -m "chore: remove subprocess path, rust wrapper, and JSON dependency"
```

- [ ] **Step 3: Write the test for `nickel_eval` with a simple integer**

Create `test/test_eval.jl`:

```julia
@testset "C API Evaluation" begin
    @testset "Primitive types" begin
        @test nickel_eval("42") === Int64(42)
        @test nickel_eval("-42") === Int64(-42)
        @test nickel_eval("0") === Int64(0)
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Expected: FAIL — `nickel_eval` still calls subprocess.

- [ ] **Step 3: Write library loading in `src/ffi.jl`**

Replace the entire file with:

```julia
# FFI bindings to Nickel's official C API
# Generated wrappers in libnickel.jl, convenience layer here.

using Artifacts: artifact_hash
using LazyArtifacts

include("libnickel.jl")

# Platform-specific library name
const LIB_NAME = if Sys.isapple()
    "libnickel_lang.dylib"
elseif Sys.iswindows()
    "nickel_lang.dll"
else
    "libnickel_lang.so"
end

# Find library: local deps/ -> artifact -> not found
function _find_library_path()
    # Local deps/ (custom builds, HPC overrides)
    local_path = joinpath(@__DIR__, "..", "deps", LIB_NAME)
    if isfile(local_path)
        return local_path
    end

    # Artifact (auto-selects platform)
    try
        artifact_dir = @artifact_str("libnickel_lang")
        lib_path = joinpath(artifact_dir, LIB_NAME)
        if isfile(lib_path)
            return lib_path
        end
    catch
    end

    return nothing
end

const LIB_PATH = _find_library_path()
const FFI_AVAILABLE = LIB_PATH !== nothing

"""
    check_ffi_available() -> Bool

Check if the Nickel C API library is available.
"""
check_ffi_available() = FFI_AVAILABLE

function _check_ffi_available()
    FFI_AVAILABLE && return
    error("Nickel C API library not available.\n\n" *
          "Install options:\n" *
          "  1. Build from source: NICKELEVAL_BUILD_FFI=true julia -e 'using Pkg; Pkg.build(\"NickelEval\")'\n" *
          "  2. Place $(LIB_NAME) in deps/ manually\n")
end
```

- [ ] **Step 4: Write the core `_walk_expr` function**

Append to `src/ffi.jl`:

```julia
# Convert a C API nickel_expr to a Julia value by walking the type tree.
# The expr must have been fully evaluated (eval_deep).
function _walk_expr(expr::Ptr{Cvoid})
    if nickel_expr_is_null(expr) != 0
        return nothing
    elseif nickel_expr_is_bool(expr) != 0
        return nickel_expr_as_bool(expr) != 0
    elseif nickel_expr_is_number(expr) != 0
        num = nickel_expr_as_number(expr)  # borrowed pointer, no free
        if nickel_number_is_i64(num) != 0
            return nickel_number_as_i64(num)
        else
            return nickel_number_as_f64(num)
        end
    elseif nickel_expr_is_str(expr) != 0
        out_ptr = Ref{Ptr{UInt8}}(C_NULL)
        len = nickel_expr_as_str(expr, out_ptr)
        return unsafe_string(out_ptr[], len)
    elseif nickel_expr_is_array(expr) != 0
        arr = nickel_expr_as_array(expr)  # borrowed pointer
        n = nickel_array_len(arr)
        result = Vector{Any}(undef, n)
        elem = nickel_expr_alloc()
        try
            for i in 0:(n-1)
                nickel_array_get(arr, i, elem)
                result[i+1] = _walk_expr(elem)
            end
        finally
            nickel_expr_free(elem)
        end
        return result
    elseif nickel_expr_is_record(expr) != 0
        rec = nickel_expr_as_record(expr)  # borrowed pointer
        n = nickel_record_len(rec)
        result = Dict{String, Any}()
        key_ptr = Ref{Ptr{UInt8}}(C_NULL)
        key_len = Ref{Csize_t}(0)
        val_expr = nickel_expr_alloc()
        try
            for i in 0:(n-1)
                nickel_record_key_value_by_index(rec, i, key_ptr, key_len, val_expr)
                key = unsafe_string(key_ptr[], key_len[])
                result[key] = _walk_expr(val_expr)
            end
        finally
            nickel_expr_free(val_expr)
        end
        return result
    elseif nickel_expr_is_enum_variant(expr) != 0
        out_ptr = Ref{Ptr{UInt8}}(C_NULL)
        arg_expr = nickel_expr_alloc()
        try
            len = nickel_expr_as_enum_variant(expr, out_ptr, arg_expr)
            tag = Symbol(unsafe_string(out_ptr[], len))
            arg = _walk_expr(arg_expr)
            return NickelEnum(tag, arg)
        finally
            nickel_expr_free(arg_expr)
        end
    elseif nickel_expr_is_enum_tag(expr) != 0
        out_ptr = Ref{Ptr{UInt8}}(C_NULL)
        len = nickel_expr_as_enum_tag(expr, out_ptr)
        tag = Symbol(unsafe_string(out_ptr[], len))
        return NickelEnum(tag, nothing)
    else
        error("Unknown Nickel expression type")
    end
end
```

**Note:** The exact `ccall` wrapper signatures from `libnickel.jl` may differ. Adjust argument types (e.g., `Ptr{Cvoid}` vs named opaque types) to match the generated bindings. The key logic — predicate checks, extraction, recursion — stays the same.

- [ ] **Step 5: Write `nickel_eval(code::String)`**

Append to `src/ffi.jl`:

```julia
"""
    nickel_eval(code::String) -> Any

Evaluate Nickel code and return a Julia value.

Returns native Julia types: Int64, Float64, Bool, String, nothing,
Vector{Any}, Dict{String,Any}, or NickelEnum.
"""
function nickel_eval(code::String)
    _check_ffi_available()
    ctx = nickel_context_alloc()
    expr = nickel_expr_alloc()
    err = nickel_error_alloc()
    try
        result = nickel_context_eval_deep(ctx, code, expr, err)
        if result != 0  # NICKEL_RESULT_ERR
            _throw_nickel_error(err)
        end
        return _walk_expr(expr)
    finally
        nickel_error_free(err)
        nickel_expr_free(expr)
        nickel_context_free(ctx)
    end
end

"""
    nickel_eval(code::String, ::Type{T}) -> T

Evaluate Nickel code and convert to type T.
Supports Dict, Vector, and NamedTuple conversions from the tree-walked result.
"""
function nickel_eval(code::String, ::Type{T}) where T
    result = nickel_eval(code)
    return _convert_result(T, result)
end

# Recursive type conversion for tree-walked results.
# Handles cases that Julia's convert() does not (NamedTuple from Dict, typed containers).
_convert_result(::Type{T}, x) where T = convert(T, x)

function _convert_result(::Type{T}, d::Dict{String,Any}) where T <: NamedTuple
    fields = fieldnames(T)
    types = fieldtypes(T)
    values = Tuple(_convert_result(types[i], d[String(fields[i])]) for i in eachindex(fields))
    return T(values)
end

function _convert_result(::Type{Dict{K,V}}, d::Dict{String,Any}) where {K,V}
    return Dict{K,V}(K(k) => _convert_result(V, v) for (k, v) in d)
end

function _convert_result(::Type{Vector{T}}, v::Vector{Any}) where T
    return T[_convert_result(T, x) for x in v]
end

function _throw_nickel_error(err::Ptr{Cvoid})
    out_str = nickel_string_alloc()
    try
        nickel_error_format_as_string(err, out_str)
        ptr = nickel_string_data(out_str)
        # nickel_string_data returns pointer; need length
        # The exact API may vary — check generated bindings
        msg = unsafe_string(ptr)
        throw(NickelError(msg))
    finally
        nickel_string_free(out_str)
    end
end
```

- [ ] **Step 6: Run primitive type tests**

```bash
julia --project=. -e '
using NickelEval, Test
@test nickel_eval("42") === Int64(42)
@test nickel_eval("3.14") ≈ 3.14
@test nickel_eval("true") === true
@test nickel_eval("null") === nothing
@test nickel_eval("\"hello\"") == "hello"
println("All primitive tests passed")
'
```

Expected: PASS. If any fail, debug by checking the generated binding signatures against the actual C API.

- [ ] **Step 7: Commit**

```bash
git add src/ffi.jl
git commit -m "feat: rewrite ffi.jl to use Nickel C API tree-walk"
```

---

### Task 3: Add file evaluation, export functions, and string macro

**Files:**
- Modify: `src/ffi.jl` (append functions)

**Depends on:** Task 2

- [ ] **Step 1: Write tests for file evaluation**

Add to `test/test_eval.jl`:

```julia
@testset "File Evaluation" begin
    mktempdir() do dir
        # Simple file
        f = joinpath(dir, "test.ncl")
        write(f, "{ x = 42 }")
        result = nickel_eval_file(f)
        @test result["x"] === Int64(42)

        # File with import
        shared = joinpath(dir, "shared.ncl")
        write(shared, "{ val = 100 }")
        main = joinpath(dir, "main.ncl")
        write(main, """
        let s = import "shared.ncl" in
        { result = s.val }
        """)
        result = nickel_eval_file(main)
        @test result["result"] === Int64(100)
    end
end
```

- [ ] **Step 2: Implement `nickel_eval_file`**

Append to `src/ffi.jl`:

```julia
"""
    nickel_eval_file(path::String) -> Any

Evaluate a Nickel file. Supports `import` statements resolved relative
to the file's directory.
"""
function nickel_eval_file(path::String)
    _check_ffi_available()
    abs_path = abspath(path)
    if !isfile(abs_path)
        throw(NickelError("File not found: $abs_path"))
    end
    code = read(abs_path, String)
    ctx = nickel_context_alloc()
    expr = nickel_expr_alloc()
    err = nickel_error_alloc()
    try
        nickel_context_set_source_name(ctx, abs_path)
        result = nickel_context_eval_deep(ctx, code, expr, err)
        if result != 0
            _throw_nickel_error(err)
        end
        return _walk_expr(expr)
    finally
        nickel_error_free(err)
        nickel_expr_free(expr)
        nickel_context_free(ctx)
    end
end
```

- [ ] **Step 3: Run file evaluation tests**

```bash
julia --project=. -e 'using NickelEval, Test; include("test/test_eval.jl")'
```

Expected: PASS

- [ ] **Step 4: Write tests for export functions**

Add to `test/test_eval.jl`:

```julia
@testset "Export formats" begin
    json = nickel_to_json("{ a = 1 }")
    @test occursin("\"a\"", json)
    @test occursin("1", json)

    yaml = nickel_to_yaml("{ a = 1 }")
    @test occursin("a:", yaml)

    toml = nickel_to_toml("{ a = 1 }")
    @test occursin("a = 1", toml)
end
```

- [ ] **Step 5: Implement export functions**

Append to `src/ffi.jl`:

```julia
function _eval_and_serialize(code::String, serialize_fn::Function)
    _check_ffi_available()
    ctx = nickel_context_alloc()
    expr = nickel_expr_alloc()
    err = nickel_error_alloc()
    out_str = nickel_string_alloc()
    try
        result = nickel_context_eval_deep_for_export(ctx, code, expr, err)
        if result != 0
            _throw_nickel_error(err)
        end
        serialize_fn(ctx, expr, out_str)
        ptr = nickel_string_data(out_str)
        return unsafe_string(ptr)
    finally
        nickel_string_free(out_str)
        nickel_error_free(err)
        nickel_expr_free(expr)
        nickel_context_free(ctx)
    end
end

"""
    nickel_to_json(code::String) -> String

Export Nickel code to a JSON string.
"""
nickel_to_json(code::String) = _eval_and_serialize(code, nickel_context_expr_to_json)

"""
    nickel_to_yaml(code::String) -> String

Export Nickel code to a YAML string.
"""
nickel_to_yaml(code::String) = _eval_and_serialize(code, nickel_context_expr_to_yaml)

"""
    nickel_to_toml(code::String) -> String

Export Nickel code to a TOML string.
"""
nickel_to_toml(code::String) = _eval_and_serialize(code, nickel_context_expr_to_toml)
```

- [ ] **Step 6: Run export tests**

```bash
julia --project=. -e 'using NickelEval, Test; include("test/test_eval.jl")'
```

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add src/ffi.jl test/test_eval.jl
git commit -m "feat: add file evaluation and export functions via C API"
```

---

### Task 4: Complete the test suite

Port all tests from `test/test_ffi.jl` into `test/test_eval.jl` (started in Task 2), add export and typed conversion tests, and rewrite `test/runtests.jl`.

**Files:**
- Rewrite: `test/test_eval.jl` (expand with full test port from `test_ffi.jl`)
- Rewrite: `test/runtests.jl`
- Delete: `test/test_subprocess.jl`, `test/test_ffi.jl`

**Depends on:** Task 3

- [ ] **Step 1: Port `test/test_ffi.jl` into `test/test_eval.jl`**

Copy the content of `test/test_ffi.jl` into `test/test_eval.jl`, applying these substitutions:
- `nickel_eval_native(x)` → `nickel_eval(x)` (throughout)
- `nickel_eval_file_native(x)` → `nickel_eval_file(x)` (throughout)
- Remove the `FFI JSON Evaluation` testset entirely (lines 341-351 of test_ffi.jl)
- Keep ALL other testsets: primitive types, arrays, records, type preservation, computed values, record operations, array operations, all enum testsets, deeply nested structures, file evaluation with imports, error handling

The test content is ~95% identical — just function name changes.

- [ ] **Step 2: Add export format, string macro, error, and typed conversion tests**

Append to `test/test_eval.jl`:

```julia
@testset "Export Formats" begin
    json = nickel_to_json("{ a = 1, b = 2 }")
    @test occursin("\"a\"", json)
    @test occursin("\"b\"", json)

    yaml = nickel_to_yaml("{ name = \"test\", port = 8080 }")
    @test occursin("name:", yaml)

    toml = nickel_to_toml("{ name = \"test\", port = 8080 }")
    @test occursin("name", toml)
end

@testset "String macro" begin
    @test ncl"42" === Int64(42)
    @test ncl"\"hello\"" == "hello"
end

@testset "Error handling" begin
    @test_throws NickelError nickel_eval("{ x = }")
    @test_throws NickelError nickel_eval_file("/nonexistent/path.ncl")
end

@testset "Typed conversion" begin
    # Dict{String, Int}
    result = nickel_eval("{ a = 1, b = 2 }", Dict{String, Int})
    @test result isa Dict{String, Int}
    @test result["a"] == 1

    # Vector{Int}
    result = nickel_eval("[1, 2, 3]", Vector{Int})
    @test result isa Vector{Int}
    @test result == [1, 2, 3]

    # NamedTuple
    result = nickel_eval("{ x = 1, y = 2 }", @NamedTuple{x::Int, y::Int})
    @test result isa @NamedTuple{x::Int, y::Int}
    @test result.x == 1
    @test result.y == 2
end

@testset "File evaluation import resolution" begin
    # Verify that set_source_name correctly resolves relative imports
    mktempdir() do dir
        write(joinpath(dir, "dep.ncl"), "{ val = 99 }")
        write(joinpath(dir, "main.ncl"), """
        let d = import "dep.ncl" in
        { result = d.val }
        """)
        result = nickel_eval_file(joinpath(dir, "main.ncl"))
        @test result["result"] === Int64(99)
    end
end
```

- [ ] **Step 3: Write `test/runtests.jl`**

```julia
using NickelEval
using Test

@testset "NickelEval.jl" begin
    if check_ffi_available()
        include("test_eval.jl")
    else
        @warn "Nickel C API library not available. Build with: NICKELEVAL_BUILD_FFI=true julia -e 'using Pkg; Pkg.build(\"NickelEval\")'"
        @test_skip "C API not available"
    end
end
```

- [ ] **Step 4: Delete old test files**

```bash
git rm test/test_subprocess.jl test/test_ffi.jl
```

- [ ] **Step 5: Run full test suite**

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add test/runtests.jl test/test_eval.jl
git commit -m "test: port test suite to C API, remove old test files"
```

---

### Task 5: Rewrite `deps/build.jl` for source builds

**Files:**
- Rewrite: `deps/build.jl`

**Depends on:** Task 4

- [ ] **Step 1: Rewrite `deps/build.jl`**

```julia
# Build script: compile Nickel's C API library from source
# Triggered by NICKELEVAL_BUILD_FFI=true or when no artifact/local lib exists

const NICKEL_VERSION = "1.16.0"
const NICKEL_REPO = "https://github.com/nickel-lang/nickel.git"

function library_name()
    if Sys.isapple()
        return "libnickel_lang.dylib"
    elseif Sys.iswindows()
        return "nickel_lang.dll"
    else
        return "libnickel_lang.so"
    end
end

function build_nickel_capi()
    cargo = Sys.which("cargo")
    if cargo === nothing
        @warn "cargo not found in PATH. Install Rust: https://rustup.rs/"
        return false
    end

    src_dir = joinpath(@__DIR__, "_nickel_src")

    # Clone or update
    if isdir(src_dir)
        @info "Updating Nickel source..."
        cd(src_dir) do
            run(`git fetch --depth 1 origin tag $(NICKEL_VERSION)`)
            run(`git checkout $(NICKEL_VERSION)`)
        end
    else
        @info "Cloning Nickel $(NICKEL_VERSION)..."
        run(`git clone --depth 1 --branch $(NICKEL_VERSION) $(NICKEL_REPO) $(src_dir)`)
    end

    @info "Building Nickel C API library..."
    try
        cd(src_dir) do
            run(`cargo build --release -p nickel-lang --features capi`)
        end

        src_lib = joinpath(src_dir, "target", "release", library_name())
        dst_lib = joinpath(@__DIR__, library_name())

        if isfile(src_lib)
            cp(src_lib, dst_lib; force=true)
            @info "Library built: $(dst_lib)"

            # Also copy header if cbindgen is available
            if Sys.which("cbindgen") !== nothing
                cd(joinpath(src_dir, "nickel")) do
                    run(`cbindgen --config cbindgen.toml --crate nickel-lang --output $(joinpath(@__DIR__, "nickel_lang.h"))`)
                end
                @info "Header generated: $(joinpath(@__DIR__, "nickel_lang.h"))"
            end

            return true
        else
            @warn "Built library not found at $(src_lib)"
            return false
        end
    catch e
        @warn "Build failed: $(e)"
        return false
    end
end

if get(ENV, "NICKELEVAL_BUILD_FFI", "false") == "true"
    build_nickel_capi()
else
    @info "Skipping FFI build (set NICKELEVAL_BUILD_FFI=true to enable)"
end
```

- [ ] **Step 2: Test build from source**

```bash
NICKELEVAL_BUILD_FFI=true julia --project=. deps/build.jl
```

Expected: Library builds and is copied to `deps/`.

- [ ] **Step 3: Commit**

```bash
git add deps/build.jl
git commit -m "feat: rewrite build.jl to build upstream Nickel C API from source"
```

---

### Task 6: Update artifacts and CI

**Files:**
- Modify: `Artifacts.toml`
- Modify: `.github/workflows/build-ffi.yml`
- Modify: `.github/workflows/CI.yml`

**Depends on:** Task 4, Task 5

- [ ] **Step 1: Update `Artifacts.toml`**

Replace with placeholder for new artifact name (`libnickel_lang` instead of `libnickel_jl`), two platforms only:

```toml
# Pre-built Nickel C API library
# Built by GitHub Actions from nickel-lang/nickel v1.16.0 with --features capi
# Platforms: aarch64-darwin, x86_64-linux

# macOS Apple Silicon (aarch64)
[[libnickel_lang]]
arch = "aarch64"
git-tree-sha1 = "TODO"
os = "macos"
lazy = true

    [[libnickel_lang.download]]
    url = "https://github.com/LouLouLibs/NickelEval.jl/releases/download/v0.6.0/libnickel_lang-aarch64-apple-darwin.tar.gz"
    sha256 = "TODO"

# Linux x86_64
[[libnickel_lang]]
arch = "x86_64"
git-tree-sha1 = "TODO"
os = "linux"
lazy = true

    [[libnickel_lang.download]]
    url = "https://github.com/LouLouLibs/NickelEval.jl/releases/download/v0.6.0/libnickel_lang-x86_64-linux-gnu.tar.gz"
    sha256 = "TODO"
```

- [ ] **Step 3: Update `.github/workflows/build-ffi.yml`**

Reduce to 2 platforms. Build upstream `nickel-lang` crate instead of `rust/nickel-jl`:

```yaml
name: Build FFI Library

on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:

jobs:
  build:
    strategy:
      fail-fast: false
      matrix:
        include:
          - os: ubuntu-latest
            target: x86_64-unknown-linux-gnu
            artifact: libnickel_lang.so
            artifact_name: libnickel_lang-x86_64-linux-gnu.tar.gz
          - os: macos-14
            target: aarch64-apple-darwin
            artifact: libnickel_lang.dylib
            artifact_name: libnickel_lang-aarch64-apple-darwin.tar.gz

    runs-on: ${{ matrix.os }}

    steps:
      - name: Clone Nickel
        run: git clone --depth 1 --branch 1.16.0 https://github.com/nickel-lang/nickel.git

      - name: Install Rust
        uses: dtolnay/rust-toolchain@stable
        with:
          targets: ${{ matrix.target }}

      - name: Build library
        working-directory: nickel
        run: cargo build --release -p nickel-lang --features capi --target ${{ matrix.target }}

      - name: Package artifact
        run: |
          cd nickel/target/${{ matrix.target }}/release
          tar -czvf ${{ matrix.artifact_name }} ${{ matrix.artifact }}
          mv ${{ matrix.artifact_name }} ${{ github.workspace }}/

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: ${{ matrix.artifact_name }}
          path: ${{ matrix.artifact_name }}

  release:
    needs: build
    runs-on: ubuntu-latest
    if: startsWith(github.ref, 'refs/tags/')
    permissions:
      contents: write

    steps:
      - name: Download all artifacts
        uses: actions/download-artifact@v4
        with:
          path: artifacts

      - name: Create Release
        uses: softprops/action-gh-release@v1
        with:
          files: artifacts/**/*.tar.gz
          generate_release_notes: true
```

- [ ] **Step 4: Update `.github/workflows/CI.yml`**

Remove Nickel CLI install. Build C API from source with Rust cargo caching to avoid rebuilding on every CI run:

```yaml
name: CI

on:
  push:
    branches:
      - main
    tags: '*'
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: julia-actions/setup-julia@v2
        with:
          version: '1'
      - uses: julia-actions/cache@v2
      - name: Install Rust
        uses: dtolnay/rust-toolchain@stable
      - name: Cache Rust build
        uses: actions/cache@v4
        with:
          path: deps/_nickel_src/target
          key: nickel-capi-${{ runner.os }}-1.16.0
      - name: Build Nickel C API
        run: NICKELEVAL_BUILD_FFI=true julia --project=. deps/build.jl
      - name: Run tests
        run: julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
```

- [ ] **Step 5: Run tests one more time**

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Artifacts.toml .github/workflows/build-ffi.yml .github/workflows/CI.yml
git commit -m "chore: update artifacts and CI for C API"
```

---

### Task 7: Update documentation

**Files:**
- Modify: `docs/src/index.md`
- Modify: `docs/src/lib/public.md`
- Modify: `docs/src/man/quickstart.md`
- Delete: `docs/src/man/ffi.md` (old FFI docs — now the only path)
- Delete: `docs/src/man/typed.md` (references `nickel_read` and JSON.jl typed parsing — both removed)
- Delete: `docs/src/man/export.md` (references `nickel_export` with format kwarg — removed)
- Modify: `docs/make.jl` (remove deleted pages from nav)
- Modify: `CLAUDE.md` and `.claude/CLAUDE.md`

**Depends on:** Task 6

- [ ] **Step 1: Update `docs/src/lib/public.md`**

Remove all old function docs (`nickel_eval_ffi`, `nickel_eval_native`, `nickel_eval_file_native`, `nickel_export`, `nickel_read`, `find_nickel_executable`). Keep/add docs for: `nickel_eval`, `nickel_eval_file`, `nickel_to_json`, `nickel_to_yaml`, `nickel_to_toml`, `check_ffi_available`, `@ncl_str`, `NickelError`, `NickelEnum`.

- [ ] **Step 2: Update quickstart and index**

Update examples to use `nickel_eval` instead of `nickel_eval_native`. Remove subprocess references. Update install instructions to mention the C API library.

- [ ] **Step 3: Remove obsolete doc pages and update `docs/make.jl`**

```bash
git rm docs/src/man/ffi.md docs/src/man/typed.md docs/src/man/export.md
```

Update `docs/make.jl` to remove `"man/ffi.md"`, `"man/typed.md"`, and `"man/export.md"` from the pages list.

- [ ] **Step 4: Update `CLAUDE.md`**

Update the root `CLAUDE.md` to reflect the new architecture: no more `rust/nickel-jl`, no more `subprocess.jl`, no more binary protocol, no more JSON.jl. Update the API functions section and building instructions. Also update `.claude/CLAUDE.md` if it references old architecture.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md .claude/CLAUDE.md docs/
git commit -m "docs: update documentation for C API migration"
```
