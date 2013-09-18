// Initialize the state of a new run, whether it is on the stack or malloc'ed.
static void CRunInitialize(CRun *run,
						   CAttrs *attrs,
						   CGFloat x);

// Append a single unicode character (no combining marks allowed) to a run.
// Returns the new tail of the run list.
static CRun *CRunAppend(CRun *run,
						CRunStorage *storage,
						CAttrs *attrs,
						unichar code,
						CGFloat advance,
						CGFloat x);

// Append a string, possibly with combining marks, to a run.
// Returns the new tail of the run list.
static CRun *CRunAppendString(CRun *run,
							  CRunStorage *storage,
							  CAttrs *attrs,
							  NSString *string,
							  CGFloat advance,
							  CGFloat x);

// Release the storage from a run and its successors in the run list.
static void CRunDestroy(CRun *run);

// Destroy and free() the run.
static void CRunFree(CRun *run);

// Move the start of the run past |offset| codes. Only valid if run->codes is
// non-null.
static void CRunAdvance(CRun *run, int offset);

// Advance past the first |newStart| characters. Split the next character into
// a CRun with a string and return that, which the caller must free. The
// remainder of the run remains in |run|. This is used when the |newStart|th
// character has a missing glyph.
static CRun *CRunSplit(CRun *run, CRunStorage *storage, int newStart);

// Gets an array of glyphs for the current run (not including its linked
// successors). The return value's memory is owned by the run's storage.
// *firstMissingGlyph will be filled in with the index of the first glyph that
// could not be found.
static CGGlyph *CRunGetGlyphs(CRun *run, int *firstMissingGlyph);

// Prevent further appends from going to |run|. They will go into a linked
// successor.
static void CRunTerminate(CRun *run);

#pragma mark - Implementations

static void CRunInitialize(CRun *run,
						   CAttrs *attrs,
						   CGFloat x) {
	run->attrs = *attrs;
	[run->attrs.color retain];
	[run->attrs.fontInfo retain];
	run->x = x;
	run->length = 0;
	run->codes = NULL;
	run->glyphs = NULL;
	run->advances = NULL;
	run->next = NULL;
	run->string = nil;
	run->terminated = NO;
}

// Append codes to an existing run. It must not have a complex string already set.
static void CRunAppendSelf(CRun *run,
						   CRunStorage *storage,
						   unichar code,
						   CGFloat advance) {
	int theIndex = [storage allocate:1];
	assert(!run->string);
	if (!run->codes) {
		run->codes = [storage codesFromIndex:theIndex];
		run->glyphs = [storage glyphsFromIndex:theIndex];
		run->advances = [storage advancesFromIndex:theIndex];
	}
	run->codes[run->length] = code;
	run->advances[run->length].height = 0;
	run->advances[run->length].width = advance;
	run->length++;
}

// Append a complex string to a run which has neither characters nor a string
// already set.
static void CRunAppendSelfString(CRun *run,
								 CRunStorage *storage,
								 NSString *string,
								 CGFloat advance) {
	int theIndex = [storage allocate:1];
	assert(!run->codes);
	assert(run->length == 0);
	run->string = [string retain];
	run->advances = [storage advancesFromIndex:theIndex];
	run->advances[0].height = 0;
	run->advances[0].width = advance;
}

// Allocate a new run and append a character to it. Link the new run as the
// successor of |run|.
static CRun *CRunAppendNew(CRun *run,
						   CRunStorage *storage,
						   CAttrs *attrs,
						   CGFloat x,
						   unichar code,
						   CGFloat advance) {
	assert(!run->next);
	CRun *newRun = malloc(sizeof(CRun));
	CRunInitialize(newRun, attrs, x);
	CRunAppendSelf(newRun, storage, code, advance);
	run->next = newRun;
	return newRun;
}

// Allocate a new run and append a complex string to it. Link the new run as
// the successor of |run|.
static CRun *CRunAppendNewString(CRun *run,
								 CRunStorage *storage,
								 CAttrs *attrs,
								 CGFloat x,
								 NSString *string,
								 CGFloat advance) {
    assert(!run->next);
	CRun *newRun = malloc(sizeof(CRun));
	CRunInitialize(newRun, attrs, x);
	CRunAppendSelfString(newRun, storage, string, advance);
    run->next = newRun;
	return newRun;
}

static CRun *CRunAppend(CRun *run,
						CRunStorage *storage,
						CAttrs *attrs,
						unichar code,
						CGFloat advance,
						CGFloat x) {
	if (run->attrs.antiAlias == attrs->antiAlias &&
		run->attrs.color == attrs->color &&
		run->attrs.fakeBold == attrs->fakeBold &&
        run->attrs.underline == attrs->underline &&
		run->attrs.fontInfo == attrs->fontInfo &&
		!run->terminated &&
		!run->string) {
		CRunAppendSelf(run, storage, code, advance);
		return run;
	} else {
		return CRunAppendNew(run, storage, attrs, x, code, advance);
	}
}

static CRun *CRunAppendString(CRun *run,
							  CRunStorage *storage,
							  CAttrs *attrs,
							  NSString *string,
							  CGFloat advance,
							  CGFloat x) {
	if (!run->codes && !run->string) {
		CRunAppendSelfString(run, storage, string, advance);
		return run;
	} else {
		return CRunAppendNewString(run, storage, attrs, x, string, advance);
	}
}

static void CRunDestroy(CRun *run) {
	[run->string release];
	[run->attrs.color release];
	[run->attrs.fontInfo release];

	if (run->next) {
		CRunDestroy(run->next);
		free(run->next);
		run->next = NULL;
	}
}

static void CRunFree(CRun *run) {
	CRunDestroy(run);
	free(run);
}

static void CRunAdvance(CRun *run, int offset) {
	assert(run->codes);
	for (int i = 0; i < offset; i++) {
		run->x += run->advances[i].width;
	}
	run->codes += offset;
	run->advances += offset;
	run->glyphs += offset;
	run->length -= offset;
}

static CRun *CRunSplit(CRun *run, CRunStorage *storage, int newStart) {
	if (run->length == 0) {
		return nil;
	}
	assert(newStart < run->length);
	CRun *newRun = malloc(sizeof(CRun));

	// Skip past |newStart| chars
	CRunAdvance(run, newStart);

	// Create a new string run from the first char
	CRunInitialize(newRun, &run->attrs, run->x);
	CRunAppendString(newRun,
					 storage,
					 &run->attrs,
					 [NSString stringWithCharacters:run->codes length:1],
					 run->advances[newStart].width,
					 run->x);

	// Skip past that one char.
	CRunAdvance(run, 1);

	return newRun;
}

static CGGlyph *CRunGetGlyphs(CRun *run, int *firstMissingGlyph) {
	assert(run->codes);
	*firstMissingGlyph = -1;
	if (run->length == 0) {
		return nil;
	}
	BOOL foundAllGlyphs = CTFontGetGlyphsForCharacters((CTFontRef)run->attrs.fontInfo.font,
													   run->codes,
													   run->glyphs,
													   run->length);
	if (!foundAllGlyphs) {
		for (int i = 0; i < run->length; i++) {
			if (!run->glyphs[i]) {
				*firstMissingGlyph = i;
				break;
			}
		}
	}
	return run->glyphs;
}

static void CRunTerminate(CRun *run) {
	run->terminated = YES;
}

