## 1.0.18
* bugfix: `ReplicationStateProxyWidget` showed the app before the initial sync was complete
* `ReplicationStateProxyWidget` shows hints for waiting for network, paused, initializing and error
* `OfflineFirstServerLifecycleObserver`: replication restarts immediately after wakeup (via `resume()`); docs mention `server.retryNow()`
