@testset "C API Evaluation" begin
    @testset "Primitive types" begin
        # Integers
        @test nickel_eval("42") === Int64(42)
        @test nickel_eval("-42") === Int64(-42)
        @test nickel_eval("0") === Int64(0)
        @test nickel_eval("1000000000000") === Int64(1000000000000)

        # Floats (only true decimals)
        @test nickel_eval("3.14") ≈ 3.14
        @test nickel_eval("-2.718") ≈ -2.718
        @test nickel_eval("0.5") ≈ 0.5
        @test typeof(nickel_eval("3.14")) == Float64

        # Booleans
        @test nickel_eval("true") === true
        @test nickel_eval("false") === false

        # Null
        @test nickel_eval("null") === nothing

        # Strings
        @test nickel_eval("\"hello\"") == "hello"
        @test nickel_eval("\"\"") == ""
        @test nickel_eval("\"hello 世界\"") == "hello 世界"
    end

    @testset "Arrays" begin
        @test nickel_eval("[]") == Any[]
        @test nickel_eval("[1, 2, 3]") == Any[1, 2, 3]
        @test nickel_eval("[true, false]") == Any[true, false]
        @test nickel_eval("[\"a\", \"b\"]") == Any["a", "b"]

        # Nested arrays
        result = nickel_eval("[[1, 2], [3, 4]]")
        @test result == Any[Any[1, 2], Any[3, 4]]

        # Mixed types
        result = nickel_eval("[1, \"two\", true, null]")
        @test result == Any[1, "two", true, nothing]
    end

    @testset "Records" begin
        result = nickel_eval("{ x = 1 }")
        @test result isa Dict{String, Any}
        @test result["x"] === Int64(1)

        result = nickel_eval("{ name = \"test\", count = 42 }")
        @test result["name"] == "test"
        @test result["count"] === Int64(42)

        # Empty record
        @test nickel_eval("{}") == Dict{String, Any}()

        # Nested records
        result = nickel_eval("{ outer = { inner = 42 } }")
        @test result["outer"]["inner"] === Int64(42)
    end

    @testset "Type preservation" begin
        @test typeof(nickel_eval("42")) == Int64
        @test typeof(nickel_eval("42.5")) == Float64
        @test typeof(nickel_eval("42.0")) == Int64  # whole numbers -> Int64
    end

    @testset "Computed values" begin
        @test nickel_eval("1 + 2") === Int64(3)
        @test nickel_eval("10 - 3") === Int64(7)
        @test nickel_eval("let x = 10 in x * 2") === Int64(20)
        @test nickel_eval("let add = fun x y => x + y in add 3 4") === Int64(7)
    end

    @testset "Record operations" begin
        result = nickel_eval("{ a = 1 } & { b = 2 }")
        @test result["a"] === Int64(1)
        @test result["b"] === Int64(2)
    end

    @testset "Array operations" begin
        result = nickel_eval("[1, 2, 3] |> std.array.map (fun x => x * 2)")
        @test result == Any[2, 4, 6]
    end

    @testset "Enums - Simple (no argument)" begin
        result = nickel_eval("let x = 'Foo in x")
        @test result isa NickelEnum
        @test result.tag == :Foo
        @test result.arg === nothing

        # Convenience comparison
        @test result == :Foo
        @test :Foo == result
        @test result != :Bar

        @test nickel_eval("let x = 'None in x").tag == :None
        @test nickel_eval("let x = 'True in x").tag == :True
        @test nickel_eval("let x = 'False in x").tag == :False
        @test nickel_eval("let x = 'Pending in x").tag == :Pending
        @test nickel_eval("let x = 'Red in x").tag == :Red
    end

    @testset "Enums - With primitive arguments" begin
        # Integer argument
        result = nickel_eval("let x = 'Count 42 in x")
        @test result.tag == :Count
        @test result.arg === Int64(42)

        # Negative integer (needs parentheses in Nickel)
        result = nickel_eval("let x = 'Offset (-100) in x")
        @test result.arg === Int64(-100)

        # Float argument
        result = nickel_eval("let x = 'Temperature 98.6 in x")
        @test result.tag == :Temperature
        @test result.arg ≈ 98.6

        # String argument
        result = nickel_eval("let x = 'Message \"hello world\" in x")
        @test result.tag == :Message
        @test result.arg == "hello world"

        # Empty string argument
        result = nickel_eval("let x = 'Empty \"\" in x")
        @test result.arg == ""

        # Boolean arguments
        result = nickel_eval("let x = 'Flag true in x")
        @test result.arg === true
        result = nickel_eval("let x = 'Flag false in x")
        @test result.arg === false

        # Null argument
        result = nickel_eval("let x = 'Nullable null in x")
        @test result.arg === nothing
    end

    @testset "Enums - With record arguments" begin
        # Simple record argument
        result = nickel_eval("let x = 'Ok { value = 123 } in x")
        @test result.tag == :Ok
        @test result.arg isa Dict{String, Any}
        @test result.arg["value"] === Int64(123)

        # Record with multiple fields
        code = """
        let result = 'Ok { value = 123, message = "success" } in result
        """
        result = nickel_eval(code)
        @test result.arg["value"] === Int64(123)
        @test result.arg["message"] == "success"

        # Error with details
        code = """
        let err = 'Error { code = 404, reason = "not found" } in err
        """
        result = nickel_eval(code)
        @test result.tag == :Error
        @test result.arg["code"] === Int64(404)
        @test result.arg["reason"] == "not found"

        # Nested record in enum
        code = """
        let x = 'Data { outer = { inner = 42 } } in x
        """
        result = nickel_eval(code)
        @test result.arg["outer"]["inner"] === Int64(42)
    end

    @testset "Enums - With array arguments" begin
        # Array of integers
        result = nickel_eval("let x = 'Batch [1, 2, 3, 4, 5] in x")
        @test result.tag == :Batch
        @test result.arg == Any[1, 2, 3, 4, 5]

        # Empty array
        result = nickel_eval("let x = 'Empty [] in x")
        @test result.arg == Any[]

        # Array of strings
        result = nickel_eval("let x = 'Names [\"alice\", \"bob\"] in x")
        @test result.arg == Any["alice", "bob"]

        # Array of records
        code = """
        let x = 'Users [{ name = "alice" }, { name = "bob" }] in x
        """
        result = nickel_eval(code)
        @test result.arg[1]["name"] == "alice"
        @test result.arg[2]["name"] == "bob"
    end

    @testset "Enums - Nested enums" begin
        # Enum inside record inside enum
        code = """
        let outer = 'Container { inner = 'Value 42 } in outer
        """
        result = nickel_eval(code)
        @test result.tag == :Container
        @test result.arg["inner"] isa NickelEnum
        @test result.arg["inner"].tag == :Value
        @test result.arg["inner"].arg === Int64(42)

        # Array of enums inside enum
        code = """
        let items = 'List ['Some 1, 'None, 'Some 3] in items
        """
        result = nickel_eval(code)
        @test result.tag == :List
        @test length(result.arg) == 3
        @test result.arg[1].tag == :Some
        @test result.arg[1].arg === Int64(1)
        @test result.arg[2].tag == :None
        @test result.arg[2].arg === nothing
        @test result.arg[3].tag == :Some
        @test result.arg[3].arg === Int64(3)

        # Deeply nested enums
        code = """
        let x = 'L1 { a = 'L2 { b = 'L3 42 } } in x
        """
        result = nickel_eval(code)
        @test result.arg["a"].arg["b"].arg === Int64(42)
    end

    @testset "Enums - Pattern matching" begin
        # Match resolves to extracted value
        code = """
        let x = 'Some 42 in
        x |> match {
          'Some v => v,
          'None => 0
        }
        """
        result = nickel_eval(code)
        @test result === Int64(42)

        # Match with record destructuring
        code = """
        let result = 'Ok { value = 100 } in
        result |> match {
          'Ok r => r.value,
          'Error _ => -1
        }
        """
        result = nickel_eval(code)
        @test result === Int64(100)

        # Match returning enum
        code = """
        let x = 'Some 42 in
        x |> match {
          'Some v => 'Doubled (v * 2),
          'None => 'Zero 0
        }
        """
        result = nickel_eval(code)
        @test result.tag == :Doubled
        @test result.arg === Int64(84)
    end

    @testset "Enums - Pretty printing" begin
        # Simple enum
        @test repr(nickel_eval("let x = 'None in x")) == "'None"
        @test repr(nickel_eval("let x = 'Foo in x")) == "'Foo"

        # Enum with simple argument
        @test repr(nickel_eval("let x = 'Some 42 in x")) == "'Some 42"

        # Enum with string argument
        result = nickel_eval("let x = 'Msg \"hi\" in x")
        @test startswith(repr(result), "'Msg")
    end

    @testset "Enums - Real-world patterns" begin
        # Result type pattern
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
        @test result == :Ok
        @test result.arg === Int64(5)

        # Option type pattern
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
        @test result == :Some
        @test result.arg === Int64(3)

        # State machine pattern
        code = """
        let state = 'Running { progress = 75, task = "downloading" } in state
        """
        result = nickel_eval(code)
        @test result.tag == :Running
        @test result.arg["progress"] === Int64(75)
        @test result.arg["task"] == "downloading"
    end

    @testset "Deeply nested structures" begin
        # Deep nesting
        result = nickel_eval("{ a = { b = { c = { d = 42 } } } }")
        @test result["a"]["b"]["c"]["d"] === Int64(42)

        # Array of records
        result = nickel_eval("[{ x = 1 }, { x = 2 }, { x = 3 }]")
        @test length(result) == 3
        @test result[1]["x"] === Int64(1)
        @test result[3]["x"] === Int64(3)

        # Records containing arrays
        result = nickel_eval("{ items = [1, 2, 3], name = \"test\" }")
        @test result["items"] == Any[1, 2, 3]
        @test result["name"] == "test"

        # Mixed deep nesting
        result = nickel_eval("{ data = [{ a = 1 }, { b = [true, false] }] }")
        @test result["data"][1]["a"] === Int64(1)
        @test result["data"][2]["b"] == Any[true, false]
    end

    @testset "Typed evaluation - primitives" begin
        @test nickel_eval("42", Int) === 42
        @test nickel_eval("3.14", Float64) === 3.14
        @test nickel_eval("\"hello\"", String) == "hello"
        @test nickel_eval("true", Bool) === true
    end

    @testset "Typed evaluation - Dict{String, V}" begin
        result = nickel_eval("{ a = 1, b = 2 }", Dict{String, Int})
        @test result isa Dict{String, Int}
        @test result["a"] === 1
        @test result["b"] === 2
    end

    @testset "Typed evaluation - Dict{Symbol, V}" begin
        result = nickel_eval("{ x = 1.5, y = 2.5 }", Dict{Symbol, Float64})
        @test result isa Dict{Symbol, Float64}
        @test result[:x] === 1.5
        @test result[:y] === 2.5
    end

    @testset "Typed evaluation - Vector{T}" begin
        result = nickel_eval("[1, 2, 3]", Vector{Int})
        @test result isa Vector{Int}
        @test result == [1, 2, 3]

        result = nickel_eval("[\"a\", \"b\", \"c\"]", Vector{String})
        @test result isa Vector{String}
        @test result == ["a", "b", "c"]
    end

    @testset "Typed evaluation - NamedTuple" begin
        result = nickel_eval("{ host = \"localhost\", port = 8080 }",
                             @NamedTuple{host::String, port::Int})
        @test result isa NamedTuple{(:host, :port), Tuple{String, Int}}
        @test result.host == "localhost"
        @test result.port === 8080
    end

    @testset "String macro" begin
        @test ncl"42" === Int64(42)
        @test ncl"1 + 1" == 2
        @test ncl"true" === true
        @test ncl"{ x = 10 }"["x"] === Int64(10)
    end

    @testset "check_ffi_available" begin
        @test check_ffi_available() === true
    end

    @testset "Error handling" begin
        # Undefined variable
        @test_throws NickelError nickel_eval("undefined_variable")
        # Syntax error
        @test_throws NickelError nickel_eval("{ x = }")
    end
