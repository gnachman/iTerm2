//
//  iTermRestorableStateSQLite.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import "iTermRestorableStateSQLite.h"
#import "iTermGraphSQLEncoder.h"
#import "iTermGraphDatabase.h"

@implementation iTermRestorableStateSQLite {
    iTermGraphDatabase *_db;
}

- (instancetype)initWithURL:(NSURL *)url {
    self = [super init];
    if (self) {
        _db = [[iTermGraphDatabase alloc] initWithURL:url
                                      databaseFactory:[[iTermSqliteDatabaseFactory alloc] init]];
    }
    return self;
}

- (id<iTermRestorableStateIndex>)restorableStateIndex {
    // TODO
    return nil;
}

- (void)restoreWindowWithRecord:(id<iTermRestorableStateRecord>)record
                     completion:(void (^)(void))completion {
    // TODO
    completion();
}

- (void)save {
    // TODO
}

@end
