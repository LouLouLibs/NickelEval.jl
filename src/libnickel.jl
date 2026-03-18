# Julia bindings for the Nickel C API (nickel-lang 2.0.0 / capi feature)
#
# Generated from deps/nickel_lang.h by Clang.jl (deps/generate_bindings.jl),
# with manual docstrings and minor type corrections applied.
#
# All functions reference `libnickel_lang` as the library symbol.
# The actual library path must be assigned to `libnickel_lang` before use.

module LibNickel

# ── Enums ────────────────────────────────────────────────────────────────────

"""
    nickel_result

Return value for fallible C API functions.

- `NICKEL_RESULT_OK  = 0` — success
- `NICKEL_RESULT_ERR = 1` — failure
"""
@enum nickel_result::UInt32 begin
    NICKEL_RESULT_OK  = 0
    NICKEL_RESULT_ERR = 1
end

"""
    nickel_error_format

Format selector for error diagnostics.

- `NICKEL_ERROR_FORMAT_TEXT      = 0` — plain text
- `NICKEL_ERROR_FORMAT_ANSI_TEXT = 1` — text with ANSI color codes
- `NICKEL_ERROR_FORMAT_JSON      = 2` — JSON
- `NICKEL_ERROR_FORMAT_YAML      = 3` — YAML
- `NICKEL_ERROR_FORMAT_TOML      = 4` — TOML
"""
@enum nickel_error_format::UInt32 begin
    NICKEL_ERROR_FORMAT_TEXT      = 0
    NICKEL_ERROR_FORMAT_ANSI_TEXT = 1
    NICKEL_ERROR_FORMAT_JSON      = 2
    NICKEL_ERROR_FORMAT_YAML      = 3
    NICKEL_ERROR_FORMAT_TOML      = 4
end

# ── Opaque types ─────────────────────────────────────────────────────────────
# Opaque structs from C; only used via `Ptr{T}`.

mutable struct nickel_array end
mutable struct nickel_context end
mutable struct nickel_error end
mutable struct nickel_expr end
mutable struct nickel_number end
mutable struct nickel_record end
mutable struct nickel_string end

# ── Callback types ───────────────────────────────────────────────────────────
# typedef uintptr_t (*nickel_write_callback)(void *context, const uint8_t *buf, uintptr_t len);
# typedef void (*nickel_flush_callback)(const void *context);

const nickel_write_callback = Ptr{Cvoid}
const nickel_flush_callback = Ptr{Cvoid}

# ── Context lifecycle ────────────────────────────────────────────────────────

"""
    nickel_context_alloc() -> Ptr{nickel_context}

Allocate a new context for evaluating Nickel expressions.
Must be freed with [`nickel_context_free`](@ref).
"""
function nickel_context_alloc()
    @ccall libnickel_lang.nickel_context_alloc()::Ptr{nickel_context}
end

"""
    nickel_context_free(ctx)

Free a context allocated with [`nickel_context_alloc`](@ref).
"""
function nickel_context_free(ctx)
    @ccall libnickel_lang.nickel_context_free(ctx::Ptr{nickel_context})::Cvoid
end

# ── Context configuration ───────────────────────────────────────────────────

"""
    nickel_context_set_trace_callback(ctx, write, flush, user_data)

Provide a callback for `std.trace` output during evaluation.
"""
function nickel_context_set_trace_callback(ctx, write, flush, user_data)
    @ccall libnickel_lang.nickel_context_set_trace_callback(ctx::Ptr{nickel_context}, write::nickel_write_callback, flush::nickel_flush_callback, user_data::Ptr{Cvoid})::Cvoid
end

"""
    nickel_context_set_source_name(ctx, name)

Set a name for the main input program (used in error messages).
`name` must be a null-terminated UTF-8 C string; it is only borrowed temporarily.
"""
function nickel_context_set_source_name(ctx, name)
    @ccall libnickel_lang.nickel_context_set_source_name(ctx::Ptr{nickel_context}, name::Ptr{Cchar})::Cvoid
end

# ── Evaluation ───────────────────────────────────────────────────────────────

