//
//  ContextMenuActionPrefsController.m
//  iTerm
//
//  Created by George Nachman on 11/18/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "ContextMenuActionPrefsController.h"
#import "NSStringITerm.h"

static NSString* kTitleKey = @"title";
static NSString* kActionKey = @"action";
static NSString* kParameterKey = @"parameter";

@implementation ContextMenuActionPrefsController

@synthesize delegate = delegate_;
@synthesize hasSelection = hasSelection_;

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        model_ = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [model_ release];
    [super dealloc];
}

+ (ContextMenuActions)actionForActionDict:(NSDictionary *)dict
{
    return (ContextMenuActions) [[dict objectForKey:kActionKey] intValue];
}

+ (NSString *)titleForActionDict:(NSDictionary *)dict withCaptureComponents:(NSArray *)components
{
    NSString *title = [dict objectForKey:kTitleKey];
    for (int i = 0; i < 9; i++) {
        NSString *repl = @"";
        if (i < components.count) {
            repl = [components objectAtIndex:i];
        }
        title = [title stringByReplacingBackreference:i withString:repl];
    }
    return title;
}

+ (NSString *)parameterValue:(NSString *)parameter
            encodedForAction:(ContextMenuActions)action
{
    switch (action) {
        case kRunCommandContextMenuAction:
        case kRunCoprocessContextMenuAction:
            return [parameter stringWithEscapedShellCharacters];
        case kOpenFileContextMenuAction:
            return parameter;
        case kOpenUrlContextMenuAction:
            return [parameter stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    }

    return nil;
}

+ (NSString *)parameterForActionDict:(NSDictionary *)dict withCaptureComponents:(NSArray *)components
{
    NSString *parameter = [dict objectForKey:kParameterKey];
    ContextMenuActions action = (ContextMenuActions) [[dict objectForKey:kActionKey] intValue];
    for (int i = 0; i < 9; i++) {
        NSString *repl = @"";
        if (i < components.count) {
            repl = [self parameterValue:[components objectAtIndex:i]
                       encodedForAction:action];
        }
        parameter = [parameter stringByReplacingBackreference:i withString:repl];
    }
    return parameter;
}

- (IBAction)ok:(id)sender
{
    [delegate_ contextMenuActionsChanged:model_];
}

- (IBAction)add:(id)sender
{
    NSDictionary *defaultAction = [NSDictionary dictionaryWithObjectsAndKeys:
                                   @"", kTitleKey,
                                   [NSNumber numberWithInt:kOpenFileContextMenuAction], kActionKey,
                                   nil];
    [model_ addObject:defaultAction];
    [tableView_ reloadData];
}

- (IBAction)remove:(id)sender
{
    [tableView_ reloadData];
    [model_ removeObjectAtIndex:[tableView_ selectedRow]];
    [tableView_ reloadData];
}

- (void)setActions:(NSArray *)newActions
{
    if (!newActions) {
        newActions = [NSMutableArray array];
    }
    [model_ autorelease];
    model_ = [newActions mutableCopy];
    [tableView_ reloadData];
}

#pragma mark NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [model_ count];
}

- (NSString *)keyForColumn:(NSTableColumn *)aTableColumn
{
    if (aTableColumn == titleColumn_) {
        return kTitleKey;
    } else if (aTableColumn == actionColumn_) {
        return kActionKey;
    } else if (aTableColumn == parameterColumn_) {
        return kParameterKey;
    } else {
        return nil;
    }
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    NSString *key = [self keyForColumn:aTableColumn];
    NSDictionary *row = [model_ objectAtIndex:rowIndex];
    return key ? [row objectForKey:key] : nil;
}

- (void)tableView:(NSTableView *)aTableView setObjectValue:(id)anObject forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    NSString *key = [self keyForColumn:aTableColumn];
    if (key) {
        NSMutableDictionary *temp = [[[model_ objectAtIndex:rowIndex] mutableCopy] autorelease];
        [temp setObject:anObject forKey:key];
        [model_ replaceObjectAtIndex:rowIndex withObject:temp];
        [aTableView reloadData];
    }
}

- (NSCell *)tableView:(NSTableView *)tableView
    dataCellForTableColumn:(NSTableColumn *)tableColumn
    row:(NSInteger)row
{
    // These two arrays and the enum in the header file must be parallel
    NSArray *actionNames = [NSArray arrayWithObjects:
                            @"Open File…",
                            @"Open URL…",
                            @"Run Command…",
                            @"Run Coprocess…",
                            nil];
    NSArray *paramPlaceholders = [NSArray arrayWithObjects:
                                  @"Enter file name",
                                  @"Enter URL",
                                  @"Enter command",
                                  @"Enter coprocess command",
                                  nil];


    if (tableColumn == titleColumn_) {
        NSTextFieldCell *cell = [[[NSTextFieldCell alloc] initTextCell:@""] autorelease];
        [cell setPlaceholderString:@"Enter Title"];
        [cell setEditable:YES];
        [cell setTruncatesLastVisibleLine:YES];
        [cell setLineBreakMode:NSLineBreakByTruncatingTail];

        return cell;
    } else if (tableColumn == actionColumn_) {
        NSPopUpButtonCell *cell =
            [[[NSPopUpButtonCell alloc] initTextCell:[actionNames objectAtIndex:0] pullsDown:NO] autorelease];
        for (int i = 0; i < actionNames.count; i++) {
            [cell addItemWithTitle:[actionNames objectAtIndex:i]];
            NSMenuItem *lastItem = [[[cell menu] itemArray] lastObject];
            [lastItem setTag:i];
        }

        [cell setBordered:NO];

        return cell;
    } else if (tableColumn == parameterColumn_) {
        NSDictionary *actionDict = [model_ objectAtIndex:row];
        int actionNum = [[actionDict objectForKey:kActionKey] intValue];
        NSString *placeholder = [paramPlaceholders objectAtIndex:actionNum];
        if (placeholder.length) {
            NSTextFieldCell *cell = [[[NSTextFieldCell alloc] initTextCell:@""] autorelease];
            [cell setPlaceholderString:placeholder];
            [cell setEditable:YES];
            [cell setTruncatesLastVisibleLine:YES];
            [cell setLineBreakMode:NSLineBreakByTruncatingTail];
            return cell;
        } else {
            NSTextFieldCell *cell = [[[NSTextFieldCell alloc] initTextCell:@""] autorelease];
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
    self.hasSelection = [tableView_ numberOfSelectedRows] > 0;
}

#pragma mark NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification
{
    [tableView_ reloadData];
}

@end
