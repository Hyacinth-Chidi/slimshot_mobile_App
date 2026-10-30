import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lucide_icons.dart';
import '../../../core/utils/toast_utils.dart';
import '../../../core/widgets/settings_rows.dart';
import '../push_controller.dart';
import '../push_providers.dart';

/// Notifications, on or off, in Settings' General group — only in a build
/// with push. It shows on only where notifications can actually arrive, and
/// reads the phone again on coming back to the app, where they may just have
/// been allowed.
class SettingsNotificationsRow extends ConsumerStatefulWidget {
  const SettingsNotificationsRow({super.key});

  @override
  ConsumerState<SettingsNotificationsRow> createState() =>
      _SettingsNotificationsRowState();
}

class _SettingsNotificationsRowState
    extends ConsumerState<SettingsNotificationsRow> {
  bool? _on;
  bool _busy = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Back from the phone's settings, where they may just have been
    // allowed: sync the server, then show what the phone now says.
    _lifecycle = AppLifecycleListener(onResume: _resume);
    // Now, or once Firebase is ready.
    ref.listenManual(pushControllerProvider, (_, __) => _read(),
        fireImmediately: true);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _resume() async {
    await ref.read(pushControllerProvider)?.start();
    await _read();
  }

  Future<void> _read() async {
    final controller = ref.read(pushControllerProvider);
    if (controller == null) return;
    final on = await controller.isOn();
    if (mounted && !_busy) setState(() => _on = on);
  }

  Future<void> _toggle() async {
    final controller = ref.read(pushControllerProvider);
    if (controller == null || _busy) return;
    HapticFeedback.selectionClick();
    _busy = true;
    final result = await controller.setEnabled(!(_on ?? false));
    _busy = false;
    if (!mounted) return;
    setState(() => _on = result == PushSwitch.on);
    if (result == PushSwitch.blocked) {
      ToastUtils.show(
        context,
        'Allow notifications in your phone\'s settings',
        isWarning: true,
      );
      unawaited(ref.read(openAppSettingsProvider)());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(pushControllerProvider) == null) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsItem(
          icon: LucideIcons.bell,
          title: 'Notifications',
          onTap: _toggle,
          trailing: Switch(
            key: const ValueKey('settings_notifications_switch'),
            value: _on ?? false,
            onChanged: (_) => _toggle(),
            activeTrackColor: AppColors.primaryStart,
            activeThumbColor: Colors.white,
            inactiveTrackColor: AppColors.surfaceLight,
            inactiveThumbColor: AppColors.textSecondary,
            trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
        ),
        const SettingsDivider(),
      ],
    );
  }
}
