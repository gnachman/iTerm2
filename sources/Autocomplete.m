#include <wctype.h>
#import "Autocomplete.h"
#import "FindViewController.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplicationDelegate.h"
#import "iTermCommandHistoryEntryMO+Additions.h"
#import "iTermController.h"
#import "iTermShellHistoryController.h"
#import "iTermTextExtractor.h"
#import "LineBuffer.h"
#import "PasteboardHistory.h"
#import "PopupModel.h"
#import "PTYTextView.h"
#import "SearchResult.h"
#import "VT100Screen.h"

#define AcLog DLog

const int kMaxQueryContextWords = 4;
const int kMaxResultContextWords = 4;

@implementation AutocompleteView
{
    // Table view that displays choices.
    IBOutlet NSTableView* table_;
    
    // Word before cursor.
    NSMutableString* prefix_;
    
    // Is there whitespace before the cursor? If so, strip whitespace from before candidates.
    BOOL whitespaceBeforeCursor_;
    
    // Words before the word at the cursor.
    NSMutableArray* context_;
    
    // x,y coords where prefix occurred.
    int startX_;
    long long startY_;  // absolute coord
    
    // Context for searches while populating unfilteredModel.
    FindContext *findContext_;
    
    // Timer for doing asynch seraches for prefix.
    NSTimer* populateTimer_;
    
    // Cursor location to begin next search.
    int x_;
    long long y_;  // absolute coord
    
    // Number of matches found so far
    int matchCount_;
    
    // Text from previous autocompletes that were followed by -[more];
    NSMutableString* moreText_;
    
    // Previous state from calls to -[more] so that -[less] can go back in time.
    NSMutableArray* stack_;
    
    // SearchResults from doing a find operation
    NSMutableArray* findResults_;
    
    // Result of previous search
    BOOL more_;
    
    // Character set for word separators
    NSCharacterSet *wordSeparatorCharacterSet_;
}

+ (int)maxOptions
{
    return [iTermAdvancedSettingsModel autocompleteMaxOptions];
}

- (instancetype)init {
    const int kMaxOptions = [AutocompleteView maxOptions];
    self = [super initWithWindowNibName:@"Autocomplete"
                               tablePtr:nil
                                  model:[[[PopupModel alloc] initWithMaxEntries:kMaxOptions] autorelease]];
    if (!self) {
        return nil;
    }
    [self setTableView:table_];
    prefix_ = [[NSMutableString alloc] init];
    context_ = [[NSMutableArray alloc] init];
    stack_ = [[NSMutableArray alloc] init];
    findResults_ = [[NSMutableArray alloc] init];
    findContext_ = [[FindContext alloc] init];
    return self;
}

- (void)dealloc
{
    [findResults_ release];
    [stack_ release];
    [moreText_ release];
    [context_ release];
    [prefix_ release];
    [populateTimer_ invalidate];
    [populateTimer_ release];
    [findContext_ release];
    [wordSeparatorCharacterSet_ release];
    [super dealloc];
}

- (void)appendContextAtX:(int)x y:(int)y into:(NSMutableArray*)context maxWords:(int)maxWords
{
    const int kMaxIterations = maxWords * 2;
    VT100Screen* screen = [[self delegate] popupVT100Screen];
    NSCharacterSet* nonWhitespace = [[NSCharacterSet whitespaceCharacterSet] invertedSet];

    iTermTextExtractor *textExtractor = [self textExtractor];
    for (int i = 0; i < kMaxIterations && [context count] < maxWords; ++i) {
        // Move back one position
        --x;
        if (x < 0) {
            x += [screen width];
            --y;
        }
        if (y < 0) {
            break;
        }

        VT100GridWindowedRange range = [textExtractor rangeForWordAt:VT100GridCoordMake(x, y)
                                                       maximumLength:kReasonableMaximumWordLength];
        NSString *s = [textExtractor contentInRange:range
                                  attributeProvider:nil
                                         nullPolicy:kiTermTextExtractorNullPolicyFromStartToFirst
                                                pad:NO
                                 includeLastNewline:NO
                             trimTrailingWhitespace:NO
                                       cappedAtSize:-1
                                       truncateTail:YES
                                  continuationChars:nil
                                             coords:nil];
        if ([s rangeOfCharacterFromSet:nonWhitespace].location != NSNotFound) {
            // Add only if not whitespace.
            AcLog(@"Add to context (%d/%d): %@", (int) [context count], (int) maxWords, s);
            [context addObject:s];
        }
        x = range.coordRange.start.x;
    }
}

