import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel defaultReminderChannel = AndroidNotificationChannel(
  'daily_reminders_default',
  'Daily Reminders (Default)',
  description: 'Medicine, health, personal and work reminders',
  importance: Importance.max,
  playSound: true,
);
const AndroidNotificationChannel gentleReminderChannel = AndroidNotificationChannel(
  'daily_reminders_gentle',
  'Daily Reminders (Gentle)',
  description: 'Gentle reminder alarm sound',
  importance: Importance.max,
  playSound: true,
  sound: RawResourceAndroidNotificationSound('gentle'),
);
const AndroidNotificationChannel urgentReminderChannel = AndroidNotificationChannel(
  'daily_reminders_urgent',
  'Daily Reminders (Urgent)',
  description: 'Urgent reminder alarm sound',
  importance: Importance.max,
  playSound: true,
  sound: RawResourceAndroidNotificationSound('urgent'),
);
const AndroidNotificationChannel caregiverChannel = AndroidNotificationChannel(
  'caregiver_alerts',
  'Caregiver Alerts',
  description: 'Local alerts when a reminder is marked missed',
  importance: Importance.max,
  playSound: true,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  runApp(const DailyReminderApp());
}

class NotificationService {
  static Future<void> init() async {
    tz.initializeTimeZones();
    // The initial release targets India. Avoid the flutter_timezone plugin,
    // which currently fails Kotlin compilation with the generated Android build.
    // Keep scheduled reminders aligned with Indian Standard Time.
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await notifications.initialize(settings);

    final android = notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(defaultReminderChannel);
    await android?.createNotificationChannel(gentleReminderChannel);
    await android?.createNotificationChannel(urgentReminderChannel);
    await android?.createNotificationChannel(caregiverChannel);
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
  }

  static AndroidNotificationDetails _androidDetails(Reminder reminder) {
    final channelId = switch (reminder.alarmSound) {
      'Gentle' => 'daily_reminders_gentle',
      'Urgent' => 'daily_reminders_urgent',
      _ => 'daily_reminders_default',
    };
    final channelName = switch (reminder.alarmSound) {
      'Gentle' => 'Daily Reminders (Gentle)',
      'Urgent' => 'Daily Reminders (Urgent)',
      _ => 'Daily Reminders (Default)',
    };
    AndroidNotificationSound? sound;
    if (reminder.alarmSound == 'Gentle') {
      sound = const RawResourceAndroidNotificationSound('gentle');
    } else if (reminder.alarmSound == 'Urgent') {
      sound = const RawResourceAndroidNotificationSound('urgent');
    }
    return AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Medicine, health, personal and work reminders',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: sound,
      enableVibration: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
    );
  }

  static Future<void> schedule(Reminder reminder) async {
    await cancel(reminder.id);
    final when = _nextOccurrence(reminder);
    await notifications.zonedSchedule(
      reminder.id,
      reminder.title,
      reminder.note.isEmpty
          ? 'Time for your ${reminder.category.toLowerCase()} reminder.'
          : reminder.note,
      when,
      NotificationDetails(android: _androidDetails(reminder)),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'open:${reminder.id}',
      matchDateTimeComponents: _matchComponents(reminder),
    );
  }

  static Future<void> snooze(Reminder reminder, int minutes) async {
    final id = reminder.id + 1000000000;
    await notifications.cancel(id);
    await notifications.zonedSchedule(
      id,
      reminder.title,
      'Snoozed reminder • ${reminder.note.isEmpty ? reminder.category : reminder.note}',
      tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes)),
      NotificationDetails(android: _androidDetails(reminder)),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'snooze:${reminder.id}',
    );
  }

  static Future<void> caregiverLocalAlert(Reminder reminder, String caregiver) async {
    if (caregiver.trim().isEmpty) return;
    final id = reminder.id + 1500000000;
    await notifications.show(
      id,
      'Caregiver Alert',
      '${reminder.title} was marked missed. Please check on the user.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'caregiver_alerts',
          'Caregiver Alerts',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );
  }

  static Future<void> cancel(int id) async {
    await notifications.cancel(id);
    await notifications.cancel(id + 1000000000);
    await notifications.cancel(id + 1500000000);
  }

  static DateTimeComponents? _matchComponents(Reminder r) {
    switch (r.repeat) {
      case 'Every Day': return DateTimeComponents.time;
      case 'Weekly': return DateTimeComponents.dayOfWeekAndTime;
      case 'Monthly': return DateTimeComponents.dayOfMonthAndTime;
      default: return null;
    }
  }

  static tz.TZDateTime _nextOccurrence(Reminder r) {
    final now = tz.TZDateTime.now(tz.local);
    var candidate = tz.TZDateTime(
      tz.local, now.year, now.month, now.day, r.time.hour, r.time.minute);

    if (r.repeat == 'Weekly') {
      final target = r.weekday ?? now.weekday;
      while (candidate.weekday != target || !candidate.isAfter(now)) {
        candidate = candidate.add(const Duration(days: 1));
      }
      return candidate;
    }

    if (r.repeat == 'Monthly') {
      final day = r.dayOfMonth ?? now.day;
      var d = day.clamp(1, DateTime(now.year, now.month + 1, 0).day).toInt();
      candidate = tz.TZDateTime(tz.local, now.year, now.month, d,
          r.time.hour, r.time.minute);
      if (!candidate.isAfter(now)) {
        final nextMonth = now.month == 12 ? 1 : now.month + 1;
        final nextYear = now.month == 12 ? now.year + 1 : now.year;
        d = day.clamp(1, DateTime(nextYear, nextMonth + 1, 0).day).toInt();
        candidate = tz.TZDateTime(tz.local, nextYear, nextMonth, d,
            r.time.hour, r.time.minute);
      }
      return candidate;
    }

    if (!candidate.isAfter(now)) candidate = candidate.add(const Duration(days: 1));
    return candidate;
  }
}

