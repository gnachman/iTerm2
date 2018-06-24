//
//  iTermScriptChooser.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/23/18.
//

#import "iTermScriptChooser.h"
#import "NSFileManager+iTerm.h"

@interface iTermScriptChooser()<NSOpenSavePanelDelegate>
@property (nonatomic, copy) BOOL (^validator)(NSURL *);
@property (nonatomic, copy) void (^completion)(NSURL *);
@property (nonatomic, strong) NSOpenPanel *panel;
@end

@implementation iTermScriptChooser

+ (void)chooseWithValidator:(BOOL (^)(NSURL *))validator completion:(void (^)(NSURL *))completion {
    iTermScriptChooser *chooser = [[self alloc] init];
    chooser.validator = validator;
    chooser.completion = completion;
    [chooser choose];
}

- (void)choose {
    self.panel = [[NSOpenPanel alloc] init];
    self.panel.delegate = self;
    self.panel.directoryURL = [NSURL fileURLWithPath:[[NSFileManager defaultManager] scriptsPath]];
    self.panel.canChooseFiles = YES;
    self.panel.canChooseDirectories = YES;
    self.panel.allowsMultipleSelection = NO;
    [self.panel beginWithCompletionHandler:^(NSModalResponse result) {
        [self didChooseWithResult:result];
    }];
}

- (void)didChooseWithResult:(NSModalResponse)result {
    if (result != NSFileHandlingPanelOKButton) {
        self.completion(nil);
    } else {
        self.completion(self.panel.URL);
    }
    self.panel = nil;
}

#pragma mark - NSOpenSavePanelDelegate

- (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url {
    return self.validator(url);
}

- (void)panel:(id)sender didChangeToDirectoryURL:(nullable NSURL *)url {
    NSString *scriptsPath = [[NSFileManager defaultManager] scriptsPath];
    const BOOL ok = [url.path hasPrefix:scriptsPath];
    if (!ok) {
        NSOpenPanel *openPanel = sender;
        openPanel.directoryURL = [NSURL fileURLWithPath:scriptsPath];
    }
}

@end
