// The before version of the Objective-C extractions in safe.m and broken.m
// (compiled with ARC). Each block is the lines between "// NAME{" and
// "// NAME}".
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

- (void)outObject {
    id result = nil;
    // out_object{
    result = make();
    consume(result);
    // out_object}
    consume(result);
}

- (void)viaMethod {
    id result = nil;
    // via_method{
    result = make();
    _count++;
    log_line(__FILE__, __LINE__, __func__);
    // via_method}
    consume(result);
}

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
    // super_poke{
    [super poke];
    // super_poke}
}
- (id)selfAny {
    id x = nil;
    // self_any{
    x = make();
    // self_any}
    return x;
}
@end
