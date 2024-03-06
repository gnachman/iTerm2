#import <Cocoa/Cocoa.h>
#import "VT100GridTypes.h"

typedef enum {
    MOUSE_BUTTON_UNKNOWN = -1,   // unknown button
    // X11 button number
    MOUSE_BUTTON_LEFT = 0,       // left button
    MOUSE_BUTTON_MIDDLE = 1,     // middle button
    MOUSE_BUTTON_RIGHT = 2,      // right button
    MOUSE_BUTTON_NONE = 3,       // no button pressed - for 1000/1005/1015 mode
    MOUSE_BUTTON_SCROLLDOWN = 4, // scroll down
    MOUSE_BUTTON_SCROLLUP = 5,   // scroll up
    MOUSE_BUTTON_SCROLLLEFT = 6, // scroll left
    MOUSE_BUTTON_SCROLLRIGHT = 7,// scroll right
    MOUSE_BUTTON_BACKWARD = 8,   // backward (4th button)
    MOUSE_BUTTON_FORWARD = 9,    // forward (5th button)
    MOUSE_BUTTON_10 = 10,        // extra button 1
    MOUSE_BUTTON_11 = 11,        // extra button 2
} MouseButtonNumber;

typedef NS_ENUM(NSInteger, MouseFormat) {
    MOUSE_FORMAT_XTERM = 0,       // Regular 1000 mode (limited to 223 rows/cols)
    MOUSE_FORMAT_XTERM_EXT = 1,   // UTF-8 1005 mode (does not pass through luit unchanged)
    MOUSE_FORMAT_URXVT = 2,       // rxvt's 1015 mode (outputs csi codes, that if echoed to the term, mess up the display)
    MOUSE_FORMAT_SGR = 3,         // SGR 1006 mode (preferred)
    MOUSE_FORMAT_SGR_PIXEL = 4,   // xterm's SGR 1016 mode (like 1006 but pixels instead of cells)
};

typedef NS_ENUM(NSInteger, VT100EmulationLevel) {
    VT100EmulationLevel100,
    VT100EmulationLevel200,
    VT100EmulationLevel400
};

typedef struct {
    int pr;
    int pc;
    int pp;
    char srend;
    char satt;
    char sflag;
    int pgl;
    int pgr;
    char scss;
    char const *sdesig[4];
} VT100OutputCursorInformation;

VT100OutputCursorInformation VT100OutputCursorInformationCreate(int row,  // 1-based
                                                                int column,  // 1-based
                                                                BOOL reverseVideo,
                                                                BOOL blink,
                                                                BOOL underline,
                                                                BOOL bold,
                                                                BOOL autowrapPending,
                                                                BOOL lineDrawingMode,  // ss2: g2 mapped into gl
                                                                BOOL originMode);
VT100OutputCursorInformation VT100OutputCursorInformationFromString(NSString *string, BOOL *ok);
int VT100OutputCursorInformationGetCursorX(VT100OutputCursorInformation info);
int VT100OutputCursorInformationGetCursorY(VT100OutputCursorInformation info);
BOOL VT100OutputCursorInformationGetReverseVideo(VT100OutputCursorInformation info);
BOOL VT100OutputCursorInformationGetBlink(VT100OutputCursorInformation info);
BOOL VT100OutputCursorInformationGetUnderline(VT100OutputCursorInformation info);
BOOL VT100OutputCursorInformationGetBold(VT100OutputCursorInformation info);
BOOL VT100OutputCursorInformationGetAutowrapPending(VT100OutputCursorInformation info);
BOOL VT100OutputCursorInformationGetOriginMode(VT100OutputCursorInformation info);
BOOL VT100OutputCursorInformationGetLineDrawingMode(VT100OutputCursorInformation info);

// This class produces data to send for special keys (arrow keys, function keys, etc.)
// It has a small amount of state that is copied from VT100Terminal. This object is 1:1 with
// VT100Terminal.
@interface VT100Output : NSObject<NSCopying>

@property(nonatomic, copy) NSString *termType;
@property(nonatomic, assign) BOOL keypadMode;
@property(nonatomic, assign) MouseFormat mouseFormat;
@property(nonatomic, assign) BOOL cursorMode;
@property(nonatomic, assign) BOOL optionIsMetaForSpecialKeys;
@property(nonatomic, assign) VT100EmulationLevel vtLevel;

- (NSDictionary *)configDictionary;

