//
//  iTermWorkingDirectoryProvider.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/24/26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Protocol for synchronous/async working directory fetching.
/// PTYTask implements this.
@protocol iTermWorkingDirectoryProvider <NSObject>

/// Get working directory synchronously (slow - avoid).
@property (atomic, readonly, nullable) NSString *getWorkingDirectory;

/// Get working directory asynchronously.
- (void)getWorkingDirectoryWithCompletion:(void (^)(NSString * _Nullable pwd))completion;

@end

NS_ASSUME_NONNULL_END
