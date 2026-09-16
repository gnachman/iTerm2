#!/bin/sh
# claude_usage.sh
#
# Anthropic (Claude Code) provider script for the "AI Usage" workgroup
# toolbar item. Emits AI usage as JSON.
# Reads Claude Code's subscription usage via `claude -p /usage` and
# converts the three progress lines into a bar list.
#
# Output contract (always valid JSON on stdout, always exit 0):
#   {"bars":[{"label":"Session","short":"S","fraction":0.02,
#             "detail":"resets ..."}],
#    "error":null}
# `short` is the caption for the cramped toolbar row (the toolbar item
# falls back to a derived abbreviation of `label` when it is absent).
#
# On failure, bars is empty and:
#   error       - short human-readable summary
#   diagnostic  - detailed text the user can forward to the developer, or
#                 null (present for the "format not recognized" case)
#   reportable  - true when the user should update/report (unrecognized
#                 format); false for expected states (no subscription,
#                 claude not installed, no output)
#   {"bars":[],"error":"...","diagnostic":"...","reportable":true}
# or, when nothing usable is available:
#   {"bars":[],"error":"some human-readable reason"}
#
# For testing, set ITERM2_AI_USAGE_FIXTURE to a file containing canned
# `claude -p /usage` output; the script parses that instead of invoking
# claude.

# Escape stdin into a JSON string body (no surrounding quotes). Reads the
# whole input, rejoining lines with a literal \n so a multi-line
# diagnostic stays one valid JSON string. Truncation is done by the caller
# on line boundaries (never mid-byte) so UTF-8 stays intact.
json_escape() {
    awk '
    { if (NR > 1) buf = buf "\n" $0; else buf = $0 }
    END {
        gsub(/\r/, "", buf)
        out = ""
        n = length(buf)
        for (i = 1; i <= n; i++) {
            c = substr(buf, i, 1)
            if (c == "\\") out = out "\\\\"
            else if (c == "\"") out = out "\\\""
            else if (c == "\n") out = out "\\n"
            else if (c == "\t") out = out "\\t"
            else out = out c
        }
        printf "%s", out
    }'
}

# emit_error SUMMARY REPORTABLE [DIAGNOSTIC]
# SUMMARY is a plain ASCII string (no quotes/backslashes). REPORTABLE is
# the literal `true` or `false`. DIAGNOSTIC, if given, is arbitrary text
# (JSON-escaped here) that the user can forward to the developer.
emit_error() {
    _summary=$(printf '%s' "$1" | json_escape)
    _reportable=$2
    if [ -n "$3" ]; then
        # Bound the diagnostic on line boundaries to keep it (and the
        # tooltip/alert) manageable and UTF-8-safe.
        _diag=$(printf '%s' "$3" | head -n 60 | json_escape)
        printf '{"bars":[],"error":"%s","diagnostic":"%s","reportable":%s}\n' \
            "$_summary" "$_diag" "$_reportable"
    else
        printf '{"bars":[],"error":"%s","diagnostic":null,"reportable":%s}\n' \
            "$_summary" "$_reportable"
    fi
    exit 0
}

stderr_text=""
if [ -n "$ITERM2_AI_USAGE_FIXTURE" ]; then
    if [ ! -f "$ITERM2_AI_USAGE_FIXTURE" ]; then
        emit_error "Usage fixture file not found." false ""
    fi
    usage_text=$(cat "$ITERM2_AI_USAGE_FIXTURE")
else
    if ! command -v claude >/dev/null 2>&1; then
        emit_error "The Claude Code command-line tool (claude) was not found in your PATH." false ""
    fi
    # Unset ANTHROPIC_API_KEY so claude uses the subscription login
    # rather than a developer API key (usage is subscription-only).
    # Capture stderr separately so it can go into a diagnostic if parsing
    # fails, without polluting the text we parse.
    _err_file=$(mktemp 2>/dev/null || printf '/tmp/it2_claude_usage_err.%s' "$$")
    usage_text=$(env -u ANTHROPIC_API_KEY claude -p /usage 2>"$_err_file")
    stderr_text=$(cat "$_err_file" 2>/dev/null)
    rm -f "$_err_file"
fi

