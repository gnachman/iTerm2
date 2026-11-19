// Fixture: the implementation whose synthesized ivars carry the facts of
// Probe.h's property types. A struct with a flexible array member cannot be
// an ivar, so flexS is @dynamic and a file static of its type carries them.
#import "Probe.h"
static FlexS flexS;
@implementation Probe
@dynamic flexS;
@end
