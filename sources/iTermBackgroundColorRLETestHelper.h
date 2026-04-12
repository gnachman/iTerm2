#import <Foundation/Foundation.h>
#import "ScreenChar.h"
#import "iTermTextRendererCommon.h"

NS_ASSUME_NONNULL_BEGIN

// Simplified RLE result for testing.
typedef struct {
    int origin;
    int count;
    int logicalOrigin;
} iTermTestBackgroundRLE;

// Test helper that wraps iTermGetMetalBackgroundColors without requiring
// Swift to import the full Metal per-frame state class hierarchy.
@interface iTermBackgroundColorRLETestHelper : NSObject

- (int)buildRLEsForLine:(const screen_char_t *)line
                   width:(int)width
                 results:(iTermTestBackgroundRLE *)results
                 maxResults:(int)maxResults
                 bidiLUT:(const int * _Nullable)bidiLUT
              bidiLUTLen:(int)bidiLUTLen
           lineAttribute:(iTermLineAttribute)lineAttribute;

@end

NS_ASSUME_NONNULL_END
