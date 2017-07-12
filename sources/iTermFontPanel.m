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

- (NSFontPanelModeMask)validModesForFontPanel:(NSFontPanel *)fontPanel
{
    return kValidModesForFontPanel;
}

@end
