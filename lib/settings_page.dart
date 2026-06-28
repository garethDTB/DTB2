import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dtb2/services/api_service.dart';
import 'package:provider/provider.dart';
import 'auth_state.dart';
import 'edit_profile_page.dart';
import 'services/ble_cast_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _gradeMode = "french";
  bool _autoSend = false;
  String _castMethod = "websocket";
  String _bluetoothMode = "auto";

  bool _showGuide = false;
  bool _showCastingSettings = false;

  final List<bool> _expanded = List.filled(9, false);
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
      _castMethod = prefs.getString('castMethod') ?? "websocket";
      _bluetoothMode = prefs.getString('bluetoothMode') ?? "auto";
    });
  }

  Future<void> _connectBluetoothNow() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Connecting to board by Bluetooth…"),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      await BleCastService().sendMessage({
        "type": "test",
        "problem": "test",
      }, boardName: "DTB Board");

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Bluetooth connected"),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Bluetooth connection failed: $e"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _saveCastMethod(String method) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('castMethod', method);

    final bluetoothMode = prefs.getString('bluetoothMode') ?? "auto";

    setState(() => _castMethod = method);

    if (method == "bluetooth" && bluetoothMode == "exclusive") {
      await _connectBluetoothNow();
    }
  }

  Future<void> _saveBluetoothMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bluetoothMode', mode);

    setState(() => _bluetoothMode = mode);

    if (_castMethod == "bluetooth" && mode == "exclusive") {
      await _connectBluetoothNow();
    }
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
            color: _showCastingSettings
                ? theme.colorScheme.primary.withOpacity(0.05)
                : theme.cardColor,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cast),
                  title: const Text("Casting"),
                  subtitle: Text(
                    _castMethod == "bluetooth"
                        ? "Bluetooth • ${_bluetoothMode == "shared"
                              ? "Shared 5s disconnect"
                              : _bluetoothMode == "auto"
                              ? "Auto 30s disconnect"
                              : "Exclusive"}"
                        : "Cloud Connection",
                  ),
                  trailing: AnimatedRotation(
                    turns: _showCastingSettings ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  onTap: () {
                    setState(
                      () => _showCastingSettings = !_showCastingSettings,
                    );
                  },
                ),

                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 250),
                  crossFadeState: _showCastingSettings
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: Column(
                    children: [
                      RadioListTile<String>(
                        title: const Text("Cloud Connection"),
                        subtitle: const Text(
                          "Use the normal online connection to send problems to the board.",
                        ),
                        value: "websocket",
                        groupValue: _castMethod,
                        onChanged: (v) => _saveCastMethod(v!),
                      ),
                      RadioListTile<String>(
                        title: const Text("Bluetooth nearby"),
                        subtitle: const Text(
                          "Send directly to a nearby board without using the Cloud Connection.",
                        ),
                        value: "bluetooth",
                        groupValue: _castMethod,
                        onChanged: (v) => _saveCastMethod(v!),
                      ),

                      if (_castMethod == "bluetooth") ...[
                        const Divider(height: 8),

                        RadioListTile<String>(
                          title: const Text("Shared"),
                          subtitle: const Text(
                            "Disconnect 5 seconds after each cast so other users can connect.",
                          ),
                          value: "shared",
                          groupValue: _bluetoothMode,
                          onChanged: (v) => _saveBluetoothMode(v!),
                        ),

                        RadioListTile<String>(
                          title: const Text("Auto Disconnect"),
                          subtitle: const Text(
                            "Disconnect 30 seconds after the last cast.",
                          ),
                          value: "auto",
                          groupValue: _bluetoothMode,
                          onChanged: (v) => _saveBluetoothMode(v!),
                        ),

                        RadioListTile<String>(
                          title: const Text("Exclusive"),
                          subtitle: const Text(
                            "Stay connected for fastest repeated casting.",
                          ),
                          value: "exclusive",
                          groupValue: _bluetoothMode,
                          onChanged: (v) => _saveBluetoothMode(v!),
                        ),
                      ],

                      const Divider(height: 8),

                      SwitchListTile(
                        title: const Text("Auto Cast to Board"),
                        subtitle: const Text(
                          "Automatically send the problem when swiping through details.",
                        ),
                        value: _autoSend,
                        onChanged: (v) => _saveAutoSend(v),
                      ),
                    ],
                  ),
                  secondChild: const SizedBox.shrink(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Divider(),

          Card(
            key: _guideKey,
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            color: _showGuide
                ? theme.colorScheme.primary.withOpacity(0.05)
                : theme.cardColor,
            child: ListTile(
              leading: const Icon(Icons.menu_book),
              title: const Text("App Guide"),
              subtitle: const Text(
                "How to use filters, lists, casting and more",
              ),
              trailing: AnimatedRotation(
                turns: _showGuide ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
              onTap: _toggleGuide,
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
                      "• The filters and search tools help you quickly find the problems you want:\n\n"
                      "• 🔎 Search — Search by problem name, setter, grade or comment.\n"
                      "• 📏 Grade Range — Show problems between a minimum and maximum grade.\n"
                      "• ✋ Hold Filter — Tap holds directly on the board image to find problems using those holds.\n"
                      "• 🦶 Foot Filter — Filter by foot options where supported by the wall.\n"
                      "• ❤️ Liked — Problems you've liked.\n"
                      "• ❌ Attempted — Problems you've tried but not yet completed.\n"
                      "• ✅ Ticked — Problems you've completed.\n"
                      "• ⚪ Unticked — Problems you haven't completed yet.\n"
                      "• ⭐ Benchmarks — Show benchmark problems only.\n\n"
                      "• Sorting options allow you to organise problems by:\n"
                      "• Grade\n"
                      "• Most Recent\n"
                      "• Oldest\n"
                      "• Most Ascents\n"
                      "• Least Ascents\n"
                      "• Most Likes\n\n"
                      "• Active filters are highlighted in colour. Use the 🔄 Reset button to clear all filters and return to the full problem list.",
                ),
                _buildExpandableSection(
                  index: 1,
                  title: "Colour Meaning",
                  content:
                      "• 🟢 Green — A problem you’ve completed in today’s session.\n"
                      "• 🟣 Purple — A problem you’ve completed in a previous session.\n"
                      "• 🔴 Red — A problem you’ve attempted but not ticked yet.\n"
                      "• ⚪ White — A problem you’ve not attempted or ticked yet.\n\n"
                      "• Colours give you a quick visual snapshot of your progress on the wall — what’s new, what’s done, and what’s still waiting.",
                ),
                _buildExpandableSection(
                  index: 2,
                  title: "Create",
                  content:
                      "• Use Create Problem to design new climbs directly on your board image.\n\n"
                      "• Tap holds to select them — tap again to turn them off.\n"
                      "• Once you’ve chosen your holds, press Save to start the confirmation process.\n"
                      "• Confirm your Start holds (green), Finish hold (red), and Feet holds (yellow) if your board supports tracked feet.\n"
                      "• After confirming, you can review your selection and save or edit it.\n"
                      "• You can add a name, comment, grade, and star rating.\n"
                      "• Problems can be saved as drafts or uploaded immediately.\n"
                      "• A maximum of 10 drafts can be stored at once.\n\n"
                      "• When you tap Cast to Wall, the holds light up on the board:\n"
                      "• 🟢 Start • 🔴 Finish • 🔵 Intermediate • 🟡 Feet (if enabled).",
                ),
                _buildExpandableSection(
                  index: 3,
                  title: "Editing",
                  content:
                      "• Problems can be edited from the details page.\n\n"
                      "• Tap the ✏️ pencil icon to enter edit mode.\n"
                      "• Update the name, comment, grade, stars or hold selection.\n"
                      "• Adjust start, finish and foot holds where supported.\n"
                      "• Save your changes to update the problem.\n\n"
                      "• Problems can normally be edited by their creator. Wall superusers may also be able to edit problems. "
                      "• When a problem is updated, the original setter is retained.",
                ),
                _buildExpandableSection(
                  index: 4,
                  title: "Problems App Bar",
                  content:
                      "• The buttons in the details view let you record your session and interact with the problem quickly:\n\n"
                      "• ❤️ Like — Show appreciation for a problem.\n"
                      "• ❌ Attempt — Log that you’ve tried the problem but haven’t sent it yet.\n"
                      "• ✅ Tick — Mark the problem as completed in this session.\n"
                      "• ⚡ Flash — Record that you sent it on your first attempt.\n"
                      "• 💡 Show the problem on the board — lights up the holds on the training board.\n"
                      "• 🔄 Mirror — Toggle a mirrored version of the problem on the opposite side.\n"
                      "• 📺 What’s On — See what’s currently loaded on the board.\n"
                      "• 💬 Comments — View or add feedback from other climbers.\n\n"
                      "• Swipe sideways if you don’t see all the buttons — the row scrolls horizontally.",
                ),
                _buildExpandableSection(
                  index: 5,
                  title: "Drafts",
                  content:
                      "• Drafts are unfinished problems you’ve started creating but haven’t yet sent.\n\n"
                      "• Drafts stay local until you publish or send them.\n"
                      "• Other people are not able to see them.\n"
                      "• Great for testing ideas before uploading.\n\n"
                      "• Use drafts to experiment or build multiple climbs before finalising your set.\n"
                      "• You can create up to 10 drafts at a time.",
                ),
                _buildExpandableSection(
                  index: 6,
                  title: "Casting to the Wall",
                  content:
                      "• Casting sends the selected problem to the training board so the holds light up.\n\n"
                      "• You can choose the casting method in Settings:\n\n"
                      "• Cloud Connection  — uses the normal online connection.\n"
                      "• Bluetooth nearby — sends directly to a nearby board without needing the Cloud Connection.\n\n"
                      "• Bluetooth has three connection modes:\n"
                      "• Shared — disconnects after 5 seconds so other climbers can connect.\n"
                      "• Auto Disconnect — disconnects after 30 seconds after the last cast.\n"
                      "• Exclusive — stays connected for faster repeated casting.\n\n"
                      "• Hold colours on the board:\n"
                      "• 🟢 Green — Start holds\n"
                      "• 🔴 Red — Finish holds\n"
                      "• 🔵 Blue — Intermediate holds\n"
                      "• 🟡 Yellow — Feet or tracked holds where supported\n\n"
                      "• Auto Cast can also be switched on, which sends the problem automatically when swiping between problems.",
                ),
                _buildExpandableSection(
                  index: 7,
                  title: "Lists",
                  content:
                      "• Lists allow you to save and organise groups of problems.\n\n"
                      "• Save your current filtered results as a list.\n"
                      "• Create personal circuits and training sessions.\n"
                      "• Browse public lists shared by other climbers.\n"
                      "• Copy public lists to your own account.\n"
                      "• Edit, rename and delete your own lists.\n"
                      "• Use lists to track projects, circuits or training goals.\n\n"
                      "• Public lists can be copied to your account and customised without affecting the original list.",
                ),
                _buildExpandableSection(
                  index: 8,
                  title: "Beta Videos",
                  content:
                      "Beta Videos allow climbers to share and discover videos showing how problems have been climbed.\n\n"
                      "• Watch beta from other climbers.\n"
                      "• Share useful beta with the community.\n"
                      "• Discover alternative sequences and methods.\n"
                      "• Help other climbers unlock difficult moves.\n\n"
                      "Availability of videos will vary between problems and walls.",
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
              "Version 2.0.0 • © 2026 Digital Training Boards",
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
