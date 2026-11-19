// Fixture: compiled with MODE=2. Line numbers are part of the expectations.
#import "macros.h"
#define LOCAL 2
int BValue(void) {
    return KIND + LOCAL;
}
#if 0
void Hidden(MRoot *r) { [r hiddenSelector]; [r ping]; }
#endif
// A macro from outside the repository in a repository macro's argument: its
// declarations are not the repository macro's.
int BMax(int x, int y) {
    return FIRST_ONLY(SDK_MAX(x, y), 0);
}
