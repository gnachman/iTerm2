//
//  GeneralPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import "GeneralPreferencesViewController.h"
#import "SFSymbolEnum/SFSymbolEnum.h"
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

@interface GeneralPreferencesViewController () <NSTextFieldDelegate>
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
static NSString *const kAIManualModelSupportsTemperatureKey = @"supportsTemperature";
static NSString *const kAIManualModelConfigurableThinkingKey = @"configurableThinking";
// Array of {"name","value"} dictionaries. Must match LLMMetadata.ManualModelKey.customHeaders.
static NSString *const kAIManualModelCustomHeadersKey = @"customHeaders";

static NSString *const kAIManualModelsDefaultColumn = @"default";
static NSString *const kAIManualModelsModelColumn = @"model";
static NSString *const kAIManualModelsAPIColumn = @"api";
static NSString *const kAIManualModelsEndpointColumn = @"endpoint";
static NSString *const kAIDefaultModelProviderPrefix = @"provider:";
static NSString *const kAIDefaultModelManualPrefix = @"manual:";

// Preset-popup tag scheme for the manual model editor: Custom is -1, catalog
// model presets use their index (0..n-1), and provider presets (OpenAI-compatible
// gateways) use their index plus this base so the two lists never collide.
static const NSInteger kAIProviderPresetTagBase = 100000;

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

static BOOL iTermManualAIModelBoolValue(NSDictionary *configuration, NSString *key) {
    id value = configuration[key];
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
}

static NSString *iTermTitleForAIAPI(iTermAIAPI api) {
    switch (api) {
        case iTermAIAPIResponses:
            return NSLocalizedStringWithDefaultValue(@"AIAPI.Responses", nil, [NSBundle mainBundle], @"Responses", @"Name of the Responses AI API");
        case iTermAIAPIChatCompletions:
            return NSLocalizedStringWithDefaultValue(@"AIAPI.ChatCompletions", nil, [NSBundle mainBundle], @"Chat Completions", @"Name of the Chat Completions AI API");
        case iTermAIAPICompletions:
            return NSLocalizedStringWithDefaultValue(@"AIAPI.Completions", nil, [NSBundle mainBundle], @"Completions", @"Name of the Completions AI API");
        case iTermAIAPIGemini:
            return NSLocalizedStringWithDefaultValue(@"AIAPI.GoogleGemini", nil, [NSBundle mainBundle], @"Google Gemini", @"Name of the Google Gemini AI API");
        case iTermAIAPIEarlyO1:
            return NSLocalizedStringWithDefaultValue(@"AIAPI.ChatCompletionsEarlyO1", nil, [NSBundle mainBundle], @"Chat Completions (Early O1)", @"Name of the early-O1 Chat Completions AI API");
        case iTermAIAPILlama:
            return NSLocalizedStringWithDefaultValue(@"AIProvider.Llama", nil, [NSBundle mainBundle], @"Llama", @"Llama provider name");
        case iTermAIAPIDeepSeek:
            return NSLocalizedStringWithDefaultValue(@"AIProvider.DeepSeek", nil, [NSBundle mainBundle], @"DeepSeek", @"DeepSeek provider name");
        case iTermAIAPIAnthropic:
            return NSLocalizedStringWithDefaultValue(@"AIProvider.Anthropic", nil, [NSBundle mainBundle], @"Anthropic", @"Anthropic provider name");
        case iTermAIAPIAppleIntelligence:
            return NSLocalizedStringWithDefaultValue(@"AIProvider.AppleIntelligence", nil, [NSBundle mainBundle], @"Apple Intelligence", @"Apple Intelligence provider name");
    }
    // An out-of-range api (e.g. api: 999 from hand-edited or synced prefs) would
    // otherwise fall off the end of this non-void function (UB). No default: in
    // the switch so -Wswitch still flags a genuinely new enum value. Mirror
    // LLMMetadata's tolerance of a bad api (iTermAIAPI(rawValue:) ?? .chatCompletions).
    return NSLocalizedStringWithDefaultValue(@"AIAPI.ChatCompletions", nil, [NSBundle mainBundle], @"Chat Completions", @"Name of the Chat Completions AI API");
}

// Human-readable provider name for the vendor whose stored key authorizes a
// model. Used both by the API Keys section and by the manual AI settings key
// hint so the two never disagree.
static NSString *iTermAIVendorProviderName(iTermAIVendor vendor) {
    switch (vendor) {
        case iTermAIVendorOpenAI:
            return NSLocalizedStringWithDefaultValue(@"AIProvider.OpenAI", nil, [NSBundle mainBundle], @"OpenAI", @"OpenAI provider name");
        case iTermAIVendorAnthropic:
            return NSLocalizedStringWithDefaultValue(@"AIProvider.Anthropic", nil, [NSBundle mainBundle], @"Anthropic", @"Anthropic provider name");
        case iTermAIVendorGemini:
            return NSLocalizedStringWithDefaultValue(@"AIProvider.Gemini", nil, [NSBundle mainBundle], @"Gemini", @"Gemini provider name");
        case iTermAIVendorDeepSeek:
            return NSLocalizedStringWithDefaultValue(@"AIProvider.DeepSeek", nil, [NSBundle mainBundle], @"DeepSeek", @"DeepSeek provider name");
        case iTermAIVendorLlama:
            return NSLocalizedStringWithDefaultValue(@"AIProvider.Llama", nil, [NSBundle mainBundle], @"Llama", @"Llama provider name");
        case iTermAIVendorApple:
            return NSLocalizedStringWithDefaultValue(@"AIProvider.AppleIntelligence", nil, [NSBundle mainBundle], @"Apple Intelligence", @"Apple Intelligence provider name");
    }
    return NSLocalizedStringWithDefaultValue(@"AIProvider.OpenAI", nil, [NSBundle mainBundle], @"OpenAI", @"OpenAI provider name");
}

// Whether the user can actually configure a key for this vendor. Only the
// vendors in the "Set API Key" sheet (see aiAPIKeyProviderVendors) have one.
// Llama endpoints are self-hosted and Apple runs on-device, so neither has an
// enterable key; the hint must not claim one exists.
static BOOL iTermAIVendorHasEnterableKey(iTermAIVendor vendor) {
    switch (vendor) {
        case iTermAIVendorOpenAI:
        case iTermAIVendorAnthropic:
        case iTermAIVendorGemini:
        case iTermAIVendorDeepSeek:
            return YES;
        case iTermAIVendorLlama:
        case iTermAIVendorApple:
            return NO;
    }
    return YES;
}

static NSString *iTermManualAIModelHost(NSDictionary *configuration) {
    NSString *url = configuration[kAIManualModelURLKey] ?: @"";
    if (url.length == 0) {
        return @"";
    }
    NSURL *parsedURL = [NSURL URLWithString:url];
    return parsedURL.host ?: url;
}

@class iTermManualAIModelsPanelController;

@protocol iTermManualAIModelsPanelDelegate <NSObject>
- (void)manualModelsPanelAdd:(iTermManualAIModelsPanelController *)panel;
- (void)manualModelsPanel:(iTermManualAIModelsPanelController *)panel editRow:(NSInteger)row;
- (void)manualModelsPanel:(iTermManualAIModelsPanelController *)panel duplicateRow:(NSInteger)row;
- (void)manualModelsPanel:(iTermManualAIModelsPanelController *)panel deleteRow:(NSInteger)row;
- (void)manualModelsPanel:(iTermManualAIModelsPanelController *)panel setDefaultRow:(NSInteger)row;
- (void)manualModelsPanel:(iTermManualAIModelsPanelController *)panel setEconomyRow:(NSInteger)row;
- (void)manualModelsPanelDone:(iTermManualAIModelsPanelController *)panel;
@end

// Sheet listing the manually-configured AI models with add/edit/duplicate/
// delete/set-default/done controls. Owns its window; button clicks route to
// the delegate, which owns persistence and presents the editor sheet.
@interface iTermManualAIModelsPanelController : NSObject<NSTableViewDataSource, NSTableViewDelegate>
@property(nonatomic, readonly) NSWindow *window;
@property(nonatomic, strong) NSMutableArray<NSMutableDictionary *> *configurations;
@property(nonatomic, copy) NSString *defaultModelName;
@property(nonatomic, copy) NSString *economyModelName;
@property(nonatomic) NSInteger selectedIndex;
@property(nonatomic, weak) id<iTermManualAIModelsPanelDelegate> delegate;
- (instancetype)initWithConfigurations:(NSArray<NSDictionary *> *)configurations
                      defaultModelName:(NSString *)defaultModelName
                      economyModelName:(NSString *)economyModelName
                         selectedIndex:(NSInteger)selectedIndex;
- (void)reloadSelectingIndex:(NSInteger)index;
@end

// Sheet form for adding or editing one manual model. Owns its window; presented
// as a child sheet of the manager panel. Completion is called with the built
// configuration dictionary, or nil if the user cancels.
@interface iTermManualAIModelEditorController : NSObject <NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate>
@property(nonatomic, readonly) NSWindow *window;
- (instancetype)initWithConfiguration:(NSDictionary *)configuration
                            isEditing:(BOOL)isEditing;
- (void)beginSheetModalForWindow:(NSWindow *)parent
                     nameIsTaken:(BOOL (^)(NSString *name))nameIsTaken
                      completion:(void (^)(NSDictionary *result))completion;
@end

// A read-only text cell that vertically centers its text within the row.
@interface iTermVerticallyCenteredTextFieldCell : NSTextFieldCell
@end

@implementation iTermVerticallyCenteredTextFieldCell
- (NSRect)titleRectForBounds:(NSRect)bounds {
    NSRect rect = [super titleRectForBounds:bounds];
    const CGFloat textHeight = self.attributedStringValue.size.height;
    const CGFloat delta = (rect.size.height - textHeight) / 2.0;
    if (delta > 0) {
        rect.origin.y += delta;
        rect.size.height -= delta;
    }
    return rect;
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    [super drawInteriorWithFrame:[self titleRectForBounds:cellFrame] inView:controlView];
}
@end

@implementation iTermManualAIModelsPanelController {
    NSWindow *_window;
    NSTableView *_tableView;
    NSSegmentedControl *_addDeleteControl;
    NSSegmentedControl *_editControl;
}

- (instancetype)initWithConfigurations:(NSArray<NSDictionary *> *)configurations
                      defaultModelName:(NSString *)defaultModelName
                      economyModelName:(NSString *)economyModelName
                         selectedIndex:(NSInteger)selectedIndex {
    self = [super init];
    if (self) {
        _configurations = [NSMutableArray array];
        for (NSDictionary *configuration in configurations) {
            [_configurations addObject:[configuration mutableCopy]];
        }
        _defaultModelName = [defaultModelName copy];
        _economyModelName = [economyModelName copy];
        _selectedIndex = selectedIndex;
        [self buildWindow];
        [self reloadSelectingIndex:selectedIndex];
    }
    return self;
}

- (NSWindow *)window {
    return _window;
}

