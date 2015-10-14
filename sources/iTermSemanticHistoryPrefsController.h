//
//  iTermSemanticHistoryPrefsController.h
//  iTerm
//
//  Created by George Nachman on 9/28/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>

extern NSString *kSemanticHistoryActionKey;
extern NSString *kSemanticHistoryEditorKey;
extern NSString *kSemanticHistoryTextKey;

extern NSString *kSublimeText2Identifier;
extern NSString *kSublimeText3Identifier;
extern NSString *kMacVimIdentifier;
extern NSString *kAtomIdentifier;
extern NSString *kTextmateIdentifier;
extern NSString *kTextmate2Identifier;
extern NSString *kBBEditIdentifier;

extern NSString *kSemanticHistoryBestEditorAction;
extern NSString *kSemanticHistoryUrlAction;
extern NSString *kSemanticHistoryEditorAction;
extern NSString *kSemanticHistoryCommandAction;
extern NSString *kSemanticHistoryRawCommandAction;
extern NSString *kSemanticHistoryCoprocessAction;

@class iTermSemanticHistoryPrefsController;

@protocol iTermSemanticHistoryPrefsControllerDelegate <NSObject>
- (void)semanticHistoryPrefsControllerSettingChanged:(iTermSemanticHistoryPrefsController *)controller;
@end

@interface iTermSemanticHistoryPrefsController : NSObject

@property(nonatomic, copy) NSString *guid;
@property(nonatomic, assign) IBOutlet id<iTermSemanticHistoryPrefsControllerDelegate> delegate;
@property(nonatomic, readonly) NSDictionary *prefs;

+ (NSString *)bestEditor;
+ (NSString *)schemeForEditor:(NSString *)editor;
+ (BOOL)bundleIdIsEditor:(NSString *)bundleId;

- (IBAction)actionChanged:(id)sender;
- (void)setEnabled:(BOOL)enabled;

@end
