/// The emoji the picker offers, grouped the way a keyboard groups them.
///
/// **There is no emoji font in this app and there must not be one.** An emoji
/// is a character, so it renders through the platform's own colour emoji face
/// — which is why one typed from the system keyboard already exports
/// correctly, and why bundling a face would only add megabytes and a second
/// look that drifts from what the keyboard produces.
///
/// So this file is a *list of strings*, nothing more. The picker inserts one
/// as a text overlay and it inherits the whole text pipeline: the glyph atlas,
/// per-character animation, mask, chroma key, keyframes and export parity. A
/// separate "emoji overlay" kind would be a second implementation of something
/// already device-verified.
///
/// **Every entry must be a single grapheme cluster.** Flags, skin tones and
/// ZWJ sequences are several codepoints that the renderer counts as one glyph
/// (`text_overlay_emoji_test.dart` pins that); a string holding two clusters
/// would silently insert two glyphs and animate as two characters.
///
/// Kept to well-supported, long-standing emoji on purpose: a codepoint newer
/// than the device's font renders as a hollow box — ugly, and worse, it would
/// export that way too. Nothing here is newer than Emoji 12 (2019), which
/// Android 10 and up carry; older devices fall back to a box only for the
/// rarest entries.
library;

/// One named group in the picker.
class EmojiGroup {
  const EmojiGroup({required this.name, required this.emoji});

  /// Shown on the group's pill.
  final String name;

  /// The cluster shown on the pill — the group's first emoji, so the row of
  /// pills reads as pictures rather than as a row of words.
  String get icon => emoji.first;

  final List<String> emoji;
}

