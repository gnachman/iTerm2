//
//  LineBufferHelpers.h
//  iTerm
//
//  Created by George Nachman on 11/21/13.
//
//

#import <Foundation/Foundation.h>
#import "VT100GridTypes.h"

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
@property (nonatomic, readonly) int position;
@property (nonatomic, readonly) int length;

- (instancetype)initWithPosition:(int)position length:(int)length;

@end

@interface XYRange : NSObject {
@public
    int xStart;
    int yStart;
    int xEnd;
    int yEnd;
}

@property (nonatomic, readonly) int xStart;
@property (nonatomic, readonly) int yStart;
@property (nonatomic, readonly) int xEnd;
@property (nonatomic, readonly) int yEnd;

@property (nonatomic, readonly) VT100GridCoordRange coordRange;

@end

