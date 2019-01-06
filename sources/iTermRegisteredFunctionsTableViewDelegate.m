//
//  iTermRegisteredFunctionsTableViewDelegate.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/5/19.
//

#import "iTermRegisteredFunctionsTableViewDelegate.h"
#import "iTermAPIHelper.h"
#import "iTermScriptHistory.h"
#import "NSArray+iTerm.h"
#import "NSTextField+iTerm.h"

@interface iTermRegisteredFunctionProxy : NSObject
@property (nonatomic, readonly) NSString *signature;
@property (nonatomic, readonly) NSString *role;
@property (nonatomic, readonly) NSString *script;
@end

@implementation iTermRegisteredFunctionProxy
- (instancetype)initWithSignature:(NSString *)signature
                             role:(NSString *)role
                           script:(NSString *)script {
    self = [super init];
    if (self) {
        _signature = [signature copy];
        _role = [role copy];
        _script = [script copy];
    }
    return self;
}
@end

@implementation iTermRegisteredFunctionsTableViewDelegate {
    NSArray<iTermRegisteredFunctionProxy *> *_rows;
    IBOutlet NSTableView *_tableView;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self loadRows];
    }
    return self;
}

- (void)loadRows {
    NSDictionary<NSString *, iTermTuple<id, ITMNotificationRequest *> *> *subs = [[iTermAPIHelper sharedInstance] serverOriginatedRPCSubscriptions];
    _rows = [subs.allKeys mapWithBlock:^id(NSString *signature) {
        NSString *role = @"RPC";
        switch (subs[signature].secondObject.rpcRegistrationRequest.role) {
            case ITMRPCRegistrationRequest_Role_Generic:
                role = @"RPC";
                break;
            case ITMRPCRegistrationRequest_Role_SessionTitle:
                role = @"Title Provider";
                break;
            case ITMRPCRegistrationRequest_Role_StatusBarComponent:
                role = @"Status Bar Component";
                break;
        }
        id connectionKey = subs[signature].firstObject;
        iTermScriptHistoryEntry *entry =  [[iTermAPIHelper sharedInstance] scriptHistoryEntryForConnectionKey:connectionKey];
        NSString *script = entry.name ?: @"Unknown";
        return [[iTermRegisteredFunctionProxy alloc] initWithSignature:signature role:role script:script];
    }];
}

- (void)reload {
    [self loadRows];
    [_tableView reloadData];
}

- (NSString *)stringForProxy:(iTermRegisteredFunctionProxy *)proxy
            columnIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"signature"]) {
        return proxy.signature;
    }
    if ([identifier isEqualToString:@"role"]) {
        return proxy.role;
    }
    if ([identifier isEqualToString:@"script"]) {
        return proxy.script;
    }
    assert(NO);
    return nil;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _rows.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    iTermRegisteredFunctionProxy *proxy = _rows[row];

    NSString *identifier = [NSString stringWithFormat:@"%@_%@", NSStringFromClass(proxy.class), tableColumn.identifier];
    NSTableCellView *view = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!view) {
        view = [[NSTableCellView alloc] init];

        NSTextField *textField = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
        textField.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
        view.textField = textField;
        [view addSubview:textField];
        textField.frame = view.bounds;
        textField.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
    }
    view.textField.stringValue = [self stringForProxy:proxy columnIdentifier:tableColumn.identifier];
    return view;

}
@end
