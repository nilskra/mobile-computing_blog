enum PendingOpType { createBlog, patchBlog, deleteBlog, setLike }

class PendingOp {
  PendingOp({
    required this.id,
    required this.type,
    required this.blogId,
    required this.createdAt,
    this.payload,
  });

  final String id; // uuid oder timestamp string
  final PendingOpType type;
  final String blogId;
  final DateTime createdAt;

  /// z.B. { "title": "...", "content": "..." } oder { "likedByMe": true }
  final Map<String, dynamic>? payload;

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'blogId': blogId,
        'createdAt': createdAt.toIso8601String(),
        'payload': payload,
      };

  factory PendingOp.fromMap(Map<String, dynamic> map) => PendingOp(
        id: map['id'].toString(),
        type: PendingOpType.values.firstWhere(
          (e) => e.name == map['type'],
          orElse: () => PendingOpType.patchBlog,
        ),
        blogId: map['blogId'].toString(),
        createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        payload: (map['payload'] as Map?)?.cast<String, dynamic>(),
      );
}
