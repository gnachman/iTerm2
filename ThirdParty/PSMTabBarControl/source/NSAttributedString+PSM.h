//
//  NSAttributedString+PSM.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/14/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSAttributedString (PSM)

- (NSAttributedString *)attributedStringWithTextAlignment:(NSTextAlignment)textAlignment;

// Parses lightweight HTML: <b>, <i>, <u>, and <font color="#rrggbb">, plus
// the entities iterm2.escape_html() produces. attributes apply to all text.
+ (instancetype)newAttributedStringWithHTML:(NSString *)html
                                 attributes:(NSDictionary *)attributes
    NS_SWIFT_NAME(fromLightweightHTML(_:attributes:));

@end

NS_ASSUME_NONNULL_END
