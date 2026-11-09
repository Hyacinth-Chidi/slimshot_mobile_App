import '../../../core/models/draft_project.dart';
import '../../../core/services/draft_service.dart';

/// Whether leaving the editor asks "Save as draft?" (the owner's call,
/// 2026-11-09): only for a project that was not in Recent Edits when the
/// editor opened. One opened from there is a draft already and saves as it
/// always did, so a Back press can never throw earlier work away. A draft
/// built but never saved — a reaction opened from the camera the first time
/// — is as new as picked media.
Future<bool> asksToSaveOnLeave(DraftProject? opened) async =>
    opened == null || await DraftService.getDraftById(opened.id) == null;
