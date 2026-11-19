// Fixture: C arrays that decay to pointers, compiled with ARC. Line numbers are part of the expectations.
#import "state_base.h"
void *memcpy(void *dst, const void *src, unsigned long n);
void *memmove(void *dst, const void *src, unsigned long n);
// As the SDK's secure headers define it when fortified.
#define memmove(d, s, n) __builtin___memmove_chk(d, s, n, __builtin_object_size(d, 0))
unsigned long strlen(const char *s);
int pipe(int fds[2]);
void FillStats(int *stats);
void ReadInt(const int *p);
static int gPipe[2];
static char gPrefix[8];
static char gName[8];
@interface Arrays : Root
@end
@implementation Arrays {
    double _last[4];
    int _stats[3];
    char _src[8];
    struct { int vals[2]; } _pair;
    int _n;
}
- (void)run:(const double *)d {
    pipe(gPipe);
    memcpy(gPrefix, _src, 8);
    memmove(_last, d, 32);
    FillStats(_stats);
    (void)strlen(gName);
    _stats[1] = 2;
    (void)_stats[0];
    const char *cp = _src;
    char *p = _src;
    p = _src + 1;
    FillStats(_pair.vals);
    ReadInt(&_n);
    FillStats(&_n);
    (void)cp;
}
- (const char *)name {
    return gName;
}
- (char *)mutableName {
    return gName;
}
@end