- (NSData *)keyArrowUp:(unsigned int)modflag;
- (NSData *)keyArrowDown:(unsigned int)modflag;
- (NSData *)keyArrowLeft:(unsigned int)modflag;
- (NSData *)keyArrowRight:(unsigned int)modflag;
- (NSData *)keyHome:(unsigned int)modflag screenlikeTerminal:(BOOL)screenlike;
- (NSData *)keyEnd:(unsigned int)modflag screenlikeTerminal:(BOOL)screenlike;
- (NSData *)keyInsert;
- (NSData *)keyDelete:(NSEventModifierFlags)flags;
- (NSData *)keyBackspace;
- (NSData *)keyPageUp:(unsigned int)modflag;
- (NSData *)keyPageDown:(unsigned int)modflag;
- (NSData *)keyFunction:(int)no modifiers:(NSEventModifierFlags)modifiers;
- (NSData *)keypadDataForString:(NSString *)keystr modifiers:(NSEventModifierFlags)modifiers;

- (NSData *)mousePress:(int)button withModifiers:(unsigned int)modflag at:(VT100GridCoord)coord point:(NSPoint)point;
- (NSData *)mouseRelease:(int)button withModifiers:(unsigned int)modflag at:(VT100GridCoord)coord point:(NSPoint)point;
- (NSData *)mouseMotion:(int)button withModifiers:(unsigned int)modflag at:(VT100GridCoord)coord point:(NSPoint)point;
- (BOOL)shouldReportMouseMotionAtCoord:(VT100GridCoord)coord
                             lastCoord:(VT100GridCoord)lastReportedCoord
                                 point:(NSPoint)point
                             lastPoint:(NSPoint)lastReportedPoint;

- (NSData *)reportActivePositionWithX:(int)x Y:(int)y withQuestion:(BOOL)q;
- (NSData *)reportStatus;
- (NSData *)reportDeviceAttribute;
- (NSData *)reportSecondaryDeviceAttribute;
- (NSData *)reportExtendedDeviceAttribute;
- (NSData *)reportTertiaryDeviceAttribute;

// Prefix is either @"4;" (for OSC 4) or @"" (for OSC 10 and OSC 11).
- (NSData *)reportColor:(NSColor *)color atIndex:(int)index prefix:(NSString *)prefix;

- (NSData *)reportChecksum:(int)checksum withIdentifier:(int)identifier;
- (NSData *)reportSGRCodes:(NSArray<NSString *> *)codes;

- (NSData *)reportFocusGained:(BOOL)gained;
- (NSData *)reportiTerm2Version;
- (NSData *)reportKeyReportingMode:(int)mode;
- (NSData *)reportCursorInformation:(VT100OutputCursorInformation)info;
- (NSData *)reportTabStops:(NSArray<NSNumber *> *)tabStops;
- (NSData *)reportSavedColorsUsed:(int)used
                      largestUsed:(int)last;
- (NSData *)reportGraphicsAttributeWithItem:(int)item
                                     status:(int)status
                                      value:(NSString *)value;
- (NSData *)reportDECDSR:(int)code;
- (NSData *)reportDECDSR:(int)code :(int)subcode;
- (NSData *)reportMacroSpace:(int)space;
- (NSData *)reportMemoryChecksum:(int)checksum id:(int)reqid;
- (NSData *)reportVariableNamed:(NSString *)name value:(NSString *)variableValue;
- (NSData *)reportPasteboard:(NSString *)pasteboard contents:(NSString *)string;

typedef struct {
    uint32_t twentyFourBit;  // "T"
    BOOL clipboardWritable;  // "Cw"
    BOOL DECSLRM;            // "Lr"
    BOOL mouse;              // "M"
    uint32_t DECSCUSR;       // "Sc"
    BOOL unicodeBasic;       // "U"
    BOOL ambiguousWide;      // "Aw"
    uint32_t unicodeWidths;  // "Uw"
    uint32_t titles;         // "Ts"
    BOOL bracketedPaste;     // "B"
    BOOL focusReporting;     // "F"
    BOOL strikethrough;      // "Gs"
    BOOL overline;           // "Go"
    BOOL sync;               // "Sy"
    BOOL hyperlinks;         // "H"
    BOOL notifications;      // "No"
    BOOL sixel;              // "Sx"
    BOOL file;               // "F"
} VT100Capabilities;

VT100Capabilities VT100OutputMakeCapabilities(BOOL compatibility24Bit,
                                              BOOL full24Bit,
                                              BOOL clipboardWritable,
                                              BOOL decslrm,
                                              BOOL mouse,
                                              BOOL DECSCUSR14,
                                              BOOL DECSCUSR56,
                                              BOOL DECSCUSR0,
                                              BOOL unicode,
                                              BOOL ambiguousWide,
                                              uint32_t unicodeVersion,
                                              BOOL titleStacks,
                                              BOOL titleSetting,
                                              BOOL bracketedPaste,
                                              BOOL focusReporting,
                                              BOOL strikethrough,
                                              BOOL overline,
                                              BOOL sync,
                                              BOOL hyperlinks,
                                              BOOL notifications,
                                              BOOL sixel,
                                              BOOL file);

- (NSData *)reportCapabilities:(VT100Capabilities)capabilities;
+ (NSString *)encodedTermFeaturesForCapabilities:(VT100Capabilities)capabilities;

@end
