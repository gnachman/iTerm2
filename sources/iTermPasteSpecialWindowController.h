//
//  iTermPasteSpecialWindowController.h
//  iTerm2
//
//  Created by George Nachman on 11/29/14.
//
//

#import <Cocoa/Cocoa.h>
#import "PasteEvent.h"

typedef void (^iTermPasteSpecialCompletionBlock)(PasteEvent *pasteEvent);

@interface iTermPasteSpecialWindowController : NSWindowController

+ (void)showAsPanelInWindow:(NSWindow *)presentingWindow
                  chunkSize:(NSInteger)chunkSize
         delayBetweenChunks:(NSTimeInterval)delayBetweenChunks
          bracketingEnabled:(BOOL)bracketingEnabled
                   encoding:(NSStringEncoding)encoding
           canWaitForPrompt:(BOOL)canWaitForPrompt
            isAtShellPrompt:(BOOL)isAtShellPrompt
         forceEscapeSymbols:(BOOL)forceEscapeSymbols
                 completion:(iTermPasteSpecialCompletionBlock)completion;

@end