- (void)onOpen
{
    VT100GridWindowedRange range;
    VT100Screen* screen = [[self delegate] popupVT100Screen];

    [wordSeparatorCharacterSet_ autorelease];
    wordSeparatorCharacterSet_ = [[iTermTextExtractor wordSeparatorCharacterSet] retain];

    int x = [screen cursorX]-2;
    int y = [screen cursorY] + [screen numberOfLines] - [screen height] - 1;
    screen_char_t* sct = [screen getLineAtIndex:y];
    [context_ removeAllObjects];
    NSString* charBeforeCursor = ScreenCharToStr(&sct[x]);
    AcLog(@"Char before cursor is '%@'", charBeforeCursor);
    whitespaceBeforeCursor_ = ([charBeforeCursor rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]].location != NSNotFound);
    NSCharacterSet* nonWhitespace = [[NSCharacterSet whitespaceCharacterSet] invertedSet];
    if (x < 0) {
        [prefix_ setString:@""];
    } else {
        iTermTextExtractor *extractor = [self textExtractor];
        range = [extractor rangeForWordAt:VT100GridCoordMake(x, y)
                            maximumLength:kReasonableMaximumWordLength];
        NSString *s = [extractor contentInRange:range
                              attributeProvider:nil
                                     nullPolicy:kiTermTextExtractorNullPolicyFromStartToFirst
                                            pad:NO
                             includeLastNewline:NO
                         trimTrailingWhitespace:NO
                                   cappedAtSize:-1
                                   truncateTail:YES
                              continuationChars:nil
                                         coords:nil];
        int maxWords = kMaxQueryContextWords;
        if ([s rangeOfCharacterFromSet:nonWhitespace].location == NSNotFound) {
            ++maxWords;
        } else {
            [prefix_ setString:s];
        }
        AcLog(@"Prefix is %@ starting at %d", s, range.coordRange.start.x);
        startX_ = range.coordRange.start.x;
        startY_ = range.coordRange.start.y + [screen scrollbackOverflow];

        [self appendContextAtX:range.coordRange.start.x
                             y:range.coordRange.start.y
                          into:context_
                      maxWords:maxWords];
        if (maxWords > kMaxQueryContextWords) {
            if ([context_ count] > 0) {
                [prefix_ setString:[context_ objectAtIndex:0]];
                [context_ removeObjectAtIndex:0];
            } else {
                [prefix_ setString:@""];
            }
        }
    }
}

- (int)_timestampToResultNumber:(NSDate*)timestamp
{
    NSDate *now = [NSDate date];
    double x = -[timestamp timeIntervalSinceDate:now];
    x = sqrt(x / 60);
    if (x > 20) {
        x = 20;
    }
    return x;
}

- (NSString*)formatContext:(NSArray*)context
{
    NSMutableString* s = [NSMutableString stringWithString:@""];
    for (int i = 0; i < [context count]; ++i) {
        [s appendFormat:@"'%@' ", [context objectAtIndex:i]];
    }
    return s;
}

- (double)contextSimilarityBetweenQuery:(NSArray*)queryContext andResult:(NSArray*)resultContext
{
    NSMutableArray* scratch = [NSMutableArray arrayWithArray:resultContext];
    double similarity = 0;
    AcLog(@"  Determining similarity score. Initialized to 0.");
    for (int i = 0; i < [queryContext count]; ++i) {
        NSString* qs = [queryContext objectAtIndex:i];
        double lengthFactor = 1.0;
        if ([qs length] == 1) {
            // One-character matches have less significance.
            lengthFactor = 5.0;
        }
        AcLog(@"  Looking for match for query string '%@'", qs);
        for (int j = 0; j < [scratch count]; ++j) {
            NSString* rs = [scratch objectAtIndex:j];
            // Distance is a measure of how far a word in the query context is from
            // a word in the result context. Higher distances hurt the similarity
            // score.
            double distance = (abs(i - j) + 1) * lengthFactor;

            if ([qs localizedCompare:rs] == NSOrderedSame) {
                AcLog(@"  Exact match %@ = %@. Incr similarity by %lf", rs, qs, (1.0/distance));
                similarity += 1.0 / distance;
                [scratch replaceObjectAtIndex:j withObject:@""];
                break;
            } else if ([qs localizedCaseInsensitiveCompare:rs] == NSOrderedSame) {
                AcLog(@"  Approximate match of %@ = %@. Incr similarity by %lf", rs, qs, (0.9/distance));
                similarity += 0.9 / distance;
                [scratch replaceObjectAtIndex:j withObject:@""];
                break;
            }
        }
    }
    // Boost similarity. This is applied in quadrature.
    similarity *= 1.5;
    AcLog(@"  Final similarity score with boost is %lf", similarity);
    return similarity;
}

