//
//  iTermAddTriggerViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/30/20.
//

#import <Cocoa/Cocoa.h>

#import "ITAddressBookMgr.h"

NS_ASSUME_NONNULL_BEGIN

@class Trigger;

@interface iTermAddTriggerViewController : NSViewController

@property (nonatomic, copy) void (^didChange)(void);
@property (nonatomic, readonly) NSString *regex;
@property (nonatomic, readonly, nullable) NSString *contentRegex;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) id parameter;
@property (nonatomic, readonly) NSString *action;
@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) BOOL instant;
@property (nonatomic, readonly) iTermTriggerMatchType matchType;
@property (nonatomic, strong) NSColor *defaultTextColor;
@property (nonatomic, strong) NSColor *defaultBackgroundColor;
@property (nonatomic) BOOL browserMode;

+ (void)addTriggerForText:(NSString *)text
                   window:(NSWindow *)window
               interpolatedStrings:(BOOL)interpolatedStrings
         defaultTextColor:(NSColor *)defaultTextColor
   defaultBackgroundColor:(NSColor *)defaultBackgroundColor
              browserMode:(BOOL)browserMode
               completion:(void (^)(NSDictionary *, BOOL))completion;

- (instancetype)initWithName:(NSString *)name
                   matchType:(iTermTriggerMatchType)matchType
                       regex:(NSString *)regex
                contentRegex:(NSString * _Nullable)contentRegex
         interpolatedStrings:(BOOL)interpolatedStrings
            defaultTextColor:(NSColor *)defaultTextColor
      defaultBackgroundColor:(NSColor *)defaultBackgroundColor
                 browserMode:(BOOL)browserMode
                  completion:(void (^)(NSDictionary * _Nullable, BOOL))completion NS_DESIGNATED_INITIALIZER;

- (void)setTrigger:(Trigger *)trigger;
- (void)removeOkCancel;

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_DESIGNATED_INITIALIZER;
- (void)willHide;
@end

NS_ASSUME_NONNULL_END
