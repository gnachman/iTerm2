//
//  iTermRule.h
//  iTerm
//
//  Created by George Nachman on 6/24/14.
//
//

#import <Foundation/Foundation.h>

@class iTermAutomaticProfileSwitchingSession;
@protocol iTermAutomaticProfileSwitchingExpressionValueProvider;

@interface iTermRule : NSObject
@property(nonatomic, copy, readonly) NSString *username;
@property(nonatomic, copy, readonly) NSString *hostname;
@property(nonatomic, copy, readonly) NSString *path;
@property(nonatomic, copy, readonly) NSString *job;
@property(nonatomic, copy, readonly) NSString *expression;
@property(nonatomic, readonly, getter=isSticky) BOOL sticky;

+ (instancetype)ruleWithString:(NSString *)string;
- (double)scoreForHostname:(NSString *)hostname
                  username:(NSString *)username
                      path:(NSString *)path
                       job:(NSString *)job
               commandLine:(NSString *)commandLine
   expressionValueProvider:(id<iTermAutomaticProfileSwitchingExpressionValueProvider>)expressionValueProvider;

@end
