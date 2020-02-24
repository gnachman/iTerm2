//
//  iTermBackgroundColorView.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/24/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

NS_CLASS_AVAILABLE_MAC(10_14)
@interface iTermBackgroundColorView: NSView
@property (nonatomic, strong) NSColor *backgroundColor;
@property (nonatomic) CGFloat blend;
@property (nonatomic) CGFloat transparency;

- (void)setAlphaValue:(CGFloat)alphaValue NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
