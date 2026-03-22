# Detailed Examples

## Type Conversions

### Nickel to Julia Type Mapping

| Nickel Type | Julia Type |
|:------------|:-----------|
| Null | `nothing` |
| Bool | `Bool` |
| Number (integer) | `Int64` |
| Number (float) | `Float64` |
| String | `String` |
| Array | `Vector{Any}` |
| Record | `Dict{String, Any}` |
| Enum (tag only) | `NickelEnum(tag, nothing)` |
| Enum (with argument) | `NickelEnum(tag, arg)` |

### Typed Evaluation

Pass a type as the second argument to `nickel_eval` to convert the result:

```julia
nickel_eval("42", Int)              # => 42::Int64
nickel_eval("3.14", Float64)        # => 3.14::Float64
nickel_eval("\"hello\"", String)    # => "hello"::String
```

#### Typed Dicts

```julia
nickel_eval("{ a = 1, b = 2 }", Dict{String, Int})
# => Dict{String, Int64}("a" => 1, "b" => 2)

nickel_eval("{ x = 1.5, y = 2.5 }", Dict{Symbol, Float64})
# => Dict{Symbol, Float64}(:x => 1.5, :y => 2.5)
```

#### Typed Vectors

```julia
nickel_eval("[1, 2, 3]", Vector{Int})
# => [1, 2, 3]::Vector{Int64}

nickel_eval("[\"a\", \"b\", \"c\"]", Vector{String})
# => ["a", "b", "c"]::Vector{String}
```

#### NamedTuples

Records can be converted to `NamedTuple` for convenient field access:

```julia
server = nickel_eval(
    "{ host = \"localhost\", port = 8080 }",
    @NamedTuple{host::String, port::Int}
)
server.host  # => "localhost"
server.port  # => 8080
```

## Enums — `NickelEnum`

Nickel enums are represented as `NickelEnum`, a struct with two fields:
- `tag::Symbol` — the variant name
- `arg::Any` — the payload (`nothing` for bare tags)

### Simple Enum Tags

```julia
result = nickel_eval("let x = 'Foo in x")
result.tag   # => :Foo
result.arg   # => nothing
```

`NickelEnum` supports direct comparison with `Symbol`:

```julia
result == :Foo   # => true
result == :Bar   # => false
```

### Enums with Arguments

Enum variants can carry a value of any type:

```julia
# Integer payload
result = nickel_eval("let x = 'Some 42 in x")
result.tag   # => :Some
result.arg   # => 42

# String payload
result = nickel_eval("let x = 'Message \"hello\" in x")
result.tag   # => :Message
result.arg   # => "hello"

# Record payload
result = nickel_eval("let x = 'Ok { value = 123, status = \"done\" } in x")
result.tag                # => :Ok
result.arg["value"]       # => 123
result.arg["status"]      # => "done"

# Array payload
result = nickel_eval("let x = 'Batch [1, 2, 3] in x")
result.arg                # => Any[1, 2, 3]
```

### Nested Enums

Enums can appear inside records, arrays, or other enums:

```julia
# Enum inside a record
result = nickel_eval("{ status = 'Active, result = 'Ok 42 }")
result["status"] == :Active        # => true
result["result"].arg               # => 42

# Enum inside another enum
result = nickel_eval("let x = 'Container { inner = 'Value 42 } in x")
result.tag                         # => :Container
result.arg["inner"].tag            # => :Value
result.arg["inner"].arg            # => 42

# Array of enums
result = nickel_eval("let x = 'List ['Some 1, 'None, 'Some 3] in x")
result.arg[1].tag                  # => :Some
result.arg[1].arg                  # => 1
result.arg[2] == :None             # => true
```

### Pattern Matching

Nickel's `match` resolves before reaching Julia — you get back the matched value:

```julia
result = nickel_eval("""
let x = 'Some 42 in
x |> match {
  'Some v => v,
  'None => 0
}
""")
# => 42

result = nickel_eval("""
let x = 'Some 42 in
x |> match {
  'Some v => 'Doubled (v * 2),
  'None => 'Zero 0
}
""")
result.tag   # => :Doubled
result.arg   # => 84
```

### Pretty Printing

`NickelEnum` displays in Nickel's own syntax:

```julia
repr(nickel_eval("let x = 'None in x"))       # => "'None"
repr(nickel_eval("let x = 'Some 42 in x"))     # => "'Some 42"
repr(nickel_eval("let x = 'Msg \"hi\" in x"))  # => "'Msg \"hi\""
```

### Real-World Patterns

#### Result Type

```julia
code = """
let divide = fun a b =>
  if b == 0 then
    'Err "division by zero"
  else
    'Ok (a / b)
in
divide 10 2
"""
result = nickel_eval(code)
result == :Ok    # => true
result.arg       # => 5
```

#### Option Type

```julia
code = """
let find = fun arr pred =>
  let matches = std.array.filter pred arr in
  if std.array.length matches == 0 then
    'None
  else
    'Some (std.array.first matches)
in
find [1, 2, 3, 4] (fun x => x > 2)
"""
result = nickel_eval(code)
result == :Some  # => true
result.arg       # => 3
```

#### State Machine

```julia
result = nickel_eval("""
let state = 'Running { progress = 75, task = "downloading" } in state
""")
result.tag               # => :Running
result.arg["progress"]   # => 75
result.arg["task"]       # => "downloading"
```

## Export Formats

Evaluate Nickel code and serialize to JSON, TOML, or YAML:

```julia
nickel_to_json("{ name = \"myapp\", version = \"1.0\" }")
# => "{\n  \"name\": \"myapp\",\n  \"version\": \"1.0\"\n}"

nickel_to_yaml("{ name = \"myapp\", version = \"1.0\" }")
# => "name: myapp\nversion: '1.0'\n"

nickel_to_toml("{ name = \"myapp\", version = \"1.0\" }")
# => "name = \"myapp\"\nversion = \"1.0\"\n"
```

## File Evaluation with Imports

Nickel files can import other Nickel files. `nickel_eval_file` resolves imports relative to the file's directory.

Given these files:

```nickel
# shared.ncl
{
  project_name = "MyProject",
  version = "1.0.0"
}
```

```nickel
# config.ncl
let shared = import "shared.ncl" in
{
  name = shared.project_name,
  version = shared.version,
  debug = true
}
```

```julia
config = nickel_eval_file("config.ncl")
config["name"]     # => "MyProject"
config["version"]  # => "1.0.0"
config["debug"]    # => true
```

Subdirectory imports also work:

```nickel
# lib/utils.ncl
{
  helper = fun x => x * 2
}
```

```nickel
# main.ncl
let utils = import "lib/utils.ncl" in
{ result = utils.helper 21 }
```

```julia
nickel_eval_file("main.ncl")
# => Dict("result" => 42)
```
