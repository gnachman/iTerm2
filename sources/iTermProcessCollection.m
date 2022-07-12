//
//  iTermProcessCollection.m
//  iTerm2
//
//  Created by George Nachman on 4/30/17.
//
//

#import "iTermProcessCollection.h"

#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

#import "iTerm2SharedARC-Swift.h"

@implementation iTermProcessCollection {
    NSMutableDictionary<NSNumber *, iTermProcessInfo *> *_processes;
    id<iTermProcessDataSource> _dataSource;
}

- (instancetype)initWithDataSource:(id<iTermProcessDataSource>)dataSource {
    self = [super init];
    if (self) {
        _dataSource = dataSource;
        _processes = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (NSString *)treeString {
    return [[_processes.allValues mapWithBlock:^id(iTermProcessInfo *anObject) {
        return [anObject treeStringWithIndent:@""];
    }] componentsJoinedByString:@"\n"];
}

- (iTermProcessInfo *)addProcessWithProcessID:(pid_t)processID
                              parentProcessID:(pid_t)parentProcessID {
    iTermProcessInfo *info = [[iTermProcessInfo alloc] initWithPid:processID
                                                              ppid:parentProcessID
                                                        collection:self
                                                        dataSource:_dataSource];
    _processes[@(processID)] = info;
    return info;
}

- (void)commit {
    [_processes enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull processID, iTermProcessInfo * _Nonnull info, BOOL * _Nonnull stop) {
        info.parent = self->_processes[@(info.parentProcessID)];
        [info.parent addChildWithProcessID:info.processID];
    }];
}

- (iTermProcessInfo *)infoForProcessID:(pid_t)processID {
    return _processes[@(processID)];
}

@end
