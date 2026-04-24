//
//  iTermGlyphCharacterSource.h
//  iTerm2
//
//  Created by George Nachman on 2/26/25.
//

#import "iTermCharacterSource.h"

// Produces bitmaps of a single glyph from a font.
@interface iTermGlyphCharacterSource: iTermCharacterSource

- (instancetype)initWithFontID:(unsigned int)fontID
                      fakeBold:(BOOL)fakeBold
                    fakeItalic:(BOOL)fakeItalic
                   glyphNumber:(unsigned short)glyphNumber
                      position:(NSPoint)position
                    descriptor:(iTermCharacterSourceDescriptor *)descriptor
                    attributes:(iTermCharacterSourceAttributes *)attributes
                        radius:(int)radius
                 lineAttribute:(iTermLineAttribute)lineAttribute
                       context:(CGContextRef)context;
@end
