//
//  GeneralPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import "GeneralPreferencesViewController.h"
#import "NSBundle+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSTextField+iTerm.h"
#import "NSWorkspace+iTerm.h"
#import "PasteboardHistory.h"
#import "RegexKitLite.h"
#import "WindowArrangements.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAPIHelper.h"
#import "iTermAdvancedGPUSettingsViewController.h"
#import "iTermApplicationDelegate.h"
#import "iTermBuriedSessions.h"
#import "iTermHotKeyController.h"
#import "iTermNotificationCenter.h"
#import "iTermPreferenceDidChangeNotification.h"
#import "iTermRemotePreferences.h"
#import "iTermScriptsMenuController.h"
#import "iTermShellHistoryController.h"
#import "iTermUserDefaults.h"
#import "iTermUserDefaultsObserver.h"
#import "iTermWarning.h"
#import <SSKeychain/SSKeychain.h>

@interface GeneralPreferencesViewController () <NSTableViewDataSource, CompetentTableViewDelegate, NSTextFieldDelegate>
@end

enum {
    kUseSystemWindowRestorationSettingTag = 0,
    kOpenDefaultWindowArrangementTag = 1,
    kDontOpenAnyWindowsTag= 2
};

static NSString *const kAIManualModelIDKey = @"id";
static NSString *const kAIManualModelNameKey = @"name";
static NSString *const kAIManualModelURLKey = @"url";
static NSString *const kAIManualModelAPIKey = @"api";
static NSString *const kAIManualModelContextWindowTokensKey = @"contextWindowTokens";
static NSString *const kAIManualModelMaxResponseTokensKey = @"maxResponseTokens";
static NSString *const kAIManualModelHostedCodeInterpreterKey = @"hostedCodeInterpreter";
static NSString *const kAIManualModelHostedFileSearchKey = @"hostedFileSearch";
static NSString *const kAIManualModelHostedWebSearchKey = @"hostedWebSearch";
static NSString *const kAIManualModelFunctionCallingKey = @"functionCalling";
static NSString *const kAIManualModelStreamingKey = @"streaming";
static NSString *const kAIManualModelVectorStoreKey = @"vectorStore";

static NSString *const kAIManualModelsDefaultColumn = @"default";
static NSString *const kAIManualModelsModelColumn = @"model";
static NSString *const kAIManualModelsAPIColumn = @"api";
static NSString *const kAIManualModelsEndpointColumn = @"endpoint";
static NSString *const kAIDefaultModelProviderPrefix = @"provider:";
static NSString *const kAIDefaultModelManualPrefix = @"manual:";

typedef NS_ENUM(NSInteger, iTermManualAIModelManagerResponse) {
    iTermManualAIModelManagerResponseAdd = 1001,
    iTermManualAIModelManagerResponseEdit,
    iTermManualAIModelManagerResponseDuplicate,
    iTermManualAIModelManagerResponseDelete,
    iTermManualAIModelManagerResponseDefault
};

static NSInteger iTermManualAIModelIntegerValue(NSDictionary *configuration,
                                                NSString *key,
                                                NSInteger fallback) {
    id value = configuration[key];
    if ([value respondsToSelector:@selector(integerValue)]) {
        return [value integerValue];
    }
    return fallback;
}

static NSString *iTermTitleForAIAPI(iTermAIAPI api) {
    switch (api) {
        case iTermAIAPIResponses:
            return @"Responses";
        case iTermAIAPIChatCompletions:
            return @"Chat Completions";
        case iTermAIAPICompletions:
            return @"Completions";
        case iTermAIAPIGemini:
            return @"Google Gemini";
        case iTermAIAPIEarlyO1:
            return @"Chat Completions (Early O1)";
        case iTermAIAPILlama:
            return @"Llama";
        case iTermAIAPIDeepSeek:
            return @"DeepSeek";
        case iTermAIAPIAnthropic:
            return @"Anthropic";
        case iTermAIAPIAppleIntelligence:
            return @"Apple Intelligence";
    }
}

static NSString *iTermManualAIModelHost(NSDictionary *configuration) {
    NSString *url = configuration[kAIManualModelURLKey] ?: @"";
    if (url.length == 0) {
        return @"";
    }
    NSURL *parsedURL = [NSURL URLWithString:url];
    return parsedURL.host ?: url;
}

@interface iTermManualAIModelsPanelController : NSObject<NSTableViewDataSource, NSTableViewDelegate>
@property(nonatomic, copy) NSArray<NSDictionary *> *configurations;
@property(nonatomic, copy) NSString *defaultModelName;
@property(nonatomic) NSInteger selectedIndex;
@property(nonatomic, strong) NSTableView *tableView;
@property(nonatomic, copy) NSArray<NSButton *> *selectionButtons;
- (instancetype)initWithConfigurations:(NSArray<NSDictionary *> *)configurations
                      defaultModelName:(NSString *)defaultModelName
                         selectedIndex:(NSInteger)selectedIndex;
- (NSView *)view;
@end

@implementation iTermManualAIModelsPanelController

- (instancetype)initWithConfigurations:(NSArray<NSDictionary *> *)configurations
                      defaultModelName:(NSString *)defaultModelName
                         selectedIndex:(NSInteger)selectedIndex {
    self = [super init];
    if (self) {
        _configurations = [configurations copy];
        _defaultModelName = [defaultModelName copy];
        _selectedIndex = selectedIndex;
    }
    return self;
}

- (NSView *)view {
    const CGFloat width = 720;
    const CGFloat height = 292;
    const CGFloat tableWidth = 568;
    const CGFloat buttonWidth = 120;
    const CGFloat buttonHeight = 28;
    const CGFloat buttonX = tableWidth + 16;
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];

    NSTextField *title = [NSTextField labelWithString:@"Manual models"];
    title.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    title.frame = NSMakeRect(0, height - 24, tableWidth, 20);
    [view addSubview:title];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 42, tableWidth, 214)];
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.borderType = NSBezelBorder;

    NSTableView *tableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
    tableView.delegate = self;
    tableView.dataSource = self;
    tableView.headerView = [[NSTableHeaderView alloc] initWithFrame:NSMakeRect(0, 0, tableWidth, 22)];
    tableView.usesAlternatingRowBackgroundColors = YES;
    tableView.allowsMultipleSelection = NO;
    tableView.rowHeight = 28;

    NSArray<NSDictionary *> *columns = @[
        @{ @"identifier": kAIManualModelsDefaultColumn, @"title": @"", @"width": @64 },
        @{ @"identifier": kAIManualModelsModelColumn, @"title": @"Model", @"width": @210 },
        @{ @"identifier": kAIManualModelsAPIColumn, @"title": @"API", @"width": @134 },
        @{ @"identifier": kAIManualModelsEndpointColumn, @"title": @"Endpoint", @"width": @150 }
    ];
    for (NSDictionary *spec in columns) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:spec[@"identifier"]];
        column.title = spec[@"title"];
        column.width = [spec[@"width"] doubleValue];
        column.resizingMask = NSTableColumnUserResizingMask;
        [tableView addTableColumn:column];
    }

    scrollView.documentView = tableView;
    _tableView = tableView;
    [view addSubview:scrollView];

    NSArray<NSDictionary *> *buttons = @[
        @{ @"title": @"Add", @"tag": @(iTermManualAIModelManagerResponseAdd) },
        @{ @"title": @"Edit", @"tag": @(iTermManualAIModelManagerResponseEdit) },
        @{ @"title": @"Duplicate", @"tag": @(iTermManualAIModelManagerResponseDuplicate) },
        @{ @"title": @"Delete", @"tag": @(iTermManualAIModelManagerResponseDelete) },
        @{ @"title": @"Set Default", @"tag": @(iTermManualAIModelManagerResponseDefault) }
    ];
    NSMutableArray<NSButton *> *selectionButtons = [NSMutableArray array];
    CGFloat buttonY = 226;
    for (NSDictionary *spec in buttons) {
        NSButton *button = [NSButton buttonWithTitle:spec[@"title"]
                                              target:self
                                              action:@selector(performManualModelAction:)];
        button.frame = NSMakeRect(buttonX, buttonY, buttonWidth, buttonHeight);
        button.bezelStyle = NSBezelStyleRounded;
        button.tag = [spec[@"tag"] integerValue];
        [view addSubview:button];
        if (button.tag != iTermManualAIModelManagerResponseAdd) {
            [selectionButtons addObject:button];
        }
        buttonY -= 36;
    }
    self.selectionButtons = selectionButtons;

    NSString *footerText = self.configurations.count == 0
        ? @"No manual models configured. Add one to use it as a default model or from AI Chat."
        : @"Select a row to edit, duplicate, delete, or make it the default model for new chats.";
    NSTextField *footer = [NSTextField labelWithString:footerText];
    footer.textColor = NSColor.secondaryLabelColor;
    footer.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    footer.frame = NSMakeRect(0, 8, width, 20);
    [view addSubview:footer];

    if (self.configurations.count > 0) {
        self.selectedIndex = MAX(0, MIN(self.selectedIndex, (NSInteger)self.configurations.count - 1));
        [tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)self.selectedIndex]
                byExtendingSelection:NO];
    }
    [self updateSelectionButtons];
    return view;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.configurations.count;
}

- (id)tableView:(NSTableView *)tableView
objectValueForTableColumn:(NSTableColumn *)tableColumn
            row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.configurations.count) {
        return @"";
    }
    NSDictionary *configuration = self.configurations[(NSUInteger)row];
    NSString *identifier = tableColumn.identifier;
    if ([identifier isEqualToString:kAIManualModelsDefaultColumn]) {
        NSString *name = configuration[kAIManualModelNameKey];
        return [name isEqualToString:self.defaultModelName] ? @"Default" : @"";
    }
    if ([identifier isEqualToString:kAIManualModelsModelColumn]) {
        return configuration[kAIManualModelNameKey] ?: @"Untitled model";
    }
    if ([identifier isEqualToString:kAIManualModelsAPIColumn]) {
        iTermAIAPI api = (iTermAIAPI)iTermManualAIModelIntegerValue(configuration,
                                                                   kAIManualModelAPIKey,
                                                                   iTermAIAPIChatCompletions);
        return iTermTitleForAIAPI(api);
    }
    if ([identifier isEqualToString:kAIManualModelsEndpointColumn]) {
        return iTermManualAIModelHost(configuration);
    }
    return @"";
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    self.selectedIndex = self.tableView.selectedRow;
    [self updateSelectionButtons];
}

- (void)updateSelectionButtons {
    const BOOL hasSelection = self.selectedIndex >= 0 && self.selectedIndex < (NSInteger)self.configurations.count;
    for (NSButton *button in self.selectionButtons) {
        button.enabled = hasSelection;
    }
}

- (void)performManualModelAction:(NSButton *)sender {
    if (sender.tag != iTermManualAIModelManagerResponseAdd) {
        self.selectedIndex = self.tableView.selectedRow;
        if (self.selectedIndex < 0 || self.selectedIndex >= (NSInteger)self.configurations.count) {
            NSBeep();
            return;
        }
    }
    [NSApp stopModalWithCode:sender.tag];
}

@end

