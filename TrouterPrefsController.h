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
extern NSString *kTextmateIdentifier;
extern NSString *kBBEditIdentifier;

extern NSString *kTrouterBestEditorAction;
extern NSString *kTrouterUrlAction;
extern NSString *kTrouterEditorAction;
extern NSString *kTrouterCommandAction;
extern NSString *kTrouterRawCommandAction;

@interface TrouterPrefsController : NSObject {
    NSString *guid_;
    IBOutlet NSPopUpButton *action_;
    IBOutlet NSTextField *text_;
    IBOutlet NSPopUpButton *editors_;
    IBOutlet NSTextField *caveat_;
}

@property (nonatomic, copy) NSString *guid;

+ (NSString *)bestEditor;
+ (NSString *)schemeForEditor:(NSString *)editor;
- (IBAction)actionChanged:(id)sender;
- (NSDictionary *)prefs;

@end
