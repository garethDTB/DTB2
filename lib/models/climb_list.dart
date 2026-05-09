class ClimbListProblem {
  final String problemId;
  final String problem;
  final String grade;
  final int order;
  final String note;

  ClimbListProblem({
    required this.problemId,
    required this.problem,
    required this.grade,
    required this.order,
    this.note = '',
  });

  factory ClimbListProblem.fromJson(Map<String, dynamic> json) {
    return ClimbListProblem(
      problemId: json['ProblemId'] ?? '',
      problem: json['Problem'] ?? '',
      grade: json['Grade'] ?? '',
      order: json['Order'] ?? 0,
      note: json['Note'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ProblemId': problemId,
      'Problem': problem,
      'Grade': grade,
      'Order': order,
      'Note': note,
    };
  }
}

class ClimbList {
  final String id;
  final String users;
  final String displayName;
  final String wall;
  final String title;
  final String description;
  final bool isPublic;
  final List<ClimbListProblem> problems;

  ClimbList({
    required this.id,
    required this.users,
    required this.displayName,
    required this.wall,
    required this.title,
    required this.description,
    required this.isPublic,
    required this.problems,
  });

  factory ClimbList.fromJson(Map<String, dynamic> json) {
    return ClimbList(
      id: json['id'] ?? '',
      users: json['Users'] ?? '',
      displayName: json['DisplayName'] ?? '',
      wall: json['Wall'] ?? '',
      title: json['Title'] ?? '',
      description: json['Description'] ?? '',
      isPublic: json['IsPublic'] ?? true,
      problems: (json['Problems'] as List? ?? [])
          .map((p) => ClimbListProblem.fromJson(Map<String, dynamic>.from(p)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'Users': users,
      'DisplayName': displayName,
      'Wall': wall,
      'Title': title,
      'Description': description,
      'IsPublic': isPublic,
      'Problems': problems.map((p) => p.toJson()).toList(),
    };
  }
}