@implementation GeneralPreferencesViewController {
    BOOL _awoken;
    // open bookmarks when iterm starts
    IBOutlet NSButton *_openBookmark;
    IBOutlet NSButton *_advancedGPUPrefsButton;

    // Open saved window arrangement at startup
    IBOutlet NSPopUpButton *_openWindowsAtStartup;
    IBOutlet NSTextField *_openWindowsAtStartupLabel;
    IBOutlet NSButton *_alwaysOpenWindowAtStartup;
    IBOutlet NSTextField *_alwaysOpenLegend;
    IBOutlet NSButton *_restoreWindowsToSameSpaces;

    IBOutlet NSMenuItem *_openDefaultWindowArrangementItem;

    // Quit when all windows are closed
    IBOutlet NSButton *_quitWhenAllWindowsClosed;

    // Confirm closing multiple sessions
    IBOutlet id _confirmClosingMultipleSessions;

    // Warn when quitting
    IBOutlet id _promptOnQuit;
    IBOutlet NSButton *_evenIfThereAreNoWindows;

    // Instant replay memory usage.
    IBOutlet NSTextField *_irMemory;
    IBOutlet NSTextField *_irMemoryLabel;

    // Save copy paste history
    IBOutlet NSButton *_savePasteHistory;

    // Use GPU?
    IBOutlet NSButton *_gpuRendering;
    IBOutlet NSButton *_advancedGPU;
    iTermAdvancedGPUSettingsWindowController *_advancedGPUWindowController;

    IBOutlet NSButton *_maximizeThroughput;
    IBOutlet NSButton *_enableAPI;
    IBOutlet NSPopUpButton *_apiPermission;

    // Enable bonjour
    IBOutlet NSButton *_enableBonjour;

    IBOutlet NSButton *_notifyOnlyCriticalShellIntegrationUpdates;

    // Check for updates automatically
    IBOutlet NSButton *_checkUpdate;

    // Prompt for test-release updates
    IBOutlet NSButton *_checkTestRelease;

    // Warning that nightly builds can't update to beta/release
    IBOutlet NSTextField *_nightlyBuildNotice;

    // Load prefs from custom folder
    IBOutlet NSButton *_loadPrefsFromCustomFolder;  // Should load?
    IBOutlet NSTextField *_prefsCustomFolder;  // Path or URL text field
    IBOutlet NSImageView *_prefsDirWarning;  // Image shown when path is not writable
    IBOutlet NSButton *_browseCustomFolder;  // Push button to open file browser
    IBOutlet NSButton *_pushToCustomFolder;  // Push button to copy local to remote
    IBOutlet NSPopUpButton *_saveChanges;  // Save settings to folder when
    IBOutlet NSTextField *_saveChangesLabel;

    IBOutlet NSButton *_useCustomScriptsFolder;
    IBOutlet NSTextField *_customScriptsFolder;
    IBOutlet NSImageView *_customScriptsFolderWarning;
    IBOutlet NSButton *_browseCustomScriptsFolder;

    // Copy to clipboard on selection
    IBOutlet NSButton *_selectionCopiesText;

    // Copy includes trailing newline
    IBOutlet NSButton *_copyLastNewline;

    // Triple click selects full, wrapped lines.
    IBOutlet NSButton *_tripleClickSelectsFullLines;

    // Double click perform smart selection
    IBOutlet NSButton *_doubleClickPerformsSmartSelection;

    // Allow clipboard access by terminal applications
    IBOutlet NSButton *_allowClipboardAccessFromTerminal;

    // Characters considered part of word
    IBOutlet NSTextField *_wordChars;
    IBOutlet NSTextField *_wordCharsRegex;
    IBOutlet NSTextField *_wordCharsLabel;
    IBOutlet NSPopUpButton *_wordMode;

    // Smart window placement
    IBOutlet NSButton *_smartPlacement;
    IBOutlet NSButton *_useAutoSaveFrames;
    IBOutlet NSButton *_rememberPositionOnly;
    IBOutlet NSButton *_defaultPositioning;
    IBOutlet NSView *_placementContainer;

    // Adjust window size when changing font size
    IBOutlet NSButton *_adjustWindowForFontSizeChange;

    // Zoom vertically only
    IBOutlet NSButton *_maxVertically;

    IBOutlet NSButton *_separateWindowTitlePerTab;

    // Lion-style fullscreen
    IBOutlet NSButton *_lionStyleFullscreen;

    // Open tmux windows in [windows, tabs]
    IBOutlet NSButton *_openTmuxWindowsAsTabsInAttachingWindow;
    IBOutlet NSTextField *_whenAttachingTmuxLabel;
    IBOutlet NSPopUpButton *_openUnrecognizedTmuxWindowsIn;

    // Hide the tmux client session
    IBOutlet NSButton *_autoHideTmuxClientSession;
    
    IBOutlet NSButton *_useTmuxProfile;
    IBOutlet NSButton *_useTmuxStatusBar;

    IBOutlet NSTextField *_tmuxPauseModeAgeLimit;
    IBOutlet NSButton *_unpauseTmuxAutomatically;
    IBOutlet NSButton *_tmuxWarnBeforePausing;

    IBOutlet NSButton *_syncTmuxClipboard;

    IBOutlet NSTabView *_tabView;

    IBOutlet NSButton *_enterCopyModeAutomatically;
    IBOutlet NSButton *_warningButton;
    iTermUserDefaultsObserver *_observer;

    IBOutlet NSButton *_clickToSelectCommand;
    IBOutlet NSButton *_wrapDroppedFilenamesInQuotesWhenPasting;

    IBOutlet NSPopUpButton *_allowsSendingClipboardContents;
    IBOutlet NSTextField *_allowsSendingClipboardContentsLabel;

    IBOutlet NSButton *_disableConfirmationOnShutdown;

    IBOutlet NSButton *_openAIAPIKey;
    IBOutlet NSTextField *_openAIAPIKeyLabel;
    NSTextField *_aiAPIKeysStatus;
    NSMutableArray<NSSecureTextField *> *_aiAPIKeySheetFields;
    NSMutableArray<NSTextField *> *_aiAPIKeySheetStatusLabels;

    IBOutlet NSPopUpButton *_promptSelector;
    IBOutlet NSTextView *_aiPrompt;
    IBOutlet NSImageView *_aiPromptWarning;  // Image shown when prompt lacks \(ai.prompt)

    BOOL _customScriptsFolderDidChange;

    IBOutlet NSComboBox *_aiModel;
    IBOutlet NSTextField *_aiTokenLimit;
    IBOutlet NSTextField *_aiResponseTokenLimit;
    IBOutlet NSTextField *_aiModelLabel;
    IBOutlet NSTextField *_aiTokenLimitLabel;
    IBOutlet NSButton *_resetAIPrompt;
    IBOutlet NSTextField *_aiTimeout;

    IBOutlet NSTextField *_aiPluginLabel;
    IBOutlet NSButton *_enableAI;
    IBOutlet NSTextField *_pluginStatus;
    IBOutlet NSButton *_installPluginButton;
    BOOL _pluginOK;

    IBOutlet NSTextField *_customAIEndpoint;
    IBOutlet NSPopUpButton *_aiAPI;

    IBOutlet NSButton *_aiFeatureHostedCodeInterpeter;
    IBOutlet NSButton *_aiFeatureHostedFileSearch;
    IBOutlet NSButton *_aiFeatureHostedWebSearch;
    IBOutlet NSButton *_aiFeatureFunctionCalling;
    IBOutlet NSButton *_aiFeatureStreamingResponses;
    IBOutlet NSPopUpButton *_vectorStore;

    IBOutlet NSButton *_useRecommendedModel;
    IBOutlet NSView *_manualAISettings;
    NSWindow *_manualAIConfigurationSheet;
    IBOutlet NSButton *_manualAIConfiguration;
    IBOutlet NSPopUpButton *_aiVendor;
    IBOutlet NSButton *_aiSafetyCheck;

    IBOutlet NSTextField *_checkTerminalStateLabel; // Check Terminal State
    IBOutlet NSPopUpButton *_checkTerminalStateButton;
    IBOutlet NSTextField *_runCommandsLabel; // Run Commands
    IBOutlet NSPopUpButton *_runCommandsButton;
    IBOutlet NSTextField *_viewHistoryLabel; // View History
    IBOutlet NSPopUpButton *_viewHistoryButton;
    IBOutlet NSTextField *_writeToClipboardLabel; // Write to the Clipboard
    IBOutlet NSPopUpButton *_writeToClipboardButton;
    IBOutlet NSTextField *_typeForYouLabel; // Type for You
    IBOutlet NSPopUpButton *_typeForYouButton;
    IBOutlet NSTextField *_viewManpagesLabel; // View Manpages
    IBOutlet NSPopUpButton *_viewManpagesButton;
    IBOutlet NSTextField *_writeToFilesystemLabel; // View Manpages
    IBOutlet NSPopUpButton *_writeToFilesystemButton;
    IBOutlet NSTextField *_actInWebBrowserLabel; // Act in web browser
    IBOutlet NSPopUpButton *_actInWebBrowserButton;
    IBOutlet NSButton *_aiCompletions;

    IBOutlet NSButton *_enableRTL;
    IBOutlet NSButton *_sshIntegrationForURLs;

    NSString *_lastModel;
    PreferenceInfo *_aiModelInfo;
    PreferenceInfo *_aiTokenLimitInfo;
    PreferenceInfo *_aiResponseTokenLimitInfo;
    PreferenceInfo *_aiURLInfo;
    PreferenceInfo *_aiAPIInfo;
    NSArray<PreferenceInfo *> *_aiFeatureInfos;

    // Custom headers section (wired up in the XIB).
    IBOutlet NSButton *_aiCustomHeadersEnabled;
    IBOutlet NSTableView *_aiCustomHeadersTableView;
    IBOutlet NSSegmentedControl *_aiCustomHeadersAddRemove;  // segment 0 = add, segment 1 = remove
    NSMutableArray<NSMutableDictionary *> *_customHeaders;
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(savedArrangementChanged:)
                                                     name:kSavedArrangementDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didRevertPythonAuthenticationMethod:)
                                                     name:iTermAPIHelperDidDetectChangeOfPythonAuthMethodNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(updateAlwaysOpenLegend)
                                                     name:iTermSessionBuriedStateChangeTabNotification
                                                   object:nil];
        _observer = [[iTermUserDefaultsObserver alloc] init];
        __weak __typeof(self) weakSelf = self;
        [_observer observeKey:@"NSQuitAlwaysKeepsWindows" block:^{
            [weakSelf updateEnabledState];
        }];

        static iTermUserDefaultsObserver *gRemotePrefsObserver;
        gRemotePrefsObserver = [[iTermUserDefaultsObserver alloc] init];
        [gRemotePrefsObserver observeKey:kPreferenceKeyCustomFolder block:^{
            DLog(@"Remote prefs changed from\n%@", [NSThread callStackSymbols]);
        }];
        [gRemotePrefsObserver observeKey:kPreferenceKeyLoadPrefsFromCustomFolder block:^{
            [weakSelf loadPrefsFromCustomFolderDidChangeByUI:NO];
        }];
    }
    return self;
}

