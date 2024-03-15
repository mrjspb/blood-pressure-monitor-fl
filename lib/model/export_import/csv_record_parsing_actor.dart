
import 'dart:collection';

import 'package:blood_pressure_app/model/export_import/column.dart';
import 'package:blood_pressure_app/model/export_import/csv_converter.dart';
import 'package:blood_pressure_app/model/export_import/record_parsing_result.dart';

/// A intermediate class usable by UI components to drive csv parsing.
class CsvRecordParsingActor {
  /// Create an intermediate object to manage a record parsing process.
  CsvRecordParsingActor(this._converter, String csvString) {
    final lines = _converter.getCsvLines(csvString);
    _firstLine = lines.removeAt(0);
    _bodyLines = lines;
    _columnNames = _firstLine ?? [];
    _columnParsers = _converter.getColumns(_columnNames);
  }

  final CsvConverter _converter;

  /// All lines without the first line.
  late final List<List<String>> _bodyLines;
  
  /// All lines containing data.
  UnmodifiableListView<List<String>> get dataLines {
    final lines = _bodyLines.toList();
    if(!hasHeadline && _firstLine != null) lines.insert(0, _firstLine!);
    return UnmodifiableListView(lines);
  }

  /// The first line in the csv file.
  List<String>? _firstLine;

  late List<String> _columnNames;

  /// All columns defined in the csv headline.
  List<String> get columnNames => _columnNames;

  late Map<String, ExportColumn> _columnParsers;

  /// The current interpretation of columns in the csv data.
  ///
  /// There is no guarantee that every column in [columnNames] has a parser.
  Map<String, ExportColumn> get columnParsers => _columnParsers;

  /// Whether the CSV file has a title row (first line) that contains no data.
  bool hasHeadline = true;
  
  /// Override a columns with a custom one.
  void changeColumnParser(String columnName, ExportColumn? parser) {
    assert(_columnNames.contains(columnName));
    if (parser == null) {
      _columnParsers.remove(columnName);
      return;
    }
    _columnParsers[columnName] = parser;
  }

  /// Try to parse the data with the current configuration.
  RecordParsingResult attemptParse() {
    return _converter.parseRecords(dataLines, columnNames, columnParsers, false);
  }
}
