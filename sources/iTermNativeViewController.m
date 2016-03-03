//
//  iTermNativeViewController.m
//  iTerm2
//
//  Created by George Nachman on 3/2/16.
//
//

#import "iTermNativeViewController.h"
#import "NSStringITerm.h"

@implementation iTermNativeViewController {
  NSString *_identifier;
  BOOL _ready;
}

ITERM_WEAKLY_REFERENCEABLE

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
  return [super init];
}

- (void)iterm_dealloc {
  [_identifier release];
  [_nativeViewControllerDelegate release];
  [super dealloc];
}

- (NSString *)identifier {
  if (!_identifier) {
    _identifier = [[NSString uuid] retain];
  }
  return _identifier;
}

- (void)notifyViewReadyForDisplay {
  if (!_ready) {
    _ready = YES;
    [_nativeViewControllerDelegate nativeViewControllerViewDidLoad:self];
  }
}

- (void)setNativeViewControllerDelegate:(id<iTermNativeViewControllerDelegate>)nativeViewControllerDelegate {
  [_nativeViewControllerDelegate autorelease];
  _nativeViewControllerDelegate = [nativeViewControllerDelegate retain];
  if (_ready) {
    [_nativeViewControllerDelegate nativeViewControllerViewDidLoad:self];
  }
}

- (void)requestSizeChangeTo:(NSSize)desiredSize {
  // delegate will do whatever needs to be done and eventually call setSize:.
  [_nativeViewControllerDelegate nativeViewController:self willResizeTo:desiredSize];
}

- (void)setSize:(NSSize)size {
  NSRect rect = self.view.frame;
  rect.size.height = size.height;
  self.view.frame = rect;
}

@end

