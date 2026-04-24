//
//  iTermStatusBarGraphicComponent.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/20/18.
//

#import "iTermStatusBarBaseComponent.h"

@interface iTermStatusBarImageComponentView : NSView
@property (nonatomic, strong) NSView *contentView;
@property (nonatomic, strong) NSColor *backgroundColor;

- (instancetype)initWithCoder:(NSCoder *)decoder NS_UNAVAILABLE;
@end

// T is the type of the model.
@interface iTermStatusBarGraphicComponent<T> : iTermStatusBarBaseComponent

@property (nonatomic, readonly) iTermStatusBarImageComponentView *view;
@property (nonatomic, readonly) T model;
@property (nonatomic, strong) T preferredModel;
@property (nonatomic, readonly) NSColor *textColor;
@property (nonatomic, readonly) BOOL shouldHaveTextColorKnob;

- (void)redraw;
- (void)updateViewIfNeededAnimated:(BOOL)animated;

#pragma mark - Overrides

- (T)modelForWidth:(CGFloat)maximumWidth width:(out CGFloat *)preferredWidth;

@end

