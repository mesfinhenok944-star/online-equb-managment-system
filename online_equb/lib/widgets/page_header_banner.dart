import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PageHeaderBanner
//
// Animated cycling-text banner used at the top of every front-end page.
// Text is centred, large, bold — like the home page hero banner.
// ─────────────────────────────────────────────────────────────────────────────
class PageHeaderBanner extends StatefulWidget {
  final Color color;
  final IconData icon;
  final List<_Phrase> phrases;
  final String? staticTitle;
  final double height;

  const PageHeaderBanner({
    super.key,
    required this.color,
    required this.icon,
    required this.phrases,
    this.staticTitle,
    this.height = 90,
  });

  // ── Pre-built phrase sets ─────────────────────────────────────────────────

  static const List<_Phrase> equbPhrases = [
    _Phrase(en: 'Ethiopian Digital Equb Management System',    am: 'ኢትዮጵያዊ ዲጂታል እቁብ ስርዓት'),
    _Phrase(en: 'Fair · Transparent · Automated Weekly Draws', am: 'ፍትሃዊ · ግልጽ · ራስ-ሰር ሳምንታዊ ዕጣ'),
    _Phrase(en: '1-to-1 Verified — Every Member Wins Once',    am: '1-ለ-1 ማረጋገጫ — ሁሉም አባል አንዴ ያሸንፋል'),
    _Phrase(en: 'Secure Wheel Draw — Verified & Protected',    am: 'ደህንነቱ ያለ ዕጣ — ተጠብቆ ተረጋግጧል'),
  ];

  static const List<_Phrase> historyPhrases = [
    _Phrase(en: 'Equb Draw Winners — All Levels',              am: 'የእቁብ ዕጣ አሸናፊዎች — ሁሉም ደረጃዎች'),
    _Phrase(en: 'Low · Medium · High Level Results',           am: 'ዝቅተኛ · መካከለኛ · ከፍተኛ ደረጃ'),
    _Phrase(en: 'Past winners excluded from future draws',     am: 'ያሸነፉ ሰዎች ወደፊት ዕጣ አይሳተፉም'),
  ];

  static const List<_Phrase> paymentPhrases = [
    _Phrase(en: 'Submit Your Equb Payment Receipt',            am: 'የእቁብ ክፍያ ደረሰኝ ያስገቡ'),
    _Phrase(en: 'Supported: CBE · Telebirr · Abyssinia',       am: 'ድጋፍ: ንግድ ባንክ · ቴሌብር · አቢሲንያ'),
    _Phrase(en: 'Payment verified by the Level Admin',        am: 'ክፍያ በደረጃ አስተዳዳሪ ይረጋገጣል'),
  ];

  static const List<_Phrase> registerPhrases = [
    _Phrase(en: 'Register a New Equb Member',                  am: 'አዲስ የእቁብ አባል ይምዝገቡ'),
    _Phrase(en: 'Use valid Ethiopian phone: 09XXXXXXXX',       am: 'ትክክለኛ ስልክ ቁጥር ይጠቀሙ: 09XXXXXXXX'),
    _Phrase(en: 'Unique ID maps 1-to-1 per member',           am: 'ልዩ መታወቂያ ለአንድ አባል ብቻ'),
  ];

  @override
  State<PageHeaderBanner> createState() => _PageHeaderBannerState();
}

class _PageHeaderBannerState extends State<PageHeaderBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;
  int _idx = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 550));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _slide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
    _schedule();
  }

  void _schedule() {
    Future.delayed(const Duration(milliseconds: 3200), () {
      if (!mounted) return;
      _ctrl.reverse().then((_) {
        if (!mounted) return;
        setState(() => _idx = (_idx + 1) % widget.phrases.length);
        _ctrl.forward();
        _schedule();
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phrase = widget.phrases[_idx];
    final c = widget.color;
    // Alternate EN/AM: even indices show English, odd show Amharic
    final text = _idx.isOdd ? phrase.am : phrase.en;

    return Container(
      width: double.infinity,
      height: widget.height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c, c.withOpacity(0.80)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: c.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(right: -20, top: -20,
            child: Container(width: 90, height: 90,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.07)))),
          Positioned(left: -10, bottom: -15,
            child: Container(width: 60, height: 60,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05)))),

          // Centred animated text
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: FadeTransition(
                opacity: _fade,
                child: SlideTransition(
                  position: _slide,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Static title — smaller subtitle above
                      if (widget.staticTitle != null) ...[
                        Text(
                          widget.staticTitle!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.75),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                      ],
                      // Main cycling text — LARGE BOLD CENTRED
                      Text(
                        text,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                          letterSpacing: -0.2,
                          shadows: [
                            Shadow(
                              color: Colors.black38,
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Icon on the left
          Positioned(
            left: 14,
            top: 0,
            bottom: 0,
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withOpacity(0.3), width: 1.5),
                ),
                child: Icon(widget.icon, color: Colors.white, size: 18),
              ),
            ),
          ),

          // Dot indicators on the right
          Positioned(
            right: 12,
            top: 0,
            bottom: 0,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.phrases.length, (i) =>
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 5,
                    height: i == _idx ? 16 : 5,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: i == _idx
                          ? Colors.white
                          : Colors.white.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Phrase {
  final String en;
  final String am;
  const _Phrase({required this.en, required this.am});
}
