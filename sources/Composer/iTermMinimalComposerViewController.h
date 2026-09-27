//
//  iTermMinimalComposerViewController.h
//  iTerm2
//
//  Created by George Nachman on 3/31/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class TmuxController;
@protocol VT100RemoteHostReading;
@class iTermMinimalComposerViewController;
@class iTermSuggestionRequest;
@protocol iTermSyntaxHighlighting;
@class iTermVariableScope;
@protocol VT100RemoteHostReading;

@protocol iTermMinimalComposerViewControllerDelegate<NSObject>
- (void)minimalComposer:(iTermMinimalComposerViewController *)composer
            sendCommand:(NSString *)command
             addNewline:(BOOL)addNewlin
                dismiss:(BOOL)dismiss;
- (void)minimalComposer:(iTermMinimalComposerViewController *)composer
         enqueueCommand:(NSString *)command
                dismiss:(BOOL)dismiss;
- (void)minimalComposer:(iTermMinimalComposerViewController *)composer
            sendControl:(NSString *)control;
- (void)minimalComposer:(iTermMinimalComposerViewController *)composer
    sendToAdvancedPaste:(NSString *)content;
- (NSRect)minimalComposer:(iTermMinimalComposerViewController *)composer
           frameForHeight:(CGFloat)desiredHeight;
- (CGFloat)minimalComposerMaximumHeight:(iTermMinimalComposerViewController *)composer;
- (void)minimalComposer:(iTermMinimalComposerViewController *)composer
       frameDidChangeTo:(NSRect)newFrame;
- (CGFloat)minimalComposerLineHeight:(iTermMinimalComposerViewController *)composer;
- (void)minimalComposerOpenHistory:(iTermMinimalComposerViewController *)composer
                            prefix:(NSString *)prefix
                         forSearch:(BOOL)forSearch;
- (void)minimalComposerShowCompletions:(NSArray<NSString *> *)completions;
- (BOOL)minimalComposer:(iTermMinimalComposerViewController *)composer wantsKeyEquivalent:(NSEvent *)event;
- (void)minimalComposer:(iTermMinimalComposerViewController *)composer performFindPanelAction:(id)sender;
- (void)minimalComposer:(iTermMinimalComposerViewController *)composer
 desiredHeightDidChange:(CGFloat)desiredHeight;
- (void)minimalComposerAutoComposerTextDidChange:(iTermMinimalComposerViewController *)composer;
- (void)minimalComposerClear:(iTermMinimalComposerViewController *)composer;
- (id<iTermSyntaxHighlighting>)minimalComposer:(iTermMinimalComposerViewController *)composer
          syntaxHighlighterForAttributedString:(NSMutableAttributedString *)attributedString;
- (void)minimalComposerDidBecomeFirstResponder:(iTermMinimalComposerViewController *)composer;
- (BOOL)minimalComposerShouldFetchSuggestions:(iTermMinimalComposerViewController *)composer
                                      forHost:(id<VT100RemoteHostReading>)remoteHost
                               tmuxController:(TmuxController *)tmuxController;
- (void)minimalComposer:(iTermMinimalComposerViewController *)composer
       fetchSuggestions:(iTermSuggestionRequest *)request
          byUserRequest:(BOOL)byUserRequest;
- (BOOL)minimalComposerHandleKeyDown:(NSEvent *)event;
- (nullable NSResponder *)minimalComposerNextResponder;
- (BOOL)minimalComposerShouldForwardCopy:(iTermMinimalComposerViewController *)composer;
- (void)minimalComposerForwardMenuItem:(NSMenuItem *)menuItem;
- (NSString * _Nullable)minimalComposer:(iTermMinimalComposerViewController *)composer
             valueOfEnvironmentVariable:(NSString *)name;
- (void)minimalComposerPreferredOffsetFromTopDidChange:(iTermMinimalComposerViewController *)composer;

@optional
// Opt-in: fired on every text change (even outside auto-composer mode)
// when `forwardsTextChangesAlways` is set. The cockpit uses it to drive
// its @-mention picker. No effect on ordinary composer usage.
- (void)minimalComposerTextDidChange:(iTermMinimalComposerViewController *)composer;
@end

@interface iTermMinimalComposerViewController : NSViewController
@property (nonatomic, weak) id<iTermMinimalComposerViewControllerDelegate> delegate;
@property (nonatomic, readonly) NSString *stringValue;
@property (nonatomic) BOOL isAutoComposer;
@property (nonatomic, readonly) CGFloat desiredHeight;
@property (nonatomic) BOOL isSeparatorVisible;
@property (nonatomic, strong) NSColor *separatorColor;
@property (nonatomic, readonly) NSRect cursorFrameInScreenCoordinates;
@property (nonatomic) CGFloat preferredOffsetFromTop;

// Cockpit hosting hooks. All are opt-in and inert unless the embedder
// sets them; ordinary composer usage is unaffected.

// When YES, minimalComposerTextDidChange: is delivered on every edit,
// not just in auto-composer mode.
@property (nonatomic) BOOL forwardsTextChangesAlways;
// The current contents including any @-mention attachment tokens.
@property (nonatomic, readonly) NSAttributedString *attributedStringValue;
@property (nonatomic, readonly) NSRange composerSelectedRange;
// The view an @-mention completion popup should anchor to.
@property (nonatomic, readonly) NSView *completionAnchorView;
// Replace a character range with an attributed string (e.g. a mention
// token), going through the text view's change machinery.
- (void)replaceRange:(NSRange)range withAttributedString:(NSAttributedString *)attributedString;
// Remove the drag handles, close button, and border and disable
// dragging so the composer can sit docked inside another view.
- (void)setDockedChromeHidden:(BOOL)hidden;
// Allow attachment tokens (e.g. @-mention chips) to survive editing.
// The composer is plain-text by default (richText=NO in the XIB), which
// strips attachments; the cockpit turns this on for its instance only.
- (void)setComposerRichTextEnabled:(BOOL)enabled;
// Placeholder drawn when the composer holds no typed command. Inert
// (nil) for ordinary composer usage.
- (void)setComposerPlaceholder:(nullable NSString *)placeholder;
// Empty the field.
- (void)clearComposer;

- (void)updateFrame;
- (void)makeFirstResponder;
- (void)setHost:(id<VT100RemoteHostReading>)host
workingDirectory:(NSString *)pwd
          scope:(iTermVariableScope *)scope
 tmuxController:(TmuxController *)tmuxController;
- (void)setFont:(NSFont *)font;
- (void)setTextColor:(NSColor *)textColor cursorColor:(NSColor *)cursorColor;
- (void)setPrefix:(NSMutableAttributedString * _Nullable)prefix;

- (BOOL)composerIsFirstResponder;
- (void)insertText:(NSString *)text;
- (void)paste:(id)sender;
- (void)deleteLastCharacter;
- (void)setString:(NSString *)string includingPrefix:(BOOL)includingPrefix;

@end

NS_ASSUME_NONNULL_END
