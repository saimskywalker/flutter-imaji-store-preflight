import 'package:xml/xml_events.dart';

/// A minimal, read-only XML element tree that remembers the line each element
/// starts on.
///
/// The `xml` package's DOM does not track source positions, and findings are
/// only useful when they point at a line, so the tree is built from the
/// location-annotated event stream instead.
class XmlNode {
  /// Creates an element node.
  XmlNode(this.name, this.attributes, this.line);

  /// The qualified element name, e.g. `key` or `uses-permission`.
  final String name;

  /// Attributes by qualified name, e.g. `android:name`.
  final Map<String, String> attributes;

  /// The 1-based line the element's start tag is on.
  final int line;

  /// The 1-based line of each attribute, for start tags that span lines.
  final Map<String, int> attributeLines = {};

  /// The line of attribute [attributeName], falling back to [line].
  int lineOf(String attributeName) => attributeLines[attributeName] ?? line;

  /// Child elements, in document order. Comments are dropped.
  final List<XmlNode> children = [];

  final StringBuffer _text = StringBuffer();

  /// The concatenated character data directly inside this element.
  String get text => _text.toString();

  /// Child elements named [childName].
  Iterable<XmlNode> elements(String childName) =>
      children.where((c) => c.name == childName);

  /// All descendants (depth first, document order) named [descendantName].
  Iterable<XmlNode> descendants(String descendantName) sync* {
    for (final child in children) {
      if (child.name == descendantName) yield child;
      yield* child.descendants(descendantName);
    }
  }
}

/// Thrown when a document is not well-formed XML.
class XmlTreeException implements Exception {
  /// Creates the exception.
  XmlTreeException(this.message, [this.line]);

  /// What went wrong.
  final String message;

  /// The 1-based line of the problem, when known.
  final int? line;

  @override
  String toString() => line == null ? message : 'line $line: $message';
}

/// Parses [source] into an [XmlNode] tree and returns its root element.
///
/// Throws [XmlTreeException] for input that is not well-formed.
XmlNode parseXmlTree(String source) {
  final lineStarts = _lineStarts(source);
  int lineOf(int? offset) => offset == null ? 1 : _lineFor(lineStarts, offset);

  XmlNode? root;
  final stack = <XmlNode>[];
  try {
    for (final event in parseEvents(
      source,
      withLocation: true,
      validateNesting: true,
      validateDocument: true,
    )) {
      switch (event) {
        case XmlStartElementEvent():
          final node = XmlNode(event.name, {
            for (final a in event.attributes) a.name: a.value,
          }, lineOf(event.start));
          if (event.attributes.isNotEmpty && event.start != null) {
            _locateAttributes(source, event.start!, node, lineOf);
          }
          if (stack.isEmpty) {
            root ??= node;
          } else {
            stack.last.children.add(node);
          }
          if (!event.isSelfClosing) stack.add(node);
        case XmlEndElementEvent():
          stack.removeLast();
        case XmlTextEvent():
          if (stack.isNotEmpty) stack.last._text.write(event.value);
        case XmlCDATAEvent():
          if (stack.isNotEmpty) stack.last._text.write(event.value);
        default:
          break;
      }
    }
  } on FormatException catch (e) {
    final offset = e.offset;
    throw XmlTreeException(e.message, offset == null ? null : lineOf(offset));
  } on Exception catch (e) {
    throw XmlTreeException('$e');
  }
  if (root == null) throw XmlTreeException('the document has no root element');
  return root;
}

/// Records the line of each of [node]'s attributes by scanning its start
/// tag, which begins at [start] (the `<`), up to the first `>` outside a
/// quoted value.
void _locateAttributes(
  String source,
  int start,
  XmlNode node,
  int Function(int offset) lineOf,
) {
  bool separates(String c) => c == '=' || c == '/' || c.trim().isEmpty;
  var i = start + 1;
  // Skip the element name.
  while (i < source.length && !separates(source[i]) && source[i] != '>') {
    i++;
  }
  String? quote;
  var nameStart = -1;
  for (; i < source.length; i++) {
    final c = source[i];
    if (quote != null) {
      if (c == quote) quote = null;
    } else if (c == '"' || c == "'") {
      quote = c;
    } else if (c == '>') {
      return;
    } else if (separates(c)) {
      if (nameStart >= 0) {
        final name = source.substring(nameStart, i);
        if (node.attributes.containsKey(name)) {
          node.attributeLines[name] = lineOf(nameStart);
        }
        nameStart = -1;
      }
    } else if (nameStart < 0) {
      nameStart = i;
    }
  }
}

List<int> _lineStarts(String source) {
  final starts = [0];
  for (var i = 0; i < source.length; i++) {
    if (source.codeUnitAt(i) == 0x0A) starts.add(i + 1);
  }
  return starts;
}

int _lineFor(List<int> starts, int offset) {
  var lo = 0;
  var hi = starts.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (starts[mid] <= offset) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo + 1;
}