class Reminder {
  Reminder({
    required this.id,
    required this.title,
    required this.time,
    required this.category,
    required this.repeat,
    this.note = '',
    this.weekday,
    this.dayOfMonth,
    this.completed = false,
    this.alarmSound = 'Default',
    this.dosage = '',
    this.beforeAfterFood = 'Not Applicable',
  });

  final int id;
  final String title;
  final TimeOfDay time;
  final String category;
  final String repeat;
  final String note;
  final int? weekday;
  final int? dayOfMonth;
  final bool completed;
  final String alarmSound;
  final String dosage;
  final String beforeAfterFood;

  Reminder copyWith({bool? completed}) => Reminder(
    id: id, title: title, time: time, category: category, repeat: repeat,
    note: note, weekday: weekday, dayOfMonth: dayOfMonth,
    completed: completed ?? this.completed, alarmSound: alarmSound,
    dosage: dosage, beforeAfterFood: beforeAfterFood,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'hour': time.hour, 'minute': time.minute,
    'category': category, 'repeat': repeat, 'note': note,
    'weekday': weekday, 'dayOfMonth': dayOfMonth, 'completed': completed,
    'alarmSound': alarmSound, 'dosage': dosage,
    'beforeAfterFood': beforeAfterFood,
  };

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
    id: j['id'], title: j['title'],
    time: TimeOfDay(hour: j['hour'], minute: j['minute']),
    category: j['category'], repeat: j['repeat'], note: j['note'] ?? '',
    weekday: j['weekday'], dayOfMonth: j['dayOfMonth'],
    completed: j['completed'] ?? false,
    alarmSound: j['alarmSound'] ?? 'Default',
    dosage: j['dosage'] ?? '',
    beforeAfterFood: j['beforeAfterFood'] ?? 'Not Applicable',
  );
}

class ReminderStore {
  static const _items = 'daily_reminder_v22_items';
  static const _easy = 'daily_reminder_v22_easy';
  static const _caregiverName = 'daily_reminder_v22_caregiver_name';
  static const _caregiverPhone = 'daily_reminder_v22_caregiver_phone';

  static Future<List<Reminder>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_items);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Reminder.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  static Future<void> save(List<Reminder> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_items, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  static Future<bool> easyMode() async =>
      (await SharedPreferences.getInstance()).getBool(_easy) ?? false;
  static Future<void> setEasyMode(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_easy, v);
  }

  static Future<Map<String, String>> caregiver() async {
    final p = await SharedPreferences.getInstance();
    return {
      'name': p.getString(_caregiverName) ?? '',
      'phone': p.getString(_caregiverPhone) ?? '',
    };
  }

  static Future<void> setCaregiver(String name, String phone) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_caregiverName, name);
    await p.setString(_caregiverPhone, phone);
  }
}

