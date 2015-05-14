//
//  iTermProfileSearchToken.h
//  iTerm2
//
//  Created by George Nachman on 5/14/15.
//
//

#import <Foundation/Foundation.h>

@interface iTermProfileSearchToken : NSObject

@property(nonatomic, copy) NSArray *strings;
@property(nonatomic, copy) NSString *operator;
@property(nonatomic, assign) BOOL anchor;
@property(nonatomic, readonly) NSRange range;

- (instancetype)initWithPhrase:(NSString *)phrase;

@end
