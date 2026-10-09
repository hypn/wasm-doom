include(OdamexTargetSettings)

# The client only builds for the browser, with Emscripten: see ../build.sh.
if(NOT EMSCRIPTEN)
  message(FATAL_ERROR "The client builds for the browser only; configure it with emcmake (see build.sh).")
endif()

# use unquoted #defines
cmake_policy(SET CMP0005 NEW)

# #define CLIENT_APP for use in the source code
add_definitions(-DCLIENT_APP)

file(GLOB CLIENT_SOURCES src/*.cpp src/*.h)
file(GLOB CLIENT_SDL_SOURCES sdl/*.cpp sdl/*.h)
get_target_property(COMMON_SOURCES odamex-common INTERFACE_SOURCES)

source_group("Client" FILES ${CLIENT_SOURCES})
source_group("Common" FILES ${COMMON_SOURCES})
source_group("SDL" FILES ${CLIENT_SDL_SOURCES})

include_directories(sdl src)

# Textscreen
set(TEXTSCREEN_DIR ../libraries/textscreen)
include_directories(${TEXTSCREEN_DIR})
add_library(textscreen STATIC
  ${TEXTSCREEN_DIR}/txt_sdl.cpp ${TEXTSCREEN_DIR}/txt_sdl.h ${TEXTSCREEN_DIR}/txt_main.h)
target_include_directories(textscreen PRIVATE ../common)
target_link_libraries(textscreen SDL2::SDL2)

# Client target
add_executable(odamex ${CLIENT_SOURCES} ${CLIENT_SDL_SOURCES} ${COMMON_SOURCES})
odamex_target_settings(odamex)

target_link_libraries(odamex textscreen odamex-common odaproto tinylibs
  SDL2::SDL2 SDL2::mixer jsoncpp_static ZLIB::ZLIB PNG::PNG fmt::fmt minilzo
  libADLMIDI::ADLMIDI_static curl_interface)

# Emit odamex.js + odamex.wasm for web/index.html to load.  The game files are
# fetched by the page and written to /data before main().
set_target_properties(odamex PROPERTIES SUFFIX ".js")
target_link_options(odamex PRIVATE
  -sMODULARIZE=1
  -sEXPORT_NAME=createOdamex
  -sINVOKE_RUN=0
  -sEXIT_RUNTIME=0
  -sALLOW_MEMORY_GROWTH=1
  -sINITIAL_MEMORY=128MB
  -sSTACK_SIZE=1MB
  -sFORCE_FILESYSTEM=1
  -sEXPORTED_RUNTIME_METHODS=FS,callMain
  -lidbfs.js)

if(BUILD_OR_FAIL AND NOT TARGET odamex)
  message(FATAL_ERROR "Odamex target could not be generated")
endif()
