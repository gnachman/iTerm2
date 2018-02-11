//
//  iTermMouseCursor.h
//  iTerm
//
//  Created by George Nachman on 5/11/14.
//
//

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, iTermMouseCursorType) {
    iTermMouseCursorTypeIBeam,
    iTermMouseCursorTypeIBeamWithCircle,
    iTermMouseCursorTypeNorthwestSoutheastArrow,
    iTermMouseCursorTypeArrow
};

@interface iTermMouseCursor : NSCursor

+ (instancetype)mouseCursorOfType:(iTermMouseCursorType)cursorType;

@end
