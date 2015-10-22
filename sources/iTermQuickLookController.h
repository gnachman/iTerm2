//
//  iTermQuickLookController.h
//  iTerm2
//
//  Created by George Nachman on 10/22/15.
//
//

#import <Foundation/Foundation.h>

// Simplifies displaying a QuickLook panel.
@interface iTermQuickLookController : NSObject

// Add a file to the list of files to display in the quicklook. You must call this before
// showWithSourceRect and not after.
- (void)addFile:(NSString *)path;

// Open the panel. sourceRect should be in screen coordinates and is where it will open from.
- (void)showWithSourceRect:(NSRect)sourceRect;

// Close the panel.
- (void)close;

@end
