#import "PTYSession.h"

// These methods are exposed via an AppleScript API and should not be removed.
@interface PTYSession (Scripting)

// Key-value coding compliance for AppleScript. It's generally better to go through the |colorMap|.
@property(nonatomic, retain) NSColor *backgroundColor;
@property(nonatomic, retain) NSColor *boldColor;
@property(nonatomic, retain) NSColor *cursorColor;
@property(nonatomic, retain) NSColor *cursorTextColor;
@property(nonatomic, retain) NSColor *foregroundColor;
@property(nonatomic, retain) NSColor *selectedTextColor;
@property(nonatomic, retain) NSColor *selectionColor;
@property(nonatomic, retain) NSColor *ansiBlackColor;
@property(nonatomic, retain) NSColor *ansiRedColor;
@property(nonatomic, retain) NSColor *ansiGreenColor;
@property(nonatomic, retain) NSColor *ansiYellowColor;
@property(nonatomic, retain) NSColor *ansiBlueColor;
@property(nonatomic, retain) NSColor *ansiMagentaColor;
@property(nonatomic, retain) NSColor *ansiCyanColor;
@property(nonatomic, retain) NSColor *ansiWhiteColor;
@property(nonatomic, retain) NSColor *ansiBrightBlackColor;
@property(nonatomic, retain) NSColor *ansiBrightRedColor;
@property(nonatomic, retain) NSColor *ansiBrightGreenColor;
@property(nonatomic, retain) NSColor *ansiBrightYellowColor;
@property(nonatomic, retain) NSColor *ansiBrightBlueColor;
@property(nonatomic, retain) NSColor *ansiBrightMagentaColor;
@property(nonatomic, retain) NSColor *ansiBrightCyanColor;
@property(nonatomic, retain) NSColor *ansiBrightWhiteColor;
@property(nonatomic, readonly) NSString *profileName;
@property(nonatomic, copy) NSString *colorPresetName;

@end
