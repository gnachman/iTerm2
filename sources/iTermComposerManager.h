//
//  iTermComposerManager.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/31/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class TmuxController;
@class VT100RemoteHost;
@class iTermComposerManager;
@class iTermVariableScope;
@class iTermStatusBarViewController;

@protocol iTermComposerManagerDelegate<NSObject>
- (iTermStatusBarViewController *)composerManagerStatusBarViewController:(iTermComposerManager *)composerManager;
- (iTermVariableScope *)composerManagerScope:(iTermComposerManager *)composerManager;
- (NSView *)composerManagerContainerView:(iTermComposerManager *)composerManager;
- (void)composerManagerDidRemoveTemporaryStatusBarComponent:(iTermComposerManager *)composerManager;
- (void)composerManager:(iTermComposerManager *)composerManager
            sendCommand:(NSString *)command;
- (void)composerManager:(iTermComposerManager *)composerManager
    sendToAdvancedPaste:(NSString *)command;
- (void)composerManagerDidDismissMinimalView:(iTermComposerManager *)composerManager;
- (NSAppearance *_Nullable)composerManagerAppearance:(iTermComposerManager *)composerManager;
- (VT100RemoteHost *)composerManagerRemoteHost:(iTermComposerManager *)composerManager;
- (NSString *_Nullable)composerManagerWorkingDirectory:(iTermComposerManager *)composerManager;
- (NSString *)composerManagerShell:(iTermComposerManager *)composerManager;
- (TmuxController * _Nullable)composerManagerTmuxController:(iTermComposerManager *)composerManager;
- (NSFont *)composerManagerFont:(iTermComposerManager *)composerManager;
@end

@interface iTermComposerManager : NSObject
@property (nonatomic, weak) id<iTermComposerManagerDelegate> delegate;
@property (nonatomic, readonly) BOOL dropDownComposerViewIsVisible;

- (void)setCommand:(NSString *)command;
// Reveal appropriately (focus status bar, open popover, or open minimal)
- (void)reveal;
// Reveal minimal composer.
- (void)revealMinimal;
- (BOOL)dismiss;
- (void)layout;
- (void)showWithCommand:(NSString *)command;
- (void)showOrAppendToDropdownWithString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