- (void)awakeFromNib {
    if (_awoken) {
        // View-based NSTableView lazily unarchives each NSTableCellView prototype
        // from an inline nib using File’s Owner as the nib owner, which causes a
        // second -awakeFromNib on this controller. Idempotency is required.
        return;
    }
    _awoken = YES;

    [self setupCustomHeadersSection];
    [self setupAIAPIKeysRow];
    [self setupDefaultAIModelSelector];
    PreferenceInfo *info;

    __weak __typeof(self) weakSelf = self;
    [self defineControl:_openBookmark
                    key:kPreferenceKeyOpenBookmark
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_openWindowsAtStartup
                           key:kPreferenceKeyOpenArrangementAtStartup
                   relatedView:_openWindowsAtStartupLabel
                          type:kPreferenceInfoTypeCheckbox
                settingChanged:^(id sender) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        switch ([strongSelf->_openWindowsAtStartup selectedTag]) {
            case kUseSystemWindowRestorationSettingTag:
                [strongSelf setBool:NO forKey:kPreferenceKeyOpenArrangementAtStartup];
                [strongSelf setBool:NO forKey:kPreferenceKeyOpenNoWindowsAtStartup];
                break;

            case kOpenDefaultWindowArrangementTag:
                [strongSelf setBool:YES forKey:kPreferenceKeyOpenArrangementAtStartup];
                [strongSelf setBool:NO forKey:kPreferenceKeyOpenNoWindowsAtStartup];
                break;

            case kDontOpenAnyWindowsTag:
                [strongSelf setBool:NO forKey:kPreferenceKeyOpenArrangementAtStartup];
                [strongSelf setBool:YES forKey:kPreferenceKeyOpenNoWindowsAtStartup];
                break;
        }
        [strongSelf updateEnabledState];
    } update:^BOOL{
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return NO;
        }
        if ([strongSelf boolForKey:kPreferenceKeyOpenNoWindowsAtStartup]) {
            [strongSelf->_openWindowsAtStartup selectItemWithTag:kDontOpenAnyWindowsTag];
        } else if ([WindowArrangements count] &&
                   [self boolForKey:kPreferenceKeyOpenArrangementAtStartup]) {
            [strongSelf->_openWindowsAtStartup selectItemWithTag:kOpenDefaultWindowArrangementTag];
        } else {
            [strongSelf->_openWindowsAtStartup selectItemWithTag:kUseSystemWindowRestorationSettingTag];
        }
        [strongSelf updateEnabledState];
        return YES;
    }];
    info.hasDefaultValue = ^BOOL{
        return [weakSelf boolForKey:kPreferenceKeyOpenArrangementAtStartup] == NO && [weakSelf boolForKey:kPreferenceKeyOpenNoWindowsAtStartup] == NO;
    };
    [self updateNonDefaultIndicatorVisibleForInfo:info];

    [_openDefaultWindowArrangementItem setEnabled:[WindowArrangements count] > 0];

    [self defineControl:_restoreWindowsToSameSpaces
                    key:kPreferenceKeyRestoreWindowsToSameSpaces
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_alwaysOpenWindowAtStartup
                    key:kPreferenceKeyAlwaysOpenWindowAtStartup
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self updateAlwaysOpenLegend];

    [self defineControl:_quitWhenAllWindowsClosed
                    key:kPreferenceKeyQuitWhenAllWindowsClosed
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_confirmClosingMultipleSessions
                    key:kPreferenceKeyConfirmClosingMultipleTabs
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_promptOnQuit
                           key:kPreferenceKeyPromptOnQuit
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^{
        [weakSelf updateEnabledState];
    };

    [self defineControl:_disableConfirmationOnShutdown
                    key:kPreferenceKeyNeverBlockSystemShutdown
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_evenIfThereAreNoWindows
                    key:kPreferenceKeyPromptOnQuitEvenIfThereAreNoWindows
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_irMemory
                           key:kPreferenceKeyInstantReplayMemoryMegabytes
                   displayName:@"Instant Replay memory usage limit"
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(0, 1000);

    info = [self defineControl:_savePasteHistory
                           key:kPreferenceKeySavePasteAndCommandHistory
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() {
        [[iTermShellHistoryController sharedInstance] backingStoreTypeDidChange];
    };

    info = [self defineControl:_gpuRendering
                           key:kPreferenceKeyUseMetal
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        [weakSelf updateAdvancedGPUEnabled];
    };

    info = [self defineControl:_enableAPI
                           key:kPreferenceKeyEnableAPIServer
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.customSettingChangedHandler = ^(id sender) {
        [weakSelf enableAPISettingDidChange];
    };
    [iTermPreferenceDidChangeNotification subscribe:self
                                              block:^(iTermPreferenceDidChangeNotification * _Nonnull notification) {
        if ([notification.key isEqualToString:kPreferenceKeyEnableAPIServer]) {
            __typeof(self) strongSelf = weakSelf;
            if (strongSelf) {
                strongSelf->_enableAPI.state = NSControlStateValueOn;
            }
        }
    }];

    info = [self defineControl:_apiPermission
                           key:kPreferenceKeyAPIAuthentication
                   displayName:@"Authentication method for Python API"
                          type:kPreferenceInfoTypePopup];
    info.syntheticGetter = ^id{
        return @([iTermAPIHelper requireApplescriptAuth] ? 0 : 1);
    };
    info.syntheticSetter = ^(NSNumber *newValue) {
        const BOOL useApplescript = (newValue.intValue == 0);
        [iTermAPIHelper setRequireApplescriptAuth:useApplescript
                                           window:self.view.window];
        [weakSelf updateAPIEnabledState];
    };
    info.shouldBeEnabled = ^BOOL{
        return [weakSelf boolForKey:kPreferenceKeyEnableAPIServer];
    };

    _advancedGPUWindowController = [[iTermAdvancedGPUSettingsWindowController alloc] initWithWindowNibName:@"iTermAdvancedGPUSettingsWindowController"];
    [_advancedGPUWindowController.window orderOut:nil];
    _advancedGPUWindowController.viewController.disableWhenDisconnected.target = self;
    _advancedGPUWindowController.viewController.disableWhenDisconnected.action = @selector(settingChanged:);
    info = [self defineUnsearchableControl:_advancedGPUWindowController.viewController.disableWhenDisconnected
                                       key:kPreferenceKeyDisableMetalWhenUnplugged
                                      type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermMetalSettingsDidChangeNotification object:nil];
    };

    _advancedGPUWindowController.viewController.disableInLowPowerMode.target = self;
    _advancedGPUWindowController.viewController.disableInLowPowerMode.action = @selector(settingChanged:);
    info = [self defineUnsearchableControl:_advancedGPUWindowController.viewController.disableInLowPowerMode
                                       key:kPreferenceKeyDisableInLowPowerMode
                                      type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermMetalSettingsDidChangeNotification object:nil];
    };

    _advancedGPUWindowController.viewController.preferIntegratedGPU.target = self;
    _advancedGPUWindowController.viewController.preferIntegratedGPU.action = @selector(settingChanged:);
    info = [self defineUnsearchableControl:_advancedGPUWindowController.viewController.preferIntegratedGPU
                                       key:kPreferenceKeyPreferIntegratedGPU
                                      type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermMetalSettingsDidChangeNotification object:nil];
    };
    info.onChange = ^{
        [iTermWarning showWarningWithTitle:@"You must restart iTerm2 for this change to take effect."
                                   actions:@[ @"OK" ]
                                identifier:nil
                               silenceable:kiTermWarningTypePersistent
                                    window:nil];
    };


    [self addViewToSearchIndex:_advancedGPUPrefsButton
                   displayName:@"Advanced GPU settings"
                       phrases:@[ _advancedGPUWindowController.viewController.disableWhenDisconnected.title,
                                  _advancedGPUWindowController.viewController.disableInLowPowerMode.title,
                                  _advancedGPUWindowController.viewController.preferIntegratedGPU.title ]
                           key:nil];

    info = [self defineControl:_maximizeThroughput
                           key:kPreferenceKeyMaximizeThroughput
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermMetalSettingsDidChangeNotification object:nil];
    };

    [self defineControl:_enableBonjour
                    key:kPreferenceKeyAddBonjourHostsToProfiles
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_notifyOnlyCriticalShellIntegrationUpdates
                    key:kPreferenceKeyNotifyOnlyForCriticalShellIntegrationUpdates
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_checkUpdate
                    key:kPreferenceKeyCheckForUpdatesAutomatically
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    if ([NSBundle it_isNightlyBuild]) {
        _checkTestRelease.enabled = NO;
    } else {
        _nightlyBuildNotice.hidden = YES;
    }
    [self defineControl:_checkTestRelease
                    key:kPreferenceKeyCheckForTestReleases
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    // ---------------------------------------------------------------------------------------------
    info = [self defineControl:_useCustomScriptsFolder
                           key:kPreferenceKeyUseCustomScriptsFolder
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() {
        [self useCustomScriptsFolderDidChange];
        [weakSelf customScriptsFolderDidChange];
        [weakSelf postCustomScriptsFolderDidChangeNotificationIfNeeded];
    };
    info.observer = ^() { [self updateCustomScriptsFolderViews]; };

    info = [self defineControl:_customScriptsFolder
                           key:kPreferenceKeyCustomScriptsFolder
                   displayName:@"Custom folder for Python API scripts"
                          type:kPreferenceInfoTypeStringTextField];
    info.shouldBeEnabled = ^BOOL() {
        return [iTermPreferences boolForKey:kPreferenceKeyUseCustomScriptsFolder];
    };
    info.onChange = ^() {
        [self updateCustomScriptsFolderViews];
        [weakSelf customScriptsFolderDidChange];
    };
    info.controlTextDidEndEditing = ^(NSNotification *notif) {
        // Post here instead of onChange since a patial path, like "/", would kick off a very slow
        // recursive search for scripts.
        [weakSelf postCustomScriptsFolderDidChangeNotificationIfNeeded];
    };
    [self updateCustomScriptsFolderViews];

    // ---------------------------------------------------------------------------------------------
    info = [self defineControl:_loadPrefsFromCustomFolder
                           key:kPreferenceKeyLoadPrefsFromCustomFolder
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^() { [self loadPrefsFromCustomFolderDidChangeByUI:YES]; };
    info.observer = ^() { [self updateRemotePrefsViews]; };

    info = [self defineControl:_saveChanges
                           key:kPreferenceKeyNeverRemindPrefsChangesLostForFileSelection
                   relatedView:_saveChangesLabel
                          type:kPreferenceInfoTypePopup];
    // Called when user interacts with control
    info.customSettingChangedHandler = ^(id sender) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [[iTermUserDefaults userDefaults] setBool:YES forKey:kPreferenceKeyNeverRemindPrefsChangesLostForFileHaveSelection];
        [[iTermUserDefaults userDefaults] setObject:@([strongSelf->_saveChanges selectedTag])
                                                  forKey:kPreferenceKeyNeverRemindPrefsChangesLostForFileSelection];
    };

    // Called on programmatic change (e.g., selecting a different profile. Returns YES to avoid
    // normal code path.
    info.onUpdate = ^BOOL () {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return NO;
        }
        NSUserDefaults *userDefaults = [iTermUserDefaults userDefaults];
        NSUInteger tag = iTermPreferenceSavePrefsModeNever;
        if ([userDefaults boolForKey:kPreferenceKeyNeverRemindPrefsChangesLostForFileHaveSelection]) {
            tag = [userDefaults integerForKey:kPreferenceKeyNeverRemindPrefsChangesLostForFileSelection];
        }
        [strongSelf->_saveChanges selectItemWithTag:tag];
        return YES;
    };
    info.onUpdate();

    // ---------------------------------------------------------------------------------------------
    info = [self defineUnsearchableControl:_prefsCustomFolder
                                       key:kPreferenceKeyCustomFolder
                                      type:kPreferenceInfoTypeStringTextField];
    info.shouldBeEnabled = ^BOOL() {
        return [iTermPreferences boolForKey:kPreferenceKeyLoadPrefsFromCustomFolder];
    };
    info.onChange = ^() {
        DLog(@"prefsCustomFolder did change");
        [iTermRemotePreferences sharedInstance].customFolderChanged = YES;
        [self updateRemotePrefsViews];
    };
    [self updateRemotePrefsViews];

    // ---------------------------------------------------------------------------------------------
    [self defineControl:_selectionCopiesText
                    key:kPreferenceKeySelectionCopiesText
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_copyLastNewline
                    key:kPreferenceKeyCopyLastNewline
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_allowClipboardAccessFromTerminal
                    key:kPreferenceKeyAllowClipboardAccessFromTerminal
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_wordMode
                            key:kPreferenceKeyCharactersConsideredPartOfAWordForSelectionMode
                    relatedView:nil
                           type:kPreferenceInfoTypePopup];
    info.observer = ^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        BOOL isRegexMode = ([strongSelf unsignedIntegerForKey:kPreferenceKeyCharactersConsideredPartOfAWordForSelectionMode] == iTermSelectionWordModeRegularExpression);
        // Show/hide the appropriate text field based on mode
        strongSelf->_wordChars.hidden = isRegexMode;
        strongSelf->_wordCharsRegex.hidden = !isRegexMode;
    };

    [self defineControl:_wordChars
                    key:kPreferenceKeyCharactersConsideredPartOfAWordForSelection
            relatedView:_wordCharsLabel
                   type:kPreferenceInfoTypeStringTextField];

    [self defineControl:_wordCharsRegex
                    key:kPreferenceKeyWordSelectionRegexPattern
            relatedView:_wordCharsLabel
                   type:kPreferenceInfoTypeStringTextField];

    // Set initial visibility based on current mode
    {
        BOOL isRegexMode = ([self unsignedIntegerForKey:kPreferenceKeyCharactersConsideredPartOfAWordForSelectionMode] == iTermSelectionWordModeRegularExpression);
        _wordChars.hidden = isRegexMode;
        _wordCharsRegex.hidden = !isRegexMode;
    }

    [self defineControl:_tripleClickSelectsFullLines
                    key:kPreferenceKeyTripleClickSelectsFullWrappedLines
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    info = [self defineControl:_doubleClickPerformsSmartSelection
                           key:kPreferenceKeyDoubleClickPerformsSmartSelection
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        BOOL enabled = ![strongSelf boolForKey:kPreferenceKeyDoubleClickPerformsSmartSelection];
        strongSelf->_wordChars.enabled = enabled;
        strongSelf->_wordCharsRegex.enabled = enabled;
        strongSelf->_wordCharsLabel.labelEnabled = enabled;
        strongSelf->_wordMode.enabled = enabled;
    };
    [self defineControl:_enterCopyModeAutomatically
                    key:kPreferenceKeyEnterCopyModeAutomatically
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_clickToSelectCommand
                    key:kPreferenceKeyClickToSelectCommand
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_wrapDroppedFilenamesInQuotesWhenPasting
                    key:kPreferenceKeyWrapDroppedFilenamesInQuotesWhenPasting
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_placementContainer
                           key:kPreferenceKeyWindowPlacement
                   displayName:@"New window placement"
                          type:kPreferenceInfoTypeRadioButton];

    [self defineControl:_adjustWindowForFontSizeChange
                    key:kPreferenceKeyAdjustWindowForFontSizeChange
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_maxVertically
                    key:kPreferenceKeyMaximizeVerticallyOnly
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_lionStyleFullscreen
                    key:kPreferenceKeyLionStyleFullscreen
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_separateWindowTitlePerTab
                    key:kPreferenceKeySeparateWindowTitlePerTab
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_openTmuxWindowsAsTabsInAttachingWindow
                           key:kPreferenceKeyOpenTmuxWindowsAsTabsInAttachingWindow
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.syntheticGetter = ^id{
        const iTermOpenTmuxWindowsMode mode = (iTermOpenTmuxWindowsMode)[iTermPreferences unsignedIntegerForKey:kPreferenceKeyOpenTmuxWindowsIn];
        return @(mode == kOpenTmuxWindowsAsNativeTabsInExistingWindow);
    };
    info.syntheticSetter = ^(id newValue) {
        __strong __typeof(self) strongSelf = weakSelf;
        if ([NSNumber castFrom:newValue].boolValue) {
            [iTermPreferences setUnsignedInteger:kOpenTmuxWindowsAsNativeTabsInExistingWindow
                                          forKey:kPreferenceKeyOpenTmuxWindowsIn];
        } else if (strongSelf) {
            [iTermPreferences setUnsignedInteger:strongSelf->_openUnrecognizedTmuxWindowsIn.selectedTag
                                          forKey:kPreferenceKeyOpenTmuxWindowsIn];
        }
    };
    info = [self defineControl:_openUnrecognizedTmuxWindowsIn
                           key:kPreferenceKeyOpenUnrecognizedTmuxWindowsIn
                   relatedView:_whenAttachingTmuxLabel
                          type:kPreferenceInfoTypePopup];
    info.syntheticGetter = ^id{
        const iTermOpenTmuxWindowsMode mode = (iTermOpenTmuxWindowsMode)[iTermPreferences unsignedIntegerForKey:kPreferenceKeyOpenTmuxWindowsIn];
        if (mode == kOpenTmuxWindowsAsNativeTabsInExistingWindow) {
            return @(kOpenTmuxWindowsAsNativeTabsInNewWindow);
        }
        return @(mode);
    };
    info.syntheticSetter = ^(id newValue) {
        [iTermPreferences setUnsignedInteger:[NSNumber castFrom:newValue].unsignedIntegerValue
                                      forKey:kPreferenceKeyOpenTmuxWindowsIn];
    };
    info.shouldBeEnabled = ^BOOL{
        const iTermOpenTmuxWindowsMode mode = (iTermOpenTmuxWindowsMode)[iTermPreferences unsignedIntegerForKey:kPreferenceKeyOpenTmuxWindowsIn];
        return (mode != kOpenTmuxWindowsAsNativeTabsInExistingWindow);
    };
    // Depend on the user defaults key, not the phony one, since it uses a User Defaults Observer to cause updates.
    [info addShouldBeEnabledDependencyOnSetting:kPreferenceKeyOpenTmuxWindowsIn
                                     controller:self];
    // This is how it was done before the great refactoring, but I don't see why it's needed.
    info.onChange = ^() { [weakSelf postRefreshNotification]; };
    [self updateEnabledStateForInfo:info];

    [self defineControl:_autoHideTmuxClientSession
                    key:kPreferenceKeyAutoHideTmuxClientSession
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_useTmuxProfile
                    key:kPreferenceKeyUseTmuxProfile
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_useTmuxStatusBar
                    key:kPreferenceKeyUseTmuxStatusBar
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_tmuxPauseModeAgeLimit
                    key:kPreferenceKeyTmuxPauseModeAgeLimit
            displayName:@"Pause a tmux pane if it would take more than this many seconds to catch up."
                   type:kPreferenceInfoTypeUnsignedIntegerTextField];
    [self defineControl:_unpauseTmuxAutomatically
                    key:kPreferenceKeyTmuxUnpauseAutomatically
            displayName:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_tmuxWarnBeforePausing
                    key:kPreferenceKeyTmuxWarnBeforePausing
            displayName:nil
                   type:kPreferenceInfoTypeCheckbox];
    [self defineControl:_syncTmuxClipboard
                    key:kPreferenceKeyTmuxSyncClipboard
            displayName:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_allowsSendingClipboardContents
                           key:kPreferenceKeyPhonyAllowSendingClipboardContents
                   relatedView:_allowsSendingClipboardContentsLabel
                          type:kPreferenceInfoTypePopup];
    info.syntheticGetter = ^id{
        return @([iTermPasteboardReporter configuration]);
    };
    info.syntheticSetter = ^(NSNumber *newValue) {
        [iTermPasteboardReporter setConfiguration:newValue.intValue];
    };
    PreferenceInfo *allowSendingClipboardInfo = info;

    /// -------

    [self addViewToSearchIndex:_openAIAPIKey
                   displayName:@"Manage AI API Keys"
                       phrases:@[ @"Set API key for AI",
                                   @"OpenAI Anthropic Gemini DeepSeek API keys" ]
                           key:kPreferenceKeyAIAPIKey];

    info = [self defineControl:_aiPrompt
                           key:kPreferenceKeyAIPromptPlaceholder
                   relatedView:_promptSelector
                          type:kPreferenceInfoTypeStringTextView];
    info.observer = ^{
        [weakSelf updateAIPromptWarning];
    };
    info.syntheticGetter = ^id{
        NSString *key = [weakSelf keyForCurrentlySelectedAIPrompt];
        return [iTermPreferences stringForKey:key];
    };
    info.syntheticSetter = ^(id newValue) {
        NSString *key = [weakSelf keyForCurrentlySelectedAIPrompt];
        [iTermPreferences setWithoutSideEffectsObject:newValue forKey:key];
    };

    [AIMetadata.instance enumerateModels:^(NSString * _Nonnull name, NSInteger context, NSString *url) {
        [_aiModel addItemWithObjectValue:name];
    }];

    PreferenceInfo *tokenLimitInfo =
        [self defineControl:_aiTokenLimit
                        key:kPreferenceKeyAITokenLimit
                relatedView:_aiTokenLimitLabel
                       type:kPreferenceInfoTypeIntegerTextField];
    _aiTokenLimitInfo = tokenLimitInfo;
    PreferenceInfo *responseTokenLimitInfo =
        [self defineControl:_aiResponseTokenLimit
                        key:kPreferenceKeyAIResponseTokenLimit
                relatedView:_aiTokenLimitLabel
                       type:kPreferenceInfoTypeIntegerTextField];
    _aiResponseTokenLimitInfo = responseTokenLimitInfo;
    PreferenceInfo *urlInfo = [self defineControl:_customAIEndpoint
                                              key:kPreferenceKeyAITermURL
                                      displayName:@"Custom URL for AI"
                                             type:kPreferenceInfoTypeStringTextField];
    _aiURLInfo = urlInfo;
    urlInfo.onUpdate = ^BOOL{
        [weakSelf updateEnabledState];
        return NO;
    };

    info = [self defineControl:_checkTerminalStateButton
                           key:kPreferenceKeyAIPermissionCheckTerminalState
                   relatedView:_checkTerminalStateLabel
                          type:kPreferenceInfoTypeUnsignedIntegerPopup];

    info = [self defineControl:_runCommandsButton
                           key:kPreferenceKeyAIPermissionRunCommands
                   relatedView:_runCommandsLabel
                          type:kPreferenceInfoTypeUnsignedIntegerPopup];

    info = [self defineControl:_viewHistoryButton
                           key:kPreferenceKeyAIPermissionViewHistory
                   relatedView:_viewHistoryLabel
                          type:kPreferenceInfoTypeUnsignedIntegerPopup];

    info = [self defineControl:_writeToClipboardButton
                           key:kPreferenceKeyAIPermissionWriteToClipboard
                   relatedView:_writeToClipboardLabel
                          type:kPreferenceInfoTypeUnsignedIntegerPopup];

    info = [self defineControl:_typeForYouButton
                           key:kPreferenceKeyAIPermissionTypeForYou
                   relatedView:_typeForYouLabel
                          type:kPreferenceInfoTypeUnsignedIntegerPopup];

    info = [self defineControl:_viewManpagesButton
                           key:kPreferenceKeyAIPermissionViewManpages
                   relatedView:_viewManpagesLabel
                          type:kPreferenceInfoTypeUnsignedIntegerPopup];

    info = [self defineControl:_writeToFilesystemButton
                           key:kPreferenceKeyAIPermissionWriteToFilesystem
                   relatedView:_writeToFilesystemLabel
                          type:kPreferenceInfoTypeUnsignedIntegerPopup];

    info = [self defineControl:_actInWebBrowserButton
                           key:kPreferenceKeyAIPermissionActInWebBrowser
                   relatedView:_actInWebBrowserLabel
                          type:kPreferenceInfoTypeUnsignedIntegerPopup];

    NSMutableArray<PreferenceInfo *> *aiFeatureInfos = [NSMutableArray array];
    info = [self defineControl:_aiFeatureHostedCodeInterpeter
                    key:kPreferenceKeyAIFeatureHostedCodeInterpreter
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [aiFeatureInfos addObject:info];
    info = [self defineControl:_aiFeatureHostedFileSearch
                    key:kPreferenceKeyAIFeatureHostedFileSearch
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [aiFeatureInfos addObject:info];
    info = [self defineControl:_aiFeatureHostedWebSearch
                    key:kPreferenceKeyAIFeatureHostedWebSearch
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [aiFeatureInfos addObject:info];
    info = [self defineControl:_aiFeatureFunctionCalling
                    key:kPreferenceKeyAIFeatureFunctionCalling
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [aiFeatureInfos addObject:info];
    info = [self defineControl:_aiFeatureStreamingResponses
                    key:kPreferenceKeyAIFeatureStreamingResponses
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
    [aiFeatureInfos addObject:info];
    info = [self defineControl:_vectorStore
                           key:kPreferenceKeyAIVectorStore
                   relatedView:nil
                          type:kPreferenceInfoTypePopup];
    [aiFeatureInfos addObject:info];

    PreferenceInfo *apiInfo = [self defineControl:_aiAPI
                           key:kPreferenceKeyAITermAPI
                   relatedView:nil
                          type:kPreferenceInfoTypePopup];
    _aiAPIInfo = apiInfo;
    apiInfo.shouldBeEnabled = ^BOOL{
        return [weakSelf canCustomizeAPI];
    };
    apiInfo.observer = ^{
        [weakSelf updateAIEnabled];
    };

    _lastModel = [self stringForKey:kPreferenceKeyAIModel];
    info = [self defineControl:_aiModel
                           key:kPreferenceKeyAIModel
                   relatedView:_aiModelLabel
                          type:kPreferenceInfoTypeStringTextField];
    _aiModelInfo = info;
    info.onChange = ^{
        [weakSelf aiModelDidChange:tokenLimitInfo
                 responseLimitInfo:responseTokenLimitInfo
                           urlInfo:urlInfo
                           apiInfo:apiInfo
                      featureInfos:aiFeatureInfos];
        [weakSelf updateAIEnabled];
    };

    _aiFeatureInfos = [aiFeatureInfos copy];
    [_observer observeKey:kPreferenceKeyUseRecommendedAIModel block:^{
        [weakSelf reloadDefaultAIModelPopup];
        [weakSelf updateCoarseAIModelSettingsEnabled];
    }];
    [_observer observeKey:kPreferenceKeyAIVendor block:^{
        [weakSelf reloadDefaultAIModelPopup];
    }];
    [_observer observeKey:kPreferenceKeyAIModel block:^{
        [weakSelf reloadDefaultAIModelPopup];
    }];
    [_observer observeKey:kPreferenceKeyAIManualModelConfigurations block:^{
        [weakSelf reloadDefaultAIModelPopup];
    }];
    [self addViewToSearchIndex:_aiPluginLabel
                   displayName:@"Install AI Plugin"
                       phrases:@[ @"AI Plugin" ]
                           key:kPhonyPreferenceKeyInstallAIPlugin];

    info = [self defineControl:_enableAI
                           key:kPreferenceKeyEnableAI
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.syntheticGetter = ^id{
        NSNumber *result = @(iTermSecureUserDefaults.instance.enableAI);
        DLog(@"enableAI=%@\n%@", result, [NSThread callStackSymbols]);
        return result;
    };
    info.syntheticSetter = ^(id newValue) {
        DLog(@"set enableAI<-%@\n%@", newValue, [NSThread callStackSymbols]);
        iTermSecureUserDefaults.instance.enableAI = [newValue boolValue];
        [weakSelf updateAIEnabled];
    };
    PreferenceInfo *enableAIInfo = info;


    info = [self defineControl:_aiCompletions
                           key:kPreferenceKeyAICompletion
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.syntheticGetter = ^id {
        return @(iTermSecureUserDefaults.instance.aiCompletionsEnabled);
    };
    info.syntheticSetter = ^(id newValue) {
        const BOOL setting = [newValue boolValue];
        if (setting == iTermSecureUserDefaults.instance.defaultValue_aiCompletionsEnabled) {
            [iTermSecureUserDefaults.instance resetAICompletionsEnabled];
        } else {
            iTermSecureUserDefaults.instance.aiCompletionsEnabled = [newValue boolValue];
        }
    };
    [self defineControl:_aiTimeout
                    key:kPreferenceKeyAITimeout
            displayName:@"AI timeout"
                   type:kPreferenceInfoTypeIntegerTextField];

    [self defineControl:_aiSafetyCheck
                    key:kPreferenceKeyAISafetyCheck
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_aiCustomHeadersEnabled
                           key:kPreferenceKeyAICustomHeadersEnabled
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^{
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf updateCustomHeadersControlsEnabled];
    };

    // ---------------------------------------------------------------------------------------------
    [self defineControl:_enableRTL
                    key:kPreferenceKeyBidi
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];
     [self defineControl:_sshIntegrationForURLs
                     key:kPreferenceKeySshIntegrationForURLs
             relatedView:nil
                    type:kPreferenceInfoTypeCheckbox];

    [self validatePlugin];
    [self updateEnabledState];
    [self commitControls];
    [self updateValueForInfo:allowSendingClipboardInfo];
    [self updateValueForInfo:enableAIInfo];
    [self updateAIEnabled];
}

- (NSString *)keyForCurrentlySelectedAIPrompt {
    switch ((iTermAIPrompt)_promptSelector.selectedTag) {
        case iTermAIPromptEngageAI:
            return kPreferenceKeyAIPrompt;
        case iTermAIPromptAIChat:
            return kPreferenceKeyAIPromptAIChat;
        case iTermAIPromptAIChatReadOnlyTerminal:
            return kPreferenceKeyAIPromptAIChatReadOnlyTerminal;
        case iTermAIPromptAIChatReadWriteTerminal:
            return kPreferenceKeyAIPromptAIChatReadWriteTerminal;
        case iTermAIPromptAIChatBrowser:
            return kPreferenceKeyAIPromptAIChatBrowser;
        case iTermAIPromptAIChatReadOnlyTerminalBrowser:
            return kPreferenceKeyAIPromptAIChatReadOnlyTerminalBrowser;
        case iTermAIPromptAIChatReadWriteTerminalBrowser:
            return kPreferenceKeyAIPromptAIChatReadWriteTerminalBrowser;
        case iTermAIPromptAIChatOrchestration:
            return kPreferenceKeyAIPromptAIChatOrchestration;
        case iTermAIPromptCodeReviewSystem:
            return kPreferenceKeyAIPromptCodeReviewSystem;
    }
}

- (BOOL)canCustomizeAPI {
    // Only allow customization for non-default settings.
    if ([self valueOfKeyEqualsDefaultValue:kPreferenceKeyAITermURL]) {
        return NO;
    }
    if ([[self stringForKey:kPreferenceKeyAITermURL] length] == 0) {
        return NO;
    }
    return YES;
}

- (NSArray<NSNumber *> *)defaultAIModelProviderVendors {
    return @[
        @(iTermAIVendorOpenAI),
        @(iTermAIVendorAnthropic),
        @(iTermAIVendorGemini),
        @(iTermAIVendorDeepSeek),
        @(iTermAIVendorLlama)
    ];
}

- (NSString *)defaultAIModelIdentifierForProvider:(iTermAIVendor)provider {
    return [NSString stringWithFormat:@"%@%lu",
            kAIDefaultModelProviderPrefix,
            (unsigned long)provider];
}

- (NSString *)defaultAIModelIdentifierForManualModelName:(NSString *)name {
    return [NSString stringWithFormat:@"%@%@", kAIDefaultModelManualPrefix, name ?: @""];
}

- (NSString *)manualModelNameFromDefaultAIModelIdentifier:(NSString *)identifier {
    if (![identifier hasPrefix:kAIDefaultModelManualPrefix]) {
        return nil;
    }
    return [identifier substringFromIndex:kAIDefaultModelManualPrefix.length];
}

- (NSNumber *)providerFromDefaultAIModelIdentifier:(NSString *)identifier {
    if (![identifier hasPrefix:kAIDefaultModelProviderPrefix]) {
        return nil;
    }
    NSString *raw = [identifier substringFromIndex:kAIDefaultModelProviderPrefix.length];
    return @((NSUInteger)raw.integerValue);
}

- (NSString *)currentDefaultManualModelName {
    if ([self boolForKey:kPreferenceKeyUseRecommendedAIModel]) {
        return nil;
    }
    return [self stringForKey:kPreferenceKeyAIModel];
}

- (NSDictionary *)manualAIModelConfigurationNamed:(NSString *)name
                                inConfigurations:(NSArray<NSDictionary *> *)configurations {
    if (name.length == 0) {
        return nil;
    }
    for (NSDictionary *configuration in configurations) {
        if ([configuration[kAIManualModelNameKey] isEqualToString:name]) {
            return configuration;
        }
    }
    return nil;
}

- (iTermAIVendor)providerForManualAIModelConfiguration:(NSDictionary *)configuration {
    const iTermAIAPI api = (iTermAIAPI)[self manualAIModelConfiguration:configuration
                                                          integerForKey:kAIManualModelAPIKey
                                                               fallback:iTermAIAPIChatCompletions];
    switch (api) {
        case iTermAIAPIAnthropic:
            return iTermAIVendorAnthropic;
        case iTermAIAPIGemini:
            return iTermAIVendorGemini;
        case iTermAIAPIDeepSeek:
            return iTermAIVendorDeepSeek;
        case iTermAIAPILlama:
            return iTermAIVendorLlama;
        case iTermAIAPIAppleIntelligence:
            return iTermAIVendorApple;
        case iTermAIAPIResponses:
        case iTermAIAPIChatCompletions:
        case iTermAIAPICompletions:
        case iTermAIAPIEarlyO1:
            break;
    }

    NSString *modelName = [configuration[kAIManualModelNameKey] lowercaseString] ?: @"";
    NSString *host = [iTermManualAIModelHost(configuration) lowercaseString] ?: @"";
    if ([modelName containsString:@"claude"] || [host containsString:@"anthropic"]) {
        return iTermAIVendorAnthropic;
    }
    if ([modelName containsString:@"gemini"] || [host containsString:@"google"]) {
        return iTermAIVendorGemini;
    }
    if ([modelName containsString:@"deepseek"] || [host containsString:@"deepseek"]) {
        return iTermAIVendorDeepSeek;
    }
    if ([modelName containsString:@"llama"] || [host containsString:@"localhost"]) {
        return iTermAIVendorLlama;
    }
    return iTermAIVendorOpenAI;
}

- (NSString *)defaultAIModelTitleForManualConfiguration:(NSDictionary *)configuration {
    NSString *name = configuration[kAIManualModelNameKey] ?: @"Untitled model";
    iTermAIVendor provider = [self providerForManualAIModelConfiguration:configuration];
    return [NSString stringWithFormat:@"Manual: %@ — %@",
            name,
            [self aiAPIKeyProviderNameForVendor:provider]];
}

- (NSTextField *)defaultAIModelSelectorLabel {
    for (NSView *subview in _aiVendor.superview.subviews) {
        if (![subview isKindOfClass:NSTextField.class]) {
            continue;
        }
        NSTextField *label = (NSTextField *)subview;
        if (![label.stringValue isEqualToString:@"AI Model:"]) {
            continue;
        }
        CGFloat delta = NSMidY(label.frame) - NSMidY(_aiVendor.frame);
        if (delta < 0) {
            delta = -delta;
        }
        if (delta < 16) {
            return label;
        }
    }
    return nil;
}

- (void)setupDefaultAIModelSelector {
    _useRecommendedModel.hidden = YES;
    _useRecommendedModel.enabled = NO;

    NSTextField *label = [self defaultAIModelSelectorLabel];
    if (label) {
        label.stringValue = @"Default model for new chats:";
        label.frame = NSMakeRect(9, NSMinY(label.frame), 210, NSHeight(label.frame));
    }

    NSRect popupFrame = _aiVendor.frame;
    popupFrame.origin.x = 224;
    popupFrame.size.width = 358;
    _aiVendor.frame = popupFrame;
    _aiVendor.target = self;
    _aiVendor.action = @selector(defaultAIModelPopupDidChange:);
    _aiVendor.toolTip = @"Default provider or manual model for new AI chats. Existing chats keep their provider.";

    [self addViewToSearchIndex:_aiVendor
                   displayName:@"Default model for new AI chats"
                       phrases:@[ @"AI default provider",
                                   @"AI manual model default" ]
                           key:kPreferenceKeyAIModel];
    [self reloadDefaultAIModelPopup];
}

- (void)selectPopUpButton:(NSPopUpButton *)button representedObject:(NSString *)representedObject {
    for (NSMenuItem *item in button.itemArray) {
        if ([item.representedObject isEqual:representedObject]) {
            [button selectItem:item];
            return;
        }
    }
}

- (void)reloadDefaultAIModelPopup {
    if (!_aiVendor) {
        return;
    }

    NSString *selectedIdentifier = nil;
    if ([self boolForKey:kPreferenceKeyUseRecommendedAIModel]) {
        selectedIdentifier =
            [self defaultAIModelIdentifierForProvider:(iTermAIVendor)[self unsignedIntegerForKey:kPreferenceKeyAIVendor]];
    } else {
        selectedIdentifier =
            [self defaultAIModelIdentifierForManualModelName:[self stringForKey:kPreferenceKeyAIModel]];
    }

    [_aiVendor removeAllItems];
    for (NSNumber *number in [self defaultAIModelProviderVendors]) {
        iTermAIVendor provider = (iTermAIVendor)number.unsignedIntegerValue;
        [_aiVendor addItemWithTitle:[self aiAPIKeyProviderNameForVendor:provider]];
        _aiVendor.lastItem.representedObject = [self defaultAIModelIdentifierForProvider:provider];
    }

    NSArray<NSDictionary *> *manualConfigurations = [self mutableManualAIModelConfigurations];
    if (manualConfigurations.count > 0) {
        [_aiVendor.menu addItem:[NSMenuItem separatorItem]];
        NSMenuItem *header = [[NSMenuItem alloc] initWithTitle:@"Manual Models"
                                                        action:nil
                                                 keyEquivalent:@""];
        header.enabled = NO;
        [_aiVendor.menu addItem:header];
        for (NSDictionary *configuration in manualConfigurations) {
            NSString *name = configuration[kAIManualModelNameKey] ?: @"";
            [_aiVendor addItemWithTitle:[self defaultAIModelTitleForManualConfiguration:configuration]];
            _aiVendor.lastItem.representedObject = [self defaultAIModelIdentifierForManualModelName:name];
        }
    }

    [self selectPopUpButton:_aiVendor representedObject:selectedIdentifier];
    if (_aiVendor.selectedItem == nil && _aiVendor.numberOfItems > 0) {
        [_aiVendor selectItemAtIndex:0];
    }
}

- (void)updateAIModelDependentControlValues {
    NSMutableArray<PreferenceInfo *> *infos = [NSMutableArray array];
    if (_aiModelInfo) {
        [infos addObject:_aiModelInfo];
    }
    if (_aiTokenLimitInfo) {
        [infos addObject:_aiTokenLimitInfo];
    }
    if (_aiResponseTokenLimitInfo) {
        [infos addObject:_aiResponseTokenLimitInfo];
    }
    if (_aiURLInfo) {
        [infos addObject:_aiURLInfo];
    }
    if (_aiAPIInfo) {
        [infos addObject:_aiAPIInfo];
    }
    for (PreferenceInfo *info in infos) {
        [self updateValueForInfo:info];
    }
    for (PreferenceInfo *info in _aiFeatureInfos) {
        [self updateValueForInfo:info];
    }
}

- (void)updateAIAfterDefaultModelChange {
    [self aiModelDidChange:_aiTokenLimitInfo
         responseLimitInfo:_aiResponseTokenLimitInfo
                   urlInfo:_aiURLInfo
                   apiInfo:_aiAPIInfo
              featureInfos:_aiFeatureInfos ?: @[]];
    [self updateAIModelDependentControlValues];
    [self reloadDefaultAIModelPopup];
    [self updateAIEnabled];
}

- (void)selectProviderAsDefaultForNewChats:(iTermAIVendor)provider {
    [self setBool:YES forKey:kPreferenceKeyUseRecommendedAIModel];
    [self setObject:@(provider) forKey:kPreferenceKeyAIVendor];
    [self updateAIModelFromVendor];
    [self updateAIAfterDefaultModelChange];
}

- (void)selectManualConfigurationAsDefaultForNewChats:(NSDictionary *)configuration {
    if (!configuration) {
        return;
    }
    [self setBool:NO forKey:kPreferenceKeyUseRecommendedAIModel];
    [self applyManualAIModelConfigurationToDefaults:configuration];
    [self updateAIAfterDefaultModelChange];
}

- (IBAction)defaultAIModelPopupDidChange:(id)sender {
    NSString *identifier = _aiVendor.selectedItem.representedObject;
    NSNumber *providerNumber = [self providerFromDefaultAIModelIdentifier:identifier];
    if (providerNumber) {
        [self selectProviderAsDefaultForNewChats:(iTermAIVendor)providerNumber.unsignedIntegerValue];
        return;
    }

    NSString *manualName = [self manualModelNameFromDefaultAIModelIdentifier:identifier];
    NSDictionary *configuration =
        [self manualAIModelConfigurationNamed:manualName
                            inConfigurations:[self mutableManualAIModelConfigurations]];
    if (configuration) {
        [self selectManualConfigurationAsDefaultForNewChats:configuration];
        return;
    }

    [self reloadDefaultAIModelPopup];
}

- (void)updateCoarseAIModelSettingsEnabled {
    const BOOL allowed = _pluginOK && [iTermAITermGatekeeper allowed];
    _manualAIConfiguration.enabled = allowed;
    _manualAIConfiguration.title = @"Manage Manual Models...";
    _aiVendor.enabled = allowed;
    [self reloadDefaultAIModelPopup];
}

- (void)updateAIModelFromVendor {
    iTermAIModel *model = [iTermAIModel modelFromSettings];
    if (model) {
        [self setString:model.name forKey:kPreferenceKeyAIModel];
    }
}

- (void)aiModelDidChange:(PreferenceInfo *)tokenLimitInfo
       responseLimitInfo:(PreferenceInfo *)responseLimitInfo
                 urlInfo:(PreferenceInfo *)urlInfo
                 apiInfo:(PreferenceInfo *)apiInfo
            featureInfos:(NSArray<PreferenceInfo *> *)featureInfos {
    NSString *model = [self stringForKey:kPreferenceKeyAIModel];
    // Ignore it if it doesn't change because this is called when the view is closed.
    if (!model || [model isEqualToString:_lastModel]) {
        return;
    }

    _lastModel = [self stringForKey:kPreferenceKeyAIModel];

    const iTermAIAPI api = [AIMetadata.instance apiForModel:model
                                                   fallback:[self unsignedIntegerForKey:kPreferenceKeyAITermAPI]];
    [self setObject:@(api) forKey:kPreferenceKeyAITermAPI];
    [self updateValueForInfo:apiInfo];

    NSNumber *tokens = [AIMetadata.instance contextWindowTokensForModelName:model];
    if (tokens) {
        [self setObject:tokens forKey:kPreferenceKeyAITokenLimit];
        [self updateValueForInfo:tokenLimitInfo];
    }
    NSNumber *responseTokens = [AIMetadata.instance responseTokenLimitForModelName:model];
    if (responseTokens) {
        [self setObject:responseTokens forKey:kPreferenceKeyAIResponseTokenLimit];
        [self updateValueForInfo:responseLimitInfo];
    }
    NSString *url = [AIMetadata.instance urlForModelName:model];
    if (url) {
        [self setObject:url forKey:kPreferenceKeyAITermURL];
        [self updateValueForInfo:urlInfo];
    }
    if ([AIMetadata.instance modelHasDefaults:model]) {
        [self setBool:[AIMetadata.instance modelSupportsHostedCodeInterpreter:model]
               forKey:kPreferenceKeyAIFeatureHostedCodeInterpreter];
        [self setBool:[AIMetadata.instance modelSupportsHostedFileSearch:model]
               forKey:kPreferenceKeyAIFeatureHostedFileSearch];
        [self setBool:[AIMetadata.instance modelSupportsHostedWebSearch:model]
               forKey:kPreferenceKeyAIFeatureHostedWebSearch];
        [self setBool:[AIMetadata.instance modelSupportsFunctionCalling:model]
               forKey:kPreferenceKeyAIFeatureFunctionCalling];
        [self setBool:[AIMetadata.instance modelSupportsStreamingResponses:model]
               forKey:kPreferenceKeyAIFeatureStreamingResponses];
        [self setInteger:[AIMetadata.instance vectorStoreForModel:model]
                  forKey:kPreferenceKeyAIVectorStore];
        for (PreferenceInfo *info in featureInfos) {
            [self updateValueForInfo:info];
        }
    }
}

- (void)validatePlugin {
    DLog(@"validatePlugin");
    _pluginStatus.stringValue = @"Checking plugin status…";
    __weak __typeof(self) weakSelf = self;
    [iTermAITermGatekeeper validatePlugin:^(NSString * _Nullable problem) {
        [weakSelf setPluginProblem:problem];
    }];
}

- (void)setPluginProblem:(NSString *)problem {
    DLog(@"problem=%@", problem);
    if (problem) {
        _pluginStatus.stringValue = problem;
        _installPluginButton.title = @"Install…";
        _installPluginButton.action = @selector(installPlugin:);
        [_installPluginButton sizeToFit];
        _installPluginButton.enabled = [iTermAdvancedSettingsModel generativeAIAllowed];
        _pluginOK = NO;
        __weak __typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf validatePlugin];
        });
    } else {
        _pluginStatus.stringValue = @"Plugin installed and working ✅";
        _installPluginButton.title = @"Reveal in Finder";
        [_installPluginButton sizeToFit];
        _installPluginButton.action = @selector(revealPlugin:);
        _installPluginButton.enabled = YES;
        _pluginOK = YES;
    }
    [self updateAIEnabled];
}

- (void)viewDidAppear {
    DLog(@"viewDidAppear");
    [self updateAIAPIKeysStatus];
}

- (NSArray<NSNumber *> *)aiAPIKeyProviderVendors {
    return @[
        @(iTermAIVendorOpenAI),
        @(iTermAIVendorAnthropic),
        @(iTermAIVendorGemini),
        @(iTermAIVendorDeepSeek)
    ];
}

- (NSString *)aiAPIKeyProviderNameForVendor:(iTermAIVendor)vendor {
    switch (vendor) {
        case iTermAIVendorOpenAI:
            return @"OpenAI";
        case iTermAIVendorAnthropic:
            return @"Anthropic";
        case iTermAIVendorGemini:
            return @"Gemini";
        case iTermAIVendorDeepSeek:
            return @"DeepSeek";
        case iTermAIVendorLlama:
            return @"Llama";
        case iTermAIVendorApple:
            return @"Apple Intelligence";
    }
}

- (BOOL)aiAPIKeyStringIsConfigured:(NSString *)string {
    return [[string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] length] > 0;
}

- (BOOL)aiAPIKeyIsConfiguredForVendor:(iTermAIVendor)vendor {
    return [self aiAPIKeyStringIsConfigured:[AITermControllerObjC apiKeyForVendor:vendor]];
}

- (void)setupAIAPIKeysRow {
    _openAIAPIKeyLabel.stringValue = @"API Keys:";
    _openAIAPIKey.title = @"Manage…";
    [_openAIAPIKey sizeToFit];

    if (!_aiAPIKeysStatus) {
        NSRect buttonFrame = _openAIAPIKey.frame;
        CGFloat x = NSMaxX(buttonFrame) + 8;
        _aiAPIKeysStatus =
            [NSTextField labelWithString:@""];
        _aiAPIKeysStatus.frame = NSMakeRect(x,
                                            NSMinY(buttonFrame),
                                            260,
                                            NSHeight(buttonFrame));
        _aiAPIKeysStatus.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
        _aiAPIKeysStatus.textColor = NSColor.secondaryLabelColor;
        _aiAPIKeysStatus.lineBreakMode = NSLineBreakByTruncatingTail;
        _aiAPIKeysStatus.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
        [_openAIAPIKey.superview addSubview:_aiAPIKeysStatus];
    }

    [self updateAIAPIKeysStatus];
}

- (void)updateAIAPIKeysStatus {
    NSArray<NSNumber *> *vendors = [self aiAPIKeyProviderVendors];
    NSMutableArray<NSString *> *configured = [NSMutableArray array];
    for (NSNumber *number in vendors) {
        iTermAIVendor vendor = (iTermAIVendor)number.unsignedIntegerValue;
        if ([self aiAPIKeyIsConfiguredForVendor:vendor]) {
            [configured addObject:[self aiAPIKeyProviderNameForVendor:vendor]];
        }
    }

    switch (configured.count) {
        case 0:
            _aiAPIKeysStatus.stringValue = @"No provider keys configured";
            break;
        case 1:
            _aiAPIKeysStatus.stringValue =
                [NSString stringWithFormat:@"%@ configured", configured[0]];
            break;
        case 2:
            _aiAPIKeysStatus.stringValue =
                [NSString stringWithFormat:@"%@ configured",
                 [configured componentsJoinedByString:@", "]];
            break;
        default:
            _aiAPIKeysStatus.stringValue =
                [NSString stringWithFormat:@"%lu of %lu configured",
                 (unsigned long)configured.count,
                 (unsigned long)vendors.count];
            break;
    }
}

- (void)updateAIAPIKeySheetStatusAtIndex:(NSInteger)index {
    if (index < 0 || index >= _aiAPIKeySheetFields.count ||
        index >= _aiAPIKeySheetStatusLabels.count) {
        return;
    }
    NSSecureTextField *field = _aiAPIKeySheetFields[index];
    NSTextField *status = _aiAPIKeySheetStatusLabels[index];
    if (![self aiAPIKeyStringIsConfigured:field.stringValue]) {
        status.stringValue = @"Not Set";
        status.textColor = NSColor.tertiaryLabelColor;
        return;
    }
    NSArray<NSNumber *> *vendors = [self aiAPIKeyProviderVendors];
    if (index >= vendors.count) {
        status.stringValue = @"Set";
        status.textColor = NSColor.secondaryLabelColor;
        return;
    }
    iTermAIVendor vendor = (iTermAIVendor)vendors[index].unsignedIntegerValue;
    const BOOL matches = [AITermControllerObjC apiKey:field.stringValue matchesVendor:vendor];
    status.stringValue = matches ? @"Set" : @"Invalid";
    status.textColor = matches ? NSColor.secondaryLabelColor : NSColor.systemRedColor;
}

- (IBAction)clearAIAPIKeyField:(id)sender {
    NSInteger index = [sender tag];
    if (index < 0 || index >= _aiAPIKeySheetFields.count) {
        return;
    }
    _aiAPIKeySheetFields[index].stringValue = @"";
    [self updateAIAPIKeySheetStatusAtIndex:index];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    id object = notification.object;
    NSInteger index = [_aiAPIKeySheetFields indexOfObject:object];
    if (index != NSNotFound) {
        [self updateAIAPIKeySheetStatusAtIndex:index];
    }
}

- (void)updateAIEnabled {
    _enableAI.enabled = _pluginOK;

    const BOOL allowed = _pluginOK && [iTermAITermGatekeeper allowed];
    _openAIAPIKey.enabled = allowed;
    _aiAPIKeysStatus.enabled = allowed;
    _aiPrompt.editable = allowed;
    _aiModel.enabled = allowed;
    _aiTokenLimit.enabled = allowed;
    _resetAIPrompt.enabled = allowed;
    _customAIEndpoint.enabled = allowed;
    _enableAI.enabled = [iTermAdvancedSettingsModel generativeAIAllowed];
    _aiResponseTokenLimit.enabled = allowed;
    _aiModelLabel.enabled = allowed;
    _aiTokenLimitLabel.enabled = allowed;
    _aiAPI.enabled = allowed;
    _aiFeatureHostedCodeInterpeter.enabled = allowed;
    _aiFeatureHostedFileSearch.enabled = allowed;
    _aiFeatureHostedWebSearch.enabled = allowed;
    _aiFeatureFunctionCalling.enabled = allowed;
    _aiFeatureStreamingResponses.enabled = allowed;
    _aiSafetyCheck.enabled = allowed;
    _vectorStore.enabled = allowed;

    [self updateCoarseAIModelSettingsEnabled];
}

- (BOOL)modelSupportsModernAPI {
    NSURL *url = [NSURL URLWithString:[self stringForKey:kPreferenceKeyAITermURL]];
    return [iTermLLMMetadata hostIsOpenAIAPIForURL:url];
}

- (void)customScriptsFolderDidChange {
    _customScriptsFolderDidChange = YES;
}

- (void)postCustomScriptsFolderDidChangeNotificationIfNeeded {
    if (_customScriptsFolderDidChange) {
        _customScriptsFolderDidChange = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermScriptsFolderDidChange object:nil];
    }
}

- (void)windowWillClose {
    [self postCustomScriptsFolderDidChangeNotificationIfNeeded];
}

- (void)willDeselectTab {
    [self postCustomScriptsFolderDidChangeNotificationIfNeeded];
}

- (void)updateAIPromptWarning {
    if ([[self keyForCurrentlySelectedAIPrompt] isEqualToString:kPreferenceKeyAIPrompt]) {
        if ([[self stringForKey:kPreferenceKeyAIPrompt] containsString:@"\\(ai.prompt)"]) {
            _aiPromptWarning.alphaValue = 0.0;
        } else {
            _aiPromptWarning.alphaValue = 1.0;
        }
    } else {
        _aiPromptWarning.alphaValue = 0.0;
    }
}

- (NSString *)alwaysOpenLegend {
    if ([iTermScriptsMenuController autoLaunchFolderExists]) {
        return @"The presence of auto-launch scripts disables opening a window at startup.";
    }
    if ([[[iTermHotKeyController sharedInstance] profileHotKeys] count] > 0) {
        return @"The existence of hotkey windows disables opening a window at startup.";
    }
    if ([[[iTermBuriedSessions sharedInstance] buriedSessions] count] > 0) {
        return @"The existence of buried sessions disables opening a window at startup.";
    }
    return nil;
}

- (void)updateAlwaysOpenLegend {
    NSString *legend = [self alwaysOpenLegend];
    if (!legend) {
        _alwaysOpenLegend.hidden = YES;
        return;
    }
    _alwaysOpenLegend.stringValue = legend;
    _alwaysOpenLegend.hidden = NO;
}

- (void)updateAPIEnabledState {
    _enableAPI.state = [self boolForKey:kPreferenceKeyEnableAPIServer];
    [_apiPermission selectItemWithTag:[iTermAPIHelper requireApplescriptAuth] ? 0 : 1];
    [self updateEnabledState];
}

- (BOOL)shouldEnableAlwaysOpenWindowAtStartup {
    if ([self boolForKey:kPreferenceKeyOpenArrangementAtStartup]) {
        return NO;
    }
    if ([self boolForKey:kPreferenceKeyOpenNoWindowsAtStartup]) {
        return NO;
    }
    return YES;
}

- (void)updateEnabledState {
    [super updateEnabledState];
    [_apiPermission selectItemWithTag:[iTermAPIHelper requireApplescriptAuth] ? 0 : 1];
    _evenIfThereAreNoWindows.enabled = [self boolForKey:kPreferenceKeyPromptOnQuit];
    const BOOL useSystemWindowRestoration = (![self boolForKey:kPreferenceKeyOpenArrangementAtStartup] &&
                                             ![self boolForKey:kPreferenceKeyOpenNoWindowsAtStartup]);
    const BOOL systemRestorationEnabled = [[iTermUserDefaults userDefaults] boolForKey:@"NSQuitAlwaysKeepsWindows"];
    _warningButton.hidden = (!useSystemWindowRestoration || systemRestorationEnabled);
    _alwaysOpenWindowAtStartup.enabled = [self shouldEnableAlwaysOpenWindowAtStartup];
    _restoreWindowsToSameSpaces.enabled = systemRestorationEnabled && useSystemWindowRestoration;
}

- (void)updateAdvancedGPUEnabled {
    _advancedGPU.enabled = [self boolForKey:kPreferenceKeyUseMetal];
}

- (BOOL)enableAPISettingDidChange {
    const BOOL result = [self reallyEnableAPISettingDidChange];
    [self updateEnabledState];
    return result;
}

- (BOOL)reallyEnableAPISettingDidChange {
    const BOOL enabled = _enableAPI.state == NSControlStateValueOn;
    if (enabled) {
        // Prompt the user. If they agree, or have permanently agreed, set the user default to YES.
        if ([iTermAPIHelper confirmShouldStartServerAndUpdateUserDefaultsForced:YES]) {
            [iTermAPIHelper sharedInstance];
        } else {
            return NO;
            
        }
    } else {
        [iTermAPIHelper setEnabled:NO];
    }
    if (enabled && ![iTermAPIHelper isEnabled]) {
        _enableAPI.state = NSControlStateValueOff;
        return NO;
    }
    return YES;
}

#pragma mark - Actions

- (IBAction)selectedPromptDidChange:(id)sender {
    NSString *string = [self stringForKey:kPreferenceKeyAIPromptPlaceholder];
    [_aiPrompt.textStorage setAttributedString:[NSAttributedString attributedStringWithString:string
                                                                                   attributes:_aiPrompt.typingAttributes]];
    [self updateAIPromptWarning];
}

- (IBAction)changeAPIKey:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Manage AI API Keys";
    alert.informativeText = @"Keys are stored securely in the macOS Keychain.";
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];

    NSArray<NSNumber *> *vendors = [self aiAPIKeyProviderVendors];
    const CGFloat width = 620;
    const CGFloat rowHeight = 36;
    const CGFloat topPadding = 10;
    const CGFloat bottomPadding = 10;
    NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0,
                                                                0,
                                                                width,
                                                                topPadding + bottomPadding +
                                                                rowHeight * vendors.count)];
    _aiAPIKeySheetFields = [NSMutableArray array];
    _aiAPIKeySheetStatusLabels = [NSMutableArray array];

    for (NSInteger i = 0; i < vendors.count; i++) {
        iTermAIVendor vendor = (iTermAIVendor)vendors[i].unsignedIntegerValue;
        NSString *name = [self aiAPIKeyProviderNameForVendor:vendor];
        CGFloat y = bottomPadding + rowHeight * (vendors.count - 1 - i);

        NSTextField *label = [NSTextField labelWithString:name];
        label.frame = NSMakeRect(0, y + 5, 90, 22);
        label.alignment = NSTextAlignmentRight;
        [accessory addSubview:label];

        NSSecureTextField *field =
            [[NSSecureTextField alloc] initWithFrame:NSMakeRect(104, y + 2, 350, 24)];
        field.usesSingleLineMode = YES;
        field.editable = YES;
        field.selectable = YES;
        field.delegate = self;
        field.placeholderString = [NSString stringWithFormat:@"%@ API key", name];
        field.stringValue = [AITermControllerObjC apiKeyForVendor:vendor] ?: @"";
        [accessory addSubview:field];
        [_aiAPIKeySheetFields addObject:field];

        NSTextField *status = [NSTextField labelWithString:@""];
        status.frame = NSMakeRect(466, y + 5, 58, 22);
        status.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
        [accessory addSubview:status];
        [_aiAPIKeySheetStatusLabels addObject:status];

        NSButton *clear = [NSButton buttonWithTitle:@"Clear"
                                             target:self
                                             action:@selector(clearAIAPIKeyField:)];
        clear.frame = NSMakeRect(536, y, 68, 28);
        clear.tag = i;
        clear.bezelStyle = NSBezelStyleRounded;
        [accessory addSubview:clear];

        [self updateAIAPIKeySheetStatusAtIndex:i];
    }

    alert.accessoryView = accessory;
    [alert layout];
    if (_aiAPIKeySheetFields.count > 0) {
        [[alert window] makeFirstResponder:_aiAPIKeySheetFields[0]];
    }

    [NSApp activateIgnoringOtherApps:YES];
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        switch (returnCode) {
            case NSAlertFirstButtonReturn: {
                for (NSInteger i = 0; i < vendors.count && i < self->_aiAPIKeySheetFields.count; i++) {
                    iTermAIVendor vendor = (iTermAIVendor)vendors[i].unsignedIntegerValue;
                    [AITermControllerObjC setAPIKey:self->_aiAPIKeySheetFields[i].stringValue
                                          forVendor:vendor];
                }
                [self updateAIAPIKeysStatus];
                break;
            }
            case NSAlertSecondButtonReturn: {
                break;
            }
        }
        self->_aiAPIKeySheetFields = nil;
        self->_aiAPIKeySheetStatusLabels = nil;
    }];
}

