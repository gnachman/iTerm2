//
//  iTermStatusBarVariableBaseComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/1/18.
//

#import "iTermStatusBarVariableBaseComponent.h"

#import "iTermController.h"
#import "iTermSessionLauncher.h"
#import "iTermShellHistoryController.h"
#import "iTermVariableScope.h"
#import "iTermVariableReference.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSHost+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "iTermProfile.h"
#import "ProfileModel.h"
#import "iTermProfilePreferences.h"
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
            _ref = [[iTermVariableReference alloc] initWithPath:path vendor:scope];
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
    NSArray<NSString *> *parts = [string componentsSeparatedByString:@"."];
    if (parts.count > 1) {
        NSString *localname = parts.firstObject;
        if ([localname length] > 1) {
            for (NSInteger numberToOmit = 2; numberToOmit < parts.firstObject.numberOfComposedCharacters - 2; numberToOmit++) {
                [result addObject:[parts.firstObject byTruncatingComposedCharactersInCenter:numberToOmit]];
            }
            [result addObject:parts.firstObject];
        }
    }
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

static NSString *const iTermStatusBarHostnameComponentAbbreviateLocalhost = @"abbreviate-localhost";

@implementation iTermStatusBarHostnameComponent

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration
                                scope:(nullable iTermVariableScope *)scope {
    return [super initWithPath:@"hostname" configuration:configuration scope:scope];
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    iTermStatusBarComponentKnob *abbreviateLocalhostKnob =
    [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"localhost replacement"
                                                      type:iTermStatusBarComponentKnobTypeText
                                               placeholder:@"Enter replacement text for localhost"
                                              defaultValue:@""
                                                       key:iTermStatusBarHostnameComponentAbbreviateLocalhost];
    return [@[ abbreviateLocalhostKnob ] arrayByAddingObjectsFromArray:[super statusBarComponentKnobs]];
}

- (nullable NSImage *)statusBarComponentIcon {
    return [NSImage it_cacheableImageNamed:@"StatusBarIconHost" forClass:[self class]];
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

- (nullable NSArray<NSString *> *)stringVariants {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    NSString *abbreviation = [NSString castFrom:knobValues[iTermStatusBarHostnameComponentAbbreviateLocalhost]];
    if (abbreviation.length &&
        [[NSHost fullyQualifiedDomainName] isEqualToString:self.cached]) {
        return @[ abbreviation ];
    }
    return [super stringVariants];
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
    parts[index] = replacement ?: @"";
    return [parts componentsJoinedByString:@"."];
}

@end

@implementation iTermStatusBarUsernameComponent

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey, id> *)configuration
                                scope:(nullable iTermVariableScope *)scope {
    return [super initWithPath:@"username" configuration:configuration scope:scope];
}

+ (ProfileType)compatibleProfileTypes {
    return ProfileTypeTerminal;
}

