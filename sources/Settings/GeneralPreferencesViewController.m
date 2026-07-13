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
static NSString *const kAIManualModelSupportsTemperatureKey = @"supportsTemperature";
static NSString *const kAIManualModelConfigurableThinkingKey = @"configurableThinking";

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

static BOOL iTermManualAIModelBoolValue(NSDictionary *configuration, NSString *key) {
    id value = configuration[key];
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
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
    // An out-of-range api (e.g. api: 999 from hand-edited or synced prefs) would
    // otherwise fall off the end of this non-void function (UB). No default: in
    // the switch so -Wswitch still flags a genuinely new enum value. Mirror
    // LLMMetadata's tolerance of a bad api (iTermAIAPI(rawValue:) ?? .chatCompletions).
    return @"Chat Completions";
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
@interface iTermManualAIModelEditorController : NSObject
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
    _window.title = @"Manual AI Models";
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
        @{ @"identifier": kAIManualModelsModelColumn, @"title": @"Model", @"width": @260 },
        @{ @"identifier": kAIManualModelsAPIColumn, @"title": @"API", @"width": @130 },
        @{ @"identifier": kAIManualModelsEndpointColumn, @"title": @"Endpoint", @"width": @150 }
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
        @{ @"symbol": SFSymbolGetString(SFSymbolPlus), @"tip": @"Add" },
        @{ @"symbol": SFSymbolGetString(SFSymbolMinus), @"tip": @"Delete" }
    ] action:@selector(addDeleteClicked:)];
    _editControl = [self makeSegmentedControlWithSegments:@[
        @{ @"symbol": SFSymbolGetString(SFSymbolPencil), @"tip": @"Edit" },
        @{ @"symbol": SFSymbolGetString(SFSymbolPlusSquareOnSquare), @"tip": @"Duplicate" },
        @{ @"symbol": SFSymbolGetString(SFSymbolStar), @"tip": @"Toggle Default" },
        @{ @"symbol": SFSymbolGetString(SFSymbolLeaf),
           @"tip": @"Toggle Economy Model. A cheaper model used for frequent background jobs "
                   @"like command-safety checks and screen-idle detection." }
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
    NSButton *ok = [NSButton buttonWithTitle:@"OK" target:self action:@selector(okClicked:)];
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
            : @"Untitled model";
        // A leading black star marks the default model, matching the profile list.
        // A leaf SF Symbol marks the economy model. The two are mutually
        // exclusive per row.
        if ([name isEqualToString:self.defaultModelName]) {
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
                               accessibilityDescription:@"Economy model"]
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
    NSTextField *_nameField;
    NSTextField *_urlField;
    NSPopUpButton *_apiPopup;
    NSTextField *_contextField;
    NSTextField *_responseField;
    NSPopUpButton *_vectorStorePopup;
    NSButton *_supportsTemperatureButton;
    NSButton *_configurableThinkingButton;
    NSMutableDictionary<NSString *, NSButton *> *_featureButtons;
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
    const CGFloat width = 540;
    const CGFloat height = 528;
    const CGFloat margin = 20;
    const CGFloat labelWidth = 150;
    const CGFloat fieldX = margin + labelWidth + 12;
    const CGFloat fieldWidth = width - margin - fieldX;
    const CGFloat rowHeight = 30;

    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
                                          styleMask:NSWindowStyleMaskTitled
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.title = _isEditing ? @"Edit Manual AI Model" : @"Add Manual AI Model";
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
    addLabel(@"Preset:");
    _presetPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(fieldX, y, fieldWidth, 24)];
    [_presetPopup addItemWithTitle:@"Custom"];
    _presetPopup.lastItem.tag = -1;
    [_presetPopup.menu addItem:[NSMenuItem separatorItem]];
    _presets = [[AIMetadata instance] presetModels];
    for (NSInteger i = 0; i < (NSInteger)_presets.count; i++) {
        [_presetPopup addItemWithTitle:_presets[(NSUInteger)i].name];
        _presetPopup.lastItem.tag = i;
    }
    [_presetPopup selectItemWithTag:-1];
    _presetPopup.target = self;
    _presetPopup.action = @selector(presetSelected:);
    [content addSubview:_presetPopup];
    y -= rowHeight + 8;

    _nameField = addTextField(@"Model:", _base[kAIManualModelNameKey]);
    _urlField = addTextField(@"URL:", _base[kAIManualModelURLKey]);

    addLabel(@"API:");
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
    [content addSubview:_apiPopup];
    y -= rowHeight;

    _contextField =
        addTextField(@"Context tokens:",
                     [NSString stringWithFormat:@"%ld",
                      (long)iTermManualAIModelIntegerValue(_base, kAIManualModelContextWindowTokensKey, 8192)]);
    _responseField =
        addTextField(@"Max response tokens:",
                     [NSString stringWithFormat:@"%ld",
                      (long)iTermManualAIModelIntegerValue(_base, kAIManualModelMaxResponseTokensKey, 8192)]);

    addLabel(@"Vector store:");
    _vectorStorePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(fieldX, y, fieldWidth, 24)];
    [_vectorStorePopup addItemWithTitle:@"Disabled"];
    _vectorStorePopup.lastItem.tag = 0;
    [_vectorStorePopup addItemWithTitle:@"OpenAI"];
    _vectorStorePopup.lastItem.tag = 1;
    [_vectorStorePopup selectItemWithTag:iTermManualAIModelIntegerValue(_base, kAIManualModelVectorStoreKey, 0)];
    [content addSubview:_vectorStorePopup];
    y -= rowHeight + 8;

    NSArray<NSDictionary *> *features = @[
        @{ @"title": @"Function calling", @"key": kAIManualModelFunctionCallingKey },
        @{ @"title": @"Streaming responses", @"key": kAIManualModelStreamingKey },
        @{ @"title": @"Hosted web search", @"key": kAIManualModelHostedWebSearchKey },
        @{ @"title": @"Hosted file search", @"key": kAIManualModelHostedFileSearchKey },
        @{ @"title": @"Hosted code interpreter", @"key": kAIManualModelHostedCodeInterpreterKey }
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
        [self addQuirkCheckboxWithTitle:@"Configurable thinking"
                                    key:kAIManualModelConfigurableThinkingKey
                           catalogValue:[[AIMetadata instance] modelSupportsConfigurableThinking:baseName]
                                tooltip:@"Enable for reasoning models with a thinking mode, such as GPT-5, "
                                        @"o-series, or DeepSeek models, so the chat’s Think toggle appears."
                                    toY:&y
                                 fieldX:fieldX
                                  width:fieldWidth
                                content:content];
    _supportsTemperatureButton =
        [self addQuirkCheckboxWithTitle:@"Supports temperature"
                                    key:kAIManualModelSupportsTemperatureKey
                           catalogValue:[[AIMetadata instance] modelSupportsTemperature:baseName]
                                tooltip:@"Uncheck for models that reject a temperature parameter, such as "
                                        @"Anthropic Opus 4.7 and later."
                                    toY:&y
                                 fieldX:fieldX
                                  width:fieldWidth
                                content:content];

    NSButton *save = [NSButton buttonWithTitle:(_isEditing ? @"Save" : @"Add")
                                        target:self
                                        action:@selector(saveClicked:)];
    save.bezelStyle = NSBezelStyleRounded;
    save.keyEquivalent = @"\r";
    save.frame = NSMakeRect(width - margin - 100, 16, 100, 30);
    [content addSubview:save];

    NSButton *cancel = [NSButton buttonWithTitle:@"Cancel"
                                          target:self
                                          action:@selector(cancelClicked:)];
    cancel.bezelStyle = NSBezelStyleRounded;
    cancel.keyEquivalent = @"\033";
    cancel.frame = NSMakeRect(width - margin - 100 - 8 - 100, 16, 100, 30);
    [content addSubview:cancel];

    _window.initialFirstResponder = _nameField;
    _window.defaultButtonCell = save.cell;
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
}