- (void)buildWindow {
    const CGFloat width = 600;
    const CGFloat height = 300;
    const CGFloat margin = 20;
    const CGFloat tableWidth = width - 2 * margin;   // right edge at width - margin
    const CGFloat bottomRowY = 20;
    const CGFloat okWidth = 90;
    const CGFloat okHeight = 30;
    const CGFloat tableBottom = bottomRowY + okHeight + 14;
    const CGFloat tableTop = height - margin;

    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
                                          styleMask:NSWindowStyleMaskTitled
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.title = NSLocalizedStringWithDefaultValue(@"AIManualModels.WindowTitle", nil, [NSBundle mainBundle], @"Manual AI Models", @"Title of the manual AI models panel window");
    NSView *content = _window.contentView;

    NSScrollView *scrollView =
        [[NSScrollView alloc] initWithFrame:NSMakeRect(margin, tableBottom, tableWidth, tableTop - tableBottom)];
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.borderType = NSBezelBorder;

    _tableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.headerView = [[NSTableHeaderView alloc] initWithFrame:NSMakeRect(0, 0, tableWidth, 22)];
    _tableView.usesAlternatingRowBackgroundColors = YES;
    _tableView.allowsMultipleSelection = NO;
    _tableView.rowHeight = 28;
    _tableView.target = self;
    _tableView.doubleAction = @selector(tableDoubleClicked:);

    NSArray<NSDictionary *> *columns = @[
        @{ @"identifier": kAIManualModelsModelColumn, @"title": NSLocalizedStringWithDefaultValue(@"AIManualModels.ModelColumn", nil, [NSBundle mainBundle], @"Model", @"Column title for the model name"), @"width": @260 },
        @{ @"identifier": kAIManualModelsAPIColumn, @"title": NSLocalizedStringWithDefaultValue(@"AIManualModels.APIColumn", nil, [NSBundle mainBundle], @"API", @"Column title for the API"), @"width": @130 },
        @{ @"identifier": kAIManualModelsEndpointColumn, @"title": NSLocalizedStringWithDefaultValue(@"AIManualModels.EndpointColumn", nil, [NSBundle mainBundle], @"Endpoint", @"Column title for the endpoint"), @"width": @150 }
    ];
    for (NSDictionary *spec in columns) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:spec[@"identifier"]];
        column.title = spec[@"title"];
        column.width = [spec[@"width"] doubleValue];
        column.resizingMask = NSTableColumnUserResizingMask;
        iTermVerticallyCenteredTextFieldCell *cell = [[iTermVerticallyCenteredTextFieldCell alloc] init];
        cell.editable = NO;
        cell.selectable = NO;
        column.dataCell = cell;
        [_tableView addTableColumn:column];
    }
    scrollView.documentView = _tableView;
    [content addSubview:scrollView];

    // Add / remove on the left, then edit / duplicate / default.
    _addDeleteControl = [self makeSegmentedControlWithSegments:@[
        @{ @"symbol": SFSymbolGetString(SFSymbolPlus), @"tip": iTermLocalizedAdd() },
        @{ @"symbol": SFSymbolGetString(SFSymbolMinus), @"tip": NSLocalizedStringWithDefaultValue(@"General.Delete", nil, [NSBundle mainBundle], @"Delete", @"Delete button") }
    ] action:@selector(addDeleteClicked:)];
    _editControl = [self makeSegmentedControlWithSegments:@[
        @{ @"symbol": SFSymbolGetString(SFSymbolPencil), @"tip": iTermLocalizedEdit() },
        @{ @"symbol": SFSymbolGetString(SFSymbolPlusSquareOnSquare), @"tip": NSLocalizedStringWithDefaultValue(@"AIManualModels.Duplicate", nil, [NSBundle mainBundle], @"Duplicate", @"Tooltip for the duplicate model button") },
        @{ @"symbol": SFSymbolGetString(SFSymbolStar), @"tip": NSLocalizedStringWithDefaultValue(@"AIManualModels.ToggleDefault", nil, [NSBundle mainBundle], @"Toggle Default", @"Tooltip for the toggle default model button") },
        @{ @"symbol": SFSymbolGetString(SFSymbolLeaf),
           @"tip": NSLocalizedStringWithDefaultValue(@"AIManualModels.ToggleEconomyModel", nil, [NSBundle mainBundle], @"Toggle Economy Model. A cheaper model used for frequent background jobs "
                   @"like command-safety checks and screen-idle detection.", @"Tooltip for the toggle economy model button") }
    ] action:@selector(editControlClicked:)];

    const CGFloat controlY = bottomRowY + (okHeight - _addDeleteControl.frame.size.height) / 2.0;
    NSRect addFrame = _addDeleteControl.frame;
    addFrame.origin = NSMakePoint(margin, controlY);
    _addDeleteControl.frame = addFrame;
    [content addSubview:_addDeleteControl];

    NSRect editFrame = _editControl.frame;
    editFrame.origin = NSMakePoint(NSMaxX(addFrame) + 12, controlY);
    _editControl.frame = editFrame;
    [content addSubview:_editControl];

    // OK: its right edge aligns with the table's right edge.
    NSButton *ok = [NSButton buttonWithTitle:iTermLocalizedOK() target:self action:@selector(okClicked:)];
    ok.bezelStyle = NSBezelStyleRounded;
    ok.keyEquivalent = @"\r";
    ok.frame = NSMakeRect(margin + tableWidth - okWidth, bottomRowY, okWidth, okHeight);
    [content addSubview:ok];

    _window.initialFirstResponder = _tableView;
    _window.defaultButtonCell = ok.cell;
}

- (void)reloadSelectingIndex:(NSInteger)index {
    [_tableView reloadData];
    if (self.configurations.count > 0) {
        const NSInteger clamped = MAX(0, MIN(index, (NSInteger)self.configurations.count - 1));
        self.selectedIndex = clamped;
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)clamped]
                byExtendingSelection:NO];
    } else {
        self.selectedIndex = -1;
    }
    [self updateSegmentEnabled];
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
    if ([identifier isEqualToString:kAIManualModelsModelColumn]) {
        NSString *name = [configuration[kAIManualModelNameKey] isKindOfClass:NSString.class]
            ? configuration[kAIManualModelNameKey]
            : NSLocalizedStringWithDefaultValue(@"AIManualModels.UntitledModel", nil, [NSBundle mainBundle], @"Untitled model", @"Placeholder name for a manual AI model with no name");
        // A leading black star marks the default model, matching the profile list.
        // A leaf SF Symbol marks the economy model. The two are mutually
        // exclusive per row.
        if ([name isEqualToString:self.defaultModelName]) {
            // Localization unneeded
            return [@"★ " stringByAppendingString:name];
        }
        if (self.economyModelName.length > 0 && [name isEqualToString:self.economyModelName]) {
            return [self economyMarkedNameForColumn:tableColumn name:name];
        }
        return name;
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

// The model-name cell for the economy model: a leaf SF Symbol (tinted to the
// text color so it stays monochrome, like the default row's star) followed by
// the model name.
- (NSAttributedString *)economyMarkedNameForColumn:(NSTableColumn *)column name:(NSString *)name {
    NSFont *font = [column.dataCell isKindOfClass:NSCell.class] ? [column.dataCell font] : nil;
    if (!font) {
        font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    }
    NSDictionary *attributes = @{ NSFontAttributeName: font,
                                  NSForegroundColorAttributeName: NSColor.labelColor };

    NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
    NSImageSymbolConfiguration *config =
        [NSImageSymbolConfiguration configurationWithHierarchicalColor:NSColor.labelColor];
    NSImage *image = [[NSImage imageWithSystemSymbolName:SFSymbolGetString(SFSymbolLeaf)
                               accessibilityDescription:NSLocalizedStringWithDefaultValue(@"AIManualModels.EconomyModelAccessibility", nil, [NSBundle mainBundle], @"Economy model", @"Accessibility description for the economy model marker symbol")]
                      imageWithSymbolConfiguration:config];
    const CGFloat side = font.pointSize + 1;
    image.size = NSMakeSize(side, side);
    attachment.image = image;

    NSMutableAttributedString *result =
        [[NSMutableAttributedString alloc] initWithAttributedString:
            [NSAttributedString attributedStringWithAttachment:attachment]];
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:[@" " stringByAppendingString:name]
                                                                   attributes:attributes]];
    return result;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    self.selectedIndex = _tableView.selectedRow;
    [self updateSegmentEnabled];
}

- (NSSegmentedControl *)makeSegmentedControlWithSegments:(NSArray<NSDictionary *> *)segments
                                                  action:(SEL)action {
    NSSegmentedControl *control = [[NSSegmentedControl alloc] init];
    control.segmentCount = (NSInteger)segments.count;
    control.trackingMode = NSSegmentSwitchTrackingMomentary;
    control.target = self;
    control.action = action;
    for (NSInteger i = 0; i < (NSInteger)segments.count; i++) {
        NSDictionary *segment = segments[(NSUInteger)i];
        NSImage *image = [NSImage imageWithSystemSymbolName:segment[@"symbol"]
                                  accessibilityDescription:segment[@"tip"]];
        [control setImage:image forSegment:i];
        [control setWidth:34 forSegment:i];
        [control setToolTip:segment[@"tip"] forSegment:i];
    }
    [control sizeToFit];
    return control;
}

- (BOOL)ensureSelectionForSegmentAction {
    self.selectedIndex = _tableView.selectedRow;
    if (self.selectedIndex < 0 || self.selectedIndex >= (NSInteger)self.configurations.count) {
        NSBeep();
        return NO;
    }
    return YES;
}

- (void)updateSegmentEnabled {
    const BOOL hasSelection = self.selectedIndex >= 0 && self.selectedIndex < (NSInteger)self.configurations.count;
    [_addDeleteControl setEnabled:YES forSegment:0];        // Add is always available.
    [_addDeleteControl setEnabled:hasSelection forSegment:1]; // Delete needs a selection.

    // The economy toggle is the last (leaf) segment. It is unavailable for the
    // default model because a model can't be both the default and the economy
    // model. Disabling the control (rather than beeping on click) shows the
    // reason: the selected row already carries the default star.
    NSString *selectedName = nil;
    if (hasSelection) {
        id value = self.configurations[(NSUInteger)self.selectedIndex][kAIManualModelNameKey];
        selectedName = [value isKindOfClass:NSString.class] ? value : nil;
    }
    const BOOL selectedIsDefault = selectedName != nil &&
        [selectedName isEqualToString:self.defaultModelName];
    const NSInteger economySegment = _editControl.segmentCount - 1;
    for (NSInteger i = 0; i < _editControl.segmentCount; i++) {
        const BOOL enabled = hasSelection && !(i == economySegment && selectedIsDefault);
        [_editControl setEnabled:enabled forSegment:i];
    }
}

- (void)tableDoubleClicked:(id)sender {
    if (_tableView.clickedRow >= 0) {
        [self.delegate manualModelsPanel:self editRow:_tableView.clickedRow];
    }
}

- (void)addDeleteClicked:(NSSegmentedControl *)sender {
    if (sender.selectedSegment == 0) {
        [self.delegate manualModelsPanelAdd:self];
        return;
    }
    if ([self ensureSelectionForSegmentAction]) {
        [self.delegate manualModelsPanel:self deleteRow:self.selectedIndex];
    }
}

- (void)editControlClicked:(NSSegmentedControl *)sender {
    if (![self ensureSelectionForSegmentAction]) {
        return;
    }
    switch (sender.selectedSegment) {
        case 0:
            [self.delegate manualModelsPanel:self editRow:self.selectedIndex];
            break;
        case 1:
            [self.delegate manualModelsPanel:self duplicateRow:self.selectedIndex];
            break;
        case 2:
            [self.delegate manualModelsPanel:self setDefaultRow:self.selectedIndex];
            break;
        case 3:
            [self.delegate manualModelsPanel:self setEconomyRow:self.selectedIndex];
            break;
        default:
            break;
    }
}

- (void)okClicked:(id)sender {
    [self.delegate manualModelsPanelDone:self];
}

@end

@implementation iTermManualAIModelEditorController {
    NSWindow *_window;
    NSDictionary *_base;
    BOOL _isEditing;
    NSPopUpButton *_presetPopup;
    NSArray<iTermAIModel *> *_presets;
    NSArray<iTermAIProviderPreset *> *_providerPresets;
    NSTextField *_nameField;
    NSTextField *_urlField;
    NSPopUpButton *_apiPopup;
    NSTextField *_apiKeyHintLabel;
    NSTextField *_contextField;
    NSTextField *_responseField;
    NSPopUpButton *_vectorStorePopup;
    NSButton *_supportsTemperatureButton;
    NSButton *_configurableThinkingButton;
    NSTableView *_headersTable;
    NSMutableArray<NSMutableDictionary *> *_headers;
    NSMutableDictionary<NSString *, NSButton *> *_featureButtons;
    NSButton *_testButton;
    NSProgressIndicator *_testSpinner;
    NSDictionary *_result;
    BOOL (^_nameIsTaken)(NSString *name);
}

- (instancetype)initWithConfiguration:(NSDictionary *)configuration
                            isEditing:(BOOL)isEditing {
    self = [super init];
    if (self) {
        _base = [configuration copy] ?: @{};
        _isEditing = isEditing;
        _featureButtons = [NSMutableDictionary dictionary];
        [self buildWindow];
    }
    return self;
}

- (NSWindow *)window {
    return _window;
}

// A checkbox for a per-model quirk the config could not previously express. Its
// initial state matches the runtime fallback in LLMMetadata.manualModel: a
// stored value wins; when absent it uses catalogValue (the same-named built-in's
// value). Advances *y down one row so callers can stack more controls.
- (NSButton *)addQuirkCheckboxWithTitle:(NSString *)title
                                    key:(NSString *)key
                           catalogValue:(BOOL)catalogValue
                                tooltip:(NSString *)tooltip
                                    toY:(CGFloat *)y
                                 fieldX:(CGFloat)fieldX
                                  width:(CGFloat)fieldWidth
                                content:(NSView *)content {
    NSButton *button = [NSButton checkboxWithTitle:title target:nil action:nil];
    button.frame = NSMakeRect(fieldX, *y, fieldWidth, 22);
    const BOOL value = (_base[key] != nil) ? iTermManualAIModelBoolValue(_base, key) : catalogValue;
    button.state = value ? NSControlStateValueOn : NSControlStateValueOff;
    button.toolTip = tooltip;
    [content addSubview:button];
    *y -= 26;
    return button;
}

