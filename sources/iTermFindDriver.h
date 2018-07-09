//
//  iTermFindDriver.h
//  iTerm2SharedARC
//
//  Created by GEORGE NACHMAN on 7/4/18.
//

#import <cocoa/cocoa.h>
#import "iTermFindViewController.h"

@class FindViewController;

@protocol iTermFindDriverDelegate <NSObject>

// Returns true if there is a text area to search.
- (BOOL)canSearch;

// Delegate should call resetFindCursor in textview.
- (void)resetFindCursor;

// Is the delegate in the process of searching?
- (BOOL)findInProgress;

// Search more. Fill in *progress with how much of the buffer has been searched.
- (BOOL)continueFind:(double *)progress;

// Moves the beginning of the current selection leftward by a word.
- (BOOL)growSelectionLeft;

// Moves the end of the current selection rightward by a word.
- (void)growSelectionRight;

// Returns the currently selected text.
- (NSString*)selectedText;

// Returns the currently selected text including leading/trailing whitespace.
- (NSString*)unpaddedSelectedText;

// Copies selected text to the pasteboard.
- (void)copySelection;

// Pastes the selected text to the session.
- (void)pasteString:(NSString*)string;

// Requests that the document (in practice, PTYTextView) become the first responder.
- (void)findViewControllerMakeDocumentFirstResponder;

// Remove highlighted matches
- (void)findViewControllerClearSearch;

// Perform a search
- (void)findString:(NSString *)aString
  forwardDirection:(BOOL)direction
              mode:(iTermFindMode)mode
        withOffset:(int)offset;

// The search view became (in)visible.
- (void)findViewControllerVisibilityDidChange:(id<iTermFindViewController>)sender;

@end

@interface iTermFindDriver : NSObject

@property (nonatomic, weak) id<iTermFindDriverDelegate> delegate;
@property (nonatomic, readonly) NSViewController<iTermFindViewController> *viewController;
@property (nonatomic) iTermFindMode mode;
@property (nonatomic, readonly) BOOL isVisible;
@property (nonatomic, copy) NSString *findString;

- (instancetype)initWithViewController:(NSViewController<iTermFindViewController> *)viewController NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Animates in a hidden find view.
- (void)open;

// Animates out a visible find view.
- (void)close;

// Animates if needed, otherwise just makes first responder.
- (void)makeVisible;

// Find the next (above) or previous (below) match.
- (void)searchNext;
- (void)searchPrevious;

// Performs a "temporary" search. The current state (case sensitivity, regex)
// is saved and the find view is hidden. A search is performed and the user can
// navigate with with next-previous. When the find window is opened, the state
// is restored.
- (void)closeViewAndDoTemporarySearchForString:(NSString *)string
                                          mode:(iTermFindMode)mode;

@end
