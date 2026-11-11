// Temporary probe (stage 4 prep): logs the arguments of the Direct3D functions found by tools/pm4_scan.py, so each one
// can be named from what the game passes it (primitive type, counts, pointers) before the native renderer hooks them.
// Every hook calls the original unchanged; nothing in the game's state is written.
//
// Candidates (notes/d3d-census.md):
//   82A49570, 82A49988, 82A48B28, 82A49030, 82A49E00  - functions that write DRAW_INDX packets
//   82A517E0                                          - called by all five; reads device+13072 / +13068 (VS / PS)
//   82A4F610, 82A4EAA8                                - write INTERRUPT packets (Swap / fences)
//   82A4D080                                          - writes INDIRECT_BUFFER + touches the GPU MMIO (KickOff)

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>

#include <rex/cvar.h>
#include <rex/hook.h>
#include <rex/logging.h>
#include <rex/ppc.h>

REXCVAR_DEFINE_BOOL(dishonored_d3d_probe, true, "Dishonored",
                    "Log the arguments of the Direct3D candidates (first calls, then counts every 5 s)");

namespace {

inline uint32_t L32(const uint8_t* base, uint32_t a) {
  uint32_t v;
  std::memcpy(&v, base + a, 4);
  return __builtin_bswap32(v);
}

struct Probe {
  const char* name;
  std::atomic<uint32_t> calls{0};
  std::atomic<uint32_t> since{0};
};

Probe g_probes[] = {{"82A49570"}, {"82A49988"}, {"82A48B28"}, {"82A49030"}, {"82A49E00"},
                    {"82A517E0"}, {"82A4F610"}, {"82A4EAA8"}, {"82A4D080"}};
constexpr int kFirstCalls = 12;

std::atomic<int64_t> g_last_report{0};

void Report() {
  using namespace std::chrono;
  const int64_t now = duration_cast<seconds>(steady_clock::now().time_since_epoch()).count();
  int64_t last = g_last_report.load(std::memory_order_relaxed);
  if (now - last < 5 || !g_last_report.compare_exchange_strong(last, now)) return;
  REXLOG_INFO("[d3dprobe] last ~5 s: {}={} {}={} {}={} {}={} {}={} {}={} {}={} {}={} {}={}",
              g_probes[0].name, g_probes[0].since.exchange(0), g_probes[1].name, g_probes[1].since.exchange(0),
              g_probes[2].name, g_probes[2].since.exchange(0), g_probes[3].name, g_probes[3].since.exchange(0),
              g_probes[4].name, g_probes[4].since.exchange(0), g_probes[5].name, g_probes[5].since.exchange(0),
              g_probes[6].name, g_probes[6].since.exchange(0), g_probes[7].name, g_probes[7].since.exchange(0),
              g_probes[8].name, g_probes[8].since.exchange(0));
}

void Note(int i, PPCContext& ctx, uint8_t* base) {
  if (!REXCVAR_GET(dishonored_d3d_probe)) return;
  Probe& p = g_probes[i];
  const uint32_t n = p.calls.fetch_add(1, std::memory_order_relaxed);
  p.since.fetch_add(1, std::memory_order_relaxed);
  if (n < kFirstCalls) {
    const uint32_t dev = ctx.r3.u32;
    uint32_t vs = 0, ps = 0;
    if (dev >= 0x40000000 && dev < 0xF0000000) {
      vs = L32(base, dev + 13072);
      ps = L32(base, dev + 13068);
    }
    REXLOG_INFO("[d3dprobe] {} #{} r3={:08X} r4={:08X} r5={:08X} r6={:08X} r7={:08X} r8={:08X} r9={:08X} r10={:08X} "
                "lr={:08X} vs={:08X} ps={:08X}",
                p.name, n, ctx.r3.u32, ctx.r4.u32, ctx.r5.u32, ctx.r6.u32, ctx.r7.u32, ctx.r8.u32, ctx.r9.u32,
                ctx.r10.u32, uint32_t(ctx.lr), vs, ps);
  }
  Report();
}

}  // namespace

#define DISHONORED_PROBE(i, addr)        \
  REX_EXTERN(__imp__sub_##addr);         \
  REX_HOOK_RAW(sub_##addr) {             \
    Note(i, ctx, base);                  \
    __imp__sub_##addr(ctx, base);        \
  }

DISHONORED_PROBE(0, 82A49570)
DISHONORED_PROBE(1, 82A49988)
DISHONORED_PROBE(2, 82A48B28)
DISHONORED_PROBE(3, 82A49030)
DISHONORED_PROBE(4, 82A49E00)
DISHONORED_PROBE(5, 82A517E0)
DISHONORED_PROBE(6, 82A4F610)
DISHONORED_PROBE(7, 82A4EAA8)
DISHONORED_PROBE(8, 82A4D080)
