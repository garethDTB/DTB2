import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_state.dart';
import 'services/api_service.dart';
import 'wall_log_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin(AuthState auth, ApiService api) async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() => _isLoading = true);

      final ok = await auth.login(
        api,
        _usernameCtrl.text.trim(),
        _passwordCtrl.text.trim(),
      );

      setState(() => _isLoading = false);

      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login failed. Please try again.')),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const WallLogPage()),
        );
      }
    }
  }

  Future<void> _showRegisterDialog(AuthState auth, ApiService api) async {
    final regForm = GlobalKey<FormState>();
    final regUserCtrl = TextEditingController();
    final regEmailCtrl = TextEditingController();
    final regPassCtrl = TextEditingController();
    final regConfirmCtrl = TextEditingController();
    final regNameCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Register"),
          content: SingleChildScrollView(
            child: Form(
              key: regForm,
              child: Column(
                children: [
                  TextFormField(
                    controller: regUserCtrl,
                    decoration: const InputDecoration(labelText: "Username"),
                    validator: (v) =>
                        v == null || v.isEmpty ? "Enter a username" : null,
                  ),
                  TextFormField(
                    controller: regEmailCtrl,
                    decoration: const InputDecoration(labelText: "Email"),
                    validator: (v) =>
                        v == null || v.isEmpty ? "Enter an email" : null,
                  ),
                  TextFormField(
                    controller: regPassCtrl,
                    decoration: const InputDecoration(labelText: "Password"),
                    obscureText: true,
                    validator: (v) =>
                        v == null || v.isEmpty ? "Enter a password" : null,
                  ),
                  TextFormField(
                    controller: regConfirmCtrl,
                    decoration: const InputDecoration(
                      labelText: "Confirm Password",
                    ),
                    obscureText: true,
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return "Confirm your password";
                      }
                      if (v != regPassCtrl.text) {
                        return "Passwords do not match";
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: regNameCtrl,
                    decoration: const InputDecoration(labelText: "Real Name"),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              child: const Text("Register"),
              onPressed: () async {
                if (regForm.currentState?.validate() ?? false) {
                  try {
                    final ok = await auth.register(
                      api,
                      regUserCtrl.text.trim(),
                      regEmailCtrl.text.trim(),
                      regPassCtrl.text.trim(),
                      displayName: regNameCtrl.text.trim().isEmpty
                          ? null
                          : regNameCtrl.text.trim(),
                    );
                    Navigator.pop(context);
                    if (ok) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Registration successful. Please log in.",
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          e.toString().replaceAll("Exception: ", ""),
                        ),
                      ),
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showResetDialog(AuthState auth, ApiService api) async {
    final resetForm = GlobalKey<FormState>();
    final resetUserCtrl = TextEditingController();
    final resetEmailCtrl = TextEditingController();
    final resetPassCtrl = TextEditingController();
    final resetConfirmCtrl = TextEditingController();
    bool obscurePass = true;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("Reset Password"),
              content: Form(
                key: resetForm,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: resetUserCtrl,
                      decoration: const InputDecoration(labelText: "Username"),
                      validator: (v) =>
                          v == null || v.isEmpty ? "Enter your username" : null,
                    ),
                    TextFormField(
                      controller: resetEmailCtrl,
                      decoration: const InputDecoration(labelText: "Email"),
                      validator: (v) =>
                          v == null || v.isEmpty ? "Enter your email" : null,
                    ),
                    TextFormField(
                      controller: resetPassCtrl,
                      decoration: InputDecoration(
                        labelText: "New Password",
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePass
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              obscurePass = !obscurePass;
                            });
                          },
                        ),
                      ),
                      obscureText: obscurePass,
                      validator: (v) => v == null || v.isEmpty
                          ? "Enter a new password"
                          : null,
                    ),
                    TextFormField(
                      controller: resetConfirmCtrl,
                      decoration: const InputDecoration(
                        labelText: "Confirm Password",
                      ),
                      obscureText: obscurePass,
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return "Confirm your password";
                        }
                        if (v != resetPassCtrl.text) {
                          return "Passwords do not match";
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: const Text("Cancel"),
                  onPressed: () => Navigator.pop(context),
                ),
                ElevatedButton(
                  child: const Text("Reset"),
                  onPressed: () async {
                    if (resetForm.currentState?.validate() ?? false) {
                      final ok = await auth.resetPassword(
                        api,
                        resetUserCtrl.text.trim(),
                        resetEmailCtrl.text.trim(),
                        resetPassCtrl.text.trim(),
                      );
                      Navigator.pop(context);

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? "Password reset successfully"
                                : "No email was registered with this account please contact DTB",
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthState>();
    final api = context.read<ApiService>();

    return Scaffold(
      appBar: AppBar(title: const Text("Login")),
      resizeToAvoidBottomInset: true,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: "Username",
                    border: OutlineInputBorder(),
                  ),
                  autofillHints: const [AutofillHints.username],
                  validator: (value) => value == null || value.isEmpty
                      ? "Enter a username"
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordCtrl,
                  decoration: InputDecoration(
                    labelText: "Password",
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscurePassword,
                  autofillHints: const [AutofillHints.password],
                  validator: (value) => value == null || value.isEmpty
                      ? "Enter a password"
                      : null,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : () => _handleLogin(auth, api),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text("Login"),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () => _showRegisterDialog(auth, api),
                      child: const Text("Register"),
                    ),
                    TextButton(
                      onPressed: () => _showResetDialog(auth, api),
                      child: const Text("Reset Password"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
