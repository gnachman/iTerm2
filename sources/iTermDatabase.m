//
//  iTermDatabase.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import "iTermDatabase.h"

#import "DebugLogging.h"
#import "FMDatabase.h"
#import "NSArray+iTerm.h"
#import "iTermAdvancedSettingsModel.h"

@interface FMResultSet (iTerm)<iTermDatabaseResultSet>
@end

@interface iTermSqliteDatabaseImpl()
+ (NSArray<NSURL *> *)allURLsForDatabaseAt:(NSURL *)url;
- (instancetype)initWithDatabase:(FMDatabase *)db
                        lockName:(NSString *)lockName NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@implementation iTermSqliteDatabaseImpl {
    FMDatabase *_db;
    NSURL *_url;
    NSFileHandle *_advisoryLock;
    NSString *_lockName;
}

@synthesize timeoutHandler;

+ (NSArray<NSURL *> *)allURLsForDatabaseAt:(NSURL *)url {
    return [@[
        url,
        [url.URLByDeletingPathExtension URLByAppendingPathExtension:@"sqlite-shm"] ?: [NSNull null],
        [url.URLByDeletingPathExtension URLByAppendingPathExtension:@"sqlite-wal"] ?: [NSNull null],
    ] arrayByRemovingNulls];
}

+ (void)touchWithPrivateUnixPermissions:(NSURL *)url {
    int fd;
    do {
        fd = open(url.path.UTF8String, O_WRONLY | O_CREAT, 0600);
    } while (fd == -1 && (errno == EAGAIN || errno == EINTR));
    if (fd >= 0) {
        close(fd);
    }
}

- (instancetype)initWithURL:(NSURL *)url {
    return [self initWithURL:url lockName:@"lock"];
}

- (instancetype)initWithURL:(NSURL *)url lockName:(NSString *)lockName {
    if (![url.absoluteString hasPrefix:@"file::memory:"]) {
        for (NSURL *fileURL in [iTermSqliteDatabaseImpl allURLsForDatabaseAt:url]) {
            [iTermSqliteDatabaseImpl touchWithPrivateUnixPermissions:fileURL];
        }
    }
    FMDatabase *db = [FMDatabase databaseWithPath:url.path];
    return [self initWithDatabase:db lockName:lockName];
}

- (instancetype)initWithDatabase:(FMDatabase *)db lockName:(NSString *)lockName {
    self = [super init];
    if (self) {
        _lockName = [lockName copy];
        _url = db.databaseURL;
        _db = db;
    }
    return self;
}

- (void)unlink {
    assert(!_db.isOpen);
    if (!self.url) {
        return;
    }
    NSError *error = nil;
    NSArray<NSURL *> *urls = [iTermSqliteDatabaseImpl allURLsForDatabaseAt:self.url];
    for (NSURL *url in urls) {
        if (![[NSFileManager defaultManager] removeItemAtURL:url
                                                       error:&error]) {
            DLog(@"Failed to unlink %@: %@", url.path, error);
        }
    }
}

- (BOOL)executeUpdate:(NSString *)sql, ... {
    va_list args;
    va_start(args, sql);
    const BOOL result = [_db executeUpdate:sql withVAList:args];
    va_end(args);

    if (gDebugLogging) {
        va_start(args, sql);
        [self logStatement:sql vaList:args];
        va_end(args);
    }
    return result;
}

- (BOOL)executeUpdate:(NSString *)sql withNonOptionalArguments:(NSArray *)arguments {
    NSError *error = nil;

    BOOL result = [_db executeUpdate:sql values:arguments error:&error];
    if (error) {
        XLog(@"%@ failed: %@", sql, error);
    }

    if (gDebugLogging) {
        [self logStatement:sql arguments:arguments];
    }
    return result;
}

- (NSNumber *)lastInsertRowId {
    const int64_t rowid = _db.lastInsertRowId;
    if (!rowid) {
        return nil;
    }
    return @(rowid);
}

- (NSString *)formatSQL:(NSString *)sql vaList:(va_list)args {
    NSString *fmt = [sql stringByReplacingOccurrencesOfString:@"?" withString:@"“%@”"];
    return [[NSString alloc] initWithFormat:fmt arguments:args];
}

