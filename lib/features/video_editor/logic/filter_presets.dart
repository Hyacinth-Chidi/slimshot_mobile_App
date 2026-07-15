import '../models/filter_preset.dart';

class FilterPresets {
  static const List<String> categories = [
    'Trending',
    'Movies',
    'Vintage',
    'Glitch', // (Using color tints as placeholders for glitch/weather)
    'Weather',
  ];

  static const List<FilterPreset> allPresets = [
    // --- TRENDING ---
    FilterPreset(
      id: 'neon',
      name: 'NEON',
      category: 'Trending',
      matrix: [
        1.5, 0.0, 0.0, 0.0, 0.0,
        0.0, 0.5, 0.0, 0.0, 0.0,
        0.0, 0.0, 1.5, 0.0, 0.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ],
    ),
    FilterPreset(
      id: 'dual',
      name: 'DUAL',
      category: 'Trending',
      matrix: [
        1.0, 0.5, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.5, 0.0, 0.0,
        0.5, 0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ],
    ),
    FilterPreset(
      id: 'cyberpunk',
      name: 'CYBER',
      category: 'Trending',
      matrix: [
        0.8, 0.0, 0.5, 0.0, 10.0,
        0.0, 1.2, 0.0, 0.0, 0.0,
        0.5, 0.0, 1.3, 0.0, 20.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ], // Teal and magenta push
    ),
    FilterPreset(
      id: 'golden',
      name: 'GOLDEN',
      category: 'Trending',
      matrix: [
        1.2, 0.1, 0.0, 0.0, 15.0,
        0.1, 1.1, 0.0, 0.0, 5.0,
        0.0, 0.0, 0.8, 0.0, -10.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ], // Warm gold highlight
    ),
    FilterPreset(
      id: 'arctic',
      name: 'ARCTIC',
      category: 'Trending',
      matrix: [
        0.8, 0.1, 0.1, 0.0, 0.0,
        0.1, 0.9, 0.2, 0.0, 5.0,
        0.1, 0.2, 1.2, 0.0, 20.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ], // Icy desaturated blue
    ),
    FilterPreset(
      id: 'haze',
      name: 'HAZE',
      category: 'Trending',
      matrix: [
        0.9, 0.1, 0.1, 0.0, 30.0,
        0.1, 0.9, 0.1, 0.0, 30.0,
        0.1, 0.1, 0.9, 0.0, 30.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ], // Soft pastel wash
    ),

    // --- MOVIES ---
    FilterPreset(
      id: 'film',
      name: 'FILM',
      category: 'Movies',
      matrix: [
        1.1, 0.0, 0.0, 0.0, -10.0,
        0.0, 1.1, 0.0, 0.0, -10.0,
        0.0, 0.0, 1.1, 0.0, -10.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ],
    ),
    FilterPreset(
      id: 'cinematic',
      name: 'CINEMA',
      category: 'Movies',
      matrix: [
        0.9, 0.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 1.2, 0.0, 0.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ],
    ),
    FilterPreset(
      id: 'noir',
      name: 'NOIR',
      category: 'Movies',
      matrix: [
        0.3, 0.59, 0.11, 0.0, -20.0,
        0.3, 0.59, 0.11, 0.0, -20.0,
        0.3, 0.59, 0.11, 0.0, -20.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ], // High contrast B&W
    ),
    FilterPreset(
      id: 'retro70',
      name: '70s',
      category: 'Movies',
      matrix: [
        1.3, 0.0, 0.0, 0.0, 20.0,
        0.0, 1.1, 0.0, 0.0, 5.0,
        0.0, 0.0, 0.8, 0.0, -15.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ], // Faded warm orange
    ),
    FilterPreset(
      id: 'thriller',
      name: 'THRILLER',
      category: 'Movies',
      matrix: [
        0.8, 0.0, 0.0, 0.0, -10.0,
        0.0, 1.1, 0.0, 0.0, 5.0,
        0.0, 0.0, 0.9, 0.0, -5.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ], // Green tinted dark
    ),
    FilterPreset(
      id: 'drama',
      name: 'DRAMA',
      category: 'Movies',
      matrix: [
        0.9, 0.0, 0.0, 0.0, -5.0,
        0.0, 0.9, 0.0, 0.0, -5.0,
        0.0, 0.0, 1.1, 0.0, 10.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ], // Moody desaturated blue
    ),

    // --- VINTAGE ---
    FilterPreset(
      id: 'vintage',
      name: 'VINTAGE',
      category: 'Vintage',
      matrix: [
        1.2, 0.1, 0.1, 0.0, 20.0,
        0.0, 1.0, 0.1, 0.0, 10.0,
        0.0, 0.0, 0.8, 0.0, -10.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ],
    ),
    FilterPreset(
      id: 'sepia',
      name: 'SEPIA',
      category: 'Vintage',
      matrix: [
        0.393, 0.769, 0.189, 0.0, 0.0,
        0.349, 0.686, 0.168, 0.0, 0.0,
        0.272, 0.534, 0.131, 0.0, 0.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ],
    ),
    FilterPreset(
      id: 'bw',
      name: 'B&W',
      category: 'Vintage',
      matrix: [
        0.33, 0.59, 0.11, 0.0, 0.0,
        0.33, 0.59, 0.11, 0.0, 0.0,
        0.33, 0.59, 0.11, 0.0, 0.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ],
    ),
    FilterPreset(
      id: 'polaroid',
      name: 'POLAROID',
      category: 'Vintage',
      matrix: [
        1.1, 0.0, 0.0, 0.0, 20.0,
        0.0, 1.0, 0.0, 0.0, 10.0,
        0.0, 0.0, 0.9, 0.0, -5.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ], // Slight warm fade
    ),
    FilterPreset(
      id: 'faded',
      name: 'FADED',
      category: 'Vintage',
      matrix: [
        0.8, 0.1, 0.1, 0.0, 40.0,
        0.1, 0.8, 0.1, 0.0, 40.0,
        0.1, 0.1, 0.8, 0.0, 40.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ], // Low contrast washed out
    ),
    FilterPreset(
      id: 'lomo',
      name: 'LOMO',
      category: 'Vintage',
      matrix: [
        1.2, 0.0, 0.0, 0.0, 10.0,
        0.0, 1.2, 0.0, 0.0, 10.0,
        0.0, 0.0, 0.8, 0.0, -20.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ], // Cross processed saturation
    ),

    // --- GLITCH ---
    FilterPreset(
      id: 'glitch',
      name: 'GLITCH',
      category: 'Glitch',
      matrix: [
        0.0, 1.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0, 0.0,
        1.0, 0.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ],
    ),
    FilterPreset(
      id: 'invert',
      name: 'INVERT',
      category: 'Glitch',
      matrix: [
        -1.0,  0.0,  0.0, 0.0, 255.0,
         0.0, -1.0,  0.0, 0.0, 255.0,
         0.0,  0.0, -1.0, 0.0, 255.0,
         0.0,  0.0,  0.0, 1.0,   0.0,
      ], // Negative image
    ),
    FilterPreset(
      id: 'thermal',
      name: 'THERMAL',
      category: 'Glitch',
      matrix: [
        1.0, 0.5, 0.0, 0.0, 0.0,
        0.0, 0.5, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0, 50.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ], // Fake thermal look
    ),
    FilterPreset(
      id: 'matrix',
      name: 'MATRIX',
      category: 'Glitch',
      matrix: [
        0.0, 0.5, 0.0, 0.0, 0.0,
        0.0, 1.2, 0.0, 0.0, 20.0,
        0.0, 0.3, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ], // Green monochrome
    ),

    // --- WEATHER ---
    FilterPreset(
      id: 'cold',
      name: 'COLD',
      category: 'Weather',
      matrix: [
        0.8, 0.0, 0.0, 0.0, 0.0,
        0.0, 0.9, 0.0, 0.0, 0.0,
        0.0, 0.0, 1.3, 0.0, 10.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ],
    ),
    FilterPreset(
      id: 'warm',
      name: 'WARM',
      category: 'Weather',
      matrix: [
        1.2, 0.0, 0.0, 0.0, 10.0,
        0.0, 1.1, 0.0, 0.0, 5.0,
        0.0, 0.0, 0.9, 0.0, -10.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ], // Golden sunlight
    ),
    FilterPreset(
      id: 'foggy',
      name: 'FOGGY',
      category: 'Weather',
      matrix: [
        0.8, 0.0, 0.0, 0.0, 60.0,
        0.0, 0.8, 0.0, 0.0, 60.0,
        0.0, 0.0, 0.8, 0.0, 60.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ], // Low contrast bright
    ),
    FilterPreset(
      id: 'sunset',
      name: 'SUNSET',
      category: 'Weather',
      matrix: [
        1.3, 0.0, 0.0, 0.0, 20.0,
        0.0, 0.9, 0.0, 0.0, -10.0,
        0.0, 0.0, 1.2, 0.0, 10.0,
        0.0, 0.0, 0.0, 1.0, 0.0,
      ], // Orange and purple tones
    ),
  ];

  static List<FilterPreset> getByCategory(String category) {
    return allPresets.where((p) => p.category == category).toList();
  }
}
