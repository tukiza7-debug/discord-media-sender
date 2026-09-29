/// Utiliti tunggu dikongsi (dipindahkan keluar dari foreground_manager — B22).
library;

/// Tamat masa tunggu yang boleh dijeda/batalkan (dipakai enjin).
Future<bool> interruptibleWait({
  required int milliseconds,
  required bool Function() isPaused,
  required bool Function() isCancelled,
  Duration step = const Duration(milliseconds: 100),
}) async {
  var waited = 0;
  while (waited < milliseconds) {
    if (isCancelled()) return false;
    if (!isPaused()) waited += step.inMilliseconds;
    await Future<void>.delayed(step);
  }
  return !isCancelled();
}
