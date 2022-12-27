//
//  Header.h
//  iTerm2
//
//  Created by George Nachman on 5/17/19.
//

#import "iTermScriptFunctionCall.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermBuiltInFunctions;
@class iTermScriptFunctionCall;
@class iTermVariableScope;

@protocol iTermObject<NSObject>

@property (readonly, copy) NSString *description;

- (iTermBuiltInFunctions * _Nullable)objectMethodRegistry;
- (iTermVariableScope * _Nullable)objectScope;

@end

void iTermCallMethodByIdentifier(NSString *identifier,
                                 NSString *name,
                                 NSDictionary *args,
                                 void (^completion)(id, NSError *));

void iTermCallMethodOnObject(id<iTermObject> object,
                             NSString *name,
                             NSDictionary *args,
                             void (^completion)(id, NSError *));


NS_ASSUME_NONNULL_END
