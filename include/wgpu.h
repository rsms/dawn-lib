// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <webgpu.h>

#ifdef __cplusplus
  #define WGPU_API extern "C" __attribute__((visibility("default")))
#else
  #define WGPU_API __attribute__((visibility("default")))
#endif

typedef signed char        i8;
typedef unsigned char      u8;
typedef signed short       i16;
typedef unsigned short     u16;
typedef signed int         i32;
typedef unsigned int       u32;
typedef signed long long   i64;
typedef unsigned long long u64;
typedef signed long        isize;
typedef unsigned long      usize;
typedef float              f32;
typedef double             f64;

WGPU_API WGPUDevice wgpu_select_device();
WGPU_API WGPUSurface wgpu_create_surface();
WGPU_API bool wgpu_surface_poll();
