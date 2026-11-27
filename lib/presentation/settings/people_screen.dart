import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/database/app_database.dart';
import '../../core/people/avatar_picker.dart';
import '../../core/people/people_repository.dart';
import '../../core/people/person_avatar.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import '../expenses/providers/expenses_provider.dart';
import '../medicine/providers/medicine_provider.dart';

/// The one list of people the whole app draws on (`40-people.html`): the
/// household doubles as medicine profiles and who an expense was for, contacts
/// are who money is lent to or borrowed from.
class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  bool _showInlineNew = true;

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(peopleProvider).valueOrNull ?? const [];
    final household = people
        .where((p) => p.type == PersonType.household)
        .toList();
    final contacts = people.where((p) => p.type == PersonType.contact).toList();
    final brand = context.brand;
    final theme = Theme.of(context);

    return BrandScaffold(
      header: BrandTopBar(
        title: 'People',
        subtitle: 'Household & contacts',
        leadingIcon: AppIcons.back,
        actions: [
          BrandTappable(
            onPressed: () => PersonEditor.show(context, ref),
            semanticsLabel: 'Add person',
            child: Container(
              height: 44,
              padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
              decoration: ShapeDecoration(
                color: brand.ink,
                shape: const StadiumBorder(),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(AppIcons.add, size: 18, color: brand.onInk),
                  const SizedBox(width: 6),
                  Text(
                    'Add person',
                    style: TextStyle(
                      color: brand.onInk,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      child: ListView(
        padding: pageInsets(context, top: 8, end: PageEnd.none),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
            child: Text(
              'HOUSEHOLD',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: context.muted,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(AppRadii.tile),
              boxShadow: AppShadows.card(theme.brightness),
            ),
            child: Column(
              children: [
                for (final (i, p) in household.indexed)
                  _PersonRow(person: p, showDivider: i < household.length - 1),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
            child: Text(
              'CONTACTS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: context.muted,
              ),
            ),
          ),
          if (contacts.isEmpty)
            const EmptyState(
              icon: AppIcons.people,
              title: 'No contacts yet',
              message: 'People you lend to or borrow from land here.',
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(AppRadii.tile),
                boxShadow: AppShadows.card(theme.brightness),
              ),
              child: Column(
                children: [
                  for (final (i, p) in contacts.indexed)
                    _PersonRow(person: p, showDivider: i < contacts.length - 1),
                ],
              ),
            ),
          if (_showInlineNew) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
              child: Text(
                'NEW PERSON',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: context.muted,
                ),
              ),
            ),
            _InlineNewPersonCard(
              onCancel: () => setState(() => _showInlineNew = false),
            ),
          ],
        ],
      ),
    );
  }
}

class _PersonRow extends ConsumerWidget {
  final Person person;
  final bool showDivider;

