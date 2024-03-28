//
//  VT100GridTypes.h
//  iTerm
//
//  Created by George Nachman on 10/13/13.
//
//

#import <Foundation/Foundation.h>
#import "NSObject+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    int x;
    int y;
} VT100GridCoord;

typedef struct {
    int x;
    long long y;
} VT100GridAbsCoord;

typedef struct {
    int width;
    int height;
} VT100GridSize;

typedef struct {
    int location;
    int length;
} VT100GridRange;

typedef struct {
    VT100GridCoord origin;
    VT100GridSize size;
} VT100GridRect;

typedef struct {
    VT100GridCoord origin;
    int length;
} VT100GridRun;

typedef struct {
  VT100GridCoord start;
  VT100GridCoord end;  // inclusive of y, half-open on x
} VT100GridCoordRange;

typedef struct {
    VT100GridAbsCoord start;
    VT100GridAbsCoord end;  // inclusive of y, half-open on x
} VT100GridAbsCoordRange;

typedef struct {
    VT100GridCoordRange coordRange;  // inclusive of y, half-open on x
    VT100GridRange columnWindow;  // 0s if you don't care
} VT100GridWindowedRange;

// An invalid range has -1 for all values, including columnWindow.
typedef struct {
    VT100GridAbsCoordRange coordRange;  // inclusive of y, half-open on x
    VT100GridRange columnWindow;  // Use (0,0) for when the there is no window.
} VT100GridAbsWindowedRange;

extern const VT100GridCoord VT100GridCoordInvalid;
extern const VT100GridCoordRange VT100GridCoordRangeInvalid;

@interface NSValue (VT100Grid)

+ (NSValue *)valueWithGridCoord:(VT100GridCoord)coord;
+ (NSValue *)valueWithGridAbsCoord:(VT100GridAbsCoord)coord;
+ (NSValue *)valueWithGridSize:(VT100GridSize)size;
+ (NSValue *)valueWithGridRange:(VT100GridRange)range;
+ (NSValue *)valueWithGridRect:(VT100GridRect)rect;
+ (NSValue *)valueWithGridRun:(VT100GridRun)run;
+ (NSValue *)valueWithGridCoordRange:(VT100GridCoordRange)coordRange;
+ (NSValue *)valueWithGridAbsCoordRange:(VT100GridAbsCoordRange)absCoordRange;

- (VT100GridCoord)gridCoordValue;
- (VT100GridAbsCoord)gridAbsCoordValue;
- (VT100GridSize)gridSizeValue;
- (VT100GridRange)gridRangeValue;
- (VT100GridRect)gridRectValue;
- (VT100GridRun)gridRunValue;
- (VT100GridCoordRange)gridCoordRangeValue;
- (VT100GridAbsCoordRange)gridAbsCoordRangeValue;

// Use for sorting array of VT100GridCoorRange's in NSValue*s by the start coord.
- (NSComparisonResult)compareGridAbsCoordRangeStart:(NSValue *)other;

@end

NSString *VT100GridCoordRangeDescription(VT100GridCoordRange range);
NSString *VT100GridWindowedRangeDescription(VT100GridWindowedRange range);
NSString *VT100GridAbsCoordRangeDescription(VT100GridAbsCoordRange range);
NSString *VT100GridSizeDescription(VT100GridSize size);

NS_INLINE VT100GridAbsWindowedRange VT100GridAbsWindowedRangeClampedToWidth(const VT100GridAbsWindowedRange range,
                                                                            const int width) {
    if (width <= 0) {
        return range;
    }
    VT100GridAbsWindowedRange result = range;
    result.coordRange.start.x = MAX(0, MIN(result.coordRange.start.x, width - 1));
    result.coordRange.end.x = MIN(result.coordRange.end.x, width);

    int left = result.columnWindow.location;
    int right = range.columnWindow.location + range.columnWindow.length;
    if (left <= 0 && right <= 0) {
        return result;
    }
    if (left >= width) {
        left = width - 1;
    }
    if (right > width) {
        right = width;
    }
    result.columnWindow.location = left;
    result.columnWindow.length = right - left;
    return result;
}

