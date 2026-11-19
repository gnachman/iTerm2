// Fixture: target T's gDup. Line numbers are part of the expectations.
#include "dup.h"
int gDup = 1;
void SetA(void) {
    gDup = 2;
    sHeaderCounter++;
}