- (double)scoreResultNumber:(int)resultNumber
               queryContext:(NSArray*)queryContext
              resultContext:(NSArray*)resultContext
        joiningPrefixLength:(int)joiningPrefixLength
                       word:(NSString*)word
{
    AcLog(@"Score result #%d with queryContext:%@ and resultContext:%@", resultNumber, [self formatContext:queryContext], [self formatContext:resultContext]);
    double similarity = [self contextSimilarityBetweenQuery:queryContext andResult:resultContext] * 2;
    // Square similarity so that it has a strong effect if a full context match
    // is found. Likewise, add 3 to the denominator so that the result number has
    // a small influence when it's close to 0.
    double score = (1.0 + similarity * similarity)/(double)(resultNumber + 3);

    // Strongly penalize very short candidates, because they're not worth completing, unless the context similarity is very strong.
    double length = [word length] + joiningPrefixLength;
    if (length < 4 && similarity < 2) {
        score *= length / 50.0;
        AcLog(@"Apply length multiplier of %lf", length/50.0);
    }

    // Prefer suffixes to full words
    if (joiningPrefixLength == 0) {
        score /= 2;
    }
    
    AcLog(@"Final score is %lf", score);
    return score;
}


- (void)_processPasteboardEntry:(PasteboardEntry*)entry
{
    NSString* value = [entry mainValue];
    NSRange range = [value rangeOfString:prefix_ options:(NSCaseInsensitiveSearch)];
    if (range.location != NSNotFound) {
        if (range.location > 0) {
            if (![wordSeparatorCharacterSet_ characterIsMember:[value characterAtIndex:range.location - 1]]) {
                return;
            }
        }
        NSRange suffixRange;
        suffixRange.location = range.length + range.location;
        suffixRange.length = [value length] - suffixRange.location;
        NSString* word = [value substringWithRange:suffixRange];
        // TODO: This is kind of sketchy. We need to look at text before the prefix and lower the score if not much of the prefix was matched.
        double score = [self scoreResultNumber:[self _timestampToResultNumber:[entry timestamp]]
                                  queryContext:context_
                                 resultContext:@[]
                           joiningPrefixLength:[prefix_ length]
                                          word:word];
        PopupEntry* e = [PopupEntry entryWithString:word 
                                              score:score];
        if (whitespaceBeforeCursor_) {
            [e setPrefix:[NSString stringWithFormat:@"%@ ", prefix_]];
        } else {
            [e setPrefix:prefix_];
        }
        [[self unfilteredModel] addHit:e];
    }
}

- (void)_processPasteboardHistory
{
    NSArray* entries = [[PasteboardHistory sharedInstance] entries];
    for (PasteboardEntry* entry in entries) {
        [self _processPasteboardEntry:entry];
    }
}

- (void)refresh {
    [self.delegate popupIsSearching:YES];
    [[self unfilteredModel] removeAllObjects];
    findContext_.substring = nil;
    VT100Screen* screen = [[self delegate] popupVT100Screen];

    x_ = startX_;
    y_ = startY_ - [screen scrollbackOverflow];

    [self _processPasteboardHistory];

    AcLog(@"Searching for '%@'", prefix_);
    matchCount_ = 0;
    [findResults_ removeAllObjects];
    more_ = YES;
    [screen setFindString:prefix_
         forwardDirection:NO
                     mode:iTermFindModeCaseInsensitiveSubstring
              startingAtX:x_
              startingAtY:y_
               withOffset:1
                inContext:findContext_
          multipleResults:YES];

    [self _doPopulateMore];
}

- (void)onClose {
    [self.delegate popupIsSearching:NO];
    [stack_ removeAllObjects];
    [moreText_ release];
    moreText_ = nil;

    if (populateTimer_) {
        [populateTimer_ invalidate];
        populateTimer_ = nil;
    }
    [super onClose];
}

- (void)rowSelected:(id)sender
{
    if ([table_ selectedRow] >= 0) {
        PopupEntry* e = [[self model] objectAtIndex:[self convertIndex:[table_ selectedRow]]];
        [stack_ removeAllObjects];
        if (moreText_) {
            [[self delegate] popupInsertText:moreText_];
            [moreText_ release];
            moreText_ = nil;
        }
        [[self delegate] popupInsertText:[e mainValue]];
        [super rowSelected:sender];
    }
}

