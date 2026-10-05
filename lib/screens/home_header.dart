import 'package:flutter/material.dart';

import '../features/account/widgets/credits_pill.dart';

/// The home screen's top row: the brand on the left, the credits pill pinned
/// to the right edge. On a narrow phone the brand scales down rather than
/// push the pill off the screen.
///
/// The brand takes all the room the pill leaves (`Expanded`, aligned left).
/// It used to be `Flexible`, which sized it to the brand alone, so a short
/// balance — "500" — followed the brand at the minimum gap instead of
/// sitting at the edge (device-reported).
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, required this.brand});

  final Widget brand;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: brand,
            ),
          ),
        ),
        const SizedBox(width: 16),
        const CreditsPill(),
      ],
    );
  }
}
