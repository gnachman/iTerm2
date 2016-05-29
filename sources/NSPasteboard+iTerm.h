//
//  NSPasteboard+iTerm.h
//  iTerm2
//
//  Created by George Nachman on 12/11/14.
//
//

#import <Cocoa/Cocoa.h>

@interface NSPasteboard (iTerm)

- (NSArray *)filenamesOnPasteboardWithShellEscaping:(BOOL)escape;
- (NSData *)dataForFirstFile;

@end
