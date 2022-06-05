# Package

version       = "0.1.0"
author        = "George Lemon"
description   = "A simple ORM for poets"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 1.4.8"

task docgen, "Generate API documentation":
    exec "nim doc --project --index:on --outdir:htmldocs src/enimsql.nim"