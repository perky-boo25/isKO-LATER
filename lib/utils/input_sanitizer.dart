// [ i n p u t   s a n i t i z e r ]
// blocks script, NoSQL operator, and SQL injection payloads on user inputs
abstract final class InputSanitizer {
  // toggle to `false` during live defense to demo the attack succeeding
  static bool securityEnabled = true;

  static final RegExp _xssPattern = RegExp(
    r'(<\s*\/?\s*(script|img|svg|iframe|object|embed|body|style|link|meta)\b|on\w+\s*=|javascript\s*:)',
    caseSensitive: false,
  );

  static final RegExp _nosqlOperatorPattern = RegExp(
    r'(\$(ne|eq|gt|gte|lt|lte|in|nin|where|regex|or|and|not|exists)\b|__proto__|constructor\s*:)',
    caseSensitive: false,
  );

  static final RegExp _sqliPattern = RegExp(
    r"(\b(DROP\s+TABLE|UNION\s+SELECT|INSERT\s+INTO|DELETE\s+FROM)\b|'\s*OR\s+'?1'?\s*=\s*'?1|--\s*$)",
    caseSensitive: false,
  );

  static bool containsMaliciousPayload(String input) {
    if (!securityEnabled) return false;
    return _xssPattern.hasMatch(input) ||
        _nosqlOperatorPattern.hasMatch(input) ||
        _sqliPattern.hasMatch(input);
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