- (void)buildWindow {
    // Wide enough for the API-key hint line under the API popup to fit longer
    // localizations (e.g. Russian) without truncating.
    const CGFloat width = 590;
    // Extra height over the base layout makes room for the API-key hint line
    // under the API popup and the custom-headers section near the bottom.
    const CGFloat height = 706;
    const CGFloat margin = 20;
    const CGFloat labelWidth = 150;
    const CGFloat fieldX = margin + labelWidth + 12;
    const CGFloat fieldWidth = width - margin - fieldX;
    const CGFloat rowHeight = 30;

    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
                                          styleMask:NSWindowStyleMaskTitled
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.title = _isEditing ? NSLocalizedStringWithDefaultValue(@"AIModelEditor.EditTitle", nil, [NSBundle mainBundle], @"Edit Manual AI Model", @"Window title when editing a manual AI model") : NSLocalizedStringWithDefaultValue(@"AIModelEditor.AddTitle", nil, [NSBundle mainBundle], @"Add Manual AI Model", @"Window title when adding a manual AI model");
    NSView *content = _window.contentView;

    NSTextField *title = [NSTextField labelWithString:_window.title];
    title.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
    title.frame = NSMakeRect(margin, height - 34, width - 2 * margin, 20);
    [content addSubview:title];

    __block CGFloat y = height - 66;
    void (^addLabel)(NSString *) = ^(NSString *labelTitle) {
        NSTextField *label = [NSTextField labelWithString:labelTitle];
        label.alignment = NSTextAlignmentRight;
        label.frame = NSMakeRect(margin, y + 3, labelWidth, 20);
        [content addSubview:label];
    };
    NSTextField *(^addTextField)(NSString *, NSString *) = ^NSTextField *(NSString *labelTitle, NSString *value) {
        addLabel(labelTitle);
        NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(fieldX, y, fieldWidth, 24)];
        field.stringValue = [value isKindOfClass:NSString.class] ? value : @"";
        [content addSubview:field];
        y -= rowHeight;
        return field;
    };

    // Presets copy a built-in model's settings into the form so a user can start
    // from something close to what they want and tweak it.
    addLabel(NSLocalizedStringWithDefaultValue(@"AIModelEditor.PresetLabel", nil, [NSBundle mainBundle], @"Preset:", @"Label for the preset popup"));
    _presetPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(fieldX, y, fieldWidth, 24)];
    [_presetPopup addItemWithTitle:NSLocalizedStringWithDefaultValue(@"AIModelEditor.PresetCustom", nil, [NSBundle mainBundle], @"Custom", @"Preset popup option for a custom (non-preset) model")];
    _presetPopup.lastItem.tag = -1;
    [_presetPopup.menu addItem:[NSMenuItem separatorItem]];
    _presets = [[AIMetadata instance] presetModels];
    for (NSInteger i = 0; i < (NSInteger)_presets.count; i++) {
        [_presetPopup addItemWithTitle:_presets[(NSUInteger)i].name];
        _presetPopup.lastItem.tag = i;
    }
    // Third-party OpenAI-compatible gateways. Unlike the catalog presets above,
    // these fill in the endpoint and API but leave the model name for the user.
    _providerPresets = [[AIMetadata instance] providerPresets];
    if (_providerPresets.count > 0) {
        [_presetPopup.menu addItem:[NSMenuItem separatorItem]];
        for (NSInteger i = 0; i < (NSInteger)_providerPresets.count; i++) {
            [_presetPopup addItemWithTitle:_providerPresets[(NSUInteger)i].name];
            _presetPopup.lastItem.tag = kAIProviderPresetTagBase + i;
        }
    }
    [_presetPopup selectItemWithTag:-1];
    _presetPopup.target = self;
    _presetPopup.action = @selector(presetSelected:);
    [content addSubview:_presetPopup];
    y -= rowHeight + 8;

    _nameField = addTextField(NSLocalizedStringWithDefaultValue(@"AIModelEditor.ModelLabel", nil, [NSBundle mainBundle], @"Model:", @"Label for the model name field"), _base[kAIManualModelNameKey]);
    _urlField = addTextField(NSLocalizedStringWithDefaultValue(@"AIModelEditor.URLLabel", nil, [NSBundle mainBundle], @"URL:", @"Label for the URL field"), _base[kAIManualModelURLKey]);

    addLabel(NSLocalizedStringWithDefaultValue(@"AIModelEditor.APILabel", nil, [NSBundle mainBundle], @"API:", @"Label for the API popup"));
    _apiPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(fieldX, y, fieldWidth, 24)];
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
        [_apiPopup addItemWithTitle:iTermTitleForAIAPI(api)];
        _apiPopup.lastItem.tag = (NSInteger)api;
    }
    [_apiPopup selectItemWithTag:iTermManualAIModelIntegerValue(_base,
                                                                kAIManualModelAPIKey,
                                                                iTermAIAPIChatCompletions)];
    _apiPopup.target = self;
    _apiPopup.action = @selector(apiKeyHintInputDidChange:);
    [content addSubview:_apiPopup];
    y -= 24;

    // The API key sent is the stored key for the vendor inferred from the API,
    // URL, and model name, which is not obvious to users (see issue 12975). Spell
    // it out here, updated live as those fields change.
    _apiKeyHintLabel = [NSTextField labelWithString:@""];
    _apiKeyHintLabel.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    _apiKeyHintLabel.textColor = [NSColor secondaryLabelColor];
    _apiKeyHintLabel.frame = NSMakeRect(fieldX, y + 4, fieldWidth, 16);
    [content addSubview:_apiKeyHintLabel];
    y -= 22;

    // The name and URL fields feed the vendor resolver, so track their edits.
    _nameField.delegate = self;
    _urlField.delegate = self;

    _contextField =
        addTextField(NSLocalizedStringWithDefaultValue(@"AIModelEditor.ContextTokensLabel", nil, [NSBundle mainBundle], @"Context tokens:", @"Label for the context window tokens field"),
                     [NSString stringWithFormat:@"%ld",
                      (long)iTermManualAIModelIntegerValue(_base, kAIManualModelContextWindowTokensKey, 8192)]);
    _responseField =
        addTextField(NSLocalizedStringWithDefaultValue(@"AIModelEditor.MaxResponseTokensLabel", nil, [NSBundle mainBundle], @"Max response tokens:", @"Label for the max response tokens field"),
                     [NSString stringWithFormat:@"%ld",
                      (long)iTermManualAIModelIntegerValue(_base, kAIManualModelMaxResponseTokensKey, 8192)]);

    addLabel(NSLocalizedStringWithDefaultValue(@"AIModelEditor.VectorStoreLabel", nil, [NSBundle mainBundle], @"Vector store:", @"Label for the vector store popup"));
    _vectorStorePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(fieldX, y, fieldWidth, 24)];
    [_vectorStorePopup addItemWithTitle:NSLocalizedStringWithDefaultValue(@"AIModelEditor.VectorStoreDisabled", nil, [NSBundle mainBundle], @"Disabled", @"Vector store popup option meaning no vector store")];
    _vectorStorePopup.lastItem.tag = 0;
    [_vectorStorePopup addItemWithTitle:NSLocalizedStringWithDefaultValue(@"AIProvider.OpenAI", nil, [NSBundle mainBundle], @"OpenAI", @"OpenAI provider name")];
    _vectorStorePopup.lastItem.tag = 1;
    [_vectorStorePopup selectItemWithTag:iTermManualAIModelIntegerValue(_base, kAIManualModelVectorStoreKey, 0)];
    [content addSubview:_vectorStorePopup];
    y -= rowHeight + 8;

    NSArray<NSDictionary *> *features = @[
        @{ @"title": NSLocalizedStringWithDefaultValue(@"AIModelEditor.FeatureFunctionCalling", nil, [NSBundle mainBundle], @"Function calling", @"Checkbox label for the function-calling model feature"), @"key": kAIManualModelFunctionCallingKey },
        @{ @"title": NSLocalizedStringWithDefaultValue(@"AIModelEditor.FeatureStreamingResponses", nil, [NSBundle mainBundle], @"Streaming responses", @"Checkbox label for the streaming-responses model feature"), @"key": kAIManualModelStreamingKey },
        @{ @"title": NSLocalizedStringWithDefaultValue(@"AIModelEditor.FeatureHostedWebSearch", nil, [NSBundle mainBundle], @"Hosted web search", @"Checkbox label for the hosted web search model feature"), @"key": kAIManualModelHostedWebSearchKey },
        @{ @"title": NSLocalizedStringWithDefaultValue(@"AIModelEditor.FeatureHostedFileSearch", nil, [NSBundle mainBundle], @"Hosted file search", @"Checkbox label for the hosted file search model feature"), @"key": kAIManualModelHostedFileSearchKey },
        @{ @"title": NSLocalizedStringWithDefaultValue(@"AIModelEditor.FeatureHostedCodeInterpreter", nil, [NSBundle mainBundle], @"Hosted code interpreter", @"Checkbox label for the hosted code interpreter model feature"), @"key": kAIManualModelHostedCodeInterpreterKey }
    ];
    for (NSDictionary *feature in features) {
        NSString *key = feature[@"key"];
        NSButton *button = [NSButton checkboxWithTitle:feature[@"title"] target:nil action:nil];
        button.frame = NSMakeRect(fieldX, y, fieldWidth, 22);
        button.state = iTermManualAIModelBoolValue(_base, key) ? NSControlStateValueOn : NSControlStateValueOff;
        [content addSubview:button];
        _featureButtons[key] = button;
        y -= 26;
    }

    // Configurable thinking and temperature-support are per-model quirks that
    // the request builder reads but the manual config could not previously
    // express. Both use the same rule: a stored value wins; when absent, inherit
    // from a built-in with the same name so cloning a preset (or an older config
    // predating the field) matches the built-in. A blank default that a Save
    // then persisted would silently disable thinking or send a rejected
    // temperature.
    NSString *baseName = [_base[kAIManualModelNameKey] isKindOfClass:NSString.class]
        ? _base[kAIManualModelNameKey] : @"";
    _configurableThinkingButton =
        [self addQuirkCheckboxWithTitle:NSLocalizedStringWithDefaultValue(@"AIModelEditor.ConfigurableThinking", nil, [NSBundle mainBundle], @"Configurable thinking", @"Checkbox label for whether a model supports configurable thinking")
                                    key:kAIManualModelConfigurableThinkingKey
                           catalogValue:[[AIMetadata instance] modelSupportsConfigurableThinking:baseName]
                                tooltip:NSLocalizedStringWithDefaultValue(@"AIModelEditor.ConfigurableThinkingTooltip", nil, [NSBundle mainBundle], @"Enable for reasoning models with a thinking mode, such as GPT-5, "
                                        @"o-series, or DeepSeek models, so the chat’s Think toggle appears.", @"Tooltip for the configurable thinking checkbox")
                                    toY:&y
                                 fieldX:fieldX
                                  width:fieldWidth
                                content:content];
    _supportsTemperatureButton =
        [self addQuirkCheckboxWithTitle:NSLocalizedStringWithDefaultValue(@"AIModelEditor.SupportsTemperature", nil, [NSBundle mainBundle], @"Supports temperature", @"Checkbox label for whether a model supports a temperature parameter")
                                    key:kAIManualModelSupportsTemperatureKey
                           catalogValue:[[AIMetadata instance] modelSupportsTemperature:baseName]
                                tooltip:NSLocalizedStringWithDefaultValue(@"AIModelEditor.SupportsTemperatureTooltip", nil, [NSBundle mainBundle], @"Uncheck for models that reject a temperature parameter, such as "
                                        @"Anthropic Opus 4.7 and later.", @"Tooltip for the supports temperature checkbox")
                                    toY:&y
                                 fieldX:fieldX
                                  width:fieldWidth
                                content:content];

    // Per-model custom HTTP headers, merged into every request to this model's
    // endpoint. Lets an authenticated self-hosted endpoint carry the auth header
    // it needs (issue 12975). Editable Header/Value table with add/remove.
    _headers = [NSMutableArray array];
    id savedHeaders = _base[kAIManualModelCustomHeadersKey];
    if ([savedHeaders isKindOfClass:NSArray.class]) {
        for (id entry in (NSArray *)savedHeaders) {
            if ([entry isKindOfClass:NSDictionary.class]) {
                [_headers addObject:[entry mutableCopy]];
            }
        }
    }

    y -= 6;
    NSTextField *headersLabel = [NSTextField labelWithString:NSLocalizedStringWithDefaultValue(@"AIModelEditor.CustomHeadersLabel", nil, [NSBundle mainBundle], @"Custom headers:", @"Label for the custom HTTP headers table")];
    headersLabel.alignment = NSTextAlignmentRight;
    headersLabel.frame = NSMakeRect(margin, y - 17, labelWidth, 20);
    [content addSubview:headersLabel];

    const CGFloat headersTableHeight = 120;
    NSScrollView *headersScroll =
        [[NSScrollView alloc] initWithFrame:NSMakeRect(fieldX, y - headersTableHeight, fieldWidth, headersTableHeight)];
    headersScroll.hasVerticalScroller = YES;
    headersScroll.borderType = NSBezelBorder;
    _headersTable = [[NSTableView alloc] initWithFrame:headersScroll.bounds];
    _headersTable.usesAlternatingRowBackgroundColors = YES;
    _headersTable.allowsMultipleSelection = NO;
    _headersTable.rowHeight = 22;
    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameColumn.title = NSLocalizedStringWithDefaultValue(@"AIModelEditor.HeaderColumn", nil, [NSBundle mainBundle], @"Header", @"Column title for the custom header name");
    nameColumn.width = 170;
    nameColumn.editable = YES;
    NSTableColumn *valueColumn = [[NSTableColumn alloc] initWithIdentifier:@"value"];
    valueColumn.title = NSLocalizedStringWithDefaultValue(@"AIModelEditor.ValueColumn", nil, [NSBundle mainBundle], @"Value", @"Column title for the custom header value");
    valueColumn.width = fieldWidth - nameColumn.width - 24;
    valueColumn.editable = YES;
    [_headersTable addTableColumn:nameColumn];
    [_headersTable addTableColumn:valueColumn];
    _headersTable.dataSource = self;
    _headersTable.delegate = self;
    headersScroll.documentView = _headersTable;
    [content addSubview:headersScroll];
    y -= headersTableHeight + 4;

    NSSegmentedControl *headersAddRemove =
        // Localization unneeded
        [NSSegmentedControl segmentedControlWithLabels:@[ @"+", @"−" ]
                                          trackingMode:NSSegmentSwitchTrackingMomentary
                                                target:self
                                                action:@selector(headersAddRemoveClicked:)];
    headersAddRemove.frame = NSMakeRect(fieldX, y - 22, 72, 22);
    [content addSubview:headersAddRemove];
    y -= 22 + 10;

    NSButton *save = [NSButton buttonWithTitle:(_isEditing ? NSLocalizedStringWithDefaultValue(@"General.Save", nil, [NSBundle mainBundle], @"Save", @"Save button") : iTermLocalizedAdd())
                                        target:self
                                        action:@selector(saveClicked:)];
    save.bezelStyle = NSBezelStyleRounded;
    save.keyEquivalent = @"\r";
    save.frame = NSMakeRect(width - margin - 100, 16, 100, 30);
    [content addSubview:save];

    NSButton *cancel = [NSButton buttonWithTitle:iTermLocalizedCancel()
                                          target:self
                                          action:@selector(cancelClicked:)];
    cancel.bezelStyle = NSBezelStyleRounded;
    cancel.keyEquivalent = @"\033";
    cancel.frame = NSMakeRect(width - margin - 100 - 8 - 100, 16, 100, 30);
    [content addSubview:cancel];

    // Sends a live probe with the current form values so the user can confirm the
    // endpoint and API key work before saving. Sits on the far left of the button
    // row, away from Save/Cancel.
    _testButton = [NSButton buttonWithTitle:NSLocalizedStringWithDefaultValue(@"AIModelEditor.TestConnection", nil, [NSBundle mainBundle], @"Test Connection", @"Title of the button that tests the AI endpoint connection")
                                     target:self
                                     action:@selector(testClicked:)];
    _testButton.bezelStyle = NSBezelStyleRounded;
    _testButton.frame = NSMakeRect(margin, 16, 150, 30);
    [content addSubview:_testButton];

    // Spinner just to the right of the Test button so a slow endpoint (a cold
    // local Ollama can take tens of seconds) visibly reads as in-progress rather
    // than hung. Hidden while stopped. Let it take its natural size, then center
    // it vertically against the button so it doesn't look squashed.
    _testSpinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _testSpinner.style = NSProgressIndicatorStyleSpinning;
    _testSpinner.controlSize = NSControlSizeSmall;
    _testSpinner.displayedWhenStopped = NO;
    [_testSpinner sizeToFit];
    const CGFloat testButtonMidY = 16 + 30.0 / 2.0;
    NSRect spinnerFrame = _testSpinner.frame;
    spinnerFrame.origin.x = margin + 150 + 8;
    spinnerFrame.origin.y = testButtonMidY - spinnerFrame.size.height / 2.0;
    _testSpinner.frame = spinnerFrame;
    [content addSubview:_testSpinner];

    _window.initialFirstResponder = _nameField;
    _window.defaultButtonCell = save.cell;

    [self updateEditorAPIKeyHint];
}

