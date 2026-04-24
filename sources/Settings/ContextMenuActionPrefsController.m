//
//  ContextMenuActionPrefsController.m
//  iTerm
//
//  Created by George Nachman on 11/18/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "ContextMenuActionPrefsController.h"
#import "DebugLogging.h"
#import "FutureMethods.h"
#import "NSArray+iTerm.h"
#import "NSStringITerm.h"
#import "NSURL+iTerm.h"
#import "NSWorkspace+iTerm.h"
#import "VT100RemoteHost.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermVariableScope+Session.h"

static NSString* kTitleKey = @"title";
static NSString* kActionKey = @"action";
static NSString* kParameterKey = @"parameter";

NSString *iTermSmartSelectionActionContextKeyAction = @"action";
NSString *iTermSmartSelectionActionContextKeyComponents = @"components";
NSString *iTermSmartSelectionActionContextKeyWorkingDirectory = @"workingDirectory";
NSString *iTermSmartSelectionActionContextKeyRemoteHost = @"remoteHost";

typedef struct {
    NSString *title;
    NSString *placeholder;
    NSString *parameterLabel;
    ContextMenuActions tag;
    BOOL browser;  // Can browser profiles use it?
} ContextMenuActionDeclaration;

static ContextMenuActionDeclaration gContextMenuActionDeclarations[] = {
    { @"Open File…",               @"Enter file name",          @"File:",      kOpenFileContextMenuAction,             YES },
    { @"Open URL…",                @"Enter URL",                @"URL:",       kOpenUrlContextMenuAction,              YES },
    { @"Run Command…",             @"Enter command",            @"Command:",   kRunCommandContextMenuAction,           NO  },
    { @"Run Coprocess…",           @"Enter coprocess command",  @"Coprocess:", kRunCoprocessContextMenuAction,         NO  },
    { @"Send text…",               @"Enter text",               @"Text:",      kSendTextContextMenuAction,             NO  },
    { @"Run Command in Window…",   @"Enter command",            @"Command:",   kRunCommandInWindowContextMenuAction,   YES },
    { @"Copy",                     @"",                         @"",           kCopyContextMenuAction,                 YES },
};

static ContextMenuActionDeclaration ContextMenuActionDeclarationForTag(ContextMenuActions tag) {
    const NSUInteger actionsCount = sizeof(gContextMenuActionDeclarations) / sizeof(gContextMenuActionDeclarations[0]);
    for (NSUInteger i = 0; i < actionsCount; i++) {
        if (gContextMenuActionDeclarations[i].tag == tag) {
            return gContextMenuActionDeclarations[i];
        }
    }
    ITAssertWithMessage(NO, @"Invalid tag %@", @(tag));
}

@interface ContextMenuActionPrefsController()<NSTextFieldDelegate, NSMenuItemValidation>
@end

@implementation ContextMenuActionPrefsController {
    IBOutlet NSTableView *_tableView;
    IBOutlet NSButton *_useInterpolatedStringsButton;
    IBOutlet NSTextField *_parameterInfoTextField;

    IBOutlet NSTextField *_title;
    IBOutlet NSPopUpButton *_action;
    IBOutlet NSTextField *_parameter;
    IBOutlet NSTextField *_parameterLabel;
    IBOutlet NSView *_detailContainer;

    NSMutableArray *_model;
    BOOL _browser;

    NSUndoManager *_undoManager;
}

- (instancetype)initWithWindow:(NSWindow *)window {
    self = [super initWithWindow:window];
    if (self) {
        _model = [[NSMutableArray alloc] init];
    }
    return self;
}

+ (ContextMenuActions)actionForActionDict:(NSDictionary *)dict {
    return (ContextMenuActions) [[dict objectForKey:kActionKey] intValue];
}

