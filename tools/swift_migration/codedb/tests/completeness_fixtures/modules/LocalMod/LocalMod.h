// Fixture: a repository header that units read only through a Clang module
// (test_codedb_completeness.py, ModuleHeaderTest).
__attribute__((objc_root_class))
@interface ModBase {
    int _count;
    id _object;
}
@property (nonatomic) int size;
- (void)poke;
+ (instancetype)make;
@end
@protocol ModProto
- (void)required;
@optional
- (void)optionalOne;
@end
@interface ModChild : ModBase <ModProto> {
    double _extra;
}
@end
@interface ModBase (ModCat)
- (void)catMethod;
@end
extern int ModGlobal;
static const int ModConstant = 3;
@protocol ModChildProto <ModProto>
@end
