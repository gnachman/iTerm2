//
//  NSWorkspace+iTerm.m
//  iTerm2
//
//  Created by George Nachman on 5/11/15.
//
//

#import "NSWorkspace+iTerm.h"

@implementation NSWorkspace (iTerm)

- (NSString *)temporaryFileName {
    NSString *tempFileTemplate =
        [NSTemporaryDirectory() stringByAppendingPathComponent:@"iTerm2.XXXXXX"];
    const char *tempFileTemplateCString =
        [tempFileTemplate fileSystemRepresentation];
    char *tempFileNameCString = (char *)malloc(strlen(tempFileTemplateCString) + 1);
    strcpy(tempFileNameCString, tempFileTemplateCString);
    int fileDescriptor = mkstemp(tempFileNameCString);

    if (fileDescriptor == -1) {
        return nil;
    }
    close(fileDescriptor);
    NSString *filename = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:tempFileNameCString
                                                                                     length:strlen(tempFileNameCString)];
    free(tempFileNameCString);
    return filename;
}

@end
