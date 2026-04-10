#import <Foundation/Foundation.h>
#import "iTermMetalGlyphKey.h"
#import "ScreenChar.h"
#import "iTermTextRendererCommon.h"

NS_ASSUME_NONNULL_BEGIN

// Test helper that wraps computeUnderlineSpansFromAttributes: without requiring
// Swift to import the full Metal renderer transient state class hierarchy.
@interface iTermUnderlineSpanTestHelper : NSObject

@property (nonatomic) iTermMetalUnderlineDescriptor asciiUnderlineDescriptor;
@property (nonatomic) iTermMetalUnderlineDescriptor nonAsciiUnderlineDescriptor;

- (void)computeSpansFromAttributes:(const iTermMetalGlyphAttributes *)attributes
                             count:(int)count
                               row:(int)row
                 markedRangeOnLine:(NSRange)markedRangeOnLine
                              line:(const screen_char_t *)line
                        lineLength:(int)lineLength
                        inverseLUT:(const int * _Nullable)inverseLUT
                    inverseLUTLen:(int)inverseLUTLen
                    underlineSpans:(NSMutableData *)underlineSpans
                strikethroughSpans:(NSMutableData *)strikethroughSpans;

@end

NS_ASSUME_NONNULL_END
