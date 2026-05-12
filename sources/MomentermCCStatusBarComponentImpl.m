//
//  MomentermCCStatusBarComponentImpl.m
//  iTerm2
//

#import "MomentermCCStatusBarComponentImpl.h"
#import "iTermStatusBarComponentKnob.h"
#import "iTermStatusBarLayout.h"
#import "NSObject+iTerm.h"

NSString *const kMomentermCCStatusBarIdentifier = @"com.momenterm.statusbar.ccusage";

static NSString *const kCCStatusFilePath = @"/tmp/momenterm-cc-status.json";
static const NSTimeInterval kStalenessThreshold = 30.0;
static const NSTimeInterval kRetryInterval = 5.0;

// Nord palette (RGB 0-1)
#define NORD_GREEN   [NSColor colorWithRed:0.639 green:0.745 blue:0.549 alpha:1.0]  // #a3be8c
#define NORD_ORANGE  [NSColor colorWithRed:0.816 green:0.529 blue:0.439 alpha:1.0]  // #d08770
#define NORD_RED     [NSColor colorWithRed:0.749 green:0.380 blue:0.412 alpha:1.0]  // #bf616a
#define NORD_YELLOW  [NSColor colorWithRed:0.922 green:0.796 blue:0.545 alpha:1.0]  // #ebcb8b
#define NORD_FROST   [NSColor colorWithRed:0.533 green:0.753 blue:0.816 alpha:1.0]  // #88c0d0

@interface MomentermCCStatusBarComponentImpl ()
@property (nonatomic, strong, nullable) NSTextField *label;
@property (nonatomic, strong, nullable) dispatch_source_t fileSource;
@property (nonatomic, assign) int watchFD;
@property (nonatomic, strong, nullable) NSTimer *retryTimer;
@property (nonatomic, strong, nullable) NSDictionary *lastPayload;
@property (nonatomic, strong, nullable) NSDate *lastUpdated;
@end

@implementation MomentermCCStatusBarComponentImpl

// MARK: - Registration

+ (NSString *)statusBarComponentIdentifier {
    return kMomentermCCStatusBarIdentifier;
}

+ (NSDictionary *)statusBarComponentDefaultKnobs {
    return [super statusBarComponentDefaultKnobs] ?: @{};
}

// MARK: - Description

- (NSString *)statusBarComponentShortDescription {
    return @"Claude Code 사용량";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Claude Code 5H/7D rate limit 사용량, 비용, 현재 모델을 표시합니다.";
}

- (BOOL)statusBarComponentIsInternal {
    return NO;
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    return @"proj>my-app | main | 5H ###------- 30% | 7D #--------- 10% | $12.34 | sonnet";
}

// MARK: - Layout

- (double)statusBarComponentPriority {
    return iTermStatusBarBaseComponentDefaultPriority;
}

- (NSTimeInterval)statusBarComponentUpdateCadence {
    return 0;  // driven by file watcher, not cadence
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (CGFloat)statusBarComponentSpringConstant {
    return 1.0;
}

- (CGFloat)statusBarComponentMinimumWidth {
    return 120.0;
}

- (CGFloat)statusBarComponentMaximumWidth {
    return 700.0;
}

- (CGFloat)statusBarComponentPreferredWidth {
    return 500.0;
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    return [self minMaxWidthKnobs];
}

- (void)statusBarComponentSizeView:(NSView *)view toFitWidth:(CGFloat)width {
    view.frame = NSMakeRect(0, 0, width, view.frame.size.height);
}

// MARK: - View

- (NSView *)statusBarComponentView {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
    label.editable = NO;
    label.selectable = NO;
    label.bordered = NO;
    label.backgroundColor = NSColor.clearColor;
    label.drawsBackground = NO;
    label.cell.scrollable = YES;
    label.cell.wraps = NO;
    NSFont *font = self.advancedConfiguration.font
        ?: [NSFont monospacedSystemFontOfSize:[NSFont smallSystemFontSize] weight:NSFontWeightRegular];
    label.font = font;
    self.label = label;

    [self reloadFromFile];
    [self startWatching];
    return label;
}

// MARK: - File Watching

- (void)startWatching {
    [self.retryTimer invalidate];
    self.retryTimer = nil;

    int fd = open(kCCStatusFilePath.UTF8String, O_EVTONLY);
    if (fd < 0) {
        [self scheduleRetry];
        return;
    }
    self.watchFD = fd;

    __weak typeof(self) weakSelf = self;
    dispatch_source_t source = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)fd,
        DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_DELETE,
        dispatch_get_main_queue());

    dispatch_source_set_event_handler(source, ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        unsigned long flags = dispatch_source_get_data(source);
        if (flags & DISPATCH_VNODE_DELETE) {
            dispatch_source_cancel(source);
        } else {
            [strongSelf reloadFromFile];
        }
    });
    dispatch_source_set_cancel_handler(source, ^{
        close(fd);
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.fileSource = nil;
            [strongSelf scheduleRetry];
        });
    });
    dispatch_resume(source);
    self.fileSource = source;
}

