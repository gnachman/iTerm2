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

+ (instancetype)newAttributedStringWithHTML:(NSString *)html
                                 attributes:(NSDictionary *)attributes;

@end

NS_ASSUME_NONNULL_END
