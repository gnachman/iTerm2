// Fixture: macros defined outside the repository, as the SDK's are.
#define SDK_MIN(a, b) ((a) < (b) ? (a) : (b))
#define SDK_PING(obj) [obj ping]
// As the SDK's MAX: names made by pasting a counter, in a statement expression.
#define __SDK_IMPL(A, B, L) ({ __typeof__(A) __a##L = (A); __typeof__(B) __b##L = (B); __a##L < __b##L ? __b##L : __a##L; })
#define SDK_MAX(A, B) __SDK_IMPL(A, B, __COUNTER__)
