## 1.0.24
* requires Flutter 3.50: widgets use `material_ui` instead of `package:flutter/material.dart` (fixes missing localizations / crash in the login dialog on non-English devices)
* `wakelock_plus` constraint relaxed to `^1.8.0` (1.8.1+ needs `dbus` 0.8, which conflicts with `desktop_drop` 0.8.x in apps)

## 1.0.18
* bugfix: `ReplicationStateProxyWidget` showed the app before the initial sync was complete
* `ReplicationStateProxyWidget` shows hints for waiting for network, paused, initializing and error
* `OfflineFirstServerLifecycleObserver`: replication restarts immediately after wakeup (via `resume()`); docs mention `server.retryNow()`
