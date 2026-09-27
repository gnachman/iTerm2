//
//  NSPasteboard+iTerm.h
//  iTerm2
//
//  Created by George Nachman on 12/11/14.
//
//

#import <Cocoa/Cocoa.h>

@interface NSPasteboard (iTerm)

- (NSArray *)filenamesOnPasteboardWithShellEscaping:(BOOL)escape forPaste:(BOOL)forPaste;
- (NSData *)dataForFirstFile;

// Whether -dataForFirstFile would return data, without reading the file. Use this for
// menu validation and anywhere else the contents are not actually wanted yet.
- (BOOL)hasReadableFirstFile;

// Check for raw image data (not from a file URL)
- (BOOL)hasRawImageData;
- (NSData *)rawImageData;
- (NSString *)rawImageDataUTType;

// Check for file URLs
- (BOOL)hasFileURLs;
- (NSArray<NSString *> *)filePaths;

@end
