//
//  iTermGraphicSource.m
//  iTerm2
//
//  Created by George Nachman on 9/7/18.
//

#import "iTermGraphicSource.h"

#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermProcessCache.h"
#import "iTermTextExtractor.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

#import <os/lock.h>

NSString *const iTermGraphicSourceDidReloadNotification = @"iTermGraphicSourceDidReloadNotification";

// Guards sGraphicColorMap/sGraphicIconMap and the rendered-image cache. They were once written only
// inside dispatch_once, but +reloadGraphicMaps can now reassign the maps and clear the cache at
// runtime (after a settings-sync import) while session icon updates read them off the main thread,
// so all access takes this lock.
static os_unfair_lock sGraphicMapLock = OS_UNFAIR_LOCK_INIT;
static NSDictionary *sGraphicColorMap;
static NSDictionary *sGraphicIconMap;
// Bumped on every +reloadGraphicMaps. A reader captures it with its map snapshot and refuses to
// write a freshly-computed image into the cache if the generation has since changed, so an image
// computed from the pre-reload maps can't land in the just-cleared cache and be served stale.
static uint64_t sGraphicMapGeneration;

@interface NSDictionary (Graphic)
- (NSDictionary *)it_invertedGraphicDictionary;
@end

@implementation NSDictionary (Graphic)

- (NSDictionary *)it_invertedGraphicDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [self enumerateKeysAndObjectsUsingBlock:^(id graphicName, id obj, BOOL * _Nonnull stop) {
        // graphic_icons.json now syncs between machines, so it may be malformed (corrupt, or
        // hand-edited on another Mac). Validate structure instead of trusting it: a non-array value
        // would crash the for-in enumeration below (an NSString/NSNumber does not conform to
        // NSFastEnumeration), and a non-string key or element would produce a garbage mapping.
        if (![graphicName isKindOfClass:[NSString class]] || ![obj isKindOfClass:[NSArray class]]) {
            return;
        }
        for (id appName in obj) {
            if (![appName isKindOfClass:[NSString class]]) {
                continue;
            }
            [dict it_addObject:graphicName toMutableArrayForKey:appName];
        }
    }];
    return dict;
}

@end

@implementation iTermGraphicSource

- (instancetype)init {
    self = [super init];
    if (self) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            [iTermGraphicSource reloadGraphicMaps];
        });
    }
    return self;
}

// Load one graphic map: parse the bundle JSON resource (optionally transforming it, e.g. inverting the
// icon dictionary), merge a parsed app-support override on top, and - only when the override is present
// but UNPARSEABLE - fall back to `previousMap` rather than reverting to bundle-only. Shared by the color
// and icon paths in +reloadGraphicMaps so those subtle rules can't drift between the two. The app-support
// filenames come from the sync allowlist's constants (not literals) so the on-disk names and the synced
// allowlist can't silently diverge; the bundle resource names are the app's own resources, not synced.
+ (NSDictionary *)loadGraphicMapFromBundleResource:(NSString *)bundleResource
                                    appSupportName:(NSString *)appSupportName
                                       previousMap:(NSDictionary *)previousMap
                                         transform:(NSDictionary *(^)(NSDictionary *))transform {
    NSDictionary *(^parse)(NSData *) = ^NSDictionary *(NSData *data) {
        if (!data) {
            return nil;
        }
        NSDictionary *dict = [NSDictionary castFrom:[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]];
        if (!dict) {
            return nil;
        }
        return transform ? transform(dict) : dict;
    };

    NSString *bundlePath = [[NSBundle bundleForClass:self] pathForResource:bundleResource ofType:@"json"];
    NSDictionary *map = parse([NSData dataWithContentsOfFile:bundlePath options:0 error:nil]);

    NSString *appSupport = [[NSFileManager defaultManager] applicationSupportDirectory];
    NSString *overridePath = [appSupport stringByAppendingPathComponent:appSupportName];
    // Read the override bytes ONCE so "file absent" (skip) is distinguished from "present but unparseable"
    // (fall back to previousMap): parse(nil) can't tell those apart, but a nil `data` here means absent.
    NSData *overrideData = [NSData dataWithContentsOfFile:overridePath options:0 error:nil];
    if (overrideData) {
        NSDictionary *override = parse(overrideData);
        if (override) {
            // Merge over the bundle map, or use the override directly if the bundle map failed to load
            // (merging INTO nil returns nil, which would silently discard a valid custom map).
            map = map ? [map dictionaryByMergingDictionary:override] : override;
        } else if (previousMap) {
            // Present but unparseable: keep the previously-loaded good map instead of reverting to
            // bundle-only. It will re-merge once the file parses again.
            map = previousMap;
        }
    }
    return map;
}

