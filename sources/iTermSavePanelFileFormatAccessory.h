//
//  iTermSavePanelFileFormatAccessory.h
//  iTerm2
//
//  Created by George Nachman on 12/8/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermSavePanelFileFormatAccessory : NSViewController

@property (nonatomic, strong) IBOutlet NSPopUpButton *popupButton;
@property (nonatomic, copy) void (^onChange)(NSInteger);
@end

NS_ASSUME_NONNULL_END