class DailyReminderApp extends StatelessWidget {
  const DailyReminderApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Daily Reminder',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF5B43C7),
      scaffoldBackgroundColor: const Color(0xFFF8F8FC),
    ),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Reminder> reminders = [];
  bool loading = true, easy = false;
  int tab = 0;
  String caregiverName = '', caregiverPhone = '';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final list = await ReminderStore.load();
    final mode = await ReminderStore.easyMode();
    final caregiver = await ReminderStore.caregiver();
    if (!mounted) return;
    setState(() {
      reminders = list..sort(_compare);
      easy = mode;
      caregiverName = caregiver['name'] ?? '';
      caregiverPhone = caregiver['phone'] ?? '';
      loading = false;
    });
  }

  int _compare(Reminder a, Reminder b) =>
      (a.time.hour * 60 + a.time.minute).compareTo(b.time.hour * 60 + b.time.minute);

  Future<void> _persist() => ReminderStore.save(reminders);

  Future<void> _complete(Reminder r) async {
    setState(() {
      final i = reminders.indexWhere((x) => x.id == r.id);
      reminders[i] = r.copyWith(completed: true);
    });
    await _persist();
    if (r.repeat == 'Once') await NotificationService.cancel(r.id);
  }

  Future<void> _snooze(Reminder r, int minutes) async {
    await NotificationService.snooze(r, minutes);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${r.title} snoozed for $minutes minutes')));
  }

  Future<void> _missed(Reminder r) async {
    await NotificationService.caregiverLocalAlert(r, caregiverName);
    if (caregiverPhone.trim().isNotEmpty) {
      final body = Uri.encodeComponent(
        'Daily Reminder alert: ${r.title} was missed. Please check on the user.');
      final uri = Uri.parse('sms:$caregiverPhone?body=$body');
      if (await canLaunchUrl(uri)) await launchUrl(uri);
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(caregiverPhone.isEmpty
        ? 'Missed reminder recorded. Add caregiver details in Settings.'
        : 'Caregiver message is ready to send.')));
  }

  Future<void> _delete(Reminder r) async {
    setState(() => reminders.removeWhere((x) => x.id == r.id));
    await _persist();
    await NotificationService.cancel(r.id);
  }

  Future<void> _add() async {
    final r = await Navigator.push<Reminder>(
      context, MaterialPageRoute(builder: (_) => const AddReminderPage()));
    if (r == null) return;
    setState(() { reminders.add(r); reminders.sort(_compare); });
    await _persist();
    await NotificationService.schedule(r);
  }

  IconData iconFor(String c) => {
    'Medicine': Icons.medication_rounded,
    'Health': Icons.favorite_rounded,
    'Workout': Icons.directions_walk_rounded,
    'Work': Icons.business_center_rounded,
    'Personal': Icons.person_rounded,
  }[c] ?? Icons.notifications_active;

  @override
  Widget build(BuildContext context) {
    final pages = [_home(), _schedule(), _history(), _settings()];
    return Scaffold(
      body: SafeArea(child: pages[tab]),
      floatingActionButton: tab == 0 ? FloatingActionButton.extended(
        onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add Reminder')) : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Schedule'),
          NavigationDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history), label: 'History'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _home() {
    if (loading) return const Center(child: CircularProgressIndicator());
    final pending = reminders.where((r) => !r.completed).toList();
    return Column(children: [
      Padding(
        padding: EdgeInsets.fromLTRB(easy ? 24 : 20, 18, easy ? 24 : 20, 8),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(easy ? 'Hello 👋' : 'Good Morning 👋',
              style: TextStyle(fontSize: easy ? 30 : 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${pending.length} reminders for today',
              style: TextStyle(fontSize: easy ? 18 : 14)),
          ])),
          IconButton(iconSize: easy ? 32 : 24, onPressed: () {}, icon: const Icon(Icons.notifications_none)),
        ]),
      ),
      Expanded(child: pending.isEmpty
        ? Center(child: Text('No pending reminders.\nEnjoy your day!',
            textAlign: TextAlign.center, style: TextStyle(fontSize: easy ? 22 : 18)))
        : ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          itemCount: pending.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final r = pending[i];
            return Card(child: ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: easy ? 20 : 16, vertical: easy ? 14 : 8),
              leading: CircleAvatar(radius: easy ? 28 : 22, child: Icon(iconFor(r.category), size: easy ? 28 : 22)),
              title: Text(r.title, style: TextStyle(fontSize: easy ? 21 : 16, fontWeight: FontWeight.w700)),
              subtitle: Text('${r.time.format(context)} • ${r.note.isEmpty ? r.category : r.note}',
                style: TextStyle(fontSize: easy ? 16 : 13)),
              onTap: () async {
                final result = await Navigator.push<String>(context,
                  MaterialPageRoute(builder: (_) => ReminderAlertPage(reminder: r, easyMode: easy)));
                if (result == 'done') _complete(r);
                if (result == 'missed') _missed(r);
                if (result != null && result.startsWith('snooze:')) {
                  _snooze(r, int.parse(result.split(':')[1]));
                }
              },
              onLongPress: () => _delete(r),
            ));
          },
        )),
    ]);
  }

  Widget _schedule() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text('Schedule', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      const SizedBox(height: 14),
      ...reminders.map((r) => Card(child: ListTile(
        leading: Icon(iconFor(r.category)),
        title: Text(r.title),
        subtitle: Text('${r.time.format(context)} • ${r.repeat} • ${r.alarmSound} sound'),
        trailing: r.completed ? const Icon(Icons.check_circle, color: Colors.green) : const Icon(Icons.schedule),
      ))),
    ],
  );

  Widget _history() {
    final done = reminders.where((r) => r.completed).toList();
    return ListView(padding: const EdgeInsets.all(20), children: [
      const Text('History', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      const SizedBox(height: 18),
      if (done.isEmpty) const Padding(padding: EdgeInsets.only(top: 40),
        child: Center(child: Text('Completed reminders will appear here.'))),
      ...done.map((r) => Card(child: ListTile(
        leading: const Icon(Icons.check_circle, color: Colors.green),
        title: Text(r.title), subtitle: Text('${r.time.format(context)} • Completed'),
      ))),
    ]);
  }

  Widget _settings() => ListView(padding: const EdgeInsets.all(20), children: [
    const Text('Settings', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
    const SizedBox(height: 20),
    Card(child: SwitchListTile(
      secondary: const Icon(Icons.accessibility_new),
      title: const Text('Easy Mode'),
      subtitle: const Text('Large text and simple controls for elderly users'),
      value: easy,
      onChanged: (v) async {
        setState(() => easy = v);
        await ReminderStore.setEasyMode(v);
      },
    )),
    Card(child: ListTile(
      leading: const Icon(Icons.family_restroom),
      title: Text(caregiverName.isEmpty ? 'Set Caregiver / Family Contact' : caregiverName),
      subtitle: Text(caregiverPhone.isEmpty ? 'Receive missed medicine alerts' : caregiverPhone),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final result = await Navigator.push<Map<String, String>>(
          context, MaterialPageRoute(builder: (_) => CaregiverPage(
            name: caregiverName, phone: caregiverPhone)));
        if (result != null) {
          setState(() {
            caregiverName = result['name'] ?? '';
            caregiverPhone = result['phone'] ?? '';
          });
        }
      },
    )),
    const Card(child: ListTile(
      leading: Icon(Icons.mic),
      title: Text('Voice Reminder'),
      subtitle: Text('Use the microphone while adding a reminder'),
    )),
    const Card(child: ListTile(
      leading: Icon(Icons.music_note),
      title: Text('Alarm Sounds'),
      subtitle: Text('Default, Gentle or Urgent'),
    )),
    const Card(child: ListTile(
      leading: Icon(Icons.info_outline),
      title: Text('Version 2.2'),
      subtitle: Text('Sounds, dosage, voice input and caregiver alerts'),
    )),
  ]);
}

