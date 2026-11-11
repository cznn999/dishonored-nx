// dishonored - ReXGlue Recompiled Project
//
// Stage 1: the recompiled game on the PC with ReXGlue's emulated Xenos GPU.
// Based on the `rexglue init` template; only the default game path is added.

#pragma once

#include <filesystem>
#include <functional>
#include <optional>
#include <string_view>
#include <system_error>

#include <rex/logging.h>
#include <rex/rex_app.h>
#include <rex/runtime.h>
#include <rex/input/device_assignment.h>  // dishonored-nx (2026-10-31): every pad is player 1
#include <rex/input/input_system.h>

#include "me/me_native_system.h"

#include <rex/filesystem.h>

#if defined(DISHONORED_BUILTIN_CONFIG)
#include "dishonored_builtin_config.h"  // generated from dishonored_switch_defaults.toml (CMake)
#endif

#include <rex/platform.h>
#if REX_PLATFORM_SWITCH
#include <rex/cvar.h>
#include <rex/ui/switch_apm.h>

// dishonored-nx (2026-11-11, pure-nx's pure_gpu_boost, renut-nx's banjo_gpu_boost): the official handheld GPU profile.
REXCVAR_DEFINE_BOOL(dishonored_gpu_boost, true, "Dishonored",
                    "Handheld: ask for the official 460.8 MHz GPU profile (memory clock checked unchanged, else "
                    "reverted); docked: nothing")
    .lifecycle(rex::cvar::Lifecycle::kInitOnly);
#endif

#if DISHONORED_RENUT_RENDERER
// Renut's Direct3D-level renderer (src/renut_engine, from reNut by masterspike52 through banjo-nx and sa2-nx), chosen
// at boot with dishonored_renderer = "renut".
#include "dishonored_pgo.h"  // dishonored-nx (2026-11-11): PGO profile collection (DISHONORED_PGO=generate only)
#include "renut_engine/gpu/banjo_renut_select.h"
#include "renut_engine/gpu/overlay/app_integration.h"
#endif

class DishonoredApp : public rex::ReXApp {
 public:
  using rex::ReXApp::ReXApp;

  static std::unique_ptr<rex::ui::WindowedApp> Create(
      rex::ui::WindowedAppContext& ctx) {
    return std::unique_ptr<DishonoredApp>(new DishonoredApp(ctx, "dishonored",
        PPCImageConfig));
  }

  // The Switch build's fixed settings (dishonored_switch_defaults.toml, compiled in): applied before dishonored.toml.
  std::string_view BuiltInConfig() const override {
#if defined(DISHONORED_BUILTIN_CONFIG)
    return kDishonoredBuiltInConfig;
#else
    return {};
#endif
  }
  // Without a dishonored.toml beside the NRO, the player's default one is written there (dishonored_switch.toml).
  std::string_view DefaultConfigFile() const override {
#if defined(DISHONORED_BUILTIN_CONFIG)
    return kDishonoredPlayerConfig;
#else
    return {};
#endif
  }

  // Without --game_data_root the runtime has no game path and stops. Default to the
  // project's assets/game_root (your own extracted disc), so a plain double-click works.
  // --game_data_root=<folder> or game_data_root in dishonored.toml still wins.
  // Stage 2: with dishonored_renderer_native = true the graphics system is the native PM4-ring Vulkan renderer (src/me);
  // the emulated Xenos GPU plugin is then not loaded (ReXApp loads it only when config.graphics is empty).
  // With dishonored_renderer = "renut" there is no SDK graphics system at all: Renut's renderer has its own swapchain
  // and render thread (as sa2-nx's sa2_app.h).
  void OnPreSetup(rex::RuntimeConfig& config) override {
#if REX_PLATFORM_SWITCH
    // dishonored-nx (2026-11-11, pure-nx's pure_app.h): the official handheld GPU profile 0x92220008 (GPU 460.8 MHz,
    // memory 1331.2 MHz, as commercial games ask for it), through the SDK's switch_apm.cpp: it checks the real clocks
    // for 1.5 s that the memory clock did not move, reverts if it did, asks nothing when docked, and logs what it did.
    // No overclock (no sysmodule): Horizon's own API. At 307.2 MHz the GPU took 27-33 ms a frame in the city.
    if (REXCVAR_GET(dishonored_gpu_boost)) {
      RexSwitchApmRequestGpuMhz(460);
      RexSwitchApmApply();
    }
#endif
#if DISHONORED_RENUT_RENDERER
    if (banjo::renut_gpu::Active()) {
      renut::gpu::ConfigureRuntime(config);
      REXLOG_INFO("graphics: Renut's Direct3D-level renderer (dishonored_renderer = renut: no PM4 ring, no EDRAM)");
      return;
    }
#endif
    if (me::native::Enabled()) {
      config.graphics = me::native::CreateGraphicsSystem();
      REXLOG_INFO("graphics: native Vulkan renderer (PM4 ring)");
    }
  }

