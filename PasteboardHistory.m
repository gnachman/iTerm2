// -*- mode:objc -*-
/*
 **  PasteboardHistory.m
 **
 **  Copyright 2010
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: Remembers pasteboard contents and offers a UI to access old
 **  entries.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <wctype.h>
#import "PasteboardHistory.h"
#import "iTerm/iTermController.h"
#import "NSDateFormatterExtras.h"
#define kPasteboardHistoryDidChange @"PasteboardHistoryDidChange"

@implementation PasteboardEntry

+ (PasteboardEntry*)entryWithString:(NSString *)s score:(double)score
{
    PasteboardEntry* e = [[[PasteboardEntry alloc] init] autorelease];
    [e setMainValue:s];
    [e setScore:score];
    [e setPrefix:@""];
    return e;
}

- (NSDate*)timestamp
{
    return timestamp;
}

@end

@implementation PasteboardHistory

+ (PasteboardHistory*)sharedInstance
{
    static PasteboardHistory* instance;
    if (!instance) {
        instance = [[PasteboardHistory alloc] initWithMaxEntries:20];
    }
    return instance;
}

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
        if ([[entry mainValue] isEqualToString:value]) {
            [entries_ removeObjectAtIndex:i];
            break;
        }
    }

    // If the last value is a prefix of this value then remove it. This prevents
    // pressing tab in the findbar from filling the history with various
    // versions of the same thing.
    PasteboardEntry* lastEntry;
    if ([entries_ count] > 0) {
        lastEntry = [entries_ objectAtIndex:[entries_ count] - 1];
        if ([value hasPrefix:[lastEntry mainValue]]) {
            [entries_ removeObjectAtIndex:[entries_ count] - 1];
        }
    }

    // Append this value.
    PasteboardEntry* entry = [PasteboardEntry entryWithString:value score:-[entries_ count]];
    entry->timestamp = [[NSDate alloc] init];
    [entries_ addObject:entry];
    if ([entries_ count] == maxEntries_) {
        [entries_ removeObjectAtIndex:0];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:kPasteboardHistoryDidChange
                                                        object:self];
}

@end

@implementation PasteboardHistoryView

- (id)init
{
    self = [super initWithWindowNibName:@"PasteboardHistory" tablePtr:&table_ model:[[[PopupModel alloc] init] autorelease]];
    if (!self) {
        return nil;
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(pasteboardHistoryDidChange:)
                                                 name:kPasteboardHistoryDidChange
                                               object:nil];

    return self;
}

- (void)dealloc
{
    [super dealloc];
}

- (void)pasteboardHistoryDidChange:(id)sender
{
    [self refresh];
}

- (void)copyFromHistory
{
    [[self unfilteredModel] removeAllObjects];
    for (PasteboardEntry* e in [[PasteboardHistory sharedInstance] entries]) {
        [[self unfilteredModel] addObject:e];
    }
}

- (void)refresh
{
    [self copyFromHistory];
    [self reloadData:YES];
}

- (void)onOpen
{
    [self copyFromHistory];
    if (!minuteRefreshTimer_) {
        minuteRefreshTimer_ = [NSTimer scheduledTimerWithTimeInterval:61
                                                               target:self
                                                             selector:@selector(pasteboardHistoryDidChange:)
                                                             userInfo:nil
                                                              repeats:YES];
    }
}

- (void)onClose
{
    if (minuteRefreshTimer_) {
        [minuteRefreshTimer_ invalidate];
        minuteRefreshTimer_ = nil;
    }
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    PasteboardEntry* entry = [[self model] objectAtIndex:[self convertIndex:rowIndex]];
    if ([[aTableColumn identifier] isEqualToString:@"date"]) {
        // Date
        return [NSDateFormatter dateDifferenceStringFromDate:entry->timestamp];
    } else {
        // Contents
        return [super tableView:aTableView objectValueForTableColumn:aTableColumn row:rowIndex];
    }
}

- (void)rowSelected:(id)sender;
{
    if ([table_ selectedRow] >= 0) {
        PasteboardEntry* entry = [[self model] objectAtIndex:[self convertIndex:[table_ selectedRow]]];
        NSPasteboard* thePasteboard = [NSPasteboard generalPasteboard];
        [thePasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
        [thePasteboard setString:[entry mainValue] forType:NSStringPboardType];
        [[[iTermController sharedInstance] frontTextView] paste:nil];
        [super rowSelected:sender];
    }
}

@end