NS_INLINE VT100GridCoord VT100GridCoordMake(int x, int y) {
    VT100GridCoord coord;
    coord.x = x;
    coord.y = y;
    return coord;
}

NS_INLINE VT100GridAbsCoord VT100GridAbsCoordMake(int x, long long y) {
    VT100GridAbsCoord coord;
    coord.x = x;
    coord.y = y;
    return coord;
}

NS_INLINE VT100GridSize VT100GridSizeMake(int width, int height) {
    VT100GridSize size;
    size.width = width;
    size.height = height;
    return size;
}

NS_INLINE VT100GridRange VT100GridRangeMake(int location, int length) {
    VT100GridRange range;
    range.location = location;
    range.length = length;
    return range;
}

NS_INLINE BOOL VT100GridRangeContains(VT100GridRange range, int value) {
    return value >= range.location && value < range.location + range.length;
}

NS_INLINE BOOL VT100GridRangeEqualsRange(VT100GridRange a, VT100GridRange b) {
    return a.location == b.location && a.length == b.length;
}

NS_INLINE int VT100GridRangeMax(VT100GridRange range) {
    return range.location + range.length - 1;
}

NS_INLINE long long VT100GridRangeNoninclusiveMaxLL(VT100GridRange range) {
    return (long long)range.location + (long long)range.length;
}

NS_INLINE VT100GridRange VT100GridRangeIntersection(VT100GridRange r1, VT100GridRange r2) {
    const long long start = MAX(r1.location, r2.location);
    const long long end = MIN(VT100GridRangeNoninclusiveMaxLL(r1), VT100GridRangeNoninclusiveMaxLL(r2));
    return VT100GridRangeMake((int)start, (int)MAX(0, end - start));
}

NS_INLINE VT100GridRect VT100GridRectMake(int x, int y, int width, int height) {
    VT100GridRect rect;
    rect.origin = VT100GridCoordMake(x, y);
    rect.size = VT100GridSizeMake(width, height);
    return rect;
}

NS_INLINE BOOL VT100GridRectEquals(VT100GridRect a, VT100GridRect b) {
    return (a.origin.x == b.origin.x &&
            a.origin.y == b.origin.y &&
            a.size.width == b.size.width &&
            a.size.height == b.size.height);
}

NS_INLINE BOOL VT100GridCoordEquals(VT100GridCoord a, VT100GridCoord b) {
    return a.x == b.x && a.y == b.y;
}

NS_INLINE BOOL VT100GridRunEquals(VT100GridRun a, VT100GridRun b) {
    return (a.length == b.length &&
            VT100GridCoordEquals(a.origin, b.origin));
}

NS_INLINE BOOL VT100GridAbsCoordEquals(VT100GridAbsCoord a, VT100GridAbsCoord b) {
    return a.x == b.x && a.y == b.y;
}

NS_INLINE BOOL VT100GridSizeEquals(VT100GridSize a, VT100GridSize b) {
    return a.width == b.width && a.height == b.height;
}

NS_INLINE VT100GridWindowedRange VT100GridWindowedRangeMake(VT100GridCoordRange range,
                                                            int windowStart,
                                                            int windowWidth) {
    VT100GridWindowedRange windowedRange;
    windowedRange.coordRange = range;
    windowedRange.columnWindow.location = windowStart;
    windowedRange.columnWindow.length = windowWidth;
    return windowedRange;
}

NS_INLINE VT100GridAbsWindowedRange VT100GridAbsWindowedRangeMake(VT100GridAbsCoordRange range,
                                                                  int windowStart,
                                                                  int windowWidth) {
    VT100GridAbsWindowedRange windowedRange;
    windowedRange.coordRange = range;
    windowedRange.columnWindow.location = windowStart;
    windowedRange.columnWindow.length = windowWidth;
    return windowedRange;
}

