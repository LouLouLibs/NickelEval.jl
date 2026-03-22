# Lazy Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `nickel_open` / `NickelValue` API for lazy, on-demand evaluation of Nickel configs via the C API's shallow eval.

**Architecture:** `NickelSession` owns the `nickel_context` and tracks all expr allocations. `NickelValue` is an immutable wrapper around a single expr + session back-reference. `nickel_open` evaluates shallowly; navigation (`getproperty`/`getindex`) evaluates sub-expressions on demand. `collect` materializes an entire subtree eagerly.

**Tech Stack:** Julia, Nickel C API (ccall via LibNickel module in `src/libnickel.jl`)

**Spec:** `docs/superpowers/specs/2026-03-21-lazy-evaluation-design.md`

**Design deviation:** `NickelSession` has no `root` field (avoids circular type reference). `nickel_open` returns `NickelValue` directly in both do-block and manual modes. `close(::NickelValue)` delegates to `close(session)`.

---

### File Structure

- **Modify:** `src/NickelEval.jl` — add `NickelSession` and `NickelValue` type definitions, new exports
- **Modify:** `src/ffi.jl` — add `nickel_open`, navigation, `collect`, inspection, iteration, `show`
- **Create:** `test/test_lazy.jl` — all lazy evaluation tests
- **Modify:** `test/runtests.jl` — include `test_lazy.jl`
- **Modify:** `docs/src/lib/public.md` — add new exports to docs

---

### Task 1: Define types and wire up test file

Define the two new types in `NickelEval.jl` and create the test file skeleton.

**Files:**
- Modify: `src/NickelEval.jl` (lines 1-6 for exports, add types before `include("ffi.jl")`)
- Create: `test/test_lazy.jl`
- Modify: `test/runtests.jl` (add include for test_lazy.jl)

- [ ] **Step 1: Add types to `src/NickelEval.jl`**

Add after the `NickelEnum` definition (after line 69), before `include("ffi.jl")`:

```julia
# ── Lazy evaluation types ─────────────────────────────────────────────────────

"""
    NickelSession

Owns a Nickel evaluation context for lazy (shallow) evaluation.
Tracks all allocated expressions and frees them on `close`.

Not thread-safe. All access must occur on a single thread.
"""
mutable struct NickelSession
    ctx::Ptr{Cvoid}                  # Ptr{LibNickel.nickel_context} — Cvoid avoids forward ref
    exprs::Vector{Ptr{Cvoid}}        # tracked allocations, freed on close
    closed::Bool
end

"""
    NickelValue

A lazy reference to a Nickel expression. Accessing fields (`.field` or `["field"]`)
evaluates only the requested sub-expression. Use `collect` to materialize the
full subtree into plain Julia types.

# Examples
```julia
nickel_open("{ x = 1, y = { z = 2 } }") do cfg
    cfg.x        # => 1
    cfg.y.z      # => 2
    collect(cfg)  # => Dict("x" => 1, "y" => Dict("z" => 2))
end
```
"""
struct NickelValue
    session::NickelSession
    expr::Ptr{Cvoid}                 # Ptr{LibNickel.nickel_expr}
end
```

Note: We use `Ptr{Cvoid}` here because the `LibNickel` module hasn't been loaded yet at this point in the file. The actual C API calls in `ffi.jl` will `reinterpret` these pointers to the correct types. This is safe because all Nickel opaque types are just pointer-sized handles.

- [ ] **Step 2: Add exports to `src/NickelEval.jl`**

Add a new export line after line 5:

```julia
export nickel_open, NickelValue, NickelSession, nickel_kind
```

- [ ] **Step 3: Create `test/test_lazy.jl` skeleton**

```julia
@testset "Lazy Evaluation" begin
    @testset "nickel_open returns NickelValue" begin
        result = nickel_open("{ x = 1 }") do cfg
            cfg
        end
        @test result isa NickelValue
    end
end
```

- [ ] **Step 4: Add include to `test/runtests.jl`**

After the `include("test_eval.jl")` line (line 6), add:

```julia
        include("test_lazy.jl")
```

- [ ] **Step 5: Run tests — expect failure**

Run: `cd /Users/loulou/Dropbox/projects_claude/NickelEval && julia --project=. -e 'using Pkg; Pkg.test()'`

Expected: FAIL — `nickel_open` is not defined yet. This confirms the test is wired up correctly.

- [ ] **Step 6: Commit types and test skeleton**

```bash
git add src/NickelEval.jl test/test_lazy.jl test/runtests.jl
git commit -m "feat: add NickelSession/NickelValue types and test skeleton"
```

---

### Task 2: Implement `nickel_open` (code string, do-block)

The core function: shallow-eval a code string and return a `NickelValue`.

**Files:**
- Modify: `src/ffi.jl` (append after line 384)

- [ ] **Step 1: Add session helpers to `src/ffi.jl`**

Append to end of `src/ffi.jl`:

```julia
# ── Lazy evaluation ──────────────────────────────────────────────────────────

function _check_session_open(session::NickelSession)
    session.closed && throw(ArgumentError("NickelSession is closed"))
end

# Allocate a new expr tracked by the session
function _tracked_expr_alloc(session::NickelSession)
    expr = L.nickel_expr_alloc()
    push!(session.exprs, Ptr{Cvoid}(expr))
    return expr
end

function Base.close(session::NickelSession)
    session.closed && return
    session.closed = true
    for expr_ptr in session.exprs
        L.nickel_expr_free(Ptr{L.nickel_expr}(expr_ptr))
    end
    empty!(session.exprs)
    L.nickel_context_free(Ptr{L.nickel_context}(session.ctx))
    return nothing
end

Base.close(v::NickelValue) = close(getfield(v, :session))
```

