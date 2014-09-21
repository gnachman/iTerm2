//
//  iTermMouseCursor.h
//  iTerm
//
//  Created by George Nachman on 5/11/14.
//
//

#import <Cocoa/Cocoa.h>

typedef enum {
    iTermMouseCursorTypeIBeam,
    iTermMouseCursorTypeIBeamWithCircle,
    iTermMouseCursorTypeNorthwestSoutheastArrow,
    iTermMouseCursorTypeArrow
} iTermMouseCursorType;

@interface iTermMouseCursor : NSCursor

+ (instancetype)mouseCursorOfType:(iTermMouseCursorType)cursorType;

@end