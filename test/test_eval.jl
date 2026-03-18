@testset "C API Evaluation" begin
    @testset "Primitive types" begin
        @test nickel_eval("42") === Int64(42)
        @test nickel_eval("-42") === Int64(-42)
        @test nickel_eval("0") === Int64(0)
        @test nickel_eval("3.14") ≈ 3.14
        @test typeof(nickel_eval("3.14")) == Float64
        @test nickel_eval("true") === true
        @test nickel_eval("false") === false
        @test nickel_eval("null") === nothing
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
    end

    @testset "Enums - With arguments" begin
        result = nickel_eval("let x = 'Count 42 in x")
        @test result.tag == :Count
        @test result.arg === Int64(42)

        result = nickel_eval("let x = 'Message \"hello world\" in x")
        @test result.tag == :Message
        @test result.arg == "hello world"

        result = nickel_eval("let x = 'Flag true in x")
        @test result.arg === true
    end

    @testset "Enums - With record arguments" begin
        result = nickel_eval("let x = 'Ok { value = 123 } in x")
        @test result.tag == :Ok
        @test result.arg isa Dict{String, Any}
        @test result.arg["value"] === Int64(123)
    end

    @testset "Enums - Pretty printing" begin
        @test repr(nickel_eval("let x = 'None in x")) == "'None"
        @test repr(nickel_eval("let x = 'Some 42 in x")) == "'Some 42"
    end

    @testset "Deeply nested structures" begin
        result = nickel_eval("{ a = { b = { c = { d = 42 } } } }")
        @test result["a"]["b"]["c"]["d"] === Int64(42)

        result = nickel_eval("[{ x = 1 }, { x = 2 }, { x = 3 }]")
        @test length(result) == 3
        @test result[1]["x"] === Int64(1)
        @test result[3]["x"] === Int64(3)

        result = nickel_eval("{ items = [1, 2, 3], name = \"test\" }")
        @test result["items"] == Any[1, 2, 3]
        @test result["name"] == "test"
    end

    @testset "Typed evaluation" begin
        @test nickel_eval("42", Int) === 42
        @test nickel_eval("3.14", Float64) === 3.14
        @test nickel_eval("\"hello\"", String) == "hello"
        @test nickel_eval("true", Bool) === true

        result = nickel_eval("{ a = 1, b = 2 }", Dict{String, Int})
        @test result isa Dict{String, Int}
        @test result["a"] === 1
        @test result["b"] === 2

        result = nickel_eval("[1, 2, 3]", Vector{Int})
        @test result isa Vector{Int}
        @test result == [1, 2, 3]

        result = nickel_eval("{ host = \"localhost\", port = 8080 }",
                             @NamedTuple{host::String, port::Int})
        @test result isa NamedTuple{(:host, :port), Tuple{String, Int}}
        @test result.host == "localhost"
        @test result.port === 8080
    end

    @testset "String macro" begin
        @test ncl"1 + 1" == 2
        @test ncl"true" === true
    end

    @testset "Error handling" begin
        @test_throws NickelError nickel_eval("undefined_variable")
    end
end
