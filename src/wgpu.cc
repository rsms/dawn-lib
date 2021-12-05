// SPDX-License-Identifier: Apache-2.0
#include "../include/wgpu.h"

#include <dawn/webgpu_cpp.h>
#include <dawn/dawn_proc.h>
#include <dawn_native/DawnNative.h>

#if defined(__linux__)
  // no <GL/gl.h>
  #define GLFW_INCLUDE_NONE
  #define GLFW_INCLUDE_VULKAN
#endif
#include <GLFW/glfw3.h>
//#include <utils/GLFWUtils.h> /* from dawn */

#if defined(WIN32)
  #define GLFW_EXPOSE_NATIVE_WIN32
#elif defined(__linux__)
  #define GLFW_EXPOSE_NATIVE_X11
#endif
#include "GLFW/glfw3native.h"

#include <memory> // unique_ptr
#include <vector>
#include <unistd.h>
#include <assert.h>
#include <stdio.h>


#ifdef DEBUG
  #define dlog(format, ...) ({ \
    fprintf(stderr, format " \e[2m(%s %d)\e[0m\n", ##__VA_ARGS__, __FUNCTION__, __LINE__); \
    fflush(stderr); \
  })
  static const char* backend_type_name(wgpu::BackendType);
  static const char* adapter_type_name(wgpu::AdapterType);
#else
  #define dlog(...) do{}while(0)
#endif


// kBackendType -- Dawn backend type.
// Default to D3D12, Metal, Vulkan, OpenGL in that order as D3D12 and Metal are the
// preferred on their respective platforms, and Vulkan is preferred to OpenGL
static const wgpu::BackendType kBackendType =
#if defined(DAWN_ENABLE_BACKEND_D3D12)
  wgpu::BackendType::D3D12;
#elif defined(DAWN_ENABLE_BACKEND_METAL)
  wgpu::BackendType::Metal;
#elif defined(DAWN_ENABLE_BACKEND_VULKAN)
  wgpu::BackendType::Vulkan;
#elif defined(DAWN_ENABLE_BACKEND_OPENGL)
  wgpu::BackendType::OpenGL;
#else
#  error
#endif
;

static GLFWwindow*           gWindow;
static DawnProcTable         gNativeProcs;
// static dawn_native::Instance gDawnNative;
static dawn_native::Instance* gDawnNative = nullptr;
static struct {
  u32   width, height;
  float dpscale;
} gFramebuffer;


#if !defined(__APPLE__)
static
#endif
std::unique_ptr<wgpu::ChainedStruct> surf_wgpu_descriptor(GLFWwindow*);


static void report_glfw_error(int code, const char* message) {
  fprintf(stderr, "GLFW error: [%d] %s\n", code, message);
}

static void init() {
  static bool initialized = false;
  if (initialized)
    return;
  initialized = true;

  glfwInit();
  glfwSetErrorCallback(report_glfw_error);
  dlog("GLFW %s", glfwGetVersionString());

  // Set up the native procs for the global proctable
  gNativeProcs = dawn_native::GetProcs();
  dawnProcSetProcs(&gNativeProcs);
  gDawnNative = new dawn_native::Instance();
  gDawnNative->DiscoverDefaultAdapters();
  gDawnNative->EnableBackendValidation(true);
  gDawnNative->SetBackendValidationLevel(dawn_native::BackendValidationLevel::Full);
}


static dawn_native::Adapter select_adapter() {
  // search available adapters for a good match, in the following priority order:
  const std::vector<wgpu::AdapterType> typePriority = (
    // force software
    // std::vector<wgpu::AdapterType>{
    //   wgpu::AdapterType::CPU,
    // }

    // low power
    std::vector<wgpu::AdapterType>{
      wgpu::AdapterType::IntegratedGPU,
      wgpu::AdapterType::DiscreteGPU,
      wgpu::AdapterType::CPU,
    }

    // // high performance
    // std::vector<wgpu::AdapterType>{
    //   wgpu::AdapterType::DiscreteGPU,
    //   wgpu::AdapterType::IntegratedGPU,
    //   wgpu::AdapterType::CPU,
    // }
  );

  std::vector<dawn_native::Adapter> adapters = gDawnNative->GetAdapters();

  for (auto reqType : typePriority) {
    for (const dawn_native::Adapter& adapter : adapters) {
      wgpu::AdapterProperties ap;
      adapter.GetProperties(&ap);
      if (ap.adapterType == reqType &&
          (reqType == wgpu::AdapterType::CPU || ap.backendType == kBackendType) )
      {
        dlog("selected adapter %s (device=0x%x vendor=0x%x type=%s/%s)",
          ap.name, ap.deviceID, ap.vendorID,
          adapter_type_name(ap.adapterType), backend_type_name(ap.backendType));
        return adapter;
      }
    }
  }

  return nullptr;
}


