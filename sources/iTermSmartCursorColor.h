//
//  iTermSmartCursorColor.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/28/17.
//

#import <Foundation/Foundation.h>

#import "ScreenChar.h"

typedef struct {
    screen_char_t chars[3][3];
    BOOL valid[3][3];
} iTermCursorNeighbors;

@protocol iTermSmartCursorColorDelegate<NSObject>

- (iTermCursorNeighbors)cursorNeighbors;

- (NSColor *)cursorColorForCharacter:(screen_char_t)screenChar
                      wantBackground:(BOOL)wantBackgroundColor
                               muted:(BOOL)muted;

- (NSColor *)cursorColorByDimmingSmartColor:(NSColor *)color;

- (NSColor *)cursorWhiteColor;
- (NSColor *)cursorBlackColor;

@end

@interface iTermSmartCursorColor : NSObject
@property (nonatomic, weak) id<iTermSmartCursorColorDelegate> delegate;

+ (iTermCursorNeighbors)neighborsForCursorAtCoord:(VT100GridCoord)cursorCoord
                                         gridSize:(VT100GridSize)gridSize
                                       lineSource:(const screen_char_t *(^)(int))lineSource;

- (NSColor *)backgroundColorForCharacter:(screen_char_t)screenChar;

- (NSColor *)textColorForCharacter:(screen_char_t)screenChar
                  regularTextColor:(NSColor *)proposedForeground
              smartBackgroundColor:(NSColor *)backgroundColor;

@end
