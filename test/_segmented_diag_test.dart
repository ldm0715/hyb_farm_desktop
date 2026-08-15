import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyb_farm_desktop/theme/farm_theme.dart';
import 'package:hyb_farm_desktop/ui/warehouse_segmented_control.dart';

void main() {
  testWidgets('segmented isolated', (tester) async {
    await tester.binding.setSurfaceSize(const Size(560, 300));
    bool v = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Column(
              children: [
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: WarehouseSegmentedControl(
                    selected: v,
                    onChanged: (next) => setState(() => v = next),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byType(WarehouseSegmentedControl),
      matchesGoldenFile('segmented_diag.png'),
    );
  });
}
