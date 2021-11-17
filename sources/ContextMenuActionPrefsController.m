//
//  ContextMenuActionPrefsController.m
//  iTerm
//
//  Created by George Nachman on 11/18/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "ContextMenuActionPrefsController.h"
#import "FutureMethods.h"
#import "NSArray+iTerm.h"
#import "NSStringITerm.h"
#import "NSURL+iTerm.h"
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

@implementation ContextMenuActionPrefsController {
    IBOutlet NSTableView *_tableView;
    IBOutlet NSTableColumn *_titleColumn;
    IBOutlet NSTableColumn *_actionColumn;
    IBOutlet NSTableColumn *_parameterColumn;
    IBOutlet NSButton *_useInterpolatedStringsButton;
    NSMutableArray *_model;
}

- (instancetype)initWithWindow:(NSWindow *)window {
    self = [super initWithWindow:window];
    if (self) {
        _model = [[NSMutableArray alloc] init];
    }
    return self;
}

+ (ContextMenuActions)actionForActionDict:(NSDictionary *)dict
{
    return (ContextMenuActions) [[dict objectForKey:kActionKey] intValue];
}

+ (NSString *)titleForActionDict:(NSDictionary *)dict
           withCaptureComponents:(NSArray *)components
                workingDirectory:(NSString *)workingDirectory
                      remoteHost:(VT100RemoteHost *)remoteHost
{
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
    NSString *parameter = [dict objectForKey:kParameterKey];
    ContextMenuActions action = (ContextMenuActions) [[dict objectForKey:kActionKey] intValue];
    if (useInterpolation) {
        iTermSwiftyStringWithBackreferencesEvaluator *evaluator = [[iTermSwiftyStringWithBackreferencesEvaluator alloc] initWithExpression:parameter];
        NSArray *encodedCaptures = [components mapWithBlock:^id(id anObject) {
            return [self parameterValue:anObject encodedForAction:action];
        }];
        [evaluator evaluateWithBackreferences:encodedCaptures
                                        scope:scope
                                        owner:owner
                                   completion:^(NSString * _Nullable value,
                                            NSError * _Nullable error) {
            DLog(@"value=%@, error=%@", value, error);
            completion(value);
        }];
        return;
    }
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

    completion(parameter);
}

- (IBAction)help:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://iterm2.com/documentation-smart-selection.html"]];
}

- (IBAction)toggleUseInterpolatedStrings:(id)sender {
    self.useInterpolatedStrings = !self.useInterpolatedStrings;
}

- (void)setUseInterpolatedStrings:(BOOL)useInterpolatedStrings {
    _useInterpolatedStringsButton.state = useInterpolatedStrings ? NSControlStateValueOn : NSControlStateValueOff;
}

- (BOOL)useInterpolatedStrings {
    return _useInterpolatedStringsButton.state == NSControlStateValueOn;
}

- (IBAction)ok:(id)sender
{
    [_delegate contextMenuActionsChanged:_model
                  useInterpolatedStrings:self.useInterpolatedStrings];
}

- (IBAction)add:(id)sender
{
    NSDictionary *defaultAction = [NSDictionary dictionaryWithObjectsAndKeys:
                                   @"", kTitleKey,
                                   [NSNumber numberWithInt:kOpenFileContextMenuAction], kActionKey,
                                   nil];
    [_model addObject:defaultAction];
    [_tableView reloadData];
}

- (IBAction)remove:(id)sender
{
    [_tableView reloadData];
    [_model removeObjectAtIndex:[_tableView selectedRow]];
    [_tableView reloadData];
}

- (void)setActions:(NSArray *)newActions
{
    if (!newActions) {
        newActions = [NSMutableArray array];
    }
    _model = [newActions mutableCopy];
    [_tableView reloadData];
}

#pragma mark NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [_model count];
}

- (NSString *)keyForColumn:(NSTableColumn *)aTableColumn
{
    if (aTableColumn == _titleColumn) {
        return kTitleKey;
    } else if (aTableColumn == _actionColumn) {
        return kActionKey;
    } else if (aTableColumn == _parameterColumn) {
        return kParameterKey;
    } else {
        return nil;
    }
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    NSString *key = [self keyForColumn:aTableColumn];
    NSDictionary *row = [_model objectAtIndex:rowIndex];
    return key ? [row objectForKey:key] : nil;
}

- (void)tableView:(NSTableView *)aTableView setObjectValue:(id)anObject forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    NSString *key = [self keyForColumn:aTableColumn];
    if (key) {
        NSMutableDictionary *temp = [[_model objectAtIndex:rowIndex] mutableCopy];
        [temp setObject:anObject forKey:key];
        [_model replaceObjectAtIndex:rowIndex withObject:temp];
        [aTableView reloadData];
    }
}

- (NSCell *)tableView:(NSTableView *)tableView
    dataCellForTableColumn:(NSTableColumn *)tableColumn
    row:(NSInteger)row
{
    // These two arrays and the enum in the header file must be parallel
    NSArray *actionNames = @[ @"Open File…",
                              @"Open URL…",
                              @"Run Command…",
                              @"Run Coprocess…",
                              @"Send text…",
                              @"Run Command in Window…" ];
    NSArray *paramPlaceholders = @[ @"Enter file name",
                                    @"Enter URL",
                                    @"Enter command",
                                    @"Enter coprocess command",
                                    @"Enter text",
                                    @"Enter command" ];


    if (tableColumn == _titleColumn) {
        NSTextFieldCell *cell = [[NSTextFieldCell alloc] initTextCell:@""];
        [cell setPlaceholderString:@"Enter Title"];
        [cell setEditable:YES];
        [cell setTruncatesLastVisibleLine:YES];
        [cell setLineBreakMode:NSLineBreakByTruncatingTail];

        return cell;
    } else if (tableColumn == _actionColumn) {
        NSPopUpButtonCell *cell =
        [[NSPopUpButtonCell alloc] initTextCell:[actionNames objectAtIndex:0] pullsDown:NO];
        for (int i = 0; i < actionNames.count; i++) {
            [cell addItemWithTitle:[actionNames objectAtIndex:i]];
            NSMenuItem *lastItem = [[[cell menu] itemArray] lastObject];
            [lastItem setTag:i];
        }

        [cell setBordered:NO];

        return cell;
    } else if (tableColumn == _parameterColumn) {
        NSDictionary *actionDict = [_model objectAtIndex:row];
        int actionNum = [[actionDict objectForKey:kActionKey] intValue];
        NSString *placeholder = [paramPlaceholders objectAtIndex:actionNum];
        if (placeholder.length) {
            NSTextFieldCell *cell = [[NSTextFieldCell alloc] initTextCell:@""];
            [cell setPlaceholderString:placeholder];
            [cell setEditable:YES];
            [cell setTruncatesLastVisibleLine:YES];
            [cell setLineBreakMode:NSLineBreakByTruncatingTail];
            return cell;
        } else {
            NSTextFieldCell *cell = [[NSTextFieldCell alloc] initTextCell:@""];
            [cell setEditable:NO];
            return cell;
        }
    }
    return nil;
}

#pragma mark NSTableViewDelegate

- (BOOL)tableView:(NSTableView *)aTableView shouldEditTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    return YES;
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
    self.hasSelection = [_tableView numberOfSelectedRows] > 0;
}

#pragma mark NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification
{
    [_tableView reloadData];
}

@end
