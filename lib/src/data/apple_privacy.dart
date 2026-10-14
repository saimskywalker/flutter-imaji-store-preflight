/// Apple's privacy manifest vocabulary.
///
/// Transcribed from the public documentation:
///
/// * Data types and purposes —
///   https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests
/// * Required reason APIs —
///   https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
///
/// Apple extends these lists from time to time. Rules accept extra values
/// through configuration so that a new value never forces a release of this
/// package; open an issue so the table catches up.
library;

/// Prefix of every collected data type value.
const collectedDataTypePrefix = 'NSPrivacyCollectedDataType';

/// Prefix of every collection purpose value.
const purposePrefix = 'NSPrivacyCollectedDataTypePurpose';

/// Prefix of every required-reason API category value.
const apiCategoryPrefix = 'NSPrivacyAccessedAPICategory';

/// Collected data types, without [collectedDataTypePrefix].
const collectedDataTypes = <String>{
  // Contact info
  'Name',
  'EmailAddress',
  'PhoneNumber',
  'PhysicalAddress',
  'OtherUserContactInfo',
  // Health and fitness
  'Health',
  'Fitness',
  // Financial info
  'PaymentInfo',
  'CreditInfo',
  'OtherFinancialInfo',
  // Location
  'PreciseLocation',
  'CoarseLocation',
  // Sensitive info
  'SensitiveInfo',
  // Contacts
  'Contacts',
  // User content
  'EmailsOrTextMessages',
  'PhotosorVideos',
  'AudioData',
  'GameplayContent',
  'CustomerSupport',
  'OtherUserContent',
  // Browsing and search history
  'BrowsingHistory',
  'SearchHistory',
  // Identifiers
  'UserID',
  'DeviceID',
  // Purchases
  'PurchaseHistory',
  // Usage data
  'ProductInteraction',
  'AdvertisingData',
  'OtherUsageData',
  // Diagnostics
  'CrashData',
  'PerformanceData',
  'OtherDiagnosticData',
  // Surroundings and body (visionOS)
  'EnvironmentScanning',
  'Hands',
  'Head',
  // Other
  'OtherDataTypes',
};

/// Collection purposes, without [purposePrefix].
const collectionPurposes = <String>{
  'ThirdPartyAdvertising',
  'DeveloperAdvertising',
  'Analytics',
  'ProductPersonalization',
  'AppFunctionality',
  'Other',
};

/// Required-reason API categories (without [apiCategoryPrefix]) and the
/// approved reason codes for each.
const requiredReasonApis = <String, Set<String>>{
  'FileTimestamp': {'DDA9.1', 'C617.1', '3B52.1', '0A2A.1'},
  'SystemBootTime': {'35F9.1', '8FFB.1', '3D61.1'},
  'DiskSpace': {'85F4.1', 'E174.1', '7D9E.1', 'B728.1'},
  'ActiveKeyboards': {'3EC4.1', '54BD.1'},
  'UserDefaults': {'CA92.1', '1C8F.1', 'C56D.1', 'AC6B.1'},
};

/// Values of `UIBackgroundModes` Apple documents.
///
/// https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes
const backgroundModes = <String>{
  'audio',
  'bluetooth-central',
  'bluetooth-peripheral',
  'external-accessory',
  'fetch',
  'location',
  'nearby-interaction',
  'network-authentication',
  'newsstand-content',
  'processing',
  'push-to-talk',
  'remote-notification',
  'voip',
};

/// Documentation links shared by the privacy manifest rules.
const privacyManifestDocs = [
  'https://developer.apple.com/documentation/bundleresources/privacy-manifest-files',
  'https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests',
  'https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api',
];
