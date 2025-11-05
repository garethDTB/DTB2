import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sticky_grouped_list/sticky_grouped_list.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'features/problem_detail/presentation/problem_detail_page.dart';
import 'create_problem_page.dart'; // ✅ needed for draft editing
import 'settings_page.dart';
import 'auth_state.dart';
import 'services/api_service.dart';
import 'providers/problems_provider.dart';
import 'hold_utils.dart';
import 'package:flutter/services.dart' show rootBundle;

class LoadProblemsPage extends StatefulWidget {
  final String wallId;
  final bool isDraftMode; // ✅ distinguish drafts
  final List<String> superusers;
  const LoadProblemsPage({
    super.key,
    required this.wallId,
    this.isDraftMode = false,
    this.superusers = const [],
  });

  @override
  State<LoadProblemsPage> createState() => _LoadProblemsPageState();
}

class _LoadProblemsPageState extends State<LoadProblemsPage> {
  TextEditingController searchController = TextEditingController();
  ProblemFilterType activeFilter = ProblemFilterType.none;

  List<Map<String, dynamic>> _draftProblems = [];
  bool _loadingDrafts = false;
  String? wallDisplayName;

  @override
  void initState() {
    super.initState();
    _loadWallName();
    if (widget.isDraftMode) {
      _loadDrafts();
    } else {
      Future.microtask(() async {
        final provider = context.read<ProblemsProvider>();
        final api = context.read<ApiService>();
        final auth = context.read<AuthState>();
        await provider.load(widget.wallId, api, auth.username ?? "guest");
      });
    }
  }