# Parse the usage text with awk. Recognized line shapes (the middle dot
# is UTF-8; we key off "% used" and "resets" rather than the dot):
#   Current session: N% used ... resets REST
#   Current week (all models): N% used ... resets REST
#   Current week (LABEL): N% used ... resets REST
json=$(printf '%s\n' "$usage_text" | awk '
function jsonesc(s,   out, i, c) {
    out = ""
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "\\") out = out "\\\\"
        else if (c == "\"") out = out "\\\""
        else out = out c
    }
    return out
}
function trim(s) {
    sub(/^[ \t]+/, "", s)
    sub(/[ \t]+$/, "", s)
    return s
}
BEGIN { n = 0 }
{
    line = $0
    # Must look like a usage line.
    if (line !~ /% used/) next

    label = ""
    shortlbl = ""
    if (line ~ /^Current session:/) {
        label = "Session"
        shortlbl = "S"
    } else if (line ~ /^Current week \(all models\):/) {
        label = "Week"
        shortlbl = "W"
    } else if (line ~ /^Current week \(/) {
        # Portable capture (BSD awk has no 3-arg match): strip the
        # prefix and the trailing "):..." to isolate the model label.
        inner = line
        sub(/^Current week \(/, "", inner)
        sub(/\):.*$/, "", inner)
        label = "Week (" inner ")"
        # W + the first alphanumeric initial of the model, uppercased.
        initial = inner
        sub(/^[^0-9A-Za-z]*/, "", initial)
        initial = substr(initial, 1, 1)
        shortlbl = "W" toupper(initial)
    } else {
        next
    }

    # Extract the integer or decimal percent preceding "% used".
    pct = line
    sub(/% used.*$/, "", pct)
    # pct now ends with the number; strip everything up to the last
    # non-number run.
    if (match(pct, /[0-9]+(\.[0-9]+)?$/)) {
        num = substr(pct, RSTART, RLENGTH)
    } else {
        next
    }
    frac = num / 100.0

    # Extract the reset clause, if any.
    detail = ""
    if (match(line, /resets/)) {
        detail = substr(line, RSTART)
        detail = trim(detail)
    }

    bars[n] = "{\"label\":\"" jsonesc(label) "\",\"short\":\"" \
              jsonesc(shortlbl) "\",\"fraction\":" frac \
              ",\"detail\":\"" jsonesc(detail) "\"}"
    n++
}
END {
    if (n == 0) {
        exit 2
    }
    out = "{\"bars\":["
    for (i = 0; i < n; i++) {
        if (i > 0) out = out ","
        out = out bars[i]
    }
    out = out "],\"error\":null}"
    print out
}
')

if [ -n "$json" ]; then
    printf '%s\n' "$json"
    exit 0
fi

# No bars parsed. Classify why. The guiding rule: only ask the user to
# report a bug when the output *looks like a usage report we failed to
# parse* (a changed or localized format) - the genuine iTerm2-side defect.
# Every other outcome is an expected environment state (no subscription,
# not signed in, API-only billing, rate limited, an old claude, ...), so
# it must NOT be reportable, or users will file issues about their own
# setup. Expected states get a plain, actionable message instead.

both_output=$usage_text$stderr_text

# Does the output resemble a usage report? These phrases are the load-
# bearing parts of the format; if they're present but no bar parsed, the
# format drifted and that's worth reporting.
case "$usage_text" in
    *"% used"*|*"Current session"*|*"Current week"*)
        diag=$usage_text
        if [ -n "$stderr_text" ]; then
            diag=$(printf '%s\n--- stderr ---\n%s' "$usage_text" "$stderr_text")
        fi
        emit_error "Could not read the Claude usage report. iTerm2 may need to be updated." true "$diag"
        ;;
esac

# Not usage-shaped: an expected environment state. Pick the most helpful
# message we can from known signals (best-effort, English). Reportable is
# false in every branch below - none of these are iTerm2 bugs.

case "$both_output" in
    *"API key"*|*"api key"*|*ANTHROPIC_API_KEY*|*api_key*)
        emit_error "AI usage needs a Claude subscription (Pro or Max); it isn’t available for API-billing accounts." false ""
        ;;
esac

case "$both_output" in
    *[Ss]ubscription*)
        emit_error "AI usage is available only on a Claude subscription (Pro or Max)." false ""
        ;;
esac

case "$both_output" in
    *[Ll]og\ in*|*[Ll]ogin*|*"sign in"*|*"signed in"*|*[Aa]uthenticat*)
        emit_error "Sign in to Claude Code with a Pro or Max plan to see AI usage." false ""
        ;;
esac

case "$both_output" in
    *"rate limit"*|*"Rate limit"*|*overloaded*|*"529"*|*"429"*)
        emit_error "Claude usage is temporarily unavailable. Try again later." false ""
        ;;
esac

case "$both_output" in
    *"nknown command"*|*"available commands"*|*"not a valid"*)
        emit_error "Update Claude Code to a version that supports usage reporting." false ""
        ;;
esac

if [ -z "$usage_text" ] && [ -z "$stderr_text" ]; then
    emit_error "Claude Code produced no usage output." false ""
fi

# Got non-empty output we can't attribute to any known cause. Do NOT
# guess that it's the user's setup - unrecognized output is just as
# likely an iTerm2 problem. Make it reportable with the raw output, and
# let the wording stay neutral about who is at fault.
diag=$usage_text
if [ -n "$stderr_text" ]; then
    diag=$(printf '%s\n--- stderr ---\n%s' "$usage_text" "$stderr_text")
fi
emit_error "Could not read Claude usage. If this keeps happening, please report it." true "$diag"
