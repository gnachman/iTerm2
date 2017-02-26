//
//  iTermFakeUserDefaults.m
//  iTerm2
//
//  Created by George Nachman on 2/25/17.
//
//

#import "iTermFakeUserDefaults.h"

@implementation iTermFakeUserDefaults {
    NSMutableDictionary *_fakeObjects;
}

- (void)dealloc {
    [_fakeObjects release];
    [super dealloc];
}

- (NSMutableDictionary *)fakeObjects {
    if (!_fakeObjects) {
        _fakeObjects = [[NSMutableDictionary alloc] init];
    }
    return _fakeObjects;
}

- (void)setFakeObject:(id)object forKey:(id)key {
    self.fakeObjects[key] = object;
}

- (id)objectForKey:(NSString *)defaultName {
    if (_fakeObjects[defaultName]) {
        return _fakeObjects[defaultName];
    }
    return [super objectForKey:defaultName];
}

@end
