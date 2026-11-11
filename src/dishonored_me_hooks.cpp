// Dishonored hooks for the native PM4-ring renderer (src/me, from sa2-nx / masseffect-nx / banjo-nx).
//
// The renderer reads the game's PM4 ring by itself; these hooks only feed it what the ring cannot say. Addresses from
// the runtime probe (src/d3d_probe.cpp, notes/d3d-census.md; Direct3D 2.0.21076 LTCG, the same build as SA2):
//
//   - Shader objects: the draw-time shader load sub_82A517E0 (r3 = device), called by every Draw*; it reads the bound
//     VS from device+13072 and the PS from device+13068 (SA2's offsets, same XDK build).
//   - Draw records, a hint for pairing (NoteDrawCall: primitive type, then r5..r7 as Direct3D received them):
//       D3DDevice_DrawVertices          sub_82A49570
//       D3DDevice_DrawIndexedVertices   sub_82A49988
//       D3DDevice_BeginVertices         sub_82A48B28
//       D3DDevice_BeginIndexedVertices  sub_82A49030
//   With dishonored_renderer = "renut" these draw hooks and the shader setup hooks hand over to Renut's
//   (BANJO_RENUT_YIELD_SHARED, renut_engine/gpu/banjo_shared_hooks.h).
//   - Shader containers for the library (dishonored_dump_shaders = true): read from the shader objects at the load.
//
// Every hook calls the original unchanged. The direct-state path of sa2-nx (BeginDrawDirect / flush hooks) is not used.

#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <system_error>
#include <unordered_set>
#include <vector>

#include <fmt/format.h>

#include <rex/cvar.h>
#include <rex/filesystem.h>
#include <rex/hook.h>
#include <rex/logging.h>
#include <rex/ppc.h>
#include <rex/system/kernel_state.h>
#include <rex/system/xmemory.h>

#define XXH_INLINE_ALL
#include <xxhash.h>

#include "me/me_native_system.h"
#include "renut_engine/gpu/banjo_renut_select.h"
#include "renut_engine/gpu/banjo_shared_hooks.h"

REXCVAR_DEFINE_BOOL(dishonored_dump_shaders, false, "Dishonored",
                    "Write every shader the game draws with to shaders/ next to the executable (vs_/ps_<hash>.bin)");

namespace {

inline uint32_t Load32(const uint8_t* base, uint32_t address) {
  uint32_t v;
  std::memcpy(&v, base + address, 4);
  return __builtin_bswap32(v);
}

constexpr uint32_t kDeviceVertexShader = 13072;  // 0x3310
constexpr uint32_t kDevicePixelShader = 13068;   // 0x330C

const bool g_device_layout_set = [] {
  me::native::SetDeviceShaderOffsets(kDeviceVertexShader, kDevicePixelShader);
  return true;
}();

std::mutex g_dump_mutex;
std::unordered_set<uint32_t> g_dumped_objects;
std::unordered_set<uint64_t> g_dumped_hashes;

// The container a D3D shader object carries (the renderer reads it the same way, NoteShaderObject): its header and
// constant tables at object+0x368 (VS) / +0x28 (PS) with the virtual size at +4 and the physical (microcode) size at
// +8, and the microcode at the pointer object+0x20 (VS) / +0x18 (PS), in a physical-memory view. Written as one blob
// (header part, then microcode), the layout sa2-nx's shader tools read: shaders/vs_<hash>.bin / ps_<hash>.bin.
void DumpShaderObject(const uint8_t* base, uint32_t object, bool vertex, bool at_creation = false) {
  if (!REXCVAR_GET(dishonored_dump_shaders) || object < 0x40000000 || object >= 0x7F000000) return;
  if (!at_creation) {
    std::lock_guard lock(g_dump_mutex);
    if (!g_dumped_objects.insert(object).second) return;
  }
  if ((Load32(base, object) & 0xFF) != (vertex ? 6u : 7u)) return;
  const uint32_t header = object + (vertex ? 0x368 : 0x28);
  const uint32_t virtual_size = Load32(base, header + 4);
  const uint32_t physical_size = Load32(base, header + 8);
  const uint32_t microcode = Load32(base, object + (vertex ? 0x20 : 0x18));
  if ((Load32(base, header) & 0xFFFFFF00u) != 0x102A1100u || virtual_size < 28 || virtual_size > 0x40000 ||
      !physical_size || physical_size > 0x40000 || microcode < 0xA0000000u) {
    REXLOG_WARN("[shaders] {} object {:08X} has no container (word {:08X}, sizes {}/{}, microcode {:08X})",
                vertex ? "VS" : "PS", object, Load32(base, header), virtual_size, physical_size, microcode);
    return;
  }
  std::vector<uint8_t> blob(size_t(virtual_size) + physical_size);
  std::memcpy(blob.data(), base + header, virtual_size);
  std::memcpy(blob.data() + virtual_size,
              rex::system::kernel_state()->memory()->TranslateVirtual<const uint8_t*>(microcode), physical_size);
  const uint64_t hash = XXH3_64bits(blob.data(), blob.size());
  {
    std::lock_guard lock(g_dump_mutex);
    if (!g_dumped_hashes.insert(hash).second) return;
  }
  const auto folder = rex::filesystem::GetExecutableFolder() / "shaders";
  std::error_code ec;
  std::filesystem::create_directories(folder, ec);
  std::ofstream(folder / fmt::format("{}_{:016x}.bin", vertex ? "vs" : "ps", hash), std::ios::binary)
      .write(reinterpret_cast<const char*>(blob.data()), std::streamsize(blob.size()));
}

}  // namespace

