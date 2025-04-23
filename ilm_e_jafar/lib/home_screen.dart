import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart' as material;
import 'package:flutter/material.dart';
import 'package:xml/xml.dart' as xml;
import 'records.dart';
import 'dart:io';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = false;
  String _selectedFilter = 'All';
  bool _includeNearMatches = false;
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _digitsController = TextEditingController();
  Records _result = Records(digitsInName: 0, records: []);
  String _errorMessage = '';
  bool _showTableView = true;

  final List<String> _matchTypes = [
    'All',
    'Single',
    'Two Names',
    'Three Names',
  ];
  Map<String, int> _matchCounts = {
    'All': 0,
    'Single': 0,
    'Two Names': 0,
    'Three Names': 0,
  };

  @override
  Future<void> _exportToExcel() async {
    try {
      setState(() => _isLoading = true);

      final filteredRecords = _includeNearMatches
          ? _result.records
          .where((r) => r.commulativeDigits != r.inputDigits)
          .toList()
          : _result.records
          .where((r) => _selectedFilter == 'All' || r.category == _selectedFilter)
          .toList();

      // 1. Create Excel workbook and sheet
      final workbook = xlsio.Workbook();
      final sheet = workbook.worksheets[0];
      sheet.name = 'Names Data';

      // 2. Define header names
      final headers = [
        'S.No',
        'Arabic Name',
        'English Name',
        'Numerical Value',
        'Type',
        'Meaning',
        'Category',
        'Combined Value',
        'Match Status',
      ];

      // 3. Apply header styles and add headers
      final headerStyle = workbook.styles.add('headerStyle');
      headerStyle.bold = true;
      headerStyle.hAlign = xlsio.HAlignType.center;
      headerStyle.backColor = '#0078D7';
      headerStyle.fontColor = '#FFFFFF';

      for (int i = 0; i < headers.length; i++) {
        final cell = sheet.getRangeByIndex(1, i + 1);
        cell.setText(headers[i]);
        cell.cellStyle = headerStyle;
      }

      // 4. Add data rows
      for (int i = 0; i < filteredRecords.length; i++) {
        final record = filteredRecords[i];
        final isExactMatch = record.commulativeDigits == record.inputDigits;

        sheet.getRangeByIndex(i + 2, 1).setNumber(i + 1);
        sheet.getRangeByIndex(i + 2, 2).setText(record.arabic ?? 'N/A');
        sheet.getRangeByIndex(i + 2, 3).setText(record.english ?? 'N/A');
        sheet.getRangeByIndex(i + 2, 4).setNumber((int.tryParse(record.value ?? '0') ?? 0).toDouble());
        sheet.getRangeByIndex(i + 2, 5).setText(record.type ?? 'N/A');
        sheet.getRangeByIndex(i + 2, 6).setText(record.meaning ?? 'N/A');
        sheet.getRangeByIndex(i + 2, 7).setText(record.category ?? 'N/A');
        sheet.getRangeByIndex(i + 2, 8).setText(
          (record.category == 'All Names' || record.category == 'Single')
              ? '-'
              : (record.commulativeDigits ?? 'N/A'),
        );
        final matchCell = sheet.getRangeByIndex(i + 2, 9);
        matchCell.setText(isExactMatch ? 'Exact Match' : 'Near Match (±1)');
        matchCell.cellStyle = workbook.styles.add('matchStyle$i')
          ..bold = true
          ..fontColor = isExactMatch ? '#00AA00' : '#FF0000';
      }

      // 5. Auto-fit columns
      for (var i = 1; i <= 9; i++) {
        sheet.autoFitColumn(i);
      }
      // 6. Save the workbook
      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();
      final directory = await getDownloadsDirectory();
      final filePath = '${directory?.path}/NameMatches_${_result.digitsInName}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);

      await OpenFile.open(file.path);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Excel exported successfully!'),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => OpenFile.open(file.path),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void initState() {
    super.initState();
    _loadAllNames();
  }

  Future<void> _loadAllNames() async {
    setState(() => _isLoading = true);
    try {
      final data = await deserializeNames();
      setState(() {
        _result = Records(
          digitsInName: 0,
          records:
          data.records
              .map(
                (record) => Record(
              sNo: record.sNo,
              english: record.english,
              arabic: record.arabic,
              value: record.value,
              type: record.type,
              meaning: record.meaning,
              category: 'All Names',
            ),
          )
              .toList(),
          resultCount: data.records.length,
        );
        _updateMatchCounts();
      });
    } catch (e) {
      setState(() => _errorMessage = 'Error loading names: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<Records> deserializeNames() async {
    try {
      final xmlString = await rootBundle.loadString('assets/Names.xml');
      final document = xml.XmlDocument.parse(xmlString);

      final records =
      document.findAllElements('record').map((element) {
        String getText(String tagName) =>
            element.findElements(tagName).firstOrNull?.innerText ?? '';

        return Record(
          sNo: getText('SNo'),
          english: getText('English'),
          arabic: getText('Arabic'),
          value: getText('Value'),
          type: getText('Type'),
          meaning: getText('Meaning'),
        );
      }).toList();

      return Records(
        records: records.where((r) => r.value.isNotEmpty).toList(),
      );
    } catch (e) {
      debugPrint('XML error: $e');
      throw Exception('Failed to parse names data');
    }
  }
  Future<void> _evaluateName() async {
    if (_digitsController.text.isEmpty) {
      await _loadAllNames();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final userName = int.tryParse(_digitsController.text.trim()) ?? 0;
      if (userName == 0) {
        setState(() => _errorMessage = 'Please enter a valid number');
        return;
      }

      final data = await deserializeNames();
      var counter = 1;
      final result = Records(digitsInName: userName, records: []);

      // Single names (only exact matches)
      for (var item in data.records) {
        try {
          if (userName == int.parse(item.value)) {
            result.records.add(
              _createResultRecord(
                item,
                counter++,
                'Single',
                item.value,
                userName.toString(),
                true,
              ),
            );
          }
        } catch (e) {
          debugPrint('Error parsing value for ${item.english}: $e');
        }
      }

      // Two-name combinations
      final twoNameGroups = <String, List<Record>>{};
      for (var i = 0; i < data.records.length; i++) {
        for (var j = i + 1; j < data.records.length; j++) {
          try {
            final item1 = data.records[i];
            final item2 = data.records[j];
            final sum = int.parse(item1.value) + int.parse(item2.value);
            final isMatch =
                (sum == userName) ||
                    (_includeNearMatches &&
                        (sum == userName - 1 || sum == userName + 1));

            if (isMatch) {
              final groupKey = '${item1.sNo}-${item2.sNo}';
              twoNameGroups.putIfAbsent(groupKey, () => []).addAll([
                item1,
                item2,
              ]);
            }
          } catch (e) {
            debugPrint('Error processing pair: $e');
          }
        }
      }

      // Create merged records for two-name combinations
      twoNameGroups.forEach((key, records) {
        if (records.length == 2) {
          final sum = int.parse(records[0].value) + int.parse(records[1].value);
          result.records.add(
            _createMergedRecord(
              records,
              counter,
              'Two Names',
              sum.toString(),
              userName.toString(),
            ),
          );
          counter++;
        }
      });

      // Three-name combinations
      final threeNameGroups = <String, List<Record>>{};
      for (var i = 0; i < data.records.length; i++) {
        for (var j = i + 1; j < data.records.length; j++) {
          for (var k = j + 1; k < data.records.length; k++) {
            try {
              final item1 = data.records[i];
              final item2 = data.records[j];
              final item3 = data.records[k];
              final sum =
                  int.parse(item1.value) +
                      int.parse(item2.value) +
                      int.parse(item3.value);
              final isMatch =
                  (sum == userName) ||
                      (_includeNearMatches &&
                          (sum == userName - 1 || sum == userName + 1));

              if (isMatch) {
                final groupKey = '${item1.sNo}-${item2.sNo}-${item3.sNo}';
                threeNameGroups.putIfAbsent(groupKey, () => []).addAll([
                  item1,
                  item2,
                  item3,
                ]);
              }
            } catch (e) {
              debugPrint('Error processing triple: $e');
            }
          }
        }
      }

      // Create merged records for three-name combinations
      threeNameGroups.forEach((key, records) {
        if (records.length == 3) {
          final sum =
              int.parse(records[0].value) +
                  int.parse(records[1].value) +
                  int.parse(records[2].value);
          result.records.add(
            _createMergedRecord(
              records,
              counter,
              'Three Names',
              sum.toString(),
              userName.toString(),
            ),
          );
          counter++;
        }
      });

      result.resultCount = counter - 1;

      // Sort records: exact matches first, then by category (Single, Two Names, Three Names)
      result.records.sort((a, b) {
        // First sort by exact match (exact matches come first)
        final aIsExact = a.commulativeDigits == a.inputDigits;
        final bIsExact = b.commulativeDigits == b.inputDigits;
        if (aIsExact != bIsExact) {
          return aIsExact ? -1 : 1;
        }

        // For near matches, sort by difference (-1 first, then +1)
        if (!aIsExact && !bIsExact) {
          final aDiff = (int.tryParse(a.commulativeDigits ?? '0') ?? 0) -
              (int.tryParse(a.inputDigits ?? '0') ?? 0);
          final bDiff = (int.tryParse(b.commulativeDigits ?? '0') ?? 0) -
              (int.tryParse(b.inputDigits ?? '0') ?? 0);

          if (aDiff != bDiff) {
            return aDiff.compareTo(bDiff); // This will put -1 before +1
          }
        }

        // Then sort by category order
        final categoryOrder = {'Single': 1, 'Two Names': 2, 'Three Names': 3};
        final aOrder = categoryOrder[a.category] ?? 0;
        final bOrder = categoryOrder[b.category] ?? 0;
        return aOrder.compareTo(bOrder);
      });

      setState(() {
        _result = result;
        _updateMatchCounts();

        // Set default filter based on results
        if (result.records.any(
              (r) => r.category == 'Single' && r.commulativeDigits == r.inputDigits,
        )) {
          _selectedFilter = 'Single';
        } else if (result.records.any(
              (r) =>
          r.category == 'Two Names' && r.commulativeDigits == r.inputDigits,
        )) {
          _selectedFilter = 'Two Names';
        } else if (result.records.any(
              (r) =>
          r.category == 'Three Names' &&
              r.commulativeDigits == r.inputDigits,
        )) {
          _selectedFilter = 'Three Names';
        } else {
          _selectedFilter = 'All';
        }
      });
    } catch (e) {
      setState(() => _errorMessage = 'Error: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _updateMatchCounts() {
    setState(() {
      _matchCounts = {
        'All': _result.records.length,
        'Single': _result.records.where((r) => r.category == 'Single').length,
        'Two Names':
        _result.records.where((r) => r.category == 'Two Names').length,
        'Three Names':
        _result.records.where((r) => r.category == 'Three Names').length,
      };
    });
  }

  Record _createResultRecord(
      Record item,
      int counter,
      String category,
      String cumulative,
      String inputDigits, [
        bool lineBreak = false,
      ]) {
    return Record(
      sNo: counter.toString(),
      english: item.english,
      arabic: item.arabic,
      value: item.value,
      type: item.type,
      meaning: item.meaning,
      category: category,
      inputDigits: inputDigits,
      commulativeDigits: cumulative,
      lineBreak: lineBreak,
      order:
      (int.tryParse(cumulative) ?? 0) == (int.tryParse(inputDigits) ?? 0)
          ? 1
          : 0,
    );
  }

  Record _createMergedRecord(
      List<Record> items,
      int counter,
      String category,
      String cumulative,
      String inputDigits,
      ) {
    final reversedEnglishItems = items.reversed.toList();
    final inputNum = int.tryParse(inputDigits) ?? 0;
    final cumulativeNum = int.tryParse(cumulative) ?? 0;
    final difference = cumulativeNum - inputNum;

    return Record(
      sNo: counter.toString(),
      english: reversedEnglishItems.map((e) => e.english).join(' + '),
      arabic: items.map((e) => e.arabic).join(' + '),
      value: reversedEnglishItems.map((e) => e.value).join(' + '),
      type: reversedEnglishItems.map((e) => e.type).join(', '),
      meaning: reversedEnglishItems.map((e) => e.meaning).join('\n'),
      category: category,
      inputDigits: inputDigits,
      commulativeDigits: cumulative,
      lineBreak: true,
      order: difference == 0 ? 1 : (difference < 0 ? 0 : 2),
      componentNames: reversedEnglishItems,
      difference: difference, // Now this is properly defined
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false, // Remove default back button
        titleSpacing: 0, // Remove default title spacing
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Icons on the left
            Row(
              children: [
                // View toggle button
                IconButton(
                  icon: Icon(
                    _showTableView ? Icons.list : Icons.table_chart,
                    color: Colors.blue,
                    size: 24, // Slightly larger icon
                  ),
                  onPressed: () => setState(() => _showTableView = !_showTableView),
                  tooltip: _showTableView ? 'Switch to List View' : 'Switch to Table View',
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                // Export to Excel button
                _isLoading
                    ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                    ),
                  ),
                )
                    : IconButton(
                  icon: const Icon(Icons.download, color: Colors.blue, size: 24),
                  onPressed: _exportToExcel,
                  tooltip: 'Export to Excel',
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ],
            ),
            // Title text on the right
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Text(
                'اسماء الحسنیٰ',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 20,
                  fontWeight: FontWeight.bold, // Make text bolder
                ),
              ),
            ),
          ],
        ),
        elevation: 1,
        backgroundColor: Colors.white,
        centerTitle: false, // Important for alignment
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            material.Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: material.Column(
                children: [
                  // Search Input Field
                  TextFormField(
                    controller: _digitsController,
                    textDirection: TextDirection.rtl, // Right-to-left for Urdu text
                    textAlign: TextAlign.right, // Align text to right
                    decoration: InputDecoration(
                      labelText: 'نام کے اعداد درج کریں',
                      alignLabelWithHint: true,
                      labelStyle: TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      prefixIcon: Container( // Changed from suffixIcon to prefixIcon
                        margin: EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: IconButton(
                          icon: Icon(Icons.search, size: 24),
                          color: Colors.blue,
                          onPressed: _evaluateName,
                        ),
                      ),
                      errorText: _errorMessage.isEmpty ? null : _errorMessage,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onFieldSubmitted: (_) => _evaluateName(),
                  ),
                  // Toggle Section
                  material.Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: material.Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Toggle Label
                        Text(
                          'Show ±1 matches:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),

                        // Toggle Switch with custom styling
                        Container(
                          height: 30,
                          decoration: BoxDecoration(
                            color: _includeNearMatches
                                ? Colors.blue.withOpacity(0.1)
                                : Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: material.Row(
                            children: [
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  _includeNearMatches ? 'ON' : 'OFF',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _includeNearMatches
                                        ? Colors.blue
                                        : Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Switch(
                                value: _includeNearMatches,
                                onChanged: (value) {
                                  setState(() {
                                    _includeNearMatches = value;
                                    if (value) _selectedFilter = 'All';
                                  });
                                  if (_digitsController.text.isNotEmpty) {
                                    _evaluateName();
                                  }
                                },
                                activeColor: Colors.blue,
                                activeTrackColor: Colors.blue.withOpacity(0.4),
                                inactiveThumbColor: Colors.grey,
                                inactiveTrackColor: Colors.grey.withOpacity(0.4),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 50,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children:
                _matchTypes.map((type) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: FilterChip(
                      label: Text('$type (${_matchCounts[type] ?? 0})'),
                      selected: _selectedFilter == type,
                      onSelected: (selected) {
                        setState(() {
                          _selectedFilter = selected ? type : 'All';
                        });
                      },
                      selectedColor: _getCategoryColor(type),
                      checkmarkColor: Colors.white,
                      labelStyle: TextStyle(
                        color:
                        _selectedFilter == type ? Colors.white : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child:
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _result.records.isNotEmpty
                  ? _showTableView
                  ? _buildTableView()
                  : _buildListView()
                  : const Center(child: Text('No records found.')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListView() {
    // Filter records based on selected filter
    var filteredRecords = _includeNearMatches
        ? _result.records.where((record) {
      return record.commulativeDigits != record.inputDigits; // Only ±1 matches
    }).toList()
        : _result.records.where((record) {
      if (_selectedFilter == 'All') return true;
      return record.category == _selectedFilter;
    }).toList();

    // Regenerate serial numbers for filtered records
    filteredRecords = filteredRecords.asMap().entries.map((entry) {
      final index = entry.key;
      final record = entry.value;
      return record.copyWith(sNo: (index + 1).toString());
    }).toList();

    return ListView.builder(
      itemCount: filteredRecords.length,
      itemBuilder: (context, index) {
        final record = filteredRecords[index];
        final isExactMatch = record.commulativeDigits == record.inputDigits;
        final isSingleCategory = record.category == 'Single';

        return Card(
          margin: const EdgeInsets.only(bottom: 8.0),
          color: isExactMatch ? Colors.blue[50] : null,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('${record.sNo}. ', style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    )),
                    Expanded(
                      child: Text(record.arabic,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          )),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 4.0,
                      ),
                      decoration: BoxDecoration(
                        color: _getCategoryColor(record.category),
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: Text(
                        record.category ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // If Single, show Meaning and Type only
                if (isSingleCategory) ...[
                  _buildInfoRow('Meaning', record.meaning),
                  _buildInfoRow('Type', record.type),
                ] else ...[
                  _buildInfoRow('Type', record.type),
                  if (record.componentNames != null && record.componentNames!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Components: ${record.commulativeDigits}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    ...record.componentNames!.map((component) => Padding(
                      padding: const EdgeInsets.only(left: 16.0, top: 4.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('• ${component.arabic} (${component.value})'),
                          Text('  ${component.meaning}', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    )),
                  ],
                ],
                if (record.lineBreak) const Divider(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableView() {
    // Filter records based on selected filter
    var filteredRecords = _includeNearMatches
        ? _result.records.where((record) {
      return record.commulativeDigits != record.inputDigits; // Only ±1 matches
    }).toList()
        : _result.records.where((record) {
      if (_selectedFilter == 'All') return true;
      return record.category == _selectedFilter;
    }).toList();

    // Regenerate serial numbers for filtered records
    filteredRecords = filteredRecords.asMap().entries.map((entry) {
      final index = entry.key;
      final record = entry.value;
      return record.copyWith(sNo: (index + 1).toString());
    }).toList();

    return Expanded( // Important to avoid tight constraints
        child: SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 20,
          headingRowHeight: 56,
          dataRowMinHeight: 60, // Minimum row height
          dataRowMaxHeight: double.infinity, // Allow it to expand as needed
          headingRowColor: MaterialStateProperty.resolveWith(
                (states) => Theme.of(context).primaryColor.withOpacity(0.1),
          ),
          columns: const [
            DataColumn(label: Text('SNo', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Arabic Name', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Value', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Type', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Meaning', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Combined Value', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: filteredRecords.map((record) {
            final isExactMatch = record.commulativeDigits == record.inputDigits;
            return DataRow(
              color: MaterialStateProperty.resolveWith<Color?>(
                    (states) => isExactMatch ? Colors.blue[50] : null,
              ),
              cells: [
                DataCell(Center(child: Text(record.sNo))),
                DataCell(Text(record.arabic)),
                DataCell(Center(child: Text(record.value))),
                DataCell(Center(child: Text(record.type))),
                // ✅ Expandable Meaning Cell
                DataCell(
                  Container(
                    width: 250, // Adjust width if needed
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      record.meaning,
                      style: const TextStyle(fontSize: 14),
                      softWrap: true,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getCategoryColor(record.category),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      record.category ?? '',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                DataCell(
                  Center(
                    child: Text(
                      record.category == 'All Names' || record.category == 'Single'
                          ? '-'
                          : '${record.commulativeDigits} ${_getDifferenceIndicator(record)}',
                      style: TextStyle(
                        color: record.commulativeDigits == record.inputDigits
                            ? Colors.green
                            : (record.difference != null && record.difference! < 0
                            ? Colors.orange
                            : Colors.blue),
                        fontWeight: record.commulativeDigits == record.inputDigits
                            ? FontWeight.bold
                            : null,
                      ),
                    ),
                  ),
                ),              ],
            );
          }).toList(),
        )
      ),
    )
    );
  }
  String _getDifferenceIndicator(Record record) {
    if (record.difference == null) return '';
    if (record.difference == 0) return '(Exact)';
    if (record.difference! < 0) return '(-1)';
    return '(+1)';
  }
  Color _getCategoryColor(String? category) {
    switch (category) {
      case 'Single':
        return Colors.lightBlueAccent.shade400;
      case 'Two Names':
        return Colors.lightBlueAccent.shade200;
      case 'Three Names':
        return Colors.lightBlueAccent.shade100;
      case 'All Names':
        return Colors.lightBlueAccent.shade700;
      default:
        return Colors.grey.shade400;
    }
  }
}

Widget _buildInfoRow(String label, String value, {bool isHighlighted = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isHighlighted ? Colors.green : null,
                fontWeight: isHighlighted ? FontWeight.bold : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

