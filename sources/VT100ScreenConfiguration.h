//
//  VT100ScreenConfiguration.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/21/21.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Configuration info passed from PTYSession down to VT100Screen. This reduces the size of the
// delegate interface and will make it possible to move a bunch of code in VT100Screen off the main
// thread. In a multi-threaded design VT100Screen can never block on PTYSession and fetching config
// state is a very common cause of a synchronous dependency.
@protocol VT100ScreenConfiguration<NSObject, NSCopying>

// Shell integration: if a command ends without a terminal newline, should we inject one prior to the prompt?
@property (nonatomic, readonly) BOOL shouldPlacePromptAtFirstColumn;
@property (nonatomic, copy, readonly) NSString *sessionGuid;
@property (nonatomic, readonly) BOOL enableTriggersInInteractiveApps;

@end

@interface VT100ScreenConfiguration : NSObject<VT100ScreenConfiguration>
@end

@interface VT100MutableScreenConfiguration : VT100ScreenConfiguration

@property (nonatomic, readwrite) BOOL shouldPlacePromptAtFirstColumn;
@property (nonatomic, copy, readwrite) NSString *sessionGuid;
@property (nonatomic, readwrite) BOOL enableTriggersInInteractiveApps;

@end

NS_ASSUME_NONNULL_END