class AddReminderPage extends StatefulWidget {
  const AddReminderPage({super.key});
  @override
  State<AddReminderPage> createState() => _AddReminderPageState();
}

class _AddReminderPageState extends State<AddReminderPage> {
  final title = TextEditingController();
  final note = TextEditingController();
  final dosage = TextEditingController();
  final speech = stt.SpeechToText();

  String category = 'Medicine';
  String repeat = 'Every Day';
  String alarmSound = 'Default';
  String foodTiming = 'After Food';
  TimeOfDay time = const TimeOfDay(hour: 8, minute: 0);
  int weekday = DateTime.now().weekday;
  int dayOfMonth = DateTime.now().day;
  bool listening = false;
  bool speechAvailable = false;

  @override
  void dispose() {
    title.dispose(); note.dispose(); dosage.dispose(); super.dispose();
  }

  Future<void> _voiceInput() async {
    if (!speechAvailable) {
      speechAvailable = await speech.initialize(
        onStatus: (status) {
          if (mounted && (status == 'done' || status == 'notListening')) {
            setState(() => listening = false);
          }
        },
      );
    }
    if (!speechAvailable) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition is not available on this device.')));
      return;
    }
    setState(() => listening = true);
    await speech.listen(
      onResult: (result) {
        if (result.recognizedWords.isNotEmpty) {
          setState(() => title.text = result.recognizedWords);
        }
        if (result.finalResult) setState(() => listening = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const categories = ['Medicine','Health','Workout','Work','Personal'];
    const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return Scaffold(
      appBar: AppBar(title: const Text('Add Reminder')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          const Expanded(child: Text('Create reminder', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          IconButton(
            tooltip: 'Speak reminder',
            onPressed: _voiceInput,
            icon: Icon(listening ? Icons.mic : Icons.mic_none,
              color: listening ? Colors.red : null),
          ),
        ]),
        TextField(
          controller: title,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'What should we remind you about?',
            hintText: listening ? 'Listening...' : 'e.g. Take BP Medicine',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(icon: const Icon(Icons.mic), onPressed: _voiceInput),
          ),
        ),
        const SizedBox(height: 18),
        const Text('Category', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: categories.map((x) => ChoiceChip(
          label: Text(x), selected: category == x,
          onSelected: (_) => setState(() => category = x))).toList()),

        if (category == 'Medicine') ...[
          const SizedBox(height: 18),
          TextField(
            controller: dosage,
            decoration: const InputDecoration(
              labelText: 'Dosage',
              hintText: 'e.g. 1 tablet / 5 ml',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: foodTiming,
            decoration: const InputDecoration(labelText: 'Medicine timing', border: OutlineInputBorder()),
            items: const ['Before Food','After Food','With Food','Not Applicable']
              .map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
            onChanged: (v) => setState(() => foodTiming = v ?? 'After Food'),
          ),
        ],

        const SizedBox(height: 18),
        ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          tileColor: Colors.white, leading: const Icon(Icons.access_time),
          title: const Text('Reminder Time'), trailing: Text(time.format(context)),
          onTap: () async {
            final v = await showTimePicker(context: context, initialTime: time);
            if (v != null) setState(() => time = v);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: repeat,
          decoration: const InputDecoration(labelText: 'Repeat', border: OutlineInputBorder()),
          items: const ['Once','Every Day','Weekly','Monthly']
            .map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
          onChanged: (v) => setState(() => repeat = v ?? 'Every Day')),
        if (repeat == 'Weekly') ...[
          const SizedBox(height: 12), const Text('Repeat on'),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: List.generate(7, (i) => ChoiceChip(
            label: Text(days[i]), selected: weekday == i + 1,
            onSelected: (_) => setState(() => weekday = i + 1)))),
        ],
        if (repeat == 'Monthly') ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: dayOfMonth,
            decoration: const InputDecoration(labelText: 'Day of month', border: OutlineInputBorder()),
            items: List.generate(31, (i) => i + 1).map((x) =>
              DropdownMenuItem(value: x, child: Text('$x'))).toList(),
            onChanged: (v) => setState(() => dayOfMonth = v ?? 1)),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: alarmSound,
          decoration: const InputDecoration(labelText: 'Alarm Sound', border: OutlineInputBorder()),
          items: const ['Default','Gentle','Urgent']
            .map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
          onChanged: (v) => setState(() => alarmSound = v ?? 'Default')),
        const SizedBox(height: 12),
        TextField(
          controller: note,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            hintText: 'e.g. Check BP before medicine',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          icon: const Icon(Icons.notifications_active),
          label: const Padding(padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('Save & Activate Alarm')),
          onPressed: () {
            if (title.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please enter a reminder')));
              return;
            }
            Navigator.pop(context, Reminder(
              id: DateTime.now().millisecondsSinceEpoch.remainder(900000000),
              title: title.text.trim(),
              time: time,
              category: category,
              repeat: repeat,
              note: note.text.trim(),
              weekday: repeat == 'Weekly' ? weekday : null,
              dayOfMonth: repeat == 'Monthly' ? dayOfMonth : null,
              alarmSound: alarmSound,
              dosage: category == 'Medicine' ? dosage.text.trim() : '',
              beforeAfterFood: category == 'Medicine' ? foodTiming : 'Not Applicable',
            ));
          }),
      ]),
    );
  }
}