NS_INLINE VT100GridRect VT100GridWindowedRangeBoundingRect(VT100GridWindowedRange range) {
    if (range.coordRange.start.y != range.coordRange.end.y) {
        // Spans multiple lines so it covers the full width of the column window.
        return VT100GridRectMake(range.columnWindow.location,
                                 range.coordRange.start.y,
                                 range.columnWindow.length,
                                 range.coordRange.end.y - range.coordRange.start.y + 1);
    }
    const int minX = MAX(range.columnWindow.location, range.coordRange.start.x);
    const int maxX = MIN(range.columnWindow.location + range.columnWindow.length,
                         range.coordRange.end.x);

    return VT100GridRectMake(minX,
                             range.coordRange.start.y,
                             maxX - minX + 1,
                             range.coordRange.end.y - range.coordRange.start.y + 1);
}

NS_INLINE VT100GridCoord VT100GridWindowedRangeStart(VT100GridWindowedRange range) {
    VT100GridCoord coord = range.coordRange.start;
    if (range.columnWindow.length) {
        coord.x = MIN(MAX(coord.x, range.columnWindow.location),
                      range.columnWindow.location + range.columnWindow.length);
    }
    return coord;
}

NS_INLINE VT100GridCoord VT100GridWindowedRangeEnd(VT100GridWindowedRange range) {
    VT100GridCoord coord = range.coordRange.end;
    if (range.columnWindow.length) {
        coord.x = MIN(coord.x, VT100GridRangeMax(range.columnWindow) + 1);
    }
    return coord;
}

NS_INLINE BOOL VT100GridCoordRangeEqualsCoordRange(VT100GridCoordRange a, VT100GridCoordRange b) {
    return (VT100GridCoordEquals(a.start, b.start) &&
            VT100GridCoordEquals(a.end, b.end));
}

NS_INLINE BOOL VT100GridWindowsRangeEqualsWindowedRange(VT100GridWindowedRange a, VT100GridWindowedRange b) {
    return (VT100GridRangeEqualsRange(a.columnWindow,
                                      b.columnWindow) &&
            VT100GridCoordRangeEqualsCoordRange(a.coordRange,
                                                b.coordRange));
}

NS_INLINE BOOL VT100GridAbsCoordRangeEquals(VT100GridAbsCoordRange a, VT100GridAbsCoordRange b) {
    return (VT100GridAbsCoordEquals(a.start, b.start) &&
            VT100GridAbsCoordEquals(a.end, b.end));
}

NS_INLINE BOOL VT100GridAbsWindowedRangeEquals(VT100GridAbsWindowedRange a, VT100GridAbsWindowedRange b) {
    return (VT100GridAbsCoordRangeEquals(a.coordRange, b.coordRange) &&
            VT100GridRangeEqualsRange(a.columnWindow, b.columnWindow));
}

NS_INLINE BOOL VT100GridAbsWindowsRangeEqualsAbsWindowedRange(VT100GridAbsWindowedRange a, VT100GridAbsWindowedRange b) {
    return (VT100GridRangeEqualsRange(a.columnWindow,
                                      b.columnWindow) &&
            VT100GridAbsCoordRangeEquals(a.coordRange,
                                         b.coordRange));
}

NSString *VT100GridAbsWindowedRangeDescription(VT100GridAbsWindowedRange range);

NS_INLINE VT100GridAbsCoord VT100GridAbsWindowedRangeStart(VT100GridAbsWindowedRange range) {
    VT100GridAbsCoord coord = range.coordRange.start;
    if (range.columnWindow.length > 0) {
        coord.x = MIN(MAX(coord.x, range.columnWindow.location),
                      range.columnWindow.location + range.columnWindow.length);
    }
    return coord;
}

NS_INLINE VT100GridAbsCoord VT100GridAbsWindowedRangeEnd(VT100GridAbsWindowedRange range) {
    VT100GridAbsCoord coord = range.coordRange.end;
    if (range.columnWindow.length > 0) {
        coord.x = MIN(coord.x, VT100GridRangeMax(range.columnWindow) + 1);
    }
    return coord;
}