- (nullable NSImage *)statusBarComponentIcon {
    return [NSImage it_cacheableImageNamed:@"StatusBarIconUser" forClass:[self class]];
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

+ (ProfileType)compatibleProfileTypes {
    return ProfileTypeTerminal;
}

- (nullable NSImage *)statusBarComponentIcon {
    return [NSImage it_cacheableImageNamed:@"StatusBarIconFolder" forClass:[self class]];
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

- (nullable NSString *)statusBarComponentCopyableString {
    return self.fullString;
}

- (BOOL)statusBarComponentHandlesClicks {
    return YES;
}

- (BOOL)statusBarComponentIsEmpty {
    return [[self.fullString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0;
}

- (void)statusBarComponentDidClickWithView:(NSView *)view {
    [self openMenuWithView:view];
}

- (BOOL)statusBarComponentHandlesMouseDown:(NSView *)view {
    return YES;
}

- (void)statusBarComponentMouseDownWithView:(NSView *)view {
    [self openMenuWithView:view];
}

- (void)openMenuWithView:(NSView *)view {
    NSMenu *menu = [[NSMenu alloc] init];
    NSView *containingView = view.superview;

    id<VT100RemoteHostReading> remoteHost = [self remoteHost];
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

    NSString *currentPath = self.fullString;
    if (currentPath.length) {
        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *copyPath = [[NSMenuItem alloc] initWithTitle:@"Copy Path"
                                                          action:@selector(copyCurrentPath:)
                                                   keyEquivalent:@""];
        copyPath.target = self;
        [menu addItem:copyPath];

        NSMenuItem *copyBasename = [[NSMenuItem alloc] initWithTitle:@"Copy Folder Name"
                                                              action:@selector(copyCurrentBasename:)
                                                       keyEquivalent:@""];
        copyBasename.target = self;
        [menu addItem:copyBasename];

        NSMenuItem *openInFinder = [[NSMenuItem alloc] initWithTitle:@"Reveal in Finder"
                                                              action:@selector(openCurrentPathInFinder:)
                                                       keyEquivalent:@""];
        openInFinder.target = self;
        [menu addItem:openInFinder];

        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *openInNewWindow = [[NSMenuItem alloc] initWithTitle:@"New Session Here in New Window"
                                                                 action:@selector(openCurrentPathInNewWindow:)
                                                          keyEquivalent:@""];
        openInNewWindow.target = self;
        [menu addItem:openInNewWindow];

        NSMenuItem *openInNewTab = [[NSMenuItem alloc] initWithTitle:@"New Session Here in New Tab"
                                                              action:@selector(openCurrentPathInNewTab:)
                                                       keyEquivalent:@""];
        openInNewTab.target = self;
        [menu addItem:openInNewTab];
    }

    [menu popUpMenuPositioningItem:menu.itemArray.firstObject atLocation:NSMakePoint(0, 0) inView:containingView];
}

- (void)directorySelected:(NSMenuItem *)sender {
    NSString *path = sender.representedObject;
    [self.delegate statusBarComponent:self
                          writeString:[NSString stringWithFormat:@"cd %@", [path stringWithEscapedShellCharactersIncludingNewlines:YES]]];
}

- (id<VT100RemoteHostReading>)remoteHost {
    VT100RemoteHost *result = [[VT100RemoteHost alloc] initWithUsername:[self.scope valueForVariableName:iTermVariableKeySessionUsername]
                                                               hostname:[self.scope valueForVariableName:iTermVariableKeySessionHostname]];
    return result;
}

- (void)copyCurrentPath:(NSMenuItem *)sender {
    NSString *path = self.fullString;
    if (path.length) {
        [[NSPasteboard generalPasteboard] clearContents];
        [[NSPasteboard generalPasteboard] setString:path forType:NSPasteboardTypeString];
    }
}

- (void)copyCurrentBasename:(NSMenuItem *)sender {
    NSString *path = self.fullString;
    if (path.length) {
        [[NSPasteboard generalPasteboard] clearContents];
        [[NSPasteboard generalPasteboard] setString:[path lastPathComponent] forType:NSPasteboardTypeString];
    }
}

- (void)openCurrentPathInFinder:(NSMenuItem *)sender {
    NSString *path = self.fullString;
    if (path.length) {
        [[NSWorkspace sharedWorkspace] selectFile:nil inFileViewerRootedAtPath:path];
    }
}

- (void)openCurrentPathInNewWindow:(NSMenuItem *)sender {
    [self launchSessionWithPath:self.fullString style:iTermOpenStyleWindow terminal:nil];
}

- (void)openCurrentPathInNewTab:(NSMenuItem *)sender {
    NSString *path = self.fullString;
    PseudoTerminal *currentTerminal = [[iTermController sharedInstance] currentTerminal];
    if (currentTerminal) {
        [self launchSessionWithPath:path style:iTermOpenStyleTab terminal:currentTerminal];
    } else {
        [self launchSessionWithPath:path style:iTermOpenStyleWindow terminal:nil];
    }
}

- (void)launchSessionWithPath:(NSString *)path
                        style:(iTermOpenStyle)style
                     terminal:(nullable PseudoTerminal *)terminal {
    if (!path.length) {
        return;
    }
    MutableProfile *profile = [[[ProfileModel sharedInstance] defaultBookmark] mutableCopy];
    if (!profile) {
        return;
    }
    profile[KEY_WORKING_DIRECTORY] = path;
    profile[KEY_CUSTOM_DIRECTORY] = kProfilePreferenceInitialDirectoryCustomValue;
    [iTermSessionLauncher launchBookmark:profile
                              inTerminal:terminal
                                   style:style
                                 withURL:nil
                        hotkeyWindowType:iTermHotkeyWindowTypeNone
                                 makeKey:YES
                             canActivate:YES
                      respectTabbingMode:NO
                                   index:nil
                                 command:nil
                             makeSession:nil
                          didMakeSession:nil
                              completion:nil];
}

@end

NS_ASSUME_NONNULL_END
