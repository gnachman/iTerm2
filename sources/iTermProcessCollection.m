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

@interface iTermProcessInfoLock : NSObject
@end

@implementation iTermProcessInfoLock
@end

@interface iTermProcessInfo()
@property(nonatomic, weak, readwrite) iTermProcessInfo *parent;
@property(atomic, copy) NSString *nameValue;
@property(atomic, copy) NSString *argv0Value;
@property(atomic, copy) NSString *commandLineValue;
@property(atomic) NSNumber *isForegroundJobValue;
@end

@implementation iTermProcessInfo {
    __weak iTermProcessCollection *_collection;
    NSMutableIndexSet *_childProcessIDs;
    __weak iTermProcessInfo *_deepestForegroundJob;
    BOOL _haveDeepestForegroundJob;
    NSNumber *_isForegroundJob;
    BOOL _initialized;
    NSNumber *_testValueForForegroundJob;
    BOOL _computingTreeString;
    NSDate *_startTime;
    id<iTermProcessDataSource> _dataSource;
}

- (instancetype)initWithPid:(pid_t)processID
                       ppid:(pid_t)parentProcessID
                 collection:(iTermProcessCollection *)collection
                 dataSource:(id<iTermProcessDataSource>)dataSource {
    self = [super init];
    if (self) {
        _processID = processID;
        _parentProcessID = parentProcessID;
        _childProcessIDs = [[NSMutableIndexSet alloc] init];
        _collection = collection;
        _dataSource = dataSource;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p pid=%@ name=%@ children.count=%@ haveDeepest=%@ isFg=%@>",
            self.class, self, @(self.processID), self.name, @(_childProcessIDs.count), @(_haveDeepestForegroundJob), _isForegroundJob];
}

- (NSString *)recursiveDescription {
    return [self recursiveDescription:0];
}

- (NSString *)recursiveDescription:(int)depth {
    if (depth == 100) {
        return @"Truncated at 100 levels";
    }
    NSString *me = [NSString stringWithFormat:@"%@%@ %@",
            [@"  " stringRepeatedTimes:depth],
            @(_processID), self.name];
    if (!self.children.count) {
        return me;
    }
    NSArray<NSString *> *childStrings = [self.children mapWithBlock:^id _Nonnull(iTermProcessInfo * _Nonnull child) {
        return [child recursiveDescription:depth + 1];
    }];
    return [[@[ me ] arrayByAddingObjectsFromArray:childStrings] componentsJoinedByString:@"\n"];
}

- (BOOL)isEqual:(id)object {
    iTermProcessInfo *other = [iTermProcessInfo castFrom:object];
    if (!other) {
        return NO;
    }
    return self.processID == other.processID && [self.name isEqualToString:other.name] && self.parentProcessID == self.parentProcessID;
}

- (NSString *)treeStringWithIndent:(NSString *)indent {
    if (_computingTreeString) {
        return [NSString stringWithFormat:@"<CYCLE DETECTED AT %@>", self];
    }
    _computingTreeString = YES;
    NSArray<iTermProcessInfo *> *childArray = self.children;
    NSString *children = [[childArray mapWithBlock:^id(id anObject) {
        return [anObject treeStringWithIndent:[indent stringByAppendingString:@"  "]];
    }] componentsJoinedByString:@"\n"];
    _computingTreeString = NO;
    if (childArray.count > 0) {
        children = [@"\n" stringByAppendingString:children];
    }
    return [NSString stringWithFormat:@"%@pid=%@ name=%@ fg=%@%@", indent, @(self.processID), self.name, @(self.isForegroundJob), children];
}

- (NSArray<iTermProcessInfo *> *)children {
    NSMutableArray<iTermProcessInfo *> *result = [NSMutableArray array];
    [_childProcessIDs enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        iTermProcessInfo *child = [_collection infoForProcessID:idx];
        if (child) {
            [result addObject:child];
        }
    }];
    return result;
}

- (NSArray<iTermProcessInfo *> *)sortedChildren {
    return [self.children sortedArrayUsingComparator:^NSComparisonResult(iTermProcessInfo *  _Nonnull obj1, iTermProcessInfo *  _Nonnull obj2) {
        return [@(obj1.processID) compare:@(obj2.processID)];
    }];
}

- (void)addChildWithProcessID:(pid_t)pid {
    [_childProcessIDs addIndex:pid];
}

- (NSDate *)startTime {
    if (!_startTime) {
        _startTime = [_dataSource startTimeForProcess:self.processID];
    }
    return _startTime;
}

