//
//  iTermContextMenuUtilities.h
//  iTerm2
//
//  Created by George Nachman on 6/30/25.
//

#import <AppKit/AppKit.h>
#import "iTermTuple.h"

NS_ASSUME_NONNULL_BEGIN

@interface NSString(ContextMenu)
@property (nonatomic, readonly) NSArray<iTermTuple<NSString *, NSString *> *> *helpfulSynonyms;
@end

@interface iTermContextMenuUtilities: NSObject
+ (BOOL)addMenuItemForColors:(NSString *)shortSelectedText menu:(NSMenu *)theMenu index:(NSInteger)i;
+ (BOOL)addMenuItemForBase64Encoded:(NSString *)shortSelectedText
                               menu:(NSMenu *)theMenu
                              index:(NSInteger)i
                           selector:(SEL)selector
                             target:(id _Nullable)target;

+ (NSInteger)addMenuItemsForNumericConversions:(NSString *)text
                                          menu:(NSMenu *)theMenu
                                         index:(NSInteger)i
                                      selector:(SEL)selector
                                        target:(id _Nullable)target;

+ (NSInteger)addMenuItemsToCopyBase64:(NSString *)text
                                 menu:(NSMenu *)theMenu
                                index:(NSInteger)i
                             selectorForString:(SEL)selectorForString
                      selectorForData:(SEL)selectorForData
                               target:(id _Nullable)target;

@end

NS_ASSUME_NONNULL_END
