//
//  iTermPasteSpecialWindowController.h
//  iTerm2
//
//  Created by George Nachman on 11/29/14.
//
//

#import <Cocoa/Cocoa.h>

typedef void (^iTermPasteSpecialCompletionBlock)(NSString *, NSInteger, NSTimeInterval);

@interface iTermPasteSpecialWindowController : NSWindowController

+ (void)e:(NSWindow *)presentingWindow
                  chunkSize:(NSInteger)chunkSize
         delayBetweenChunks:(NSTimeInterval)delayBetweenChunks
          bracketingEnabled:(BOOL)bracketingEnabled
                   encoding:(NSStringEncoding)encoding
                 completion:(iTermPasteSpecialCompletionBlock)completion;

@end
