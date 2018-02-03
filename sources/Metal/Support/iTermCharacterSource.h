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

- (instancetype)initWithCharacter:(NSString *)string
                             font:(NSFont *)font
                             size:(CGSize)size
                   baselineOffset:(CGFloat)baselineOffset
                            scale:(CGFloat)scale
                   useThinStrokes:(BOOL)useThinStrokes
                         fakeBold:(BOOL)fakeBold
                       fakeItalic:(BOOL)fakeItalic
                      antialiased:(BOOL)antialiased;

- (iTermCharacterBitmap *)bitmapForPart:(int)part;

@end
