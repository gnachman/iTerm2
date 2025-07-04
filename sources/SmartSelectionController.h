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

extern const double SmartSelectionVeryLowPrecision;
extern const double SmartSelectionLowPrecision;
extern const double SmartSelectionNormalPrecision;
extern const double SmartSelectionHighPrecision;
extern const double SmartSelectionVeryHighPrecision;

@class SmartSelectionController;

@protocol SmartSelectionDelegate <NSObject>
- (void)smartSelectionChanged:(SmartSelectionController *)controller;
@end


@interface SmartSelectionController : NSWindowController <ContextMenuActionPrefsDelegate>

@property (nonatomic, copy) NSString *guid;
@property (nonatomic) BOOL hasSelection;
@property (nonatomic, weak) id<SmartSelectionDelegate> delegate;
@property (nonatomic, readonly) NSArray<NSDictionary *> *rules;

+ (BOOL)logDebugInfo;
+ (double)precisionInRule:(NSDictionary *)rule;
+ (NSArray<NSDictionary<NSString *, id> *> *)actionsInRule:(NSDictionary *)rule;
+ (NSString *)regexInRule:(NSDictionary *)rule;
+ (NSArray<NSDictionary<NSString *, id> *> *)defaultRules;
- (IBAction)addRule:(id)sender;
- (IBAction)removeRule:(id)sender;
- (IBAction)loadDefaults:(id)sender;
- (IBAction)help:(id)sender;
- (IBAction)logDebugInfoChanged:(id)sender;
- (IBAction)editActions:(id)sender;
- (void)windowWillOpen;

@end
