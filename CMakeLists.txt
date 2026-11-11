# dishonored - ReXGlue Recompiled Project
#
# SDK boilerplate lives in generated/rexglue.cmake.

cmake_minimum_required(VERSION 3.25)
project(dishonored LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Switch (devkitA64 GCC): no AArch64 early register allocation pass (sa2-nx: it miscompiled table lookups of the
# XDK's streaming copy on the console). Before the SDK is added, so its libraries get it too.
if(REXGLUE_PLATFORM_SWITCH)
    add_compile_options(-mearly-ra=none)
    add_link_options(-mearly-ra=none)
endif()

include(generated/rexglue.cmake)

# Sources
set(DISHONORED_SOURCES
    src/main.cpp
    # Stage 2: the native PM4-ring Vulkan renderer (src/me, from sa2-nx / masseffect-nx / banjo-nx). Off by default;
    # dishonored_renderer_native = true in dishonored.toml switches it on instead of the emulated Xenos GPU.
    src/me/me_native_system.cpp
    src/me/me_ring_wait.cpp
    src/me/me_renderdoc.cpp
    src/me/native/dishonored_native_draws.cpp
    src/me/native/dishonored_deferred_recording.cpp
    src/me/native/dishonored_native_targets.cpp
    src/me/native/dishonored_native_shaders.cpp
    src/me/native/dishonored_native_textures_pool.cpp
    src/me/native/dishonored_shader_library.cpp
    src/me/native/dishonored_native_glue.cpp
    src/me/dishonored_render_mode.cpp
    src/cpu/dishonored_enhancements.cpp
    # dishonored-nx (2026-10-30): localized copies of the hot Wwise functions (src/cpu/dishonored_hot_wwise.cpp), left
    # out since the optimised codegen (2026-11-11): they are code of the old generator, which keeps r14-r31 in ctx,
    # where the new one's callers keep them in locals (non_volatile_as_local).
    # dishonored-nx (2026-11-11): whether the generated code marks the store cards (tools/store_cards.py): Renut then
    # proves its cached copies by the cards instead of hashing them whole (pure-nx's src/pure_store_cards.cpp).
    src/dishonored_store_cards.cpp
    # src/cpu/dishonored_hot_render.cpp: the rendering thread's 62 copies, left out (2026-10-31): little gain (the
    # thread 86 -> 83 %) and objects drew black at a distance until near.
    # Dishonored's Direct3D addresses for the renderer (notes/d3d-census.md) and the stubs of sa2-nx-only parts.
    src/dishonored_me_hooks.cpp
    src/dishonored_me_stubs.cpp
    # src/d3d_census.cpp (the census of every Direct3D function the Renut addresses came from) and src/d3d_probe.cpp
    # hook the same functions as the renderers, so they are left out of this build.
    # What Renut's renderer takes from sa2-nx's app (game frame count, recorder hooks, store cards).
    src/dishonored_renut_compat.cpp
    # dishonored-nx (2026-11-11, pure-nx's src/pure_native.cpp): native replacements of hot guest leaf functions.
    src/dishonored_native.cpp
    # dishonored-nx (2026-11-11): PGO profile collection (DISHONORED_PGO=generate; empty otherwise). pure-nx's.
    src/dishonored_pgo.cpp
)
if(NOT REXGLUE_PLATFORM_SWITCH)
    list(APPEND DISHONORED_SOURCES src/me/me_pc_stubs.cpp)
endif()

if(WIN32)
    add_executable(dishonored WIN32 ${DISHONORED_SOURCES})
else()
    add_executable(dishonored ${DISHONORED_SOURCES})
endif()

rexglue_setup_target(dishonored GPU_PLUGINS xenos)
# An emulator (Ryujinx) starts NROs without argv[0]: the SDK then takes the NRO's usual place on the SD for its folder.
if(REXGLUE_PLATFORM_SWITCH AND TARGET rexcore)
    target_compile_definitions(rexcore PRIVATE REX_SWITCH_FALLBACK_EXE="/switch/dishonored-nx/dishonored.nro")
endif()

# Stage 2: Renut's Direct3D-level renderer (src/renut_engine; cmake/dishonored_renut_gpu.cmake), chosen at boot with
# dishonored_renderer = "renut". Needs sa2-nx's app folder (its third-party code) and renut_shaders/.
option(DISHONORED_RENUT_RENDERER "Link Renut's Direct3D-level renderer (dishonored_renderer = renut)" ON)
if(DISHONORED_RENUT_RENDERER)
    include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/dishonored_renut_gpu.cmake")
endif()

# The renderer's includes: its own folders, the precompiled SPIR-V of its EDRAM / utility shaders
# (src/me/native/generated-shaders, made with glslangValidator from src/me/native/shaders; SPIR-V is the same on every
# platform), SDK internals and the presenter's SPIR-V it draws into.
target_include_directories(dishonored PRIVATE
    src
    src/me
    src/me/native
    src/me/native/shaders
    src/me/native/generated-shaders
    "${REXSDK_DIR}/src/core"
    "${REXSDK_DIR}/src/ui/shaders")
# CPU-only SDK sources the renderer reuses (draw-extent estimation, shader microcode interpretation): the GPU plugin's
# private symbols cannot satisfy application-side use.
target_sources(dishonored PRIVATE
    "${REXSDK_DIR}/src/graphics/register_file.cpp"
    "${REXSDK_DIR}/src/graphics/format/ucode.cpp"
    "${REXSDK_DIR}/src/graphics/pipeline/shader/interpreter.cpp")
foreach(_dep xxhash renderdoc)
    if(TARGET ${_dep})
        target_include_directories(dishonored PRIVATE $<TARGET_PROPERTY:${_dep},INTERFACE_INCLUDE_DIRECTORIES>)
    endif()
endforeach()
# As sa2-nx: no FMA contraction and no strict aliasing for recompiled code (rounding like the Xbox 360).
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    foreach(_t dishonored dishonored_recomp)
        if(TARGET ${_t})
            target_compile_options(${_t} PRIVATE -ffp-contract=off -fno-strict-aliasing)
        endif()
    endforeach()
endif()

# Default game path for DishonoredApp::OnConfigurePaths (assets/game_root of this project).
if(NOT REXGLUE_PLATFORM_SWITCH)
    target_compile_definitions(dishonored PRIVATE DISHONORED_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
endif()

# Settings next to the executable (gpu_plugin = "xenos" etc.), only when there is none yet.
if(NOT REXGLUE_PLATFORM_SWITCH)
add_custom_command(TARGET dishonored POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -DSRC=${CMAKE_CURRENT_SOURCE_DIR}/dishonored.toml -DDST=$<TARGET_FILE_DIR:dishonored>/dishonored.toml
            -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/copy_if_missing.cmake"
    VERBATIM)
endif()

# dishonored-nx (2026-10-29): the Nintendo Switch NRO (sa2-nx's app/CMakeLists.txt, Switch part), built by
# build_switch.cmd. Renut on deko3d; LTO (build_switch.cmd with LTO=1) and PGO (build_switch_pgo.cmd) below.
if(REXGLUE_PLATFORM_SWITCH)
    # The register file is one generated function of tens of thousands of SetFunction calls run once at start:
    # -O0 compiles it in seconds (GCC -O3 spent a quarter of an hour on SA2's).
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/generated/default/dishonored_register.cpp")
        set_property(SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/generated/default/dishonored_register.cpp"
                     APPEND PROPERTY COMPILE_OPTIONS -O0)
    endif()
    # dishonored-nx (2026-11-11, pure-nx's): the same for dishonored_init.cpp, a table of the function pointers
    # (PPCFuncMappings): at -O3 cc1plus ran out of memory on Pure's beside the game files of a full rebuild.
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/generated/default/dishonored_init.cpp")
        set_property(SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/generated/default/dishonored_init.cpp"
                     APPEND PROPERTY COMPILE_OPTIONS -O0)
    endif()
    # The game code without the x29 frame chain and without the errno check of sqrt (sa2-nx's defaults).
    if(TARGET dishonored_recomp)
        target_compile_options(dishonored_recomp PRIVATE -fomit-frame-pointer -fno-math-errno)
    endif()
    target_compile_definitions(dishonored PRIVATE XXH_FORCE_MEMORY_ACCESS=0)
    # The built-in settings (dishonored_switch_defaults.toml) and the player's dishonored.toml written beside the NRO
    # when there is none (dishonored_switch.toml).
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/dishonored_switch_defaults.toml" DISHONORED_BUILTIN_CONFIG)
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/dishonored_switch.toml" DISHONORED_PLAYER_CONFIG)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/dishonored_switch_defaults.toml" "${CMAKE_CURRENT_SOURCE_DIR}/dishonored_switch.toml")
    configure_file("${CMAKE_CURRENT_SOURCE_DIR}/src/dishonored_builtin_config.h.in"
                   "${CMAKE_CURRENT_BINARY_DIR}/builtin_config/dishonored_builtin_config.h" @ONLY)
    target_include_directories(dishonored PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/builtin_config")
    target_compile_definitions(dishonored PRIVATE DISHONORED_BUILTIN_CONFIG=1)
    # dishonored-nx (2026-11-01, sa2-nx's Switch LTO, after nfsmw-nx / UnleashedRecomp-NX): the recompiled game
    # (dishonored_recomp) and the app compiled to GIMPLE and optimised as one program at the link (small game functions
    # inline across files; calls between unhooked game functions are already direct). Off by default: the game code is
    # about four times SA2's, and the link takes long and much memory (build_switch.cmd with LTO=1 builds it in out\nx-lto).
    # The link repeats -ffp-contract=off and -fno-strict-aliasing (the LTRANS stage must not fuse what the compile kept
    # apart); xxHash is built with XXH_FORCE_MEMORY_ACCESS=0 (above) for the same reason as sa2-nx's.
    option(DISHONORED_SWITCH_LTO "Link-time optimisation of the game code and the app (Switch)" OFF)
    set(DISHONORED_SWITCH_LTO_JOBS "2" CACHE STRING "Parallel LTRANS jobs of the Switch LTO link (memory: about 4 GB each)")
    option(DISHONORED_SWITCH_IPA_PTA "-fipa-pta at the Switch LTO link (more memory and time)" OFF)
    if(DISHONORED_SWITCH_LTO)
        set(_dis_lto_compile -flto -fno-fat-lto-objects)
        set(_dis_lto_link -flto=${DISHONORED_SWITCH_LTO_JOBS} -flto-partition=balanced -ffp-contract=off
                          -fno-strict-aliasing)
        if(DISHONORED_SWITCH_IPA_PTA)
            list(APPEND _dis_lto_compile -fipa-pta)
            list(APPEND _dis_lto_link -fipa-pta)
        endif()
        # dishonored-nx (2026-11-11, as pure-nx): Renut's renderer (dishonored_renut_gpu: the hooks, the capture, the
        # render thread) too: a large part of the guest rendering thread's time and all of the render thread's.
        foreach(target dishonored_recomp dishonored dishonored_renut_gpu)
            if(TARGET ${target})
                target_compile_options(${target} PRIVATE ${_dis_lto_compile})
            endif()
        endforeach()
        target_link_options(dishonored PRIVATE ${_dis_lto_link})
        message(STATUS "dishonored: Switch LTO on (${DISHONORED_SWITCH_LTO_JOBS} LTRANS jobs, -fipa-pta "
                       "${DISHONORED_SWITCH_IPA_PTA})")
    endif()
    # dishonored-nx (2026-11-11, pure-nx's CMakeLists.txt, renut-nx's docs/pgo-lto.md, sa2-nx's method): profile-guided
    # optimisation, in build folders of its own (build_switch_pgo.cmd); out\nx and out\nx-lto stay without it.
    #   - DISHONORED_PGO=generate: an instrumented NRO that streams its branch counts to pgo/ next to the NRO
    #     (src/dishonored_pgo.cpp; -fprofile-info-section: libgcov's exit-time files do not fit the Switch; no value
    #     profiling, not thread-safe).
    #   - DISHONORED_PGO=use: the counts merged on the PC (tools/pgo_merge.py) from DISHONORED_PGO_DIR (pgo\ at the
    #     root). Code the sessions did not run is compiled as without a profile (-fprofile-partial-training); functions
    #     changed since keep none (-Wno-coverage-mismatch). With a profile, the game code's inliner limits of sa2-nx
    #     (max-inline-insns-auto 64, inline-unit-growth 12).
    # Neither changes what the code computes: the same source, compiled with better information.
    set(DISHONORED_PGO "" CACHE STRING "Profile-guided optimisation of the Switch build: empty, generate or use")
    set_property(CACHE DISHONORED_PGO PROPERTY STRINGS "" generate use)
    set(DISHONORED_PGO_DIR "${CMAKE_CURRENT_SOURCE_DIR}/pgo" CACHE PATH "Folder of the PGO profile (.gcda files)")
    get_filename_component(_dis_pgo_dir "${DISHONORED_PGO_DIR}" ABSOLUTE)
    file(TO_NATIVE_PATH "${_dis_pgo_dir}" _dis_pgo_dir)
    file(TO_NATIVE_PATH "${CMAKE_BINARY_DIR}" _dis_pgo_prefix)
    if(DISHONORED_PGO STREQUAL "generate")
        set(_dis_pgo "-fprofile-generate=${_dis_pgo_dir}" "-fprofile-prefix-path=${_dis_pgo_prefix}"
                     -fno-profile-values -fprofile-update=single -fprofile-info-section=gcov_info)
        target_compile_definitions(dishonored PRIVATE DISHONORED_PGO_GENERATE=1)
    elseif(DISHONORED_PGO STREQUAL "use")
        if(NOT EXISTS "${DISHONORED_PGO_DIR}")
            message(FATAL_ERROR "DISHONORED_PGO=use: no profile in ${DISHONORED_PGO_DIR} (tools/pgo_merge.py)")
        endif()
        # -fprofile-correction: counts taken without atomic updates while several threads ran the same code.
        set(_dis_pgo "-fprofile-use=${_dis_pgo_dir}" "-fprofile-prefix-path=${_dis_pgo_prefix}" -fprofile-correction
                     -fno-profile-values -fprofile-partial-training -Wno-missing-profile -Wno-coverage-mismatch)
        if(TARGET dishonored_recomp)
            target_compile_options(dishonored_recomp PRIVATE --param=max-inline-insns-auto=64
                                   --param=inline-unit-growth=12)
        endif()
    elseif(DISHONORED_PGO)
        message(FATAL_ERROR "DISHONORED_PGO must be empty, generate or use (got ${DISHONORED_PGO})")
    endif()
    if(DISHONORED_PGO)
        foreach(target dishonored dishonored_recomp dishonored_renut_gpu)
            if(TARGET ${target})
                target_compile_options(${target} PRIVATE ${_dis_pgo})
            endif()
        endforeach()
        target_link_options(dishonored PRIVATE ${_dis_pgo})
        message(STATUS "dishonored: PGO ${DISHONORED_PGO} (${DISHONORED_PGO_DIR})")
    endif()
    rexglue_switch_add_nro(dishonored
        NAME "Dishonored"
        AUTHOR "dishonored-nx"
        VERSION "0.10"  # dishonored-nx (2026-11-11): the first release (pure-nx: "0.10" too)
        ICON "${CMAKE_CURRENT_SOURCE_DIR}/icon.jpg")
endif()

# Tool: every Xbox 360 shader container in the game's cooked files (tools/ue3_shader_extract.cpp), for the native
# renderer's shader package. PC only; uses the SDK's libmspack (LZX).
if(NOT REXGLUE_PLATFORM_SWITCH AND TARGET mspack)
    add_executable(ue3_shader_extract tools/ue3_shader_extract.cpp)
    target_link_libraries(ue3_shader_extract PRIVATE mspack)
endif()
