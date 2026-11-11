// The addresses both renderers hook (banjo-nx's tools/renut_gpu_import.py generated this list for N&B). sa2-nx
// (2026-10-20): SA2's. dishonored-nx (2026-10-29): Dishonored's; its own hooks there (src/dishonored_me_hooks.cpp: the
// shader dump and the PM4-ring renderer's notes) call renut_native_sub_X when Renut's renderer is chosen.
#pragma once

#include <rex/ppc.h>

extern "C" void renut_native_sub_82A49570(PPCContext& ctx, uint8_t* base);  // D3DDevice_DrawVertices
extern "C" void renut_native_sub_82A49988(PPCContext& ctx, uint8_t* base);  // D3DDevice_DrawIndexedVertices
extern "C" void renut_native_sub_82A48B28(PPCContext& ctx, uint8_t* base);  // D3DDevice_BeginVertices
extern "C" void renut_native_sub_82A49030(PPCContext& ctx, uint8_t* base);  // D3DDevice_BeginIndexedVertices
extern "C" void renut_native_sub_82A48688(PPCContext& ctx, uint8_t* base);  // XGRegisterVertexShader
extern "C" void renut_native_sub_82A48490(PPCContext& ctx, uint8_t* base);  // XGRegisterPixelShader
