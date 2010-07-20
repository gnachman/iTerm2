// -*- mode:objc -*-
// $Id: VT100Terminal.h,v 1.35 2008-10-21 05:43:52 yfabian Exp $
/*
 **  VT100Terminal.h
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **	     Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: Implements the model class VT100 terminal.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import <Cocoa/Cocoa.h>
//#include <term.h>

@class VT100Screen;
@class PseudoTerminal;

// VT100TCC types
#define VT100CC_NULL        0
#define VT100CC_ENQ         5    // Transmit ANSWERBACK message
#define VT100CC_BEL         7    // Sound bell
#define VT100CC_BS          8    // Move cursor to the left
#define VT100CC_HT          9    // Move cursor to the next tab stop
#define VT100CC_LF         10    // line feed or new line operation
#define VT100CC_VT         11    // Same as <LF>.
#define VT100CC_FF         12	 // Same as <LF>.
#define VT100CC_CR         13    // Move the cursor to the left margin
#define VT100CC_SO         14    // Invoke the G1 character set
#define VT100CC_SI         15    // Invoke the G0 character set
#define VT100CC_DC1        17    // Causes terminal to resume transmission (XON).
#define VT100CC_DC3        19    // Causes terminal to stop transmitting all codes except XOFF and XON (XOFF).
#define VT100CC_CAN        24    // Cancel a control sequence
#define VT100CC_SUB        26    // Same as <CAN>.
#define VT100CC_ESC        27    // Introduces a control sequence.
#define VT100CC_DEL       255    // Ignored on input; not stored in buffer.
                                                                              
#define VT100_WAIT        	1000
#define VT100_NOTSUPPORT  	1001
#define VT100_SKIP        	1002
#define VT100_STRING      	1003       // string
#define VT100_ASCIISTRING	1004	   // only for ASCIIs
#define VT100_UNKNOWNCHAR 	1005
#define VT100CSI_DECSET		1006
#define VT100CSI_DECRST		1007

#define VT100CSI_CPR         2000       // Cursor Position Report
#define VT100CSI_CUB         2001       // Cursor Backward
#define VT100CSI_CUD         2002       // Cursor Down
#define VT100CSI_CUF         2003       // Cursor Forward
#define VT100CSI_CUP         2004       // Cursor Position
#define VT100CSI_CUU         2005       // Cursor Up
#define VT100CSI_DA          2006       // Device Attributes
#define VT100CSI_DECALN	     2007		// Screen Alignment Display
#define VT100CSI_DECDHL      2013       // Double Height Line
#define VT100CSI_DECDWL      2014       // Double Width Line
#define VT100CSI_DECID       2015       // Identify Terminal
#define VT100CSI_DECKPAM     2017       // Keypad Application Mode
#define VT100CSI_DECKPNM     2018       // Keypad Numeric Mode
#define VT100CSI_DECLL       2019       // Load LEDS
#define VT100CSI_DECRC       2021       // Restore Cursor
#define VT100CSI_DECREPTPARM 2022       // Report Terminal Parameters
#define VT100CSI_DECREQTPARM 2023       // Request Terminal Parameters
#define VT100CSI_DECSC       2024       // Save Cursor
#define VT100CSI_DECSTBM     2027       // Set Top and Bottom Margins
#define VT100CSI_DECSWL      2028       // Single-width Line
#define VT100CSI_DECTST      2029       // Invoke Confidence Test
#define VT100CSI_DSR         2030       // Device Status Report
#define VT100CSI_ED          2031       // Erase In Display
#define VT100CSI_EL          2032       // Erase In Line
#define VT100CSI_HTS         2033       // Horizontal Tabulation Set
#define VT100CSI_HVP         2034       // Horizontal and Vertical Position
#define VT100CSI_IND         2035       // Index
#define VT100CSI_NEL         2037       // Next Line
#define VT100CSI_RI          2038       // Reverse Index
#define VT100CSI_RIS         2039       // Reset To Initial State
#define VT100CSI_RM          2040       // Reset Mode
#define VT100CSI_SCS         2041
#define VT100CSI_SCS0        2041       // Select Character Set 0
#define VT100CSI_SCS1        2042       // Select Character Set 1
#define VT100CSI_SCS2        2043       // Select Character Set 2
#define VT100CSI_SCS3        2044       // Select Character Set 3
#define VT100CSI_SGR         2045       // Select Graphic Rendition
#define VT100CSI_SM          2046       // Set Mode
#define VT100CSI_TBC         2047       // Tabulation Clear

// some xterm extension
#define XTERMCC_WIN_TITLE	     86	      // Set window title
#define XTERMCC_ICON_TITLE	     91
#define XTERMCC_WINICON_TITLE	 92
#define XTERMCC_INSBLNK	     87       // Insert blank
#define XTERMCC_INSLN	     88	      // Insert lines
#define XTERMCC_DELCH	     89       // delete blank
#define XTERMCC_DELLN	     90	      // delete lines
#define XTERMCC_WINDOWSIZE	 93       // (8,H,W) NK: added for Vim resizing window
#define XTERMCC_WINDOWSIZE_PIXEL	 94       // (8,H,W) NK: added for Vim resizing window
#define XTERMCC_WINDOWPOS	 95       // (3,Y,X) NK: added for Vim positioning window
#define XTERMCC_ICONIFY      96
#define XTERMCC_DEICONIFY    97
#define XTERMCC_RAISE        98
#define XTERMCC_LOWER        99
#define XTERMCC_SU			 100	 // scroll up
#define XTERMCC_SD			 101     // scroll down
#define XTERMCC_REPORT_WIN_STATE	102
#define XTERMCC_REPORT_WIN_POS		103
#define XTERMCC_REPORT_WIN_PIX_SIZE	104
#define XTERMCC_REPORT_WIN_SIZE		105
#define XTERMCC_REPORT_SCREEN_SIZE	106
#define XTERMCC_REPORT_ICON_TITLE	107
#define XTERMCC_REPORT_WIN_TITLE	108
#define XTERMCC_SET_RGB	109

// Some ansi stuff
#define ANSICSI_CHA	     3000	// Cursor Horizontal Absolute
#define ANSICSI_VPA	     3001	// Vert Position Absolute
#define ANSICSI_VPR	     3002	// Vert Position Relative
#define ANSICSI_ECH	     3003	// Erase Character
#define ANSICSI_PRINT	 3004	// Print to Ansi
#define ANSICSI_SCP      3005   // Save cursor position
#define ANSICSI_RCP      3006   // Restore cursor position
#define ANSICSI_CBT	     3007	// Back tab

// Toggle between ansi/vt52
#define STRICT_ANSI_MODE		4000

// iTerm extension
#define ITERM_GROWL     5000

#define VT100CSIPARAM_MAX    16

typedef struct {
    int type;
    unsigned char *position;
    int length;
    union {
	NSString *string;
	unsigned char code;
	struct {
	    int p[VT100CSIPARAM_MAX];
	    int count;
	    BOOL question;
		int modifier;
	} csi;
    } u;
} VT100TCC;

// character attributes
#define VT100CHARATTR_ALLOFF   0
#define VT100CHARATTR_BOLD     1
#define VT100CHARATTR_UNDER    4
#define VT100CHARATTR_BLINK    5
#define VT100CHARATTR_REVERSE  7

// xterm additions
#define VT100CHARATTR_NORMAL  		22
#define VT100CHARATTR_NOT_UNDER  	24
#define VT100CHARATTR_STEADY	  	25
#define VT100CHARATTR_POSITIVE  	27

typedef enum {
    COLORCODE_BLACK=0,
    COLORCODE_RED=1,
    COLORCODE_GREEN=2,
    COLORCODE_YELLOW=3,
    COLORCODE_BLUE=4,
    COLORCODE_PURPLE=5,
    COLORCODE_WATER=6,
    COLORCODE_WHITE=7,
	COLORCODE_256=8,
    COLORS
} colorCode;

// 8 color support
#define VT100CHARATTR_FG_BASE  30
#define VT100CHARATTR_BG_BASE  40

#define VT100CHARATTR_FG_BLACK     (VT100CHARATTR_FG_BASE + COLORCODE_BLACK)
#define VT100CHARATTR_FG_RED       (VT100CHARATTR_FG_BASE + COLORCODE_RED)
#define VT100CHARATTR_FG_GREEN     (VT100CHARATTR_FG_BASE + COLORCODE_GREEN)
#define VT100CHARATTR_FG_YELLOW    (VT100CHARATTR_FG_BASE + COLORCODE_YELLOW)
#define VT100CHARATTR_FG_BLUE      (VT100CHARATTR_FG_BASE + COLORCODE_BLUE)
#define VT100CHARATTR_FG_PURPLE    (VT100CHARATTR_FG_BASE + COLORCODE_PURPLE)
#define VT100CHARATTR_FG_WATER     (VT100CHARATTR_FG_BASE + COLORCODE_WATER)
#define VT100CHARATTR_FG_WHITE     (VT100CHARATTR_FG_BASE + COLORCODE_WHITE)
#define VT100CHARATTR_FG_256	   (VT100CHARATTR_FG_BASE + COLORCODE_256)
#define VT100CHARATTR_FG_DEFAULT   (VT100CHARATTR_FG_BASE + 9)

#define VT100CHARATTR_BG_BLACK     (VT100CHARATTR_BG_BASE + COLORCODE_BLACK)
#define VT100CHARATTR_BG_RED       (VT100CHARATTR_BG_BASE + COLORCODE_RED)
#define VT100CHARATTR_BG_GREEN     (VT100CHARATTR_BG_BASE + COLORCODE_GREEN)
#define VT100CHARATTR_BG_YELLOW    (VT100CHARATTR_BG_BASE + COLORCODE_YELLOW)
#define VT100CHARATTR_BG_BLUE      (VT100CHARATTR_BG_BASE + COLORCODE_BLUE)
#define VT100CHARATTR_BG_PURPLE    (VT100CHARATTR_BG_BASE + COLORCODE_PURPLE)
#define VT100CHARATTR_BG_WATER     (VT100CHARATTR_BG_BASE + COLORCODE_WATER)
#define VT100CHARATTR_BG_WHITE     (VT100CHARATTR_BG_BASE + COLORCODE_WHITE)
#define VT100CHARATTR_BG_256	   (VT100CHARATTR_BG_BASE + COLORCODE_256)
#define VT100CHARATTR_BG_DEFAULT   (VT100CHARATTR_BG_BASE + 9)

// 16 color support
#define VT100CHARATTR_FG_HI_BASE  90
#define VT100CHARATTR_BG_HI_BASE  100

#define VT100CHARATTR_FG_HI_BLACK     (VT100CHARATTR_FG_HI_BASE + COLORCODE_BLACK)
#define VT100CHARATTR_FG_HI_RED       (VT100CHARATTR_FG_HI_BASE + COLORCODE_RED)
#define VT100CHARATTR_FG_HI_GREEN     (VT100CHARATTR_FG_HI_BASE + COLORCODE_GREEN)
#define VT100CHARATTR_FG_HI_YELLOW    (VT100CHARATTR_FG_HI_BASE + COLORCODE_YELLOW)
#define VT100CHARATTR_FG_HI_BLUE      (VT100CHARATTR_FG_HI_BASE + COLORCODE_BLUE)
#define VT100CHARATTR_FG_HI_PURPLE    (VT100CHARATTR_FG_HI_BASE + COLORCODE_PURPLE)
#define VT100CHARATTR_FG_HI_WATER     (VT100CHARATTR_FG_HI_BASE + COLORCODE_WATER)
#define VT100CHARATTR_FG_HI_WHITE     (VT100CHARATTR_FG_HI_BASE + COLORCODE_WHITE)

#define VT100CHARATTR_BG_HI_BLACK     (VT100CHARATTR_BG_HI_BASE + COLORCODE_BLACK)
#define VT100CHARATTR_BG_HI_RED       (VT100CHARATTR_BG_HI_BASE + COLORCODE_RED)
#define VT100CHARATTR_BG_HI_GREEN     (VT100CHARATTR_BG_HI_BASE + COLORCODE_GREEN)
#define VT100CHARATTR_BG_HI_YELLOW    (VT100CHARATTR_BG_HI_BASE + COLORCODE_YELLOW)
#define VT100CHARATTR_BG_HI_BLUE      (VT100CHARATTR_BG_HI_BASE + COLORCODE_BLUE)
#define VT100CHARATTR_BG_HI_PURPLE    (VT100CHARATTR_BG_HI_BASE + COLORCODE_PURPLE)
#define VT100CHARATTR_BG_HI_WATER     (VT100CHARATTR_BG_HI_BASE + COLORCODE_WATER)
#define VT100CHARATTR_BG_HI_WHITE     (VT100CHARATTR_BG_HI_BASE + COLORCODE_WHITE)


// for foreground colors
#define DEFAULT_FG_COLOR_CODE	0x100
#define BOLD_MASK 0x200
#define BLINK_MASK 0x400
#define UNDER_MASK 0x800
#define SELECTED_TEXT   0x102
#define CURSOR_TEXT		0x103

// for background colors
#define DEFAULT_BG_COLOR_CODE	0x101

// terminfo stuff
enum {
	TERMINFO_KEY_LEFT, TERMINFO_KEY_RIGHT, TERMINFO_KEY_UP, TERMINFO_KEY_DOWN, 
	TERMINFO_KEY_HOME, TERMINFO_KEY_END, TERMINFO_KEY_PAGEDOWN, TERMINFO_KEY_PAGEUP,
    TERMINFO_KEY_F0, TERMINFO_KEY_F1, TERMINFO_KEY_F2, TERMINFO_KEY_F3, TERMINFO_KEY_F4, 
	TERMINFO_KEY_F5, TERMINFO_KEY_F6, TERMINFO_KEY_F7, TERMINFO_KEY_F8, TERMINFO_KEY_F9, 
	TERMINFO_KEY_F10, TERMINFO_KEY_F11, TERMINFO_KEY_F12, TERMINFO_KEY_F13, TERMINFO_KEY_F14,
	TERMINFO_KEY_F15, TERMINFO_KEY_F16, TERMINFO_KEY_F17, TERMINFO_KEY_F18, TERMINFO_KEY_F19, 
    TERMINFO_KEY_F20, TERMINFO_KEY_F21, TERMINFO_KEY_F22, TERMINFO_KEY_F23, TERMINFO_KEY_F24, 
	TERMINFO_KEY_F25, TERMINFO_KEY_F26, TERMINFO_KEY_F27, TERMINFO_KEY_F28, TERMINFO_KEY_F29, 
    TERMINFO_KEY_F30, TERMINFO_KEY_F31, TERMINFO_KEY_F32, TERMINFO_KEY_F33, TERMINFO_KEY_F34, 
	TERMINFO_KEY_F35,
	TERMINFO_KEY_BACKSPACE, TERMINFO_KEY_BACK_TAB, 
	TERMINFO_KEY_TAB, 
    TERMINFO_KEY_DEL, TERMINFO_KEY_INS, 
	TERMINFO_KEY_HELP,
    TERMINFO_KEYS 
};
    
typedef enum {
	MOUSE_REPORTING_NONE = -1,
	MOUSE_REPORTING_NORMAL = 0,
	MOUSE_REPORTING_HILITE,
	MOUSE_REPORTING_BUTTON_MOTION,
	MOUSE_REPORTING_ALL_MOTION,
} mouseMode;

@interface VT100Terminal : NSObject
{
    NSString          *termType;
    NSStringEncoding  ENCODING;
    VT100Screen       *SCREEN;

	unsigned char     *STREAM;
	int				  current_stream_length;
	int				  total_stream_length;
	
    BOOL LINE_MODE;			// YES=Newline, NO=Line feed
    BOOL CURSOR_MODE;		// YES=Application, NO=Cursor
    BOOL ANSI_MODE;			// YES=ANSI, NO=VT52
    BOOL COLUMN_MODE;		// YES=132 Column, NO=80 Column
    BOOL SCROLL_MODE;		// YES=Smooth, NO=Jump
    BOOL SCREEN_MODE;		// YES=Reverse, NO=Normal
    BOOL ORIGIN_MODE;		// YES=Relative, NO=Absolute
    BOOL WRAPAROUND_MODE;	// YES=On, NO=Off
    BOOL AUTOREPEAT_MODE;	// YES=On, NO=Off
    BOOL INTERLACE_MODE;	// YES=On, NO=Off
    BOOL KEYPAD_MODE;		// YES=Application, NO=Numeric
    BOOL INSERT_MODE;		// YES=Insert, NO=Replace
    int  CHARSET;			// G0...G3
    BOOL XON;				// YES=XON, NO=XOFF
    BOOL numLock;			// YES=ON, NO=OFF, default=YES;
	mouseMode MOUSE_MODE;
    
    int FG_COLORCODE;
    int BG_COLORCODE;
    int	bold, under, blink, reversed;

    int saveBold, saveUnder, saveBlink, saveReversed;
    int saveCHARSET;
    
    BOOL TRACE;

    BOOL strictAnsiMode;
    BOOL allowColumnMode;
	
	BOOL allowKeypadMode;
    
    unsigned int streamOffset;
    
    //terminfo
    char  *key_strings[TERMINFO_KEYS];
}

+ (void)initialize;

- (id)init;
- (void)dealloc;

- (NSString *)termtype;
- (void)setTermType:(NSString *)termtype;

- (BOOL)trace;
- (void)setTrace:(BOOL)flag;

- (BOOL)strictAnsiMode;
- (void)setStrictAnsiMode: (BOOL)flag;

- (BOOL)allowColumnMode;
- (void)setAllowColumnMode: (BOOL)flag;

- (NSStringEncoding)encoding;
- (void)setEncoding:(NSStringEncoding)encoding;

- (void)cleanStream;
- (void)putStreamData:(NSData*)data;
- (VT100TCC)getNextToken;

- (void)saveCursorAttributes;
- (void)restoreCursorAttributes;

- (void)reset;

- (NSData *)keyArrowUp:(unsigned int)modflag;
- (NSData *)keyArrowDown:(unsigned int)modflag;
- (NSData *)keyArrowLeft:(unsigned int)modflag;
- (NSData *)keyArrowRight:(unsigned int)modflag;
- (NSData *)keyHome:(unsigned int)modflag;
- (NSData *)keyEnd:(unsigned int)modflag;
- (NSData *)keyInsert;
- (NSData *)keyDelete;
- (NSData *)keyBackspace;
- (NSData *)keyPageUp;
- (NSData *)keyPageDown;
- (NSData *)keyFunction:(int)no;
- (NSData *)keypadData: (unichar) unicode keystr: (NSString *) keystr;

- (NSData *)mousePress: (int)button withModifiers: (unsigned int)modflag atX: (int)x Y: (int)y;
- (NSData *)mouseReleaseAtX: (int)x Y: (int)y;
- (NSData *)mouseMotion: (int)button withModifiers: (unsigned int)modflag atX: (int)x Y: (int)y;

- (BOOL)lineMode;
- (BOOL)cursorMode;
- (BOOL)columnMode;
- (BOOL)scrollMode;
- (BOOL)screenMode;
- (BOOL)originMode;
- (BOOL)wraparoundMode;
- (BOOL)autorepeatMode;
- (BOOL)interlaceMode;
- (BOOL)keypadMode;
- (BOOL)insertMode;
- (int)charset;
- (BOOL)xon;
- (mouseMode)mouseMode;

- (int)foregroundColorCode;
- (int)backgroundColorCode;
- (int)foregroundColorCodeReal;
- (int)backgroundColorCodeReal;

- (NSData *)reportActivePositionWithX:(int)x Y:(int)y withQuestion:(BOOL)q;
- (NSData *)reportStatus;
- (NSData *)reportDeviceAttribute;
- (NSData *)reportSecondaryDeviceAttribute;

- (void)_setMode:(VT100TCC)token;
- (void)_setCharAttr:(VT100TCC)token;
- (void)_setRGB:(VT100TCC)token;

- (void) setScreen:(VT100Screen *)sc;
@end

