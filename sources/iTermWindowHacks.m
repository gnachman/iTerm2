//
//  iTermWindowHacks.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/21/18.
//

#import "iTermWindowHacks.h"

@implementation iTermWindowHacks

void WindowListApplierFunction(const void *inputDictionary, void *context) {
    NSDictionary *entry = (__bridge NSDictionary*)inputDictionary;
    BOOL *foundPtr = (BOOL *)context;
    NSString *name = entry[(NSString *)kCGWindowOwnerName];
    if ([name isEqualToString:@"Emoji & Symbols"]) {
        NSNumber *level = entry[(NSString *)kCGWindowLayer];
        int n = level.integerValue;
        *foundPtr = (n == 20);
    }
}

+ (BOOL)isCharacterPanelOpen {
    CGWindowListOption listOptions;
    listOptions = kCGWindowListOptionOnScreenOnly;
    BOOL found = NO;
    CFArrayRef windowList = CGWindowListCopyWindowInfo(listOptions, kCGNullWindowID);
    CFArrayApplyFunction(windowList,
                         CFRangeMake(0,
                                     CFArrayGetCount(windowList)),
                         &WindowListApplierFunction,
                         (void *)&found);
    CFRelease(windowList);
    return found;
}

+ (void)pollForCharacterPanelToOpenOrCloseWithCompletion:(BOOL (^)(BOOL))block {
    __block NSTimer *timer;
    timer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer * _Nonnull timer) {
        if (!block([self isCharacterPanelOpen])) {
            [timer invalidate];
        }
    }];
}

@end
