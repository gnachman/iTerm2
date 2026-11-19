// expect: -Wswitch-enum
#import "iTermStrictWarnings.h"
enum E { E_A, E_B };
int f(enum E e) { switch (e) { case E_A: return 1; default: return 0; } }
