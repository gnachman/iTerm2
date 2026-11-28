# An object that subscribes to two internal notifications silently loses the first subscription

**Waiting on the owner:** the fix changes what is stored in an existing associated object; CLAUDE.md asks for his permission for associated objects.

**Where:** `sources/Notifications/iTermNotificationCenter.m`, `+[iTermBaseNotification internalSubscribe:withBlock:]` (near line 55).

**What happens:** every subscription stores the object that removes its observer as an associated object of the owner, under one static key shared by every notification class. A second subscription by the same owner, to another notification class or to the same one, replaces the first remover; the first remover is then freed, removes its observer, and the first subscription stops with no error. Every owner in the tree subscribes once today (checked: each subscribing file has one `subscribe` call, and no subscribing class's superclass subscribes too), so nothing is known to be affected. The first class that subscribes to two notifications will lose one.

**Why:**

```objc
[owner it_setAssociatedObject:[[iTermNotificationCenterObserverUnregisterer alloc] initWithToken:token]
                       forKey:(void *)&iTermNotificationTokenAssociatedObject];
```

**How to see it:** subscribe one owner to two notification classes, post the first, and see that its block does not run. Seen by reading the code; not run in the app.

**Suggested fix:** let the existing association hold an array of removers instead of one, appending each new remover, so that no subscription replaces another. That adds no new associated object, but it changes what an existing one stores, so it is the owner's call.

**Found:** 2026-11-27, while moving `iTermSetFindStringNotification` to Swift.

**Checked against the tree:** 2026-11-27. The single key is unchanged, and a search for subscription calls found at most one per file.
