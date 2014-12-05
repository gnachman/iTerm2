//
//  TrouterPrefsController.h
//  iTerm
//
//  Created by George Nachman on 9/28/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import <Cocoa/Cocoa.h>

extern NSString *kTrouterActionKey;
extern NSString *kTrouterEditorKey;
extern NSString *kTrouterTextKey;

extern NSString *kSublimeText2Identifier;
extern NSString *kSublimeText3Identifier;
extern NSString *kMacVimIdentifier;
extern NSString *kAtomIdentifier;
extern NSString *kTextmateIdentifier;
extern NSString *kBBEditIdentifier;

extern NSString *kTrouterBestEditorAction;
extern NSString *kTrouterUrlAction;
extern NSString *kTrouterEditorAction;
extern NSString *kTrouterCommandAction;
extern NSString *kTrouterRawCommandAction;
extern NSString *kTrouterCoprocessAction;

@class TrouterPrefsController;

@protocol TrouterPrefsControllerDelegate <NSObject>
- (void)trouterPrefsControllerSettingChanged:(TrouterPrefsController *)controller;
@end

@interface TrouterPrefsController : NSObject {
    NSString *guid_;
    IBOutlet NSPopUpButton *action_;
    IBOutlet NSTextField *text_;
    IBOutlet NSPopUpButton *editors_;
    IBOutlet NSTextField *caveat_;
}

@property (nonatomic, copy) NSString *guid;
@property (nonatomic, assign) IBOutlet id<TrouterPrefsControllerDelegate> delegate;

+ (NSString *)bestEditor;
+ (NSString *)schemeForEditor:(NSString *)editor;
+ (BOOL)bundleIdIsEditor:(NSString *)bundleId;
- (IBAction)actionChanged:(id)sender;
- (NSDictionary *)prefs;

@end
