import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/todo_task.dart';
import '../services/api_service.dart';
import '../services/foreground_refresh_service.dart';
import 'todo_detail_screen.dart';
import 'todo_form_screen.dart';

enum _TaskFilter { all, pending, completed }

class TodoListScreen extends StatefulWidget {
  const TodoListScreen({super.key});

  @override
  State<TodoListScreen> createState() => _TodoListScreenState();
}

class _TodoListScreenState extends State<TodoListScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String _errorMessage = '';
  List<TodoTask> _tasks = [];
  _TaskFilter _filter = _TaskFilter.all;
  late DateTime _selectedDate;
  bool _historyMode = false;
  late DateTime _historyStart;
  late DateTime _historyEnd;

  static final _dateFormat = DateFormat('yyyy-MM-dd');
  static final _displayFormat = DateFormat('EEEE, d MMM yyyy');
  static final _completedAtFormat = DateFormat('d MMM yyyy, h:mm a');

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get _maxFutureDate => _today.add(const Duration(days: 30));

  bool get _canAddOnSelectedDate {
    final selected = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    return !selected.isBefore(_today) && !selected.isAfter(_maxFutureDate);
  }

  List<TodoTask> get _filteredTasks {
    switch (_filter) {
      case _TaskFilter.pending:
        return _tasks.where((t) => t.isPending).toList();
      case _TaskFilter.completed:
        return _tasks.where((t) => t.isCompleted).toList();
      case _TaskFilter.all:
        return _tasks;
    }
  }

  List<TodoTask> get _pendingTasks => _filteredTasks.where((t) => t.isPending).toList();
  List<TodoTask> get _completedTasks => _filteredTasks.where((t) => t.isCompleted).toList();

  int get _completedCount => _tasks.where((t) => t.isCompleted).length;
  int get _totalCount => _tasks.length;

  @override
  void initState() {
    super.initState();
    _selectedDate = _today;
    _historyStart = _today.subtract(const Duration(days: 30));
    _historyEnd = _today;
    ForegroundRefreshService().addListener(_onForegroundRefresh);
    _fetchTasks();
  }

  @override
  void dispose() {
    ForegroundRefreshService().removeListener(_onForegroundRefresh);
    _searchController.dispose();
    super.dispose();
  }

  void _onForegroundRefresh() {
    if (!mounted) return;
    _fetchTasks();
  }

  Future<void> _fetchTasks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final search = _searchController.text.trim();
    List<Map<String, dynamic>> raw;
    if (_historyMode) {
      raw = await _apiService.getMyTodos(
        taskDateFrom: _dateFormat.format(_historyStart),
        taskDateTo: _dateFormat.format(_historyEnd),
        search: search.isEmpty ? null : search,
      );
    } else {
      raw = await _apiService.getMyTodos(
        taskDate: _dateFormat.format(_selectedDate),
        search: search.isEmpty ? null : search,
      );
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _tasks = raw.map(TodoTask.fromJson).toList();
    });
  }

  Future<void> _onRefresh() async {
    ApiService().initialize();
    await _fetchTasks();
  }

  Future<void> _pickSelectedDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: _today.subtract(const Duration(days: 365)),
      lastDate: _maxFutureDate,
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = DateTime(picked.year, picked.month, picked.day);
        _historyMode = false;
      });
      _fetchTasks();
    }
  }

  Future<void> _showAddTaskDialog() async {
    if (!_canAddOnSelectedDate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot add tasks for this date.')),
      );
      return;
    }

    final result = await showDialog<String>(
      context: context,
      builder: (context) => const _AddTaskDialog(),
    );

    if (result == null || !mounted) return;

    setState(() => _isLoading = true);
    final created = await _apiService.createTodo(
      description: result,
      taskDate: _dateFormat.format(_selectedDate),
    );
    if (!mounted) return;

    if (created != null && created.containsKey('error')) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(created['error']?.toString() ?? 'Failed to create task')),
      );
      return;
    }
    await _fetchTasks();
  }

  Future<void> _confirmDelete(TodoTask task) async {
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

    final ok = await _apiService.deleteTodo(task.id);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete task')),
      );
      return;
    }
    await _fetchTasks();
  }

  Future<void> _toggleComplete(TodoTask task) async {
    final updated = await _apiService.toggleTodoComplete(
      id: task.id,
      isCompleted: !task.isCompleted,
    );
    if (!mounted) return;
    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update completion')),
      );
      return;
    }
    await _fetchTasks();
  }

  String? _formatCompletedAt(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    try {
      return _completedAtFormat.format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return null;
    }
  }

  Widget _buildDateChips(ThemeData theme, ColorScheme colorScheme) {
    final tomorrow = _today.add(const Duration(days: 1));
    final nextWeek = _today.add(const Duration(days: 7));

    void select(DateTime date) {
      setState(() {
        _selectedDate = date;
        _historyMode = false;
      });
      _fetchTasks();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          FilterChip(
            label: const Text('Today'),
            selected: !_historyMode && _isSameDay(_selectedDate, _today),
            onSelected: (_) => select(_today),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Tomorrow'),
            selected: !_historyMode && _isSameDay(_selectedDate, tomorrow),
            onSelected: (_) => select(tomorrow),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('+7 days'),
            selected: !_historyMode && _isSameDay(_selectedDate, nextWeek),
            onSelected: (_) => select(nextWeek),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('History'),
            selected: _historyMode,
            onSelected: (_) {
              setState(() => _historyMode = true);
              _fetchTasks();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(ColorScheme colorScheme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          FilterChip(
            label: const Text('All'),
            selected: _filter == _TaskFilter.all,
            onSelected: (_) => setState(() => _filter = _TaskFilter.all),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Pending'),
            selected: _filter == _TaskFilter.pending,
            onSelected: (_) => setState(() => _filter = _TaskFilter.pending),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Completed'),
            selected: _filter == _TaskFilter.completed,
            onSelected: (_) => setState(() => _filter = _TaskFilter.completed),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildTaskCard(TodoTask task, ThemeData theme, ColorScheme colorScheme) {
    final completedLabel = _formatCompletedAt(task.completedAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: task.isCompleted ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.4) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TodoDetailScreen(task: task)),
          );
          if (mounted) _fetchTasks();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: task.isCompleted,
                onChanged: (_) => _toggleComplete(task),
                shape: const CircleBorder(),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              task.title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: task.isCompleted ? colorScheme.onSurfaceVariant : null,
                              ),
                            ),
                          ),
                          if (_historyMode)
                            Text(
                              task.taskDate,
                              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                      if (task.assignerDisplay != null && task.assignerDisplay!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${task.assignerDisplay} assigned this task',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        task.description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: task.isCompleted ? colorScheme.onSurfaceVariant : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (task.isCompleted && completedLabel != null)
                        Text(
                          'Completed $completedLabel',
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.green.shade700),
                        )
                      else if (task.isPending)
                        Text(
                          'Not complete yet',
                          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              ),
              if (task.canEdit)
                IconButton(
                  tooltip: 'Edit',
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TodoFormScreen(
                          taskId: task.id,
                          initialDescription: task.description,
                        ),
                      ),
                    );
                    if (mounted) _fetchTasks();
                  },
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
              if (task.canDelete)
                IconButton(
                  tooltip: 'Delete',
                  onPressed: () => _confirmDelete(task),
                  icon: Icon(Icons.delete_outline, color: colorScheme.error, size: 20),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: color ?? Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: (color ?? Colors.grey).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color ?? Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final progress = _totalCount > 0 ? _completedCount / _totalCount : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TO-DO'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _onRefresh,
          ),
        ],
      ),
      floatingActionButton: !_historyMode && _canAddOnSelectedDate
          ? FloatingActionButton.extended(
              onPressed: _showAddTaskDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add Task'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (_totalCount > 0 && !_isLoading)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$_completedCount/$_totalCount completed',
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${_tasks.where((t) => t.isPending).length} pending',
                            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_historyMode) ...[
                      InkWell(
                        onTap: _pickSelectedDate,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colorScheme.outlineVariant),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today_outlined, color: colorScheme.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _displayFormat.format(_selectedDate),
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildDateChips(theme, colorScheme),
                    ] else ...[
                      Text('History range', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _historyStart,
                                  firstDate: DateTime(2020),
                                  lastDate: _today,
                                );
                                if (picked != null && mounted) {
                                  setState(() => _historyStart = picked);
                                  _fetchTasks();
                                }
                              },
                              child: Text(_dateFormat.format(_historyStart)),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('to'),
                          ),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _historyEnd,
                                  firstDate: _historyStart,
                                  lastDate: _today,
                                );
                                if (picked != null && mounted) {
                                  setState(() => _historyEnd = picked);
                                  _fetchTasks();
                                }
                              },
                              child: Text(_dateFormat.format(_historyEnd)),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search task title',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _fetchTasks();
                          },
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _fetchTasks(),
                    ),
                    if (!_isLoading && _tasks.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildFilterChips(colorScheme),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errorMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(_errorMessage, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _fetchTasks,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else if (_filteredTasks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(48),
                child: Center(
                  child: Text(
                    _historyMode ? 'No tasks found in this range.' : 'No tasks for this date.',
                    style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else ...[
              if (_pendingTasks.isNotEmpty) ...[
                _buildSectionHeader('Pending', _pendingTasks.length),
                ..._pendingTasks.map((task) => _buildTaskCard(task, theme, colorScheme)),
              ],
              if (_completedTasks.isNotEmpty) ...[
                _buildSectionHeader('Completed', _completedTasks.length, color: Colors.green),
                ..._completedTasks.map((task) => _buildTaskCard(task, theme, colorScheme)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _AddTaskDialog extends StatefulWidget {
  const _AddTaskDialog();

  @override
  State<_AddTaskDialog> createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends State<_AddTaskDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Task'),
      content: TextField(
        controller: _controller,
        maxLines: 4,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Task description',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
