import '../../../core/database/app_database.dart';

class DropWithTags {
  final Drop drop;
  final List<String> tags;

  const DropWithTags({
    required this.drop,
    this.tags = const [],
  });

  int get id => drop.id;
  String get content => drop.content;
  String? get title => drop.title;
  String? get description => drop.description;
  String? get previewImageUrl => drop.previewImageUrl;
  String? get faviconUrl => drop.faviconUrl;
  String? get sourceDomain => drop.sourceDomain;
  String get assetType => drop.assetType;
  String get triageStatus => drop.triageStatus;
  bool get isPinned => drop.isPinned;
  String? get mediaPath => drop.mediaPath;
  String? get mediaThumbnailPath => drop.mediaThumbnailPath;
  String? get ocrText => drop.ocrText;
  DateTime? get reminderAt => drop.reminderAt;
  DateTime get createdAt => drop.createdAt;
  DateTime get updatedAt => drop.updatedAt;

  bool get isArticle => assetType == 'article';
  bool get isVideo => assetType == 'video';
  bool get isImage => assetType == 'image';
  bool get isClip => assetType == 'clip';

  bool get isArchived => triageStatus == 'archived';
  bool get isInbox => triageStatus == 'inbox';

  DropWithTags copyWith({
    Drop? drop,
    List<String>? tags,
  }) {
    return DropWithTags(
      drop: drop ?? this.drop,
      tags: tags ?? this.tags,
    );
  }
}
