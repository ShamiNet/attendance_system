import 'dart:async';

class WorkTimerState {
  final Duration elapsed;
  final bool isRunning;
  final String formattedTime;

  WorkTimerState({
    required this.elapsed,
    required this.isRunning,
    required this.formattedTime,
  });

  factory WorkTimerState.initial() => WorkTimerState(
        elapsed: Duration.zero,
        isRunning: false,
        formattedTime: "00:00:00",
      );
}

class WorkTimerController {
  Timer? _timer;
  DateTime? _startTime;
  final _stateController = StreamController<WorkTimerState>.broadcast();

  Stream<WorkTimerState> get stateStream => _stateController.stream;

  void start(DateTime checkInTime) {
    _startTime = checkInTime;
    _timer?.cancel();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (_startTime == null) return;
    final now = DateTime.now();
    final diff = now.difference(_startTime!);
    final duration = diff.isNegative ? Duration.zero : diff;

    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');

    _stateController.add(
      WorkTimerState(
        elapsed: duration,
        isRunning: true,
        formattedTime: "$hours:$minutes:$seconds",
      ),
    );
  }

  void stop() {
    _timer?.cancel();
    _startTime = null;
    _stateController.add(WorkTimerState.initial());
  }

  void dispose() {
    _timer?.cancel();
    _stateController.close();
  }
}