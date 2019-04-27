//
//  PTYSession+ARC.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/19.
//

#import "PTYSession+ARC.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermExpressionEvaluator.h"
#import "iTermProfilePreferences.h"
#import "iTermWarning.h"

@implementation PTYSession (ARC)

- (void)fetchAutoLogFilenameSynchronously:(BOOL)synchronous
                               completion:(void (^)(NSString *filename))completion {
    if (![self.profile[KEY_AUTOLOG] boolValue]) {
        completion(nil);
        return;
    }

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"yyyyMMdd_HHmmss";
    NSString *format = [iTermAdvancedSettingsModel autoLogFormat];
    iTermExpressionEvaluator *evaluator = [[iTermExpressionEvaluator alloc] initWithInterpolatedString:format scope:self.variablesScope];
    [evaluator evaluateWithTimeout:synchronous ? 0 : 5
                        completion:^(iTermExpressionEvaluator * _Nonnull evaluator) {
        if (evaluator.error) {
            NSString *message = [NSString stringWithFormat:@"Cannot start logging to session with profile “%@”: %@",
                                 self.profile[KEY_NAME],
                                 evaluator.error.localizedDescription];
            [iTermWarning showWarningWithTitle:message
                                       actions:@[ @"OK" ]
                                     accessory:nil
                                    identifier:@"NoSyncCannotStartLogging"
                                   silenceable:kiTermWarningTypePersistent
                                       heading:@"Session Logging Problem"
                                        window:nil];
            completion(nil);
            return;
        }
        NSString *name = [evaluator.value stringByReplacingOccurrencesOfString:@"/" withString:@"__"];
        NSString *folder = [iTermProfilePreferences stringForKey:KEY_LOGDIR inProfile:self.profile];
        NSString *filename = [folder stringByAppendingPathComponent:name];
        DLog(@"Using autolog filename %@ from format %@", filename, format);
        completion(filename);
    }];
}

@end
