//
//  iTermDatabase.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import "iTermDatabase.h"

#import "DebugLogging.h"
#import "FMDatabase.h"
#import "iTermAdvancedSettingsModel.h"

@interface FMResultSet (iTerm)<iTermDatabaseResultSet>
@end

@interface iTermSqliteDatabaseImpl()
+ (NSArray<NSURL *> *)allURLsForDatabaseAt:(NSURL *)url;
- (instancetype)initWithDatabase:(FMDatabase *)db NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@implementation iTermSqliteDatabaseImpl {
    FMDatabase *_db;
    NSURL *_url;
    NSFileHandle *_advisoryLock;
}

@synthesize timeoutHandler;

+ (NSArray<NSURL *> *)allURLsForDatabaseAt:(NSURL *)url {
    return @[
        url,
        [url.URLByDeletingPathExtension URLByAppendingPathExtension:@"sqlite-shm"],
        [url.URLByDeletingPathExtension URLByAppendingPathExtension:@"sqlite-wal"],
    ];
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
    for (NSURL *fileURL in [iTermSqliteDatabaseImpl allURLsForDatabaseAt:url]) {
        [iTermSqliteDatabaseImpl touchWithPrivateUnixPermissions:fileURL];
    }
    FMDatabase *db = [FMDatabase databaseWithPath:url.path];
    return [self initWithDatabase:db];
}

- (instancetype)initWithDatabase:(FMDatabase *)db {
    self = [super init];
    if (self) {
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

- (void)logStatement:(NSString *)sql vaList:(va_list)args {
    if (!gDebugLogging) {
        return;
    }
    NSString *statement = [self formatSQL:sql vaList:args];
    NSLog(@"%@", statement);
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
    assert(_advisoryLock);

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
    assert(_advisoryLock);
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
    [_advisoryLock closeFile];
    _advisoryLock = nil;
}

- (NSString *)advisoryLockPath {
    NSURL *url = [_db.databaseURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"lock"];
    return url.path;
}

- (BOOL)lock {
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

- (BOOL)transaction:(BOOL (^ NS_NOESCAPE)(void))block {
    [_db beginDeferredTransaction];
    DLog(@"Begin transaction");
    BOOL result;
#if BETA
    {
        FMResultSet *rs = [_db executeQuery:@"select count(*) as c from Node where parent=0"];
        if ([rs next]) {
            NSString *count = [rs stringForColumn:@"c"];
            ITBetaAssert(count.integerValue < 2, @"PRE: %@", count);
        }
    }
#endif
    if (block()) {
        DLog(@"Commit");
        result = [_db commit];
    } else {
        DLog(@"Rollback");
        result = [_db rollback];
    }
#if BETA
    {
        FMResultSet *rs = [_db executeQuery:@"select count(*) as c from Node where parent=0"];
        if ([rs next]) {
            NSString *count = [rs stringForColumn:@"c"];
            ITBetaAssert(count.integerValue == 1, @"POST: %@", count);
        }
    }
#endif
    if (!result) {
        DLog(@"error=%@", _db.lastError);
    }
    return result;
}

- (nonnull NSURL *)url {
    return _url;
}


@end
