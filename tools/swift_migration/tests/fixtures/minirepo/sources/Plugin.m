#import "Plugin.h"

@implementation PluginBase

+ (PluginBase *)pluginNamed:(NSString *)name {
    Class c = NSClassFromString(name);
    if (![c isSubclassOfClass:[PluginBase class]]) {
        return nil;
    }
    return [[c alloc] init];
}

+ (id)loadableNamed:(NSString *)name {
    Class c = NSClassFromString(name);
    if (![c conformsToProtocol:@protocol(FixtureLoadable)]) {
        return nil;
    }
    return [[c alloc] init];
}

+ (id)responderNamed:(NSString *)name {
    Class c = NSClassFromString(name);
    if (![c instancesRespondToSelector:@selector(initWithFixture:)]) {
        return nil;
    }
    return [[c alloc] initWithFixture:nil];
}

+ (id)anythingNamed:(NSString *)name {
    Class c = NSClassFromString(name);
    return [[c alloc] init];
}

@end
