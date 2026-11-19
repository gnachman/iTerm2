// expect: -Wformat-nonliteral
#import "iTermStrictWarnings.h"
int my_printf(const char *format, ...) __attribute__((format(printf, 1, 2)));
void f(const char *s) { my_printf(s, 1); }
