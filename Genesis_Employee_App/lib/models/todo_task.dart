class TodoTask {
  final String id;
  final String title;
  final String description;
  final bool isCompleted;
  final String? completedAt;
  final String taskDate;
  final int sortOrder;
  final bool canEdit;
  final bool canDelete;
  final String? assignerDisplay;
  final String? assignmentLabel;

  const TodoTask({
    required this.id,
    required this.title,
    required this.description,
    required this.isCompleted,
    this.completedAt,
    required this.taskDate,
    required this.sortOrder,
    this.canEdit = true,
    this.canDelete = true,
    this.assignerDisplay,
    this.assignmentLabel,
  });

  bool get isPending => !isCompleted;

  factory TodoTask.fromJson(Map<String, dynamic> json) {
    return TodoTask(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      isCompleted: json['is_completed'] == true,
      completedAt: json['completed_at']?.toString(),
      taskDate: json['task_date']?.toString() ?? '',
      sortOrder: json['sort_order'] is int
          ? json['sort_order'] as int
          : int.tryParse(json['sort_order']?.toString() ?? '0') ?? 0,
      canEdit: json['can_edit'] != false,
      canDelete: json['can_delete'] != false,
      assignerDisplay: json['assigner_display']?.toString(),
      assignmentLabel: json['assignment_label']?.toString(),
    );
  }
}
