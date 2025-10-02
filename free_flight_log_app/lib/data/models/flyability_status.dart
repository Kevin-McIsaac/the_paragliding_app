/// Status of flyability calculation for a site
enum FlyabilityStatus {
  /// Site is flyable with current wind conditions
  flyable,

  /// Site is not flyable with current wind conditions
  notFlyable,

  /// Flyability unknown - no wind data available or site has no wind directions
  unknown,

  /// Wind data is currently being fetched
  loading,
}
