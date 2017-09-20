//
//  iTermFontPanel.m
//  iTerm
//
//  Created by George Nachman on 3/18/12.
//  Copyright (c) 2012 Georgetech. All rights reserved.
//

#import "iTermFontPanel.h"

@implementation iTermFontPanel

+ (void)makeDefault
{
    [NSFontManager setFontPanelFactory:[iTermFontPanel class]];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
- (NSFontPanelModeMask)validModesForFontPanel:(NSFontPanel *)fontPanel
{
    return kValidModesForFontPanel;
}
#pragma clang diagnostic pop

@end