+ (void)reloadGraphicMaps {
    // NOT asserted main-thread at entry: the map mutation is fully lock-protected (see below), so
    // construction/first-load stays thread-agnostic (as it was before this file synced at runtime) - a
    // future off-main first construction must not become a hard crash. The ONE part that genuinely
    // requires the main thread is the SYNCHRONOUS notification post at the end (observers must run inside
    // the caller's _applyingRemoteDataFilesDepth suppression window); the assert lives there. That post
    // only fires on a runtime reload (hadMaps && mapsChanged), whose sole caller
    // (applyImportedRemoteDataFilesForItems:) is already main-thread; the first load posts nothing.
    //
    // The compare-and-publish below IS a single critical section (both maps assigned together, generation
    // bump, cache flush), so no torn pair is ever published; the only non-atomicity is that the
    // previous-map snapshot here (used solely for the parse-failure fallback) may be slightly stale if
    // another call publishes during the parse phase - benign, and only for the corrupt-file edge. Parsing
    // is deliberately OUTSIDE the lock (it does file I/O; an os_unfair_lock must not be held across it).
    //
    // Snapshot the currently-loaded maps so a present-but-unparseable app-support file (e.g. a corrupt
    // graphic_*.json synced from another machine) can fall back to them rather than reverting the
    // user's customizations to bundle-only. Now that this runs at runtime after a sync import, a
    // reversion would visibly wipe custom icons/colors until a valid file loads.
    os_unfair_lock_lock(&sGraphicMapLock);
    NSDictionary *previousColorMap = sGraphicColorMap;
    NSDictionary *previousIconMap = sGraphicIconMap;
    os_unfair_lock_unlock(&sGraphicMapLock);

    // The color and icon maps load by the identical recipe (bundle JSON, merge an app-support override
    // over it, keep the previous map if the override is present-but-unparseable), differing only in the
    // resource/override names and whether the JSON is inverted. Factor it so the subtle fallback rules
    // (merge-into-nil discards a valid custom map; unparseable keeps the previous map) live in one place.
    NSDictionary *colorMap = [self loadGraphicMapFromBundleResource:@"graphic_colors"
                                                     appSupportName:iTermRemoteDataFileSync.graphicColorsName
                                                        previousMap:previousColorMap
                                                          transform:nil];
    NSDictionary *iconMap = [self loadGraphicMapFromBundleResource:@"graphic_icons"
                                                    appSupportName:iTermRemoteDataFileSync.graphicIconsName
                                                       previousMap:previousIconMap
                                                         transform:^NSDictionary *(NSDictionary *parsed) {
        return [parsed it_invertedGraphicDictionary];
    }];

    os_unfair_lock_lock(&sGraphicMapLock);
    // Post a "recompute your icon" nudge only when maps were already loaded AND the new maps actually
    // differ. This avoids a startup recompute storm on the initial load (no maps yet) regardless of
    // whether the first +reloadGraphicMaps comes from -init's dispatch_once or from a settings-sync
    // import, and also skips a notification when a reload produces identical maps.
    const BOOL hadMaps = (sGraphicColorMap != nil || sGraphicIconMap != nil);
    const BOOL mapsChanged = (![NSObject object:sGraphicColorMap isEqualToObject:colorMap] ||
                              ![NSObject object:sGraphicIconMap isEqualToObject:iconMap]);
    if (mapsChanged) {
        sGraphicColorMap = colorMap;
        sGraphicIconMap = iconMap;
        sGraphicMapGeneration += 1;
        // Drop rendered images: their icon/color may have changed, so they must be recomputed with the
        // new maps rather than served stale from the cache. Do this ONLY when the maps actually changed
        // - a no-op reload (dispatch_once after a direct reload, or a byte-identical synced JSON) must
        // not discard every cached tinted image and force a full re-render+re-tint on the next lookup.
        [CachedGraphicImagesLocked() removeAllObjects];
    }
    os_unfair_lock_unlock(&sGraphicMapLock);

    if (hadMaps && mapsChanged) {
        // The synchronous post is the one genuinely main-thread-only step: it must run inside the
        // caller's _applyingRemoteDataFilesDepth suppression window (main-thread-only state), and its
        // observers touch AppKit. Assert here rather than at entry so first-load/construction stays
        // thread-agnostic. Its sole caller (applyImportedRemoteDataFilesForItems:) is main-thread.
        ITAssertWithMessage([NSThread isMainThread],
                            @"reloadGraphicMaps must post the reload notification on the main thread");
        // Post SYNCHRONOUSLY (the map lock is released). A synchronous post keeps observers inside the
        // suppression window so a future observer that writes synced state can't re-arm a push of the
        // freshly-imported maps (an async post would run a runloop turn later, after the depth dropped).
        [[NSNotificationCenter defaultCenter] postNotificationName:iTermGraphicSourceDidReloadNotification
                                                            object:nil];
    }
}

