//
//  iTermGitStringMaker.m
//  iTerm2
//
//  Created by George Nachman on 4/16/26.
//

#import "iTermGitStringMaker.h"

#import "DebugLogging.h"
#import "NSAppearance+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSHost+iTerm.h"
#import "NSImage+iTerm.h"
#import "iTermGitPoller.h"
#import "iTermGitState.h"
#import "iTermGitState+MainApp.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope+Session.h"
#import "iTermVariables.h"
#import "NSObject+iTerm.h"

@implementation iTermGitStringMaker {
    // Cache of the tinted arrow/dirty glyphs. They only need rebuilding
    // when the tint color or the theme they resolve against changes, so
    // we don't re-tint identical bitmaps on every git poll. The theme
    // name is part of the key because gitTextColor is often a dynamic
    // color (e.g. labelColor) whose object identity is unchanged across
    // a light/dark switch even though what it resolves to differs.
    NSColor *_tintedGlyphColor;
    NSString *_tintedGlyphAppearanceName;
    NSAttributedString *_upImage;
    NSAttributedString *_downImage;
    NSAttributedString *_dirtyImage;
}

- (instancetype)initWithScope:(iTermVariableScope *)scope
                    gitPoller:(iTermGitPoller *)gitPoller {
    self = [super init];
    if (self) {
        _gitPoller = gitPoller;
        _scope = scope;
        gitPoller.currentDirectory = [scope valueForVariableName:iTermVariableKeySessionPath];
    }
    return self;
}

- (nullable NSAttributedString *)attributedStringValueForBranch:(NSString *)branchString {
    if (_status) {
        return [self attributedStringWithString:_status];
    }
    if (!self.pollerReady) {
        return nil;
    }
    switch (self.currentState.repoState) {
        case iTermGitRepoStateNone:
            break;
        case iTermGitRepoStateMerge:
            return [self attributedStringWithString:@"Merging"];
        case iTermGitRepoStateRevert:
            return [self attributedStringWithString:@"Reverting"];
        case iTermGitRepoStateCherrypick:
            return [self attributedStringWithString:@"Cherrypicking"];
        case iTermGitRepoStateBisect:
            return [self attributedStringWithString:@"Bisecting"];
        case iTermGitRepoStateRebase:
            return [self attributedStringWithString:@"Rebasing"];
        case iTermGitRepoStateApply:
            return [self attributedStringWithString:@"Applying"];
    }
    if (self.currentState.xcode.length > 0) {
        return [self attributedStringWithString:@"⚠️"];
    }
    NSAttributedString *branch = branchString ? [self attributedStringWithString:branchString] : nil;
    if (!branch) {
        return nil;
    }

    // The arrow/dirty glyphs are bitmaps, so unlike the text runs above
    // they can't carry a dynamic NSColor that resolves per appearance.
    // Tint them to the current git text color so they track light/dark
    // instead of showing the PNG's baked-in black. Cached so a poll that
    // doesn't change the color/theme reuses the existing bitmaps.
    [self updateTintedGlyphs];
    NSAttributedString *upImage = _upImage;
    NSAttributedString *downImage = _downImage;
    NSAttributedString *dirtyImage = _dirtyImage;

    NSAttributedString *upCount = self.currentState.ahead.integerValue > 0 ? [self attributedStringWithString:self.currentState.ahead] : nil;
    NSAttributedString *downCount = self.currentState.behind.integerValue > 0 ? [self attributedStringWithString:self.currentState.behind] : nil;

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];

    const NSInteger filesAdded = self.currentState.filesAdded;
    const NSInteger filesModified = self.currentState.filesModified;
    const NSInteger filesDeleted = self.currentState.filesDeleted;
    const NSInteger linesInserted = self.currentState.linesInserted;
    const NSInteger linesDeleted = self.currentState.linesDeleted;
    const BOOL haveRichStats = (filesAdded || filesModified || filesDeleted ||
                                linesInserted || linesDeleted);

    if (haveRichStats) {
        NSMutableArray<NSAttributedString *> *parts = [NSMutableArray array];
        if (filesAdded > 0 || filesDeleted > 0) {
            if (filesAdded == 0) {
                [parts addObject:[self attributedStringWithString:[NSString stringWithFormat:@"-%@ files",
                                                                                 @(filesDeleted)]]];
            } else if (filesDeleted == 0) {
                [parts addObject:[self attributedStringWithString:[NSString stringWithFormat:@"+%@ files",
                                                                                 @(filesAdded)]]];
            } else {
                [parts addObject:[self attributedStringWithString:[NSString stringWithFormat:@"+%@/-%@ files",
                                                                                 @(filesAdded), @(filesDeleted)]]];
            }
        }
        if (linesInserted > 0 || linesDeleted > 0) {
            if (linesInserted == 0) {
                [parts addObject:[self attributedStringWithString:[NSString stringWithFormat:@"-%@ lines",
                                                                                 @(linesDeleted)]]];
            } else if (linesDeleted == 0) {
                [parts addObject:[self attributedStringWithString:[NSString stringWithFormat:@"+%@ lines",
                                                                                 @(linesInserted)]]];
            } else {
                [parts addObject:[self attributedStringWithString:[NSString stringWithFormat:@"+%@/-%@ lines",
                                                                                 @(linesInserted), @(linesDeleted)]]];

            }
        }
        return [parts attributedComponentsJoinedByAttributedString:[self attributedStringWithString:@" "]];
    }
    
    // Minimal: the legacy adds/deletes indicator used by the status bar.
    // Built per call rather than cached in a static: gitFont/gitTextColor
    // differ between makers (e.g. the toolbar's system font + labelColor
    // vs. a status bar's profile font + configured text color), and two
    // windows can even render with different effective appearances at the
    // same time (Minimal theme derives appearance from background color).
    // A single app-wide static would freeze the first maker's font/color
    // and hand it to everyone.
    NSAttributedString *enSpace = [self attributedStringWithString:@"\u2002"];
    NSAttributedString *thinSpace = [self attributedStringWithString:@"\u2009"];
    NSAttributedString *adds = [self attributedStringWithString:@"+"];
    NSAttributedString *deletes = [self attributedStringWithString:@"-"];
    NSAttributedString *addsAndDeletes = [self attributedStringWithString:@"±"];

    [result appendAttributedString:branch];
    if (self.currentState.adds && self.currentState.deletes) {
        [result appendAttributedString:thinSpace];
        [result appendAttributedString:addsAndDeletes];
    } else {
        if (self.currentState.adds) {
            [result appendAttributedString:thinSpace];
            [result appendAttributedString:adds];
        }
        if (self.currentState.deletes) {
            [result appendAttributedString:thinSpace];
            [result appendAttributedString:deletes];
        }
    }
    if (self.currentState.dirty) {
        [result appendAttributedString:thinSpace];
        [result appendAttributedString:dirtyImage];
    }
    
    if (self.currentState.ahead.integerValue > 0) {
        [result appendAttributedString:enSpace];
        [result appendAttributedString:upImage];
        [result appendAttributedString:upCount];
    }

    if (self.currentState.behind.integerValue > 0) {
        [result appendAttributedString:enSpace];
        [result appendAttributedString:downImage];
        [result appendAttributedString:downCount];
    }

    return result;
}

