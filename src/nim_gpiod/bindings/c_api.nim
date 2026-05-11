import std/os

const shimDir = currentSourcePath().parentDir().parentDir() / "shim"

{.passC: "-I" & shimDir.}
{.compile: shimDir / "ngpio.c".}

import ./generated/ngpio

export ngpio
