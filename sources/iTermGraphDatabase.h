//
//  iTermGraphDatabase.h
//  iTerm2
//
//  Created by George Nachman on 7/27/20.
//

#import <Foundation/Foundation.h>

#import "iTermGraphEncoder.h"

NS_ASSUME_NONNULL_BEGIN

// Converts a table from a db into a graph record.
@interface iTermGraphTableTransformer: NSObject
@property (nonatomic, readonly, nullable) iTermEncoderGraphRecord *root;
@property (nonatomic, readonly) NSArray *nodeRows;
@property (nonatomic, readonly) NSArray *valueRows;
@property (nonatomic, readonly, nullable) NSError *lastError;

- (instancetype)initWithNodeRows:(NSArray *)nodeRows
                       valueRows:(NSArray *)valueRows NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

#pragma mark - Private - for tests only

- (NSDictionary<NSDictionary *, NSMutableDictionary *> *)nodes:(out NSString **)rootNodeIDOut;
- (BOOL)attachValuesToNodes:(NSDictionary<NSDictionary *, NSMutableDictionary *> *)nodes;
- (BOOL)attachChildrenToParents:(NSDictionary<NSDictionary *, NSMutableDictionary *> *)nodes;

@end

@class FMResultSet;

@protocol iTermDatabaseResultSet<NSObject>
- (BOOL)next;
- (void)close;
- (NSString *)stringForColumn:(NSString *)columnName;
- (long long)longLongIntForColumn:(NSString *)columnName;
- (NSData *)dataForColumn:(NSString *)columnName;
- (NSDate *)dateForColumn:(NSString *)columnName;
@end

@protocol iTermDatabase<NSObject>
- (BOOL)executeUpdate:(NSString*)sql, ...;
- (id<iTermDatabaseResultSet> _Nullable)executeQuery:(NSString*)sql, ...;
- (BOOL)open;
- (NSError *)lastError;
// Return YES to commit, no to cancel
- (BOOL)transaction:(BOOL (^ NS_NOESCAPE)(void))block;
@end

@protocol iTermDatabaseFactory<NSObject>
- (nullable id<iTermDatabase>)withURL:(NSURL *)url;
@end

@interface iTermSqliteDatabaseFactory<iTermDatabaseFactory>: NSObject
- (instancetype)init NS_UNAVAILABLE;
@end

@class iTermThread;

// Manages a SQLite database that holds an encoded graph. Loads it and updates it incrementally.
@interface iTermGraphDatabase: NSObject
@property (nonatomic, readonly) iTermEncoderGraphRecord *record;
@property (nonatomic, readonly) NSURL *url;
@property (nonatomic, readonly) iTermThread *thread;

- (instancetype)initWithURL:(NSURL *)url
            databaseFactory:(id<iTermDatabaseFactory>)databaseFactory NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)update:(void (^ NS_NOESCAPE)(iTermGraphEncoder *encoder))block;

@end

NS_ASSUME_NONNULL_END
