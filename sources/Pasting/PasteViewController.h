//
//  PasteViewController.h
//  iTerm
//
//  Created by George Nachman on 3/12/13.
//
//

#import <Cocoa/Cocoa.h>

@class PasteContext;

@protocol PasteViewControllerDelegate <NSObject>

- (void)pasteViewControllerDidCancel;

// The user toggled the "send keystrokes to the terminal" control. When `on`,
// keystrokes should go straight to the terminal instead of being queued until
// the paste finishes (e.g. so the user can answer a password prompt).
- (void)pasteViewControllerDidSetKeystrokePassthrough:(BOOL)on;

@end

@interface PasteViewController : NSViewController

@property(nonatomic, assign) id<PasteViewControllerDelegate> delegate;
@property(nonatomic, assign) int remainingLength;
@property(nonatomic, readonly) BOOL mini;

- (instancetype)initWithContext:(PasteContext *)pasteContext_
                         length:(int)length
                           mini:(BOOL)mini NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(NSNibName)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (IBAction)cancel:(id)sender;
- (IBAction)toggleKeystrokePassthrough:(id)sender;
- (void)updateFrame;
- (void)closeWithCompletion:(void (^)(void))completion;
- (void)updateLabelColor;

// Show or hide the "send keystrokes to the terminal" control. It's shown only
// while a wait-for-prompt paste is paused waiting for a shell prompt.
- (void)setWaitingForPrompt:(BOOL)waitingForPrompt;

// Show a transient callout pointing at the keystroke-passthrough button telling
// the user that their typing is being queued. No-op unless that button is shown.
- (void)showKeystrokeQueuedHint;

@end
