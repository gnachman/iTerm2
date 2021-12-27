//
//  PTYAnnotation.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/26/21.
//

#import "PTYAnnotation.h"

static NSString *const PTYAnnotationDictionaryKeyText = @"Text";

@implementation PTYAnnotation {
    BOOL _deferHide;
}

@synthesize entry = _entry;
- (instancetype)init {
    self = [super init];
    if (self) {
        _stringValue = @"";
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [self init];
    if (self) {
        _stringValue = [dict[PTYAnnotationDictionaryKeyText] copy] ?: @"";
    }
    return self;
}

- (NSDictionary *)dictionaryValue {
    return @{ PTYAnnotationDictionaryKeyText: _stringValue.copy };
}

- (instancetype)copyOfIntervalTreeObject {
    return [[PTYAnnotation alloc] initWithDictionary:self.dictionaryValue];
}

- (void)hide {
    if (!self.delegate) {
        _deferHide = YES;
        return;
    }
    [self.delegate annotationDidRequestHide:self];
}

- (void)setDelegate:(id<PTYAnnotationDelegate>)delegate {
    if (delegate == _delegate) {
        return;
    }
    _delegate = delegate;
    if (delegate && _deferHide) {
        _deferHide = NO;
        [delegate annotationDidRequestHide:self];
    }
}

- (void)setStringValue:(NSString *)stringValue {
    _stringValue = [stringValue copy];
    [_delegate annotationStringDidChange:self];
}

- (void)setStringValueWithoutSideEffects:(NSString *)value {
    _stringValue = [value copy];
}

- (void)willRemove {
    [_delegate annotationWillBeRemoved:self];
}

@end