class ReminderAlertPage extends StatelessWidget {
  const ReminderAlertPage({super.key, required this.reminder, required this.easyMode});
  final Reminder reminder;
  final bool easyMode;

  @override
  Widget build(BuildContext context) {
    final titleSize = easyMode ? 38.0 : 32.0;
    return Scaffold(
      backgroundColor: const Color(0xFF4F3AAE),
      body: SafeArea(child: Padding(
        padding: EdgeInsets.all(easyMode ? 32 : 28),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(reminder.category == 'Medicine'
              ? Icons.medication_rounded : Icons.notifications_active_rounded,
              size: easyMode ? 110 : 90, color: Colors.amber),
          const SizedBox(height: 18),
          Text(reminder.time.format(context),
            style: TextStyle(color: Colors.white70, fontSize: easyMode ? 28 : 22)),
          const SizedBox(height: 18),
          Text(reminder.title, textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: titleSize, fontWeight: FontWeight.bold)),
          if (reminder.dosage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('${reminder.dosage} • ${reminder.beforeAfterFood}',
              style: TextStyle(color: Colors.white, fontSize: easyMode ? 20 : 16)),
          ],
          const SizedBox(height: 10),
          Text(reminder.note.isEmpty ? reminder.category : reminder.note,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: easyMode ? 21 : 18)),
          const Spacer(),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58)),
            onPressed: () => Navigator.pop(context, 'done'),
            child: Text('DONE ✓', style: TextStyle(fontSize: easyMode ? 22 : 18)),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              foregroundColor: Colors.white, side: const BorderSide(color: Colors.white)),
            onPressed: () async {
              final minutes = await showModalBottomSheet<int>(
                context: context,
                builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min,
                  children: [5, 10, 30, 60].map((m) => ListTile(
                    leading: const Icon(Icons.snooze),
                    title: Text('Remind me again in $m minutes'),
                    onTap: () => Navigator.pop(context, m),
                  )).toList())),
              );
              if (minutes != null && context.mounted) Navigator.pop(context, 'snooze:$minutes');
            },
            child: Text('SNOOZE', style: TextStyle(fontSize: easyMode ? 22 : 18)),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => Navigator.pop(context, 'missed'),
            icon: const Icon(Icons.warning_amber, color: Colors.white70),
            label: const Text('I MISSED THIS',
              style: TextStyle(color: Colors.white70)),
          ),
        ]),
      )),
    );
  }
}

class CaregiverPage extends StatefulWidget {
  const CaregiverPage({super.key, required this.name, required this.phone});
  final String name, phone;
  @override
  State<CaregiverPage> createState() => _CaregiverPageState();
}

class _CaregiverPageState extends State<CaregiverPage> {
  late final TextEditingController name;
  late final TextEditingController phone;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.name);
    phone = TextEditingController(text: widget.phone);
  }

  @override
  void dispose() { name.dispose(); phone.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Caregiver Contact')),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        const Text(
          'If a medicine reminder is marked as missed, the app can prepare an SMS alert for this contact.',
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 20),
        TextField(controller: name,
          decoration: const InputDecoration(labelText: 'Caregiver / Family Name', border: OutlineInputBorder())),
        const SizedBox(height: 14),
        TextField(controller: phone, keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Mobile Number', hintText: 'Include country code if needed', border: OutlineInputBorder())),
        const Spacer(),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          onPressed: () async {
            await ReminderStore.setCaregiver(name.text.trim(), phone.text.trim());
            if (context.mounted) Navigator.pop(context, {
              'name': name.text.trim(), 'phone': phone.text.trim()
            });
          },
          child: const Text('Save Caregiver'),
        ),
      ]),
    ),
  );
}
