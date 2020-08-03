//
//  iTermDatabase.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

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
- (NSNumber * _Nullable)lastInsertRowId;
- (id<iTermDatabaseResultSet> _Nullable)executeQuery:(NSString*)sql, ...;
- (BOOL)open;
- (BOOL)close;
- (NSError *)lastError;
// Return YES to commit, no to cancel
- (BOOL)transaction:(BOOL (^ NS_NOESCAPE)(void))block;
- (void)unlink;
@end

@protocol iTermDatabaseFactory<NSObject>
- (nullable id<iTermDatabase>)withURL:(NSURL *)url;
@end

@interface iTermSqliteDatabaseFactory: NSObject<iTermDatabaseFactory>
@end

NS_ASSUME_NONNULL_END
