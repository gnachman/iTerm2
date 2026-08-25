//
//  iTermPasteViewManager.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/26/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermStatusBarViewController;
@class PasteContext;
@class iTermVariableScope;

@protocol iTermPasteViewManagerDelegate<NSObject>

- (void)pasteViewManagerDropDownPasteViewVisibilityDidChange;
- (void)pasteViewManagerUserDidCancel;
- (iTermVariableScope *)pasteViewManagerScope;

// The user toggled the "send keystrokes to the terminal" control in the paste
// indicator. When `on`, keystrokes bypass the paste queue and go to the terminal.
- (void)pasteViewManagerDidSetKeystrokePassthrough:(BOOL)on;

@end

@interface iTermPasteViewManager : NSObject

@property (nonatomic, strong) PasteContext *pasteContext;
@property (nonatomic) NSUInteger bufferLength;
@property (nonatomic, readonly) BOOL dropDownPasteViewIsVisible;
@property (nonatomic, weak) id<iTermPasteViewManagerDelegate> delegate;
@property (nonatomic, assign) int remainingLength;

- (void)startWithViewForDropdown:(NSView *)dropdownSuperview
         statusBarViewController:(iTermStatusBarViewController *)statusBarController;

// Show/hide the "send keystrokes to the terminal" control in whichever paste
// indicator is currently visible.
- (void)setWaitingForPrompt:(BOOL)waitingForPrompt;

// Show the "typing is queued" hint pointing at that control.
- (void)showKeystrokeQueuedHint;

- (void)didStop;

- (void)temporaryRightStatusBarComponentDidBecomeAvailable;

@end

NS_ASSUME_NONNULL_END
