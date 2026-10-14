import 'dart:async';
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color _purple = Color(0xFF6750A4);
const String _boxName = 'iqaa_tasks';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox<String>(_boxName);
  final prefs = await SharedPreferences.getInstance();
  runApp(IqaaApp(prefs: prefs));
}

class IqaaApp extends StatefulWidget {
  const IqaaApp({super.key, required this.prefs});
  final SharedPreferences prefs;

  @override
  State<IqaaApp> createState() => _IqaaAppState();
}

class _IqaaAppState extends State<IqaaApp> {
  late ThemeMode _mode = _readMode();
  Locale _locale = const Locale('ar');

  ThemeMode _readMode() {
    final value = widget.prefs.getString('theme_mode');
    if (value == 'light') return ThemeMode.light;
    if (value == 'dark') return ThemeMode.dark;
    return ThemeMode.system;
  }

  Future<void> _setMode(ThemeMode mode) async {
    setState(() => _mode = mode);
    await widget.prefs.setString('theme_mode', mode.name);
  }

  @override
  Widget build(BuildContext context) {
    final light = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: _purple),
      useMaterial3: true,
      cardTheme: const CardThemeData(elevation: 1, margin: EdgeInsets.zero),
    );
    final dark = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _purple,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      cardTheme: const CardThemeData(elevation: 1, margin: EdgeInsets.zero),
    );
    final english = _locale.languageCode == 'en';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'إيقاع | Iqaa',
      locale: _locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: light.copyWith(
        textTheme: english
            ? GoogleFonts.interTextTheme(light.textTheme)
            : GoogleFonts.cairoTextTheme(light.textTheme),
      ),
      darkTheme: dark.copyWith(
        textTheme: english
            ? GoogleFonts.interTextTheme(dark.textTheme)
            : GoogleFonts.cairoTextTheme(dark.textTheme),
      ),
      themeMode: _mode,
      home: HomePage(
        isArabic: !english,
        onLocaleChanged: (locale) => setState(() => _locale = locale),
        mode: _mode,
        onThemeChanged: _setMode,
      ),
    );
  }
}

class IqaaTask {
  IqaaTask({
    required this.id,
    required this.title,
    required this.note,
    required this.minutes,
    required this.energy,
    this.done = false,
    this.deadline,
  });

