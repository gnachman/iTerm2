//
//  NSAlert+iTerm.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/6/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSAlert (iTerm)

- (NSInteger)runSheetModalForWindow:(NSWindow *)window;

@end

NS_ASSUME_NONNULL_END
