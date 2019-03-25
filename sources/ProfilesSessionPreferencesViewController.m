//
//  ProfilesSessionViewController.m
//  iTerm
//
//  Created by George Nachman on 4/18/14.
//
//

#import "ProfilesSessionPreferencesViewController.h"
#import "ITAddressBookMgr.h"
#import "iTermColorMap.h"
#import "iTermStatusBarSetupViewController.h"
#import "iTermTheme.h"
#import "iTermWarning.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSObject+iTerm.h"
#import "PSMMinimalTabStyle.h"
#import "PreferencePanel.h"

@interface iTermStatusBarSetupPanel : NSPanel
@end

@implementation iTermStatusBarSetupPanel

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return YES;
}

- (BOOL)becomeFirstResponder {
    [super becomeFirstResponder];
    return YES;
}

@end

@interface ProfilesSessionPreferencesViewController () <NSTableViewDelegate, NSTableViewDataSource, PSMMinimalTabStyleDelegate>
@end

@implementation ProfilesSessionPreferencesViewController {
    IBOutlet NSButton *_closeSessionsOnEnd;
    IBOutlet NSTableView *_jobsTable;
    IBOutlet NSButton *_removeJob;
    IBOutlet NSButton *_autoLog;
    IBOutlet NSTextField *_logDir;
    IBOutlet NSButton *_sendCodeWhenIdle;
    IBOutlet NSTextField *_idleCode;
    IBOutlet NSTextField *_idlePeriod;

    IBOutlet NSImageView *_logDirWarning;
    IBOutlet NSButton *_changeLogDir;

    IBOutlet NSTextField *_undoTimeout;
    IBOutlet NSButton *_reduceFlicker;

    IBOutlet NSView *_warnContainer;
    IBOutlet NSButton *_alwaysWarn;
    IBOutlet NSButton *_neverWarn;
    IBOutlet NSButton *_warnIfJobsBesides;

    IBOutlet NSButton *_statusBarEnabled;
    IBOutlet NSButton *_configureStatusBar;
    iTermStatusBarSetupViewController *_statusBarSetupViewController;
    iTermStatusBarSetupPanel *_statusBarSetupWindow;
    BOOL _awoken;
}

- (void)dealloc {
    _jobsTable.dataSource = nil;
    _jobsTable.delegate = nil;
}

