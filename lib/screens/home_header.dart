import 'package:flutter/material.dart';

import '../features/account/widgets/credits_pill.dart';

/// The home screen's top row: the brand on the left, the credits pill on the
/// right. On a narrow phone the brand scales down rather than push the pill
/// off the screen.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, required this.brand});

  final Widget brand;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: brand,
          ),
        ),
        const SizedBox(width: 12),
        const CreditsPill(),
      ],
    );
  }
}