// Ascending: a < b
// Descending: a > b
// Same: a == b
NS_INLINE NSComparisonResult VT100GridCoordOrder(VT100GridCoord a, VT100GridCoord b) {
    if (a.y < b.y) {
        return NSOrderedAscending;
    }
    if (a.y > b.y) {
        return NSOrderedDescending;
    }
    if (a.x < b.x) {
        return NSOrderedAscending;
    }
    if (a.x > b.x) {
        return NSOrderedDescending;
    }

    return NSOrderedSame;
}

NS_INLINE NSComparisonResult VT100GridAbsCoordOrder(VT100GridAbsCoord a, VT100GridAbsCoord b) {
    if (a.y < b.y) {
        return NSOrderedAscending;
    }
    if (a.y > b.y) {
        return NSOrderedDescending;
    }
    if (a.x < b.x) {
        return NSOrderedAscending;
    }
    if (a.x > b.x) {
        return NSOrderedDescending;
    }

    return NSOrderedSame;
}

NS_INLINE VT100GridRun VT100GridRunMake(int x, int y, int length) {
    VT100GridRun run;
    run.origin.x = x;
    run.origin.y = y;
    run.length = length;
    return run;
}

NS_INLINE VT100GridCoordRange VT100GridCoordRangeMake(int startX, int startY, int endX, int endY) {
    VT100GridCoordRange coordRange;
    coordRange.start.x = startX;
    coordRange.start.y = startY;
    coordRange.end.x = endX;
    coordRange.end.y = endY;
    return coordRange;
}

NS_INLINE VT100GridAbsCoordRange VT100GridAbsCoordRangeMake(int startX,
                                                            long long startY,
                                                            int endX,
                                                            long long endY) {
    VT100GridAbsCoordRange coordRange;
    coordRange.start.x = startX;
    coordRange.start.y = startY;
    coordRange.end.x = endX;
    coordRange.end.y = endY;
    return coordRange;
}

NS_INLINE VT100GridWindowedRange VT100GridWindowedRangeFromAbsWindowedRange(VT100GridAbsWindowedRange absrange,
                                                                            long long offset) {
    return VT100GridWindowedRangeMake(VT100GridCoordRangeMake(absrange.coordRange.start.x,
                                                              (int)MIN(INT_MAX, MAX(offset, absrange.coordRange.start.y) - offset),
                                                              absrange.coordRange.end.x,
                                                              (int)MIN(INT_MAX, MAX(offset, absrange.coordRange.end.y) - offset)),
                                      absrange.columnWindow.location,
                                      absrange.columnWindow.length);
}

NS_INLINE BOOL VT100GridAbsCoordIsValid(VT100GridAbsCoord coord) {
    return coord.x >= 0 && coord.y >= 0;
}

NS_INLINE BOOL VT100GridAbsCoordRangeIsValid(VT100GridAbsCoordRange range) {
    return VT100GridAbsCoordIsValid(range.start) && VT100GridAbsCoordIsValid(range.end);
}

NS_INLINE VT100GridAbsCoordRange VT100GridAbsCoordRangeFromCoordRange(VT100GridCoordRange range,
                                                                      long long offset) {
    return VT100GridAbsCoordRangeMake(range.start.x, range.start.y + offset, range.end.x, range.end.y + offset);
}

NS_INLINE VT100GridAbsWindowedRange VT100GridAbsWindowedRangeFromRelative(VT100GridWindowedRange range,
                                                                          long long scrollbackOffset) {
    VT100GridAbsWindowedRange windowedRange;
    windowedRange.coordRange = VT100GridAbsCoordRangeMake(range.coordRange.start.x,
                                                          range.coordRange.start.y + scrollbackOffset,
                                                          range.coordRange.end.x,
                                                          range.coordRange.end.y + scrollbackOffset);
    windowedRange.columnWindow = range.columnWindow;
    return windowedRange;
}

NS_INLINE VT100GridAbsWindowedRange VT100GridAbsWindowedRangeFromWindowedRange(VT100GridWindowedRange range,
                                                                               long long offset) {
    return VT100GridAbsWindowedRangeFromRelative(range, offset);
}

