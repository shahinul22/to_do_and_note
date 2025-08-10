import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'second_screen.dart';

void main() {
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
      theme: isDarkTheme ? ThemeData.dark() : ThemeData.light(),
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
  List<Map<String, dynamic>> _todos = [];
  int _currentIndex = 0;

  static const String todosKey = 'todos_list';

  @override
  void initState() {
    super.initState();
    _loadTodos();
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
  }

  Future<void> _saveTodos() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_todos);
    await prefs.setString(todosKey, encoded);
  }

  @override
  void dispose() {
    _todoController.dispose();
    super.dispose();
  }

  void _addTodo() {
    if (_todoController.text.trim().isEmpty) return;

    setState(() {
      _todos.add({
        'task': _todoController.text.trim(),
        'completed': false,
        'created': DateTime.now().toIso8601String(),
      });
      _todoController.clear();
    });
    _saveTodos();
  }

  void _toggleTodo(int index) {
    setState(() {
      _todos[index]['completed'] = !_todos[index]['completed'];
    });
    _saveTodos();
  }

  void _deleteTodo(int index) {
    setState(() {
      _todos.removeAt(index);
    });
    _saveTodos();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Task deleted')),
    );
  }

  void _clearCompleted() {
    setState(() {
      _todos.removeWhere((todo) => todo['completed']);
    });
    _saveTodos();
  }

  Widget _buildTodoItem(BuildContext context, int index) {
    final todo = _todos[index];
    return Dismissible(
      key: Key('${todo['task']}_${todo['created']}'),
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) => _deleteTodo(index),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          leading: Checkbox(
            value: todo['completed'],
            onChanged: (value) => _toggleTodo(index),
          ),
          title: Text(
            todo['task'],
            style: TextStyle(
              decoration: todo['completed'] ? TextDecoration.lineThrough : null,
              color: todo['completed'] ? Colors.grey : null,
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _deleteTodo(index),
          ),
        ),
      ),
    );
  }

  Widget _buildAddTodoCard() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add New Task',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _todoController,
              decoration: InputDecoration(
                labelText: 'Task description',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _todoController.clear(),
                ),
              ),
              onSubmitted: (_) => _addTodo(),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(Icons.list_alt, 'Total', _todos.length.toString()),
            _buildStatItem(Icons.check_circle, 'Completed', completedCount.toString()),
            _buildStatItem(Icons.pending_actions, 'Pending', pendingCount.toString()),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, size: 30, color: Theme.of(context).primaryColor),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }

  Widget _buildTodoList() {
    if (_todos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment, size: 60, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No tasks yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey),
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
      children: [
        if (_todos.any((todo) => todo['completed']))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _clearCompleted,
                child: const Text('Clear completed'),
              ),
            ),
          ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _todos.length,
          itemBuilder: _buildTodoItem,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('To-Do List App'),
        actions: [
          IconButton(
            icon: Icon(widget.isDarkTheme ? Icons.wb_sunny : Icons.nightlight_round),
            onPressed: widget.toggleTheme,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
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
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
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
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _todoController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Task description',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
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
