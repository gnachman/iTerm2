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

@class iTermStatusBarViewController;
@class iTermVariableScope;

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

@property(nonatomic, assign) id<iTermPasteHelperDelegate> delegate;
@property(nonatomic, readonly) BOOL isPasting;
@property(nonatomic, readonly) BOOL dropDownPasteViewIsVisible;

+ (NSMutableCharacterSet *)unsafeControlCodeSet;

// This performs all the transformations except for bracketing.
+ (void)sanitizePasteEvent:(PasteEvent *)pasteEvent
                  encoding:(NSStringEncoding)encoding;

// Queue up a string to paste. If the queue is empty, it will begin pasting immediately.
- (void)pasteString:(NSString *)theString
             slowly:(BOOL)slowly
   escapeShellChars:(BOOL)escapeShellChars
           isUpload:(BOOL)isUpload
       tabTransform:(iTermTabTransformTags)tabTransform
       spacesPerTab:(int)spacesPerTab;

- (void)pasteString:(NSString *)theString
             slowly:(BOOL)slowly
   escapeShellChars:(BOOL)escapeShellChars
           isUpload:(BOOL)isUpload
       tabTransform:(iTermTabTransformTags)tabTransform
       spacesPerTab:(int)spacesPerTab
           progress:(void (^)(NSInteger))progress;

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

#pragma mark - Testing

// This method can be overridden for testing.
- (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti
                                     target:(id)aTarget
                                   selector:(SEL)aSelector
                                   userInfo:(id)userInfo
                                    repeats:(BOOL)yesOrNo;

@end