- (NSAttributedString *)attributedStringWithString:(NSString *)string {
    NSDictionary *attributes = @{
        NSFontAttributeName: self.delegate.gitFont ?: [NSFont systemFontOfSize:[NSFont systemFontSize]],
        NSForegroundColorAttributeName: self.delegate.gitTextColor ?: [NSColor textColor],
        NSParagraphStyleAttributeName: self.paragraphStyle
    };
    return [[NSAttributedString alloc] initWithString:string ?: @"" attributes:attributes];
}

- (BOOL)pollerReady {
    return self.currentState && _gitPoller.enabled;
}

- (BOOL)onLocalhost {
    // Prefer the frozen locality published when the host was reported. It's
    // immune to network-driven local hostname changes, which the string
    // compare below is not.
    NSNumber *flag = [NSNumber castFrom:[self.scope valueForVariableName:iTermVariableKeySessionIsLocalhost]];
    if (flag != nil) {
        DLog(@"git poller isLocalhost variable is %@", flag);
        return flag.boolValue;
    }
    NSString *currentHostname = self.scope.hostname;
    const BOOL isLocal = [NSHost it_hostnameIsThisMachine:currentHostname];
    DLog(@"git poller current hostname is %@, it_hostnameIsThisMachine=%@ (no locality flag)", currentHostname, @(isLocal));
    return isLocal;
}

- (NSString *)branch {
    return self.currentState.branch;
}

- (NSString *)xcode {
    return self.currentState.xcode;
}

- (iTermGitState *)currentState {
    if ([self onLocalhost]) {
        return _gitPoller.state;
    } else {
        return [[iTermGitState alloc] initWithScope:self.scope];
    }
}

