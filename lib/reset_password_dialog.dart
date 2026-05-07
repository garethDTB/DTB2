import 'package:flutter/material.dart';
import 'auth_state.dart';
import 'services/api_service.dart';

Future<bool?> showResetPasswordDialog(
  BuildContext context,
  AuthState auth,
  ApiService api, {
  String? initialUsername,
  String? initialEmail,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ResetPasswordDialog(
      auth: auth,
      api: api,
      initialUsername: initialUsername,
      initialEmail: initialEmail,
    ),
  );
}

class ResetPasswordDialog extends StatefulWidget {
  final AuthState auth;
  final ApiService api;
  final String? initialUsername;
  final String? initialEmail;

  const ResetPasswordDialog({
    super.key,
    required this.auth,
    required this.api,
    this.initialUsername,
    this.initialEmail,
  });

  @override
  State<ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<ResetPasswordDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _userCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _confirmCtrl;

  final FocusNode _userFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passFocus = FocusNode();
  final FocusNode _confirmFocus = FocusNode();

  bool _obscurePass = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _userCtrl = TextEditingController(text: widget.initialUsername ?? '');
    _emailCtrl = TextEditingController(text: widget.initialEmail ?? '');
    _passCtrl = TextEditingController();
    _confirmCtrl = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (_userCtrl.text.trim().isEmpty) {
        _userFocus.requestFocus();
      } else if (_emailCtrl.text.trim().isEmpty) {
        _emailFocus.requestFocus();
      } else if (_passCtrl.text.trim().isEmpty) {
        _passFocus.requestFocus();
      } else {
        _confirmFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();

    _userFocus.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    _confirmFocus.dispose();

    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isSubmitting = true;
    });

    try {
      final ok = await widget.auth.resetPassword(
        widget.api,
        _userCtrl.text.trim(),
        _emailCtrl.text.trim(),
        _passCtrl.text.trim(),
      );

      if (!mounted) return;

      Navigator.of(context).pop(ok);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSubmitting = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Password reset failed: $e')));
    }
  }

  String? _validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter your username';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your email';

    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(v)) {
      return 'Enter a valid email';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Enter a new password';
    if (v.length < 4) return 'Password must be at least 4 characters';
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Confirm your password';
    if (v != _passCtrl.text) return 'Passwords do not match';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Reset Password',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _userCtrl,
                            focusNode: _userFocus,
                            enabled: !_isSubmitting,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              border: OutlineInputBorder(),
                            ),
                            validator: _validateUsername,
                            onFieldSubmitted: (_) {
                              FocusScope.of(context).requestFocus(_emailFocus);
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _emailCtrl,
                            focusNode: _emailFocus,
                            enabled: !_isSubmitting,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              border: OutlineInputBorder(),
                            ),
                            validator: _validateEmail,
                            onFieldSubmitted: (_) {
                              FocusScope.of(context).requestFocus(_passFocus);
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passCtrl,
                            focusNode: _passFocus,
                            enabled: !_isSubmitting,
                            obscureText: _obscurePass,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'New Password',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                onPressed: _isSubmitting
                                    ? null
                                    : () {
                                        setState(() {
                                          _obscurePass = !_obscurePass;
                                        });
                                      },
                                icon: Icon(
                                  _obscurePass
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                              ),
                            ),
                            validator: _validatePassword,
                            onChanged: (_) {
                              if (_confirmCtrl.text.isNotEmpty) {
                                _formKey.currentState?.validate();
                              }
                            },
                            onFieldSubmitted: (_) {
                              FocusScope.of(
                                context,
                              ).requestFocus(_confirmFocus);
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _confirmCtrl,
                            focusNode: _confirmFocus,
                            enabled: !_isSubmitting,
                            obscureText: _obscurePass,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: 'Confirm Password',
                              border: OutlineInputBorder(),
                            ),
                            validator: _validateConfirmPassword,
                            onFieldSubmitted: (_) => _submit(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _isSubmitting
                            ? null
                            : () => Navigator.of(context).pop(null),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Reset'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
