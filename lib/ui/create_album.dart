import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../services/app_store.dart';
import '../services/reminder_service.dart';
import 'theme.dart';

class CreateAlbumDialog extends StatefulWidget {
  const CreateAlbumDialog({
    super.key,
    required this.store,
    required this.reminders,
  });
  final AppStore store;
  final ReminderService reminders;
  @override
  State<CreateAlbumDialog> createState() => _CreateAlbumDialogState();
}

class _CreateAlbumDialogState extends State<CreateAlbumDialog> {
  final title = TextEditingController();
  final form = GlobalKey<FormState>();
  PlaceCategory category = PlaceCategory.restaurant;
  DateTime date = DateTime.now().add(const Duration(days: 1));
  bool busy = false;
  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  Future<void> create() async {
    if (!form.currentState!.validate()) {
      return;
    }
    setState(() => busy = true);
    try {
      final album = await widget.store.createAlbum(
        title: title.text.trim(),
        category: category,
        eventDate: DateTime(date.year, date.month, date.day),
      );
      if (mounted) {
        Navigator.pop(context, album);
      }
    } catch (_) {
      if (mounted) {
        setState(() => busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save your album. Check available storage and try again.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Eyebrow('A new chapter'),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                'What’s the occasion?',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 10),
              const Text(
                'Give it a name. We’ll help with the photo ideas.',
                style: TextStyle(color: Palette.sage),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: title,
                autofocus: true,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Album name',
                  hintText: 'Sunday dinner with my favourite people',
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Give your album a name.'
                    : null,
              ),
              const SizedBox(height: 18),
              const Eyebrow('Choose your occasion'),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, c) => Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: PlaceCategory.values
                      .map(
                        (item) => SizedBox(
                          width: (c.maxWidth - 10) / 2,
                          child: Material(
                            color: item == category
                                ? Palette.wine
                                : Palette.cream,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: busy
                                  ? null
                                  : () => setState(() => category = item),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Icon(
                                      categoryIcon(item.name),
                                      color: item == category
                                          ? Palette.cream
                                          : Palette.sage,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Text(
                                        item.label,
                                        style: TextStyle(
                                          color: item == category
                                              ? Palette.cream
                                              : Palette.ink,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.calendar_today_outlined,
                  color: Palette.wine,
                ),
                title: const Text('When is it happening?'),
                subtitle: Text(shortDate(date)),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy
                    ? null
                    : () async {
                        final now = DateTime.now();
                        final result = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(now.year - 20),
                          lastDate: DateTime(now.year + 10),
                        );
                        if (result != null && mounted) {
                          setState(() => date = result);
                        }
                      },
              ),
              const SizedBox(height: 16),
              const PaperCard(
                padding: EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline, color: Palette.sage),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'A little advice: plan your album a day ahead. Browse your ideas now, then set a reminder inside the album.',
                        style: TextStyle(color: Palette.sage, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy ? null : create,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_outlined),
                  label: Text(
                    busy ? 'Creating…' : 'Create album & find my photo ideas',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
