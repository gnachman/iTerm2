//
//  TransferrableFileMenuItemViewController.m
//  iTerm
//
//  Created by George Nachman on 12/23/13.
//
//

#import "TransferrableFileMenuItemViewController.h"
#import "FileTransferManager.h"
#import "TransferrableFileMenuItemView.h"

static const CGFloat kWidth = 300;
static const CGFloat kHeight = 63;
static const CGFloat kCollapsedHeight = 47;

@implementation TransferrableFileMenuItemViewController {
    BOOL _hasOpenedMenu;
}

- (id)initWithTransferrableFile:(TransferrableFile *)transferrableFile {
    self = [super init];
    if (self) {
        _transferrableFile = [transferrableFile retain];
        [self view];
    }
    return self;
}

- (void)loadView {
    self.view = [[[TransferrableFileMenuItemView alloc] initWithFrame:NSMakeRect(0,
                                                                                 0,
                                                                                 kWidth,
                                                                                 kHeight)] autorelease];
}

- (void)dealloc {
    [_transferrableFile release];
    [_stopSubItem release];
    [_showInFinderSubItem release];
    [_removeFromListSubItem release];
    [_openSubItem release];
    
    [super dealloc];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if ([menuItem action] == @selector(itemSelected:)) {
        return YES;
    }
    TransferrableFileStatus status = _transferrableFile.status;
    if ([menuItem action] == @selector(stop:)) {
        return (status == kTransferrableFileStatusStarting ||
                status == kTransferrableFileStatusTransferring);
    }
    if ([menuItem action] == @selector(showInFinder:)) {
        return (status == kTransferrableFileStatusFinishedSuccessfully);
    }
    if ([menuItem action] == @selector(removeFromList:)) {
        return (status == kTransferrableFileStatusFinishedSuccessfully ||
                status == kTransferrableFileStatusFinishedWithError ||
                status == kTransferrableFileStatusCancelled);
    }
    if ([menuItem action] == @selector(open:)) {
        return (status == kTransferrableFileStatusFinishedSuccessfully);
    }
    if ([menuItem action] == @selector(getInfo:)) {
        return YES;
    }
    return NO;
}

- (void)showDownloadsMenu {
    if (!_hasOpenedMenu) {
        [[FileTransferManager sharedInstance] openDownloadsMenu];
        _hasOpenedMenu = YES;
    }
}

- (void)update {
    TransferrableFileMenuItemView *view = (TransferrableFileMenuItemView *)[self view];
    view.filename = [_transferrableFile shortName];
    view.subheading = [_transferrableFile subheading];
    double fileSize = [_transferrableFile fileSize];
    view.size = fileSize;
    if ([_transferrableFile fileSize] > 0) {
        double fraction = [_transferrableFile bytesTransferred];
        fraction /= [_transferrableFile fileSize];
        view.progressIndicator.doubleValue = fraction;
    }
    view.bytesTransferred = [_transferrableFile bytesTransferred];
    switch (_transferrableFile.status) {
        case kTransferrableFileStatusUnstarted:
        case kTransferrableFileStatusStarting:
            view.statusMessage = @"Starting…";
            [self collapse];
            break;
            
        case kTransferrableFileStatusTransferring:
            [self expand];
            [view.progressIndicator setHidden:[_transferrableFile fileSize] < 0];
            view.statusMessage = @"Downloading…";
            [self showDownloadsMenu];
            break;
            
        case kTransferrableFileStatusFinishedSuccessfully:
            [self collapse];
            view.statusMessage = @"Finished";
            break;
            
        case kTransferrableFileStatusFinishedWithError:
            [self collapse];
            view.statusMessage = @"Failed";
            [self showDownloadsMenu];
            break;
            
        case kTransferrableFileStatusCancelling:
            [self expand];
            view.statusMessage = @"Cancelling…";
            break;
            
        case kTransferrableFileStatusCancelled:
            [self collapse];
            view.statusMessage = @"Cancelled";
            break;
    }
    [view setNeedsDisplay:YES];
}

- (void)collapse {
    TransferrableFileMenuItemView *view = (TransferrableFileMenuItemView *)[self view];
    [view.progressIndicator setHidden:YES];
    view.frame = NSMakeRect(0, 0, view.frame.size.width, kCollapsedHeight);
}

- (void)expand {
    TransferrableFileMenuItemView *view = (TransferrableFileMenuItemView *)[self view];
    [view.progressIndicator setHidden:NO];
    view.frame = NSMakeRect(0, 0, view.frame.size.width, kHeight);
}

- (void)itemSelected:(id)sender {
    NSLog(@"Click");
}

- (void)stop:(id)sender {
    [self.transferrableFile stop];
}

- (void)showInFinder:(id)sender {
    NSURL *theUrl = [NSURL fileURLWithPath:self.transferrableFile.localPath];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ theUrl ]];

}
- (void)removeFromList:(id)sender {
    [[FileTransferManager sharedInstance] removeItem:self];
}

- (void)open:(id)sender {
    [[NSWorkspace sharedWorkspace] openFile:self.transferrableFile.localPath];
}

- (NSString *)stringForStatus:(TransferrableFileStatus)status {
    switch (_transferrableFile.status) {
        case kTransferrableFileStatusUnstarted:
            return @"Unstarted";
        case kTransferrableFileStatusStarting:
            return @"Starting";
        case kTransferrableFileStatusTransferring:
            return @"Transferring";
        case kTransferrableFileStatusFinishedSuccessfully:
            return @"Finished";
        case kTransferrableFileStatusFinishedWithError:
            return [NSString stringWithFormat:@"Failed with error: %@", [_transferrableFile error]];
        case kTransferrableFileStatusCancelling:
            return @"Waiting to cancel";
        case kTransferrableFileStatusCancelled:
            return @"Canceled by user";
    }
}

- (void)getInfo:(id)sender {
    NSString *destination = @"";
    if (_transferrableFile.destination) {
        destination = [NSString stringWithFormat:@"\nDestination: %@",
                       _transferrableFile.destination];
    }
    NSString *text = [NSString stringWithFormat:@"%@\nStatus: %@%@",
                      [_transferrableFile displayName],
                      [self stringForStatus:_transferrableFile.status],
                      destination];
    NSAlert *alert = [NSAlert alertWithMessageText:text
                                     defaultButton:@"OK"
                                   alternateButton:nil
                                       otherButton:nil
                         informativeTextWithFormat:@""];
    
    [alert layout];
    [alert runModal];
}

@end
