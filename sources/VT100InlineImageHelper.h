//
//  VT100InlineImageHelper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/20/20.
//

#import <Foundation/Foundation.h>

#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

@class VT100Grid;

typedef NS_ENUM(NSInteger, VT100TerminalUnits) {
    kVT100TerminalUnitsCells,
    kVT100TerminalUnitsPixels,
    kVT100TerminalUnitsPercentage,
    kVT100TerminalUnitsAuto,
};

@protocol VT100InlineImageHelperDelegate<NSObject>
- (void)inlineImageConfirmBigDownloadWithBeforeSize:(NSInteger)lengthBefore
                                          afterSize:(NSInteger)lengthAfter
                                               name:(NSString *)name;
- (NSSize)inlineImageCellSize;
- (void)inlineImageAppendLinefeed;
- (void)inlineImageSetMarkOnScreenLine:(NSInteger)line
                                  code:(unichar)code;
- (void)inlineImageDidCreateTextDocumentInRange:(VT100GridAbsCoordRange)range
                                           type:(NSString *)type
                                       filename:(NSString * _Nullable)filename;
- (void)inlineImageDidFinishWithImageData:(NSData *)imageData;
- (VT100GridAbsCoord)inlineImageCursorAbsoluteCoord;
- (void)inlineImageAppendStringAtCursor:(NSString *)string;

@end

// Take an image as base-64 encoded compressed image, sixel data, or an NSImage
// and write it to a VT100Grid.
@interface VT100InlineImageHelper : NSObject

@property (nonatomic, weak) id<VT100InlineImageHelperDelegate> delegate;

// Type hints for non-image files.
@property (nullable, nonatomic, readonly, copy) NSString *type;

- (instancetype)initWithName:(NSString *)name
                       width:(int)width
                  widthUnits:(VT100TerminalUnits)widthUnits
                      height:(int)height
                 heightUnits:(VT100TerminalUnits)heightUnits
                 scaleFactor:(CGFloat)scaleFactor
         preserveAspectRatio:(BOOL)preserveAspectRatio
                       inset:(NSEdgeInsets)inset
                        type:(NSString * _Nullable)type
                preconfirmed:(BOOL)preconfirmed;

- (instancetype)initWithSixelData:(NSData *)data
                      scaleFactor:(CGFloat)scaleFactor;

- (instancetype)initWithNativeImageNamed:(NSString *)name
                           spanningWidth:(int)width
                             scaleFactor:(CGFloat)scaleFactor;

- (instancetype)init NS_UNAVAILABLE;

- (void)appendBase64EncodedData:(NSString *)data;
- (void)writeToGrid:(VT100Grid *)grid;

@end

NS_ASSUME_NONNULL_END
