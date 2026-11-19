// The helper assigns self but returns nil: -initCommon now returns nil.
// Correct Objective-C extractions of the blocks in before.m. Each block is
// now the lines between "// NAME{" and "// NAME}" inside its helper.
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
    int _count;
}
@end

@implementation Holder

static void out_object_helper(__strong id *result) {
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

- (void)viaMethodHelper:(__strong id *)result {
    // via_method{
    *result = make();
    _count++;
    log_line(__FILE__, __LINE__, __func__);
    // via_method}
}

- (void)viaMethod {
    id result = nil;
    [self viaMethodHelper:&result];
    consume(result);
}

@end

@implementation Holder (Init)
- (instancetype)initCommonHelper {
    // init_self{
    self = [super init];
    if (self) {
        consume(self);
    }
    // init_self}
    return nil;
}

- (instancetype)initCommon {
    self = [self initCommonHelper];
    return self;
}

- (void)superPokeHelper {
    // super_poke{
    [super poke];
    // super_poke}
}

- (void)superPoke {
    consume(nil);
    [self superPokeHelper];
}
@end
