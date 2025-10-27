class Attempt {
  final String problem;
  final String grade;
  final int attempts;

  Attempt({required this.problem, required this.grade, required this.attempts});

  factory Attempt.fromJson(Map<String, dynamic> json) {
    return Attempt(
      problem: json['Problem'] ?? '',
      grade: json['Grade'] ?? '',
      attempts: json['Number'] ?? 0, // normalize "Number" → attempts
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "Problem": problem,
      "Grade": grade,
      "Number": attempts, // always write back as "Number"
    };
  }
}

class SentProblem {
  final String problem;
  final String grade;
  final String user;
  final String wall;
  final int attempts;
  final String? notes;
  final bool? tooHard;
  final bool? tooEasy;
  final int? stars;

  SentProblem({
    required this.problem,
    required this.grade,
    required this.user,
    required this.wall,
    required this.attempts,
    this.notes,
    this.tooHard,
    this.tooEasy,
    this.stars,
  });

  factory SentProblem.fromJson(Map<String, dynamic> json) {
    int rawAttempts = json['Attempts'] ?? 0;

    return SentProblem(
      problem: json['Problem'] ?? '',
      grade: json['Grade'] ?? '',
      user: json['User'] ?? '',
      wall: json['Wall'] ?? '',
      // ensure at least 1 attempt if it was actually sent
      attempts: rawAttempts == 0 ? 1 : rawAttempts,
      notes: json['Notes'],
      tooHard: json['TooHard'],
      tooEasy: json['TooEasy'],
      stars: json['Stars'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "Problem": problem,
      "Grade": grade,
      "User": user,
      "Wall": wall,
      "Attempts": attempts,
      "Notes": notes,
      "TooHard": tooHard,
      "TooEasy": tooEasy,
      "Stars": stars,
    };
  }
}

class Session {
  final String id;
  final String user;
  final String wall;
  final DateTime date;
  final int score;
  final List<Attempt> attempts;
  final List<SentProblem> sent;

  Session({
    required this.id,
    required this.user,
    required this.wall,
    required this.date,
    required this.score,
    required this.attempts,
    required this.sent,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'] ?? '',
      user: json['User'] ?? '',
      wall: json['Wall'] ?? '',
      date: DateTime.tryParse(json['Date'] ?? '') ?? DateTime.now(),
      score: json['Score'] ?? 0,
      attempts: (json['Attempts'] as List<dynamic>? ?? [])
          .map((a) => Attempt.fromJson(a))
          .toList(),
      sent: (json['Sent'] as List<dynamic>? ?? [])
          .map((s) => SentProblem.fromJson(s))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "User": user,
      "Wall": wall,
      "Date": date.toIso8601String(),
      "Score": score,
      "Attempts": attempts.map((a) => a.toJson()).toList(),
      "Sent": sent.map((s) => s.toJson()).toList(),
    };
  }
}
