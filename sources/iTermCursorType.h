//
//  iTermCursorType.h
//  iTerm2
//
//  Created by George Nachman on 2/18/18.
//

typedef NS_ENUM(NSInteger, ITermCursorType) {
    CURSOR_UNDERLINE,
    CURSOR_VERTICAL,
    CURSOR_BOX,

    CURSOR_DEFAULT = -1  // Use the default cursor type for a profile. Internally used for DECSTR.
};

