//
//  ITMRPCRegistrationRequest+Extensions.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 02/05/19.
//

#import "Api.pbobjc.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermVariableScope;

@interface ITMRPCRegistrationRequest (Extensions)

- (BOOL)it_rpcRegistrationRequestValidWithError:(out NSError **)error;
- (NSString *)it_stringRepresentation;
- (NSSet<NSString *> *)it_allArgumentNames;
- (NSSet<NSString *> *)it_argumentsWithDefaultValues;
- (NSSet<NSString *> *)it_requiredArguments;

- (BOOL)it_satisfiesExplicitParameters:(NSDictionary<NSString *, id> *)explicitParameters
                                 scope:(iTermVariableScope *)scope
                        fullParameters:(out NSDictionary<NSString *, id> **)fullParameters;

@end

NS_ASSUME_NONNULL_END
