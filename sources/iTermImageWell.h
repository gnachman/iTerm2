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

@property(nonatomic, assign) IBOutlet id<iTermImageWellDelegate> delegate;

@end
