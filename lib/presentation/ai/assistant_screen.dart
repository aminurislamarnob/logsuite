import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ai/ai_action.dart';
import '../../core/ai/ai_provider.dart';
import '../../core/ai/ai_providers.dart';
import '../../core/services/security_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import 'assistant_controller.dart';
import 'widgets/action_preview_card.dart';
import 'widgets/document_source_sheet.dart';

/// The one place to say what you want added, whichever module it lands in.
///
/// Every state of a command has a screen of its own here: recording, an
/// editable transcript, thinking, the preview cards, and what was saved.
/// The mic is the default path and goes straight from stop to the model;
/// "Type instead" covers a quiet room and "Scan" a receipt.
class AssistantScreen extends ConsumerStatefulWidget {
  /// Text to start from instead of the microphone.
  final String? initialTranscript;

  /// Open straight into a scan: true for the camera, false for the gallery.
  final bool? scanFromCamera;

  const AssistantScreen({
    super.key,
    this.initialTranscript,
    this.scanFromCamera,
  });

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _transcript = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = ref.read(assistantControllerProvider.notifier);
      controller.unlockGate = _unlock;
      final initial = widget.initialTranscript;
      final scan = widget.scanFromCamera;
      if (initial != null && initial.trim().isNotEmpty) {
        controller.editTranscript(initial);
        controller.typeInstead();
      } else if (scan != null) {
        controller.scanDocument(fromCamera: scan);
      }
    });
  }

  @override
  void dispose() {
    _transcript.dispose();
    super.dispose();
  }

  /// The same sequence `ModuleLockGate` runs: biometrics, then the PIN.
  Future<bool> _unlock(Set<AppModule> modules) async {
    final security = ref.read(securityServiceProvider);
    final label = modules.map((m) => m.label).join(', ');
    if (await security.authenticate(reason: 'Unlock $label')) return true;
    if (!mounted || !security.hasPin) return false;
    return promptForPin(context, security.verifyPin, title: 'Unlock $label');
  }

  void _record(AssistantController controller) {
    controller.startListening();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assistantControllerProvider);
    final controller = ref.read(assistantControllerProvider.notifier);
    final brand = context.brand;
    final isListening = state is AssistantListening;

    final scaffold = BrandScaffold(
      header: isListening
          ? SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  8,
                  AppSpacing.gutter,
                  8,
                ),
                child: Row(
                  children: [
                    CircleIconButton(
                      icon: AppIcons.close,
                      tooltip: 'Back',
                      onInk: true,
                      onPressed: () {
                        controller.cancelListening();
                        Navigator.maybePop(context);
                      },
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Assistant',
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                            ),
                      ),
                    ),
                    const _SourceBadge(onInk: true),
                    const SizedBox(width: 8),
                    CircleIconButton(
                      icon: AppIcons.settings,
                      tooltip: 'AI settings',
                      onInk: true,
                      onPressed: () => context.go('/settings'),
                    ),
                  ],
                ),
              ),
            )
          : BrandTopBar(
              title: 'Assistant',
              leadingIcon: AppIcons.close,
              actions: [
                if (state is AssistantPreview)
                  _SourceBadge(source: state.result.source),
                CircleIconButton(
                  icon: AppIcons.settings,
                  tooltip: 'AI settings',
                  size: 44,
                  onPressed: () => context.go('/settings'),
                ),
              ],
            ),
      child: switch (state) {
        AssistantIdle() => _Idle(onListen: () => _record(controller)),
        AssistantListening s => _Listening(
          state: s,
          onStop: controller.stopListening,
          onCancel: controller.cancelListening,
          onTypeInstead: controller.typeInstead,
          onScanInstead: () => _scan(context, ref),
        ),
        AssistantTranscript s => _Transcript(
          controller: _transcript..text = s.text,
          onChanged: controller.editTranscript,
          onListen: () => _record(controller),
          onSend: controller.submit,
        ),
        AssistantThinking s => _Thinking(transcript: s.transcript),
        AssistantPreview s => _Preview(state: s),
        AssistantSaving() => const _Thinking(transcript: null, saving: true),
        AssistantSaved s => _Saved(state: s, onAnother: controller.discard),
        AssistantFailure s => _Failure(state: s),
      },
    );

    if (!isListening) return scaffold;
    return Theme(
      data: Theme.of(context).copyWith(scaffoldBackgroundColor: brand.inkDeep),
      child: ColoredBox(color: brand.inkDeep, child: scaffold),
    );
  }
}