"""
    nickel_context_eval_deep(ctx, src, out_expr, out_error) -> nickel_result

Evaluate Nickel source deeply (recursively evaluating records and arrays).

- `src`: null-terminated UTF-8 Nickel source code
- `out_expr`: allocated with `nickel_expr_alloc`, or `C_NULL`
- `out_error`: allocated with `nickel_error_alloc`, or `C_NULL`

Returns `NICKEL_RESULT_OK` on success, `NICKEL_RESULT_ERR` on failure.
"""
function nickel_context_eval_deep(ctx, src, out_expr, out_error)
    @ccall libnickel_lang.nickel_context_eval_deep(ctx::Ptr{nickel_context}, src::Ptr{Cchar}, out_expr::Ptr{nickel_expr}, out_error::Ptr{nickel_error})::nickel_result
end

"""
    nickel_context_eval_deep_for_export(ctx, src, out_expr, out_error) -> nickel_result

Like [`nickel_context_eval_deep`](@ref), but ignores fields marked `not_exported`.
"""
function nickel_context_eval_deep_for_export(ctx, src, out_expr, out_error)
    @ccall libnickel_lang.nickel_context_eval_deep_for_export(ctx::Ptr{nickel_context}, src::Ptr{Cchar}, out_expr::Ptr{nickel_expr}, out_error::Ptr{nickel_error})::nickel_result
end

"""
    nickel_context_eval_shallow(ctx, src, out_expr, out_error) -> nickel_result

Evaluate Nickel source to weak head normal form (WHNF).
Sub-expressions of records, arrays, and enum variants are left unevaluated.
Use [`nickel_context_eval_expr_shallow`](@ref) to evaluate them further.
"""
function nickel_context_eval_shallow(ctx, src, out_expr, out_error)
    @ccall libnickel_lang.nickel_context_eval_shallow(ctx::Ptr{nickel_context}, src::Ptr{Cchar}, out_expr::Ptr{nickel_expr}, out_error::Ptr{nickel_error})::nickel_result
end

"""
    nickel_context_eval_expr_shallow(ctx, expr, out_expr, out_error) -> nickel_result

Further evaluate an unevaluated expression to WHNF. Useful for evaluating
sub-expressions obtained from a shallow evaluation.
"""
function nickel_context_eval_expr_shallow(ctx, expr, out_expr, out_error)
    @ccall libnickel_lang.nickel_context_eval_expr_shallow(ctx::Ptr{nickel_context}, expr::Ptr{nickel_expr}, out_expr::Ptr{nickel_expr}, out_error::Ptr{nickel_error})::nickel_result
end

# ── Expression lifecycle ─────────────────────────────────────────────────────

"""
    nickel_expr_alloc() -> Ptr{nickel_expr}

Allocate a new expression. Must be freed with [`nickel_expr_free`](@ref).
Can be reused across multiple evaluations (overwritten in place).
"""
function nickel_expr_alloc()
    @ccall libnickel_lang.nickel_expr_alloc()::Ptr{nickel_expr}
end

"""
    nickel_expr_free(expr)

Free an expression allocated with [`nickel_expr_alloc`](@ref).
"""
function nickel_expr_free(expr)
    @ccall libnickel_lang.nickel_expr_free(expr::Ptr{nickel_expr})::Cvoid
end

# ── Expression type checks ──────────────────────────────────────────────────

"""
    nickel_expr_is_bool(expr) -> Cint

Returns non-zero if the expression is a boolean.
"""
function nickel_expr_is_bool(expr)
    @ccall libnickel_lang.nickel_expr_is_bool(expr::Ptr{nickel_expr})::Cint
end

"""
    nickel_expr_is_number(expr) -> Cint

Returns non-zero if the expression is a number.
"""
function nickel_expr_is_number(expr)
    @ccall libnickel_lang.nickel_expr_is_number(expr::Ptr{nickel_expr})::Cint
end

"""
    nickel_expr_is_str(expr) -> Cint

Returns non-zero if the expression is a string.
"""
function nickel_expr_is_str(expr)
    @ccall libnickel_lang.nickel_expr_is_str(expr::Ptr{nickel_expr})::Cint
end

"""
    nickel_expr_is_enum_tag(expr) -> Cint

Returns non-zero if the expression is an enum tag (no payload).
"""
function nickel_expr_is_enum_tag(expr)
    @ccall libnickel_lang.nickel_expr_is_enum_tag(expr::Ptr{nickel_expr})::Cint
end

