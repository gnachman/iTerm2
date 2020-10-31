//
//  iTermColorSuggester.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/30/20.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermColorSuggester : NSObject
@property (nonatomic, readonly) NSColor *suggestedTextColor;
@property (nonatomic, readonly) NSColor *suggestedBackgroundColor;

- (instancetype)initWithDefaultTextColor:(NSColor *)defaultTextColor
                  defaultBackgroundColor:(NSColor *)defaultBackgroundColor
                       minimumDifference:(CGFloat)minimumDifference  // In [0,1)
                                    seed:(long)seed NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
