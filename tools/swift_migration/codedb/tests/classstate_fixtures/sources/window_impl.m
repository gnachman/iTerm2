// Fixture: a class body included with THE_CLASS defined, as iTermWindowImpl.m is. Line numbers are part of the expectations.
#ifndef THE_CLASS
#define THE_CLASS JustForTheEditor
#define SPECIAL 1
@interface THE_CLASS : Thing
@end
#endif
@interface THE_CLASS : Root {
    int _w;
}
@end
@implementation THE_CLASS
- (void)wave {
    _w = 1;
}
#if SPECIAL
- (void)special {
}
#else
- (void)ordinary {
}
#endif
#if NEVER_DEFINED
- (void)never {
}
#elif SPECIAL
- (void)alsoSpecial {
}
#else
- (void)alsoOrdinary {
}
#endif
@end
