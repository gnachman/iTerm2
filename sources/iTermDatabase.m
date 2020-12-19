//
//  iTermDatabase.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import "iTermDatabase.h"

#import "DebugLogging.h"
#import "FMDatabase.h"

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

- (BOOL)passesIntegrityCheck {
    assert(_advisoryLock);

    NSString *checkType = arc4random_uniform(100) == 0 ? @"integrity_check" : @"quick_check";
    FMResultSet *results = [_db executeQuery:[NSString stringWithFormat:@"pragma %@", checkType]];
    NSString *value = nil;
    if ([results next]) {
        value = [results stringForColumn:checkType];
    } else {
        DLog(@"%@ check failed - no next result", checkType);
    }
    [results close];
    if (![value isEqualToString:@"ok"]) {
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