- (BOOL)updateImageForProcessID:(pid_t)pid
                        enabled:(BOOL)enabled
            processInfoProvider:(id<ProcessInfoProvider>)processInfoProvider {
    NSImage *image = [self imageForProcessID:pid
                                     enabled:enabled
                         processInfoProvider:processInfoProvider];
    if (image == self.image) {
        return NO;
    }
    _image = image;
    return YES;
}

- (BOOL)updateImageForJobName:(NSString *)name enabled:(BOOL)enabled {
    NSImage *image = [self imageForJobName:name enabled:enabled];
    if (image == self.image) {
        return NO;
    }
    _image = image;
    return YES;
}

- (NSImage *)imageForProcessID:(pid_t)pid
                       enabled:(BOOL)enabled
           processInfoProvider:(id<ProcessInfoProvider>)processInfoProvider {
    if (!enabled) {
        return nil;
    }
    iTermProcessInfo *info = [processInfoProvider displayForegroundJobForPid:pid];
    if (!info) {
        return nil;
    }

    NSImage *image = [self iconImageForProcessInfo:info];
    if (image) {
        return image;
    }

    // Fallback: the deepest foreground job didn't match any icon, so walk up the parent
    // chain looking for one that does. This handles cases like claude → awk where the
    // child has no icon but a non-shell ancestor does. Stop at the login shell (argv0
    // starts with "-") or iTermServer.
    iTermProcessInfo *ancestor = info.parent;
    int depth = 0;
    while (ancestor && depth < 50) {
        NSString *title = ancestor.argv0 ?: ancestor.name;
        if ([title hasPrefix:@"-"] || [title hasPrefix:@"iTermServer"]) {
            break;
        }
        image = [self iconImageForProcessInfo:ancestor];
        if (image) {
            return image;
        }
        ancestor = ancestor.parent;
        depth++;
    }

    // No graphic match — fall back to the default (letter) image for the deepest job,
    // preferring argv0 over name so a versioned symlink target like 2.1.121 still
    // shows "C" for claude.
    return [self imageForJobName:[self preferredFallbackNameForProcessInfo:info] enabled:YES];
}

- (NSString *)preferredFallbackNameForProcessInfo:(iTermProcessInfo *)info {
    NSString *raw = info.argv0 ?: info.commandLine ?: info.name;
    return [[raw componentsInShellCommand] firstObject].lastPathComponent;
}

- (NSImage *)iconImageForProcessInfo:(iTermProcessInfo *)info {
    for (NSString *candidate in [self iconCandidateNamesForProcessInfo:info]) {
        NSImage *image = [self imageForJobName:candidate];
        if (image) {
            // imageForJobName: already cached this under the normalized command, with a generation
            // check, so we don't write the cache here.
            return image;
        }
    }
    return nil;
}

- (NSArray<NSString *> *)iconCandidateNamesForProcessInfo:(iTermProcessInfo *)info {
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    void (^addCandidate)(NSString *) = ^(NSString *raw) {
        NSString *first = [[raw componentsInShellCommand] firstObject].lastPathComponent;
        if (first.length > 0 && ![candidates containsObject:first]) {
            [candidates addObject:first];
        }
    };
    addCandidate(info.name);
    addCandidate(info.argv0);
    addCandidate(info.commandLine);
    return candidates;
}

