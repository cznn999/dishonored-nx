// The parts of sa2-nx's app the ring renderer calls that Dishonored does not have (sa2-nx's native Direct3D layer and
// its codegen self-checks): empty here.
#include "cpu/dishonored_enhancements.h"
#include "me/dishonored_api.h"

namespace dishonored::api {
void Report() {}
}  // namespace dishonored::api

namespace dishonored::enh {
void CodegenChecksInit() {}
void CodegenChecksReport(int) {}
void FormsSelfCheck() {}
}  // namespace dishonored::enh
