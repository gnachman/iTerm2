// Base classes for popup windows like autocomplete and pasteboardhistory.

#import "iTermPopupWindowController.h"
#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermPreferences.h"
#import "NSObject+iTerm.h"
#import "NSTextField+iTerm.h"
#import "NSView+iTerm.h"
#import "NSWindow+PSM.h"
#import "PopupEntry.h"
#import "PopupModel.h"
#import "PopupWindow.h"
#import "SolidColorView.h"
#import "VT100Screen.h"

#import <QuartzCore/QuartzCore.h>
#include <wctype.h>

#define PopLog DLog

@interface iTermPopupWindowController()<NSMenuItemValidation>
@end

@implementation iTermPopupWindowController {
    // Subclass-owned tableview.
    NSTableView* tableView_;

    // Results currently being displayed.
    PopupModel* model_;

    // All candidate results, including those not matching filter. Subclass-owned.
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

    NSString *footerString_;
    NSTextField *footerView_;
    NSView *_footerBackground;
}

- (instancetype)initWithWindowNibName:(NSString*)nibName tablePtr:(NSTableView**)table model:(PopupModel*)model {
    self = [super initWithWindowNibName:nibName];
    if (self) {
        if (table) {
            tableView_ = [*table retain];
        }
        model_ = [[PopupModel alloc] init];
        substring_ = [[NSMutableString alloc] init];
        unfilteredModel_ = [model retain];
        selectionMainValue_ = [[NSMutableString alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [tableView_ setDelegate:nil];
    [tableView_ setDataSource:nil];
    [selectionMainValue_ release];
    [unfilteredModel_ release];
    [substring_ release];
    [model_ release];
    [tableView_ release];
    [footerString_ release];
    [footerView_ release];
    [_footerBackground release];
    [super dealloc];
}

- (void)awakeFromNib {
    [super awakeFromNib];
    NSVisualEffectView *vev = [[[NSVisualEffectView alloc] init] autorelease];
    vev.wantsLayer = YES;
    vev.layer.cornerRadius = 4;
    vev.material = NSVisualEffectMaterialSheet;
    [self.window.contentView insertSubview:vev atIndex:0];
    vev.frame = self.window.contentView.bounds;
    vev.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    footerString_ = [[self footerString] copy];
    if (!footerString_) {
        return;
    }

    footerView_ = [NSTextField newLabelStyledTextField];
    footerView_.stringValue = footerString_;
    [self.window.contentView addSubview:footerView_];
    [footerView_ sizeToFit];
    const CGFloat footerHeight = footerView_.frame.size.height;
    footerView_.frame = NSMakeRect(0, self.footerMargin, self.window.contentView.frame.size.width - footerHeight, footerHeight);
    footerView_.autoresizingMask = (NSViewWidthSizable | NSViewMaxYMargin);

    _footerBackground = [[NSView alloc] init];
    _footerBackground.wantsLayer = YES;
    [_footerBackground makeBackingLayer];
    _footerBackground.layer.backgroundColor = [[NSColor colorWithWhite:0.5 alpha:1] CGColor];
    _footerBackground.layer.opacity = 0.2;
    _footerBackground.layer.cornerRadius = 4;
    _footerBackground.layer.maskedCorners = (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner);
    _footerBackground.frame = NSMakeRect(0, 0, self.window.contentView.frame.size.width, footerHeight + self.footerMargin * 1.5);
    _footerBackground.autoresizingMask = NSViewWidthSizable;
    [self.window.contentView insertSubview:_footerBackground atIndex:1];

    NSRect frame = [[tableView_ enclosingScrollView] frame];
    frame.size.height = MAX(0, frame.size.height - footerHeight);
    frame.origin.y += footerHeight;
    [[tableView_ enclosingScrollView] setFrame:frame];
}

- (void)shutdown
{
    // Disable the fancy footwork in -[PopupWindow close]
    [(PopupWindow *)[self window] shutdown];

    // Prevent twiddleKeyWindow from running after parent window is dealloc'ed.
    [NSObject cancelPreviousPerformRequestsWithTarget:[self window]];

    // Force the window to close immediately.
    [self close];
}

- (void)setTableView:(NSTableView *)table {
    [tableView_ autorelease];
    tableView_ = [table retain];
}

- (BOOL)disableFocusFollowsMouse
{
    return YES;
}

- (BOOL)implementsDisableFocusFollowsMouse {
    return YES;
}

- (PopupWindow *)popupWindow {
    return (PopupWindow *)self.window;
}

- (void)popWithDelegate:(id<PopupDelegate>)delegate
               inWindow:(NSWindow *)owningWindow {
    self.delegate = delegate;

    [self.popupWindow setOwningWindow:owningWindow];

    static const NSTimeInterval kAnimationDuration = 0.15;
    self.window.alphaValue = 0;
    if (delegate.popupWindowIsInFloatingHotkeyWindow) {
        self.window.styleMask = NSWindowStyleMaskNonactivatingPanel;
        self.window.collectionBehavior = (NSWindowCollectionBehaviorCanJoinAllSpaces |
                                          NSWindowCollectionBehaviorIgnoresCycle |
                                          NSWindowCollectionBehaviorFullScreenAuxiliary);
        self.window.level = NSPopUpMenuWindowLevel;
        [self.window makeKeyAndOrderFront:nil];
    } else {
        [self showWindow:nil];
        [[self window] makeKeyAndOrderFront:nil];
    }
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:kAnimationDuration];
    self.window.animator.alphaValue = 1;
    [NSAnimationContext endGrouping];
}

#pragma mark - NSResponder Hacks

// When a popup window is open we will forward some actions to the "real" responder in the owning
// window. We have to implement the methods in question so that the SDK will enable them in the
// menu.
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    for (NSResponder *responder in self.allResponders) {
        if ([responder respondsToSelector:@selector(validateMenuItem:)] &&
            [responder validateMenuItem:menuItem]) {
            return YES;
        }
    }
    return NO;
}

- (NSArray *)allResponders {
    NSMutableArray *responders = [NSMutableArray array];
    NSResponder *responder = [self.popupWindow.owningWindow firstResponder];
    while (responder) {
        [responders addObject:responder];
        responder = [responder nextResponder];
    }
    return responders;
}

- (void)paste:(id)sender {
    [self.popupWindow.owningWindow.firstResponder tryToPerform:_cmd with:sender];
}

- (void)copy:(id)sender {
    [self.popupWindow.owningWindow.firstResponder tryToPerform:_cmd with:sender];
}

- (void)copyWithStyles:(id)sender {
    [self.popupWindow.owningWindow.firstResponder tryToPerform:_cmd with:sender];
}

- (void)selectAll:(id)sender {
    [self.popupWindow.owningWindow.firstResponder tryToPerform:_cmd with:sender];
}

- (void)selectOutputOfLastCommand:(id)sender {
    [self.popupWindow.owningWindow.firstResponder tryToPerform:_cmd with:sender];
}

- (PopupModel*)unfilteredModel
{
    return unfilteredModel_;
}

- (PopupModel*)model
{
    return model_;
}

- (void)onClose
{
    clearFilterOnNextKeyDown_ = NO;
    if (timer_) {
        [timer_ invalidate];
        timer_ = nil;
    }
    [substring_ setString:@""];
    [_delegate popupWillClose:self];
    self.delegate = nil;
}

- (void)onOpen
{
}

- (void)reloadData:(BOOL)canChangeSide
{
    [model_ removeAllObjects];
    [unfilteredModel_ sortByScore];
    for (PopupEntry* s in unfilteredModel_) {
        if ([self _word:[self truncatedMainValueForEntry:s] matchesFilter:substring_]) {
            [model_ addObject:s];
        }
    }
    BOOL oldReloading = reloading_;
    reloading_ = YES;
    [tableView_ reloadData];
    [self setPosition:canChangeSide];
    [tableView_ sizeToFit];
    [[tableView_ enclosingScrollView] setHasHorizontalScroller:NO];

    if (!haveChangedSelection_ && [tableView_ numberOfRows] > 0) {
        NSIndexSet* indexes = [NSIndexSet indexSetWithIndex:[self convertIndex:0]];
        [tableView_ selectRowIndexes:indexes byExtendingSelection:NO];
    } else if (haveChangedSelection_ && [tableView_ numberOfRows] > 0) {
        int i = [model_ indexOfObjectWithMainValue:selectionMainValue_];
        if (i >= 0) {
            NSIndexSet* indexes = [NSIndexSet indexSetWithIndex:[self convertIndex:i]];
            [tableView_ selectRowIndexes:indexes byExtendingSelection:NO];
        }
    }
    reloading_ = oldReloading;
}

- (int)convertIndex:(int)i
{
    return onTop_ ? [model_ count] - i - 1 : i;
}

- (void)_setClearFilterOnNextKeyDownFlag:(id)sender
{
    clearFilterOnNextKeyDown_ = YES;
    timer_ = nil;
}

- (CGFloat)footerMargin {
    return 4;
}

- (CGFloat)desiredHeight {
    CGFloat height = [[tableView_ headerView] frame].size.height + MIN(20, [model_ count]) * ([tableView_ rowHeight] + [tableView_ intercellSpacing].height);
    if (@available(macOS 10.16, *)) {
        // Fudge factor
        height += 20;
    }
    if (footerView_) {
        height += footerView_.frame.size.height + self.footerMargin * 2;
    }
    return height;
}

- (void)setPosition:(BOOL)canChangeSide
{
    BOOL onTop = NO;

    id<iTermPopupWindowPresenter> presenter = [self.delegate popupPresenter];
    [presenter popupWindowWillPresent:self];

    NSRect frame = [[self window] frame];
    frame.size.height = self.desiredHeight;

    const NSRect cursorRect = [presenter popupWindowOriginRectInScreenCoords];
    NSPoint p = cursorRect.origin;
    p.y -= frame.size.height;

    NSRect monitorFrame = [self.delegate popupScreenVisibleFrame];

    if (canChangeSide) {
        // p.y gives the bottom of the frame relative to the bottom of the screen, assuming it's below the cursor.
        float bottomOverflow = monitorFrame.origin.y - p.y;
        float topOverflow = p.y + 2 * frame.size.height + NSHeight(cursorRect) - (monitorFrame.origin.y + monitorFrame.size.height);
        if (bottomOverflow > 0 && topOverflow < bottomOverflow) {
            onTop = YES;
        }
    } else {
        onTop = onTop_;
    }
    if (onTop) {
        p.y += frame.size.height + NSHeight(cursorRect);
    }
    float rightX = monitorFrame.origin.x + monitorFrame.size.width;
    if (p.x + frame.size.width > rightX) {
        float excess = p.x + frame.size.width - rightX;
        p.x -= excess;
    }

    frame.origin = p;
    [[self window] setFrame:frame display:NO];

    if (footerView_) {
        NSRect frame = [self.window.contentView bounds];
        const CGFloat footerHeight = footerView_.frame.size.height;
        frame.size.height = MAX(0, frame.size.height - footerHeight);
        frame.origin.y += footerHeight;
        tableView_.enclosingScrollView.frame = frame;
    }

    if (canChangeSide) {
        BOOL flip = (onTop != onTop_);
        [self setOnTop:onTop];
        if (flip) {
            BOOL oldReloading = reloading_;
            reloading_ = YES;
            NSIndexSet* indexes = [NSIndexSet indexSetWithIndex:[self convertIndex:[tableView_ selectedRow]]];
            [tableView_ selectRowIndexes:indexes byExtendingSelection:NO];
            reloading_ = oldReloading;
        }
    }
    if (onTop) {
        [tableView_ scrollToEndOfDocument:nil];
    } else {
        [tableView_ scrollToBeginningOfDocument:nil];
    }
}

- (void)setOnTop:(BOOL)onTop
{
    onTop_ = onTop;
}

- (void)moveDown:(id)sender {
    if ([self passKeyEventToDelegateForSelector:_cmd string:nil]) {
        return;
    }
    NSInteger row = tableView_.selectedRow;
    if (row == -1) {
        return;
    }
    if (row + 1 == tableView_.numberOfRows) {
        return;
    }
    [tableView_ selectRowIndexes:[NSIndexSet indexSetWithIndex:row + 1] byExtendingSelection:NO];
}

- (void)moveUp:(id)sender {
    if ([self passKeyEventToDelegateForSelector:_cmd string:nil]) {
        return;
    }
    NSInteger row = tableView_.selectedRow;
    if (row <= 0) {
        return;
    }
    [tableView_ selectRowIndexes:[NSIndexSet indexSetWithIndex:row - 1] byExtendingSelection:NO];
}

- (void)deleteBackward:(id)sender {
    if ([self passKeyEventToDelegateForSelector:_cmd string:nil]) {
        return;
    }
    // backspace
    if (timer_) {
        [timer_ invalidate];
        timer_ = nil;
    }
    clearFilterOnNextKeyDown_ = NO;
    [substring_ setString:@""];
    [self reloadData:NO];
}

- (void)cancel:(id)sender {
    if ([self passKeyEventToDelegateForSelector:_cmd string:nil]) {
        return;
    }
    // Escape
    [self closePopupWindow];
}

- (void)closePopupWindow {
    if ([self.delegate popupWindowShouldAvoidChangingWindowOrderOnClose]) {
        // Weird code path for non-hotkey windows with focus follows mouse when the popup is in a
        // non-front window. We don't want it to order front when the popup closes. This goes
        // against nature so it's a bit of a mess.
        PopupWindow *window = [PopupWindow castFrom:self.window];
        NSWindow *parent = [window owningWindow];
        [window closeWithoutAdjustingWindowOrder];
        // If I call makeKeyWindow synchronously then it orders itself front.
        dispatch_async(dispatch_get_main_queue(), ^{
            [parent makeKeyWindow];
        });
    } else {
        [[self window] close];
    }
    [self onClose];
}

- (void)insertNewline:(id)sender {
    if ([self passKeyEventToDelegateForSelector:_cmd string:nil]) {
        return;
    }
    [self rowSelected:self];
}

- (void)insertText:(NSString *)insertString {
    if ([self passKeyEventToDelegateForSelector:_cmd string:insertString]) {
        return;
    }
    if (clearFilterOnNextKeyDown_) {
        [substring_ setString:@""];
        clearFilterOnNextKeyDown_ = NO;
    }
    [substring_ appendString:insertString];
    [self reloadData:NO];
    if (timer_) {
        [timer_ invalidate];
    }
    timer_ = [NSTimer scheduledTimerWithTimeInterval:4
                                              target:self
                                            selector:@selector(_setClearFilterOnNextKeyDownFlag:)
                                            userInfo:nil
                                             repeats:NO];
}

- (BOOL)passKeyEventToDelegateForSelector:(SEL)selector string:(NSString *)string {
    if ([_delegate respondsToSelector:@selector(popupHandleSelector:string:currentValue:)]) {
        PopupEntry *entry = nil;
        if ([tableView_ selectedRow] >= 0) {
            entry = [[self model] objectAtIndex:[self convertIndex:[tableView_ selectedRow]]];
        }
        if ([_delegate popupHandleSelector:selector string:string currentValue:entry.mainValue]) {
            return YES;
        }
    }
    return NO;
}

- (void)rowSelected:(id)sender {
    [self closePopupWindow];
}

- (NSString *)truncatedMainValueForEntry:(PopupEntry *)entry {
    static const int kMaxLength = 200;
    if ([[entry mainValue] length] > kMaxLength) {
        return [[entry mainValue] substringToIndex:kMaxLength];
    } else {
        return [entry mainValue];
    }
}

- (NSAttributedString *)attributedStringForEntry:(PopupEntry*)entry isSelected:(BOOL)isSelected
{
    float size = [NSFont systemFontSize];
    NSFont* sysFont = [NSFont systemFontOfSize:size];
    NSMutableAttributedString* as = [[[NSMutableAttributedString alloc] init] autorelease];

    NSMutableParagraphStyle *paragraphStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
    paragraphStyle.lineBreakMode = NSLineBreakByTruncatingMiddle;

    NSColor* textColor;
    if (isSelected) {
        textColor = [NSColor selectedMenuItemTextColor];
    } else {
        textColor = [NSColor labelColor];
    }
    NSColor* lightColor = [textColor colorWithAlphaComponent:0.7];
    NSDictionary* lightAttributes = @{ NSFontAttributeName: sysFont,
                                       NSForegroundColorAttributeName: lightColor,
                                       NSParagraphStyleAttributeName: paragraphStyle };
    NSDictionary* plainAttributes = @{ NSFontAttributeName: sysFont,
                                       NSForegroundColorAttributeName: textColor,
                                       NSParagraphStyleAttributeName: paragraphStyle };
    NSDictionary* boldAttributes = @{ NSFontAttributeName: [NSFont boldSystemFontOfSize:size],
                                      NSForegroundColorAttributeName: textColor,
                                      NSParagraphStyleAttributeName: paragraphStyle };

    [as appendAttributedString:[[[NSAttributedString alloc] initWithString:[entry prefix]
                                                                attributes:lightAttributes] autorelease]];
    NSString *truncatedMainValue = [self truncatedMainValueForEntry:entry];
    NSString* value = [truncatedMainValue stringByReplacingOccurrencesOfString:@"\n" withString:@" "];

    NSString* temp = value;
    for (int i = 0; i < [substring_ length]; ++i) {
        unichar wantChar = [substring_ characterAtIndex:i];
        NSRange r = [temp rangeOfString:[NSString stringWithCharacters:&wantChar
                                                                length:1]
                                options:NSCaseInsensitiveSearch];
        if (r.location == NSNotFound) {
            continue;
        }
        NSRange prefix;
        prefix.location = 0;
        prefix.length = r.location;

        NSAttributedString* attributedSubstr;
        if (prefix.length > 0) {
            NSString* substr = [temp substringWithRange:prefix];
            attributedSubstr =
                [[[NSAttributedString alloc] initWithString:substr
                                                 attributes:plainAttributes] autorelease];
            [as appendAttributedString:attributedSubstr];
        }

        unichar matchChar = [temp characterAtIndex:r.location];
        attributedSubstr =
            [[[NSAttributedString alloc] initWithString:[NSString stringWithCharacters:&matchChar
                                                                                length:1]
                                             attributes:boldAttributes] autorelease];
        [as appendAttributedString:attributedSubstr];

        r.length = [temp length] - r.location - 1;
        ++r.location;
        temp = [temp substringWithRange:r];
    }

    if ([temp length] > 0) {
        NSAttributedString* attributedSubstr =
            [[[NSAttributedString alloc] initWithString:temp
                                             attributes:plainAttributes] autorelease];
        [as appendAttributedString:attributedSubstr];
    }

    return [self shrunkToFitAttributedString:as inEntry:entry baseAttributes:plainAttributes];
}

- (NSAttributedString *)shrunkToFitAttributedString:(NSAttributedString *)attributedString
                                            inEntry:(PopupEntry *)entry
                                     baseAttributes:(NSDictionary *)baseAttributes {
    return attributedString;
}

- (BOOL)_word:(NSString*)temp matchesFilter:(NSString*)filter
{
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

// Delegate methods
- (void)windowDidResignKey:(NSNotification *)aNotification {
    [self closePopupWindow];
}

- (void)windowDidBecomeKey:(NSNotification *)aNotification
{
    if (!self.delegate) {
        // A dialog box can cause you to become key after closing because of a
        // race condition with twiddleKeyWindow. But it immediately loses key
        // status again after this. Because it was already closed, there is no
        // delegate at this point and we just return harmlessly.
        return;
    }
    clearFilterOnNextKeyDown_ = NO;
    if (timer_) {
        [timer_ invalidate];
        timer_ = nil;
    }
    [substring_ setString:@""];
    [self onOpen];
    haveChangedSelection_ = NO;
    [selectionMainValue_ setString:@""];
    [self refresh];
    if ([tableView_ numberOfRows] > 0) {
        BOOL oldReloading = reloading_;
        reloading_ = YES;
        NSIndexSet* indexes = [NSIndexSet indexSetWithIndex:[self convertIndex:0]];
        [tableView_ selectRowIndexes:indexes byExtendingSelection:NO];
        reloading_ = oldReloading;
    }
}

- (void)refresh
{
}

- (NSString *)footerString {
    return NULL;
}

// DataSource methods
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [model_ count];
}

// Tableview delegate methods
- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    int i = [self convertIndex:rowIndex];
    PopupEntry* e = [[self model] objectAtIndex:i];
    return [self attributedStringForEntry:e isSelected:[aTableView selectedRow]==rowIndex];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
    if (!reloading_) {
        haveChangedSelection_ = YES;
        int rowNum = [tableView_ selectedRow];
        NSString* s = nil;
        if (rowNum >= 0) {
            [tableView_ scrollRowToVisible:rowNum];
            s = [[model_ objectAtIndex:[self convertIndex:rowNum]] mainValue];
        }
        if (!s) {
            s = @"";
        }
        [selectionMainValue_ setString:s];
    }
    [self previewCurrentRow];
}

- (void)previewCurrentRow {
}

- (BOOL)shouldEscapeShellCharacters {
    return NO;
}
@end
