// A wrong Objective-C extraction of out_object in before.m: the out-parameter
// is __autoreleasing, the ARC default for a pointer to an object pointer.
// via_method is extracted to a C function, which cannot reach the ivar
// through self, so it takes self explicitly.
#define nil ((id)0)
id make(void);
void consume(id);
void log_line(const char *, int, const char *);

__attribute__((objc_root_class))
@interface Base2
- (instancetype)init;
- (void)poke;
@end

@interface Holder : Base2 {
@public
    int _count;
}
@end

@implementation Holder

static void out_object_helper(id *result) {
    // out_object{
    *result = make();
    consume(*result);
    // out_object}
}

- (void)outObject {
    id result = nil;
    out_object_helper(&result);
    consume(result);
}

static void via_method_helper(Holder *holder, __strong id *result) {
    // via_method{
    *result = make();
    holder->_count++;
    log_line(__FILE__, __LINE__, __func__);
    // via_method}
}

- (void)viaMethod {
    id result = nil;
    via_method_helper(self, &result);
    consume(result);
}

@end

@interface Holder (Other)
- (void)superPokeHelper;
@end

@implementation Holder (Init)
- (instancetype)initCommon {
    // init_self{
    self = [super init];
    if (self) {
        consume(self);
    }
    // init_self}
    return self;
}

- (void)superPoke {
    consume(nil);
    [self superPokeHelper];
}
@end

// super from a method in another category.
@implementation Holder (Other)
- (void)superPokeHelper {
    // super_poke{
    [super poke];
    // super_poke}
}
// The helper returns self, not x.
- (id)selfAnyHelper {
    id x = nil;
    // self_any{
    x = make();
    // self_any}
    return self;
}

- (id)selfAny {
    id x = nil;
    x = [self selfAnyHelper];
    return x;
}
@end