  final String id;
  String title;
  String note;
  int minutes;
  int energy;
  bool done;
  final DateTime? deadline;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'minutes': minutes,
        'energy': energy,
        'done': done,
        'deadline': deadline?.toIso8601String(),
      };

  factory IqaaTask.fromJson(Map<String, dynamic> json) => IqaaTask(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        note: json['note'] as String? ?? '',
        minutes: json['minutes'] as int? ?? 25,
        energy: json['energy'] as int? ?? 2,
        done: json['done'] as bool? ?? false,
        deadline: json['deadline'] == null
            ? null
            : DateTime.tryParse(json['deadline'] as String),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.isArabic,
    required this.onLocaleChanged,
    required this.mode,
    required this.onThemeChanged,
  });

  final bool isArabic;
  final ValueChanged<Locale> onLocaleChanged;
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onThemeChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Box<String> _box = Hive.box<String>(_boxName);
  int _energy = 3;
  int _tab = 0;
  int _seconds = 0;
  Timer? _timer;
  bool _running = false;

  bool get ar => widget.isArabic;
  String t(String arabic, String english) => ar ? arabic : english;

  List<IqaaTask> get _tasks {
    final result = <IqaaTask>[];
    for (final value in _box.values) {
      try {
        result
            .add(IqaaTask.fromJson(jsonDecode(value) as Map<String, dynamic>));
      } catch (_) {
        // Ignore malformed legacy entries so the remaining tasks remain usable.
      }
    }
    result.sort((a, b) =>
        a.done == b.done ? a.title.compareTo(b.title) : (a.done ? 1 : -1));
    return result;
  }

  Future<void> _save(IqaaTask task) async =>
      _box.put(task.id, jsonEncode(task.toJson()));
  Future<void> _remove(IqaaTask task) async => _box.delete(task.id);

  Future<void> _exportJson() async {
    final content = const JsonEncoder.withIndent('  ')
        .convert(_tasks.map((task) => task.toJson()).toList());
    await Clipboard.setData(ClipboardData(text: content));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(t('نُسخت بيانات المهام بصيغة JSON.',
                'Task data copied as JSON.'))),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggleTimer() {
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
      return;
    }
    if (_seconds <= 0) _seconds = 25 * 60;
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_seconds <= 1) {
        timer.cancel();
        setState(() {
          _seconds = 0;
          _running = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(t('انتهت جلسة التركيز، أحسنت!',
                  'Focus session complete. Well done!'))),
        );
      } else {
        setState(() => _seconds--);
      }
    });
  }

  Future<void> _addTask([IqaaTask? existing]) async {
    if (existing == null && _tasks.where((e) => !e.done).length >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(t('وصلت إلى الحد المجاني: ١٠ مهام نشطة.',
                'Free plan limit: 10 active tasks.'))),
      );
      return;
    }
    final title = TextEditingController(text: existing?.title ?? '');
    final note = TextEditingController(text: existing?.note ?? '');
    var energy = existing?.energy ?? 2;
    var minutes = existing?.minutes ?? 25;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, sheetSet) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  existing == null
                      ? t('مهمة جديدة', 'New task')
                      : t('تعديل المهمة', 'Edit task'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: title,
                  autofocus: true,
                  maxLength: 80,
                  decoration: InputDecoration(
                    labelText: t('عنوان المهمة', 'Task title'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: note,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: t('وصف اختياري', 'Optional description'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                Text(t('الطاقة المطلوبة: ${_energyName(energy)}',
                    'Energy required: ${_energyName(energy)}')),
                SegmentedButton<int>(
                  segments: [
                    for (var i = 1; i <= 3; i++)
                      ButtonSegment(
                        value: i,
                        label: Text(_energyName(i)),
                        icon: Icon(_energyIcon(i)),
                      ),
                  ],
                  selected: {energy},
                  onSelectionChanged: (value) =>
                      sheetSet(() => energy = value.first),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                        child: Text(t('المدة التقديرية', 'Estimated time'))),
                    IconButton(
                      onPressed: () => sheetSet(
                          () => minutes = (minutes - 5).clamp(5, 240).toInt()),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text('$minutes ${t('د', 'min')}'),
                    IconButton(
                      onPressed: () => sheetSet(
                          () => minutes = (minutes + 5).clamp(5, 240).toInt()),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final cleanTitle = title.text.trim();
                    if (cleanTitle.isEmpty) return;
                    final task = existing ??
                        IqaaTask(
                          id: DateTime.now().microsecondsSinceEpoch.toString(),
                          title: '',
                          note: '',
                          minutes: minutes,
                          energy: energy,
                        );
                    task.title = cleanTitle;
                    task.note = note.text.trim();
                    task.minutes = minutes;
                    task.energy = energy;
                    await _save(task);
                    if (context.mounted) Navigator.pop(context);
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.check),
                  label: Text(t('حفظ المهمة', 'Save task')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    title.dispose();
    note.dispose();
  }

  String _energyName(int energy) => energy == 1
      ? t('منخفضة', 'Low')
      : energy == 2
          ? t('متوسطة', 'Medium')
          : t('عالية', 'High');

  IconData _energyIcon(int energy) => energy == 1
      ? Icons.spa_outlined
      : energy == 2
          ? Icons.bolt
          : Icons.local_fire_department_outlined;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<String>>(
      valueListenable: _box.listenable(),
      builder: (context, box, _) => Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _purple.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.waves_rounded, color: _purple),
              ),
              const SizedBox(width: 10),
              Text('إيقاع',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(
                tooltip: t('الإعدادات', 'Settings'),
                onPressed: _showSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
        ),
        body: AnimatedSwitcher(
          duration: 300.ms,
          child: _tab == 0
              ? _home()
              : _tab == 1
                  ? _stats()
                  : _settings(),
        ),
        floatingActionButton: _tab == 0
            ? FloatingActionButton.extended(
                onPressed: () => _addTask(),
                icon: const Icon(Icons.add),
                label: Text(t('مهمة جديدة', 'New task')),
              ).animate().scale(duration: 240.ms)
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (value) => setState(() => _tab = value),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.today_outlined),
              selectedIcon: const Icon(Icons.today),
              label: t('اليوم', 'Today'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.insights_outlined),
              selectedIcon: const Icon(Icons.insights),
              label: t('التقارير', 'Reports'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.tune_outlined),
              selectedIcon: const Icon(Icons.tune),
              label: t('الإعدادات', 'Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _home() {
    final tasks = _tasks;
    final done = tasks.where((e) => e.done).length;
    final suggested =
        tasks.where((e) => !e.done && e.energy <= _energy).take(3).toList();
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? t('صباح الخير', 'Good morning')
        : hour < 18
            ? t('مساء الخير', 'Good afternoon')
            : t('مساء النور', 'Good evening');
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
      children: [
        Text(
          greeting,
          style: Theme.of(context)
              .textTheme
              .headlineMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ).animate().fadeIn().slideX(begin: -.08),
        Text(
          t('خطّط بإيقاع طاقتك، لا بعقارب الساعة.',
              'Plan with your energy, not just the clock.'),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 20),
        _energyPanel(),
        const SizedBox(height: 18),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('إنجاز اليوم', 'Today’s progress'),
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(t('$done من ${tasks.length} مهام مكتملة',
                          '$done of ${tasks.length} tasks completed')),
                    ],
                  ),
                ),
                SizedBox(
                  width: 58,
                  height: 58,
                  child: CircularProgressIndicator(
                    value: tasks.isEmpty ? 0 : done / tasks.length,
                    strokeWidth: 7,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: .6),
                    strokeCap: StrokeCap.round,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
                child: Text(t('ماذا تفعل الآن؟', 'What to do now?'),
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold))),
            TextButton.icon(
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(t('اقتراح', 'Suggest')),
            ),
          ],
        ),
        if (suggested.isEmpty) _emptyState() else ...suggested.map(_taskCard),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
                child: Text(t('كل المهام', 'All tasks'),
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold))),
            Text('${tasks.length}/10',
                style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
        if (tasks.isEmpty) _emptyState() else ...tasks.map(_taskCard),
        const SizedBox(height: 20),
        _pomodoroCard(),
      ],
    );
  }

  Widget _energyPanel() => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text(t('كيف طاقتك الآن؟', 'How is your energy?'),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold))),
                  Text('$_energy/5',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: _purple, fontWeight: FontWeight.w800)),
                ],
              ),
              Slider(
                value: _energy.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                label: '$_energy',
                onChanged: (value) => setState(() => _energy = value.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 1; i <= 5; i++)
                    GestureDetector(
                      onTap: () => setState(() => _energy = i),
                      child: AnimatedScale(
                        scale: _energy == i ? 1.3 : 1,
                        duration: 180.ms,
                        child: Text(
                          ['😴', '😕', '😐', '🙂', '⚡'][i - 1],
                          style: const TextStyle(fontSize: 25),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _energy <= 2
                    ? t('اختر مهمة خفيفة وامنح نفسك مساحة.',
                        'Choose a light task and give yourself room.')
                    : _energy >= 4
                        ? t('استثمر نشاطك في مهمة تحتاج تركيزاً.',
                            'Use your momentum on a demanding task.')
                        : t('إيقاع متوازن؛ اختر ما يناسبك.',
                            'A balanced pace. Pick what feels right.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );

  Widget _taskCard(IqaaTask task) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Dismissible(
          key: ValueKey(task.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
                color: Colors.red, borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          onDismissed: (_) => _remove(task),
          child: Card(
            child: ListTile(
              leading: Checkbox(
                value: task.done,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
                onChanged: (value) async {
                  task.done = value ?? false;
                  await _save(task);
                },
              ),
              title: Text(
                task.title,
                style: TextStyle(
                  decoration: task.done ? TextDecoration.lineThrough : null,
                  color: task.done
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : null,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                '${_energyName(task.energy)} · ${task.minutes} ${t('دقيقة', 'min')}${task.note.isEmpty ? '' : ' · ${task.note}'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                onPressed: () => _addTask(task),
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
          ),
        ),
      ).animate().fadeIn(duration: 250.ms).slideX(begin: .04, duration: 250.ms);

  Widget _emptyState() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(
              Icons.wb_twilight_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            )
                .animate(
                    onPlay: (controller) => controller.repeat(reverse: true))
                .moveY(
                  begin: -4,
                  end: 4,
                  duration: 1100.ms,
                ),
            const SizedBox(height: 8),
            Text(
              t('لا توجد مهام مناسبة الآن. أضف مهمة تناسب طاقتك.',
                  'No matching tasks yet. Add one that fits your energy.'),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );

  Widget _pomodoroCard() {
    final min = (_seconds ~/ 60).toString().padLeft(2, '0');
    final sec = (_seconds % 60).toString().padLeft(2, '0');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(Icons.timer_outlined, size: 34, color: _purple),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('جلسة تركيز', 'Focus session'),
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(_seconds == 0
                      ? t('٢٥ دقيقة من التركيز الهادئ',
                          'A calm 25-minute focus session')
                      : '$min:$sec'),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _toggleTimer,
              icon: Icon(_running ? Icons.pause : Icons.play_arrow),
              label: Text(_running ? t('إيقاف', 'Pause') : t('ابدأ', 'Start')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stats() {
    final tasks = _tasks;
    final completed = tasks.where((task) => task.done).length;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(t('ملخص اليوم', 'Today at a glance'),
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(t('تقارير أسبوعية ورؤى أعمق متاحة مع إيقاع بلس.',
            'Weekly reports and deeper insights are available with Iqaa Plus.')),
        const SizedBox(height: 20),
        Card(
          child: SizedBox(
            height: 200,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: BarChart(
                BarChartData(
                  maxY: 6,
                  minY: 0,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          const days = ['س', 'ن', 'ث', 'ر', 'خ', 'ج', 'س'];
                          final index = value.toInt().clamp(0, days.length - 1);
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(days[index],
                                style: const TextStyle(fontSize: 11)),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < 7; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: i == 6 ? completed.toDouble() : 0.4 + (i % 3),
                            color: _purple,
                            width: 15,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6)),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(t('تقارير أسبوعية', 'Weekly analytics')),
            subtitle: Text(t('توزيع الطاقة والإنجاز والرؤى الذكية.',
                'Energy distribution, completion trends and insights.')),
            trailing: TextButton(
                onPressed: _showPaywall,
                child: Text(t('إيقاع بلس', 'Iqaa Plus'))),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.check_circle_outline),
            title: Text(t('إنجاز اليوم', 'Completed today')),
            trailing: Text('$completed/${tasks.length}'),
          ),
        ),
      ],
    );
  }

  Widget _settings() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(t('الإعدادات', 'Settings'),
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dark_mode_outlined),
                  title: Text(t('المظهر', 'Appearance')),
                  subtitle: Text(widget.mode.name),
                  trailing: DropdownButton<ThemeMode>(
                    value: widget.mode,
                    underline: const SizedBox(),
                    items: [
                      DropdownMenuItem(
                          value: ThemeMode.system,
                          child: Text(t('النظام', 'System'))),
                      DropdownMenuItem(
                          value: ThemeMode.light,
                          child: Text(t('فاتح', 'Light'))),
                      DropdownMenuItem(
                          value: ThemeMode.dark,
                          child: Text(t('داكن', 'Dark'))),
                    ],
                    onChanged: (value) {
                      if (value != null) widget.onThemeChanged(value);
                    },
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(t('اللغة', 'Language')),
                  trailing: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'ar', label: Text('العربية')),
                      ButtonSegment(value: 'en', label: Text('English')),
                    ],
                    selected: {ar ? 'ar' : 'en'},
                    onSelectionChanged: (values) =>
                        widget.onLocaleChanged(Locale(values.first)),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: Text(t('إيقاع بلس', 'Iqaa Plus')),
                  subtitle: Text(t('تقارير وتخصيص أكثر', 'Analytics and more')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showPaywall,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.ios_share),
                  title: Text(t('نسخ نسخة JSON', 'Copy JSON backup')),
                  onTap: _exportJson,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: Text(t('استعادة المشتريات', 'Restore purchases')),
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(t(
                            'تحتاج استعادة المشتريات إلى إعداد RevenueCat بمفاتيح مشروعك.',
                            'Purchase restoration requires your RevenueCat project keys.'))),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            t('تُحفظ مهامك على هذا الجهاز فقط. لا يلزم اتصال بالإنترنت لاستخدام الميزات الأساسية.',
                'Your tasks are stored on this device. Core features work offline.'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );

  void _showSettings() => setState(() => _tab = 2);

  void _showPaywall() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 48, color: _purple),
            const SizedBox(height: 8),
            Text(t('إيقاع بلس', 'Iqaa Plus'),
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(t('خطوات أوضح نحو يوم يناسب طاقتك.',
                'More clarity for a day that fits your energy.')),
            const SizedBox(height: 18),
            for (final feature in [
              t('تقارير أسبوعية وتحليلات الطاقة',
                  'Weekly reports and energy analytics'),
              t('رؤى ذكية وفلاتر متقدمة',
                  'Smart insights and advanced filters'),
              t('وسوم مخصصة وتصدير البيانات', 'Custom tags and data export'),
              t('مهام نشطة بلا حدود', 'Unlimited active tasks'),
            ])
              ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: Text(feature),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('تجربة مجانية ٧ أيام · \$4.99/شهر',
                  '7-day free trial · \$4.99/month')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('ليس الآن', 'Not now')),
            ),
            Text(
              t('يلزم إعداد منتجات RevenueCat ومفاتيح المتجر قبل تفعيل الشراء.',
                  'RevenueCat products and store keys must be configured to enable purchases.'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}