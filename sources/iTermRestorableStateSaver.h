//
//  iTermRestorableStateSaver.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/26/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol iTermRestorableStateSaving<NSObject>
- (NSArray<NSWindow *> *)restorableStateWindows;

- (BOOL)restorableStateWindowNeedsRestoration:(NSWindow *)window;

- (void)restorableStateEncodeWithCoder:(NSCoder *)coder
                                window:(NSWindow *)window;
@end

@interface iTermRestorableStateSaver : NSObject
@property (nonatomic) BOOL needsSave;
@property (nonatomic, weak) id<iTermRestorableStateSaving> delegate;
@property (nonatomic, readonly) dispatch_queue_t queue;
@property (nonatomic, readonly) NSURL *indexURL;

- (instancetype)initWithQueue:(dispatch_queue_t)queue
                     indexURL:(NSURL *)indexURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)save;

@end

NS_ASSUME_NONNULL_END
