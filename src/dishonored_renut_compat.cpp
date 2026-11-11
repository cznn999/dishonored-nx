// What Renut's renderer (src/renut_engine, from sa2-nx) takes from sa2-nx's app that Dishonored does not have: the game
// frame count, the video recorder's lockstep hooks (no recorder here) and the store cards (Dishonored's generated code
// does not mark them, so Renut hashes its cached copies as before).
#include <atomic>
#include <cstdint>
#include <functional>

#include "dishonored_capture.h"

std::atomic<uint64_t> g_dishonored_game_frames{0};

// (g_banjo_store_cards, whether the generated code marks the store cards: src/dishonored_store_cards.cpp, 2026-11-11.)

namespace dishonored::capture {
void Start(std::function<rex::ui::Presenter*()>) {}
void StartWithSource(std::function<bool(rex::ui::RawImage&)>) {}
bool RenutLockstepOn() { return false; }
void RenutLockstepFrame(uint64_t, const rex::ui::RawImage*) {}
void Stop() {}
void BeforeFlip() {}
}  // namespace dishonored::capture
