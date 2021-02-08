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

@protocol iTermRestorableWindowController<NSObject>
- (void)didFinishRestoringWindow;
@end

@interface iTermRestorableStateController : NSObject
@property (nonatomic, class, readwrite) BOOL shouldIgnoreOpenUntitledFile;
@property (nonatomic, weak) id<iTermRestorableStateControllerDelegate> delegate;
@property (nonatomic, readonly) NSInteger numberOfWindowsRestored;
@property (nonatomic, class) BOOL forceSaveState;

+ (instancetype)sharedInstance;

// This is the single source of truth for the whole app.
+ (BOOL)stateRestorationEnabled;

- (void)saveRestorableState;

// Call exactly one of these at startup:
- (void)restoreWindowsWithCompletion:(void (^)(void))completion;
- (void)didSkipRestoration;

// The callback will be run after the window with this
// identifier gets restored. If restoration completes
// without this window, the callback is run with two nil
// arguments.
- (void)setSystemRestorationCallback:(void (^)(NSWindow *, NSError *))callback
                    windowIdentifier:(NSString *)windowIdentifier;

@end

NS_ASSUME_NONNULL_END
