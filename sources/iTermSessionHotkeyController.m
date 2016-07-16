//
//  iTermSessionHotkeyController.m
//  iTerm2
//
//  Created by George Nachman on 6/27/16.
//
//

#import "iTermSessionHotkeyController.h"

#import "DebugLogging.h"
#import "iTermCarbonHotKeyController.h"
#import "NSArray+iTerm.h"

@interface iTermSessionHotkeyRegistration : NSObject
@property(nonatomic, readonly) iTermShortcut *shortcut;
@property(nonatomic, retain) NSMutableArray<iTermWeakReference<id<iTermHotKeyNavigableSession>> *> *weakSessions;

- (instancetype)initWithShortcut:(iTermShortcut *)shortcut NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (NSUInteger)indexOfSession:(id<iTermHotKeyNavigableSession>)session;
- (void)unregister;

@end

@implementation iTermSessionHotkeyRegistration {
    __unsafe_unretained iTermHotKey *_hotKey;
}

- (instancetype)initWithShortcut:(iTermShortcut *)shortcut {
    self = [super init];
    if (self) {
        _shortcut = [shortcut retain];
        _weakSessions = [[NSMutableArray alloc] init];
        _hotKey = [[iTermCarbonHotKeyController sharedInstance] registerShortcut:shortcut
                                                                          target:self
                                                                        selector:@selector(hotkeyPressed:siblings:)
                                                                        userData:nil];
    }
    return self;
}

- (void)dealloc {
    assert(!_hotKey);
    [_weakSessions release];
    [_shortcut release];
    [super dealloc];
}

- (void)unregister {
    [[iTermCarbonHotKeyController sharedInstance] unregisterHotKey:_hotKey];
    _hotKey = nil;
}

- (NSUInteger)indexOfSession:(id<iTermHotKeyNavigableSession>)session {
    __block NSUInteger result = NSNotFound;
    [_weakSessions enumerateObjectsUsingBlock:^(iTermWeakReference<id<iTermHotKeyNavigableSession>> * _Nonnull obj,
                                                NSUInteger idx,
                                                BOOL * _Nonnull stop) {
        if (obj.weaklyReferencedObject == session) {
            result = idx;
            *stop = YES;
        }
    }];
    return result;
}

- (void)hotkeyPressed:(NSDictionary *)userData siblings:(NSArray *)siblings {
    NSUInteger index = [self.weakSessions indexOfObjectPassingTest:^BOOL(iTermWeakReference<id<iTermHotKeyNavigableSession>> * _Nonnull obj,
                                                                         NSUInteger idx,
                                                                         BOOL * _Nonnull stop) {
        return [obj.weaklyReferencedObject sessionHotkeyIsAlreadyFirstResponder];
    }];

    id<iTermHotKeyNavigableSession> session = self.weakSessions.firstObject.weaklyReferencedObject;
    if (index != NSNotFound) {
        NSUInteger next = (index + 1) % self.weakSessions.count;
        session = [self.weakSessions[next] weaklyReferencedObject];
    } else {
        index = [self.weakSessions indexOfObjectPassingTest:^BOOL(iTermWeakReference<id<iTermHotKeyNavigableSession>> * _Nonnull obj,
                                                                  NSUInteger idx,
                                                                  BOOL * _Nonnull stop) {
            return [obj.weaklyReferencedObject sessionHotkeyIsAlreadyActiveInNonkeyWindow];
        }];
        if (index != NSNotFound) {
            session = [self.weakSessions[index] weaklyReferencedObject];
        }
    }
    [session sessionHotkeyDidNavigateToSession:self.shortcut];
}

@end

@implementation iTermSessionHotkeyController {
    NSMutableArray<iTermSessionHotkeyRegistration *> *_registrations;
}

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static id instance;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _registrations = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_registrations release];
    [super dealloc];
}

- (iTermSessionHotkeyRegistration *)registrationForSession:(id<iTermHotKeyNavigableSession>)session index:(NSUInteger *)index {
    for (iTermSessionHotkeyRegistration *registration in _registrations) {
        *index = [registration indexOfSession:session];
        if (*index != NSNotFound) {
            return registration;
        }
    }
    return nil;
}

- (iTermSessionHotkeyRegistration *)registrationForShortcut:(iTermShortcut *)shortcut {
    NSUInteger index = [_registrations indexOfObjectPassingTest:^BOOL(iTermSessionHotkeyRegistration * _Nonnull obj,
                                                                      NSUInteger idx,
                                                                      BOOL * _Nonnull stop) {
        return [obj.shortcut isEqualToShortcut:shortcut];
    }];
    if (index == NSNotFound) {
        return nil;
    } else {
        return _registrations[index];
    }
}

- (void)setShortcut:(iTermShortcut *)shortcut forSession:(id<iTermHotKeyNavigableSession>)session {
    [self removeSession:session];
    
    if (shortcut) {
        iTermSessionHotkeyRegistration *registration = [self registrationForShortcut:shortcut];
        if (!registration) {
            registration = [[[iTermSessionHotkeyRegistration alloc] initWithShortcut:shortcut] autorelease];
            [_registrations addObject:registration];
        }
        [registration.weakSessions addObject:session.weakSelf];
    }
}

- (void)removeSession:(id<iTermHotKeyNavigableSession>)session {
    NSUInteger index;
    iTermSessionHotkeyRegistration *registration = [self registrationForSession:session index:&index];
    if (registration) {
        [registration.weakSessions removeObjectAtIndex:index];
    }
    if (registration.weakSessions.count == 0) {
        [registration unregister];
        [_registrations removeObject:registration];
    }
}

- (iTermShortcut *)shortcutForSession:(id<iTermHotKeyNavigableSession>)session {
    NSUInteger index;
    iTermSessionHotkeyRegistration *registration = [self registrationForSession:session index:&index];
    return registration.shortcut;
}

@end
