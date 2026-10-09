# Writes resources.wad out as C++ source, so the engine's resources are
# compiled into the executable instead of shipping as a separate WAD.
#
# Usage: cmake -D INPUT=resources.wad -D OUTPUT=builtin_resources.cpp -P embed.cmake

file(READ "${INPUT}" hex HEX)
file(SIZE "${INPUT}" size)

# One "0xNN," per byte, 24 bytes per line.
string(REGEX REPLACE "([0-9a-f][0-9a-f])" "0x\\1," bytes "${hex}")
string(REGEX REPLACE "((0x..,)(0x..,)(0x..,)(0x..,)(0x..,)(0x..,)(0x..,)(0x..,)(0x..,)(0x..,)(0x..,)(0x..,)(0x..,)(0x..,)(0x..,)(0x..,)(0x..,)(0x..,)(0x..,)(0x..,)(0x..,)(0x..,)(0x..,)(0x..,))" "\\1\n\t" bytes "${bytes}")

file(WRITE "${OUTPUT}" "// Generated from wad/resources.wad by wad/embed.cmake - do not edit.

#include <cstddef>

extern const unsigned char W_BuiltinResources[];
extern const size_t W_BuiltinResourcesSize;

const unsigned char W_BuiltinResources[] = {
\t${bytes}
};

const size_t W_BuiltinResourcesSize = ${size};
")
