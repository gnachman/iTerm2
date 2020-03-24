//
//  iTermFindPasteboard.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/22/20.
//

#import "iTermFindPasteboard.h"
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
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName:NSFindPboard];
    if (pasteboard) {
        [pasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
        [pasteboard setString:stringValue ?: @"" forType:NSStringPboardType];
    }
}

- (NSString *)stringValue {
    NSPasteboard *findBoard = [NSPasteboard pasteboardWithName:NSFindPboard];
    if (![[findBoard types] containsObject:NSStringPboardType]) {
        return @"";
    }
    return [findBoard stringForType:NSStringPboardType] ?: @"";
}

- (void)updateObservers {
    [[iTermSearchQueryDidChangeNotification notification] post];
}

- (void)addObserver:(id)observer block:(void (^)(NSString *newValue))block {
    __weak __typeof(self) weakSelf = self;
    [iTermSearchQueryDidChangeNotification subscribe:observer block:^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        block(strongSelf.stringValue);
    }];
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    [self updateObservers];
}

@end
