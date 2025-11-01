import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _gradeMode = "french";
  bool _autoSend = false;

  bool _showGuide = false;
  final List<bool> _expanded = List.filled(6, false); // one extra for "Create"
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _guideKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _gradeMode = prefs.getString('gradeMode') ?? "french";
      _autoSend = prefs.getBool('autoSend') ?? false;
    });
  }

  Future<void> _saveGradeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gradeMode', mode);
    setState(() => _gradeMode = mode);
  }

  Future<void> _saveAutoSend(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoSend', value);
    setState(() => _autoSend = value);
  }

  void _toggleGuide() {
    setState(() => _showGuide = !_showGuide);

    if (!_showGuide) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _guideKey.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Settings & Help")),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          // --- Settings section ---
          Text("Settings", style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),

          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const ListTile(
                  title: Text("Grade Display"),
                  subtitle: Text("Choose how grades are shown"),
                ),
                RadioListTile<String>(
                  title: const Text("French (6a, 7b+)"),
                  value: "french",
                  groupValue: _gradeMode,
                  onChanged: (v) => _saveGradeMode(v!),
                ),
                RadioListTile<String>(
                  title: const Text("V-Grades (V2, V6)"),
                  value: "vgrade",
                  groupValue: _gradeMode,
                  onChanged: (v) => _saveGradeMode(v!),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: SwitchListTile(
              title: const Text("Auto Send to Board"),
              subtitle: const Text("Automatically send problem when swiping"),
              value: _autoSend,
              onChanged: (v) => _saveAutoSend(v),
            ),
          ),

          const SizedBox(height: 24),
          const Divider(),

          // --- App Guide section ---
          Container(
            key: _guideKey,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _toggleGuide,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                decoration: BoxDecoration(
                  color: _showGuide
                      ? theme.colorScheme.primary.withOpacity(0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("App Guide", style: theme.textTheme.titleLarge),
                    AnimatedRotation(
                      turns: _showGuide ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: _showGuide
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Column(
              children: [
                // 0. Filters
                _buildExpandableSection(
                  index: 0,
                  title: "Filters",
                  content:
                      "Filters let you quickly focus your wall log:\n\n"
                      "• **Grade Filter** — View problems of a single grade.\n"
                      "• **Search Bar** — Find problems by any word or phrase.\n"
                      "• **Benchmarks** — Show only benchmark problems.\n"
                      "• **Reset Filters** — Clear all filters and return to full view.\n\n"
                      "Active filters appear in red to remind you they’re on.",
                ),

                // 1. Colour Meaning
                _buildExpandableSection(
                  index: 1,
                  title: "Colour Meaning",
                  content:
                      "• 🟣 **Purple** — Benchmark problems used for grade consistency.\n"
                      "• 🔴 **Red** — Projects you’re still working on.\n"
                      "• 🟢 **Green** — Problems you’ve sent.\n\n"
                      "Colours make it easy to spot progress and benchmarks at a glance.",
                ),

                // 2. Create
                _buildExpandableSection(
                  index: 2,
                  title: "Create",
                  content:
                      "Use **Create Problem** to design new climbs directly on your board image.\n\n"
                      "• Tap holds to select them — tap again to turn them **off**.\n"
                      "• Once you’ve chosen your holds, press **Save** to start the confirmation process:\n"
                      "Confirm your **Start** holds (green), **Finish** hold (red), and **Feet** holds (yellow) if your board supports them.\n"
                      "• After confirming, you can review your selection and save or edit it.\n"
                      "• You can add a name, comment, grade, and star rating.\n"
                      "• Problems can be **saved as drafts** or uploaded immediately.\n"
                      "• A maximum of **10 drafts** can be stored at once.\n\n"
                      "When you tap **Send to Wall**, the holds light up on the board:\n"
                      "🟢 Start • 🔴 Finish • 🔵 Intermediate • 🟡 Feet (if enabled).",
                ),

                // 3. Problem App Bar
                _buildExpandableSection(
                  index: 3,
                  title: "Problems App Bar",
                  content:
                      "The top bar in each problem’s details page gives quick access to key actions:\n\n"
                      "• ✏️ **Edit** — Change problem details or holds.\n"
                      "• 💬 **Comments** — View or add discussion.\n"
                      "• 📤 **Send** — Display the problem on your board.\n"
                      "• 🗑️ **Delete** — Remove a problem you created.\n\n"
                      "Everything related to managing a problem lives here.",
                ),

                // 4. Drafts
                _buildExpandableSection(
                  index: 4,
                  title: "Drafts",
                  content:
                      "Drafts are problems you’ve started but not yet uploaded.\n\n"
                      "• Drafts stay local until you publish or send them.\n"
                      "• Other people are not able to see them.\n"
                      "• Great for testing ideas before uploading.\n"
                      "• You can create up to **10 drafts** at a time.",
                ),

                // 5. Sending to the Wall
                _buildExpandableSection(
                  index: 5,
                  title: "Sending to the Wall",
                  content:
                      "When you tap **Send to Board**, the problem will appear on the wall if your device is connected to the internet.\n\n"
                      "• 🟢 **Green holds** — Starting positions\n"
                      "• 🔴 **Red holds** — Finishing positions\n"
                      "• 🔵 **Blue holds** — Intermediate or optional holds\n"
                      "• 🟡 **Yellow holds** — Tracked holds (only on boards that support hold tracking)\n\n"
                      "💡 If you see a 🚫 **phone symbol** on the wall tablet, the system is restricted — tap it to remove the restriction and allow mobile devices to connect.",
                ),
              ],
            ),
            secondChild: const SizedBox.shrink(),
          ),

          const SizedBox(height: 24),
          Center(
            child: Text(
              "Version 1.0.0 • © 2025 Digital Training Boards",
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  // --- Reusable Expandable Tile ---
  Widget _buildExpandableSection({
    required int index,
    required String title,
    required String content,
  }) {
    final isExpanded = _expanded[index];
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isExpanded
          ? theme.colorScheme.primary.withOpacity(0.05)
          : theme.cardColor,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _expanded[index] = !isExpanded),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              ListTile(
                title: Text(title, style: theme.textTheme.titleMedium),
                trailing: AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 250),
                crossFadeState: isExpanded
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                firstChild: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(content, style: theme.textTheme.bodyMedium),
                ),
                secondChild: const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
