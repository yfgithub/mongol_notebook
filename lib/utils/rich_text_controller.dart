import 'package:flutter/material.dart';
import '../models/note.dart';

class _HistoryState {
  final String text;
  final TextSelection selection;
  final List<AttributeRange> attributes;

  _HistoryState({
    required this.text,
    required this.selection,
    required this.attributes,
  });
}

class MongolRichTextController extends TextEditingController {
  List<AttributeRange> attributes = [];
  TextStyle defaultStyle;

  final List<_HistoryState> _undoStack = [];
  final List<_HistoryState> _redoStack = [];
  static const int _maxHistory = 10;
  bool _isManualChange = false;

  MongolRichTextController({String? text, required this.defaultStyle})
      : super(text: text);

  void _saveHistory() {
    if (_undoStack.length >= _maxHistory) {
      _undoStack.removeAt(0);
    }
    _undoStack.add(_HistoryState(
      text: text,
      selection: selection,
      attributes: attributes.map((a) => AttributeRange(
        start: a.start,
        end: a.end,
        attribute: a.attribute,
      )).toList(),
    ));
    _redoStack.clear();
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void undo() {
    if (_undoStack.isEmpty) return;
    
    _redoStack.add(_HistoryState(
      text: text,
      selection: selection,
      attributes: attributes.map((a) => AttributeRange(
        start: a.start,
        end: a.end,
        attribute: a.attribute,
      )).toList(),
    ));
    
    final state = _undoStack.removeLast();
    _isManualChange = true;
    attributes = state.attributes;
    value = TextEditingValue(text: state.text, selection: state.selection);
    _isManualChange = false;
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;

    _undoStack.add(_HistoryState(
      text: text,
      selection: selection,
      attributes: attributes.map((a) => AttributeRange(
        start: a.start,
        end: a.end,
        attribute: a.attribute,
      )).toList(),
    ));

    final state = _redoStack.removeLast();
    _isManualChange = true;
    attributes = state.attributes;
    value = TextEditingValue(text: state.text, selection: state.selection);
    _isManualChange = false;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final String fullText = text;
    if (fullText.isEmpty) {
      return TextSpan(text: '', style: style);
    }

    // 1. Collect all boundary points
    final Set<int> boundaries = {0, fullText.length};
    for (final attr in attributes) {
      boundaries.add(attr.start.clamp(0, fullText.length));
      boundaries.add(attr.end.clamp(0, fullText.length));
    }

    final sortedBoundaries = boundaries.toList()..sort();
    final List<InlineSpan> children = [];

    // 2. Create spans for each segment
    for (int i = 0; i < sortedBoundaries.length - 1; i++) {
      final int start = sortedBoundaries[i];
      final int end = sortedBoundaries[i + 1];
      if (start >= end) continue;

      // Find all attributes that apply to this segment
      bool isBold = false;
      bool isUnderline = false;
      Color? color;
      double? fontSize;
      String? imagePath;

      for (final attr in attributes) {
        if (attr.start <= start && attr.end >= end) {
          if (attr.attribute.isBold) isBold = true;
          if (attr.attribute.isUnderline) isUnderline = true;
          if (attr.attribute.color != null) color = attr.attribute.color;
          if (attr.attribute.fontSize != null) fontSize = attr.attribute.fontSize;
          if (attr.attribute.imagePath != null) imagePath = attr.attribute.imagePath;
        }
      }

      final String segmentText = fullText.substring(start, end);

      if (segmentText == '\uFFFC') {
         // Placeholder for unsupported image
         children.add(TextSpan(
           text: ' [🖼️] ', // Text placeholder
           style: style?.copyWith(color: Colors.grey),
         ));
      } else {
        final segmentStyle = TextStyle(
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          decoration: isUnderline ? TextDecoration.overline : TextDecoration.none,
          color: color ?? style?.color,
          fontSize: fontSize,
        );
        

        children.add(TextSpan(
          text: segmentText,
          style: segmentStyle,
        ));
      }
    }

    return TextSpan(style: style, children: children);
  }

  void applyFontSize(double? size) {
    _saveHistory();
    if (size == null) {
      _toggleAttribute((attr) => TextAttribute(
        isBold: attr.isBold,
        isUnderline: attr.isUnderline,
        color: attr.color,
        imagePath: attr.imagePath,
        fontSize: null,
      ));
    } else {
      _toggleAttribute((attr) => attr.copyWith(fontSize: size));
    }
  }

  void insertImage(String path) {
    _saveHistory();
    final int start = selection.start;
    final String imagePlaceholder = '\uFFFC';
    
    final newText = text.replaceRange(start, selection.end, imagePlaceholder);
    
    // Shift attributes
    final diff = imagePlaceholder.length - (selection.end - selection.start);
    for (var attr in attributes) {
      if (attr.start >= selection.end) {
        attr.start += diff;
        attr.end += diff;
      }
    }

    // Add image attribute
    attributes.add(AttributeRange(
      start: start, 
      end: start + 1, 
      attribute: TextAttribute(imagePath: path)
    ));

    value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + 1),
    );
  }

  void toggleBold() {
    _saveHistory();
    final bool allBold = _isAttributeSet((attr) => attr.isBold);
    _toggleAttribute((attr) => attr.copyWith(isBold: !allBold));
  }

  void toggleUnderline() {
    _saveHistory();
    final bool allUnderline = _isAttributeSet((attr) => attr.isUnderline);
    _toggleAttribute((attr) => attr.copyWith(isUnderline: !allUnderline));
  }

  bool _isAttributeSet(bool Function(TextAttribute) check) {
    if (selection.isCollapsed) return false;
    final int selStart = selection.start;
    final int selEnd = selection.end;

    final List<int> boundaries = [selStart, selEnd];
    for (final attr in attributes) {
        if (attr.start > selStart && attr.start < selEnd) boundaries.add(attr.start);
        if (attr.end > selStart && attr.end < selEnd) boundaries.add(attr.end);
    }
    final sortedBoundaries = boundaries.toSet().toList()..sort();
    
    for (int i = 0; i < sortedBoundaries.length - 1; i++) {
        final int s = sortedBoundaries[i];
        final int e = sortedBoundaries[i+1];
        if (s >= e) continue;
        
        bool segmentSet = false;
        for (final attr in attributes) {
            if (attr.start <= s && attr.end >= e && check(attr.attribute)) {
                segmentSet = true;
                break;
            }
        }
        if (!segmentSet) return false;
    }
    return true;
  }

  void applyColor(Color? color) {
    _saveHistory();
    if (color == null) {
      _toggleAttribute((attr) => TextAttribute(
        isBold: attr.isBold,
        isUnderline: attr.isUnderline,
        color: null,
        fontSize: attr.fontSize,
        imagePath: attr.imagePath,
      ));
    } else {
      _toggleAttribute((attr) => attr.copyWith(color: color));
    }
  }

  void _toggleAttribute(TextAttribute Function(TextAttribute) transform) {
    if (selection.isCollapsed) {
       return;
    }

    final int selStart = selection.start;
    final int selEnd = selection.end;
    final String fullText = text;

    // 1. Determine segments based on ALL current boundaries + selection boundaries
    final Set<int> boundaries = {0, fullText.length, selStart, selEnd};
    for (final attr in attributes) {
      boundaries.add(attr.start.clamp(0, fullText.length));
      boundaries.add(attr.end.clamp(0, fullText.length));
    }
    final sortedBoundaries = boundaries.toList()..sort();

    final List<AttributeRange> newAttributes = [];

    // 2. For each segment, calculate its new style
    for (int i = 0; i < sortedBoundaries.length - 1; i++) {
        final int start = sortedBoundaries[i];
        final int end = sortedBoundaries[i + 1];
        if (start >= end) continue;

        // Find existing style for this segment
        bool isBold = false;
        bool isUnderline = false;
        Color? color;
        double? fontSize;
        String? imagePath;

        for (final attr in attributes) {
            if (attr.start <= start && attr.end >= end) {
                if (attr.attribute.isBold) isBold = true;
                if (attr.attribute.isUnderline) isUnderline = true;
                if (attr.attribute.color != null) color = attr.attribute.color;
                if (attr.attribute.fontSize != null) fontSize = attr.attribute.fontSize;
                if (attr.attribute.imagePath != null) imagePath = attr.attribute.imagePath;
            }
        }

        TextAttribute style = TextAttribute(
            isBold: isBold,
            isUnderline: isUnderline,
            color: color,
            fontSize: fontSize,
            imagePath: imagePath,
        );

        // If segment is within selection, apply transform
        if (start >= selStart && end <= selEnd) {
            style = transform(style);
        }

        // Only add if it has any formatting
        if (style.isBold || style.isUnderline || style.color != null || style.fontSize != null || style.imagePath != null) {
            newAttributes.add(AttributeRange(start: start, end: end, attribute: style));
        }
    }

    // 3. Merge adjacent segments with identical styles
    final List<AttributeRange> mergedAttributes = [];
    if (newAttributes.isNotEmpty) {
        AttributeRange current = newAttributes[0];
        for (int i = 1; i < newAttributes.length; i++) {
            final next = newAttributes[i];
            bool sameStyle = next.attribute.isBold == current.attribute.isBold &&
                             next.attribute.isUnderline == current.attribute.isUnderline &&
                             next.attribute.color == current.attribute.color &&
                             next.attribute.fontSize == current.attribute.fontSize &&
                             next.attribute.imagePath == current.attribute.imagePath;
            
            if (sameStyle && next.start == current.end) {
                current.end = next.end;
            } else {
                mergedAttributes.add(current);
                current = next;
            }
        }
        mergedAttributes.add(current);
    }

    attributes = mergedAttributes;
    notifyListeners();
  }

  @override
  set value(TextEditingValue newValue) {
    if (_isManualChange) {
      super.value = newValue;
      return;
    }

    final oldText = value.text;
    final newText = newValue.text;
    final oldSelection = value.selection;

    // Save history if text changes significantly or after a pause (simulated here by word/length triggers)
    if (oldText != newText && oldText.isNotEmpty) {
       // Save history every 10 characters or on space
       if ((newText.length - oldText.length).abs() > 10 || (newText.length > oldText.length && newText.endsWith(' '))) {
         _saveHistory();
       }
       
      final diff = newText.length - oldText.length;
      final editPos = oldSelection.start;

      // If we are replacing the WHOLE text, skip shifting
      if (editPos == 0 && oldSelection.end == oldText.length) {
          // Full replacement, attributes should be reset by the caller
      } else if (oldSelection.isCollapsed) {
        // Simple insertion or deletion
        for (var attr in attributes) {
          if (attr.start >= editPos) {
            attr.start += diff;
            attr.end += diff;
          } else if (attr.end > editPos) {
            attr.end += diff;
          }
        }
      } else {
        // Overwriting selection
        final selectionStart = oldSelection.start;
        final selectionEnd = oldSelection.end;
        
        for (var attr in attributes) {
          if (attr.start >= selectionEnd) {
            attr.start += diff;
            attr.end += diff;
          } else if (attr.start >= selectionStart && attr.end <= selectionEnd) {
            attr.end = attr.start; 
          } else if (attr.start < selectionStart && attr.end > selectionEnd) {
             attr.end += diff;
          } else if (attr.start < selectionStart && attr.end > selectionStart) {
             attr.end = selectionStart; 
          }
        }
      }
      
      // Cleanup
      attributes.removeWhere((a) => a.start >= a.end || a.start < 0 || a.start >= newText.length);
    }
    super.value = newValue;
  }

  @override
  void clear() {
    attributes.clear();
    super.clear();
  }

  void setContent(String newText, List<AttributeRange> newAttributes) {
    _undoStack.clear();
    _redoStack.clear();
    
    // Deep copy AttributeRange instances to prevent side effects
    attributes = newAttributes.map((a) => AttributeRange(
      start: a.start,
      end: a.end,
      attribute: a.attribute,
    )).toList();
    
    // Bypass the custom setter using super.value to avoid shifting logic during replacements
    super.value = TextEditingValue(
      text: newText,
      selection: const TextSelection.collapsed(offset: 0),
    );
    notifyListeners();
  }

  void clearStyles() {
    _saveHistory();
    attributes.clear();
    notifyListeners();
  }
}
