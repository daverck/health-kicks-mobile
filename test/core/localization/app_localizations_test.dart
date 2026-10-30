import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/core/localization/app_localizations.dart';

void main() {
  group('AppLocalizations - Translations Suite for 7 Languages', () {
    const supportedCodes = ['fr', 'en', 'nl', 'es', 'de', 'ar', 'zh'];

    test('Delegate supports exactly the 7 frontend languages', () {
      const delegate = AppLocalizations.delegate;
      for (final code in supportedCodes) {
        expect(delegate.isSupported(Locale(code)), isTrue);
      }
      expect(delegate.isSupported(const Locale('it')), isFalse);
      expect(delegate.isSupported(const Locale('pt')), isFalse);
    });

    test('Each of the 7 languages translates fall types without raw fallbacks', () {
      final fallTypes = [
        'fall_forward',
        'fall_backward',
        'fall_lateral',
        'fall_recovery',
        'stand_up',
        'lie_down',
        'lying_supine',
        'lying_prone',
        'lying_lateral',
        'fall_generic',
        'fall_detected',
        'free_fall',
      ];

      for (final code in supportedCodes) {
        final l10n = AppLocalizations(Locale(code));
        for (final fall in fallTypes) {
          final translated = l10n.translateEventType(fall);
          expect(translated, isNotEmpty, reason: 'Failed for $fall in $code');
          expect(translated, isNot(fall), reason: 'Unmapped raw key for $fall in $code');
        }
      }
    });

    test('Specific fall translations match expected terms', () {
      final fr = AppLocalizations(const Locale('fr'));
      expect(fr.translateEventType('fall_forward'), 'Chute avant');
      expect(fr.translateEventType('fall_backward'), 'Chute arrière');
      expect(fr.translateEventType('fall_lateral'), 'Chute latérale');
      expect(fr.translateEventType('fall_recovery'), 'Chute relevée');
      expect(fr.translateEventType('stand_up'), 'Relevage après chute');

      final en = AppLocalizations(const Locale('en'));
      expect(en.translateEventType('fall_forward'), 'Forward fall');
      expect(en.translateEventType('fall_backward'), 'Backward fall');
      expect(en.translateEventType('fall_lateral'), 'Lateral fall');
      expect(en.translateEventType('fall_recovery'), 'Recovered fall');
      expect(en.translateEventType('stand_up'), 'Standing up');

      final nl = AppLocalizations(const Locale('nl'));
      expect(nl.translateEventType('fall_forward'), 'Val voorover');
      expect(nl.translateEventType('fall_backward'), 'Val achterover');

      final es = AppLocalizations(const Locale('es'));
      expect(es.translateEventType('fall_forward'), 'Caída frontal');
      expect(es.translateEventType('fall_backward'), 'Caída hacia atrás');

      final de = AppLocalizations(const Locale('de'));
      expect(de.translateEventType('fall_forward'), 'Sturz vorwärts');
      expect(de.translateEventType('fall_backward'), 'Sturz rückwärts');

      final ar = AppLocalizations(const Locale('ar'));
      expect(ar.translateEventType('fall_forward'), 'سقوط إلى الأمام');
      expect(ar.translateEventType('fall_backward'), 'سقوط إلى الخلف');

      final zh = AppLocalizations(const Locale('zh'));
      expect(zh.translateEventType('fall_forward'), '向前跌倒');
      expect(zh.translateEventType('fall_backward'), '向后跌倒');
    });

    test('Interpolates placeholders in translations correctly', () {
      final fr = AppLocalizations(const Locale('fr'));
      expect(fr.inactivityThreshold(45), 'Durée avant alerte : 45 minutes');
      expect(fr.inactivityCooldown(10), 'Délai de répétition : 10 minutes');

      final en = AppLocalizations(const Locale('en'));
      expect(en.inactivityThreshold(45), 'Duration before alert: 45 minutes');
      expect(en.inactivityCooldown(10), 'Repeat delay: 10 minutes');
    });
  });
}

