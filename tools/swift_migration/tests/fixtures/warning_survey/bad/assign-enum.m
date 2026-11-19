// expect: -Wassign-enum
#import "iTermStrictWarnings.h"
typedef enum __attribute__((enum_extensibility(closed))) { E_A = 1, E_B = 2 } E;
E f(void) { E e = 5; return e; }
