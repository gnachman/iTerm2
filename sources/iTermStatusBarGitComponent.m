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
#import "iTermVariableReference.h"
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
    iTermVariableReference *_pwdRef;
    iTermVariableReference *_hostRef;
    BOOL _hidden;
}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey,id> *)configuration
                                scope:(nullable iTermVariableScope *)scope {
    self = [super initWithConfiguration:configuration scope:scope];
    if (self) {
        const NSTimeInterval cadence = [self cadenceInDictionary:configuration[iTermStatusBarComponentConfigurationKeyKnobValues]];
        __weak __typeof(self) weakSelf = self;
        iTermGitPoller *gitPoller = [[iTermGitPoller alloc] initWithCadence:cadence update:^{
            [weakSelf statusBarComponentUpdate];
        }];
        _gitPoller = gitPoller;
        _pwdRef = [[iTermVariableReference alloc] initWithPath:iTermVariableKeySessionPath scope:scope];
        _pwdRef.onChangeBlock = ^{
            gitPoller.currentDirectory = [scope valueForVariableName:iTermVariableKeySessionPath];
        };
        _hostRef = [[iTermVariableReference alloc] initWithPath:iTermVariableKeySessionHostname scope:scope];
        _hostRef.onChangeBlock = ^{
            [weakSelf updatePollerEnabled];
        };
        gitPoller.currentDirectory = [scope valueForVariableName:iTermVariableKeySessionPath];
        [self updatePollerEnabled];
    };
    return self;
}

- (void)setDelegate:(id<iTermStatusBarComponentDelegate>)delegate {
    [super setDelegate:delegate];
    [self statusBarComponentUpdate];
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
    NSArray<iTermStatusBarComponentKnob *> *knobs;

    iTermStatusBarComponentKnob *formatKnob =
    [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Polling Interval (seconds):"
                                                      type:iTermStatusBarComponentKnobTypeDouble
                                               placeholder:nil
                                              defaultValue:@(iTermStatusBarGitComponentDefaultCadence)
                                                       key:iTermStatusBarGitComponentPollingIntervalKey];

    knobs = @[ formatKnob ];
    knobs = [knobs arrayByAddingObjectsFromArray:self.minMaxWidthKnobs];
    knobs = [knobs arrayByAddingObjectsFromArray:[super statusBarComponentKnobs]];
    return knobs;
}

+ (NSDictionary *)statusBarComponentDefaultKnobs {
    NSDictionary *knobs = [super statusBarComponentDefaultKnobs];
    knobs = [knobs dictionaryByMergingDictionary:@{ iTermStatusBarGitComponentPollingIntervalKey: @(iTermStatusBarGitComponentDefaultCadence) }];
    knobs = [knobs dictionaryByMergingDictionary:self.defaultMinMaxWidthKnobValues];
    return knobs;
}

- (CGFloat)statusBarComponentPreferredWidth {
    return [self clampedWidth:[super statusBarComponentPreferredWidth]];
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

- (BOOL)shouldBeHidden {
    return !self.pollerReady || _gitPoller.state.branch.length == 0;
}

- (BOOL)pollerReady {
    return _gitPoller.state && _gitPoller.enabled;
}

- (void)statusBarComponentUpdate {
    [super statusBarComponentUpdate];
    if (self.delegate == nil) {
        return;
    }
    const BOOL shouldBeHidden = self.shouldBeHidden;
    if (shouldBeHidden != _hidden) {
        _hidden = shouldBeHidden;
        [self.delegate statusBarComponent:self setHidden:_hidden];
    }
}

- (nullable NSAttributedString *)attributedStringValue {
    if (!self.pollerReady) {
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
    NSString *currentHostname = [self.scope valueForVariableName:iTermVariableKeySessionHostname];
    NSString *localhostName = [[iTermLocalHostNameGuesser sharedInstance] name];
    DLog(@"git poller current hostname is %@, localhost is %@", currentHostname, localhostName);
    _gitPoller.enabled = [localhostName isEqualToString:currentHostname];
}

- (void)statusBarComponentSetKnobValues:(NSDictionary *)knobValues {
    _gitPoller.cadence = [self cadenceInDictionary:knobValues];
    [super statusBarComponentSetKnobValues:knobValues];
}

@end

NS_ASSUME_NONNULL_END
