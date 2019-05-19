//
//  Header.h
//  iTerm2
//
//  Created by George Nachman on 5/17/19.
//

#import "iTermScriptFunctionCall.h"

@class iTermBuiltInFunctions;
@class iTermScriptFunctionCall;
@class iTermVariableScope;

@protocol iTermObject<NSObject>

- (NSString *)description;
- (iTermBuiltInFunctions *)objectMethodRegistry;
- (iTermVariableScope *)objectScope;

@end

void iTermCallMethodByIdentifier(NSString *identifier,
                                 NSString *name,
                                 NSDictionary *args,
                                 void (^completion)(id, NSError *));

void iTermCallMethodOnObject(id<iTermObject> object,
                             NSString *name,
                             NSDictionary *args,
                             void (^completion)(id, NSError *));

