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
- (id<iTermRestorableStateIndex>)restorableStateIndex;

- (void)restoreWindowWithRecord:(id<iTermRestorableStateRecord>)record
                     completion:(void (^)(void))completion;

- (void)restoreApplicationState;

- (void)eraseStateRestorationData;

@end

@protocol iTermRestorableStateSaving<NSObject>
- (NSArray<NSWindow *> *)restorableStateWindows;

- (BOOL)restorableStateWindowNeedsRestoration:(NSWindow *)window;

- (void)restorableStateEncodeWithCoder:(NSCoder *)coder
                                window:(NSWindow *)window;

@end

@protocol iTermRestorableStateSaver<NSObject>
@property (nonatomic, weak) id<iTermRestorableStateSaving> delegate;
- (void)saveSynchronously:(BOOL)synchronously withCompletion:(void (^)(void))completion;
@end

@interface iTermRestorableStateDriver : NSObject
@property (nonatomic, weak) id<iTermRestorableStateRestorer> restorer;
@property (nonatomic, weak) id<iTermRestorableStateSaver> saver;
@property (nonatomic, readonly) BOOL restoring;
@property (nonatomic, readonly) NSInteger numberOfWindowsRestored;
@property (nonatomic) BOOL needsSave;

- (void)restoreWithCompletion:(void (^)(void))completion;
- (void)save;
- (void)saveSynchronously;
- (void)erase;

@end

NS_ASSUME_NONNULL_END
