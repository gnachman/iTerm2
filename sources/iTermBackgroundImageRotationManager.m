#import "iTermBackgroundImageRotationManager.h"

#import <AppKit/AppKit.h>

#import "ITAddressBookMgr.h"
#import "iTermProfilePreferences.h"

NSString *const iTermBackgroundImageRotationDidChangeNotification = @"iTermBackgroundImageRotationDidChangeNotification";

@interface iTermBackgroundImageRotationState : NSObject

@property(nonatomic, copy) NSString *guid;
@property(nonatomic, copy, nullable) NSString *folder;
@property(nonatomic) NSInteger interval;
@property(nonatomic, copy, nullable) NSString *currentImage;
@property(nonatomic, copy) NSArray<NSString *> *deck;
@property(nonatomic, strong, nullable) dispatch_source_t timer;
@property(nonatomic) NSUInteger generation;

@end

@implementation iTermBackgroundImageRotationState
@end

@interface iTermBackgroundImageRotationManager ()

@property(nonatomic, strong) NSMutableDictionary<NSString *, iTermBackgroundImageRotationState *> *states;
@property(nonatomic, strong) dispatch_queue_t queue;

@end

@implementation iTermBackgroundImageRotationManager

+ (instancetype)sharedInstance {
    static iTermBackgroundImageRotationManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initPrivate];
    });
    return instance;
}

- (instancetype)init {
    assert(NO);
    return [self initPrivate];
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _states = [[NSMutableDictionary alloc] init];
        _queue = dispatch_queue_create("com.iterm2.background-image-rotation", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (NSString *)backgroundImagePathForProfile:(NSDictionary *)profile {
    NSString *guid = profile[KEY_GUID];
    if (guid.length == 0) {
        return nil;
    }
    if ([iTermProfilePreferences unsignedIntegerForKey:KEY_BACKGROUND_IMAGE_SOURCE_MODE inProfile:profile] != iTermBackgroundImageSourceModeFolderRotation) {
        return profile[KEY_BACKGROUND_IMAGE_LOCATION];
    }
    __block NSString *path = nil;
    dispatch_sync(self.queue, ^{
        iTermBackgroundImageRotationState *state = [self stateForProfileLocked:profile];
        path = state.currentImage;
    });
    return path;
}

- (void)profileDidChange:(NSDictionary *)profile {
    NSString *guid = profile[KEY_GUID];
    if (guid.length == 0) {
        return;
    }
    dispatch_async(self.queue, ^{
        if ([iTermProfilePreferences unsignedIntegerForKey:KEY_BACKGROUND_IMAGE_SOURCE_MODE inProfile:profile] != iTermBackgroundImageSourceModeFolderRotation) {
            [self invalidateStateLockedForGUID:guid];
            return;
        }
        iTermBackgroundImageRotationState *state = [self stateForProfileLocked:profile];
        NSString *previousImage = state.currentImage;
        [self reconfigureTimerLockedForState:state];
        if (![previousImage isEqualToString:state.currentImage]) {
            [self postDidChangeForGUID:guid];
        }
    });
}

- (void)invalidateProfileGUID:(NSString *)guid {
    if (guid.length == 0) {
        return;
    }
    dispatch_async(self.queue, ^{
        [self invalidateStateLockedForGUID:guid];
    });
}

#pragma mark - Locked helpers

- (iTermBackgroundImageRotationState *)stateForProfileLocked:(NSDictionary *)profile {
    NSString *guid = profile[KEY_GUID];
    iTermBackgroundImageRotationState *state = self.states[guid];
    if (!state) {
        state = [[iTermBackgroundImageRotationState alloc] init];
        state.guid = guid;
        state.deck = @[];
        self.states[guid] = state;
    }
    NSString *folder = [iTermProfilePreferences stringForKey:KEY_BACKGROUND_IMAGE_FOLDER_LOCATION inProfile:profile];
    NSInteger interval = [iTermProfilePreferences integerForKey:KEY_BACKGROUND_IMAGE_FOLDER_INTERVAL inProfile:profile];
    interval = MAX(interval, 1);
    BOOL needsRescan = ![state.folder isEqualToString:folder] || state.interval != interval || state.currentImage == nil;
    state.folder = folder;
    state.interval = interval;
    if (needsRescan) {
        [self selectNextImageLockedForState:state];
    }
    return state;
}

- (void)invalidateStateLockedForGUID:(NSString *)guid {
    iTermBackgroundImageRotationState *state = self.states[guid];
    if (!state) {
        return;
    }
    if (state.timer) {
        dispatch_source_cancel(state.timer);
        state.timer = nil;
    }
    [self.states removeObjectForKey:guid];
}

- (void)reconfigureTimerLockedForState:(iTermBackgroundImageRotationState *)state {
    if (state.timer) {
        dispatch_source_cancel(state.timer);
        state.timer = nil;
    }
    if (state.folder.length == 0) {
        return;
    }
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
    state.timer = timer;
    state.generation += 1;
    NSUInteger generation = state.generation;
    uint64_t intervalNsec = (uint64_t)state.interval * NSEC_PER_SEC;
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, intervalNsec),
                              intervalNsec,
                              NSEC_PER_SEC / 10);
    __weak __typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        iTermBackgroundImageRotationState *strongState = strongSelf.states[state.guid];
        if (!strongState || strongState.generation != generation) {
            return;
        }
        NSString *previousImage = strongState.currentImage;
        [strongSelf selectNextImageLockedForState:strongState];
        if (![previousImage isEqualToString:strongState.currentImage]) {
            [strongSelf postDidChangeForGUID:strongState.guid];
        }
    });
    dispatch_resume(timer);
}