"""
    nickel_expr_is_enum_variant(expr) -> Cint

Returns non-zero if the expression is an enum variant (tag with payload).
"""
function nickel_expr_is_enum_variant(expr)
    @ccall libnickel_lang.nickel_expr_is_enum_variant(expr::Ptr{nickel_expr})::Cint
end

"""
    nickel_expr_is_record(expr) -> Cint

Returns non-zero if the expression is a record.
"""
function nickel_expr_is_record(expr)
    @ccall libnickel_lang.nickel_expr_is_record(expr::Ptr{nickel_expr})::Cint
end

"""
    nickel_expr_is_array(expr) -> Cint

Returns non-zero if the expression is an array.
"""
function nickel_expr_is_array(expr)
    @ccall libnickel_lang.nickel_expr_is_array(expr::Ptr{nickel_expr})::Cint
end

"""
    nickel_expr_is_value(expr) -> Cint

Returns non-zero if the expression has been evaluated to a value
(null, bool, number, string, record, array, or enum).
Unevaluated sub-expressions from shallow eval return zero.
"""
function nickel_expr_is_value(expr)
    @ccall libnickel_lang.nickel_expr_is_value(expr::Ptr{nickel_expr})::Cint
end

"""
    nickel_expr_is_null(expr) -> Cint

Returns non-zero if the expression is null.
"""
function nickel_expr_is_null(expr)
    @ccall libnickel_lang.nickel_expr_is_null(expr::Ptr{nickel_expr})::Cint
end

# ── Expression accessors ─────────────────────────────────────────────────────

"""
    nickel_expr_as_bool(expr) -> Cint

Extract a boolean value. **Panics** (in Rust) if expr is not a bool.
"""
function nickel_expr_as_bool(expr)
    @ccall libnickel_lang.nickel_expr_as_bool(expr::Ptr{nickel_expr})::Cint
end

"""
    nickel_expr_as_str(expr, out_str) -> Csize_t

Extract a string value. Writes a pointer to the UTF-8 bytes (NOT null-terminated)
into `out_str`. Returns the byte length.

The string data borrows from `expr` and is invalidated on free/overwrite.
**Panics** (in Rust) if expr is not a string.
"""
function nickel_expr_as_str(expr, out_str)
    @ccall libnickel_lang.nickel_expr_as_str(expr::Ptr{nickel_expr}, out_str::Ptr{Ptr{Cchar}})::Csize_t
end

"""
    nickel_expr_as_number(expr) -> Ptr{nickel_number}

Extract a number reference. The returned pointer borrows from `expr`.
**Panics** (in Rust) if expr is not a number.
"""
function nickel_expr_as_number(expr)
    @ccall libnickel_lang.nickel_expr_as_number(expr::Ptr{nickel_expr})::Ptr{nickel_number}
end

"""
    nickel_expr_as_enum_tag(expr, out_str) -> Csize_t

Extract an enum tag string. Writes a pointer to the UTF-8 bytes (NOT null-terminated)
into `out_str`. Returns the byte length.

The string points to an interned string and will never be invalidated.
**Panics** (in Rust) if expr is not an enum tag.
"""
function nickel_expr_as_enum_tag(expr, out_str)
    @ccall libnickel_lang.nickel_expr_as_enum_tag(expr::Ptr{nickel_expr}, out_str::Ptr{Ptr{Cchar}})::Csize_t
end

"""
    nickel_expr_as_enum_variant(expr, out_str, out_expr) -> Csize_t

Extract an enum variant's tag string and payload.

- Writes tag string pointer to `out_str` (NOT null-terminated)
- Writes payload expression into `out_expr` (must be allocated)
- Returns the tag string byte length

**Panics** (in Rust) if expr is not an enum variant.
"""
function nickel_expr_as_enum_variant(expr, out_str, out_expr)
    @ccall libnickel_lang.nickel_expr_as_enum_variant(expr::Ptr{nickel_expr}, out_str::Ptr{Ptr{Cchar}}, out_expr::Ptr{nickel_expr})::Csize_t
end

"""
    nickel_expr_as_record(expr) -> Ptr{nickel_record}

Extract a record reference. The returned pointer borrows from `expr`.
**Panics** (in Rust) if expr is not a record.
"""
function nickel_expr_as_record(expr)
    @ccall libnickel_lang.nickel_expr_as_record(expr::Ptr{nickel_expr})::Ptr{nickel_record}
end

