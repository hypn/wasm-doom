# CMake >= 3.13 needed for -S and -B params in library compilation.
# CMake >= 3.19 needed for policy CMP0112: target-dependent generator expressions
#               do not implicitly add target-level dependencies.
#
# Note that if you are running Linux, there are many ways to get newer
# versions of CMake.
#
# - Kitware offers binary downloads direct from their website, which you can
#   extract to /usr/local or ~/.local.
# - Ubuntu LTS users can install the CMake snap, and Kitware also runs an
#   official Ubuntu CMake apt repository.
# - Debian users can get a new version through backports.
# - CentOS users can get a new version through EPEL.
# - If you have Python installed, you can install CMake through pip.
#

cmake_minimum_required(VERSION 3.19)

project(Odamex VERSION 12.3.0)

include(CMakeDependentOption)

# CMAKE_INSTALL_BINDIR and CMAKE_INSTALL_DATADIR will be changed if GNUInstallDirs is availible
set(CMAKE_INSTALL_BINDIR "bin")
set(CMAKE_INSTALL_DATADIR "share")
include(GNUInstallDirs OPTIONAL)

# No git commit in the version string: it described Odamex's own repository.
add_definitions(-DODAMEX_NO_GITVER)

add_definitions(-DINSTALL_BINDIR="${CMAKE_INSTALL_BINDIR}")
add_definitions(-DINSTALL_DATADIR="${CMAKE_INSTALL_DATADIR}")

# Set up FHS installation path
if(NOT APPLE AND NOT WIN32)
  add_definitions(-DINSTALL_PREFIX="${CMAKE_INSTALL_PREFIX}")
endif()

# options
#
# This tree builds the browser client (with Emscripten) and the native
# dedicated server.  See build.sh in the repository root.
option(BUILD_CLIENT "Build client target" 1)
option(BUILD_SERVER "Build server target" 1)
option(BUILD_OR_FAIL "Must build the BUILD_* targets or else generation will fail" 0)
option(USE_LTO "Build Release builds with Link Time Optimization" 1)
cmake_dependent_option( USE_INTERNAL_JSONCPP "Use internal JsonCpp" 1 "BUILD_CLIENT OR BUILD_SERVER" 0 )
cmake_dependent_option( USE_INTERNAL_LIBADLMIDI "Use internal libADLMIDI" 1 BUILD_CLIENT 0 )

set(ODAMEX_INSTALL_BINDIR "/usr/local/bin" CACHE PATH "Smart default for bin dir location")
set(ODAMEX_INSTALL_DATADIR "/usr/local/share" CACHE PATH "Smart default for data dir location")

if(NOT APPLE AND NOT WIN32)
  add_definitions(-DODAMEX_INSTALL_BINDIR="${ODAMEX_INSTALL_BINDIR}")
  add_definitions(-DODAMEX_INSTALL_DATADIR="${ODAMEX_INSTALL_DATADIR}")
endif()

set(PROJECT_COPYRIGHT "2006-2026")
set(PROJECT_RC_VERSION "12,3,0,0")
set(PROJECT_COMPANY "The Odamex Team")

# Ensure that we can use folders in projects.
set_property(GLOBAL PROPERTY USE_FOLDERS ON)

# identify the target CPU
# adapted from the FindJNI.cmake module included with the CMake distribution
if(CMAKE_SYSTEM_PROCESSOR STREQUAL "x86_64")
  set(ODAMEX_TARGET_ARCH "amd64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^i[3-9]86$")
  set(ODAMEX_TARGET_ARCH "i386")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^alpha")
  set(ODAMEX_TARGET_ARCH "alpha")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^arm")
  set(ODAMEX_TARGET_ARCH "arm")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(powerpc|ppc)64")
  set(ODAMEX_TARGET_ARCH "ppc64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(powerpc|ppc)")
  set(ODAMEX_TARGET_ARCH "ppc")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^sparc")
  # Both flavors can run on the same processor
  set(ODAMEX_TARGET_ARCH "${CMAKE_SYSTEM_PROCESSOR}" "sparc" "sparcv9")
else()
  set(ODAMEX_TARGET_ARCH "${CMAKE_SYSTEM_PROCESSOR}")
endif()

list(REMOVE_DUPLICATES ODAMEX_TARGET_ARCH)
message(STATUS "Target architecture: ${ODAMEX_TARGET_ARCH}")

# Default build type
if(NOT CMAKE_CONFIGURATION_TYPES)
  if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE RelWithDebInfo)
  endif()
  message(STATUS "Build Type: ${CMAKE_BUILD_TYPE}")
  set(CMAKE_BUILD_TYPE "${CMAKE_BUILD_TYPE}" CACHE STRING
    "Choose the type of build, options are: None Debug Release RelWithDebInfo MinSizeRel."
    FORCE)
endif()

if(NOT CMAKE_EXPORT_COMPILE_COMMANDS)
  # Export compile commands unless we're generating a modern project.
  if(CMAKE_GENERATOR MATCHES "Make" OR CMAKE_GENERATOR MATCHES "Ninja")
    set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
  else()
    set(CMAKE_EXPORT_COMPILE_COMMANDS OFF)
  endif()
endif()
message(STATUS "Export Compile Commands: ${CMAKE_EXPORT_COMPILE_COMMANDS}")
set(CMAKE_EXPORT_COMPILE_COMMANDS "${CMAKE_EXPORT_COMPILE_COMMANDS}" CACHE BOOL
  "Export compile commands for use in supported editors."
  FORCE)

# Global compile options as shown in a GUI.
option(USE_SANITIZE_ADDRESS "Turn on Address Sanitizer in Debug builds." OFF)
if(NOT MSVC)
  option(USE_COLOR_DIAGNOSTICS "Force the use of color diagnostics, necessary to get color output with Ninja." ON)
  option(USE_STATIC_STDLIB "Statically link against the C and C++ Standard Library." OFF)
  option(USE_SANITIZE_THREAD "Turn on Thread Sanitizer in Debug builds." OFF)
  if(USE_SANITIZE_ADDRESS AND USE_SANITIZE_THREAD)
    message(FATAL_ERROR "USE_SANITIZE_ADDRESS and USE_SANITIZE_THREAD are mutually exclusive options.")
  endif()
  option(USE_SANITIZE_UNDEFINED "Turn on Undefined Behavior Sanitizer in Debug builds." OFF)
endif()

if(${CMAKE_SYSTEM_NAME} MATCHES SunOS )
  set(SOLARIS 1)
endif()

if(USE_LTO)
  include(CheckIPOSupported)
  check_ipo_supported(RESULT HAS_LTO OUTPUT HAS_LTO_ERROR)
  if(HAS_LTO)
    message(STATUS "Link Time Optimization: ON")
  else()
    message(STATUS "Link Time Optimization: OFF")
  endif()
endif()

set(CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake/modules)

# Emscripten only searches its sysroot, so let it see the libraries we build.
if(EMSCRIPTEN)
  list(APPEND CMAKE_FIND_ROOT_PATH "${CMAKE_BINARY_DIR}/libraries")
endif()

# Libraries
add_subdirectory(libraries)

# Subdirectories for Odamex projects
add_subdirectory(common)
add_subdirectory(odaproto)
if(BUILD_CLIENT)
  add_subdirectory(client)
endif()
if(BUILD_SERVER)
  add_subdirectory(server)
endif()
if(NOT BUILD_CLIENT AND NOT BUILD_SERVER)
  message(FATAL_ERROR "No target chosen, doing nothing.")
endif()

# The engine's built-in resources
add_subdirectory(wad)
