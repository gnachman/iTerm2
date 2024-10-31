//
//  iTermCoreTextLineRenderingHelper.h
//  iTerm2
//
//  Created by George Nachman on 11/1/24.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermCoreTextLineRenderingHelper: NSObject

@property (nonatomic) BOOL verbose;

- (instancetype)initWithLine:(CTLineRef)line
                      string:(NSString *)string
             drawInCellIndex:(NSData *)drawInCellIndex NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (void)enumerateRuns:(void (^ NS_NOESCAPE)(size_t j,
                                            CTRunRef run,
                                            size_t length,
                                            const CGGlyph *glyphs,
                                            CGPoint *positions,
                                            const CGSize *advances,
                                            const CFIndex *glyphIndexToCharacterIndex,
                                            BOOL *stop))closure;

// `positions` is relative to xOriginsForCharacters[0].
- (void)enumerateGridAlignedRunsWithColumnPositions:(const CGFloat *)xOriginsForCharacters
                                        alignToZero:(BOOL)alignToZero
                                            closure:(void (^ NS_NOESCAPE)(CTRunRef run,
                                                                          CTFontRef font,
                                                                          const CGGlyph *glyphs,
                                                                          const NSPoint *positions,
                                                                          const CFIndex *glyphIndexToCharacterIndex,
                                                                          size_t length,
                                                                          BOOL *stop))closure;

@end

NS_ASSUME_NONNULL_END
