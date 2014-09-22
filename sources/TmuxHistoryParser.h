//
//  TmuxHistoryParser.h
//  iTerm
//
//  Created by George Nachman on 11/29/11.
//

#import <Foundation/Foundation.h>

@interface TmuxHistoryParser : NSObject

+ (TmuxHistoryParser *)sharedInstance;
- (NSArray *)parseDumpHistoryResponse:(NSString *)response
               ambiguousIsDoubleWidth:(BOOL)ambiguousIsDoubleWidth;

@end
