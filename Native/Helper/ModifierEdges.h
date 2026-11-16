#ifndef KKVOICE_MODIFIER_EDGES_H
#define KKVOICE_MODIFIER_EDGES_H
#include <stdbool.h>
#include <stdint.h>

/* Decode only the configured modifier's own events. Device-side flag bits are
   used when present, so pressing both Control keys does not merge their edges.
   When side bits are absent and the aggregate flag stays high, a side-specific
   release is unknowable: retain the prior state rather than invent an edge. */
typedef enum { KKModifierNone, KKModifierDown, KKModifierUp } KKModifierEdge;
typedef enum { KKKeyDown, KKKeyUp, KKFlagsChanged } KKModifierEvent;
typedef struct { bool down; } KKModifierState;

static inline bool KKModifierMasks(uint16_t code, uint64_t *aggregate,
                                   uint64_t *side, uint64_t *group) {
    switch (code) {
      case 0x3b: *aggregate=0x40000; *side=0x1;    *group=0x2001; return true;
      case 0x3e: *aggregate=0x40000; *side=0x2000; *group=0x2001; return true;
      case 0x38: *aggregate=0x20000; *side=0x2;    *group=0x6; return true;
      case 0x3c: *aggregate=0x20000; *side=0x4;    *group=0x6; return true;
      case 0x3a: *aggregate=0x80000; *side=0x20;   *group=0x60; return true;
      case 0x3d: *aggregate=0x80000; *side=0x40;   *group=0x60; return true;
      case 0x37: *aggregate=0x100000; *side=0x8;   *group=0x18; return true;
      case 0x36: *aggregate=0x100000; *side=0x10;  *group=0x18; return true;
      case 0x3f: *aggregate=0x800000; *side=0;     *group=0; return true;
      default: return false;
    }
}
static inline KKModifierEdge KKModifierObserve(KKModifierState *state,
    uint16_t configured, uint16_t keyCode, KKModifierEvent event,
    uint64_t flags, bool synthetic, bool repeat) {
    uint64_t aggregate, side, group;
    if (synthetic || keyCode != configured ||
        !KKModifierMasks(configured, &aggregate, &side, &group)) return KKModifierNone;
    bool down = state->down;
    if (event == KKKeyDown) { if (repeat) return KKModifierNone; down = true; }
    else if (event == KKKeyUp) down = false;
    else if (event == KKFlagsChanged) {
        if (group && (flags & group)) down = (flags & side) != 0;
        else if (!(flags & aggregate)) down = false;
        else if (!state->down) down = true;
        /* Otherwise the aggregate flag is still set and side is ambiguous. */
    } else return KKModifierNone;
    if (down == state->down) return KKModifierNone;
    state->down = down;
    return down ? KKModifierDown : KKModifierUp;
}
#endif
