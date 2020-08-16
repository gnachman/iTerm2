//
//  iTermKeyMappings.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/21/20.
//

#import <Foundation/Foundation.h>
#import "iTermTuple.h"
#import "iTermKeyBindingAction.h"
#import "ProfileModel.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermKeyBindingAction;
@class iTermKeystroke;

@interface iTermKeyMappings : NSObject

#pragma mark - Lookup

#pragma mark Action-Returning

// Given a keycode and modifier mask, return the action and fill in the optional text
// string. if keyMappings is provided, that is searched first, and if nothing is
// found (or keyMappings is nil) then the global mappings are searched.
+ (nullable iTermKeyBindingAction *)actionForKeystroke:(iTermKeystroke *)keystroke
                                           keyMappings:(nullable NSDictionary *)keyMappings;

// Return the action for a given keycode and modifiers, searching only the
// specified keymappings dictionary.
+ (iTermKeyBindingAction * _Nullable)localActionForKeystroke:(iTermKeystroke *)keystroke
                                                 keyMappings:(NSDictionary *)keyMappings;

// Return anaction at a given index from the global key mappings.
+ (iTermKeyBindingAction * _Nullable)globalActionAtIndex:(NSInteger)rowIndex;

#pragma mark Keystroke-Returning

+ (NSSet<iTermKeystroke *> *)keystrokesInKeyMappingsInProfile:(Profile *)sourceProfile;
+ (NSSet<iTermKeystroke *> *)keystrokesInGlobalMapping;

#pragma mark Mapping-Related

+ (NSDictionary *)keyMappingsForProfile:(Profile *)profile;

// True if a bookmark has a mapping for a keystroke.
+ (BOOL)haveKeyMappingForKeystroke:(iTermKeystroke *)keystroke inProfile:(Profile *)profile;

// Return the number of key mappings in a profile.
+ (int)numberOfMappingsInProfile:(Profile *)profile;

+ (NSArray<iTermTuple<iTermKeystroke *, iTermKeyBindingAction *> *> *)tuplesOfActionsInProfile:(Profile *)profile;

#pragma mark - Ordering

+ (NSArray<iTermKeystroke *> *)sortedGlobalKeystrokes;
+ (NSArray<iTermKeystroke *> *)sortedKeystrokesForProfile:(Profile *)profile;

// Return a keystroke by index from a profile.
+ (iTermKeystroke * _Nullable)keystrokeAtIndex:(int)rowIndex inprofile:(Profile *)profile;

// Return a shortcut (0xKeycode-0xModifier) from the global keymappings.
+ (iTermKeystroke * _Nullable)globalKeystrokeAtIndex:(int)rowIndex;

+ (NSArray<iTermKeystroke *> *)sortedKeystrokesForKeyMappingsInProfile:(Profile *)profile;

#pragma mark - Mutation

+ (void)removeAllGlobalKeyMappings;

// This function has two modes:
// If newMapping is NO, replace a mapping at the specified index. The index
// must be in bounds.
// If newMapping is YES, either replace the existing mapping for the given keystroke
// or add a new one if there is no existing mapping.
//
// profile will be modified in place.
+ (void)setMappingAtIndex:(int)rowIndex
             forKeystroke:(iTermKeystroke *)keyStroke
                   action:(iTermKeyBindingAction *)action
                createNew:(BOOL)newMapping
                inProfile:(MutableProfile *)profile;

// Replace an existing key mapping in a key mapping dictionary.
+ (void)setMappingAtIndex:(int)rowIndex
             forKeystroke:(iTermKeystroke*)keyStroke
                   action:(iTermKeyBindingAction *)action
                createNew:(BOOL)newMapping
             inDictionary:(NSMutableDictionary *)mutableKeyMapping;

// Return a dictionary that is a copy of dict, but without the keymapping at the
// requested index.
+ (NSMutableDictionary *)removeMappingAtIndex:(int)rowIndex inDictionary:(NSDictionary *)dict;

+ (void)removeMappingAtIndex:(int)rowIndex fromProfile:(MutableProfile *)profile;
+ (void)removeAllMappingsInProfile:(MutableProfile *)profile;

// Remove a keymapping with a given keycode and modifier mask from a bookmark.
+ (void)removeKeystroke:(iTermKeystroke *)keystroke
            fromProfile:(MutableProfile *)profile;

#pragma mark - Global State

+ (BOOL)haveLoadedKeyMappings;
+ (void)loadGlobalKeyMap;

// Returns the global keymap ("0xKeycode-0xModifiers"->{Action=int, [Text=str])
+ (NSDictionary *)globalKeyMap;

// Replace the global keymap with a new dictionary.
+ (void)setGlobalKeyMap:(NSDictionary*)src;

// True if a keystroke has any global mapping.
+ (BOOL)haveGlobalKeyMappingForKeystroke:(iTermKeystroke *)keystroke;

#pragma mark - High-Level APIs

+ (iTermKeystroke *)keystrokeForMappingReferencingProfileWithGuid:(NSString *)guid
inProfile:(Profile *)profile;

+ (Profile * _Nullable)removeKeyMappingsReferencingGuid:(NSString *)guid
fromProfile:(nullable Profile *)profile;

@end

NS_ASSUME_NONNULL_END