  const _PersonRow({required this.person, required this.showDivider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final settings = ref.watch(settingsProvider);
    final color = personColor(context, person.color);
    final roles = brand.roleFor(color);

    final medicines = ref.watch(medicinesProvider).valueOrNull ?? const [];
    final medCount = medicines.where((m) => m.profileId == person.id).length;

    final expenses =
        ref.watch(recentExpensesProvider).valueOrNull ?? const <Expense>[];
    final expCount = expenses.where((e) => e.personId == person.id).length;

    final loans = ref.watch(loanRowsProvider).valueOrNull ?? const <LoanRow>[];
    final personLoans = loans
        .where((l) => !l.isSettled && l.loan.personId == person.id)
        .toList();

    final displayName = person.isSelf
        ? (person.name.trim().isEmpty ? 'Me' : person.name)
        : person.name;
    final initials = Fmt.initials(displayName);

    String subtitle;
    if (person.type == PersonType.household) {
      final medText = medCount == 0
          ? 'No medicines'
          : '$medCount ${medCount == 1 ? 'medicine' : 'medicines'}';
      final expText = '$expCount ${expCount == 1 ? 'expense' : 'expenses'}';
      subtitle = '$medText · $expText';
    } else if (personLoans.isNotEmpty) {
      final first = personLoans.first;
      final dueText = first.loan.dueDate == null
          ? 'no due date'
          : 'due ${Fmt.dayMonth(first.loan.dueDate!)}';
      subtitle =
          '${personLoans.length} ${personLoans.length == 1 ? 'loan' : 'loans'} · $dueText';
    } else {
      subtitle = person.relation.isEmpty ? 'Contact' : person.relation;
    }

    return BrandTappable(
      onPressed: () => PersonEditor.show(context, ref, person: person),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: showDivider
              ? Border(bottom: BorderSide(color: brand.hairline))
              : null,
        ),
        child: Row(
          children: [
            if (person.photoPath != null)
              PersonAvatar(photoPath: person.photoPath, color: color, size: 44)
            else
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: person.isSelf ? brand.ink : roles.tintFill,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initials.isEmpty ? 'ME' : initials,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: person.isSelf ? brand.onInk : roles.textOnTint,
                  ),
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: brand.ink,
                      ),
                      children: [
                        TextSpan(text: displayName),
                        if (!person.isSelf && person.relation.trim().isNotEmpty)
                          TextSpan(
                            text: ' · ${person.relation}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: context.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: context.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (person.isSelf)
              Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: brand.hairline,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'You',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: context.muted,
                  ),
                ),
              )
            else if (personLoans.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    personLoans.first.isLent ? 'Owes you' : 'You owe',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: personLoans.first.isLent
                          ? brand.habitRoles.textOnTint
                          : brand.danger,
                    ),
                  ),
                  Text(
                    Fmt.money(
                      personLoans.first.outstanding,
                      settings.currencySymbol,
                    ),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              )
            else ...[
              CircleIconButton(
                icon: AppIcons.delete,
                tooltip: 'Delete',
                size: 36,
                onPressed: () => _delete(context, ref),
              ),
              AppIcon(AppIcons.chevronRight, size: 16, color: context.subtle),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(peopleRepositoryProvider);
    final count = await repo.referenceCount(person.id);
    if (!context.mounted) return;

    final ok = await brandConfirm(
      context,
      title: 'Delete ${person.name}?',
      message: count == 0
          ? null
          : 'Their $count ${count == 1 ? 'record' : 'records'} move to Self.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok) await repo.deletePerson(person.id);
  }
}

class _InlineNewPersonCard extends ConsumerStatefulWidget {
  final VoidCallback onCancel;

  const _InlineNewPersonCard({required this.onCancel});

  @override
  ConsumerState<_InlineNewPersonCard> createState() =>
      _InlineNewPersonCardState();
}

class _InlineNewPersonCardState extends ConsumerState<_InlineNewPersonCard> {
  final _name = TextEditingController();
  final _relation = TextEditingController();
  String _kind = PersonType.household;
  int _color = 0xFF0284C7;
  File? _picked;

