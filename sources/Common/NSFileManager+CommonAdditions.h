//
//  NSFileManager+CommonAdditions.h
//  iTerm2
//
//  Created by George Nachman on 2/24/22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSFileManager (CommonAdditions)

// Returns YES if the file exists on a local (non-network) filesystem.
- (BOOL)fileExistsAtPathLocally:(NSString *)filename
         additionalNetworkPaths:(NSArray<NSString *> *)additionalNetworkpaths
             allowNetworkMounts:(BOOL)allowNetworkMounts;

- (BOOL)fileHasForbiddenPrefix:(NSString *)filename
        additionalNetworkPaths:(NSArray<NSString *> *)additionalNetworkpaths;

- (BOOL)fileIsLocal:(NSString *)filename
additionalNetworkPaths:(NSArray<NSString *> *)additionalNetworkPaths
 allowNetworkMounts:(BOOL)allowNetworkMounts;

@end

NS_ASSUME_NONNULL_END