// Draw-time shader load (called from every Draw*).
REX_EXTERN(__imp__sub_82A517E0);
REX_HOOK_RAW(sub_82A517E0) {
  const uint32_t device = ctx.r3.u32;
  if (device >= 0x40000000 && device < 0x7F000000) {
    const uint32_t vs = Load32(base, device + kDeviceVertexShader), ps = Load32(base, device + kDevicePixelShader);
    if (!me::native::ShaderObjectsFinished(vs, ps)) {
      me::native::NoteShaderObject(base, vs, true);
      me::native::NoteShaderObject(base, ps, false);
    }
    DumpShaderObject(base, vs, true);
    DumpShaderObject(base, ps, false);
  }
  __imp__sub_82A517E0(ctx, base);
}

#define DISHONORED_DRAW_HOOK(addr)                                                                  \
  REX_EXTERN(__imp__sub_##addr);                                                                    \
  REX_HOOK_RAW(sub_##addr) {                                                                        \
    BANJO_RENUT_YIELD_SHARED(sub_##addr)                                                            \
    me::native::NoteDrawCall(base, ctx.r3.u32, ctx.r4.u32, ctx.r5.u32, ctx.r6.u32, ctx.r7.u32);   \
    __imp__sub_##addr(ctx, base);                                                                   \
  }

DISHONORED_DRAW_HOOK(82A49570)  // D3DDevice_DrawVertices
DISHONORED_DRAW_HOOK(82A49988)  // D3DDevice_DrawIndexedVertices
DISHONORED_DRAW_HOOK(82A48B28)  // D3DDevice_BeginVertices
DISHONORED_DRAW_HOOK(82A49030)  // D3DDevice_BeginIndexedVertices

// Shader creation (Direct3D's in-place object setup, called by UE3's RHI when a shader cache is loaded): every shader
// of a loaded package, drawn or not, so loading a level is enough to collect its shaders.
//   sub_82A48688: vertex shader object (r3 = object: type 6, container header at +0x368, microcode pointer r4 -> +0x20)
//   sub_82A48490: pixel shader object  (r3 = object: type 7, container header at +0x28,  microcode pointer r4 -> +0x18)
REX_EXTERN(__imp__sub_82A48688);
REX_HOOK_RAW(sub_82A48688) {
  const uint32_t object = ctx.r3.u32;
  // Renut (dishonored_renderer = "renut"): the original, then the host shader (renut_engine/gpu/d3d/hooks/shader.cpp).
  if (::banjo::renut_gpu::Active())
    renut_native_sub_82A48688(ctx, base);
  else
    __imp__sub_82A48688(ctx, base);
  DumpShaderObject(base, object, true, true);
}

REX_EXTERN(__imp__sub_82A48490);
REX_HOOK_RAW(sub_82A48490) {
  const uint32_t object = ctx.r3.u32;
  if (::banjo::renut_gpu::Active())
    renut_native_sub_82A48490(ctx, base);
  else
    __imp__sub_82A48490(ctx, base);
  DumpShaderObject(base, object, false, true);
}