#pragma mark - Custom Headers

// Loads the persisted headers into _customHeaders and sets initial UI state.
// All view layout (labels, segmented control, table view, columns, scroll
// view) lives in the XIB; the controls are connected via the IBOutlets above
// and the table view's dataSource/delegate are set in the XIB to this
// controller.
- (void)setupCustomHeadersSection {
    id saved = [iTermPreferences objectForKey:kPreferenceKeyAICustomHeaders];
    _customHeaders = [NSMutableArray array];
    if ([saved isKindOfClass:[NSArray class]]) {
        for (id entry in (NSArray *)saved) {
            if ([entry isKindOfClass:[NSDictionary class]]) {
                [_customHeaders addObject:[entry mutableCopy]];
            }
        }
    }
    [_aiCustomHeadersTableView reloadData];
    [self updateCustomHeadersControlsEnabled];
}

- (BOOL)customHeadersEnabled {
    return [iTermPreferences boolForKey:kPreferenceKeyAICustomHeadersEnabled];
}

- (void)updateCustomHeadersControlsEnabled {
    const BOOL enabled = [self customHeadersEnabled];
    _aiCustomHeadersAddRemove.enabled = enabled;
    _aiCustomHeadersTableView.enabled = enabled;
    if (!enabled) {
        [_aiCustomHeadersTableView deselectAll:nil];
    }
    [_aiCustomHeadersTableView reloadData];  // refresh cell editability
    [self updateCustomHeadersRemoveEnabled];
}

