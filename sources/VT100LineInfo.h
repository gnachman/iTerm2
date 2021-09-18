//
//  VT100LineInfo.h
//  iTerm
//
//  Created by George Nachman on 11/17/13.
//
//

#import <Foundation/Foundation.h>
#import "ScreenChar.h"
#import "VT100GridTypes.h"
#import "iTermMetadata.h"

@interface VT100LineInfo : NSObject <NSCopying>

@property(nonatomic) iTermMetadata metadata;
@property(nonatomic, readonly) NSInteger generation;

- (instancetype)initWithWidth:(int)width;
- (void)setDirty:(BOOL)dirty inRange:(VT100GridRange)range updateTimestamp:(BOOL)updateTimestamp;
- (BOOL)isDirtyAtOffset:(int)x;
- (BOOL)anyCharIsDirty;
- (VT100GridRange)dirtyRange;
- (NSIndexSet *)dirtyIndexes;
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)decodeMetadataArray:(NSArray *)array;
- (void)resetMetadata;
- (NSArray *)encodedMetadata;
- (iTermExternalAttributeIndex *)externalAttributesCreatingIfNeeded:(BOOL)create;

@end
