//
//  VT100OtherParser.m
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import "VT100OtherParser.h"

@implementation VT100OtherParser

+ (void)decodeBytes:(unsigned char *)datap
             length:(int)datalen
          bytesUsed:(int *)rmlen
              token:(VT100Token *)result
           encoding:(NSStringEncoding)encoding {
    int c1, c2;
    
    NSCParameterAssert(datap[0] == VT100CC_ESC);
    NSCParameterAssert(datalen > 1);
    
    c1 = (datalen >= 2 ? datap[1]: -1);
    c2 = (datalen >= 3 ? datap[2]: -1);
    // A third parameter could be available but isn't currently used.
    // c3 = (datalen >= 4 ? datap[3]: -1);
    
    switch (c1) {
        case 27: // esc: two esc's in a row. Ignore the first one.
            result->type = VT100_NOTSUPPORT;
            *rmlen = 1;
            break;

        case '%':
            if (c2 == '@') {
                result->type = ISO2022_SELECT_LATIN_1;
                *rmlen = 3;
            } else if (c2 == 'G') {
                result->type = ISO2022_SELECT_UTF_8;
                *rmlen = 3;
            } else {
                result->type = VT100_NOTSUPPORT;
                *rmlen = 2;
            }
            break;

        case '#':
            if (c2 < 0) {
                result->type = VT100_WAIT;
            } else {
                switch (c2) {
                    case '8':
                        result->type = VT100CSI_DECALN;
                        break;
                    default:
                        result->type = VT100_NOTSUPPORT;
                }
                *rmlen = 3;
            }
            break;
            
        case '=':
            result->type = VT100CSI_DECKPAM;
            *rmlen = 2;
            break;
            
        case '>':
            result->type = VT100CSI_DECKPNM;
            *rmlen = 2;
            break;
            
        case '<':
            result->type = STRICT_ANSI_MODE;
            *rmlen = 2;
            break;
            
        case '(':
            if (c2 < 0) {
                result->type = VT100_WAIT;
            } else {
                result->type = VT100CSI_SCS0;
                result->code = c2;
                *rmlen = 3;
            }
            break;
        case ')':
            if (c2 < 0) {
                result->type = VT100_WAIT;
            } else {
                result->type = VT100CSI_SCS1;
                result->code = c2;
                *rmlen = 3;
            }
            break;
        case '*':
            if (c2 < 0) {
                result->type = VT100_WAIT;
            } else {
                result->type = VT100CSI_SCS2;
                result->code = c2;
                *rmlen = 3;
            }
            break;
        case '+':
            if (c2 < 0) {
                result->type = VT100_WAIT;
            } else {
                result->type = VT100CSI_SCS3;
                result->code = c2;
                *rmlen = 3;
            }
            break;
            
        case '8':
            result->type = VT100CSI_DECRC;
            *rmlen = 2;
            break;
            
        case '7':
            result->type = VT100CSI_DECSC;
            *rmlen = 2;
            break;
            
        case 'D':
            result->type = VT100CSI_IND;
            *rmlen = 2;
            break;
            
        case 'E':
            result->type = VT100CSI_NEL;
            *rmlen = 2;
            break;
            
        case 'H':
            result->type = VT100CSI_HTS;
            *rmlen = 2;
            break;
            
        case 'M':
            result->type = VT100CSI_RI;
            *rmlen = 2;
            break;
            
        case 'Z':
            result->type = VT100CSI_DECID;
            *rmlen = 2;
            break;
            
        case 'c':
            result->type = VT100CSI_RIS;
            *rmlen = 2;
            break;
            
        case 'k':
            // The screen term uses <esc>k<title><cr|esc\> to set the title.
            if (datalen > 0) {
                int i;
                BOOL found = NO;
                // Search for esc or newline terminator.
                for (i = 2; i < datalen; i++) {
                    BOOL isTerminator = NO;
                    int length = i - 2;
                    if (datap[i] == VT100CC_ESC && i + 1 == datalen) {
                        break;
                    } else if (datap[i] == VT100CC_ESC && datap[i + 1] == '\\') {
                        i++;  // cause the backslash to be consumed below
                        isTerminator = YES;
                    } else if (datap[i] == '\n' || datap[i] == '\r') {
                        isTerminator = YES;
                    }
                    if (isTerminator) {
                        // Found terminator. Grab text from datap to char before it
                        // save in result.string.
                        NSData *data = [NSData dataWithBytes:datap + 2 length:length];
                        result.string = [[[NSString alloc] initWithData:data
                                                                  encoding:encoding] autorelease];
                        // Consume everything up to the terminator
                        *rmlen = i + 1;
                        found = YES;
                        break;
                    }
                }
                if (found) {
                    if (result.string.length == 0) {
                        // Ignore 0-length titles to avoid getting bitten by a screen
                        // feature/hack described here:
                        // http://www.gnu.org/software/screen/manual/screen.html#Dynamic-Titles
                        //
                        // screen has a shell-specific heuristic that is enabled by setting the
                        // window's name to search|name and arranging to have a null title
                        // escape-sequence output as a part of your prompt. The search portion
                        // specifies an end-of-prompt search string, while the name portion
                        // specifies the default shell name for the window. If the name ends in
                        // a ‘:’ screen will add what it believes to be the current command
                        // running in the window to the end of the specified name (e.g. name:cmd).
                        // Otherwise the current command name supersedes the shell name while it
                        // is running.
                        //
                        // Here's how it works: you must modify your shell prompt to output a null
                        // title-escape-sequence (<ESC> k <ESC> \) as a part of your prompt. The
                        // last part of your prompt must be the same as the string you specified
                        // for the search portion of the title. Once this is set up, screen will
                        // use the title-escape-sequence to clear the previous command name and
                        // get ready for the next command. Then, when a newline is received from
                        // the shell, a search is made for the end of the prompt. If found, it
                        // will grab the first word after the matched string and use it as the
                        // command name. If the command name begins with ‘!’, ‘%’, or ‘^’, screen
                        // will use the first word on the following line (if found) in preference
                        // to the just-found name. This helps csh users get more accurate titles
                        // when using job control or history recall commands.
                        result->type = VT100_NOTSUPPORT;
                    } else {
                        result->type = XTERMCC_WINICON_TITLE;
                    }
                } else {
                    result->type = VT100_WAIT;
                }
            } else {
                result->type = VT100_WAIT;
            }
            break;
            
        case ' ':
            if (c2 < 0) {
                result->type = VT100_WAIT;
            } else {
                switch (c2) {
                    case 'L':
                    case 'M':
                    case 'N':
                    case 'F':
                    case 'G':
                        *rmlen = 3;
                        result->type = VT100_NOTSUPPORT;
                        break;
                    default:
                        *rmlen = 1;
                        result->type = VT100_NOTSUPPORT;
                        break;
                }
            }
            break;
            
        default:
            result->type = VT100_NOTSUPPORT;
            *rmlen = 2;
            break;
    }
}

@end
