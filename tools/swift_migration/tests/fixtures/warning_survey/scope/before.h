// Imported before iTermStrictWarnings.h: its inline function is not held to the strict set,
// but its macro is, where it is expanded after the import.
#define ASSIGN_NARROW(dst, src) dst = src
static inline int before_inline(long v) { return v; }
