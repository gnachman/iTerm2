//
//  LineBufferTest.m
//  iTerm
//
//  Created by George Nachman on 7/19/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "LineBuffer.h"
#import "LineBufferTest.h"


@implementation LineBufferTest

////////////////////////////////////////////////////////////////////////////////////////////////
// Tests

- (screen_char_t*) toSct: (char*) str length: (int*) length partial: (BOOL*) partial
{
	screen_char_t* sct = (screen_char_t*) malloc(sizeof(screen_char_t)*strlen(str));
	*partial = NO;
	*length = 0;
	int i;
	for (i = 0; str[i]; ++i) {
		if (str[i] == '-') {
			*partial = YES;
			break;
		}
		++(*length);
		sct[i].ch = str[i];
	}
	return sct;
}


- (void) testWrapWidth: (int) width expect: (char*) expect withBlock: (LineBlock*) block
{
	char buffer[100];
	int o = 0;
	int i;
	for (i = 0; i < [block getNumLinesWithWrapWidth: width]; ++i) {
		int lineNum = i;
		int length;
		BOOL eol;
		screen_char_t* sct = [block getWrappedLineWithWrapWidth: width lineNum: &lineNum lineLength: &length includesEndOfLine: &eol];
		NSAssert(sct, @"Unexpected null result from getWrappedLineWithWrapWidth");
		int j;
		for (j = 0; j < length; ++j) {
			buffer[o++] = sct[j].ch;
		}
		if (eol) {
			buffer[o++] = '.';
		} else {
			buffer[o++] = '-';
		}
	}
	buffer[o++] = '\0';
	if (strcmp(buffer, expect)) {
		NSLog(@"Actual: %s\nExpected: %s\n", buffer, expect);
		NSAssert(NO, @"Unexpected result in testWrapWidth.");
	} else {
		NSLog(@"testWrapWidth ok for width %d", width);
	}
}


- (void) testBufferWrapWidth: (int) width expect: (char*) expect withBuffer: (LineBuffer*) linebuf
{
	char buffer[100];
	int o = 0;
	int i;
	for (i = 0; i < [linebuf numLinesWithWidth: width]; ++i) {
		screen_char_t sctbuf[100];
		memset((char*) sctbuf, 0, sizeof(sctbuf));
		BOOL continuation = [linebuf copyLineToBuffer: sctbuf width: width lineNum: i];
		
		int j;
		for (j = 0; sctbuf[j].ch; ++j) {
			buffer[o++] = sctbuf[j].ch;
		}
		if (!continuation) {
			buffer[o++] = '.';
		} else {
			buffer[o++] = '-';
		}
	}
	buffer[o++] = '\0';
	if (strcmp(buffer, expect)) {
		NSLog(@"Actual: %s\nExpected: %s\n", buffer, expect);
		NSAssert(NO, @"Unexpected result in testWrapWidth.");
	} else {
		NSLog(@"testWrapWidth ok for width %d", width);
	}
}

char* testlines[] = {
"aaa",
"b",
"ccc-", "c",
"dddddd-", "ddd",
"",
"e-", "e",
NULL
};
- (void) fillBlock: (LineBlock*) block
{
	int i;
	for (i = 0; testlines[i]; ++i) {
		int length;
		BOOL partial;
		screen_char_t* sct = [self toSct: testlines[i] length: &length partial: &partial];
		[block appendLine: sct length: length partial: partial];
		free((void*) sct);
	}	
}

- (void) fillBuffer: (LineBuffer*) buffer
{
	int i;
	for (i = 0; testlines[i]; ++i) {
		int length;
		BOOL partial;
		screen_char_t* sct = [self toSct: testlines[i] length: &length partial: &partial];
		[buffer appendLine: sct length: length partial: partial];
		free((void*) sct);
	}	
}

char* wraplines2 =
"aa-"
"a."
"b."
"cc-"
"cc."
"dd-"
"dd-"
"dd-"
"dd-"
"d."
"."
"ee.";
char* wraplines3 =
"aaa."
"b."
"ccc-"
"c."
"ddd-"
"ddd-"
"ddd."
"."
"ee.";
char* wraplines4 =
"aaa."
"b."
"cccc."
"dddd-"
"dddd-"
"d."
"."
"ee.";
char* wraplines9 =
"aaa."
"b."
"cccc."
"ddddddddd."
"."
"ee.";

- (void) testAppend
{
	LineBlock* block = [[LineBlock alloc] initWithRawBufferSize: 100];
	[self fillBlock: block];
	[self testWrapWidth:2 expect:wraplines2 withBlock: block];
	[self testWrapWidth:3 expect:wraplines3 withBlock: block];
	[self testWrapWidth:4 expect:wraplines4 withBlock: block];
	[self testWrapWidth:9 expect:wraplines9 withBlock: block];
	[block release];
}

