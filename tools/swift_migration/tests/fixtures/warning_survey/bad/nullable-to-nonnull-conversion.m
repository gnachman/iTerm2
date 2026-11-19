// expect: -Wnullable-to-nonnull-conversion
#import "iTermStrictWarnings.h"
void g(int * _Nonnull p);
void f(int * _Nullable q) { g(q); }
