import 'wind_data.dart';

/// What one on-tap Holfuy read produced.
///
/// A plain `WindData?` cannot say *why* there is no reading, and for Holfuy the
/// difference matters: these stations are frequently solar-powered and go flat
/// for days, so "offline — battery empty" is normal information, while
/// "couldn't reach Holfuy" is a real failure. Collapsing both into null is what
/// made an offline station look like a broken feature.
enum HolfuyReadingStatus {
  /// A usable wind reading.
  ok,

  /// The station answered and says it is not reporting - flat battery, offline,
  /// not activated. Not a failure, and not retryable by tapping again.
  offline,

  /// The request failed, or the page did not match the contract (wrong units,
  /// unexpected markup). Worth retrying later.
  unavailable,
}

class HolfuyReading {
  final HolfuyReadingStatus status;

  /// Present only for [HolfuyReadingStatus.ok].
  final WindData? wind;

  /// The station's own words for why it is offline, when it says so.
  final String? offlineReason;

  /// The page's own "Last update:" text, kept verbatim: it carries a timezone
  /// abbreviation (`AEST`) that `DateTime.parse` does not accept, and the raw
  /// string is more honest than a guessed conversion.
  final String? lastUpdate;

  const HolfuyReading._({
    required this.status,
    this.wind,
    this.offlineReason,
    this.lastUpdate,
  });

  const HolfuyReading.ok(WindData wind)
      : this._(status: HolfuyReadingStatus.ok, wind: wind);

  const HolfuyReading.offline({String? reason, String? lastUpdate})
      : this._(
          status: HolfuyReadingStatus.offline,
          offlineReason: reason,
          lastUpdate: lastUpdate,
        );

  const HolfuyReading.unavailable()
      : this._(status: HolfuyReadingStatus.unavailable);

  bool get hasWind => wind != null;

  @override
  String toString() =>
      'HolfuyReading(${status.name}, wind: $wind, reason: $offlineReason, '
      'lastUpdate: $lastUpdate)';
}