- (void)scheduleRetry {
    __weak typeof(self) weakSelf = self;
    self.retryTimer = [NSTimer scheduledTimerWithTimeInterval:kRetryInterval
                                                       repeats:NO
                                                         block:^(NSTimer *t) {
        [weakSelf startWatching];
    }];
}

// MARK: - Data

- (void)reloadFromFile {
    NSData *data = [NSData dataWithContentsOfFile:kCCStatusFilePath];
    if (!data) return;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) return;
    self.lastPayload = json;
    self.lastUpdated = [NSDate date];
    [self updateLabel];
}

- (void)updateLabel {
    if (!self.label) return;
    BOOL stale = self.lastUpdated == nil
        || [[NSDate date] timeIntervalSinceDate:self.lastUpdated] > kStalenessThreshold;
    NSAttributedString *str = [self buildAttributedStringStale:stale];
    self.label.attributedStringValue = str;
    self.label.toolTip = [self buildTooltip];
}

// MARK: - Attributed String Builder

- (NSAttributedString *)buildAttributedStringStale:(BOOL)stale {
    if (!self.lastPayload) {
        NSColor *dim = NSColor.tertiaryLabelColor;
        return [[NSAttributedString alloc] initWithString:@"CC 미실행"
                    attributes:@{NSForegroundColorAttributeName: dim}];
    }

    NSFont *font = self.label.font
        ?: [NSFont monospacedSystemFontOfSize:[NSFont smallSystemFontSize] weight:NSFontWeightRegular];
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    CGFloat alpha = stale ? 0.4 : 1.0;

    void (^append)(NSString *, NSColor *) = ^(NSString *text, NSColor *color) {
        NSColor *c = [color colorWithAlphaComponent:alpha];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:text
            attributes:@{NSForegroundColorAttributeName: c, NSFontAttributeName: font}]];
    };

    NSColor *sep = [NSColor.separatorColor colorWithAlphaComponent:alpha];
    void (^sep_append)(void) = ^{
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:@" | "
            attributes:@{NSForegroundColorAttributeName: sep, NSFontAttributeName: font}]];
    };

    NSDictionary *payload = self.lastPayload;
    NSString *cwd = payload[@"cwd"] ?: (payload[@"workspace"] ?: @"");
    if ([cwd isKindOfClass:[NSDictionary class]]) {
        cwd = ((NSDictionary *)cwd)[@"current_dir"] ?: @"";
    }

    // workspace>project
    NSString *label = [self workspaceProjectLabelForDirectory:cwd] ?: [cwd lastPathComponent];
    append(label, NSColor.labelColor);
    sep_append();

    // git branch
    NSString *branch = [self gitBranchInDirectory:cwd] ?: @"-";
    append(branch, NORD_FROST);
    sep_append();

    // 5H bar
    NSDictionary *fiveH = [payload valueForKeyPath:@"rate_limits.five_hour"];
    NSInteger pct5 = [self pctFromValue:fiveH[@"used_percentage"]];
    NSNumber *reset5 = fiveH[@"resets_at"];
    append(@"5H ", NSColor.secondaryLabelColor);
    [result appendAttributedString:[self blockBarForPct:pct5]];
    NSString *pctStr5 = [NSString stringWithFormat:@" %ld%%", (long)pct5];
    append(pctStr5, [self colorForPct:pct5]);
    NSString *left5 = [self formatRemaining:reset5.doubleValue];
    append([NSString stringWithFormat:@" %@", left5], NSColor.tertiaryLabelColor);
    sep_append();

    // 7D bar
    NSDictionary *sevenD = [payload valueForKeyPath:@"rate_limits.seven_day"];
    NSInteger pct7 = [self pctFromValue:sevenD[@"used_percentage"]];
    NSNumber *reset7 = sevenD[@"resets_at"];
    append(@"7D ", NSColor.secondaryLabelColor);
    [result appendAttributedString:[self blockBarForPct:pct7]];
    NSString *pctStr7 = [NSString stringWithFormat:@" %ld%%", (long)pct7];
    append(pctStr7, [self colorForPct:pct7]);
    NSString *left7 = [self formatRemaining:reset7.doubleValue];
    append([NSString stringWithFormat:@" %@", left7], NSColor.tertiaryLabelColor);
    sep_append();

    // cost
    double cost = [[payload valueForKeyPath:@"cost.total_cost_usd"] doubleValue];
    append([NSString stringWithFormat:@"$%.2f", cost], NORD_YELLOW);
    sep_append();

    // model
    NSString *model = [self currentModel] ?: @"?";
    append(model, NSColor.secondaryLabelColor);

    return result;
}

// MARK: - Helpers

