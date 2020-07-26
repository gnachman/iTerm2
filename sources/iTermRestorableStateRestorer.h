//
//  iTermRestorableStateRestorer.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/26/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol iTermRestorableStateRestoring<NSObject>
- (void)restorableStateRestoreWithCoder:(NSCoder *)coder
                             identifier:(NSString *)identifier
                             completion:(void (^)(NSWindow *, NSError *))completion;
@end

@interface iTermRestorableStateRestorer : NSObject
@property (nonatomic, weak) id<iTermRestorableStateRestoring> delegate;
@property (nonatomic, readonly) dispatch_queue_t queue;
@property (nonatomic, readonly) NSURL *indexURL;
@property (nonatomic, readonly) NSInteger numberOfWindowsRestored;
@property (nonatomic, readonly) BOOL restoring;

- (instancetype)initWithQueue:(dispatch_queue_t)queue
                     indexURL:(NSURL *)indexURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)restoreWithCompletion:(void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