+ (NSString *)titleForActionDict:(NSDictionary *)dict
           withCaptureComponents:(NSArray *)components
                workingDirectory:(NSString *)workingDirectory
                      remoteHost:(id<VT100RemoteHostReading>)remoteHost {
    NSString *title = [dict objectForKey:kTitleKey];
    for (int i = 0; i < 9; i++) {
        NSString *repl = @"";
        if (i < components.count) {
            repl = [components objectAtIndex:i];
        }
        title = [title stringByReplacingBackreference:i withString:repl];
    }

    title = [title stringByReplacingEscapedChar:'d' withString:workingDirectory ?: @"."];
    title = [title stringByReplacingEscapedChar:'h' withString:remoteHost.hostname];
    title = [title stringByReplacingEscapedChar:'u' withString:remoteHost.username];
    title = [title stringByReplacingEscapedChar:'\\' withString:@"\\"];

    return title;
}

+ (NSString *)parameterValue:(NSString *)parameter
            encodedForAction:(ContextMenuActions)action {
    switch (action) {
        case kRunCommandContextMenuAction:
        case kRunCommandInWindowContextMenuAction:
        case kRunCoprocessContextMenuAction:
            return [parameter stringWithBackslashEscapedShellCharactersIncludingNewlines:NO];
        case kOpenFileContextMenuAction:
            return parameter;
        case kCopyContextMenuAction:
            return parameter;
        case kOpenUrlContextMenuAction: {
            return [NSURL URLWithUserSuppliedString:parameter].absoluteString;
        }
        case kSendTextContextMenuAction:
            return parameter;
    }

    return nil;
}

+ (void)computeParameterForActionDict:(NSDictionary *)dict
                withCaptureComponents:(NSArray *)components
                     useInterpolation:(BOOL)useInterpolation
                                scope:(iTermVariableScope *)scope
                                owner:(id<iTermObject>)owner
                           completion:(void (^)(NSString *parameter))completion {
    if (useInterpolation) {
        [self computeInterpolatedParameterForActionDict:dict
                                  withCaptureComponents:components
                                                  scope:scope
                                                  owner:owner
                                            synchronous:NO
                                             completion:completion];
        return;
    }
    NSString *result = [self computeNonInterpolatedParameterForActionDict:dict
                                                    withCaptureComponents:components
                                                                    scope:scope];
    completion(result);
}

+ (void)computeInterpolatedParameterForActionDict:(NSDictionary *)dict
                            withCaptureComponents:(NSArray *)components
                                            scope:(iTermVariableScope *)scope
                                            owner:(id<iTermObject>)owner
                                      synchronous:(BOOL)synchronous
                                       completion:(void (^)(NSString *parameter))completion {
    NSString *parameter = [dict objectForKey:kParameterKey];
    ContextMenuActions action = (ContextMenuActions) [[dict objectForKey:kActionKey] intValue];
    iTermSwiftyStringWithBackreferencesEvaluator *evaluator = [[iTermSwiftyStringWithBackreferencesEvaluator alloc] initWithExpression:parameter];
    NSArray *encodedCaptures = [components mapWithBlock:^id(id anObject) {
        return [self parameterValue:anObject encodedForAction:action];
    }];
    NSDictionary *additionalContext = @{ @"matches": encodedCaptures };
    if (synchronous) {
        NSError *error;
        NSString *result = [evaluator evaluateWithAdditionalContext:additionalContext
                                                              scope:scope
                                                              owner:owner
                                                 sideEffectsAllowed:NO
                                                              error:&error];
        DLog(@"value=%@, error=%@", result, error);
        completion(result);
    } else {
        [evaluator evaluateWithAdditionalContext:additionalContext
                                           scope:scope
                                           owner:owner
                                      completion:^(NSString * _Nullable value,
                                                   NSError * _Nullable error) {
            DLog(@"value=%@, error=%@", value, error);
            completion(value);
        }];
    }
}