  Future<void> _loadWallName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wallJson = prefs.getString('lastSelectedWall');
      if (wallJson != null) {
        final wall = Map<String, dynamic>.from(jsonDecode(wallJson));
        if (wall['appName'] == widget.wallId) {
          setState(() => wallDisplayName = wall['userName']);
        }
      }
    } catch (e) {
      debugPrint("⚠️ Failed to load wall display name: $e");
    }
  }

  Future<void> _loadDrafts() async {
    setState(() => _loadingDrafts = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File("${dir.path}/${widget.wallId}_drafts.csv");
      if (await file.exists()) {
        final lines = await file.readAsLines();
        final problems = <Map<String, dynamic>>[];

        for (final line in lines) {
          final parts = line.split("\t");
          if (parts.length < 5) continue;

          final holdLabels = parts.sublist(5);

          // 🔎 Debug only — just show labels, no coordinate math here
          debugPrint(
            "📄 Draft parsed: ${parts[0]}  ★${parts[4]}  "
            "holds=${holdLabels.length}  [${holdLabels.take(8).join(', ')}…]",
          );

          problems.add({
            "name": parts[0],
            "grade": parts[1],
            "comment": parts[2],
            "setter": parts[3],
            "stars": int.tryParse(parts[4]) ?? 0,
            "holds": holdLabels, // <-- pass labels only
          });
        }

        setState(() => _draftProblems = problems);
      }
    } catch (e) {
      debugPrint("⚠️ Failed to load drafts: $e");
    } finally {
      setState(() => _loadingDrafts = false);
    }
  }

  Future<void> _deleteDraft(String name) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File("${dir.path}/${widget.wallId}_drafts.csv");
      if (!await file.exists()) return;
      final lines = await file.readAsLines();
      final updated = lines.where((line) {
        final parts = line.split("\t");
        return parts.isNotEmpty && parts[0] != name;
      }).toList();
      await file.writeAsString(updated.join("\n"));
      _loadDrafts();
    } catch (e) {
      debugPrint("⚠️ Failed to delete draft: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProblemsProvider>();

    final availableGrades = widget.isDraftMode
        ? _draftProblems
              .map((p) => p['grade'] as String? ?? '')
              .where((g) => g.isNotEmpty)
              .toSet()
              .toList()
        : provider.allProblems
              .map((p) => p['grade'] as String? ?? '')
              .where((g) => g.isNotEmpty)
              .toSet()
              .toList();

    availableGrades.sort(provider.gradeSort);

    // ✅ Ensure selectedGrade is valid
    if (!widget.isDraftMode &&
        provider.selectedGrade != null &&
        !availableGrades.contains(provider.selectedGrade)) {
      provider.selectedGrade = null;
    }

    Widget body;
    if (widget.isDraftMode) {
      if (_loadingDrafts) {
        body = const Center(child: CircularProgressIndicator());
      } else if (_draftProblems.isEmpty) {
        body = const Center(child: Text("No draft problems yet"));
      } else {
        body = _buildListView(
          context,
          _draftProblems,
          availableGrades,
          isDraftMode: true,
        );
      }
    } else {
      if (provider.isLoading && !provider.hasLoaded) {
        body = const Center(child: CircularProgressIndicator());
      } else if (provider.filteredProblems.isEmpty) {
        body = const Center(child: Text("No problems yet for this wall"));
      } else {
        body = RefreshIndicator(
          onRefresh: () async {
            final api = context.read<ApiService>();
            final auth = context.read<AuthState>();
            await provider.load(widget.wallId, api, auth.username!);

            // 🔄 Reset filters & search after reload
            setState(() {
              activeFilter = ProblemFilterType.none;
              provider.selectedGrade = null;
              searchController.clear();
            });
            provider.filterProblems(
              "",
              null,
              extraFilter: ProblemFilterType.none,
            );
          },

          child: _buildListView(
            context,
            provider.filteredProblems,
            availableGrades,
          ),
        );
      }
    }

    final filtersActive =
        activeFilter != ProblemFilterType.none ||
        (!widget.isDraftMode && provider.selectedGrade != null);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isDraftMode
              ? "Draft Problems"
              : "${wallDisplayName ?? widget.wallId} Problems",
        ),
        actions: [
          if (!widget.isDraftMode)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
                final api = context.read<ApiService>();
                final auth = context.read<AuthState>();
                await provider.load(
                  widget.wallId,
                  api,
                  auth.username ?? "guest",
                );
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 🔍 Search bar
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: searchController,
                decoration: InputDecoration(
                  labelText: "Search",
                  hintText: widget.isDraftMode
                      ? "By name, grade or comment"
                      : "By name, setter, grade or comment",
                  border: const OutlineInputBorder(),
                ),
                onChanged: (query) {
                  if (!widget.isDraftMode) {
                    final grade =
                        availableGrades.contains(provider.selectedGrade)
                        ? provider.selectedGrade
                        : null;
                    provider.filterProblems(
                      query,
                      grade,
                      extraFilter: activeFilter,
                    );
                  } else {
                    setState(() {
                      _draftProblems = _draftProblems.where((p) {
                        final n = (p['name'] ?? '').toLowerCase();
                        final g = (p['grade'] ?? '').toLowerCase();
                        final c = (p['comment'] ?? '').toLowerCase();
                        return n.contains(query.toLowerCase()) ||
                            g.contains(query.toLowerCase()) ||
                            c.contains(query.toLowerCase());
                      }).toList();
                    });
                  }
                },
              ),
            ),
            // 🔹 Grade + filters row
            if (!widget.isDraftMode)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    DropdownButton<String?>(
                      hint: const Text("All grades"),
                      value: availableGrades.contains(provider.selectedGrade)
                          ? provider.selectedGrade
                          : null,
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text("All grades"),
                        ),
                        ...availableGrades.map(
                          (grade) => DropdownMenuItem<String?>(
                            value: grade,
                            child: Text(
                              provider.gradeMode == "vgrade"
                                  ? frenchToVGrade(grade)
                                  : grade,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        provider.selectedGrade = value;
                        provider.filterProblems(
                          searchController.text,
                          provider.selectedGrade,
                          extraFilter: activeFilter,
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    _filterIcon(
                      provider,
                      tooltip: "Liked",
                      icon: Icons.favorite,
                      color: Colors.purple,
                      type: ProblemFilterType.liked,
                      availableGrades: availableGrades,
                    ),
                    _filterIcon(
                      provider,
                      tooltip: "Attempted (not ticked)",
                      icon: Icons.close,
                      color: Colors.red,
                      type: ProblemFilterType.attempted,
                      availableGrades: availableGrades,
                    ),
                    _filterIcon(
                      provider,
                      tooltip: "Ticked",
                      icon: Icons.check_circle,
                      color: Colors.green,
                      type: ProblemFilterType.ticked,
                      availableGrades: availableGrades,
                    ),
                    _filterIcon(
                      provider,
                      tooltip: "Not ticked",
                      icon: Icons.radio_button_unchecked,
                      color: Colors.grey,
                      type: ProblemFilterType.notTicked,
                      availableGrades: availableGrades,
                    ),
                    _filterIcon(
                      provider,
                      tooltip: "Benchmarks",
                      icon: Icons.star,
                      color: Colors.amber,
                      type: ProblemFilterType.benchmarks,
                      availableGrades: availableGrades,
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: "Reset filters",
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          setState(() {
                            activeFilter = ProblemFilterType.none;
                            provider.selectedGrade = null;
                            searchController.clear();
                          });
                          provider.filterProblems(
                            "",
                            null,
                            extraFilter: ProblemFilterType.none,
                          );
                        },
                        child: CircleAvatar(
                          backgroundColor: filtersActive
                              ? Colors.red.withOpacity(0.8)
                              : Colors.grey[200],
                          child: Icon(
                            Icons.refresh,
                            color: filtersActive
                                ? Colors.white
                                : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _buildListView(
    BuildContext context,
    List<Map<String, dynamic>> problems,
    List<String> availableGrades, {
    bool isDraftMode = false,
  }) {
    return StickyGroupedListView<Map<String, dynamic>, String>(
      elements: problems,
      groupBy: (element) => element['grade'] as String? ?? '',
      physics: const AlwaysScrollableScrollPhysics(),
      groupSeparatorBuilder: (Map<String, dynamic> element) {
        final grade = element['grade'] as String? ?? '';
        final displayGrade =
            !isDraftMode &&
                context.read<ProblemsProvider>().gradeMode == "vgrade"
            ? frenchToVGrade(grade)
            : grade;
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            displayGrade,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        );
      },
      itemBuilder: (context, problem) {
        final provider = context.read<ProblemsProvider>();
        final rawName = (problem['name'] as String? ?? '').trim();

        Color? bgColor;
        if (!isDraftMode) {
          if (provider.tickedProblemsToday.contains(rawName)) {
            bgColor = Colors.green.shade100;
          } else if (provider.tickedProblemsPast.contains(rawName)) {
            bgColor = Colors.purple.shade100;
          } else if (provider.attemptedProblems.contains(rawName)) {
            bgColor = Colors.red.shade100;
          }
        }

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          decoration: BoxDecoration(
            color: bgColor ?? Colors.white,
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(6),
          ),
          child: ListTile(
            title: Text(
              _displayName(
                problem,
                isDraftMode ? "french" : provider.gradeMode,
              ),
            ),
            subtitle: Text(
              "${problem['setter'] ?? ''} - ${problem['comment'] ?? ''}",
            ),
            trailing: isDraftMode
                ? IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteDraft(problem['name']),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IgnorePointer(
                        ignoring: true,
                        child: Opacity(
                          opacity: 0.6,
                          child: Row(
                            children: [
                              Icon(
                                Icons.favorite,
                                color: problem['likedByUser'] == true
                                    ? Colors.purple
                                    : (problem['likesCount'] ?? 0) > 0
                                    ? Colors.red
                                    : Colors.grey,
                                size: problem['likedByUser'] == true ? 30 : 24,
                              ),
                              const SizedBox(width: 4),
                              Text("${problem['likesCount'] ?? 0}"),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      IgnorePointer(
                        ignoring: true,
                        child: Opacity(
                          opacity: 0.6,
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: Colors.teal,
                                size: 24,
                              ),
                              const SizedBox(width: 4),
                              Text("${problem['ticks'] ?? 0}"),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
            onTap: () async {
              if (isDraftMode) {
                // 🚀 Jump to CreateProblemPage with this draft
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateProblemPage(
                      wallId: widget.wallId,
                      isDraftMode: true,
                      draftRow: [
                        problem['name'] ?? '',
                        problem['grade'] ?? '',
                        problem['comment'] ?? '',
                        problem['setter'] ?? '',
                        (problem['stars'] ?? 0).toString(),
                        ...(problem['holds'] ?? []),
                      ],
                    ),
                  ),
                );
                // After returning, refresh drafts
                _loadDrafts();
              } else {
                final index = problems.indexOf(problem);
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProblemDetailPage(
                      wallId: widget.wallId,
                      problem: problem,
                      problems: problems,
                      initialIndex: index,
                      numRows: provider.numRows,
                      numCols: provider.numCols,
                      gradeMode: provider.gradeMode,
                      superusers: widget.superusers,
                    ),
                  ),
                );
              }
            },
          ),
        );
      },
      itemComparator: (a, b) {
        final provider = context.read<ProblemsProvider>();
        final gA = a['grade'] ?? '';
        final gB = b['grade'] ?? '';
        final cmp = provider.gradeSort(gA, gB);
        if (cmp != 0) return cmp;
        final popA = (a['ticks'] ?? 0) + (a['likesCount'] ?? 0);
        final popB = (b['ticks'] ?? 0) + (b['likesCount'] ?? 0);
        return popB.compareTo(popA);
      },
      order: StickyGroupedListOrder.ASC,
    );
  }

  Widget _filterIcon(
    ProblemsProvider provider, {
    required String tooltip,
    required IconData icon,
    required Color color,
    required ProblemFilterType type,
    required List<String> availableGrades,
  }) {
    final isActive = activeFilter == type;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            setState(() {
              activeFilter = isActive ? ProblemFilterType.none : type;
            });
            final grade = availableGrades.contains(provider.selectedGrade)
                ? provider.selectedGrade
                : null;
            provider.filterProblems(
              searchController.text,
              grade,
              extraFilter: activeFilter,
            );
          },
          child: CircleAvatar(
            backgroundColor: isActive
                ? color.withOpacity(0.2)
                : Colors.grey[200],
            child: Icon(icon, color: isActive ? color : Colors.grey),
          ),
        ),
      ),
    );
  }

  String _displayName(Map<String, dynamic> problem, String gradeMode) {
    final rawName = problem['name'] ?? '';
    final grade = problem['grade'] ?? '';
    if (gradeMode == "vgrade") {
      return rawName.replaceAll(grade, frenchToVGrade(grade));
    }
    return rawName;
  }
}
