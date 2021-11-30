#pragma once
#include <webgpu.h>

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

#ifdef __cplusplus
  extern "C" {
#endif

WGPUDevice gui_select_device();
WGPUSurface gui_create_surface();
bool gui_poll();

#ifdef __cplusplus
  }
#endif
