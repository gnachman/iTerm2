//
//  LineBlock+SwiftInterop.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/29/24.
//

#import <Foundation/Foundation.h>
#import "LineBlock.h"

@class iTermBidiDisplayInfo;

NS_ASSUME_NONNULL_BEGIN

@interface LineBlock(SwiftInterop)

- (NSData * _Nullable)decompressedDataFromV4Data:(NSData *)v4data;
- (void)sanityCheckBidiDisplayInfoForRawLine:(int)i;
- (void)reallyReloadBidiInfo;
// YES if any raw line has RTL content or a non-nil bidi info, i.e. reloadBidiInfo
// would actually do something. Lets callers skip the (COW-cloning) reload entirely
// when there is nothing to recompute.
- (BOOL)anyLineNeedsBidiReload;
- (iTermBidiDisplayInfo * _Nullable)_bidiInfoForLineNumber:(int)lineNum width:(int)width;
- (iTermBidiDisplayInfo * _Nullable)subBidiInfo:(iTermBidiDisplayInfo *)bidi
                                          range:(NSRange)range
                                          width:(int)width;

@end

NS_ASSUME_NONNULL_END
