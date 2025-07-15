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
- (NSString * _Nullable)stringForColumn:(NSString *)columnName;
- (long long)longLongIntForColumn:(NSString *)columnName;
- (NSData * _Nullable)dataForColumn:(NSString *)columnName;
- (NSDate * _Nullable)dateForColumn:(NSString *)columnName;
@end

@protocol iTermDatabase<NSObject>
- (BOOL)executeUpdate:(NSString*)sql, ...;

- (BOOL)executeUpdate:(NSString *)sql
withNonOptionalArguments:(NSArray *)arguments
                error:(out NSError * _Nullable __autoreleasing *)error;

- (NSNumber * _Nullable)lastInsertRowId;
- (id<iTermDatabaseResultSet> _Nullable)executeQuery:(NSString*)sql, ...;

- (id<iTermDatabaseResultSet> _Nullable)executeQuery:(NSString*)sql
                            withNonOptionalArguments:(NSArray *)arguments
                                               error:(NSError * _Nullable __autoreleasing *)error;  // for swift
- (BOOL)open;
- (BOOL)close;
- (BOOL)lock;
- (void)unlock;
- (NSError *)lastError;
// Return YES to commit, no to cancel
- (BOOL)transaction:(BOOL (^ NS_NOESCAPE)(void))block;
- (void)unlink;
- (NSURL *)url;

- (void)beginDeferredTransaction;
- (void)commit;
- (void)rollback;

// If set the timeout handler will be called and can return YES to erase the db when it takes
// too long to initialize or NO to keep trying.
@property (nonatomic, copy) BOOL (^timeoutHandler)(void);
@end

@interface iTermSqliteDatabaseImpl: NSObject<iTermDatabase>
- (instancetype)initWithURL:(NSURL *)url lockName:(NSString * _Nullable)lockName;
- (instancetype)initWithURL:(NSURL *)url;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
