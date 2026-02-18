/// Модель факта о POI
/// Не хранится в Hive, получается с сервера
class PoiFact {
  final int id;
  final int poiId;
  final String text;

  PoiFact({required this.id, required this.poiId, required this.text});

  factory PoiFact.fromJson(Map<String, dynamic> json) {
    return PoiFact(
      id: json['id'] as int,
      poiId: json['poi_id'] as int,
      text: json['fact_text'] as String,
    );
  }
}

/// Модель общего факта
/// Не хранится в Hive, получается с сервера
class GeneralFact {
  final int id;
  final String text;
  final String category;

  GeneralFact({required this.id, required this.text, required this.category});

  factory GeneralFact.fromJson(Map<String, dynamic> json) {
    return GeneralFact(
      id: json['id'] as int,
      text: json['fact_text'] as String,
      category: json['category'] as String,
    );
  }
}