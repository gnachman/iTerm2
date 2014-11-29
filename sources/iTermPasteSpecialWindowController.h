//
//  iTermPasteSpecialWindowController.h
//  iTerm2
//
//  Created by George Nachman on 11/29/14.
//
//

#import <Cocoa/Cocoa.h>

typedef void (^iTermPasteSpecialCompletionBlock)(NSData *, NSInteger, NSTimeInterval);

@interface iTermPasteSpecialWindowController : NSWindowController

+ (void)showAsPanelInWindow:(NSWindow *)presentingWindow
                  chunkSize:(NSInteger)chunkSize
         delayBetweenChunks:(NSTimeInterval)delayBetweenChunks
          bracketingEnabled:(BOOL)bracketingEnabled
                 completion:(iTermPasteSpecialCompletionBlock)completion;

@end
