import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_ui/sg_ui.dart';

import 'harness.dart';

/// Every component, both platforms, normal and 1.3x text: no overflow or
/// layout exceptions (frontend plan §4.4, §8).
Widget _gallery() {
  return SgScaffold(
    topBar: SgTopBar(
      title: 'Gallery',
      subtitle: 'Sat, 24-10-2026 · 10:42 AM',
      largeTitle: true,
      leading: SgLeading.back,
      leadingLabel: 'Back',
      onLeading: () {},
      actions: [SgBarAction(icon: SgIcons.more, label: 'More', onTap: () {})],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SgBanner(
          kind: SgBannerKind.warning,
          title: 'Last backup 8 days ago',
          message: 'Back up now so a lost phone does not lose records.',
        ),
        const SizedBox(height: 12),
        const SgStepper(current: 2, total: 6),
        const SizedBox(height: 12),
        const SgFlowSteps(labels: ['Details', 'Notice', 'Face'], current: 2),
        const SizedBox(height: 12),
        const Row(
          children: [
            Expanded(
              child: SgStatCard(
                dot: SgColors.successFill,
                label: 'Present',
                value: '21',
                caption: 'of 24 expected',
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: SgStatCard(
                dot: SgColors.warningIcon,
                label: 'On premises',
                value: '20',
                caption: '1 went OUT',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SgChoiceChips<int>(
          options: const [
            SgOption(value: 0, label: 'All 25'),
            SgOption(value: 1, label: 'Not in 6'),
            SgOption(value: 2, label: 'Needs face 1'),
          ],
          selected: 0,
          onSelected: (_) {},
        ),
        const SizedBox(height: 12),
        SgSelectRow(
          title: 'हिन्दी',
          subtitle: 'Hindi',
          selected: true,
          onTap: () {},
        ),
        const SizedBox(height: 12),
        SgSection(
          header: 'Worker',
          children: [
            const SgTextField(label: 'Full name'),
            SgSelectField<int>(
              label: 'Department',
              options: const [SgOption(value: 1, label: 'Stitching')],
              value: 1,
              onChanged: (_) {},
            ),
            const SgFieldNote('✓ Age 28 — must be 18 or older to enrol'),
          ],
        ),
        const SizedBox(height: 12),
        SgCardList(
          children: [
            SgSwitchRow(
              title: 'Auto backup to Google Drive',
              subtitle: 'when online',
              value: true,
              onChanged: (_) {},
            ),
            const SgListRow(
              title: 'Licence',
              trailingText: 'Active · to 24-10-2027',
            ),
            const SgListRow(title: 'Report phone lost', danger: true),
          ],
        ),
        const SizedBox(height: 12),
        SgSegmented<int>(
          selected: 1,
          onChanged: (_) {},
          options: const [
            SgOption(value: 0, label: 'Owner'),
            SgOption(value: 1, label: 'Admin'),
            SgOption(value: 2, label: 'Gate operator'),
          ],
        ),
        const SizedBox(height: 12),
        const SgCheckRow(value: true, onChanged: _noop, title: 'I agree'),
        const SizedBox(height: 12),
        SgButton(label: 'Continue · आगे बढ़ें', onPressed: () {}),
        const SizedBox(height: 8),
        SgButton(
          label: 'Check again',
          kind: SgButtonKind.secondary,
          onPressed: () {},
        ),
        const SizedBox(height: 8),
        SgButton(
          label: 'Start gate mode',
          kind: SgButtonKind.brand,
          icon: SgIcons.faceScan,
          onPressed: () {},
        ),
        const SizedBox(height: 12),
        const SgStatusTag(
          label: 'MISSING OUT',
          background: SgColors.warningBg,
          foreground: SgColors.warningText,
        ),
      ],
    ),
  );
}

void _noop(bool value) {}

void main() {
  for (final platform in platforms) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('gallery renders on ${platform.name} at ${scale}x', (
        tester,
      ) async {
        await pumpSg(tester, _gallery(), platform: platform, textScale: scale);
        await tester.pumpAndSettle();
      });
    }
  }

  testWidgets('tap targets are at least 48 and labelled', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpSg(
      tester,
      SgScaffold(
        topBar: SgTopBar(
          title: 'Settings',
          leading: SgLeading.back,
          leadingLabel: 'Back',
          onLeading: () {},
        ),
        body: Center(
          child: SgButton(label: 'Save', onPressed: () {}),
        ),
      ),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
