# Clicking a notification can fail to reveal its session, or reveal a different one

**Where:** `sources/Notifications/iTermNotificationController.m`, `-notificationWasClicked:` (near line 387), and the posting methods that store the window index, tab index and view id (near lines 172 and 252).

**What happens:** a notification remembers its session as a window index, a tab index and a view id, taken when it was posted. View ids count the `SessionView`s created since launch (`SessionView.m`, near lines 51 and 257), so each is unique. Two cases go wrong:
- **Windows or tabs changed after it was posted.** If an earlier window or tab was closed, or the tabs were reordered, before the user clicks, the indexes name another tab or none. That tab does not hold the view id, so `-[PTYTab sessionWithViewId:]` returns nil and the click does nothing, or beeps when an index is past the end, although the session still exists. This is the likelier case: notifications stay in Notification Center for a long time.
- **It was posted without a window.** A notification posted through `-notify:withDescription:`, which passes -1, or for a session whose window is not registered (`-[PTYSession screenWindowIndex]` is -1), carries an empty user info. A click reads the missing indexes as 0. View id 0 is the first session of the run, so the click reveals that unrelated session while it is still in the first tab of the first window, and otherwise does nothing.

**Why:**

```objc
int win = [clickContext[@"win"] intValue];   // 0 when absent
...
if (win >= [controller numberOfTerminals]) { NSBeep(); return; }
```

The handler finds the session by position, checks only the upper bound, and cannot tell an absent index from index 0.

**How to see it:** in the third of three tabs, run a command that posts a notification when it finishes (an alert on completion), close the first tab, then click the notification: nothing is revealed. Seen by reading the code; not run.

**Suggested fix:** store the session's GUID in the notification and look the session up by GUID on a click, doing nothing when there is none.

**Found:** 2026-11-21, from a question by the owner about `screenWindowIndex`.

**Checked against the tree:** 2026-11-27. The handler and the posting code are unchanged; view ids still come from a counter that starts at 0.
