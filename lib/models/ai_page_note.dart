class AiPageNote {
  final int pageNumber;
  final String markdown;

  const AiPageNote({required this.pageNumber, required this.markdown});

  factory AiPageNote.fromJson(Map<String, dynamic> json) {
    final pageValue = json['page_number'] ?? json['pageNumber'];
    final pageNumber = pageValue is int
        ? pageValue
        : int.tryParse(pageValue.toString());

    if (pageNumber == null) {
      throw const FormatException('Missing page_number in AI note response.');
    }

    final markdown = json['markdown'];
    if (markdown is! String) {
      throw const FormatException('Missing markdown in AI note response.');
    }

    return AiPageNote(pageNumber: pageNumber, markdown: markdown.trim());
  }

  Map<String, dynamic> toJson() {
    return {'page_number': pageNumber, 'markdown': markdown};
  }
}
