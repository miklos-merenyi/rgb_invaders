import 'package:flutter/material.dart';

import '../services/purchase_service.dart';

Future<void> showTipJar(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: Colors.black87,
  builder: (_) => const TipJarDialog(),
);

class TipJarDialog extends StatelessWidget {
  const TipJarDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final ps = PurchaseService();
    final tips = [
      (kProductTipS, '☕', 'Small tip', '1 month ad-free'),
      (kProductTipM, '🎩', 'Medium tip', '3 months ad-free'),
      (kProductTipL, '👑', 'Royal tip', '1 year ad-free'),
    ];

    return Dialog(
      backgroundColor: const Color(0xFF1A1A2A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: ListenableBuilder(
          listenable: ps,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('☕', style: TextStyle(fontSize: 44)),
              const SizedBox(height: 16),
              const Text(
                'SUPPORT THE DEV',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'RGB Invaders is free to play, with an ad every few games. '
                'A tip removes ads for a while and stops these popups too.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white60,
                  height: 1.6,
                ),
              ),
              if (ps.adsRemoved) ...[
                const SizedBox(height: 10),
                Text(
                  adsFreeLabel(context, ps.adsFreeUntil!),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              for (final (id, emoji, label, duration) in tips)
                _TipOption(
                  emoji: emoji,
                  label: label,
                  duration: duration,
                  price: ps.product(id)?.price ?? '—',
                  onTap: ps.loadingPurchase || ps.product(id) == null
                      ? null
                      : () async {
                          await ps.buyTip(id);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                ),
              const SizedBox(height: 4),
              const Text(
                'Ad-free time is tied to this device only. It can\'t be '
                'transferred to another device or account, and isn\'t '
                'restored if you reinstall.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white24,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Not now, keep playing',
                  style: TextStyle(fontSize: 12, color: Colors.white24),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String adsFreeLabel(BuildContext context, DateTime until) =>
    'Ads removed until '
    '${MaterialLocalizations.of(context).formatMediumDate(until)}';

class _TipOption extends StatelessWidget {
  const _TipOption({
    required this.emoji,
    required this.label,
    required this.duration,
    required this.price,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final String duration;
  final String price;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: Colors.white24, width: 1.5),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      duration,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white38,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                price,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
