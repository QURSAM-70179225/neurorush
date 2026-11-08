import 'dart:math' as math;

/// Builds [count] distinct, non-negative multiple-choice options that include
/// [answer], using plausible near-miss distractors (plus any [tempting] wrong
/// answers that come from applying the wrong rule).
List<int> buildNumericOptions(
  math.Random r,
  int answer, {
  int count = 4,
  Iterable<int> tempting = const [],
}) {
  final opts = <int>{answer};
  for (final t in tempting) {
    if (opts.length >= count) break;
    if (t >= 0) opts.add(t);
  }
  final offsets = <int>[1, 2, 3, 10, if (answer >= 20) 20];
  var guard = 0;
  while (opts.length < count && guard++ < 100) {
    final v = answer + offsets[r.nextInt(offsets.length)] * (r.nextBool() ? 1 : -1);
    if (v >= 0) opts.add(v);
  }
  var fill = answer + 4;
  while (opts.length < count) {
    opts.add(fill++);
  }
  return opts.toList()..shuffle(r);
}
