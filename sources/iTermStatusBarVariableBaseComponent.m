//
//  iTermStatusBarVariableBaseComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/1/18.
//

#import "iTermStatusBarVariableBaseComponent.h"

#import "iTermVariables.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

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

- (NSString *)statusBarComponentShortDescription {
    [self doesNotRecognizeSelector:_cmd];
    return @"";
}

- (NSString *)statusBarComponentDetailedDescription {
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

- (NSString *)fullString {
    return [self.scope valueForVariableName:_path];
}

- (nullable NSArray<NSString *> *)stringVariants {
    return [self variantsOf:self.cached ?: @""];
}

- (NSSet<NSString *> *)statusBarComponentVariableDependencies {
    return [NSSet setWithObject:_path];
}

- (void)statusBarComponentVariablesDidChange:(NSSet<NSString *> *)variables {
    [self updateTextFieldIfNeeded];
}

- (void)statusBarComponentSetVariableScope:(iTermVariableScope *)scope {
    [super statusBarComponentSetVariableScope:scope];
    [self updateTextFieldIfNeeded];
}

- (void)updateTextFieldIfNeeded {
    _cached = self.fullString;
    [super updateTextFieldIfNeeded];
}

- (NSArray<NSString *> *)variantsOf:(NSString *)string {
    if (string.length == 0) {
        return @[];
    }

    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSString *prev = nil;
    while (string != nil && (!prev || string.length < prev.length)) {
        [result addObject:string];
        prev = string;
        string = [self stringByCompressingString:string];
    }
    return [result copy];
}

- (NSString *)stringByCompressingString:(NSString *)source {
    return nil;
}

@end

@implementation iTermStatusBarHostnameComponent

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration {
    return [super initWithPath:@"session.hostname" configuration:configuration];
}

- (NSImage *)statusBarComponentIcon {
    return [NSImage it_imageNamed:@"StatusBarIconHost" forClass:[self class]];
}

- (NSString *)statusBarComponentShortDescription {
    return @"Host Name";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Current host name. Requires shell integration.";
}

- (id)statusBarComponentExemplar {
    return @"example.com";
}

- (NSString *)stringByCompressingString:(NSString *)source {
    NSMutableArray<NSString *> *parts = [[source componentsSeparatedByString:@"."] mutableCopy];
    __block NSString *replacement = nil;
    NSUInteger index = [parts indexOfObjectWithOptions:NSEnumerationReverse
                                           passingTest:
                        ^BOOL(NSString * _Nonnull part, NSUInteger idx, BOOL * _Nonnull stop) {
                            replacement = [part firstComposedCharacter:nil];
                            return ![replacement isEqualToString:part];
                        }];
    if (index == NSNotFound) {
        return nil;
    }
    parts[index] = replacement;
    return [parts componentsJoinedByString:@"."];
}

@end

@implementation iTermStatusBarUsernameComponent

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration {
    return [super initWithPath:@"session.username" configuration:configuration];
}

- (NSImage *)statusBarComponentIcon {
    return [NSImage it_imageNamed:@"StatusBarIconUser" forClass:[self class]];
}

- (NSString *)statusBarComponentShortDescription {
    return @"User Name";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Current user name. Requires shell integration.";
}

- (id)statusBarComponentExemplar {
    return NSUserName();
}

- (CGFloat)statusBarComponentMinimumWidth {
    CGFloat full = [self widthForString:self.cached ?: @""];
    NSString *firstCharacter = [self.cached firstComposedCharacter:nil];
    if (!firstCharacter) {
        return full;
    }
    NSString *truncated = [firstCharacter stringByAppendingString:@"…"];
    CGFloat trunc = [self widthForString:truncated];
    return MIN(full, trunc);
}

- (nullable NSString *)stringForWidth:(CGFloat)width {
    return self.cached;
}

@end

@implementation iTermStatusBarWorkingDirectoryComponent

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration {
    return [super initWithPath:@"session.path" configuration:configuration];
}

- (NSImage *)statusBarComponentIcon {
    return [NSImage it_imageNamed:@"StatusBarIconFolder" forClass:[self class]];
}

- (NSString *)statusBarComponentShortDescription {
    return @"Current Directory";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Current directory. Best with shell integration.";
}

- (id)statusBarComponentExemplar {
    return NSHomeDirectory();
}

- (NSString *)stringByCompressingString:(NSString *)source {
    NSMutableArray<NSString *> *parts = [[source componentsSeparatedByString:@"/"] mutableCopy];
    __block NSString *replacement = nil;
    NSUInteger index = [parts indexOfObjectPassingTest:^BOOL(NSString * _Nonnull part, NSUInteger idx, BOOL * _Nonnull stop) {
        replacement = [part firstComposedCharacter:nil];
        return replacement && ![replacement isEqualToString:part];
    }];
    if (index == NSNotFound) {
        return nil;
    }
    parts[index] = replacement;
    return [parts componentsJoinedByString:@"/"];
}

@end

NS_ASSUME_NONNULL_END
