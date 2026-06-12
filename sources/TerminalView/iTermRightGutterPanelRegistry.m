//
//  iTermRightGutterPanelRegistry.m
//  iTerm2
//

#import "iTermRightGutterPanelRegistry.h"

@interface iTermRightGutterPanelRegistration : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) iTermRightGutterPanelFactory factory;
@property (nonatomic, copy) iTermRightGutterPanelWidthProvider widthProvider;
@end

@implementation iTermRightGutterPanelRegistration
@end

@implementation iTermRightGutterPanelRegistry {
    NSMutableArray<iTermRightGutterPanelRegistration *> *_registrations;
}

+ (instancetype)sharedInstance {
    static iTermRightGutterPanelRegistry *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[iTermRightGutterPanelRegistry alloc] init];
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

- (NSInteger)indexOfRegistrationWithIdentifier:(NSString *)identifier {
    for (NSInteger i = 0; i < (NSInteger)_registrations.count; i++) {
        if ([_registrations[i].identifier isEqualToString:identifier]) {
            return i;
        }
    }
    return NSNotFound;
}

- (void)registerPanelType:(NSString *)identifier
                  factory:(iTermRightGutterPanelFactory)factory
            widthProvider:(iTermRightGutterPanelWidthProvider)widthProvider {
    iTermRightGutterPanelRegistration *registration = [[iTermRightGutterPanelRegistration alloc] init];
    registration.identifier = [identifier copy];
    registration.factory = [factory copy];
    registration.widthProvider = [widthProvider copy];

    const NSInteger existing = [self indexOfRegistrationWithIdentifier:identifier];
    if (existing == NSNotFound) {
        [_registrations addObject:registration];
    } else {
        _registrations[existing] = registration;
    }
}

- (NSArray<NSString *> *)enabledPanelIdentifiersForProfile:(Profile *)profile
                                                   session:(PTYSession *)session {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (iTermRightGutterPanelRegistration *registration in _registrations) {
        if (registration.widthProvider(profile, session) > 0) {
            [result addObject:registration.identifier];
        }
    }
    return result;
}

- (CGFloat)totalWidthForProfile:(Profile *)profile
                        session:(PTYSession *)session {
    CGFloat total = 0;
    for (iTermRightGutterPanelRegistration *registration in _registrations) {
        const CGFloat w = registration.widthProvider(profile, session);
        if (w > 0) {
            total += w;
        }
    }
    return total;
}

- (id<iTermRightGutterPanel>)createPanelWithIdentifier:(NSString *)identifier {
    const NSInteger index = [self indexOfRegistrationWithIdentifier:identifier];
    if (index == NSNotFound) {
        return nil;
    }
    return _registrations[index].factory();
}

@end
