//
//  iTermGraphTableTransformer.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import <Foundation/Foundation.h>

#import "iTermGraphEncoder.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermGraphDatabase;

// Converts a table from a db into a graph record.
@interface iTermGraphTableTransformer: NSObject
@property (nonatomic, readonly, nullable) iTermEncoderGraphRecord *root;
@property (nonatomic, readonly) NSArray *nodeRows;
@property (nonatomic, readonly) NSArray *valueRows;
@property (nonatomic, readonly, nullable) NSError *lastError;

// Database reference for lazy loading of large data
- (instancetype)initWithNodeRows:(NSArray *)nodeRows
                        database:(iTermGraphDatabase *_Nullable)database NS_DESIGNATED_INITIALIZER;

// Convenience initializer without database (no lazy loading)
- (instancetype)initWithNodeRows:(NSArray *)nodeRows;
- (instancetype)init NS_UNAVAILABLE;

#pragma mark - Private - for tests only

- (NSDictionary<NSNumber *, NSMutableDictionary *> * _Nullable)nodes:(out NSNumber **)rootNodeIDOut;
- (BOOL)attachChildrenToParents:(NSDictionary<NSNumber *, NSMutableDictionary *> *)nodes
              ignoringRootRowID:(NSNumber *)rootRowID;
@end

NS_ASSUME_NONNULL_END
