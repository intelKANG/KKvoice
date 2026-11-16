#include "../Native/Helper/ModifierEdges.h"
#include <assert.h>
#include <stdio.h>
#define L 0x3b
#define R 0x3e
#define CTRL 0x40000
#define E(s,c,k,t,f,y,r) KKModifierObserve(&(s),(c),(k),(t),(f),(y),(r))
int main(void) {
    KKModifierState l={0}, r={0};
    assert(E(l,L,L,KKKeyDown,CTRL,false,false)==KKModifierDown);
    assert(E(l,L,L,KKKeyDown,CTRL,false,true)==KKModifierNone);
    assert(E(l,L,L,KKFlagsChanged,0,false,false)==KKModifierUp);
    assert(E(l,L,L,KKFlagsChanged,0,false,false)==KKModifierNone);
    assert(E(l,L,L,KKFlagsChanged,CTRL|1,false,false)==KKModifierDown);
    assert(E(l,L,L,KKFlagsChanged,CTRL|1,false,false)==KKModifierNone);
    assert(E(r,R,R,KKFlagsChanged,CTRL|1|0x2000,false,false)==KKModifierDown);
    assert(E(l,L,R,KKFlagsChanged,CTRL|1|0x2000,false,false)==KKModifierNone);
    assert(E(l,L,L,KKFlagsChanged,CTRL|0x2000,false,false)==KKModifierUp);
    assert(r.down);
    assert(E(r,R,R,KKFlagsChanged,0,false,false)==KKModifierUp);
    assert(E(l,L,L,KKKeyDown,0,true,false)==KKModifierNone);
    assert(E(l,L,L,KKKeyUp,0,false,false)==KKModifierNone);
    assert(E(l,L,L,KKFlagsChanged,CTRL,false,false)==KKModifierDown);
    assert(E(l,L,L,KKFlagsChanged,CTRL,false,false)==KKModifierNone);
    assert(E(l,L,L,KKFlagsChanged,0,false,false)==KKModifierUp);
    puts("PASS: modifier key edges, repeats, sides, orphan and synthetic events");
}
