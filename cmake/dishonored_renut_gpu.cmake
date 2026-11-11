# dishonored-nx (2026-10-29): Renut's Direct3D-level renderer (github.com/masterspike52/reNut, through banjo-nx and
# sa2-nx's app/src/renut_engine), retargeted to Dishonored's Direct3D (src/renut_engine: the hooks at Dishonored's
# addresses, notes/d3d-census.md). From sa2-nx's cmake/sa2_renut_gpu.cmake, PC part: plume's Vulkan / D3D12 back ends.
# Chosen at boot with dishonored_renderer = "renut" (dishonored.toml); the emulated Xenos GPU stays the default.
#
# The third-party code (plume, reblue-XenosRecomp with DXC, imgui) and the shader tools are sa2-nx's, used where they
# are: RENUT_SDK_APP_DIR, sa2-nx's app folder (by default next to the SDK this build uses).
#
# An OBJECT library, not a static one: its hooks replace the generated code's weak sub_X definitions, and a static
# archive's members are only pulled in for undefined symbols, so the hooks would silently not be linked.

# dishonored-nx (2026-11-11): standalone, the app folder of this tree's SDK (tools/rexglue-sdk-dishonored/app).
get_filename_component(_dishonored_sdk_app "${REXSDK_DIR}/../app" ABSOLUTE)
set(RENUT_SDK_APP_DIR "${_dishonored_sdk_app}" CACHE PATH "sa2-nx's app folder (Renut's third-party code and tools)")
foreach(_dishonored_need thirdparty/plume/CMakeLists.txt thirdparty/reblue-XenosRecomp/CMakeLists.txt
                         thirdparty/imgui/imgui.cpp cmake/collect_captured_shaders.cmake)
    if(NOT EXISTS "${RENUT_SDK_APP_DIR}/${_dishonored_need}")
        message(FATAL_ERROR "Renut: ${RENUT_SDK_APP_DIR}/${_dishonored_need} missing (the app folder of "
                            "tools/rexglue-sdk-dishonored, this tree's SDK; or set RENUT_SDK_APP_DIR)")
    endif()
endforeach()

# The game's shader containers Renut's translator builds its cache from (the creation-time dumps,
# dishonored_dump_shaders, and tools/ue3_shader_extract): one container a file, vs_/ps_<hash>.bin. Must exist (the
# dump tool of gpu.cmake is N&B's / SA2's).
set(RENUT_SHADER_DUMP_DIR "${CMAKE_SOURCE_DIR}/renut_shaders" CACHE PATH "Dishonored's shader containers for Renut")
if(NOT EXISTS "${RENUT_SHADER_DUMP_DIR}")
    message(FATAL_ERROR "Renut: no ${RENUT_SHADER_DUMP_DIR}: unpack the shader containers there (renut_shaders.zip)")
endif()
set(RENUT_ASSETS_DIR "${CMAKE_SOURCE_DIR}/assets/game_root" CACHE PATH "Game assets")

# Renut's XenosRecomp is built as an ExternalProject (gpu.cmake): it gets this build's whole host toolchain.
set(BANJO_RENUT_XENOS_RECOMP_ARGS "")
foreach(_banjo_var CMAKE_C_COMPILER_TARGET CMAKE_CXX_COMPILER_TARGET CMAKE_LINKER_TYPE CMAKE_C_FLAGS CMAKE_CXX_FLAGS
                   CMAKE_AR CMAKE_RC_COMPILER CMAKE_MT)
    if(DEFINED ${_banjo_var} AND NOT "${${_banjo_var}}" STREQUAL "")
        list(APPEND BANJO_RENUT_XENOS_RECOMP_ARGS "-D${_banjo_var}=${${_banjo_var}}")
    endif()
endforeach()

# Renut's SDK exports o1heap as rex::o1heap; banjo-nx's SDK fork names it o1heap.
if(TARGET o1heap AND NOT TARGET rex::o1heap)
    add_library(rex::o1heap ALIAS o1heap)
endif()

