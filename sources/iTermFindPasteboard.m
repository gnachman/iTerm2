//
//  iTermFindPasteboard.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/22/20.
//

#import "iTermFindPasteboard.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermSearchQueryDidChangeNotification.h"

#import <Cocoa/Cocoa.h>

@implementation iTermFindPasteboard {
    NSString *_localValue;
}

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

- (BOOL)setStringValueIfAllowed:(NSString *)stringValue {
    DLog(@"Set string value to %@\n%@", stringValue, [NSThread callStackSymbols]);

    const NSInteger maxLength = 10 * 1024;
    if (stringValue.length > maxLength) {
        DLog(@"Refusing to set find pasteboard to a string longer than %@", @(maxLength));
        return NO;
    }
    _localValue = [stringValue copy];
    if (![iTermAdvancedSettingsModel synchronizeQueryWithFindPasteboard]) {
        return NO;
    }
    [self reallySetStringValueUnconditionally:stringValue];
    return YES;
}

- (void)setStringValueUnconditionally:(NSString *)stringValue {
    _localValue = [stringValue copy];
    [self reallySetStringValueUnconditionally:stringValue];
}

- (void)reallySetStringValueUnconditionally:(NSString *)stringValue {
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName:NSPasteboardNameFind];
    [pasteboard declareTypes:[NSArray arrayWithObject:NSPasteboardTypeString] owner:nil];
    [pasteboard setString:stringValue ?: @"" forType:NSPasteboardTypeString];
}

- (NSString *)stringValue {
    if (![iTermAdvancedSettingsModel synchronizeQueryWithFindPasteboard]) {
        return _localValue ?: @"";
    }
    NSPasteboard *findBoard = [NSPasteboard pasteboardWithName:NSPasteboardNameFind];
    if (![[findBoard types] containsObject:NSPasteboardTypeString]) {
        return @"";
    }
    return [findBoard stringForType:NSPasteboardTypeString] ?: @"";
}

- (void)updateObservers:(id _Nullable)sender internallyGenerated:(BOOL)internallyGenerated {
    [[iTermSearchQueryDidChangeNotification notificationWithSender:sender
                                               internallyGenerated:internallyGenerated] post];
}

- (void)addObserver:(id)observer block:(void (^)(id sender, NSString *newValue, BOOL internallyGenerated))block {
    __weak __typeof(self) weakSelf = self;
    [iTermSearchQueryDidChangeNotification subscribe:observer block:^(id sender, BOOL internallyGenerated) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        block(sender, strongSelf.stringValue, internallyGenerated);
    }];
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    [self updateObservers:nil internallyGenerated:NO];
}

@end