+ (NSString *)computeNonInterpolatedParameterForActionDict:(NSDictionary *)dict
                                     withCaptureComponents:(NSArray *)components
                                                     scope:(iTermVariableScope *)scope {
    NSString *parameter = [dict objectForKey:kParameterKey];
    ContextMenuActions action = (ContextMenuActions) [[dict objectForKey:kActionKey] intValue];
    for (int i = 0; i < 9; i++) {
        NSString *repl = @"";
        if (i < components.count) {
            repl = [self parameterValue:[components objectAtIndex:i]
                       encodedForAction:action];
        }
        parameter = [parameter stringByReplacingBackreference:i withString:repl ?: @""];
    }

    NSString *workingDirectory = [scope path];
    NSString *hostname = [scope hostname];
    NSString *username = [scope username];

    parameter = [parameter stringByReplacingEscapedChar:'d' withString:workingDirectory ?: @"."];
    parameter = [parameter stringByReplacingEscapedChar:'h' withString:hostname];
    parameter = [parameter stringByReplacingEscapedChar:'u' withString:username];
    parameter = [parameter stringByReplacingEscapedChar:'n' withString:@"\n"];
    parameter = [parameter stringByReplacingEscapedChar:'\\' withString:@"\\"];

    return parameter;
}

+ (NSString *)computeParameterForActionDict:(NSDictionary *)dict
                withCaptureComponents:(NSArray *)components
                     useInterpolation:(BOOL)useInterpolation
                                scope:(iTermVariableScope *)scope
                                owner:(id<iTermObject>)owner {
    if (useInterpolation) {
        __block NSString *result = nil;
        [self computeInterpolatedParameterForActionDict:dict
                                  withCaptureComponents:components
                                                  scope:scope
                                                  owner:owner
                                            synchronous:YES
                                             completion:^(NSString *parameter) {
            result = parameter;
        }];
        return result;
    }
    NSString *result = [self computeNonInterpolatedParameterForActionDict:dict
                                                    withCaptureComponents:components
                                                                    scope:scope];
    return result;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    DLog(@"%@", menuItem);
    if (menuItem.action == @selector(undo:)) {
        return [_undoManager canUndo];
    }
    if (menuItem.action == @selector(redo:)) {
        return [_undoManager canRedo];
    }
    return YES;
}

- (void)awakeFromNib {
    _undoManager = [[NSUndoManager alloc] init];
    [super awakeFromNib];
}

- (IBAction)undo:(id)sender {
    [_undoManager undo];
}

- (IBAction)redo:(id)sender {
    [_undoManager redo];
}

- (void)pushUndo {
    [_undoManager registerUndoWithTarget:self
                                selector:@selector(setState:)
                                  object:@{ @"selectedIndexes": [_tableView selectedRowIndexes],
                                            @"model": _model.mutableCopy,
                                            @"firstResponderIdentifier": self.firstResponderID }];
}

- (NSString *)firstResponderID {
    if (_title.textFieldIsFirstResponder) {
        return _title.identifier;
    }
    if (_parameter.textFieldIsFirstResponder) {
        return _parameter.identifier;
    }
    if (_action.window.firstResponder == _action) {
        return _action.identifier;
    }
    return @"";
}

- (void)setState:(NSDictionary *)state {
    _model = [state[@"model"] mutableCopy];
    NSIndexSet *indexes = state[@"selectedIndexes"];
    [_tableView reloadData];
    [_tableView selectRowIndexes:indexes byExtendingSelection:NO];
    [self updateDetailView];
    NSString *firstResponderID = state[@"firstResponderIdentifier"];
    if ([firstResponderID isEqualToString:_title.identifier]) {
        [_title.window makeFirstResponder:_title];
    } else if ([firstResponderID isEqualToString:_action.identifier]) {
        [_action.window makeFirstResponder:_action];
    } else if ([firstResponderID isEqualToString:_parameter.identifier]) {
        [_parameter.window makeFirstResponder:_parameter];
    }
}

- (IBAction)help:(id)sender {
    [[NSWorkspace sharedWorkspace] it_openURL:[NSURL URLWithString:@"https://iterm2.com/documentation-smart-selection.html"]
                                       target:nil
                                        style:iTermOpenStyleTab
                                       window:self.window];
}

- (IBAction)didToggleUseInterpolatedStrings:(id)sender {
    [self updateHelpText];
}

