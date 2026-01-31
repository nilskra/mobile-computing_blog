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

  /// Local-only: downloaded header image stored in DB cache as base64
  final String? headerImageBase64;

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
    this.headerImageBase64,
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
      userIdsWithLikes: (json['userIdsWithLikes'] as List<dynamic>?)
          ?.cast<String>(),
      isLikedByMe: (json['likedByMe'] as bool?) ?? false,
      likes: (json['likes'] as int?) ?? 0,
      createdByMe: (json['createdByMe'] as bool?) ?? false,
    );
  }

  factory Blog.fromApiResponse(dynamic decoded) {
    if (decoded is Map<String, dynamic> && decoded['data'] is List) {
      final list = decoded['data'] as List<dynamic>;
      if (list.isEmpty) {
        throw const FormatException('Empty blog data list');
      }
      return Blog.fromJson(list.first as Map<String, dynamic>);
    }

    if (decoded is Map<String, dynamic> && decoded['data'] is Map) {
      return Blog.fromJson(decoded['data'] as Map<String, dynamic>);
    }

    if (decoded is Map<String, dynamic>) {
      return Blog.fromJson(decoded);
    }

    throw const FormatException('Invalid single blog response format');
  }

  Blog copyWith({
    String? id,
    String? author,
    String? title,
    String? contentPreview,
    String? content,
    DateTime? publishedAt,
    DateTime? lastUpdate,
    Object? comments,
    String? headerImageUrl,
    String? headerImageBase64,
    bool? isLikedByMe,
    int? likes,
    List<String>? userIdsWithLikes,
    bool? createdByMe,
  }) {
    return Blog(
      id: id ?? this.id,
      author: author ?? this.author,
      title: title ?? this.title,
      contentPreview: contentPreview ?? this.contentPreview,
      content: content ?? this.content,
      publishedAt: publishedAt ?? this.publishedAt,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      comments: comments ?? this.comments,
      headerImageUrl: headerImageUrl ?? this.headerImageUrl,
      headerImageBase64: headerImageBase64 ?? this.headerImageBase64,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      likes: likes ?? this.likes,
      userIdsWithLikes: userIdsWithLikes ?? this.userIdsWithLikes,
      createdByMe: createdByMe ?? this.createdByMe,
    );
  }

  static List<Blog> listFromApiResponse(dynamic decoded) {
    final dynamic raw = (decoded is Map<String, dynamic>)
        ? decoded['data']
        : decoded;

    if (raw is List) {
      return raw.whereType<Map<String, dynamic>>().map(Blog.fromJson).toList();
    }

    if (raw is Map<String, dynamic>) {
      return [Blog.fromJson(raw)];
    }

    throw const FormatException('Invalid blog list response format');
  }

  Map<String, dynamic> toJson() {
    return {"title": title, "content": content ?? ""};
  }

  String get displayText => content ?? contentPreview ?? "";

  static String? titleValidator(String? value) {
    if (value == null || value.length < 4) return "Enter at least 4 characters";
    return null;
  }

  static String? contentValidator(String? value) {
    if (value == null || value.length < 10)
      return "Enter at least 10 characters";
    return null;
  }

  Map<String, dynamic> toCacheMap() => {
    'id': id,
    'author': author,
    'title': title,
    'content': content,
    'contentPreview': contentPreview,
    'publishedAt': publishedAt.toIso8601String(),
    'lastUpdate': lastUpdate?.toIso8601String(),
    'comments': comments,
    'headerImageUrl': headerImageUrl,
    'headerImageBase64': headerImageBase64,
    'userIdsWithLikes': userIdsWithLikes,
    'likes': likes,
    'isLikedByMe': isLikedByMe,
    'createdByMe': createdByMe,
  };

  factory Blog.fromCacheMap(Map<String, dynamic> map) {
    return Blog(
      id: (map['id'] ?? '').toString(),
      author: (map['author'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      content: map['content'] as String?,
      contentPreview: map['contentPreview'] as String?,
      publishedAt:
          DateTime.tryParse((map['publishedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastUpdate: map['lastUpdate'] == null
          ? null
          : DateTime.tryParse(map['lastUpdate'].toString()),
      comments: map['comments'],
      headerImageUrl: map['headerImageUrl']?.toString(),
      headerImageBase64: map['headerImageBase64']?.toString(),
      userIdsWithLikes: map['userIdsWithLikes'] != null
          ? List<String>.from(map['userIdsWithLikes'] as List)
          : null,

      likes: (map['likes'] as int?) ?? 0,
      isLikedByMe: (map['isLikedByMe'] as bool?) ?? false,
      createdByMe: (map['createdByMe'] as bool?) ?? false,
    );
  }
}
