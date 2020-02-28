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

// This ought to be an instance method but apple created NSLocalSavePanel which is a subclass of
// NSPanel and so it doesn't receive this method. I don't know how you get one, but I saw a few
// crashes because of this folly.
+ (void)setDirectoryURL:(NSURL *)url
              onceForID:(NSString *)identifier
              savePanel:(NSSavePanel *)savePanel;

@end
