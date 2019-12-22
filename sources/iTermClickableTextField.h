//
//  iTermClickableTextField.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/21/19.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermClickableTextField : NSTextField

- (void)openURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