# dishonored-nx (2026-10-29): the Switch build (sa2-nx's cmake/sa2_renut_gpu.cmake, Switch part). A cross build: the
# shader translator (XenosRecomp) and the deko3d shader tools are host programs, so their output comes ready made in
# switch_shaders/ (made on Linux from renut_shaders/ with the same XenosRecomp, DXC, SPIRV-Cross and uam):
#   shader_cache_switch.cpp.in + spirv_cache.zst   Renut's shader cache (SPIR-V only; the console reads no DXIL)
#   deko3d_glsl_switch.cpp.in + deko3d_glsl.bin    the game shaders' GLSL for deko3d (uam compiles them on the console)
#   host_shaders/*.deko3d.h                        Renut's own shaders for deko3d
# Renut always draws with deko3d here (REXGLUE_SWITCH_NO_NVK: no Vulkan driver in the NRO).
if(REXGLUE_PLATFORM_SWITCH)
    set(DISHONORED_SWITCH_SHADER_DIR "${CMAKE_SOURCE_DIR}/switch_shaders" CACHE PATH
        "The ready-made Switch shader files (switch_shaders from the dishonored-nx package)")
    foreach(_dishonored_need shader_cache_switch.cpp.in spirv_cache.zst deko3d_glsl_switch.cpp.in deko3d_glsl.bin
                             host_shaders/present_ps.deko3d.h)
        if(NOT EXISTS "${DISHONORED_SWITCH_SHADER_DIR}/${_dishonored_need}")
            message(FATAL_ERROR "Renut (Switch): no ${DISHONORED_SWITCH_SHADER_DIR}/${_dishonored_need}")
        endif()
    endforeach()
    set(PLUME_PLATFORM_SWITCH ON CACHE BOOL "" FORCE)
    set(PLUME_SWITCH_DEVKITPRO "${DEVKITPRO}" CACHE PATH "" FORCE)
    set(PLUME_SWITCH_NVK_ROOT "${REXGLUE_SWITCH_NVK_SDK}" CACHE PATH "" FORCE)
    set(PLUME_SWITCH_NVK_LIBRARY "${REXGLUE_SWITCH_NVK_SDK}/lib/libvulkan.a" CACHE FILEPATH "" FORCE)
    set(PLUME_SWITCH_NO_NVK "${REXGLUE_SWITCH_NO_NVK}" CACHE BOOL "" FORCE)
    set(PLUME_SWITCH_UAM_DIR "${RENUT_SDK_APP_DIR}/thirdparty/uam" CACHE PATH "" FORCE)
    set(PLUME_DEKO3D ON CACHE BOOL "deko3d back end (Switch)" FORCE)
    set(BANJO_DEKO3D_HOST_SHADERS_PREBUILT "${DISHONORED_SWITCH_SHADER_DIR}/host_shaders")
    # The .incbin paths of the two embedded files: forward slashes for the assembler.
    file(TO_CMAKE_PATH "${DISHONORED_SWITCH_SHADER_DIR}" DISHONORED_SWITCH_SHADER_DIR_FWD)
    set(_dishonored_saved_dir "${DISHONORED_SWITCH_SHADER_DIR}")
    set(DISHONORED_SWITCH_SHADER_DIR "${DISHONORED_SWITCH_SHADER_DIR_FWD}")
    set(BANJO_DEKO3D_GLSL_CPP "${CMAKE_BINARY_DIR}/dishonored_switch/deko3d_glsl_switch.cpp")
    set(BANJO_RENUT_SHADER_CACHE_CPP "${CMAKE_BINARY_DIR}/dishonored_switch/shader_cache_switch.cpp")
    configure_file("${_dishonored_saved_dir}/deko3d_glsl_switch.cpp.in" "${BANJO_DEKO3D_GLSL_CPP}" @ONLY)
    configure_file("${_dishonored_saved_dir}/shader_cache_switch.cpp.in" "${BANJO_RENUT_SHADER_CACHE_CPP}" @ONLY)
    set(DISHONORED_SWITCH_SHADER_DIR "${_dishonored_saved_dir}")
    # A change of the embedded files rebuilds the two sources (the assembler reads them, CMake does not see that).
    set_source_files_properties("${BANJO_DEKO3D_GLSL_CPP}" PROPERTIES
        OBJECT_DEPENDS "${DISHONORED_SWITCH_SHADER_DIR}/deko3d_glsl.bin" SKIP_PRECOMPILE_HEADERS ON)
    set_source_files_properties("${BANJO_RENUT_SHADER_CACHE_CPP}" PROPERTIES
        OBJECT_DEPENDS "${DISHONORED_SWITCH_SHADER_DIR}/spirv_cache.zst" SKIP_PRECOMPILE_HEADERS ON)
    function(banjo_renut_shader_cache_override TARGET)
        target_sources(${TARGET} PRIVATE "${BANJO_RENUT_SHADER_CACHE_CPP}")
    endfunction()
