#!/usr/bin/env julia

using NickelEval
using Documenter
using DocumenterVitepress

makedocs(
    format = MarkdownVitepress(
        repo = "https://github.com/LouLouLibs/NickelEval.jl",
    ),
    repo = Remotes.GitHub("LouLouLibs", "NickelEval.jl"),
    sitename = "NickelEval.jl",
    modules  = [NickelEval],
    authors = "LouLouLibs Contributors",
    pages = [
        "Home" => "index.md",
        "Manual" => [
            "man/quickstart.md",
            "man/typed.md",
            "man/export.md",
            "man/ffi.md",
        ],
        "Library" => [
            "lib/public.md",
        ]
    ]
)

DocumenterVitepress.deploydocs(;
    repo = "github.com/LouLouLibs/NickelEval.jl",
    target = "build",
    devbranch = "main",
    branch = "gh-pages",
    push_preview = true,
)
