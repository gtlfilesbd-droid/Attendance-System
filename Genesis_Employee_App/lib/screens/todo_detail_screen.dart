import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/todo_task.dart';
import '../services/api_service.dart';
import 'todo_form_screen.dart';

class TodoDetailScreen extends StatefulWidget {
  final TodoTask task;

  const TodoDetailScreen({super.key, required this.task});

  @override
  State<TodoDetailScreen> createState() => _TodoDetailScreenState();
}

class _TodoDetailScreenState extends State<TodoDetailScreen> {
  final ApiService _apiService = ApiService();
  late TodoTask _task;
  static final _displayFormat = DateFormat('EEEE, d MMM yyyy');
  static final _completedAtFormat = DateFormat('d MMM yyyy, h:mm a');

  @override
  void initState() {
    super.initState();
    _task = widget.task;
  }

  Future<void> _toggleComplete(bool value) async {
    final updated = await _apiService.toggleTodoComplete(
      id: _task.id,
      isCompleted: value,
    );
    if (!mounted) return;
    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update completion')),
      );
      return;
    }
    setState(() => _task = TodoTask.fromJson(updated));
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await _apiService.deleteTodo(_task.id);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete task')),
      );
      return;
    }
    Navigator.pop(context, true);
  }

  DateTime? _parseDate(String value) {
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  String? _formatCompletedAt(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    try {
      return _completedAtFormat.format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final parsed = _parseDate(_task.taskDate);
    final completedLabel = _formatCompletedAt(_task.completedAt);

    return Scaffold(
      appBar: AppBar(
        title: Text(_task.title),
        actions: [
          if (_task.canEdit)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final changed = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TodoFormScreen(
                      taskId: _task.id,
                      initialDescription: _task.description,
                    ),
                  ),
                );
                if (changed == true && mounted) {
                  final tasks = await _apiService.getMyTodos(taskDate: _task.taskDate);
                  final match = tasks
                      .map(TodoTask.fromJson)
                      .where((t) => t.id == _task.id)
                      .toList();
                  if (match.isNotEmpty) {
                    setState(() => _task = match.first);
                  }
                }
              },
            ),
          if (_task.canDelete)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Checkbox(
                      value: _task.isCompleted,
                      onChanged: (value) {
                        if (value != null) _toggleComplete(value);
                      },
                      shape: const CircleBorder(),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _task.isCompleted ? 'Completed' : 'Not complete yet',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: _task.isCompleted ? Colors.green.shade700 : colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (_task.isCompleted && completedLabel != null)
                            Text(
                              'Completed at: $completedLabel',
                              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (parsed != null)
              Text(
                _displayFormat.format(parsed),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 16),
            Text('Description', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              _task.description,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: _task.isCompleted ? colorScheme.onSurfaceVariant : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