- (void) fromScr: (screen_char_t*) ptr length: (int) length into: (char*) buffer
{
	int i;
	for (i = 0; i < length; i++) {
		buffer[i] = ptr[i].ch;
	}
	buffer[i] = '\0';
}

- (void) testPopWithWidth: (int) width expect: (char**) expect
{
	LineBlock* block = [[LineBlock alloc] initWithRawBufferSize: 100];
	[self fillBlock: block];
	[block shrinkToFit];  // throw in a test of this too, why not
	
	char buffer[100];
	screen_char_t* ptr;
	int length;
	
	int i;
	for (i = 0; expect[i+1]; ++i)
		;
	while ([block popLastLineInto: &ptr withLength: &length upToWidth: width]) {
		[self fromScr: ptr length: length into: buffer];
		NSAssert(i >= 0, @"Too many lines popped");
		if (strcmp(buffer, expect[i--])) {
			NSLog(@"Actual: %s\nExpected: %s\n", buffer, expect[i+1]);
			NSAssert(NO, @"testPopWithWidth failed");
		}
	}
	NSAssert(i == -1, @"Not enough lines popped");
	NSAssert([block isEmpty], @"Block not empty");
	[block release];
	NSLog(@"Test popWithWidth for %d ok", width);
}

- (void) testBufferPopWithWidth: (int) width expect: (char**) expect blocksize: (int) blocksize
{
	LineBuffer* linebuf = [[LineBuffer alloc] initWithBlockSize: blocksize];
	[self fillBuffer: linebuf];
	char buffer[100];
	
	int i;
	for (i = 0; expect[i+1]; ++i)
		;
	screen_char_t scbuf[100];
	BOOL eol;
	memset((char*) scbuf, 0, sizeof(scbuf));
	while ([linebuf popAndCopyLastLineInto: scbuf width: width includesEndOfLine: &eol]) {
		int length;
		for (length = 0; length < 100 && scbuf[length].ch; ++length)
			;
		[self fromScr: scbuf length: length into: buffer];
		NSAssert(i >= 0, @"Too many lines popped");
		if (strcmp(buffer, expect[i--])) {
			NSLog(@"Actual: %s\nExpected: %s\n", buffer, expect[i+1]);
			NSAssert(NO, @"testPopWithWidth failed");
		}
		memset((char*) scbuf, 0, sizeof(scbuf));
	}
	NSAssert(i == -1, @"Not enough lines popped");
	NSAssert([linebuf numLinesWithWidth: width] == 0, @"Buffer not empty");
	[linebuf release];
	NSLog(@"Test bufferPopWithWidth for %d, blocksize %d ok", width, blocksize);
}

char* poplines2[] = {
"aa",
"a",
"b",
"cc",
"cc",
"dd",
"dd",
"dd",
"dd",
"d",
"",
"ee",
0 };
char* poplines3[] = {
"aaa",
"b",
"ccc",
"c",
"ddd",
"ddd",
"ddd",
"",
"ee",
0 };
char* poplines4[] = {
"aaa",
"b",
"cccc",
"dddd",
"dddd",
"d",
"",
"ee",
0 };
char* poplines9[] = {
"aaa",
"b",
"cccc",
"ddddddddd",
"",
"ee",
0 };

- (void) testPop
{
	[self testPopWithWidth: 2 expect: poplines2];
	[self testPopWithWidth: 3 expect: poplines3];
	[self testPopWithWidth: 4 expect: poplines4];
	[self testPopWithWidth: 9 expect: poplines9];
}

- (void) testBufferPopWithBlockSize: (int) blocksize
{
	[self testBufferPopWithWidth: 2 expect: poplines2 blocksize: blocksize];
	[self testBufferPopWithWidth: 3 expect: poplines3 blocksize: blocksize];
	[self testBufferPopWithWidth: 4 expect: poplines4 blocksize: blocksize];
	[self testBufferPopWithWidth: 9 expect: poplines9 blocksize: blocksize];
}

- (void) testBufferAppendWithBlockSize: (int) blocksize
{
	LineBuffer* buf = [[LineBuffer alloc] initWithBlockSize: blocksize];
	[self fillBuffer: buf];
	[self testBufferWrapWidth: 2 expect: wraplines2 withBuffer: buf];
	[self testBufferWrapWidth: 3 expect: wraplines3 withBuffer: buf];
	[self testBufferWrapWidth: 4 expect: wraplines4 withBuffer: buf];
	[self testBufferWrapWidth: 9 expect: wraplines9 withBuffer: buf];
	[buf release];
}

