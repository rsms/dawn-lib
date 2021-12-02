cmake_minimum_required(VERSION 3.10)
set_property(GLOBAL PROPERTY USE_FOLDERS ON)
project(wgpu)

# make sure we use llvm's libc++ for any C++ linking
add_link_options(
  $<$<COMPILE_LANGUAGE:CXX>:-stdlib=libc++>
  $<$<COMPILE_LANGUAGE:OBJCXX>:-stdlib=libc++>
)

# customize dawn cmake options (must include "CACHE TYPE DESCRIPTION")
set(TINT_BUILD_SAMPLES     OFF CACHE BOOL "customize dawn build")
set(TINT_BUILD_GLSL_WRITER OFF CACHE BOOL "customize dawn build")
set(TINT_BUILD_HLSL_WRITER OFF CACHE BOOL "customize dawn build")
set(TINT_BUILD_MSL_WRITER  OFF CACHE BOOL "customize dawn build")
set(DAWN_ENABLE_DESKTOP_GL OFF CACHE BOOL "customize dawn build")
set(DAWN_ENABLE_OPENGLES   OFF CACHE BOOL "customize dawn build")
set(DAWN_BUILD_EXAMPLES    OFF CACHE BOOL "customize dawn build")
set(DAWN_ENABLE_PIC        ON CACHE BOOL "customize dawn build")

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Debug)
endif()

add_subdirectory(../dawn dawn EXCLUDE_FROM_ALL)
set(DAWN_BINARY_DIR ${CMAKE_CURRENT_BINARY_DIR}/dawn)

set(PWGPU_C_FLAGS
  -std=c11
)
set(PWGPU_CXX_FLAGS
  -std=gnu++14
  -fno-rtti
  -fno-exceptions
  -Wno-narrowing
  -Wno-non-virtual-dtor
)
set(PWGPU_COMPILE_OPTIONS
  -g
  -Wall -Wextra
  -Wvla
  -Wimplicit-fallthrough
  -Wno-missing-field-initializers
  -Wno-unused-parameter
  -Werror=implicit-function-declaration
  -Wunused
  -fcolor-diagnostics
  -fvisibility=hidden
  -fPIC

  $<$<COMPILE_LANGUAGE:C>:${PWGPU_C_FLAGS}>
  $<$<COMPILE_LANGUAGE:OBJC>:${PWGPU_C_FLAGS}>
  $<$<COMPILE_LANGUAGE:CXX>:${PWGPU_CXX_FLAGS}>
  $<$<COMPILE_LANGUAGE:OBJCXX>:${PWGPU_CXX_FLAGS}>
)
set(PWGPU_COMPILE_DEFS)
if (${CMAKE_BUILD_TYPE} MATCHES "Debug")
  set(PWGPU_COMPILE_DEFS ${PWGPU_COMPILE_DEFS} DEBUG=1)
  set(PWGPU_COMPILE_OPTIONS ${PWGPU_COMPILE_OPTIONS} -O0)
else()
  set(PWGPU_COMPILE_OPTIONS ${PWGPU_COMPILE_OPTIONS} -O3 -march=native)
  set(PWGPU_COMPILE_DEFS ${PWGPU_COMPILE_DEFS} PWGPU_DAWN_DISABLE_VALIDATION=1)
endif()

add_library(wgpu1 STATIC wgpu.cc)
target_compile_definitions(wgpu1 PRIVATE ${PWGPU_COMPILE_DEFS} PWGPU_STATIC_LIB=1)
target_compile_options(wgpu1 PRIVATE ${PWGPU_COMPILE_OPTIONS})
target_include_directories(wgpu1
  PRIVATE
    ${DAWN_BINARY_DIR}/gen/src/include/dawn # <webgpu.h>
)
target_link_libraries(wgpu1
  PRIVATE
    dawncpp
    dawn_proc
    dawn_common
    dawn_platform
    dawn_native
    dawn_utils
    dawn_internal_config  # for definitions DAWN_ENABLE_BACKEND_*
    glm
    glfw
)

add_custom_command(TARGET wgpu1 POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy
    ${DAWN_BINARY_DIR}/gen/src/include/dawn/webgpu.h
    ${CMAKE_CURRENT_SOURCE_DIR}/../include/webgpu.h
)
