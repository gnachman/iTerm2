//
//  iTermGraphDatabase.h
//  iTerm2
//
//  Created by George Nachman on 7/27/20.
//

#import <Foundation/Foundation.h>

#import "iTermGraphEncoder.h"
#import "iTermDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermCallback;
@class iTermThread;

// Manages a SQLite database that holds an encoded graph. Loads it and updates it incrementally.
@interface iTermGraphDatabase: NSObject
@property (atomic, readonly) iTermEncoderGraphRecord *record;
@property (nonatomic, readonly) NSURL *url;
@property (nonatomic, readonly) iTermThread *thread;

// Tests only!
@property (nonatomic, readonly) id<iTermDatabase> db;

- (instancetype)initWithDatabase:(id<iTermDatabase>)db NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;


// Returns NO if the completion block will never be called. Otherwise it will be called after the
// method returns (guaranteed!).
- (BOOL)updateSynchronously:(BOOL)sync
                      block:(void (^ NS_NOESCAPE)(iTermGraphEncoder * _Nonnull))block
                 completion:(nullable iTermCallback *)completion;
- (void)invalidateSynchronously:(BOOL)sync;
- (void)whenReady:(void (^)(void))readyBlock;

@end

NS_ASSUME_NONNULL_END