// Resolves the vendor from the current form values exactly as at request time so
// the hint agrees with the key that will actually be sent.
- (void)updateEditorAPIKeyHint {
    const iTermAIAPI api = (iTermAIAPI)_apiPopup.selectedTag;
    NSString *modelName = _nameField.stringValue ?: @"";
    NSString *url = _urlField.stringValue ?: @"";
    const iTermAIVendor vendor = [iTermLLMMetadata vendorForManualModelWithAPI:api
                                                                           url:url
                                                                     modelName:modelName];
    if (iTermAIVendorHasEnterableKey(vendor)) {
        _apiKeyHintLabel.stringValue =
            [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"AIKeyHint.Authorizes", nil, [NSBundle mainBundle], @"Authorizes with your %@ API key.", @"Hint telling the user which provider's API key authorizes the model; %@ is the provider name"),
             iTermAIVendorProviderName(vendor)];
    } else {
        // No key can be configured: self-hosted (Llama) or Apple Intelligence
        // (which runs on-device or via Private Cloud Compute).
        _apiKeyHintLabel.stringValue = NSLocalizedStringWithDefaultValue(@"AIKeyHint.NoKeyUsed", nil, [NSBundle mainBundle], @"No API key is used.", @"Hint shown when the selected model needs no API key");
    }
}

- (void)apiKeyHintInputDidChange:(id)sender {
    [self updateEditorAPIKeyHint];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    [self updateEditorAPIKeyHint];
}

#pragma mark - Custom headers table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView != _headersTable) {
        return 0;
    }
    return (NSInteger)_headers.count;
}

// View-based cell: a borderless editable NSTextField inside an NSTableCellView.
// NSTextField vertically centers single-line text and uses the correct control
// text color, unlike a bare NSTextFieldCell (which top-aligns). Edits commit
// through -controlTextDidEndEditing:.
- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    if (tableView != _headersTable || row < 0 || row >= (NSInteger)_headers.count) {
        return nil;
    }
    NSString *identifier = tableColumn.identifier;
    NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (cell == nil) {
        const CGFloat cellHeight = _headersTable.rowHeight;
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, cellHeight)];
        cell.identifier = identifier;
        NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
        field.bordered = NO;
        field.drawsBackground = NO;
        field.editable = YES;
        field.selectable = YES;
        field.usesSingleLineMode = YES;
        field.lineBreakMode = NSLineBreakByTruncatingTail;
        field.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
        [field sizeToFit];  // natural single-line height for the font
        // NSTextFieldCell top-aligns single-line text, so a field that fills a
        // taller row draws its text near the top (the off-center look). Give the
        // field its natural height and center it in the row with flexible
        // top/bottom margins, so the text stays centered for both display and
        // editing (the field editor inherits this frame).
        const CGFloat fieldHeight = NSHeight(field.frame) > 0 ? NSHeight(field.frame) : 17;
        field.frame = NSMakeRect(0,
                                 floor((cellHeight - fieldHeight) / 2.0),
                                 tableColumn.width,
                                 fieldHeight);
        field.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;
        field.delegate = self;
        cell.textField = field;
        [cell addSubview:field];
    }
    cell.textField.stringValue = _headers[(NSUInteger)row][identifier] ?: @"";
    return cell;
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    NSTextField *field = notification.object;
    if (![field isKindOfClass:NSTextField.class]) {
        return;
    }
    const NSInteger row = [_headersTable rowForView:field];
    const NSInteger column = [_headersTable columnForView:field];
    if (row < 0 || column < 0 || row >= (NSInteger)_headers.count ||
        column >= (NSInteger)_headersTable.tableColumns.count) {
        return;  // not one of our header cells (e.g. the model/URL fields)
    }
    NSString *identifier = _headersTable.tableColumns[(NSUInteger)column].identifier;
    NSString *value = field.stringValue ?: @"";
    if ([identifier isEqualToString:@"name"]) {
        value = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    // Commit the raw value into the model. Validation happens once in
    // -saveClicked:, not here: presenting an alert from this delegate (which
    // fires while first responder resigns as the Save button is clicked) would
    // race the sheet teardown, orphaning the alert and dropping the edit.
    _headers[(NSUInteger)row][identifier] = value;
}

- (void)headersAddRemoveClicked:(NSSegmentedControl *)sender {
    // Commit any in-progress cell edit before mutating _headers, so the pending
    // value lands in the right row (rowForView: would otherwise resolve against
    // the already-mutated table) and is not dropped.
    [_window makeFirstResponder:nil];
    if (sender.selectedSegment == 0) {
        [_headers addObject:[@{ @"name": @"", @"value": @"" } mutableCopy]];
        [_headersTable reloadData];
        const NSInteger row = (NSInteger)_headers.count - 1;
        [_headersTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                   byExtendingSelection:NO];
        [_headersTable editColumn:0 row:row withEvent:nil select:YES];
        return;
    }
    const NSInteger row = _headersTable.selectedRow;
    if (row >= 0 && row < (NSInteger)_headers.count) {
        [_headers removeObjectAtIndex:(NSUInteger)row];
        [_headersTable reloadData];
    }
}

// The persisted list, dropping rows the user added but never named.
- (NSArray<NSDictionary *> *)nonEmptyHeaders {
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (NSDictionary *entry in _headers) {
        // Persist exactly what -saveClicked: validated: the trimmed name and a
        // string value. Otherwise a name like "Foo " validates (trimmed) but is
        // stored untrimmed and later dropped by AICustomHeaders.merged.
        NSString *name = [entry[@"name"] isKindOfClass:NSString.class] ? entry[@"name"] : @"";
        name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (name.length == 0) {
            continue;
        }
        NSString *value = [entry[@"value"] isKindOfClass:NSString.class] ? entry[@"value"] : @"";
        [result addObject:@{ @"name": name, @"value": value }];
    }
    return result;
}

- (void)beginSheetModalForWindow:(NSWindow *)parent
                     nameIsTaken:(BOOL (^)(NSString *name))nameIsTaken
                      completion:(void (^)(NSDictionary *result))completion {
    _nameIsTaken = [nameIsTaken copy];
    void (^copiedCompletion)(NSDictionary *) = [completion copy];
    __weak __typeof(self) weakSelf = self;
    [parent beginSheet:_window completionHandler:^(NSModalResponse returnCode) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        NSDictionary *result = nil;
        if (strongSelf && returnCode == NSModalResponseOK) {
            result = strongSelf->_result;
        }
        if (copiedCompletion) {
            copiedCompletion(result);
        }
    }];
}

- (void)presetSelected:(NSPopUpButton *)sender {
    const NSInteger index = sender.selectedItem.tag;
    if (index >= kAIProviderPresetTagBase) {
        [self providerPresetSelected:index - kAIProviderPresetTagBase];
        return;
    }
    if (index < 0 || index >= (NSInteger)_presets.count) {
        return;
    }
    iTermAIModel *preset = _presets[(NSUInteger)index];
    // Fill every field, including the model name, from the preset so choosing a
    // preset actually configures the model the user picked. The provider needs
    // the real model name in the request; a user who is proxying can rename it
    // afterward if they want a name distinct from the built-in catalog entry.
    _nameField.stringValue = preset.name ?: @"";
    _urlField.stringValue = preset.url ?: @"";
    [_apiPopup selectItemWithTag:(NSInteger)preset.api];
    _contextField.stringValue = [NSString stringWithFormat:@"%ld", (long)preset.contextWindowTokens];
    _responseField.stringValue = [NSString stringWithFormat:@"%ld", (long)preset.maxResponseTokens];
    [_vectorStorePopup selectItemWithTag:(NSInteger)preset.vectorStoreConfig];
    _featureButtons[kAIManualModelFunctionCallingKey].state =
        preset.functionCallingFeatureEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _featureButtons[kAIManualModelStreamingKey].state =
        preset.streamingFeatureEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _featureButtons[kAIManualModelHostedWebSearchKey].state =
        preset.hostedWebSearchFeatureEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _featureButtons[kAIManualModelHostedFileSearchKey].state =
        preset.hostedFileSearchFeatureEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _featureButtons[kAIManualModelHostedCodeInterpreterKey].state =
        preset.hostedCodeInterpreterFeatureEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _configurableThinkingButton.state =
        preset.configurableThinkingFeatureEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _supportsTemperatureButton.state =
        preset.supportsTemperature ? NSControlStateValueOn : NSControlStateValueOff;
    [self updateEditorAPIKeyHint];
}

// A provider preset configures an OpenAI-compatible gateway: it fills in the
// endpoint, API, token limits, and capability checkboxes, but deliberately
// clears the model name (offering the host's example as placeholder text) so the
// user picks the specific model the gateway should serve.
- (void)providerPresetSelected:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_providerPresets.count) {
        return;
    }
    iTermAIProviderPreset *preset = _providerPresets[(NSUInteger)index];
    _nameField.stringValue = @"";
    _nameField.placeholderString = preset.placeholderModelName ?: @"";
    _urlField.stringValue = preset.url ?: @"";
    [_apiPopup selectItemWithTag:(NSInteger)preset.api];
    _contextField.stringValue = [NSString stringWithFormat:@"%ld", (long)preset.contextWindowTokens];
    _responseField.stringValue = [NSString stringWithFormat:@"%ld", (long)preset.maxResponseTokens];
    [_vectorStorePopup selectItemWithTag:0];
    _featureButtons[kAIManualModelFunctionCallingKey].state =
        preset.functionCalling ? NSControlStateValueOn : NSControlStateValueOff;
    _featureButtons[kAIManualModelStreamingKey].state =
        preset.streaming ? NSControlStateValueOn : NSControlStateValueOff;
    _featureButtons[kAIManualModelHostedWebSearchKey].state = NSControlStateValueOff;
    _featureButtons[kAIManualModelHostedFileSearchKey].state = NSControlStateValueOff;
    _featureButtons[kAIManualModelHostedCodeInterpreterKey].state = NSControlStateValueOff;
    _configurableThinkingButton.state = NSControlStateValueOff;
    _supportsTemperatureButton.state = NSControlStateValueOn;
    [self updateEditorAPIKeyHint];
    // The model name is required to save; nudge the user straight to it.
    [_window makeFirstResponder:_nameField];
}

