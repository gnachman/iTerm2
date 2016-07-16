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
#import "iTermProgressIndicator.h"
#import "iTermSystemVersion.h"
#import "NSTextField+iTerm.h"

// This used to be absurdly fast (.075) for reasons neither I nor revision
// history can recall. This looks nicer to my eyes.
static const float kAnimationDuration = 0.2;
static BOOL gDefaultIgnoresCase;
static BOOL gDefaultRegex;
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

- (instancetype)initImageCell:(NSImage *)image {
    self = [super initImageCell:image];
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
        if (IsYosemiteOrLater()) {
            [super drawFocusRingMaskWithFrame:NSInsetRect(cellFrame, kFocusRingInset.width, kFocusRingInset.height)
                                       inView:controlView];
        } else {
            [super drawFocusRingMaskWithFrame:cellFrame inView:controlView];
        }
    }    
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    if (IsYosemiteOrLater()) {
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
        return;
    }
    NSColor *insetTopColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.0];
    NSColor *insetBottomColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.35];
    NSColor *strokeTopColor = [NSColor colorWithCalibratedWhite:0.240 alpha:1.0];
    NSColor *strokeBottomColor = [NSColor colorWithCalibratedWhite:0.380 alpha:1.0];

    if (![[controlView window] isKeyWindow]) {
            strokeTopColor = [NSColor colorWithCalibratedWhite:0.550 alpha:1.0];
            strokeBottomColor = [NSColor colorWithCalibratedWhite:0.557 alpha:1.0];
    }

    NSRect strokeRect = cellFrame;
    strokeRect.size.height -= 1.0;
    NSBezierPath *strokePath = [NSBezierPath bezierPathWithRoundedRect:strokeRect xRadius:strokeRect.size.height/2.0 yRadius:strokeRect.size.height/2.0];

    NSBezierPath *insetPath = [NSBezierPath bezierPath];
    [insetPath appendBezierPath:strokePath];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:0 yBy:1.0];
    [insetPath transformUsingAffineTransform:transform];
    NSGradient *insetGradient = [[NSGradient alloc] initWithStartingColor:insetTopColor endingColor:insetBottomColor];
    [insetGradient drawInBezierPath:insetPath angle:90.0];
    [insetGradient release];

    NSGradient *strokeGradient = [[NSGradient alloc] initWithStartingColor:strokeTopColor endingColor:strokeBottomColor];
    [strokeGradient drawInBezierPath:strokePath angle:90.0];
    [strokeGradient release];

    NSRect fieldRect = NSInsetRect(cellFrame, 1.0, 1.0);
    fieldRect.size.height -= 1.0;
    NSBezierPath *fieldPath = [NSBezierPath bezierPathWithRoundedRect:fieldRect xRadius:fieldRect.size.height/2.0 yRadius:fieldRect.size.height/2.0];

    [[NSColor whiteColor] set];
    [fieldPath fill];

    CGFloat w = fieldRect.size.width;
    [[NSGraphicsContext currentContext] saveGraphicsState];
    [fieldPath addClip];

    NSRect blueRect = NSMakeRect(0, 0, w * [self fraction] + kEdgeWidth, cellFrame.size.height);
    const CGFloat alpha = 0.3 * _alphaMultiplier;
    NSGradient *horizontalGradient =
        [[[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedRed:204.0/255.0
                                                                             green:219.0/255.0
                                                                              blue:233.0/255.0
                                                                             alpha:alpha]
                                       endingColor:[NSColor colorWithCalibratedRed:131.0/255.0
                                                                             green:187.0/255.0
                                                                              blue:239.0/255.0
                                                                             alpha:alpha]] autorelease];
    [horizontalGradient drawInRect:blueRect angle:0];

    NSGradient *verticalGradient =
        [[[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedRed:0/255.0
                                                                             green:0/255.0
                                                                              blue:0/255.0
                                                                             alpha:alpha]
                                       endingColor:[NSColor colorWithCalibratedRed:10.0/255.0
                                                                             green:13.0/255.0
                                                                              blue:0/255.0
                                                                             alpha:alpha]] autorelease];
    [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositePlusLighter];
    [verticalGradient drawInRect:blueRect angle:90];

    NSGradient *edgeGradient =
        [[[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedRed:255/255.0
                                                                             green:255/255.0
                                                                              blue:255/255.0
                                                                             alpha:0.0]
                                       endingColor:[NSColor colorWithCalibratedRed:255.0/255.0
                                                                             green:255.0/255.0
                                                                              blue:255.0/255.0
                                                                             alpha:1.0]] autorelease];
    [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositeSourceOver];
    NSRect edgeRect = NSMakeRect(blueRect.size.width - kEdgeWidth, 0, kEdgeWidth, blueRect.size.height);
    [edgeGradient drawInRect:edgeRect angle:0];

    [[NSGraphicsContext currentContext] restoreGraphicsState];

        // Draw the inner shadow
        [[NSGraphicsContext currentContext] saveGraphicsState];
        NSShadow *innerShadow = [[NSShadow alloc] init];
        float innerShadowAlpha = 0.4;
        if (![[controlView window] isKeyWindow])
                innerShadowAlpha = 0.2;
        [innerShadow setShadowColor:[NSColor colorWithCalibratedWhite:0.0 alpha:innerShadowAlpha]];
        [innerShadow setShadowOffset:NSMakeSize(0, -1.0)];
        [innerShadow setShadowBlurRadius:1.0];
        [innerShadow set];

        [fieldPath addClip];

        NSBezierPath *outlinePath = [NSBezierPath bezierPath];
        [outlinePath appendBezierPath:strokePath];
        [outlinePath appendBezierPath:fieldPath];
        [outlinePath setWindingRule:NSEvenOddWindingRule];
        [strokeTopColor set];
        [outlinePath fill];

        [[NSGraphicsContext currentContext] restoreGraphicsState];
        [innerShadow release];

        [self drawInteriorWithFrame:cellFrame inView:controlView];
        if ([controlView respondsToSelector:@selector(currentEditor)] && [(NSControl *)controlView currentEditor]) {
                [[NSGraphicsContext currentContext] saveGraphicsState];
                NSSetFocusRingStyle(NSFocusRingOnly);
                [strokePath fill];
                [[NSGraphicsContext currentContext] restoreGraphicsState];
        }
}


