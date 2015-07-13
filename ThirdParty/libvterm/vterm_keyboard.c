// This code is based on keyboard.c in libvterm but is hacked up to work in iTerm2.

#include "vterm_keyboard.h"
#include "vterm_utf8.h"
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>


static void vterm_push_output_vsprintf(VTermWriteCallback *callback, const char *format, va_list args)
{
    char *outbuffer;
    int written = vasprintf(&outbuffer, format, args);
    if (written > 0) {
        callback(outbuffer, written);
    }
    if (written >= 0) {
        free(outbuffer);
    }
}

static void vterm_push_output_sprintf(VTermWriteCallback *callback, const char *format, ...)
{
    va_list args;
    va_start(args, format);
    vterm_push_output_vsprintf(callback, format, args);
    va_end(args);
}

static void vterm_push_output_sprintf_ctrl(VTermWriteCallback *callback, unsigned char ctrl, const char *fmt, ...)
{
    vterm_push_output_sprintf(callback, "%c", ctrl);

    va_list args;
    va_start(args, fmt);
    vterm_push_output_vsprintf(callback, fmt, args);
    va_end(args);
}

void vterm_keyboard_unichar(uint32_t c, VTermModifier mod, VTermWriteCallback *callback)
{
  /* The shift modifier is never important for Unicode characters
   * apart from Space
   */
  if(c != ' ')
    mod &= ~VTERM_MOD_SHIFT;

  if(mod == 0) {
    // Normal text - ignore just shift
    char str[6];
    int seqlen = vterm_fill_utf8(c, str);
    callback(str, seqlen);
    return;
  }

  int needs_CSIu;
  switch(c) {
    /* Special Ctrl- letters that can't be represented elsewise */
    case 'i': case 'j': case 'm': case '[':
      needs_CSIu = 1;
      break;
    /* Ctrl-\ ] ^ _ don't need CSUu */
    case '\\': case ']': case '^': case '_':
      needs_CSIu = 0;
      break;
    /* All other characters needs CSIu except for letters a-z */
    default:
      needs_CSIu = (c < 'a' || c > 'z');
  }

  /* ALT we can just prefix with ESC; anything else requires CSI u */
  if(needs_CSIu && (mod & ~VTERM_MOD_ALT)) {
    vterm_push_output_sprintf_ctrl(callback, C1_CSI, "%d;%du", c, mod+1);
    return;
  }

  if(mod & VTERM_MOD_CTRL)
    c &= 0x1f;

  vterm_push_output_sprintf(callback, "%s%c", mod & VTERM_MOD_ALT ? "\e" : "", c);
}

typedef struct {
  enum {
    KEYCODE_NONE,
    KEYCODE_LITERAL,
    KEYCODE_TAB,
    KEYCODE_ENTER,
    KEYCODE_SS3,
    KEYCODE_CSI,
    KEYCODE_CSI_CURSOR,
    KEYCODE_CSINUM,
    KEYCODE_KEYPAD,
  } type;
  char literal;
  int csinum;
} keycodes_s;

static keycodes_s keycodes[] = {
  { KEYCODE_NONE }, // NONE

  { KEYCODE_ENTER,   '\r'   }, // ENTER
  { KEYCODE_TAB,     '\t'   }, // TAB
  { KEYCODE_LITERAL, '\x7f' }, // BACKSPACE == ASCII DEL
  { KEYCODE_LITERAL, '\e'   }, // ESCAPE

  { KEYCODE_CSI_CURSOR, 'A' }, // UP
  { KEYCODE_CSI_CURSOR, 'B' }, // DOWN
  { KEYCODE_CSI_CURSOR, 'D' }, // LEFT
  { KEYCODE_CSI_CURSOR, 'C' }, // RIGHT

  { KEYCODE_CSINUM, '~', 2 },  // INS
  { KEYCODE_CSINUM, '~', 3 },  // DEL
  { KEYCODE_CSI_CURSOR, 'H' }, // HOME
  { KEYCODE_CSI_CURSOR, 'F' }, // END
  { KEYCODE_CSINUM, '~', 5 },  // PAGEUP
  { KEYCODE_CSINUM, '~', 6 },  // PAGEDOWN
};

static keycodes_s keycodes_fn[] = {
  { KEYCODE_NONE },            // F0 - shouldn't happen
  { KEYCODE_CSI_CURSOR, 'P' }, // F1
  { KEYCODE_CSI_CURSOR, 'Q' }, // F2
  { KEYCODE_CSI_CURSOR, 'R' }, // F3
  { KEYCODE_CSI_CURSOR, 'S' }, // F4
  { KEYCODE_CSINUM, '~', 15 }, // F5
  { KEYCODE_CSINUM, '~', 17 }, // F6
  { KEYCODE_CSINUM, '~', 18 }, // F7
  { KEYCODE_CSINUM, '~', 19 }, // F8
  { KEYCODE_CSINUM, '~', 20 }, // F9
  { KEYCODE_CSINUM, '~', 21 }, // F10
  { KEYCODE_CSINUM, '~', 23 }, // F11
  { KEYCODE_CSINUM, '~', 24 }, // F12
};

