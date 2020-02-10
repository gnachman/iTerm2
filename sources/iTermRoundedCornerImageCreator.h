//
//  iTermRoundedCornerImageCreator.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/9/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermRoundedCornerImageCreator : NSObject

@property (nonatomic, readonly) NSColor *color;
@property (nonatomic, readonly) NSSize size;
@property (nonatomic, readonly) CGFloat radius;
@property (nonatomic, readonly) CGFloat strokeThickness;

- (instancetype)initWithColor:(NSColor *)color
                         size:(NSSize)size
                       radius:(CGFloat)radius
              strokeThickness:(CGFloat)strokeThickness NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) NSImage *topLeft;
@property (nonatomic, readonly) NSImage *topRight;
@property (nonatomic, readonly) NSImage *bottomLeft;
@property (nonatomic, readonly) NSImage *bottomRight;

@end

NS_ASSUME_NONNULL_END
