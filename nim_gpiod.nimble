# Package

version       = "0.2.0"
author        = "Takeyoshi Kikuchi"
description   = "Nim libgpiod bindings"
license       = "MIT"
bin           = @["nim_gpiod"]
installFiles  = @["nim_gpiod.nim", "nim_gpiodpkg/libgpiod.nim"]

# Dependencies

requires "nim >= 1.6.12"