static void surf_update_fbsize() {
  float yscale = 1.0;
  glfwGetFramebufferSize(gWindow, (int*)&gFramebuffer.width, (int*)&gFramebuffer.height);
  glfwGetWindowContentScale(gWindow, &gFramebuffer.dpscale, &yscale);
}


// onFramebufferResize is called when a window's framebuffer has changed size.
// width & height are in pixels (the framebuffer size)
static void onFramebufferResize(GLFWwindow* window, int width, int height) {
  surf_update_fbsize();
}


WGPUDevice wgpu_select_device() {
  init();
  static dawn_native::Adapter adapter; // FIXME: match lifetime of device
  adapter = select_adapter();
  if (!adapter)
    return nullptr;
  return adapter.CreateDevice();
}


WGPUSurface wgpu_create_surface() {
  init();

  glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
  gWindow = glfwCreateWindow(400, 300, "hello_triangle", NULL, NULL);
  if (!gWindow)
    return nullptr;
  surf_update_fbsize();
  glfwSetFramebufferSizeCallback(gWindow, onFramebufferResize);

  std::unique_ptr<wgpu::ChainedStruct> sd1 = surf_wgpu_descriptor(gWindow);
  wgpu::SurfaceDescriptor descriptor;
  descriptor.nextInChain = sd1.get();
  wgpu::Surface surface = wgpu::Instance(gDawnNative->Get()).CreateSurface(&descriptor);
  if (!surface)
    return nullptr;
  WGPUSurface surf = surface.Get();
  wgpuSurfaceReference(surf);
  return surf;
}

bool wgpu_surface_poll() {
  if (glfwWindowShouldClose(gWindow))
    return false;
  glfwWaitEvents();
  return true;
}


#ifdef DEBUG
  static const char* backend_type_name(wgpu::BackendType t) {
    switch (t) {
      case wgpu::BackendType::Null:     return "Null";
      case wgpu::BackendType::WebGPU:   return "WebGPU";
      case wgpu::BackendType::D3D11:    return "D3D11";
      case wgpu::BackendType::D3D12:    return "D3D12";
      case wgpu::BackendType::Metal:    return "Metal";
      case wgpu::BackendType::Vulkan:   return "Vulkan";
      case wgpu::BackendType::OpenGL:   return "OpenGL";
      case wgpu::BackendType::OpenGLES: return "OpenGLES";
    }
    return "?";
  }
  static const char* adapter_type_name(wgpu::AdapterType t) {
    switch (t) {
      case wgpu::AdapterType::DiscreteGPU:   return "DiscreteGPU";
      case wgpu::AdapterType::IntegratedGPU: return "IntegratedGPU";
      case wgpu::AdapterType::CPU:           return "CPU";
      case wgpu::AdapterType::Unknown:       return "Unknown";
    }
    return "?";
  }
#endif // defined(DEBUG)


#if defined(WIN32)
  static std::unique_ptr<wgpu::ChainedStruct> surf_wgpu_descriptor(GLFWwindow* win) {
    std::unique_ptr<wgpu::SurfaceDescriptorFromWindowsHWND> desc =
      std::make_unique<wgpu::SurfaceDescriptorFromWindowsHWND>();
    desc->hwnd = glfwGetWin32Window(win);
    desc->hinstance = GetModuleHandle(nullptr);
    return std::move(desc);
  }
#elif defined(__linux__) // X11
  static std::unique_ptr<wgpu::ChainedStruct> surf_wgpu_descriptor(GLFWwindow* win) {
    std::unique_ptr<wgpu::SurfaceDescriptorFromXlib> desc =
      std::make_unique<wgpu::SurfaceDescriptorFromXlib>();
    desc->display = glfwGetX11Display();
    desc->window = glfwGetX11Window(win);
    return std::move(desc);
  }
#elif defined(__APPLE__)
  // implemented in wgpu_metal.mm
#else
  #warning unknown wgpu backend implementation
  static std::unique_ptr<wgpu::ChainedStruct> surf_wgpu_descriptor(GLFWwindow* win) {
    return nullptr;
  }
#endif
