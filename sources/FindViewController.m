/*
 **  FindViewController.m
 **
 **  Copyright (c) 2011
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: View controller for find view. Controls the UI layer of
 **    searching a session.
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

#import "FindViewController.h"
#import "DebugLogging.h"
#import "iTerm.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplication.h"
#import "iTermPreferences.h"
#import "iTermProgressIndicator.h"
#import "iTermSystemVersion.h"
#import "NSTextField+iTerm.h"

// This used to be absurdly fast (.075) for reasons neither I nor revision
// history can recall. This looks nicer to my eyes.
static const float kAnimationDuration = 0.2;
static iTermFindMode gFindMode;
static NSString *gSearchString;
static NSSize kFocusRingInset = { 2, 3 };

const CGFloat kEdgeWidth = 3;

@interface iTermSearchFieldCell : NSSearchFieldCell
@property(nonatomic, assign) CGFloat fraction;
@property(nonatomic, readonly) BOOL needsAnimation;
@property(nonatomic, assign) CGFloat alphaMultiplier;
@end

@implementation iTermSearchFieldCell {
    CGFloat _alphaMultiplier;
    NSTimer *_timer;
    BOOL _needsAnimation;
}

- (instancetype)initTextCell:(NSString *)aString  {
    self = [super initTextCell:aString];
    if (self) {
        _alphaMultiplier = 1;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        _alphaMultiplier = 1;
    }
    return self;
}

- (void)setFraction:(CGFloat)fraction {
    if (fraction == 1.0 && _fraction < 1.0) {
        _needsAnimation = YES;
    } else if (fraction < 1.0) {
        _needsAnimation = NO;
    }
    _fraction = fraction;
    _alphaMultiplier = 1;
}

- (void)willAnimate {
    _alphaMultiplier -= 0.05;
    if (_alphaMultiplier <= 0) {
        _needsAnimation = NO;
        _alphaMultiplier = 0;
    }
}

- (void)drawFocusRingMaskWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    if (controlView.frame.origin.y >= 0) {
        [super drawFocusRingMaskWithFrame:NSInsetRect(cellFrame, kFocusRingInset.width, kFocusRingInset.height)
                                   inView:controlView];
    }
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    NSRect originalFrame = cellFrame;
    [[NSColor whiteColor] set];

    BOOL focused = ([controlView respondsToSelector:@selector(currentEditor)] &&
                    [(NSControl *)controlView currentEditor]);

    CGFloat xInset, yInset;
    if (focused) {
        xInset = 2.5;
        yInset = 1.5;
    } else {
        xInset = 0.5;
        yInset = 0.5;
    }
    cellFrame = NSInsetRect(cellFrame, xInset, yInset);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:cellFrame
                                                         xRadius:4
                                                         yRadius:4];
    [path fill];

    [self drawProgressBarInFrame:originalFrame path:path];

    if (!focused) {
        [[NSColor colorWithCalibratedWhite:0.5 alpha:1] set];
        [path setLineWidth:0.25];
        [path stroke];

        cellFrame = NSInsetRect(cellFrame, 0.25, 0.25);
        path = [NSBezierPath bezierPathWithRoundedRect:cellFrame
                                               xRadius:4
                                               yRadius:4];
        [path setLineWidth:0.25];
        [[NSColor colorWithCalibratedWhite:0.7 alpha:1] set];
        [path stroke];
    }

    [self drawInteriorWithFrame:originalFrame inView:controlView];
}

- (void)drawProgressBarInFrame:(NSRect)cellFrame path:(NSBezierPath *)fieldPath {
    [[NSGraphicsContext currentContext] saveGraphicsState];
    [fieldPath addClip];

    const CGFloat maximumWidth = cellFrame.size.width - 1.0;
    NSRect blueRect = NSMakeRect(0, 0, maximumWidth * [self fraction] + kEdgeWidth, cellFrame.size.height);

    const CGFloat alpha = 0.3 * _alphaMultiplier;
    [[NSColor colorWithCalibratedRed:0.6
                               green:0.6
                               blue:1.0
                               alpha:alpha] set];
    NSRectFillUsingOperation(blueRect, NSCompositingOperationSourceOver);

    [[NSGraphicsContext currentContext] restoreGraphicsState];
}

@end

@interface FindState : NSObject

@property(nonatomic, assign) iTermFindMode mode;
@property(nonatomic, copy) NSString *string;

@end

@implementation FindState

- (instancetype)init {
    self = [super init];
    if (self) {
        _string = [@"" retain];
    }
    return self;
}

- (void)dealloc {
    [_string release];
    [super dealloc];
}

@end

@interface FindViewController()<NSSearchFieldDelegate>
@end

@implementation FindViewController {
    __weak IBOutlet NSSearchField* findBarTextField_;

    FindState *savedState_;
    FindState *state_;

    // Find runs out of a timer so that if you have a huge buffer then it
    // doesn't lock up. This timer runs the show.
    NSTimer* timer_;

    // Fades out the progress indicator.
    NSTimer *_animationTimer;

    id<FindViewControllerDelegate> delegate_;
    NSRect fullFrame_;
    NSSize textFieldSize_;
    NSSize textFieldSmallSize_;

    // Last time the text field was edited.
    NSTimeInterval lastEditTime_;
    enum {
        kFindViewDelayStateEmpty,
        kFindViewDelayStateDelaying,
        kFindViewDelayStateActiveShort,
        kFindViewDelayStateActiveMedium,
        kFindViewDelayStateActiveLong,
    } delayState_;
}


+ (void)initialize {
    NSNumber *mode = [[NSUserDefaults standardUserDefaults] objectForKey:@"findMode_iTerm"];
    if (!mode) {
        // Migrate legacy value.
        NSNumber *ignoreCase = [[NSUserDefaults standardUserDefaults] objectForKey:@"findIgnoreCase_iTerm"];
        BOOL caseSensitive = ignoreCase ? ![ignoreCase boolValue] : NO;
        BOOL isRegex = [[NSUserDefaults standardUserDefaults] boolForKey:@"findRegex_iTerm"];

        if (caseSensitive && isRegex) {
            gFindMode = iTermFindModeCaseSensitiveRegex;
        } else if (!caseSensitive && isRegex) {
            gFindMode = iTermFindModeCaseInsensitiveRegex;
        } else if (caseSensitive && !isRegex) {
            gFindMode = iTermFindModeCaseSensitiveSubstring;
        } else if (!caseSensitive && !isRegex) {
            gFindMode = iTermFindModeSmartCaseSensitivity;  // Upgrade case-insensitive substring to smart case sensitivity.
        }
    } else {
        // Modern value
        gFindMode = [mode unsignedIntegerValue];
    }
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        ITERM_IGNORE_PARTIAL_BEGIN
        [findBarTextField_ setDelegate:self];
        ITERM_IGNORE_PARTIAL_END
        state_ = [[FindState alloc] init];
        state_.mode = gFindMode;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_loadFindStringFromSharedPasteboard)
                                                     name:@"iTermLoadFindStringFromSharedPasteboard"
                                                   object:nil];
        [self loadView];
        self.view.wantsLayer = [iTermPreferences boolForKey:kPreferenceKeyUseMetal];
        [[self view] setHidden:YES];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (timer_) {
        [timer_ invalidate];
        timer_ = nil;
    }
    [state_ release];
    [savedState_ release];
    [super dealloc];
}

- (NSRect)superframe
{
    return [[[self view] superview] frame];
}

- (void)setFrameOrigin:(NSPoint)p
{
    [[self view] setFrameOrigin:p];
    if (fullFrame_.size.width == 0) {
        fullFrame_ = [[self view] frame];
        fullFrame_.origin.y -= [self superframe].size.height;
        fullFrame_.origin.x -= [self superframe].size.width;

        textFieldSize_ = [findBarTextField_ frame].size;
        textFieldSmallSize_ = textFieldSize_;
    }
}

- (void)_loadFindStringFromSharedPasteboard
{
    if (![findBarTextField_ textFieldIsFirstResponder]) {
        NSPasteboard* findBoard = [NSPasteboard pasteboardWithName:NSFindPboard];
        if ([[findBoard types] containsObject:NSStringPboardType]) {
            NSString *value = [findBoard stringForType:NSStringPboardType];
            if (value && [value length] > 0) {
                if (savedState_ && ![value isEqualTo:savedState_.string]) {
                    [self restoreState];
                }
                [findBarTextField_ setStringValue:value];
            }
        }
    }
}

- (IBAction)closeFindView:(id)sender {
    [self close];
}

- (NSRect)collapsedFrame {
    return NSMakeRect([[self view] frame].origin.x,
                      fullFrame_.origin.y + [self superframe].size.height + fullFrame_.size.height,
                      [[self view] frame].size.width,
                      0);
}

- (NSRect)fullSizeFrame {
    return NSMakeRect([[self view] frame].origin.x,
                      fullFrame_.origin.y + [self superframe].size.height,
                      [[self view] frame].size.width,
                      fullFrame_.size.height);
}

- (void)close {
    [self updateDelayState];
    BOOL wasHidden = [[self view] isHidden];
    if (!wasHidden && timer_) {
        [timer_ invalidate];
        timer_ = nil;
    }

    DLog(@"Closing find view %@", self.view);
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setCompletionHandler:^{
        [[self view] setHidden:YES];
        [[[[self view] window] contentView] setNeedsDisplay:YES];
        _isVisible = NO;
        [self.delegate findViewControllerVisibilityDidChange:self];
    }];
    [[NSAnimationContext currentContext] setDuration:kAnimationDuration];
    [[[self view] animator] setFrame:[self collapsedFrame]];
    [NSAnimationContext endGrouping];

    [delegate_ findViewControllerClearSearch];
    [delegate_ findViewControllerMakeDocumentFirstResponder];
}

- (void)restoreState {
    [state_ release];
    state_ = savedState_;
    savedState_ = nil;
}

- (void)saveState {
    [savedState_ release];
    savedState_ = state_;
    state_ = [[FindState alloc] init];
    state_.mode = savedState_.mode;
    state_.string = savedState_.string;
}

- (void)open {
    if ([findBarTextField_.window.appearance.name isEqual:NSAppearanceNameVibrantDark]) {
        findBarTextField_.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantLight];
    } else {
        findBarTextField_.appearance = nil;
    }

    if (savedState_) {
        [self restoreState];
        findBarTextField_.stringValue = state_.string;
    }

    _isVisible = YES;
    [self.delegate findViewControllerVisibilityDidChange:self];

    [[self view] setFrame:[self collapsedFrame]];
    [[self view] setHidden:NO];
    [[NSAnimationContext currentContext] setDuration:kAnimationDuration];
    DLog(@"Animate find view %@ to full size frame: %@",
         self.view, NSStringFromRect([self fullSizeFrame]));

    [NSAnimationContext beginGrouping];

    [[NSAnimationContext currentContext] setCompletionHandler:^{
        [[[[self view] window] contentView] setNeedsDisplay:YES];
    }];

    [[[self view] animator] setFrame:[self fullSizeFrame]];

    [NSAnimationContext endGrouping];

    DLog(@"Grab focus for find view %@", self.view);
    [[[self view] window] makeFirstResponder:findBarTextField_];
}

- (void)makeVisible {
    BOOL wasHidden = [[self view] isHidden];
    if (!wasHidden && [findBarTextField_ textFieldIsFirstResponder]) {
        // The bar was already visible but didn't have focus. Just set the focus.
        [[[self view] window] makeFirstResponder:findBarTextField_];
        return;
    }
    if (wasHidden) {
        [self open];
    } else {
        [findBarTextField_ selectText:nil];
    }
}

- (void)setProgress:(double)progress {
    iTermSearchFieldCell *cell = (iTermSearchFieldCell *)findBarTextField_.cell;
    if (round(progress * 100) != round(cell.fraction * 100)) {
        [findBarTextField_ setNeedsDisplay:YES];
    }

    [cell setFraction:progress];
    if (cell.needsAnimation && !_animationTimer) {
        _animationTimer = [NSTimer scheduledTimerWithTimeInterval:1/60.0
                                                  target:self
                                                selector:@selector(redrawSearchField:)
                                                userInfo:nil
                                                 repeats:YES];
    }
}

- (void)redrawSearchField:(NSTimer *)timer {
    iTermSearchFieldCell *cell = findBarTextField_.cell;
    [cell willAnimate];
    if (!cell.needsAnimation) {
        [_animationTimer invalidate];
        _animationTimer = nil;
    }
    [findBarTextField_ setNeedsDisplay:YES];
}

- (BOOL)_continueSearch {
    BOOL more = NO;
    if ([delegate_ findInProgress]) {
        double progress;
        more = [delegate_ continueFind:&progress];
        [self setProgress:progress];
    }
    if (!more) {
        [timer_ invalidate];
        timer_ = nil;
        [self setProgress:1];
    }
    return more;
}

- (void)_setSearchString:(NSString *)s {
    if (!savedState_) {
        [gSearchString autorelease];
        gSearchString = [s retain];
        state_.string = s;
    }
}

- (void)setMode:(iTermFindMode)set {
    if (!savedState_) {
        gFindMode = set;
        // The user defaults key got recycled to make it clear whether the legacy (number) or modern value (dict) is
        // in use, but the key doesn't reflect its true meaning any more.
        [[NSUserDefaults standardUserDefaults] setObject:@(set) forKey:@"findMode_iTerm"];
    }
}

- (void)_setSearchDefaults {
    [self _setSearchString:[findBarTextField_ stringValue]];
    [self setMode:state_.mode];
}

- (void)findSubString:(NSString *)subString
     forwardDirection:(BOOL)direction
                 mode:(iTermFindMode)mode
           withOffset:(int)offset {
    BOOL ok = NO;
    if ([delegate_ canSearch]) {
        if ([subString length] <= 0) {
            [delegate_ findViewControllerClearSearch];
        } else {
            [delegate_ findString:subString
                 forwardDirection:direction
                             mode:mode
                       withOffset:offset];
            ok = YES;
        }
    }

    if (ok && !timer_) {
        [self setProgress:0];
        if ([self _continueSearch]) {
            timer_ = [NSTimer scheduledTimerWithTimeInterval:0.01
                                                      target:self
                                                    selector:@selector(_continueSearch)
                                                    userInfo:nil
                                                     repeats:YES];
            [[NSRunLoop currentRunLoop] addTimer:timer_ forMode:NSRunLoopCommonModes];
        }
    } else if (!ok && timer_) {
        [timer_ invalidate];
        timer_ = nil;
        [self setProgress:1];
    }
}

- (void)searchNext {
    [self _setSearchDefaults];
    [self findSubString:savedState_ ? state_.string : gSearchString
       forwardDirection:YES
                   mode:state_.mode
             withOffset:1];
}

- (void)searchPrevious {
    [self _setSearchDefaults];
    [self findSubString:savedState_ ? state_.string : gSearchString
       forwardDirection:NO
                   mode:state_.mode
             withOffset:1];
}

- (IBAction)searchNextPrev:(id)sender {
    if ([sender selectedSegment] == 0) {
        [self searchPrevious];
    } else {
        [self searchNext];
    }
    [sender setSelected:NO
             forSegment:[sender selectedSegment]];
}

- (BOOL)validateUserInterfaceItem:(NSMenuItem *)item {
    item.state = (item.tag == state_.mode) ? NSOnState : NSOffState;
    return YES;
}

- (IBAction)changeMode:(id)sender {
    state_.mode = (iTermFindMode)[sender tag];
    [self setMode:state_.mode];
}


- (void)_loadFindStringIntoSharedPasteboard {
    if (savedState_) {
        return;
    }
    // Copy into the NSFindPboard
    NSPasteboard *findPB = [NSPasteboard pasteboardWithName:NSFindPboard];
    if (findPB) {
        [findPB declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
        [findPB setString:[findBarTextField_ stringValue] forType:NSStringPboardType];
    }
}

- (void)setFindString:(NSString*)string {
    [findBarTextField_ setStringValue:string];
    [self _loadFindStringIntoSharedPasteboard];
}

- (void)closeViewAndDoTemporarySearchForString:(NSString *)string
                                          mode:(iTermFindMode)mode {
    [self close];
    if (!savedState_) {
        [self saveState];
    }
    state_.mode = mode;
    state_.string = string;
    findBarTextField_.stringValue = string;
    [self doSearch];
}

- (void)controlTextDidChange:(NSNotification *)aNotification {
    NSTextField *field = [aNotification object];
    if (field != findBarTextField_) {
        return;
    }

    // A query becomes stale when it is 1 or 2 chars long and it hasn't been edited in 3 seconds (or
    // the search field has lost focus since the last char was entered).
    static const CGFloat kStaleTime = 3;
    BOOL isStale = (([NSDate timeIntervalSinceReferenceDate] - lastEditTime_) > kStaleTime &&
                    findBarTextField_.stringValue.length > 0 &&
                    [self queryIsShort]);

    // This state machine implements a delay before executing short (1 or 2 char) queries. The delay
    // is incurred again when a 5+ char query becomes short. It's kind of complicated so the delay
    // gets inserted at appropriate but minimally annoying times. Plug this into graphviz to see the
    // full state machine:
    //
    // digraph g {
    //   Empty -> Delaying [ label = "1 or 2 chars entered" ]
    //   Empty -> ActiveShort
    //   Empty -> ActiveMedium [ label = "3 or 4 chars entered" ]
    //   Empty -> ActiveLong [ label = "5+ chars entered" ]
    //
    //   Delaying -> Empty [ label = "Erased" ]
    //   Delaying -> ActiveShort [ label = "After Delay" ]
    //   Delaying -> ActiveMedium
    //   Delaying -> ActiveLong
    //
    //   ActiveShort -> ActiveMedium
    //   ActiveShort -> ActiveLong
    //   ActiveShort -> Delaying [ label = "When Stale" ]
    //
    //   ActiveMedium -> Empty
    //   ActiveMedium -> ActiveLong
    //   ActiveMedium -> Delaying [ label = "When Stale" ]
    //
    //   ActiveLong -> Delaying [ label = "Becomes Short" ]
    //   ActiveLong -> ActiveMedium
    //   ActiveLong -> Empty
    // }
    switch (delayState_) {
        case kFindViewDelayStateEmpty:
            if (findBarTextField_.stringValue.length == 0) {
                break;
            } else if ([self queryIsShort]) {
                [self startDelay];
            } else {
                [self becomeActive];
            }
            break;

        case kFindViewDelayStateDelaying:
            if (findBarTextField_.stringValue.length == 0) {
                delayState_ = kFindViewDelayStateEmpty;
            } else if (![self queryIsShort]) {
                [self becomeActive];
            }
            break;

        case kFindViewDelayStateActiveShort:
            // This differs from ActiveMedium in that it will not enter the Empty state.
            if (isStale) {
                [self startDelay];
                break;
            }

            [self doSearch];
            if ([self queryIsLong]) {
                delayState_ = kFindViewDelayStateActiveLong;
            } else if (![self queryIsShort]) {
                delayState_ = kFindViewDelayStateActiveMedium;
            }
            break;

        case kFindViewDelayStateActiveMedium:
            if (isStale) {
                [self startDelay];
                break;
            }
            if (findBarTextField_.stringValue.length == 0) {
                delayState_ = kFindViewDelayStateEmpty;
            } else if ([self queryIsLong]) {
                delayState_ = kFindViewDelayStateActiveLong;
            }
            // This state intentionally does not transition to ActiveShort. If you backspace over
            // the whole query, the delay must be done again.
            [self doSearch];
            break;

        case kFindViewDelayStateActiveLong:
            if (findBarTextField_.stringValue.length == 0) {
                delayState_ = kFindViewDelayStateEmpty;
                [self doSearch];
            } else if ([self queryIsShort]) {
                // long->short transition. Common when select-all followed by typing.
                [self startDelay];
            } else if (![self queryIsLong]) {
                delayState_ = kFindViewDelayStateActiveMedium;
                [self doSearch];
            } else {
                [self doSearch];
            }
            break;
    }
    lastEditTime_ = [NSDate timeIntervalSinceReferenceDate];
}

- (void)startDelay {
    delayState_ = kFindViewDelayStateDelaying;
    [self retain];
    NSTimeInterval delay = [iTermAdvancedSettingsModel findDelaySeconds];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       if (![[self view] isHidden] &&
                           delayState_ == kFindViewDelayStateDelaying) {
                           [self becomeActive];
                       }
                       [self release];
                   });
}

- (BOOL)queryIsLong {
    return findBarTextField_.stringValue.length >= 5;
}

- (BOOL)queryIsShort {
    return findBarTextField_.stringValue.length <= 2;
}

- (void)becomeActive {
    [self updateDelayState];
    [self doSearch];
}

- (void)updateDelayState {
    if ([self queryIsLong]) {
        delayState_ = kFindViewDelayStateActiveLong;
    } else if ([self queryIsShort]) {
        delayState_ = kFindViewDelayStateActiveShort;
    } else {
        delayState_ = kFindViewDelayStateActiveMedium;
    }
}

- (void)doSearch {
    NSString *theString = savedState_ ? state_.string : [findBarTextField_ stringValue];
    if (!savedState_) {
        [self _loadFindStringIntoSharedPasteboard];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermLoadFindStringFromSharedPasteboard"
                                                            object:nil];
    }
    // Search.
    [self _setSearchDefaults];
    [self findSubString:theString
       forwardDirection:NO
                   mode:state_.mode
             withOffset:-1];
}

- (void)deselectFindBarTextField {
    NSText* fieldEditor = [[[self view] window] fieldEditor:YES
                                                  forObject:findBarTextField_];
    [fieldEditor setSelectedRange:NSMakeRange([[fieldEditor string] length], 0)];
    [fieldEditor setNeedsDisplay:YES];
}

- (BOOL)control:(NSControl *)control
       textView:(NSTextView *)textView
    doCommandBySelector:(SEL)commandSelector {
    if (control != findBarTextField_) {
        return NO;
    }

    if (commandSelector == @selector(cancelOperation:)) {
        // Have the esc key close the find bar instead of erasing its contents.
        [self close];
        return YES;
    } else if (commandSelector == @selector(insertBacktab:)) {
        if ([delegate_ growSelectionLeft]) {
            NSString* text = [delegate_ selectedText];
            if (text) {
                [delegate_ copySelection];
                [findBarTextField_ setStringValue:text];
                [self _loadFindStringIntoSharedPasteboard];
                [self deselectFindBarTextField];
                [self searchPrevious];
            }
        }
        return YES;
    } else if (commandSelector == @selector(insertTab:)) {
        [delegate_ growSelectionRight];
        NSString* text = [delegate_ selectedText];
        if (text) {
            [delegate_ copySelection];
            [findBarTextField_ setStringValue:text];
            [self _loadFindStringIntoSharedPasteboard];
            [self deselectFindBarTextField];
        }
        return YES;
    } else if (commandSelector == @selector(insertNewlineIgnoringFieldEditor:)) {
        // Alt-enter
        [delegate_ copySelection];
        NSString* text = [delegate_ unpaddedSelectedText];
        [delegate_ pasteString:text];
        [delegate_ findViewControllerMakeDocumentFirstResponder];
        return YES;
    } else {
        return NO;
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)aNotification {
    NSControl *postingObject = [aNotification object];
    if (postingObject != findBarTextField_) {
        return;
    }

    int move = [[[aNotification userInfo] objectForKey:@"NSTextMovement"] intValue];
    switch (move) {
        case NSOtherTextMovement:
            // Focus lost
            lastEditTime_ = 0;
            break;
        case NSReturnTextMovement:
            // Return key
            if ([[NSApp currentEvent] modifierFlags] & NSShiftKeyMask) {
                [self searchNext];
            } else {
                [self searchPrevious];
            }
            break;
    }
    return;
}

- (void)setDelegate:(id<FindViewControllerDelegate>)delegate {
    delegate_ = delegate;
}

- (id<FindViewControllerDelegate>)delegate {
    return delegate_;
}

@end
