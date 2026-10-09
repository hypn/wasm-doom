include(OdamexTargetSettings)

if(EMSCRIPTEN)
  # The cross-compiled protobuf has no protoc, so use a native one of the
  # same version (3.21.1).
  set(ODAMEX_HOST_PROTOC "" CACHE FILEPATH "Native protoc for cross builds")
  if(NOT ODAMEX_HOST_PROTOC)
    message(FATAL_ERROR "Set ODAMEX_HOST_PROTOC to a native protoc 3.21.1")
  endif()
  add_executable(protobuf::protoc IMPORTED)
  set_target_properties(protobuf::protoc PROPERTIES
    IMPORTED_LOCATION "${ODAMEX_HOST_PROTOC}")
endif()

# Find the protobuf we just compiled
find_package(protobuf
  PATHS
    "${CMAKE_CURRENT_BINARY_DIR}/../libraries/protobuf-build/cmake"
    "${CMAKE_CURRENT_BINARY_DIR}/../libraries/protobuf-build/lib/cmake/protobuf"
    "${CMAKE_CURRENT_BINARY_DIR}/../libraries/protobuf-build/lib64/cmake/protobuf"
  NO_DEFAULT_PATH)

set(ODAPROTO_PROTOS common.proto server.proto)

protobuf_generate(OUT_VAR ODAPROTO_SOURCES PROTOS ${ODAPROTO_PROTOS})

source_group("Definitions" FILES ${ODAPROTO_PROTOS})
source_group("Generated" FILES ${ODAPROTO_SOURCES})

add_library(odaproto STATIC ${ODAPROTO_SOURCES} ${ODAPROTO_PROTOS})
odamex_target_settings(odaproto)
target_include_directories(odaproto PUBLIC "${CMAKE_CURRENT_BINARY_DIR}")
target_link_libraries(odaproto protobuf::libprotobuf)

if(MSVC)
  # https://developercommunity.visualstudio.com/t/Visual-Studio-1740-no-longer-compiles-/10193665
  target_compile_definitions(odaproto PUBLIC "_SILENCE_STDEXT_HASH_DEPRECATION_WARNINGS")
endif()
