class TextCleaner {
  /// Удаляет markdown-разметку, эмодзи и лишние символы, оставляя читаемый текст.
  static String cleanForTts(String text) {
    if (text.isEmpty) return text;

    // Удаляем markdown-ссылки: [текст](url) -> текст
    text = text.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^)]+\)'),
      (match) => match[1] ?? '',
    );

    // Удаляем markdown-символы: *, _, `, #, >, -, +, =, |, ~
    text = text.replaceAll(RegExp(r'[*_`#>\-+=|~]'), '');

    // Удаляем эмодзи (основные диапазоны)
    text = text.replaceAll(
      RegExp(
        r'[\u00a9\u00ae\u2000-\u3300\ud83c\ud000-\udfff\ud83d\ud000-\udfff\ud83e\ud000-\udfff]',
      ),
      '',
    );

    // Заменяем множественные пробелы одним
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    return text;
  }
}