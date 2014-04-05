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
#import "NSTextField+iTerm.h"
#import "iTermApplication.h"

static const float FINDVIEW_DURATION = 0.075;
static BOOL gDefaultIgnoresCase;
static BOOL gDefaultRegex;
static NSString *gSearchString;

@interface FindState : NSObject

@property(nonatomic, assign) BOOL ignoreCase;
@property(nonatomic, assign) BOOL regex;
@property(nonatomic, copy) NSString *string;

@end

@implementation FindState

- (id)init {
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

@implementation FindViewController {
    IBOutlet NSSearchField* findBarTextField_;
    IBOutlet NSProgressIndicator* findBarProgressIndicator_;
    // These pointers are just "prototypes" and do not refer to any actual menu
    // items.
    IBOutlet NSMenuItem* ignoreCaseMenuItem_;
    IBOutlet NSMenuItem* regexMenuItem_;
    
    FindState *savedState_;
    FindState *state_;
    
    // Find happens incrementally. This remembers the string to search for.
    NSMutableString* previousFindString_;
    
    // Find runs out of a timer so that if you have a huge buffer then it
    // doesn't lock up. This timer runs the show.
    NSTimer* timer_;
    
    id<FindViewControllerDelegate> delegate_;
    NSRect fullFrame_;
    NSSize textFieldSize_;
    NSSize textFieldSmallSize_;
}


+ (void)initialize
{
    gDefaultIgnoresCase =
        [[NSUserDefaults standardUserDefaults] objectForKey:@"findIgnoreCase_iTerm"] ?
            [[NSUserDefaults standardUserDefaults] boolForKey:@"findIgnoreCase_iTerm"] :
            YES;
    gDefaultRegex = [[NSUserDefaults standardUserDefaults] boolForKey:@"findRegex_iTerm"];
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        previousFindString_ = [[NSMutableString alloc] init];
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

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (timer_) {
        [timer_ invalidate];
        [findBarProgressIndicator_ setHidden:YES];
        timer_ = nil;
    }
    [previousFindString_ release];
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
        textFieldSmallSize_.width -= [findBarProgressIndicator_ frame].size.width + 3;
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

- (IBAction)closeFindView:(id)sender
{
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

- (void)close
{
    BOOL wasHidden = [[self view] isHidden];
    if (!wasHidden && timer_) {
        [timer_ invalidate];
        timer_ = nil;
        [findBarProgressIndicator_ setHidden:YES];
    }
    
    [[NSAnimationContext currentContext] setDuration:FINDVIEW_DURATION];
    [[[self view] animator] setFrame:[self collapsedFrame]];
    [self performSelector:@selector(_hide)
               withObject:nil
               afterDelay:[[NSAnimationContext currentContext] duration]];
    [delegate_ clearHighlights];
    [delegate_ takeFocus];
}

- (void)_hide
{
    [[self view] setHidden:YES];
    [[[[self view] window] contentView] setNeedsDisplay:YES];
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

- (void)open
{
    if (savedState_) {
        [self restoreState];
        ignoreCaseMenuItem_.state = state_.ignoreCase ? NSOnState : NSOffState;
        regexMenuItem_.state = state_.regex ? NSOnState : NSOffState;
        findBarTextField_.stringValue = state_.string;
    }
    [[self view] setFrame:[self collapsedFrame]];
    [[self view] setHidden:NO];
    [[NSAnimationContext currentContext] setDuration:FINDVIEW_DURATION];
    [[[self view] animator] setFrame:[self fullSizeFrame]];
    [delegate_ takeFocus];
    [self performSelector:@selector(_grabFocus)
               withObject:nil
               afterDelay:[[NSAnimationContext currentContext] duration]];    
}

- (void)_grabFocus
{
    [[[self view] window] makeFirstResponder:findBarTextField_];
    [[[[self view] window] contentView] setNeedsDisplay:YES];
}

- (void)toggleVisibility
{
    BOOL wasHidden = [[self view] isHidden];
    NSObject* firstResponder = [[[self view] window] firstResponder];
    NSText* currentEditor = [findBarTextField_ currentEditor];
    if (!wasHidden && (!currentEditor || currentEditor != firstResponder)) {
        // The bar was already visible but didn't have focus. Just set the focus.
        [[[self view] window] makeFirstResponder:findBarTextField_];
        return;
    }
    if (wasHidden) {
        [self open];
    } else {
        [self close];
    }
}

- (void)_continueSearch
{
    BOOL more = NO;
    if ([delegate_ findInProgress]) {
        more = [delegate_ continueFind];
    }
    if (!more) {
        [timer_ invalidate];
        timer_ = nil;
        [findBarProgressIndicator_ setHidden:YES];
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
            NSBeep();
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
        [findBarProgressIndicator_ setHidden:NO];
        [findBarProgressIndicator_ startAnimation:self];
    } else if (!ok && timer_) {
        [timer_ invalidate];
        timer_ = nil;
        [findBarProgressIndicator_ setHidden:YES];
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

- (void)findString:(NSString*)string
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
    [previousFindString_ setString:@""];
    [self doSearch];
}

- (void)controlTextDidChange:(NSNotification *)aNotification
{
    NSTextField *field = [aNotification object];
    if (field != findBarTextField_) {
        return;
    }
    [self doSearch];
}

- (void)doSearch {
    NSString *theString = savedState_ ? state_.string : [findBarTextField_ stringValue];
    if (!savedState_) {
        [self _loadFindStringIntoSharedPasteboard];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermLoadFindStringFromSharedPasteboard"
                                                            object:nil];
    }
    // Search.
    if ([previousFindString_ length] == 0) {
        [delegate_ resetFindCursor];
    } else {
        NSRange range =  [theString rangeOfString:previousFindString_];
        if (range.location != 0) {
            [delegate_ resetFindCursor];
        }
    }
    [previousFindString_ setString:theString];
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
        [delegate_ takeFocus];
        return YES;
    } else {
        return NO;
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)aNotification
{
    NSControl *postingObject = [aNotification object];
    if (postingObject != findBarTextField_) {
        return;
    }
    
    int move = [[[aNotification userInfo] objectForKey:@"NSTextMovement"] intValue];
    [previousFindString_ setString:@""];
    switch (move) {
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
