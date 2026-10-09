# The engine's resources are compiled into the executable rather than shipped
# as a WAD.  resources.wad is Odamex 12.3.0's odamex.wad trimmed to what Doom 1
# needs (see README.md); embed.cmake turns it into C++.
set(BUILTIN_WAD "${CMAKE_CURRENT_SOURCE_DIR}/resources.wad")
set(BUILTIN_SOURCE "${CMAKE_CURRENT_BINARY_DIR}/builtin_resources.cpp")

add_custom_command(
  OUTPUT "${BUILTIN_SOURCE}"
  COMMAND "${CMAKE_COMMAND}" -D "INPUT=${BUILTIN_WAD}" -D "OUTPUT=${BUILTIN_SOURCE}"
          -P "${CMAKE_CURRENT_SOURCE_DIR}/embed.cmake"
  DEPENDS "${BUILTIN_WAD}" "${CMAKE_CURRENT_SOURCE_DIR}/embed.cmake"
  VERBATIM)

# Linked by odamex-common, so the client and server both get it.
add_library(odamex-builtin STATIC "${BUILTIN_SOURCE}")