- (void)updateCustomHeadersRemoveEnabled {
    const BOOL hasSelection = (_aiCustomHeadersTableView.selectedRow >= 0);
    const BOOL canRemove = hasSelection && [self customHeadersEnabled];
    [_aiCustomHeadersAddRemove setEnabled:canRemove forSegment:1];
}

- (void)saveCustomHeaders {
    // Skip rows with empty names so the persisted plist doesn't accumulate
    // blanks from rows the user added but never named.
    NSMutableArray *toSave = [NSMutableArray array];
    for (NSDictionary *entry in _customHeaders) {
        NSString *name = entry[@"name"];
        if ([name isKindOfClass:[NSString class]] && name.length > 0) {
            [toSave addObject:[entry copy]];
        }
    }
    [iTermPreferences setObject:toSave forKey:kPreferenceKeyAICustomHeaders];
}

- (IBAction)customHeadersAddRemove:(id)sender {
    NSSegmentedControl *control = (NSSegmentedControl *)sender;
    switch (control.selectedSegment) {
        case 0:
            [self addCustomHeader];
            break;
        case 1:
            [self removeCustomHeader];
            break;
    }
}

- (void)addCustomHeader {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Add Custom Header";
    alert.informativeText = @"Enter a header name and value. The name is required.";
    [alert addButtonWithTitle:@"Add"];
    [alert addButtonWithTitle:@"Cancel"];

    const CGFloat width = 280.0;
    const CGFloat fieldHeight = 22.0;
    const CGFloat labelHeight = 17.0;
    const CGFloat gap = 4.0;
    const CGFloat sectionGap = 10.0;
    const CGFloat totalHeight = labelHeight + gap + fieldHeight + sectionGap + labelHeight + gap + fieldHeight;

    NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, totalHeight)];

    CGFloat y = totalHeight;

    y -= labelHeight;
    NSTextField *nameLabel = [NSTextField labelWithString:@"Name:"];
    nameLabel.frame = NSMakeRect(0, y, width, labelHeight);
    [accessory addSubview:nameLabel];

    y -= gap + fieldHeight;
    NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, y, width, fieldHeight)];
    [accessory addSubview:nameField];

    y -= sectionGap + labelHeight;
    NSTextField *valueLabel = [NSTextField labelWithString:@"Value:"];
    valueLabel.frame = NSMakeRect(0, y, width, labelHeight);
    [accessory addSubview:valueLabel];

    y -= gap + fieldHeight;
    NSTextField *valueField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, y, width, fieldHeight)];
    [accessory addSubview:valueField];

    alert.accessoryView = accessory;

    NSTextField *focusField = nameField;
    while (YES) {
        [alert.window setInitialFirstResponder:focusField];
        const NSModalResponse response = [alert runModal];
        if (response != NSAlertFirstButtonReturn) {
            return;
        }
        NSString *name = [nameField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *value = valueField.stringValue ?: @"";
        if (![AICustomHeaders isValidName:name]) {
            alert.informativeText = @"The header name must be non-empty and contain only RFC 7230 token characters (letters, digits, and any of !#$%&'*+-.^_`|~).";
            focusField = nameField;
            continue;
        }
        if (![AICustomHeaders isValidValue:value]) {
            alert.informativeText = @"The header value must not contain newline or null characters.";
            focusField = valueField;
            continue;
        }
        [_customHeaders addObject:[@{@"name": name, @"value": value} mutableCopy]];
        [self saveCustomHeaders];
        [_aiCustomHeadersTableView reloadData];
        NSInteger newRow = (NSInteger)_customHeaders.count - 1;
        [_aiCustomHeadersTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)newRow]
                               byExtendingSelection:NO];
        [_aiCustomHeadersTableView scrollRowToVisible:newRow];
        return;
    }
}

