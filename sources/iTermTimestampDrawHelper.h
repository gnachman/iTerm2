//
//  iTermTimestampDrawHelper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/31/17.
//

#import <Cocoa/Cocoa.h>

// Create a new instance for each frame and call -drawTimestampWithDate:line: repeatedly for each
// row.
@interface iTermTimestampDrawHelper : NSObject

// Gets updated after each -drawTimestampWithDate:line:.
@property (nonatomic, readonly) CGFloat maximumWidth;

- (instancetype)initWithBackgroundColor:(NSColor *)backgroundColor
                              textColor:(NSColor *)textColor
                                    now:(NSTimeInterval)now
                     useTestingTimezone:(BOOL)useTestingTimezone
                                inFrame:(NSRect)frame
                              rowHeight:(CGFloat)rowHeight
                                context:(NSGraphicsContext *)context
                                 retina:(BOOL)isRetina;

- (void)setDate:(NSDate *)timestamp forLine:(int)line;
- (void)draw;

@end
