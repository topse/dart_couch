enum OfflineFirstServerState {
  /// We do not have valid credentials yet.
  unititialized,

  /// this state means we are trying to login with given credentials. It can happen after uninitialized or errorWrongCredentials.
  tryingToConnect,

  /// login with given credentials failed
  errorWrongCredentials,

  /// login was successful, but currently offline because of network error
  normalOffline,

  /// login was successful and currently online -- normal operation, everything in sync
  normalOnline,
}
