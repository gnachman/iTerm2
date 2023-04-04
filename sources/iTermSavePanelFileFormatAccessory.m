//
//  iTermSavePanelFileFormatAccessory.m
//  iTerm2
//
//  Created by George Nachman on 12/8/18.
//

#import "iTermSavePanelFileFormatAccessory.h"

NSString *iTermSaveWithTimestampsUserDefaultsKey = @"NoSyncSaveWithTimestamps";

@interface iTermSavePanelFileFormatAccessory ()

@end

@implementation iTermSavePanelFileFormatAccessory {
    IBOutlet NSView *_fileFormat;
    IBOutlet NSButton *_timestampsButton;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [_popupButton setTarget:self];
    [_popupButton setAction:@selector(popupButtonDidChange:)];

    NSArray<NSView *> *views = @[ _fileFormat, _timestampsButton ];
    NSMutableArray<NSNumber *> *ys = [NSMutableArray array];
    const CGFloat margin = 12;
    CGFloat y = margin;
    for (NSView *view in views) {
        [ys addObject:@(y)];
        if ((view == _fileFormat && self.showFileFormat) ||
            (view == _timestampsButton && self.showTimestamps)) {
            y += view.frame.size.height + margin;
        } else {
            view.hidden = YES;
        }
    }
    NSRect frame = self.view.frame;
    frame.size.height = y;
    self.view.frame = frame;

    [views enumerateObjectsUsingBlock:^(NSView * _Nonnull view, NSUInteger idx, BOOL * _Nonnull stop) {
        NSRect frame = view.frame;
        frame.origin.y = ys[idx].doubleValue;
        view.frame = frame;
    }];

    _timestampsButton.state = [[NSUserDefaults standardUserDefaults] boolForKey:iTermSaveWithTimestampsUserDefaultsKey] ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)popupButtonDidChange:(id)sender {
    self.onChange(_popupButton.selectedTag);
}

- (BOOL)timestampsEnabled {
    return self.showTimestamps && _timestampsButton.state == NSControlStateValueOn;
}

- (IBAction)timestampsDidChange:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:_timestampsButton.state == NSControlStateValueOn forKey:iTermSaveWithTimestampsUserDefaultsKey];
}
@end
