//
//  iTermComposerManager.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/31/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

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
- (void)composerManagerDidDismissMinimalView:(iTermComposerManager *)composerManager;
@end

@interface iTermComposerManager : NSObject
@property (nonatomic, weak) id<iTermComposerManagerDelegate> delegate;
@property (nonatomic, readonly) BOOL dropDownComposerViewIsVisible;

- (void)reveal;
- (void)layout;

@end

NS_ASSUME_NONNULL_END
