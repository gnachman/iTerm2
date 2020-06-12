//
//  iTermTmuxBufferSizeMonitor.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/6/20.
//

#import "iTermTmuxBufferSizeMonitor.h"

#import "DebugLogging.h"
#import "iTermTmuxOptionMonitor.h"
#import "NSArray+iTerm.h"
#import "TmuxController.h"

@interface iTermTmuxBufferSizeDataPoint : NSObject

@property (nonatomic, readonly) NSTimeInterval t;
@property (nonatomic, readonly) NSTimeInterval age;

+ (NSTimeInterval)now;

- (instancetype)initWithTime:(NSTimeInterval)t age:(NSTimeInterval)age NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@implementation iTermTmuxBufferSizeDataPoint

static double TimespecToSeconds(struct timespec* ts) {
    return (double)ts->tv_sec + (double)ts->tv_nsec / 1000000000.0;
}

+ (NSTimeInterval)now {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return TimespecToSeconds(&ts);
}

- (instancetype)initWithTime:(NSTimeInterval)t age:(NSTimeInterval)age {
    self = [super init];
    if (self) {
        _t = t;
        _age = age;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"(t=%@, age=%@)", @(_t), @(_age)];
}

@end

@interface iTermTimeSeries : NSObject
@property (nonatomic, readonly) NSInteger count;
@property (nonatomic, readonly) NSInteger capacity;
@property (nonatomic) double lastTTL;

- (instancetype)initWithCapacity:(NSInteger)capacity NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)addDataPoint:(iTermTmuxBufferSizeDataPoint *)dataPoint;
- (BOOL)getLinearRegressionSlope:(double *)slope offset:(double *)offset;
- (NSTimeInterval)estimatedTimeForAge:(NSTimeInterval)target;
- (void)removeLastDataPoint;

@end

@implementation iTermTimeSeries {
    NSMutableArray<iTermTmuxBufferSizeDataPoint *> *_data;
}

- (instancetype)initWithCapacity:(NSInteger)capacity {
    self = [super init];
    if (self) {
        _data = [NSMutableArray arrayWithCapacity:capacity];
        _capacity = capacity;
    }
    return self;
}

- (NSString *)description {
    NSArray<NSString *> *descriptions =
    [_data mapWithBlock:^NSString *(iTermTmuxBufferSizeDataPoint *point) {
        return point.description;
    }];
    NSString *data = [descriptions componentsJoinedByString:@", "];
    return [NSString stringWithFormat:@"<%@: %p %@>", NSStringFromClass(self.class), self,
            data];
}

- (void)addDataPoint:(iTermTmuxBufferSizeDataPoint *)dataPoint {
    [_data addObject:dataPoint];
    while (_data.count > self.capacity) {
        [_data removeObjectAtIndex:0];
    }
}

- (void)removeLastDataPoint {
    [_data removeLastObject];
}

- (NSTimeInterval)estimatedTimeForAge:(NSTimeInterval)target {
    double slope = 0;
    double offset = 0;
    const BOOL ok = [self getLinearRegressionSlope:&slope offset:&offset];
    if (!ok) {
        return INFINITY;
    }
    return (target - offset) / slope;
}

- (NSInteger)count {
    return _data.count;
}

- (BOOL)getLinearRegressionSlope:(double *)slope offset:(double *)offset {
    if (self.count < 2) {
        return NO;
    }
    double sumX = 0;
    double sumX2 = 0;
    double sumY = 0;
    double sumXY = 0;
    for (iTermTmuxBufferSizeDataPoint *point in _data) {
        sumX += point.t;
        sumX2 += point.t * point.t;
        sumY += point.age;
        sumXY += point.t * point.age;
    }
    const double n = self.count;
    const double b = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    *slope = b;
    *offset = (sumY - b * sumX) / n;
    return YES;
}


@end
@implementation iTermTmuxBufferSizeMonitor {
    NSMutableDictionary<NSNumber *, iTermTimeSeries *> *_series;
    NSTimeInterval _lastSampleTime;
}

- (instancetype)initWithController:(TmuxController *)controller
                          pauseAge:(NSTimeInterval)pauseAge {
    self = [super init];
    if (self) {
        _controller = controller;
        _pauseAge = pauseAge;
        _series = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)setCurrentLatency:(NSTimeInterval)age forPane:(int)wp {
    const NSTimeInterval now = [iTermTmuxBufferSizeDataPoint now];
    iTermTimeSeries *series = _series[@(wp)];
    if (!series) {
        series = [[iTermTimeSeries alloc] initWithCapacity:4];
        series.lastTTL = INFINITY;
        _series[@(wp)] = series;
    }
    if (now - _lastSampleTime < 1) {
        return;
    } else {
        _lastSampleTime = now;
    }
    iTermTmuxBufferSizeDataPoint *dataPoint =
    [[iTermTmuxBufferSizeDataPoint alloc] initWithTime:now
                                                   age:age];
    [series addDataPoint:dataPoint];

    [_series enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull wp, iTermTimeSeries * _Nonnull series, BOOL * _Nonnull stop) {
        if (series.count < 4) {
            // Not enough info to make a decision
            return;
        }
        const NSTimeInterval time = [series estimatedTimeForAge:_pauseAge];
        const NSTimeInterval ttl = time - now;
        DLog(@"%@ -> time=%@ ttl=%@", series, @(time), @(ttl));
        [self maybeWarnPane:wp.intValue ttl:ttl lastTTL:series.lastTTL];
        series.lastTTL = ttl;
    }];
}

- (void)resetPane:(int)wp {
    [_series removeObjectForKey:@(wp)];
}

- (void)maybeWarnPane:(int)wp ttl:(NSTimeInterval)ttl lastTTL:(NSTimeInterval)lastTTL {
    if (![self shouldWarnPaneWithTTL:ttl lastTTL:lastTTL]) {
        return;
    }
    [self.delegate tmuxBufferSizeMonitor:self updatePane:wp ttl:ttl];
}

- (BOOL)shouldWarnPaneWithTTL:(NSTimeInterval)ttl lastTTL:(NSTimeInterval)lastTTL {
    const BOOL inRedZone = (ttl < _pauseAge / 2);
    if (inRedZone) {
        return YES;
    }
    const BOOL wasInRedZone = (lastTTL < _pauseAge / 2);
    if (wasInRedZone) {
        return YES;
    }
    return NO;
}

@end
