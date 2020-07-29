//
//  iTermRestorableStateRestorer.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/26/20.
//

#import <Cocoa/Cocoa.h>

#import "iTermRestorableStateDriver.h"

NS_ASSUME_NONNULL_BEGIN

@protocol iTermRestorableStateRestoring<NSObject>
- (void)restorableStateRestoreWithCoder:(NSCoder *)coder
                             identifier:(NSString *)identifier
                             completion:(void (^)(NSWindow *, NSError *))completion;
@end

@interface iTermRestorableStateRestorer : NSObject<iTermRestorableStateRestorer>
@property (nonatomic, weak) id<iTermRestorableStateRestoring> delegate;
@property (nonatomic, readonly) NSURL *indexURL;

- (instancetype)initWithIndexURL:(NSURL *)indexURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
