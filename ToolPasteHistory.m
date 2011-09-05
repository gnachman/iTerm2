//
//  ToolPasteHistory.m
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "ToolPasteHistory.h"
#import "NSDateFormatterExtras.h"
#import "iTermController.h"

@implementation ToolPasteHistory

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        scrollView_ = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)];
        [scrollView_ setHasVerticalScroller:YES];
        [scrollView_ setHasHorizontalScroller:NO];
        NSSize contentSize = [scrollView_ contentSize];
        [scrollView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        
        tableView_ = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
        NSTableColumn *col;        
        col = [[NSTableColumn alloc] initWithIdentifier:@"contents"];
        [col setEditable:NO];
        [tableView_ addTableColumn:col];
        [[col headerCell] setStringValue:@"Contents"];
        
#ifdef INCLUDE_DATE_COLUMN
        col = [[NSTableColumn alloc] initWithIdentifier:@"date"];
        [col setEditable:NO];
        [col setWidth:75];
        [col setMinWidth:75];
        [col setMaxWidth:75];
        [tableView_ addTableColumn:col];
        [[col headerCell] setStringValue:@"Date"];
#endif
        
        [tableView_ setDataSource:self];
        [tableView_ setDelegate:self];
        
        [tableView_ setDoubleAction:@selector(doubleClickOnTableView:)];
        [tableView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        

        [scrollView_ setDocumentView:tableView_];
        [self addSubview:scrollView_];

        [tableView_ sizeToFit];
        [tableView_ setColumnAutoresizingStyle:NSTableViewSequentialColumnAutoresizingStyle];
        
        pasteHistory_ = [PasteboardHistory sharedInstance];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(pasteboardHistoryDidChange:)
                                                     name:kPasteboardHistoryDidChange
                                                   object:nil];
        minuteRefreshTimer_ = [NSTimer scheduledTimerWithTimeInterval:61
                                                               target:self
                                                             selector:@selector(pasteboardHistoryDidChange:)
                                                             userInfo:nil
                                                              repeats:YES];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [minuteRefreshTimer_ invalidate];
    [tableView_ release];
    [scrollView_ release];
    [super dealloc];
}

- (BOOL)isFlipped
{
    return YES;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [[pasteHistory_ entries] count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    PasteboardEntry* entry = [[pasteHistory_ entries] objectAtIndex:[[pasteHistory_ entries] count] - rowIndex - 1];
    if ([[aTableColumn identifier] isEqualToString:@"date"]) {
        // Date
        return [NSDateFormatter compactDateDifferenceStringFromDate:entry->timestamp];
    } else {
        // Contents
        NSString* value = [[entry mainValue] stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        return value;
    }
}

- (void)pasteboardHistoryDidChange:(id)sender
{
    [tableView_ reloadData];
}

- (void)drawRect:(NSRect)rect
{
    [[NSColor redColor] set];
    NSFrameRect(NSMakeRect(10, 0, rect.size.width - 20, rect.size.height));
    [super drawRect:rect];
}

- (void)doubleClickOnTableView:(id)sender
{
    NSInteger selectedIndex = [tableView_ selectedRow];
    if (selectedIndex < 0) {
        return;
    }
    PasteboardEntry* entry = [[pasteHistory_ entries] objectAtIndex:[[pasteHistory_ entries] count] - selectedIndex - 1];
    NSPasteboard* thePasteboard = [NSPasteboard generalPasteboard];
    [thePasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
    [thePasteboard setString:[entry mainValue] forType:NSStringPboardType];
    [[[iTermController sharedInstance] frontTextView] paste:nil];
}

@end