- (void)selectNextImageLockedForState:(iTermBackgroundImageRotationState *)state {
    NSArray<NSString *> *images = [self sortedImagePathsInFolder:state.folder];
    if (images.count == 0) {
        state.deck = @[];
        state.currentImage = nil;
        return;
    }
    if (images.count == 1) {
        state.deck = @[];
        state.currentImage = images.firstObject;
        return;
    }
    NSMutableArray<NSString *> *deck = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSString *image in state.deck) {
        if ([images containsObject:image] &&
            ![image isEqualToString:state.currentImage] &&
            ![seen containsObject:image]) {
            [deck addObject:image];
            [seen addObject:image];
        }
    }
    for (NSString *image in images) {
        if (![image isEqualToString:state.currentImage] && ![seen containsObject:image]) {
            [deck addObject:image];
            [seen addObject:image];
        }
    }
    if (deck.count == 0) {
        [deck addObjectsFromArray:images];
        [deck removeObject:state.currentImage];
        [self shuffleArray:deck];
    }
    NSString *next = deck.firstObject;
    if (!next) {
        next = state.currentImage ?: images.firstObject;
    }
    if ([next isEqualToString:state.currentImage]) {
        for (NSString *candidate in images) {
            if (![candidate isEqualToString:state.currentImage]) {
                next = candidate;
                break;
            }
        }
    }
    if (deck.count > 0 && [deck.firstObject isEqualToString:next]) {
        [deck removeObjectAtIndex:0];
    } else {
        [deck removeObject:next];
    }
    state.currentImage = next;
    state.deck = deck.copy;
}

- (NSArray<NSString *> *)sortedImagePathsInFolder:(NSString *)folder {
    if (folder.length == 0) {
        return @[];
    }
    NSURL *folderURL = [NSURL fileURLWithPath:[folder stringByExpandingTildeInPath] isDirectory:YES];
    NSArray<NSURL *> *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:folderURL
                                                               includingPropertiesForKeys:@[ NSURLIsRegularFileKey, NSURLIsHiddenKey ]
                                                                                  options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                    error:nil];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (NSURL *url in contents) {
        NSNumber *isRegularFile = nil;
        [url getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil];
        if (!isRegularFile.boolValue) {
            continue;
        }
        if ([[NSImage alloc] initWithContentsOfFile:url.path]) {
            [result addObject:url.path];
        }
    }
    [result sortUsingComparator:^NSComparisonResult(NSString *lhs, NSString *rhs) {
        return [lhs.lastPathComponent localizedStandardCompare:rhs.lastPathComponent];
    }];
    return result;
}

- (void)shuffleArray:(NSMutableArray<NSString *> *)array {
    for (NSUInteger i = array.count; i > 1; i--) {
        [array exchangeObjectAtIndex:i - 1 withObjectAtIndex:arc4random_uniform((u_int32_t)i)];
    }
}

- (void)postDidChangeForGUID:(NSString *)guid {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermBackgroundImageRotationDidChangeNotification
                                                            object:guid];
    });
}

@end
