//
//  NSView+RecursiveDescription.h
//  iTerm
//
//  Created by George Nachman on 11/18/13.
//
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSView (RecursiveDescription)

@property (nonatomic, readonly) NSString *it_description;

- (NSString *)iterm_recursiveDescription;

@end

NS_ASSUME_NONNULL_END
