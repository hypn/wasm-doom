file(GLOB COMMON_HEADERS *.h)
file(GLOB COMMON_SOURCES *.cpp)

add_library(odamex-common INTERFACE)
target_sources(odamex-common INTERFACE ${COMMON_SOURCES} ${COMMON_HEADERS})
target_include_directories(odamex-common INTERFACE . ${CMAKE_CURRENT_BINARY_DIR})

# The engine's built-in resources, generated in wad/.
target_link_libraries(odamex-common INTERFACE odamex-builtin)

if(UNIX)
  include(CheckSymbolExists)
  check_symbol_exists(backtrace "execinfo.h" HAVE_BACKTRACE)

  if(HAVE_BACKTRACE)
    target_compile_definitions(odamex-common INTERFACE HAVE_BACKTRACE)
  endif()
endif()