- (void)awakeFromNib {
    if (_awoken) {
        return;
    }
    _awoken = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProfiles)
                                                 name:kReloadAllProfiles
                                               object:nil];
    __weak __typeof(self) weakSelf = self;
    [self defineControl:_closeSessionsOnEnd
                    key:KEY_CLOSE_SESSIONS_ON_END
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_alwaysWarn
                    key:KEY_PROMPT_CLOSE
                   type:kPreferenceInfoTypeRadioButton
         settingChanged:^(id sender) { [self promptBeforeClosingDidChange]; }
                 update:^BOOL { [self updatePromptBeforeClosing]; return YES; }];

    [self defineControl:_neverWarn
                    key:KEY_PROMPT_CLOSE
                   type:kPreferenceInfoTypeRadioButton
         settingChanged:^(id sender) { [self promptBeforeClosingDidChange]; }
                 update:^BOOL { [self updatePromptBeforeClosing]; return YES; }];

    [self defineControl:_warnIfJobsBesides
                    key:KEY_PROMPT_CLOSE
                   type:kPreferenceInfoTypeRadioButton
         settingChanged:^(id sender) { [self promptBeforeClosingDidChange]; }
                 update:^BOOL { [self updatePromptBeforeClosing]; return YES; }];

    [self defineControl:_undoTimeout
                    key:KEY_UNDO_TIMEOUT
                   type:kPreferenceInfoTypeIntegerTextField];

    PreferenceInfo *info;
    info = [self defineControl:_autoLog
                           key:KEY_AUTOLOG
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^() {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf->_logDir.enabled = [strongSelf boolForKey:KEY_AUTOLOG];
        strongSelf->_changeLogDir.enabled = [strongSelf boolForKey:KEY_AUTOLOG];
        [strongSelf updateLogDirWarning];
    };

    info = [self defineControl:_logDir
                           key:KEY_LOGDIR
                          type:kPreferenceInfoTypeStringTextField];
    info.observer = ^() { [weakSelf updateLogDirWarning]; };

    info = [self defineControl:_sendCodeWhenIdle
                           key:KEY_SEND_CODE_WHEN_IDLE
                          type:kPreferenceInfoTypeCheckbox];
    info.customSettingChangedHandler = ^(id sender) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        BOOL isOn = [sender state] == NSOnState;
        if (isOn) {
            static NSString *const kWarnAboutSendCodeWhenIdle = @"NoSyncWarnAboutSendCodeWhenIdle";
            // This stupid feature was inherited from iTerm 0.1. It doesn't work because people
            // set a code of 0, thinking it will keep their ssh sessions alive. While it does, it
            // will also fill your prompt with ^@ characters, if you're lucky. If you're not at your
            // prompt it could do basically anything. It's useful for people working with awful
            // outdated networking equipment who know what they're doing so I'm not killing it.
            // If you came here because you want to keep your ssh sessions alive, look into enabling
            // KeepAlive on your ssh client. Put this in your ~/.ssh/config:
            // Host *
            //   ServerAliveInterval 60
            iTermWarningSelection selection =
                [iTermWarning showWarningWithTitle:@"You probably don't want to turn this on. "
                                                   @"It's not suitable for keeping ssh sessions alive, "
                                                   @"even with a code of “0”. Are you sure you want this?"
                                           actions:@[ @"Enable Send Code", @"Cancel" ]
                                        identifier:kWarnAboutSendCodeWhenIdle
                                       silenceable:kiTermWarningTypePermanentlySilenceable
                                            window:weakSelf.view.window];
            if (selection == kiTermWarningSelection0) {
                [strongSelf setBool:YES forKey:KEY_SEND_CODE_WHEN_IDLE];
            }
        } else {
            [strongSelf setBool:NO forKey:KEY_SEND_CODE_WHEN_IDLE];
        }
    };
    info.observer = ^() {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf->_idleCode.enabled = [self boolForKey:KEY_SEND_CODE_WHEN_IDLE];
        strongSelf->_idlePeriod.enabled = [self boolForKey:KEY_SEND_CODE_WHEN_IDLE];
    };

    info = [self defineControl:_idleCode
                           key:KEY_IDLE_CODE
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(0, 256);

    [self defineControl:_idlePeriod
                    key:KEY_IDLE_PERIOD
                   type:kPreferenceInfoTypeDoubleTextField];

    [self updateRemoveJobButtonEnabled];

    [self defineControl:_reduceFlicker
                    key:KEY_REDUCE_FLICKER
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_statusBarEnabled
                           key:KEY_SHOW_STATUS_BAR
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf->_configureStatusBar.enabled = (![self.delegate editingTmuxSession] &&
                                                   [strongSelf boolForKey:KEY_SHOW_STATUS_BAR]);
    };
    info.onChange = ^() { [weakSelf postRefreshNotification]; };
}

// Ensure the anti-idle period's value is constrained to the legal range.
- (void)setDouble:(double)value forKey:(NSString *)key {
    if ([key isEqualToString:KEY_IDLE_PERIOD]) {
        value = MAX(kMinimumAntiIdlePeriod, value);
    }
    [super setDouble:value forKey:key];
}

- (void)layoutSubviewsForEditCurrentSessionMode {
    NSArray *viewsToDisable = @[ _autoLog,
                                 _logDir,
                                 _changeLogDir ];
    for (id view in viewsToDisable) {
        [view setEnabled:NO];
    }
    [self awakeFromNib];  // We can get called before awakeFromNib
    [self infoForControl:_autoLog].observer = NULL;
    [self infoForControl:_logDir].observer = NULL;
    [self updateStatusBarSettingsEnabled];
}

- (void)updateStatusBarSettingsEnabled {
    const BOOL tmux = [self.delegate editingTmuxSession];
    _statusBarEnabled.enabled = !tmux;
    _configureStatusBar.enabled = !tmux;
}

- (void)reloadProfile {
    [super reloadProfile];
    [_jobsTable reloadData];
    [self updateRemoveJobButtonEnabled];
    [self updateStatusBarSettingsEnabled];
}

- (NSArray *)keysForBulkCopy {
    NSArray *keys = @[ KEY_JOBS ];
    return [[super keysForBulkCopy] arrayByAddingObjectsFromArray:keys];
}

