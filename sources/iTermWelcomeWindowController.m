
//
//  iTermWelcomeWindowController.m
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import "iTermWelcomeWindowController.h"
#import "iTermWelcomeCardViewController.h"

@interface iTermWelcomeWindowController ()

@end

@implementation iTermWelcomeWindowController

- (instancetype)init {
    return [self initWithWindowNibName:@"iTermWelcomeWindowController"];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    self.window.level = NSModalPanelWindowLevel;
    self.window.opaque = NO;

    iTermWelcomeCardViewController *card = [[iTermWelcomeCardViewController alloc] initWithNibName:@"iTermWelcomeCardViewController" bundle:nil];  // leaks
    [card view];
    card.titleString = @"Shell Integration";
    card.color = [NSColor colorWithCalibratedRed:120/255.0 green:178/255.0 blue:1.0 alpha:1];
    card.bodyText = @"Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla molestie molestie erat ac tempor.";
    [card addActionWithTitle:@"Learn More"
                        icon:[NSImage imageNamed:@"Navigate"]
                       block:^() {
                           NSLog(@"Learn more");
                       }];
    [card addActionWithTitle:@"Remove This tip"
                        icon:[NSImage imageNamed:@"Dismiss"]
                       block:^() {
                           NSLog(@"Remove");
                       }];
    [card addActionWithTitle:@"Remind Me Later"
                        icon:[NSImage imageNamed:@"Later"]
                       block:^() {
                           NSLog(@"Later");
                       }];
    [card layoutWithWidth:400];

    NSRect frame = card.view.frame;
    frame.origin.y = 20;
    card.view.frame = frame;
    [self.window.contentView addSubview:card.view];
}

@end
