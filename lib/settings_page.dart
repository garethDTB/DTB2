import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dtb2/services/api_service.dart';
import 'package:provider/provider.dart';
import 'auth_state.dart';
import 'edit_profile_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _gradeMode = "french";
  bool _autoSend = false;

  bool _showGuide = false;
  final List<bool> _expanded = List.filled(7, false);
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
      final guideContext = _guideKey.currentContext;
      if (guideContext != null) {
        Scrollable.ensureVisible(
          guideContext,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _openEditProfile(BuildContext context) async {
    final auth = context.read<AuthState>();
    final api = ApiService(
      "https://dtb2-func-hkhagfe5gkfaa0g9.ukwest-01.azurewebsites.net/api",
    );

    if (auth.isGuest) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Guest mode: please log in to edit your profile."),
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConfirmPasswordDialog(
        onConfirm: (pw) => auth.confirmPassword(api, pw),
      ),
    );

    if (ok == true && context.mounted) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => EditProfilePage()));
    }
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Account"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Please confirm your username and password to permanently delete your account. "
              "This action cannot be undone.",
            ),
            const SizedBox(height: 16),
            TextField(
              controller: usernameController,
              decoration: const InputDecoration(labelText: "Username"),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: "Password"),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final username = usernameController.text.trim();
      final password = passwordController.text.trim();

      if (username.isEmpty || password.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enter both fields.")),
        );
        return;
      }

      try {
        final api = ApiService(
          "https://dtb2-func-hkhagfe5gkfaa0g9.ukwest-01.azurewebsites.net/api",
        );

        final success = await api.deleteAccount(username, password);

        if (success) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.clear();

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Account deleted successfully.")),
            );
            Navigator.of(context).pop();
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Deletion failed. Check credentials."),
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
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
              title: const Text("Auto Cast to Board"),
              subtitle: const Text("Automatically send problem when swiping"),
              value: _autoSend,
              onChanged: (v) => _saveAutoSend(v),
            ),
          ),

          const SizedBox(height: 24),
          const Divider(),

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
                _buildExpandableSection(
                  index: 0,
                  title: "Filters",
                  content:
                      "The filters and search bar help you quickly find the problems you want:\n\n"
                      "• 🧩 Grade Filter — Use the dropdown to show only problems of a single grade (e.g. just 6c or 7a+).\n"
                      "• 🔎 Search Bar — Type any word or phrase to search by name, setter, grade, or comment.\n"
                      "• ❤️ Liked — Shows problems you’ve liked.\n"
                      "• ❌ Attempted (not ticked) — Problems you’ve tried but not yet completed.\n"
                      "• ✅ Ticked — Problems you’ve completed.\n"
                      "• ⚪ Not ticked — Problems you haven’t attempted or logged yet.\n"
                      "• ⭐ Benchmarks — Shows only benchmark problems.\n\n"
                      "Tap an icon to toggle its filter — active ones highlight in colour.\n"
                      "Use the 🔄 Reset button (which turns red when filters are active) to clear everything and return to the full list.",
                ),
                _buildExpandableSection(
                  index: 1,
                  title: "Colour Meaning",
                  content:
                      "• 🟢 Green — A problem you’ve completed in today’s session.\n"
                      "• 🟣 Purple — A problem you’ve completed in a previous session.\n"
                      "• 🔴 Red — A problem you’ve attempted but not ticked yet.\n"
                      "• ⚪ White — A problem you’ve not attempted or ticked yet.\n\n"
                      "Colours give you a quick visual snapshot of your progress on the wall — what’s new, what’s done, and what’s still waiting.",
                ),
                _buildExpandableSection(
                  index: 2,
                  title: "Create",
                  content:
                      "Use Create Problem to design new climbs directly on your board image.\n\n"
                      "• Tap holds to select them — tap again to turn them off.\n"
                      "• Once you’ve chosen your holds, press Save to start the confirmation process.\n"
                      "• Confirm your Start holds (green), Finish hold (red), and Feet holds (yellow) if your board supports tracked feet.\n"
                      "• After confirming, you can review your selection and save or edit it.\n"
                      "• You can add a name, comment, grade, and star rating.\n"
                      "• Problems can be saved as drafts or uploaded immediately.\n"
                      "• A maximum of 10 drafts can be stored at once.\n\n"
                      "When you tap Cast to Wall, the holds light up on the board:\n"
                      "🟢 Start • 🔴 Finish • 🔵 Intermediate • 🟡 Feet (if enabled).",
                ),
                _buildExpandableSection(
                  index: 3,
                  title: "Editing",
                  content:
                      "If a problem was created by you, you can edit it directly from the details page.\n\n"
                      "• Tap the ✏️ pencil icon to enter edit mode.\n"
                      "• You can change the name, comments, and grade.\n"
                      "• You can also reselect or adjust your start and finish holds.\n"
                      "• Once updated, just save to apply your changes.\n\n"
                      "Other users’ problems cannot be edited, but you can copy or recreate them using Create Problem.",
                ),
                _buildExpandableSection(
                  index: 4,
                  title: "Problems App Bar",
                  content:
                      "The buttons in the details view let you record your session and interact with the problem quickly:\n\n"
                      "• ❤️ Like — Show appreciation for a problem.\n"
                      "• ❌ Attempt — Log that you’ve tried the problem but haven’t sent it yet.\n"
                      "• ✅ Tick — Mark the problem as completed in this session.\n"
                      "• ⚡ Flash — Record that you sent it on your first attempt.\n"
                      "• 💡 Cast to Board — Push the problem to your connected training board.\n"
                      "• 🔄 Mirror — Toggle a mirrored version of the problem on the opposite side.\n"
                      "• 📺 What’s On — See what’s currently loaded on the board.\n"
                      "• 💬 Comments — View or add feedback from other climbers.\n\n"
                      "Swipe sideways if you don’t see all the buttons — the row scrolls horizontally.",
                ),
                _buildExpandableSection(
                  index: 5,
                  title: "Drafts",
                  content:
                      "Drafts are unfinished problems you’ve started creating but haven’t yet sent.\n\n"
                      "• Drafts stay local until you publish or send them.\n"
                      "• Other people are not able to see them.\n"
                      "• Great for testing ideas before uploading.\n\n"
                      "Use drafts to experiment or build multiple climbs before finalising your set.\n"
                      "You can create up to 10 drafts at a time.",
                ),
                _buildExpandableSection(
                  index: 6,
                  title: "Casting to the Wall",
                  content:
                      "When you tap Cast to Board, the problem will appear on the wall if your device is connected through the internet.\n\n"
                      "• 🟢 Green holds — Starting positions\n"
                      "• 🔴 Red holds — Finishing positions\n"
                      "• 🔵 Blue holds — Intermediate or optional holds\n"
                      "• 🟡 Yellow holds — Tracked holds (only on boards that support hold tracking)\n\n"
                      "Make sure your phone or tablet is connected to the internet before casting.\n"
                      "If you see a 🚫 phone symbol on the wall tablet, it means the system is restricted — tap it to remove the restriction and allow mobile devices to connect.",
                ),
              ],
            ),
            secondChild: const SizedBox.shrink(),
          ),

          const SizedBox(height: 16),

          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              leading: const Icon(Icons.person),
              title: const Text("Profile"),
              subtitle: const Text(
                "Edit your profile details (password required)",
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openEditProfile(context),
            ),
          ),

          const SizedBox(height: 24),

          Center(
            child: Text(
              "Version 1.0.0 • © 2025 Digital Training Boards",
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ),

          const SizedBox(height: 24),

          Card(
            color: Colors.red.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text(
                "Delete Account",
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text(
                "Permanently remove your account and all associated data.",
                style: TextStyle(color: Colors.red),
              ),
              onTap: () => _confirmDeleteAccount(context),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

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

class _ConfirmPasswordDialog extends StatefulWidget {
  final Future<bool> Function(String password) onConfirm;

  const _ConfirmPasswordDialog({required this.onConfirm});

  @override
  State<_ConfirmPasswordDialog> createState() => _ConfirmPasswordDialogState();
}

class _ConfirmPasswordDialogState extends State<_ConfirmPasswordDialog> {
  final TextEditingController _pw = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final ok = await widget.onConfirm(_pw.text);

    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = "Wrong password.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Confirm password"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Enter your password to edit profile details."),
          const SizedBox(height: 12),
          TextField(
            controller: _pw,
            obscureText: _obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: "Password",
              errorText: _error,
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _busy ? null : _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text("Continue"),
        ),
      ],
    );
  }
}