- (void)removeCustomHeader {
    NSInteger row = _aiCustomHeadersTableView.selectedRow;
    if (row < 0 || row >= (NSInteger)_customHeaders.count) {
        return;
    }
    [_customHeaders removeObjectAtIndex:(NSUInteger)row];
    [self saveCustomHeaders];
    [_aiCustomHeadersTableView deselectAll:nil];
    [_aiCustomHeadersTableView reloadData];
    [self updateCustomHeadersRemoveEnabled];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView != _aiCustomHeadersTableView) {
        return 0;
    }
    return (NSInteger)_customHeaders.count;
}

#pragma mark - NSTableViewDelegate

// View-based table view. The XIB defines an NSTableCellView prototype per
// column whose identifier matches the column identifier (“name” or “value”),
// containing an editable NSTextField wired to the cell view’s textField
// outlet. The text field’s delegate is forced to this controller here so
// edits always route through -controlTextDidEndEditing:.
- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    if (tableView != _aiCustomHeadersTableView) {
        return nil;
    }
    NSTableCellView *cell = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    NSMutableDictionary *entry = _customHeaders[(NSUInteger)row];
    const BOOL enabled = [self customHeadersEnabled];
    cell.textField.stringValue = entry[tableColumn.identifier] ?: @"";
    cell.textField.editable = enabled;
    cell.textField.selectable = enabled;
    cell.textField.enabled = enabled;
    cell.textField.delegate = self;
    return cell;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    if (tableView == _aiCustomHeadersTableView && ![self customHeadersEnabled]) {
        return NO;
    }
    return YES;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (notification.object == _aiCustomHeadersTableView) {
        [self updateCustomHeadersRemoveEnabled];
    }
}

- (void)competentTableViewDeleteSelectedRows:(CompetentTableView *)sender {
    if (sender != _aiCustomHeadersTableView || ![self customHeadersEnabled]) {
        return;
    }
    [self removeCustomHeader];
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    NSTextField *field = (NSTextField *)notification.object;
    if (![field isKindOfClass:[NSTextField class]]) {
        [super controlTextDidEndEditing:notification];
        return;
    }
    const NSInteger row = [_aiCustomHeadersTableView rowForView:field];
    const NSInteger column = [_aiCustomHeadersTableView columnForView:field];
    if (row < 0 || column < 0) {
        // Not one of our custom-header cells; let the base class handle
        // info.controlTextDidEndEditing blocks and integer/double field
        // canonicalization.
        [super controlTextDidEndEditing:notification];
        return;
    }
    if (row >= (NSInteger)_customHeaders.count ||
        column >= (NSInteger)_aiCustomHeadersTableView.tableColumns.count) {
        return;
    }
    NSTableColumn *tableColumn = _aiCustomHeadersTableView.tableColumns[(NSUInteger)column];
    NSMutableDictionary *entry = _customHeaders[(NSUInteger)row];
    NSString *newValue = field.stringValue;
    NSString *failure = nil;
    if ([tableColumn.identifier isEqualToString:@"name"]) {
        newValue = [newValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (![AICustomHeaders isValidName:newValue]) {
            failure = @"The header name must be non-empty and contain only RFC 7230 token characters (letters, digits, and any of !#$%&'*+-.^_`|~).";
        }
    } else if ([tableColumn.identifier isEqualToString:@"value"]) {
        if (![AICustomHeaders isValidValue:newValue]) {
            failure = @"The header value must not contain newline or null characters.";
        }
    }
    if (failure) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Invalid HTTP header";
        alert.informativeText = failure;
        [alert runModal];
        // Put the user back into the same cell so they can fix the value
        // without retyping it from scratch.
        dispatch_async(dispatch_get_main_queue(), ^{
            if (row < (NSInteger)self->_customHeaders.count &&
                column < (NSInteger)self->_aiCustomHeadersTableView.tableColumns.count) {
                [self->_aiCustomHeadersTableView editColumn:column
                                                        row:row
                                                  withEvent:nil
                                                     select:YES];
            }
        });
        return;
    }
    entry[tableColumn.identifier] = newValue;
    [self saveCustomHeaders];
}

- (BOOL)manualAIModelConfiguration:(NSDictionary *)configuration boolForKey:(NSString *)key {
    id value = configuration[key];
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue];
    }
    return NO;
}

- (NSInteger)manualAIModelConfiguration:(NSDictionary *)configuration
                          integerForKey:(NSString *)key
                               fallback:(NSInteger)fallback {
    id value = configuration[key];
    if ([value respondsToSelector:@selector(integerValue)]) {
        return [value integerValue];
    }
    return fallback;
}

