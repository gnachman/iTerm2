//
//  iTermDoubleWidthCharacterCache.h
//  iTerm2
//
//  Created by George Nachman on 11/26/24.
//

#import <Foundation/Foundation.h>

#import "ScreenChar.h"

// When wrapping a raw line to a given width, double-width characters' positions may need to be
// adjusted by moving them to the next line if they would intrude into the margin.
// In the example below, a double-width character is written as a capital letter followed by a
// dash to indicate the two cells it occupies. For this raw line:
//
// abcdE-f
//
// When wrapped to five columns, you cannot do this:
//
// 12345
// abcdE  ❌
// -f
//
// Since the E and the - cannot be separated (they are a single logical unit taking two cells of
// visual space). You also cannot do:
//
// 12345
// abcdE-  ❌
// f
//
// Because that would make the double-width character intrude into the margin. The only remaining
// option is to move it to the next line and leave the first line short by one cell:
//
// 12345
// abcd   ✅
// E-f
//
// To assist, this class remembers which lines are affected by recording the lines that receive
// the moved double-width character. In the example above, the index set would be {1} since a
// DWC moved from line 0 to line 1.
@interface iTermDoubleWidthCharacterCache: NSObject

// Which lines, when wrapped at the given width, receive an adjust double-width character.
@property (nonatomic, readonly) NSIndexSet *indexSet;
@property (nonatomic, readonly) int width;
@property (nonatomic, readonly) int length;

+ (NSIndexSet *)indexSetForCharacters:(const screen_char_t *)characters
                               length:(int)length
                                width:(int)width;

- (instancetype)initWithCharacters:(const screen_char_t *)characters
                            length:(int)length
                             width:(int)width;

- (BOOL)validForWidth:(int)width length:(int)length;

// Gives the offset into the raw line of the `n`th wrapped line.
// totalLines is provided for debugging purposes and returns the last line considered.
- (int)offsetForWrappedLine:(int)n totalLines:(out int *)linesPtr;

- (void)sanityCheckWithCharacters:(const screen_char_t *)characters length:(int)length;

@end

