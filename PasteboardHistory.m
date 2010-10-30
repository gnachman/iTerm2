//
//  PasteboardHistory.m
//  iTerm
//
//  Created by George Nachman on 10/25/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#include <wctype.h>
#import "PasteboardHistory.h"
#import "iTerm/iTermController.h"
#import "NSDateFormatterExtras.h"
#define kPasteboardHistoryDidChange @"PasteboardHistoryDidChange"

@implementation PasteboardModel

- (id)initWithHistory:(PasteboardHistory*)history
{
    self = [super init];
    if (!self) {
        return nil;
    }
    history_ = history;
    [history retain];
    entries_ = [[NSMutableArray alloc] init];
    filter_ = [[NSMutableString alloc] init];
    [self reload];
    
    return self;
}

- (void)dealloc
{
    [filter_ release];
    [entries_ release];
    [history_ release];
    [super dealloc];
}

- (void)appendString:(NSString*)string
{
    [filter_ appendString:string];
    [self reload];
}

- (void)clearFilter
{
    [filter_ setString:@""];
    [self reload];
}

- (int)numberOfEntries
{
    return [entries_ count];
}

- (PasteboardEntry*)entryAtIndex:(int)i
{
    return [entries_ objectAtIndex:i];
}

- (NSString*)filter
{
    return filter_;
}

- (NSAttributedString*)attributedStringForValue:(NSString*)value
{
    NSMutableAttributedString* as = [[[NSMutableAttributedString alloc] init] autorelease];
    NSDictionary* plainAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                         [NSFont systemFontOfSize:[NSFont systemFontSize]], NSFontAttributeName,
                                         nil];
    NSDictionary* boldAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                        [NSFont boldSystemFontOfSize:[NSFont systemFontSize]], NSFontAttributeName,
                                        nil];
    value = [value stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    NSString* temp = value;
    for (int i = 0; i < [filter_ length]; ++i) {
        unichar wantChar = [filter_ characterAtIndex:i];
        NSRange r = [temp rangeOfString:[NSString stringWithCharacters:&wantChar length:1] options:NSCaseInsensitiveSearch];
        if (r.location == NSNotFound) {
            return nil;
        }
        NSRange prefix;
        prefix.location = 0;
        prefix.length = r.location;
        NSAttributedString* attributedSubstr;
        if (prefix.length > 0) {
            NSString* substr = [temp substringWithRange:prefix];
            attributedSubstr = [[[NSAttributedString alloc] initWithString:substr attributes:plainAttributes] autorelease];
            [as appendAttributedString:attributedSubstr];
        }
        
        unichar matchChar = [temp characterAtIndex:r.location];
        attributedSubstr = [[[NSAttributedString alloc] initWithString:[NSString stringWithCharacters:&matchChar length:1] attributes:boldAttributes] autorelease];
        [as appendAttributedString:attributedSubstr];
        
        r.length = [temp length] - r.location - 1;
        ++r.location;
        temp = [temp substringWithRange:r];
    }
    
    NSAttributedString* attributedSubstr;
    if ([temp length] > 0) {
        attributedSubstr = [[[NSAttributedString alloc] initWithString:temp attributes:plainAttributes] autorelease];
        [as appendAttributedString:attributedSubstr];
    }
    
    return as;
}

- (void)reload
{
    [entries_ removeAllObjects];
    NSArray* backingEntries = [history_ entries];
    for (int i = 0; i < [backingEntries count]; ++i) {
        PasteboardEntry* entry = [backingEntries objectAtIndex:i];
        if ([self _entry:entry matchesFilter:filter_]) {
            [entries_ addObject:entry];
        }
    }
}

- (BOOL)_entry:(PasteboardEntry*)entry matchesFilter:(NSString*)filter
{
    NSString* temp = entry->value;
    for (int i = 0; i < [filter length]; ++i) {
        unichar wantChar = [filter characterAtIndex:i];
        NSRange r = [temp rangeOfString:[NSString stringWithCharacters:&wantChar length:1] options:NSCaseInsensitiveSearch];
        if (r.location == NSNotFound) {
            return NO;
        }
        r.length = [temp length] - r.location - 1;
        ++r.location;
        temp = [temp substringWithRange:r];
    }
    return YES;
}


@end

@implementation PasteboardEntry

@end

@implementation PasteboardHistory

- (id)initWithMaxEntries:(int)maxEntries
{
    if (![super init]) {
        return nil;
    }
    maxEntries_ = maxEntries;
    entries_ = [[NSMutableArray alloc] init];
    return self;
}

- (void)dealloc
{
    [entries_ release];
    [super dealloc];
}

- (NSArray*)entries
{
    return entries_;
}

- (void)save:(NSString*)value
{
    value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![value length]) {
        return;
    }

    // Remove existing duplicate value.
    for (int i = 0; i < [entries_ count]; ++i) {
        PasteboardEntry* entry = [entries_ objectAtIndex:i];
        if ([entry->value isEqualToString:value]) {
            [entries_ removeObjectAtIndex:i];
            break;
        }
    }
    
    // Append this value.
    PasteboardEntry* entry = [[PasteboardEntry alloc] init];
    entry->value = value;
    [entry->value retain];
    entry->timestamp = [[NSDate alloc] init];
    [entries_ addObject:entry];
    [entry release];
    if ([entries_ count] == maxEntries_) {
        [entries_ removeObjectAtIndex:0];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:kPasteboardHistoryDidChange 
                                                        object:self];
}

@end

@implementation PasteboardHistoryWindow