- (NSString *)normalizedCommand:(NSString *)nonnormalCommand {
    // A little hack for emacs. So far I haven't found anything else that needs normalization.
    if ([nonnormalCommand hasPrefix:@"Emacs-"] || [nonnormalCommand hasPrefix:@"emacs-"]) {
        return @"emacs";
    }
    if ([nonnormalCommand hasPrefix:@"Python"] || [nonnormalCommand hasPrefix:@"python"]) {
        NSString *suffix = [nonnormalCommand substringFromIndex:[@"python" length]];
        if ([suffix rangeOfCharacterFromSet:[NSCharacterSet letterCharacterSet]].location == NSNotFound) {
            // python followed by non-letters, e.g. python3.7
            return @"python";
        }
    }
    return nonnormalCommand;
}

// Raw accessor: callers must already hold sGraphicMapLock.
static NSMutableDictionary *CachedGraphicImagesLocked(void) {
    static NSMutableDictionary *images;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        images = [NSMutableDictionary dictionary];
    });
    return images;
}

- (NSImage *)imageForJobName:(NSString *)command enabled:(BOOL)enabled {
    if (!enabled || !command) {
        return nil;
    }
    NSImage *graphic = [self imageForJobName:command];
    if (graphic) {
        // Map-derived; imageForJobName: cached it internally with a generation check.
        return graphic;
    }
    // No map entry (the common case: vim, less, bash, ...). Fall back to the map-independent default
    // (letter) image, cached under the RAW command. The letter image's tint comes from
    // randomTintColorForString: of the raw command, so two versioned commands that normalize to the
    // same name (e.g. "python3.11" and "python3.9") must get DISTINCT cache entries or they would share
    // one tint. Caching under the raw command still returns the SAME NSImage pointer for repeated
    // lookups of one command, so the no-op suppression in updateImageForProcessID:/updateImageForJobName:
    // still skips redundant tab redraws. (The map-derived path in -imageForJobName: correctly keys on
    // the NORMALIZED name, because there the icon is shared across versions; the letter tint is not.)
    // Untinted instances (disableTinting) must neither read nor write the shared tinted cache.
    NSString *normalized = [self normalizedCommand:command];
    const BOOL useCache = !self.disableTinting;
    if (useCache) {
        os_unfair_lock_lock(&sGraphicMapLock);
        NSImage *cached = CachedGraphicImagesLocked()[command];
        os_unfair_lock_unlock(&sGraphicMapLock);
        if (cached) {
            return cached;
        }
    }
    NSImage *defaultImage = [self defaultImageForCommand:command];
    if (defaultImage && useCache) {
        os_unfair_lock_lock(&sGraphicMapLock);
        // Only cache the default if the command still has no map entry (checked on the normalized name,
        // which is how the map is keyed). A reload between computing this default and writing it could
        // have given the command a real custom icon; caching a default in that now-occupied slot would
        // shadow the new icon until the next reload.
        if ([sGraphicIconMap[normalized] firstObject] == nil) {
            CachedGraphicImagesLocked()[command] = defaultImage;
        }
        os_unfair_lock_unlock(&sGraphicMapLock);
    }
    return defaultImage;
}

- (NSImage *)imageForJobName:(NSString *)jobName {
    NSString *command = [self normalizedCommand:jobName];
    // The shared cache holds TINTED images (the tab paths). An untinted instance (the Processes tool
    // sets disableTinting=YES) must neither read nor write it: reading would serve a wrong-color
    // tinted image, and writing would poison every tab with an untinted one. Such instances bypass
    // the cache and compute fresh (not a hot path).
    const BOOL useCache = !self.disableTinting;
    // Snapshot both maps and the cached image under the lock, capturing the generation so a write
    // back can be dropped if a +reloadGraphicMaps lands between this read and the write. The local
    // map references retain the dictionaries so a concurrent reload can't release them mid-read.
    os_unfair_lock_lock(&sGraphicMapLock);
    NSDictionary *iconMap = sGraphicIconMap;
    NSDictionary *colorMap = sGraphicColorMap;
    NSImage *cached = useCache ? CachedGraphicImagesLocked()[command] : nil;
    const uint64_t generation = sGraphicMapGeneration;
    os_unfair_lock_unlock(&sGraphicMapLock);
    NSString *logicalName = [iconMap[command] firstObject];
    if (!logicalName) {
        return nil;
    }
    if (cached) {
        return cached;
    }

    NSString *iconName = [@"graphic_" stringByAppendingString:logicalName];
    NSImage *image = [NSImage it_imageNamed:iconName forClass:[self class]];
    if (!image) {
        NSString *const appSupport = [[NSFileManager defaultManager] applicationSupportDirectory];
        NSString *path = [appSupport stringByAppendingPathComponent:[iconName stringByAppendingPathExtension:@"png"]];
        image = [NSImage it_imageWithScaledBitmapFromFile:path pointSize:NSMakeSize(16, 16)];
    }
    // graphic_colors.json now syncs between machines, so a value may be malformed (not a string).
    // Cast so a non-string falls through to the default rather than crashing -colorFromHexString:,
    // which sends -hasPrefix: to whatever it's given.
    NSString *colorCode = [NSString castFrom:colorMap[command]];
    if (!colorCode) {
        colorCode = [NSString castFrom:colorMap[logicalName]];
    }
    if (!colorCode) {
        colorCode = @"#888";
    }
    image = [self image:image tinted:colorCode];

    // Cache it, but only for tinting instances (see useCache above) and only if no reload happened
    // since the snapshot; otherwise this image was computed from now-stale maps and must not poison
    // the cache.
    if (image && useCache) {
        os_unfair_lock_lock(&sGraphicMapLock);
        if (generation == sGraphicMapGeneration) {
            CachedGraphicImagesLocked()[command] = image;
        }
        os_unfair_lock_unlock(&sGraphicMapLock);
    }
    return image;
}

