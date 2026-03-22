# Lazy Evaluation

## The Problem

`nickel_eval` evaluates the entire expression tree before returning. For a large configuration file with hundreds of fields, this means every field is computed even if you only need one:

```julia
# Evaluates ALL fields, even though we only need port
config = nickel_eval_file("large_config.ncl")
config["database"]["port"]  # => 5432
```

## The Solution: `nickel_open`

`nickel_open` evaluates shallowly — it figures out the top-level structure but leaves field values as frozen computations. Values are only computed when you access them:

```julia
nickel_open("large_config.ncl") do cfg
    cfg.database.port  # only evaluates the path you walk
end
```

## Basic Usage

### Do-block (preferred)

The do-block automatically cleans up resources when the block exits:

```julia
using NickelEval

result = nickel_open("{ name = \"myapp\", version = \"1.0\" }") do cfg
    cfg.name  # => "myapp"
end
```

### Manual mode (REPL exploration)

For interactive exploration, you can manage the lifecycle yourself:

```julia
cfg = nickel_open("{ x = 1, y = 2 }")
cfg.x       # => 1
cfg.y       # => 2
close(cfg)  # free resources
```

### File evaluation

Files ending in `.ncl` are detected automatically. Imports resolve relative to the file:

```julia
nickel_open("config.ncl") do cfg
    cfg.database.host  # => "localhost"
end
```

## Navigation

Access fields with dot syntax or brackets:

```julia
nickel_open("{ db = { host = \"localhost\", port = 5432 } }") do cfg
    cfg.db.host      # dot syntax
    cfg["db"]["host"] # bracket syntax — same result

    cfg.db           # returns a NickelValue (still lazy)
    cfg.db.port      # returns Int64(5432) (primitive, resolved)
end
```

Arrays use 1-based indexing:

```julia
nickel_open("{ items = [10, 20, 30] }") do cfg
    cfg.items[1]  # => 10
    cfg.items[3]  # => 30
end
```

## Inspecting Without Evaluating

Check the kind and size of a value without evaluating its contents:

```julia
nickel_open("{ a = 1, b = 2, c = 3 }") do cfg
    nickel_kind(cfg)  # => :record
    length(cfg)       # => 3
    keys(cfg)         # => ["a", "b", "c"]
end
```

## Materializing a Subtree

`collect` recursively evaluates an entire subtree, returning the same types as `nickel_eval`:

```julia
nickel_open("{ db = { host = \"localhost\", port = 5432 } }") do cfg
    collect(cfg.db)
    # => Dict{String, Any}("host" => "localhost", "port" => 5432)

    collect(cfg)
    # => Dict{String, Any}("db" => Dict("host" => "localhost", "port" => 5432))
end
```

## Iteration

Iterate over records (yields `key => value` pairs) or arrays:

```julia
nickel_open("{ a = 1, b = 2 }") do cfg
    for (k, v) in cfg
        println("$k = $v")
    end
end

nickel_open("[10, 20, 30]") do cfg
    for item in cfg
        println(item)
    end
end
```

## Benchmark: Lazy vs Eager

The benefit of lazy evaluation depends on how expensive your fields are to compute. For configs with computationally intensive fields (array operations, complex merges, function calls), the difference is dramatic.

This benchmark generates configs where each field folds over a 1000-element array. Eager evaluation computes every field; lazy evaluation computes only the one you access:

```julia
using NickelEval

function make_expensive_config(n)
    fields = String[]
    for i in 1:n
        push!(fields,
            "section_$i = std.array.fold_left " *
            "(fun acc x => acc + x) 0 " *
            "(std.array.generate (fun x => x + $i) 1000)")
    end
    "{ " * join(fields, ", ") * " }"
end

code = make_expensive_config(100)

# Eager: evaluates all 100 expensive fields (~470 ms)
@time result = nickel_eval(code)
result["section_50"]

# Lazy: evaluates only section_50 (~26 ms)
@time nickel_open(code) do cfg
    cfg.section_50
end
```

Results on Apple M1 (averaged over 3 runs):

| Fields | Eager | Lazy | Speedup |
|--------|-------|------|---------|
| 10     | 51 ms  | 13 ms | 4x     |
| 50     | 242 ms | 18 ms | 13x    |
| 100    | 473 ms | 26 ms | 18x    |
| 200    | 940 ms | 44 ms | 21x    |

Lazy evaluation time grows slowly (parsing overhead) while eager time scales linearly with the number of fields. For configs with simple static values (no computation), the difference is negligible since parsing dominates.

## When to Use Lazy vs Eager

| Use case | Recommended |
|----------|------------|
| Small configs (< 50 fields) | `nickel_eval` — simpler, negligible overhead |
| Large configs, need all fields | `nickel_eval` — eager is fine if you need everything |
| Large configs, need a few fields | `nickel_open` — avoids evaluating unused fields |
| Interactive exploration | `nickel_open` (manual mode) — drill in on demand |
| Exporting to JSON/YAML/TOML | `nickel_to_json` etc. — these are always eager |
