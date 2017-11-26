//
//  iTermTextureMap+CPP.h
//  iTerm2
//
//  Created by George Nachman on 11/7/17.
//

#include <map>
#include <vector>

#import "iTermTextureMap.h"

enum {
    iTermTextureMapStatusGlyphNotRenderable = -1,
    iTermTextureMapStatusOutOfMemory = -2
};

@interface iTermTextureMapStage (CPP)
@property (nonatomic, readonly) std::vector<int> *locks;

// Returns a nonnegative value or one of the statuses declared above.
- (NSInteger)findOrAllocateIndexOfLockedTextureWithKey:(const iTermMetalGlyphKey *)key
                                                column:(int)column
                                             relations:(std::map<int, int> *)relations
                                                 emoji:(BOOL *)emoji
                                              creation:(NSDictionary<NSNumber *, NSImage *> *(NS_NOESCAPE ^)(int x, BOOL *emoji))creation;

@end
