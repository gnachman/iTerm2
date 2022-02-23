//
//  iTermProfileSearchToken.h
//  iTerm2
//
//  Created by George Nachman on 5/14/15.
//
//

#import <Foundation/Foundation.h>

@interface iTermProfileSearchToken : NSObject

@property(nonatomic, readonly) NSRange range;
@property(nonatomic, readonly) BOOL negated;

- (instancetype)initWithPhrase:(NSString *)phrase;

- (BOOL)matchesAnyWordInNameWords:(NSArray *)nameWords;
- (BOOL)matchesAnyWordInTagWords:(NSArray *)tagWords;

@end
