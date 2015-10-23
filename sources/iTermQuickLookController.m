//
//  iTermQuickLookController.m
//  iTerm2
//
//  Created by George Nachman on 10/22/15.
//
//

#import "iTermQuickLookController.h"
#import <Quartz/Quartz.h>

@interface iTermQuickLookController() <QLPreviewPanelDataSource, QLPreviewPanelDelegate>
@property(nonatomic, retain) NSMutableArray<NSURL *> *files;
@property(nonatomic, assign) NSRect sourceRect;
@end

@interface QLPreviewPanel()
// Private API
- (void)setPositionNearPreviewItem:(id<QLPreviewItem>)item;
@end

@implementation iTermQuickLookController

+ (void)dismissSharedPanel {
  if ([[QLPreviewPanel sharedPreviewPanel] isVisible]) {
    [[QLPreviewPanel sharedPreviewPanel] orderOut:nil];
  }
}

- (void)dealloc {
  [_files release];
  [super dealloc];
}

- (void)addURL:(NSURL *)url {
  if (!_files) {
    _files = [[NSMutableArray alloc] init];
  }
  [_files addObject:url];
}

- (void)showWithSourceRect:(NSRect)sourceRect controller:(id)controller {
  self.sourceRect = sourceRect;
  QLPreviewPanel *panel = [QLPreviewPanel sharedPreviewPanel];
  if (panel.currentController == controller) {
    panel.dataSource = self;
    panel.delegate = self;
    [panel reloadData];
  } else {
    [panel updateController];
  }

  // This undocumented API makes the quicklook window appear beneath the cursor. It doesn't seem
  // to matter what the item is. NSURL implements QLPreviewItem so it's as good as anything.
  if ([panel respondsToSelector:@selector(setPositionNearPreviewItem:)]) {
    [panel setPositionNearPreviewItem:[NSURL URLWithString:@"http://example.com/"]];
  }

  [panel makeKeyAndOrderFront:nil];
}

- (void)close {
  QLPreviewPanel *panel = [QLPreviewPanel sharedPreviewPanel];
  if ([panel isVisible] &&
      [panel delegate] == self) {
    [panel orderOut:nil];
  }
}

- (void)takeControl {
  QLPreviewPanel *panel = [QLPreviewPanel sharedPreviewPanel];
  if (panel.delegate != self || panel.dataSource != self) {
    panel.delegate = self;
    panel.dataSource = self;
    [panel reloadData];
  }
}

#pragma mark - QLPreviewPanelDataSource

- (NSInteger)numberOfPreviewItemsInPreviewPanel:(QLPreviewPanel *)panel {
  return self.files.count;
}

- (id<QLPreviewItem>)previewPanel:(QLPreviewPanel *)panel previewItemAtIndex:(NSInteger)index {
  return self.files[index];
}


#pragma mark - QLPreviewPanelDelegate

- (BOOL)previewPanel:(QLPreviewPanel *)panel handleEvent:(NSEvent *)event {
  if ([event type] == NSKeyDown &&
      event.charactersIgnoringModifiers.length == 1 &&
      [event.charactersIgnoringModifiers characterAtIndex:0] == 27) {
    [self close];
    return YES;
  }

  return NO;
}

// This delegate method provides the rect on screen from which the panel will zoom.
- (NSRect)previewPanel:(QLPreviewPanel *)panel
    sourceFrameOnScreenForPreviewItem:(id <QLPreviewItem>)item {
  return self.sourceRect;
}

// This delegate method provides a transition image between the table view and the preview panel
- (NSImage *)previewPanel:(QLPreviewPanel *)panel
    transitionImageForPreviewItem:(id <QLPreviewItem>)item
                      contentRect:(NSRect *)contentRect {
  NSURL *url = [item previewItemURL];
  return [[NSWorkspace sharedWorkspace] iconForFile:url.path];
}

- (void)beginPreviewPanelControl:(QLPreviewPanel *)panel {
  panel.delegate = self;
  panel.dataSource = self;
  [panel reloadData];
}

- (void)endPreviewPanelControl:(QLPreviewPanel *)panel {
}

@end
