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
#import "VT100Screen.h"
#import "PTYTextView.h"
#import "Popup.h"

@interface PasteboardEntry : PopupEntry {
    @public
    NSDate* timestamp;
}

+ (PasteboardEntry*)entryWithString:(NSString *)s score:(double)score;
- (NSDate*)timestamp;

@end

@interface PasteboardHistory : NSObject {
    NSMutableArray* entries_;
    int maxEntries_;
    NSString* path_;
}

+ (PasteboardHistory*)sharedInstance;
- (id)initWithMaxEntries:(int)maxEntries;
- (void)dealloc;
- (NSArray*)entries;
- (void)save:(NSString*)value;
- (void)eraseHistory;

- (void)_loadHistoryFromDisk;
- (void)_writeHistoryToDisk;

@end

@interface PasteboardHistoryView : Popup
{
    IBOutlet NSTableView* table_;
    NSTimer* minuteRefreshTimer_;
}

- (id)init;
- (void)dealloc;
- (void)pasteboardHistoryDidChange:(id)sender;
- (void)copyFromHistory;
- (void)refresh;
- (void)onOpen;
- (void)onClose;
- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex;
- (void)rowSelected:(id)sender;;

@end

