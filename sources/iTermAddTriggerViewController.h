//
//  iTermAddTriggerViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/30/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermAddTriggerViewController : NSViewController

+ (void)addTriggerForText:(NSString *)text
                   window:(NSWindow *)window
               interpolatedStrings:(BOOL)interpolatedStrings
         defaultTextColor:(NSColor *)defaultTextColor
   defaultBackgroundColor:(NSColor *)defaultBackgroundColor
               completion:(void (^)(NSDictionary *, BOOL))completion;

- (instancetype)initWithName:(NSString *)name
                       regex:(NSString *)regex
         interpolatedStrings:(BOOL)interpolatedStrings
            defaultTextColor:(NSColor *)defaultTextColor
      defaultBackgroundColor:(NSColor *)defaultBackgroundColor
                  completion:(void (^)(NSDictionary * _Nullable, BOOL))completion NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(NSNibName _Nullable)nibNameOrNil bundle:(NSBundle * _Nullable)nibBundleOrNil NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
