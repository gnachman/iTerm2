//
//  iTermStatusBarGitComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/22/18.
//
// This is loosely based on hyperline git-status

#import "iTermStatusBarGitComponent.h"

#import "DebugLogging.h"
#import "iTermCommandRunner.h"
#import "iTermGitPoller.h"
#import "iTermGitState.h"
#import "iTermLocalHostNameGuesser.h"
#import "iTermVariables.h"
#import "NSArray+iTerm.h"
#import "NSDate+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSTimer+iTerm.h"
#import "RegexKitLite.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const iTermStatusBarGitComponentPollingIntervalKey = @"iTermStatusBarGitComponentPollingIntervalKey";
static const NSTimeInterval iTermStatusBarGitComponentDefaultCadence = 2;

@implementation iTermStatusBarGitComponent {
    iTermGitPoller *_gitPoller;
    iTermVariableScope *_scope;
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey,id> *)configuration {
    self = [super initWithConfiguration:configuration];
    if (self) {
        const NSTimeInterval cadence = [self cadenceInDictionary:configuration[iTermStatusBarComponentConfigurationKeyKnobValues]];
        __weak __typeof(self) weakSelf = self;
        _gitPoller = [[iTermGitPoller alloc] initWithCadence:cadence update:^{
            [weakSelf statusBarComponentUpdate];
        }];
    }
    return self;
}

- (NSImage *)statusBarComponentIcon {
    return [NSImage it_imageNamed:@"StatusBarIconGitBranch" forClass:[self class]];
}

- (NSString *)statusBarComponentShortDescription {
    return @"git state";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Shows a summary of the git state of the current directory.";
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    iTermStatusBarComponentKnob *formatKnob =
    [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Polling Interval (seconds):"
                                                      type:iTermStatusBarComponentKnobTypeDouble
                                               placeholder:nil
                                              defaultValue:@(iTermStatusBarGitComponentDefaultCadence)
                                                       key:iTermStatusBarGitComponentPollingIntervalKey];
    return [@[ formatKnob ] arrayByAddingObjectsFromArray:[super statusBarComponentKnobs]];
}

+ (NSDictionary *)statusBarComponentDefaultKnobs {
    NSDictionary *fromSuper = [super statusBarComponentDefaultKnobs];
    return [fromSuper dictionaryByMergingDictionary:@{ iTermStatusBarGitComponentPollingIntervalKey: @(iTermStatusBarGitComponentDefaultCadence) }];
}

- (id)statusBarComponentExemplar {
    return @"⎇ master";
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (NSArray<NSAttributedString *> *)attributedStringVariants {
    return @[ self.attributedStringValue ?: [self attributedStringWithString:@""] ];
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

- (NSAttributedString *)attributedStringWithImageNamed:(NSString *)imageName {
    NSTextAttachment *textAttachment = [[NSTextAttachment alloc] init];
    textAttachment.image = [NSImage it_imageNamed:imageName forClass:self.class];
    return [NSAttributedString attributedStringWithAttachment:textAttachment];
}

- (NSAttributedString *)attributedStringWithString:(NSString *)string {
    NSDictionary *attributes = @{ NSFontAttributeName: self.advancedConfiguration.font ?: [iTermStatusBarAdvancedConfiguration defaultFont],
                                  NSForegroundColorAttributeName: [self textColor],
                                  NSParagraphStyleAttributeName: self.paragraphStyle };
    return [[NSAttributedString alloc] initWithString:string ?: @"" attributes:attributes];
}

- (nullable NSAttributedString *)attributedStringValue {
    if (!_gitPoller.state || !_gitPoller.enabled) {
        return nil;
    }
    static NSAttributedString *upImage;
    static NSAttributedString *downImage;
    static NSAttributedString *dirtyImage;
    static NSAttributedString *space;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        upImage = [self attributedStringWithImageNamed:@"gitup"];
        downImage = [self attributedStringWithImageNamed:@"gitdown"];
        dirtyImage = [self attributedStringWithImageNamed:@"gitdirty"];
        space = [self attributedStringWithString:@"\u2003\u2003"];
    });

    NSAttributedString *branch = _gitPoller.state.branch ? [self attributedStringWithString:_gitPoller.state.branch] : nil;
    if (!branch) {
        return nil;
    }

    NSAttributedString *upCount = _gitPoller.state.pushArrow.length ? [self attributedStringWithString:_gitPoller.state.pushArrow] : nil;
    NSAttributedString *downCount = _gitPoller.state.pullArrow.length ? [self attributedStringWithString:_gitPoller.state.pullArrow] : nil;

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [result appendAttributedString:branch];

    if (_gitPoller.state.pushArrow.integerValue > 0) {
        [result appendAttributedString:space];
        [result appendAttributedString:upImage];
        [result appendAttributedString:upCount];
    }

    if (_gitPoller.state.pullArrow.integerValue > 0) {
        [result appendAttributedString:space];
        [result appendAttributedString:downImage];
        [result appendAttributedString:downCount];
    }

    if (_gitPoller.state.dirty) {
        [result appendAttributedString:space];
        [result appendAttributedString:dirtyImage];
    }

    return result;
}

- (NSTimeInterval)cadenceInDictionary:(NSDictionary *)knobValues {
    return [knobValues[iTermStatusBarGitComponentPollingIntervalKey] doubleValue] ?: 1;
}

- (void)updatePollerEnabled {
    NSString *currentHostname = [_scope valueForVariableName:iTermVariableKeySessionHostname];
    NSString *localhostName = [[iTermLocalHostNameGuesser sharedInstance] name];
    DLog(@"git poller current hostname is %@, localhost is %@", currentHostname, localhostName);
    _gitPoller.enabled = [localhostName isEqualToString:currentHostname];
}

- (void)statusBarComponentSetKnobValues:(NSDictionary *)knobValues {
    _gitPoller.cadence = [self cadenceInDictionary:knobValues];
    [super statusBarComponentSetKnobValues:knobValues];
}

- (NSSet<NSString *> *)statusBarComponentVariableDependencies {
    return [NSSet setWithArray:@[ iTermVariableKeySessionPath, iTermVariableKeySessionHostname ]];
}

- (void)statusBarComponentSetVariableScope:(iTermVariableScope *)scope {
    _scope = scope;
    [self updatePollerEnabled];
}

- (void)statusBarComponentVariablesDidChange:(NSSet<NSString *> *)variables {
    if ([variables containsObject:iTermVariableKeySessionPath]) {
        _gitPoller.currentDirectory = [_scope valueForVariableName:iTermVariableKeySessionPath];
    }
    if ([variables containsObject:iTermVariableKeySessionHostname]) {
        [self updatePollerEnabled];
    }
}

@end

NS_ASSUME_NONNULL_END
