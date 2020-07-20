//
//  NSPasteboard+iTerm.m
//  iTerm2
//
//  Created by George Nachman on 12/11/14.
//
//

#import "NSPasteboard+iTerm.h"
#import "NSStringITerm.h"

@implementation NSPasteboard (iTerm)

- (NSArray *)filenamesOnPasteboardWithShellEscaping:(BOOL)escape {
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
            filename = [filename stringWithEscapedShellCharactersIncludingNewlines:YES];
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

@end
