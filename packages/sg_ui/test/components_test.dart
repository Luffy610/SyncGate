import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_ui/sg_ui.dart';

import 'harness.dart';

void main() {
  group('SgButton', () {
    for (final platform in platforms) {
      testWidgets('uses the ${platform.name} height and calls onPressed', (
        tester,
      ) async {
        var taps = 0;
        await pumpSg(
          tester,
          SgScaffold(
            body: Center(
              child: SgButton(label: 'Continue', onPressed: () => taps++),
            ),
          ),
          platform: platform,
        );

        final box = find.ancestor(
          of: find.text('Continue'),
          matching: find.byType(DecoratedBox),
        );
        final height = tester.getSize(box.first).height;
        expect(height, platform == TargetPlatform.iOS ? 50 : 48);

        await tester.tap(find.text('Continue'));
        expect(taps, 1);
      });
    }

    testWidgets('disabled button ignores taps', (tester) async {
      await pumpSg(
        tester,
        const SgScaffold(
          body: Center(child: SgButton(label: 'Save', onPressed: null)),
        ),
      );
      await tester.tap(find.text('Save'), warnIfMissed: false);
      expect(find.text('Save'), findsOneWidget);
    });
  });

  group('SgTopBar', () {
    testWidgets('iOS large title shows leading label and action', (
      tester,
    ) async {
      var back = 0;
      await pumpSg(
        tester,
        SgScaffold(
          topBar: SgTopBar(
            title: 'Exceptions',
            largeTitle: true,
            leading: SgLeading.back,
            leadingLabel: 'Today',
            onLeading: () => back++,
          ),
          body: const SizedBox(),
        ),
        platform: TargetPlatform.iOS,
      );
      expect(find.text('Exceptions'), findsOneWidget);
      await tester.tap(find.text('Today'));
      expect(back, 1);
    });

    testWidgets('Android shows the back arrow with a semantic label', (
      tester,
    ) async {
      await pumpSg(
        tester,
        SgScaffold(
          topBar: SgTopBar(
            title: 'Exceptions',
            leading: SgLeading.back,
            leadingLabel: 'Back',
            onLeading: () {},
          ),
          body: const SizedBox(),
        ),
      );
      expect(find.byIcon(SgIcons.back), findsOneWidget);
      expect(find.bySemanticsLabel('Back'), findsOneWidget);
    });

    testWidgets('primary action is a FAB on Android, "+" on iOS', (
      tester,
    ) async {
      Widget build() => SgScaffold(
        topBar: const SgTopBar(title: 'Workers', largeTitle: true),
        primaryAction: SgPrimaryActionSpec(label: 'Enrol worker', onTap: () {}),
        body: const SizedBox(),
      );
      await pumpSg(tester, build());
      expect(find.text('Enrol worker'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);

      await pumpSg(tester, build(), platform: TargetPlatform.iOS);
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byIcon(SgIcons.add), findsOneWidget);
    });
  });

  group('SgNavBar', () {
    for (final platform in platforms) {
      testWidgets('selects tabs on ${platform.name}', (tester) async {
        var selected = 0;
        await pumpSg(
          tester,
          StatefulBuilder(
            builder: (context, setState) => SgScaffold(
              body: const SizedBox(),
              bottom: SgNavBar(
                selectedIndex: selected,
                onSelected: (i) => setState(() => selected = i),
                items: const [
                  SgNavItem(
                    icon: SgIcons.home,
                    activeIcon: SgIcons.homeActive,
                    label: 'Today',
                  ),
                  SgNavItem(
                    icon: SgIcons.people,
                    activeIcon: SgIcons.peopleActive,
                    label: 'Workers',
                  ),
                ],
              ),
            ),
          ),
          platform: platform,
        );
        await tester.tap(find.text('Workers'));
        await tester.pump();
        expect(selected, 1);
        expect(find.byIcon(SgIcons.peopleActive), findsOneWidget);
      });
    }
  });

  group('inputs', () {
    testWidgets('SgSelectField opens the picker and returns the choice', (
      tester,
    ) async {
      String? chosen;
      await pumpSg(
        tester,
        SgScaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: SgSelectField<String>(
              label: 'Department',
              value: 'a',
              options: const [
                SgOption(value: 'a', label: 'Stitching'),
                SgOption(value: 'b', label: 'Packing'),
              ],
              onChanged: (v) => chosen = v,
            ),
          ),
        ),
      );
      expect(find.text('Stitching'), findsOneWidget);
      await tester.tap(find.text('Stitching'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Packing'));
      await tester.pumpAndSettle();
      expect(chosen, 'b');
    });

    testWidgets('SgSwitch toggles', (tester) async {
      var on = false;
      await pumpSg(
        tester,
        StatefulBuilder(
          builder: (context, setState) => SgScaffold(
            body: Center(
              child: SgSwitch(
                value: on,
                semanticLabel: 'Fill light',
                onChanged: (v) => setState(() => on = v),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(SgSwitch));
      await tester.pump(const Duration(milliseconds: 300));
      expect(on, isTrue);
    });

    testWidgets('SgSegmented reports the tapped option', (tester) async {
      var value = 'owner';
      await pumpSg(
        tester,
        StatefulBuilder(
          builder: (context, setState) => SgScaffold(
            body: SgSegmented<String>(
              selected: value,
              onChanged: (v) => setState(() => value = v),
              options: const [
                SgOption(value: 'owner', label: 'Owner'),
                SgOption(value: 'admin', label: 'Admin'),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Admin'));
      await tester.pump();
      expect(value, 'admin');
    });

    testWidgets('iOS section draws field notes below the card', (tester) async {
      await pumpSg(
        tester,
        const SgScaffold(
          body: SgSection(
            header: 'Worker',
            children: [
              SgTextField(label: 'Full name'),
              SgFieldNote('Age 28'),
            ],
          ),
        ),
        platform: TargetPlatform.iOS,
      );
      final card = tester.getRect(find.byType(SgCardList));
      final note = tester.getRect(find.text('Age 28'));
      expect(note.top, greaterThanOrEqualTo(card.bottom));
    });
  });

  testWidgets('SgPinPad emits digits and backspace', (tester) async {
    final digits = <int>[];
    var back = 0;
    await pumpSg(
      tester,
      SgScaffold(
        body: Center(
          child: SgPinPad(
            onDigit: digits.add,
            onBackspace: () => back++,
            backspaceLabel: 'Delete',
          ),
        ),
      ),
    );
    await tester.tap(find.text('7'));
    await tester.tap(find.text('0'));
    await tester.tap(find.bySemanticsLabel('Delete'));
    expect(digits, [7, 0]);
    expect(back, 1);
  });

  testWidgets('time picker steps hours and minutes', (tester) async {
    int? result;
    await pumpSg(
      tester,
      Builder(
        builder: (context) => SgScaffold(
          body: Center(
            child: SgButton(
              label: 'Open',
              onPressed: () async {
                result = await showSgTimePicker(
                  context,
                  title: 'OUT time',
                  initialMinute: 14 * 60 + 5,
                  confirmLabel: 'Set',
                  cancelLabel: 'Cancel',
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('hour up'));
    await tester.tap(find.bySemanticsLabel('minute down'));
    await tester.pump();
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();
    expect(result, 15 * 60 + 4);
  });

  test('avatar initials', () {
    expect(SgAvatarInitials.initialsOf('Mohd. Irfan'), 'MI');
    expect(SgAvatarInitials.initialsOf('Lakshmi M.'), 'LM');
    expect(SgAvatarInitials.initialsOf('Priya'), 'P');
  });
}
