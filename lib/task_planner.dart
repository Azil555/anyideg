class TaskItem {
  final int id;
  String title;
  String playlistName;
  bool isImportant;
  DateTime? deadline;
  int durationMinutes;
  DateTime? scheduledAt;
  bool isCompleted;

  TaskItem({
    required this.id,
    required this.title,
    required this.playlistName,
    required this.isImportant,
    required this.durationMinutes,
    this.deadline,
    this.scheduledAt,
    this.isCompleted = false,
  });

  bool isCriticalAt(DateTime now) =>
      deadline != null && deadline!.difference(now) <= const Duration(hours: 24);
}

class WeeklyBlock {
  final int weekday;
  final String title;
  final int startMinute;
  final int endMinute;

  const WeeklyBlock({
    required this.weekday,
    required this.title,
    required this.startMinute,
    required this.endMinute,
  });
}

class TaskPlanner {
  static const int _dayStart = 8 * 60;
  static const int _dayEnd = 22 * 60;
  static const int _stepMinutes = 30;
  static const int _searchDays = 14;

  static DateTime? schedule({
    required TaskItem task,
    required DateTime now,
    required List<WeeklyBlock> weeklyBlocks,
    required List<TaskItem> tasks,
  }) {
    final canDisplace = task.isImportant;
    for (var dayOffset = 0; dayOffset < _searchDays; dayOffset++) {
      final day = DateTime(now.year, now.month, now.day + dayOffset);
      var minute = _dayStart;
      if (dayOffset == 0) {
        final nowMinute = now.hour * 60 + now.minute;
        minute = ((nowMinute + _stepMinutes - 1) ~/ _stepMinutes) * _stepMinutes;
        if (minute < _dayStart) minute = _dayStart;
      }

      while (minute + task.durationMinutes <= _dayEnd) {
        final start = DateTime(day.year, day.month, day.day).add(Duration(minutes: minute));
        final end = start.add(Duration(minutes: task.durationMinutes));
        if (task.deadline != null && end.isAfter(task.deadline!)) {
          minute += _stepMinutes;
          continue;
        }

        final hitsRoutine = weeklyBlocks.any((block) =>
            block.weekday == day.weekday &&
            _overlaps(minute, minute + task.durationMinutes, block.startMinute, block.endMinute));
        if (hitsRoutine) {
          minute += _stepMinutes;
          continue;
        }

        final collisions = tasks.where((other) =>
            other.id != task.id &&
            !other.isCompleted &&
            other.scheduledAt != null &&
            _overlapsDateTime(start, end, other.scheduledAt!,
                other.scheduledAt!.add(Duration(minutes: other.durationMinutes)))).toList();

        if (collisions.isEmpty) {
          task.scheduledAt = start;
          return start;
        }

        final movable = canDisplace && collisions.every((other) =>
            !other.isImportant && !other.isCriticalAt(now));
        if (movable && _relocateCollisions(
          task: task,
          start: start,
          collisions: collisions,
          now: now,
          weeklyBlocks: weeklyBlocks,
          tasks: tasks,
        )) {
          return start;
        }
        minute += _stepMinutes;
      }
    }
    return null;
  }

  static bool _relocateCollisions({
    required TaskItem task,
    required DateTime start,
    required List<TaskItem> collisions,
    required DateTime now,
    required List<WeeklyBlock> weeklyBlocks,
    required List<TaskItem> tasks,
  }) {
    final moved = collisions.toSet();
    final reservations = tasks.where((item) => !moved.contains(item)).toList();
    task.scheduledAt = start;
    reservations.add(task);
    final proposedTimes = <TaskItem, DateTime>{};
    final originalTimes = {for (final item in collisions) item: item.scheduledAt};

    for (final displaced in collisions) {
      displaced.scheduledAt = null;
      final replacement = schedule(
        task: displaced,
        now: now,
        weeklyBlocks: weeklyBlocks,
        tasks: reservations,
      );
      if (replacement == null) {
        for (final entry in originalTimes.entries) {
          entry.key.scheduledAt = entry.value;
        }
        task.scheduledAt = null;
        return false;
      }
      proposedTimes[displaced] = replacement;
      reservations.add(displaced);
    }

    for (final entry in proposedTimes.entries) {
      entry.key.scheduledAt = entry.value;
    }
    return true;
  }

  static bool _overlaps(int startA, int endA, int startB, int endB) =>
      startA < endB && startB < endA;

  static bool _overlapsDateTime(DateTime startA, DateTime endA, DateTime startB, DateTime endB) =>
      startA.isBefore(endB) && startB.isBefore(endA);
}