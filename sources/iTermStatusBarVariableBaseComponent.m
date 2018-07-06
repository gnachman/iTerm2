//
//  iTermStatusBarVariableBaseComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/1/18.
//

#import "iTermStatusBarVariableBaseComponent.h"

#import "iTermVariables.h"
#import "NSDictionary+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermStatusBarVariableBaseComponent {
    NSString *_path;
}

- (instancetype)initWithPath:(NSString *)path
               configuration:(NSDictionary *)configuration {
    NSDictionary *knobValueOverrides = @{ @"path": path };
    NSMutableDictionary *mergedConfiguration = [configuration ?: @{} mutableCopy];
    NSDictionary *knobValues = [mergedConfiguration[iTermStatusBarComponentConfigurationKeyKnobValues] ?: @{} mutableCopy];
    knobValues = [knobValues dictionaryByMergingDictionary:knobValueOverrides];
    mergedConfiguration[iTermStatusBarComponentConfigurationKeyKnobValues] = knobValues;
    
    self = [super initWithConfiguration:mergedConfiguration];
    if (self) {
        _path = path;
    }
    return self;
}

+ (NSString *)statusBarComponentShortDescription {
    [self doesNotRecognizeSelector:_cmd];
    return @"";
}

+ (NSString *)statusBarComponentDetailedDescription {
    [self doesNotRecognizeSelector:_cmd];
    return @"";
}

- (id)statusBarComponentExemplar {
    [self doesNotRecognizeSelector:_cmd];
    return @"";
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (nullable NSString *)stringValue {
    return [self.scope valueForVariableName:_path];
}

- (NSSet<NSString *> *)statusBarComponentVariableDependencies {
    return [NSSet setWithObject:_path];
}

- (void)statusBarComponentVariablesDidChange:(NSSet<NSString *> *)variables {
    [self setStringValue:self.stringValue];
}

- (void)statusBarComponentSetVariableScope:(iTermVariableScope *)scope {
    [super statusBarComponentSetVariableScope:scope];
    [self setStringValue:self.stringValue];
}

@end

@implementation iTermStatusBarHostnameComponent

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration {
    return [super initWithPath:@"session.hostname" configuration:configuration];
}

+ (NSString *)statusBarComponentShortDescription {
    return @"Host Name";
}

+ (NSString *)statusBarComponentDetailedDescription {
    return @"Current host name. Requires shell integration.";
}

- (id)statusBarComponentExemplar {
    return @"example.com";
}

@end

@implementation iTermStatusBarUsernameComponent

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration {
    return [super initWithPath:@"session.username" configuration:configuration];
}

+ (NSString *)statusBarComponentShortDescription {
    return @"User Name";
}

+ (NSString *)statusBarComponentDetailedDescription {
    return @"Current user name. Requires shell integration.";
}

- (id)statusBarComponentExemplar {
    return NSUserName();
}


@end

@implementation iTermStatusBarWorkingDirectoryComponent

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration {
    return [super initWithPath:@"session.path" configuration:configuration];
}

+ (NSString *)statusBarComponentShortDescription {
    return @"Current Directory";
}

+ (NSString *)statusBarComponentDetailedDescription {
    return @"Current directory. Best with shell integration.";
}

- (id)statusBarComponentExemplar {
    return NSHomeDirectory();
}

@end

NS_ASSUME_NONNULL_END