- (NSInteger)pctFromValue:(id)value {
    if (!value || [value isKindOfClass:[NSNull class]]) return 0;
    NSInteger v = [value integerValue];
    return MAX(0, MIN(100, v));
}

- (NSAttributedString *)blockBarForPct:(NSInteger)pct {
    NSFont *font = [NSFont monospacedSystemFontOfSize:
        (self.label.font.pointSize ?: [NSFont smallSystemFontSize]) weight:NSFontWeightRegular];
    NSMutableAttributedString *bar = [[NSMutableAttributedString alloc] init];
    NSInteger filled = MAX(0, MIN(10, (pct * 10) / 100));
    NSColor *fillColor = [self colorForPct:pct];
    NSColor *emptyColor = NSColor.tertiaryLabelColor;
    for (NSInteger i = 0; i < 10; i++) {
        NSColor *color = (i < filled) ? fillColor : emptyColor;
        NSString *ch = (i < filled) ? @"#" : @"-";
        [bar appendAttributedString:[[NSAttributedString alloc] initWithString:ch
            attributes:@{NSForegroundColorAttributeName: color, NSFontAttributeName: font}]];
    }
    return bar;
}

- (NSColor *)colorForPct:(NSInteger)pct {
    if (pct >= 90) return NORD_RED;
    if (pct >= 80) return NORD_ORANGE;
    return NORD_GREEN;
}

- (NSString *)formatRemaining:(double)resetsAt {
    if (resetsAt <= 0) return @"-";
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    NSTimeInterval diff = resetsAt - now;
    if (diff <= 0) return @"0m";
    long days  = (long)diff / 86400;
    long hours = ((long)diff % 86400) / 3600;
    long mins  = ((long)diff % 3600) / 60;
    if (days > 0)  return [NSString stringWithFormat:@"%ldd %ldh", days, hours];
    if (hours > 0) return [NSString stringWithFormat:@"%ldh %ldm", hours, mins];
    return [NSString stringWithFormat:@"%ldm", mins];
}

- (nullable NSString *)workspaceProjectLabelForDirectory:(NSString *)directory {
    if (!directory.length) return nil;
    NSString *configPath = [NSHomeDirectory() stringByAppendingPathComponent:@".momenterm/projects.json"];
    NSData *data = [NSData dataWithContentsOfFile:configPath];
    if (!data) return nil;
    NSDictionary *store = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (!store) return nil;
    NSString *resolved = [directory stringByResolvingSymlinksInPath];
    for (NSDictionary *space in store[@"spaces"]) {
        for (NSDictionary *project in space[@"projects"]) {
            NSString *projectPath = [project[@"path"] stringByResolvingSymlinksInPath];
            if ([projectPath isEqualToString:resolved]) {
                return [NSString stringWithFormat:@"%@>%@", space[@"name"], project[@"name"]];
            }
        }
    }
    return nil;
}

- (nullable NSString *)gitBranchInDirectory:(NSString *)directory {
    if (!directory.length) return nil;
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/git"];
    task.arguments = @[@"-C", directory, @"rev-parse", @"--abbrev-ref", @"HEAD"];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSPipe pipe];
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) return nil;
    [task waitUntilExit];
    if (task.terminationStatus != 0) return nil;
    NSData *outputData = [pipe.fileHandleForReading readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
    output = [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return (output.length > 0 && ![output isEqualToString:@"HEAD"]) ? output : nil;
}

- (nullable NSString *)currentModel {
    NSString *settingsPath = [NSHomeDirectory() stringByAppendingPathComponent:@".claude/settings.json"];
    NSData *data = [NSData dataWithContentsOfFile:settingsPath];
    if (!data) return nil;
    NSDictionary *settings = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [settings[@"model"] isKindOfClass:[NSString class]] ? settings[@"model"] : nil;
}

- (NSString *)buildTooltip {
    if (!self.lastPayload) return @"Claude Code 미실행";
    NSDictionary *p = self.lastPayload;
    NSString *cwd = p[@"cwd"] ?: @"";
    NSInteger pct5 = [self pctFromValue:[p valueForKeyPath:@"rate_limits.five_hour.used_percentage"]];
    NSInteger pct7 = [self pctFromValue:[p valueForKeyPath:@"rate_limits.seven_day.used_percentage"]];
    double cost = [[p valueForKeyPath:@"cost.total_cost_usd"] doubleValue];
    return [NSString stringWithFormat:@"Claude Code 사용량\n디렉터리: %@\n5H: %ld%%\n7D: %ld%%\n비용: $%.2f\n모델: %@",
            cwd, (long)pct5, (long)pct7, cost, [self currentModel] ?: @"?"];
}

// MARK: - Cleanup

- (void)dealloc {
    [_retryTimer invalidate];
    if (_fileSource) {
        dispatch_source_cancel(_fileSource);
    }
}

@end