@end

@interface FindState : NSObject

@property(nonatomic, assign) BOOL ignoreCase;
@property(nonatomic, assign) BOOL regex;
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
    IBOutlet NSSearchField* findBarTextField_;
    // These pointers are just "prototypes" and do not refer to any actual menu
    // items.
    IBOutlet NSMenuItem* ignoreCaseMenuItem_;
    IBOutlet NSMenuItem* regexMenuItem_;

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


+ (void)initialize
{
    gDefaultIgnoresCase =
        [[NSUserDefaults standardUserDefaults] objectForKey:@"findIgnoreCase_iTerm"] ?
            [[NSUserDefaults standardUserDefaults] boolForKey:@"findIgnoreCase_iTerm"] :
            YES;
    gDefaultRegex = [[NSUserDefaults standardUserDefaults] boolForKey:@"findRegex_iTerm"];
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        [findBarTextField_ setDelegate:self];
        state_ = [[FindState alloc] init];
        state_.ignoreCase = gDefaultIgnoresCase;
        state_.regex = gDefaultRegex;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_loadFindStringFromSharedPasteboard)
                                                     name:@"iTermLoadFindStringFromSharedPasteboard"
                                                   object:nil];
        [self loadView];
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

- (NSRect)collapsedFrame
{
    return NSMakeRect([[self view] frame].origin.x,
                      fullFrame_.origin.y + [self superframe].size.height + fullFrame_.size.height,
                      [[self view] frame].size.width,
                      0);
}

- (NSRect)fullSizeFrame
{
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
    }];
    [[NSAnimationContext currentContext] setDuration:kAnimationDuration];
    [[[self view] animator] setFrame:[self collapsedFrame]];
    [NSAnimationContext endGrouping];

    [delegate_ clearHighlights];
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
    state_.ignoreCase = savedState_.ignoreCase;
    state_.regex = savedState_.regex;
    state_.string = savedState_.string;
}

