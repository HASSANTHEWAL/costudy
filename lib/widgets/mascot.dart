import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The CoStudy mascot, carried over verbatim from the Figma prototype.
///
/// The path data is the prototype's SVG rather than a hand-redrawn
/// approximation — a blob silhouette is exactly the kind of shape that drifts
/// when it is eyeballed into a CustomPainter, and the character is meant to be
/// the same character.
///
/// Note the yellow blob: #FFD23F appears here and nowhere else outside the
/// Coalition Found screen. It is the mascot, not UI chrome, so it does not
/// break the one-colour rule — but nothing else in this file's neighbourhood
/// may borrow it.
const String _mascotSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 150" fill="none">
  <ellipse cx="100" cy="136" rx="80" ry="6" fill="rgba(0,0,0,0.07)"/>
  <path d="M138,38 C159,38 172,54 172,77 C172,100 161,118 138,118 C115,118 104,100 104,77 C104,54 117,38 138,38 Z" fill="#FFD23F"/>
  <ellipse cx="122" cy="55" rx="10" ry="6" fill="rgba(255,255,255,0.28)" transform="rotate(-30 122 55)"/>
  <path d="M68,26 C90,26 108,43 108,70 C108,97 95,120 68,120 C41,120 28,97 28,70 C28,43 46,26 68,26 Z" fill="#3B6FFF" stroke="rgba(255,255,255,0.32)" stroke-width="2.5"/>
  <ellipse cx="51" cy="44" rx="11" ry="7" fill="rgba(255,255,255,0.2)" transform="rotate(-28 51 44)"/>
  <circle cx="55" cy="61" r="12.5" fill="white"/>
  <circle cx="80" cy="61" r="12.5" fill="white"/>
  <circle cx="58" cy="65" r="7.5" fill="#1A1A2E"/>
  <circle cx="83" cy="65" r="7.5" fill="#1A1A2E"/>
  <circle cx="60.5" cy="61.5" r="3" fill="white"/>
  <circle cx="85.5" cy="61.5" r="3" fill="white"/>
  <rect x="36" y="112" width="128" height="14" rx="6" fill="#8FA4BD"/>
  <rect x="43" y="77" width="114" height="38" rx="8" fill="#8FA4BD"/>
  <rect x="48" y="82" width="104" height="28" rx="5" fill="white"/>
  <rect x="48" y="82" width="104" height="28" rx="5" fill="#3B6FFF" fill-opacity="0.06"/>
  <path d="M100,87 L102.2,93 L108,95 L102.2,97 L100,103 L97.8,97 L92,95 L97.8,93 Z" fill="#3B6FFF" opacity="0.9"/>
  <line x1="43" y1="112" x2="157" y2="112" stroke="#6B84A0" stroke-width="1.5"/>
</svg>
''';

/// Just the blue character's face — used where the full scene would be too
/// busy, notably at the centre of the Waiting screen's rings.
const String _mascotFaceSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 72 76" fill="none">
  <path d="M36,4 C53,4 64,16 64,36 C64,56 53,72 36,72 C19,72 8,56 8,36 C8,16 19,4 36,4 Z" fill="#3B6FFF" stroke="rgba(255,255,255,0.3)" stroke-width="2"/>
  <ellipse cx="24" cy="34" rx="9.5" ry="9.5" fill="white"/>
  <ellipse cx="48" cy="34" rx="9.5" ry="9.5" fill="white"/>
  <circle cx="26" cy="37" r="5.5" fill="#1A1A2E"/>
  <circle cx="50" cy="37" r="5.5" fill="#1A1A2E"/>
  <circle cx="28" cy="34" r="2" fill="white"/>
  <circle cx="52" cy="34" r="2" fill="white"/>
</svg>
''';

/// Blue blob with eyes, yellow blob without, and a laptop. 4:3 aspect.
class CoStudyMascot extends StatelessWidget {
  const CoStudyMascot({super.key, this.width = 200});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      _mascotSvg,
      width: width,
      height: width * 0.75,
    );
  }
}

/// The face alone, square.
class MascotFace extends StatelessWidget {
  const MascotFace({super.key, this.size = 68});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(_mascotFaceSvg, width: size, height: size);
  }
}

/// The prototype's `mascotFloat` keyframe: a 7px bob on a 3s ease-in-out loop.
///
/// Small enough to read as breathing rather than motion. On the Waiting screen
/// it is doing real work — it is the difference between "the system is
/// thinking" and "the app has hung".
class FloatingMascot extends StatefulWidget {
  const FloatingMascot({super.key, required this.child});

  final Widget child;

  @override
  State<FloatingMascot> createState() => _FloatingMascotState();
}

class _FloatingMascotState extends State<FloatingMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);

  late final Animation<double> _offset = Tween<double>(begin: 0, end: -7)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offset,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _offset.value),
        child: child,
      ),
      child: widget.child,
    );
  }
}