- (NSString *)formatSQL:(NSString *)sql arguments:(NSArray *)arguments {
    NSMutableString *formattedSQL = [sql mutableCopy];
    NSUInteger count = arguments.count;
    NSUInteger index = 0;

    NSRange searchRange = NSMakeRange(0, formattedSQL.length);
    while (index < count) {
        NSRange range = [formattedSQL rangeOfString:@"?" options:0 range:searchRange];
        if (range.location == NSNotFound) {
            break;
        }

        id argument = arguments[index++];
        NSString *replacement;

        if ([argument isKindOfClass:[NSString class]]) {
            replacement = [NSString stringWithFormat:@"“%@”", argument];
        } else if ([argument isKindOfClass:[NSNumber class]]) {
            replacement = [argument stringValue];
        } else if ([argument isKindOfClass:[NSNull class]]) {
            replacement = @"NULL";
        } else {
            replacement = [NSString stringWithFormat:@"“%@”", argument];
        }

        [formattedSQL replaceCharactersInRange:range withString:replacement];
        searchRange.location = range.location + replacement.length;
        searchRange.length = formattedSQL.length - searchRange.location;
    }

    return formattedSQL;
}

- (void)logStatement:(NSString *)sql vaList:(va_list)args {
    if (!gDebugLogging) {
        return;
    }
    NSString *statement = [self formatSQL:sql vaList:args];
    DebugLogImpl(__FILE__,
                 __LINE__,
                 __FUNCTION__,
                 statement);
}

- (void)logStatement:(NSString *)sql arguments:(NSArray *)arguments {
    if (!gDebugLogging) {
        return;
    }

    // Format the SQL statement with arguments
    NSString *statement = [self formatSQL:sql arguments:arguments];

    DebugLogImpl(__FILE__,
                 __LINE__,
                 __FUNCTION__,
                 statement);
}
- (id<iTermDatabaseResultSet> _Nullable)executeQuery:(NSString*)sql, ... {
    va_list args;
    va_start(args, sql);
    FMResultSet * _Nullable result = [_db executeQuery:sql withVAList:args];
    va_end(args);

    if (gDebugLogging) {
        va_start(args, sql);
        [self logStatement:sql vaList:args];
        va_end(args);
    }

    return result;
}

- (id<iTermDatabaseResultSet> _Nullable)executeQuery:(NSString*)sql withNonOptionalArguments:(NSArray *)arguments {
    FMResultSet * _Nullable result = [_db executeQuery:sql withArgumentsInArray:arguments];

    if (gDebugLogging) {
        [self logStatement:sql arguments:arguments];
    }

    return result;
}

typedef enum {
    iTermDatabaseIntegrityCheckStateQuerying,
    iTermDatabaseIntegrityCheckStateFinished,
    iTermDatabaseIntegrityCheckStateInterrupted
} iTermDatabaseIntegrityCheckState;

- (void)integrityCheckDidTimeOut:(NSObject *)lock state:(iTermDatabaseIntegrityCheckState *)statePtr {
    DLog(@"integrityCheckDidTimeOut");
    if (!self.timeoutHandler) {
        DLog(@"There is no timeout handler");
        return;
    }

    @synchronized(lock) {
        if (*statePtr != iTermDatabaseIntegrityCheckStateQuerying) {
            DLog(@"Timeout check running after completion");
            return;
        }
        DLog(@"Timeout check running while still querying");
    }

    DLog(@"Invoke timeout handler");
    if (!self.timeoutHandler()) {
        DLog(@"User declined to delete the db");
        return;
    }

    @synchronized(lock) {
        if (*statePtr != iTermDatabaseIntegrityCheckStateQuerying) {
            DLog(@"Succeeded on second chance");
            return;
        }
        DLog(@"Interrupt db check");
        [_db interrupt];
        DLog(@"state<-interrupted");
        *statePtr = iTermDatabaseIntegrityCheckStateInterrupted;
    }
}