- [ ] **Step 2: Add `nickel_open` for code strings**

Append to `src/ffi.jl`:

```julia
"""
    nickel_open(f, code::String)
    nickel_open(code::String) -> NickelValue

Evaluate Nickel code shallowly and return a lazy `NickelValue`.
Sub-expressions are evaluated on demand when accessed via `.field` or `["field"]`.

# Do-block (preferred)
```julia
nickel_open("{ x = 1, y = 2 }") do cfg
    cfg.x  # => 1 (only evaluates x)
end
```

# Manual
```julia
cfg = nickel_open("{ x = 1, y = 2 }")
cfg.x  # => 1
close(cfg)
```
"""
function nickel_open(f::Function, code::String)
    val = nickel_open(code)
    try
        return f(val)
    finally
        close(val)
    end
end

function nickel_open(code::String)
    _check_ffi_available()
    ctx = L.nickel_context_alloc()
    session = NickelSession(Ptr{Cvoid}(ctx), Ptr{Cvoid}[], false)
    finalizer(close, session)  # safety net: free resources if user forgets close()
    expr = _tracked_expr_alloc(session)
    err = L.nickel_error_alloc()
    try
        result = L.nickel_context_eval_shallow(ctx, code, expr, err)
        if result == L.NICKEL_RESULT_ERR
            _throw_nickel_error(err)
        end
        return NickelValue(session, Ptr{Cvoid}(expr))
    catch
        close(session)
        rethrow()
    finally
        L.nickel_error_free(err)
    end
end
```

