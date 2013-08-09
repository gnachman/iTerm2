#import <Cocoa/Cocoa.h>

// Represents a search result when searching the screen and scrollback history
// contents.
@interface SearchResult : NSObject
{
@public
    // TODO(georgen): Use properties.
    int startX, endX;
    long long absStartY, absEndY;
}

@end