- (void)keyDown:(NSEvent*)event
{
    NSString* keystr = [event characters];
    if ([keystr length] == 1) {
        unichar c = [keystr characterAtIndex:0];
        AcLog(@"c=%d", (int)c);
        unsigned int modflag = [event modifierFlags];
        if ((modflag & NSShiftKeyMask) && c == 25) {
            // backtab
            [self less];
            return;
        } else if (c == '\t') {
            // tab
            [self more];
        }
    }
    [super keyDown:event];
}

- (void)_pushStackObject
{
    NSArray* value = [NSArray arrayWithObjects:
                      [[moreText_ ? moreText_ : @"" copy] autorelease],
                      [[prefix_ copy] autorelease],
                      [NSNumber numberWithBool:whitespaceBeforeCursor_],
                      nil];
    assert([value count] == 3);
    [stack_ addObject:value];
}

- (void)_popStackObject
{
    NSArray* value = [stack_ lastObject];
    assert([value count] == 3);
    if (moreText_) {
        [moreText_ release];
    }
    moreText_ = [[NSMutableString stringWithString:[value objectAtIndex:0]] retain];
    prefix_ = [[NSMutableString stringWithString:[value objectAtIndex:1]] retain];
    whitespaceBeforeCursor_ = [[value objectAtIndex:2] boolValue];
    [stack_ removeLastObject];
}

- (void)less
{
    AcLog(@"Less");
    if ([stack_ count] == 0) {
        return;
    }
    [self _popStackObject];
    [self refresh];
}

- (void)more
{
    AcLog(@"More");
    if ([table_ selectedRow] >= 0) {
        PopupEntry* e = [[self model] objectAtIndex:[self convertIndex:[table_ selectedRow]]];
        NSString* selectedValue = [e mainValue];
        [self _pushStackObject];
        if (!moreText_) {
            moreText_ = [[NSMutableString alloc] initWithString:selectedValue];
        } else {
            [moreText_ appendString:selectedValue];
        }
        if (whitespaceBeforeCursor_) {
            [prefix_ appendString:@" "];
            whitespaceBeforeCursor_ = NO;
        }
        [prefix_ appendString:selectedValue];
        [self refresh];
    }
}

- (void)_populateMore:(id)sender
{
    if (populateTimer_ == nil) {
        return;
    }
    populateTimer_ = nil;
    [self _doPopulateMore];
}

