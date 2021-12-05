#ifndef DAWN_ENABLE_BACKEND_METAL
#error !DAWN_ENABLE_BACKEND_METAL
#endif

#include <memory>
#include <dawn/webgpu_cpp.h>
#include <QuartzCore/CAMetalLayer.h>
#include <GLFW/glfw3.h>
#define GLFW_EXPOSE_NATIVE_COCOA
#include <GLFW/glfw3native.h>

std::unique_ptr<wgpu::ChainedStruct> surf_wgpu_descriptor(GLFWwindow* win) {
  NSWindow* nswin = glfwGetCocoaWindow(win);
  NSView* view = [nswin contentView];

  [view setWantsLayer:YES];
  [view setLayer:[CAMetalLayer layer]];
  [[view layer] setContentsScale:[nswin backingScaleFactor]];

  std::unique_ptr<wgpu::SurfaceDescriptorFromMetalLayer> desc =
      std::make_unique<wgpu::SurfaceDescriptorFromMetalLayer>();
  desc->layer = [view layer];
  return std::move(desc);
}

// HERE BE DRAGONS!
// On macos dawn/src/dawn_native/metal/ShaderModuleMTL.mm uses the @available ObjC
// feature which expects a runtime symbol that is AFAIK only provided by Apple's
// version of clang.
// extern "C"
extern "C" int __isPlatformVersionAtLeast(
  long unkn, long majv, long minv, long buildv)
{
  // <= 10.15.x
  return majv < 10 || (majv == 10 && minv <= 15);
}
