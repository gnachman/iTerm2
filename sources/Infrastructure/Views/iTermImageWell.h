//
//  iTermImageWell.h
//  iTerm2
//
//  Created by George Nachman on 12/17/14.
//
//

#import <Cocoa/Cocoa.h>

@class iTermImageWell;

@protocol iTermImageWellDelegate <NSObject>
- (void)imageWellDidClick:(iTermImageWell *)imageWell;
- (void)imageWellDidPerformDropOperation:(iTermImageWell *)imageWell filename:(NSString *)filename;
@end

@interface iTermImageWell : NSImageView

@property(nonatomic, weak) IBOutlet id<iTermImageWellDelegate> delegate;

// When YES, dropping a folder is accepted and the delegate is invoked with
// the folder path. NSImageView's parent implementation only accepts image
// files by default, so folder drops are silently rejected without this.
@property(nonatomic) BOOL acceptsFolders;

@end