NS_INLINE VT100GridWindowedRange VT100GridWindowedRangeClampedToWidth(const VT100GridWindowedRange range,
                                                                      const int width) {
    const VT100GridAbsWindowedRange input = VT100GridAbsWindowedRangeFromWindowedRange(range, 0);
    const VT100GridAbsWindowedRange output = VT100GridAbsWindowedRangeClampedToWidth(input, width);
    return VT100GridWindowedRangeFromAbsWindowedRange(output, 0);
}

NS_INLINE VT100GridWindowedRange VT100GridWindowedRangeFromVT100GridAbsWindowedRange(VT100GridAbsWindowedRange source,
                                                                                     long long totalScrollbackOverflow) {
    const long long minY = source.coordRange.start.y;
    const long long maxY = source.coordRange.end.y;
    VT100GridWindowedRange result = VT100GridWindowedRangeMake(VT100GridCoordRangeMake(source.coordRange.start.x,
                                                                                       MAX(0, (int)(minY - totalScrollbackOverflow)),
                                                                                       source.coordRange.end.x,
                                                                                       MAX(0, (int)(maxY - totalScrollbackOverflow))),
                                                               source.columnWindow.location,
                                                               source.columnWindow.length);
    return result;
}

NS_INLINE VT100GridCoordRange VT100GridCoordRangeFromAbsCoordRange(VT100GridAbsCoordRange absRange, long long totalOverflow) {
    const long long startY = MAX(0, absRange.start.y - totalOverflow);
    const long long endY = absRange.end.y - totalOverflow;
    if (endY < 0 || startY >= INT_MAX || endY >= INT_MAX) {
        // Avoid integer underflow
        return VT100GridCoordRangeMake(-1, -1, -1, -1);
    }
    return VT100GridCoordRangeMake(absRange.start.x,
                                   (int)startY,
                                   absRange.end.x,
                                   (int)endY);
}

NS_INLINE VT100GridAbsCoord VT100GridAbsCoordFromCoord(VT100GridCoord coord, long long overflow) {
    return VT100GridAbsCoordMake(coord.x, coord.y + overflow);
}

NS_INLINE VT100GridCoord VT100GridCoordFromAbsCoord(VT100GridAbsCoord absCoord,
                                                    long long totalOverflow,
                                                    BOOL * _Nullable ok) {
    const long long y = absCoord.y - totalOverflow;
    if (y < 0 || y > INT_MAX) {
        if (ok) {
            *ok = NO;
        }
        return VT100GridCoordMake(0, 0);
    }
    if (ok) {
        *ok = YES;
    }
    return VT100GridCoordMake(absCoord.x, (int)y);
}

NS_INLINE BOOL VT100GridAbsCoordRangeTryMakeRelative(VT100GridAbsCoordRange range,
                                                     long long overflow,
                                                     void (^NS_NOESCAPE block)(VT100GridCoordRange range)) {
    VT100GridCoordRange relative = VT100GridCoordRangeFromAbsCoordRange(range, overflow);
    if (relative.start.x < 0) {
        return NO;
    }
    block(relative);
    return YES;
}

NS_INLINE NSString *VT100GridAbsCoordDescription(VT100GridAbsCoord c) {
    return [NSString stringWithFormat:@"(%d, %lld)", c.x, c.y];
}

NS_INLINE NSString *VT100GridCoordDescription(VT100GridCoord c) {
    return [NSString stringWithFormat:@"(%d, %d)", c.x, c.y];
}

NS_INLINE NSString *VT100GridRectDescription(VT100GridRect rect) {
    return [NSString stringWithFormat:@"{%@ %@}",
            VT100GridCoordDescription(rect.origin),
            VT100GridSizeDescription(rect.size)];
}

NS_INLINE NSString *VT100GridRunDescription(VT100GridRun run) {
    return [NSString stringWithFormat:@"[origin=%@ length=%@]", VT100GridCoordDescription(run.origin), @(run.length)];
}

