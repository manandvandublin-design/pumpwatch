import 'package:flutter/material.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import 'station_screen.dart';

class CheapestScreen extends StatefulWidget {
  const CheapestScreen({super.key});
  @override
  State<CheapestScreen> createState() => _CheapestScreenState();
}

class _CheapestScreenState extends State<CheapestScreen> {
  String sort = 'price';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final list = List<Station>.from(app.priced);
        final f = app.fuel;
        if (sort == 'distance') {
          list.sort((a, b) => (a.distanceKm ?? 0).compareTo(b.distanceKm ?? 0));
        } else if (sort == 'fresh') {
          list.sort((a, b) =>
              b.priceFor(f, app.maxAgeDays)!.reportedAt.compareTo(a.priceFor(f, app.maxAgeDays)!.reportedAt));
        }
        final cheapestId = app.cheapest?.id;
        final unpriced = app.stations.length - app.priced.length;

        Widget sortChip(String key, String label) => ChoiceChip(
              label: Text(label),
              selected: sort == key,
              showCheckmark: false,
              onSelected: (_) => setState(() => sort = key),
              selectedColor: ink,
              backgroundColor: Colors.white,
              side: BorderSide(color: sort == key ? ink : line),
              labelStyle: TextStyle(color: sort == key ? Colors.white : ink, fontWeight: FontWeight.w600),
              shape: const StadiumBorder(),
            );

        return RefreshIndicator(
          onRefresh: () => app.refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            children: [
              Text('Cheapest ${f == 'petrol' ? 'petrol' : 'diesel'}', style: titleStyle),
              const SizedBox(height: 12),
              FuelChips(value: f, onChanged: app.setFuel),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                sortChip('price', 'Price'),
                sortChip('distance', 'Distance'),
                sortChip('fresh', 'Freshest'),
              ]),
              const SizedBox(height: 12),
              if (app.error != null)
                Card2(child: Text(app.error!, style: const TextStyle(color: muted)))
              else if (list.isEmpty)
                const Card2(
                  child: Text('No prices within your search area yet.', style: TextStyle(color: muted)),
                ),
              for (var i = 0; i < list.length; i++) ...[
                _row(context, i + 1, list[i], list[i].id == cheapestId),
                const SizedBox(height: 10),
              ],
              if (unpriced > 0)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF8C877E)),
                  ),
                  child: Text(
                    '$unpriced more station${unpriced == 1 ? '' : 's'} nearby with no recent $f price.',
                    style: const TextStyle(color: muted),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(BuildContext context, int rank, Station s, bool isCheapest) {
    final p = s.priceFor(app.fuel, app.maxAgeDays)!;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StationScreen(station: s))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFFEFECE6),
              child: Text('$rank', style: const TextStyle(color: ink, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                Text('${km(s.distanceKm)} · ${sourceLabel(p.source)} · ${ago(p.reportedAt)}',
                    style: const TextStyle(fontSize: 13, color: muted)),
              ]),
            ),
            Text(euro(p.price),
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: isCheapest ? cheap : ink)),
          ]),
        ),
      ),
    );
  }
}
