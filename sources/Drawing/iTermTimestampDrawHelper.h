//
//  iTermTimestampDrawHelper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/31/17.
//

#import <Cocoa/Cocoa.h>

@class PTYFontInfo;

extern const CGFloat iTermTimestampGradientWidth;

// Create a new instance for each frame and call -drawTimestampWithDate:line: repeatedly for each
// row.
@interface iTermTimestampDrawHelper : NSObject

// Gets updated after each -drawTimestampWithDate:line:. Does not include gradient width.
@property (nonatomic, readonly) CGFloat maximumWidth;

// Includes gradient and right margin
@property (nonatomic, readonly) CGFloat suggestedWidth;

// The font to use
@property (nonatomic, readonly) NSFont *font;

// Time in seconds-since-reference-date, or 0 to use absolute times.
@property (nonatomic) NSTimeInterval timestampBaseline;

- (instancetype)initWithBackgroundColor:(NSColor *)backgroundColor
                              textColor:(NSColor *)textColor
                                    now:(NSTimeInterval)now
                     useTestingTimezone:(BOOL)useTestingTimezone
                              rowHeight:(CGFloat)rowHeight
              rowHeightWithoutSpacing:(CGFloat)rowHeightWithoutSpacing
                                 retina:(BOOL)isRetina
                               fontInfo:(PTYFontInfo *)fontInfo
                               obscured:(CGFloat)obscured;

- (void)setDate:(NSDate *)timestamp forLine:(int)line;

// Frame is a possibly very wide container that this is right-aligned in.
- (void)drawInContext:(NSGraphicsContext *)context
                frame:(NSRect)frame
        virtualOffset:(CGFloat)virtualOffset;

// Frame includes gradient
- (void)drawRow:(int)index
      inContext:(NSGraphicsContext *)context
          frame:(NSRect)frame
  virtualOffset:(CGFloat)virtualOffset;
- (BOOL)rowIsRepeat:(int)index;
- (NSString *)stringForRow:(int)index;

@end
