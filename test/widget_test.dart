import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:iqaa/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('iqaa_test_');
  });

  setUp(() async {
    Hive.init(hiveDirectory.path);
    await Hive.openBox<String>('iqaa_tasks');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await Hive.close();
  });

  testWidgets('shows Arabic dashboard and opens reports', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(IqaaApp(prefs: prefs));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('إيقاع'), findsWidgets);
    expect(find.text('كيف طاقتك الآن؟'), findsOneWidget);

    await tester.tap(find.text('التقارير'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('ملخص اليوم'), findsOneWidget);
  });
}
