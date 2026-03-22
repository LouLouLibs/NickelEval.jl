# Lazy Evaluation API for NickelEval.jl

## Problem

`nickel_eval` and `nickel_eval_file` evaluate the entire Nickel expression tree eagerly. For large configuration files, this wastes time evaluating fields the caller never reads. The Nickel C API already supports shallow evaluation (`nickel_context_eval_shallow`) and on-demand sub-expression evaluation (`nickel_context_eval_expr_shallow`). NickelEval.jl wraps both functions in `libnickel.jl` but exposes neither to users.

## Solution

Add a `nickel_open` function that evaluates shallowly and returns a lazy `NickelValue` wrapper. Users navigate the result with `.field` and `["field"]` syntax. Each access evaluates only the requested sub-expression. A `collect` call materializes an entire subtree into plain Julia types.

## Types

### `NickelSession`

Owns the `nickel_context` and tracks all allocated expressions for cleanup.

```julia
mutable struct NickelSession
    ctx::Ptr{LibNickel.nickel_context}
    root::NickelValue                          # top-level lazy value
    exprs::Vector{Ptr{LibNickel.nickel_expr}}  # all allocations, freed on close
    closed::Bool
end
```

- `close(session)` frees every tracked expression, then the context.
- A `closed` flag prevents use-after-free.
- A GC finalizer calls `close` as a safety net, but users should not rely on GC timing.
- `root` holds the top-level `NickelValue` for manual (non-do-block) use.

### `NickelValue`

Wraps a single Nickel expression with a back-reference to its session.

```julia
struct NickelValue
    session::NickelSession
    expr::Ptr{LibNickel.nickel_expr}
end
```

- Does not own `expr` — the session tracks and frees it.
- The back-reference keeps the session reachable by the GC as long as any `NickelValue` exists.

**Important:** Because `getproperty` is overridden on `NickelValue`, all internal access to struct fields must use `getfield(v, :session)` and `getfield(v, :expr)`.

## Public API

### `nickel_open`

```julia
# Do-block (preferred) — receives the root NickelValue
nickel_open("config.ncl") do cfg::NickelValue
    cfg.database.port  # => 5432
end

# Code string
nickel_open(code="{ a = 1 }") do cfg
    cfg.a  # => 1
end

# Manual (REPL exploration) — returns the NickelSession
session = nickel_open("config.ncl")
port = session.root.database.port
close(session)
```

Internally:
1. Allocates a `nickel_context`.
2. For file paths: reads the file, sets the source name via `nickel_context_set_source_name`, then calls `nickel_context_eval_shallow` on the code string.
3. For code strings: calls `nickel_context_eval_shallow` directly.
4. Wraps the root expression in a `NickelValue`.
5. Do-block variant: passes the root `NickelValue` to the block, calls `close(session)` in a `finally` clause. Returns the block's result.
6. Manual variant: returns the `NickelSession` (which holds `.root`).

### Navigation

```julia
Base.getproperty(v::NickelValue, name::Symbol)  # v.field
Base.getindex(v::NickelValue, key::String)       # v["field"]
Base.getindex(v::NickelValue, idx::Integer)      # v[1]
```

Each access:
1. Checks the session is open.
2. Extracts the sub-expression: uses `nickel_record_value_by_name` for field access (both `getproperty` and string `getindex`), or `nickel_array_get` for integer indexing.
3. Allocates a new `nickel_expr` via `nickel_expr_alloc`, registers it in the session's `exprs` vector.
4. Calls `nickel_context_eval_expr_shallow` to evaluate the sub-expression to WHNF.
5. If the result is a primitive (number, string, bool, null, or bare enum tag), returns the Julia value directly.
6. If the result is a record, array, or enum variant, returns a new `NickelValue`.

### Materialization

```julia
Base.collect(v::NickelValue) -> Any
```

Recursively evaluates the entire subtree rooted at `v` and converts it to plain Julia types (`Dict`, `Vector`, `Int64`, etc.) — the same types that `nickel_eval` returns today. Uses a modified `_walk_expr` that calls `nickel_context_eval_expr_shallow` on each sub-expression before inspecting its type. The C API has no `eval_expr_deep`, so `collect` must walk and shallow-eval recursively.

### Inspection

```julia
Base.keys(v::NickelValue)       # field names of a record, without evaluating values
Base.length(v::NickelValue)     # field count (record) or element count (array)
nickel_kind(v::NickelValue)     # :record, :array, :number, :string, :bool, :null, :enum
```

`keys` returns a `Vector{String}`. It iterates `nickel_record_key_value_by_index` with a `C_NULL` out-expression (the C API explicitly supports NULL here to skip value extraction).

### Iteration

```julia
# Records: iterate key-value pairs (values are lazy NickelValues or primitives)
for (key, val) in cfg
    println(key, " => ", val)
end

# Arrays: iterate elements
for item in cfg.items
    println(item)
end
```

Implements Julia's `iterate` protocol. Record iteration yields `Pair{String, Any}` (where values follow the same lazy-or-primitive rule as navigation). Array iteration yields elements.

### `show`

```julia
Base.show(io::IO, v::NickelValue)
# NickelValue(:record, 3 fields)
# NickelValue(:array, 10 elements)
# NickelValue(:number)
```

Displays the kind and size without evaluating children.

## Exports

```julia
export nickel_open, NickelValue, NickelSession, nickel_kind
```

New exports must be added to `docs/src/lib/public.md` for the documentation build.

## File Organization

All new code goes in `src/ffi.jl`, below the existing public API section. No new files (except test file).

## Lifetime Rules

1. **Do-block**: session opens before the block, closes in `finally`. All `NickelValue` references become invalid after the block. Accessing a closed session throws an error.
2. **Manual**: caller must call `close(session)`. The `NickelSession` finalizer also calls `close` as a safety net, but users should not rely on GC timing.
3. **Nesting**: `NickelValue` objects returned from navigation hold a reference to the session. They do not extend the session's lifetime beyond the do-block — the do-block closes the session regardless.

## Thread Safety

`NickelSession` and `NickelValue` are not thread-safe. The underlying `nickel_context` holds mutable Rust state. All access to a session must occur on a single thread.

## Error Handling

- Accessing a field that does not exist: throws `NickelError` with a message from the C API.
- Accessing a closed session: throws `ArgumentError("NickelSession is closed")`.
- Evaluating a sub-expression that fails (e.g., contract violation): throws `NickelError`.
- Using `.field` on an array or `[index]` on a record of the wrong kind: throws `ArgumentError`.

## Testing

Tests go in `test/test_lazy.jl`, included from `test/runtests.jl` alongside `test_eval.jl`.

Test cases:
1. **Shallow record access**: open a record, access one field, verify correct value returned.
2. **Nested navigation**: `cfg.a.b.c` returns the correct primitive.
3. **Array access**: `cfg.items[1]` works.
4. **`collect`**: materializes the full subtree, matches `nickel_eval` output.
5. **`keys` and `length`**: return correct values without evaluating children.
6. **File evaluation**: `nickel_open("file.ncl")` works with imports.
7. **Do-block cleanup**: after the block, accessing a value throws.
8. **Error on missing field**: throws `NickelError`.
9. **Enum handling**: enum tags return immediately, enum variants with record payloads return lazy `NickelValue`.
10. **`nickel_kind`**: returns correct symbol for each Nickel type.
11. **Iteration**: `for (k, v) in record` and `for item in array` work correctly.
12. **Manual session**: `nickel_open` without do-block returns a session, `session.root` navigates, `close` cleans up.
