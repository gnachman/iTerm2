//
//  iTermTouchbarMappings.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/21/20.
//

#import <Foundation/Foundation.h>

#import "iTermKeyBindingAction.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermTouchbarItem;

@interface iTermTouchbarMappings : NSObject

// Returns the global touchbar map ("touchbar:uuid" -> (Action=int, [Text=str])
+ (NSDictionary *)globalTouchBarMap;

// Replace the global touchbar map with a new dictionary.
+ (void)setGlobalTouchBarMap:(NSDictionary*)src;

+ (void)removeTouchbarItem:(iTermTouchbarItem *)item;

+ (NSArray<iTermTouchbarItem *> *)sortedTouchbarItemsInDictionary:(NSDictionary<NSString *, NSDictionary *> *)dict;

+ (NSDictionary *)dictionaryByRemovingTouchbarItem:(iTermTouchbarItem *)item
                                    fromDictionary:(NSDictionary *)dictionary;

+ (void)updateDictionary:(NSMutableDictionary *)dict
         forTouchbarItem:(iTermTouchbarItem *)touchbarItem
                  action:(iTermKeyBindingAction *)action;

@end

NS_ASSUME_NONNULL_END
