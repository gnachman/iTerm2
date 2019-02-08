//
//  iTermHyperlinkTrigger.m
//  iTerm2
//
//  Created by leppich on 09.05.18.
//

#import "PTYScrollView.h"
#import "PTYSession.h"
#import "VT100Screen.h"
#import "iTermURLMark.h"
#import "iTermURLStore.h"
#import "NSURL+iTerm.h"
#import "iTermHyperlinkTrigger.h"

#import <CoreServices/CoreServices.h>
#import <QuartzCore/QuartzCore.h>

@implementation iTermHyperlinkTrigger

+ (NSString *)title {
    return @"Make Hyperlink…";
}

- (BOOL)takesParameter {
    return YES;
}

- (NSString *)triggerOptionalParameterPlaceholderWithInterpolation:(BOOL)interpolation {
    return [self triggerOptionalDefaultParameterValueWithInterpolation:interpolation];
}

- (NSString *)triggerOptionalDefaultParameterValueWithInterpolation:(BOOL)interpolation {
    if (interpolation) {
        return @"https://\\(match0)";
    }
    return @"https://\\0";
}

- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(PTYSession *)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                        useInterpolation:(BOOL)useInterpolation
                                    stop:(BOOL *)stop {
    const NSRange rangeInString = capturedRanges[0];
    
    [self paramWithBackreferencesReplacedWithValues:capturedStrings
                                              count:captureCount
                                              scope:aSession.variablesScope
                                   useInterpolation:useInterpolation
                                         completion:^(NSString *urlString) {
                                             [self performActionWithURLString:urlString
                                                                        range:rangeInString
                                                                      session:aSession
                                                           absoluteLineNumber:lineNumber];
                                         }];
    return YES;
}

- (void)performActionWithURLString:(NSString *)urlString
                             range:(NSRange)rangeInString
                           session:(PTYSession *)aSession
                absoluteLineNumber:(long long)lineNumber {
    NSURL *url = urlString.length ? [NSURL URLWithUserSuppliedString:urlString] : nil;

    // add URL to URL Store and retrieve URL code for later reference
    unsigned short code = [[iTermURLStore sharedInstance] codeForURL:url withParams:@""];
    
    // add url link to screen
    [[aSession screen] linkTextInRange:rangeInString
             basedAtAbsoluteLineNumber:lineNumber
                               URLCode:code];
    
    // add invisible URL Mark so the URL can automatically freed
    iTermURLMark *mark = [aSession.screen addMarkStartingAtAbsoluteLine:lineNumber
                                                                oneLine:YES
                                                                ofClass:[iTermURLMark class]];
    mark.code = code;
}

@end