- (void)testClicked:(id)sender {
    // Commit any in-progress header cell edit so the probe uses what's on screen.
    [_window makeFirstResponder:nil];
    NSString *name =
        [_nameField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *url =
        [_urlField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (name.length == 0 || url.length == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedStringWithDefaultValue(@"AIModelEditor.MissingInfoTitle", nil, [NSBundle mainBundle], @"Missing Information", @"Title of alert shown when required fields are empty before testing");
        alert.informativeText = NSLocalizedStringWithDefaultValue(@"AIModelEditor.MissingInfoText", nil, [NSBundle mainBundle], @"Enter a model name and URL before testing the connection.", @"Body of alert shown when required fields are empty before testing");
        [alert beginSheetModalForWindow:_window completionHandler:^(NSModalResponse returnCode) {}];
        return;
    }
    const iTermAIAPI api = (iTermAIAPI)_apiPopup.selectedItem.tag;
    const BOOL functionCalling =
        _featureButtons[kAIManualModelFunctionCallingKey].state == NSControlStateValueOn;
    const BOOL supportsTemperature =
        _supportsTemperatureButton.state == NSControlStateValueOn;

    NSString *savedTitle = _testButton.title;
    _testButton.enabled = NO;
    _testButton.title = NSLocalizedStringWithDefaultValue(@"AIModelEditor.Testing", nil, [NSBundle mainBundle], @"Testing…", @"Title of the test button while an AI connection test is running");
    [_testSpinner startAnimation:nil];
    __weak __typeof(self) weakSelf = self;
    [iTermAIConnectionTester testModelName:name
                                       url:url
                                       api:api
                           functionCalling:functionCalling
                       supportsTemperature:supportsTemperature
                             customHeaders:[self nonEmptyHeaders]
                                  inWindow:_window
                                completion:^(iTermAIConnectionTestOutcome outcome, NSString *message) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf->_testSpinner stopAnimation:nil];
        strongSelf->_testButton.enabled = YES;
        strongSelf->_testButton.title = savedTitle;
        if (outcome == iTermAIConnectionTestOutcomeCancelled) {
            return;
        }
        NSAlert *alert = [[NSAlert alloc] init];
        if (outcome == iTermAIConnectionTestOutcomeSuccess) {
            alert.alertStyle = NSAlertStyleInformational;
            alert.messageText = NSLocalizedStringWithDefaultValue(@"AIModelEditor.ConnectionSucceeded", nil, [NSBundle mainBundle], @"Connection Succeeded", @"Title of alert when the AI connection test succeeds");
        } else {
            alert.alertStyle = NSAlertStyleWarning;
            alert.messageText = NSLocalizedStringWithDefaultValue(@"AIModelEditor.ConnectionFailed", nil, [NSBundle mainBundle], @"Connection Failed", @"Title of alert when the AI connection test fails");
        }
        alert.informativeText = message ?: @"";
        [alert beginSheetModalForWindow:strongSelf->_window completionHandler:^(NSModalResponse returnCode) {}];
    }];
}

- (void)cancelClicked:(id)sender {
    [_window.sheetParent endSheet:_window returnCode:NSModalResponseCancel];
}

