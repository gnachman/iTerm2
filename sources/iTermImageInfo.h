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

// Describes an image. A screen_char_t may be used to draw a part of an image.
// The code in the screen_char_t can be used to look up this object which is
// 1:1 with images.
@interface iTermImageInfo : NSObject<NSPasteboardItemDataProvider>

// A UUID, lazily allocated.
@property(nonatomic, readonly) NSString *uniqueIdentifier;

// Size in cells.
@property(nonatomic, assign) NSSize size;

// Full-size image.
@property(nonatomic, retain) iTermImage *image;

// If set, the image won't be squished.
@property(nonatomic, assign) BOOL preserveAspectRatio;

// Original filename
@property(nonatomic, copy) NSString *filename;

// Inset for the image within its area.
@property(nonatomic, assign) NSEdgeInsets inset;

// Image code
@property(nonatomic, readonly) unichar code;

// Is animated?
@property(nonatomic, readonly) BOOL animated;

// If animated, set this to stop animation.
@property(nonatomic) BOOL paused;

// Raw data for image.
@property(nonatomic, readonly) NSData *data;

// UTI string for image type.
@property(nonatomic, readonly) NSString *imageType;

// Creates a new randomly named temp file containing the image and returns its name.
@property(nonatomic, readonly) NSString *nameForNewSavedTempFile;

// Creates a pasteboard item that responds with image or file.
@property(nonatomic, readonly) NSPasteboardItem *pasteboardItem;

// Is this a broken image?
@property(nonatomic) BOOL broken;

// Is there an image yet? one might be coming later
@property (nonatomic, readonly) BOOL ready;

// Used to create a new instance for a new image. This may remain an empty container until
// -setImageFromImage: is called.
- (instancetype)initWithCode:(unichar)code;

// Used to create a new instance from a coded dictionary.
- (instancetype)initWithDictionary:(NSDictionary *)dictionary;

// Returns an image whose size is self.size * cellSize. If the image is smaller and/or has an inset
// there will be a transparent area around the edges.
- (NSImage *)imageWithCellSize:(CGSize)cellSize;

// A more predictable version of the above. Timestamp determines GIF frame.
- (NSImage *)imageWithCellSize:(CGSize)cellSize timestamp:(NSTimeInterval)timestamp;

// Binds an image. Data is optional and only used for animated GIFs. Not to be used after
// -initWithDictionary.
- (void)setImageFromImage:(iTermImage *)image data:(NSData *)data;

// Coded representation
- (NSDictionary *)dictionary;

// Format inferred from extension
- (void)saveToFile:(NSString *)filename;

// Always returns 0 for non-animated images.
- (int)frameForTimestamp:(NSTimeInterval)timestamp;

@end
