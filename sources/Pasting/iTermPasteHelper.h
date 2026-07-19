//
//  iTermPasteHelper.h
//  iTerm
//
//  Created by George Nachman on 3/29/14.
//
//

#import <Cocoa/Cocoa.h>
#import "PasteEvent.h"

extern const int kNumberOfSpacesPerTabCancel;
extern const int kNumberOfSpacesPerTabNoConversion;
extern const int kNumberOfSpacesPerTabOpenAdvancedPaste;
extern const NSInteger iTermQuickPasteBytesPerCallDefaultValue;

@class iTermStatusBarViewController;
@class iTermVariableScope;
@class PasteContext;

@protocol iTermPasteHelperDelegate <NSObject>

- (void)pasteHelperWriteString:(NSString *)string;

// Handle a key-down event that was previously enqueued.
- (void)pasteHelperKeyDown:(NSEvent *)event;

// Indicates if pastes should be bracketed with a special escape sequence.
- (BOOL)pasteHelperShouldBracket;

// Encoding to use for converting strings to byte arrays.
- (NSStringEncoding)pasteHelperEncoding;

// View in which to show the paste indicator.
- (NSView *)pasteHelperViewForIndicator;
- (iTermStatusBarViewController *)pasteHelperStatusBarViewController;

// Are you currently at a shell prompt? Implies shell integration.
- (BOOL)pasteHelperIsAtShellPrompt;

// Returns YES if we know we're NOT at a shell prompt. If uncertain, returns NO.
- (BOOL)pasteHelperShouldWaitForPrompt;

// Is shell integration installed?
- (BOOL)pasteHelperCanWaitForPrompt;

// Paste view did appear/disappear
- (void)pasteHelperPasteViewVisibilityDidChange;

- (iTermVariableScope *)pasteHelperScope;

@end

@interface iTermPasteHelper : NSObject

@property(nonatomic, weak) id<iTermPasteHelperDelegate> delegate;
@property(nonatomic, readonly) BOOL isPasting;
@property(nonatomic, readonly) BOOL dropDownPasteViewIsVisible;
@property(nonatomic, readonly) BOOL isWaitingForPrompt;
@property(nonatomic, readonly) PasteContext *pasteContext;

+ (BOOL)promptToConvertTabsToSpacesWhenPasting;
+ (void)togglePromptToConvertTabsToSpacesWhenPasting;

+ (NSMutableCharacterSet *)unsafeControlCodeSet;

// This performs all the transformations except for bracketing.
+ (void)sanitizePasteEvent:(PasteEvent *)pasteEvent
                  encoding:(NSStringEncoding)encoding;

// Queue up a string to paste. If the queue is empty, it will begin pasting immediately.
- (void)pasteString:(NSString *)theString
             slowly:(BOOL)slowly
   escapeShellChars:(BOOL)escapeShellChars
           isUpload:(BOOL)isUpload
    allowBracketing:(BOOL)allowBracketing
       tabTransform:(iTermTabTransformTags)tabTransform
       spacesPerTab:(int)spacesPerTab;

- (void)pasteString:(NSString *)theString
             slowly:(BOOL)slowly
   escapeShellChars:(BOOL)escapeShellChars
           isUpload:(BOOL)isUpload
    allowBracketing:(BOOL)allowBracketing
       tabTransform:(iTermTabTransformTags)tabTransform
       spacesPerTab:(int)spacesPerTab
           progress:(void (^)(NSInteger))progress;

// Queue up `string` to paste literally: no bracketing, no multi-line warning,
// no tab transform. Like the other paste methods it serializes behind any
// in-progress paste, but once it reaches the head of the queue it waits `delay`
// seconds before writing its first byte (so the delay is measured from when the
// prior paste drains, not from now). Intended for sending a submit key (a
// Return) a beat after a bracketed paste, so a TUI that debounces bracketed
// paste (e.g. Claude Code) has time to leave paste mode and treats the Return
// as a submit rather than absorbing it into the paste.
- (void)pasteLiteralString:(NSString *)string afterDelay:(NSTimeInterval)delay;

// The string comes from the paste special view controller.
- (void)pasteString:(NSString *)theString stringConfig:(NSString *)jsonConfig;

// Save an event to process after pasting is done.
- (void)enqueueEvent:(NSEvent *)event;

// Remove all queued events and pending pastes, and hide the paste indicator if shown.
- (void)abort;

- (void)showPasteOptionsInWindow:(NSWindow *)window bracketingEnabled:(BOOL)bracketingEnabled;

// Convert tabs to spaces in source, perhaps asking the user questions in modal alerts.
- (int)numberOfSpacesToConvertTabsTo:(NSString *)source;

// Call this when a shell prompt begins. If pasting in "commands" mode this
// allows one more line to be pasted.
- (void)unblock;

- (void)showAdvancedPasteWithFlags:(PTYSessionPasteFlags)flags;
- (void)temporaryRightStatusBarComponentDidBecomeAvailable;

#pragma mark - Testing

// This method can be overridden for testing.
- (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti
                                     target:(id)aTarget
                                   selector:(SEL)aSelector
                                   userInfo:(id)userInfo
                                    repeats:(BOOL)yesOrNo;

- (PasteEvent *)pasteEventWithString:(NSString *)theString
                              slowly:(BOOL)slowly
                    escapeShellChars:(BOOL)escapeShellChars
                            isUpload:(BOOL)isUpload
                     allowBracketing:(BOOL)allowBracketing  // if true respect delegate's wishes.
                        tabTransform:(iTermTabTransformTags)tabTransform
                        spacesPerTab:(int)spacesPerTab
                            progress:(void (^)(NSInteger))progress;
- (void)tryToPasteEvent:(PasteEvent *)pasteEvent;

@end
