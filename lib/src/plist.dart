import 'dart:convert';
import 'dart:typed_data';

import 'xml_tree.dart';

/// Thrown when a property list cannot be read.
class PlistFormatException implements Exception {
  /// Creates the exception.
  PlistFormatException(this.message, [this.line]);

  /// A human-readable explanation, including how to fix it when possible.
  final String message;

  /// The 1-based line of the problem, when known.
  final int? line;

  @override
  String toString() => line == null ? message : 'line $line: $message';
}

/// A value in a property list, with the line it was declared on.
sealed class PlistValue {
  PlistValue(this.line);

  /// The 1-based line of the element that holds this value.
  final int line;
}

/// A `<dict>`.
final class PlistDict extends PlistValue {
  /// Creates a dictionary value.
  PlistDict(super.line, this.entries, this.keyLines);

  /// The dictionary's entries, in document order.
  final Map<String, PlistValue> entries;

  /// The line of each entry's `<key>` element.
  final Map<String, int> keyLines;

  /// The value for [key], or `null` when absent.
  PlistValue? operator [](String key) => entries[key];

  /// Whether [key] is present.
  bool has(String key) => entries.containsKey(key);

  /// The string value of [key], or `null` when absent or not a string.
  String? string(String key) => switch (entries[key]) {
    PlistString(:final value) => value,
    _ => null,
  };

  /// The boolean value of [key], or `null` when absent or not a boolean.
  bool? boolean(String key) => switch (entries[key]) {
    PlistBool(:final value) => value,
    _ => null,
  };

  /// The array value of [key], or `null` when absent or not an array.
  PlistArray? array(String key) => switch (entries[key]) {
    final PlistArray a => a,
    _ => null,
  };

  /// The dictionary value of [key], or `null` when absent or not a dict.
  PlistDict? dict(String key) => switch (entries[key]) {
    final PlistDict d => d,
    _ => null,
  };

  /// The line of [key]'s `<key>` element, falling back to the dict's line.
  int lineOf(String key) => keyLines[key] ?? line;
}

/// An `<array>`.
final class PlistArray extends PlistValue {
  /// Creates an array value.
  PlistArray(super.line, this.items);

  /// The array's items, in document order.
  final List<PlistValue> items;

  /// The items that are strings, trimmed.
  Iterable<PlistString> get strings => items.whereType<PlistString>();
}

/// A `<string>`.
final class PlistString extends PlistValue {
  /// Creates a string value.
  PlistString(super.line, this.value);

  /// The string, exactly as written (entities decoded).
  final String value;
}

/// A `<true/>` or `<false/>`.
final class PlistBool extends PlistValue {
  /// Creates a boolean value.
  PlistBool(super.line, this.value);

  /// The boolean.
  final bool value;
}

/// An `<integer>` or `<real>`.
final class PlistNumber extends PlistValue {
  /// Creates a numeric value.
  PlistNumber(super.line, this.value);

  /// The number.
  final num value;
}

/// A `<date>` or `<data>`, kept as raw text: no rule needs to interpret it.
final class PlistOpaque extends PlistValue {
  /// Creates an opaque value.
  PlistOpaque(super.line, this.kind, this.raw);

  /// `date` or `data`.
  final String kind;

  /// The element's text.
  final String raw;
}

/// The magic number at the start of every binary property list.
const _binaryMagic = 'bplist';

/// Parses an XML property list from raw [bytes].
///
/// Binary property lists are recognised and refused with a message that says
/// how to convert them, rather than being reported as malformed XML.
PlistValue parsePlistBytes(Uint8List bytes) {
  if (bytes.length >= _binaryMagic.length &&
      ascii.decode(bytes.sublist(0, _binaryMagic.length), allowInvalid: true) ==
          _binaryMagic) {
    throw PlistFormatException(
      'is a binary property list, which this tool does not read. Convert it '
      'to XML with `plutil -convert xml1 <file>` (Xcode reads both formats, '
      'and XML keeps it reviewable in diffs).',
    );
  }
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    throw PlistFormatException('is not valid UTF-8 text');
  }
  return parsePlistString(text);
}

/// Parses an XML property list from [source].
PlistValue parsePlistString(String source) {
  final trimmed = source.trimLeft();
  if (trimmed.startsWith(_binaryMagic)) {
    throw PlistFormatException(
      'is a binary property list; convert it with `plutil -convert xml1`.',
    );
  }
  if (trimmed.startsWith('{') || trimmed.startsWith('(')) {
    throw PlistFormatException(
      'looks like an OpenStep/JSON property list; convert it with '
      '`plutil -convert xml1 <file>`.',
    );
  }
  final XmlNode root;
  try {
    root = parseXmlTree(source);
  } on XmlTreeException catch (e) {
    throw PlistFormatException('is not well-formed XML: ${e.message}', e.line);
  }
  if (root.name != 'plist') {
    throw PlistFormatException(
      'has root element <${root.name}>, expected <plist>',
      root.line,
    );
  }
  if (root.children.length != 1) {
    throw PlistFormatException(
      '<plist> must contain exactly one value, found ${root.children.length}',
      root.line,
    );
  }
  return _value(root.children.single);
}

PlistValue _value(XmlNode node) {
  switch (node.name) {
    case 'dict':
      final entries = <String, PlistValue>{};
      final keyLines = <String, int>{};
      final kids = node.children;
      for (var i = 0; i < kids.length; i++) {
        final key = kids[i];
        if (key.name != 'key') {
          throw PlistFormatException(
            'expected <key> inside <dict>, found <${key.name}>',
            key.line,
          );
        }
        if (i + 1 >= kids.length) {
          throw PlistFormatException(
            '<key>${key.text}</key> has no value',
            key.line,
          );
        }
        final name = key.text;
        entries[name] = _value(kids[++i]);
        keyLines[name] = key.line;
      }
      return PlistDict(node.line, entries, keyLines);
    case 'array':
      return PlistArray(node.line, node.children.map(_value).toList());
    case 'string':
      return PlistString(node.line, node.text);
    case 'true':
      return PlistBool(node.line, true);
    case 'false':
      return PlistBool(node.line, false);
    case 'integer':
    case 'real':
      final n = num.tryParse(node.text.trim());
      if (n == null) {
        throw PlistFormatException(
          '<${node.name}> holds "${node.text}", which is not a number',
          node.line,
        );
      }
      return PlistNumber(node.line, n);
    case 'date':
    case 'data':
      return PlistOpaque(node.line, node.name, node.text);
    default:
      throw PlistFormatException(
        'unknown property list element <${node.name}>',
        node.line,
      );
  }
}
