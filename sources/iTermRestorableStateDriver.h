//
//  iTermRestorableStateDriver.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class NSWindow;

@protocol iTermRestorableStateRecord<NSObject>
- (void)didFinishRestoring;
- (NSKeyedUnarchiver *)unarchiver;
- (NSString *)identifier;
- (NSInteger)windowNumber;
// withPlaintext
- (id<iTermRestorableStateRecord>)recordWithPayload:(id)payload;
@end

@protocol iTermRestorableStateIndex<NSObject>

- (NSUInteger)restorableStateIndexNumberOfWindows;

- (void)restorableStateIndexUnlink;

- (id<iTermRestorableStateRecord>)restorableStateRecordAtIndex:(NSUInteger)i;

@end

@protocol iTermRestorableStateRestorer<NSObject>

- (void)loadRestorableStateIndexWithCompletion:(void (^)(id<iTermRestorableStateIndex> _Nullable))completion;

- (void)restoreWindowWithRecord:(id<iTermRestorableStateRecord>)record
                     completion:(void (^)(NSString *windowIdentifier, NSWindow *window))completion;

- (void)restoreApplicationState;

- (void)eraseStateRestorationDataSynchronously:(BOOL)sync;

@end

@protocol iTermRestorableStateSaving<NSObject>
- (NSArray<NSWindow *> *)restorableStateWindows;

- (BOOL)restorableStateWindowNeedsRestoration:(NSWindow *)window;

- (void)restorableStateEncodeWithCoder:(NSCoder *)coder
                                window:(NSWindow *)window;

@end

@protocol iTermRestorableStateSaver<NSObject>
@property (nonatomic, weak) id<iTermRestorableStateSaving> delegate;
// Returns NO if an async request couldn't be done because it's busy. Completion is not called in
// that case.
- (BOOL)saveSynchronously:(BOOL)synchronously withCompletion:(void (^)(void))completion;
@end

@interface iTermRestorableStateDriver : NSObject
@property (nonatomic, weak) id<iTermRestorableStateRestorer> restorer;
@property (nonatomic, weak) id<iTermRestorableStateSaver> saver;
@property (nonatomic, readonly) BOOL restoring;
@property (nonatomic, readonly) NSInteger numberOfWindowsRestored;
@property (nonatomic) BOOL needsSave;

// callbacks will be removed when they are used and won't be mutated after completion runs.
// ready is called after all windows have been asked to restore.
// completion is called when they are actually restored.
- (void)restoreWithSystemCallbacks:(NSMutableDictionary<NSString *, void (^)(NSWindow *, NSError *)> *)callbacks
                             ready:(void (^)(void))ready
                        completion:(void (^)(void))completion;
- (void)save;
- (void)saveSynchronously;
- (void)eraseSynchronously:(BOOL)sync;

@end

NS_ASSUME_NONNULL_END
