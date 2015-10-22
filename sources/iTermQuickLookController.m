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

@implementation iTermQuickLookController

- (void)dealloc {
  QLPreviewPanel *panel = [QLPreviewPanel sharedPreviewPanel];
  if (panel.delegate == self) {
    panel.delegate = nil;
  }
  if (panel.dataSource == self) {
    panel.dataSource = nil;
  }
  [_files release];
  [super dealloc];
}

- (void)addFile:(NSString *)path {
  if (!_files) {
    _files = [[NSMutableArray alloc] init];
  }
  [_files addObject:[NSURL fileURLWithPath:path]];
}

- (void)showWithSourceRect:(NSRect)sourceRect {
  self.sourceRect = sourceRect;
  BOOL alreadyExisted = [QLPreviewPanel sharedPreviewPanelExists];
  QLPreviewPanel *panel = [QLPreviewPanel sharedPreviewPanel];
  panel.delegate = self;
  panel.dataSource = self;
  if (alreadyExisted) {
    [panel reloadData];
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

@end
