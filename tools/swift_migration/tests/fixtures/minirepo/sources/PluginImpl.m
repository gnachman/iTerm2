#import "Plugin.h"

@interface PluginImpl : PluginBase
@end

@implementation PluginImpl
@end

@interface LoadableThing : NSObject <FixtureLoadableMore>
@end

@implementation LoadableThing
@end

@interface FixtureResponder : NSObject
@end

@implementation FixtureResponder
- (instancetype)initWithFixture:(id)fixture {
    return [super init];
}
@end

@interface Bystander : NSObject
@end

@implementation Bystander
- (instancetype)initWithOther:(id)other {
    return [super init];
}
@end