- (void)setUseInterpolatedStrings:(BOOL)useInterpolatedStrings {
    _useInterpolatedStringsButton.state = useInterpolatedStrings ? NSControlStateValueOn : NSControlStateValueOff;
    [self updateHelpText];
}

- (void)updateHelpText {
    if (_useInterpolatedStringsButton.state == NSControlStateValueOn) {
        NSString *html = @"You can use captured strings from the Smart Selection's regular expression in the parameter. Use \\(matches[i]) where i=0 for the entire match and i>0 for capture groups. For other values, see <a href=\"https://iterm2.com/documentation-scripting-fundamentals.html\">Scripting Fundamentals</a> and <a href=\"https://iterm2.com/documentation-variables.html#session-context\">Variables Reference (Session Context)</a>.";
        NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        paragraphStyle.lineBreakMode = NSLineBreakByWordWrapping;
        _parameterInfoTextField.attributedStringValue = [NSAttributedString attributedStringWithHTML:html
                                                                                                font:_parameterInfoTextField.font
                                                                                      paragraphStyle:paragraphStyle];
        _parameterInfoTextField.selectable = YES;
        _parameterInfoTextField.allowsEditingTextAttributes = YES;
    } else {
        _parameterInfoTextField.stringValue = @"You can use captured strings from the Smart Selection's regular expression in the parameter. Use \\0 for match, \\1…\\9 for match groups, \\d for directory, \\u for user, \\h for host.";
    }
}

- (BOOL)useInterpolatedStrings {
    return _useInterpolatedStringsButton.state == NSControlStateValueOn;
}

- (IBAction)ok:(id)sender {
    [_delegate contextMenuActionsChanged:_model
                  useInterpolatedStrings:self.useInterpolatedStrings];
}

- (IBAction)add:(id)sender {
    [self pushUndo];
    NSDictionary *defaultAction = [NSDictionary dictionaryWithObjectsAndKeys:
                                   @"", kTitleKey,
                                   [NSNumber numberWithInt:kOpenFileContextMenuAction], kActionKey,
                                   nil];
    [_model addObject:defaultAction];
    [_tableView reloadData];
    [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:_model.count - 1]
            byExtendingSelection:NO];
    [_title.window makeFirstResponder:_title];
}

- (IBAction)remove:(id)sender {
    [self pushUndo];
    [_model removeObjectsAtIndexes:[_tableView selectedRowIndexes]];
    [_tableView reloadData];
    [self updateDetailView];
}

- (void)setActions:(NSArray *)newActions browser:(BOOL)browser {
    if (!newActions) {
        newActions = [NSMutableArray array];
    }
    _browser = browser;
    _model = [newActions mutableCopy];
    [_tableView reloadData];
    [_action.menu removeAllItems];
    for (NSInteger i = 0; i < sizeof(gContextMenuActionDeclarations) / sizeof(*gContextMenuActionDeclarations); i++) {
        if (_browser && !gContextMenuActionDeclarations[i].browser) {
            continue;
        }
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:gContextMenuActionDeclarations[i].title
                                                      action:nil
                                               keyEquivalent:@""];
        item.tag = gContextMenuActionDeclarations[i].tag;
        [_action.menu addItem:item];
    }
    [self updateDetailView];
}

#pragma mark NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [_model count];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
    iTermTableCellViewWithTextField *view = [tableView newTableCellViewWithTextFieldUsingIdentifier:@"Smart Selection Action Tableview Entry"
                                                                                   attributedString:[self attributedStringForAction:_model[rowIndex]]];
    return view;
}

