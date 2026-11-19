// Fixture: declarations in every kind of container. Line numbers are part of the expectations.
#import "sel_base.h"
@protocol Shape
@property (nonatomic, readonly) int sides;
- (void)draw;
@optional
+ (id)shapeNamed:(id)name;
@end
@interface Gadget : Base <Shape>
@property (nonatomic) int count;
@property (nonatomic, getter=isOn, setter=turn:) int on;
@property (nonatomic, readonly, getter=label) id name;
@property (nonatomic, readonly) int size;
@property (nonatomic, strong) id dyn;
@property (class, nonatomic) int shared;
- (void)reset:(int)a with:(int)b;
@end
@interface Gadget (Extras)
- (void)extra;
@property (nonatomic, readonly) int extraCount;
@end
