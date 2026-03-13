//
//  NSPasteboard+iTerm.m
//  iTerm2
//
//  Created by George Nachman on 12/11/14.
//
//

#import "NSPasteboard+iTerm.h"
#import "DebugLogging.h"
#import "NSStringITerm.h"
#import "iTermPreferences.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation NSPasteboard (iTerm)

- (NSArray *)filenamesOnPasteboardWithShellEscaping:(BOOL)escape forPaste:(BOOL)forPaste {
    NSMutableArray *results = [NSMutableArray array];
    NSArray<NSURL *> *urls = [self readObjectsForClasses:@[ [NSURL class] ] options:0];
    for (NSURL *url in urls) {
        NSString *filename = url.path;
        NSDictionary *filenamesAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filename
                                                                                             error:nil];
        if (([filenamesAttributes fileHFSTypeCode] == 'clpt' &&
             [filenamesAttributes fileHFSCreatorCode] == 'MACS') ||
            [[filename pathExtension] isEqualToString:@"textClipping"] == YES) {
            // Ignore text clippings
            continue;
        }

        if (escape) {
            if (forPaste && [iTermPreferences boolForKey:kPreferenceKeyWrapDroppedFilenamesInQuotesWhenPasting]) {
                filename = [filename quotedStringForPaste];
            } else {
                filename = [filename stringWithEscapedShellCharactersIncludingNewlines:YES];
            }
        }
        if (filename) {
            [results addObject:filename];
        }
    }
    return results;
}

- (NSData *)dataForFirstFile {
    NSString *bestType = [self availableTypeFromArray:@[ NSPasteboardTypeFileURL ]];

    if ([bestType isEqualToString:NSPasteboardTypeFileURL]) {
        NSArray<NSURL *> *urls = [self readObjectsForClasses:@[ [NSURL class] ] options:0];
        if (urls.count > 0) {
            NSString *filename = urls.firstObject.path;
            return [NSData dataWithContentsOfFile:filename];
        }
    }
    return nil;
}

// Returns the UTType identifier for available image data, or nil if none.
// Only checks type availability - does not fetch or decode any data.
- (NSString *)rawImageDataUTType {
    // Don't report image data if we have file URLs - those take precedence
    if ([self hasFileURLs]) {
        return nil;
    }
    NSArray<NSString *> *imageTypeIdentifiers = @[
        UTTypePNG.identifier,
        UTTypeJPEG.identifier,
        UTTypeTIFF.identifier,
        UTTypeBMP.identifier,
        UTTypeGIF.identifier,
        UTTypeWebP.identifier,
        UTTypeHEIC.identifier
    ];
    return [self availableTypeFromArray:imageTypeIdentifiers];
}

- (BOOL)hasRawImageData {
    return [self rawImageDataUTType] != nil;
}

// Fetches the raw bytes for the available image type.
// Only call this when you actually need the data.
- (NSData *)rawImageData {
    NSString *type = [self rawImageDataUTType];
    if (!type) {
        return nil;
    }
    return [self dataForType:type];
}

- (BOOL)hasFileURLs {
    DLog(@"hasFileURLs: pasteboard types=%@", self.types);
    NSString *bestType = [self availableTypeFromArray:@[ NSPasteboardTypeFileURL ]];
    DLog(@"hasFileURLs: bestType=%@", bestType);
    if (![bestType isEqualToString:NSPasteboardTypeFileURL]) {
        DLog(@"hasFileURLs: no file URL type available");
        return NO;
    }
    NSArray<NSURL *> *urls = [self readObjectsForClasses:@[ [NSURL class] ] options:0];
    DLog(@"hasFileURLs: urls=%@", urls);
    for (NSURL *url in urls) {
        if (url.isFileURL) {
            DLog(@"hasFileURLs: found file URL %@", url);
            return YES;
        }
    }
    DLog(@"hasFileURLs: no file URLs found");
    return NO;
}

- (NSArray<NSString *> *)filePaths {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSArray<NSURL *> *urls = [self readObjectsForClasses:@[ [NSURL class] ] options:0];
    for (NSURL *url in urls) {
        if (url.isFileURL && url.path) {
            [paths addObject:url.path];
        }
    }
    return paths;
}

@end
