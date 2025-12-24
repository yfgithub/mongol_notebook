import 'package:flutter/material.dart';

class TextAttribute {
  final bool isBold;
  final bool isUnderline;
  final Color? color;
  final double? fontSize;
  final String? imagePath;

  TextAttribute({
    this.isBold = false,
    this.isUnderline = false,
    this.color,
    this.fontSize,
    this.imagePath,
  });

  TextAttribute copyWith({
    bool? isBold,
    bool? isUnderline,
    Color? color,
    double? fontSize,
    String? imagePath,
  }) {
    return TextAttribute(
      isBold: isBold ?? this.isBold,
      isUnderline: isUnderline ?? this.isUnderline,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
      imagePath: imagePath ?? this.imagePath,
    );
  }

  Map<String, dynamic> toJson() => {
        'bold': isBold,
        'underline': isUnderline,
        'color': color?.value,
        'fontSize': fontSize,
        'imagePath': imagePath,
      };

  factory TextAttribute.fromJson(Map<String, dynamic> json) => TextAttribute(
        isBold: json['bold'] ?? false,
        isUnderline: json['underline'] ?? false,
        color: json['color'] != null ? Color(json['color']) : null,
        fontSize: json['fontSize']?.toDouble(),
        imagePath: json['imagePath'],
      );
}

class AttributeRange {
  int start;
  int end;
  final TextAttribute attribute;

  AttributeRange({
    required this.start,
    required this.end,
    required this.attribute,
  });

  AttributeRange copyWith({
    int? start,
    int? end,
    TextAttribute? attribute,
  }) {
    return AttributeRange(
      start: start ?? this.start,
      end: end ?? this.end,
      attribute: attribute ?? this.attribute,
    );
  }

  Map<String, dynamic> toJson() => {
        'start': start,
        'end': end,
        'attribute': attribute.toJson(),
      };

  factory AttributeRange.fromJson(Map<String, dynamic> json) => AttributeRange(
        start: json['start'],
        end: json['end'],
        attribute: TextAttribute.fromJson(json['attribute']),
      );
}

class Note {
  final String id;
  String title;
  String content;
  List<AttributeRange> attributes; // NEW: true rich text spans
  DateTime updatedAt;
  List<String> tags;
  bool isPinned;
  bool isDeleted; // NEW: Soft delete support

  Note({
    required this.id,
    required this.title,
    required this.content,
    List<AttributeRange>? attributes,
    required this.updatedAt,
    this.tags = const [],
    this.isPinned = false,
    this.isDeleted = false,
  }) : attributes = attributes ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'attributes': attributes.map((a) => a.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
        'tags': tags,
        'isPinned': isPinned,
        'isDeleted': isDeleted,
      };

  factory Note.fromJson(Map<String, dynamic> json) {
    List<AttributeRange> attrs = [];
    if (json['attributes'] != null) {
      attrs = (json['attributes'] as List)
          .map((a) => AttributeRange.fromJson(a as Map<String, dynamic>))
          .toList();
    }

    return Note(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      attributes: attrs,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      tags: json['tags'] != null ? List<String>.from(json['tags'] as List) : [],
      isPinned: json['isPinned'] as bool? ?? false,
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }
}
