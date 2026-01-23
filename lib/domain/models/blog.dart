class Blog {
  final String id;
  final String author;
  final String title;

  /// In list + detail responses from your backend, you currently only get contentPreview
  final String? contentPreview;

  /// Full content is currently NOT returned by your backend (stays null most of the time)
  final String? content;

  final DateTime publishedAt;
  final DateTime? lastUpdate;

  final Object? comments;
  final String? headerImageUrl;

  final bool isLikedByMe;
  final int likes;
  final List<String>? userIdsWithLikes; // optional, might not exist in response
  final bool createdByMe;

  Blog({
    this.id = "0",
    required this.author,
    required this.title,
    this.contentPreview,
    this.content,
    required this.publishedAt,
    this.lastUpdate,
    this.comments,
    this.headerImageUrl,
    this.userIdsWithLikes,
    this.isLikedByMe = false,
    this.likes = 0,
    this.createdByMe = false,
  });

  /// ✅ Parses ONE blog object (no wrapper)
  factory Blog.fromJson(Map<String, dynamic> json) {
    return Blog(
      id: (json['id'] as int).toString(),
      author: json['author'] as String,
      title: json['title'] as String,
      contentPreview: json['contentPreview'] as String?,
      content: json['content'] as String?, // usually null with your API
      publishedAt: DateTime.parse(json['createdAt'] as String),
      lastUpdate: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
      comments: json['comments'],
      headerImageUrl: json['headerImageUrl'] as String?,
      userIdsWithLikes:
          (json['userIdsWithLikes'] as List<dynamic>?)?.cast<String>(),
      isLikedByMe: (json['likedByMe'] as bool?) ?? false,
      likes: (json['likes'] as int?) ?? 0,
      createdByMe: (json['createdByMe'] as bool?) ?? false,
    );
  }

  /// ✅ Parses an API response that may wrap blogs like:
  /// 1) { data: [ { ... } ] }
  /// 2) { data: { ... } }
  /// 3) { ... }
  factory Blog.fromApiResponse(dynamic decoded) {
    // { data: [ ... ] }
    if (decoded is Map<String, dynamic> && decoded['data'] is List) {
      final list = decoded['data'] as List<dynamic>;
      if (list.isEmpty) {
        throw const FormatException('Empty blog data list');
      }
      return Blog.fromJson(list.first as Map<String, dynamic>);
    }

    // { data: { ... } }
    if (decoded is Map<String, dynamic> && decoded['data'] is Map) {
      return Blog.fromJson(decoded['data'] as Map<String, dynamic>);
    }

    // { ... }
    if (decoded is Map<String, dynamic>) {
      return Blog.fromJson(decoded);
    }

    throw const FormatException('Invalid single blog response format');
  }

  /// ✅ Parses list response (your GET /entries)
  static List<Blog> listFromApiResponse(dynamic decoded) {
    final dynamic raw =
        (decoded is Map<String, dynamic>) ? decoded['data'] : decoded;

    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map(Blog.fromJson)
          .toList();
    }

    // fallback if backend ever returns a single object
    if (raw is Map<String, dynamic>) {
      return [Blog.fromJson(raw)];
    }

    throw const FormatException('Invalid blog list response format');
  }

  Map<String, dynamic> toJson() {
    return {
      "title": title,
      "content": content ?? "",
      // "headerImageUrl": headerImageUrl ?? "",
    };
  }

  // Optional helpers
  String get displayText => content ?? contentPreview ?? "";

  static String? titleValidator(String? value) {
    if (value == null || value.length < 4) return "Enter at least 4 characters";
    return null;
  }

  static String? contentValidator(String? value) {
    if (value == null || value.length < 10) return "Enter at least 10 characters";
    return null;
  }
}
