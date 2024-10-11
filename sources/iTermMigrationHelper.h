//
//  iTermMigrationHelper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/1/18.
//

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSUInteger, iTermMigrationHelperShouldRemoveDeprecatedKeyMappings) {
    // User wasn't prompted yet.
    iTermMigrationHelperShouldRemoveDeprecatedKeyMappingsDefault,

    // Last time we looked we didn't find anything so the user wasn't prompted.
    iTermMigrationHelperShouldRemoveDeprecatedKeyMappingsNoneFound,

    // User consented.
    iTermMigrationHelperShouldRemoveDeprecatedKeyMappingsYes,

    // User declined.
    iTermMigrationHelperShouldRemoveDeprecatedKeyMappingsNo
};

@interface iTermMigrationHelper : NSObject

+ (void)migrateApplicationSupportDirectoryIfNeeded;
+ (void)recursiveMigrateBookmarks:(NSDictionary*)node path:(NSArray*)path;
+ (void)migrateOpenAIKeyIfNeeded;

// If this was never called before, check if there's anything with a bad keymapping. If there was one and we have never asked, then ask.
+ (void)askToRemoveDeprecatedKeyMappingsIfNeeded NS_AVAILABLE_MAC(15);

// Just ask. Remember the response.
+ (BOOL)askToRemoveDeprecatedKeyMappings:(NSString *)specialReason NS_AVAILABLE_MAC(15);

// Returns nil if the key mapping is valid or a modified keymapping without deprecated mappings otherwise.
+ (NSDictionary *)keyMappingsByRemovingDeprecatedKeyMappingsFrom:(NSDictionary *)input;

// See comments in the enum.
+ (iTermMigrationHelperShouldRemoveDeprecatedKeyMappings)shouldRemoveDeprecatedKeyMappings;

@end
