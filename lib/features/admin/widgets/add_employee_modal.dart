// Modale d'ajout / édition d'un salarié — variante Pastille.
//
// Preview live en haut (pastille + nom), puis champs nom + taux horaire
// (en €/h, nullable), puis picker de couleur (8 couleurs). À l'enregistrement
// on appelle EmployeeRepository.create ou update.
//
// Note : la ref design prévoit aussi un PIN et un "rôle" pour chaque salarié.
// La DB actuelle ne stocke ni l'un ni l'autre — on reste fidèle au schéma
// existant (firstName/lastName/color/hourlyRateCents) pour éviter une
// migration de schéma trop tôt. Le rôle pourra être ajouté à v2 plus tard.
//
// Ref design : shared/onboarding.jsx (fonction AddEmployeeModal).

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/app_database.dart';
import '../../../design/tokens.dart';
import '../../../state/providers.dart';

// Palette Pastille : chaud terracotta/ambre/bordeaux, 8 teintes distinctes.
const _palette = <String>[
  '#C96F4A', // terra
  '#D4A24C', // mustard
  '#8B5A3C', // brown
  '#A8453E', // bordeaux
  '#5C7A4A', // olive
  '#7A5C9E', // plum
  '#4A6B7A', // teal
  '#B5834C', // caramel
];

class AddEmployeeModal extends ConsumerStatefulWidget {
  const AddEmployeeModal({super.key, this.existing});

  final Employee? existing;

  @override
  ConsumerState<AddEmployeeModal> createState() => _AddEmployeeModalState();
}

class _AddEmployeeModalState extends ConsumerState<AddEmployeeModal> {
  late final TextEditingController _firstCtrl;
  late final TextEditingController _lastCtrl;
  late final TextEditingController _rateCtrl;
  late String _color;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _firstCtrl = TextEditingController(text: e?.firstName ?? '');
    _lastCtrl = TextEditingController(text: e?.lastName ?? '');
    _rateCtrl = TextEditingController(
      text: e?.hourlyRateCents != null
          ? (e!.hourlyRateCents! / 100).toStringAsFixed(2)
          : '',
    );
    _color = e?.color ?? _palette.first;
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  bool get _canSave => _firstCtrl.text.trim().isNotEmpty;

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_canSave) {
      setState(() => _error = 'Prénom requis');
      return;
    }
    final rateText = _rateCtrl.text.replaceAll(',', '.').trim();
    int? cents;
    if (rateText.isNotEmpty) {
      final n = double.tryParse(rateText);
      if (n == null || n < 0) {
        setState(() => _error = 'Taux horaire invalide');
        return;
      }
      cents = (n * 100).round();
    }

    final repo = ref.read(employeeRepositoryProvider);
    if (widget.existing == null) {
      await repo.create(
        firstName: _firstCtrl.text.trim(),
        lastName: _lastCtrl.text.trim(),
        color: _color,
        hourlyRateCents: cents,
      );
    } else {
      await repo.update(
        widget.existing!.copyWith(
          firstName: _firstCtrl.text.trim(),
          lastName: _lastCtrl.text.trim(),
          color: _color,
          hourlyRateCents: Value(cents),
        ),
      );
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final initials = _computeInitials(_firstCtrl.text, _lastCtrl.text);
    final previewColor = _parseHexColor(_color);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 560,
        decoration: BoxDecoration(
          color: KlokTokens.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              offset: Offset(0, 20),
              blurRadius: 60,
            ),
          ],
        ),
        padding: const EdgeInsets.all(28),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEdit ? 'Modifier le salarié' : 'Ajouter un salarié',
                          style: TextStyle(
                            fontFamily: KlokTokens.fontDisplay,
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.4,
                            color: KlokTokens.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isEdit
                              ? "Mets à jour les infos de l'équipe"
                              : 'Choisis un prénom, un nom et une couleur',
                          style: TextStyle(
                            fontSize: 13,
                            color: KlokTokens.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _CloseButton(onTap: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 20),

              // Preview
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: KlokTokens.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: previewColor,
                      ),
                      child: Center(
                        child: Text(
                          initials,
                          style: const TextStyle(
                            fontFamily: KlokTokens.fontDisplay,
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _firstCtrl.text.trim().isEmpty
                                ? 'Nouveau salarié'
                                : '${_firstCtrl.text} ${_lastCtrl.text}'.trim(),
                            style: TextStyle(
                              fontFamily: KlokTokens.fontDisplay,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: KlokTokens.ink,
                            ),
                          ),
                          if (_rateCtrl.text.trim().isNotEmpty)
                            Text(
                              '${_rateCtrl.text}€/h',
                              style: TextStyle(
                                fontSize: 12,
                                color: KlokTokens.inkSoft,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Champs
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _Field(
                      label: 'Prénom *',
                      controller: _firstCtrl,
                      autofocus: !isEdit,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: _Field(
                      label: 'Nom',
                      controller: _lastCtrl,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Field(
                label: 'Taux horaire (€/h) — optionnel',
                controller: _rateCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),

              // Color picker
              Text(
                'Couleur de pastille',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: KlokTokens.inkSoft,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in _palette)
                    _ColorDot(
                      color: c,
                      selected: c == _color,
                      onTap: () => setState(() => _color = c),
                    ),
                ],
              ),

              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 13, color: KlokTokens.danger),
                ),
              ],

              const SizedBox(height: 22),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _SecondaryButton(
                    label: 'Annuler',
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  _PrimaryButton(
                    label: isEdit ? 'Enregistrer' : 'Ajouter le salarié',
                    enabled: _canSave,
                    onTap: _save,
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

// ─────────────────────────────────────────────────────────────
// Widgets internes
// ─────────────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.onChanged,
    this.autofocus = false,
    this.keyboardType,
    this.inputFormatters,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: KlokTokens.inkSoft,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          autofocus: autofocus,
          onChanged: onChanged,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: TextStyle(fontSize: 14, color: KlokTokens.ink),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            fillColor: KlokTokens.card,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: KlokTokens.border, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: KlokTokens.border, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: KlokTokens.bordeaux, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _parseHexColor(color),
          border: Border.all(
            color: selected ? KlokTokens.ink : Colors.transparent,
            width: 3,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              offset: Offset(0, 1),
              blurRadius: 3,
            ),
          ],
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: KlokTokens.border),
          ),
          width: 32,
          height: 32,
          child: Center(
            child: Icon(Icons.close, size: 16, color: KlokTokens.inkSoft),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onTap,
    required this.enabled,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final bg = enabled ? KlokTokens.bordeaux : KlokTokens.border;
    final fg = enabled ? Colors.white : KlokTokens.muted;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: KlokTokens.fontDisplay,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KlokTokens.card,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: KlokTokens.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: KlokTokens.inkSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────
String _computeInitials(String first, String last) {
  final f = first.trim().isNotEmpty ? first.trim()[0] : '';
  final l = last.trim().isNotEmpty ? last.trim()[0] : '';
  final out = '$f$l';
  return out.isEmpty ? '??' : out.toUpperCase();
}

Color _parseHexColor(String hex) {
  final clean = hex.replaceAll('#', '').trim();
  if (clean.length == 3) {
    final r = clean[0] * 2;
    final g = clean[1] * 2;
    final b = clean[2] * 2;
    return Color(int.parse('FF$r$g$b', radix: 16));
  }
  if (clean.length == 8) return Color(int.parse(clean, radix: 16));
  return Color(int.parse('FF$clean', radix: 16));
}
