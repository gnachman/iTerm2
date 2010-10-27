//
//  PasteboardHistory.h
//  iTerm
//
//  Created by George Nachman on 10/25/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface PasteboardEntry : NSObject {
    @public
    NSString* value;
    NSDate* timestamp;
}
@end

@interface PasteboardHistory : NSObject {
    NSMutableArray* entries_;
    int maxEntries_;
}

- (id)initWithMaxEntries:(int)maxEntries;
- (void)dealloc;
- (NSArray*)entries;
- (void)save:(NSString*)value;

@end

@interface PasteboardHistoryWindow : NSWindow {
}
- (id)initWithContentRect:(NSRect)contentRect
                styleMask:(NSUInteger)aStyle
                  backing:(NSBackingStoreType)bufferingType
                    defer:(BOOL)flag;

- (BOOL)canBecomeKeyWindow;
- (void)keyDown:(NSEvent *)event;

@end

@interface PasteboardModel : NSObject
{
    PasteboardHistory* history_;
    NSMutableString* filter_;
    NSMutableArray* entries_;
}

- (id)initWithHistory:(PasteboardHistory*)history;
- (void)dealloc;
- (void)appendString:(NSString*)string;
- (void)clearFilter;
- (int)numberOfEntries;
- (PasteboardEntry*)entryAtIndex:(int)i;
- (void)reload;
- (NSString*)filter;
- (BOOL)_entry:(PasteboardEntry*)entry matchesFilter:(NSString*)filter;

@end

@interface PasteboardHistoryView : NSWindowController
{
    IBOutlet NSTableView* table_;
    PasteboardModel* model_;
    NSTimer* timer_;
    NSTimer* minuteRefreshTimer_;
    BOOL clearFilterOnNextKeyDown_;
}

- (id)init;
- (void)dealloc;
- (void)setDataSource:(PasteboardHistory*)dataSource;
- (void)windowDidResignKey:(NSNotification *)aNotification;
- (void)windowDidBecomeKey:(NSNotification *)aNotification;
- (void)pasteboardHistoryDidChange:(id)sender;
- (void)refresh;

- (void)_setClearFilterOnNextKeyDownFlag:(id)sender;

// DataSource methods
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView;
- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex;

- (void)rowSelected:(id)sender;
- (void)keyDown:(NSEvent*)event;

@end

