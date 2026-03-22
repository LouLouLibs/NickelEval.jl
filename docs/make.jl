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
    checkdocs = :exports,
    authors = "LouLouLibs Contributors",
    pages = [
        "Home" => "index.md",
        "Quick Examples" => "man/examples.md",
        "Detailed Examples" => "man/detailed.md",
        "Lazy Evaluation" => "man/lazy.md",
        "API Reference" => "lib/public.md",
    ]
)

DocumenterVitepress.deploydocs(;
    repo = "github.com/LouLouLibs/NickelEval.jl",
    target = "build",
    devbranch = "main",
    branch = "gh-pages",
    push_preview = true,
)
