//
//  iTermTimestampDrawHelper.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/31/17.
//

#import "iTermTimestampDrawHelper.h"

#import "iTermAdvancedSettingsModel.h"
#import "NSColor+iTerm.h"
#import "RegexKitLite.h"

@interface iTermTimestampRow : NSObject
@property (nonatomic, strong) NSString *string;
@property (nonatomic) int line;
@end

@implementation iTermTimestampRow
@end

@implementation iTermTimestampDrawHelper {
    NSColor *_bgColor;
    NSColor *_fgColor;
    NSTimeInterval _now;
    BOOL _useTestingTimezone;
    NSRect _frame;
    CGFloat _rowHeight;
    NSGraphicsContext *_context;
    BOOL _isRetina;

    NSString *_previousString;
    NSMutableArray<iTermTimestampRow *> *_rows;
}

- (instancetype)initWithBackgroundColor:(NSColor *)backgroundColor
                              textColor:(NSColor *)textColor
                                    now:(NSTimeInterval)now
                     useTestingTimezone:(BOOL)useTestingTimezone
                                inFrame:(NSRect)frame
                              rowHeight:(CGFloat)rowHeight
                                context:(NSGraphicsContext *)context
                                 retina:(BOOL)isRetina {
    self = [super init];
    if (self) {
        _bgColor = backgroundColor;
        _fgColor = textColor;
        _now = now;
        _useTestingTimezone = useTestingTimezone;
        _frame = frame;
        _rowHeight = rowHeight;
        _context = context;
        _isRetina = isRetina;
        _rows = [NSMutableArray array];
    }
    return self;
}

#pragma mark - APIs

- (void)setDate:(NSDate *)timestamp forLine:(int)line {
    NSString *string = [self stringForTimestamp:timestamp
                                            now:_now
                             useTestingTimezone:_useTestingTimezone];
    NSRect textFrame = [self frameForString:string line:line];
    _maximumWidth = MAX(_maximumWidth, NSWidth(textFrame));

    iTermTimestampRow *row = [[iTermTimestampRow alloc] init];
    row.string = string;
    row.line = line;
    [_rows addObject:row];
}

- (void)draw {
    [_rows enumerateObjectsUsingBlock:^(iTermTimestampRow * _Nonnull row, NSUInteger idx, BOOL * _Nonnull stop) {
        NSRect frame = [self frameForStringGivenWidth:_maximumWidth line:row.line];
        [self drawBackgroundInFrame:[self backgroundFrameForTextFrame:frame]
                            bgColor:_bgColor
                            context:_context];
        [self drawString:row.string frame:frame];
    }];
}

#pragma mark - Draw Methods

- (void)drawBackgroundInFrame:(NSRect)frame
                      bgColor:(NSColor *)bgColor
                      context:(NSGraphicsContext *)context {
    static const CGFloat gradientWidth = 20;
    const CGFloat alpha = 0.9;
    NSGradient *gradient =
    [[NSGradient alloc] initWithStartingColor:[bgColor colorWithAlphaComponent:0]
                                  endingColor:[bgColor colorWithAlphaComponent:alpha]];
    [context setCompositingOperation:NSCompositeSourceOver];
    NSRect gradientFrame = frame;
    gradientFrame.size.width = gradientWidth;
    [gradient drawInRect:gradientFrame
                   angle:0];

    NSRect solidFrame = frame;
    solidFrame.origin.x += gradientWidth;
    solidFrame.size.width -= gradientWidth;
    [[bgColor colorWithAlphaComponent:alpha] set];
    [context setCompositingOperation:NSCompositeSourceOver];
    NSRectFillUsingOperation(solidFrame, NSCompositeSourceOver);
}

- (void)drawString:(NSString *)s frame:(NSRect)frame {
    NSDictionary *attributes = [self attributesForTextColor:_fgColor
                                                     shadow:[self shadowForTextColor:_fgColor]
                                                     retina:_isRetina];
    const CGFloat offset = (_rowHeight - NSHeight(frame)) / 2;
    const BOOL repeat = [s isEqualToString:_previousString];
    if (s.length && repeat) {
        [_fgColor set];
        const CGFloat center = NSMinX(frame) + 10;
        NSRectFill(NSMakeRect(center - 1, NSMinY(frame), 1, _rowHeight));
        NSRectFill(NSMakeRect(center + 1, NSMinY(frame), 1, _rowHeight));
    } else {
        [s drawAtPoint:NSMakePoint(NSMinX(frame), NSMinY(frame) + offset) withAttributes:attributes];
    }
    _previousString = s;
}

#pragma mark - Pixel Arithmetic

