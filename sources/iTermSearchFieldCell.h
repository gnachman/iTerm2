//
//  iTermSearchFieldCell.h
//  iTerm2SharedARC
//
//  Created by GEORGE NACHMAN on 7/4/18.
//

#import <Cocoa/Cocoa.h>

@interface iTermSearchFieldCell : NSSearchFieldCell
@property(nonatomic, assign) CGFloat fraction;
@property(nonatomic, readonly) BOOL needsAnimation;
@property(nonatomic, assign) CGFloat alphaMultiplier;

- (void)willAnimate;

@end
