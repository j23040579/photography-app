import 'package:flutter/material.dart';
import 'theme.dart';

class Onboarding extends StatefulWidget {
  const Onboarding({super.key, required this.onFinish});
  final Future<void> Function() onFinish;
  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  int step = 0;
  bool saving = false;
  static const titles = [
    'Make room for\nthe little things.',
    'A little intention.\nA lot of memories.',
    'Tomorrow starts\nwith a little plan.',
  ];
  static const descriptions = [
    'Create an album for a dinner, a party, or an ordinary Tuesday. Pick the occasion. We’ll help you see it differently.',
    'Get a fresh list of photo ideas, make them your own, and capture the moment. Add photos, videos, notes, and a rating to keep the whole story.',
    'Try creating your album one day ahead. Read your photo ideas, set a reminder, and arrive ready to notice the moments that matter.',
  ];
  Future<void> finish() async {
    setState(() => saving = true);
    try {
      await widget.onFinish();
    } catch (_) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.camera_rounded, color: Palette.wine),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Jett's Archive",
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    TextButton(
                      onPressed: saving ? null : finish,
                      child: const Text('Skip guide'),
                    ),
                  ],
                ),
                const SizedBox(height: 36),
                Container(
                  height: 240,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Palette.wine,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        right: -35,
                        top: -60,
                        child: Container(
                          width: 270,
                          height: 270,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Palette.cream.withValues(alpha: .12),
                              width: 42,
                            ),
                          ),
                        ),
                      ),
                      Transform.rotate(
                        angle: -.12,
                        child: Container(
                          width: 165,
                          height: 178,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Palette.cream,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Column(
                            children: [
                              Expanded(
                                child: Container(
                                  color: Palette.sage,
                                  child: Center(
                                    child: Icon(
                                      [
                                        Icons.filter_vintage_rounded,
                                        Icons.auto_awesome_rounded,
                                        Icons.notifications_active_rounded,
                                      ][step],
                                      size: 64,
                                      color: Palette.cream,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Eyebrow('A moment to keep'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Eyebrow('A field guide / 0${step + 1}'),
                const SizedBox(height: 16),
                Text(
                  titles[step],
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: 20),
                Text(
                  descriptions[step],
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    for (int i = 0; i < 3; i++)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        width: i == step ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == step ? Palette.wine : Palette.line,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    const Spacer(),
                    Flexible(
                      child: FilledButton.icon(
                        onPressed: saving
                            ? null
                            : () {
                                if (step < 2) {
                                  setState(() => step++);
                                } else {
                                  finish();
                                }
                              },
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: Text(
                          saving
                              ? 'Saving…'
                              : step < 2
                              ? 'Next'
                              : 'Start my journal',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Center(
                  child: Text(
                    'Private by design. Your memories stay on this device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Palette.sage, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