NS_INLINE NSString *VT100GridRangeDescription(VT100GridRange r) {
    return [NSString stringWithFormat:@"[%d, %d)", r.location, r.location + r.length];
}

NS_INLINE VT100GridCoord VT100GridCoordRangeMin(VT100GridCoordRange range) {
    if (VT100GridCoordOrder(range.start, range.end) == NSOrderedAscending) {
        return range.start;
    } else {
        return range.end;
    }
}

NS_INLINE VT100GridCoord VT100GridCoordRangeMax(VT100GridCoordRange range) {
    if (VT100GridCoordOrder(range.start, range.end) == NSOrderedAscending) {
        return range.end;
    } else {
        return range.start;
    }
}

NS_INLINE VT100GridAbsCoord VT100GridAbsCoordRangeMin(VT100GridAbsCoordRange range) {
    if (VT100GridAbsCoordOrder(range.start, range.end) == NSOrderedAscending) {
        return range.start;
    } else {
        return range.end;
    }
}

NS_INLINE VT100GridAbsCoord VT100GridAbsCoordRangeMax(VT100GridAbsCoordRange range) {
    if (VT100GridAbsCoordOrder(range.start, range.end) == NSOrderedAscending) {
        return range.end;
    } else {
        return range.start;
    }
}

NS_INLINE BOOL VT100GridAbsCoordRangeContainsAbsCoord(VT100GridAbsCoordRange range, VT100GridAbsCoord coord) {
  NSComparisonResult order = VT100GridAbsCoordOrder(VT100GridAbsCoordRangeMin(range), coord);
  if (order == NSOrderedDescending) {
    return NO;
  }

  order = VT100GridAbsCoordOrder(VT100GridAbsCoordRangeMax(range), coord);
  return (order == NSOrderedDescending);
}

NS_INLINE BOOL VT100GridCoordRangeContainsCoord(VT100GridCoordRange range, VT100GridCoord coord) {
  NSComparisonResult order = VT100GridCoordOrder(VT100GridCoordRangeMin(range), coord);
  if (order == NSOrderedDescending) {
    return NO;
  }

  order = VT100GridCoordOrder(VT100GridCoordRangeMax(range), coord);
  return (order == NSOrderedDescending);
}

NS_INLINE long long VT100GridCoordDistance(VT100GridCoord a, VT100GridCoord b, int gridWidth) {
    long long aPos = a.y;
    aPos *= gridWidth;
    aPos += a.x;

    long long bPos = b.y;
    bPos *= gridWidth;
    bPos += b.x;

    return llabs(aPos - bPos);
}

NS_INLINE long long VT100GridAbsCoordDistance(VT100GridAbsCoord a, VT100GridAbsCoord b, int gridWidth) {
    long long aPos = a.y;
    aPos *= gridWidth;
    aPos += a.x;

    long long bPos = b.y;
    bPos *= gridWidth;
    bPos += b.x;

    return llabs(aPos - bPos);
}

NS_INLINE BOOL VT100GridWindowedRangeContainsCoord(VT100GridWindowedRange range,
                                                   VT100GridCoord coord) {
    if (range.columnWindow.location < 0 && range.columnWindow.length < 0) {
        return VT100GridCoordRangeContainsCoord(range.coordRange, coord);
    }
    return (coord.x >= range.columnWindow.location &&
            coord.x < range.columnWindow.location + range.columnWindow.length &&
            VT100GridCoordRangeContainsCoord(range.coordRange, coord));
}

NS_INLINE long long VT100GridAbsWindowedRangeLength(VT100GridAbsWindowedRange range, int gridWidth) {
    if (range.coordRange.start.y == range.coordRange.end.y) {
        return VT100GridAbsWindowedRangeEnd(range).x - VT100GridAbsWindowedRangeStart(range).x;
    } else {
        int left = range.columnWindow.location;
        int right = left + range.columnWindow.length;
        if (range.columnWindow.length == 0) {
            left = 0;
            right = gridWidth;
        }
        const long long numFullLines = MAX(0, (range.coordRange.end.y - range.coordRange.start.y - 1));
        return ((right - VT100GridAbsWindowedRangeStart(range).x) +  // Chars on first line
                (VT100GridAbsWindowedRangeEnd(range).x - left) +  // Chars on second line
                (right - left) * numFullLines);  // Chars between
    }
}

