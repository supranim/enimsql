# Package

version       = "0.1.0"
author        = "George Lemon"
description   = "A fancy ORM for poets. From compile-time to runtime"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 1.6.12"
requires "db_connector"
requires "flatty"

task dev, "Build a dev version":
  exec "nim --mm:arc --out:bin/enimsql --hints:off --threads:off c src/enimsql.nim"