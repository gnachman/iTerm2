// -*- mode:objc -*-
/*
 **  PasteboardHistory.h
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



#import <Cocoa/Cocoa.h>
#import "iTermPopupWindowController.h"
#import "PTYTextView.h"
#import "PopupEntry.h"
#import "VT100Screen.h"

#define kPasteboardHistoryDidChange @"PasteboardHistoryDidChange"

@interface PasteboardEntry : PopupEntry

@property(nonatomic, retain) NSDate *timestamp;

+ (PasteboardEntry*)entryWithString:(NSString *)s score:(double)score;

@end

@interface PasteboardHistory : NSObject

+ (instancetype)sharedInstance;
- (instancetype)initWithMaxEntries:(int)maxEntries;
- (NSArray<PasteboardEntry *> *)entries;
- (void)save:(NSString*)value;

// Erases persistent history, but not in-memory.
- (void)eraseHistory;

// Erases in-memory history but not persistent copy.
- (void)clear;

- (void)_loadHistoryFromDisk;
- (void)_writeHistoryToDisk;

@end

@interface PasteboardHistoryWindowController : iTermPopupWindowController

- (void)pasteboardHistoryDidChange:(id)sender;
- (void)copyFromHistory;
- (void)refresh;
- (void)onOpen;
- (void)onClose;
- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex;
- (void)rowSelected:(id)sender;;

@end

