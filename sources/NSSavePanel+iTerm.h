//
//  NSSavePanel+iTerm.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/1/18.
//

#import <Cocoa/Cocoa.h>

@interface NSSavePanel (iTerm)

// Uses URL as the suggested directory (sets it on the first call for any
// identifier) but remembers the user's setting.
- (void)setDirectoryURL:(NSURL *)url
              onceForID:(NSString *)identifier;

@end
