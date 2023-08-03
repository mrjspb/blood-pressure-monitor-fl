
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blood_pressure_app/model/blood_pressure_analyzer.dart';
import 'package:blood_pressure_app/model/export_options.dart';
import 'package:blood_pressure_app/model/settings_store.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:jsaver/jSaver.dart';
import 'package:path/path.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import 'blood_pressure.dart';

extension PdfCompatability on Color {
  PdfColor toPdfColor() {
    return PdfColor(red / 256, green / 256, blue / 256, opacity);
  }
}

// TODO: update import warning
// TODO: more testing
class ExportFileCreator {
  final Settings settings;
  final AppLocalizations localizations;
  final ThemeData theme;
  final ExportConfigurationModel exportColumnsConfig;

  ExportFileCreator(this.settings, this.localizations, this.theme, this.exportColumnsConfig);

  Future<Uint8List> createFile(List<BloodPressureRecord> records) async {
    switch (settings.exportFormat) {
      case ExportFormat.csv:
        return createCSVCFile(records);
      case ExportFormat.pdf:
        return createPdfFile(records);
      case ExportFormat.db:
        return copyDBFile();
    }
  }

  Future<List<BloodPressureRecord>?> parseFile(String filePath, Uint8List data) async {
    switch(settings.exportFormat) {
      case ExportFormat.csv:
        try {
          return parseCSVFile(data);
        } catch (e) {
          return null;
        }
      case ExportFormat.pdf:
        return null;
      case ExportFormat.db:
        return loadDBFile(filePath);
    }
  }

  Uint8List createCSVCFile(List<BloodPressureRecord> records) {
    List<ExportColumn> exportItems;
    if (settings.exportCustomEntries) {
      exportItems = exportColumnsConfig.getActiveExportColumns();
    } else {
      exportItems = exportColumnsConfig.getDefaultFormates().where((e) => ['timestampUnixMs','systolic','diastolic','pulse','notes'].contains(e.internalName)).toList();
    }

    var csvHead = '';
    if (settings.exportCsvHeadline) {
      for (var i = 0; i<exportItems.length; i++) {
        csvHead += exportItems[i].internalName;
        if (i<(exportItems.length - 1)) {
          csvHead += settings.csvFieldDelimiter;
        }
      }
      csvHead += '\r\n';
    }

    List<List<dynamic>> items = [];
    for (var record in records) {
      List<dynamic> row = [];
      for (var attribute in exportItems) {
        row.add(attribute.formatRecord(record));
      }
      items.add(row);
    }
    var converter = ListToCsvConverter(fieldDelimiter: settings.csvFieldDelimiter, textDelimiter: settings.csvTextDelimiter);
    var csvData = converter.convert(items);
    return Uint8List.fromList(utf8.encode(csvHead + csvData));
  }

  List<BloodPressureRecord> parseCSVFile(Uint8List data) {
    List<BloodPressureRecord> records = [];

    String fileContents = utf8.decode(data.toList());
    var converter = CsvToListConverter(fieldDelimiter: settings.csvFieldDelimiter, textDelimiter: settings.csvTextDelimiter);
    var csvLines = converter.convert(fileContents);
    if (csvLines.length <= 1) { // legacy files
      converter = CsvToListConverter(fieldDelimiter: settings.csvFieldDelimiter, textDelimiter: settings.csvTextDelimiter, eol: '\n');
      csvLines = converter.convert(fileContents);
    }

    final attributes = csvLines.removeAt(0);
    final availableFormatsMap = exportColumnsConfig.availableFormatsMap;

    for (var lineIndex = 0; lineIndex < csvLines.length; lineIndex++) {
      // get values from columns
      int? timestamp, sys, dia, pul;
      String? notes;
      for (var attributeIndex = 0; attributeIndex < attributes.length; attributeIndex++) {
        if (timestamp != null && sys != null && dia !=null && pul != null) continue; // optimization

        // get colum from internal name
        final columnInternalTitle = attributes[attributeIndex].toString().trim();
        final columnFormat = availableFormatsMap[columnInternalTitle];
        if (columnFormat == null) {
          throw ArgumentError('Unknown column: $columnInternalTitle');
        }
        if(!columnFormat.isReversible) continue;

        final parsedRecord = columnFormat.parseRecord(csvLines[lineIndex][attributeIndex].toString());
        for (final parsedRecordDataType in parsedRecord) {
          switch (parsedRecordDataType.$1) {
            case RowDataFieldType.notes:
              assert(parsedRecordDataType.$2 is String?);
              notes ??= parsedRecordDataType.$2;
              break;
            case RowDataFieldType.sys:
              assert(parsedRecordDataType.$2 is double?);
              sys ??= (parsedRecordDataType.$2 as double?)?.toInt();
              break;
            case RowDataFieldType.dia:
              assert(parsedRecordDataType.$2 is double?);
              dia ??= (parsedRecordDataType.$2 as double?)?.toInt();
              break;
            case RowDataFieldType.pul:
              assert(parsedRecordDataType.$2 is double?);
              pul ??= (parsedRecordDataType.$2 as double?)?.toInt();
              break;
            case RowDataFieldType.timestamp:
              assert(parsedRecordDataType.$2 is int?);
              timestamp ??= parsedRecordDataType.$2 as int?;
              break;
          }
        }
      }

      // create record
      if (timestamp == null) {
        throw ArgumentError('File didn\'t save timestamps');
      }
      records.add(BloodPressureRecord(DateTime.fromMillisecondsSinceEpoch(timestamp), sys, dia, pul, notes ?? ''));
    }

    return records;
  }

