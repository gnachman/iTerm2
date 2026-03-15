//
//  iTermStreamingPNGWriter.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/12/26.
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A streaming PNG writer that writes rows incrementally to a file.
/// Uses Apple's ImageIO framework for efficient PNG encoding without
/// holding the entire image in memory.
@interface iTermStreamingPNGWriter : NSObject

/// Initialize with destination URL and image dimensions.
/// @param url The file URL to write the PNG to
/// @param width Image width in pixels
/// @param height Image height in pixels
/// @param scale Scale factor for Retina (affects DPI metadata)
/// @return Initialized writer, or nil if initialization failed
- (nullable instancetype)initWithDestinationURL:(NSURL *)url
                                          width:(NSInteger)width
                                         height:(NSInteger)height
                                    scaleFactor:(CGFloat)scale;

/// Write a batch of rows as an image slice.
/// Each call appends rows to the in-progress PNG.
/// @param rowData Pointer to pixel data (RGBA, 4 bytes per pixel, width * rowCount pixels)
/// @param rowCount Number of rows in this batch
/// @return YES on success, NO on failure
- (BOOL)writeRows:(const uint8_t *)rowData count:(NSInteger)rowCount;

/// Write a single row of pixel data.
/// @param rowData Pointer to one row of pixel data (RGBA, 4 bytes per pixel)
/// @return YES on success, NO on failure
- (BOOL)writeRow:(const uint8_t *)rowData;

/// Finalize the PNG file. Must be called after all rows are written.
/// @return YES on success, NO on failure
- (BOOL)finalize;

/// Cancel the write operation and clean up any partial files.
- (void)cancel;

/// The destination URL
@property (nonatomic, readonly) NSURL *url;

/// Total number of rows expected
@property (nonatomic, readonly) NSInteger height;

/// Number of rows written so far
@property (nonatomic, readonly) NSInteger rowsWritten;

@end

NS_ASSUME_NONNULL_END
