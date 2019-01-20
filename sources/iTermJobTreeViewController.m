//
//  iTermJobTreeViewController.m
//  iTerm2
//
//  Created by George Nachman on 1/18/19.
//

#import "iTermJobTreeViewController.h"

#import "DebugLogging.h"
#import "iTermLSOF.h"
#import "iTermProcessCache.h"
#import "NSArray+iTerm.h"
#import "NSTextField+iTerm.h"

@interface iTermJobTreeViewController ()<NSOutlineViewDelegate, NSOutlineViewDataSource>
@end

@interface iTermJobProxy : NSObject
@property (nonatomic, strong) NSMutableArray<iTermJobProxy *> *children;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *fullName;
@property (nonatomic) pid_t pid;
@property (nonatomic) BOOL known;
@end

@implementation iTermJobProxy {
    NSString *_fullName;
}

- (instancetype)initWithProcessInfo:(iTermProcessInfo *)processInfo {
    self = [super init];
    if (self) {
        _pid = processInfo.processID;
        _name = [processInfo.name copy];
        _children = [[processInfo.sortedChildren mapWithBlock:^id(iTermProcessInfo *anObject) {
            return [[iTermJobProxy alloc] initWithProcessInfo:anObject];
        }] mutableCopy];
    }
    return self;
}

- (void)moveFrom:(iTermJobProxy *)other {
    self.name = other.name;
    self.pid = other.pid;
    self.children = other.children;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p name=%@ pid=%@>", self.class, self, self.name, @(self.pid)];
}

- (NSString *)fullName {
    if (_fullName) {
        return _fullName;
    }
    _fullName = [iTermLSOF commandForProcess:_pid execName:nil];
    if (!_fullName) {
        // login has this problem
        _fullName = _name;
    }
    return _fullName;
}
@end

@implementation iTermJobTreeViewController {
    iTermJobProxy *_root;
    pid_t _pid;
    IBOutlet NSOutlineView *_outlineView;
    IBOutlet NSButton *_forceQuit;
    NSTimer *_timer;
}

- (instancetype)initWithProcessID:(pid_t)pid {
    self = [super initWithNibName:@"iTermJobTreeViewController" bundle:[NSBundle bundleForClass:[iTermJobTreeViewController class]]];
    if (self) {
        _pid = pid;
    }
    return self;
}

- (void)viewDidAppear {
    if (!_timer) {
        __weak __typeof(self) weakSelf = self;
        _timer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer * _Nonnull timer) {
            [weakSelf update];
        }];
    }
    [self update];
}

- (void)viewDidDisappear {
    [_timer invalidate];
    _timer = nil;
}

- (IBAction)forceQuit:(id)sender {
    [_outlineView.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        iTermJobProxy *job = [self->_outlineView itemAtRow:idx];
        pid_t pid = job.pid;
        if (pid) {
            kill(pid, SIGKILL);
        }
    }];
    [self update];
}

- (void)update {
    iTermJobProxy *newRoot = [[iTermJobProxy alloc] initWithProcessInfo:[[iTermProcessCache sharedInstance] processInfoForPid:_pid]];
    if (!_root) {
        _root = newRoot;
        DLog(@"reloadData");
        [_outlineView reloadData];
        [_outlineView expandItem:nil expandChildren:YES];
        return;
    }
    [_outlineView beginUpdates];
    DLog(@"beginUpdates");
    [self updateOld:_root andNew:newRoot index:0 parent:nil];
    DLog(@"endUpdates");
    [_outlineView endUpdates];
}

