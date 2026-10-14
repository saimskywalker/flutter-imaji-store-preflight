/// Google Play's target API level requirement over time.
///
/// Source: "Target API level requirements for Google Play apps",
/// https://developer.android.com/google/play/requirements/target-sdk and
/// https://support.google.com/googleplay/android-developer/answer/11926878.
///
/// Each row is the date from which **new apps and app updates** must target
/// at least that API level (phone and tablet apps; Wear OS, Android TV and
/// Automotive follow their own, later schedules). Google has granted
/// extensions on request in past years, so a project can override or extend
/// this table with the `deadlines` option of the `android-target-sdk` rule.
library;

/// One row of the table.
class TargetSdkDeadline {
  /// Creates a row.
  const TargetSdkDeadline(this.apiLevel, this.from);

  /// Minimum `targetSdk` once [from] has passed.
  final int apiLevel;

  /// The first day the requirement applies.
  final DateTime from;
}

/// The built-in table, oldest first.
final builtInTargetSdkDeadlines = <TargetSdkDeadline>[
  TargetSdkDeadline(31, DateTime.utc(2022, 11, 1)),
  TargetSdkDeadline(33, DateTime.utc(2023, 8, 31)),
  TargetSdkDeadline(34, DateTime.utc(2024, 8, 31)),
  TargetSdkDeadline(35, DateTime.utc(2025, 8, 31)),
  TargetSdkDeadline(36, DateTime.utc(2026, 8, 31)),
];
