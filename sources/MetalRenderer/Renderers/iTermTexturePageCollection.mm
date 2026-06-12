//
//  iTermTexturePageCollection.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/26/17.
//

#import "iTermTexturePageCollection.h"

@implementation iTermTexturePageCollectionSharedPointer

- (instancetype)initWithObject:(iTerm2::TexturePageCollection *)object {
    self = [super init];
    if (self) {
        _object = object;
    }
    return self;
}

- (void)dealloc {
    if (_object) {
        delete _object;
    }
}

@end
