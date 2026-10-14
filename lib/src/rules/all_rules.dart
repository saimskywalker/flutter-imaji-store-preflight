import '../rule.dart';
import 'unreadable_file.dart';

/// Every built-in rule, in the order findings are reported.
const List<Rule> builtInRules = [UnreadableFileRule()];