- (void) testBufferAppend
{
	int i;
	for (i = 1; i < 21; ++i) {
		NSLog(@"Begin tests with block size %d", i);
		[self testBufferAppendWithBlockSize: i];
	}	
}

- (void) testBufferPop
{
	int i;
	for (i = 1; i < 21; ++i) {
		NSLog(@"Begin tests with block size %d", i);
		[self testBufferPopWithBlockSize: i];
	}
}

- (void) randomTest
{
	char* lines[100];
	char wrapped[100 * 1000];
	BOOL continued[10000];
	int numlines = 0;
	int width = 50;
	int y = 0;
	LineBuffer* linebuf = [[LineBuffer alloc] initWithBlockSize: 100];
	int iter;
	srand(0);
	for (iter = 0; iter < 1000000; iter++) {
		if (y > 0 && wrapped[0] == 0) {
			NSAssert(wrapped[0] != 0, @"Wrapped[0] is 0");
		}
		//		NSLog(@"Begin iteration %d\n", iter);
		if (iter % 1000 == 0) {
			NSLog(@"Iteartion %d\n", iter);
		}
		
		int action = rand() % 2;
		int reps = rand() % 10;
		int i;
		switch (action) {
			case 0:
				// Append
				if (numlines + reps > 100) break;
				for (i = 0; i < reps; ++i) {
					// Generate a random string and put a text version in ascii
					// and and sct version in buf. Also append it to wrapped.
					// Then add ascii to lines.
					screen_char_t buf[200];
					int len = rand() % 200;
					char* prefix = "";
					if (y > 0 && numlines > 0 && continued[y-1]) {
						prefix = lines[numlines - 1];
						numlines--;
					}
					char* whole_ascii = (char*)malloc(len+1+strlen(prefix));
					char* ascii = whole_ascii + strlen(prefix);
					int j;
					for (j = 0; j < len; ++j) {
						char ch = 'A' + (rand() % 26);
						buf[j].ch = ch;
						ascii[j] = ch;
					}			
					ascii[j] = 0;					
					memcpy(whole_ascii, prefix, strlen(prefix));
					lines[numlines++] = whole_ascii;
					
					// Recompute wrapped buffer
					memset(wrapped, 0, sizeof(wrapped));
					y = 0;
					for (j = 0; j < numlines; ++j) {
						int k;
						int x = 0;
						for (k = 0; lines[j][k]; ++k) {
							wrapped[y*width + x] = lines[j][k];
							++x;
							if (x == width) {
								continued[y] = YES;
								x = 0;
								++y;
							}
						}
						if (x == 0 && y > 0 && lines[j][0]) {
							// the line happened to be an exact multiple of
							// width, but wasn't 0 length.
							continued[y - 1] = NO;
						} else {
							continued[y] = NO;
							++y;
						}
					}
					
					//					NSLog(@"Append: \"%s\", length=%d, y=%d\n", ascii, len, y);
					if (strlen(prefix)) {
						free(prefix);
					}
					
					// Add it in random sized parts to linebuf.
					int offset = 0;
					if (len == 0) {
						[linebuf appendLine: buf length: 0 partial: NO];
					}
					while (offset < len) {
						int n = rand() % ((len-offset) + 1);
						[linebuf appendLine: buf+offset length: n partial: ((offset+n)<len)];
						offset += n;
					}
				}
				break;
				
			case 1:
				// Pop
				if (numlines - reps < 0) break;
				for (i = 0; i < reps; ++i) {
					screen_char_t popped[1000];
					BOOL eol;
					memset((char*) popped, 0, sizeof(popped));
					BOOL ok = [linebuf popAndCopyLastLineInto: popped width: width includesEndOfLine: &eol];
					NSAssert(ok, @"Pop failed");
					NSAssert(eol != continued[y-1], @"EOL mismatch");
					int j;
					char ascii[1000];
					for (j = 0; j < width; ++j) {
						ascii[j] = popped[j].ch;
						NSAssert(wrapped[width*(y-1) + j] == popped[j].ch,
								 @"Popped something unexpected.");
					}
					ascii[j] = 0;
					if (strlen(lines[numlines-1]) <= width) {
						//						NSLog(@"Popped to start of line: %s\n", ascii);
						NSAssert(!strcmp(lines[numlines-1], ascii), @"Line doesn't match popped");
						free((void*) lines[numlines-1]);
						numlines--;
					} else {
						//						NSLog(@"Popped off end of line: %s\n", ascii);
						for (j = 0; j < width && wrapped[width*(y-1)+j]; ++j)
							;
						NSAssert(!strcmp(lines[numlines-1] + strlen(lines[numlines-1]) - j, ascii), @"Popped doesn't equal line suffix");
						lines[numlines-1][strlen(lines[numlines-1]) - j] = 0;
					}
					--y;
					NSAssert(y >= 0, @"Bug");
				}
				break;
		}
		
		// Verify that the wrapped contents match the buffer
		int nl = [linebuf numLinesWithWidth: width];
		for (i = 0; i < y && i < nl; ++i) {
			screen_char_t sct[1000];
			memset((char*)sct, 0, sizeof(sct));
			BOOL cont = [linebuf copyLineToBuffer: sct	width:width lineNum:i];
			int j;
			char temp2[1000];
			for (j = 0; j < width; ++j) {
				temp2[j] = sct[j].ch;
			}
			temp2[j] = 0;
			char temp[1000];
			for (j = 0; j < width; ++j) {
				temp[j] = wrapped[i*width + j];
			}
			temp[j] = 0;
			// Uncomment the next line to see side-by-side logs of expected vs actual wrapped buffers.
			//			NSLog(@"%d %-50s %c    %-50s %c\n", i, temp, continued[i] ? '-' : '.', temp2, cont ? '-' : '.');
			for (j = 0; j < width; ++j) {
				NSAssert(wrapped[width*i + j] == sct[j].ch, @"Verify failed");
			}
			NSAssert(cont == continued[i], @"Continuation mismatch");
		}
	}
}