- (BOOL)allowRainbow {
    if (@available(macOS 10.14, *)) {
        const iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
        const iTermWindowType windowType = [self intForKey:KEY_WINDOW_TYPE];
        return (preferredStyle == TAB_STYLE_MINIMAL && windowType == WINDOW_TYPE_COMPACT);
    } else {
        return NO;
    }
}

- (iTermColorMap *)colorMap {
    iTermColorMap *colorMap = [[iTermColorMap alloc] init];
    colorMap.mutingAmount = [self floatForKey:KEY_CURSOR_BOOST];
    colorMap.dimOnlyText = [iTermPreferences boolForKey:kPreferenceKeyDimOnlyText];
    colorMap.minimumContrast = [self floatForKey:KEY_MINIMUM_CONTRAST];
    return colorMap;
}

- (id<PSMTabStyle>)tabStyle {
    return [[iTermTheme sharedInstance] tabStyleWithDelegate:self
                                         effectiveAppearance:self.view.window.effectiveAppearance];
}

- (NSColor *)sessionBackgroundColor {
    NSDictionary *dict = [NSDictionary castFrom:[self objectForKey:KEY_BACKGROUND_COLOR]];
    if (!dict) {
        return [NSColor colorWithRed:0 green:0 blue:0 alpha:1];
    }
    return [dict colorValue];
}

- (NSColor *)tabColor {
    if (![self boolForKey:KEY_USE_TAB_COLOR]) {
        return nil;
    }
    NSDictionary *dict = [NSDictionary castFrom:[self objectForKey:KEY_TAB_COLOR]];
    if (!dict) {
        return nil;
    }
    return [dict colorValue];
}

- (NSAppearance *)appearanceForCurrentTheme {
    const iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    switch (preferredStyle) {
        case TAB_STYLE_DARK:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            return [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
        case TAB_STYLE_LIGHT:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
            return [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_MINIMAL:
            return self.view.effectiveAppearance;
    }
}

- (IBAction)configureStatusBar:(id)sender {
    NSDictionary *layoutDictionary = [NSDictionary castFrom:[self objectForKey:KEY_STATUS_BAR_LAYOUT]] ?: @{};
    NSDictionary *colorDict = [NSDictionary castFrom:[self objectForKey:KEY_BACKGROUND_COLOR]];
    const BOOL dark = [[colorDict colorValue] perceivedBrightness] < 0.5;
    _statusBarSetupViewController =
        [[iTermStatusBarSetupViewController alloc] initWithLayoutDictionary:layoutDictionary
                                                             darkBackground:dark
                                                               allowRainbow:[self allowRainbow]];
    _statusBarSetupViewController.defaultTextColor = [[iTermTheme sharedInstance] statusBarTextColorForEffectiveAppearance:[self appearanceForCurrentTheme]
                                                                                                                  colorMap:[self colorMap]
                                                                                                                  tabStyle:[self tabStyle]
                                                                                                             mainAndActive:YES];
    _statusBarSetupViewController.defaultBackgroundColor = [[iTermTheme sharedInstance] statusBarContainerBackgroundColorForTabColor:[self tabColor]
                                                                                                                 effectiveAppearance:[self appearanceForCurrentTheme]
                                                                                                                            tabStyle:[self tabStyle]
                                                                                                              sessionBackgroundColor:[self sessionBackgroundColor]
                                                                                                                    isFirstResponder:YES
                                                                                                                         dimOnlyText:[self boolForKey:kPreferenceKeyDimOnlyText]
                                                                                                               adjustedDimmingAmount:0];

    _statusBarSetupWindow =
        [[iTermStatusBarSetupPanel alloc] initWithContentRect:_statusBarSetupViewController.view.frame
                                                    styleMask:NSWindowStyleMaskResizable
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
    _statusBarSetupWindow.contentView = _statusBarSetupViewController.view;
    __weak __typeof(self) weakSelf = self;
    [self.view.window beginSheet:_statusBarSetupWindow completionHandler:^(NSModalResponse returnCode) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            if (strongSelf->_statusBarSetupViewController.ok) {
                [strongSelf setObject:strongSelf->_statusBarSetupViewController.layoutDictionary
                               forKey:KEY_STATUS_BAR_LAYOUT];
            }
            strongSelf->_statusBarSetupWindow = nil;
            strongSelf->_statusBarSetupViewController = nil;
        }
    }];
}

- (void)configureStatusBarComponentWithIdentifier:(NSString *)identifier {
    if (_statusBarEnabled.state != NSOnState) {
        return;
    }
    [self configureStatusBar:nil];
    [_statusBarSetupViewController configureStatusBarComponentWithIdentifier:identifier];
}

#pragma mark - Prompt before closing

- (void)promptBeforeClosingDidChange {
    int tag = 0;
    for (NSButton *button in @[_alwaysWarn, _neverWarn, _warnIfJobsBesides]) {
        if (button.state == NSOnState) {
            tag = button.tag;
            break;
        }
    }
    [self setInt:tag forKey:KEY_PROMPT_CLOSE];
}

- (void)updatePromptBeforeClosing {
    int tag = [self intForKey:KEY_PROMPT_CLOSE];
    for (NSButton *button in @[_alwaysWarn, _neverWarn, _warnIfJobsBesides]) {
        if (button.tag == tag) {
            button.state = NSOnState;
        } else {
            button.state = NSOffState;
        }
    }
}

#pragma mark - Jobs

- (NSArray *)jobs {
    return (NSArray *)[self objectForKey:KEY_JOBS];
}

- (IBAction)addJob:(id)sender {
    NSArray *jobNames = [self jobs];
    NSMutableArray *augmented;
    if (jobNames) {
        augmented = [NSMutableArray arrayWithArray:jobNames];
        [augmented addObject:@"Job Name"];
    } else {
        augmented = [NSMutableArray arrayWithObject:@"Job Name"];
    }
    [self setObject:augmented forKey:KEY_JOBS];
    [_jobsTable reloadData];
    [_jobsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:[augmented count] - 1]
            byExtendingSelection:NO];
    [_jobsTable editColumn:0
                       row:[self numberOfRowsInTableView:_jobsTable] - 1
                 withEvent:nil
                    select:YES];
    [self updateRemoveJobButtonEnabled];
    [self postRefreshNotification];
}

