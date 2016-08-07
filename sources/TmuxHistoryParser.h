//
//  TmuxHistoryParser.h
//  iTerm
//
//  Created by George Nachman on 11/29/11.
//

#import <Foundation/Foundation.h>

@interface TmuxHistoryParser : NSObject

+ (instancetype)sharedInstance;
- (NSArray<NSData *> *)parseDumpHistoryResponse:(NSString *)response
                         ambiguousIsDoubleWidth:(BOOL)ambiguousIsDoubleWidth
                                 unicodeVersion:(NSInteger)unicodeVersion;

@end
