//
//  LineBufferHelpers.h
//  iTerm
//
//  Created by George Nachman on 11/21/13.
//
//

#import <Foundation/Foundation.h>

// When receiving search results, you'll get an array of this class. Positions
// can be converted to x,y coordinates with -convertPosition:withWidth:toX:toY.
// length gives the number of screen_char_t elements matching the search (which
// may differ from the number of code points in the search string because of
// the vagueries of unicode, or more obviously, for regex searches).
@interface ResultRange : NSObject {
@public
    int position;
    int length;
}
@end

@interface XYRange : NSObject {
@public
    int xStart;
    int yStart;
    int xEnd;
    int yEnd;
}
@end

