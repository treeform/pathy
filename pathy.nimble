version     = "0.0.1"
author      = "treeform"
description = "Pathfinding spaces for Nim."
license     = "MIT"

srcDir = "src"

requires "nim >= 2.0.0"
requires "benchy >= 0.0.1"
requires "pixie >= 5.1.0"

task test, "Runs the test suite":
  exec "nim check src/pathy.nim"
  exec "nim r tests/tests.nim"

task bench, "Runs the benchmark suite":
  exec "nim r tests/bench_pathy.nim"

task images, "Generates README images":
  exec "nim r tools/gen_readme.nim"
