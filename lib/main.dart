import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'task_planner.dart';

final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
bool _notificationsReady = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  try {
    final localTimezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTimezone.identifier));
  } catch (error) {
    debugPrint('Часовой пояс устройства недоступен: $error');
  }
  await _notifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
  );
  await _notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
  await _notifications
      .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(alert: true, badge: true, sound: true);
  _notificationsReady = true;
  runApp(const AntiProcrastinationApp());
}

class AntiProcrastinationApp extends StatelessWidget {
  const AntiProcrastinationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Мой ритм',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F7A67),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class PlaylistCategory {
  String name;
  List<String> motivationalTexts;
  IconData icon;
  Color color;

  PlaylistCategory({
    required this.name,
    required this.motivationalTexts,
    required this.icon,
    required this.color,
  });

  String get motivation => motivationalTexts.isEmpty
      ? 'Ты справишься. Начни с одного небольшого шага.'
      : motivationalTexts[Random().nextInt(motivationalTexts.length)];
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _dayNames = [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ];

  int _currentIndex = 0;
  int _nextTaskId = 3;
  bool _loading = true;
  Timer? _timer;
  final Set<int> _shownReminderIds = {};
  final List<PlaylistCategory> _playlists = [
    PlaylistCategory(
      name: 'Похудение',
      motivationalTexts: [
        'Вспомни, ради чего ты начинала! Каждая тренировка делает тебя сильнее!',
        '20 минут тренировки — и ты на шаг ближе к цели!',
      ],
      icon: Icons.fitness_center,
      color: const Color(0xFFFF7C6B),
    ),
    PlaylistCategory(
      name: 'Учеба и IT',
      motivationalTexts: [
        'Твой код меняет мир! Шаг за шагом к большим проектам.',
        'Сосредоточься на одном маленьком шаге. Ты уже продвигаешься.',
      ],
      icon: Icons.code,
      color: const Color(0xFF65B8E8),
    ),
  ];
  final List<WeeklyBlock> _weeklyBlocks = [
    for (var weekday = 1; weekday <= 5; weekday++)
      WeeklyBlock(
        weekday: weekday,
        title: 'Учеба / работа',
        startMinute: 9 * 60,
        endMinute: 13 * 60,
      ),
  ];
  final List<TaskItem> _tasks = [
    TaskItem(
      id: 1,
      title: 'Пробежка 20 минут',
      playlistName: 'Похудение',
      isImportant: true,
      durationMinutes: 30,
      deadline: DateTime.now().add(const Duration(hours: 5)),
    ),
    TaskItem(
      id: 2,
      title: 'Повторить физику',
      playlistName: 'Учеба и IT',
      isImportant: false,
      durationMinutes: 60,
      deadline: DateTime.now().add(const Duration(days: 2)),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _restoreState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _checkTasks());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _reflowTasks() {
    final now = DateTime.now();
    for (final task in _tasks) {
      task.scheduledAt = null;
    }
    final ordered = [..._tasks]
      ..sort((a, b) {
        if (a.isImportant != b.isImportant) return a.isImportant ? -1 : 1;
        final aDeadline = a.deadline ?? DateTime(9999);
        final bDeadline = b.deadline ?? DateTime(9999);
        return aDeadline.compareTo(bDeadline);
      });
    for (final task in ordered) {
      TaskPlanner.schedule(
        task: task,
        now: now,
        weeklyBlocks: _weeklyBlocks,
        tasks: _tasks,
      );
    }
  }

  Future<void> _restoreState() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString('anti_procrastination_state');
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _playlists
          ..clear()
          ..addAll((data['playlists'] as List<dynamic>).map((item) {
            final value = item as Map<String, dynamic>;
            return PlaylistCategory(
              name: value['name'] as String,
              motivationalTexts: (value['phrases'] as List<dynamic>).cast<String>(),
              icon: IconData(value['icon'] as int, fontFamily: 'MaterialIcons'),
              color: Color(value['color'] as int),
            );
          }));
        _weeklyBlocks
          ..clear()
          ..addAll((data['blocks'] as List<dynamic>).map((item) {
            final value = item as Map<String, dynamic>;
            return WeeklyBlock(
              weekday: value['weekday'] as int,
              title: value['title'] as String,
              startMinute: value['start'] as int,
              endMinute: value['end'] as int,
            );
          }));
        _tasks
          ..clear()
          ..addAll((data['tasks'] as List<dynamic>).map((item) {
            final value = item as Map<String, dynamic>;
            return TaskItem(
              id: value['id'] as int,
              title: value['title'] as String,
              playlistName: value['playlist'] as String,
              isImportant: value['important'] as bool,
              durationMinutes: value['duration'] as int,
              deadline: value['deadline'] == null ? null : DateTime.parse(value['deadline'] as String),
              scheduledAt: value['scheduledAt'] == null ? null : DateTime.parse(value['scheduledAt'] as String),
            );
          }));
        _nextTaskId = _tasks.fold<int>(0, (maximum, task) => max(maximum, task.id)) + 1;
      }
    } catch (error) {
      debugPrint('Не удалось загрузить сохраненные данные: $error');
    }
    _reflowTasks();
    await _saveState();
    await _syncNotifications();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveState() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('anti_procrastination_state', jsonEncode({
      'playlists': _playlists.map((playlist) => {
            'name': playlist.name,
            'phrases': playlist.motivationalTexts,
            'icon': playlist.icon.codePoint,
            'color': playlist.color.toARGB32(),
          }).toList(),
      'blocks': _weeklyBlocks.map((block) => {
            'weekday': block.weekday,
            'title': block.title,
            'start': block.startMinute,
            'end': block.endMinute,
          }).toList(),
      'tasks': _tasks.map((task) => {
            'id': task.id,
            'title': task.title,
            'playlist': task.playlistName,
            'important': task.isImportant,
            'duration': task.durationMinutes,
            'deadline': task.deadline?.toIso8601String(),
            'scheduledAt': task.scheduledAt?.toIso8601String(),
          }).toList(),
    }));
  }

  void _persistAndSync() {
    unawaited(_saveState());
    unawaited(_syncNotifications());
  }

  Future<void> _syncNotifications() async {
    if (!_notificationsReady) return;
    await _notifications.cancelAll();
    final now = DateTime.now();
    for (final task in _tasks) {
      final scheduledAt = task.scheduledAt;
      if (task.isCompleted || scheduledAt == null || !scheduledAt.isAfter(now)) continue;
      final phrase = _playlistFor(task.playlistName).motivation;
      await _notifications.zonedSchedule(
        id: task.id,
        title: task.title,
        body: phrase,
        scheduledDate: tz.TZDateTime.from(scheduledAt, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'task_reminders',
            'Напоминания о задачах',
            channelDescription: 'Задачи вместе с личной мотивационной фразой',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  void _checkTasks() {
    final now = DateTime.now();
    final overdue = _tasks.where((task) =>
      !task.isCompleted &&
      task.scheduledAt != null &&
      task.scheduledAt!.add(Duration(minutes: task.durationMinutes)).isBefore(now));
    var changed = false;
    for (final task in overdue) {
      if (!_shownReminderIds.contains(task.id)) {
        _shownReminderIds.add(task.id);
        final playlist = _playlistFor(task.playlistName);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${task.title}. ${playlist.motivation}')),
        );
      }
      task.scheduledAt = null;
      _shownReminderIds.remove(task.id);
      changed = true;
    }
    if (changed && mounted) {
      _reflowTasks();
      unawaited(_saveState());
      unawaited(_syncNotifications());
      setState(() {});
    }
  }

  PlaylistCategory _playlistFor(String name) => _playlists.firstWhere(
        (playlist) => playlist.name == name,
        orElse: () => _playlists.first,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? 'Мой ритм' : 'Шаблон недели'),
        actions: [
          if (_currentIndex == 0)
            IconButton(
              tooltip: 'Добавить категорию',
              onPressed: () => _showPlaylistDialog(),
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
        ],
      ),
        body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_currentIndex == 0 ? _buildTasksScreen() : _buildScheduleScreen()),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.checklist), label: 'Задачи'),
          NavigationDestination(icon: Icon(Icons.calendar_view_week), label: 'Неделя'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _currentIndex == 0 ? _showAddTaskDialog : _showAddBlockDialog,
        icon: Icon(_currentIndex == 0 ? Icons.add_task : Icons.event_available),
        label: Text(_currentIndex == 0 ? 'Новая задача' : 'Постоянное дело'),
      ),
    );
  }

  Widget _buildTasksScreen() {
    final sortedTasks = [..._tasks]
      ..sort((a, b) => (a.scheduledAt ?? DateTime(9999))
          .compareTo(b.scheduledAt ?? DateTime(9999)));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Цели и мотивация', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            Text('${_playlists.length}', style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
        const SizedBox(height: 10),
        if (_playlists.isEmpty)
          const ListTile(title: Text('Добавь первую категорию целей'))
        else
          ..._playlists.map((playlist) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () => _showPlaylistDialog(playlist),
                  leading: CircleAvatar(
                    backgroundColor: playlist.color.withValues(alpha: 0.18),
                    child: Icon(playlist.icon, color: playlist.color),
                  ),
                  title: Text(playlist.name),
                  subtitle: Text('${playlist.motivationalTexts.length} фраз мотивации'),
                  trailing: const Icon(Icons.edit_outlined),
                ),
              )),
        const SizedBox(height: 20),
        const Text('Запланированные задачи', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (sortedTasks.isEmpty)
          const ListTile(title: Text('Пока нет задач. Добавь первую, и я найду для нее окно.'))
        else
          ...sortedTasks.map(_buildTaskTile),
      ],
    );
  }

  Widget _buildTaskTile(TaskItem task) {
    final playlist = _playlistFor(task.playlistName);
    final critical = task.isCriticalAt(DateTime.now());
    final slotLabel = task.scheduledAt == null
        ? 'Нет свободного окна в ближайшие 14 дней'
        : '${_dayNames[task.scheduledAt!.weekday - 1]}, ${_formatDate(task.scheduledAt!)} · ${_formatTime(task.scheduledAt!)}';
    final deadlineLabel = task.deadline == null
        ? 'Без дедлайна'
        : 'Дедлайн ${_formatDateTime(task.deadline!)}${critical ? ' · Критический' : ''}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Checkbox(
          value: task.isCompleted,
          onChanged: (_) {
            setState(() {
              _tasks.removeWhere((item) => item.id == task.id);
              _shownReminderIds.remove(task.id);
              _reflowTasks();
              _persistAndSync();
            });
          },
        ),
        title: Text(task.title),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$slotLabel · ${task.durationMinutes} мин'),
              Text('$deadlineLabel · ${task.isImportant ? 'Важная' : 'Обычная'}'),
              Text(playlist.name, style: TextStyle(color: playlist.color)),
            ],
          ),
        ),
        trailing: IconButton(
          tooltip: 'Мотивация',
          icon: const Icon(Icons.lightbulb_outline),
          onPressed: () => _showMotivation(playlist),
        ),
        isThreeLine: true,
      ),
    );
  }

  Widget _buildScheduleScreen() {
    final today = DateTime.now();
    final monday = DateTime(today.year, today.month, today.day - today.weekday + 1);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: 7,
      itemBuilder: (context, index) {
        final date = monday.add(Duration(days: index));
        final entries = _entriesForDay(date);
        final freeCount = entries.where((entry) => entry.isFree).length;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            title: Text(_dayNames[index], style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${_formatDate(date)} · свободных окон: $freeCount'),
            children: [
              if (entries.isEmpty)
                const ListTile(title: Text('Нет событий в диапазоне 08:00–22:00')),
              for (final entry in entries)
                ListTile(
                  dense: true,
                  leading: Icon(
                    entry.isFree ? Icons.more_time : (entry.isTask ? Icons.task_alt : Icons.repeat),
                    color: entry.isFree ? Colors.lightGreenAccent : null,
                  ),
                  title: Text(entry.isFree ? 'Свободно' : entry.title),
                  subtitle: Text('${_minuteTime(entry.startMinute)}–${_minuteTime(entry.endMinute)}'),
                  trailing: entry.isBlock
                      ? IconButton(
                          tooltip: 'Удалить постоянное дело',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => setState(() {
                            _weeklyBlocks.remove(entry.block);
                            _reflowTasks();
                            _persistAndSync();
                          }),
                        )
                      : null,
                ),
            ],
          ),
        );
      },
    );
  }

  List<_CalendarEntry> _entriesForDay(DateTime date) {
    final entries = <_CalendarEntry>[
      for (final block in _weeklyBlocks.where((item) => item.weekday == date.weekday))
        _CalendarEntry(
          title: block.title,
          startMinute: block.startMinute,
          endMinute: block.endMinute,
          isBlock: true,
          block: block,
        ),
      for (final task in _tasks.where((item) =>
          item.scheduledAt != null &&
          item.scheduledAt!.year == date.year &&
          item.scheduledAt!.month == date.month &&
          item.scheduledAt!.day == date.day))
        _CalendarEntry(
          title: task.title,
          startMinute: task.scheduledAt!.hour * 60 + task.scheduledAt!.minute,
          endMinute: task.scheduledAt!.hour * 60 + task.scheduledAt!.minute + task.durationMinutes,
          isTask: true,
        ),
    ]..sort((a, b) => a.startMinute.compareTo(b.startMinute));

    final withFreeTime = <_CalendarEntry>[];
    var cursor = 8 * 60;
    for (final entry in entries) {
      if (entry.startMinute > cursor) {
        withFreeTime.add(_CalendarEntry(
          title: 'Свободно',
          startMinute: cursor,
          endMinute: entry.startMinute,
          isFree: true,
        ));
      }
      withFreeTime.add(entry);
      if (entry.endMinute > cursor) cursor = entry.endMinute;
    }
    if (cursor < 22 * 60) {
      withFreeTime.add(_CalendarEntry(
        title: 'Свободно',
        startMinute: cursor,
        endMinute: 22 * 60,
        isFree: true,
      ));
    }
    return withFreeTime;
  }

  Future<void> _showAddTaskDialog() async {
    if (_playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала создай категорию целей')),
      );
      return;
    }
    final titleController = TextEditingController();
    var playlistName = _playlists.first.name;
    var duration = 60;
    var important = false;
    DateTime? deadline;
    final task = await showDialog<TaskItem>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Новая задача'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Название'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: playlistName,
                  decoration: const InputDecoration(labelText: 'Категория'),
                  items: _playlists.map((item) => DropdownMenuItem(value: item.name, child: Text(item.name))).toList(),
                  onChanged: (value) => setDialogState(() => playlistName = value ?? playlistName),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: duration,
                  decoration: const InputDecoration(labelText: 'Длительность'),
                  items: const [30, 60, 90, 120]
                      .map((value) => DropdownMenuItem(value: value, child: Text('$value минут')))
                      .toList(),
                  onChanged: (value) => setDialogState(() => duration = value ?? duration),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Важная задача'),
                  value: important,
                  onChanged: (value) => setDialogState(() => important = value),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final selected = await showDatePicker(
                      context: dialogContext,
                      initialDate: deadline ?? DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                    );
                    if (selected != null) {
                      setDialogState(() => deadline = DateTime(selected.year, selected.month, selected.day, 23, 59));
                    }
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text(deadline == null ? 'Добавить дедлайн' : 'Дедлайн: ${_formatDate(deadline!)}'),
                ),
                if (deadline != null)
                  TextButton(
                    onPressed: () => setDialogState(() => deadline = null),
                    child: const Text('Убрать дедлайн'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
            FilledButton(
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isEmpty) return;
                Navigator.pop(
                  dialogContext,
                  TaskItem(
                    id: _nextTaskId++,
                    title: title,
                    playlistName: playlistName,
                    isImportant: important,
                    durationMinutes: duration,
                    deadline: deadline,
                  ),
                );
              },
              child: const Text('Найти время'),
            ),
          ],
        ),
      ),
    );
    titleController.dispose();
    if (task == null || !mounted) return;
    setState(() {
      _tasks.add(task);
      TaskPlanner.schedule(task: task, now: DateTime.now(), weeklyBlocks: _weeklyBlocks, tasks: _tasks);
      _persistAndSync();
    });
    if (task.scheduledAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Окно не найдено. Попробуй увеличить срок или изменить расписание.')),
      );
    }
  }

  Future<void> _showPlaylistDialog([PlaylistCategory? existing]) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final phrasesController = TextEditingController(text: existing?.motivationalTexts.join('\n') ?? '');
    final result = await showDialog<PlaylistCategory>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null ? 'Новая категория' : 'Категория'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, autofocus: true, decoration: const InputDecoration(labelText: 'Название')),
              const SizedBox(height: 12),
              TextField(
                controller: phrasesController,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Мотивационные фразы',
                  hintText: 'Каждая фраза с новой строки',
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, PlaylistCategory(name: '', motivationalTexts: [], icon: Icons.circle, color: Colors.transparent)),
              child: const Text('Удалить'),
            ),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              final duplicate = _playlists.any((item) => item.name == name && item != existing);
              if (duplicate) return;
              Navigator.pop(
                dialogContext,
                PlaylistCategory(
                  name: name,
                  motivationalTexts: phrasesController.text
                      .split('\n')
                      .map((phrase) => phrase.trim())
                      .where((phrase) => phrase.isNotEmpty)
                      .toList(),
                  icon: existing?.icon ?? Icons.flag_outlined,
                  color: existing?.color ?? const Color(0xFF8CCB75),
                ),
              );
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    nameController.dispose();
    phrasesController.dispose();
    if (result == null || !mounted) return;
    setState(() {
      if (result.name.isEmpty && existing != null) {
        _playlists.remove(existing);
        _tasks.removeWhere((task) => task.playlistName == existing.name);
        _reflowTasks();
      } else if (existing == null) {
        _playlists.add(result);
      } else {
        final oldName = existing.name;
        existing
          ..name = result.name
          ..motivationalTexts = result.motivationalTexts;
        for (final task in _tasks.where((task) => task.playlistName == oldName)) {
          task.playlistName = result.name;
        }
      }
      _persistAndSync();
    });
  }

  Future<void> _showAddBlockDialog() async {
    final titleController = TextEditingController();
    var weekday = DateTime.now().weekday;
    var start = const TimeOfDay(hour: 9, minute: 0);
    var end = const TimeOfDay(hour: 10, minute: 0);
    final block = await showDialog<WeeklyBlock>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Постоянное дело'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleController, autofocus: true, decoration: const InputDecoration(labelText: 'Название')),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: weekday,
                decoration: const InputDecoration(labelText: 'День недели'),
                items: List.generate(7, (index) => DropdownMenuItem(value: index + 1, child: Text(_dayNames[index]))),
                onChanged: (value) => setDialogState(() => weekday = value ?? weekday),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        final value = await showTimePicker(context: dialogContext, initialTime: start);
                        if (value != null) setDialogState(() => start = value);
                      },
                      child: Text('С ${start.format(context)}'),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        final value = await showTimePicker(context: dialogContext, initialTime: end);
                        if (value != null) setDialogState(() => end = value);
                      },
                      child: Text('До ${end.format(context)}'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
            FilledButton(
              onPressed: () {
                final title = titleController.text.trim();
                final startMinute = start.hour * 60 + start.minute;
                final endMinute = end.hour * 60 + end.minute;
                if (title.isEmpty ||
                    startMinute < 8 * 60 ||
                    endMinute > 22 * 60 ||
                    startMinute >= endMinute) {
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  WeeklyBlock(weekday: weekday, title: title, startMinute: startMinute, endMinute: endMinute),
                );
              },
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
    titleController.dispose();
    if (block == null || !mounted) return;
    final overlapsRoutine = _weeklyBlocks.any((existing) =>
        existing.weekday == block.weekday &&
        existing.startMinute < block.endMinute &&
        block.startMinute < existing.endMinute);
    if (overlapsRoutine) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Это время уже занято постоянным делом.')),
      );
      return;
    }
    setState(() {
      _weeklyBlocks.add(block);
      _reflowTasks();
      _persistAndSync();
    });
  }

  void _showMotivation(PlaylistCategory playlist) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(playlist.name),
        content: Text(playlist.motivation),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Начинаю')),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';

  String _formatTime(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  String _formatDateTime(DateTime date) => '${_formatDate(date)} ${_formatTime(date)}';

  String _minuteTime(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
}

class _CalendarEntry {
  final String title;
  final int startMinute;
  final int endMinute;
  final bool isFree;
  final bool isTask;
  final bool isBlock;
  final WeeklyBlock? block;

  const _CalendarEntry({
    required this.title,
    required this.startMinute,
    required this.endMinute,
    this.isFree = false,
    this.isTask = false,
    this.isBlock = false,
    this.block,
  });
}