- (void)updateOld:(iTermJobProxy *)old andNew:(iTermJobProxy *)new index:(NSUInteger)index parent:(iTermJobProxy *)parent {
    DLog(@"updateOld:%@ andNew:%@ index:%@ parent:%@", old, new, @(index), parent);
    if (old.pid != new.pid) {
        [old moveFrom:new];
        DLog(@"Reload %@ (recursive)", old);
        [_outlineView reloadItem:old reloadChildren:YES];
        return;
    }
    if (![old.name isEqualToString:new.name]) {
        old.name = new.name;
        DLog(@"Reload %@ (not recursive)", old);
        [_outlineView reloadItem:old reloadChildren:NO];
    }
    BOOL posthocReloadOld = NO;
    if ((old.children.count == 0) != (new.children.count == 0)) {
        posthocReloadOld = YES;
    }

    const NSUInteger oldCount = old.children.count;
    const NSUInteger newCount = new.children.count;
    NSArray<iTermJobProxy *> *oldChildren = [old.children copy];
    NSArray<iTermJobProxy *> *newChildren = [new.children copy];
    NSInteger o = 0, n = 0, i = 0, offset = 0;
    while (o < oldCount && n < newCount) {
        iTermJobProxy *oldChild = oldChildren[o];
        iTermJobProxy *newChild = newChildren[n];

        const pid_t oldPid = oldChildren[o].pid;
        const pid_t newPid = newChildren[n].pid;
        if (oldPid == newPid) {
            [self updateOld:oldChild andNew:newChild index:o parent:old];
            o++;
            n++;
        } else if (oldPid < newPid) {
            DLog(@"Remove index %@ of %@", @(o), old);
            [_outlineView removeItemsAtIndexes:[NSIndexSet indexSetWithIndex:o + offset] inParent:old withAnimation:YES];
            offset -= 1;
            [old.children removeObject:oldChild];
            o++;
        } else {
            DLog(@"Insert index %@ in %@", @(i), old);
            [_outlineView insertItemsAtIndexes:[NSIndexSet indexSetWithIndex:o + offset] inParent:old withAnimation:YES];
            [old.children insertObject:newChild atIndex:o + offset];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->_outlineView expandItem:newChild expandChildren:YES];
            });
            offset += 1;
            n++;
        }
        i++;
    }
    while (o < oldCount) {
        DLog(@"Remove index %@ of %@", @(o), old);
        [_outlineView removeItemsAtIndexes:[NSIndexSet indexSetWithIndex:o + offset] inParent:old withAnimation:YES];
        offset -= 1;
        [old.children removeObject:oldChildren[o]];
        o++;
    }
    while (n < newCount) {
        DLog(@"Insert index %@ in %@", @(i), old);
        [_outlineView insertItemsAtIndexes:[NSIndexSet indexSetWithIndex:o + offset] inParent:old withAnimation:YES];
        [old.children insertObject:newChildren[n] atIndex:o + offset];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_outlineView expandItem:newChildren[n] expandChildren:YES];
        });
        offset += 1;
        n++;
    }
    if (posthocReloadOld) {
        DLog(@"Expandable changed for %@", old);
        [_outlineView reloadItem:old reloadChildren:NO];
        if (old.children.count) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->_outlineView expandItem:old expandChildren:YES];
            });
        }
    }
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(nullable id)item {
    if (item == nil) {
        NSInteger result = _root ? 1 : 0;
        DLog(@"Return that top level has %@ items", @(result));
        return result;
    }
    iTermJobProxy *info = item;
    DLog(@"Report that %@ has %@ children", info, @(info.children.count));
    return info.children.count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(nullable id)item {
    if (item == nil) {
        _root.known = YES;
        DLog(@"Return root %@", _root);
        return _root;
    }
    iTermJobProxy *info = item ?: _root;
    DLog(@"Return child %@ of %@: %@", @(index), info, info.children[index]);
    info.children[index].known = YES;
    return info.children[index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    iTermJobProxy *info = item;
    return info.children.count > 0;
}

#pragma mark - NSOutlineViewDelegate

- (nullable NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(nullable NSTableColumn *)tableColumn item:(id)item {
    iTermJobProxy *info = item ?: _root;
    NSString *identifier = @"processinfo";
    NSTableCellView *view = [outlineView makeViewWithIdentifier:identifier owner:self];
    if (!view) {
        view = [[NSTableCellView alloc] init];

        NSTextField *textField = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
        textField.translatesAutoresizingMaskIntoConstraints = NO;
        textField.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
        view.textField = textField;
        [view addSubview:textField];
        [view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[textField]-0-|"
                                                                     options:0
                                                                     metrics:nil
                                                                       views:@{ @"textField": textField }]];
        [view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-0-[textField]-0-|"
                                                                     options:0
                                                                     metrics:nil
                                                                       views:@{ @"textField": textField }]];
        textField.frame = view.bounds;
        textField.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
    }
    if ([tableColumn.identifier isEqualToString:@"job"]) {
        view.textField.stringValue = info.fullName ?: @"(terminated)";
    } else {
        view.textField.stringValue = [@(info.pid) stringValue];
    }
    return view;

}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    NSOutlineView *outlineView = notification.object;
    _forceQuit.enabled = (outlineView.selectedRow != -1);
}

@end
