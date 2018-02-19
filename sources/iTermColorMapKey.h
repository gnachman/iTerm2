//
//  iTermColorMapKey.h
//  iTerm2
//
//  Created by George Nachman on 2/19/18.
//

typedef enum {
    kColorMapForeground = 0,
    kColorMapBackground = 1,
    kColorMapBold = 2,
    kColorMapSelection = 3,
    kColorMapSelectedText = 4,
    kColorMapCursor = 5,
    kColorMapCursorText = 6,
    kColorMapInvalid = 7,
    kColorMapLink = 8,
    kColorMapUnderline = 9,
    // This value plus 0...255 are accepted.
    kColorMap8bitBase = 10,
    // This value plus 0...2^24-1 are accepted as read-only keys. These must be the highest-valued keys.
    kColorMap24bitBase = kColorMap8bitBase + 256,

    kColorMapAnsiBlack = kColorMap8bitBase + 0,
    kColorMapAnsiRed = kColorMap8bitBase + 1,
    kColorMapAnsiGreen = kColorMap8bitBase + 2,
    kColorMapAnsiYellow = kColorMap8bitBase + 3,
    kColorMapAnsiBlue = kColorMap8bitBase + 4,
    kColorMapAnsiMagenta = kColorMap8bitBase + 5,
    kColorMapAnsiCyan = kColorMap8bitBase + 6,
    kColorMapAnsiWhite = kColorMap8bitBase + 7,
    kColorMapAnsiBrightModifier = 8,
} iTermColorMapKey;