- (void) findTest
{
	LineBuffer* buffer = [[LineBuffer alloc] initWithBlockSize:20];
	[buffer setMaxLines:3];
	
	screen_char_t* sct;
	int length;
	BOOL partial;
	sct = [self toSct: "deadxx" length: &length partial: &partial];
	[buffer appendLine:sct length:6 partial:NO];
	free((void*)sct);

	sct = [self toSct: "firstx" length: &length partial: &partial];
	[buffer appendLine:sct length:6 partial:NO];
	free((void*)sct);
	
	sct = [self toSct: "lastxx" length: &length partial: &partial];
	[buffer appendLine:sct length:6 partial:NO];
	free((void*)sct);
	
	sct = [self toSct: "xzzyzza" length: &length partial: &partial];
	[buffer appendLine:sct length:7 partial:NO];
	free((void*)sct);
	[buffer dropExcessLinesWithWidth:10];

	[buffer dump];
	int len;
	int pos = [buffer findSubstring:@"zz" startingAt:0 resultLength:&len options:FindOptCaseInsensitive stopAt:[buffer lastPos]];
	NSAssert(pos == 19, @"First match in wrong place");
	int x=0, y=0;
	BOOL ok = [buffer convertPosition:pos withWidth:8 toX:&x toY:&y];
	NSAssert(ok, @"convertPosition failed");
	NSAssert(x == 1, @"Wrong x");
	NSAssert(y == 2, @"Wrong y");
	
	ok = [buffer convertCoordinatesAtX:x atY:y withWidth:8 toPosition:&pos offset:1];
	NSAssert(ok, @"convertCoords failed");
	NSAssert(pos == 20, @"Pos advanced wrong");
	
	pos = [buffer findSubstring:@"zz" startingAt:pos resultLength:&len options:FindOptCaseInsensitive stopAt:[buffer lastPos]];
	NSAssert(pos == 22, @"Seond match in wrong place");
	
	ok = [buffer convertPosition:pos withWidth:8 toX:&x toY:&y];
	NSAssert(ok, @"convertposition failed");
	NSAssert(x == 4, @"Wrong x");
	NSAssert(y == 2, @"Wrong y");

	ok = [buffer convertCoordinatesAtX:x atY:y withWidth:8 toPosition:&pos offset:1];
	NSAssert(ok, @"convertCoords failed");
	NSAssert(pos == 23, @"Pos advanced wrong");
	
	ok = [buffer convertCoordinatesAtX:6 atY:2 withWidth:10 toPosition:&pos offset:1];
	NSAssert(!ok, @"Went past end but succeeded.");

	ok = [buffer convertCoordinatesAtX:5 atY:0 withWidth:10 toPosition:&pos offset:1];
	NSAssert(ok, @"Crossing blocks failed.");
	NSAssert(pos == 12, @"offset crossing blocks failed");

	[buffer release];
}

- (void) runTests
{
	[self findTest];
	[self testAppend];
	[self testPop];
	[self testBufferAppend];
	[self testBufferPop];
	[self randomTest];
}

@end
