//
//  iTermBetaAssertionTestObserverLoader.m
//  ModernTests
//
//  Registers iTermBetaAssertionTestObserver (Swift) when the test bundle loads, so that a failed
//  Swift beta assertion fails the running test instead of crashing the test host. Swift has no
//  +load, and the observer must be in place before the first test runs.
//

#import <Foundation/Foundation.h>

@protocol iTermBetaAssertionTestObserverRegistering
+ (void)registerObserver;
@end

@interface iTermBetaAssertionTestObserverLoader : NSObject
@end

@implementation iTermBetaAssertionTestObserverLoader

+ (void)load {
    Class observerClass = NSClassFromString(@"iTermBetaAssertionTestObserver");
    if (!observerClass) {
        // Without the observer a failed beta assertion crashes the test host, which still fails
        // the run, only less clearly. Say why.
        NSLog(@"iTermBetaAssertionTestObserver is missing; failed beta assertions will crash the test host");
        return;
    }
    [(Class<iTermBetaAssertionTestObserverRegistering>)observerClass registerObserver];
}

@end
