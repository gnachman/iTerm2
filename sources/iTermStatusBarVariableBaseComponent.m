//
//  iTermStatusBarVariableBaseComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/1/18.
//

#import "iTermStatusBarVariableBaseComponent.h"

#import "iTermVariables.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermStatusBarVariableBaseComponent {
    NSString *_path;
}

- (instancetype)initWithPath:(NSString *)path {
    NSDictionary *knobValues = @{ @"path": path };
    self = [super initWithConfiguration:@{iTermStatusBarComponentConfigurationKeyKnobValues: knobValues}];
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

+ (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    return @[];
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

- (instancetype)init {
    return [super initWithPath:@"session.hostname"];
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration {
    return [self init];
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

- (instancetype)init {
    return [super initWithPath:@"session.username"];
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration {
    return [self init];
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

- (instancetype)init {
    return [super initWithPath:@"session.path"];
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration {
    return [self init];
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
