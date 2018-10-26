//
//  iTermCharacterSource.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/26/17.
//

#import <Foundation/Foundation.h>

@class iTermCharacterBitmap;

@interface iTermCharacterSource : NSObject

@property (nonatomic, readonly) BOOL isEmoji;
@property (nonatomic, readonly) CGRect frame;
@property (nonatomic, readonly) NSArray<NSNumber *> *parts;

// Using conservative settings (bold, italic, thick strokes, antialiased)
// returns the frame that contains all characters in the range. This is useful
// for finding the bounding box of all ASCII glyphs.
+ (NSRect)boundingRectForCharactersInRange:(NSRange)range
                                      font:(NSFont *)font
                            baselineOffset:(CGFloat)baselineOffset
                                     scale:(CGFloat)scale
                                   context:(CGContextRef)context;

- (instancetype)initWithCharacter:(NSString *)string
                             font:(NSFont *)font
                        glyphSize:(CGSize)glyphSize
                         cellSize:(CGSize)cellSize
           cellSizeWithoutSpacing:(CGSize)cellSizeWithoutSpacing
                   baselineOffset:(CGFloat)baselineOffset
                            scale:(CGFloat)scale
                   useThinStrokes:(BOOL)useThinStrokes
                         fakeBold:(BOOL)fakeBold
                       fakeItalic:(BOOL)fakeItalic
                      antialiased:(BOOL)antialiased
                       boxDrawing:(BOOL)boxDrawing
                           radius:(int)radius
                          context:(CGContextRef)context;

- (iTermCharacterBitmap *)bitmapForPart:(int)part;

@end