- (void)saveClicked:(id)sender {
    // The Save button is momentary and refuses first responder, so a mouse click
    // does not end an in-progress header cell edit. Force it to commit into
    // _headers before we read them, or the last-typed header is lost.
    [_window makeFirstResponder:nil];
    NSString *name =
        [_nameField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *url =
        [_urlField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *failure = nil;
    if (name.length == 0) {
        failure = NSLocalizedStringWithDefaultValue(@"AIModelEditor.ModelRequired", nil, [NSBundle mainBundle], @"Model is required.", @"Validation error when the model name is empty");
    } else if (url.length == 0) {
        failure = NSLocalizedStringWithDefaultValue(@"AIModelEditor.URLRequired", nil, [NSBundle mainBundle], @"URL is required.", @"Validation error when the URL is empty");
    } else if (_contextField.integerValue <= 0) {
        failure = NSLocalizedStringWithDefaultValue(@"AIModelEditor.ContextTokensPositive", nil, [NSBundle mainBundle], @"Context tokens must be greater than zero.", @"Validation error when context tokens is not positive");
    } else if (_responseField.integerValue <= 0) {
        failure = NSLocalizedStringWithDefaultValue(@"AIModelEditor.MaxResponseTokensPositive", nil, [NSBundle mainBundle], @"Max response tokens must be greater than zero.", @"Validation error when max response tokens is not positive");
    } else if (_nameIsTaken && _nameIsTaken(name)) {
        failure = NSLocalizedStringWithDefaultValue(@"AIModelEditor.NamesUnique", nil, [NSBundle mainBundle], @"Manual model names must be unique.", @"Validation error when a manual model name is already taken");
    }
    // Validate custom headers here rather than in the per-cell delegate: the Save
    // button click ends the active cell edit, so a per-cell alert would race the
    // sheet teardown. Blank-name rows are dropped on save, so skip them.
    if (!failure) {
        for (NSDictionary *entry in _headers) {
            NSString *headerName = [entry[@"name"] isKindOfClass:NSString.class] ? entry[@"name"] : @"";
            headerName = [headerName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (headerName.length == 0) {
                continue;
            }
            NSString *headerValue = [entry[@"value"] isKindOfClass:NSString.class] ? entry[@"value"] : @"";
            if (![AICustomHeaders isValidName:headerName]) {
                failure = [NSString stringWithFormat:
                           NSLocalizedStringWithDefaultValue(@"AIModelEditor.InvalidHeaderName", nil, [NSBundle mainBundle], @"Custom header name “%@” is not valid. Use only RFC 7230 token "
                           @"characters (letters, digits, and any of !#$%%&'*+-.^_`|~).", @"Validation error for an invalid custom HTTP header name; %@ is the name"), headerName];
                break;
            }
            if (![AICustomHeaders isValidValue:headerValue]) {
                failure = [NSString stringWithFormat:
                           NSLocalizedStringWithDefaultValue(@"AIModelEditor.InvalidHeaderValue", nil, [NSBundle mainBundle], @"The value for custom header “%@” must not contain newline or "
                           @"null characters.", @"Validation error for an invalid custom HTTP header value; %@ is the header name"), headerName];
                break;
            }
        }
    }
    if (failure) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedStringWithDefaultValue(@"AIModelEditor.InvalidModelTitle", nil, [NSBundle mainBundle], @"Invalid Manual AI Model", @"Title of alert shown when a manual AI model fails validation");
        alert.informativeText = failure;
        [alert beginSheetModalForWindow:_window completionHandler:^(NSModalResponse returnCode) {}];
        return;
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[kAIManualModelIDKey] = _base[kAIManualModelIDKey] ?: NSUUID.UUID.UUIDString;
    result[kAIManualModelNameKey] = name;
    result[kAIManualModelURLKey] = url;
    result[kAIManualModelAPIKey] = @(_apiPopup.selectedItem.tag);
    result[kAIManualModelContextWindowTokensKey] = @(_contextField.integerValue);
    result[kAIManualModelMaxResponseTokensKey] = @(_responseField.integerValue);
    result[kAIManualModelVectorStoreKey] = @(_vectorStorePopup.selectedItem.tag);
    result[kAIManualModelSupportsTemperatureKey] =
        @(_supportsTemperatureButton.state == NSControlStateValueOn);
    result[kAIManualModelConfigurableThinkingKey] =
        @(_configurableThinkingButton.state == NSControlStateValueOn);
    for (NSString *key in _featureButtons) {
        result[key] = @(_featureButtons[key].state == NSControlStateValueOn);
    }
    result[kAIManualModelCustomHeadersKey] = [self nonEmptyHeaders];
    _result = result;
    [_window.sheetParent endSheet:_window returnCode:NSModalResponseOK];
}

@end

@interface GeneralPreferencesViewController () <iTermManualAIModelsPanelDelegate>
@end

@implementation GeneralPreferencesViewController {
    BOOL _awoken;
    // Retained while their sheets are presented (table delegate/dataSource are
    // weak, so nothing else keeps these alive).
    iTermManualAIModelsPanelController *_manualModelsPanel;
    iTermManualAIModelEditorController *_manualModelEditor;
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
    NSMutableArray<NSSecureTextField *> *_aiAPIKeySheetFields;

    IBOutlet NSPopUpButton *_promptSelector;
    IBOutlet NSTextView *_aiPrompt;
    IBOutlet NSImageView *_aiPromptWarning;  // Image shown when prompt lacks \(ai.prompt)

    BOOL _customScriptsFolderDidChange;

    IBOutlet NSButton *_resetAIPrompt;
    IBOutlet NSTextField *_aiTimeout;
    IBOutlet NSButton *_automaticallyUpdateAIModels;
    IBOutlet NSButton *_updateAIModelsNowButton;

    IBOutlet NSTextField *_aiPluginLabel;
    IBOutlet NSButton *_enableAI;
    IBOutlet NSTextField *_pluginStatus;
    IBOutlet NSButton *_installPluginButton;
    BOOL _pluginOK;

    IBOutlet NSButton *_useRecommendedModel;
    IBOutlet NSButton *_manualAIConfiguration;
    IBOutlet NSPopUpButton *_aiVendor;
    IBOutlet NSButton *_aiSafetyCheck;
    IBOutlet NSButton *_aiZeroDataRetention;

    IBOutlet NSTextField *_checkTerminalStateLabel; // Check Terminal State
    IBOutlet NSPopUpButton *_checkTerminalStateButton;
    IBOutlet NSTextField *_runCommandsLabel; // Run Commands
    IBOutlet NSPopUpButton *_runCommandsButton;
    IBOutlet NSTextField *_viewHistoryLabel; // View History
    IBOutlet NSPopUpButton *_viewHistoryButton;
    IBOutlet NSTextField *_writeToClipboardLabel; // Write to the Clipboard
    IBOutlet NSPopUpButton *_writeToClipboardButton;
    IBOutlet NSTextField *_controlTerminalLabel; // Control Terminal
    IBOutlet NSPopUpButton *_controlTerminalButton;
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

    IBOutlet NSTextField *_mainAIAPIKeyHint;
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
                   displayName:NSLocalizedStringWithDefaultValue(@"GeneralPrefs.InstantReplayMemoryLimit", nil, [NSBundle mainBundle], @"Instant Replay memory usage limit", @"Label for the Instant Replay memory limit setting")
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
                   displayName:NSLocalizedStringWithDefaultValue(@"GeneralPrefs.APIAuthMethod", nil, [NSBundle mainBundle], @"Authentication method for Python API", @"Label for the Python API authentication method setting")
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
        [iTermWarning showWarningWithTitle:NSLocalizedStringWithDefaultValue(@"GeneralPrefs.RestartRequired", nil, [NSBundle mainBundle], @"You must restart iTerm2 for this change to take effect.", @"Warning that a setting change requires restarting iTerm2")
                                   actions:@[ iTermLocalizedOK() ]
                                identifier:nil
                               silenceable:kiTermWarningTypePersistent
                                    window:nil];
    };


    [self addViewToSearchIndex:_advancedGPUPrefsButton
                   displayName:NSLocalizedStringWithDefaultValue(@"GeneralPrefs.AdvancedGPUSettings", nil, [NSBundle mainBundle], @"Advanced GPU settings", @"Search index display name for advanced GPU settings")
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
                   displayName:NSLocalizedStringWithDefaultValue(@"GeneralPrefs.CustomScriptsFolder", nil, [NSBundle mainBundle], @"Custom folder for Python API scripts", @"Label for the custom scripts folder setting")
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
                   displayName:NSLocalizedStringWithDefaultValue(@"GeneralPrefs.NewWindowPlacement", nil, [NSBundle mainBundle], @"New window placement", @"Label for the new window placement setting")
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
            displayName:NSLocalizedStringWithDefaultValue(@"GeneralPrefs.TmuxPauseAgeLimit", nil, [NSBundle mainBundle], @"Pause a tmux pane if it would take more than this many seconds to catch up.", @"Label for the tmux pause age limit setting")
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
                   displayName:NSLocalizedStringWithDefaultValue(@"GeneralPrefs.ManageAIAPIKeys", nil, [NSBundle mainBundle], @"Manage AI API Keys", @"Title for the AI API keys management UI")
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

    info = [self defineControl:_controlTerminalButton
                           key:kPreferenceKeyAIPermissionControlTerminal
                   relatedView:_controlTerminalLabel
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
                   displayName:NSLocalizedStringWithDefaultValue(@"GeneralPrefs.InstallAIPlugin", nil, [NSBundle mainBundle], @"Install AI Plugin", @"Search index display name for the install AI plugin action")
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
            displayName:NSLocalizedStringWithDefaultValue(@"GeneralPrefs.AITimeout", nil, [NSBundle mainBundle], @"AI timeout", @"Label for the AI request timeout setting")
                   type:kPreferenceInfoTypeIntegerTextField];

    [self defineControl:_aiSafetyCheck
                    key:kPreferenceKeyAISafetyCheck
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_aiZeroDataRetention
                    key:kPreferenceKeyAIZeroDataRetention
            relatedView:nil
                   type:kPreferenceInfoTypeCheckbox];

    info = [self defineControl:_automaticallyUpdateAIModels
                           key:kPreferenceKeyAIModelUpdatesEnabled
                   relatedView:nil
                          type:kPreferenceInfoTypeCheckbox];
    info.onChange = ^{
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if ([iTermPreferences boolForKey:kPreferenceKeyAIModelUpdatesEnabled]) {
            // Ticking the visible, labeled checkbox is itself consent to the
            // network fetch on this machine, so record it and skip the one-time
            // consent modal here. A different machine that syncs this preference
            // on still confirms via the modal (the existing per-machine logic).
            [iTermUserDefaults setAiModelCatalogUpdateConsent:iTermAIModelCatalogUpdateConsentGranted];
        }
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

// The single source of per-prompt metadata: the preference key plus,
// for prompts whose template must interpolate a feature-supplied
// variable, that variable's bare name (in the "ai" scope) and a
// sentence explaining what replaces it. The switch is exhaustive so
// adding a prompt forces this method to be updated; everything else
// (warning logic, reset, editor binding) derives from it. The
// \(ai.<name>) wrapper and the shared "must contain" sentence are
// composed once in updateAIPromptWarning. Out params may be NULL.
- (NSString *)keyForCurrentlySelectedAIPromptGetting:(NSString **)variableName
                                  variableExplanation:(NSString **)variableExplanation {
    NSString *name = nil;
    NSString *explanation = nil;
    NSString *key;
    switch ((iTermAIPrompt)_promptSelector.selectedTag) {
        case iTermAIPromptEngageAI:
            name = iTermAIPromptVariablePrompt;
            explanation = NSLocalizedStringWithDefaultValue(@"GeneralPrefs.PromptEngageExplanation", nil, [NSBundle mainBundle], @"The query you enter will replace it when speaking to the AI. For example: “Write a unix command to \\(ai.prompt).”", @"Explanation of the ai.prompt variable in the AI prompt editor");
            key = kPreferenceKeyAIPrompt;
            break;
        case iTermAIPromptAIChat:
            key = kPreferenceKeyAIPromptAIChat;
            break;
        case iTermAIPromptAIChatReadOnlyTerminal:
            key = kPreferenceKeyAIPromptAIChatReadOnlyTerminal;
            break;
        case iTermAIPromptAIChatReadWriteTerminal:
            key = kPreferenceKeyAIPromptAIChatReadWriteTerminal;
            break;
        case iTermAIPromptAIChatBrowser:
            key = kPreferenceKeyAIPromptAIChatBrowser;
            break;
        case iTermAIPromptAIChatReadOnlyTerminalBrowser:
            key = kPreferenceKeyAIPromptAIChatReadOnlyTerminalBrowser;
            break;
        case iTermAIPromptAIChatReadWriteTerminalBrowser:
            key = kPreferenceKeyAIPromptAIChatReadWriteTerminalBrowser;
            break;
        case iTermAIPromptAIChatOrchestration:
            key = kPreferenceKeyAIPromptAIChatOrchestration;
            break;
        case iTermAIPromptCodeReviewSystem:
            key = kPreferenceKeyAIPromptCodeReviewSystem;
            break;
        case iTermAIPromptChatIcon:
            name = iTermAIPromptVariableSubject;
            explanation = NSLocalizedStringWithDefaultValue(@"GeneralPrefs.PromptChatIconExplanation", nil, [NSBundle mainBundle], @"The chat’s title will replace it when speaking to the AI.", @"Explanation of the ai.subject variable in the chat-icon prompt editor");
            key = kPreferenceKeyAIPromptChatIcon;
            break;
    }
    if (variableName) {
        *variableName = name;
    }
    if (variableExplanation) {
        *variableExplanation = explanation;
    }
    return key;
}

- (NSString *)keyForCurrentlySelectedAIPrompt {
    return [self keyForCurrentlySelectedAIPromptGetting:NULL variableExplanation:NULL];
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

- (NSString *)currentEconomyModelName {
    NSString *name = [self stringForKey:kPreferenceKeyAIEconomyModelName];
    return name.length > 0 ? name : nil;
}

- (void)setCurrentEconomyModelName:(NSString *)name {
    [self setString:name ?: @"" forKey:kPreferenceKeyAIEconomyModelName];
}

- (NSDictionary *)manualAIModelConfigurationNamed:(NSString *)name
                                inConfigurations:(NSArray<NSDictionary *> *)configurations {
    if (name.length == 0) {
        return nil;
    }
    for (NSDictionary *configuration in configurations) {
        NSString *configuredName = configuration[kAIManualModelNameKey];
        if ([configuredName isKindOfClass:NSString.class] &&
            [configuredName isEqualToString:name]) {
            return configuration;
        }
    }
    return nil;
}

- (iTermAIVendor)providerForManualAIModelConfiguration:(NSDictionary *)configuration {
    const iTermAIAPI api = (iTermAIAPI)[self manualAIModelConfiguration:configuration
                                                          integerForKey:kAIManualModelAPIKey
                                                               fallback:iTermAIAPIChatCompletions];
    // Route through the same resolver LLMMetadata uses at request time so the
    // Settings label never disagrees with how the model is actually classified.
    NSString *modelName = configuration[kAIManualModelNameKey] ?: @"";
    NSString *url = configuration[kAIManualModelURLKey] ?: @"";
    return [iTermLLMMetadata vendorForManualModelWithAPI:api url:url modelName:modelName];
}

- (NSString *)defaultAIModelTitleForManualConfiguration:(NSDictionary *)configuration {
    NSString *name = configuration[kAIManualModelNameKey] ?: NSLocalizedStringWithDefaultValue(@"AIManualModels.UntitledModel", nil, [NSBundle mainBundle], @"Untitled model", @"Placeholder name for a manual AI model with no name");
    iTermAIVendor provider = [self providerForManualAIModelConfiguration:configuration];
    return [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"GeneralPrefs.DefaultModelManualTitle", nil, [NSBundle mainBundle], @"Manual: %1$@ — %2$@", @"Menu title for a manual AI model; first %@ is the model name, second is the provider"),
            name,
            [self aiAPIKeyProviderNameForVendor:provider]];
}

- (void)setupDefaultAIModelSelector {
    // The popup's placement/size, the adjacent label text, and whether the
    // "use recommended model" checkbox is shown all live in the XIB. Here we
    // only wire behavior (action + dynamic menu contents).
    _aiVendor.target = self;
    _aiVendor.action = @selector(defaultAIModelPopupDidChange:);

    [self addViewToSearchIndex:_aiVendor
                   displayName:NSLocalizedStringWithDefaultValue(@"GeneralPrefs.DefaultModelForNewChats", nil, [NSBundle mainBundle], @"Default model for new AI chats", @"Search index display name for the default AI model setting")
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
    [self updateAIAPIKeyHint];
}

- (void)updateAIAfterDefaultModelChange {
    [self aiModelDidChange];
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
    // A model cannot be both the default and the economy model. If the model
    // becoming the default is the current economy model, drop the economy
    // designation so the invariant holds however the default was chosen (panel
    // toggle or the default-model popup).
    NSString *name = configuration[kAIManualModelNameKey];
    if ([name isKindOfClass:NSString.class] &&
        [name isEqualToString:[self currentEconomyModelName]]) {
        [self setCurrentEconomyModelName:nil];
    }
    [self setBool:NO forKey:kPreferenceKeyUseRecommendedAIModel];
    [self applyManualAIModelConfigurationToDefaults:configuration];
    [self updateAIAfterDefaultModelChange];
}

- (IBAction)updateAIModels:(id)sender {
    _updateAIModelsNowButton.enabled = NO;
    __weak __typeof(self) weakSelf = self;
    [[iTermAIModelCatalogUpdater instance] checkNowWithCompletion:^(AIModelCatalogUpdateOutcome outcome) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        // Recompute enabled state (this re-enables the button unless AI was
        // turned off while the check was running).
        [strongSelf updateAIEnabled];
        [strongSelf presentAIModelUpdateOutcome:outcome];
    }];
}

- (void)presentAIModelUpdateOutcome:(AIModelCatalogUpdateOutcome)outcome {
    NSString *title;
    switch (outcome) {
        case AIModelCatalogUpdateOutcomeUpdated:
            title = NSLocalizedStringWithDefaultValue(@"GeneralPrefs.ModelUpdateDownloaded", nil, [NSBundle mainBundle], @"A newer AI model list was downloaded. It will take effect the next time you launch iTerm2.", @"Alert shown after a newer AI model list was downloaded");
            break;
        case AIModelCatalogUpdateOutcomeUpToDate:
            title = NSLocalizedStringWithDefaultValue(@"GeneralPrefs.ModelUpdateUpToDate", nil, [NSBundle mainBundle], @"Your AI model list is already up to date.", @"Alert shown when the AI model list is already current");
            break;
        case AIModelCatalogUpdateOutcomeFailed:
            title = NSLocalizedStringWithDefaultValue(@"GeneralPrefs.ModelUpdateFailed", nil, [NSBundle mainBundle], @"Couldn’t check for AI model updates. Please try again later.", @"Alert shown when checking for AI model updates fails");
            break;
        case AIModelCatalogUpdateOutcomeDisabled:
            title = NSLocalizedStringWithDefaultValue(@"GeneralPrefs.ModelUpdateDisabled", nil, [NSBundle mainBundle], @"AI model updates are turned off in Advanced Settings (the update URL is empty).", @"Alert shown when AI model updates are disabled");
            break;
        case AIModelCatalogUpdateOutcomeNotEnabled:
            title = NSLocalizedStringWithDefaultValue(@"GeneralPrefs.ModelUpdateNotEnabled", nil, [NSBundle mainBundle], @"Turn on AI features before checking for model updates.", @"Alert shown when AI is not enabled but the user checks for model updates");
            break;
        case AIModelCatalogUpdateOutcomeBusy:
            title = NSLocalizedStringWithDefaultValue(@"GeneralPrefs.ModelUpdateBusy", nil, [NSBundle mainBundle], @"A check for AI model updates is already in progress.", @"Alert shown when an AI model update check is already running");
            break;
        case AIModelCatalogUpdateOutcomeDeclined:
            // The user just dismissed or declined the consent modal; a second
            // alert would be redundant.
            return;
    }
    [iTermWarning showWarningWithTitle:title
                               actions:@[ iTermLocalizedOK() ]
                            identifier:nil
                           silenceable:kiTermWarningTypePersistent
                                window:self.view.window];
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
    // The button title lives in the XIB; here we only toggle enabled state.
    _manualAIConfiguration.enabled = allowed;
    _aiVendor.enabled = allowed;
    [self reloadDefaultAIModelPopup];
}

- (void)updateAIModelFromVendor {
    iTermAIModel *model = [iTermAIModel modelFromSettings];
    if (model) {
        [self setString:model.name forKey:kPreferenceKeyAIModel];
    }
}

- (void)aiModelDidChange {
    NSString *model = [self stringForKey:kPreferenceKeyAIModel];
    // Ignore it if it doesn't change because this is called when the view is closed.
    if (!model || [model isEqualToString:_lastModel]) {
        return;
    }
    _lastModel = [self stringForKey:kPreferenceKeyAIModel];

    const iTermAIAPI api = [AIMetadata.instance apiForModel:model
                                                   fallback:[self unsignedIntegerForKey:kPreferenceKeyAITermAPI]];
    [self setObject:@(api) forKey:kPreferenceKeyAITermAPI];

    NSNumber *tokens = [AIMetadata.instance contextWindowTokensForModelName:model];
    if (tokens) {
        [self setObject:tokens forKey:kPreferenceKeyAITokenLimit];
    }
    NSNumber *responseTokens = [AIMetadata.instance responseTokenLimitForModelName:model];
    if (responseTokens) {
        [self setObject:responseTokens forKey:kPreferenceKeyAIResponseTokenLimit];
    }
    NSString *url = [AIMetadata.instance urlForModelName:model];
    if (url) {
        [self setObject:url forKey:kPreferenceKeyAITermURL];
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
    }
}

- (void)validatePlugin {
    DLog(@"validatePlugin");
    _pluginStatus.stringValue = NSLocalizedStringWithDefaultValue(@"GeneralPrefs.CheckingPluginStatus", nil, [NSBundle mainBundle], @"Checking plugin status…", @"Status shown while the AI plugin is being validated");
    __weak __typeof(self) weakSelf = self;
    [iTermAITermGatekeeper validatePlugin:^(NSString * _Nullable problem) {
        [weakSelf setPluginProblem:problem];
    }];
}

- (void)setPluginProblem:(NSString *)problem {
    DLog(@"problem=%@", problem);
    if (problem) {
        _pluginStatus.stringValue = problem;
        _installPluginButton.title = NSLocalizedStringWithDefaultValue(@"GeneralPrefs.InstallEllipsis", nil, [NSBundle mainBundle], @"Install…", @"Title of button that installs the AI plugin");
        _installPluginButton.action = @selector(installPlugin:);
        [_installPluginButton sizeToFit];
        _installPluginButton.enabled = [iTermAdvancedSettingsModel generativeAIAllowed];
        _pluginOK = NO;
        __weak __typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf validatePlugin];
        });
    } else {
        _pluginStatus.stringValue = NSLocalizedStringWithDefaultValue(@"GeneralPrefs.PluginInstalledWorking", nil, [NSBundle mainBundle], @"Plugin installed and working ✅", @"Status shown when the AI plugin is installed and working");
        _installPluginButton.title = NSLocalizedStringWithDefaultValue(@"GeneralPrefs.RevealInFinder", nil, [NSBundle mainBundle], @"Reveal in Finder", @"Title of button that reveals the plugin in Finder");
        [_installPluginButton sizeToFit];
        _installPluginButton.action = @selector(revealPlugin:);
        _installPluginButton.enabled = YES;
        _pluginOK = YES;
    }
    [self updateAIEnabled];
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
    return iTermAIVendorProviderName(vendor);
}

- (void)updateAIEnabled {
    _enableAI.enabled = _pluginOK;

    const BOOL allowed = _pluginOK && [iTermAITermGatekeeper allowed];
    _openAIAPIKey.enabled = allowed;
    _aiPrompt.editable = allowed;
    _resetAIPrompt.enabled = allowed;
    _enableAI.enabled = [iTermAdvancedSettingsModel generativeAIAllowed];
    _aiSafetyCheck.enabled = allowed;
    _automaticallyUpdateAIModels.enabled = allowed;
    _updateAIModelsNowButton.enabled = allowed;

    [self updateCoarseAIModelSettingsEnabled];
}

// The API key that authorizes the default model is not obvious: it is the stored
// key for the model's vendor, and for a manual model that vendor is inferred from
// its API, URL, and name (see issue 12975). Spell it out under the model popup,
// but only when a manual model is the default: a built-in vendor selection makes
// the key obvious, so hide it then. (The manual model editor has its own hint.)
- (void)updateAIAPIKeyHint {
    if (!_mainAIAPIKeyHint) {
        return;
    }
    NSString *identifier = _aiVendor.selectedItem.representedObject;
    if ([self providerFromDefaultAIModelIdentifier:identifier] != nil) {
        _mainAIAPIKeyHint.hidden = YES;
        return;
    }
    const iTermAIVendor vendor = [self vendorForSelectedDefaultAIModel];
    _mainAIAPIKeyHint.hidden = NO;
    if (iTermAIVendorHasEnterableKey(vendor)) {
        _mainAIAPIKeyHint.stringValue =
            [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"AIKeyHint.Authorizes", nil, [NSBundle mainBundle], @"Authorizes with your %@ API key.", @"Hint telling the user which provider's API key authorizes the model; %@ is the provider name"),
             iTermAIVendorProviderName(vendor)];
    } else {
        // No key can be configured: self-hosted (Llama) or Apple Intelligence
        // (which runs on-device or via Private Cloud Compute).
        _mainAIAPIKeyHint.stringValue = NSLocalizedStringWithDefaultValue(@"AIKeyHint.NoKeyUsed", nil, [NSBundle mainBundle], @"No API key is used.", @"Hint shown when the selected model needs no API key");
    }
}

// The vendor whose stored key authorizes the model currently selected in the
// default-model popup. Mirrors the routing in defaultAIModelPopupDidChange: so
// the hint agrees with what actually gets used.
- (iTermAIVendor)vendorForSelectedDefaultAIModel {
    NSString *identifier = _aiVendor.selectedItem.representedObject;
    NSNumber *providerNumber = [self providerFromDefaultAIModelIdentifier:identifier];
    if (providerNumber) {
        return (iTermAIVendor)providerNumber.unsignedIntegerValue;
    }
    NSString *manualName = [self manualModelNameFromDefaultAIModelIdentifier:identifier];
    NSDictionary *configuration =
        [self manualAIModelConfigurationNamed:manualName
                             inConfigurations:[self mutableManualAIModelConfigurations]];
    if (configuration) {
        return [self providerForManualAIModelConfiguration:configuration];
    }
    return (iTermAIVendor)[self unsignedIntegerForKey:kPreferenceKeyAIVendor];
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
    NSString *variableName = nil;
    NSString *explanation = nil;
    NSString *key = [self keyForCurrentlySelectedAIPromptGetting:&variableName
                                             variableExplanation:&explanation];
    NSString *requiredVariable =
        variableName ? [NSString stringWithFormat:@"\\(ai.%@)", variableName] : nil;
    if (requiredVariable && ![[self stringForKey:key] containsString:requiredVariable]) {
        _aiPromptWarning.toolTip =
            [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"GeneralPrefs.PromptMustContain", nil, [NSBundle mainBundle], @"The prompt must contain the substring %1$@. %2$@", @"Tooltip warning that a prompt is missing a required variable; first %@ is the variable, second is an explanation"),
             requiredVariable, explanation];
        _aiPromptWarning.alphaValue = 1.0;
    } else {
        // Clear the tooltip as well as fading: alpha 0 doesn't remove
        // the view from hit-testing, so a stale tooltip would still
        // answer hover/click on the invisible warning.
        _aiPromptWarning.toolTip = nil;
        _aiPromptWarning.alphaValue = 0.0;
    }
}

