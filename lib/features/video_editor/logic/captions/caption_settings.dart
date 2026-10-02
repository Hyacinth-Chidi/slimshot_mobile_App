import 'caption_highlight.dart';

/// Which sound auto captions listen to.
enum CaptionSource {
  /// The clips and the video overlays — the speech in the footage. The
  /// default, so background music does not become lyric captions.
  video(['clips', 'overlays']),

  /// Imported audio tracks — a voiceover recorded elsewhere, or music.
  tracks(['tracks']),

  all(['clips', 'overlays', 'tracks']);

  const CaptionSource(this.include);

  /// The kinds of sound the native caption pass mixes
  /// (`CaptionAudioSources.Include` on the Kotlin side).
  final List<String> include;
}

/// How much of the speech one caption holds.
enum CaptionLength {
  word(maxWords: 1, maxChars: 1 << 30),
  phrase(maxWords: 3, maxChars: 20),
  line(maxWords: 7, maxChars: 32);

  const CaptionLength({required this.maxWords, required this.maxChars});

  final int maxWords;

  /// Grapheme clusters, separators included.
  final int maxChars;
}

/// The languages the sheet offers after Auto detect, as the server's ISO 639-1
/// codes. Which of them transcribe well depends on the provider the server has
/// active; a refusal comes back as an ordinary caption error.
const List<({String code, String name})> kCaptionLanguages = [
  (code: 'en', name: 'English'),
  (code: 'fr', name: 'French'),
  (code: 'es', name: 'Spanish'),
  (code: 'pt', name: 'Portuguese'),
  (code: 'de', name: 'German'),
  (code: 'it', name: 'Italian'),
  (code: 'nl', name: 'Dutch'),
  (code: 'ar', name: 'Arabic'),
  (code: 'hi', name: 'Hindi'),
  (code: 'zh', name: 'Chinese'),
  (code: 'ja', name: 'Japanese'),
  (code: 'ko', name: 'Korean'),
  (code: 'ru', name: 'Russian'),
  (code: 'tr', name: 'Turkish'),
  (code: 'id', name: 'Indonesian'),
  (code: 'sw', name: 'Swahili'),
  (code: 'yo', name: 'Yoruba'),
  (code: 'ig', name: 'Igbo'),
  (code: 'ha', name: 'Hausa'),
];

/// Whether [code] is a language the sheet offers.
bool isCaptionLanguage(Object? code) =>
    code is String && kCaptionLanguages.any((l) => l.code == code);

/// What a project's caption set was made with — what the sheet reopens on and
/// what a regeneration starts from.
class CaptionSettings {
  const CaptionSettings({
    required this.setId,
    this.source = CaptionSource.video,
    this.language,
    this.length = CaptionLength.phrase,
    this.highlight = CaptionHighlight.none,
  });

  /// The `captionSetId` every caption of the set carries.
  final String setId;

  final CaptionSource source;

  /// An ISO 639-1 code, or null for Auto detect.
  final String? language;

  final CaptionLength length;

  /// How the set marks the word being spoken.
  final CaptionHighlight highlight;

  CaptionSettings copyWith({
    CaptionSource? source,
    CaptionLength? length,
    CaptionHighlight? highlight,
  }) =>
      CaptionSettings(
        setId: setId,
        source: source ?? this.source,
        language: language,
        length: length ?? this.length,
        highlight: highlight ?? this.highlight,
      );

  Map<String, dynamic> toJson() => {
        'setId': setId,
        'source': source.name,
        if (language != null) 'language': language,
        'length': length.name,
        if (!highlight.isNone) 'highlight': highlight.toJson(),
      };

  /// Null for anything without a set id; unknown names read as the defaults,
  /// and a language the sheet does not list as Auto detect — the sheet labels
  /// a language from its list, so an unknown one could not be shown.
  static CaptionSettings? fromJson(Object? json) {
    if (json is! Map) return null;
    final setId = json['setId'];
    if (setId is! String || setId.isEmpty) return null;
    final language = json['language'];
    return CaptionSettings(
      setId: setId,
      source: CaptionSource.values.asNameMap()[json['source']] ??
          CaptionSource.video,
      language: isCaptionLanguage(language) ? language as String : null,
      length: CaptionLength.values.asNameMap()[json['length']] ??
          CaptionLength.phrase,
      highlight: CaptionHighlight.fromJson(json['highlight']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CaptionSettings &&
      other.setId == setId &&
      other.source == source &&
      other.language == language &&
      other.length == length &&
      other.highlight == highlight;

  @override
  int get hashCode => Object.hash(setId, source, language, length, highlight);
}