"""
    nickel_expr_as_array(expr) -> Ptr{nickel_array}

Extract an array reference. The returned pointer borrows from `expr`.
**Panics** (in Rust) if expr is not an array.
"""
function nickel_expr_as_array(expr)
    @ccall libnickel_lang.nickel_expr_as_array(expr::Ptr{nickel_expr})::Ptr{nickel_array}
end

# ── Serialization (export) ───────────────────────────────────────────────────

"""
    nickel_context_expr_to_json(ctx, expr, out_string, out_err) -> nickel_result

Serialize an evaluated expression to JSON. Fails if the expression contains
enum variants or unevaluated sub-expressions.
"""
function nickel_context_expr_to_json(ctx, expr, out_string, out_err)
    @ccall libnickel_lang.nickel_context_expr_to_json(ctx::Ptr{nickel_context}, expr::Ptr{nickel_expr}, out_string::Ptr{nickel_string}, out_err::Ptr{nickel_error})::nickel_result
end

"""
    nickel_context_expr_to_yaml(ctx, expr, out_string, out_err) -> nickel_result

Serialize an evaluated expression to YAML.
"""
function nickel_context_expr_to_yaml(ctx, expr, out_string, out_err)
    @ccall libnickel_lang.nickel_context_expr_to_yaml(ctx::Ptr{nickel_context}, expr::Ptr{nickel_expr}, out_string::Ptr{nickel_string}, out_err::Ptr{nickel_error})::nickel_result
end

"""
    nickel_context_expr_to_toml(ctx, expr, out_string, out_err) -> nickel_result

Serialize an evaluated expression to TOML.
"""
function nickel_context_expr_to_toml(ctx, expr, out_string, out_err)
    @ccall libnickel_lang.nickel_context_expr_to_toml(ctx::Ptr{nickel_context}, expr::Ptr{nickel_expr}, out_string::Ptr{nickel_string}, out_err::Ptr{nickel_error})::nickel_result
end

# ── Number accessors ─────────────────────────────────────────────────────────

"""
    nickel_number_is_i64(num) -> Cint

Returns non-zero if the number is an integer within `Int64` range.
"""
function nickel_number_is_i64(num)
    @ccall libnickel_lang.nickel_number_is_i64(num::Ptr{nickel_number})::Cint
end

"""
    nickel_number_as_i64(num) -> Int64

Extract the integer value. **Panics** (in Rust) if not an in-range integer
(check with [`nickel_number_is_i64`](@ref) first).
"""
function nickel_number_as_i64(num)
    @ccall libnickel_lang.nickel_number_as_i64(num::Ptr{nickel_number})::Int64
end

"""
    nickel_number_as_f64(num) -> Cdouble

Extract the number as a `Float64`, rounding to nearest if necessary.
"""
function nickel_number_as_f64(num)
    @ccall libnickel_lang.nickel_number_as_f64(num::Ptr{nickel_number})::Cdouble
end

"""
    nickel_number_as_rational(num, out_numerator, out_denominator)

Extract the exact rational representation as decimal strings.
Both out-params must be allocated with [`nickel_string_alloc`](@ref).
"""
function nickel_number_as_rational(num, out_numerator, out_denominator)
    @ccall libnickel_lang.nickel_number_as_rational(num::Ptr{nickel_number}, out_numerator::Ptr{nickel_string}, out_denominator::Ptr{nickel_string})::Cvoid
end

# ── Array accessors ──────────────────────────────────────────────────────────

"""
    nickel_array_len(arr) -> Csize_t

Return the number of elements in the array.
A null pointer (empty array) returns 0.
"""
function nickel_array_len(arr)
    @ccall libnickel_lang.nickel_array_len(arr::Ptr{nickel_array})::Csize_t
end

"""
    nickel_array_get(arr, idx, out_expr)

Retrieve the element at 0-based index `idx` into `out_expr`.
`out_expr` must be allocated with [`nickel_expr_alloc`](@ref).
**Panics** (in Rust) if `idx` is out of bounds.
"""
function nickel_array_get(arr, idx, out_expr)
    @ccall libnickel_lang.nickel_array_get(arr::Ptr{nickel_array}, idx::Csize_t, out_expr::Ptr{nickel_expr})::Cvoid
end

# ── Record accessors ─────────────────────────────────────────────────────────