  Future<Uint8List> createPdfFile(List<BloodPressureRecord> data) async {
    final analyzer = BloodPressureAnalyser(data.toList());
    final dateFormatter = DateFormat(settings.dateFormatString);

    pw.Document pdf = pw.Document();

    pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            _buildDocumentTitle(dateFormatter, analyzer),
            _buildPdfTable(data, dateFormatter),
          ];
        }));
    return await pdf.save();
  }

  pw.Widget _buildDocumentTitle(DateFormat dateFormatter, BloodPressureAnalyser analyzer) {
    return pw.Container(
      child: pw.Text(
        localizations.pdfDocumentTitle(dateFormatter.format(analyzer.firstDay!), dateFormatter.format(analyzer.lastDay!)),
        style: const pw.TextStyle(
          fontSize: 16,
        )
      )
    );
  }

  pw.SpanningWidget _buildPdfTable(List<BloodPressureRecord> data, DateFormat dateFormatter) {
    final tableHeaders = [
      localizations.time,
      localizations.sysLong,
      localizations.diaLong,
      localizations.pulLong,
      localizations.notes
    ];

    return pw.TableHelper.fromTextArray(
        border: null,
        cellAlignment: pw.Alignment.centerLeft,
        headerDecoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black))
        ),
        headerHeight: 20,
        cellHeight: 15,
        cellAlignments: {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.centerLeft,
          2: pw.Alignment.centerLeft,
          3: pw.Alignment.centerLeft,
          4: pw.Alignment.centerRight,
        },
        headerStyle: pw.TextStyle(
          color: PdfColors.black,
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
        ),
        cellStyle: const pw.TextStyle(
          fontSize: 8,
        ),
        headerCellDecoration: pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(
              color: theme.colorScheme.primaryContainer.toPdfColor(),
              width: 5,
            ),
          ),
        ),
        rowDecoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(
              color: PdfColors.blueGrey,
              width: .5,
            ),
          ),
        ),
        headers: tableHeaders,
        data: List<List<String>>.generate(
          data.length,
              (row) => [
                dateFormatter.format(data[row].creationTime),
                (data[row].systolic ?? '-').toString(),
                (data[row].diastolic ?? '-').toString(),
                (data[row].pulse ?? '-').toString(),
                (data[row].notes.isNotEmpty) ? data[row].notes : '-'
              ],
        )
    );
  }

  Future<Uint8List> copyDBFile() async {
    var dbPath = await getDatabasesPath();

    if (dbPath != inMemoryDatabasePath) {
      dbPath = join(dbPath, 'blood_pressure.db');
    }
    return File(dbPath).readAsBytes();
  }

  Future<List<BloodPressureRecord>> loadDBFile(String filePath) async {
    final loadedModel = await BloodPressureModel.create(dbPath: filePath, isFullPath: true);
    return await loadedModel.all;
  }
}

class Exporter {
  final Settings settings;
  final BloodPressureModel model;
  final ScaffoldMessengerState messenger;
  final AppLocalizations localizations;
  final ThemeData theme;
  final ExportConfigurationModel exportColumnsConfig;

  Exporter(this.settings, this.model, this.messenger, this.localizations, this.theme, this.exportColumnsConfig);

  Future<void> export() async {
    final entries = await model.getInTimeRange(settings.displayDataStart, settings.displayDataEnd);
    var fileContents = await ExportFileCreator(settings, localizations, theme, exportColumnsConfig).createFile(entries);
    String filename = 'blood_press_${DateTime.now().toIso8601String()}';
    String ext;
    switch(settings.exportFormat) {
      case ExportFormat.csv:
        ext = 'CSV'; // lower case 'csv' gets automatically converted to 'csv.xls' for some reason
        break;
      case ExportFormat.pdf:
        ext = 'pdf';
        break;
      case ExportFormat.db:
        ext = 'db';
        break;
    }
    String path = await FileSaver.instance.saveFile(name: filename, ext: ext, bytes: fileContents);

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      messenger.showSnackBar(SnackBar(content: Text(localizations.success(path))));
    } else if (Platform.isAndroid || Platform.isIOS) {
      if (settings.defaultExportDir.isNotEmpty) {
        JSaver.instance.save(
            fromPath: path,
            androidPathOptions: AndroidPathOptions(toDefaultDirectory: true)
        );
        messenger.showSnackBar(SnackBar(content: Text(localizations.success(settings.defaultExportDir))));
      } else {
        Share.shareXFiles([
          XFile(
              path,
              mimeType: MimeType.csv.type
          )
        ]);
      }
    } else {
      messenger.showSnackBar(const SnackBar(content: Text('UNSUPPORTED PLATFORM')));
    }
  }


  Future<void> import() async {
    if (!([ExportFormat.csv, ExportFormat.db].contains(settings.exportFormat))) {
      messenger.showSnackBar(SnackBar(content: Text(localizations.errWrongImportFormat)));
      return;
    }

    var result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
    );
    if (result == null) {
      messenger.showSnackBar(SnackBar(content: Text(localizations.errNoFileOpened)));
      return;
    }
    var binaryContent = result.files.single.bytes;
    if (binaryContent == null) {
      messenger.showSnackBar(SnackBar(content: Text(localizations.errCantReadFile)));
      return;
    }
    var path = result.files.single.path;
    assert(path != null); // null state directly linked to binary content

    var fileContents = await ExportFileCreator(settings, localizations, theme, exportColumnsConfig).parseFile(path! ,binaryContent);
    if (fileContents == null) {
      messenger.showSnackBar(SnackBar(content: Text(localizations.errNotImportable)));
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(localizations.importSuccess(fileContents.length))));
    for (final e in fileContents) {
      model.add(e);
    }
  }
}

enum ExportFormat {
  csv,
  pdf,
  db
}