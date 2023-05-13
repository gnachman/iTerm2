//
//  iTermComposerManager.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/31/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class TmuxController;
@protocol VT100RemoteHostReading;
@class iTermComposerManager;
@protocol iTermSyntaxHighlighting;
@class iTermVariableScope;
@class iTermStatusBarViewController;
@class iTermSuggestionRequest;

@protocol iTermComposerManagerDelegate<NSObject>
- (iTermStatusBarViewController *)composerManagerStatusBarViewController:(iTermComposerManager *)composerManager;
- (iTermVariableScope *)composerManagerScope:(iTermComposerManager *)composerManager;
- (NSView *)composerManagerContainerView:(iTermComposerManager *)composerManager;
- (void)composerManagerDidRemoveTemporaryStatusBarComponent:(iTermComposerManager *)composerManager;
- (void)composerManager:(iTermComposerManager *)composerManager
            sendCommand:(NSString *)command;
- (void)composerManager:(iTermComposerManager *)composerManager
         enqueueCommand:(NSString *)command;
- (void)composerManager:(iTermComposerManager *)composerManager
    sendToAdvancedPaste:(NSString *)command;
- (void)composerManager:(iTermComposerManager *)composerManager
            sendControl:(NSString *)control;
- (void)composerManagerDidDismissMinimalView:(iTermComposerManager *)composerManager;
- (void)composerManagerWillDismissMinimalView:(iTermComposerManager *)composerManager;
- (void)composerManagerDidDisplayMinimalView:(iTermComposerManager *)composerManager;
- (NSAppearance *_Nullable)composerManagerAppearance:(iTermComposerManager *)composerManager;
- (id<VT100RemoteHostReading>)composerManagerRemoteHost:(iTermComposerManager *)composerManager;
- (NSString *_Nullable)composerManagerWorkingDirectory:(iTermComposerManager *)composerManager;
- (NSString *)composerManagerShell:(iTermComposerManager *)composerManager;
- (NSString *)composerManagerUName:(iTermComposerManager *)composerManager;
- (TmuxController * _Nullable)composerManagerTmuxController:(iTermComposerManager *)composerManager;
- (NSFont *)composerManagerFont:(iTermComposerManager *)composerManager;
- (NSColor *)composerManagerTextColor:(iTermComposerManager *)composerManager;
- (NSColor *)composerManagerCursorColor:(iTermComposerManager *)composerManager;
- (void)composerManager:(iTermComposerManager *)composerManager
minimalFrameDidChangeTo:(NSRect)newFrame;
- (NSRect)composerManager:(iTermComposerManager *)composerManager
    frameForDesiredHeight:(CGFloat)desiredHeight
            previousFrame:(NSRect)previousFrame;
- (CGFloat)composerManagerLineHeight:(iTermComposerManager *)composerManager;
- (void)composerManagerOpenHistory:(iTermComposerManager *)composerManager
                            prefix:(NSString *)prefix
                         forSearch:(BOOL)forSearch;
- (BOOL)composerManager:(iTermComposerManager *)composerManager wantsKeyEquivalent:(NSEvent *)event;
- (void)composerManager:(iTermComposerManager *)composerManager performFindPanelAction:(id)sender;
- (void)composerManager:(iTermComposerManager *)composerManager
 desiredHeightDidChange:(CGFloat)desiredHeight;
- (void)composerManagerClear:(iTermComposerManager *)composerManager;
- (id<iTermSyntaxHighlighting>)composerManager:(iTermComposerManager *)composerManager
          syntaxHighlighterForAttributedString:(NSMutableAttributedString *)attributedString;
- (void)composerManagerDidBecomeFirstResponder:(iTermComposerManager *)composerManager;
- (BOOL)composerManagerShouldFetchSuggestions:(iTermComposerManager *)composerManager
                                      forHost:(id<VT100RemoteHostReading>)remoteHost
                               tmuxController:(TmuxController *)tmuxController;
- (void)composerManager:(iTermComposerManager *)composerManager
       fetchSuggestions:(iTermSuggestionRequest *)request;

@end

@interface iTermComposerManager : NSObject
@property (nonatomic, weak) id<iTermComposerManagerDelegate> delegate;
@property (nonatomic, readonly) BOOL dropDownComposerViewIsVisible;
@property (nonatomic, readonly) BOOL isEmpty;
@property (nonatomic) BOOL isAutoComposer;
@property (nonatomic, readonly) CGFloat desiredHeight;
@property (nonatomic, readonly) NSRect dropDownFrame;
@property (nonatomic, readonly) NSString *contents;
@property (nonatomic) BOOL temporarilyHidden;
@property (nonatomic, strong, readonly) id prefixUserData;
@property (nonatomic, readonly) NSRect cursorFrameInScreenCoordinates;

// Only used by dropdown composer
@property (nonatomic) BOOL isSeparatorVisible;
@property (nonatomic, strong) NSColor *separatorColor;

// In auto-composer mode did we get some typed-ahead text (entered during a previous command) that
// got automatically inserted into the composer?
@property (nonatomic) BOOL haveShellProvidedText;

- (void)setCommand:(NSString *)command;
// Reveal appropriately (focus status bar, open popover, or open minimal)
- (void)reveal;
- (void)toggle;
// Reveal minimal composer.
- (void)revealMinimal;
- (BOOL)dismiss;
- (BOOL)dismissAnimated:(BOOL)animated;
- (void)layout;
- (void)showWithCommand:(NSString *)command;
- (void)showOrAppendToDropdownWithString:(NSString *)string;
- (BOOL)dropDownComposerIsFirstResponder;
- (void)updateFrame;
- (void)makeDropDownComposerFirstResponder;
- (void)updateFont;
- (void)setPrefix:(NSMutableAttributedString * _Nullable)prefix userData:(id _Nullable)userData;
- (void)insertText:(NSString *)string;
- (void)reset;
- (void)paste:(id)sender;
- (void)deleteLastCharacter;

@end

NS_ASSUME_NONNULL_END
