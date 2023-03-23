//
//  iTermTextDrawingHelperDelegate.h
//  iTerm2
//
//  Created by George Nachman on 6/20/22.
//

#import <Foundation/Foundation.h>
#import "iTermColorMap.h"
#import "ScreenChar.h"
#import "VT100GridTypes.h"

@class iTermColorMap;
@class iTermExternalAttributeIndex;
@protocol iTermExternalAttributeIndexReading;
@class iTermFindOnPageHelper;
@class iTermSelection;
@class iTermTextExtractor;
@class PTYFontInfo;
@protocol VT100ScreenMarkReading;

NS_ASSUME_NONNULL_BEGIN

@protocol iTermTextDrawingHelperDelegate <NSObject>

- (void)drawingHelperDrawBackgroundImageInRect:(NSRect)rect
                        blendDefaultBackground:(BOOL)blendDefaultBackground
                                 virtualOffset:(CGFloat)virtualOffset;

- (id<VT100ScreenMarkReading> _Nullable)drawingHelperMarkOnLine:(int)line;

- (const screen_char_t *)drawingHelperLineAtIndex:(int)line;
- (const screen_char_t *)drawingHelperLineAtScreenIndex:(int)line;

- (NSArray * _Nullable)drawingHelperCharactersWithNotesOnLine:(int)line;

- (void)drawingHelperUpdateFindCursorView;

- (NSDate * _Nullable)drawingHelperTimestampForLine:(int)line;

- (NSColor *)drawingHelperColorForCode:(int)theIndex
                                 green:(int)green
                                  blue:(int)blue
                             colorMode:(ColorMode)theMode
                                  bold:(BOOL)isBold
                                 faint:(BOOL)isFaint
                          isBackground:(BOOL)isBackground;

- (PTYFontInfo *)drawingHelperFontForChar:(UniChar)ch
                                isComplex:(BOOL)isComplex
                               renderBold:(BOOL *)renderBold
                             renderItalic:(BOOL *)renderItalic
                                 remapped:(UTF32Char *)ch;

- (NSData * _Nullable)drawingHelperMatchesOnLine:(int)line;

- (void)drawingHelperDidFindRunOfAnimatedCellsStartingAt:(VT100GridCoord)coord ofLength:(int)length;

- (NSString * _Nullable)drawingHelperLabelForDropTargetOnLine:(int)line;
- (NSRect)textDrawingHelperVisibleRect;
- (id<iTermExternalAttributeIndexReading> _Nullable)drawingHelperExternalAttributesOnLine:(int)lineNumber;

// Sometimes these are implemented by NSView
- (NSRect)frame;
- (NSScrollView * _Nullable)enclosingScrollView;

- (BOOL)drawingHelperShouldPadBackgrounds:(out NSSize *)padding;

@end

NS_ASSUME_NONNULL_END

