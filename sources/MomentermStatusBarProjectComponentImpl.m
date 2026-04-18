//
//  MomentermStatusBarProjectComponentImpl.m
//  iTerm2
//
//  Created by MomenTerm on 2026-04-19.
//

#import "MomentermStatusBarProjectComponentImpl.h"
#import "iTermStatusBarComponentKnob.h"
#import "iTermStatusBarLayout.h"
#import "iTermVariableScope.h"
#import "NSObject+iTerm.h"

NSString *const kMomentermStatusBarProjectComponentIdentifier = @"com.momenterm.statusbar.project";

@interface MomentermStatusBarProjectComponentImpl ()
@property (nonatomic, strong, nullable) NSTextField *label;
@property (nonatomic, strong, nullable) NSTimer *refreshTimer;
@end

@implementation MomentermStatusBarProjectComponentImpl

// MARK: - Registration

+ (NSString *)statusBarComponentIdentifier {
    return kMomentermStatusBarProjectComponentIdentifier;
}

+ (NSDictionary *)statusBarComponentDefaultKnobs {
    NSDictionary *superKnobs = [super statusBarComponentDefaultKnobs] ?: @{};
    return superKnobs;
}

// MARK: - Description

- (NSString *)statusBarComponentShortDescription {
    return @"MomenTerm Project";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Shows current project name, git branch, and AI model.";
}

- (BOOL)statusBarComponentIsInternal {
    return NO;
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    return @"📁 my-project  ⎇ main";
}

// MARK: - Layout

- (double)statusBarComponentPriority {
    return iTermStatusBarBaseComponentDefaultPriority;
}

- (NSTimeInterval)statusBarComponentUpdateCadence {
    return 5.0;
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (CGFloat)statusBarComponentSpringConstant {
    return 1.0;
}

- (CGFloat)statusBarComponentMinimumWidth {
    return 60.0;
}

- (CGFloat)statusBarComponentMaximumWidth {
    return 400.0;
}

- (CGFloat)statusBarComponentPreferredWidth {
    return 180.0;
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    return [self minMaxWidthKnobs];
}

- (void)statusBarComponentSizeView:(NSView *)view toFitWidth:(CGFloat)width {
    view.frame = NSMakeRect(0, 0, width, view.frame.size.height);
}

// MARK: - View

- (NSView *)statusBarComponentView {
    NSString *text = [self buildDisplayString];
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = self.advancedConfiguration.font ?: [NSFont systemFontOfSize:NSFont.systemFontSize];
    NSColor *color = self.defaultTextColor ?: NSColor.labelColor;
    label.textColor = color;
    label.toolTip = [self buildTooltip];
    self.label = label;
    [self startRefreshTimer];
    return label;
}

// MARK: - Data

- (NSString *)buildDisplayString {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSString *cwd = [self currentDirectory];

    NSString *projectName = [self findProjectNameForDirectory:cwd];
    if (projectName) {
        [parts addObject:[NSString stringWithFormat:@"📁 %@", projectName]];
    }

    NSString *branch = [self gitBranchInDirectory:cwd];
    if (branch) {
        [parts addObject:[NSString stringWithFormat:@"⎇ %@", branch]];
    }

    NSString *model = [self currentModel];
    if (model) {
        [parts addObject:[NSString stringWithFormat:@"✦ %@", model]];
    }

    return parts.count > 0 ? [parts componentsJoinedByString:@"  "] : @"mt";
}

- (NSString *)buildTooltip {
    NSString *cwd = [self currentDirectory];
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithObject:@"MomenTerm Status"];
    NSString *proj = [self findProjectNameForDirectory:cwd];
    if (proj) [lines addObject:[NSString stringWithFormat:@"Project: %@", proj]];
    NSString *branch = [self gitBranchInDirectory:cwd];
    if (branch) [lines addObject:[NSString stringWithFormat:@"Branch: %@", branch]];
    NSString *model = [self currentModel];
    if (model) [lines addObject:[NSString stringWithFormat:@"Model: %@", model]];
    [lines addObject:[NSString stringWithFormat:@"Dir: %@", cwd]];
    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)currentDirectory {
    // Try scope variable first
    id scopeValue = [self.scope valueForVariableName:@"path"];
    if ([scopeValue isKindOfClass:[NSString class]] && [(NSString *)scopeValue length] > 0) {
        return scopeValue;
    }
    NSString *pwd = NSProcessInfo.processInfo.environment[@"PWD"];
    return pwd ?: NSFileManager.defaultManager.currentDirectoryPath;
}

- (nullable NSString *)findProjectNameForDirectory:(NSString *)directory {
    // Read from ~/.momenterm/projects.json
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
                return project[@"name"];
            }
        }
    }
    return nil;
}

- (nullable NSString *)gitBranchInDirectory:(NSString *)directory {
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
    NSDictionary *env = NSProcessInfo.processInfo.environment;
    return env[@"CLAUDE_MODEL"] ?: env[@"MT_MODEL"];
}

// MARK: - Timer

- (void)startRefreshTimer {
    [self.refreshTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                        repeats:YES
                                                          block:^(NSTimer *timer) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.label.stringValue = [strongSelf buildDisplayString];
        strongSelf.label.toolTip = [strongSelf buildTooltip];
    }];
}

- (void)dealloc {
    [_refreshTimer invalidate];
}

@end
