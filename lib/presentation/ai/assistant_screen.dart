import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    HapticFeedback.lightImpact();
    controller.startListening();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assistantControllerProvider);
    final controller = ref.read(assistantControllerProvider.notifier);

    return BrandScaffold(
      header: BrandTopBar(
        title: 'Assistant',
        leadingIcon: AppIcons.back,
        actions: [
          CircleIconButton(
            icon: AppIcons.settings,
            tooltip: 'AI settings',
            size: 40,
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      child: switch (state) {
        AssistantIdle() => _Idle(onListen: () => _record(controller)),
        AssistantListening s => _Listening(
          state: s,
          onStop: () {
            HapticFeedback.lightImpact();
            controller.stopListening();
          },
          onCancel: controller.cancelListening,
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
  }
}

// --- Shared bits -----------------------------------------------------------

/// Says which parser will answer, so nobody wonders where the words went.
class _SourceBadge extends ConsumerWidget {
  final AiSource? source;

  const _SourceBadge({this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    return Pill(
      label: label,
      icon: label == offline.label ? AppIcons.lock : AppIcons.sparkle,
      color: context.muted,
    );
  }
}

class _MicButton extends ConsumerWidget {
  final bool live;
  final VoidCallback onPressed;

  const _MicButton({required this.live, required this.onPressed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final fill = live ? context.brand.danger : scheme.primary;
    final reduceMotion = ref.watch(settingsProvider).reduceMotion;

    Widget button = BrandTappable(
      onPressed: onPressed,
      semanticsLabel: live ? 'Stop listening' : 'Start listening',
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: fill,
          shape: const CircleBorder(),
          shadows: [
            BoxShadow(
              color: fill.withValues(alpha: 0.3),
              blurRadius: 18,
              spreadRadius: -2,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SizedBox(
          width: 88,
          height: 88,
          child: AppIcon(
            live ? AppIcons.micOff : AppIcons.mic,
            color: scheme.onPrimary,
            size: 38,
          ),
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

/// Concentric rings behind the live mic that swell with the input level,
/// so the animation answers the voice instead of looping on its own.
class _PulseRings extends ConsumerWidget {
  final double level;
  final Widget child;

  const _PulseRings({required this.level, required this.child});

  static const _size = 88.0;
  static const _rings = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = context.brand.danger;
    final reduceMotion = ref.watch(settingsProvider).reduceMotion;
    // A floor so the rings breathe even in silence; the voice adds on top.
    final drive = reduceMotion ? 0.0 : 0.15 + level * 0.85;
    return SizedBox(
      width: _size * 2.6,
      height: _size * 2.6,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (var i = _rings; i >= 1; i--)
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: _size + (_size * 0.5 * i) * (0.35 + 0.65 * drive),
              height: _size + (_size * 0.5 * i) * (0.35 + 0.65 * drive),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(
                  alpha: math.max(0.04, (0.22 - 0.06 * i) * (0.4 + drive)),
                ),
              ),
            ),
          child,
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
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 40),
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

  const _Listening({
    required this.state,
    required this.onStop,
    required this.onCancel,
  });

  static String _clock(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.muted;
    final danger = context.brand.danger;
    return _Centered(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
                  decoration: BoxDecoration(
                    color: danger,
                    shape: BoxShape.circle,
                  ),
                  child: const SizedBox(width: 8, height: 8),
                )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .fade(begin: 1, end: 0.2, duration: 800.ms),
            const SizedBox(width: 8),
            Text(
              'Recording  ${_clock(state.elapsed)}',
              style: TextStyle(
                color: muted,
                fontSize: 13,
                letterSpacing: 0.4,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _PulseRings(
          level: state.level,
          child: _MicButton(live: true, onPressed: onStop),
        ),
        Text('Tap to send', style: TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Text(
            state.partial.isEmpty ? 'Listening…' : state.partial,
            textAlign: TextAlign.center,
            style: state.partial.isEmpty
                ? TextStyle(color: muted, fontSize: 15, height: 1.4)
                : Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontSize: 17, height: 1.4),
          ),
        ),
        if (state.notice != null) ...[
          const SizedBox(height: 12),
          Text(
            state.notice!,
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 12, height: 1.4),
          ),
        ],
        const SizedBox(height: 20),
        BrandButton(
          label: 'Cancel',
          kind: BrandButtonKind.ghost,
          expand: false,
          onPressed: onCancel,
        ),
      ],
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
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
    final controller = ref.read(assistantControllerProvider.notifier);
    final muted = context.muted;
    final pending = state.pending.length;
    final savedCount = state.saved.length;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            children: [
              TintCard(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                onTap: controller.editAgain,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '“${state.transcript}”',
                        style: TextStyle(
                          color: muted,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AppIcon(AppIcons.edit, color: muted, size: 18),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _SourceBadge(source: state.result.source),
                  const Spacer(),
                  Text(
                    '${state.previews.length} '
                    '${state.previews.length == 1 ? 'entry' : 'entries'}',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
              if (state.result.reply.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  state.result.reply,
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
              ],
              if (state.error != null) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppIcon(
                      AppIcons.warning,
                      color: context.brand.danger,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.error!,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: context.brand.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              for (var i = 0; i < state.previews.length; i++)
                ActionPreviewCard(
                  key: ValueKey(state.previews[i].draft),
                  preview: state.previews[i],
                  saved: state.saved[i],
                  onRemove: () => controller.removePreview(i),
                  onSaved: (item) => controller.markSaved(i, item),
                ),
              const SizedBox(height: 4),
              Text(
                'Tap a card to adjust it in its own form before saving.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Row(
              children: [
                BrandButton(
                  label: 'Discard',
                  kind: BrandButtonKind.ghost,
                  expand: false,
                  onPressed: controller.discard,
                ),
                const SizedBox(width: 12),
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
      final n = widget.state.items.length;
      brandToast(context, 'Added $n ${n == 1 ? 'entry' : 'entries'}.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.state.items;
    final muted = context.muted;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
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
