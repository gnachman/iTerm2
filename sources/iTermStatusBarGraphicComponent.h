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

- (void)drawRect:(NSRect)rect;

@end

@interface iTermStatusBarSparklinesComponent : iTermStatusBarGraphicComponent

@property (nonatomic, readonly) NSArray<NSNumber *> *values;
@property (nonatomic, readonly) NSColor *lineColor;

- (void)invalidate;

@end
