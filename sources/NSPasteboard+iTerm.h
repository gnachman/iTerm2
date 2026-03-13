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

// Check for raw image data (not from a file URL)
- (BOOL)hasRawImageData;
- (NSData *)rawImageData;
- (NSString *)rawImageDataUTType;

// Check for file URLs
- (BOOL)hasFileURLs;
- (NSArray<NSString *> *)filePaths;

@end