- (NSRect)backgroundFrameForTextFrame:(NSRect)frame {
    return NSMakeRect(NSMinX(frame) - 20, NSMinY(frame), NSWidth(frame) + 20, NSHeight(frame));
}

- (NSRect)frameForString:(NSString *)s line:(int)line {
    NSString *widest = [s stringByReplacingOccurrencesOfRegex:@"[\\d\\p{Alphabetic}]" withString:@"M"];
    NSSize size = [widest sizeWithAttributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:[iTermAdvancedSettingsModel pointSizeOfTimeStamp]] }];

    return [self frameForStringGivenWidth:size.width line:line];
}

- (NSRect)frameForStringGivenWidth:(CGFloat)width line:(int)line {
    const int w = width + [iTermAdvancedSettingsModel terminalMargin];
    const int x = MAX(0, _frame.size.width - w);
    const CGFloat y = line * _rowHeight;

    return NSMakeRect(x, y, w, _rowHeight);
}

#pragma mark - String Diddling

- (NSDateFormatter *)dateFormatterWithTimeDelta:(NSTimeInterval)timeDelta
                             useTestingTimezone:(BOOL)useTestingTimezone {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    const NSTimeInterval day = -86400;
    if (timeDelta < day * 180) {
        // More than 180 days ago: include year
        // I tried using 365 but it was pretty confusing to see tomorrow's date.
        [fmt setDateFormat:[NSDateFormatter dateFormatFromTemplate:@"yyyyMMMd jj:mm:ss"
                                                           options:0
                                                            locale:[NSLocale currentLocale]]];
    } else if (timeDelta < day * 6) {
        // 6 days to 180 days ago: include date without year
        [fmt setDateFormat:[NSDateFormatter dateFormatFromTemplate:@"MMMd jj:mm:ss"
                                                           options:0
                                                            locale:[NSLocale currentLocale]]];
    } else if (timeDelta < day) {
        // 1 day to 6 days ago: include day of week
        [fmt setDateFormat:[NSDateFormatter dateFormatFromTemplate:@"EEE jj:mm:ss"
                                                           options:0
                                                            locale:[NSLocale currentLocale]]];
    } else {
        // In last 24 hours, just show time
        [fmt setDateFormat:[NSDateFormatter dateFormatFromTemplate:@"jj:mm:ss"
                                                           options:0
                                                            locale:[NSLocale currentLocale]]];
    }
    if (useTestingTimezone) {
        fmt.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    }
    return fmt;
}

- (NSString *)stringForTimestamp:(NSDate *)timestamp
                             now:(NSTimeInterval)now
              useTestingTimezone:(BOOL)useTestingTimezone {
    const NSTimeInterval timeDelta = timestamp.timeIntervalSinceReferenceDate - now;
    NSDateFormatter *fmt = [self dateFormatterWithTimeDelta:timeDelta
                                         useTestingTimezone:useTestingTimezone];
    NSString *theTimestamp = [fmt stringFromDate:timestamp];
    if (!timestamp || ![timestamp timeIntervalSinceReferenceDate]) {
        theTimestamp = @"";
    }
    return theTimestamp;
}

- (NSDictionary *)attributesForTextColor:(NSColor *)fgColor shadow:(NSShadow *)shadow retina:(BOOL)retina {
    NSDictionary *attributes;
    if (retina) {
        attributes = @{ NSFontAttributeName: [NSFont userFixedPitchFontOfSize:[iTermAdvancedSettingsModel pointSizeOfTimeStamp]],
                        NSForegroundColorAttributeName: fgColor,
                        NSShadowAttributeName: shadow };
    } else {
        NSFont *font = [NSFont userFixedPitchFontOfSize:[iTermAdvancedSettingsModel pointSizeOfTimeStamp]];
        font = [[NSFontManager sharedFontManager] fontWithFamily:font.familyName
                                                          traits:NSBoldFontMask
                                                          weight:0
                                                            size:font.pointSize];
        attributes = @{ NSFontAttributeName: font,
                        NSForegroundColorAttributeName: fgColor };
    }

    return attributes;
}

#pragma mark - Colors

- (NSColor *)shadowColorForTextColor:(NSColor *)fgColor {
    if ([fgColor isDark]) {
        return [NSColor whiteColor];
    } else {
        return [NSColor blackColor];
    }
}

- (NSShadow *)shadowForTextColor:(NSColor *)fgColor {
    NSColor *shadowColor = [self shadowColorForTextColor:fgColor];
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = shadowColor;
    shadow.shadowBlurRadius = 0.2f;
    shadow.shadowOffset = CGSizeMake(0.5, -0.5);
    return shadow;
}

@end
