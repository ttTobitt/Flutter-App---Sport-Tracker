import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// Kurzanleitung: Tracker bedienen, Einheiten übertragen, Platz.
/// Gedacht für Mitspieler, die den Tracker zum ersten Mal benutzen.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hilfe')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: const [
          _Section(
            title: 'Tracker einschalten',
            items: [
              _Item(
                Icons.battery_charging_full,
                'Akku anstecken. Nach ca. 5 s vibriert der Tracker kurz: bereit.',
              ),
              _Item(
                Icons.usb,
                'Passiert nichts, den Tracker einmal kurz per USB-C anstecken.',
              ),
              _Item(
                Icons.electrical_services,
                'Laden über USB-C. Den Akkustand siehst du auf der Startseite, wenn der Tracker verbunden ist.',
              ),
            ],
          ),
          _Section(
            title: 'Training aufzeichnen',
            items: [
              _Item(
                Icons.play_arrow,
                'SW1 drücken: Aufzeichnung startet, der Tracker vibriert kurz.',
              ),
              _Item(
                Icons.satellite_alt,
                'Gespeichert wird ab dem ersten GPS-Empfang. Im Freien dauert das meist 30 s bis 2 min, am besten schon vor dem Training starten.',
              ),
              _Item(
                Icons.stop,
                'SW1 nochmal drücken: Aufzeichnung endet, der Tracker vibriert lang.',
              ),
              _Item(
                Icons.warning_amber,
                'Vibriert er 1 s lang ohne Drücken, ist der Speicher voll. Dann zuerst übertragen.',
              ),
            ],
          ),
          _Section(
            title: 'Einheiten übertragen',
            items: [
              _Item(
                Icons.location_on_outlined,
                'Am Handy Bluetooth und Standort einschalten. Android braucht den Standort für die Bluetooth-Suche.',
              ),
              _Item(
                Icons.bluetooth,
                'Startseite → „Tracker verbinden“ → „Sporttracker“ antippen → „Übertragen“.',
              ),
              _Item(
                Icons.verified_outlined,
                'Am Tracker gelöscht wird eine Einheit erst, wenn sie vollständig in der App ist. Bricht die Verbindung ab, einfach nochmal übertragen.',
              ),
            ],
          ),
          _Section(
            title: 'Fußballplatz',
            items: [
              _Item(
                Icons.sports_soccer,
                'Der Platz wird automatisch erkannt (alle Plätze in Österreich sind in der App gespeichert).',
              ),
              _Item(
                Icons.search,
                'Falscher oder kein Platz? In der Einheit „Platz auswählen“ oder bei „Platz anpassen“ die Lupe: Plätze in der Nähe oder Suche nach Verein und Ort.',
              ),
              _Item(
                Icons.open_with,
                '„Von Hand festlegen“: Luftbild verschieben und drehen, bis die gelben Linien auf dem Platz liegen.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<_Item> items;
  const _Section({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(title),
            const SizedBox(height: 10),
            for (final item in items) item,
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Item(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.pitch),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
