#import <Cocoa/Cocoa.h>
#import "VT100GridTypes.h"

typedef enum {
    // X11 button number
    MOUSE_BUTTON_LEFT = 0,       // left button
    MOUSE_BUTTON_MIDDLE = 1,     // middle button
    MOUSE_BUTTON_RIGHT = 2,      // right button
    MOUSE_BUTTON_NONE = 3,       // no button pressed - for 1000/1005/1015 mode
    MOUSE_BUTTON_SCROLLDOWN = 4, // scroll down
    MOUSE_BUTTON_SCROLLUP = 5    // scroll up
} MouseButtonNumber;

typedef NS_ENUM(NSInteger, MouseFormat) {
    MOUSE_FORMAT_XTERM = 0,       // Regular 1000 mode (limited to 223 rows/cols)
    MOUSE_FORMAT_XTERM_EXT = 1,   // UTF-8 1005 mode (does not pass through luit unchanged)
    MOUSE_FORMAT_URXVT = 2,       // rxvt's 1015 mode (outputs csi codes, that if echoed to the term, mess up the display)
    MOUSE_FORMAT_SGR = 3          // SGR 1006 mode (preferred)
};

// This class produces data to send for special keys (arrow keys, function keys, etc.)
// It has a small amount of state that is copied from VT100Terminal. This object is 1:1 with
// VT100Terminal.
@interface VT100Output : NSObject

@property(nonatomic, assign) BOOL keypadMode;
@property(nonatomic, assign) MouseFormat mouseFormat;
@property(nonatomic, assign) BOOL cursorMode;
@property(nonatomic, assign) BOOL optionIsMetaForSpecialKeys;

- (NSData *)keyArrowUp:(unsigned int)modflag;
- (NSData *)keyArrowDown:(unsigned int)modflag;
- (NSData *)keyArrowLeft:(unsigned int)modflag;
- (NSData *)keyArrowRight:(unsigned int)modflag;
- (NSData *)keyHome:(unsigned int)modflag screenlikeTerminal:(BOOL)screenlike;
- (NSData *)keyEnd:(unsigned int)modflag screenlikeTerminal:(BOOL)screenlike;
- (NSData *)keyInsert;
- (NSData *)keyDelete;
- (NSData *)keyBackspace;
- (NSData *)keyPageUp:(unsigned int)modflag;
- (NSData *)keyPageDown:(unsigned int)modflag;
- (NSData *)keyFunction:(int)no;
- (NSData *)keypadData: (unichar) unicode keystr: (NSString *) keystr;

- (NSData *)mousePress:(int)button withModifiers:(unsigned int)modflag at:(VT100GridCoord)coord;
- (NSData *)mouseRelease:(int)button withModifiers:(unsigned int)modflag at:(VT100GridCoord)coord;
- (NSData *)mouseMotion:(int)button withModifiers:(unsigned int)modflag at:(VT100GridCoord)coord;

- (NSData *)reportActivePositionWithX:(int)x Y:(int)y withQuestion:(BOOL)q;
- (NSData *)reportStatus;
- (NSData *)reportDeviceAttribute;
- (NSData *)reportSecondaryDeviceAttribute;
- (NSData *)reportColor:(NSColor *)color atIndex:(int)index;
- (NSData *)reportChecksum:(int)checksum withIdentifier:(int)identifier;
- (NSData *)reportFocusGained:(BOOL)gained;
- (NSData *)reportiTerm2Version;

- (void)setTermTypeIsValid:(BOOL)termTypeIsValid;

@end