// --- Shared bits -----------------------------------------------------------

/// Says which parser will answer, so nobody wonders where the words went.
class _SourceBadge extends ConsumerWidget {
  final AiSource? source;
  final bool onInk;

  const _SourceBadge({this.source, this.onInk = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brand = context.brand;
    const offline = OfflineSource();
    final String label =
        source?.label ??
        ref
            .watch(aiClientProvider)
            .when<String>(
              data: (client) => client == null
                  ? offline.label
                  : '${client.provider.label} · ${client.model}',
              loading: () => '…',
              error: (_, _) => offline.label,
            );

    final isOffline = label == offline.label;
    final dotColor = isOffline
        ? context.muted
        : (onInk ? brand.successRoles.onInk : brand.success);

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: ShapeDecoration(
        color: onInk ? Colors.white.withValues(alpha: 0.08) : brand.surface,
        shape: const StadiumBorder(),
        shadows: onInk ? const [] : AppShadows.circleButton(theme.brightness),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: onInk ? Colors.white : context.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _MicButton extends ConsumerWidget {
  final bool live;
  final VoidCallback onPressed;

  const _MicButton({required this.live, required this.onPressed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final coral = brand.medicineRoles.onInk;
    final fill = live ? coral : brand.medicine;
    final fg = live ? brand.inkDeep : Colors.white;
    final reduceMotion = ref.watch(settingsProvider).reduceMotion;
    final size = live ? 108.0 : 88.0;

    Widget button = BrandTappable(
      onPressed: onPressed,
      semanticsLabel: live ? 'Stop listening' : 'Start listening',
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: fill,
          shape: const CircleBorder(),
          shadows: live
              ? [
                  BoxShadow(
                    color: coral.withValues(alpha: 0.16),
                    spreadRadius: 12,
                    blurRadius: 0,
                  ),
                  BoxShadow(
                    color: coral.withValues(alpha: 0.07),
                    spreadRadius: 26,
                    blurRadius: 0,
                  ),
                ]
              : [
                  BoxShadow(
                    color: fill.withValues(alpha: 0.3),
                    blurRadius: 18,
                    spreadRadius: -2,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: AppIcon(AppIcons.mic, color: fg, size: live ? 40 : 38),
        ),
      ),
    );
    if (live && !reduceMotion) {
      button = button
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scale(
            begin: const Offset(1, 1),
            end: const Offset(1.04, 1.04),
            duration: 900.ms,
            curve: Curves.easeInOut,
          );
    }
    return button;
  }
}

/// Live sound level waveform bars above the mic button (38-assistant-listening.html).
class _SoundLevelWave extends StatelessWidget {
  final double level;

  const _SoundLevelWave({required this.level});

  static const _baseHeights = <double>[
    14,
    26,
    18,
    40,
    30,
    56,
    44,
    68,
    36,
    60,
    48,
    24,
    52,
    34,
    44,
    20,
    30,
    12,
  ];

  @override
  Widget build(BuildContext context) {
    final coral = context.brand.medicineRoles.onInk;
    final scale = 0.45 + 0.55 * level.clamp(0.0, 1.0);
    return SizedBox(
      height: 72,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final (i, h) in _baseHeights.indexed) ...[
            if (i > 0) const SizedBox(width: 5),
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 5,
              height: math.max(8, h * scale),
              decoration: BoxDecoration(
                color: (i >= 5 && i <= 12)
                    ? coral
                    : coral.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  final List<Widget> children;

  const _Centered({required this.children});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: pageInsets(context, top: 16, gutter: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: children,
        ),
      ),
    );
  }
}

// --- States ----------------------------------------------------------------

class _Idle extends StatelessWidget {
  final VoidCallback onListen;

  const _Idle({required this.onListen});

  @override
  Widget build(BuildContext context) {
    final muted = context.muted;
    return _Centered(
      children: [
        const _SourceBadge(),
        const SizedBox(height: 28),
        Text(
          'Say what you want to add',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontSize: 22, letterSpacing: -0.4),
        ),
        const SizedBox(height: 10),
        Text(
          '“Spent 200 taka on lunch with bKash and remind me to call the '
          'doctor at 5.”\nSeveral things in one breath are fine.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: 36),
        _MicButton(live: false, onPressed: onListen),
        const SizedBox(height: 28),
        Consumer(
          builder: (context, ref, _) => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              BrandButton(
                label: 'Type instead',
                kind: BrandButtonKind.outline,
                expand: false,
                onPressed: ref
                    .read(assistantControllerProvider.notifier)
                    .typeInstead,
              ),
              const SizedBox(width: 12),
              BrandButton(
                label: 'Scan instead',
                icon: AppIcons.scan,
                kind: BrandButtonKind.outline,
                expand: false,
                onPressed: () => _scan(context, ref),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Listening extends StatelessWidget {
  final AssistantListening state;
  final VoidCallback onStop;
  final VoidCallback onCancel;
  final VoidCallback onTypeInstead;
  final VoidCallback onScanInstead;

  const _Listening({
    required this.state,
    required this.onStop,
    required this.onCancel,
    required this.onTypeInstead,
    required this.onScanInstead,
  });

  static String _clock(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final coral = brand.medicineRoles.onInk;
    return ColoredBox(
      color: brand.inkDeep,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            10,
            AppSpacing.gutter,
            24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  DecoratedBox(
                        decoration: BoxDecoration(
                          color: coral,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox(width: 8, height: 8),
                      )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .fade(begin: 1, end: 0.2, duration: 800.ms),
                  const SizedBox(width: 8),
                  Text(
                    'LISTENING · ${_clock(state.elapsed)}',
                    style: TextStyle(
                      color: coral,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Say what you want to add',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 132),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      color: state.partial.isEmpty
                          ? brand.onInkMuted
                          : Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                      letterSpacing: -0.2,
                    ),
                    children: [
                      TextSpan(
                        text: state.partial.isEmpty
                            ? 'Listening…'
                            : state.partial,
                      ),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Container(
                          width: 3,
                          height: 22,
                          margin: const EdgeInsets.only(left: 4),
                          decoration: BoxDecoration(
                            color: coral,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (state.notice != null) ...[
                const SizedBox(height: 10),
                Text(
                  state.notice!,
                  style: TextStyle(
                    color: brand.onInkMuted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
              const Spacer(),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SoundLevelWave(level: state.level),
                    const SizedBox(height: 22),
                    _MicButton(live: true, onPressed: onStop),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'TRY SAYING',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: brand.onInkMuted,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _TrySayingPill('“Add Napa 3 times a day for 5 days”'),
                  _TrySayingPill('“Rickshaw 60 cash”'),
                  _TrySayingPill('“Rent Friday 9am”'),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  CircleIconButton(
                    icon: AppIcons.textSize,
                    tooltip: 'Type instead',
                    size: 58,
                    onInk: true,
                    onPressed: () {
                      onCancel();
                      onTypeInstead();
                    },
                  ),
                  const SizedBox(width: 10),
                  CircleIconButton(
                    icon: AppIcons.camera,
                    tooltip: 'Scan instead',
                    size: 58,
                    onInk: true,
                    onPressed: () {
                      onCancel();
                      onScanInstead();
                    },
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: BrandTappable(
                      onPressed: onStop,
                      semanticsLabel: 'Tap to send',
                      child: Container(
                        height: 58,
                        alignment: Alignment.center,
                        decoration: const ShapeDecoration(
                          color: Colors.white,
                          shape: StadiumBorder(),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Tap to send',
                              style: TextStyle(
                                color: brand.inkDeep,
                                fontWeight: FontWeight.w700,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(width: 8),
                            AppIcon(
                              AppIcons.chevronRight,
                              size: 18,
                              color: brand.inkDeep,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrySayingPill extends StatelessWidget {
  final String text;

  const _TrySayingPill(this.text);

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: TextStyle(fontSize: 13, color: brand.onInkMuted)),
        ],
      ),
    );
  }
}

class _Transcript extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onListen;
  final Future<void> Function() onSend;

  const _Transcript({
    required this.controller,
    required this.onChanged,
    required this.onListen,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: pageInsets(context),
      children: [
        const Align(alignment: Alignment.centerLeft, child: _SourceBadge()),
        const SizedBox(height: 16),
        BrandField(
          controller: controller,
          hint: 'Spent 200 taka on lunch with bKash…',
          minLines: 3,
          maxLines: 6,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.newline,
          onChanged: onChanged,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            CircleIconButton(
              icon: AppIcons.mic,
              tooltip: 'Speak instead',
              onPressed: onListen,
            ),
            const SizedBox(width: 8),
            Consumer(
              builder: (context, ref, _) => CircleIconButton(
                icon: AppIcons.scan,
                tooltip: 'Scan document',
                onPressed: () => _scan(context, ref),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: BrandButton(
                label: 'Work it out',
                icon: AppIcons.sparkle,
                onPressed: onSend,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Thinking extends StatelessWidget {
  final String? transcript;
  final bool saving;

  const _Thinking({required this.transcript, this.saving = false});

  @override
  Widget build(BuildContext context) {
    final muted = context.muted;
    return _Centered(
      children: [
        const BrandSpinner(),
        const SizedBox(height: 20),
        Text(
          saving ? 'Saving…' : 'Working out what to add…',
          style: TextStyle(color: muted, fontSize: 14),
        ),
        if (transcript != null) ...[
          const SizedBox(height: 24),
          Text(
            '“$transcript”',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 13, height: 1.4),
          ),
        ],
        if (!saving) ...[const SizedBox(height: 20), const _SourceBadge()],
      ],
    );
  }
}

class _Preview extends ConsumerWidget {
  final AssistantPreview state;

  const _Preview({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brand = context.brand;
    final controller = ref.read(assistantControllerProvider.notifier);
    final muted = context.muted;
    final pending = state.pending.length;
    final savedCount = state.saved.length;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              8,
              AppSpacing.gutter,
              12,
            ),
            children: [
              // "You said" ink hero card (13-assistant.html)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: brand.heroSurface,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: AppShadows.hero(theme.brightness),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppIcon(
                              AppIcons.mic,
                              size: 16,
                              color: brand.medicineRoles.onInk,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'YOU SAID',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: brand.medicineRoles.onInk,
                              ),
                            ),
                          ],
                        ),
                        BrandTappable(
                          onPressed: controller.editAgain,
                          semanticsLabel: 'Edit text',
                          child: Container(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.center,
                            decoration: ShapeDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              shape: const StadiumBorder(),
                            ),
                            child: const Text(
                              'Edit text',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '“${state.transcript}”',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        height: 1.45,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${state.previews.length} '
                      '${state.previews.length == 1 ? 'thing' : 'things'} to add',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                      ),
                    ),
                    Text(
                      'Tap a card to adjust',
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (state.result.reply.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    state.result.reply,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                ),
              ],
              if (state.error != null) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppIcon(AppIcons.warning, color: brand.danger, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.error!,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: brand.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              for (var i = 0; i < state.previews.length; i++)
                ActionPreviewCard(
                  key: ValueKey(state.previews[i].draft),
                  preview: state.previews[i],
                  saved: state.saved[i],
                  onRemove: () => controller.removePreview(i),
                  onSaved: (item) => controller.markSaved(i, item),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              4,
              AppSpacing.gutter,
              16,
            ),
            child: Row(
              children: [
                CircleIconButton(
                  icon: AppIcons.mic,
                  tooltip: 'Add something else by voice',
                  size: 58,
                  onPressed: controller.startListening,
                ),
                const SizedBox(width: 10),
                CircleIconButton(
                  icon: AppIcons.delete,
                  tooltip: 'Discard',
                  size: 58,
                  color: brand.danger,
                  onPressed: controller.discard,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: BrandButton(
                    label: pending == 0
                        ? (savedCount > 0 ? 'Done' : 'Nothing to save')
                        : savedCount > 0
                        ? 'Save $pending remaining'
                        : pending == 1
                        ? 'Save'
                        : 'Save all $pending',
                    icon: AppIcons.check,
                    onPressed: pending == 0 && savedCount == 0
                        ? null
                        : controller.saveAll,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Saved extends StatefulWidget {
  final AssistantSaved state;
  final VoidCallback onAnother;

  const _Saved({required this.state, required this.onAnother});

  @override
  State<_Saved> createState() => _SavedState();
}

class _SavedState extends State<_Saved> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppHaptics.success();
      final n = widget.state.items.length;
      brandToast(context, 'Added $n ${n == 1 ? 'entry' : 'entries'}.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.state.items;
    final muted = context.muted;
    return ListView(
      padding: pageInsets(context),
      children: [
        Row(
          children: [
            AppIcon(AppIcons.checkCircle, color: context.brand.success),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                items.isEmpty ? 'Nothing saved' : 'Saved',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 22,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            _SourceBadge(source: widget.state.source),
          ],
        ),
        if (widget.state.reply.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            widget.state.reply,
            style: TextStyle(color: muted, fontSize: 14, height: 1.4),
          ),
        ],
        const SizedBox(height: 16),
        TintCard(
          fill: context.brand.surface,
          padding: EdgeInsets.zero,
          child: TileGroup(
            children: [
              for (final item in items)
                BrandTile(
                  leading: AppIcon(
                    item.kind.icon,
                    color: item.kind.color(context.brand),
                  ),
                  title: Text(item.title),
                  subtitle: Text(item.kind.label),
                  trailing: Pill(
                    label: 'Open',
                    color: item.kind.color(context.brand),
                    onTap: () => context.push(item.route, extra: item.extra),
                  ),
                  onTap: () => context.push(item.route, extra: item.extra),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        BrandButton(
          label: 'Add something else',
          icon: AppIcons.mic,
          onPressed: widget.onAnother,
        ),
      ],
    );
  }
}

class _Failure extends ConsumerWidget {
  final AssistantFailure state;

  const _Failure({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(assistantControllerProvider.notifier);
    final muted = context.muted;

    final (
      title,
      icon,
      actionLabel,
      VoidCallback action,
    ) = switch (state.kind) {
      AssistantErrorKind.noSpeech => (
        'Did not catch that',
        AppIcons.micOff,
        'Try again',
        controller.startListening,
      ),
      AssistantErrorKind.noKey || AssistantErrorKind.auth => (
        'Check your API key',
        AppIcons.lock,
        'Open Settings',
        () => context.go('/settings'),
      ),
      AssistantErrorKind.network || AssistantErrorKind.rateLimit => (
        'Could not reach the provider',
        AppIcons.warning,
        'Retry',
        controller.submit,
      ),
      AssistantErrorKind.refused => (
        'The provider declined',
        AppIcons.warning,
        'Edit and resend',
        controller.editAgain,
      ),
      AssistantErrorKind.malformed => (
        'The reply made no sense',
        AppIcons.error,
        'Retry',
        controller.submit,
      ),
      AssistantErrorKind.nothingParsed => (
        'Nothing to add',
        AppIcons.info,
        'Edit and resend',
        controller.editAgain,
      ),
      AssistantErrorKind.unknown => (
        'Something went wrong',
        AppIcons.error,
        'Retry',
        controller.submit,
      ),
    };

    final offlineOffer =
        state.kind == AssistantErrorKind.auth ||
        state.kind == AssistantErrorKind.network ||
        state.kind == AssistantErrorKind.rateLimit ||
        state.kind == AssistantErrorKind.refused;

    return _Centered(
      children: [
        EmptyState(
          icon: icon,
          title: title,
          message: state.message,
          actionLabel: actionLabel,
          onAction: action,
        ),
        if (state.transcript.isNotEmpty) ...[
          Text(
            '“${state.transcript}”',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            if (offlineOffer)
              BrandButton(
                label: 'Use offline parser',
                kind: BrandButtonKind.outline,
                expand: false,
                onPressed: () => controller.submit(forceOffline: true),
              ),
            if (state.kind != AssistantErrorKind.nothingParsed &&
                state.kind != AssistantErrorKind.refused)
              BrandButton(
                label: 'Edit text',
                kind: BrandButtonKind.ghost,
                expand: false,
                onPressed: controller.editAgain,
              ),
            BrandButton(
              label: 'Start over',
              kind: BrandButtonKind.ghost,
              expand: false,
              onPressed: controller.discard,
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> _scan(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(assistantControllerProvider.notifier);
  final fromCamera = await showDocumentSourceSheet(context);
  if (fromCamera == null) return;
  await controller.scanDocument(fromCamera: fromCamera);
}