- (NSAttributedString *)attributedStringForAction:(NSDictionary *)action {
    const ContextMenuActions actionTag = [action[kActionKey] integerValue];
    if (actionTag < 0 || actionTag >= sizeof(gContextMenuActionDeclarations) / sizeof(*gContextMenuActionDeclarations)) {
        return nil;
    }
    ContextMenuActionDeclaration decl = ContextMenuActionDeclarationForTag(actionTag);

    NSString *title = action[kTitleKey];
    if (title.length == 0) {
        title = @"Untitled Action";
    }
    NSAttributedString *nameAttributedString = [[NSAttributedString alloc] initWithString:title
                                                                               attributes:self.nameAttributes];
    NSAttributedString *actionAttributedString = [[NSAttributedString alloc] initWithString:decl.title
                                                                                 attributes:self.regularAttributes];
    id parameterAttributedString = nil;
    NSString *parameter = action[kParameterKey];
    if ([NSString castFrom:parameter].length) {
        parameterAttributedString = [[NSAttributedString alloc] initWithString:parameter
                                                                    attributes:self.regularAttributes];
    } else {
        parameterAttributedString = [NSNull null];
    }
    NSAttributedString *newline = [[NSAttributedString alloc] initWithString:@"\n" attributes:self.regularAttributes];
    return [[@[nameAttributedString,
               actionAttributedString,
               parameterAttributedString] arrayByRemovingNulls] it_componentsJoinedBySeparator:newline];
}

- (NSDictionary *)nameAttributes {
    NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *attributes = @{
        NSParagraphStyleAttributeName: paragraphStyle,
        NSFontAttributeName: [NSFont boldSystemFontOfSize:[NSFont systemFontSize] + 2]
    };
    return attributes;
}

- (NSDictionary *)regularAttributes {
    NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *attributes = @{
        NSParagraphStyleAttributeName: paragraphStyle,
        NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize]]
    };
    return attributes;
}

- (void)controlTextDidChange:(NSNotification *)obj {
    NSInteger i = _tableView.selectedRow;
    if (i < 0 || i >= _model.count) {
        DLog(@"Bogus selected row %@", @(i));
        return;
    }
    [self pushUndo];
    NSTextField *textField = [NSTextField castFrom:obj.object];

    NSMutableDictionary *temp = [[_model objectAtIndex:i] mutableCopy];
    if (textField == _title) {
        temp[kTitleKey] = textField.stringValue;
    } else if (textField == _parameter) {
        temp[kParameterKey] = textField.stringValue;
    }
    _model[i] = temp;
    [_tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:i]
                          columnIndexes:[NSIndexSet indexSetWithIndex:0]];
    [_tableView noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndex:i]];
}

- (IBAction)actionDidChange:(id)sender {
    NSInteger i = _tableView.selectedRow;
    if (i < 0 || i >= _model.count) {
        DLog(@"Bogus selected row %@", @(i));
        return;
    }
    [self pushUndo];
    NSMutableDictionary *temp = [[_model objectAtIndex:i] mutableCopy];
    temp[kActionKey] = @(_action.selectedTag);
    _model[i] = temp;
    [_tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:i]
                          columnIndexes:[NSIndexSet indexSetWithIndex:0]];
    [self updateDetailView];
}

#pragma mark NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
    [self updateDetailView];
}

- (void)updateDetailView {
    // The remove button is bound to this
    self.hasSelection = [_tableView numberOfSelectedRows] > 0;
    _detailContainer.hidden = ([_tableView numberOfSelectedRows] != 1);
    if (!self.hasSelection) {
        return;
    }

    NSDictionary *item = _model[_tableView.selectedRow];
    _title.stringValue = item[kTitleKey] ?: @"";
    _parameter.stringValue = item[kParameterKey] ?: @"";
    NSNumber *action = [NSNumber castFrom:item[kActionKey]] ?: @0;
    [_action selectItemWithTag:action.integerValue];
    _parameterLabel.stringValue = ContextMenuActionDeclarationForTag(action.integerValue).parameterLabel;

    const BOOL noParameter = (action.integerValue == kCopyContextMenuAction);
    _parameterLabel.hidden = noParameter;
    _parameter.hidden = noParameter;
    _parameterInfoTextField.hidden = noParameter;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    NSAttributedString *attributedString = [self attributedStringForAction:_model[row]];
    return [attributedString heightForWidth:tableView.tableColumns[0].width] + 8;
}

@end
