import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../game/share_card.dart';

/// A QR code to the game's download page for someone nearby to scan, plus
/// buttons to send or copy the link.
Future<void> showShareApp(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: Colors.black87,
  builder: (_) => const ShareAppDialog(),
);

class ShareAppDialog extends StatefulWidget {
  const ShareAppDialog({super.key});

  @override
  State<ShareAppDialog> createState() => _ShareAppDialogState();
}

class _ShareAppDialogState extends State<ShareAppDialog> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A2A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'SHARE THE APP',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Let a friend scan this to get RGB Invaders.\n'
              'Works on iPhone, iPad and Android.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white60,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 20),
            // A white tile, which scanners need for contrast.
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: QrImageView(
                data: kShareUrl,
                size: 200,
                padding: EdgeInsets.zero,
                gapless: true,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF12121E),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF12121E),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // A Builder, so the share sheet on iPad can point at this button.
            Builder(
              builder: (context) => _ShareAppButton(
                icon: '📤',
                label: 'Send the link',
                onTap: () => _shareLink(context),
              ),
            ),
            _ShareAppButton(
              icon: _copied ? '✅' : '🔗',
              label: _copied ? 'Link copied' : 'Copy the link',
              onTap: _copyLink,
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Done',
                style: TextStyle(fontSize: 12, color: Colors.white38),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareLink(BuildContext buttonContext) async {
    final box = buttonContext.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: 'Try RGB Invaders, a colour-mixing arcade game! $kShareUrl',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (e) {
      debugPrint('[ShareApp] share failed: $e');
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(const ClipboardData(text: kShareUrl));
    if (mounted) setState(() => _copied = true);
  }
}

class _ShareAppButton extends StatelessWidget {
  const _ShareAppButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 240,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: Colors.white24, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
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
