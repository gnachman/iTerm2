//
//  iTermStatusBarAutoRainbowController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/2/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, iTermStatusBarAutoRainbowStyle) {
    iTermStatusBarAutoRainbowStyleDisabled,
    iTermStatusBarAutoRainbowStyleLight,
    iTermStatusBarAutoRainbowStyleDark,
    iTermStatusBarAutoRainbowStyleAutomatic
};

@class iTermStatusBarAutoRainbowController;

@protocol iTermStatusBarAutoRainbowControllerDelegate<NSObject>
- (void)autoRainbowControllerDidInvalidateColors:(iTermStatusBarAutoRainbowController *)controller;
@end

@interface iTermStatusBarAutoRainbowController : NSObject
@property (nonatomic, weak) id<iTermStatusBarAutoRainbowControllerDelegate> delegate;
@property (nonatomic) iTermStatusBarAutoRainbowStyle style;
@property (nonatomic) BOOL darkBackground;

- (instancetype)initWithStyle:(iTermStatusBarAutoRainbowStyle)style NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)enumerateColorsWithCount:(NSInteger)count block:(void (^ NS_NOESCAPE)(NSInteger i, NSColor *color))block;

@end

NS_ASSUME_NONNULL_END
