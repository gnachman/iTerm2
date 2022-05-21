//
//  iTermJobTreeViewController.m
//  iTerm2
//
//  Created by George Nachman on 1/18/19.
//

#import "iTermJobTreeViewController.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermGraphicSource.h"
#import "iTermLSOF.h"
#import "iTermProcessCache.h"
#import "iTermWarning.h"
#import "NSAppearance+iTerm.h"
#import "NSArray+iTerm.h"
#import "NSFont+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSTableColumn+iTerm.h"
#import "NSTableView+iTerm.h"
#import "NSTextField+iTerm.h"

static const int kDefaultSignal = 9;
static int gSignalsToList[] = {
     1, // SIGHUP
     2, // SIGINTR
     3, // SIGQUIT
     6, // SIGABRT
     9, // SIGKILL
    15, // SIGTERM
};

@interface iTermJobTreeTextTableCellView: NSTableCellView
+ (instancetype)viewWithString:(NSString *)string font:(NSFont *)font from:(NSTableView *)tableView owner:(id)owner;
@end

@interface iTermJobTreeImageTableCellView: iTermJobTreeTextTableCellView
+ (instancetype)viewWithString:(NSString *)string image:(NSImage *)image font:(NSFont *)font from:(NSTableView *)tableView owner:(id)owner;
@end

@interface SignalPicker : NSComboBox <NSComboBoxDataSource>
- (BOOL)isValid;

@end

@implementation SignalPicker

+ (NSArray *)signalNames {
    return @[[NSNull null], @"HUP",  @"INT",  @"QUIT",
             @"ILL",   @"TRAP", @"ABRT",   @"EMT",
             @"FPE",   @"KILL", @"BUS",    @"SEGV",
             @"SYS",   @"PIPE", @"ALRM",   @"TERM",
             @"URG",   @"STOP", @"TSTP",   @"CONT",
             @"CHLD",  @"TTIN", @"TTOU",   @"IO",
             @"XCPU",  @"XFSZ", @"VTALRM", @"PROF",
             @"WINCH", @"INFO", @"USR1",   @"USR2"];
}

