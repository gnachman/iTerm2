//
//  CharacterRun.h
//  iTerm
//
//  Created by George Nachman on 12/16/12.
//
//

#import <Cocoa/Cocoa.h>
#import "PTYFontInfo.h"
#import <ApplicationServices/ApplicationServices.h>
#import "ScreenChar.h"

// Backinng storage for character runs.
@interface CRunStorage : NSObject {
    unichar *codes_;
    CGGlyph *glyphs_;
    NSSize *advances_;
    int capacity_;
    int used_;
}

+ (CRunStorage *)cRunStorageWithCapacity:(int)capacity;
- (unichar *)codesFromIndex:(int)index;
- (CGGlyph *)glyphsFromIndex:(int)index;
- (NSSize *)advancesFromIndex:(int)index;
- (int)allocate:(int)size;

@end

typedef struct {
    BOOL antiAlias;           // Use anti-aliasing?
    NSColor *color;           // Foreground color
    BOOL fakeBold;            // Should bold text be rendered by drawing text twice with a 1px shift?
    PTYFontInfo *fontInfo;    // Font to use.
} CAttrs;

typedef struct CRun CRun;

struct CRun {
    CAttrs attrs;
    CGFloat x;                // x pixel coordinate for the run's start.
    int length;
    unichar *codes;
    NSString *string;
    CGGlyph *glyphs;
    NSSize *advances;
    BOOL terminated;

    CRun *next;
};

// See CharacterRunInline.h for functions that operate on CRun.
void CRunDump(CRun *run);
