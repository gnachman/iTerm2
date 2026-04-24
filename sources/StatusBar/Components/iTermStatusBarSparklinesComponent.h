//
//  iTermStatusBarSparklinesComponent.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/9/20.
//

#import "iTermStatusBarGraphicComponent.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermStatusBarTimeSeries: NSObject
@property (nonatomic, readonly) NSArray<NSNumber *> *values;
@property (nonatomic, readonly) NSInteger count;

- (instancetype)initWithValues:(NSArray<NSNumber *> *)values;
- (instancetype)init NS_UNAVAILABLE;

- (iTermStatusBarTimeSeries *)timeSeriesWithLastN:(NSInteger)n;
@end

@interface iTermStatusBarTimeSeriesRendition: NSObject
@property (nonatomic, readonly, strong) iTermStatusBarTimeSeries *timeSeries;
@property (nonatomic, readonly, strong) NSColor *color;
@property (nonatomic, readonly) NSNumber *maximumValue;

- (instancetype)initWithTimeSeries:(iTermStatusBarTimeSeries *)timeSeries
                             color:(NSColor *)color NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface iTermStatusBarSparklinesModel: NSObject
@property (nonatomic, readonly) NSDictionary<NSString *, iTermStatusBarTimeSeriesRendition *> *timeSeriesDict;
@property (nonatomic, readonly) NSInteger count;
@property (nonatomic, readonly, nullable) NSNumber *maximumValue;

- (instancetype)initWithDictionary:(NSDictionary<NSString *, iTermStatusBarTimeSeriesRendition *> *)timeSeriesDict NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (iTermStatusBarSparklinesModel *)modelKeepingLast:(NSInteger)n;
@end

@interface iTermStatusBarSparklinesComponent : iTermStatusBarGraphicComponent<iTermStatusBarTimeSeries *>

@property (nonatomic, readonly) iTermStatusBarSparklinesModel *sparklinesModel;
@property (nonatomic, readonly) NSColor *lineColor;
@property (nonatomic, readonly) double ceiling;
@property (nonatomic, readonly) NSInteger maximumNumberOfValues;
@property (nonatomic, readonly, nullable) NSString *leftText;
@property (nonatomic, readonly, nullable) NSString *rightText;
@property (nonatomic, readonly, nullable) NSImage *leftImage;
@property (nonatomic, readonly, nullable) NSImage *rightImage;
@property (nonatomic, readonly) CGSize leftSize;
@property (nonatomic, readonly) CGSize rightSize;
@property (nonatomic, readonly) NSDictionary *leftAttributes;
@property (nonatomic, readonly) NSDictionary *rightAttributes;

// Vertical offset for text to line it up with other stuff.
@property (nonatomic, readonly) CGFloat textOffset;

- (void)invalidate;
- (void)redrawAnimated:(BOOL)animated;
- (void)reset;
@end

NS_ASSUME_NONNULL_END
