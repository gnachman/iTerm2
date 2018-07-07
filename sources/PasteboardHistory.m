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
#import "NSDateFormatterExtras.h"
#import "PopupModel.h"
#import "iTermController.h"
#import "iTermPreferences.h"
#import "iTermAdvancedSettingsModel.h"

#define PBHKEY_ENTRIES @"Entries"
#define PBHKEY_VALUE @"Value"
#define PBHKEY_TIMESTAMP @"Timestamp"

@implementation PasteboardEntry

+ (PasteboardEntry*)entryWithString:(NSString *)s score:(double)score
{
    PasteboardEntry *e = [[[PasteboardEntry alloc] init] autorelease];
    [e setMainValue:s];
    [e setScore:score];
    [e setPrefix:@""];
    return e;
}

- (void)dealloc {
    [_timestamp release];
    [super dealloc];
}

@end

@implementation PasteboardHistory {
    NSMutableArray *entries_;
    int maxEntries_;
    NSString *path_;
}

+ (int)maxEntries
{
    return [iTermAdvancedSettingsModel pasteHistoryMaxOptions];
}

+ (PasteboardHistory*)sharedInstance {
    static PasteboardHistory *instance;
    if (!instance) {
        int maxEntries = [PasteboardHistory maxEntries];
        // MaxPasteHistoryEntries is a legacy thing. I'm not removing it because it's a security
        // issue for some people.
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"MaxPasteHistoryEntries"]) {
            maxEntries = [[NSUserDefaults standardUserDefaults] integerForKey:@"MaxPasteHistoryEntries"];
            if (maxEntries < 0) {
                maxEntries = 0;
            }
        }
        instance = [[PasteboardHistory alloc] initWithMaxEntries:maxEntries];
    }
    return instance;
}

- (instancetype)initWithMaxEntries:(int)maxEntries {
    self = [super init];
    if (self) {
        maxEntries_ = maxEntries;
        entries_ = [[NSMutableArray alloc] init];


        path_ = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) lastObject];
        NSString *appname = [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleNameKey];
        path_ = [path_ stringByAppendingPathComponent:appname];
        [[NSFileManager defaultManager] createDirectoryAtPath:path_ withIntermediateDirectories:YES attributes:nil error:NULL];
        path_ = [[path_ stringByAppendingPathComponent:@"pbhistory.plist"] copyWithZone:[self zone]];

        [self _loadHistoryFromDisk];
    }
    return self;
}

- (void)dealloc
{
    [path_ release];
    [entries_ release];
    [super dealloc];
}

- (NSArray*)entries
{
    return entries_;
}

- (NSDictionary*)_entriesToDict {
    NSMutableArray *a = [[[NSMutableArray alloc] init] autorelease];

    for (PasteboardEntry *entry in entries_) {
        [a addObject:[NSDictionary dictionaryWithObjectsAndKeys:[entry mainValue], PBHKEY_VALUE,
                      [NSNumber numberWithDouble:[entry.timestamp timeIntervalSinceReferenceDate]], PBHKEY_TIMESTAMP,
                      nil]];
    }
    return [NSDictionary dictionaryWithObject:a forKey:PBHKEY_ENTRIES];
}

- (void)_addDictToEntries:(NSDictionary*)dict {
    NSArray *a = [dict objectForKey:PBHKEY_ENTRIES];
    for (NSDictionary *d in a) {
        double timestamp = [[d objectForKey:PBHKEY_TIMESTAMP] doubleValue];
        PasteboardEntry *entry = [PasteboardEntry entryWithString:[d objectForKey:PBHKEY_VALUE] score:timestamp];
        entry.timestamp = [NSDate dateWithTimeIntervalSinceReferenceDate:timestamp];
        [entries_ addObject:entry];
    }
}

- (void)clear
{
    [entries_ removeAllObjects];
}

- (void)eraseHistory
{
    [[NSFileManager defaultManager] removeItemAtPath:path_ error:NULL];
}

- (void)_writeHistoryToDisk
{
    if ([iTermPreferences boolForKey:kPreferenceKeySavePasteAndCommandHistory]) {
        [NSKeyedArchiver archiveRootObject:[self _entriesToDict] toFile:path_];
        [[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: @0600 }
                                         ofItemAtPath:path_
                                                error:nil];
    }
}

- (void)_loadHistoryFromDisk
{
    [entries_ removeAllObjects];
    [self _addDictToEntries:[NSKeyedUnarchiver unarchiveObjectWithFile:path_]];
}

- (void)save:(NSString*)value
{
    value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![value length]) {
        return;
    }

    // Remove existing duplicate value.
    for (int i = 0; i < [entries_ count]; ++i) {
        PasteboardEntry *entry = [entries_ objectAtIndex:i];
        if ([[entry mainValue] isEqualToString:value]) {
            [entries_ removeObjectAtIndex:i];
            break;
        }
    }

    // If the last value is a prefix of this value then remove it. This prevents
    // pressing tab in the findbar from filling the history with various
    // versions of the same thing.
    PasteboardEntry *lastEntry;
    if ([entries_ count] > 0) {
        lastEntry = [entries_ objectAtIndex:[entries_ count] - 1];
        if ([value hasPrefix:[lastEntry mainValue]]) {
            [entries_ removeObjectAtIndex:[entries_ count] - 1];
        }
    }

    // Append this value.
    PasteboardEntry *entry = [PasteboardEntry entryWithString:value score:[[NSDate date] timeIntervalSince1970]];
    entry.timestamp = [NSDate date];
    [entries_ addObject:entry];
    if ([entries_ count] > maxEntries_) {
        [entries_ removeObjectAtIndex:0];
    }

    [self _writeHistoryToDisk];

    [[NSNotificationCenter defaultCenter] postNotificationName:kPasteboardHistoryDidChange
                                                        object:self];
}

@end

@implementation PasteboardHistoryWindowController {
    IBOutlet NSTableView *table_;
    NSTimer *minuteRefreshTimer_;
}

- (instancetype)init {
    self = [super initWithWindowNibName:@"PasteboardHistory" tablePtr:nil model:[[[PopupModel alloc] init] autorelease]];
    if (!self) {
        return nil;
    }

    [self setTableView:table_];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(pasteboardHistoryDidChange:)
                                                 name:kPasteboardHistoryDidChange
                                               object:nil];

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)pasteboardHistoryDidChange:(id)sender
{
    [self refresh];
}

- (void)copyFromHistory {
    [[self unfilteredModel] removeAllObjects];
    for (PasteboardEntry *e in [[PasteboardHistory sharedInstance] entries]) {
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
    [self.delegate popupWillClose:self];
    [self setDelegate:nil];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
    PasteboardEntry *entry = [[self model] objectAtIndex:[self convertIndex:rowIndex]];
    if ([[aTableColumn identifier] isEqualToString:@"date"]) {
        // Date
        return [NSDateFormatter dateDifferenceStringFromDate:entry.timestamp];
    } else {
        // Contents
        return [super tableView:aTableView objectValueForTableColumn:aTableColumn row:rowIndex];
    }
}

- (void)rowSelected:(id)sender {
    if ([table_ selectedRow] >= 0) {
        PasteboardEntry *entry = [[self model] objectAtIndex:[self convertIndex:[table_ selectedRow]]];
        NSPasteboard *thePasteboard = [NSPasteboard generalPasteboard];
        [thePasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
        [thePasteboard setString:[entry mainValue] forType:NSStringPboardType];
        [[[iTermController sharedInstance] frontTextView] paste:nil];
        [super rowSelected:sender];
    }
}

@end

