//
//  Popup.h
//  iTerm
//
//  Created by George Nachman on 11/4/10.
//  Copyright 2010 George Nachman. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "PTYSession.h"

@interface PopupWindow : NSWindow {
    NSWindow* parentWindow_;
    BOOL shutdown_;
}
- (id)initWithContentRect:(NSRect)contentRect
                styleMask:(NSUInteger)aStyle
                  backing:(NSBackingStoreType)bufferingType
                    defer:(BOOL)flag;
- (void)setParentWindow:(NSWindow*)parentWindow;
- (BOOL)canBecomeKeyWindow;
- (void)keyDown:(NSEvent *)event;
- (void)shutdown;

@end

@interface PopupEntry : NSObject
{
    NSString* s_;
    NSString* prefix_;
    double score_;
    double hitMultiplier_;
    NSString *_truncatedValue;
}

@property(nonatomic, readonly) NSString *truncatedValue;

+ (PopupEntry*)entryWithString:(NSString*)s score:(double)score;
- (void)setMainValue:(NSString*)s;
- (void)setScore:(double)score;
- (void)setPrefix:(NSString*)prefix;
- (NSString*)prefix;
- (NSString*)mainValue;
- (double)score;
- (BOOL)isEqual:(id)o;
- (NSComparisonResult)compare:(id)otherObject;
// Update the hit multiplier for a new hit and return its new value
- (double)advanceHitMult;

@end

@interface PopupModel : NSObject
{
    @private
    NSMutableArray* values_;
    int maxEntries_;
}

- (id)init;
- (id)initWithMaxEntries:(int)maxEntries;
- (void)dealloc;
- (NSUInteger)count;
- (void)removeAllObjects;
- (void)addObject:(id)object;
- (void)addHit:(PopupEntry*)object;
- (id)objectAtIndex:(NSUInteger)index;
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)stackbuf count:(NSUInteger)len;
- (NSUInteger)indexOfObject:(id)o;
- (void)sortByScore;
- (int)indexOfObjectWithMainValue:(NSString*)value;

@end


@interface Popup : NSWindowController {
    @private
    // Backing session.
    PTYSession* session_;
    
    // Subclass-owned tableview.
    NSTableView* tableView_;

    // Results currently being displayed.
    PopupModel* model_;
    
    // All candidate results, including those not matching filter. Subclass-owend.
    PopupModel* unfilteredModel_;

    // Timer to set clearFilterOnNextKeyDown_.
    NSTimer* timer_;

    // If set, then next time a key is pressed erase substring_ before appending.
    BOOL clearFilterOnNextKeyDown_;
    // What the user has typed so far to filter result set.
    NSMutableString* substring_;

    // If true then window is above cursor.
    BOOL onTop_;

    // Set to true when the user changes the selected row.
    BOOL haveChangedSelection_;
    // String that the user has selected.
    NSMutableString* selectionMainValue_;

    // True while reloading data.
    BOOL reloading_;
}

- (id)initWithWindowNibName:(NSString*)nibName tablePtr:(NSTableView**)table model:(PopupModel*)model;
- (void)dealloc;

// Call this after initWithWindowNibName:tablePtr:model: if table was nil.
- (void)setTableView:(NSTableView *)table;

// Turn off focus follows mouse while this window is key.
- (BOOL)disableFocusFollowsMouse;

// Called by clients to open window.
- (void)popInSession:(PTYSession*)session;

// Safely shut down the popup when the parent is about to be dealloced. Clients must call this from
// dealloc. It removes possible pending timers.
- (void)shutdown;

// Subclasses may override these methods.
// Begin populating the unfiltered model.
- (void)refresh;

// Notify that a row was selected. Call this method when subclass has accepted
// the selection.
- (void)rowSelected:(id)sender;

// Handle key presses.
- (void)keyDown:(NSEvent*)event;

// Window is closing. Call this method when subclass is done.
- (void)onClose;

// Window is opening. -[refresh] will be called immediately after this returns.
- (void)onOpen;

// Get a value for a table cell. Always returns a value from the model.
- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex;
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification;

- (void)setSession:(PTYSession*)session;
- (void)setOnTop:(BOOL)onTop;
- (PTYSession*)session;
- (PopupModel*)unfilteredModel;
- (PopupModel*)model;
- (void)setPosition:(BOOL)canChangeSide;
- (void)reloadData:(BOOL)canChangeSide;
- (void)_setClearFilterOnNextKeyDownFlag:(id)sender;
- (int)convertIndex:(int)i;
- (NSAttributedString*)attributedStringForEntry:(PopupEntry*)entry isSelected:(BOOL)isSelected;
- (void)windowDidResignKey:(NSNotification *)aNotification;
- (void)windowDidBecomeKey:(NSNotification *)aNotification;
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView;
- (BOOL)_word:(NSString*)temp matchesFilter:(NSString*)filter;


@end
