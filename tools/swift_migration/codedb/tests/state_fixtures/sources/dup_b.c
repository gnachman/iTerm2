// Fixture: target U's gDup. Line numbers are part of the expectations.
#include "dup.h"
int gDup = 3;
void SetB(void) {
    gDup = 4;
    sHeaderCounter = 0;
}
