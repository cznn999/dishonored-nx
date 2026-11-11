// dishonored-nx (2026-11-11, the user's request: "punkt 3"): native replacements of hot guest leaf functions, as
// pure-nx's src/pure_native.cpp (nfsmw-nx's "native replacements"). Each one computes exactly what the recompiled
// function computes and leaves the same registers and memory behind that a caller can read; it only drops the
// recompiled overhead. dishonored_native_off = true turns them all back into the recompiled originals.
//
// Hot list (rex_profile of 2026-11-02, the heavy view at GPU 460 MHz, symbolized with out\nx-lto\dishonored):
// sub_82CD1D20, the C runtime's memcpy, 3 % of both busy guest threads ("Main XThread" and the rendering thread).
//
// After adding or removing a hook here: python tools\direct_calls.py --redo (tools\post_codegen_dishonored.py runs
// it): the generated code calls __imp__sub_X directly for every function without a hook, which would skip this one.
#include "../generated/default/dishonored_pch.h"

#include <cstring>

#include <rex/cvar.h>
#include <rex/hook.h>

#include "renut_engine/gpu/render/occlusion.h"

REXCVAR_DEFINE_BOOL(dishonored_native_off, false, "Dishonored",
                    "Run the recompiled originals of the native replacements in src/dishonored_native.cpp instead")
    .lifecycle(rex::cvar::Lifecycle::kInitOnly);

REX_EXTERN(__imp__sub_82CD1D20);

namespace {
// A guest range the host can copy with one memmove: below the hardware registers (0x7Fxxxxxx), or in the virtual
// 64 KB / 4 KB heaps under the physical views (0xA0000000 up, aliased: one page may have several guest addresses),
// and not wrapping 4 GB. Anything else goes to the original.
inline bool PlainGuestRange(uint32_t x, uint32_t n) {
  const uint32_t e = x + (n - 1);
  if (e < x) return false;
  if (x < 0x7F000000u) return e < 0x7F000000u;
  return x >= 0x80000000u && e < 0xA0000000u;
}
}  // namespace

// sub_82CD1D20, the C runtime's memcpy (r3 dst, r4 src, r5 size) -> r3 dst: the same routine as pure-nx's
// sub_82F69070 (checked against the generated code, dishonored_recomp.144.cpp): it saves r3 at -8(r1) first
// (std r3,-8(r1)), copies forward (bytes to alignment, then words / doublewords with dcbt prefetches) and reloads r3
// from that slot at every return (ld r3,-8(r1); blr). Native: the same save, one host memmove, r3 unchanged. It writes
// no other register; the original clobbers r0 and r4-r12 (volatile in the PowerPC ABI: no caller reads them after the
// call). The original still runs when the copy would differ: a destination after an overlapping source (its forward
// copy smears), a destination over the save slot (the copied bytes would come back in r3), a size that is not a
// 32-bit value, or a range the host cannot copy plainly (PlainGuestRange). With the store cards (tools/store_cards.py,
// the optimised codegen) it marks the pages it writes, as the generated stores do.
REX_HOOK_RAW(sub_82CD1D20) {
  const uint32_t dst = ctx.r3.u32, src = ctx.r4.u32, n = ctx.r5.u32;
  const uint32_t slot = ctx.r1.u32 - 8;
  if (REXCVAR_GET(dishonored_native_off) || n == 0 || ctx.r5.u64 != n || !PlainGuestRange(dst, n) ||
      !PlainGuestRange(src, n) || (dst > src && dst - src < n) || (dst < slot + 8 && slot < dst + n)) {
    __imp__sub_82CD1D20(ctx, base);
    return;
  }
  REX_STORE_D_U64(ctx.r1.u32, -8, ctx.r3.u64);  // std r3,-8(r1)
  std::memmove(REX_RAW_ADDR(dst), REX_RAW_ADDR(src), n);
#if defined(REX_CARD) && !defined(REX_STORE_CARDS_OFF)
  // dishonored-nx (2026-11-11): the store cards of every page written (tools/store_cards.py; Renut's exact streams
  // read them), as pure-nx's memcpy.
  for (uint32_t page = dst >> 12, last = (dst + n - 1) >> 12; page <= last; ++page)
    REX_CARD(page << 12);
#endif
  // ld r3,-8(r1): the value just saved
}

// dishonored-nx (2026-11-11): sub_82742AB0, UE3's occlusion batch check (the batch in r31, its fence at +804 to
// IsFencePending): the thread is marked as inside it, so the IsFencePending hook (renut_engine/gpu/d3d/hooks/device.cpp)
// may find the batch by its fence there and only there (renut::gpu::occlusion::BatchCheckScope). The original runs
// whole; not under dishonored_native_off (nothing replaced, only a mark).
REX_EXTERN(__imp__sub_82742AB0);
REX_HOOK_RAW(sub_82742AB0) {
  renut::gpu::occlusion::BatchCheckScope scope;
  __imp__sub_82742AB0(ctx, base);
}