end

@testset "File Evaluation" begin
    mktempdir() do dir
        # Simple file
        f = joinpath(dir, "test.ncl")
        write(f, "{ x = 42 }")
        result = nickel_eval_file(f)
        @test result["x"] === Int64(42)

        # File returning a primitive
        f2 = joinpath(dir, "prim.ncl")
        write(f2, "1 + 2")
        @test nickel_eval_file(f2) === Int64(3)

        # File with import
        shared = joinpath(dir, "shared.ncl")
        write(shared, """
        {
          project_name = "TestProject",
          version = "1.0.0"
        }
        """)
        main = joinpath(dir, "main.ncl")
        write(main, """
let shared = import "shared.ncl" in
{
  name = shared.project_name,
  version = shared.version,
  extra = "main-specific"
}
""")
        result = nickel_eval_file(main)
        @test result isa Dict{String, Any}
        @test result["name"] == "TestProject"
        @test result["version"] == "1.0.0"
        @test result["extra"] == "main-specific"

        # Nested imports
        utils_file = joinpath(dir, "utils.ncl")
        write(utils_file, """
        {
          helper = fun x => x * 2
        }
        """)

        complex_file = joinpath(dir, "complex.ncl")
        write(complex_file, """
let shared = import "shared.ncl" in
let utils = import "utils.ncl" in
{
  project = shared.project_name,
  doubled_value = utils.helper 21
}
""")
        result = nickel_eval_file(complex_file)
        @test result["project"] == "TestProject"
        @test result["doubled_value"] === Int64(42)

        # File evaluation with enums
        enum_file = joinpath(dir, "enum_config.ncl")
        write(enum_file, """
        {
          status = 'Active,
          result = 'Ok 42
        }
        """)

        result = nickel_eval_file(enum_file)
        @test result["status"] isa NickelEnum
        @test result["status"] == :Active
        @test result["result"].tag == :Ok
        @test result["result"].arg === Int64(42)

        # Subdirectory imports
        subdir = joinpath(dir, "lib")
        mkdir(subdir)
        lib_file = joinpath(subdir, "library.ncl")
        write(lib_file, """
        {
          lib_version = "2.0"
        }
        """)

        with_subdir_file = joinpath(dir, "use_lib.ncl")
        write(with_subdir_file, """
let lib = import "lib/library.ncl" in
{
  using = lib.lib_version
}
""")
        result = nickel_eval_file(with_subdir_file)
        @test result["using"] == "2.0"
    end

    # Non-existent file
    @test_throws NickelError nickel_eval_file("/nonexistent/path/file.ncl")

    # Import not found
    mktempdir() do dir
        bad_import = joinpath(dir, "bad_import.ncl")
        write(bad_import, """
let missing = import "not_there.ncl" in
missing
""")
        @test_throws NickelError nickel_eval_file(bad_import)
    end
end

@testset "Export formats" begin
    json = nickel_to_json("{ a = 1 }")
    @test occursin("\"a\"", json)
    @test occursin("1", json)

    yaml = nickel_to_yaml("{ a = 1 }")
    @test occursin("a:", yaml)

    toml = nickel_to_toml("{ a = 1 }")
    @test occursin("a = 1", toml)

    # Export more complex structures
    json2 = nickel_to_json("{ name = \"test\", values = [1, 2, 3] }")
    @test occursin("\"name\"", json2)
    @test occursin("\"test\"", json2)

    # Export error: expression that can't be evaluated
    @test_throws NickelError nickel_to_json("undefined_variable")
end
