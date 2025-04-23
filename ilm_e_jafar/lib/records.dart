class Record {
  final String sNo;
  final String english;
  final String arabic;
  final String value;
  final String type;
  final String meaning;
  final String? category;
  final String? inputDigits;
  final String? commulativeDigits;
  final bool lineBreak;
  final int? order;
  List<Record>? componentNames;
  int? difference; // Add this field


  Record({
    required this.sNo,
    required this.english,
    required this.arabic,
    required this.value,
    required this.type,
    required this.meaning,
    this.category,
    this.inputDigits,
    this.commulativeDigits,
    this.lineBreak = false,
    this.order,
    this.componentNames,
    this.difference, // Add this to constructor

  });
  Record copyWith({
    String? sNo,
    String? english,
    String? arabic,
    String? value,
    String? type,
    String? meaning,
    String? category,
    String? inputDigits,
    String? commulativeDigits,
    bool? lineBreak,
    int? order,
    List<Record>? componentNames,
    int? difference,

  }) {
    return Record(
      sNo: sNo ?? this.sNo,
      english: english ?? this.english,
      arabic: arabic ?? this.arabic,
      value: value ?? this.value,
      type: type ?? this.type,
      meaning: meaning ?? this.meaning,
      category: category ?? this.category,
      inputDigits: inputDigits ?? this.inputDigits,
      commulativeDigits: commulativeDigits ?? this.commulativeDigits,
      lineBreak: lineBreak ?? this.lineBreak,
      order: order ?? this.order,
      componentNames: componentNames ?? this.componentNames,
      difference: difference ?? this.difference,

    );
  }
}
// models/records.dart
class Records {
  int digitsInName;
  List<Record> records;
  int resultCount;

  Records({
    this.digitsInName = 0,
    this.records = const [],
    this.resultCount = 0,
  });
}