const List<EmojiGroup> kEmojiGroups = [
  EmojiGroup(
    name: 'Smileys',
    emoji: [
      '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '🙃',
      '😉', '😊', '😇', '🥰', '😍', '🤩', '😘', '😗', '😚', '😙',
      '😋', '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🤫', '🤔',
      '🤐', '🤨', '😐', '😑', '😶', '😏', '😒', '🙄', '😬', '😌',
      '😔', '😪', '🤤', '😴', '😷', '🤒', '🤕', '🤢', '🤮', '🥵',
      '🥶', '😵', '🤯', '🤠', '🥳', '😎', '🤓', '🧐', '😕', '😟',
      '🙁', '😮', '😯', '😲', '😳', '🥺', '😦', '😨', '😰', '😥',
      '😢', '😭', '😱', '😖', '😣', '😞', '😓', '😩', '😫', '😤',
      '😡', '😠', '🤬', '😈', '👿', '💀', '💩', '🤡', '👻', '👽',
      '🤖', '😺', '😸', '😹', '😻', '😼', '😽', '🙀', '😿', '😾',
    ],
  ),
  EmojiGroup(
    name: 'Gestures',
    emoji: [
      '👍', '👎', '👌', '✌️', '🤞', '🤟', '🤘', '🤙', '👈', '👉',
      '👆', '👇', '☝️', '✋', '🤚', '🖐️', '🖖', '👋', '🤝', '🙏',
      '✍️', '💪', '🦾', '🦵', '🦶', '👂', '👃', '🧠', '👀', '👁️',
      '👅', '👄', '💋', '🫀', '🙌', '👏', '🤲', '🤜', '🤛', '✊',
      '👊', '🖕', '💅', '🤳', '💃', '🕺', '👶', '🧒', '👦', '👧',
    ],
  ),
  EmojiGroup(
    name: 'Love',
    emoji: [
      '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔',
      '❣️', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '💟', '♥️',
      '💌', '💐', '🌹', '🌺', '🌸', '🌼', '🌻', '💍', '💒', '👰',
    ],
  ),
  EmojiGroup(
    name: 'Animals',
    emoji: [
      '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯',
      '🦁', '🐮', '🐷', '🐸', '🐵', '🙈', '🙉', '🙊', '🐒', '🐔',
      '🐧', '🐦', '🐤', '🦆', '🦅', '🦉', '🦇', '🐺', '🐗', '🐴',
      '🦄', '🐝', '🐛', '🦋', '🐌', '🐞', '🐜', '🦗', '🕷️', '🦂',
      '🐢', '🐍', '🦎', '🐙', '🦑', '🦐', '🦀', '🐡', '🐠', '🐟',
      '🐬', '🐳', '🐋', '🦈', '🐊', '🐅', '🐆', '🦓', '🦍', '🐘',
    ],
  ),
  EmojiGroup(
    name: 'Food',
    emoji: [
      '🍏', '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🍈',
      '🍒', '🍑', '🥭', '🍍', '🥥', '🥝', '🍅', '🥑', '🍆', '🥔',
      '🥕', '🌽', '🌶️', '🥒', '🥬', '🧄', '🧅', '🍄', '🥜', '🍞',
      '🥐', '🥖', '🧀', '🥚', '🍳', '🥞', '🥓', '🍔', '🍟', '🍕',
      '🌭', '🥪', '🌮', '🌯', '🥗', '🍝', '🍜', '🍲', '🍣', '🍱',
      '🍤', '🍚', '🍦', '🍩', '🍪', '🎂', '🍰', '🧁', '🍫', '🍬',
      '🍭', '🍿', '☕', '🍵', '🥤', '🍺', '🍻', '🥂', '🍷', '🍾',
    ],
  ),
  EmojiGroup(
    name: 'Activity',
    emoji: [
      '⚽', '🏀', '🏈', '⚾', '🎾', '🏐', '🏉', '🎱', '🏓', '🏸',
      '🥅', '🏒', '🏑', '🏹', '🎣', '🥊', '🥋', '⛳', '⛸️', '🎿',
      '🛷', '🥌', '🎯', '🎮', '🎲', '🧩', '🎰', '🎳', '🚴', '🏆',
      '🥇', '🥈', '🥉', '🏅', '🎖️', '🎗️', '🎫', '🎪', '🎭', '🎨',
      '🎬', '🎤', '🎧', '🎼', '🎹', '🥁', '🎷', '🎺', '🎸', '🎻',
    ],
  ),
  EmojiGroup(
    name: 'Travel',
    emoji: [
      '🚗', '🚕', '🚙', '🚌', '🚎', '🏎️', '🚓', '🚑', '🚒', '🚐',
      '🚚', '🚛', '🚜', '🛵', '🏍️', '🚲', '🛴', '✈️', '🚀', '🛸',
      '🚁', '⛵', '🚤', '🛳️', '⚓', '🚂', '🚆', '🚊', '🗺️', '🗿',
      '🗽', '🗼', '🏰', '🏯', '🎡', '🎢', '🎠', '⛲', '⛱️', '🏖️',
      '🏝️', '🏔️', '⛰️', '🌋', '🏕️', '🌄', '🌅', '🌇', '🌆', '🌃',
    ],
  ),
  EmojiGroup(
    name: 'Objects',
    emoji: [
      '⌚', '📱', '💻', '⌨️', '🖥️', '🖨️', '🖱️', '💽', '💾', '📀',
      '📷', '📸', '📹', '🎥', '📞', '☎️', '📺', '📻', '⏰', '⏱️',
      '🔋', '🔌', '💡', '🔦', '🕯️', '🧯', '🛢️', '💸', '💵', '💳',
      '💎', '⚖️', '🔧', '🔨', '⚒️', '🛠️', '⛏️', '🔩', '⚙️', '🧲',
      '🔫', '💣', '🧨', '🔪', '🗡️', '🛡️', '🚬', '⚰️', '🔮', '📿',
      '💈', '⚗️', '🔭', '🔬', '🕳️', '💊', '💉', '🩸', '🧬', '🦠',
      '🧪', '🌡️', '🧹', '🧺', '🧻', '🚽', '🚿', '🛁', '🧼', '🔑',
      '🗝️', '🚪', '🛋️', '🛏️', '🖼️', '🛍️', '🎁', '🎈', '🎉', '🎊',
    ],
  ),
  EmojiGroup(
    name: 'Symbols',
    emoji: [
      '💯', '🔥', '✨', '⭐', '🌟', '💫', '⚡', '☄️', '💥', '🌈',
      '☀️', '🌤️', '⛅', '☁️', '🌧️', '⛈️', '❄️', '☃️', '💨', '💧',
      '🌊', '🎵', '🎶', '💤', '💭', '💬', '🗯️', '❗', '❓', '‼️',
      '⁉️', '✅', '❌', '⭕', '🚫', '⚠️', '♻️', '🔱', '⚜️', '🔰',
      '✔️', '➕', '➖', '➗', '✖️', '💲', '🔔', '🔕', '📢', '📣',
      '🏁', '🚩', '🎌', '🏴', '🏳️', '🔴', '🟠', '🟡', '🟢', '🔵',
      '🟣', '⚫', '⚪', '🟥', '🟧', '🟨', '🟩', '🟦', '🟪', '⬛',
    ],
  ),
];

/// Every emoji in the catalog, in group order.
List<String> get kAllEmoji => [
      for (final group in kEmojiGroups) ...group.emoji,
    ];
