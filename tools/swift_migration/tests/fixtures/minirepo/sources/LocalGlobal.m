#import <Foundation/Foundation.h>

int gLocalCounter = 0;

void LocalHelper(id obj, SEL sel, const char *cname) {
    gLocalCounter++;
    NSLock *lock = [[NSLock alloc] init];
    dispatch_async(dispatch_get_main_queue(), ^{
        [lock lock];
    });
    SEL a = sel_registerName("fixedName");
    SEL b = sel_getUid(cname);
    SEL c = @selector(performSelector:withObject:);
    [obj performSelector:@selector(description)];
    [obj performSelector:sel withObject:nil];
}

#import "ButtonStyle.h"

void LocalDispatch(id obj, SEL sel, NSInvocation *inv) {
    [obj it_performNonObjectReturningSelector:sel withObject:nil];
    [obj fixture_dispatch:sel onTarget:obj];
    [obj fixture_dispatch:@selector(description) onTarget:obj];
    [NSApp sendAction:sel to:nil from:nil];
    IMP imp = [obj methodForSelector:sel];
    [inv setSelector:sel];
    [NSTimer scheduledTimerWithTimeInterval:1 target:obj selector:sel userInfo:nil repeats:NO];
    objc_msgSend(obj, sel);
    objc_msgSend(obj, @selector(description));
    LocalHelper(obj, sel, "name");
    LocalHelper(obj, @selector(description), "name");
    NSMenuItem *item = nil;
    item.action = sel;
    item.action = @selector(description);
    [item setAction:sel];
    [item setDoubleAction:sel];
}
