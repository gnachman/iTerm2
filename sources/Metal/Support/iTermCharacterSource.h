//
//  iTermCharacterSource.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/26/17.
//

#import <Foundation/Foundation.h>


@interface iTermCharacterSource : NSObject

@property (nonatomic, readonly) BOOL emoji;
@property (nonatomic, readonly) CGRect frame;
@property (nonatomic, readonly) NSArray<NSNumber *> *parts;

- (instancetype)initWithCharacter:(NSString *)string
                             font:(NSFont *)font
                             size:(CGSize)size
                   baselineOffset:(CGFloat)baselineOffset
                            scale:(CGFloat)scale
                   useThinStrokes:(BOOL)useThinStrokes
                         fakeBold:(BOOL)fakeBold
                       fakeItalic:(BOOL)fakeItalic;

- (NSImage *)imageAtPart:(int)part;

@end