- (NSDictionary *)legacyManualAIModelConfiguration {
    NSString *url = [self stringForKey:kPreferenceKeyAITermURL];
    if (url.length == 0) {
        return nil;
    }
    return @{
        kAIManualModelIDKey: NSUUID.UUID.UUIDString,
        kAIManualModelNameKey: [self stringForKey:kPreferenceKeyAIModel] ?: @"gpt-4o-mini",
        kAIManualModelURLKey: url,
        kAIManualModelAPIKey: @([self unsignedIntegerForKey:kPreferenceKeyAITermAPI]),
        kAIManualModelContextWindowTokensKey: @([self integerForKey:kPreferenceKeyAITokenLimit]),
        kAIManualModelMaxResponseTokensKey: @([self integerForKey:kPreferenceKeyAIResponseTokenLimit]),
        kAIManualModelHostedCodeInterpreterKey: @([self boolForKey:kPreferenceKeyAIFeatureHostedCodeInterpreter]),
        kAIManualModelHostedFileSearchKey: @([self boolForKey:kPreferenceKeyAIFeatureHostedFileSearch]),
        kAIManualModelHostedWebSearchKey: @([self boolForKey:kPreferenceKeyAIFeatureHostedWebSearch]),
        kAIManualModelFunctionCallingKey: @([self boolForKey:kPreferenceKeyAIFeatureFunctionCalling]),
        kAIManualModelStreamingKey: @([self boolForKey:kPreferenceKeyAIFeatureStreamingResponses]),
        kAIManualModelVectorStoreKey: @([self integerForKey:kPreferenceKeyAIVectorStore])
    };
}

- (NSDictionary *)defaultManualAIModelConfiguration {
    const NSInteger savedContextTokens = [self integerForKey:kPreferenceKeyAITokenLimit];
    const NSInteger savedResponseTokens = [self integerForKey:kPreferenceKeyAIResponseTokenLimit];
    const NSInteger contextTokens = savedContextTokens > 0 ? savedContextTokens : 8192;
    const NSInteger responseTokens = savedResponseTokens > 0 ? savedResponseTokens : 8192;
    return @{
        kAIManualModelIDKey: NSUUID.UUID.UUIDString,
        kAIManualModelNameKey: [self stringForKey:kPreferenceKeyAIModel] ?: @"gpt-4o-mini",
        kAIManualModelURLKey: [self stringForKey:kPreferenceKeyAITermURL] ?: @"",
        kAIManualModelAPIKey: @([self unsignedIntegerForKey:kPreferenceKeyAITermAPI]),
        kAIManualModelContextWindowTokensKey: @(contextTokens),
        kAIManualModelMaxResponseTokensKey: @(responseTokens),
        kAIManualModelHostedCodeInterpreterKey: @([self boolForKey:kPreferenceKeyAIFeatureHostedCodeInterpreter]),
        kAIManualModelHostedFileSearchKey: @([self boolForKey:kPreferenceKeyAIFeatureHostedFileSearch]),
        kAIManualModelHostedWebSearchKey: @([self boolForKey:kPreferenceKeyAIFeatureHostedWebSearch]),
        kAIManualModelFunctionCallingKey: @([self boolForKey:kPreferenceKeyAIFeatureFunctionCalling]),
        kAIManualModelStreamingKey: @([self boolForKey:kPreferenceKeyAIFeatureStreamingResponses]),
        kAIManualModelVectorStoreKey: @([self integerForKey:kPreferenceKeyAIVectorStore])
    };
}

- (NSMutableArray<NSMutableDictionary *> *)mutableManualAIModelConfigurations {
    NSMutableArray<NSMutableDictionary *> *result = [NSMutableArray array];
    id raw = [iTermPreferences objectForKey:kPreferenceKeyAIManualModelConfigurations];
    if ([raw isKindOfClass:NSArray.class]) {
        for (id entry in (NSArray *)raw) {
            if ([entry isKindOfClass:NSDictionary.class]) {
                [result addObject:[entry mutableCopy]];
            }
        }
    }
    if (result.count == 0 && ![self boolForKey:kPreferenceKeyUseRecommendedAIModel]) {
        NSDictionary *legacy = [self legacyManualAIModelConfiguration];
        if (legacy) {
            [result addObject:[legacy mutableCopy]];
        }
    }
    return result;
}

- (void)saveManualAIModelConfigurations:(NSArray<NSDictionary *> *)configurations {
    NSMutableArray<NSDictionary *> *clean = [NSMutableArray array];
    for (NSDictionary *configuration in configurations) {
        NSString *name = configuration[kAIManualModelNameKey];
        NSString *url = configuration[kAIManualModelURLKey];
        if (![name isKindOfClass:NSString.class] || name.length == 0 ||
            ![url isKindOfClass:NSString.class] || url.length == 0) {
            continue;
        }
        [clean addObject:[configuration copy]];
    }
    [iTermPreferences setObject:clean forKey:kPreferenceKeyAIManualModelConfigurations];
}

- (void)clearLegacyManualAIModelConfiguration {
    [self setString:@"gpt-4o-mini" forKey:kPreferenceKeyAIModel];
    [self setString:@"" forKey:kPreferenceKeyAITermURL];
}

- (void)applyManualAIModelConfigurationToDefaults:(NSDictionary *)configuration {
    if (!configuration) {
        [self clearLegacyManualAIModelConfiguration];
        return;
    }
    [self setString:configuration[kAIManualModelNameKey] ?: @"gpt-4o-mini"
             forKey:kPreferenceKeyAIModel];
    [self setString:configuration[kAIManualModelURLKey] ?: @""
             forKey:kPreferenceKeyAITermURL];
    [self setObject:@([self manualAIModelConfiguration:configuration
                                         integerForKey:kAIManualModelAPIKey
                                              fallback:iTermAIAPIChatCompletions])
             forKey:kPreferenceKeyAITermAPI];
    [self setInteger:[self manualAIModelConfiguration:configuration
                                       integerForKey:kAIManualModelContextWindowTokensKey
                                            fallback:8192]
              forKey:kPreferenceKeyAITokenLimit];
    [self setInteger:[self manualAIModelConfiguration:configuration
                                       integerForKey:kAIManualModelMaxResponseTokensKey
                                            fallback:8192]
              forKey:kPreferenceKeyAIResponseTokenLimit];
    [self setBool:[self manualAIModelConfiguration:configuration boolForKey:kAIManualModelHostedCodeInterpreterKey]
           forKey:kPreferenceKeyAIFeatureHostedCodeInterpreter];
    [self setBool:[self manualAIModelConfiguration:configuration boolForKey:kAIManualModelHostedFileSearchKey]
           forKey:kPreferenceKeyAIFeatureHostedFileSearch];
    [self setBool:[self manualAIModelConfiguration:configuration boolForKey:kAIManualModelHostedWebSearchKey]
           forKey:kPreferenceKeyAIFeatureHostedWebSearch];
    [self setBool:[self manualAIModelConfiguration:configuration boolForKey:kAIManualModelFunctionCallingKey]
           forKey:kPreferenceKeyAIFeatureFunctionCalling];
    [self setBool:[self manualAIModelConfiguration:configuration boolForKey:kAIManualModelStreamingKey]
           forKey:kPreferenceKeyAIFeatureStreamingResponses];
    [self setInteger:[self manualAIModelConfiguration:configuration
                                       integerForKey:kAIManualModelVectorStoreKey
                                            fallback:0]
              forKey:kPreferenceKeyAIVectorStore];
    _lastModel = configuration[kAIManualModelNameKey];
}

- (NSString *)titleForAIAPI:(iTermAIAPI)api {
    return iTermTitleForAIAPI(api);
}

- (NSString *)manualAIModelTitle:(NSDictionary *)configuration {
    NSString *name = configuration[kAIManualModelNameKey] ?: @"Untitled model";
    NSString *url = configuration[kAIManualModelURLKey] ?: @"";
    iTermAIAPI api = (iTermAIAPI)[self manualAIModelConfiguration:configuration
                                                   integerForKey:kAIManualModelAPIKey
                                                        fallback:iTermAIAPIChatCompletions];
    if (url.length == 0) {
        return [NSString stringWithFormat:@"%@ — %@", name, [self titleForAIAPI:api]];
    }
    NSURL *parsedURL = [NSURL URLWithString:url];
    NSString *host = parsedURL.host ?: url;
    return [NSString stringWithFormat:@"%@ — %@ — %@", name, [self titleForAIAPI:api], host];
}

- (NSDictionary *)runManualAIModelEditorWithConfiguration:(NSDictionary *)configuration
                                    existingConfigurations:(NSArray<NSDictionary *> *)existingConfigurations
                                             editingIndex:(NSInteger)editingIndex {
    NSDictionary *base = configuration ?: [self defaultManualAIModelConfiguration];
    while (YES) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = configuration ? @"Edit Manual AI Model" : @"Add Manual AI Model";
        alert.informativeText = @"Manual models can be selected as the default for new chats and under Manual Configs in AI Chat.";
        [alert addButtonWithTitle:configuration ? @"Save" : @"Add"];
        [alert addButtonWithTitle:@"Cancel"];

        const CGFloat width = 520;
        const CGFloat labelWidth = 150;
        const CGFloat fieldX = labelWidth + 12;
        const CGFloat fieldWidth = width - fieldX;
        const CGFloat rowHeight = 30;
        __block CGFloat y = 374;
        NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, y + 4)];

        void (^addLabel)(NSString *) = ^(NSString *title) {
            NSTextField *label = [NSTextField labelWithString:title];
            label.alignment = NSTextAlignmentRight;
            label.frame = NSMakeRect(0, y + 3, labelWidth, 20);
            [accessory addSubview:label];
        };
        NSTextField *(^addTextField)(NSString *, NSString *) = ^NSTextField *(NSString *title, NSString *value) {
            addLabel(title);
            NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(fieldX, y, fieldWidth, 24)];
            field.stringValue = value ?: @"";
            [accessory addSubview:field];
            y -= rowHeight;
            return field;
        };

        NSTextField *nameField = addTextField(@"Model:", base[kAIManualModelNameKey]);
        NSTextField *urlField = addTextField(@"URL:", base[kAIManualModelURLKey]);

        addLabel(@"API:");
        NSPopUpButton *apiPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(fieldX, y, fieldWidth, 24)];
        NSArray<NSNumber *> *apis = @[
            @(iTermAIAPIResponses),
            @(iTermAIAPIChatCompletions),
            @(iTermAIAPIAnthropic),
            @(iTermAIAPIGemini),
            @(iTermAIAPIDeepSeek),
            @(iTermAIAPILlama),
            @(iTermAIAPICompletions),
            @(iTermAIAPIEarlyO1)
        ];
        for (NSNumber *number in apis) {
            iTermAIAPI api = (iTermAIAPI)number.unsignedIntegerValue;
            [apiPopup addItemWithTitle:[self titleForAIAPI:api]];
            apiPopup.lastItem.tag = (NSInteger)api;
        }
        [apiPopup selectItemWithTag:[self manualAIModelConfiguration:base
                                                       integerForKey:kAIManualModelAPIKey
                                                            fallback:iTermAIAPIChatCompletions]];
        [accessory addSubview:apiPopup];
        y -= rowHeight;

        NSTextField *contextField =
            addTextField(@"Context tokens:",
                         [NSString stringWithFormat:@"%ld",
                          [self manualAIModelConfiguration:base
                                             integerForKey:kAIManualModelContextWindowTokensKey
                                                  fallback:8192]]);
        NSTextField *responseField =
            addTextField(@"Max response tokens:",
                         [NSString stringWithFormat:@"%ld",
                          [self manualAIModelConfiguration:base
                                             integerForKey:kAIManualModelMaxResponseTokensKey
                                                  fallback:8192]]);

        addLabel(@"Vector store:");
        NSPopUpButton *vectorStore = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(fieldX, y, fieldWidth, 24)];
        [vectorStore addItemWithTitle:@"Disabled"];
        vectorStore.lastItem.tag = 0;
        [vectorStore addItemWithTitle:@"OpenAI"];
        vectorStore.lastItem.tag = 1;
        [vectorStore selectItemWithTag:[self manualAIModelConfiguration:base
                                                           integerForKey:kAIManualModelVectorStoreKey
                                                                fallback:0]];
        [accessory addSubview:vectorStore];
        y -= rowHeight + 8;

        NSArray<NSDictionary *> *features = @[
            @{ @"title": @"Function calling", @"key": kAIManualModelFunctionCallingKey },
            @{ @"title": @"Streaming responses", @"key": kAIManualModelStreamingKey },
            @{ @"title": @"Hosted web search", @"key": kAIManualModelHostedWebSearchKey },
            @{ @"title": @"Hosted file search", @"key": kAIManualModelHostedFileSearchKey },
            @{ @"title": @"Hosted code interpreter", @"key": kAIManualModelHostedCodeInterpreterKey }
        ];
        NSMutableDictionary<NSString *, NSButton *> *featureButtons = [NSMutableDictionary dictionary];
        for (NSDictionary *feature in features) {
            NSString *key = feature[@"key"];
            NSButton *button = [NSButton checkboxWithTitle:feature[@"title"]
                                                    target:nil
                                                    action:nil];
            button.frame = NSMakeRect(fieldX, y, fieldWidth, 22);
            button.state = [self manualAIModelConfiguration:base boolForKey:key] ? NSControlStateValueOn : NSControlStateValueOff;
            [accessory addSubview:button];
            featureButtons[key] = button;
            y -= 26;
        }

        alert.accessoryView = accessory;
        [alert.window setInitialFirstResponder:nameField];
        if ([alert runModal] != NSAlertFirstButtonReturn) {
            return nil;
        }

        NSString *name =
            [nameField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *url =
            [urlField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *failure = nil;
        if (name.length == 0) {
            failure = @"Model is required.";
        } else if (url.length == 0) {
            failure = @"URL is required.";
        } else if (contextField.integerValue <= 0) {
            failure = @"Context tokens must be greater than zero.";
        } else if (responseField.integerValue <= 0) {
            failure = @"Max response tokens must be greater than zero.";
        } else {
            for (NSInteger i = 0; i < (NSInteger)existingConfigurations.count; i++) {
                if (i == editingIndex) {
                    continue;
                }
                NSString *otherName = existingConfigurations[(NSUInteger)i][kAIManualModelNameKey];
                if ([otherName isEqualToString:name]) {
                    failure = @"Manual model names must be unique.";
                    break;
                }
            }
        }
        if (failure) {
            NSAlert *failureAlert = [[NSAlert alloc] init];
            failureAlert.messageText = @"Invalid Manual AI Model";
            failureAlert.informativeText = failure;
            [failureAlert runModal];
            continue;
        }

        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[kAIManualModelIDKey] = base[kAIManualModelIDKey] ?: NSUUID.UUID.UUIDString;
        result[kAIManualModelNameKey] = name;
        result[kAIManualModelURLKey] = url;
        result[kAIManualModelAPIKey] = @(apiPopup.selectedItem.tag);
        result[kAIManualModelContextWindowTokensKey] = @(contextField.integerValue);
        result[kAIManualModelMaxResponseTokensKey] = @(responseField.integerValue);
        result[kAIManualModelVectorStoreKey] = @(vectorStore.selectedItem.tag);
        for (NSString *key in featureButtons) {
            result[key] = @(featureButtons[key].state == NSControlStateValueOn);
        }
        return result;
    }
}

- (void)saveManualAIModelConfigurationsAndRefresh:(NSArray<NSDictionary *> *)configurations {
    [self saveManualAIModelConfigurations:configurations];
    [self reloadDefaultAIModelPopup];
    [self updateAIEnabled];
}

- (void)fallbackAfterDeletingDefaultManualModel:(NSArray<NSDictionary *> *)configurations
                                  selectedIndex:(NSInteger)selectedIndex {
    if (selectedIndex >= 0 && selectedIndex < (NSInteger)configurations.count) {
        [self selectManualConfigurationAsDefaultForNewChats:configurations[(NSUInteger)selectedIndex]];
        return;
    }
    [self selectProviderAsDefaultForNewChats:(iTermAIVendor)[self unsignedIntegerForKey:kPreferenceKeyAIVendor]];
}

