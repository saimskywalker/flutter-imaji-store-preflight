import 'dart:io';

import 'package:storehound/storehound.dart';

Future<void> main(List<String> arguments) async {
  exitCode = runCli(arguments);
  await stdout.flush();
}
