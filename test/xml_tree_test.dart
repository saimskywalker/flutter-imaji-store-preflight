import 'package:storehound/src/xml_tree.dart';
import 'package:test/test.dart';

void main() {
  test('attributes of a start tag that spans lines have their own lines', () {
    final root = parseXmlTree('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="a > b"
        android:allowBackup='false'
        android:icon = "@mipmap/ic_launcher"/>
    <activity android:name=".Main" android:exported="true"></activity>
</manifest>
''');
    final application = root.children.first;
    expect(application.line, 2);
    expect(application.lineOf('android:label'), 3);
    expect(application.lineOf('android:allowBackup'), 4);
    expect(application.lineOf('android:icon'), 5);
    expect(application.lineOf('android:theme'), 2);
    final activity = root.children.last;
    expect(activity.lineOf('android:name'), 6);
    expect(activity.lineOf('android:exported'), 6);
  });
}
