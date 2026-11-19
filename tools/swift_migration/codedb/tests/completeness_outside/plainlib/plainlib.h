// Fixture: a library outside the repository that is not a framework.
__attribute__((objc_root_class))
@interface PLThing
- (void)plainThing;
#ifdef __cplusplus
- (void)plainCxxOnly;
#endif
@end
