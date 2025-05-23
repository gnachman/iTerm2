//
//  iTermTextDataSource.h
//  iTerm2
//
//  Created by George Nachman on 2/15/22.
//

#import "ScreenCharArray.h"
#import "iTermMetadata.h"

@protocol VT100ScreenMarkReading;
@protocol iTermExternalAttributeIndexReading;
@class iTermBidiDisplayInfo;

NS_ASSUME_NONNULL_BEGIN

@protocol iTermTextDataSource <NSObject>

- (int)width;
- (int)numberOfLines;
// Deprecated - use fetchLine:block: instead because it manages the lifetime of the ScreenCharArray safely.
- (ScreenCharArray *)screenCharArrayForLine:(int)line;
- (ScreenCharArray *)screenCharArrayAtScreenIndex:(int)index;
- (long long)totalScrollbackOverflow;
- (id<iTermExternalAttributeIndexReading> _Nullable)externalAttributeIndexForLine:(int)y;
- (id _Nullable)fetchLine:(int)line block:(id _Nullable (^ NS_NOESCAPE)(ScreenCharArray *sct))block;
- (NSDate * _Nullable)dateForLine:(int)line;
- (id<VT100ScreenMarkReading> _Nullable)commandMarkAt:(VT100GridCoord)coord
                                      mustHaveCommand:(BOOL)mustHaveCommand
                                                range:(out nullable VT100GridWindowedRange *)range;
- (iTermImmutableMetadata)metadataOnLine:(int)lineNumber;

@end

NS_ASSUME_NONNULL_END
