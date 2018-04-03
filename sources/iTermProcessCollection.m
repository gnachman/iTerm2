//
//  iTermProcessCollection.m
//  iTerm2
//
//  Created by George Nachman on 4/30/17.
//
//

#import "iTermProcessCollection.h"
#import "NSArray+iTerm.h"

@implementation iTermProcessInfo {
    NSMutableArray *_children;
    __weak iTermProcessInfo *_deepestForegroundJob;
    BOOL _haveDeepestForegroundJob;
}

- (NSString *)treeStringWithIndent:(NSString *)indent {
    NSString *children = [[_children mapWithBlock:^id(id anObject) {
        return [anObject treeStringWithIndent:[indent stringByAppendingString:@"  "]];
    }] componentsJoinedByString:@"\n"];
    if (_children.count > 0) {
        children = [@"\n" stringByAppendingString:children];
    }
    return [NSString stringWithFormat:@"%@pid=%@ name=%@ fg=%@%@", indent, @(self.processID), self.name, @(self.isForegroundJob), children];
}

- (NSMutableArray<iTermProcessInfo *> *)children {
    if (!_children) {
        _children = [NSMutableArray array];
    }
    return _children;
}

- (iTermProcessInfo *)deepestForegroundJob {
    if (!_haveDeepestForegroundJob) {
        NSInteger level = 0;
        NSMutableSet<NSNumber *> *visitedPids = [NSMutableSet set];
        BOOL cycle = NO;
        return [self deepestForegroundJob:&level visited:visitedPids cycle:&cycle];
    }
    return _deepestForegroundJob;
}

- (iTermProcessInfo *)deepestForegroundJob:(NSInteger *)levelInOut visited:(NSMutableSet *)visited cycle:(BOOL *)cycle {
    if ([visited containsObject:@(self.processID)]) {
        _haveDeepestForegroundJob = YES;
        _deepestForegroundJob = nil;
        *cycle = YES;
        return nil;
    } else {
        [visited addObject:@(self.processID)];
    }

    if (_children.count == 0 && _isForegroundJob) {
        _haveDeepestForegroundJob = YES;
        _deepestForegroundJob = self;
        return self;
    }

    NSInteger bestLevel = *levelInOut;
    iTermProcessInfo *bestProcessInfo = nil;
    for (iTermProcessInfo *child in _children) {
        NSInteger level = *levelInOut + 1;
        iTermProcessInfo *candidate = [child deepestForegroundJob:&level visited:visited cycle:cycle];
        if (*cycle) {
            _haveDeepestForegroundJob = YES;
            _deepestForegroundJob = nil;
            return nil;
        }
        if (level > bestLevel || bestProcessInfo == nil) {
            bestLevel = level;
            bestProcessInfo = candidate;
        }
    }
    _haveDeepestForegroundJob = YES;
    _deepestForegroundJob = bestProcessInfo;
    *levelInOut = bestLevel;
    return bestProcessInfo;
}

@end

@implementation iTermProcessCollection {
    NSMutableDictionary<NSNumber *, iTermProcessInfo *> *_processes;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _processes = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (NSString *)treeString {
    return [[_processes.allValues mapWithBlock:^id(iTermProcessInfo *anObject) {
        return [anObject treeStringWithIndent:@""];
    }] componentsJoinedByString:@"\n"];
}
- (void)addProcessWithName:(NSString *)name
                 processID:(pid_t)processID
           parentProcessID:(pid_t)parentProcessID
           isForegroundJob:(BOOL)isForegroundJob {
    iTermProcessInfo *info = [[iTermProcessInfo alloc] init];
    info.name = name;
    info.processID = processID;
    info.parentProcessID = parentProcessID;
    info.isForegroundJob = isForegroundJob;
    _processes[@(processID)] = info;
}

- (void)commit {
    [_processes enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull processID, iTermProcessInfo * _Nonnull info, BOOL * _Nonnull stop) {
        info.parent = self->_processes[@(info.parentProcessID)];
        [info.parent.children addObject:info];
    }];
}

- (iTermProcessInfo *)infoForProcessID:(pid_t)processID {
    return _processes[@(processID)];
}

@end
