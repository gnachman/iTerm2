// -*- mode:objc -*-
/*
 **  FindViewController.h
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

#import <Cocoa/Cocoa.h>

@protocol FindViewControllerDelegate

// Delegate should call resetFindCursor in textview.
- (void)resetFindCursor;

// Return [[[self currentSession] TEXTVIEW] findInProgress]
- (BOOL)findInProgress;

// Call [[[self currentSession] TEXTVIEW] continueFind];
- (BOOL)continueFind;

// Call [[self currentSession] TEXTVIEW] growSelectionLeft]
- (BOOL)growSelectionLeft;

// call [[[self currentSession] TEXTVIEW] growSelectionRight];
- (void)growSelectionRight;

// Return [[[self currentSession] TEXTVIEW] selectedText];
- (NSString*)selectedText;

// Return [textview selectedTextWithPad:NO]
- (NSString*)unpaddedSelectedText;

// call [[[self currentSession] TEXTVIEW] copy:self];
- (void)copySelection;

// call [[self currentSession] pasteString:text];
- (void)pasteString:(NSString*)string;

// call [[self window] makeFirstResponder:[[self currentSession] TEXTVIEW]];
- (void)takeFocus;

// Remove highlighted matches
- (void)clearHighlights;
@end


@interface FindViewController : NSViewController {
    IBOutlet NSSearchField* findBarTextField_;
    IBOutlet NSProgressIndicator* findBarProgressIndicator_;
    // These pointers are just "prototypes" and do not refer to any actual menu
    // items.
    IBOutlet NSMenuItem* ignoreCaseMenuItem_;
    IBOutlet NSMenuItem* regexMenuItem_;
    BOOL ignoreCase_;
    BOOL regex_;

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

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
- (void)dealloc;
- (void)close;
- (void)open;
- (void)toggleVisibility;
- (void)setFrameOrigin:(NSPoint)p;

- (IBAction)closeFindView:(id)sender;
- (IBAction)searchNextPrev:(id)sender;
- (IBAction)toggleIgnoreCase:(id)sender;
- (IBAction)toggleRegex:(id)sender;
- (void)searchNext;
- (void)searchPrevious;
- (void)findString:(NSString*)string;

- (void)setDelegate:(id<FindViewControllerDelegate>)delegate;

@end
