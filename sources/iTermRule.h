//
//  iTermRule.h
//  iTerm
//
//  Created by George Nachman on 6/24/14.
//
//

#import <Foundation/Foundation.h>

@interface iTermRule : NSObject
@property(nonatomic, readonly) NSString *username;
@property(nonatomic, readonly) NSString *hostname;
@property(nonatomic, readonly) NSString *path;
@property(nonatomic, readonly, getter=isSticky) BOOL sticky;

+ (instancetype)ruleWithString:(NSString *)string;
- (double)scoreForHostname:(NSString *)hostname
                  username:(NSString *)username
                      path:(NSString *)path;

@end
