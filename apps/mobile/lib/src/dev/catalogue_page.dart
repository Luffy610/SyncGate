import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_ui/sg_ui.dart';
import 'package:syncgate/src/app/providers.dart';

/// Dev-only component catalogue (frontend plan §4.4): every `sg_ui` piece on
/// one page, drawn for the current look. Switch the look in the debug panel.
class CataloguePage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<CataloguePage> createState() => _CataloguePageState();
}

class _CataloguePageState extends ConsumerState<CataloguePage> {
  var _chip = 0;
  var _switch = true;
  var _segment = 1;
  var _row = 0;
  var _check = false;

  @override
  Widget build(BuildContext context) {
    final platform = ref.watch(platformProvider);
    return SgScaffold(
      topBar: SgTopBar(
        title: 'Catalogue · ${platform.name}',
        leading: SgLeading.back,
        leadingLabel: 'Back',
        onLeading: () => Navigator.of(context).pop(),
      ),
      body: SgScrollColumn(
        padding: EdgeInsets.all(context.sg.gutter),
        children: [
          const SgBanner(
            kind: SgBannerKind.warning,
            title: 'Last backup 8 days ago',
            message: 'Back up now so a lost phone does not lose records.',
          ),
          const SizedBox(height: 12),
          const SgBanner(
            kind: SgBannerKind.info,
            title: 'Free trial · 30 days',
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
                  dot: SgColors.infoText,
                  label: 'On premises',
                  value: '20',
                  caption: '1 went OUT',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final kind in SgButtonKind.values) ...[
            if (kind == SgButtonKind.onColor ||
                kind == SgButtonKind.onColorOutline ||
                kind == SgButtonKind.gateOutline)
              Container(
                color: SgColors.danger,
                padding: const EdgeInsets.all(8),
                child: SgButton(label: kind.name, kind: kind, onPressed: () {}),
              )
            else
              SgButton(label: kind.name, kind: kind, onPressed: () {}),
            const SizedBox(height: 8),
          ],
          SgChoiceChips<int>(
            selected: _chip,
            onSelected: (v) => setState(() => _chip = v),
            options: const [
              SgOption(value: 0, label: 'All 25'),
              SgOption(value: 1, label: 'Not in 6'),
              SgOption(value: 2, label: 'Needs face 1'),
            ],
          ),
          const SizedBox(height: 12),
          SgSegmented<int>(
            selected: _segment,
            onChanged: (v) => setState(() => _segment = v),
            options: const [
              SgOption(value: 0, label: 'Owner'),
              SgOption(value: 1, label: 'Admin'),
              SgOption(value: 2, label: 'Gate operator'),
            ],
          ),
          const SizedBox(height: 12),
          SgSelectRow(
            title: 'हिन्दी',
            subtitle: 'Hindi',
            selected: _row == 0,
            onTap: () => setState(() => _row = 0),
          ),
          const SizedBox(height: 8),
          SgSelectRow(
            title: 'English',
            subtitle: 'English',
            selected: _row == 1,
            onTap: () => setState(() => _row = 1),
          ),
          const SizedBox(height: 12),
          SgCheckRow(
            value: _check,
            onChanged: (v) => setState(() => _check = v),
            title: 'I agree',
            subtitle: 'Worker has heard this notice',
          ),
          const SizedBox(height: 12),
          SgSection(
            header: 'Worker',
            children: [
              const SgTextField(label: 'Full name'),
              SgSelectField<int>(
                label: 'Department',
                value: 1,
                options: const [SgOption(value: 1, label: 'Stitching')],
                onChanged: (_) {},
              ),
              const SgFieldNote('✓ Age 28 — must be 18 or older to enrol'),
            ],
          ),
          SgCardList(
            children: [
              SgSwitchRow(
                title: 'Auto backup',
                subtitle: 'when online',
                value: _switch,
                onChanged: (v) => setState(() => _switch = v),
              ),
              const SgListRow(title: 'Licence', trailingText: 'Active'),
              const SgListRow(title: 'Report phone lost', danger: true),
            ],
          ),
          const SizedBox(height: 12),
          const Wrap(
            spacing: 8,
            children: [
              SgStatusTag(
                label: 'MISSING OUT',
                background: SgColors.warningBg,
                foreground: SgColors.warningText,
              ),
              SgStatusTag(
                label: 'MANUAL',
                background: SgColors.infoBg,
                foreground: SgColors.infoText,
              ),
              SgStatusTag(
                label: 'CLOCK',
                background: SgColors.dangerTint,
                foreground: SgColors.danger,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              SgAvatarInitials(name: 'Ramesh Kumar'),
              SizedBox(width: 12),
              SgLogo(),
            ],
          ),
        ],
      ),
    );
  }
}