- (BOOL)passesIntegrityCheck {
    assert(!_lockName || _advisoryLock != nil);

    if (![iTermAdvancedSettingsModel performSQLiteIntegrityCheck]) {
        return YES;
    }

    NSString *checkType = arc4random_uniform(100) == 0 ? @"integrity_check" : @"quick_check";
    NSObject *lock = [[NSObject alloc] init];
    __block iTermDatabaseIntegrityCheckState state = iTermDatabaseIntegrityCheckStateQuerying;
    __weak __typeof(self) weakSelf = self;
    const NSTimeInterval timeout = 10;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [weakSelf integrityCheckDidTimeOut:lock state:&state];
    });
    DLog(@"Begin pragma");
    FMResultSet *results = [_db executeQuery:[NSString stringWithFormat:@"pragma %@", checkType]];
    DLog(@"Returned from pragma");
    NSString *value = nil;
    DLog(@"Begin results.next");
    if ([results next]) {
        DLog(@"Returned from results.next");
        value = [results stringForColumn:checkType];
    } else {
        DLog(@"%@ check failed - no next result", checkType);
    }
    BOOL failed = NO;
    @synchronized(lock) {
        DLog(@"Check state");
        switch (state) {
            case iTermDatabaseIntegrityCheckStateQuerying:
                DLog(@"state<-finished");
                state = iTermDatabaseIntegrityCheckStateFinished;
                break;
            case iTermDatabaseIntegrityCheckStateFinished:
                assert(NO);
            case iTermDatabaseIntegrityCheckStateInterrupted:
                DLog(@"interrupted. set failed<-YES");
                failed = YES;
                break;
        }
    }
    [results close];
    if (failed || ![value isEqualToString:@"ok"]) {
        DLog(@"%@ check failed: %@", checkType, value);
        return NO;
    }
    return YES;
}

- (BOOL)open {
    DLog(@"Open");
    assert(!_lockName || _advisoryLock != nil);
    // At this point we always return with the lock held.
    const BOOL ok = [_db open];
    if (!ok) {
        DLog(@"Failed to open db: %@", _db.lastError);
        return NO;
    }
    if (![self passesIntegrityCheck]) {
        [self close];
        return NO;
    }

    DLog(@"Opened db and passed integrity check.");
    return YES;
}

- (BOOL)close {
    DLog(@"Close");
    return [_db close];
}

- (void)unlock {
    if (!_lockName) {
        return;
    }
    [_advisoryLock closeFile];
    _advisoryLock = nil;
}

- (NSString *)advisoryLockPath {
    if (!_lockName) {
        return nil;
    }
    NSURL *url = [_db.databaseURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:_lockName];
    return url.path;
}

- (BOOL)lock {
    if (!_lockName) {
        return YES;
    }
    [_advisoryLock closeFile];
    _advisoryLock = nil;

    int fd;
    do {
        DLog(@"Attempting to lock %@", self.advisoryLockPath);
        fd = open(self.advisoryLockPath.UTF8String, O_CREAT | O_TRUNC | O_EXLOCK | O_NONBLOCK, 0600);
    } while (fd < 0 && errno == EINTR);
    if (fd >= 0) {
        DLog(@"Lock acquired");
        _advisoryLock = [[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
        return YES;
    } else {
        DLog(@"Failed: %s", strerror(errno));
    }
    return NO;
}

- (NSError *)lastError {
    return [_db lastError];
}

- (void)beginDeferredTransaction {
    [_db beginDeferredTransaction];
}

- (void)commit {
    [_db commit];
}

- (void)rollback {
    [_db rollback];
}

- (BOOL)transaction:(BOOL (^ NS_NOESCAPE)(void))block {
    [_db beginDeferredTransaction];
    DLog(@"Begin transaction");
    BOOL result;
    if (block()) {
        DLog(@"Commit");
        result = [_db commit];
    } else {
        DLog(@"Rollback");
        result = [_db rollback];
    }
    if (!result) {
        DLog(@"error=%@", _db.lastError);
    }
    return result;
}

- (nonnull NSURL *)url {
    return _url;
}

- (id<iTermDatabaseResultSet> _Nullable)executeQuery:(nonnull NSString *)sql
                            withNonOptionalArguments:(nonnull NSArray *)arguments
                                               error:(NSError * _Nullable __autoreleasing * _Nullable)error { 
    FMResultSet * _Nullable result = [_db executeQuery:sql withArgumentsInArray:arguments];

    if (gDebugLogging) {
        [self logStatement:sql arguments:arguments];
    }
    if (error) {
        if (result) {
            *error = nil;
        } else {
            *error = [_db lastError];
        }
    }
    return result;
}


- (BOOL)executeUpdate:(nonnull NSString *)sql
withNonOptionalArguments:(nonnull NSArray *)arguments
                error:(out NSError * _Nullable __autoreleasing * _Nullable)error {
    BOOL result = [_db executeUpdate:sql values:arguments error:error];
    if (error && *error) {
        XLog(@"%@ failed: %@", sql, *error);
    }

    if (gDebugLogging) {
        [self logStatement:sql arguments:arguments];
    }
    return result;
}

@end
