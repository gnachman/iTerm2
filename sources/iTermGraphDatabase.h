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
@property (nonatomic, readonly) iTermEncoderGraphRecord *record;
@property (nonatomic, readonly) NSURL *url;
@property (nonatomic, readonly) iTermThread *thread;

// Tests only!
@property (nonatomic, readonly) id<iTermDatabase> db;

- (instancetype)initWithURL:(NSURL *)url
            databaseFactory:(id<iTermDatabaseFactory>)databaseFactory NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;


- (void)updateSynchronously:(BOOL)sync
                      block:(void (^ NS_NOESCAPE)(iTermGraphEncoder * _Nonnull))block
                 completion:(nullable iTermCallback *)completion;

- (void)update:(void (^ NS_NOESCAPE)(iTermGraphEncoder * _Nonnull))block
    completion:(nullable iTermCallback *)completion;

@end

NS_ASSUME_NONNULL_END