// Rebuild the tinted arrow/dirty glyphs only when the tint color or the
// theme they resolve against has changed since the last build.
- (void)updateTintedGlyphs {
    NSColor *tintColor = self.delegate.gitTextColor;
    NSString *appearanceName = [NSAppearance it_appearanceForCurrentTheme].name;
    const BOOL colorUnchanged = (tintColor == _tintedGlyphColor ||
                                 [tintColor isEqual:_tintedGlyphColor]);
    const BOOL appearanceUnchanged = (appearanceName == _tintedGlyphAppearanceName ||
                                      [appearanceName isEqualToString:_tintedGlyphAppearanceName]);
    if (_upImage && colorUnchanged && appearanceUnchanged) {
        return;
    }
    _tintedGlyphColor = tintColor;
    _tintedGlyphAppearanceName = appearanceName;
    _upImage = [self attributedStringWithImageNamed:@"gitup"];
    _downImage = [self attributedStringWithImageNamed:@"gitdown"];
    _dirtyImage = [self attributedStringWithImageNamed:@"gitdirty"];
}

- (NSAttributedString *)attributedStringWithImageNamed:(NSString *)imageName {
    NSTextAttachment *textAttachment = [[NSTextAttachment alloc] init];
    NSImage *image = [NSImage it_imageNamed:imageName forClass:self.class];
    // These are flat black PNGs. Tint them to match the surrounding text
    // (it_imageWithTintColor: resolves the color against iTerm's current
    // theme appearance) so they don't stay black in dark mode.
    NSColor *tintColor = self.delegate.gitTextColor;
    if (tintColor) {
        image = [image it_imageWithTintColor:tintColor];
    }
    textAttachment.image = image;
    return [NSAttributedString attributedStringWithAttachment:textAttachment];
}

- (NSParagraphStyle *)paragraphStyle {
    static NSMutableParagraphStyle *paragraphStyle;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;
    });

    return paragraphStyle;
}

- (NSArray<NSAttributedString *> *)attributedStringVariants {
    NSArray<NSAttributedString *> *result = [[[self variantsOfCurrentStateBranch] mapWithBlock:^id(NSString *branch) {
        return [self attributedStringValueForBranch:branch];
    }] sortedArrayUsingComparator:^NSComparisonResult(NSAttributedString * _Nonnull obj1, NSAttributedString * _Nonnull obj2) {
        return [@(obj1.length) compare:@(obj2.length)];
    }];
    if (result.count == 0) {
        return @[ [self attributedStringWithString:@""] ];
    }
    return result;
}

- (void)didFinishCommand {
    _status = nil;
    [_gitPoller bump];
}

- (nullable NSArray<NSString *> *)variantsOfCurrentStateBranch {
    NSString *branch = self.currentState.branch;
    if (!branch) {
        return nil;
    }
    return @[ branch ];
}


@end

@implementation iTermAutoGitString {
    iTermVariableReference *_pwdRef;
    iTermVariableReference *_hostRef;
    iTermRemoteGitStateObserver *_remoteObserver;
}

- (instancetype)initWithStringMaker:(iTermGitStringMaker *)maker {
    self = [super init];
    if (self) {
        _maker = maker;
        iTermVariableScope *scope = maker.scope;
        _pwdRef = [[iTermVariableReference alloc] initWithPath:iTermVariableKeySessionPath vendor:scope];
        __weak __typeof(self) weakSelf = self;
        _pwdRef.onChangeBlock = ^{
            [weakSelf pwdDidChange];
        };
        _hostRef = [[iTermVariableReference alloc] initWithPath:iTermVariableKeySessionHostname vendor:scope];
        _hostRef.onChangeBlock = ^{
            RLog(@"Hostname changed, update git poller enabled");
            [weakSelf updatePollerEnabled];
        };
        _remoteObserver = [[iTermRemoteGitStateObserver alloc] initWithScope:scope
                                                                       block:^{
            RLog(@"Remote git state changed; update enabled");
            [weakSelf updatePollerEnabled];
            [weakSelf.delegate gitStringDidChange];
        }];
        [self updatePollerEnabled];
        RLog(@"Initializing git component %@ for scope of session with ID %@. poller is %@", self, scope.ID, _maker.gitPoller);
    }
    return self;
}

- (void)pwdDidChange {
    RLog(@"PWD changed, update git poller directory");
    _maker.gitPoller.currentDirectory = [_maker.scope valueForVariableName:iTermVariableKeySessionPath];
}

- (void)updatePollerEnabled {
    _maker.gitPoller.enabled = [self gitPollerShouldBeEnabled];
}

- (BOOL)gitPollerShouldBeEnabled {
    if (_maker.onLocalhost) {
        RLog(@"Enable git poller: on localhost");
        return YES;
    }

    if ([[iTermGitState alloc] initWithScope:_maker.scope]) {
        RLog(@"Enable git poller: can construct git state");
        return YES;
    }

    RLog(@"DISABLE GIT POLLER");
    return NO;
}


@end