- (IBAction)showManualAIConfigurationPanel:(NSButton *)button {
    NSMutableArray<NSMutableDictionary *> *configurations = [self mutableManualAIModelConfigurations];
    NSInteger selectedIndex = 0;

    while (YES) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Manage Manual AI Models";
        alert.informativeText = @"These models appear in the default model selector and under Manual Configs in AI Chat.";
        [alert addButtonWithTitle:@"Done"];

        iTermManualAIModelsPanelController *panel =
            [[iTermManualAIModelsPanelController alloc] initWithConfigurations:configurations
                                                              defaultModelName:[self currentDefaultManualModelName]
                                                                 selectedIndex:selectedIndex];
        alert.accessoryView = [panel view];
        if (panel.tableView) {
            alert.window.initialFirstResponder = panel.tableView;
        }
        NSModalResponse response = [alert runModal];
        selectedIndex = panel.selectedIndex;
        if (response != NSAlertFirstButtonReturn) {
            [alert.window orderOut:nil];
        }
        if (response == NSAlertFirstButtonReturn) {
            return;
        }

        if (response == iTermManualAIModelManagerResponseAdd) {
            NSDictionary *newConfiguration =
                [self runManualAIModelEditorWithConfiguration:nil
                                       existingConfigurations:configurations
                                                editingIndex:-1];
            if (newConfiguration) {
                [configurations addObject:[newConfiguration mutableCopy]];
                selectedIndex = (NSInteger)configurations.count - 1;
                [self saveManualAIModelConfigurationsAndRefresh:configurations];
            }
        } else if (response == iTermManualAIModelManagerResponseEdit) {
            if (selectedIndex < 0 || selectedIndex >= (NSInteger)configurations.count) {
                NSBeep();
                continue;
            }
            NSString *oldName = configurations[(NSUInteger)selectedIndex][kAIManualModelNameKey];
            const BOOL editingDefault = [oldName isEqualToString:[self currentDefaultManualModelName]];
            NSDictionary *edited =
                [self runManualAIModelEditorWithConfiguration:configurations[(NSUInteger)selectedIndex]
                                       existingConfigurations:configurations
                                                editingIndex:selectedIndex];
            if (edited) {
                configurations[(NSUInteger)selectedIndex] = [edited mutableCopy];
                [self saveManualAIModelConfigurations:configurations];
                if (editingDefault) {
                    [self selectManualConfigurationAsDefaultForNewChats:edited];
                } else {
                    [self reloadDefaultAIModelPopup];
                    [self updateAIEnabled];
                }
            }
        } else if (response == iTermManualAIModelManagerResponseDuplicate) {
            if (selectedIndex < 0 || selectedIndex >= (NSInteger)configurations.count) {
                NSBeep();
                continue;
            }
            NSMutableDictionary *copy = [configurations[(NSUInteger)selectedIndex] mutableCopy];
            copy[kAIManualModelIDKey] = NSUUID.UUID.UUIDString;
            copy[kAIManualModelNameKey] =
                [NSString stringWithFormat:@"%@ copy", copy[kAIManualModelNameKey] ?: @"Manual model"];
            NSDictionary *edited =
                [self runManualAIModelEditorWithConfiguration:copy
                                       existingConfigurations:configurations
                                                editingIndex:-1];
            if (edited) {
                [configurations addObject:[edited mutableCopy]];
                selectedIndex = (NSInteger)configurations.count - 1;
                [self saveManualAIModelConfigurationsAndRefresh:configurations];
            }
        } else if (response == iTermManualAIModelManagerResponseDelete) {
            if (selectedIndex < 0 || selectedIndex >= (NSInteger)configurations.count) {
                NSBeep();
                continue;
            }
            NSString *deletedName = configurations[(NSUInteger)selectedIndex][kAIManualModelNameKey];
            const BOOL deletingDefault = [deletedName isEqualToString:[self currentDefaultManualModelName]];
            [configurations removeObjectAtIndex:(NSUInteger)selectedIndex];
            selectedIndex = MIN(selectedIndex, (NSInteger)configurations.count - 1);
            [self saveManualAIModelConfigurations:configurations];
            if (deletingDefault) {
                [self fallbackAfterDeletingDefaultManualModel:configurations
                                                selectedIndex:selectedIndex];
            } else {
                [self reloadDefaultAIModelPopup];
                [self updateAIEnabled];
            }
        } else if (response == iTermManualAIModelManagerResponseDefault) {
            if (selectedIndex < 0 || selectedIndex >= (NSInteger)configurations.count) {
                NSBeep();
                continue;
            }
            [self saveManualAIModelConfigurations:configurations];
            [self selectManualConfigurationAsDefaultForNewChats:configurations[(NSUInteger)selectedIndex]];
        }
    }
}

- (IBAction)closeManualAIConfigurationSheet:(id)sender {
    if (_manualAIConfigurationSheet == nil) {
        return;
    }
    [self.view.window endSheet:_manualAIConfigurationSheet returnCode:NSModalResponseOK];
}

- (IBAction)reloadPlugin:(id)sender {
    __weak __typeof(self) weakSelf = self;
    [iTermAITermGatekeeper reloadPlugin:^(void) {
        [weakSelf validatePlugin];
    }];
}

- (IBAction)installPlugin:(id)sender {
    [[NSWorkspace sharedWorkspace] it_openURL:[NSURL URLWithString:@"https://iterm2.com/ai-plugin.html"]
                                       target:nil
                                configuration:[NSWorkspaceOpenConfiguration configuration]
                                        style:iTermOpenStyleTab
                                       upsell:NO
                                       window:self.view.window];
}

- (void)revealPlugin:(id)sender {
    NSURL *url = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:@"com.googlecode.iterm2.iTermAI"];
    if (!url) {
        NSBeep();
        return;
    }
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[url]];
}

- (IBAction)exportAllSettingsAndData:(id)sender {
    [self showMessage:[iTerm2ImportExport exportAll] title:@"Problem Exporting"];
}

- (IBAction)importAllSettingsAndData:(id)sender {
    [self showMessage:[iTerm2ImportExport importAll] title:@"Problem Importing"];
}

- (IBAction)eraseAllSettingsAndData:(id)sender {
    [self showMessage:[iTerm2ImportExport eraseAllWithWindow:self.view.window]
                title:@"Problem Erasing Settings and Data"];
}

- (void)showMessage:(NSString *)message title:(NSString *)title {
    if (!message) {
        return;
    }
    [iTermWarning showWarningWithTitle:message
                               actions:@[ @"OK" ]
                             accessory:nil
                            identifier:nil
                           silenceable:kiTermWarningTypePersistent
                               heading:title
                                window:self.view.window];
}

- (IBAction)warning:(id)sender {
    NSString *message;
    NSString *action;
    NSString *path;
    if (@available(macOS 13, *)) {
        message = @"System window restoration has been disabled, which prevents iTerm2 from respecting this setting. Disable ”System Settings > Desktop & Dock > Close windows when quitting an application“ to enable window restoration.";
        action = @"Open System Settings";
        path = @"/System/Library/PreferencePanes/Dock.prefPane";
    } else {
        message = @"System window restoration has been disabled, which prevents iTerm2 from respecting this setting. Disable System Settings > General > Close windows when quitting an app to enable window restoration.";
        action = @"Open System Preferences";
        path = @"/System/Library/PreferencePanes/Appearance.prefPane";
    }
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:message
                               actions:@[ action, @"OK" ]
                             accessory:nil
                            identifier:@"NoSyncWindowRestorationDisabled"
                           silenceable:kiTermWarningTypePersistent
                               heading:@"Window Restoration Disabled"
                                window:self.view.window];
    if (selection == kiTermWarningSelection0) {
        [[NSWorkspace sharedWorkspace] it_openURL:[NSURL fileURLWithPath:path]
                                           target:nil
                                            style:iTermOpenStyleTab
                                           window:self.view.window];
    }
}


- (IBAction)browseCustomFolder:(id)sender {
    [self choosePrefsCustomFolder];
}

- (IBAction)browseScriptsFolder:(id)sender {
    [self chooseCustomScriptsFolder];
}

- (IBAction)pushToCustomFolder:(id)sender {
    [[iTermRemotePreferences sharedInstance] saveLocalUserDefaultsToRemotePrefs];
}

- (IBAction)advancedGPU:(NSView *)sender {
    [self.view.window beginSheet:_advancedGPUWindowController.window completionHandler:^(NSModalResponse returnCode) {
    }];
}

- (IBAction)pythonAPIAuthHelp:(id)sender {
    [[NSWorkspace sharedWorkspace] it_openURL:[NSURL URLWithString:@"https://iterm2.com/python-api-auth.html"]
                                       target:nil
                                        style:iTermOpenStyleTab
                                       window:self.view.window];
}

- (IBAction)resetAIPrompt:(id)sender {
    NSString *key = [self keyForCurrentlySelectedAIPrompt];
    NSString *defaultValue = [iTermPreferences defaultObjectForKey:key] ?: @"";
    [self setString:defaultValue forKey:key];
    [_aiPrompt.textStorage setAttributedString:[NSAttributedString attributedStringWithString:defaultValue
                                                                                   attributes:_aiPrompt.typingAttributes]];
    [self updateAIPromptWarning];
}

- (IBAction)aiPromptHelp:(id)sender {
    NSString *text =
        [NSString stringWithContentsOfFile:[[NSBundle bundleForClass:[self class]] pathForResource:@"ai-prompt-help"
                                                                                            ofType:@"md"]
                                  encoding:NSUTF8StringEncoding
                                     error:nil];

    [(NSView *)sender it_showInformativeMessageWithMarkdown:text];
}

#pragma mark - Notifications

- (void)savedArrangementChanged:(id)sender {
    PreferenceInfo *info = [self infoForControl:_openWindowsAtStartup];
    [self updateValueForInfo:info];
    [_openDefaultWindowArrangementItem setEnabled:[WindowArrangements count] > 0];
}

// The API helper just noticed that the file's contents changed.
- (void)didRevertPythonAuthenticationMethod:(NSNotification *)notification {
    [self updateAPIEnabledState];
}

- (void)preferenceDidChangeFromOtherPanel:(NSNotification *)notification {
    [self updateAlwaysOpenLegend];
    [super preferenceDidChangeFromOtherPanel:notification];
}


#pragma mark - Remote Prefs

- (void)updateCustomScriptsFolderViews {
    BOOL haveCustomFolder = [iTermPreferences boolForKey:kPreferenceKeyUseCustomScriptsFolder];
    _browseCustomScriptsFolder.enabled = haveCustomFolder;
    _customScriptsFolder.enabled = haveCustomFolder;
    if (haveCustomFolder) {
        _customScriptsFolderWarning.alphaValue = 1;
    } else {
        if (_customScriptsFolder.stringValue.length > 0) {
            _customScriptsFolderWarning.alphaValue = 0.5;
        } else {
            _customScriptsFolderWarning.alphaValue = 0;
        }
    }
    const BOOL locationIsValid = [[NSFileManager defaultManager] customScriptsFolderIsValid:_customScriptsFolder.stringValue];
    _customScriptsFolderWarning.image = locationIsValid ? [NSImage it_imageNamed:@"CheckMark" forClass:self.class] : [NSImage it_imageNamed:@"WarningSign" forClass:self.class];
}

- (void)updateRemotePrefsViews {
    BOOL shouldLoadRemotePrefs =
        [iTermPreferences boolForKey:kPreferenceKeyLoadPrefsFromCustomFolder];
    [_browseCustomFolder setEnabled:shouldLoadRemotePrefs];
    [_prefsCustomFolder setEnabled:shouldLoadRemotePrefs];

    if (shouldLoadRemotePrefs) {
        _prefsDirWarning.alphaValue = 1;
    } else {
        if (_prefsCustomFolder.stringValue.length > 0) {
            _prefsDirWarning.alphaValue = 0.5;
        } else {
            _prefsDirWarning.alphaValue = 0;
        }
    }

    BOOL remoteLocationIsValid = [[iTermRemotePreferences sharedInstance] remoteLocationIsValid];
    _prefsDirWarning.image = remoteLocationIsValid ? [NSImage it_imageNamed:@"CheckMark" forClass:self.class] : [NSImage it_imageNamed:@"WarningSign" forClass:self.class];
    BOOL isValidFile = (shouldLoadRemotePrefs &&
                        remoteLocationIsValid &&
                        ![[iTermRemotePreferences sharedInstance] remoteLocationIsURL]);
    [_saveChanges setEnabled:isValidFile];
    [_saveChangesLabel setLabelEnabled:isValidFile];
    [_pushToCustomFolder setEnabled:isValidFile];
}

- (void)useCustomScriptsFolderDidChange {
    const BOOL newValue = [iTermPreferences boolForKey:kPreferenceKeyUseCustomScriptsFolder];
    [self updateCustomScriptsFolderViews];
    if (newValue) {
        // Just turned it on
        if ([[_customScriptsFolder stringValue] length] == 0) {
            // Filed was initially empty so browse for a dir.
            if ([self chooseCustomScriptsFolder]) {
                [[NSNotificationCenter defaultCenter] postNotificationName:iTermScriptsFolderDidChange object:nil];
            }
        }
    }
    [self updateCustomScriptsFolderViews];
}

- (void)loadPrefsFromCustomFolderDidChangeByUI:(BOOL)byUI {
    BOOL shouldLoadRemotePrefs = [iTermPreferences boolForKey:kPreferenceKeyLoadPrefsFromCustomFolder];
    [self updateRemotePrefsViews];
    if (shouldLoadRemotePrefs && byUI) {
        // Just turned it on.
#if DEBUG
        const BOOL gitlab = [iTermPreferences gitlabURLOnPasteboard] != nil;
#else
        const BOOL gitlab = NO;
#endif
        if ([[_prefsCustomFolder stringValue] length] == 0 && !gitlab) {
            // Field was initially empty so browse for a dir.
            if ([self choosePrefsCustomFolder]) {
                // User didn't hit cancel; if he chose a writable directory, ask if he wants to write to it.
                if ([[iTermRemotePreferences sharedInstance] remoteLocationIsValid]) {
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = @"Copy local settings to custom folder now?";
                    [alert addButtonWithTitle:@"Copy"];
                    [alert addButtonWithTitle:@"Don’t Copy"];
                    if ([alert runModal] == NSAlertFirstButtonReturn) {
                        [[iTermRemotePreferences sharedInstance] saveLocalUserDefaultsToRemotePrefs];
                    }
                }
            }
        }
    }
    if (!byUI && (_loadPrefsFromCustomFolder.state == NSControlStateValueOn) != shouldLoadRemotePrefs) {
        _loadPrefsFromCustomFolder.state = shouldLoadRemotePrefs ? NSControlStateValueOn : NSControlStateValueOff;
    }
    [self updateRemotePrefsViews];
}

- (BOOL)chooseCustomScriptsFolder {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];

    if ([panel runModal] == NSModalResponseOK && panel.directoryURL.path) {
        [_customScriptsFolder setStringValue:panel.directoryURL.path];
        [self settingChanged:_customScriptsFolder];
        return YES;
    }  else {
        return NO;
    }
}

- (BOOL)choosePrefsCustomFolder {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];

    if ([panel runModal] == NSModalResponseOK && panel.directoryURL.path) {
        [_prefsCustomFolder setStringValue:panel.directoryURL.path];
        [self settingChanged:_prefsCustomFolder];
        return YES;
    }  else {
        return NO;
    }
}

- (NSTabView *)tabView {
    return _tabView;
}

- (CGFloat)minimumWidth {
    return 598;
}

@end