static keycodes_s keycodes_kp[] = {
  { KEYCODE_KEYPAD, '0', 'p' }, // KP_0
  { KEYCODE_KEYPAD, '1', 'q' }, // KP_1
  { KEYCODE_KEYPAD, '2', 'r' }, // KP_2
  { KEYCODE_KEYPAD, '3', 's' }, // KP_3
  { KEYCODE_KEYPAD, '4', 't' }, // KP_4
  { KEYCODE_KEYPAD, '5', 'u' }, // KP_5
  { KEYCODE_KEYPAD, '6', 'v' }, // KP_6
  { KEYCODE_KEYPAD, '7', 'w' }, // KP_7
  { KEYCODE_KEYPAD, '8', 'x' }, // KP_8
  { KEYCODE_KEYPAD, '9', 'y' }, // KP_9
  { KEYCODE_KEYPAD, '*', 'j' }, // KP_MULT
  { KEYCODE_KEYPAD, '+', 'k' }, // KP_PLUS
  { KEYCODE_KEYPAD, ',', 'l' }, // KP_COMMA
  { KEYCODE_KEYPAD, '-', 'm' }, // KP_MINUS
  { KEYCODE_KEYPAD, '.', 'n' }, // KP_PERIOD
  { KEYCODE_KEYPAD, '/', 'o' }, // KP_DIVIDE
  { KEYCODE_KEYPAD, '\n', 'M' }, // KP_ENTER
  { KEYCODE_KEYPAD, '=', 'X' }, // KP_EQUAL
};

void vterm_keyboard_key(VTermOptions *options, VTermKey key, VTermModifier mod, VTermWriteCallback *callback)
{
  if(key == VTERM_KEY_NONE)
    return;

  keycodes_s k;
  if(key < VTERM_KEY_FUNCTION_0) {
    if(key >= sizeof(keycodes)/sizeof(keycodes[0]))
      return;
    k = keycodes[key];
  }
  else if(key >= VTERM_KEY_FUNCTION_0 && key <= VTERM_KEY_FUNCTION_MAX) {
    if((key - VTERM_KEY_FUNCTION_0) >= sizeof(keycodes_fn)/sizeof(keycodes_fn[0]))
      return;
    k = keycodes_fn[key - VTERM_KEY_FUNCTION_0];
  }
  else if(key >= VTERM_KEY_KP_0) {
    if((key - VTERM_KEY_KP_0) >= sizeof(keycodes_kp)/sizeof(keycodes_kp[0]))
      return;
    k = keycodes_kp[key - VTERM_KEY_KP_0];
  }

  switch(k.type) {
  case KEYCODE_NONE:
    break;

  case KEYCODE_TAB:
    /* Shift-Tab is CSI Z but plain Tab is 0x09 */
    if(mod == VTERM_MOD_SHIFT)
      vterm_push_output_sprintf_ctrl(callback, C1_CSI, "Z");
    else if(mod & VTERM_MOD_SHIFT)
      vterm_push_output_sprintf_ctrl(callback, C1_CSI, "1;%dZ", mod+1);
    else
      goto case_LITERAL;
    break;

  case KEYCODE_ENTER:
    /* Enter is CRLF in newline mode, but just LF in linefeed */
    if (options->newline)
      vterm_push_output_sprintf(callback, "\r\n");
    else
      goto case_LITERAL;
    break;

  case KEYCODE_LITERAL: case_LITERAL:
    if(mod & (VTERM_MOD_SHIFT|VTERM_MOD_CTRL))
      vterm_push_output_sprintf_ctrl(callback, C1_CSI, "%d;%du", k.literal, mod+1);
    else
      vterm_push_output_sprintf(callback, mod & VTERM_MOD_ALT ? "\e%c" : "%c", k.literal);
    break;

  case KEYCODE_SS3: case_SS3:
    if(mod == 0)
      vterm_push_output_sprintf_ctrl(callback, C1_SS3, "%c", k.literal);
    else
      goto case_CSI;
    break;

  case KEYCODE_CSI: case_CSI:
    if(mod == 0)
      vterm_push_output_sprintf_ctrl(callback, C1_CSI, "%c", k.literal);
    else
      vterm_push_output_sprintf_ctrl(callback, C1_CSI, "1;%d%c", mod + 1, k.literal);
    break;

  case KEYCODE_CSINUM:
    if(mod == 0)
      vterm_push_output_sprintf_ctrl(callback, C1_CSI, "%d%c", k.csinum, k.literal);
    else
      vterm_push_output_sprintf_ctrl(callback, C1_CSI, "%d;%d%c", k.csinum, mod + 1, k.literal);
    break;

  case KEYCODE_CSI_CURSOR:
    if(options->cursor)
      goto case_SS3;
    else
      goto case_CSI;

  case KEYCODE_KEYPAD:
    if(options->keypad) {
      k.literal = k.csinum;
      goto case_SS3;
    }
    else
      goto case_LITERAL;
  }
}
