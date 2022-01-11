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
@property (nonatomic, readonly) BOOL treatAmbiguousCharsAsDoubleWidth;
@property (nonatomic, readonly) NSInteger unicodeVersion;
@property (nonatomic, readonly) BOOL enableTriggersInInteractiveApps;
@property (nonatomic, readonly) BOOL triggerParametersUseInterpolatedStrings;
@property (nonatomic, copy, readonly) NSArray<NSDictionary *> *triggerProfileDicts;
@property (nonatomic, readonly) BOOL notifyOfAppend;
@property (nonatomic, readonly) BOOL isTmuxClient;
@property (nonatomic, readonly) BOOL clipboardAccessAllowed;

// Is terminal-initiated printing allowed?
@property (nonatomic, readonly) BOOL printingAllowed;

@property (nonatomic, readonly) BOOL isDirty;

@end

@interface VT100ScreenConfiguration : NSObject<VT100ScreenConfiguration>
@end

@interface VT100MutableScreenConfiguration : VT100ScreenConfiguration

@property (nonatomic, readwrite) BOOL shouldPlacePromptAtFirstColumn;
@property (nonatomic, copy, readwrite) NSString *sessionGuid;
@property (nonatomic, readwrite) BOOL treatAmbiguousCharsAsDoubleWidth;
@property (nonatomic, readwrite) NSInteger unicodeVersion;
@property (nonatomic, readwrite) BOOL enableTriggersInInteractiveApps;
@property (nonatomic, readwrite) BOOL triggerParametersUseInterpolatedStrings;
@property (nonatomic, copy, readwrite) NSArray<NSDictionary *> *triggerProfileDicts;
@property (nonatomic, readwrite) BOOL notifyOfAppend;
@property (nonatomic, readwrite) BOOL isTmuxClient;
@property (nonatomic, readwrite) BOOL printingAllowed;
@property (nonatomic, readwrite) BOOL clipboardAccessAllowed;

@property (nonatomic, readwrite) BOOL isDirty;

@end

NS_ASSUME_NONNULL_END
