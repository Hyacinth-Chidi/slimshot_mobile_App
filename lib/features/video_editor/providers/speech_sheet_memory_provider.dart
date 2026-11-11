import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/panels/text_to_speech_sheet.dart';

/// The Text to speech sheet's memory, kept while the app runs: the last
/// voice list shows at once while a new one is asked for, and the voice last
/// chosen is chosen again.
final speechSheetMemoryProvider =
    Provider<SpeechSheetMemory>((ref) => SpeechSheetMemory());
