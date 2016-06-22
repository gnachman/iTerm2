//
//  iTermHotkeyModel.h
//  iTerm2
//
//  Created by George Nachman on 6/21/16.
//
//

#import <Foundation/Foundation.h>
#import "iTermHotKeyController.h"

@interface iTermHotKeyModel : NSObject

@property(nonatomic, copy) NSString *keyCombination;
@property(nonatomic) BOOL autoHide;
@property(nonatomic) BOOL showAfterAutoHiding;
@property(nonatomic) BOOL revealOnDockClick;
@property(nonatomic) BOOL revealOnDockClickOnlyIfNoOpenWindowsExist;
@property(nonatomic) BOOL animate;
@property(readonly) NSDictionary *dictionaryValue;

- (instancetype)initWithDictionary:(NSDictionary *)dictionary NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end
