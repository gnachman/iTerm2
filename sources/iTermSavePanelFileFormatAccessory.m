//
//  iTermSavePanelFileFormatAccessory.m
//  iTerm2
//
//  Created by George Nachman on 12/8/18.
//

#import "iTermSavePanelFileFormatAccessory.h"

@interface iTermSavePanelFileFormatAccessory ()

@end

@implementation iTermSavePanelFileFormatAccessory

- (void)viewDidLoad {
    [super viewDidLoad];
    [_popupButton setTarget:self];
    [_popupButton setAction:@selector(popupButtonDidChange:)];
}

- (void)popupButtonDidChange:(id)sender {
    self.onChange(_popupButton.selectedTag);
}

@end
