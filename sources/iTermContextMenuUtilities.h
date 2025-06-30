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
@end

NS_ASSUME_NONNULL_END
