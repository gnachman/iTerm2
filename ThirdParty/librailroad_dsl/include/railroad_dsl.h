#ifndef RAILROAD_DSL_H
#define RAILROAD_DSL_H

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

char *railroad_dsl_to_svg(const char *input, const char *css);

/**
 * Free any string allocated by Rust (e.g. from dsl_to_svg)
 */
void railroad_string_free(char *s);

/**
 * Return the default CSS for the given theme ("light" or "dark").
 *
 * # Safety
 * - `theme` must be a valid, NUL-terminated C string.
 * - Returns a pointer into a freshly allocated `CString`; caller must free
 *   it via `CString::from_raw(...)`.
 */
char *railroad_dsl_css_for_theme(const char *theme);

bool railroad_dsl_is_valid(const char *input);

#endif  /* RAILROAD_DSL_H */
