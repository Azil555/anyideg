import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_antideg/task_planner.dart';

void main() {
  final now = DateTime(2026, 10, 10, 8);

  test('important task moves a low-priority task with a distant deadline', () {
    final lowPriority = TaskItem(
      id: 1,
      title: 'Чтение',
      playlistName: 'Учеба',
      isImportant: false,
      durationMinutes: 60,
      deadline: now.add(const Duration(days: 3)),
      scheduledAt: DateTime(2026, 10, 10, 8),
    );
    final important = TaskItem(
      id: 2,
      title: 'Сдать проект',
      playlistName: 'Учеба',
      isImportant: true,
      durationMinutes: 60,
      deadline: now.add(const Duration(days: 1)),
    );
    final tasks = [lowPriority, important];

    final slot = TaskPlanner.schedule(
      task: important,
      now: now,
      weeklyBlocks: const [],
      tasks: tasks,
    );

    expect(slot, DateTime(2026, 10, 10, 8));
    expect(lowPriority.scheduledAt, DateTime(2026, 10, 10, 9));
  });

  test('critical low-priority task cannot be displaced', () {
    final critical = TaskItem(
      id: 1,
      title: 'Оплатить счет',
      playlistName: 'Личное',
      isImportant: false,
      durationMinutes: 60,
      deadline: now.add(const Duration(hours: 12)),
      scheduledAt: now,
    );
    final important = TaskItem(
      id: 2,
      title: 'Важная задача',
      playlistName: 'Работа',
      isImportant: true,
      durationMinutes: 60,
    );
    final tasks = [critical, important];

    final slot = TaskPlanner.schedule(
      task: important,
      now: now,
      weeklyBlocks: const [],
      tasks: tasks,
    );

    expect(slot, DateTime(2026, 10, 10, 9));
    expect(critical.scheduledAt, now);
  });

  test('recurring weekly blocks are skipped when finding a free slot', () {
    final task = TaskItem(
      id: 1,
      title: 'Тренировка',
      playlistName: 'Спорт',
      isImportant: false,
      durationMinutes: 60,
    );

    final slot = TaskPlanner.schedule(
      task: task,
      now: now,
      weeklyBlocks: [
        WeeklyBlock(weekday: now.weekday, title: 'Постоянное занятие', startMinute: 8 * 60, endMinute: 10 * 60),
      ],
      tasks: [task],
    );

    expect(slot, DateTime(2026, 10, 10, 10));
  });
}