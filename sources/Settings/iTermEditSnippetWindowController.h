//
//  iTermEditSnippetWindowController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/14/20.
//

#import <Cocoa/Cocoa.h>
#import "iTermSnippetsModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermEditSnippetWindowController : NSWindowController
@property (nullable, nonatomic, readonly) iTermSnippet *snippet;
@property (nonatomic, readonly, copy) void (^completion)(iTermSnippet * _Nullable snippet);

- (instancetype)initWithSnippet:(iTermSnippet * _Nullable)snippet
                     completion:(void (^)(iTermSnippet * _Nullable snippet))completion;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithWindowNibName:(NSNibName)windowNibName NS_UNAVAILABLE;
- (instancetype)initWithWindowNibName:(NSNibName)windowNibName owner:(id)owner NS_UNAVAILABLE;
- (instancetype)initWithWindowNibPath:(NSString *)windowNibPath owner:(id)owner NS_UNAVAILABLE;
- (instancetype)initWithWindow:(NSWindow * _Nullable)window NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