- (void)_doPopulateMore
{
    VT100Screen* screen = [[self delegate] popupVT100Screen];

    struct timeval begintime;
    gettimeofday(&begintime, NULL);
    NSCharacterSet* nonWhitespace = [[NSCharacterSet whitespaceCharacterSet] invertedSet];

    iTermTextExtractor *extractor = [self textExtractor];
    do {
        int startX;
        int startY;
        int endX;
        int endY;

        findContext_.hasWrapped = YES;
        AcLog(@"Continue search...");
        
        NSDate* cs = [NSDate date];
        if ([findResults_ count] == 0) {
            assert(more_);
            AcLog(@"Do another search");
            more_ = [screen continueFindAllResults:findResults_
                                            inContext:findContext_];
        }
        AcLog(@"This iteration found %d results in %lf sec", (int) [findResults_ count], [[NSDate date] timeIntervalSinceDate:cs]);
        NSDate* ps = [NSDate date];
        int n = 0;
        while ([findResults_ count] > 0 && [[NSDate date] timeIntervalSinceDate:cs] < 0.15) {
            ++n;
            SearchResult* result = [findResults_ objectAtIndex:0];

            startX = result.startX;
            startY = result.absStartY - [screen totalScrollbackOverflow];
            endX = result.endX;
            endY = result.absEndY - [screen totalScrollbackOverflow];

            [findResults_ removeObjectAtIndex:0];

            AcLog(@"Found match at %d-%d, line %d", startX, endX, startY);
            VT100GridWindowedRange range;
            // Get the word that includes the match.
            range = [extractor rangeForWordAt:VT100GridCoordMake(startX, startY)
                                maximumLength:kReasonableMaximumWordLength];
            NSString *immutableWord = [extractor contentInRange:range
                                              attributeProvider:nil
                                                     nullPolicy:kiTermTextExtractorNullPolicyFromStartToFirst
                                                            pad:NO
                                             includeLastNewline:NO
                                         trimTrailingWhitespace:NO
                                                   cappedAtSize:-1
                                                   truncateTail:YES
                                              continuationChars:nil
                                                         coords:nil];
            NSMutableString* firstWord = [NSMutableString stringWithString:immutableWord];
            while ([firstWord length] < [prefix_ length]) {
                range = [extractor rangeForWordAt:range.coordRange.end
                                    maximumLength:kReasonableMaximumWordLength];
                NSString* part = [extractor contentInRange:range
                                         attributeProvider:nil
                                                nullPolicy:kiTermTextExtractorNullPolicyFromStartToFirst
                                                       pad:NO
                                        includeLastNewline:NO
                                    trimTrailingWhitespace:NO
                                              cappedAtSize:-1
                                              truncateTail:YES
                                         continuationChars:nil
                                                    coords:nil];
                if ([part length] == 0) {
                    break;
                }
                [firstWord appendString:part];
            }
            NSString* word = firstWord;
            AcLog(@"Matching word is %@", word);
            NSRange wordRange = [word rangeOfString:prefix_ options:(NSCaseInsensitiveSearch|NSAnchoredSearch)];
            if (wordRange.location == 0) {
                // Result has prefix_ as prefix.
                // Set fullMatch to true if the word we found is equal to prefix, or false if word just has prefix as its prefix.
                BOOL fullMatch = (wordRange.length == [word length]);

                // Grab the context before the match.
                NSMutableArray* resultContext = [NSMutableArray arrayWithCapacity:kMaxResultContextWords];
                AcLog(@"Word before what we want is in x=[%d to %d]", startX, endX);
                [self appendContextAtX:startX y:(int)startY into:resultContext maxWords:kMaxResultContextWords];

                if (fullMatch) {
                    // Grab the word after the match (presumably containing non-word characters)
                    ++endX;
                    if (endX >= [screen width]) {
                        endX -= [screen width];
                        ++endY;
                    }

                    range = [extractor rangeForWordAt:VT100GridCoordMake(endX, endY)
                                        maximumLength:kReasonableMaximumWordLength];
                    word = [extractor contentInRange:range
                                   attributeProvider:nil
                                          nullPolicy:kiTermTextExtractorNullPolicyFromStartToFirst
                                                 pad:NO
                                  includeLastNewline:NO
                              trimTrailingWhitespace:NO
                                        cappedAtSize:-1
                                        truncateTail:YES
                                   continuationChars:nil
                                              coords:nil];
                    AcLog(@"First candidate is at %@", VT100GridWindowedRangeDescription(range));
                    if ([word rangeOfCharacterFromSet:nonWhitespace].location == NSNotFound) {
                        // word after match is all whitespace. Grab the next word.
                        if (range.coordRange.end.x == [screen width]) {
                            range.coordRange.end.x = 0;
                            ++range.coordRange.end.y;
                        }
                        if (range.coordRange.end.y < [screen numberOfLines]) {
                            range = [extractor rangeForWordAt:range.coordRange.end
                                                maximumLength:kReasonableMaximumWordLength];
                            word = [extractor contentInRange:range
                                           attributeProvider:nil
                                                  nullPolicy:kiTermTextExtractorNullPolicyFromStartToFirst
                                                         pad:NO
                                          includeLastNewline:NO
                                      trimTrailingWhitespace:NO
                                                cappedAtSize:-1
                                                truncateTail:YES
                                           continuationChars:nil
                                                      coords:nil];
                            if (!whitespaceBeforeCursor_) {
                                // Prepend a space if one is needed
                                word = [NSString stringWithFormat:@" %@", word];
                            }
                            AcLog(@"Replacement candidate is at %@: '%@'",
                                  VT100GridWindowedRangeDescription(range), word);
                        } else {
                            AcLog(@"Hit end of screen.");
                        }
                    }
                } else if (!whitespaceBeforeCursor_) {
                    // Get suffix of word after match. If there's whitespace before the cursor then only
                    // full matches are interesting.
                    word = [word substringWithRange:NSMakeRange(wordRange.length, [word length] - wordRange.length)];
                } else {
                    // Not a full match and there is whitespace before the cursor.
                    word = @"";
                }

                if ([word rangeOfCharacterFromSet:nonWhitespace].location != NSNotFound) {
                    // Found a non-whitespace word after the match.
                    AcLog(@"Candidate suffix is '%@'", word);
                    int joiningPrefixLength;
                    if (fullMatch) {
                        joiningPrefixLength = 0;
                    } else {
                        joiningPrefixLength = [prefix_ length];
                    }
                    PopupEntry* e = [PopupEntry entryWithString:word score:[self scoreResultNumber:matchCount_++
                                                                                      queryContext:context_
                                                                                     resultContext:resultContext
                                                                               joiningPrefixLength:joiningPrefixLength
                                                                                              word:word]];
                    if (whitespaceBeforeCursor_) {
                        [e setPrefix:[NSString stringWithFormat:@"%@ ", prefix_]];
                    } else {
                        [e setPrefix:prefix_];
                    }
                    [[self unfilteredModel] addHit:e];
                } else {
                    AcLog(@"No candidate here.");
                }
                x_ = startX;
                y_ = startY + [screen scrollbackOverflow];
                AcLog(@"Update x,y to %d,%d", (int) x_, (int) y_);
            } else {
                // Match started in the middle of a word.
                AcLog(@"Search found %@ which doesn't start the same as our search term %@", word, prefix_);
                x_ = startX;
                y_ = startY + [screen scrollbackOverflow];
            }
        }
        AcLog(@"This iteration processed %d results in %lf sec", n, [[NSDate date] timeIntervalSinceDate:ps]);

        if (!more_ && [findResults_ count] == 0) {
            AcLog(@"no more and no unprocessed results");
            if (populateTimer_) {
               [populateTimer_ invalidate];
               populateTimer_ = nil;
            }
            break;
        }

        // Don't spend more than 150ms outside of event loop.
        struct timeval endtime;
        gettimeofday(&endtime, NULL);
        int ms_diff = (endtime.tv_sec - begintime.tv_sec) * 1000 +
            (endtime.tv_usec - begintime.tv_usec) / 1000;
        AcLog(@"ms_diff=%d", ms_diff);
        if (ms_diff > 150) {
            // Out of time. Reschedule and try again.
            AcLog(@"Schedule timer");
            populateTimer_ = [NSTimer scheduledTimerWithTimeInterval:0.01
                                                              target:self
                                                            selector:@selector(_populateMore:)
                                                            userInfo:nil
                                                             repeats:NO];
            break;
        }
    } while (more_ || [findResults_ count] > 0);
    AcLog(@"While loop exited. Nothing more to do.");
    [self reloadData:YES];
    if (!populateTimer_) {
        if (self.unfilteredModel.count == 0) {
            [self closePopupWindow];
        } else {
            [self.delegate popupIsSearching:NO];
        }
    }
}

