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
@property (nonatomic) BOOL showTimestamps;
@property (nonatomic) BOOL showFileFormat;
@property (nonatomic, readonly) BOOL timestampsEnabled;

- (void)popupButtonDidChange:(id)sender;

@end

NS_ASSUME_NONNULL_END
