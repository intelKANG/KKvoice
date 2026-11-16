#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include "ATVVCaptureGate.h"

int main(void) {
    ATVVCaptureGate gate = {0};
    uint64_t token = 0, duplicate = 0;
    assert(!ATVVCaptureMayEmit(&gate));

    // 0x08 START_SEARCH may initiate a short probe even without a session;
    // repeated search does not open a second probe or extend its deadline.
    assert(ATVVCaptureBeginProbe(&gate, &token));
    assert(!ATVVCaptureMayEmit(&gate));
    assert(!ATVVCaptureBeginProbe(&gate, &duplicate));
    assert(ATVVCaptureExpireProbe(&gate, token));
    assert(!ATVVCaptureMayEmit(&gate));
    assert(!ATVVCaptureExpireProbe(&gate, token));

    // Physical AUDIO_START/voice_press causes the app to authorize capture.
    assert(ATVVCaptureBeginProbe(&gate, &token));
    ATVVCaptureAuthorize(&gate);
    assert(ATVVCaptureMayEmit(&gate));
    assert(!ATVVCaptureExpireProbe(&gate, token));
    assert(!ATVVCaptureBeginProbe(&gate, &duplicate));

    // Explicit stop immediately denies forwarding; late watchdogs and prior
    // probe tokens cannot authorize or interfere with a future session.
    ATVVCaptureDisable(&gate);
    assert(!ATVVCaptureMayEmit(&gate));
    assert(ATVVCaptureBeginProbe(&gate, &duplicate));
    assert(!ATVVCaptureExpireProbe(&gate, token));
    assert(ATVVCaptureExpireProbe(&gate, duplicate));
    assert(!ATVVCaptureMayEmit(&gate));

    // Keyboard-initiated authorization has no preliminary probe.
    ATVVCaptureAuthorize(&gate);
    assert(ATVVCaptureMayEmit(&gate));
    ATVVCaptureDisable(&gate);
    assert(!ATVVCaptureMayEmit(&gate));
    puts("PASS: provisional search, authorization, stop, stale timeout and keyboard start");
    return 0;
}
