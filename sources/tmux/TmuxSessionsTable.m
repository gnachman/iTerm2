//
//  TmuxSessionsTable.m
//  iTerm
//
//  Created by George Nachman on 12/23/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import "TmuxSessionsTable.h"

#import "DebugLogging.h"
#import "FutureMethods.h"
#import "iTermTmuxSessionObject.h"
#import "NSArray+iTerm.h"

extern NSString *kWindowPasteboardType;

@implementation TmuxSessionsTable {
    NSMutableArray<iTermTmuxSessionObject *> *_model;
    BOOL canAttachToSelectedSession_;

    IBOutlet NSTableColumn *checkColumn_;
    IBOutlet NSTableColumn *nameColumn_;
    IBOutlet NSTableView *tableView_;
    IBOutlet NSButton *attachButton_;
    IBOutlet NSButton *detachButton_;
    IBOutlet NSButton *removeButton_;
}

@synthesize delegate = delegate_;

- (instancetype)init {
    self = [super init];
    if (self) {
        _model = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)awakeFromNib
{
    DLog(@"dashboard: awakeFromNib");
    [tableView_ registerForDraggedTypes:[NSArray arrayWithObjects:kWindowPasteboardType, nil]];
    [tableView_ setDraggingDestinationFeedbackStyle:NSTableViewDraggingDestinationFeedbackStyleRegular];
}

- (void)dealloc {
    [_model release];
    [super dealloc];
}

- (void)setDelegate:(id<TmuxSessionsTableProtocol>)delegate {
    delegate_ = delegate;
    [self setSessionObjects:[delegate_ sessionsTableObjects:self]];
}

- (void)setSessionObjects:(NSArray<iTermTmuxSessionObject *> *)sessions
{
    DLog(@"dashboard: setSessionObjects:%@", sessions);
    // Reload in case a cell is being edited. Otherwise NSTableView asks for its row.
    [tableView_ reloadData];
    [_model removeAllObjects];
    [_model addObjectsFromArray:sessions];
    [tableView_ reloadData];
}

- (void)selectSessionNumber:(int)number {
    DLog(@"dashboard: Select session %@", @(number));

    NSInteger i = [_model indexOfObjectPassingTest:^BOOL(iTermTmuxSessionObject * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return obj.number == number;
    }];
    if (i != NSNotFound) {
        [tableView_ selectRowIndexes:[NSIndexSet indexSetWithIndex:i]
                byExtendingSelection:NO];
    }
    [self updateEnabledStateOfButtons];
}

- (void)endEditing {
    [tableView_ reloadData];
}

- (IBAction)addSession:(id)sender
{
    DLog(@"dashboard: Add session");
    [delegate_ addSessionWithName:[self nameForNewSession]];
}

- (IBAction)removeSession:(id)sender
{
    DLog(@"dashboard: Remove session");
    NSNumber *number = [self selectedSessionNumber];
    if (number) {
        [delegate_ removeSessionWithNumber:number.intValue];
    }
}

- (IBAction)attach:(id)sender {
    NSNumber *number = [self selectedSessionNumber];
    DLog(@"attach %@", number);
    if (number) {
        [delegate_ attachToSessionWithNumber:number.intValue];
    }
}

- (IBAction)detach:(id)sender {
    NSNumber *number = [self selectedSessionNumber];
    DLog(@"dashboard: detach %@", number);
    if (number) {
        [delegate_ detach];
    }
}

#pragma mark NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    DLog(@"dashboard: numberOfRowsInTableView model=%@", _model);
    return _model.count;
}

- (id)tableView:(NSTableView *)aTableView
    objectValueForTableColumn:(NSTableColumn *)aTableColumn
            row:(NSInteger)rowIndex {
    iTermTmuxSessionObject *sessionObject = _model[rowIndex];
    if (aTableColumn == checkColumn_) {
        if ([[delegate_ numberOfAttachedSession] isEqual:@(sessionObject.number)]) {
            return @"✓";
        } else {
            return @"";
        }
    } else {
        if (rowIndex < _model.count) {
            return sessionObject.name;
        } else {
            return nil;
        }
    }
}

- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex {
    [delegate_ renameSessionWithNumber:_model[rowIndex].number
                                toName:(NSString *)anObject];
}

#pragma mark NSTableViewDataSource

- (BOOL)tableView:(NSTableView *)aTableView
               shouldEditTableColumn:(NSTableColumn *)aTableColumn
                                 row:(NSInteger)rowIndex {
    return YES;
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
    [self updateEnabledStateOfButtons];
    [delegate_ selectedSessionDidChange];
}

- (NSNumber *)selectedSessionNumber {
    int i = [tableView_ selectedRow];
    if (i >= 0 && i < _model.count) {
        return @(_model[i].number);
    } else {
        return nil;
    }
}

- (BOOL)tableView:(NSTableView *)aTableView
       acceptDrop:(id <NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)operation {

    __block NSNumber *sessionNumber = nil;
    NSMutableArray<NSArray *> *draggedItems = [NSMutableArray array];
    [info enumerateDraggingItemsWithOptions:0
                                    forView:aTableView
                                    classes:@[ [NSPasteboardItem class]]
                              searchOptions:@{}
                                 usingBlock:^(NSDraggingItem * _Nonnull draggingItem, NSInteger idx, BOOL * _Nonnull stop) {
        NSPasteboardItem *item = draggingItem.item;
        NSArray *array = [item propertyListForType:kWindowPasteboardType];
        sessionNumber = array[0];
        [draggedItems addObjectsFromArray:array[1]];
    }];


    iTermTmuxSessionObject *targetSessionObject = _model[row];
    for (NSArray *tuple in draggedItems) {
        NSNumber *windowId = [tuple objectAtIndex:1];
        if (info.draggingSourceOperationMask & NSDragOperationLink) {
            [delegate_ linkWindowId:[windowId intValue]
                    inSessionNumber:sessionNumber.intValue
                    toSessionNumber:targetSessionObject.number];
        } else {
            [delegate_ moveWindowId:[windowId intValue]
                    inSessionNumber:sessionNumber.intValue
                    toSessionNumber:targetSessionObject.number];
        }
    }
    return YES;
}

- (NSDragOperation)tableView:(NSTableView *)aTableView
                validateDrop:(id < NSDraggingInfo >)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)operation
{
    if (operation == NSTableViewDropOn) {
        if (info.draggingSourceOperationMask & NSDragOperationLink) {
            return NSDragOperationLink;
        } else {
            return NSDragOperationMove;
        }
    } else {
        return NSDragOperationNone;
    }
}


#pragma mark - Private

- (NSString *)nameForNewSessionWithNumber:(int)n
{
    if (n == 0) {
        return @"New Session";
    } else {
        return [NSString stringWithFormat:@"New Session %d", n + 1];
    }
}

- (BOOL)haveSessionWithName:(NSString *)name {
    return [_model anyWithBlock:^BOOL(iTermTmuxSessionObject *anObject) {
        return [anObject.name isEqualToString:name];
    }];
}

- (NSString *)nameForNewSession {
    int n = 0;
    NSString *candidate = [self nameForNewSessionWithNumber:n];
    while ([self haveSessionWithName:candidate]) {
        n++;
        candidate = [self nameForNewSessionWithNumber:n];
    }
    return candidate;
}

- (void)updateEnabledStateOfButtons
{
    if ([tableView_ selectedRow] < 0) {
        [attachButton_ setEnabled:NO];
        [detachButton_ setEnabled:NO];
        [removeButton_ setEnabled:NO];
    } else {
        NSNumber *selected = [self selectedSessionNumber];
        BOOL isAttachedSession = (selected != nil &&
                                  [[delegate_ numberOfAttachedSession] isEqual:@(selected.intValue)]);
        [attachButton_ setEnabled:!isAttachedSession];
        [detachButton_ setEnabled:isAttachedSession];
        [removeButton_ setEnabled:YES];
    }
}

@end
