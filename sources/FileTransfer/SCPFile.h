//
//  SCPFile.h
//  iTerm
//
//  Created by George Nachman on 12/21/13.
//
//

#import "FileTransferManager.h"
#import "SCPPath.h"

@interface SCPFile : TransferrableFile

@property(nonatomic, retain) SCPPath *path;
@property(atomic, copy) NSString *localPath;

@end
