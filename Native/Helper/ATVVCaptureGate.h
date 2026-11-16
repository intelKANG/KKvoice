#ifndef KKVOICE_ATVV_CAPTURE_GATE_H
#define KKVOICE_ATVV_CAPTURE_GATE_H
#include <stdbool.h>
#include <stdint.h>

// A physical START_SEARCH may need a short MIC_OPEN probe before the remote
// reports its voice-key gesture. It is not permission to stream indefinitely.
// Tokens are local generations, not device-provided session identities.
typedef struct {
    bool authorized;
    bool probing;
    uint64_t generation;
} ATVVCaptureGate;

static inline void ATVVCaptureAuthorize(ATVVCaptureGate *gate) {
    gate->authorized = true;
    gate->probing = false;
    gate->generation++;
}
static inline void ATVVCaptureDisable(ATVVCaptureGate *gate) {
    gate->authorized = false;
    gate->probing = false;
    gate->generation++;
}
static inline bool ATVVCaptureBeginProbe(ATVVCaptureGate *gate, uint64_t *token) {
    if (gate->authorized || gate->probing) return false;
    gate->probing = true;
    gate->generation++;
    *token = gate->generation;
    return true;
}
static inline bool ATVVCaptureExpireProbe(ATVVCaptureGate *gate, uint64_t token) {
    if (gate->authorized || !gate->probing || gate->generation != token) return false;
    gate->probing = false;
    gate->generation++;
    return true;
}
static inline bool ATVVCaptureMayEmit(const ATVVCaptureGate *gate) { return gate->authorized; }
#endif