  // dishonored-nx (2026-10-31): every controller drives guest user 0, the one signed in (the SDK's SharedAssignment).
  // A second pad got user 1, which has no profile: the game asked it to sign in and could not load a save. That pad
  // is sys-botbase's (the test runs of tools/switch_agent.py) next to the console's own controls.
  void OnPostSetup() override {
    if (auto *input = static_cast<rex::input::InputSystem *>(runtime() ? runtime()->input_system() : nullptr)) {
      input->SetDeviceAssignment(std::make_unique<rex::input::SharedAssignment>());
      REXLOG_INFO("input: every controller is player 1");
    }
    // dishonored-nx (2026-11-11): nothing unless the build is the PGO-instrumented one (build_switch_pgo.cmd generate).
    dishonored::pgo::Start();
  }

  // dishonored-nx (2026-11-11): the PGO-instrumented build saves its counts when the game loses focus (HOME menu):
  // the process may be closed from there. Nothing in every other build.
  void OnWindowFocusChanged(bool focused) override {
    rex::ReXApp::OnWindowFocusChanged(focused);
    if (!focused) dishonored::pgo::DumpNow();
  }

#if DISHONORED_RENUT_RENDERER
  // Renut's renderer draws the SDK's menus through its own plume drawer, resizes its swapchain itself, and starts once
  // the window exists (before the game: the paths are final).
  std::unique_ptr<rex::ui::ImmediateDrawer> OnCreateImmediateDrawer() override {
    if (banjo::renut_gpu::Active()) return renut::gpu::CreateOverlayDrawer();
    return rex::ReXApp::OnCreateImmediateDrawer();
  }
  void OnWindowPixelSizeChanged(uint32_t pixel_width, uint32_t pixel_height) override {
    rex::ReXApp::OnWindowPixelSizeChanged(pixel_width, pixel_height);
    if (banjo::renut_gpu::Active()) renut::gpu::OnWindowResized();
  }
  std::optional<rex::PathConfig> OnFinalizePaths(const rex::PathConfig& defaults,
                                                 std::function<void(rex::PathConfig)> resume) override {
    if (banjo::renut_gpu::Active()) renut::gpu::StartRenderer(app_context(), [this] { return imgui_drawer(); });
    return rex::ReXApp::OnFinalizePaths(defaults, std::move(resume));
  }
  void OnShutdown() override {
    if (banjo::renut_gpu::Active()) renut::gpu::ShutdownRenderer();
  }
#endif

  void OnConfigurePaths(rex::PathConfig& paths) override {
    if (!paths.game_data_root.empty()) return;
#ifdef DISHONORED_SOURCE_DIR
    std::filesystem::path guess = std::filesystem::path(DISHONORED_SOURCE_DIR) / "assets" / "game_root";
    if (std::filesystem::is_directory(guess)) {
      paths.game_data_root = guess;
      return;
    }
#endif
    // dishonored-nx (2026-10-29, sa2-nx's sa2_app.h): a game_root/ folder beside the executable or above it (on the
    // Switch sdmc:/switch/dishonored-nx/game_root), or only its asset pack (game_root.nxpack + .nxidx).
    std::error_code ec;
    const auto folder = rex::filesystem::GetExecutableFolder();
    if (folder.empty()) return;
    for (auto candidate = folder; !candidate.empty(); candidate = candidate.parent_path()) {
      for (const auto& sub : {std::filesystem::path("game_root"), std::filesystem::path("assets") / "game_root"}) {
        auto pack = candidate / sub;
        pack += ".nxpack";
        if (std::filesystem::is_regular_file(candidate / sub / "default.xex", ec) ||
            std::filesystem::is_regular_file(pack, ec)) {
          paths.game_data_root = candidate / sub;
          return;
        }
      }
      if (candidate == candidate.parent_path()) break;
    }
  }
};
