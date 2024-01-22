//
//  iTermMissionControlHacks.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/22/20.
//

#import "iTermMissionControlHacks.h"
#import "iTermNotificationController.h"
#import "NSObject+iTerm.h"

@implementation iTermMissionControlHacks

+ (CGEventRef)newEventToSwitchToSpace:(int)spaceNum  // 1 indexed
                                 down:(BOOL)down {
    NSUserDefaults *userDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.apple.symbolichotkeys"];
    const NSInteger action = 118 + spaceNum - 1;
    NSDictionary *dict = [NSDictionary castFrom:[userDefaults objectForKey:@"AppleSymbolicHotKeys"]];
    if (!dict) {
        return nil;
    }
    dict = [NSDictionary castFrom:dict[@(action)]] ?: [NSDictionary castFrom:dict[@(action).stringValue]];
    if (!dict) {
        return nil;
    }
    NSNumber *enabled = [NSNumber castFrom:dict[@"enabled"]];
    if (!enabled || !enabled.boolValue) {
        return nil;
    }
    dict = [NSDictionary castFrom:dict[@"value"]];
    if (!dict) {
        return nil;
    }
    if (![dict[@"type"] isEqual:@"standard"]) {
        return nil;
    }
    NSArray *parameters = [NSArray castFrom:dict[@"parameters"]];
    if (!parameters || parameters.count < 3) {
        return nil;
    }
    NSNumber *keycode = [NSNumber castFrom:parameters[1]];
    if (!keycode) {
        return nil;
    }
    NSNumber *modifiers = [NSNumber castFrom:parameters[2]];
    if (!modifiers) {
        return nil;
    }
    CGEventRef event = CGEventCreateKeyboardEvent (NULL, (CGKeyCode)keycode.unsignedShortValue, down);
    CGEventSetFlags(event, modifiers.unsignedLongLongValue);
    return event;
}

+ (void)complainThatCantSwitchToSpace:(int)spaceNum fix:(NSString *)fix {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[iTermNotificationController sharedInstance] notify:[NSString stringWithFormat:@"Can’t switch to desktop %d", spaceNum]
                                             withDescription:fix];
    });
}

+ (void)switchToSpace:(int)spaceNum {
    if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge id)kAXTrustedCheckOptionPrompt: @YES})) {
        [self complainThatCantSwitchToSpace:spaceNum
                                        fix:@"You must grant iTerm2 accessibility permission in System Settings > Security & Privacy."];
        return;
    }
    CGEventRef keyDownEvent = [self newEventToSwitchToSpace:spaceNum down:YES];
    CGEventRef keyUpEvent = [self newEventToSwitchToSpace:spaceNum down:NO];
    if (!keyDownEvent || !keyUpEvent) {
        [self complainThatCantSwitchToSpace:spaceNum
                                        fix:@"You must enable shortcuts to switch desktops in System Settings > Keyboard."];
        if (keyDownEvent) {
            CFRelease(keyDownEvent);
        }
        if (keyUpEvent) {
            CFRelease(keyUpEvent);
        }
        return;
    }
    CGEventPost(kCGSessionEventTap, keyDownEvent);
    CFRelease(keyDownEvent);

    CGEventPost(kCGSessionEventTap, keyUpEvent);
    CFRelease(keyUpEvent);

    // Give the space-switching animation time to get started; otherwise a window opened
    // subsequent to this will appear in the previous space. This is short enough of a
    // delay that it's not annoying when you're already there.
    [NSThread sleepForTimeInterval:0.3];

    [NSApp activateIgnoringOtherApps:YES];
}

@end