- (id)initWithContentRect:(NSRect)contentRect
                styleMask:(NSUInteger)aStyle
                backing:(NSBackingStoreType)bufferingType
                    defer:(BOOL)flag
{
    self = [super initWithContentRect:contentRect
                            styleMask:NSBorderlessWindowMask
                              backing:bufferingType
                                defer:flag];

    return self;
}

- (BOOL)canBecomeKeyWindow
{
    return YES;
}

- (void)keyDown:(NSEvent *)event
{
    id cont = [self windowController];
    if (cont && [cont respondsToSelector:@selector(keyDown:)]) {
        [cont keyDown:event];
    }
}

@end

@implementation PasteboardHistoryView

- (id)init
{
    self = [super initWithWindowNibName:@"PasteboardHistory"];
    if (!self) {
        return nil;
    }

    [self window];
    return self;
}

- (void)setDataSource:(PasteboardHistory*)dataSource
{
    model_ = [[PasteboardModel alloc] initWithHistory:dataSource];
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(pasteboardHistoryDidChange:) 
                                                 name:kPasteboardHistoryDidChange 
                                               object:nil];
}

- (void)dealloc
{
    [model_ release];
    [super dealloc];
}

- (void)pasteboardHistoryDidChange:(id)sender
{
    [self refresh];
}

- (void)refresh
{
    [model_ reload];
    [table_ reloadData];

    NSRect frame = [[self window] frame];
    float diff = frame.size.height;
    frame.size.height = [[table_ headerView] frame].size.height + [model_ numberOfEntries] * ([table_ rowHeight] + [table_ intercellSpacing].height);    
    diff -= frame.size.height;
    if (!onTop_) {
        frame.origin.y += diff;
    }
    [[self window] setFrame:frame display:NO];
    [table_ sizeToFit];
    [[table_ enclosingScrollView] setHasHorizontalScroller:NO];

    if ([table_ selectedRow] == -1 && [table_ numberOfRows] > 0) {
        NSIndexSet* indexes = [NSIndexSet indexSetWithIndex:0];
        [table_ selectRowIndexes:indexes byExtendingSelection:NO];
    }
}

- (void)setOnTop:(BOOL)onTop
{
    onTop_ = onTop;
}

- (void)windowDidResignKey:(NSNotification *)aNotification
{
    NSLog(@"resigned");
    [[self window] close];
    clearFilterOnNextKeyDown_ = NO;
    if (timer_) {
        [timer_ invalidate];
        timer_ = nil;
    }
    [minuteRefreshTimer_ invalidate];
    minuteRefreshTimer_ = nil;
    [model_ clearFilter];
}

- (void)windowDidBecomeKey:(NSNotification *)aNotification
{
    clearFilterOnNextKeyDown_ = NO;
    if (timer_) {
        [timer_ invalidate];
        timer_ = nil;
    }
    [model_ clearFilter];
    [self refresh];
    if ([table_ numberOfRows] > 0) {
        NSIndexSet* indexes = [NSIndexSet indexSetWithIndex:0];
        [table_ selectRowIndexes:indexes byExtendingSelection:NO];
    }
    // Redraw window once a minute so the time column is always correct.
    minuteRefreshTimer_ = [NSTimer scheduledTimerWithTimeInterval:61
                                                           target:self
                                                         selector:@selector(pasteboardHistoryDidChange:)
                                                         userInfo:nil
                                                          repeats:YES];
}


// DataSource methods
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [model_ numberOfEntries];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    PasteboardEntry* entry = [model_ entryAtIndex:rowIndex];
    if ([[aTableColumn identifier] isEqualToString:@"date"]) {
        // Date
        return [NSDateFormatter dateDifferenceStringFromDate:entry->timestamp];
    } else {
        // Contents
        return [model_ attributedStringForValue:entry->value];
    }
}

- (void)rowSelected:(id)sender;
{
    if ([table_ selectedRow] >= 0) {
        PasteboardEntry* entry = [model_ entryAtIndex:[table_ selectedRow]];
        NSPasteboard* thePasteboard = [NSPasteboard generalPasteboard];
        [thePasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
        [thePasteboard setString:entry->value forType:NSStringPboardType];
        [[self window] close];
        [[[iTermController sharedInstance] frontTextView] paste:nil];
    }
}

- (void)keyDown:(NSEvent*)event
{
    unichar c = [[event characters] characterAtIndex:0];
    if (c == '\r') {
        [self rowSelected:self];
    } else if (c == 8 || c == 127) {
        // backspace
        [model_ clearFilter];
        if (timer_) {
            [timer_ invalidate];
            timer_ = nil;
        }
        clearFilterOnNextKeyDown_ = NO;
        [self refresh];
    } else if (!iswcntrl(c)) {
        if (clearFilterOnNextKeyDown_) {
            [model_ clearFilter];
            clearFilterOnNextKeyDown_ = NO;
        }
        [model_ appendString:[event characters]];
        [self refresh];
        if (timer_) {
            [timer_ invalidate];
        }
        timer_ = [NSTimer scheduledTimerWithTimeInterval:4
                                                  target:self
                                                selector:@selector(_setClearFilterOnNextKeyDownFlag:)
                                                userInfo:nil
                                                 repeats:NO];
    } else if (c == 27) {
        // Escape
        [[self window] close];
    }
}

- (void)_setClearFilterOnNextKeyDownFlag:(id)sender
{
    clearFilterOnNextKeyDown_ = YES;
    timer_ = nil;
}

@end
