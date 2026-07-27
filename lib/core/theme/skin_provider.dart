import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme_provider.dart' show sharedPreferencesProvider;

// ---------------------------------------------------------------------------
// FEATURE (#27): Skin themes.
//
// A skin is an accent pair applied on top of the current appearance mode
// (Light / Dark / AMOLED): `accent` for light surfaces, `accentBright`
// for dark ones. Scarlet is the exact current brand accent, so the default
// look is pixel-identical to before this feature existed.
//
// Precedence: Material You (wallpaper colors), when enabled, overrides the
// skin — picking a skin from the Skin Themes screen therefore switches
// Material You off so the choice is always visible.
// ---------------------------------------------------------------------------

enum OrvoSkin {
  scarlet('Scarlet', Color(0xFFFA233B), Color(0xFFFF5C74)), // brand default
  ocean('Ocean', Color(0xFF2E6BE6), Color(0xFF6B97FF)),
  violet('Violet', Color(0xFF7A3BE6), Color(0xFFA97BFF)),
  teal('Teal', Color(0xFF0E8F94), Color(0xFF3FC1C6)),
  emerald('Emerald', Color(0xFF1F9D57), Color(0xFF4CC98A)),
  gold('Gold', Color(0xFFC98A1B), Color(0xFFF0B44C)),
  rose('Rose', Color(0xFFD6336C), Color(0xFFF06595)),
  ember('Ember', Color(0xFFE8590C), Color(0xFFFF8A5C)),
  steel('Steel', Color(0xFF5C7599), Color(0xFF8FA8CC)),
  forest('Forest', Color(0xFF41703F), Color(0xFF7BA878));

  const OrvoSkin(this.label, this.accent, this.accentBright);

  final String label;

  /// Primary accent on light surfaces.
  final Color accent;

  /// Lifted accent for dark / AMOLED surfaces.
  final Color accentBright;
}

const _kSkinKey = 'orvo.skin';

class SkinNotifier extends Notifier<OrvoSkin> {
  @override
  OrvoSkin build() {
    final stored = ref.read(sharedPreferencesProvider).getString(_kSkinKey);
    return OrvoSkin.values.firstWhere(
      (s) => s.name == stored,
      orElse: () => OrvoSkin.scarlet,
    );
  }

  void set(OrvoSkin skin) {
    state = skin;
    ref.read(sharedPreferencesProvider).setString(_kSkinKey, skin.name);
  }
}

final skinProvider = NotifierProvider<SkinNotifier, OrvoSkin>(SkinNotifier.new);
