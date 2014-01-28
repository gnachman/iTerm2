// -*- mode:objc -*-
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

@implementation FindViewController

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
        ignoreCase_ = gDefaultIgnoresCase;
        regex_ = gDefaultRegex;
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

- (void)open
{
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

- (void)_newSearch:(BOOL)needTimer
{
    if (needTimer && !timer_) {
        // NSLog(@"creating timer");
        timer_ = [NSTimer scheduledTimerWithTimeInterval:0.01
                                                  target:self
                                                selector:@selector(_continueSearch)
                                                userInfo:nil
                                                 repeats:YES];
        [findBarProgressIndicator_ setHidden:NO];
        [findBarProgressIndicator_ startAnimation:self];
    } else if (!needTimer && timer_) {
        [timer_ invalidate];
        timer_ = nil;
        [findBarProgressIndicator_ setHidden:YES];
    }
}

- (void)_setSearchString:(NSString *)s
{
    [gSearchString autorelease];
    gSearchString = [s retain];
}

- (void)_setIgnoreCase:(BOOL)set
{
    gDefaultIgnoresCase = set;
    [[NSUserDefaults standardUserDefaults] setBool:set
                                            forKey:@"findIgnoreCase_iTerm"];
}

- (void)_setRegex:(BOOL)set
{
    gDefaultRegex = set;
    [[NSUserDefaults standardUserDefaults] setBool:set
                                            forKey:@"findRegex_iTerm"];
}

- (void)_setSearchDefaults
{
    [self _setSearchString:[findBarTextField_ stringValue]];
    [self _setIgnoreCase:ignoreCase_];
    [self _setRegex:regex_];
}

- (BOOL)findSubString:(NSString *)subString
     forwardDirection:(BOOL)direction
         ignoringCase:(BOOL)caseCheck
                regex:(BOOL)regex
           withOffset:(int)offset
{
    if ([delegate_ canSearch]) {
        if ([subString length] <= 0) {
            NSBeep();
            return NO;
        }

        return [delegate_ findString:subString
                   forwardDirection:direction
                       ignoringCase:caseCheck
                              regex:regex
                         withOffset:offset];
    }
    return NO;
}

- (void)searchNext
{
    [self _setSearchDefaults];
    BOOL timer = [self findSubString:gSearchString
                    forwardDirection:YES
                        ignoringCase:ignoreCase_
                               regex:regex_
                          withOffset:1];
    [self _newSearch:timer];
}

- (void)searchPrevious;
{
    [self _setSearchDefaults];
    BOOL timer = [self findSubString:gSearchString
                    forwardDirection:NO
                        ignoringCase:ignoreCase_
                               regex:regex_
                          withOffset:1];
    [self _newSearch:timer];
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
        [item setState:(ignoreCase_ ? NSOnState : NSOffState)];
    } else if ([item action] == @selector(toggleRegex:)) {
        [item setState:(regex_ ? NSOnState : NSOffState)];
    }
    return YES;
}

- (IBAction)toggleIgnoreCase:(id)sender
{
    ignoreCase_ = !ignoreCase_;
    [self _setIgnoreCase:ignoreCase_];
}

- (IBAction)toggleRegex:(id)sender
{
    regex_ = !regex_;
    [self _setRegex:regex_];
}

- (void)_loadFindStringIntoSharedPasteboard
{
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


- (void)controlTextDidChange:(NSNotification *)aNotification
{
    NSTextField *field = [aNotification object];
    if (field != findBarTextField_) {
        return;
    }

    [self _loadFindStringIntoSharedPasteboard];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermLoadFindStringFromSharedPasteboard"
                                                        object:nil];
    // Search.
    if ([previousFindString_ length] == 0) {
        [delegate_ resetFindCursor];
    } else {
        NSRange range =  [[findBarTextField_ stringValue] rangeOfString:previousFindString_];
        if (range.location != 0) {
            [delegate_ resetFindCursor];
        }
    }
    [previousFindString_ setString:[findBarTextField_ stringValue]];
    [self _setSearchDefaults];
    BOOL timer = [self findSubString:gSearchString
                    forwardDirection:NO
                        ignoringCase:ignoreCase_
                               regex:regex_
                          withOffset:0];
    [self _newSearch:timer];
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
