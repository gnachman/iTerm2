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
#import "iTermVariables.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "RegexKitLite.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermGitState : NSObject
@property (nonatomic, copy) NSString *pushArrow;
@property (nonatomic, copy) NSString *pullArrow;
@property (nonatomic, copy) NSString *branch;
@property (nonatomic) BOOL dirty;
@end

@implementation iTermGitState
@end

@interface iTermGitPoller : NSObject
@property (nonatomic) NSTimeInterval cadence;
@property (nonatomic, copy) NSString *currentDirectory;
@property (nonatomic, readonly) iTermGitState *state;

- (instancetype)initWithCadence:(NSTimeInterval)cadence
                         update:(void (^)(void))update NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
@end

@implementation iTermGitPoller {
    NSTimer *_timer;
    BOOL _polling;
    void (^_update)(void);
    dispatch_group_t _group;
    NSMutableArray<iTermBufferedCommandRunner *> *_runners;
}

- (instancetype)initWithCadence:(NSTimeInterval)cadence update:(void (^)(void))update {
    self = [super init];
    if (self) {
        _cadence = cadence;
        _update = [update copy];
        _runners = [NSMutableArray array];
        [self startTimer];
    }
    return self;
}

- (void)dealloc {
    [_timer invalidate];
}

#pragma mark - Private

- (void)startTimer {
    [_timer invalidate];
    _timer = [NSTimer scheduledTimerWithTimeInterval:_cadence target:self selector:@selector(poll) userInfo:nil repeats:YES];
}

- (void)execCommand:(NSString *)command withCompletion:(void (^)(int status, NSString *output))completion {
    DLog(@"Run %@", command);
    iTermBufferedCommandRunner *runner = [[iTermBufferedCommandRunner alloc] initWithCommand:@"/bin/bash"
                                                                               withArguments:@[ @"-c", command ]
                                                                                        path:self.currentDirectory];
    if (!runner) {
        completion(-1, @"");
        return;
    }
    [_runners addObject:runner];
    __weak __typeof(self) weakSelf = self;
    __weak __typeof(runner) weakRunner = runner;
    runner.completion = ^(int status) {
        __strong __typeof(self) strongSelf = weakSelf;
        __weak __typeof(runner) strongRunner = weakRunner;
        if (strongSelf && strongRunner) {
            DLog(@"%@ finished with status %@:\n%@", command, @(status),
                 [[NSString alloc] initWithData:strongRunner.output encoding:NSUTF8StringEncoding]);
            completion(status, [[NSString alloc] initWithData:strongRunner.output encoding:NSUTF8StringEncoding]);
            [strongSelf->_runners removeObject:strongRunner];
        }
    };
    [runner runWithTimeout:1];
}

- (void)poll {
    if (_polling) {
        return;
    }
    _polling = YES;

    iTermGitState *state = [[iTermGitState alloc] init];
    _group = dispatch_group_create();
    dispatch_group_t group = _group;

    dispatch_group_enter(group);
    [self execCommand:@"/usr/bin/git status --porcelain --ignore-submodules -unormal" withCompletion:^(int status, NSString * _Nonnull output) {
        state.dirty = (status == 0) && (output.length > 0);
        dispatch_group_leave(self->_group);
    }];

    dispatch_group_enter(group);
    [self execCommand:@"/usr/bin/git rev-list --left-right --count HEAD...@'{u}' 2>/dev/null" withCompletion:^(int status, NSString * _Nonnull output) {
        if (status == 0) {
            NSArray<NSString *> *arrows = [output componentsSeparatedByString:@"\t"];
            state.pushArrow = [[arrows uncheckedObjectAtIndex:0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            state.pullArrow = [[arrows uncheckedObjectAtIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }

        dispatch_group_leave(group);
    }];

    dispatch_group_enter(group);
    [self execCommand:@"/usr/bin/git symbolic-ref -q --short HEAD || git rev-parse --short HEAD" withCompletion:^(int status, NSString * _Nonnull output) {
        if (status == 0) {
            state.branch = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }

        dispatch_group_leave(group);
    }];

    __weak __typeof(self) weakSelf = self;
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (strongSelf) {
            strongSelf->_polling = NO;
            [strongSelf setState:state];
        }
    });
}

- (void)setState:(iTermGitState *)state {
    _state = state;
    _update();
}

@end

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
    NSDictionary *attributes = @{ NSFontAttributeName: [NSFont fontWithName:@"Menlo" size:12],
                                  NSParagraphStyleAttributeName: self.paragraphStyle };
    return [[NSAttributedString alloc] initWithString:string ?: @"" attributes:attributes];
}

- (nullable NSAttributedString *)attributedStringValue {
    if (!_gitPoller.state) {
        return nil;
    }
    static NSAttributedString *branchImage;
    static NSAttributedString *upImage;
    static NSAttributedString *downImage;
    static NSAttributedString *cleanImage;
    static NSAttributedString *dirtyImage;
    static NSAttributedString *space;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        branchImage = [self attributedStringWithImageNamed:@"gitbranch"];
        upImage = [self attributedStringWithImageNamed:@"gitup"];
        downImage = [self attributedStringWithImageNamed:@"gitdown"];
        cleanImage = [self attributedStringWithImageNamed:@"gitclean"];
        dirtyImage = [self attributedStringWithImageNamed:@"gitdirty"];
        space = [self attributedStringWithString:@" "];
    });

    NSAttributedString *cleanDirtyImage = _gitPoller.state.dirty ? dirtyImage : cleanImage;

    NSAttributedString *branch = _gitPoller.state.branch ? [self attributedStringWithString:_gitPoller.state.branch] : nil;
    if (!branch) {
        return nil;
    }

    NSAttributedString *upCount = _gitPoller.state.pushArrow.length ? [self attributedStringWithString:_gitPoller.state.pushArrow] : nil;
    NSAttributedString *downCount = _gitPoller.state.pullArrow.length ? [self attributedStringWithString:_gitPoller.state.pullArrow] : nil;

    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [result appendAttributedString:branchImage];
    [result appendAttributedString:branch];
    [result appendAttributedString:space];

    if (_gitPoller.state.pushArrow.integerValue > 0) {
        [result appendAttributedString:upImage];
        [result appendAttributedString:upCount];
        [result appendAttributedString:space];
    }

    if (_gitPoller.state.pullArrow.integerValue > 0) {
        [result appendAttributedString:downImage];
        [result appendAttributedString:downCount];
        [result appendAttributedString:space];
    }

    [result appendAttributedString:cleanDirtyImage];

    return result;
}

- (NSTimeInterval)cadenceInDictionary:(NSDictionary *)knobValues {
    return [knobValues[iTermStatusBarGitComponentPollingIntervalKey] doubleValue] ?: 1;
}

- (void)statusBarComponentSetKnobValues:(NSDictionary *)knobValues {
    _gitPoller.cadence = [self cadenceInDictionary:knobValues];
    [super statusBarComponentSetKnobValues:knobValues];
}

- (NSSet<NSString *> *)statusBarComponentVariableDependencies {
    return [NSSet setWithArray:@[ iTermVariableKeySessionPath ]];
}

- (void)statusBarComponentSetVariableScope:(iTermVariableScope *)scope {
    _scope = scope;
}

- (void)statusBarComponentVariablesDidChange:(NSSet<NSString *> *)variables {
    if ([variables containsObject:iTermVariableKeySessionPath]) {
        _gitPoller.currentDirectory = [_scope valueForVariableName:iTermVariableKeySessionPath];
    }
}

@end

NS_ASSUME_NONNULL_END