- (NSString *)alwaysOpenLegend {
    if ([iTermScriptsMenuController autoLaunchFolderExists]) {
        return NSLocalizedStringWithDefaultValue(@"GeneralPrefs.AlwaysOpenAutoLaunch", nil, [NSBundle mainBundle], @"The presence of auto-launch scripts disables opening a window at startup.", @"Explains why opening a window at startup is disabled");
    }
    if ([[[iTermHotKeyController sharedInstance] profileHotKeys] count] > 0) {
        return NSLocalizedStringWithDefaultValue(@"GeneralPrefs.AlwaysOpenHotkey", nil, [NSBundle mainBundle], @"The existence of hotkey windows disables opening a window at startup.", @"Explains why opening a window at startup is disabled");
    }
    if ([[[iTermBuriedSessions sharedInstance] buriedSessions] count] > 0) {
        return NSLocalizedStringWithDefaultValue(@"GeneralPrefs.AlwaysOpenBuried", nil, [NSBundle mainBundle], @"The existence of buried sessions disables opening a window at startup.", @"Explains why opening a window at startup is disabled");
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
    alert.messageText = NSLocalizedStringWithDefaultValue(@"GeneralPrefs.ManageAIAPIKeys", nil, [NSBundle mainBundle], @"Manage AI API Keys", @"Title for the AI API keys management UI");
    alert.informativeText = NSLocalizedStringWithDefaultValue(@"GeneralPrefs.KeysStoredInKeychain", nil, [NSBundle mainBundle], @"Keys are stored securely in the macOS Keychain.", @"Explanation that API keys are stored in the Keychain");
    [alert addButtonWithTitle:iTermLocalizedOK()];
    [alert addButtonWithTitle:iTermLocalizedCancel()];

    NSArray<NSNumber *> *vendors = [self aiAPIKeyProviderVendors];
    const CGFloat width = 620;
    const CGFloat rowHeight = 36;
    const CGFloat topPadding = 10;
    const CGFloat bottomPadding = 10;
    const CGFloat labelWidth = 90;
    const CGFloat fieldX = labelWidth + 14;
    const CGFloat fieldWidth = width - fieldX;
    NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0,
                                                                0,
                                                                width,
                                                                topPadding + bottomPadding +
                                                                rowHeight * vendors.count)];
    _aiAPIKeySheetFields = [NSMutableArray array];
    // The value each field was prefilled with, so OK only rewrites keys the
    // user actually changed. Without this, a field that prefilled blank because
    // the keychain read failed (locked/denied/prompt dismissed) would, on OK,
    // overwrite the still-good stored key with an empty string.
    NSMutableArray<NSString *> *initialFieldValues = [NSMutableArray array];

    for (NSInteger i = 0; i < vendors.count; i++) {
        iTermAIVendor vendor = (iTermAIVendor)vendors[i].unsignedIntegerValue;
        NSString *name = [self aiAPIKeyProviderNameForVendor:vendor];
        CGFloat y = bottomPadding + rowHeight * (vendors.count - 1 - i);

        NSTextField *label = [NSTextField labelWithString:name];
        label.frame = NSMakeRect(0, y + 5, labelWidth, 22);
        label.alignment = NSTextAlignmentRight;
        [accessory addSubview:label];

        NSSecureTextField *field =
            [[NSSecureTextField alloc] initWithFrame:NSMakeRect(fieldX, y + 2, fieldWidth, 24)];
        field.usesSingleLineMode = YES;
        field.editable = YES;
        field.selectable = YES;
        field.placeholderString = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"GeneralPrefs.APIKeyPlaceholder", nil, [NSBundle mainBundle], @"%@ API key", @"Placeholder for an API key field; %@ is the provider name"), name];
        field.stringValue = [AITermControllerObjC apiKeyForVendor:vendor] ?: @"";
        [accessory addSubview:field];
        [_aiAPIKeySheetFields addObject:field];
        [initialFieldValues addObject:field.stringValue];
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
                    NSString *newValue = self->_aiAPIKeySheetFields[i].stringValue ?: @"";
                    NSString *initialValue = i < initialFieldValues.count ? initialFieldValues[i] : @"";
                    // Only write vendors the user actually changed. Leaving a
                    // field at its prefilled value (including a blank left blank
                    // because the keychain read failed) must not touch the key.
                    if ([newValue isEqualToString:initialValue]) {
                        continue;
                    }
                    iTermAIVendor vendor = (iTermAIVendor)vendors[i].unsignedIntegerValue;
                    [AITermControllerObjC setAPIKey:newValue forVendor:vendor];
                }
                break;
            }
            case NSAlertSecondButtonReturn: {
                break;
            }
        }
        self->_aiAPIKeySheetFields = nil;
    }];
}

#pragma mark - NSTextFieldDelegate

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    [super controlTextDidEndEditing:notification];
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
            if (![entry isKindOfClass:NSDictionary.class]) {
                continue;
            }
            NSDictionary *dict = (NSDictionary *)entry;
            // Drop entries whose required fields are not strings. This pref is
            // non-NoSync (it can round-trip through synced/Dropbox prefs or be
            // hand-edited), so a name/url that decodes as an NSNumber would
            // later crash the paths that call -isEqualToString: on it.
            if (![dict[kAIManualModelNameKey] isKindOfClass:NSString.class] ||
                ![dict[kAIManualModelURLKey] isKindOfClass:NSString.class]) {
                continue;
            }
            [result addObject:[entry mutableCopy]];
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
    NSString *name = configuration[kAIManualModelNameKey] ?: NSLocalizedStringWithDefaultValue(@"AIManualModels.UntitledModel", nil, [NSBundle mainBundle], @"Untitled model", @"Placeholder name for a manual AI model with no name");
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

#pragma mark - iTermManualAIModelsPanelDelegate

- (void)manualModelsPanelDone:(iTermManualAIModelsPanelController *)panel {
    [self.view.window endSheet:panel.window returnCode:NSModalResponseOK];
}

- (void)manualModelsPanelAdd:(iTermManualAIModelsPanelController *)panel {
    [self presentManualModelEditorForPanel:panel base:nil isEditing:NO editingIndex:-1];
}

- (void)manualModelsPanel:(iTermManualAIModelsPanelController *)panel editRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)panel.configurations.count) {
        NSBeep();
        return;
    }
    [self presentManualModelEditorForPanel:panel
                                      base:panel.configurations[(NSUInteger)row]
                                 isEditing:YES
                              editingIndex:row];
}

- (void)manualModelsPanel:(iTermManualAIModelsPanelController *)panel duplicateRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)panel.configurations.count) {
        NSBeep();
        return;
    }
    NSMutableDictionary *copy = [panel.configurations[(NSUInteger)row] mutableCopy];
    copy[kAIManualModelIDKey] = NSUUID.UUID.UUIDString;
    copy[kAIManualModelNameKey] =
        [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"AIManualModels.CopySuffix", nil, [NSBundle mainBundle], @"%@ copy", @"Name given to a duplicated manual AI model; %@ is the original name"), copy[kAIManualModelNameKey] ?: NSLocalizedStringWithDefaultValue(@"AIManualModels.ManualModelDefault", nil, [NSBundle mainBundle], @"Manual model", @"Default name for a manual AI model with no name")];
    [self presentManualModelEditorForPanel:panel base:copy isEditing:NO editingIndex:-1];
}

