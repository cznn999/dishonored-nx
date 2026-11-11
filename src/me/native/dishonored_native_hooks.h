// SA2 - native renderer: access to the shader library the native graphics system has loaded.

#pragma once

namespace dishonored::native {

class ShadersNative;

// The library the native graphics system loaded (nullptr until then), from any thread. Used for pipeline
// prewarming (dishonored_native_draws.cpp).
const ShadersNative* ActiveLibrary();

}  // namespace dishonored::native
