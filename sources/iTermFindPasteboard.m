//
//  iTermFindPasteboard.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/22/20.
//

#import "iTermFindPasteboard.h"

#import "DebugLogging.h"
#import "iTermSearchQueryDidChangeNotification.h"

#import <Cocoa/Cocoa.h>

@implementation iTermFindPasteboard

+ (instancetype)sharedInstance {
    static iTermFindPasteboard *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[iTermFindPasteboard alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowDidBecomeKey:)
                                                     name:NSWindowDidBecomeKeyNotification
                                                   object:nil];
    }
    return self;
}

- (void)setStringValue:(NSString *)stringValue {
    DLog(@"Set string value to %@\n%@", stringValue, [NSThread callStackSymbols]);
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName:NSPasteboardNameFind];
    if (pasteboard) {
        [pasteboard declareTypes:[NSArray arrayWithObject:NSPasteboardTypeString] owner:nil];
        [pasteboard setString:stringValue ?: @"" forType:NSPasteboardTypeString];
    }
}

- (NSString *)stringValue {
    NSPasteboard *findBoard = [NSPasteboard pasteboardWithName:NSPasteboardNameFind];
    if (![[findBoard types] containsObject:NSPasteboardTypeString]) {
        return @"";
    }
    return [findBoard stringForType:NSPasteboardTypeString] ?: @"";
}

- (void)updateObservers:(id _Nullable)sender {
    [[iTermSearchQueryDidChangeNotification notificationWithSender:sender] post];
}

- (void)addObserver:(id)observer block:(void (^)(id sender, NSString *newValue))block {
    __weak __typeof(self) weakSelf = self;
    [iTermSearchQueryDidChangeNotification subscribe:observer block:^(id sender) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        block(sender, strongSelf.stringValue);
    }];
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    [self updateObservers:nil];
}

@end
