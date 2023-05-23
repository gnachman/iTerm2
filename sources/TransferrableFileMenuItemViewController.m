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
static const CGFloat kCollapsedHeight = 51;

@implementation TransferrableFileMenuItemViewController {
    BOOL _hasOpenedMenu;
    NSVisualEffectView *_effectView;
    TransferrableFileMenuItemView *_contentView;
}

- (instancetype)initWithTransferrableFile:(TransferrableFile *)transferrableFile {
    self = [super init];
    if (self) {
        _transferrableFile = transferrableFile;
        _effectView = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(5,
                                                                           0,
                                                                           kWidth - 10,
                                                                           kHeight)];
        _effectView.material = NSVisualEffectMaterialSelection;
        _effectView.wantsLayer = YES;
        _effectView.autoresizingMask = NSViewWidthSizable;
        _effectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        _effectView.emphasized = YES;
        _effectView.layer.cornerRadius = 4;
        _effectView.layer.masksToBounds = YES;
        _effectView.state = NSVisualEffectStateActive;
        _effectView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        self.view.autoresizesSubviews = YES;
        [self.view addSubview:_effectView];
        _contentView = [[TransferrableFileMenuItemView alloc] initWithFrame:NSMakeRect(0,
                                                                                       0,
                                                                                       kWidth,
                                                                                       kHeight)
                                                                 effectView:_effectView];
        _contentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self.view addSubview:_contentView];
    }
    return self;
}

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0,
                                                         0,
                                                         kWidth,
                                                         kHeight)];
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
        if (self.transferrableFile.localPath == nil ||
            [NSURL fileURLWithPath:self.transferrableFile.localPath] == nil) {
            return NO;
        }
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

- (void)showMenu {
    if (!_hasOpenedMenu) {
        if (self.transferrableFile.isDownloading) {
            [[FileTransferManager sharedInstance] openDownloadsMenu];
        } else {
            [[FileTransferManager sharedInstance] openUploadsMenu];
        }
        _hasOpenedMenu = YES;
    }
}

- (void)update {
    TransferrableFileMenuItemView *view = _contentView;
    view.filename = [_transferrableFile shortName];
    view.subheading = [_transferrableFile subheading];
    double fileSize = [_transferrableFile fileSize];
    view.size = fileSize;
    if ([_transferrableFile fileSize] > 0) {
        double fraction = [_transferrableFile bytesTransferred];
        fraction /= [_transferrableFile fileSize];
        view.progressIndicator.fraction = fraction;
        [view.progressIndicator setNeedsDisplay:YES];
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
            if (self.transferrableFile.isDownloading) {
                view.statusMessage = @"Downloading…";
            } else {
                view.statusMessage = @"Uploading…";
            }
            [self showMenu];
            break;

        case kTransferrableFileStatusFinishedSuccessfully:
            [self collapse];
            view.statusMessage = @"Finished";
            break;

        case kTransferrableFileStatusFinishedWithError:
            [self collapse];
            view.statusMessage = @"Failed";
            [self showMenu];
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
    [_contentView.progressIndicator setHidden:YES];
    self.view.frame = NSMakeRect(0, 0, self.view.frame.size.width, kCollapsedHeight);
}

- (void)expand {
    [_contentView.progressIndicator setHidden:NO];
    self.view.frame = NSMakeRect(0, 0, self.view.frame.size.width, kHeight);
}

- (void)itemSelected:(id)sender {
    NSLog(@"Click");
}

- (void)stop:(id)sender {
    [self.transferrableFile stop];
}

- (void)showInFinder:(id)sender {
    NSURL *theUrl = [NSURL fileURLWithPath:self.transferrableFile.localPath];
    if (theUrl) {
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ theUrl ]];
    }

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
            return [NSString stringWithFormat:@"Failed with error “%@”", [_transferrableFile error]];
        case kTransferrableFileStatusCancelling:
            return @"Waiting to cancel";
        case kTransferrableFileStatusCancelled:
            return @"Canceled by user";
    }
}

- (void)getInfo:(id)sender {
    NSString *extra = @"";
    if (_transferrableFile.destination) {
        extra = [NSString stringWithFormat:@"\nDestination: %@",
                       _transferrableFile.destination];
    } else if (_transferrableFile.localPath) {
        extra = [NSString stringWithFormat:@"\nLocal path: %@",
                       _transferrableFile.localPath];
    }
    NSString *text = [NSString stringWithFormat:@"%@\n\nStatus: %@%@",
                      [_transferrableFile displayName],
                      [self stringForStatus:_transferrableFile.status],
                      extra];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"File Transfer Summary";
    alert.informativeText = text;
    [alert layout];
    [alert runModal];
}

- (NSTimeInterval)timeSinceLastStatusChange {
    return [NSDate timeIntervalSinceReferenceDate] - [_transferrableFile timeOfLastStatusChange];
}

@end