  @override
  void dispose() {
    _name.dispose();
    _relation.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final trimmed = _name.text.trim();
    if (trimmed.isEmpty) return;
    final repo = ref.read(peopleRepositoryProvider);
    final id = await repo.createPerson(
      name: trimmed,
      relation: _relation.text.trim().isEmpty
          ? (_kind == PersonType.contact ? 'Friend' : 'Family')
          : _relation.text.trim(),
      color: _color,
      type: _kind,
    );
    if (_picked != null) await repo.setPhoto(id, _picked!);
    setState(() {
      _name.clear();
      _relation.clear();
      _picked = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final theme = Theme.of(context);
    final roles = brand.roleFor(Color(_color));
    final initials = Fmt.initials(_name.text);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: brand.ink, width: 2),
        boxShadow: AppShadows.card(theme.brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _PhotoWell(
                file: _picked,
                photoPath: null,
                color: Color(_color),
                size: 64,
                initials: initials.isEmpty ? 'NP' : initials,
                roles: roles,
                onTap: () async {
                  final choice = await pickAvatar(
                    context,
                    hasPhoto: _picked != null,
                  );
                  if (choice == null) return;
                  setState(() {
                    switch (choice) {
                      case AvatarPicked(:final file):
                        _picked = file;
                      case AvatarCleared():
                        _picked = null;
                    }
                  });
                },
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  children: [
                    BrandField(
                      controller: _name,
                      hint: 'Name',
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    BrandField(
                      controller: _relation,
                      hint: 'Relation — wife, son, friend',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          BrandSegmented<String>(
            expand: true,
            options: const {
              PersonType.household: 'Household',
              PersonType.contact: 'Contact',
            },
            selected: _kind,
            onSelected: (v) => setState(() => _kind = v),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text(
                'Colour',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ColorPickerRow(
                    selected: _color,
                    onChanged: (c) => setState(() => _color = c),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              BrandTappable(
                onPressed: widget.onCancel,
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: brand.hairline,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: brand.ink,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: BrandButton(label: 'Create', onPressed: _create),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The create / edit dialog, shared with the loan sheet's quick-add.
class PersonEditor {
  PersonEditor._();

  /// Returns the id of the created or edited person, or null if dismissed.
  static Future<int?> show(
    BuildContext context,
    WidgetRef ref, {
    Person? person,
    String type = PersonType.household,
  }) async {
    final name = TextEditingController(text: person?.name ?? '');
    final relation = TextEditingController(
      text:
          person?.relation ??
          (type == PersonType.contact ? 'Friend' : 'Family'),
    );
    var kind = person?.type ?? type;
    var color = person?.color ?? 0xFFFF6547;
    final isSelf = person?.isSelf ?? false;

    File? picked;
    var cleared = false;

    final saved = await brandDialog<bool>(
      context,
      title: person == null ? 'New person' : 'Edit person',
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: _PhotoWell(
                file: picked,
                photoPath: cleared ? null : person?.photoPath,
                color: Color(color),
                onTap: () async {
                  final choice = await pickAvatar(
                    dialogContext,
                    hasPhoto:
                        picked != null ||
                        (!cleared && person?.photoPath != null),
                  );
                  if (choice == null) return;
                  setState(() {
                    switch (choice) {
                      case AvatarPicked(:final file):
                        picked = file;
                        cleared = false;
                      case AvatarCleared():
                        picked = null;
                        cleared = true;
                    }
                  });
                },
              ),
            ),
            const SizedBox(height: 18),
            BrandField(controller: name, label: 'Name', autofocus: true),
            const SizedBox(height: 12),
            BrandField(
              controller: relation,
              label: 'Relation',
              hint: 'Wife, son, friend',
            ),
            if (!isSelf) ...[
              const SizedBox(height: 16),
              BrandSegmented<String>(
                options: const {
                  PersonType.household: 'Household',
                  PersonType.contact: 'Contact',
                },
                selected: kind,
                onSelected: (v) => setState(() => kind = v),
              ),
            ],
            const SizedBox(height: 16),
            ColorPickerRow(
              selected: color,
              onChanged: (c) => setState(() => color = c),
            ),
            const SizedBox(height: 20),
            BrandButton(
              label: person == null ? 'Create' : 'Save',
              onPressed: () => Navigator.pop(dialogContext, true),
            ),
            const SizedBox(height: 8),
            BrandButton(
              label: 'Cancel',
              kind: BrandButtonKind.ghost,
              onPressed: () => Navigator.pop(dialogContext, false),
            ),
          ],
        ),
      ),
    );

    if (saved != true || name.text.trim().isEmpty) return null;
    final repo = ref.read(peopleRepositoryProvider);
    if (person == null) {
      final id = await repo.createPerson(
        name: name.text.trim(),
        relation: relation.text.trim(),
        color: color,
        type: kind,
      );
      if (picked != null) await repo.setPhoto(id, picked!);
      return id;
    }
    await repo.updatePerson(
      person.id,
      name: name.text.trim(),
      relation: relation.text.trim(),
      color: color,
      type: isSelf ? null : kind,
      photoPath: cleared && picked == null
          ? const Value(null)
          : const Value.absent(),
    );
    if (picked != null) await repo.setPhoto(person.id, picked!);
    return person.id;
  }
}

/// The editor's photo control: the avatar with a camera badge, so it reads as
/// something to press rather than a picture of the person.
class _PhotoWell extends StatelessWidget {
  final File? file;
  final String? photoPath;
  final Color color;
  final double size;
  final String? initials;
  final ModuleColors? roles;
  final VoidCallback onTap;

  const _PhotoWell({
    required this.file,
    required this.photoPath,
    required this.color,
    this.size = 84,
    this.initials,
    this.roles,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return FTappable(
      onPress: onTap,
      semanticsLabel: 'Change photo',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (file != null)
            ClipOval(
              child: Image.file(
                file!,
                width: size,
                height: size,
                fit: BoxFit.cover,
              ),
            )
          else if (photoPath == null && initials != null && roles != null)
            Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: roles!.tintFill,
                shape: BoxShape.circle,
              ),
              child: Text(
                initials!,
                style: TextStyle(
                  fontSize: size * 0.34,
                  fontWeight: FontWeight.w800,
                  color: roles!.textOnTint,
                ),
              ),
            )
          else
            PersonAvatar(photoPath: photoPath, color: color, size: size),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: brand.ink,
                shape: BoxShape.circle,
                border: Border.all(color: brand.surface, width: 2),
              ),
              child: AppIcon(AppIcons.camera, color: brand.onInk, size: 12),
            ),
          ),
        ],
      ),
    );
  }
}
