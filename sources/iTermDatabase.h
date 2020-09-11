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
- (BOOL)lock;
- (void)unlock;
- (NSError *)lastError;
// Return YES to commit, no to cancel
- (BOOL)transaction:(BOOL (^ NS_NOESCAPE)(void))block;
- (void)unlink;
- (NSURL *)url;
@end

@interface iTermSqliteDatabaseImpl: NSObject<iTermDatabase>
- (instancetype)initWithURL:(NSURL *)url;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
