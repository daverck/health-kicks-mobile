import 'package:material_ui/material_ui.dart';

/// Vector illustration widget rendering 24x24 activity icons matching the web ActivityIconComponent.
class ActivitySvgIcon extends StatelessWidget {
  final String activityKey;
  final double size;
  final Color? color;

  const ActivitySvgIcon({
    super.key,
    required this.activityKey,
    this.size = 20,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.primary;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size.square(size),
        painter: _ActivitySvgPainter(
          activityKey: activityKey.toLowerCase().trim(),
          color: effectiveColor,
        ),
      ),
    );
  }
}

class _ActivitySvgPainter extends CustomPainter {
  final String activityKey;
  final Color color;

  const _ActivitySvgPainter({
    required this.activityKey,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.scale(size.width / 24.0, size.height / 24.0);

    switch (activityKey) {
      case 'walk':
        _paintWalk(canvas, strokePaint);
      case 'run':
        _paintRun(canvas, strokePaint);
      case 'idle':
        _paintIdle(canvas, strokePaint, fillPaint);
      case 'sit_down':
        _paintSitDown(canvas, strokePaint);
      case 'stand_up':
        _paintStandUp(canvas, strokePaint);
      case 'lie_down':
      case 'lying_supine':
      case 'lying_prone':
      case 'lying_lateral':
        _paintLying(canvas, strokePaint);
      case 'stairs':
      case 'stairs_up':
      case 'stairs_down':
      case 'jump':
        _paintStairsOrJump(canvas, strokePaint);
      case 'stumble_recover':
      case 'fall_forward':
      case 'fall_backward':
      case 'fall_lateral':
      case 'fall_recovery':
        _paintFallsAndRecovery(canvas, strokePaint);
      default:
        _paintCustomFlask(canvas, strokePaint);
    }

    canvas.restore();
  }

  void _drawPolyline(Canvas canvas, Paint paint, List<Offset> points) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  void _paintWalk(Canvas canvas, Paint paint) {
    canvas.drawCircle(const Offset(13, 4.5), 2, paint);
    _drawPolyline(canvas, paint, const [Offset(12.5, 7), Offset(11.5, 13.5)]);
    _drawPolyline(canvas, paint, const [
      Offset(7.5, 12.5),
      Offset(9, 10.5),
      Offset(12.2, 8.5),
      Offset(15.5, 11),
      Offset(17.5, 9.5),
    ]);
    _drawPolyline(
        canvas, paint, const [Offset(11.5, 13.5), Offset(14.5, 17), Offset(15.5, 21)]);
    _drawPolyline(
        canvas, paint, const [Offset(11.5, 13.5), Offset(9, 17), Offset(7, 20.5)]);
  }

  void _paintRun(Canvas canvas, Paint paint) {
    canvas.drawCircle(const Offset(15.5, 4.5), 2, paint);
    _drawPolyline(canvas, paint, const [Offset(14, 7), Offset(10.5, 13)]);
    _drawPolyline(canvas, paint, const [
      Offset(7.5, 10.5),
      Offset(10, 8),
      Offset(13.2, 8.2),
      Offset(16.5, 10.5),
      Offset(18.5, 8.5),
    ]);
    _drawPolyline(
        canvas, paint, const [Offset(10.5, 13), Offset(15, 15.5), Offset(17.5, 19.5)]);
    _drawPolyline(
        canvas, paint, const [Offset(10.5, 13), Offset(7.5, 16.5), Offset(4.5, 17.5)]);
  }

  void _paintIdle(Canvas canvas, Paint strokePaint, Paint fillPaint) {
    canvas.drawLine(const Offset(6, 19), const Offset(6, 21), strokePaint);
    canvas.drawLine(const Offset(18, 19), const Offset(18, 21), strokePaint);
    canvas.drawRRect(
      RRect.fromLTRBAndCorners(
        5,
        9,
        19,
        18,
        topLeft: const Radius.circular(2),
        topRight: const Radius.circular(2),
        bottomLeft: const Radius.circular(3),
        bottomRight: const Radius.circular(3),
      ),
      strokePaint,
    );
    canvas.drawLine(const Offset(4, 13), const Offset(6, 13), strokePaint);
    canvas.drawLine(const Offset(18, 13), const Offset(20, 13), strokePaint);
    final handle = Path()
      ..moveTo(8, 9)
      ..lineTo(8, 6)
      ..arcToPoint(const Offset(11, 3), radius: const Radius.circular(3))
      ..lineTo(13, 3)
      ..arcToPoint(const Offset(16, 6), radius: const Radius.circular(3))
      ..lineTo(16, 9);
    canvas.drawPath(handle, strokePaint);
    canvas.drawCircle(const Offset(12, 13.5), 1.5, fillPaint);
  }

  void _paintSitDown(Canvas canvas, Paint paint) {
    final backrest = Path()
      ..moveTo(19, 9)
      ..lineTo(19, 6)
      ..arcToPoint(
        const Offset(17, 4),
        radius: const Radius.circular(2),
        clockwise: false,
      )
      ..lineTo(7, 4)
      ..arcToPoint(
        const Offset(5, 6),
        radius: const Radius.circular(2),
        clockwise: false,
      )
      ..lineTo(5, 9);
    canvas.drawPath(backrest, paint);

    final cushion = Path()
      ..moveTo(3, 16)
      ..arcToPoint(
        const Offset(5, 18),
        radius: const Radius.circular(2),
        clockwise: false,
      )
      ..lineTo(19, 18)
      ..arcToPoint(
        const Offset(21, 16),
        radius: const Radius.circular(2),
        clockwise: false,
      )
      ..lineTo(21, 11)
      ..arcToPoint(
        const Offset(17, 11),
        radius: const Radius.circular(2),
        clockwise: false,
      )
      ..lineTo(17, 12.5)
      ..arcToPoint(const Offset(16.5, 13), radius: const Radius.circular(0.5))
      ..lineTo(7.5, 13)
      ..arcToPoint(const Offset(7, 12.5), radius: const Radius.circular(0.5))
      ..lineTo(7, 11)
      ..arcToPoint(
        const Offset(3, 11),
        radius: const Radius.circular(2),
        clockwise: false,
      )
      ..close();
    canvas.drawPath(cushion, paint);
    canvas.drawLine(const Offset(5, 18), const Offset(5, 20), paint);
    canvas.drawLine(const Offset(19, 18), const Offset(19, 20), paint);
  }

  void _paintStandUp(Canvas canvas, Paint paint) {
    canvas.drawCircle(const Offset(12, 4), 2, paint);
    canvas.drawLine(const Offset(12, 6), const Offset(12, 14), paint);
    _drawPolyline(canvas, paint, const [Offset(9, 10), Offset(12, 8), Offset(15, 10)]);
    _drawPolyline(canvas, paint, const [Offset(9, 20), Offset(12, 14), Offset(15, 20)]);
  }

  void _paintLying(Canvas canvas, Paint paint) {
    canvas.drawLine(const Offset(2, 19), const Offset(22, 19), paint);
    switch (activityKey) {
      case 'lie_down':
        final bed = Path()
          ..moveTo(4, 19)
          ..lineTo(4, 15)
          ..arcToPoint(const Offset(6, 13), radius: const Radius.circular(2))
          ..lineTo(18, 13)
          ..arcToPoint(const Offset(20, 15), radius: const Radius.circular(2))
          ..lineTo(20, 19);
        canvas.drawPath(bed, paint);
        canvas.drawCircle(const Offset(8, 10), 2, paint);
        canvas.drawLine(const Offset(12, 11), const Offset(16, 13), paint);
      case 'lying_supine':
        canvas.drawLine(const Offset(3, 15), const Offset(21, 15), paint);
        canvas.drawCircle(const Offset(6, 11.5), 2, paint);
        canvas.drawLine(const Offset(10, 13), const Offset(19, 13), paint);
        canvas.drawLine(const Offset(19, 13), const Offset(19, 15), paint);
      case 'lying_prone':
        canvas.drawLine(const Offset(3, 15), const Offset(21, 15), paint);
        canvas.drawCircle(const Offset(6, 12.5), 2, paint);
        canvas.drawLine(const Offset(10, 13), const Offset(19, 13), paint);
        canvas.drawLine(const Offset(4, 14), const Offset(6, 15), paint);
      case 'lying_lateral':
        canvas.drawLine(const Offset(3, 15), const Offset(21, 15), paint);
        canvas.drawCircle(const Offset(6, 11), 2, paint);
        canvas.drawLine(const Offset(10, 12), const Offset(18, 12), paint);
        canvas.drawLine(const Offset(14, 12), const Offset(16, 15), paint);
    }
  }

  void _paintStairsOrJump(Canvas canvas, Paint paint) {
    switch (activityKey) {
      case 'stairs':
        _drawPolyline(canvas, paint, const [
          Offset(4, 19),
          Offset(8, 19),
          Offset(8, 15),
          Offset(12, 15),
          Offset(12, 11),
          Offset(16, 11),
          Offset(16, 7),
          Offset(20, 7),
        ]);
        _drawPolyline(canvas, paint, const [
          Offset(4, 19),
          Offset(4, 21),
          Offset(20, 21),
          Offset(20, 19),
        ]);
      case 'stairs_up':
        _drawPolyline(canvas, paint, const [
          Offset(4, 20),
          Offset(8, 20),
          Offset(8, 16),
          Offset(12, 16),
          Offset(12, 12),
          Offset(16, 12),
          Offset(16, 8),
          Offset(20, 8),
        ]);
        canvas.drawLine(const Offset(4, 11), const Offset(11, 4), paint);
        _drawPolyline(canvas, paint, const [Offset(7, 4), Offset(11, 4), Offset(11, 8)]);
      case 'stairs_down':
        _drawPolyline(canvas, paint, const [
          Offset(4, 8),
          Offset(8, 8),
          Offset(8, 12),
          Offset(12, 12),
          Offset(12, 16),
          Offset(16, 16),
          Offset(16, 20),
          Offset(20, 20),
        ]);
        canvas.drawLine(const Offset(13, 4), const Offset(20, 11), paint);
        _drawPolyline(canvas, paint, const [Offset(16, 11), Offset(20, 11), Offset(20, 7)]);
      case 'jump':
        canvas.drawCircle(const Offset(12, 4.5), 2, paint);
        _drawPolyline(
            canvas, paint, const [Offset(6.5, 6), Offset(12, 9), Offset(17.5, 6)]);
        canvas.drawLine(const Offset(12, 7), const Offset(12, 13.5), paint);
        _drawPolyline(
            canvas, paint, const [Offset(12, 13.5), Offset(8.5, 16), Offset(9.5, 19)]);
        _drawPolyline(
            canvas, paint, const [Offset(12, 13.5), Offset(15.5, 16), Offset(14.5, 19)]);
        canvas.drawLine(const Offset(7, 22), const Offset(17, 22), paint);
    }
  }

  void _paintFallsAndRecovery(Canvas canvas, Paint paint) {
    canvas.drawLine(const Offset(3, 21), const Offset(21, 21), paint);
    switch (activityKey) {
      case 'stumble_recover':
        _drawPolyline(
            canvas, paint, const [Offset(9, 21), Offset(10.5, 18.5), Offset(12, 21)]);
        canvas.drawCircle(const Offset(16.5, 5.5), 2, paint);
        canvas.drawLine(const Offset(15, 7.5), const Offset(11, 13.5), paint);
        _drawPolyline(
            canvas, paint, const [Offset(10.5, 6.5), Offset(13.8, 9.2), Offset(18.5, 10.5)]);
        _drawPolyline(
            canvas, paint, const [Offset(11, 13.5), Offset(8.5, 17), Offset(6, 18.5)]);
        _drawPolyline(
            canvas, paint, const [Offset(11, 13.5), Offset(15, 16.5), Offset(15.5, 21)]);
        canvas.drawLine(const Offset(6, 9.5), const Offset(8.5, 8.5), paint);
      case 'fall_forward':
        canvas.drawCircle(const Offset(18.5, 14), 2, paint);
        canvas.drawLine(const Offset(10, 11.5), const Offset(16, 13.5), paint);
        _drawPolyline(
            canvas, paint, const [Offset(15, 13.2), Offset(17.5, 18.5), Offset(19.5, 19)]);
        canvas.drawLine(const Offset(14, 12.8), const Offset(14.5, 18.5), paint);
        _drawPolyline(
            canvas, paint, const [Offset(10, 11.5), Offset(6, 13), Offset(4, 16.5)]);
        _drawPolyline(
            canvas, paint, const [Offset(10, 11.5), Offset(7.5, 16), Offset(6, 20.5)]);
        final arc = Path()
          ..moveTo(11, 5.5)
          ..cubicTo(14.5, 5.5, 17.5, 7.5, 18.5, 10.5);
        canvas.drawPath(arc, paint);
        _drawPolyline(
            canvas, paint, const [Offset(16.5, 9.5), Offset(18.5, 10.5), Offset(19, 8.3)]);
      case 'fall_backward':
        canvas.drawCircle(const Offset(5.5, 13.5), 2, paint);
        canvas.drawLine(const Offset(8, 13.5), const Offset(13.5, 15), paint);
        _drawPolyline(
            canvas, paint, const [Offset(9.5, 13.8), Offset(8, 9), Offset(6, 8)]);
        canvas.drawLine(const Offset(9.5, 13.8), const Offset(12, 9.5), paint);
        _drawPolyline(
            canvas, paint, const [Offset(13.5, 15), Offset(17.5, 13.5), Offset(20, 15)]);
        _drawPolyline(
            canvas, paint, const [Offset(13.5, 15), Offset(17, 18), Offset(19.5, 20)]);
        final arc = Path()
          ..moveTo(13, 5.5)
          ..cubicTo(9.5, 5.5, 6.5, 7.5, 5.5, 10.5);
        canvas.drawPath(arc, paint);
        _drawPolyline(
            canvas, paint, const [Offset(7.5, 9.5), Offset(5.5, 10.5), Offset(5, 8.3)]);
      case 'fall_lateral':
        canvas.drawCircle(const Offset(16.5, 7), 2, paint);
        canvas.drawLine(const Offset(15, 8.5), const Offset(10.5, 14), paint);
        _drawPolyline(
            canvas, paint, const [Offset(11, 5.5), Offset(13.8, 10), Offset(18.5, 13.5)]);
        canvas.drawLine(const Offset(10.5, 14), const Offset(9.5, 20.5), paint);
        canvas.drawLine(const Offset(10.5, 14), const Offset(5.5, 12.5), paint);
        final arc = Path()
          ..moveTo(19.5, 9.5)
          ..cubicTo(20.5, 11.5, 20.5, 14, 19.5, 16);
        canvas.drawPath(arc, paint);
        _drawPolyline(
            canvas, paint, const [Offset(18, 14.5), Offset(19.5, 16), Offset(21, 15)]);
      case 'fall_recovery':
        canvas.drawCircle(const Offset(13.5, 8), 2, paint);
        canvas.drawLine(const Offset(7.5, 15.5), const Offset(12, 10.5), paint);
        _drawPolyline(
            canvas, paint, const [Offset(4, 20.5), Offset(6.5, 20.5), Offset(7.5, 15.5)]);
        _drawPolyline(
            canvas, paint, const [Offset(7.5, 15.5), Offset(11.5, 15.5), Offset(11.5, 20.5)]);
        canvas.drawLine(const Offset(10.8, 11.8), const Offset(14, 14), paint);
        canvas.drawLine(const Offset(18.5, 18), const Offset(18.5, 6), paint);
        _drawPolyline(
            canvas, paint, const [Offset(16, 8.5), Offset(18.5, 6), Offset(21, 8.5)]);
    }
  }

  void _paintCustomFlask(Canvas canvas, Paint paint) {
    final flask = Path()
      ..moveTo(10, 2)
      ..lineTo(10, 9.31)
      ..arcToPoint(const Offset(9.41, 10.72), radius: const Radius.circular(2))
      ..lineTo(4.7, 15.43)
      ..arcToPoint(
        const Offset(4.12, 16.84),
        radius: const Radius.circular(2),
        clockwise: false,
      )
      ..lineTo(4.12, 20)
      ..arcToPoint(
        const Offset(6.12, 22),
        radius: const Radius.circular(2),
        clockwise: false,
      )
      ..lineTo(17.88, 22)
      ..arcToPoint(
        const Offset(19.88, 20),
        radius: const Radius.circular(2),
        clockwise: false,
      )
      ..lineTo(19.88, 16.84)
      ..arcToPoint(
        const Offset(19.3, 15.43),
        radius: const Radius.circular(2),
        clockwise: false,
      )
      ..lineTo(14.59, 10.72)
      ..arcToPoint(const Offset(14, 9.31), radius: const Radius.circular(2))
      ..lineTo(14, 2);
    canvas.drawPath(flask, paint);
    canvas.drawLine(const Offset(8.5, 2), const Offset(15.5, 2), paint);
    canvas.drawLine(const Offset(7, 16), const Offset(17, 16), paint);
  }

  @override
  bool shouldRepaint(covariant _ActivitySvgPainter oldDelegate) =>
      oldDelegate.activityKey != activityKey || oldDelegate.color != color;
}
