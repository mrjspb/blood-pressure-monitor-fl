import 'package:blood_pressure_app/components/dialoges/add_measurement.dart';
import 'package:blood_pressure_app/components/dialoges/enter_timeformat.dart';
import 'package:blood_pressure_app/main.dart';
import 'package:blood_pressure_app/model/blood_pressure.dart';
import 'package:blood_pressure_app/model/ram_only_implementations.dart';
import 'package:blood_pressure_app/model/storage/export_csv_settings_store.dart';
import 'package:blood_pressure_app/model/storage/export_pdf_settings_store.dart';
import 'package:blood_pressure_app/model/storage/export_settings_store.dart';
import 'package:blood_pressure_app/model/storage/intervall_store.dart';
import 'package:blood_pressure_app/model/storage/settings_store.dart';
import 'package:blood_pressure_app/screens/settings.dart';
import 'package:blood_pressure_app/screens/statistics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  group('start page', () {
    testWidgets('should navigate to add measurements page', (widgetTester) async {
      await pumpAppRoot(widgetTester);
      expect(find.byIcon(Icons.add), findsOneWidget);
      await widgetTester.tap(find.byIcon(Icons.add));
      await widgetTester.pumpAndSettle();

      expect(find.byType(AddMeasurementDialoge), findsOneWidget);
    });
    testWidgets('should navigate to settings page', (widgetTester) async {
      await pumpAppRoot(widgetTester);
      expect(find.byIcon(Icons.settings), findsOneWidget);
      await widgetTester.tap(find.byIcon(Icons.settings));
      await widgetTester.pumpAndSettle();

      expect(find.byType(SettingsPage), findsOneWidget);
    });
    testWidgets('should navigate to stats page', (widgetTester) async {
      await pumpAppRoot(widgetTester);
      expect(find.byIcon(Icons.insights), findsOneWidget);
      await widgetTester.tap(find.byIcon(Icons.insights));
      await widgetTester.pumpAndSettle();

      expect(find.byType(StatisticsPage), findsOneWidget);
    });
  });
  group('settings page', () {
    testWidgets('open EnterTimeFormatScreen', (widgetTester) async {
      await pumpAppRoot(widgetTester);
      expect(find.byIcon(Icons.settings), findsOneWidget);
      await widgetTester.tap(find.byIcon(Icons.settings));
      await widgetTester.pumpAndSettle();

      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.byType(EnterTimeFormatDialoge), findsNothing);
      expect(find.byKey(const Key('EnterTimeFormatScreen')), findsOneWidget);
      await widgetTester.tap(find.byKey(const Key('EnterTimeFormatScreen')));
      await widgetTester.pumpAndSettle();

      expect(find.byType(EnterTimeFormatDialoge), findsOneWidget);
    });
    // ...
  });
}

/// Creates a the same App as the main method.
Future<void> pumpAppRoot(WidgetTester widgetTester, {
  Settings? settings,
  ExportSettings? exportSettings,
  CsvExportSettings? csvExportSettings,
  PdfExportSettings? pdfExportSettings,
  IntervallStoreManager? intervallStoreManager,
  BloodPressureModel? model
}) async {
  model ??= RamBloodPressureModel();
  settings ??= Settings();
  exportSettings ??= ExportSettings();
  csvExportSettings ??= CsvExportSettings();
  pdfExportSettings ??= PdfExportSettings();
  intervallStoreManager ??= IntervallStoreManager(IntervallStorage(), IntervallStorage(), IntervallStorage());

  await widgetTester.pumpWidget(MultiProvider(providers: [
    ChangeNotifierProvider(create: (_) => settings),
    ChangeNotifierProvider(create: (_) => exportSettings),
    ChangeNotifierProvider(create: (_) => csvExportSettings),
    ChangeNotifierProvider(create: (_) => pdfExportSettings),
    ChangeNotifierProvider(create: (_) => intervallStoreManager),
    ChangeNotifierProvider<BloodPressureModel>(create: (_) => model!),
  ], child: const AppRoot()));
}
