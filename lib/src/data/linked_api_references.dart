/// Protected APIs that a plugin's native code references without the plugin
/// ever asking for the permission.
///
/// App Store Connect's ITMS-90683 check ("Missing purpose string in
/// Info.plist") is static: it fires when the uploaded binary references a
/// protected API, whether or not the app calls it. A plugin that bundles a
/// large native SDK (real-time media, maps, secure storage) can bring such a
/// reference in for a reason unrelated to the permission. This table is kept
/// apart from `purposeStringsByPlugin`, because its meaning differs: "the
/// binary references this API" rather than "the plugin asks for this
/// permission".
///
/// A row is only added after the reference has been seen in a built binary,
/// for example with
/// `nm -u Runner.app/Frameworks/<Framework>.framework/<Framework> | grep -E 'CLLocationManager|CMMotionManager|LAContext'`
/// (or the same on `Runner.app/Runner` for static linking), with the plugin
/// version, the command and its output recorded in
/// [LinkedApiReference.evidence]. Projects add their own rows with the
/// `linked_by_plugin` option of `purpose-string-missing`.
library;

/// A protected-API reference a plugin's native code brings into the app.
class LinkedApiReference {
  /// Creates a table row.
  const LinkedApiReference({
    required this.keys,
    required this.versions,
    required this.evidence,
  });

  /// The Info.plist purpose-string keys App Store Connect asks for.
  final List<String> keys;

  /// The plugin versions the evidence covers, e.g. `>=1.0.0 <2.0.0`.
  final String versions;

  /// How the reference was confirmed: plugin version, binary-inspection
  /// command and its output.
  final String evidence;
}

/// Verified linked-only references, by package name.
///
/// Empty until a row has binary evidence; see the library comment.
const linkedApiReferences = <String, LinkedApiReference>{};
