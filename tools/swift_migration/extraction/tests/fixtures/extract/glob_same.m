// The same string, class and selector in the helpers: compares identical (the function name string differs by design).
#define nil ((id)0)
__attribute__((objc_root_class))
@interface NSObject
+ (id)class;
- (void)foo;
- (void)bar;
@end
@interface NSString : NSObject
@end
@interface NSArray : NSObject
@end
void consume(id);
void consume_c(const char *);
int counter;

static void cfs_helper(void) {
    // cfs{
    consume(@"alpha");
    // cfs}
}

void cfs(int n) {
    counter += n;
    cfs_helper();
    counter--;
}

static void cls_helper(void) {
    // cls{
    consume([NSString class]);
    // cls}
}

void cls(int n) {
    counter += n;
    cls_helper();
    counter--;
}

static void sel_helper(id x) {
    // sel{
    [x foo];
    // sel}
}

void sel(id x) {
    counter++;
    sel_helper(x);
    counter--;
}

static void ffunc_helper(void) {
    // ffunc{
    consume_c(__func__);
    // ffunc}
}

void ffunc(int n) {
    counter += n;
    ffunc_helper();
    counter--;
}
