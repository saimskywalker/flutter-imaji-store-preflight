import '../rule.dart';
import 'android.dart';
import 'ios_config.dart';
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
  BackgroundModesRule(),
  ExportOptionsBuildNumberRule(),
  BundleLocalizationsRule(),
  PushEntitlementRule(),
  AndroidPickerQueriesRule(),
  AndroidTargetSdkRule(),
  Android16KbPageSizeRule(),
];
