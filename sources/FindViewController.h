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
#import "FutureMethods.h"
#import "iTermController.h"

// Never change these values as they are saved to user defaults.
typedef NS_ENUM(NSUInteger, iTermFindMode) {
    iTermFindModeSmartCaseSensitivity = 0,
    iTermFindModeCaseSensitiveSubstring = 1,
    iTermFindModeCaseInsensitiveSubstring = 2,
    iTermFindModeCaseSensitiveRegex = 3,
    iTermFindModeCaseInsensitiveRegex = 4,
};

@class FindViewController;

@protocol FindViewControllerDelegate <NSObject>

// Returns true if there is a text area to search.
- (BOOL)canSearch;

// Delegate should call resetFindCursor in textview.
- (void)resetFindCursor;

// Return [[[self currentSession] textview] findInProgress]
- (BOOL)findInProgress;

// Call [[[self currentSession] textview] continueFind];
- (BOOL)continueFind:(double *)progress;

// Call [[self currentSession] textview] growSelectionLeft]
- (BOOL)growSelectionLeft;

// call [[[self currentSession] textview] growSelectionRight];
- (void)growSelectionRight;

// Return [[[self currentSession] textview] selectedText];
- (NSString*)selectedText;

// Return [textview selectedText]
- (NSString*)unpaddedSelectedText;

// call [[[self currentSession] textview] copy:self];
- (void)copySelection;

// call [[self currentSession] pasteString:text];
- (void)pasteString:(NSString*)string;

// Requests that the document (in practice, PTYTextView) become the first responder.
- (void)findViewControllerMakeDocumentFirstResponder;

// Remove highlighted matches
- (void)findViewControllerClearSearch;

// Preform a search
- (void)findString:(NSString *)aString
  forwardDirection:(BOOL)direction
              mode:(iTermFindMode)mode
        withOffset:(int)offset;

- (void)findViewControllerVisibilityDidChange:(FindViewController *)sender;

@end


@interface FindViewController : NSViewController <NSTextFieldDelegate>

@property (nonatomic, readonly) BOOL isVisible;

- (void)close;
- (void)open;
- (void)makeVisible;
- (void)setFrameOrigin:(NSPoint)p;

- (void)searchNext;
- (void)searchPrevious;
- (void)setFindString:(NSString*)string;

- (void)setDelegate:(id<FindViewControllerDelegate>)delegate;
- (id<FindViewControllerDelegate>)delegate;

// Performs a "temporary" search. The current state (case sensitivity, regex)
// is saved and the find view is hidden. A search is performed and the user can
// navigate with with next-previous. When the find window is opened, the state
// is restored.
- (void)closeViewAndDoTemporarySearchForString:(NSString *)string
                                  mode:(iTermFindMode)mode;
@end