- (void)cancelClicked:(id)sender {
    [_window.sheetParent endSheet:_window returnCode:NSModalResponseCancel];
}

- (void)saveClicked:(id)sender {
    NSString *name =
        [_nameField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *url =
        [_urlField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *failure = nil;
    if (name.length == 0) {
        failure = @"Model is required.";
    } else if (url.length == 0) {
        failure = @"URL is required.";
    } else if (_contextField.integerValue <= 0) {
        failure = @"Context tokens must be greater than zero.";
    } else if (_responseField.integerValue <= 0) {
        failure = @"Max response tokens must be greater than zero.";
    } else if (_nameIsTaken && _nameIsTaken(name)) {
        failure = @"Manual model names must be unique.";
    }
    if (failure) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Invalid Manual AI Model";
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
            explanation = @"The query you enter will replace it when speaking to the AI. For example: “Write a unix command to \\(ai.prompt).”";
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
            explanation = @"The chat’s title will replace it when speaking to the AI.";
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
    NSString *name = configuration[kAIManualModelNameKey] ?: @"Untitled model";
    iTermAIVendor provider = [self providerForManualAIModelConfiguration:configuration];
    return [NSString stringWithFormat:@"Manual: %@ — %@",
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

- (void)updateAIEnabled {
    _enableAI.enabled = _pluginOK;

    const BOOL allowed = _pluginOK && [iTermAITermGatekeeper allowed];
    _openAIAPIKey.enabled = allowed;
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
    NSString *variableName = nil;
    NSString *explanation = nil;
    NSString *key = [self keyForCurrentlySelectedAIPromptGetting:&variableName
                                             variableExplanation:&explanation];
    NSString *requiredVariable =
        variableName ? [NSString stringWithFormat:@"\\(ai.%@)", variableName] : nil;
    if (requiredVariable && ![[self stringForKey:key] containsString:requiredVariable]) {
        _aiPromptWarning.toolTip =
            [NSString stringWithFormat:@"The prompt must contain the substring %@. %@",
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
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

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
        field.placeholderString = [NSString stringWithFormat:@"%@ API key", name];
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
        [NSString stringWithFormat:@"%@ copy", copy[kAIManualModelNameKey] ?: @"Manual model"];
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

- (IBAction)showManualAIConfigurationPanel:(NSButton *)button {
    NSWindow *parent = self.view.window;
    if (parent == nil) {
        return;
    }
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
