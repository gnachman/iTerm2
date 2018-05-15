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

- (NSString *)paramPlaceholder
{
    return [self paramDefault];
}

- (NSString *)paramDefault
{
    return @"https://\\0";
}

- (BOOL)performActionWithCapturedStrings:(NSString *const *)capturedStrings
                          capturedRanges:(const NSRange *)capturedRanges
                            captureCount:(NSInteger)captureCount
                               inSession:(PTYSession *)aSession
                                onString:(iTermStringLine *)stringLine
                    atAbsoluteLineNumber:(long long)lineNumber
                                    stop:(BOOL *)stop {
    NSRange rangeInString = capturedRanges[0];
    
    NSString *urlString = [self paramWithBackreferencesReplacedWithValues:capturedStrings
                                                                     count:captureCount];
    
    NSURL *url = urlString.length ? [NSURL URLWithUserSuppliedString:urlString] : nil;

    if (url == nil) {
        return NO;
    }
    
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
    
    
    return YES;
}
@end
