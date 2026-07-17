enum DartCouchConnectionState {
  /// disconnected
  disconnected,

  /// currently trying to login
  loggingIn,

  /// login failed with network error
  loginFailedWithNetworkError,

  /// login failed with wrong credentials
  wrongCredentials,

  /// successfully logged in and connected
  connected,

  /// connected but network error occurred during operation (authToken may still be valid)
  connectedButNetworkError,
}