NS_INLINE long long VT100GridWindowedRangeLength(VT100GridWindowedRange range, int gridWidth) {
    return VT100GridAbsWindowedRangeLength(VT100GridAbsWindowedRangeFromWindowedRange(range, 0),
                                           gridWidth);
}

NS_INLINE long long VT100GridCoordRangeLength(VT100GridCoordRange range, int gridWidth) {
    return VT100GridCoordDistance(range.start, range.end, gridWidth);
}

NS_INLINE long long VT100GridCoordRangeHeight(VT100GridCoordRange range) {
    return range.end.y - range.start.y + 1;
}

NS_INLINE long long VT100GridAbsCoordRangeLength(VT100GridAbsCoordRange range, int gridWidth) {
    return VT100GridAbsCoordDistance(range.start, range.end, gridWidth);
}

// Returns the coord of the last char inside the run.
NS_INLINE VT100GridCoord VT100GridRunMax(VT100GridRun run, int width) {
    VT100GridCoord coord = run.origin;
    coord.y += (coord.x + run.length - 1) / width;
    coord.x = (coord.x + run.length - 1) % width;
    return coord;
}

// Returns the coord of the bottom-right cell that is in the rect. The rect must not be 0-dimensioned.
NS_INLINE VT100GridCoord VT100GridRectMax(VT100GridRect rect) {
    VT100GridCoord coord = rect.origin;
    coord.x += rect.size.width - 1;
    coord.y += rect.size.height - 1;
    return coord;
}

// Returns if the coord is within the rect.
NS_INLINE BOOL VT100GridCoordInRect(VT100GridCoord coord, VT100GridRect rect) {
    return (coord.x >= rect.origin.x &&
            coord.y >= rect.origin.y &&
            coord.x < rect.origin.x + rect.size.width &&
            coord.y < rect.origin.y + rect.size.height);
}

NS_INLINE VT100GridCoord VT100GridRectTopLeft(VT100GridRect rect) {
    return VT100GridCoordMake(rect.origin.x, rect.origin.y);
}

NS_INLINE VT100GridCoord VT100GridRectTopRight(VT100GridRect rect) {
    return VT100GridCoordMake(rect.origin.x + rect.size.width - 1, rect.origin.y);
}

NS_INLINE VT100GridCoord VT100GridRectBottomLeft(VT100GridRect rect) {
    return VT100GridCoordMake(rect.origin.x, rect.origin.y + rect.size.height - 1);
}

NS_INLINE VT100GridCoord VT100GridRectBottomRight(VT100GridRect rect) {
    return VT100GridCoordMake(rect.origin.x + rect.size.width - 1, rect.origin.y + rect.size.height - 1);
}

// Creates a run between two coords, not inclusive of end.
VT100GridRun VT100GridRunFromCoords(VT100GridCoord start,
                                    VT100GridCoord end,
                                    int width);

NS_INLINE NSDictionary *VT100GridCoordToDictionary(VT100GridCoord coord) {
    return @{ @"x": @(coord.x), @"y": @(coord.y) };
}

NS_INLINE BOOL VT100GridCoordFromDictionary(NSDictionary * _Nullable dict, VT100GridCoord *coord) {
    if (!dict) {
        return NO;
    }

    if (![dict isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    NSNumber *x = [NSNumber castFrom:dict[@"x"]];
    if (!x) {
        return NO;
    }

    NSNumber *y = [NSNumber castFrom:dict[@"y"]];
    if (!y) {
        return NO;
    }

    *coord = VT100GridCoordMake(x.intValue, y.intValue);
    return YES;
}

NS_ASSUME_NONNULL_END
