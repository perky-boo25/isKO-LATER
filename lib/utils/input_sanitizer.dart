// [ i n p u t   s a n i t i z e r ]
// defense-in-depth check blocking HTML/XSS tags and NoSQL operator syntax
abstract final class InputSanitizer {
  static bool securityEnabled = true;

  // matches HTML/script tags and inline event handlers (<script>, <img onerror=...>, javascript:)
  static final RegExp _xssPattern = RegExp(
    r'(<\s*\/?\s*(script|img|svg|iframe|object|embed|style)\b|on(error|load|click|mouseover)\s*=|javascript\s*:)',
    caseSensitive: false,
  );

  // matches Mongo/NoSQL JSON query operator syntax (e.g. {"$ne": null}, $where, __proto__)
  static final RegExp _nosqlOperatorPattern = RegExp(
    r'(\$(ne|eq|gt|gte|lt|lte|where|regex)\b|__proto__)',
    caseSensitive: false,
  );

  static bool containsMaliciousPayload(String input) {
    if (!securityEnabled) return false;
    return _xssPattern.hasMatch(input) || _nosqlOperatorPattern.hasMatch(input);
  }

  // form validator used by TextFormField
  static String? validateSafeText(
    String? value, {
    required String fieldName,
    int maxLength = 500,
  }) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return '$fieldName is required';

    if (securityEnabled && trimmed.length > maxLength) {
      return '$fieldName cannot exceed $maxLength characters';
    }

    if (containsMaliciousPayload(trimmed)) {
      return 'Security Blocked: Unsafe script or query payload detected.';
    }

    return null;
  }

  // service-layer guard so direct calls cannot bypass form validation
  static String enforceSafeText(
    String value, {
    required String fieldName,
    int maxLength = 500,
  }) {
    final error = validateSafeText(
      value,
      fieldName: fieldName,
      maxLength: maxLength,
    );
    if (error != null) throw StateError(error);
    return value.trim();
  }
}
