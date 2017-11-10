//
//  iTermTextureMap+CPP.h
//  iTerm2
//
//  Created by George Nachman on 11/7/17.
//

#include <map>
#include <vector>

#import "iTermTextureMap.h"

@interface iTermTextureMap (CPP)
- (void)unlockIndexes:(const std::vector<int> &)indexes;
@end

@interface iTermTextureMapStage (CPP)

- (NSInteger)findOrAllocateIndexOfLockedTextureWithKey:(const iTermMetalGlyphKey *)key
                                                column:(int)column
                                             relations:(std::map<int, int> *)relations
                                                 emoji:(BOOL *)emoji
                                              creation:(NSDictionary<NSNumber *, NSImage *> *(NS_NOESCAPE ^)(int x, BOOL *emoji))creation;

@end
