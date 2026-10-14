import '../rule.dart';
import 'privacy_manifest.dart';
import 'purpose_strings.dart';
import 'unreadable_file.dart';

/// Every built-in rule, in the order findings are reported.
const List<Rule> builtInRules = [
  UnreadableFileRule(),
  PrivacyManifestPresentRule(),
  PrivacyManifestValuesRule(),
  PrivacyManifestTrackingRule(),
  PrivacyManifestSdkDataRule(),
  TrackingUsageDescriptionRule(),
  PurposeStringMissingRule(),
  PurposeStringQualityRule(),
];
