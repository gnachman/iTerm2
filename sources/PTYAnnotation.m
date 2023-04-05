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
    PTYAnnotation *_doppelganger;
    BOOL _isDoppelganger;
}

@synthesize progenitor = _progenitor;
@synthesize entry = _entry;
@synthesize delegate = _delegate;

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

- (NSString *)shortDebugDescription {
    return [NSString stringWithFormat:@"[Annotation %@]", _stringValue];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p string=%@ %@>",
            NSStringFromClass([self class]),
            self,
            _stringValue,
            _isDoppelganger ? @"IsDop" : @"NotDop"];
}

- (NSDictionary *)dictionaryValue {
    return @{ PTYAnnotationDictionaryKeyText: _stringValue.copy };
}

- (instancetype)copyOfIntervalTreeObject {
    PTYAnnotation *copy = [[PTYAnnotation alloc] init];
    copy.stringValue = _stringValue;
    return copy;
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

- (id<IntervalTreeObject>)doppelganger {
    @synchronized ([PTYAnnotation class]) {
        assert(!_isDoppelganger);
        if (!_doppelganger) {
            _doppelganger = [self copyOfIntervalTreeObject];
            _doppelganger->_progenitor = self;
            _doppelganger->_isDoppelganger = YES;
        }
        return _doppelganger;
    }
}

- (id<PTYAnnotationReading>)progenitor {
    @synchronized ([PTYAnnotation class]) {
        return _progenitor;
    }
}

@end

