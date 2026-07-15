import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class OverlayAnimation {
  final String id;
  final String name;
  final IconData icon;

  const OverlayAnimation({
    required this.id,
    required this.name,
    required this.icon,
  });

  static const List<OverlayAnimation> inAnimations = [
    OverlayAnimation(id: 'fade_in', name: 'Fade In', icon: LucideIcons.eye),
    OverlayAnimation(id: 'slide_up', name: 'Slide Up', icon: LucideIcons.arrowUp),
    OverlayAnimation(id: 'slide_down', name: 'Slide Down', icon: LucideIcons.arrowDown),
    OverlayAnimation(id: 'slide_left', name: 'Slide Left', icon: LucideIcons.arrowLeft),
    OverlayAnimation(id: 'slide_right', name: 'Slide Right', icon: LucideIcons.arrowRight),
    OverlayAnimation(id: 'zoom_in', name: 'Zoom In', icon: LucideIcons.zoomIn),
    OverlayAnimation(id: 'zoom_out', name: 'Zoom Out', icon: LucideIcons.zoomOut),
  ];

  static const List<OverlayAnimation> outAnimations = [
    OverlayAnimation(id: 'fade_out', name: 'Fade Out', icon: LucideIcons.eyeOff),
    OverlayAnimation(id: 'slide_up_out', name: 'Slide Up', icon: LucideIcons.arrowUp),
    OverlayAnimation(id: 'slide_down_out', name: 'Slide Down', icon: LucideIcons.arrowDown),
    OverlayAnimation(id: 'slide_left_out', name: 'Slide Left', icon: LucideIcons.arrowLeft),
    OverlayAnimation(id: 'slide_right_out', name: 'Slide Right', icon: LucideIcons.arrowRight),
    OverlayAnimation(id: 'zoom_in_out', name: 'Zoom In', icon: LucideIcons.zoomIn),
    OverlayAnimation(id: 'zoom_out_out', name: 'Zoom Out', icon: LucideIcons.zoomOut),
  ];
}
