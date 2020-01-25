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
#import "iTermExpect.h"
#import "iTermExpressionEvaluator.h"
#import "iTermProfilePreferences.h"
#import "iTermVariableScope.h"
#import "iTermWarning.h"
#import "NSStringITerm.h"
#import "PTYSession.h"

@interface PTYSession(Private)
@property(nonatomic, retain) iTermExpectation *pasteBracketingOopsieExpectation;
- (void)offerToTurnOffBracketedPasteOnHostChange;
@end

@implementation PTYSession (ARC)

- (void)fetchAutoLogFilenameWithCompletion:(void (^)(NSString *filename))completion {
    [self setTermIDIfPossible];
    if (![self.profile[KEY_AUTOLOG] boolValue]) {
        completion(nil);
        return;
    }

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"yyyyMMdd_HHmmss";
    NSString *format = [iTermAdvancedSettingsModel autoLogFormat];
    iTermExpressionEvaluator *evaluator = [[iTermExpressionEvaluator alloc] initWithInterpolatedString:format scope:self.variablesScope];
    [evaluator evaluateWithTimeout:5
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

- (void)setTermIDIfPossible {
    if (self.delegate.tabNumberForItermSessionId >= 0) {
        [self.variablesScope setValue:[self.sessionId stringByReplacingOccurrencesOfString:@":" withString:@"."]
                     forVariableNamed:iTermVariableKeySessionTermID];
    }
}

- (void)watchForPasteBracketingOopsieWithPrefix:(NSString *)prefix {
    NSString *const redflag = @"00~";

    if ([prefix hasPrefix:redflag]) {
        return;
    }
    __weak __typeof(self) weakSelf = self;
    self.pasteBracketingOopsieExpectation =
    [self.expect expectRegularExpression:[NSString stringWithFormat:@"(%@)?%@", redflag, prefix.it_escapedForRegex]
                              completion:^(NSArray<NSString *> * _Nonnull captureGroups) {
        if ([captureGroups[1] isEqualToString:redflag]) {
            [weakSelf didFindPasteBracketingOopsie];
        }
    }];
    [self.expect setTimeout:0.5 forExpectation:self.pasteBracketingOopsieExpectation];
}

- (void)didFindPasteBracketingOopsie {
    [self.expect cancelExpectation:self.pasteBracketingOopsieExpectation];
    [self offerToTurnOffBracketedPasteOnHostChange];
 }

@end