- (IBAction)removeJob:(id)sender {
    // Causes editing to end. If you try to remove a cell that is being edited,
    // it tries to dereference the deleted cell. There doesn't seem to be an
    // API that explicitly ends editing.
    [_jobsTable reloadData];

    NSInteger selectedIndex = [_jobsTable selectedRow];
    if (selectedIndex < 0) {
        return;
    }
    NSArray *jobNames = [self jobs];
    NSMutableArray *mod = [NSMutableArray arrayWithArray:jobNames];
    [mod removeObjectAtIndex:selectedIndex];

    [self setObject:mod forKey:KEY_JOBS];
    [_jobsTable reloadData];
    [self updateRemoveJobButtonEnabled];
    [self postRefreshNotification];
}

- (void)updateRemoveJobButtonEnabled {
    _removeJob.enabled = ([_jobsTable selectedRow] != -1);
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView: (NSTableView *)aTableView {
    return [[self jobs] count];
}


- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex {
    NSMutableArray *jobs = [NSMutableArray arrayWithArray:[self jobs]];
    [jobs replaceObjectAtIndex:rowIndex withObject:anObject];
    [self setObject:jobs forKey:KEY_JOBS];
    [self postRefreshNotification];
}

- (id)tableView:(NSTableView *)aTableView
    objectValueForTableColumn:(NSTableColumn *)aTableColumn
                row:(NSInteger)rowIndex {
    NSArray *jobs = self.jobs;
    if (rowIndex >= jobs.count) {
        // Can happen during teardown when the ProfilePreferencesViewController's delegate is nilled.
        return @"";
    }
    return jobs[rowIndex];
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
    [self updateRemoveJobButtonEnabled];
}

#pragma mark - Notifications

- (void)reloadProfiles {
    [_jobsTable reloadData];
}

#pragma mark - Log directory

- (IBAction)selectLogDir:(id)sender {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];

    if ([panel runModal] == NSModalResponseOK) {
        NSString *path = [[panel directoryURL] path];
        _logDir.stringValue = path;
        [self setString:path forKey:KEY_LOGDIR];
    }
    [self updateLogDirWarning];
}

- (void)updateLogDirWarning {
    [_logDirWarning setHidden:[_autoLog state] == NSOffState || [self logDirIsWritable]];
}

- (BOOL)logDirIsWritable {
    return [[NSFileManager defaultManager] directoryIsWritable:[_logDir stringValue]];
}

#pragma mark - PSMMinimalTabStyleDelegate

- (NSColor *)minimalTabStyleBackgroundColor {
    return [self sessionBackgroundColor];
}

@end