- (NSImage *)image:(NSImage *)image tinted:(NSString *)colorCode {
    if (self.disableTinting) {
        return image;
    }

    NSColor *color = [NSColor colorFromHexString:colorCode];
    image = [image it_imageWithTintColor:color];
    return image;
}

- (NSImage *)defaultImageForCommand:(NSString *)jobName {
    if (![iTermAdvancedSettingsModel defaultIconsUsingLetters]) {
        return nil;
    }
    NSString *command = [self normalizedCommand:jobName];
    if (command.length == 0) {
        return nil;
    }
    NSString *firstLetter = [jobName firstComposedCharacter:nil];
    NSImage *image = [self imageForLetter:firstLetter];
    return [self image:image tinted:[self randomTintColorForString:jobName]];
}

- (NSImage *)imageForLetter:(NSString *)letter {
    const NSSize size = NSMakeSize(16, 16);
    return [NSImage imageOfSize:size drawBlock:^{
        // Set up the font and style
        NSFont *font = [NSFont boldSystemFontOfSize:12];
        NSDictionary *attributes = @{NSFontAttributeName: font,
                                     NSForegroundColorAttributeName: [NSColor blackColor] };

        // Create attributed string
        NSAttributedString *attrStr = [[NSAttributedString alloc] initWithString:[letter uppercaseString]
                                                                      attributes:attributes];

        // Calculate size and origin to center the text
        NSSize textSize = [attrStr size];
        NSPoint textOrigin = NSMakePoint((size.width - textSize.width) / 2.0,
                                        (size.height - textSize.height) / 2.0);

        // Draw the filled circle
        NSBezierPath *circlePath = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(1,
                                                                                     1,
                                                                                     size.width - 2,
                                                                                     size.height - 2)];
        [[NSColor blackColor] setFill];
        [circlePath fill];

        // Set the blending mode to subtract the letter from the circle
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext.currentContext setCompositingOperation:NSCompositingOperationDestinationOut];

        // Draw the attributed string at the calculated origin point
        [attrStr drawAtPoint:textOrigin];

        [NSGraphicsContext restoreGraphicsState];
    }];
}

- (iTermSRGBColor)colorForString:(NSString *)string {
    NSUInteger hash = [string hashWithDJB2];
    int red = hash & 255;
    int green = (hash >> 8) & 255;
    int blue = (hash >> 16) & 255;

    return (iTermSRGBColor){ red / 255.0, green / 255.0, blue / 255.0 };
}

- (NSString *)randomTintColorForString:(NSString *)string {
    NSMutableString *acc = [string mutableCopy];
    const CGFloat minBrightness = 0.30;
    const CGFloat maxBrightness = 0.50;
    iTermSRGBColor color = [self colorForString:acc];
    CGFloat brightness = iTermPerceptualBrightnessSRGB(color);
    while (brightness < minBrightness || brightness > maxBrightness) {
        [acc appendFormat:@"%0.2f%0.2f%0.2f", color.r, color.g, color.b];
        color = [self colorForString:acc];
        brightness = iTermPerceptualBrightnessSRGB(color);
    }
    return [NSString stringWithFormat:@"#%02x%02x%02x",
            (int)(color.r * 255), (int)(color.g * 255), (int)(color.b * 255)];
}

@end
