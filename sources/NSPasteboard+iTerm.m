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
    NSArray *propertyList = [self propertyListForType:NSFilenamesPboardType];
    for (NSString *filename in propertyList) {
        NSDictionary *filenamesAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filename
                                                                                             error:nil];
        if (([filenamesAttributes fileHFSTypeCode] == 'clpt' &&
             [filenamesAttributes fileHFSCreatorCode] == 'MACS') ||
            [[filename pathExtension] isEqualToString:@"textClipping"] == YES) {
            // Ignore text clippings
            continue;
        }

        if (escape) {
            filename = [filename stringWithEscapedShellCharacters];
        }
        [results addObject:filename];
    }
    return results;
}

- (NSData *)dataForFirstFile {
    NSString *bestType = [self availableTypeFromArray:@[ NSFilenamesPboardType ]];
    
    if ([bestType isEqualToString:NSFilenamesPboardType]) {
        NSArray *filenames = [self propertyListForType:NSFilenamesPboardType];
        if (filenames.count > 0) {
            NSString *filename = filenames[0];
            return [NSData dataWithContentsOfFile:filename];
        }
    }
    return nil;
}

@end
