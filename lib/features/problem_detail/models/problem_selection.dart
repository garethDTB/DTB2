enum ConfirmStage { none, start1, start2, finish, feet, review }

class ProblemSelection {
  final List<int> holds; // selection order
  final int? start1;
  final int? start2;
  final int? finish;
  final Set<int> feet;
  final ConfirmStage stage;

  const ProblemSelection({
    this.holds = const [],
    this.start1,
    this.start2,
    this.finish,
    this.feet = const {},
    this.stage = ConfirmStage.none,
  });

  ProblemSelection copyWith({
    List<int>? holds,
    int? start1,
    int? start2,
    int? finish,
    Set<int>? feet,
    ConfirmStage? stage,
  }) {
    return ProblemSelection(
      holds: holds ?? this.holds,
      start1: start1 ?? this.start1,
      start2: start2 ?? this.start2,
      finish: finish ?? this.finish,
      feet: feet ?? this.feet,
      stage: stage ?? this.stage,
    );
  }
}
