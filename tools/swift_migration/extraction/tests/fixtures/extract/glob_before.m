// Compiler-emitted globals in Objective-C: the before version.
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

void cfs(int n) {
    counter += n;
    // cfs{
    consume(@"alpha");
    // cfs}
    counter--;
}

void cls(int n) {
    counter += n;
    // cls{
    consume([NSString class]);
    // cls}
    counter--;
}

void sel(id x) {
    counter++;
    // sel{
    [x foo];
    // sel}
    counter--;
}

void ffunc(int n) {
    counter += n;
    // ffunc{
    consume_c(__func__);
    // ffunc}
    counter--;
}
