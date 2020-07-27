//
//  iTermRestorableStateRestorer.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/26/20.
//

#import <Cocoa/Cocoa.h>

#import "iTermRestorableStateDriver.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermEncoderGraphRecord;

@protocol iTermRestorableStateRestoring<NSObject>
- (void)restorableStateRestoreWithRecord:(iTermEncoderGraphRecord *)record
                              identifier:(NSString *)identifier
                              completion:(void (^)(NSWindow * _Nullable, NSError * _Nullable))completion;

- (void)restorableStateRestoreApplicationStateWithRecord:(iTermEncoderGraphRecord *)record;

- (void)restorableStateRestoreWithCoder:(NSCoder *)coder
                             identifier:(NSString *)identifier
                             completion:(void (^)(NSWindow * _Nullable, NSError * _Nullable))completion;
@end

@interface iTermRestorableStateRestorer : NSObject<iTermRestorableStateRestorer>
@property (nonatomic, weak) id<iTermRestorableStateRestoring> delegate;
@property (nonatomic, readonly) NSURL *indexURL;

- (instancetype)initWithIndexURL:(NSURL *)indexURL erase:(BOOL)erase NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
