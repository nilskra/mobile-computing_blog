class Blog {
  String id;
  String title;
  String content;
  DateTime publishedAt;
  String? headerImageUrl;
  List<String>? userIdsWithLikes;

  Blog({
    required this.id,
    required this.title,
    required this.content,
    required this.publishedAt,
    this.headerImageUrl,
    this.userIdsWithLikes,
  });

  String get publishedDateString =>
      "${publishedAt.day}.${publishedAt.month}.${publishedAt.year}";

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Blog &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          content == other.content &&
          publishedAt == other.publishedAt &&
          headerImageUrl == other.headerImageUrl &&
          userIdsWithLikes == other.userIdsWithLikes;

  @override
  int get hashCode =>
      id.hashCode ^
      title.hashCode ^
      content.hashCode ^
      publishedAt.hashCode ^
      headerImageUrl.hashCode ^
      userIdsWithLikes.hashCode;

  factory Blog.fromJson(Map<String, dynamic> json) {
    return Blog(
      id: json['\$id'],
      title: json['title'],
      content: json['content'],
      headerImageUrl: json['headerImageUrl'],
      publishedAt: DateTime.parse(json['\$createdAt']),
      userIdsWithLikes: json['userIdsWithLikes'] != null
          ? List<String>.from(json['userIdsWithLikes'])
          : null,
    );
  }
}