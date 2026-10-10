import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The package name the ported transitions are listed under.
const String kGlTransitionsPackage = 'gl-transitions';

/// Every author whose GL Transitions shader is ported into the engine
/// (`LayeredTransitions.kt`, which credits each beside its port). A port added
/// there adds its author here.
const List<String> kGlTransitionsAuthors = [
  'rectalogic (CrossZoom, ported by gre)',
  'gre (cube)',
  'Thibaut Foussard (DirectionalScaled)',
  'OllyOllyOlly (splitSlideInHorizontal, splitSlideOutHorizontal, zoomInOut)',
  'Adrian Purser (Bounce)',
  'Sergey Kosarevsky (Swirl, DefocusBlur)',
  'Mark Craig (RotateScaleVanish)',
  'Zeh Fernando (DreamyZoom)',
  'chenkai (tangentMotionBlur)',
  'Ben Zhang (Overexposure)',
  'Anastasia Dunbar (FilmBurn)',
  'Gunnar Roth (GlitchMemories, based on work from natewave)',
  'mernking (old_tv_lost_signal)',
  'Ben Lucas (StaticFade)',
  'bread (StripDatamoshGlitch, Drop_Zone_Flicker, Revolve_Left)',
  'Matt DesLauriers (GlitchDisplace)',
];

const String _mitText = '''
MIT License

Copyright (c) 2017-present gl-transitions contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.''';

bool _registered = false;

/// Puts the notices for code the app ships but no package declares on
/// Flutter's licences page — today the ported transitions, whose shaders are
/// compiled into the app while the credit beside them in the source is not.
/// Packages from pub list themselves. Safe to call more than once.
void registerThirdPartyLicences() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() => Stream.value(
        LicenseEntryWithLineBreaks(
          const [kGlTransitionsPackage],
          'Transitions ported from https://github.com/gl-transitions/gl-transitions, '
          'each modified for this app.\n\n'
          '${kGlTransitionsAuthors.join('\n')}\n\n$_mitText',
        ),
      ));
}

/// Opens the licences page on the app's root navigator — over the home tabs'
/// floating nav rather than under it, as every account sheet opens.
Future<void> openSourceLicences(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      builder: (_) => const LicensePage(applicationName: 'SlimShot'),
    ),
  );
}
