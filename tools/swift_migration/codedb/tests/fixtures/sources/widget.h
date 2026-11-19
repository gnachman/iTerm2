// Fixture: a root class, so that no SDK is needed.
__attribute__((objc_root_class))
@interface Widget
@property (nonatomic) int title;
+ (instancetype)make;
- (id)copy;
- (void)doThing;
- (int)load_alpha;
- (void)helperSend;
- (Widget *)makeThing;
- (id)objectAtIndexedSubscript:(long)i;
- (int)other;
- (int)vm;
- (int)gen;
@end
