import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'second_screen.dart';

void main() {
  tz.initializeTimeZones();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool isDarkTheme = false;

  void toggleTheme() {
    setState(() {
      isDarkTheme = !isDarkTheme;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: isDarkTheme
          ? ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      )
          : ThemeData.light().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(
        toggleTheme: toggleTheme,
        isDarkTheme: isDarkTheme,
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final VoidCallback toggleTheme;
  final bool isDarkTheme;

  const HomeScreen({
    super.key,
    required this.toggleTheme,
    required this.isDarkTheme,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _todoController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _todos = [];
  int _currentIndex = 0;
  DateTime? _selectedDueDate;
  String _selectedPriority = 'Medium';
  String _sortBy = 'Creation';
  String _searchQuery = '';
  int _nextNotificationId = 0;

  static const String todosKey = 'todos_list';
  static const String nextNotificationIdKey = 'next_notification_id';

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _loadTodos();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
    InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap (optional)
      },
    );

    // Create the notification channel for Android
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'todo_channel',
      'To-Do Reminders',
      description: 'Notifications for to-do list reminders',
      importance: Importance.max,
    );
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Request notification permissions for Android 13+
    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
  }

  Future<void> _loadTodos() async {
    final prefs = await SharedPreferences.getInstance();
    final String? todosString = prefs.getString(todosKey);
    if (todosString != null) {
      final List<dynamic> decoded = jsonDecode(todosString);
      setState(() {
        _todos = decoded
            .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item))
            .toList();
      });
    }
    _nextNotificationId = prefs.getInt(nextNotificationIdKey) ?? 0;
    _scheduleAllPendingNotifications();
  }

  Future<void> _saveTodos() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_todos);
    await prefs.setString(todosKey, encoded);
    await prefs.setInt(nextNotificationIdKey, _nextNotificationId);
  }

  @override
  void dispose() {
    _todoController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _scheduleNotification(Map<String, dynamic> task) async {
    if (task['dueDate'] == null || task['completed']) return;

    final DateTime dueDate = DateTime.parse(task['dueDate']);
    if (dueDate.isBefore(DateTime.now())) return;

    final tz.TZDateTime scheduledDate = tz.TZDateTime.from(dueDate, tz.local);

    await flutterLocalNotificationsPlugin.zonedSchedule(
      task['notificationId'],
      'Task Reminder',
      task['task'],
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'todo_channel',
          'To-Do Reminders',
          channelDescription: 'Notifications for to-do list reminders',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> _cancelNotification(int notificationId) async {
    await flutterLocalNotificationsPlugin.cancel(notificationId);
  }

  void _scheduleAllPendingNotifications() {
    for (var task in _todos) {
      _scheduleNotification(task);
    }
  }

  void _addTodo() {
    if (_todoController.text.trim().isEmpty) return;

    final newTodo = {
      'task': _todoController.text.trim(),
      'completed': false,
      'created': DateTime.now().toIso8601String(),
      'dueDate': _selectedDueDate?.toIso8601String(),
      'priority': _selectedPriority,
      'notificationId': _nextNotificationId++,
    };

    setState(() {
      _todos.add(newTodo);
      _todoController.clear();
      _selectedDueDate = null;
      _selectedPriority = 'Medium';
    });
    _saveTodos();
    _scheduleNotification(newTodo);
  }

  void _toggleTodo(int index) {
    final wasCompleted = _todos[index]['completed'];
    setState(() {
      _todos[index]['completed'] = !_todos[index]['completed'];
    });
    _saveTodos();
    if (_todos[index]['completed'] && !wasCompleted) {
      _cancelNotification(_todos[index]['notificationId']);
    } else if (!_todos[index]['completed'] && wasCompleted) {
      _scheduleNotification(_todos[index]);
    }
  }

  void _deleteTodo(int index) {
    final removedTodo = Map<String, dynamic>.from(_todos[index]);
    setState(() {
      _todos.removeAt(index);
    });
    _saveTodos();
    _cancelNotification(removedTodo['notificationId']);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Task deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            setState(() {
              _todos.insert(index, removedTodo);
            });
            _saveTodos();
            if (!removedTodo['completed'] && removedTodo['dueDate'] != null) {
              _scheduleNotification(removedTodo);
            }
          },
        ),
      ),
    );
  }

  void _clearCompleted() {
    final completedNotifications = _todos
        .where((todo) => todo['completed'])
        .map((todo) => todo['notificationId'] as int)
        .toList();
    setState(() {
      _todos.removeWhere((todo) => todo['completed']);
    });
    _saveTodos();
    for (var id in completedNotifications) {
      _cancelNotification(id);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Completed tasks cleared')),
    );
  }

  Widget _buildTodoItem(BuildContext context, int index) {
    final todo = _todos[index];
    final dueDateStr = todo['dueDate'];
    final priority = todo['priority'] ?? 'Medium';
    DateTime? dueDate = dueDateStr != null ? DateTime.parse(dueDateStr) : null;
    final isOverdue =
        dueDate != null && dueDate.isBefore(DateTime.now()) && !todo['completed'];

    Color priorityColor;
    switch (priority) {
      case 'High':
        priorityColor = Colors.red;
        break;
      case 'Low':
        priorityColor = Colors.green;
        break;
      default:
        priorityColor = Colors.orange;
    }

    return Dismissible(
      key: Key('${todo['task']}_${todo['created']}_${todo['dueDate'] ?? ''}'),
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) => _deleteTodo(index),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: isOverdue ? Colors.red[50] : null,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Checkbox(
            value: todo['completed'],
            onChanged: (value) => _toggleTodo(index),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            activeColor: priorityColor,
          ),
          title: Text(
            todo['task'],
            style: TextStyle(
              decoration: todo['completed'] ? TextDecoration.lineThrough : null,
              color: todo['completed']
                  ? Theme.of(context).colorScheme.onSurface.withOpacity(0.6)
                  : (isOverdue
                  ? Colors.red
                  : Theme.of(context).colorScheme.onSurface),
              fontSize: 16,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (dueDate != null)
                Text(
                  'Due: ${dueDate.toLocal().toString().split('.')[0]}',
                  style: TextStyle(
                    color: isOverdue
                        ? Colors.red
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              Text(
                'Priority: $priority',
                style: TextStyle(
                  color: priorityColor,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            color: Theme.of(context).colorScheme.error,
            onPressed: () => _deleteTodo(index),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDueDate() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _selectedDueDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (date == null) return;

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDueDate ?? DateTime.now()),
    );
    if (time == null) return;

    setState(() {
      _selectedDueDate = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Widget _buildAddTodoCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add New Task',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _todoController,
              decoration: InputDecoration(
                labelText: 'Task description',
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceVariant,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _todoController.clear(),
                ),
              ),
              onSubmitted: (_) => _addTodo(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedPriority,
                    isExpanded: true,
                    items: ['Low', 'Medium', 'High'].map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _selectedPriority = newValue;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _pickDueDate,
                  child: Text(_selectedDueDate == null
                      ? 'Set Due Date'
                      : 'Due: ${_selectedDueDate!.toLocal().toString().split('.')[0]}'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _addTodo,
              child: const Text('Add Task'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    final completedCount = _todos.where((todo) => todo['completed']).length;
    final pendingCount = _todos.length - completedCount;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(Icons.list_alt, 'Total', _todos.length.toString()),
            _buildStatItem(
                Icons.check_circle, 'Completed', completedCount.toString()),
            _buildStatItem(
                Icons.pending_actions, 'Pending', pendingCount.toString()),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(
          icon,
          size: 30,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  List<MapEntry<int, Map<String, dynamic>>> _getFilteredAndSortedTodos(
      bool completed) {
    var filtered = _todos.asMap().entries.where((entry) {
      final todo = entry.value;
      return todo['completed'] == completed &&
          todo['task'].toLowerCase().contains(_searchQuery);
    }).toList();

    filtered.sort((a, b) {
      final todoA = a.value;
      final todoB = b.value;
      switch (_sortBy) {
        case 'Due Date':
          final dateA =
          todoA['dueDate'] != null ? DateTime.parse(todoA['dueDate']) : DateTime(9999);
          final dateB =
          todoB['dueDate'] != null ? DateTime.parse(todoB['dueDate']) : DateTime(9999);
          return dateA.compareTo(dateB);
        case 'Priority':
          const priorityMap = {'High': 3, 'Medium': 2, 'Low': 1};
          final priA = priorityMap[todoA['priority'] ?? 'Medium'] ?? 2;
          final priB = priorityMap[todoB['priority'] ?? 'Medium'] ?? 2;
          return priB.compareTo(priA); // Descending
        default: // 'Creation'
          final createA = DateTime.parse(todoA['created']);
          final createB = DateTime.parse(todoB['created']);
          return createA.compareTo(createB);
      }
    });

    return filtered;
  }

  Widget _buildTodoList() {
    final pendingTodos = _getFilteredAndSortedTodos(false);
    final completedTodos = _getFilteredAndSortedTodos(true);

    if (_todos.isEmpty || (pendingTodos.isEmpty && completedTodos.isEmpty)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.assignment,
              size: 60,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No tasks yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add your first task above',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pendingTodos.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Pending Tasks',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pendingTodos.length,
            itemBuilder: (context, i) => _buildTodoItem(context, pendingTodos[i].key),
          ),
        ],
        if (completedTodos.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Pending Tasks',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: _clearCompleted,
                  child: Text(
                    'Clear completed',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: completedTodos.length,
            itemBuilder: (context, i) =>
                _buildTodoItem(context, completedTodos[i].key),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('To-Do List'),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
                widget.isDarkTheme ? Icons.wb_sunny : Icons.nightlight_round),
            onPressed: widget.toggleTheme,
            tooltip: 'Toggle theme',
          ),
          PopupMenuButton<String>(
            onSelected: (String value) {
              setState(() {
                _sortBy = value;
              });
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'Creation',
                child: Text('Sort by Creation'),
              ),
              const PopupMenuItem<String>(
                value: 'Due Date',
                child: Text('Sort by Due Date'),
              ),
              const PopupMenuItem<String>(
                value: 'Priority',
                child: Text('Sort by Priority'),
              ),
            ],
            icon: const Icon(Icons.sort),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search tasks',
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildAddTodoCard(),
            _buildStatsCard(),
            const SizedBox(height: 16),
            _buildTodoList(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _todoController.clear();
          _selectedDueDate = null;
          _selectedPriority = 'Medium';
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            builder: (context) => Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Add New Task',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _todoController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Task description',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButton<String>(
                            value: _selectedPriority,
                            isExpanded: true,
                            items: ['Low', 'Medium', 'High'].map((String value) {
                              return DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _selectedPriority = newValue;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: _pickDueDate,
                          child: Text(_selectedDueDate == null
                              ? 'Set Due Date'
                              : 'Due: ${_selectedDueDate!.toLocal().toString().split('.')[0]}'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () {
                          _addTodo();
                          Navigator.pop(context);
                        },
                        child: const Text('Add Task'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        child: const Icon(Icons.add),
        tooltip: 'Add new task',
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
          if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SecondScreen()),
            ).then((_) {
              setState(() {
                _currentIndex = 0;
              });
            });
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'My Note',
          ),
        ],
      ),
    );
  }
}