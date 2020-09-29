//
//  iTermRestorableStateController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/18/20.
//

#import <Foundation/Foundation.h>
#import "iTermRestorableStateRestorer.h"
#import "iTermRestorableStateSaver.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermRestorableStateController;
@class NSCoding;
@class NSWindow;

@protocol iTermRestorableStateControllerDelegate<iTermRestorableStateSaving, iTermRestorableStateRestoring>
- (void)restorableStateDidFinishRequestingRestorations:(iTermRestorableStateController *)sender;
@end

@interface iTermRestorableStateController : NSObject
@property (nonatomic, weak) id<iTermRestorableStateControllerDelegate> delegate;
@property (nonatomic, readonly) NSInteger numberOfWindowsRestored;

// This is the single source of truth for the whole app.
+ (BOOL)stateRestorationEnabled;

- (void)saveRestorableState;

// Call exactly one of these at startup:
- (void)restoreWindowsWithCompletion:(void (^)(void))completion;
- (void)didSkipRestoration;

@end

NS_ASSUME_NONNULL_END