endif()

# banjo-nx's early alpha pass over the pixel shaders (tools/renut_early_alpha.py, two translator runs) is off for now:
# the first PC runs compare against the emulated GPU without it, and the build needs no Python.
set(BANJO_RENUT_EARLY_ALPHA OFF)

include("${CMAKE_SOURCE_DIR}/src/renut_engine/gpu/gpu.cmake")

add_library(dishonored_renut_gpu OBJECT
    "${CMAKE_SOURCE_DIR}/src/renut_engine/gpu/banjo_renut_select.cpp"
    "${CMAKE_SOURCE_DIR}/src/renut_engine/gpu/banjo_renut_tuning.cpp"
    "${CMAKE_SOURCE_DIR}/src/renut_engine/gpu/banjo_renut_checks.cpp"
    "${CMAKE_SOURCE_DIR}/src/renut_engine/gpu/banjo_renut_record.cpp"
    "${CMAKE_SOURCE_DIR}/src/renut_engine/display_sync.cpp"
    "${CMAKE_SOURCE_DIR}/src/renut_engine/perf/frame_stats.cpp"
    "${CMAKE_SOURCE_DIR}/src/renut_engine/dishonored_compat/frame_latency.cpp"
    "${CMAKE_SOURCE_DIR}/src/renut_engine/dishonored_compat/dishonored_compat.cpp"
    "${CMAKE_SOURCE_DIR}/src/renut_engine/gpu/dishonored_renut_pacing.cpp")
target_include_directories(dishonored_renut_gpu PRIVATE
    "${CMAKE_SOURCE_DIR}"
    "${CMAKE_SOURCE_DIR}/src"
    "${CMAKE_SOURCE_DIR}/src/renut_engine/dishonored_compat"
    "${REXSDK_DIR}/src/core")
target_link_libraries(dishonored_renut_gpu PRIVATE rex::runtime)
if(REXGLUE_PLATFORM_SWITCH)
    # The deko3d back end's glue and the game shaders' GLSL package (sa2-nx's cmake/sa2_renut_gpu.cmake).
    target_sources(dishonored_renut_gpu PRIVATE
        "${CMAKE_SOURCE_DIR}/src/renut_engine/gpu/banjo_renut_deko3d.cpp"
        "${BANJO_DEKO3D_GLSL_CPP}")
    target_include_directories(dishonored_renut_gpu PRIVATE "${REXGLUE_ENTRYPOINT_INCLUDE_DIR}")
    if(REXGLUE_SWITCH_NO_NVK)
        # No Vulkan driver in the NRO: Renut on deko3d whatever renut_gpu_backend says.
        set_property(SOURCE "${CMAKE_SOURCE_DIR}/src/renut_engine/gpu/banjo_renut_select.cpp"
                            "${RENUT_GPU_DIR}/backend/backend.cpp"
                     APPEND PROPERTY COMPILE_DEFINITIONS DISHONORED_SWITCH_NO_NVK=1)
    endif()
endif()
if(COMMAND rexglue_apply_target_settings)
    rexglue_apply_target_settings(dishonored_renut_gpu)
endif()
renut_gpu_setup(dishonored_renut_gpu)
target_compile_definitions(dishonored_renut_gpu PRIVATE DISHONORED_RENUT_RENDERER=1 DISHONORED_RENUT_RENDERER=1)
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(dishonored_renut_gpu PRIVATE -ffp-contract=off -fno-strict-aliasing)
endif()
target_link_libraries(dishonored PRIVATE dishonored_renut_gpu)
target_compile_definitions(dishonored PRIVATE DISHONORED_RENUT_RENDERER=1 DISHONORED_RENUT_RENDERER=1)
target_include_directories(dishonored PRIVATE "${CMAKE_SOURCE_DIR}/src/renut_engine/dishonored_compat")
