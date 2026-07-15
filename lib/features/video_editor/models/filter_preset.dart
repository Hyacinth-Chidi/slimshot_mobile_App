class FilterPreset {
  final String id;
  final String name;
  final String category;
  final List<double> matrix;

  const FilterPreset({
    required this.id,
    required this.name,
    required this.category,
    required this.matrix,
  });

  /// Interpolate between identity matrix and this matrix based on intensity (0.0 to 1.0)
  List<double> getInterpolatedMatrix(double intensity) {
    if (intensity >= 1.0) return matrix;
    if (intensity <= 0.0) return identityMatrix;

    final result = List<double>.filled(20, 0.0);
    for (int i = 0; i < 20; i++) {
      result[i] = identityMatrix[i] + (matrix[i] - identityMatrix[i]) * intensity;
    }
    return result;
  }

  static const List<double> identityMatrix = [
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ];
}
