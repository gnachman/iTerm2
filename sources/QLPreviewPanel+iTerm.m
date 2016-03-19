//
//  QLPreviewPanel+iTerm.m
//  iTerm2
//
//  Created by Rony Fadel on 2/20/16.
//
//

#import "QLPreviewPanel+iTerm.h"

@implementation QLPreviewPanel (iTerm)

+ (instancetype)sharedPreviewPanelIfExists {
    if ([QLPreviewPanel sharedPreviewPanelExists]) {
        return [QLPreviewPanel sharedPreviewPanel];
    } else {
        return nil;
    }
}

@end
