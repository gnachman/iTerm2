//
//  NSSavePanel+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/1/18.
//

#import "NSSavePanel+iTerm.h"

static NSString *const iTermSaveDocumentAsDefaultPathSetPrefix = @"NoSyncSaveDocumentAsPathSet_";

@implementation NSSavePanel (iTerm)

- (void)setDirectoryURL:(NSURL *)url
              onceForID:(NSString *)identifier {
    NSString *key = [iTermSaveDocumentAsDefaultPathSetPrefix stringByAppendingString:identifier];
    if (![[NSUserDefaults standardUserDefaults] boolForKey:key]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:key];
        self.directoryURL = url;
    }
}

@end