"""
    nickel_record_len(rec) -> Csize_t

Return the number of fields in the record.
A null pointer (empty record) returns 0.
"""
function nickel_record_len(rec)
    @ccall libnickel_lang.nickel_record_len(rec::Ptr{nickel_record})::Csize_t
end

"""
    nickel_record_key_value_by_index(rec, idx, out_key, out_key_len, out_expr) -> Cint

Retrieve the key and value at 0-based index `idx`.

- Writes key pointer to `out_key` (UTF-8, NOT null-terminated)
- Writes key byte length to `out_key_len`
- Writes value into `out_expr` if non-NULL (must be allocated)
- Returns 1 if the field has a value, 0 if it doesn't (shallow eval)

**Panics** (in Rust) if `idx` is out of range.
"""
function nickel_record_key_value_by_index(rec, idx, out_key, out_key_len, out_expr)
    @ccall libnickel_lang.nickel_record_key_value_by_index(rec::Ptr{nickel_record}, idx::Csize_t, out_key::Ptr{Ptr{Cchar}}, out_key_len::Ptr{Csize_t}, out_expr::Ptr{nickel_expr})::Cint
end

"""
    nickel_record_value_by_name(rec, key, out_expr) -> Cint

Look up a field by name. `key` must be a null-terminated C string.
Returns 1 if found and has a value, 0 otherwise.
"""
function nickel_record_value_by_name(rec, key, out_expr)
    @ccall libnickel_lang.nickel_record_value_by_name(rec::Ptr{nickel_record}, key::Ptr{Cchar}, out_expr::Ptr{nickel_expr})::Cint
end

# ── String lifecycle and access ──────────────────────────────────────────────

"""
    nickel_string_alloc() -> Ptr{nickel_string}

Allocate a new string. Must be freed with [`nickel_string_free`](@ref).
"""
function nickel_string_alloc()
    @ccall libnickel_lang.nickel_string_alloc()::Ptr{nickel_string}
end

"""
    nickel_string_free(s)

Free a string allocated with [`nickel_string_alloc`](@ref).
"""
function nickel_string_free(s)
    @ccall libnickel_lang.nickel_string_free(s::Ptr{nickel_string})::Cvoid
end

"""
    nickel_string_data(s, data, len)

Retrieve the contents of a string. Writes a pointer to the UTF-8 bytes
(NOT null-terminated) into `data`, and the byte length into `len`.
Data is invalidated when `s` is freed or overwritten.
"""
function nickel_string_data(s, data, len)
    @ccall libnickel_lang.nickel_string_data(s::Ptr{nickel_string}, data::Ptr{Ptr{Cchar}}, len::Ptr{Csize_t})::Cvoid
end

# ── Error lifecycle and formatting ───────────────────────────────────────────

"""
    nickel_error_alloc() -> Ptr{nickel_error}

Allocate a new error. Must be freed with [`nickel_error_free`](@ref).
"""
function nickel_error_alloc()
    @ccall libnickel_lang.nickel_error_alloc()::Ptr{nickel_error}
end

"""
    nickel_error_free(err)

Free an error allocated with [`nickel_error_alloc`](@ref).
"""
function nickel_error_free(err)
    @ccall libnickel_lang.nickel_error_free(err::Ptr{nickel_error})::Cvoid
end

"""
    nickel_error_display(err, write, write_payload, format) -> nickel_result

Format an error via a write callback function.
"""
function nickel_error_display(err, write, write_payload, format)
    @ccall libnickel_lang.nickel_error_display(err::Ptr{nickel_error}, write::nickel_write_callback, write_payload::Ptr{Cvoid}, format::nickel_error_format)::nickel_result
end

"""
    nickel_error_format_as_string(err, out_string, format) -> nickel_result

Format an error into a [`nickel_string`](@ref).
`out_string` must be allocated with [`nickel_string_alloc`](@ref).
"""
function nickel_error_format_as_string(err, out_string, format)
    @ccall libnickel_lang.nickel_error_format_as_string(err::Ptr{nickel_error}, out_string::Ptr{nickel_string}, format::nickel_error_format)::nickel_result
end

# ── Exports ──────────────────────────────────────────────────────────────────

const PREFIXES = ["nickel_", "NICKEL_"]
for name in names(@__MODULE__; all=true), prefix in PREFIXES
    if startswith(string(name), prefix)
        @eval export $name
    end
end

end # module LibNickel
