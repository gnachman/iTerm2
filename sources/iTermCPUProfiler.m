//
//  iTermCPUProfiler.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/24/18.
//

#import "iTermCPUProfiler.h"
#import "iTermBacktrace.h"
#import "iTermBacktraceFrame.h"
#include <pthread.h>

@class iTermStackNode;

@interface iTermStackEdge : NSObject
@property (nonatomic, readonly) NSInteger count;
@property (nonatomic, readonly) iTermStackNode *node;

- (instancetype)initWithNode:(iTermStackNode *)node NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)incrementCount;
@end

@implementation iTermStackEdge

- (instancetype)initWithNode:(iTermStackNode *)node {
    self = [super init];
    if (self) {
        _node = node;
        _count = 1;
    }
    return self;
}

- (void)incrementCount {
    _count++;
}

@end

@interface iTermStackNode : NSObject

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSInteger divisor;

- (iTermStackNode *)addFrame:(iTermBacktraceFrame *)frame
                     divisor:(NSInteger)divisor;

@end

@implementation iTermStackNode {
    NSMutableDictionary<NSString *, iTermStackEdge *> *_edges;
}

- (instancetype)initWithName:(NSString *)name divisor:(NSInteger)divisor {
    self = [super init];
    if (self) {
        _divisor = divisor;
        _name = name;
        _edges = [NSMutableDictionary dictionary];
    }
    return self;
}

- (iTermStackNode *)addFrame:(iTermBacktraceFrame *)frame divisor:(NSInteger)divisor {
    NSString *name = [frame.stringValue substringFromIndex:4];
    iTermStackEdge *edge = _edges[name];
    if (edge) {
        [edge incrementCount];
        return edge.node;
    }

    iTermStackNode *node = [[iTermStackNode alloc] initWithName:name divisor:_divisor];
    _edges[node.name] = [[iTermStackEdge alloc] initWithNode:node];
    return node;
}

- (NSString *)indentationForLevel:(NSInteger)level {
    NSArray<NSString *> *chars = @[ @"|", @":", @";", @"'", @"`", @"#" ];
    return [chars[level % chars.count] stringByAppendingString:@"   "];
}

- (void)appendToString:(NSMutableString *)output indentation:(NSString *)indentation {
    const NSInteger minimum = _divisor * 0.01;  // Only frames in at least 1% of samples are included.
    for (NSString *name in [self namesSortedByCount]) {
        iTermStackEdge *edge = _edges[name];
        if (edge.count < minimum) {
            continue;
        }
        [output appendFormat:@"%@[%0.1f%%] %@\r\n", indentation, 100.0 * (double)edge.count / (double)_divisor, name];
        if (edge.node->_edges.count) {
            [edge.node appendToString:output indentation:[indentation stringByAppendingString:[self indentationForLevel:indentation.length / 4]]];
        }
    }
}

- (NSArray<NSString *> *)namesSortedByCount {
    return [_edges.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString * _Nonnull name1, NSString * _Nonnull name2) {
        NSInteger count1 = self->_edges[name1].count;
        NSInteger count2 = self->_edges[name2].count;
        return [@(count2) compare:@(count1)];
    }];
}

@end

@interface iTermCPUProfile()
- (instancetype)initWithSnapshots:(NSArray<NSArray<iTermBacktraceFrame *> *> *)snapshots NS_DESIGNATED_INITIALIZER;
@end

@implementation iTermCPUProfile {
    NSInteger _numberOfSnapshots;
    iTermStackNode *_root;
}

- (instancetype)initWithSnapshots:(NSArray<NSArray<iTermBacktraceFrame *> *> *)snapshots {
    self = [super init];
    if (self) {
        _numberOfSnapshots = snapshots.count;
        _root = [[iTermStackNode alloc] initWithName:@"Root" divisor:_numberOfSnapshots];
        for (NSArray<iTermBacktraceFrame *> *snapshot in [snapshots copy]) {
            [self addSnapshot:snapshot];
        }
    }
    return self;
}

- (void)addSnapshot:(NSArray<iTermBacktraceFrame *> *)snapshot {
    iTermStackNode *node = _root;
    for (iTermBacktraceFrame *frame in [snapshot copy]) {
        node = [node addFrame:frame divisor:_numberOfSnapshots];
    }
}

- (NSString *)stringTree {
    NSMutableString *string = [NSMutableString string];
    [_root appendToString:string indentation:@""];
    return string;
}

@end

@implementation iTermCPUProfiler {
    pthread_t _mainThreadID;
    dispatch_queue_t _profilerQueue;
    dispatch_source_t _profilerTimer;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        dispatch_queue_attr_t queueAttributes = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0);
        _profilerQueue = dispatch_queue_create("com.iterm2.profiler", queueAttributes);
        _mainThreadID = pthread_self();
    }
    return self;
}

- (void)startProfilingForDuration:(NSTimeInterval)duration
                       completion:(nonnull void (^)(iTermCPUProfile * _Nonnull))completion {
    assert(!_profilerTimer);

    NSMutableArray<NSArray<iTermBacktraceFrame *> *> *snapshots = [NSMutableArray array];
    _profilerTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                            0,
                                            0,
                                            _profilerQueue);
    dispatch_source_set_timer(_profilerTimer,
                              DISPATCH_TIME_NOW,
                              0.001 * NSEC_PER_SEC,
                              0.0025 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(_profilerTimer, ^{
        NSArray<iTermBacktraceFrame *> *frames = GetBacktraceFrames(self->_mainThreadID);
        [snapshots addObject:frames];
    });
    dispatch_resume(_profilerTimer);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        dispatch_cancel(self->_profilerTimer);
        self->_profilerTimer = nil;
        completion([[iTermCPUProfile alloc] initWithSnapshots:snapshots]);
    });
}

@end
