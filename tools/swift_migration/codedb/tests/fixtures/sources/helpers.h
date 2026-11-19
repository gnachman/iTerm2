// Fixture: a send in an included header.
#import "widget.h"
static inline void Helper(Widget *w) {
    [w helperSend];
}
