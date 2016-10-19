//
//  QLPreviewPanel+iTerm.h
//  iTerm2
//
//  Created by Rony Fadel on 2/20/16.
//
//

#import <Quartz/Quartz.h>

@interface QLPreviewPanel (iTerm)

// Returns the shared QLPreviewPanel if one exists, or nil otherwise.
+ (instancetype)sharedPreviewPanelIfExists;

@end
