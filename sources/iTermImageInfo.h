//
//  iTermImageInfo.h
//  iTerm2
//
//  Created by George Nachman on 5/11/15.
//
//

#import <Cocoa/Cocoa.h>
#import "iTermImage.h"

// Posted when a lazily loaded image is loaded.
extern NSString *const iTermImageDidLoad;

@protocol iTermImageInfoReading<NSPasteboardItemDataProvider>
@property(atomic, readonly) iTermImage *image;

// Raw data for image.
@property(atomic, readonly) NSData *data;

// Image code
@property(atomic, readonly) unichar code;

// Creates a pasteboard item that responds with image or file.
@property(atomic, readonly) NSPasteboardItem *pasteboardItem;

// Is this a broken image?
@property(atomic) BOOL broken;

// Is animated?
@property(atomic, readonly) BOOL animated;

// If animated, set this to stop animation.
@property(atomic) BOOL paused;

// A UUID, lazily allocated.
@property(atomic, readonly) NSString *uniqueIdentifier;

// Size in cells.
@property(atomic) NSSize size;

// Creates a new randomly named temp file containing the image and returns its name.
@property(atomic, readonly) NSString *nameForNewSavedTempFile;

// Original filename
@property(atomic, copy, readonly) NSString *filename;

// Is there an image yet? one might be coming later
@property (atomic, readonly) BOOL ready;


// Returns an image whose size is self.size * cellSize. If the image is smaller and/or has an inset
// there will be a transparent area around the edges.
- (NSImage *)imageWithCellSize:(CGSize)cellSize scale:(CGFloat)scale;

// Format inferred from extension
- (void)saveToFile:(NSString *)filename;

// Always returns 0 for non-animated images.
- (int)frameForTimestamp:(NSTimeInterval)timestamp;

// A more predictable version of the above. Timestamp determines GIF frame.
- (NSImage *)imageWithCellSize:(CGSize)cellSize timestamp:(NSTimeInterval)timestamp scale:(CGFloat)scale;

@end

// Describes an image. A screen_char_t may be used to draw a part of an image.
// The code in the screen_char_t can be used to look up this object which is
// 1:1 with images.
@interface iTermImageInfo : NSObject<iTermImageInfoReading>

+ (NSEdgeInsets)fractionalInsetsForPreservedAspectRatioWithDesiredSize:(NSSize)desiredSize
                                                          forImageSize:(NSSize)imageSize
                                                              cellSize:(NSSize)cellSize
                                                         numberOfCells:(NSSize)numberOfCells;
+ (NSEdgeInsets)fractionalInsetsStretchingToDesiredSize:(NSSize)desiredSize
                                              imageSize:(NSSize)imageSize
                                               cellSize:(NSSize)cellSize
                                          numberOfCells:(NSSize)numberOfCells;

// Full-size image.
@property(atomic, strong, readwrite) iTermImage *image;

// If set, the image won't be squished.
@property(atomic) BOOL preserveAspectRatio;

@property(atomic, copy, readwrite) NSString *filename;
// Inset for the image within its area.
@property(atomic) NSEdgeInsets inset;

// UTI string for image type.
@property(atomic, readonly) NSString *imageType;

// During restoration, do we still need to find a mark?
@property (atomic) BOOL provisional;

// First frame of animated image, or else raw image.
@property (nonatomic, readonly) NSImage *firstFrame;

// Used to create a new instance for a new image. This may remain an empty container until
// -setImageFromImage: is called.
- (instancetype)initWithCode:(unichar)code;

// Used to create a new instance from a coded dictionary.
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;

// Binds an image. Data is optional and only used for animated GIFs. Not to be used after
// -initWithDictionary.
- (void)setImageFromImage:(iTermImage *)image data:(NSData *)data;

// Coded representation
- (NSDictionary<NSString *, NSObject<NSCopying> *> *)dictionary;

@end
