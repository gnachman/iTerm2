//
//  iTermStatusBarGraphicComponent.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/20/18.
//

#import "iTermStatusBarBaseComponent.h"

@interface iTermStatusBarImageComponentView : NSView
@property (nonatomic, readonly) NSImageView *imageView;
@property (nonatomic, strong) NSColor *backgroundColor;

- (instancetype)initWithCoder:(NSCoder *)decoder NS_UNAVAILABLE;
@end

@interface iTermStatusBarGraphicComponent : iTermStatusBarBaseComponent

@property (nonatomic, readonly) iTermStatusBarImageComponentView *view;
@property (nonatomic, readonly) id model;
@property (nonatomic, strong) id preferredModel;
@property (nonatomic, readonly) NSColor *textColor;
@property (nonatomic, readonly) BOOL shouldHaveTextColorKnob;

- (void)drawRect:(NSRect)rect;

@end

@interface iTermStatusBarSparklinesComponent : iTermStatusBarGraphicComponent

@property (nonatomic, readonly) NSArray *values;
@property (nonatomic, readonly) NSColor *lineColor;
@property (nonatomic, readonly) NSInteger numberOfTimeSeries;
@property (nonatomic, readonly) double ceiling;
@property (nonatomic, readonly) NSInteger maximumNumberOfValues;

- (void)invalidate;
- (void)drawBezierPath:(NSBezierPath *)bezierPath
         forTimeSeries:(NSInteger)timeSeriesIndex;

@end
