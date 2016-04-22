//
//  iTermAdvancedSettingsController.h
//  iTerm
//
//  Created by George Nachman on 3/18/14.
//
//

#import <Cocoa/Cocoa.h>

// The model posts this notification when it makes a change.
extern NSString *const iTermAdvancedSettingsDidChange;

@interface iTermAdvancedSettingsViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>

// Don't call these methods directly. Instead, go through iTermAdvancedSettingsModel.
+ (BOOL)boolForIdentifier:(NSString*)identifier
             defaultValue:(BOOL)defaultValue
              description:(NSString*)description;

+ (int)intForIdentifier:(NSString *)identifier
           defaultValue:(int)defaultValue
            description:(NSString *)description;

+ (double)floatForIdentifier:(NSString *)identifier
                defaultValue:(double)defaultValue
                 description:(NSString *)description;

+ (NSString *)stringForIdentifier:(NSString *)identifier
                     defaultValue:(NSString *)defaultValue
                      description:(NSString *)description;


@end