- (void)open {
    if (savedState_) {
        [self restoreState];
        ignoreCaseMenuItem_.state = state_.ignoreCase ? NSOnState : NSOffState;
        regexMenuItem_.state = state_.regex ? NSOnState : NSOffState;
        findBarTextField_.stringValue = state_.string;
    }
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
    [findBarTextField_.cell setFraction:progress];
    iTermSearchFieldCell *cell = findBarTextField_.cell;
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

- (void)_continueSearch
{
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
}

- (void)_setSearchString:(NSString *)s
{
    if (!savedState_) {
        [gSearchString autorelease];
        gSearchString = [s retain];
        state_.string = s;
    }
}

- (void)_setIgnoreCase:(BOOL)set
{
    if (!savedState_) {
        gDefaultIgnoresCase = set;
        [[NSUserDefaults standardUserDefaults] setBool:set
                                                forKey:@"findIgnoreCase_iTerm"];
    }
}

- (void)_setRegex:(BOOL)set
{
    if (!savedState_) {
        gDefaultRegex = set;
        [[NSUserDefaults standardUserDefaults] setBool:set
                                                forKey:@"findRegex_iTerm"];
    }
}

- (void)_setSearchDefaults
{
    [self _setSearchString:[findBarTextField_ stringValue]];
    [self _setIgnoreCase:state_.ignoreCase];
    [self _setRegex:state_.regex];
}

- (void)findSubString:(NSString *)subString
     forwardDirection:(BOOL)direction
         ignoringCase:(BOOL)ignoringCase
                regex:(BOOL)regex
           withOffset:(int)offset
{
    BOOL ok = NO;
    if ([delegate_ canSearch]) {
        if ([subString length] <= 0) {
            [delegate_ clearHighlights];
        } else {
            [delegate_ findString:subString
                 forwardDirection:direction
                     ignoringCase:ignoringCase
                            regex:regex
                       withOffset:offset];
            ok = YES;
        }
    }

    if (ok && !timer_) {
        timer_ = [NSTimer scheduledTimerWithTimeInterval:0.01
                                                  target:self
                                                selector:@selector(_continueSearch)
                                                userInfo:nil
                                                 repeats:YES];
        [self setProgress:0];
    } else if (!ok && timer_) {
        [timer_ invalidate];
        timer_ = nil;
        [self setProgress:1];
    }
}

- (void)searchNext
{
    [self _setSearchDefaults];
    [self findSubString:savedState_ ? state_.string : gSearchString
       forwardDirection:YES
           ignoringCase:state_.ignoreCase
                  regex:state_.regex
             withOffset:1];
}

- (void)searchPrevious
{
    [self _setSearchDefaults];
    [self findSubString:savedState_ ? state_.string : gSearchString
       forwardDirection:NO
           ignoringCase:state_.ignoreCase
                  regex:state_.regex
             withOffset:1];
}

- (IBAction)searchNextPrev:(id)sender
{
    if ([sender selectedSegment] == 0) {
        [self searchPrevious];
    } else {
        [self searchNext];
    }
    [sender setSelected:NO
             forSegment:[sender selectedSegment]];
}

- (BOOL)validateUserInterfaceItem:(NSMenuItem*)item
{
    if ([item action] == @selector(toggleIgnoreCase:)) {
        [item setState:(state_.ignoreCase ? NSOnState : NSOffState)];
    } else if ([item action] == @selector(toggleRegex:)) {
        [item setState:(state_.regex ? NSOnState : NSOffState)];
    }
    return YES;
}

- (IBAction)toggleIgnoreCase:(id)sender
{
    state_.ignoreCase = !state_.ignoreCase;
    [self _setIgnoreCase:state_.ignoreCase];
}

- (IBAction)toggleRegex:(id)sender
{
    state_.regex = !state_.regex;
    [self _setRegex:state_.regex];
}

- (void)_loadFindStringIntoSharedPasteboard
{
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

- (void)setFindString:(NSString*)string
{
    [findBarTextField_ setStringValue:string];
    [self _loadFindStringIntoSharedPasteboard];
}

- (void)closeViewAndDoTemporarySearchForString:(NSString *)string
                                 ignoringCase:(BOOL)ignoringCase
                                        regex:(BOOL)regex {
    [self close];
    if (!savedState_) {
        [self saveState];
    }
    state_.ignoreCase = ignoringCase;
    state_.regex = regex;
    state_.string = string;
    findBarTextField_.stringValue = string;
    [self doSearch];
}

- (void)controlTextDidChange:(NSNotification *)aNotification
{
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
           ignoringCase:state_.ignoreCase
                  regex:state_.regex
             withOffset:0];
}

- (void)deselectFindBarTextField
{
    NSText* fieldEditor = [[[self view] window] fieldEditor:YES
                                                  forObject:findBarTextField_];
    [fieldEditor setSelectedRange:NSMakeRange([[fieldEditor string] length], 0)];
    [fieldEditor setNeedsDisplay:YES];
}

- (BOOL)control:(NSControl*)control
       textView:(NSTextView*)textView
    doCommandBySelector:(SEL)commandSelector
{
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

- (void)setDelegate:(id<FindViewControllerDelegate>)delegate
{
    delegate_ = delegate;
}

- (id<FindViewControllerDelegate>)delegate
{
    return delegate_;
}

@end