- (iTermProcessInfo *)deepestForegroundJob {
    if (!_haveDeepestForegroundJob) {
        NSInteger level = 0;
        NSMutableSet<NSNumber *> *visitedPids = [NSMutableSet set];
        BOOL cycle = NO;
        return [self deepestForegroundJob:&level visited:visitedPids cycle:&cycle depth:0];
    }
    return _deepestForegroundJob;
}

- (iTermProcessInfo *)deepestForegroundJob:(NSInteger *)levelInOut visited:(NSMutableSet *)visited cycle:(BOOL *)cycle depth:(NSInteger)depth {
    if (depth > 50 || [visited containsObject:@(self.processID)]) {
        _haveDeepestForegroundJob = YES;
        _deepestForegroundJob = nil;
        *cycle = YES;
        return nil;
    } else {
        [visited addObject:@(self.processID)];
    }

    NSInteger bestLevel = *levelInOut;
    iTermProcessInfo *bestProcessInfo = nil;

    if (_childProcessIDs.count == 0 && self.isForegroundJob) {
        _haveDeepestForegroundJob = YES;
        _deepestForegroundJob = self;
        return self;
    } else if (self.isForegroundJob) {
        bestProcessInfo = self;
    }

    for (iTermProcessInfo *child in self.children) {
        NSInteger level = *levelInOut + 1;
        iTermProcessInfo *candidate = [child deepestForegroundJob:&level visited:visited cycle:cycle depth:depth + 1];
        if (*cycle) {
            _haveDeepestForegroundJob = YES;
            _deepestForegroundJob = nil;
            return nil;
        }
        if (candidate) {
            if (level > bestLevel || bestProcessInfo == nil) {
                bestLevel = level;
                bestProcessInfo = candidate;
            }
        }
    }
    _haveDeepestForegroundJob = YES;
    _deepestForegroundJob = bestProcessInfo;
    *levelInOut = bestLevel;
    return bestProcessInfo;
}

- (NSArray<iTermProcessInfo *> *)flattenedTree {
    NSArray *flat = [self.children flatMapWithBlock:^id(iTermProcessInfo *child) {
        return child.flattenedTree;
    }];
    if (flat.count) {
        return [@[ self ] arrayByAddingObjectsFromArray:flat];
    } else {
        return @[ self ];
    }
}

- (NSArray<iTermProcessInfo *> *)descendantsSkippingLevels:(NSInteger)levels {
    if (levels < 0) {
        return [self flattenedTree];
    }
    return [self.children flatMapWithBlock:^id(iTermProcessInfo *child) {
        return [child descendantsSkippingLevels:levels - 1];
    }];
}

- (BOOL)enumerateTree:(void (^)(iTermProcessInfo *info, BOOL *stop))block {
    BOOL stop = NO;
    block(self, &stop);
    if (stop) {
        return YES;
    }
    for (iTermProcessInfo *child in self.children) {
        block(child, &stop);
        if (stop) {
            return YES;
        }
        if ([child enumerateTree:block]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)shouldInitialize {
    @synchronized ([iTermProcessInfoLock class]) {
        BOOL value = _initialized;
        _initialized = YES;
        return !value;
    }
}

- (void)doSlowLookup {
    if ([self shouldInitialize]) {
        BOOL fg = NO;
        self.nameValue = [_dataSource nameOfProcessWithPid:self->_processID isForeground:&fg];
        if (fg || [self.parent.name isEqualToString:@"login"] || !self.parent) {
            // Full command line with hacked command name.
            NSArray<NSString *> *argv = [_dataSource commandLineArgumentsForProcess:self->_processID execName:NULL];
            self.commandLineValue = [argv componentsJoinedByString:@" "];
            if (argv.firstObject.length) {
                self.argv0Value = argv[0];
            } else {
                self.argv0Value = nil;
            }
        }
        self.isForegroundJobValue = @(fg);
    }
}

- (NSString *)name {
    [self doSlowLookup];
    return self.nameValue;
}

- (NSString *)argv0 {
    [self doSlowLookup];
    return self.argv0Value;
}

- (NSString *)commandLine {
    [self doSlowLookup];
    return self.commandLineValue;
}

- (BOOL)isForegroundJob {
    if (_testValueForForegroundJob) {
        return [_testValueForForegroundJob boolValue];
    }
    [self doSlowLookup];
    return self.isForegroundJobValue.boolValue;
}

- (void)resolveAsynchronously {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.iterm2.pid-lookup", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_async(queue, ^{
        [self doSlowLookup];
    });
}

- (void)privateSetIsForegroundJob:(BOOL)value {
    _testValueForForegroundJob = @(value);
    [self shouldInitialize];
}

@end

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
