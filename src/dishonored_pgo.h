// dishonored-nx (2026-11-11): profile collection of the PGO-instrumented Switch build (DISHONORED_PGO=generate), see
// dishonored_pgo.cpp. From pure-nx's src/pure_pgo.h (renut-nx's banjo_pgo.h, sa2-nx's sa2_pgo.h). In every other
// build these do nothing.

#pragma once

namespace dishonored::pgo {

#if defined(DISHONORED_PGO_GENERATE)
// Picks this session's file (pgo/dishonored_pgo_<N>.stream next to the NRO) and starts the dumps every minute.
void Start();
// Writes every count so far to this session's file (the whole session each time, replacing the previous dump).
void DumpNow();
#else
inline void Start() {}
inline void DumpNow() {}
#endif

}  // namespace dishonored::pgo