+ (int)signalForName:(NSString*)signalName {
    signalName = [[signalName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if ([signalName hasPrefix:@"SIG"]) {
        signalName = [signalName substringFromIndex:3];
    }
    int x = [signalName intValue];
    if (x > 0 && x < [[self signalNames] count]) {
        return x;
    }

    NSArray *signalNames = [self signalNames];
    NSUInteger index = [signalNames indexOfObject:signalName];
    if (index == NSNotFound) {
        return -1;
    } else {
        return index;
    }
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    [self setIntValue:kDefaultSignal];
    [self setUsesDataSource:YES];
    [self setCompletes:YES];
    [self setDataSource:self];
}

- (int)intValue {
    int x = [[self class] signalForName:[self stringValue]];
    return x == -1 ? kDefaultSignal : x;
}

- (void)setIntValue:(int)i {
    NSArray *signalNames = [[self class] signalNames];
    if (i <= 0 || i >= [signalNames count]) {
        i = kDefaultSignal;
    }
    [self setStringValue:signalNames[i]];
    [self setToolTip:[NSString stringWithFormat:@"SIG%@ (%d)", signalNames[i], i]];
}

- (BOOL)isValid {
    return [[self class] signalForName:[self stringValue]] != -1;
}

- (void)textDidEndEditing:(NSNotification *)aNotification {
    [self setIntValue:[self intValue]];
    id<NSComboBoxDelegate> comboBoxDelegate = (id<NSComboBoxDelegate>)[self delegate];
    [comboBoxDelegate comboBoxSelectionIsChanging:[NSNotification notificationWithName:NSComboBoxSelectionIsChangingNotification
                                                                                object:nil]];
}

- (void)textDidChange:(NSNotification *)notification {
    id<NSComboBoxDelegate> comboBoxDelegate = (id<NSComboBoxDelegate>)[self delegate];
    [comboBoxDelegate comboBoxSelectionIsChanging:[NSNotification notificationWithName:NSComboBoxSelectionIsChangingNotification
                                                                                object:nil]];
}

- (void)sizeToFit {
    NSRect frame = self.frame;
    frame.size.width = 70;  // Just wide enough for the widest signal name.
    self.frame = frame;
}

- (NSInteger)numberOfItemsInComboBox:(NSComboBox *)aComboBox {
    return sizeof(gSignalsToList) / sizeof(gSignalsToList[0]);
}

- (id)comboBox:(NSComboBox *)aComboBox objectValueForItemAtIndex:(NSInteger)index {
    NSArray *signalNames = [[self class] signalNames];
    return signalNames[gSignalsToList[index]];
}

- (NSUInteger)comboBox:(NSComboBox *)aComboBox indexOfItemWithStringValue:(NSString *)aString {
    if ([aString intValue] > 0) {
        return NSNotFound;  // Without this, "1", "2", and "3" get replaced immediately!
    }

    int sig = [[self class] signalForName:aString];
    for (int i = 0; i < sizeof(gSignalsToList) / sizeof(gSignalsToList[0]); i++) {
        if (gSignalsToList[i] == sig) {
            return i;
        }
    }
    return NSNotFound;
}

- (NSString *)comboBox:(NSComboBox *)aComboBox completedString:(NSString *)uncompletedString {
    uncompletedString =
        [[uncompletedString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if ([uncompletedString hasPrefix:@"SIG"]) {
        uncompletedString = [uncompletedString substringFromIndex:3];
    }

    if ([uncompletedString length] == 0) {
        return @"";
    }

    NSArray *signalNames = [[self class] signalNames];
    int x = [uncompletedString intValue];
    if (x > 0 && x < [signalNames count]) {
        return uncompletedString;
    }

    for (int i = 1; i < [signalNames count]; i++) {
        if ([signalNames[i] hasPrefix:uncompletedString]) {
            // Found a prefix match
            return signalNames[i];
        }
    }

    return nil;
}

@end

@interface iTermJobTreeViewController ()<NSOutlineViewDelegate, NSOutlineViewDataSource>
@end

@interface iTermJobProxy : NSObject
@property (nonatomic, strong) NSMutableArray<iTermJobProxy *> *children;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *fullName;
@property (nonatomic) pid_t pid;
@property (nonatomic) BOOL known;
@property (nonatomic, readonly) int depth;
@end

@implementation iTermJobProxy {
    NSString *_fullName;
}

- (instancetype)initWithProcessInfo:(iTermProcessInfo *)processInfo depth:(int)depth {
    self = [super init];
    if (self) {
        _depth = depth;
        _pid = processInfo.processID;
        _name = [(processInfo.argv0 ?: processInfo.name) copy];
        if (depth < 50) {
            _children = [[processInfo.sortedChildren mapWithBlock:^id(iTermProcessInfo *anObject) {
                return [[iTermJobProxy alloc] initWithProcessInfo:anObject depth:depth + 1];
            }] mutableCopy];
        }
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
    NSTimer *_timer;
    IBOutlet SignalPicker *signal_;  // TODO - use this
    IBOutlet NSButton *kill_;
    iTermGraphicSource *_graphicSource;
}

- (instancetype)initWithProcessID:(pid_t)pid
              processInfoProvider:(id<ProcessInfoProvider>)processInfoProvider {
    self = [super initWithNibName:@"iTermJobTreeViewController" bundle:[NSBundle bundleForClass:[iTermJobTreeViewController class]]];
    if (self) {
        _pid = pid;
        _animateChanges = YES;
        _graphicSource = [[iTermGraphicSource alloc] init];
        _graphicSource.disableTinting = YES;
        _processInfoProvider = processInfoProvider;
    }
    return self;
}

- (void)awakeFromNib {
    if (@available(macOS 10.16, *)) {
        kill_.image = [NSImage it_imageForSymbolName:@"play" accessibilityDescription:@"Clear"];
        _outlineView.style = NSTableViewStyleInset;
    }
    [self updateKillButtonEnabled];
}

- (void)viewDidAppear {
    kill_.enabled = (_outlineView.selectedRow != -1);

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

- (BOOL)anySelectedProcessHasChildren {
    __block BOOL result = NO;
    [_outlineView.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        iTermJobProxy *job = [self->_outlineView itemAtRow:idx];
        if (job.children.count > 0) {
            result = YES;
            *stop = YES;
        }
        return;
    }];
    return result;
}

- (BOOL)shouldQuit {
    NSString *description;
    const NSUInteger count = _outlineView.selectedRowIndexes.count;
    if (count == 0) {
        return NO;
    }
    if ([self anySelectedProcessHasChildren]) {
        if (count == 1) {
            description = @"one process and its children";
        } else {
            description = [NSString stringWithFormat:@"%@ processes and their children", @(count)];
        }
    } else {
        if (count == 1) {
            description = @"one process";
        } else {
            description = [NSString stringWithFormat:@"%@ processes", @(count)];
        }
    }

    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"Are you sure? This may terminate %@.", description]
                               actions:@[ @"OK", @"Cancel"]
                             accessory:nil
                            identifier:@"NoSyncSuppressSendSignal"
                           silenceable:kiTermWarningTypePermanentlySilenceable
                               heading:@"Confirmation Needed"
                                window:self.view.window];
    return selection == kiTermWarningSelection0;
}

- (IBAction)forceQuit:(id)sender {
    if (![self shouldQuit]) {
        return;
    }
    [_outlineView.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        iTermJobProxy *job = [self->_outlineView itemAtRow:idx];
        pid_t pid = job.pid;
        if (pid) {
            DLog(@"Send %d to %@", [signal_ intValue], @(pid));
            [self.processInfoProvider sendSignal:signal_.intValue
                                           toPID:pid];
            kill(pid, [signal_ intValue]);
        }
    }];
    [self update];
}

- (void)setProcessInfoProvider:(id<ProcessInfoProvider>)processInfoProvider {
    _processInfoProvider = processInfoProvider;
    [self update];
}

- (void)setPid:(pid_t)pid {
    if (pid == _pid) {
        return;
    }
    _pid = pid;
    _root = nil;
    [self update];
}

- (void)update {
    iTermProcessInfo *info = [self.processInfoProvider processInfoForPid:_pid];
    if (!info) {
        _root = nil;
        [_outlineView reloadData];
        return;
    }
    iTermJobProxy *newRoot = [[iTermJobProxy alloc] initWithProcessInfo:info depth:0];
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
            [_outlineView removeItemsAtIndexes:[NSIndexSet indexSetWithIndex:o + offset] inParent:old withAnimation:self.animateChanges];
            offset -= 1;
            [old.children removeObject:oldChild];
            o++;
        } else {
            DLog(@"Insert index %@ in %@", @(i), old);
            [_outlineView insertItemsAtIndexes:[NSIndexSet indexSetWithIndex:o + offset] inParent:old withAnimation:self.animateChanges];
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
        [_outlineView removeItemsAtIndexes:[NSIndexSet indexSetWithIndex:o + offset] inParent:old withAnimation:self.animateChanges];
        offset -= 1;
        [old.children removeObject:oldChildren[o]];
        o++;
    }
    while (n < newCount) {
        DLog(@"Insert index %@ in %@", @(i), old);
        [_outlineView insertItemsAtIndexes:[NSIndexSet indexSetWithIndex:o + offset] inParent:old withAnimation:self.animateChanges];
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

- (void)updateKillButtonEnabled {
    const BOOL shouldBeEnabled = (_outlineView.selectedRowIndexes.count > 0 && [signal_ isValid]);
    signal_.enabled = shouldBeEnabled;
    kill_.enabled = shouldBeEnabled;
}

- (void)setFont:(NSFont *)font {
    [self view];
    _font = font;
    _outlineView.rowSizeStyle =  NSTableViewRowSizeStyleCustom;
    _outlineView.rowHeight = [NSTableView heightForTextCellUsingFont:font];
    [_outlineView reloadData];
}

- (void)sizeOutlineViewToFit {
    NSRect frame = NSZeroRect;
    const NSSize fittingSize = [_outlineView fittingSize];
    const NSSize contentSize = [_outlineView.enclosingScrollView contentSize];
    frame.size = NSMakeSize(MAX(fittingSize.width, contentSize.width),
                            fittingSize.height);
    _outlineView.frame = frame;

    // Figure out what the column widths need to sum to. I can't find a sane way to do this, so do it in a dumb way instead.
    [_outlineView sizeLastColumnToFit];
    const CGFloat totalWidth = _outlineView.tableColumns[0].width + _outlineView.tableColumns[1].width;

    const CGFloat pidWidth = [[[[self tableCellViewWithString:@"MMMMMM" image:nil isJob:NO] textField] cell] cellSizeForBounds:_outlineView.bounds].width;
    _outlineView.tableColumns.lastObject.width = pidWidth;
    _outlineView.tableColumns.firstObject.width = totalWidth - pidWidth;
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
    NSString *string;
    NSImage *image = nil;
    const BOOL isJob = [tableColumn.identifier isEqualToString:@"job"];
    if (isJob) {
        string = info.fullName ?: @"(terminated)";
        NSImage *rawImage = [_graphicSource imageForJobName:info.name];
        if (rawImage) {
            image = [NSImage imageWithSize:rawImage.size flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
                NSColor *tint;
                if (self.view.effectiveAppearance.it_isDark) {
                    tint = [NSColor colorWithWhite:1 alpha:1];
                } else {
                    tint = [NSColor colorWithWhite:0 alpha:1];
                }
                NSImage *tinted = [rawImage it_imageWithTintColor:tint];
                [tinted drawInRect:dstRect
                          fromRect:NSZeroRect
                         operation:NSCompositingOperationSourceOver
                          fraction:0.5];
                return YES;
            }];
        }
    } else {
        string = [@(info.pid) stringValue];
    }
    return [self tableCellViewWithString:string image:image isJob:isJob];
}

- (NSTableCellView *)tableCellViewWithString:(NSString *)string image:(NSImage *)image isJob:(BOOL)isJob {
    NSFont *font = self.font ?: [NSFont systemFontOfSize:[NSFont systemFontSize]];
    if (isJob && image != nil) {
        return [iTermJobTreeImageTableCellView viewWithString:string
                                                        image:image
                                                         font:font
                                                         from:_outlineView
                                                        owner:self];
    } else {
        return [iTermJobTreeTextTableCellView viewWithString:string
                                                        font:font
                                                        from:_outlineView
                                                       owner:self];
    }

}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    [self updateKillButtonEnabled];
}

- (id<NSPasteboardWriting>)outlineView:(NSOutlineView *)outlineView pasteboardWriterForItem:(id)item {
    iTermJobProxy *info = item ?: _root;
    NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
    NSString *aString = [@(info.pid) stringValue];
    [pbItem setString:aString forType:(NSString *)kUTTypeUTF8PlainText];
    return pbItem;
}

#pragma mark - NSComboBoxDelegate

- (void)comboBoxSelectionIsChanging:(NSNotification *)notification {
    [self updateKillButtonEnabled];
}

@end

@implementation iTermJobTreeTextTableCellView

+ (instancetype)viewWithString:(NSString *)string font:(NSFont *)font from:(NSTableView *)tableView owner:(id)owner {
    iTermJobTreeImageTableCellView *view = [tableView makeViewWithIdentifier:NSStringFromClass(self) owner:owner];
    if (!view) {
        view = [[self alloc] init];
        view.autoresizesSubviews = NO;

        NSTextField *textField = [NSTextField newLabelStyledTextField];
        textField.font = font;
        view.textField = textField;
        [view addSubview:textField];
        textField.frame = view.bounds;
    }
    view.textField.stringValue = string;
    [view layoutSubviews];
    return view;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [self layoutSubviews];
}

- (void)layoutSubviews {
    [self layoutTextFieldWithLeftInset:0];
}

- (void)layoutTextFieldWithLeftInset:(CGFloat)leftInset {
    [self.textField sizeToFit];
    const CGFloat width = MAX(NSWidth(self.textField.bounds), NSWidth(self.bounds));
    self.textField.frame = NSMakeRect(leftInset, -2, width - leftInset, NSHeight(self.textField.frame) + 4);
}

@end

@implementation iTermJobTreeImageTableCellView

+ (instancetype)viewWithString:(NSString *)string image:(NSImage *)image font:(NSFont *)font from:(NSTableView *)tableView owner:(id)owner {
    iTermJobTreeImageTableCellView *view = [tableView makeViewWithIdentifier:NSStringFromClass(self) owner:owner];
    if (!view) {
        view = [self viewWithString:string font:font from:tableView owner:owner];
    }
    NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 2, 2)];
    if (image) {
        imageView.image = image;
    }
    imageView.alphaValue = 0.75;
    [view addSubview:imageView];
    view.imageView = imageView;
    [view layoutSubviews];
    return view;
}

- (void)setFrame:(NSRect)frame {
    [super setFrame:frame];
    [self layoutSubviews];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [self layoutSubviews];
}

- (void)layoutSubviews {
    const CGFloat height = [self.textField fittingSize].height;
    const CGFloat margin = 4;
    [self layoutTextFieldWithLeftInset:height + margin];

    self.imageView.frame = NSMakeRect(0, NSMaxY(self.textField.frame) - height, height, height);
}
@end

