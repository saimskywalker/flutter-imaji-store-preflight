/// Which Apple privacy data types a Flutter plugin implies the app collects.
///
/// Each entry is the *minimum* a manifest should declare when the plugin is
/// linked, taken from the vendor's own App Store privacy disclosure where one
/// is published. It is deliberately conservative: a type is only listed when
/// the SDK collects it by default, without app code opting in. Projects can
/// extend or override any entry with the `sdk_data_types` option of the
/// `privacy-manifest-sdk-data` rule, and contributions are welcome.
library;

/// One plugin's implied data types, with where the claim comes from.
class SdkDataTypes {
  /// Creates an entry.
  const SdkDataTypes(this.types, this.source);

  /// Data types without the `NSPrivacyCollectedDataType` prefix.
  final List<String> types;

  /// The vendor document the entry is based on.
  final String source;
}

const _firebase =
    'https://firebase.google.com/docs/ios/app-store-data-collection';
const _admob =
    'https://developers.google.com/admob/ios/privacy/data-disclosure';
const _storeKit =
    'https://developer.apple.com/app-store/app-privacy-details/#data-type-purchases';

/// Built-in map from pub package name to implied data types.
const builtInSdkDataTypes = <String, SdkDataTypes>{
  'firebase_analytics': SdkDataTypes([
    'ProductInteraction',
    'DeviceID',
  ], _firebase),
  'firebase_crashlytics': SdkDataTypes(['CrashData'], _firebase),
  'firebase_performance': SdkDataTypes(['PerformanceData'], _firebase),
  'firebase_messaging': SdkDataTypes(['DeviceID'], _firebase),
  'firebase_in_app_messaging': SdkDataTypes([
    'ProductInteraction',
    'DeviceID',
  ], _firebase),
  'google_mobile_ads': SdkDataTypes(['AdvertisingData', 'DeviceID'], _admob),
  'in_app_purchase': SdkDataTypes(['PurchaseHistory'], _storeKit),
  'purchases_flutter': SdkDataTypes(['PurchaseHistory'], _storeKit),
  'sentry_flutter': SdkDataTypes(
    ['CrashData'],
    'https://docs.sentry.io/platforms/apple/data-management/apple-privacy-manifest/',
  ),
  'datadog_flutter_plugin': SdkDataTypes(
    ['CrashData', 'PerformanceData'],
    'Vendor documentation: collects crash reports and performance traces by default',
  ),
  'amplitude_flutter': SdkDataTypes([
    'ProductInteraction',
  ], 'Vendor documentation: event analytics'),
  'mixpanel_flutter': SdkDataTypes([
    'ProductInteraction',
  ], 'Vendor documentation: event analytics'),
  'facebook_app_events': SdkDataTypes([
    'ProductInteraction',
    'DeviceID',
  ], 'Vendor documentation: app events are tied to an install identifier'),
  'appsflyer_sdk': SdkDataTypes([
    'DeviceID',
  ], 'Vendor documentation: install attribution keyed to a device identifier'),
  'adjust_sdk': SdkDataTypes([
    'DeviceID',
  ], 'Vendor documentation: install attribution keyed to a device identifier'),
  'onesignal_flutter': SdkDataTypes([
    'DeviceID',
  ], 'Vendor documentation: push subscription keyed to a device identifier'),
};