- (void)manualModelsPanel:(iTermManualAIModelsPanelController *)panel deleteRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)panel.configurations.count) {
        NSBeep();
        return;
    }
    NSString *deletedName = panel.configurations[(NSUInteger)row][kAIManualModelNameKey];
    const BOOL deletingDefault = [deletedName isKindOfClass:NSString.class] &&
        [deletedName isEqualToString:[self currentDefaultManualModelName]];
    const BOOL deletingEconomy = [deletedName isKindOfClass:NSString.class] &&
        [deletedName isEqualToString:[self currentEconomyModelName]];
    [panel.configurations removeObjectAtIndex:(NSUInteger)row];
    const NSInteger nextIndex = MIN(row, (NSInteger)panel.configurations.count - 1);
    [self saveManualAIModelConfigurations:panel.configurations];
    if (deletingEconomy) {
        [self setCurrentEconomyModelName:nil];
    }
    if (deletingDefault) {
        [self fallbackAfterDeletingDefaultManualModel:panel.configurations selectedIndex:nextIndex];
    } else {
        [self reloadDefaultAIModelPopup];
        [self updateAIEnabled];
    }
    panel.defaultModelName = [self currentDefaultManualModelName];
    panel.economyModelName = [self currentEconomyModelName];
    [panel reloadSelectingIndex:nextIndex];
}

- (void)manualModelsPanel:(iTermManualAIModelsPanelController *)panel setDefaultRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)panel.configurations.count) {
        NSBeep();
        return;
    }
    [self saveManualAIModelConfigurations:panel.configurations];
    NSString *name = panel.configurations[(NSUInteger)row][kAIManualModelNameKey];
    const BOOL alreadyDefault = [name isKindOfClass:NSString.class] &&
        [name isEqualToString:[self currentDefaultManualModelName]];
    if (alreadyDefault) {
        // Toggle off: fall back to the provider's recommended model.
        [self selectProviderAsDefaultForNewChats:(iTermAIVendor)[self unsignedIntegerForKey:kPreferenceKeyAIVendor]];
    } else {
        // selectManualConfigurationAsDefaultForNewChats: drops the economy
        // designation if this row was the economy model (default and economy
        // are mutually exclusive).
        [self selectManualConfigurationAsDefaultForNewChats:panel.configurations[(NSUInteger)row]];
    }
    panel.defaultModelName = [self currentDefaultManualModelName];
    panel.economyModelName = [self currentEconomyModelName];
    [panel reloadSelectingIndex:row];
}

- (void)manualModelsPanel:(iTermManualAIModelsPanelController *)panel setEconomyRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)panel.configurations.count) {
        NSBeep();
        return;
    }
    [self saveManualAIModelConfigurations:panel.configurations];
    NSString *name = panel.configurations[(NSUInteger)row][kAIManualModelNameKey];
    if (![name isKindOfClass:NSString.class] || name.length == 0) {
        NSBeep();
        return;
    }
    const BOOL alreadyEconomy = [name isEqualToString:[self currentEconomyModelName]];
    if (alreadyEconomy) {
        // Toggle off.
        [self setCurrentEconomyModelName:nil];
    } else {
        // The economy model must be distinct from the default model. The leaf
        // toggle is disabled for the default row (see updateSegmentEnabled), so
        // this is just defense in depth: ignore the request rather than create
        // a model that is both.
        if ([name isEqualToString:[self currentDefaultManualModelName]]) {
            return;
        }
        [self setCurrentEconomyModelName:name];
    }
    panel.economyModelName = [self currentEconomyModelName];
    [panel reloadSelectingIndex:row];
}

// Presents the add/edit editor as a child sheet of the manager panel and, on
// save, mutates + persists the panel's configurations and reloads its table.
- (void)presentManualModelEditorForPanel:(iTermManualAIModelsPanelController *)panel
                                    base:(NSDictionary *)base
                               isEditing:(BOOL)isEditing
                            editingIndex:(NSInteger)editingIndex {
    NSDictionary *effectiveBase = base ?: [self defaultManualAIModelConfiguration];
    iTermManualAIModelEditorController *editor =
        [[iTermManualAIModelEditorController alloc] initWithConfiguration:effectiveBase
                                                               isEditing:isEditing];
    _manualModelEditor = editor;
    __weak __typeof(self) weakSelf = self;
    [editor beginSheetModalForWindow:panel.window
                         nameIsTaken:^BOOL(NSString *name) {
        for (NSInteger i = 0; i < (NSInteger)panel.configurations.count; i++) {
            if (i == editingIndex) {
                continue;
            }
            NSString *other = panel.configurations[(NSUInteger)i][kAIManualModelNameKey];
            if ([other isKindOfClass:NSString.class] && [other isEqualToString:name]) {
                return YES;
            }
        }
        return NO;
    }
                          completion:^(NSDictionary *result) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf->_manualModelEditor = nil;
        if (!result) {
            return;
        }
        NSInteger nextIndex;
        if (isEditing && editingIndex >= 0 && editingIndex < (NSInteger)panel.configurations.count) {
            NSString *oldName = panel.configurations[(NSUInteger)editingIndex][kAIManualModelNameKey];
            const BOOL editingDefault = [oldName isKindOfClass:NSString.class] &&
                [oldName isEqualToString:[strongSelf currentDefaultManualModelName]];
            // If the economy model was renamed, carry the designation to the new
            // name so the pointer doesn't dangle.
            const BOOL editingEconomy = [oldName isKindOfClass:NSString.class] &&
                [oldName isEqualToString:[strongSelf currentEconomyModelName]];
            panel.configurations[(NSUInteger)editingIndex] = [result mutableCopy];
            [strongSelf saveManualAIModelConfigurations:panel.configurations];
            if (editingEconomy) {
                NSString *newName = result[kAIManualModelNameKey];
                [strongSelf setCurrentEconomyModelName:[newName isKindOfClass:NSString.class] ? newName : nil];
            }
            if (editingDefault) {
                [strongSelf selectManualConfigurationAsDefaultForNewChats:result];
            } else {
                [strongSelf reloadDefaultAIModelPopup];
                [strongSelf updateAIEnabled];
            }
            nextIndex = editingIndex;
        } else {
            [panel.configurations addObject:[result mutableCopy]];
            nextIndex = (NSInteger)panel.configurations.count - 1;
            [strongSelf saveManualAIModelConfigurationsAndRefresh:panel.configurations];
        }
        panel.defaultModelName = [strongSelf currentDefaultManualModelName];
        panel.economyModelName = [strongSelf currentEconomyModelName];
        [panel reloadSelectingIndex:nextIndex];
    }];
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

// Legacy single-model users (no saved configurations) keep their former global
// custom headers only through LLMMetadata.legacyManualModel(). Editing anything
// in the models panel materializes a configuration, after which the legacy path
// is never consulted and the headers stop being sent. There is no config to seed
// during migration, so warn the (small, beta-only) affected population once
// before they can lose the headers.
- (void)warnAboutLegacyGlobalHeadersIfNeeded {
    NSUserDefaults *ud = [iTermUserDefaults userDefaults];
    if ([ud boolForKey:@"NoSyncAILegacyGlobalHeadersWarningShown"]) {
        return;
    }
    if (![iTermPreferences boolForKey:kPreferenceKeyAICustomHeadersEnabled]) {
        return;
    }
    id rawHeaders = [iTermPreferences objectForKey:kPreferenceKeyAICustomHeaders];
    if (![rawHeaders isKindOfClass:[NSArray class]] || [(NSArray *)rawHeaders count] == 0) {
        return;
    }
    id rawConfigs = [iTermPreferences objectForKey:kPreferenceKeyAIManualModelConfigurations];
    if ([rawConfigs isKindOfClass:[NSArray class]] && [(NSArray *)rawConfigs count] > 0) {
        return;  // Not on the legacy path; the migration handles configured models.
    }
    [ud setBool:YES forKey:@"NoSyncAILegacyGlobalHeadersWarningShown"];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = NSLocalizedStringWithDefaultValue(@"GeneralPrefs.LegacyHeadersTitle", nil, [NSBundle mainBundle], @"Custom Headers Are Now Set Per Model", @"Title of alert explaining custom headers moved to per-model settings");
    alert.informativeText = NSLocalizedStringWithDefaultValue(@"GeneralPrefs.LegacyHeadersText", nil, [NSBundle mainBundle], @"Your AI custom HTTP headers used to be a single global "
                            @"setting. They still apply to your current model, but adding "
                            @"or editing models here does not carry them over. Re-add the "
                            @"headers you need in each model’s “Custom headers” section.", @"Body of alert explaining custom headers moved to per-model settings");
    [alert runModal];
}

- (IBAction)showManualAIConfigurationPanel:(NSButton *)button {
    NSWindow *parent = self.view.window;
    if (parent == nil) {
        return;
    }
    [self warnAboutLegacyGlobalHeadersIfNeeded];
    iTermManualAIModelsPanelController *panel =
        [[iTermManualAIModelsPanelController alloc] initWithConfigurations:[self mutableManualAIModelConfigurations]
                                                          defaultModelName:[self currentDefaultManualModelName]
                                                          economyModelName:[self currentEconomyModelName]
                                                             selectedIndex:0];
    panel.delegate = self;
    _manualModelsPanel = panel;
    __weak __typeof(self) weakSelf = self;
    [parent beginSheet:panel.window completionHandler:^(NSModalResponse returnCode) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            strongSelf->_manualModelsPanel = nil;
        }
    }];
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
    [self showMessage:[iTerm2ImportExport exportAll] title:NSLocalizedStringWithDefaultValue(@"GeneralPrefs.ProblemExporting", nil, [NSBundle mainBundle], @"Problem Exporting", @"Title of alert shown when exporting settings fails")];
}

- (IBAction)importAllSettingsAndData:(id)sender {
    [self showMessage:[iTerm2ImportExport importAll] title:NSLocalizedStringWithDefaultValue(@"GeneralPrefs.ProblemImporting", nil, [NSBundle mainBundle], @"Problem Importing", @"Title of alert shown when importing settings fails")];
}

- (IBAction)eraseAllSettingsAndData:(id)sender {
    [self showMessage:[iTerm2ImportExport eraseAllWithWindow:self.view.window]
                title:NSLocalizedStringWithDefaultValue(@"GeneralPrefs.ProblemErasing", nil, [NSBundle mainBundle], @"Problem Erasing Settings and Data", @"Title of alert shown when erasing settings fails")];
}

- (void)showMessage:(NSString *)message title:(NSString *)title {
    if (!message) {
        return;
    }
    [iTermWarning showWarningWithTitle:message
                               actions:@[ iTermLocalizedOK() ]
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
        message = NSLocalizedStringWithDefaultValue(@"GeneralPrefs.WindowRestorationDisabledMessage13", nil, [NSBundle mainBundle], @"System window restoration has been disabled, which prevents iTerm2 from respecting this setting. Disable ”System Settings > Desktop & Dock > Close windows when quitting an application“ to enable window restoration.", @"Warning shown when macOS window restoration is disabled (macOS 13+)");
        action = NSLocalizedStringWithDefaultValue(@"GeneralPrefs.OpenSystemSettings", nil, [NSBundle mainBundle], @"Open System Settings", @"Button that opens System Settings");
        path = @"/System/Library/PreferencePanes/Dock.prefPane";
    } else {
        message = NSLocalizedStringWithDefaultValue(@"GeneralPrefs.WindowRestorationDisabledMessageLegacy", nil, [NSBundle mainBundle], @"System window restoration has been disabled, which prevents iTerm2 from respecting this setting. Disable System Settings > General > Close windows when quitting an app to enable window restoration.", @"Warning shown when macOS window restoration is disabled (older macOS)");
        action = NSLocalizedStringWithDefaultValue(@"GeneralPrefs.OpenSystemPreferences", nil, [NSBundle mainBundle], @"Open System Preferences", @"Button that opens System Preferences");
        path = @"/System/Library/PreferencePanes/Appearance.prefPane";
    }
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:message
                               actions:@[ action, iTermLocalizedOK() ]
                             accessory:nil
                            identifier:@"NoSyncWindowRestorationDisabled"
                           silenceable:kiTermWarningTypePersistent
                               heading:NSLocalizedStringWithDefaultValue(@"GeneralPrefs.WindowRestorationDisabledTitle", nil, [NSBundle mainBundle], @"Window Restoration Disabled", @"Title of window-restoration-disabled warning")
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
                    alert.messageText = NSLocalizedStringWithDefaultValue(@"GeneralPrefs.CopyLocalSettingsPrompt", nil, [NSBundle mainBundle], @"Copy local settings to custom folder now?", @"Prompt asking whether to copy local settings into the newly chosen custom prefs folder");
                    [alert addButtonWithTitle:iTermLocalizedCopy()];
                    [alert addButtonWithTitle:NSLocalizedStringWithDefaultValue(@"GeneralPrefs.DontCopy", nil, [NSBundle mainBundle], @"Don’t Copy", @"Button declining to copy settings")];
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
