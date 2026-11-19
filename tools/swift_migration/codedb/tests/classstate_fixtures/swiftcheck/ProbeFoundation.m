// Fixture: the implementation whose synthesized ivars carry the facts of
// ProbeFoundation.h's property types. FProbe's ivar _identifier is named
// like -[NSView identifier], which it inherits; FDeep's _layer like
// -[NSView layer], two superclasses up.
#import "ProbeFoundation.h"
@implementation FGen
@end
@implementation FProbe {
    int _identifier;
}
@end
@implementation FDeep {
    int _layer;
    int _fancy;
}
@end
// A repository category on an SDK class: FDeep inherits -isFancy from it.
@interface NSObject (FProbeCategory)
- (int)isFancy;
@end
@implementation NSObject (FProbeCategory)
- (int)isFancy {
    return 0;
}
@end
