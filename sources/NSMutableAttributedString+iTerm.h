//
//  NSMutableAttributedString+iTerm.h
//  iTerm
//
//  Created by George Nachman on 12/8/13.
//
//

#import <Foundation/Foundation.h>

@interface NSMutableAttributedString (iTerm)

- (void)iterm_appendString:(NSString *)string;
- (void)iterm_appendString:(NSString *)string withAttributes:(NSDictionary *)attributes;
- (void)trimTrailingWhitespace;

@end

@interface NSAttributedString (iTerm)

- (NSArray *)attributedComponentsSeparatedByString:(NSString *)separator;
- (CGFloat)heightForWidth:(CGFloat)maxWidth;

@end