- (void)addCommandEntries:(NSArray<iTermCommandHistoryEntryMO *> *)entries
                  context:(NSString *)context {
    int i = 0;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    for (iTermCommandHistoryEntryMO *entry in entries) {
        if (![entry.command hasPrefix:context]) {
            continue;
        }
        NSString *command = [entry.command substringFromIndex:context.length];
        NSArray *parts = [command componentsSeparatedByCharactersInSet:[iTermTextExtractor wordSeparatorCharacterSet]];
        if ([parts count] == 0) {
            continue;
        }
        command = parts[0];
        if ([command length] == 0) {
            continue;
        }
        double score = [self scoreResultNumber:i++
                                  queryContext:context_
                                 resultContext:context_  // Maximize similarity because the whole prompt is in our favor
                           joiningPrefixLength:[prefix_ length]
                                          word:command];
        
        // Boost the score for more uses of the command
        score *= sqrt(entry.numberOfUses.integerValue);
        
        // Divide the score by sqrt(the number of days since last use).
        NSTimeInterval timeSinceLastUse = now - entry.timeOfLastUse.doubleValue;
        score /= MAX(1, sqrt(timeSinceLastUse / (24 * 60 * 60.0)));
        
        score = MIN(10, score);  // Limit score of commands so really relevant context has a chance.
        PopupEntry* e = [PopupEntry entryWithString:command
                                              score:score];
        if (whitespaceBeforeCursor_) {
            [e setPrefix:[NSString stringWithFormat:@"%@ ", prefix_]];
        } else {
            [e setPrefix:prefix_];
        }
        [[self unfilteredModel] addHit:e];
    }
    [self reloadData:YES];
}

- (iTermTextExtractor *)textExtractor {
    // TODO: It would be nice to support windowed ranges, but it will hurt performance and not
    // provide a huge benefit.
    return [iTermTextExtractor textExtractorWithDataSource:[[self delegate] popupVT100Screen]];
}

@end
