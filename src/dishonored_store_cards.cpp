// dishonored-nx (2026-11-11, pure-nx's src/pure_store_cards.cpp): whether the generated code marks the store cards.
// tools/store_cards.py (the last post-codegen step) makes every guest store mark its 4 KB page in a card table; Renut's
// exact streams (banjo_renut_exact_streams) then prove a cached copy unchanged by its cards instead of hashing it whole.
// Without that step (or with REX_STORE_CARDS_OFF) the cards stay unmarked, and Renut must not trust them.
#include "../generated/default/dishonored_pch.h"

#if defined(REX_CARD) && !defined(REX_STORE_CARDS_OFF)
extern "C" const bool g_banjo_store_cards = true;
#else
extern "C" const bool g_banjo_store_cards = false;
#endif
