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
  List<Map<String, dynamic>> _publicLists = [];
  List<Map<String, dynamic>> _myLists = [];
  Map<String, dynamic>? _selectedList;
  bool _listsLoading = false;
  bool _editingList = false;

  @override
  void initState() {
    super.initState();

    _loadWallName();

    if (widget.isDraftMode) {
      _loadDrafts();
    } else {
      _loadLists();

      Future.microtask(() async {
        final provider = context.read<ProblemsProvider>();
        final api = context.read<ApiService>();
        final auth = context.read<AuthState>();
        await provider.load(widget.wallId, api, auth.username ?? "guest");
      });
    }
  }

  Future<void> _deleteList(Map<String, dynamic> list) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete list?"),
        content: Text("Delete '${list['Title'] ?? 'Untitled list'}'?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final api = context.read<ApiService>();
    final auth = context.read<AuthState>();

    await api.deleteList(
      wallId: widget.wallId,
      listId: list['id'],
      username: auth.username ?? '',
    );

    if (!mounted) return;

    setState(() {
      _myLists.removeWhere((l) => l['id'] == list['id']);
      _publicLists.removeWhere((l) => l['id'] == list['id']);

      if (_selectedList?['id'] == list['id']) {
        _selectedList = null;
        _editingList = false;
      }
    });
  }

  Future<void> _refreshListsKeepingSelection() async {
    final selectedId = _selectedList?['id'];

    await _loadLists();

    if (selectedId == null) return;

    final refreshed = [
      ..._myLists,
      ..._publicLists,
    ].where((list) => list['id'] == selectedId).toList();

    if (!mounted) return;

    setState(() {
      _selectedList = refreshed.isNotEmpty ? refreshed.first : null;
    });
  }

  Future<void> _loadLists() async {
    setState(() => _listsLoading = true);

    try {
      final api = context.read<ApiService>();
      final auth = context.read<AuthState>();
      final username = auth.username ?? '';

      debugPrint("📋 Loading lists for wall=${widget.wallId}");
      debugPrint("📋 Current user=$username");

      final allPublicLists = await api.getPublicLists(widget.wallId);
      final myLists = username.isNotEmpty
          ? await api.getMyLists(widget.wallId, username)
          : <Map<String, dynamic>>[];

      final publicLists = allPublicLists.where((list) {
        return (list['Users'] ?? '').toString() != username;
      }).toList();

      debugPrint("📋 Public lists loaded: ${publicLists.length}");
      debugPrint("📋 My lists loaded: ${myLists.length}");

      if (!mounted) return;

      setState(() {
        _publicLists = publicLists;
        _myLists = myLists;
        _listsLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Failed to load lists: $e');
      if (!mounted) return;
      setState(() => _listsLoading = false);
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
                    const SizedBox(width: 12),
                    Tooltip(
                      message: "Lists",
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _showListsMenu,
                        child: CircleAvatar(
                          backgroundColor: _selectedList != null
                              ? Colors.orange.withOpacity(0.25)
                              : Colors.grey[200],
                          child: Icon(
                            _selectedList != null
                                ? Icons.playlist_add_check
                                : Icons.format_list_bulleted,
                            color: _selectedList != null
                                ? Colors.orange
                                : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
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

  Future<void> _showListsMenu() async {
    await showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.clear),
                title: const Text('Show all climbs'),
                onTap: () {
                  setState(() {
                    _selectedList = null;
                  });
                  Navigator.pop(context);
                },
              ),

              const Divider(),

              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Create new list'),
                onTap: () {
                  Navigator.pop(context);
                  _showCreateListDialog();
                },
              ),

              if (_myLists.isNotEmpty) ...[
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'My Lists',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ..._myLists.map((list) {
                  return ListTile(
                    leading: const Icon(Icons.list),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () async {
                        Navigator.pop(context);
                        await _deleteList(list);
                      },
                    ),
                    title: Text(list['Title'] ?? 'Untitled list'),
                    subtitle: Text(
                      '${(list['Problems'] as List? ?? []).length} climbs',
                    ),
                    onTap: () {
                      setState(() {
                        _selectedList = list;
                      });
                      Navigator.pop(context);
                    },
                  );
                }),
              ],

              if (_publicLists.isNotEmpty) ...[
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Public Lists',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ..._publicLists.map((list) {
                  return ListTile(
                    leading: const Icon(Icons.public),
                    title: Text(list['Title'] ?? 'Untitled list'),
                    subtitle: Text(
                      '${list['DisplayName'] ?? list['Users'] ?? ''} • ${(list['Problems'] as List? ?? []).length} climbs',
                    ),
                    onTap: () {
                      setState(() {
                        _selectedList = list;
                      });
                      Navigator.pop(context);
                    },
                  );
                }),
              ],

              if (_listsLoading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCreateListDialog() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    bool isPublic = true;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Create new list'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'List name',
                      hintText: 'Warm-up set',
                    ),
                  ),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      hintText: 'Optional',
                    ),
                  ),
                  SwitchListTile(
                    value: isPublic,
                    title: const Text('Public list'),
                    onChanged: (value) {
                      setDialogState(() {
                        isPublic = value;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final title = titleController.text.trim();
                    if (title.isEmpty) return;

                    await _createList(
                      title: title,
                      description: descriptionController.text.trim(),
                      isPublic: isPublic,
                    );

                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _createList({
    required String title,
    required String description,
    required bool isPublic,
  }) async {
    try {
      final api = context.read<ApiService>();
      final auth = context.read<AuthState>();

      final username = auth.username ?? '';
      final displayName = auth.displayName ?? username;

      if (username.isEmpty) return;

      final newList = await api.createList(
        wallId: widget.wallId,
        username: username,
        displayName: displayName,
        title: title,
        description: description,
        isPublic: isPublic,
        problems: [],
      );

      if (!mounted) return;

      setState(() {
        _myLists.insert(0, newList);
        if (isPublic) {
          _publicLists.insert(0, newList);
        }
        _selectedList = newList;
      });
    } catch (e) {
      debugPrint('❌ Failed to create list: $e');
    }
  }

  Widget _buildListView(
    BuildContext context,
    List<Map<String, dynamic>> problems,
    List<String> availableGrades, {
    bool isDraftMode = false,
  }) {
    final auth = context.read<AuthState>();
    final username = auth.username ?? '';

    final listIsMine =
        _selectedList != null &&
        (_selectedList!['Users'] ?? '').toString() == username;
    List<Map<String, dynamic>> displayedProblems = problems;

    if (!isDraftMode && _selectedList != null) {
      final listProblems = (_selectedList!['Problems'] as List? ?? []);

      final problemIds = listProblems
          .map((p) => p['ProblemId']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .toSet();

      final problemNames = listProblems
          .map((p) => p['Problem']?.toString())
          .where((name) => name != null && name.isNotEmpty)
          .toSet();

      displayedProblems = problems.where((problem) {
        final id = problem['id']?.toString();
        final name =
            problem['name']?.toString() ?? problem['Problem']?.toString();

        return problemIds.contains(id) || problemNames.contains(name);
      }).toList();
    }

    if (displayedProblems.isEmpty) {
      return Center(
        child: Text(
          _selectedList != null
              ? "No climbs in this list yet"
              : "No problems match these filters",
        ),
      );
    }

    if (!isDraftMode && _selectedList != null) {
      final provider = context.read<ProblemsProvider>();

      final listProblems = List<Map<String, dynamic>>.from(
        (_selectedList!['Problems'] as List? ?? []),
      );

      displayedProblems.sort((a, b) {
        final aIndex = listProblems.indexWhere(
          (p) => p['Problem'] == a['name'],
        );
        final bIndex = listProblems.indexWhere(
          (p) => p['Problem'] == b['name'],
        );
        return aIndex.compareTo(bIndex);
      });

      Future<void> saveListOrder() async {
        final updatedProblems = displayedProblems.asMap().entries.map((entry) {
          return {
            "ProblemId": entry.value['id'] ?? '',
            "Problem": entry.value['name'] ?? '',
            "Grade": entry.value['grade'] ?? '',
            "Order": entry.key + 1,
            "Note": "",
          };
        }).toList();

        final api = context.read<ApiService>();

        await api.updateList(
          wallId: widget.wallId,
          listId: _selectedList!['id'],
          username: username,
          title: _selectedList!['Title'] ?? '',
          description: _selectedList!['Description'] ?? '',
          isPublic: _selectedList!['IsPublic'] ?? true,
          problems: updatedProblems,
        );

        await _refreshListsKeepingSelection();
      }

      return ReorderableListView.builder(
        itemCount: displayedProblems.length,

        onReorder: (oldIndex, newIndex) async {
          if (!listIsMine || !_editingList) return;

          if (newIndex > oldIndex) newIndex--;

          setState(() {
            final moved = displayedProblems.removeAt(oldIndex);
            displayedProblems.insert(newIndex, moved);
          });

          await saveListOrder();
        },

        itemBuilder: (context, index) {
          final problem = displayedProblems[index];
          final rawName = (problem['name'] as String? ?? '').trim();

          Color? bgColor;
          if (provider.tickedProblemsToday.contains(rawName)) {
            bgColor = Colors.green.shade100;
          } else if (provider.tickedProblemsPast.contains(rawName)) {
            bgColor = Colors.purple.shade100;
          } else if (provider.attemptedProblems.contains(rawName)) {
            bgColor = Colors.red.shade100;
          }

          return Container(
            key: ValueKey(problem['id'] ?? problem['name']),
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            decoration: BoxDecoration(
              color: bgColor ?? Colors.white,
              border: Border.all(
                color: _editingList ? Colors.orange : Colors.grey.shade400,
                width: _editingList ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ListTile(
              onLongPress: listIsMine
                  ? () {
                      setState(() {
                        _editingList = !_editingList;
                      });
                    }
                  : null,

              leading: _editingList && listIsMine
                  ? ReorderableDragStartListener(
                      index: index,
                      child: const Icon(Icons.drag_handle),
                    )
                  : null,

              title: Text(_displayName(problem, provider.gradeMode)),

              subtitle: Text(
                "${problem['setter'] ?? ''} - ${problem['comment'] ?? ''}",
              ),

              trailing: _editingList && listIsMine
                  ? IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () async {
                        setState(() {
                          displayedProblems.removeAt(index);
                        });

                        await saveListOrder();
                      },
                    )
                  : null,

              onTap: _editingList
                  ? null
                  : () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProblemDetailPage(
                            wallId: widget.wallId,
                            problem: problem,
                            problems: displayedProblems,
                            initialIndex: index,
                            numRows: provider.numRows,
                            numCols: provider.numCols,
                            gradeMode: provider.gradeMode,
                            superusers: widget.superusers,
                          ),
                        ),
                      );

                      if (!context.mounted) return;

                      final api = context.read<ApiService>();
                      final auth = context.read<AuthState>();

                      await provider.load(
                        widget.wallId,
                        api,
                        auth.username ?? "guest",
                      );

                      await _refreshListsKeepingSelection();
                    },
            ),
          );
        },
      );
    }

    return StickyGroupedListView<Map<String, dynamic>, String>(
      elements: displayedProblems,
      groupBy: (element) =>
          (element['grade'] ?? element['Grade'] ?? '').toString(),
      physics: const AlwaysScrollableScrollPhysics(),
      groupSeparatorBuilder: (Map<String, dynamic> element) {
        final grade = (element['grade'] ?? element['Grade'] ?? '').toString();
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

                _loadDrafts();
              } else {
                final index = displayedProblems.indexOf(problem);

                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProblemDetailPage(
                      wallId: widget.wallId,
                      problem: problem,
                      problems: displayedProblems,
                      initialIndex: index,
                      numRows: provider.numRows,
                      numCols: provider.numCols,
                      gradeMode: provider.gradeMode,
                      superusers: widget.superusers,
                    ),
                  ),
                );

                if (!context.mounted) return;

                final api = context.read<ApiService>();
                final auth = context.read<AuthState>();

                await provider.load(
                  widget.wallId,
                  api,
                  auth.username ?? "guest",
                );

                await _refreshListsKeepingSelection();
              }
            },
          ),
        );
      },
      itemComparator: (a, b) {
        final provider = context.read<ProblemsProvider>();
        final gA = (a['grade'] ?? a['Grade'] ?? '').toString();
        final gB = (b['grade'] ?? b['Grade'] ?? '').toString();
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
