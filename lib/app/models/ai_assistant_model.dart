class AiAssistantUsage {
  final int searchesRemaining;
  final int searchesLimit;
  final int imagesRemaining;
  final int imagesLimit;
  final String? period;
  final String? resetsAt;
  final bool aiEnabledForUser;

  AiAssistantUsage({
    required this.searchesRemaining,
    required this.searchesLimit,
    required this.imagesRemaining,
    required this.imagesLimit,
    this.period,
    this.resetsAt,
    required this.aiEnabledForUser,
  });

  factory AiAssistantUsage.fromJson(Map<String, dynamic> json) {
    return AiAssistantUsage(
      searchesRemaining: json['searches_remaining'] ?? 0,
      searchesLimit: json['searches_limit'] ?? 0,
      imagesRemaining: json['images_remaining'] ?? 0,
      imagesLimit: json['images_limit'] ?? 0,
      period: json['period']?.toString(),
      resetsAt: json['resets_at']?.toString(),
      aiEnabledForUser: json['ai_enabled_for_user'] == true,
    );
  }
}

class AiAssistantCourseItem {
  final int id;
  final String title;

  AiAssistantCourseItem({required this.id, required this.title});

  factory AiAssistantCourseItem.fromJson(Map<String, dynamic> json) {
    return AiAssistantCourseItem(
      id: json['id'] is int ? json['id'] : int.tryParse('${json['id']}') ?? 0,
      title: json['title']?.toString() ?? '',
    );
  }
}

class AiAssistantSubjectItem {
  final int id;
  final String title;

  AiAssistantSubjectItem({required this.id, required this.title});

  factory AiAssistantSubjectItem.fromJson(Map<String, dynamic> json) {
    return AiAssistantSubjectItem(
      id: json['id'] is int ? json['id'] : int.tryParse('${json['id']}') ?? 0,
      title: json['title']?.toString() ?? json['name']?.toString() ?? '',
    );
  }
}

class AiAssistantSearchResult {
  final String answer;
  final String? conversationId;
  final int? searchesRemaining;

  AiAssistantSearchResult({
    required this.answer,
    this.conversationId,
    this.searchesRemaining,
  });

  factory AiAssistantSearchResult.fromJson(Map<String, dynamic> json) {
    return AiAssistantSearchResult(
      answer: json['answer']?.toString() ?? '',
      conversationId: json['conversation_id']?.toString(),
      searchesRemaining: json['searches_remaining'] is int
          ? json['searches_remaining']
          : int.tryParse('${json['searches_remaining']}'),
    );
  }
}

class AiAssistantImageResult {
  final String imageUrl;
  final int? imagesRemaining;

  AiAssistantImageResult({required this.imageUrl, this.imagesRemaining});

  factory AiAssistantImageResult.fromJson(Map<String, dynamic> json) {
    return AiAssistantImageResult(
      imageUrl: json['image_url']?.toString() ?? '',
      imagesRemaining: json['images_remaining'] is int
          ? json['images_remaining']
          : int.tryParse('${json['images_remaining']}'),
    );
  }
}
