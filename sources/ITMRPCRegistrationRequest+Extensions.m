//
//  ITMRPCRegistrationRequest+Extensions.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 02/05/19.
//

#import "ITMRPCRegistrationRequest+Extensions.h"

#import "iTermBuiltInFunctions.h"
#import "NSArray+iTerm.h"

@implementation ITMRPCRegistrationRequest(Extensions)

- (BOOL)it_rpcRegistrationRequestValidWithError:(out NSError **)error {
    NSCharacterSet *ascii = [NSCharacterSet characterSetWithRange:NSMakeRange(0, 128)];
    NSMutableCharacterSet *invalidIdentifierCharacterSet = [NSMutableCharacterSet alphanumericCharacterSet];
    [invalidIdentifierCharacterSet addCharactersInString:@"_"];
    [invalidIdentifierCharacterSet formIntersectionWithCharacterSet:ascii];
    [invalidIdentifierCharacterSet invert];

    NSError *(^newErrorWithReason)(NSString *) = ^NSError *(NSString *reason) {
        NSDictionary *userinfo = @{ NSLocalizedDescriptionKey: reason };
        return [NSError errorWithDomain:@"com.iterm2.api"
                                   code:3
                               userInfo:userinfo];
    };
    if (self.name.length == 0) {
        if (error) {
            *error = newErrorWithReason(@"Name has length 0");
        }
        return NO;
    }
    if ([self.name rangeOfCharacterFromSet:invalidIdentifierCharacterSet].location != NSNotFound) {
        if (error) {
            *error = newErrorWithReason([NSString stringWithFormat:@"Function name '%@' contains an invalid character. Must match /[A-Za-z0-9_]/", self.name]);
        }
        return NO;
    }
    NSMutableSet<NSString *> *args = [NSMutableSet set];
    for (ITMRPCRegistrationRequest_RPCArgumentSignature *arg in self.argumentsArray) {
        NSString *name = arg.name;
        if (name.length == 0) {
            if (error) {
                *error = newErrorWithReason(@"Argument has 0-length name");
            }
            return NO;
        }
        if ([name rangeOfCharacterFromSet:invalidIdentifierCharacterSet].location != NSNotFound) {
            if (error) {
                *error = newErrorWithReason([NSString stringWithFormat:@"Argument name '%@' contains an invalid character. Must match /[A-Za-z0-9_]/", name]);
            }
            return NO;
        }
        if ([args containsObject:name]) {
            if (error) {
                *error = newErrorWithReason([NSString stringWithFormat:@"Two arguments share the name '%@'. Argument names must be unique.", name]);
            }
            return NO;
        }
        [args addObject:name];
    }

    return YES;
}

- (NSString *)it_stringRepresentation {
    NSArray<NSString *> *argNames = [self.argumentsArray mapWithBlock:^id(ITMRPCRegistrationRequest_RPCArgumentSignature *anObject) {
        return anObject.name;
    }];
    return iTermFunctionSignatureFromNameAndArguments(self.name, argNames);
}

- (NSSet<NSString *> *)it_allArgumentNames {
    return [NSSet setWithArray:[self.argumentsArray mapWithBlock:^id(ITMRPCRegistrationRequest_RPCArgumentSignature *anObject) {
        return anObject.name;
    }]];
}

- (NSSet<NSString *> *)it_argumentsWithDefaultValues {
    return [NSSet setWithArray:[self.defaultsArray mapWithBlock:^id(ITMRPCRegistrationRequest_RPCArgument *anObject) {
        return anObject.name;
    }]];
}

- (NSSet<NSString *> *)it_requiredArguments {
    NSMutableSet *result = [[self it_allArgumentNames] mutableCopy];
    [result minusSet:[self it_argumentsWithDefaultValues]];
    return result;
}

- (BOOL)it_satisfiesExplicitParameters:(NSDictionary<NSString *, id> *)explicitParameters
                                 scope:(iTermVariableScope *)scope
                        fullParameters:(out NSDictionary<NSString *, id> **)fullParameters {
    NSSet<NSString *> *providedArguments = [NSSet setWithArray:explicitParameters.allKeys];
    NSSet<NSString *> *requiredArguments = [self it_requiredArguments];
    if (![requiredArguments isSubsetOfSet:providedArguments]) {
        // Does not contain all required arguments
        return NO;
    }

    // Make sure all the arguments with defaults can be satisfied by the scope.
    NSMutableDictionary<NSString *, id> *params = [explicitParameters mutableCopy];
    for (ITMRPCRegistrationRequest_RPCArgument *defaultArgument in self.defaultsArray) {
        NSString *name = defaultArgument.name;
        NSString *path = defaultArgument.path;
        BOOL isOptional = NO;
        if ([path hasSuffix:@"?"]) {
            isOptional = YES;
            path = [path substringToIndex:path.length - 1];
        }
        if (params[name]) {
            // An explicit value was provided, which overrides the default.
            continue;
        }
        id value = [scope valueForVariableName:path];
        if (value) {
            params[name] = value;
            continue;
        }
        if (!isOptional) {
            return NO;
        }
        params[name] = [NSNull null];
    }
    *fullParameters = params;
    return YES;
}

@end
