// sa2-nx (2026-10-20): banjo-nx's enhancement switches, as Renut's renderer (through banjo-nx) asks for them, answered
// by SA2's (src/cpu/dishonored_enhancements.h): a banjo_* key is active when it is on and its group's master is on
// (dishonored_cpu_enhancements / dishonored_noncpu_enhancements).
#pragma once

#include "cpu/dishonored_enhancements.h"

namespace banjo {

enum class EnhancementGroup { kCpu, kNonCpu };

inline bool EnhancementActive(EnhancementGroup group, bool own_key) {
  return own_key && (group == EnhancementGroup::kCpu ? dishonored::enh::CpuMaster() : dishonored::enh::NonCpuMaster());
}

// The generated code's self-checks: SA2's own 10 s enhancement report gives them (dishonored::enh::StartReport).
inline void CodegenChecksReport(int) {}

}  // namespace banjo
