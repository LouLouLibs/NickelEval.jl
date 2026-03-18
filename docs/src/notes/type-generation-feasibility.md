# Feasibility: Generating Julia Types from Nickel Contracts

**Status:** Speculative / not planned
**Date:** 2026-03-17

## Motivation

Nickel has a rich type system including enum types (`[| 'active, 'inactive |]`), record contracts, and algebraic data types. It would be valuable to use Nickel as a schema language — define types in `.ncl` files and generate corresponding Julia structs and enums from them, enabling type-safe dispatch and validation on the Julia side.

Envisioned usage:

```julia
@nickel_types "schema.ncl"
# generates StatusEnum, MyConfig, etc. as Julia types
function process(s::StatusEnum) ... end
```

## Current State

### What works today

- Enum **values** (`'Foo`, `'Some 42`) are fully supported via the binary protocol (TYPE_ENUM, tag 7)
- They decode to `NickelEnum(tag::Symbol, arg::Any)` on the Julia side
- Enum values constrained by enum types evaluate correctly: `nickel_eval_native("let x : [| 'a, 'b |] = 'a in x")` returns `NickelEnum(:a, nothing)`

### What doesn't exist

- No way to extract **type definitions** themselves through the FFI
- `eval_full_for_export()` produces values, not types — type information is erased during evaluation
- `nickel-lang-core 0.9.1` does not expose a public API for type introspection
- Nickel has no runtime reflection on types — you can't ask an enum type for its list of variants

## Nickel Type System Background

- Enum type syntax: `[| 'Carnitas, 'Fish |]` (simple), `[| 'Ok Number, 'Err String |]` (with payloads)
- Enum types are structural and compile-time — they exist for the typechecker, not at runtime
- Types and contracts are interchangeable: `foo : T` and `foo | T` both enforce at runtime
- Row polymorphism allows extensible enums: `[| 'Ok a ; tail |]`
- `std.enum.to_tag_and_arg` decomposes enum values at runtime, but cannot inspect enum types
- ADTs (enum variants with data) fully supported since Nickel 1.5

Internally, `nickel-lang-core` represents types via the `TypeF` enum, which includes `TypeF::Enum(row_type)` for enum types. But this is internal API, not a stable public surface.

## Approaches Considered

### Approach 1: Convention-based (schema as value)

Write schemas as Nickel **values** that describe types, not as actual type annotations:

```nickel
{
  fields = {
    status = { type = "enum", variants = ["active", "inactive"] },
    name = { type = "string" },
    count = { type = "number" },
  }
}
```

Then `@nickel_types "schema.ncl"` evaluates this with the existing FFI and generates Julia types.

- **Pro:** Works today with no Rust changes
- **Con:** Redundant — writing schemas-about-schemas instead of using Nickel's native type syntax

### Approach 2: AST walking in Rust (recommended if pursued)

Add a new Rust FFI function (`nickel_extract_types`) that parses a `.ncl` file, walks the AST, and extracts type annotations from record contracts. Returns a structured description of the type schema.

The Rust side would:
1. Parse the Nickel source into an AST
2. Walk `Term::RecRecord` / `Term::Record` nodes looking for type annotations on fields
3. For each annotated field, extract the `TypeF` structure
4. Encode `TypeF::Enum(rows)` → list of variant names/types
5. Encode `TypeF::Record(rows)` → list of field names/types
6. Return as JSON or binary protocol

The Julia side would:
1. Call the FFI function to get the type description
2. In a `@nickel_types` macro, generate `struct` definitions and enum-like types at compile time

Estimated scope: ~200-400 lines of Rust, plus Julia macro (~100-200 lines).

- **Pro:** Uses real Nickel type syntax. Elegant.
- **Con:** Couples to `nickel-lang-core` internals (`TypeF` enum, AST structure). Could break across crate versions. Medium-to-large effort.

### Approach 3: Nickel-side reflection

Use Nickel's runtime to reflect on contracts — e.g., `std.record.fields` to list record keys, pattern matching to decompose contracts.

- **Pro:** No Rust changes
- **Con:** Doesn't work for enum types — Nickel has no runtime mechanism to list the variants of `[| 'a, 'b |]`. Dead end for the core use case.

## Conclusion

**Approach 2 is the only viable path** for using Nickel's native type syntax, but it's a significant investment that couples to unstable internal APIs. **Approach 1 is a pragmatic workaround** if the need becomes pressing.

This is outside the current scope of NickelEval.jl, which focuses on evaluation, not type extraction. If `nickel-lang-core` ever exposes a public type introspection API, the picture changes significantly.

## Key Dependencies

- `nickel-lang-core` would need to maintain a stable enough AST/type representation (currently internal)
- Julia macro system for compile-time type generation (`@generated` or expression-based macros)
- Decision on how to map Nickel's structural types to Julia's nominal type system (e.g., enum rows → `@enum` or union of `Symbol`s)
