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

@implementation iTermStatusBarHostnameComponent {
    NSString *_compressedString;
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration {
    return [super initWithPath:@"session.hostname" configuration:configuration];
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
                            __block int count = 0;
                            [part enumerateComposedCharacters:^(NSRange range, unichar simple, NSString *complexString, BOOL *stop) {
                                count++;
                                if (count > 1) {
                                    // Has more than one composed character so the last one seen will be its abbreviation, stored in `replacement`.
                                    *stop = YES;
                                } else {
                                    replacement = [part substringWithRange:range];
                                }
                            }];
                            return count > 1;
                        }];
    if (index == NSNotFound) {
        return nil;
    }
    parts[index] = replacement;
    return [parts componentsJoinedByString:@"."];
}

- (NSString *)stringForWidth:(CGFloat)newWidth {
    NSString *string = self.stringValue;
    NSString *lastGood = self.stringValue;
    while (string != nil && [self widthForString:string] > newWidth) {
        lastGood = string;
        string = [self stringByCompressingString:string];
    }
    return string ?: lastGood;
}

- (void)statusBarComponentWidthDidChangeTo:(CGFloat)newWidth {
    _compressedString = [self stringForWidth:newWidth];
    [self updateTextFieldIfNeeded];
}

- (nullable NSString *)maximallyCompressedStringValue {
    return [self stringForWidth:0];
}

- (nullable NSString *)stringValueForCurrentWidth {
    return _compressedString;
}

@end

@implementation iTermStatusBarUsernameComponent

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration {
    return [super initWithPath:@"session.username" configuration:configuration];
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
    if (!self.stringValue) {
        return [super statusBarComponentMinimumWidth];
    }
    NSString *rest;
    NSString *prefix = [self.stringValue firstComposedCharacter:&rest];
    if (rest.length > 0) {
        prefix = [prefix stringByAppendingString:@"…"];
    }
    return [self widthForString:prefix];
}

@end

@implementation iTermStatusBarWorkingDirectoryComponent {
    NSString *_compressedString;
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration {
    return [super initWithPath:@"session.path" configuration:configuration];
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
        __block int count = 0;
        [part enumerateComposedCharacters:^(NSRange range, unichar simple, NSString *complexString, BOOL *stop) {
            count++;
            if (count > 1) {
                // Has more than one composed character so the last one seen will be its abbreviation, stored in `replacement`.
                *stop = YES;
            } else {
                replacement = [part substringWithRange:range];
            }
        }];
        return count > 1;
    }];
    if (index == NSNotFound) {
        return nil;
    }
    parts[index] = replacement;
    return [parts componentsJoinedByString:@"/"];
}

- (NSString *)stringForWidth:(CGFloat)newWidth {
    NSString *string = self.stringValue;
    NSString *lastGood = self.stringValue;
    while (string != nil && [self widthForString:string] > newWidth) {
        lastGood = string;
        string = [self stringByCompressingString:string];
    }
    return string ?: lastGood;
}

- (void)statusBarComponentWidthDidChangeTo:(CGFloat)newWidth {
    _compressedString = [self stringForWidth:newWidth];
    [self updateTextFieldIfNeeded];
}

- (nullable NSString *)maximallyCompressedStringValue {
    return [self stringForWidth:0];
}

- (nullable NSString *)stringValueForCurrentWidth {
    return _compressedString;
}

@end

NS_ASSUME_NONNULL_END
