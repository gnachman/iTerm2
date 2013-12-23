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
static const CGFloat kHeight = 50;

@implementation TransferrableFileMenuItemViewController

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
    return NO;
}

- (void)update {
    TransferrableFileMenuItemView *view = (TransferrableFileMenuItemView *)[self view];
    view.filename = [_transferrableFile shortName];
    double fileSize = [_transferrableFile fileSize];
    view.size = fileSize;
    if ([_transferrableFile fileSize] > 0) {
        double fraction = [_transferrableFile bytesTransferred];
        fraction /= [_transferrableFile fileSize];
        [view.progressIndicator setIndeterminate:NO];
        view.progressIndicator.doubleValue = fraction;
    }
    switch (_transferrableFile.status) {
        case kTransferrableFileStatusUnstarted:
        case kTransferrableFileStatusStarting:
            view.statusMessage = @"Starting…";
            [view.progressIndicator setHidden:YES];
            [_stopSubItem setEnabled:YES];
            [_showInFinderSubItem setEnabled:NO];
            [_removeFromListSubItem setEnabled:NO];
            [_openSubItem setEnabled:NO];
            break;
            
        case kTransferrableFileStatusTransferring:
            [view.progressIndicator setHidden:[_transferrableFile fileSize] < 0];
            view.statusMessage = @"Downloading…";
            [_stopSubItem setEnabled:YES];
            [_showInFinderSubItem setEnabled:NO];
            [_removeFromListSubItem setEnabled:NO];
            [_openSubItem setEnabled:NO];
            break;
            
        case kTransferrableFileStatusFinishedSuccessfully:
            [view.progressIndicator setHidden:YES];
            view.statusMessage = @"Finished";
            [_stopSubItem setEnabled:NO];
            [_showInFinderSubItem setEnabled:YES];
            [_removeFromListSubItem setEnabled:YES];
            [_openSubItem setEnabled:YES];
            break;
            
        case kTransferrableFileStatusFinishedWithError:
            [view.progressIndicator setHidden:YES];
            view.statusMessage = @"Failed";
            [_stopSubItem setEnabled:NO];
            [_showInFinderSubItem setEnabled:NO];
            [_removeFromListSubItem setEnabled:YES];
            [_openSubItem setEnabled:NO];
            break;
            
        case kTransferrableFileStatusCancelling:
            [view.progressIndicator setHidden:NO];
            [view.progressIndicator setIndeterminate:YES];
            view.statusMessage = @"Cancelling…";
            [_stopSubItem setEnabled:NO];
            [_showInFinderSubItem setEnabled:NO];
            [_removeFromListSubItem setEnabled:NO];
            [_openSubItem setEnabled:NO];
            break;
            
        case kTransferrableFileStatusCancelled:
            [view.progressIndicator setHidden:YES];
            view.statusMessage = @"Cancelled";
            [_stopSubItem setEnabled:NO];
            [_showInFinderSubItem setEnabled:NO];
            [_removeFromListSubItem setEnabled:YES];
            [_openSubItem setEnabled:NO];
            break;
    }
    [view setNeedsDisplay:YES];
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

@end
