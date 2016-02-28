//
//  SmartSelection.h
//  iTerm
//
//  Created by George Nachman on 9/25/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "ContextMenuActionPrefsController.h"

// Keys that go in rules:

// Regular expression to match
extern NSString *const kRegexKey;

// Notes describing the rule
extern NSString *const kNotesKey;

// One of the kXxxPrecision strings defined below.
extern NSString *const kPrecisionKey;

// An array of actions.
extern NSString *const kActionsKey;

// Precision values that are assigned to the kPrecisionKey key.
extern NSString *const kVeryLowPrecision;
extern NSString *const kLowPrecision;
extern NSString *const kNormalPrecision;
extern NSString *const kHighPrecision;
extern NSString *const kVeryHighPrecision;

@class SmartSelectionController;

@protocol SmartSelectionDelegate <NSObject>
- (void)smartSelectionChanged:(SmartSelectionController *)controller;
@end


@interface SmartSelectionController : NSWindowController <ContextMenuActionPrefsDelegate>

@property (nonatomic, copy) NSString *guid;
@property (nonatomic, assign) BOOL hasSelection;
@property (nonatomic, assign) id<SmartSelectionDelegate> delegate;
@property (nonatomic, readonly) NSArray<NSDictionary *> *rules;

+ (BOOL)logDebugInfo;
+ (double)precisionInRule:(NSDictionary *)rule;
+ (NSArray *)actionsInRule:(NSDictionary *)rule;
+ (NSString *)regexInRule:(NSDictionary *)rule;
+ (NSArray *)defaultRules;
- (IBAction)addRule:(id)sender;
- (IBAction)removeRule:(id)sender;
- (IBAction)loadDefaults:(id)sender;
- (IBAction)help:(id)sender;
- (IBAction)logDebugInfoChanged:(id)sender;
- (IBAction)editActions:(id)sender;
- (void)windowWillOpen;
- (void)contextMenuActionsChanged:(NSArray *)newActions;

@end
