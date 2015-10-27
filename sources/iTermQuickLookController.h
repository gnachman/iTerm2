//
//  iTermQuickLookController.h
//  iTerm2
//
//  Created by George Nachman on 10/22/15.
//
//

#import <Foundation/Foundation.h>

@class QLPreviewPanel;

// Simplifies displaying a QuickLook panel.
@interface iTermQuickLookController : NSObject

+ (void)dismissSharedPanel;

// Add a file to the list of files to display in the quicklook. You must call this before
// showWithSourceRect and not after.
- (void)addURL:(NSURL *)url;

// Open the panel. sourceRect should be in screen coordinates and is where it will open from.
- (void)showWithSourceRect:(NSRect)sourceRect controller:(id)controller;

// Close the panel.
- (void)close;

// Take over the delegate and datasource of the QLPreviewPanel. Only call this if this window is
// already the controller for the panel.
- (void)takeControl;

// Window delegate should pass these messages on.
- (void)beginPreviewPanelControl:(QLPreviewPanel *)panel;
- (void)endPreviewPanelControl:(QLPreviewPanel *)panel;

@end
