//
//  iTermStatusBarVariableBaseComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/1/18.
//

#import "iTermStatusBarVariableBaseComponent.h"

#import "iTermShellHistoryController.h"
#import "iTermVariableScope.h"
#import "iTermVariableReference.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "VT100RemoteHost.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermStatusBarVariableBaseComponent {
    NSString *_path;
    iTermVariableReference *_ref;
}

- (instancetype)initWithPath:(nullable NSString *)path
               configuration:(NSDictionary *)configuration
                       scope:(iTermVariableScope *)scope {
    NSMutableDictionary *mergedConfiguration = [configuration ?: @{} mutableCopy];

    if (path) {
        NSDictionary *knobValueOverrides = @{ @"path": path };
        NSDictionary *knobValues = [mergedConfiguration[iTermStatusBarComponentConfigurationKeyKnobValues] ?: @{} mutableCopy];
        knobValues = [knobValues dictionaryByMergingDictionary:knobValueOverrides];
        mergedConfiguration[iTermStatusBarComponentConfigurationKeyKnobValues] = knobValues;
    }
    
    self = [super initWithConfiguration:mergedConfiguration scope:scope];
    if (self) {
        _path = path;
        if (path) {
            _ref = [[iTermVariableReference alloc] initWithPath:path scope:scope];
            __weak __typeof(self) weakSelf = self;
            _ref.onChangeBlock = ^{
                [weakSelf updateTextFieldIfNeeded];
            };
        }
        [self updateTextFieldIfNeeded];
    }
    return self;
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey,id> *)configuration
                                scope:(nullable iTermVariableScope *)scope {
    return [self initWithPath:nil configuration:configuration scope:scope];
}

- (NSString *)statusBarComponentShortDescription {
    [self doesNotRecognizeSelector:_cmd];
    return @"";
}

- (NSString *)statusBarComponentDetailedDescription {
    [self doesNotRecognizeSelector:_cmd];
    return @"";
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
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
    return [self variantsOf:[self transformedValue:self.cached ?: @""]];
}

- (NSString *)transformedValue:(NSString *)value {
    return value;
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

- (nullable NSString *)stringByCompressingString:(NSString *)source {
    return nil;
}

@end

@implementation iTermStatusBarHostnameComponent

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration
                                scope:(nullable iTermVariableScope *)scope {
    return [super initWithPath:@"hostname" configuration:configuration scope:scope];
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

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    return @"example.com";
}

- (nullable NSString *)stringByCompressingString:(NSString *)source {
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

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration
                                scope:(nullable iTermVariableScope *)scope {
    return [super initWithPath:@"username" configuration:configuration scope:scope];
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

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
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


@implementation iTermStatusBarWorkingDirectoryComponent {
    NSString *_home;
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration
                                scope:(nullable iTermVariableScope *)scope {
    _home = [NSHomeDirectory() copy];
    return [super initWithPath:@"path" configuration:configuration scope:scope];
}

- (NSString *)transformedValue:(NSString *)value {
    if (_home && [value hasPrefix:_home]) {
        return [@"~" stringByAppendingString:[value substringFromIndex:_home.length]];
    } else {
        return value;
    }
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    return [self.minMaxWidthKnobs arrayByAddingObjectsFromArray:[super statusBarComponentKnobs]];
}

- (NSImage *)statusBarComponentIcon {
    return [NSImage it_imageNamed:@"StatusBarIconFolder" forClass:[self class]];
}

- (CGFloat)statusBarComponentPreferredWidth {
    return [self clampedWidth:[super statusBarComponentPreferredWidth]];
}

+ (NSDictionary *)statusBarComponentDefaultKnobs {
    NSDictionary *fromSuper = [super statusBarComponentDefaultKnobs];
    return [fromSuper dictionaryByMergingDictionary:self.defaultMinMaxWidthKnobValues];
}

- (NSString *)statusBarComponentShortDescription {
    return @"Current Directory";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Current directory. Best with shell integration.";
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    return NSHomeDirectory();
}

- (nullable NSString *)stringByCompressingString:(NSString *)source {
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

- (BOOL)statusBarComponentHandlesClicks {
    return YES;
}

- (void)statusBarComponentDidClickWithView:(NSView *)view {
    [self openMenuWithView:view];
}

- (void)statusBarComponentMouseDownWithView:(NSView *)view {
    [self openMenuWithView:view];
}

- (void)openMenuWithView:(NSView *)view {
    NSMenu *menu = [[NSMenu alloc] init];
    NSView *containingView = view.superview;

    VT100RemoteHost *remoteHost = [self remoteHost];
    for (iTermRecentDirectoryMO *directory in [[[iTermShellHistoryController sharedInstance] directoriesSortedByScoreOnHost:remoteHost] it_arrayByKeepingFirstN:10]) {
        NSString *title;
        if (directory.starred.boolValue) {
            title = [@"★ " stringByAppendingString:directory.path];
        } else {
            title = directory.path;
        }
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(directorySelected:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = directory.path;
        [menu addItem:item];
    }
    [menu popUpMenuPositioningItem:menu.itemArray.firstObject atLocation:NSMakePoint(0, 0) inView:containingView];
}

- (void)directorySelected:(NSMenuItem *)sender {
    NSString *path = sender.representedObject;
    [self.delegate statusBarComponent:self
                          writeString:[NSString stringWithFormat:@"cd %@", [path stringWithEscapedShellCharactersIncludingNewlines:YES]]];
}

- (VT100RemoteHost *)remoteHost {
    VT100RemoteHost *result = [[VT100RemoteHost alloc] init];
    result.hostname = [self.scope valueForVariableName:iTermVariableKeySessionHostname];
    result.username = [self.scope valueForVariableName:iTermVariableKeySessionUsername];
    return result;
}

@end

NS_ASSUME_NONNULL_END