Key logic:
- `nickel_context_eval_shallow` evaluates to WHNF — the top-level structure is known (it's a record, array, etc.) but its children remain unevaluated.
- The `err` is freed immediately (it's only needed during eval). The `ctx` and `expr` live on inside the session.
- On error, the session is closed to free the context.
- The do-block variant uses `try/finally` to guarantee cleanup.
- A GC `finalizer` on the session is a safety net for manual mode; users should still call `close` explicitly.

- [ ] **Step 3: Run tests**

Run: `cd /Users/loulou/Dropbox/projects_claude/NickelEval && julia --project=. -e 'using Pkg; Pkg.test()'`

Expected: The test from Task 1 should now... actually fail because we return `cfg` from the do-block but the session is closed at that point. Update the test:

- [ ] **Step 4: Fix test to check type inside do-block**

Update `test/test_lazy.jl`:

```julia
@testset "Lazy Evaluation" begin
    @testset "nickel_open returns NickelValue" begin
        is_nickel_value = nickel_open("{ x = 1 }") do cfg
            cfg isa NickelValue
        end
        @test is_nickel_value
    end
end
```

- [ ] **Step 5: Run tests — expect pass**

Run: `cd /Users/loulou/Dropbox/projects_claude/NickelEval && julia --project=. -e 'using Pkg; Pkg.test()'`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add src/ffi.jl test/test_lazy.jl
git commit -m "feat: implement nickel_open with shallow evaluation"
```

---

### Task 3: Implement `nickel_kind` and `show`

Before we can navigate, we need to inspect what kind of value we have.

**Files:**
- Modify: `src/ffi.jl`
- Modify: `test/test_lazy.jl`

- [ ] **Step 1: Write failing tests**

Add to `test/test_lazy.jl`:

```julia
    @testset "nickel_kind" begin
        nickel_open("{ x = 1 }") do cfg
            @test nickel_kind(cfg) == :record
        end
        nickel_open("[1, 2, 3]") do cfg
            @test nickel_kind(cfg) == :array
        end
        nickel_open("42") do cfg
            @test nickel_kind(cfg) == :number
        end
        nickel_open("\"hello\"") do cfg
            @test nickel_kind(cfg) == :string
        end
        nickel_open("true") do cfg
            @test nickel_kind(cfg) == :bool
        end
        nickel_open("null") do cfg
            @test nickel_kind(cfg) == :null
        end
    end

    @testset "show" begin
        nickel_open("{ x = 1, y = 2, z = 3 }") do cfg
            s = repr(cfg)
            @test occursin("record", s)
            @test occursin("3", s)
        end
        nickel_open("[1, 2]") do cfg
            s = repr(cfg)
            @test occursin("array", s)
            @test occursin("2", s)
        end
    end
```

- [ ] **Step 2: Run tests to verify failure**

Run: `cd /Users/loulou/Dropbox/projects_claude/NickelEval && julia --project=. -e 'using Pkg; Pkg.test()'`

Expected: FAIL — `nickel_kind` not defined

- [ ] **Step 3: Implement `nickel_kind`**

Append to `src/ffi.jl`:

```julia
"""
    nickel_kind(v::NickelValue) -> Symbol

Return the kind of a lazy Nickel value without evaluating its children.

Returns one of: `:record`, `:array`, `:number`, `:string`, `:bool`, `:null`, `:enum`.
"""
function nickel_kind(v::NickelValue)
    _check_session_open(getfield(v, :session))
    expr = Ptr{L.nickel_expr}(getfield(v, :expr))
    if L.nickel_expr_is_null(expr) != 0
        return :null
    elseif L.nickel_expr_is_bool(expr) != 0
        return :bool
    elseif L.nickel_expr_is_number(expr) != 0
        return :number
    elseif L.nickel_expr_is_str(expr) != 0
        return :string
    elseif L.nickel_expr_is_array(expr) != 0
        return :array
    elseif L.nickel_expr_is_record(expr) != 0
        return :record
    elseif L.nickel_expr_is_enum_variant(expr) != 0 || L.nickel_expr_is_enum_tag(expr) != 0
        return :enum
    else
        error("Unknown Nickel expression type")
    end
end
```

Note: `getfield(v, :expr)` is used instead of `v.expr` because `getproperty` will be overridden later to navigate Nickel records. Same for `getfield(v, :session)`.

- [ ] **Step 4: Implement `show`**

Append to `src/ffi.jl`:

```julia
function Base.show(io::IO, v::NickelValue)
    session = getfield(v, :session)
    if session.closed
        print(io, "NickelValue(<closed>)")
        return
    end
    k = nickel_kind(v)
    expr = Ptr{L.nickel_expr}(getfield(v, :expr))
    if k == :record
        rec = L.nickel_expr_as_record(expr)
        n = Int(L.nickel_record_len(rec))
        print(io, "NickelValue(:record, $n field", n == 1 ? "" : "s", ")")
    elseif k == :array
        arr = L.nickel_expr_as_array(expr)
        n = Int(L.nickel_array_len(arr))
        print(io, "NickelValue(:array, $n element", n == 1 ? "" : "s", ")")
    else
        print(io, "NickelValue(:$k)")
    end
end
```

- [ ] **Step 5: Run tests — expect pass**

Run: `cd /Users/loulou/Dropbox/projects_claude/NickelEval && julia --project=. -e 'using Pkg; Pkg.test()'`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add src/ffi.jl test/test_lazy.jl
git commit -m "feat: add nickel_kind and show for NickelValue"
```

---

### Task 4: Implement record navigation (`getproperty` / `getindex`)

This is the core lazy behavior: `cfg.database.port` evaluates only the path you walk.

**Files:**
- Modify: `src/ffi.jl`
- Modify: `test/test_lazy.jl`

- [ ] **Step 1: Write failing tests**

Add to `test/test_lazy.jl`:

```julia
    @testset "Record field access" begin
        # getproperty (dot syntax)
        nickel_open("{ x = 42 }") do cfg
            @test cfg.x === Int64(42)
        end

        # getindex (bracket syntax)
        nickel_open("{ x = 42 }") do cfg
            @test cfg["x"] === Int64(42)
        end

        # Nested navigation
        nickel_open("{ a = { b = { c = 99 } } }") do cfg
            @test cfg.a.b.c === Int64(99)
        end

        # Mixed types in record
        nickel_open("{ name = \"test\", count = 42, flag = true }") do cfg
            @test cfg.name == "test"
            @test cfg.count === Int64(42)
            @test cfg.flag === true
        end

        # Null field
        nickel_open("{ x = null }") do cfg
            @test cfg.x === nothing
        end
    end
```

- [ ] **Step 2: Run tests to verify failure**

Run: `cd /Users/loulou/Dropbox/projects_claude/NickelEval && julia --project=. -e 'using Pkg; Pkg.test()'`

Expected: FAIL

- [ ] **Step 3: Implement `_resolve_value` helper**

This helper takes a shallow-evaluated expr and returns either a Julia primitive or a new `NickelValue`. It's used by `getproperty`, `getindex`, and `iterate`.

Append to `src/ffi.jl` (before `nickel_kind`):

```julia
# Given a shallow-eval'd expr, return a Julia value (primitive) or NickelValue (compound).
# The expr must already be tracked by the session.
function _resolve_value(session::NickelSession, expr::Ptr{L.nickel_expr})
    if L.nickel_expr_is_null(expr) != 0
        return nothing
    elseif L.nickel_expr_is_bool(expr) != 0
        return L.nickel_expr_as_bool(expr) != 0
    elseif L.nickel_expr_is_number(expr) != 0
        num = L.nickel_expr_as_number(expr)
        if L.nickel_number_is_i64(num) != 0
            return L.nickel_number_as_i64(num)
        else
            return Float64(L.nickel_number_as_f64(num))
        end
    elseif L.nickel_expr_is_str(expr) != 0
        out_ptr = Ref{Ptr{Cchar}}(C_NULL)
        len = L.nickel_expr_as_str(expr, out_ptr)
        return unsafe_string(out_ptr[], len)
    elseif L.nickel_expr_is_enum_tag(expr) != 0
        out_ptr = Ref{Ptr{Cchar}}(C_NULL)
        len = L.nickel_expr_as_enum_tag(expr, out_ptr)
        tag = Symbol(unsafe_string(out_ptr[], len))
        return NickelEnum(tag, nothing)
    else
        # record, array, or enum variant — stay lazy
        return NickelValue(session, Ptr{Cvoid}(expr))
    end
end
```

Key logic: primitives (null, bool, number, string, bare enum tag) are converted to Julia values immediately. Compound types (record, array, enum variant) are wrapped in a new `NickelValue` for lazy access.

- [ ] **Step 4: Implement `_eval_and_resolve` helper**

This combines "shallow-eval a sub-expression" and "resolve to Julia value or NickelValue":

```julia
# Evaluate a sub-expression shallowly, then resolve.
function _eval_and_resolve(session::NickelSession, sub_expr::Ptr{L.nickel_expr})
    ctx = Ptr{L.nickel_context}(session.ctx)
    out_expr = _tracked_expr_alloc(session)
    err = L.nickel_error_alloc()
    try
        result = L.nickel_context_eval_expr_shallow(ctx, sub_expr, out_expr, err)
        if result == L.NICKEL_RESULT_ERR
            _throw_nickel_error(err)
        end
        return _resolve_value(session, out_expr)
    catch
        rethrow()
    finally
        L.nickel_error_free(err)
    end
end
```

- [ ] **Step 5: Implement `getproperty` and string `getindex`**

```julia
function Base.getproperty(v::NickelValue, name::Symbol)
    return _lazy_field_access(v, String(name))
end

function Base.getindex(v::NickelValue, key::String)
    return _lazy_field_access(v, key)
end

function _lazy_field_access(v::NickelValue, key::String)
    session = getfield(v, :session)
    _check_session_open(session)
    expr = Ptr{L.nickel_expr}(getfield(v, :expr))
    if L.nickel_expr_is_record(expr) == 0
        throw(ArgumentError("Cannot access field '$key': NickelValue is not a record"))
    end
    rec = L.nickel_expr_as_record(expr)
    out_expr = _tracked_expr_alloc(session)
    has_value = L.nickel_record_value_by_name(rec, key, out_expr)
    if has_value == 0
        # Field not found or has no value (contract-only field in shallow eval).
        # Check whether the key exists at all by scanning keys.
        n = Int(L.nickel_record_len(rec))
        found = false
        key_ptr = Ref{Ptr{Cchar}}(C_NULL)
        key_len = Ref{Csize_t}(0)
        for i in 0:(n-1)
            L.nickel_record_key_value_by_index(rec, Csize_t(i), key_ptr, key_len,
                                               Ptr{L.nickel_expr}(C_NULL))
            if unsafe_string(key_ptr[], key_len[]) == key
                found = true
                break
            end
        end
        if !found
            throw(NickelError("Field '$key' not found in record"))
        end
        # Key exists but has no value — this can happen with contract-only fields
        # in shallow eval. Return nothing as the value is not available.
        throw(NickelError("Field '$key' has no value (contract-only or unevaluated)"))
    end
    return _eval_and_resolve(session, out_expr)
end
```

Note: `nickel_record_value_by_name` looks up the field by name directly — O(1) for hash-based records. Much faster than iterating all fields with `nickel_record_key_value_by_index`.

- [ ] **Step 6: Run tests — expect pass**

Run: `cd /Users/loulou/Dropbox/projects_claude/NickelEval && julia --project=. -e 'using Pkg; Pkg.test()'`

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add src/ffi.jl test/test_lazy.jl
git commit -m "feat: add lazy record navigation via getproperty/getindex"
```

---

### Task 5: Implement array indexing

**Files:**
- Modify: `src/ffi.jl`
- Modify: `test/test_lazy.jl`

- [ ] **Step 1: Write failing tests**

Add to `test/test_lazy.jl`:

```julia
    @testset "Array access" begin
        nickel_open("[10, 20, 30]") do cfg
            @test cfg[1] === Int64(10)
            @test cfg[2] === Int64(20)
            @test cfg[3] === Int64(30)
        end

        # Array of records (lazy)
        nickel_open("[{ x = 1 }, { x = 2 }]") do cfg
            @test cfg[1].x === Int64(1)
            @test cfg[2].x === Int64(2)
        end

        # Nested: record containing array
        nickel_open("{ items = [10, 20, 30] }") do cfg
            @test cfg.items[2] === Int64(20)
        end
    end
```

- [ ] **Step 2: Run tests to verify failure**

Expected: FAIL — integer `getindex` not defined for `NickelValue`

- [ ] **Step 3: Implement integer `getindex`**

Append to `src/ffi.jl`:

```julia
function Base.getindex(v::NickelValue, idx::Integer)
    session = getfield(v, :session)
    _check_session_open(session)
    expr = Ptr{L.nickel_expr}(getfield(v, :expr))
    if L.nickel_expr_is_array(expr) == 0
        throw(ArgumentError("Cannot index with integer: NickelValue is not an array"))
    end
    arr = L.nickel_expr_as_array(expr)
    n = Int(L.nickel_array_len(arr))
    if idx < 1 || idx > n
        throw(BoundsError(v, idx))
    end
    out_expr = _tracked_expr_alloc(session)
    L.nickel_array_get(arr, Csize_t(idx - 1), out_expr)  # 0-based C API
    return _eval_and_resolve(session, out_expr)
end
```

Note: Julia uses 1-based indexing, C API uses 0-based. We subtract 1.

- [ ] **Step 4: Run tests — expect pass**

Run: `cd /Users/loulou/Dropbox/projects_claude/NickelEval && julia --project=. -e 'using Pkg; Pkg.test()'`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/ffi.jl test/test_lazy.jl
git commit -m "feat: add lazy array indexing"
```

---

### Task 6: Implement `collect` (materialization)

Convert a lazy `NickelValue` subtree into plain Julia types, matching `nickel_eval` output.

**Files:**
- Modify: `src/ffi.jl`
- Modify: `test/test_lazy.jl`

- [ ] **Step 1: Write failing tests**

Add to `test/test_lazy.jl`:

```julia
    @testset "collect" begin
        # Record
        nickel_open("{ a = 1, b = \"two\", c = true }") do cfg
            result = collect(cfg)
            @test result isa Dict{String, Any}
            @test result == nickel_eval("{ a = 1, b = \"two\", c = true }")
        end

        # Nested record
        nickel_open("{ x = { y = 42 } }") do cfg
            result = collect(cfg)
            @test result["x"]["y"] === Int64(42)
        end

        # Array
        nickel_open("[1, 2, 3]") do cfg
            result = collect(cfg)
            @test result == Any[1, 2, 3]
        end

        # Collect a sub-tree
        nickel_open("{ a = 1, b = { c = 2, d = 3 } }") do cfg
            sub = collect(cfg.b)
            @test sub == Dict{String, Any}("c" => 2, "d" => 3)
        end

        # Primitive passthrough
        nickel_open("42") do cfg
            @test collect(cfg) === Int64(42)
        end
    end
```

- [ ] **Step 2: Run tests to verify failure**

Expected: FAIL — no `collect` method for `NickelValue`

- [ ] **Step 3: Implement `collect`**

Append to `src/ffi.jl`:

```julia
"""
    collect(v::NickelValue) -> Any

Recursively evaluate and materialize the entire subtree rooted at `v`.
Returns the same types as `nickel_eval`: Dict, Vector, Int64, Float64, etc.
"""
function Base.collect(v::NickelValue)
    session = getfield(v, :session)
    _check_session_open(session)
    expr = Ptr{L.nickel_expr}(getfield(v, :expr))
    return _collect_expr(session, expr)
end

# Recursive collect: shallow-eval each sub-expression, then convert.
function _collect_expr(session::NickelSession, expr::Ptr{L.nickel_expr})
    ctx = Ptr{L.nickel_context}(session.ctx)

    if L.nickel_expr_is_null(expr) != 0
        return nothing
    elseif L.nickel_expr_is_bool(expr) != 0
        return L.nickel_expr_as_bool(expr) != 0
    elseif L.nickel_expr_is_number(expr) != 0
        num = L.nickel_expr_as_number(expr)
        if L.nickel_number_is_i64(num) != 0
            return L.nickel_number_as_i64(num)
        else
            return Float64(L.nickel_number_as_f64(num))
        end
    elseif L.nickel_expr_is_str(expr) != 0
        out_ptr = Ref{Ptr{Cchar}}(C_NULL)
        len = L.nickel_expr_as_str(expr, out_ptr)
        return unsafe_string(out_ptr[], len)
    elseif L.nickel_expr_is_array(expr) != 0
        arr = L.nickel_expr_as_array(expr)
        n = Int(L.nickel_array_len(arr))
        result = Vector{Any}(undef, n)
        for i in 0:(n-1)
            elem = _tracked_expr_alloc(session)
            L.nickel_array_get(arr, Csize_t(i), elem)
            # Shallow-eval the element before collecting
            evaled = _tracked_expr_alloc(session)
            err = L.nickel_error_alloc()
            try
                r = L.nickel_context_eval_expr_shallow(ctx, elem, evaled, err)
                if r == L.NICKEL_RESULT_ERR
                    _throw_nickel_error(err)
                end
            finally
                L.nickel_error_free(err)
            end
            result[i+1] = _collect_expr(session, evaled)
        end
        return result
    elseif L.nickel_expr_is_record(expr) != 0
        rec = L.nickel_expr_as_record(expr)
        n = Int(L.nickel_record_len(rec))
        result = Dict{String, Any}()
        key_ptr = Ref{Ptr{Cchar}}(C_NULL)
        key_len = Ref{Csize_t}(0)
        for i in 0:(n-1)
            val_expr = _tracked_expr_alloc(session)
            L.nickel_record_key_value_by_index(rec, Csize_t(i), key_ptr, key_len, val_expr)
            key = unsafe_string(key_ptr[], key_len[])
            # Shallow-eval the value before collecting
            evaled = _tracked_expr_alloc(session)
            err = L.nickel_error_alloc()
            try
                r = L.nickel_context_eval_expr_shallow(ctx, val_expr, evaled, err)
                if r == L.NICKEL_RESULT_ERR
                    _throw_nickel_error(err)
                end
            finally
                L.nickel_error_free(err)
            end
            result[key] = _collect_expr(session, evaled)
        end
        return result
    elseif L.nickel_expr_is_enum_variant(expr) != 0
        out_ptr = Ref{Ptr{Cchar}}(C_NULL)
        arg_expr = _tracked_expr_alloc(session)
        len = L.nickel_expr_as_enum_variant(expr, out_ptr, arg_expr)
        tag = Symbol(unsafe_string(out_ptr[], len))
        # Shallow-eval the arg before collecting
        evaled = _tracked_expr_alloc(session)
        err = L.nickel_error_alloc()
        try
            r = L.nickel_context_eval_expr_shallow(ctx, arg_expr, evaled, err)
            if r == L.NICKEL_RESULT_ERR
                _throw_nickel_error(err)
            end
        finally
            L.nickel_error_free(err)
        end
        return NickelEnum(tag, _collect_expr(session, evaled))
    elseif L.nickel_expr_is_enum_tag(expr) != 0
        out_ptr = Ref{Ptr{Cchar}}(C_NULL)
        len = L.nickel_expr_as_enum_tag(expr, out_ptr)
        return NickelEnum(Symbol(unsafe_string(out_ptr[], len)), nothing)
    else
        error("Unknown Nickel expression type")
    end
end
```

Key logic: Unlike `_walk_expr` (which assumes everything is already deeply evaluated), `_collect_expr` calls `nickel_context_eval_expr_shallow` on each sub-expression before inspecting its type. This forces lazy thunks to evaluate one level at a time, recursing until the entire tree is materialized.

- [ ] **Step 4: Run tests — expect pass**

Run: `cd /Users/loulou/Dropbox/projects_claude/NickelEval && julia --project=. -e 'using Pkg; Pkg.test()'`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/ffi.jl test/test_lazy.jl
git commit -m "feat: add collect for NickelValue materialization"
```

---

### Task 7: Implement `keys` and `length`

**Files:**
- Modify: `src/ffi.jl`
- Modify: `test/test_lazy.jl`

- [ ] **Step 1: Write failing tests**

Add to `test/test_lazy.jl`:

```julia
    @testset "keys and length" begin
        nickel_open("{ a = 1, b = 2, c = 3 }") do cfg
            k = keys(cfg)
            @test k isa Vector{String}
            @test sort(k) == ["a", "b", "c"]
            @test length(cfg) == 3
        end

        nickel_open("[10, 20, 30, 40]") do cfg
            @test length(cfg) == 4
        end

        # keys on non-record throws
        nickel_open("[1, 2]") do cfg
            @test_throws ArgumentError keys(cfg)
        end
    end
```

- [ ] **Step 2: Run tests to verify failure**

Expected: FAIL

- [ ] **Step 3: Implement `keys` and `length`**

Append to `src/ffi.jl`:

```julia
function Base.keys(v::NickelValue)
    session = getfield(v, :session)
    _check_session_open(session)
    expr = Ptr{L.nickel_expr}(getfield(v, :expr))
    if L.nickel_expr_is_record(expr) == 0
        throw(ArgumentError("Cannot get keys: NickelValue is not a record"))
    end
    rec = L.nickel_expr_as_record(expr)
    n = Int(L.nickel_record_len(rec))
    result = Vector{String}(undef, n)
    key_ptr = Ref{Ptr{Cchar}}(C_NULL)
    key_len = Ref{Csize_t}(0)
    for i in 0:(n-1)
        # Pass C_NULL for out_expr to skip value extraction
        L.nickel_record_key_value_by_index(rec, Csize_t(i), key_ptr, key_len,
                                           Ptr{L.nickel_expr}(C_NULL))
        result[i+1] = unsafe_string(key_ptr[], key_len[])
    end
    return result
end

function Base.length(v::NickelValue)
    session = getfield(v, :session)
    _check_session_open(session)
    expr = Ptr{L.nickel_expr}(getfield(v, :expr))
    if L.nickel_expr_is_record(expr) != 0
        return Int(L.nickel_record_len(L.nickel_expr_as_record(expr)))
    elseif L.nickel_expr_is_array(expr) != 0
        return Int(L.nickel_array_len(L.nickel_expr_as_array(expr)))
    else
        throw(ArgumentError("Cannot get length: NickelValue is not a record or array"))
    end
end
```

Note: `keys` passes `C_NULL` as the out-expression to `nickel_record_key_value_by_index`. The C API explicitly supports this — it skips writing the value, giving us just the field names without evaluating anything.

- [ ] **Step 4: Run tests — expect pass**

Run: `cd /Users/loulou/Dropbox/projects_claude/NickelEval && julia --project=. -e 'using Pkg; Pkg.test()'`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/ffi.jl test/test_lazy.jl
git commit -m "feat: add keys and length for NickelValue"
```

---

### Task 8: Implement file path support for `nickel_open`

**Files:**
- Modify: `src/ffi.jl`
- Modify: `test/test_lazy.jl`

- [ ] **Step 1: Write failing tests**

Add to `test/test_lazy.jl`:

```julia
    @testset "File evaluation" begin
        mktempdir() do dir
            # Simple file
            f = joinpath(dir, "config.ncl")
            write(f, "{ host = \"localhost\", port = 8080 }")
            nickel_open(f) do cfg
                @test cfg.host == "localhost"
                @test cfg.port === Int64(8080)
            end

            # File with imports
            shared = joinpath(dir, "shared.ncl")
            write(shared, "{ version = \"1.0\" }")
            main = joinpath(dir, "main.ncl")
            write(main, """
let s = import "shared.ncl" in
{ app_version = s.version, name = "myapp" }
""")
            nickel_open(main) do cfg
                @test cfg.app_version == "1.0"
                @test cfg.name == "myapp"
            end
        end
    end
```

- [ ] **Step 2: Run tests to verify failure**

Expected: FAIL — `nickel_open` doesn't detect file paths

- [ ] **Step 3: Implement file path variant**

Add a `nickel_open` method that detects file paths. Insert above the existing `nickel_open(code::String)` in `src/ffi.jl`:

```julia
function nickel_open(f::Function, path_or_code::String)
    val = nickel_open(path_or_code)
    try
        return f(val)
    finally
        close(val)
    end
end

function nickel_open(path_or_code::String)
    _check_ffi_available()
    # Detect file path: ends with .ncl AND exists on disk
    if endswith(path_or_code, ".ncl") && isfile(abspath(path_or_code))
        return _nickel_open_file(path_or_code)
    end
    return _nickel_open_code(path_or_code)
end

function _nickel_open_file(path::String)
    abs_path = abspath(path)
    if !isfile(abs_path)
        throw(NickelError("File not found: $abs_path"))
    end
    code = read(abs_path, String)
    ctx = L.nickel_context_alloc()
    session = NickelSession(Ptr{Cvoid}(ctx), Ptr{Cvoid}[], false)
    finalizer(close, session)
    expr = _tracked_expr_alloc(session)
    err = L.nickel_error_alloc()
    try
        GC.@preserve abs_path begin
            L.nickel_context_set_source_name(ctx, Base.unsafe_convert(Ptr{Cchar}, abs_path))
        end
        result = L.nickel_context_eval_shallow(ctx, code, expr, err)
        if result == L.NICKEL_RESULT_ERR
            _throw_nickel_error(err)
        end
        return NickelValue(session, Ptr{Cvoid}(expr))
    catch
        close(session)
        rethrow()
    finally
        L.nickel_error_free(err)
    end
end

function _nickel_open_code(code::String)
    ctx = L.nickel_context_alloc()
    session = NickelSession(Ptr{Cvoid}(ctx), Ptr{Cvoid}[], false)
    finalizer(close, session)
    expr = _tracked_expr_alloc(session)
    err = L.nickel_error_alloc()
    try
        result = L.nickel_context_eval_shallow(ctx, code, expr, err)
        if result == L.NICKEL_RESULT_ERR
            _throw_nickel_error(err)
        end
        return NickelValue(session, Ptr{Cvoid}(expr))
    catch
        close(session)
        rethrow()
    finally
        L.nickel_error_free(err)
    end
end
```

This replaces the original `nickel_open(code::String)` and `nickel_open(f::Function, code::String)`. The routing logic is simple: if the string ends in `.ncl`, treat as file path (mirrors `nickel_eval_file` pattern with source name for import resolution). Otherwise treat as inline code.

- [ ] **Step 4: Run tests — expect pass**

Run: `cd /Users/loulou/Dropbox/projects_claude/NickelEval && julia --project=. -e 'using Pkg; Pkg.test()'`

Expected: PASS (all tests including earlier ones)

- [ ] **Step 5: Commit**

```bash
git add src/ffi.jl test/test_lazy.jl
git commit -m "feat: add file path support to nickel_open"
```

---

### Task 9: Implement `iterate` protocol

**Files:**
- Modify: `src/ffi.jl`
- Modify: `test/test_lazy.jl`

- [ ] **Step 1: Write failing tests**

Add to `test/test_lazy.jl`:

```julia
    @testset "Iteration" begin
        # Record iteration yields pairs
        nickel_open("{ a = 1, b = 2 }") do cfg
            pairs = Dict(k => v for (k, v) in cfg)
            @test pairs["a"] === Int64(1)
            @test pairs["b"] === Int64(2)
        end

        # Array iteration
        nickel_open("[10, 20, 30]") do cfg
            values = [x for x in cfg]
            @test values == Any[10, 20, 30]
        end
    end
```

- [ ] **Step 2: Run tests to verify failure**

Expected: FAIL

- [ ] **Step 3: Implement `iterate`**

Append to `src/ffi.jl`:

```julia
function Base.iterate(v::NickelValue, state=1)
    session = getfield(v, :session)
    _check_session_open(session)
    expr = Ptr{L.nickel_expr}(getfield(v, :expr))

    if L.nickel_expr_is_record(expr) != 0
        rec = L.nickel_expr_as_record(expr)
        n = Int(L.nickel_record_len(rec))
        state > n && return nothing
        key_ptr = Ref{Ptr{Cchar}}(C_NULL)
        key_len = Ref{Csize_t}(0)
        val_expr = _tracked_expr_alloc(session)
        L.nickel_record_key_value_by_index(rec, Csize_t(state - 1), key_ptr, key_len, val_expr)
        key = unsafe_string(key_ptr[], key_len[])
        val = _eval_and_resolve(session, val_expr)
        return (key => val, state + 1)
    elseif L.nickel_expr_is_array(expr) != 0
        arr = L.nickel_expr_as_array(expr)
        n = Int(L.nickel_array_len(arr))
        state > n && return nothing
        elem = _tracked_expr_alloc(session)
        L.nickel_array_get(arr, Csize_t(state - 1), elem)
        val = _eval_and_resolve(session, elem)
        return (val, state + 1)
    else
        throw(ArgumentError("Cannot iterate: NickelValue is not a record or array"))
    end
end
```

Records yield `Pair{String, Any}`, arrays yield elements. Both use 1-based state internally, converting to 0-based for the C API.

- [ ] **Step 4: Run tests — expect pass**

Run: `cd /Users/loulou/Dropbox/projects_claude/NickelEval && julia --project=. -e 'using Pkg; Pkg.test()'`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/ffi.jl test/test_lazy.jl
git commit -m "feat: add iterate protocol for NickelValue"
```

---

### Task 10: Error handling and edge cases

**Files:**
- Modify: `test/test_lazy.jl`

- [ ] **Step 1: Write error handling tests**

Add to `test/test_lazy.jl`:

```julia
    @testset "Error handling" begin
        # Closed session
        local stale_ref
        nickel_open("{ x = 1 }") do cfg
            stale_ref = cfg
        end
        @test_throws ArgumentError stale_ref.x

        # Missing field
        nickel_open("{ x = 1 }") do cfg
            @test_throws Union{NickelError, ArgumentError} cfg.nonexistent
        end

        # Wrong access type: dot on array
        nickel_open("[1, 2, 3]") do cfg
            @test_throws ArgumentError cfg.x
        end

        # Wrong access type: integer index on record
        nickel_open("{ x = 1 }") do cfg
            @test_throws ArgumentError cfg[1]
        end

        # Out of bounds
        nickel_open("[1, 2]") do cfg
            @test_throws BoundsError cfg[3]
        end

        # Syntax error in code
        @test_throws NickelError nickel_open("{ x = }")
    end
```

- [ ] **Step 2: Run tests — expect pass**

Run: `cd /Users/loulou/Dropbox/projects_claude/NickelEval && julia --project=. -e 'using Pkg; Pkg.test()'`

Expected: PASS — all error paths should already work from the implementations above. If any fail, fix and re-run.

- [ ] **Step 3: Commit**

```bash
git add test/test_lazy.jl
git commit -m "test: add error handling tests for lazy evaluation"
```

---

### Task 11: Enum handling

**Files:**
- Modify: `test/test_lazy.jl`

- [ ] **Step 1: Write enum tests**

Add to `test/test_lazy.jl`:

```julia
    @testset "Enum handling" begin
        # Bare enum tag returns NickelEnum immediately
        nickel_open("let x = 'Foo in x") do cfg
            @test cfg isa NickelEnum
            @test cfg.tag == :Foo
        end

        # Enum variant with primitive arg
        nickel_open("let x = 'Some 42 in x") do cfg
            @test cfg isa NickelEnum
            @test cfg.tag == :Some
            @test cfg.arg === Int64(42)
        end

        # Enum variant with record arg stays lazy
        nickel_open("{ status = 'Ok { value = 123 } }") do cfg
            status = cfg.status
            @test status isa NickelValue  # enum variant is compound, stays lazy
            result = collect(status)
            @test result isa NickelEnum
            @test result.tag == :Ok
            @test result.arg["value"] === Int64(123)
        end

        # Enum in collect
        nickel_open("{ x = 'None, y = 'Some 42 }") do cfg
            result = collect(cfg)
            @test result["x"] isa NickelEnum
            @test result["x"].tag == :None
            @test result["y"] isa NickelEnum
            @test result["y"].tag == :Some
        end
    end
```

- [ ] **Step 2: Run tests**

Run: `cd /Users/loulou/Dropbox/projects_claude/NickelEval && julia --project=. -e 'using Pkg; Pkg.test()'`

Expected: PASS — or reveals edge cases in `_resolve_value`/`_collect_expr` that need fixing. Fix and re-run if needed.

- [ ] **Step 3: Commit**

```bash
git add test/test_lazy.jl
git commit -m "test: add enum handling tests for lazy evaluation"
```

---

### Task 12: Manual session usage

**Files:**
- Modify: `test/test_lazy.jl`

- [ ] **Step 1: Write manual session tests**

Add to `test/test_lazy.jl`:

```julia
    @testset "Manual session" begin
        cfg = nickel_open("{ x = 42, y = \"hello\" }")
        @test cfg.x === Int64(42)
        @test cfg.y == "hello"
        close(cfg)

        # Double close is safe
        close(cfg)

        # Access after close throws
        @test_throws ArgumentError cfg.x
    end
```

- [ ] **Step 2: Run tests — expect pass**

Run: `cd /Users/loulou/Dropbox/projects_claude/NickelEval && julia --project=. -e 'using Pkg; Pkg.test()'`

Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add test/test_lazy.jl
git commit -m "test: add manual session tests for lazy evaluation"
```

---

### Task 13: Update documentation

**Files:**
- Modify: `docs/src/lib/public.md`

- [ ] **Step 1: Add new exports to docs**

Add a new section to `docs/src/lib/public.md`:

```markdown
## Lazy Evaluation

```@docs
nickel_open
NickelValue
NickelSession
nickel_kind
```
```

- [ ] **Step 2: Run full test suite one final time**

Run: `cd /Users/loulou/Dropbox/projects_claude/NickelEval && julia --project=. -e 'using Pkg; Pkg.test()'`

Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add docs/src/lib/public.md
git commit -m "docs: add lazy evaluation API to public docs"
```

---

### Task 14: Update spec with design deviation

**Files:**
- Modify: `docs/superpowers/specs/2026-03-21-lazy-evaluation-design.md`

- [ ] **Step 1: Add deviation note to spec**

Add to the top of the spec, after the Problem section:

```markdown
## Design Deviations

- `NickelSession` has no `root` field (avoids circular type reference). `nickel_open` returns `NickelValue` directly. `close(::NickelValue)` delegates to `close(session)`.
- Types use `Ptr{Cvoid}` instead of `Ptr{LibNickel.nickel_expr}` to avoid forward reference to `LibNickel` module.
- Bare enum tags and enum variants with primitive args are resolved immediately by `_resolve_value` (not wrapped in `NickelValue`). Only enum variants with compound args stay lazy.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-03-21-lazy-evaluation-design.md
git commit -m "docs: note design deviations in spec"
```
