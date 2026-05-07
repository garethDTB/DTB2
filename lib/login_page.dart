import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_state.dart';
import 'services/api_service.dart';
import 'wall_log_page.dart';
import 'reset_password_dialog.dart';

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

  static const List<String> _genderOptions = ['Male', 'Female', 'Other'];

  static const List<String> _countryOptions = [
    'United Kingdom',
    'Afghanistan',
    'Albania',
    'Algeria',
    'Andorra',
    'Angola',
    'Antigua and Barbuda',
    'Argentina',
    'Armenia',
    'Australia',
    'Austria',
    'Azerbaijan',
    'Bahamas',
    'Bahrain',
    'Bangladesh',
    'Barbados',
    'Belarus',
    'Belgium',
    'Belize',
    'Benin',
    'Bhutan',
    'Bolivia',
    'Bosnia and Herzegovina',
    'Botswana',
    'Brazil',
    'Brunei',
    'Bulgaria',
    'Burkina Faso',
    'Burundi',
    'Cabo Verde',
    'Cambodia',
    'Cameroon',
    'Canada',
    'Central African Republic',
    'Chad',
    'Chile',
    'China',
    'Colombia',
    'Comoros',
    'Congo',
    'Costa Rica',
    'Croatia',
    'Cuba',
    'Cyprus',
    'Czech Republic',
    'Democratic Republic of the Congo',
    'Denmark',
    'Djibouti',
    'Dominica',
    'Dominican Republic',
    'Ecuador',
    'Egypt',
    'El Salvador',
    'Equatorial Guinea',
    'Eritrea',
    'Estonia',
    'Eswatini',
    'Ethiopia',
    'Fiji',
    'Finland',
    'France',
    'Gabon',
    'Gambia',
    'Georgia',
    'Germany',
    'Ghana',
    'Greece',
    'Grenada',
    'Guatemala',
    'Guinea',
    'Guinea-Bissau',
    'Guyana',
    'Haiti',
    'Holy See',
    'Honduras',
    'Hungary',
    'Iceland',
    'India',
    'Indonesia',
    'Iran',
    'Iraq',
    'Ireland',
    'Israel',
    'Italy',
    'Ivory Coast',
    'Jamaica',
    'Japan',
    'Jordan',
    'Kazakhstan',
    'Kenya',
    'Kiribati',
    'Kuwait',
    'Kyrgyzstan',
    'Laos',
    'Latvia',
    'Lebanon',
    'Lesotho',
    'Liberia',
    'Libya',
    'Liechtenstein',
    'Lithuania',
    'Luxembourg',
    'Madagascar',
    'Malawi',
    'Malaysia',
    'Maldives',
    'Mali',
    'Malta',
    'Marshall Islands',
    'Mauritania',
    'Mauritius',
    'Mexico',
    'Micronesia',
    'Moldova',
    'Monaco',
    'Mongolia',
    'Montenegro',
    'Morocco',
    'Mozambique',
    'Myanmar',
    'Namibia',
    'Nauru',
    'Nepal',
    'Netherlands',
    'New Zealand',
    'Nicaragua',
    'Niger',
    'Nigeria',
    'North Korea',
    'North Macedonia',
    'Norway',
    'Oman',
    'Pakistan',
    'Palau',
    'Palestine State',
    'Panama',
    'Papua New Guinea',
    'Paraguay',
    'Peru',
    'Philippines',
    'Poland',
    'Portugal',
    'Qatar',
    'Romania',
    'Russia',
    'Rwanda',
    'Saint Kitts and Nevis',
    'Saint Lucia',
    'Saint Vincent and the Grenadines',
    'Samoa',
    'San Marino',
    'Sao Tome and Principe',
    'Saudi Arabia',
    'Senegal',
    'Serbia',
    'Seychelles',
    'Sierra Leone',
    'Singapore',
    'Slovakia',
    'Slovenia',
    'Solomon Islands',
    'Somalia',
    'South Africa',
    'South Korea',
    'South Sudan',
    'Spain',
    'Sri Lanka',
    'Sudan',
    'Suriname',
    'Sweden',
    'Switzerland',
    'Syria',
    'Tajikistan',
    'Tanzania',
    'Thailand',
    'Timor-Leste',
    'Togo',
    'Tonga',
    'Trinidad and Tobago',
    'Tunisia',
    'Turkey',
    'Turkmenistan',
    'Tuvalu',
    'Uganda',
    'Ukraine',
    'United Arab Emirates',
    'United States',
    'Uruguay',
    'Uzbekistan',
    'Vanuatu',
    'Venezuela',
    'Vietnam',
    'Yemen',
    'Zambia',
    'Zimbabwe',
  ];

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

  DateTime? _parseDob(String value) {
    try {
      final parts = value.split('-');
      if (parts.length != 3) return null;

      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final day = int.parse(parts[2]);

      final date = DateTime(year, month, day);

      if (date.year == year && date.month == month && date.day == day) {
        return date;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _showRegisterDialog(AuthState auth, ApiService api) async {
    final regForm = GlobalKey<FormState>();
    final regUserCtrl = TextEditingController();
    final regEmailCtrl = TextEditingController();
    final regPassCtrl = TextEditingController();
    final regConfirmCtrl = TextEditingController();
    final regNameCtrl = TextEditingController();
    final regTownCtrl = TextEditingController();
    final regBioCtrl = TextEditingController();
    final regDobCtrl = TextEditingController();

    final userFocus = FocusNode();
    final emailFocus = FocusNode();
    final passFocus = FocusNode();
    final confirmFocus = FocusNode();
    final nameFocus = FocusNode();

    String? selectedGender;
    String? selectedCountry;
    bool shareWithFriends = true;
    bool blackList = false;
    bool obscurePass = true;
    bool obscureConfirm = true;
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              title: const Text("Register"),
              content: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(dialogContext).viewInsets.bottom,
                ),
                child: SizedBox(
                  width: double.maxFinite,
                  child: Form(
                    key: regForm,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: regUserCtrl,
                          focusNode: userFocus,
                          decoration: const InputDecoration(
                            labelText: "Username",
                          ),
                          textInputAction: TextInputAction.next,
                          validator: (v) => v == null || v.trim().isEmpty
                              ? "Enter a username"
                              : null,
                          onFieldSubmitted: (_) => emailFocus.requestFocus(),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: regEmailCtrl,
                          focusNode: emailFocus,
                          decoration: const InputDecoration(labelText: "Email"),
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          validator: (v) {
                            final value = v?.trim() ?? '';
                            if (value.isEmpty) return "Enter an email";

                            final emailRegex = RegExp(
                              r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                            );
                            if (!emailRegex.hasMatch(value)) {
                              return "Enter a valid email";
                            }
                            return null;
                          },
                          onFieldSubmitted: (_) => passFocus.requestFocus(),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: regPassCtrl,
                          focusNode: passFocus,
                          decoration: InputDecoration(
                            labelText: "Password",
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscurePass
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                setDialogState(() {
                                  obscurePass = !obscurePass;
                                });
                              },
                            ),
                          ),
                          obscureText: obscurePass,
                          textInputAction: TextInputAction.next,
                          validator: (v) => v == null || v.isEmpty
                              ? "Enter a password"
                              : null,
                          onFieldSubmitted: (_) => confirmFocus.requestFocus(),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: regConfirmCtrl,
                          focusNode: confirmFocus,
                          decoration: InputDecoration(
                            labelText: "Confirm Password",
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscureConfirm
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                setDialogState(() {
                                  obscureConfirm = !obscureConfirm;
                                });
                              },
                            ),
                          ),
                          obscureText: obscureConfirm,
                          textInputAction: TextInputAction.next,
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return "Confirm your password";
                            }
                            if (v != regPassCtrl.text) {
                              return "Passwords do not match";
                            }
                            return null;
                          },
                          onFieldSubmitted: (_) => nameFocus.requestFocus(),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: regNameCtrl,
                          focusNode: nameFocus,
                          decoration: const InputDecoration(
                            labelText: "Real Name",
                          ),
                          textInputAction: TextInputAction.done,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!(regForm.currentState?.validate() ?? false)) {
                            if (regUserCtrl.text.trim().isEmpty) {
                              userFocus.requestFocus();
                            } else if (regEmailCtrl.text.trim().isEmpty) {
                              emailFocus.requestFocus();
                            } else if (regPassCtrl.text.isEmpty) {
                              passFocus.requestFocus();
                            } else if (regConfirmCtrl.text !=
                                regPassCtrl.text) {
                              confirmFocus.requestFocus();
                            } else {
                              nameFocus.requestFocus();
                            }
                            return;
                          }

                          setDialogState(() {
                            isSubmitting = true;
                          });

                          try {
                            final ok = await auth.register(
                              api,
                              regUserCtrl.text.trim(),
                              regEmailCtrl.text.trim(),
                              regPassCtrl.text.trim(),
                              displayName: regNameCtrl.text.trim().isEmpty
                                  ? null
                                  : regNameCtrl.text.trim(),
                              town: regTownCtrl.text.trim(),
                              country: selectedCountry,
                              gender: selectedGender,
                              dob: regDobCtrl.text.trim(),
                              bio: regBioCtrl.text.trim(),
                              shareWithFriends: shareWithFriends,
                              blackList: blackList,
                            );

                            if (!mounted) return;
                            Navigator.pop(dialogContext);

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
                            if (!mounted) return;
                            Navigator.pop(dialogContext);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  e.toString().replaceAll("Exception: ", ""),
                                ),
                              ),
                            );
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("Register"),
                ),
              ],
            );
          },
        );
      },
    );

    // userFocus.dispose();
    // emailFocus.dispose();
    // passFocus.dispose();
    // confirmFocus.dispose();
    // nameFocus.dispose();
    // regUserCtrl.dispose();
    // regEmailCtrl.dispose();
    // regPassCtrl.dispose();
    // regConfirmCtrl.dispose();
    // regNameCtrl.dispose();
    // regTownCtrl.dispose();
    // regBioCtrl.dispose();
    // regDobCtrl.dispose();
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
                      onPressed: () async {
                        final ok = await showResetPasswordDialog(
                          context,
                          auth,
                          api,
                        );

                        if (!mounted || ok == null) return;

                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;

                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? "Password reset successfully"
                                    : "No email was registered with this account please contact DTB",
                              ),
                            ),
                          );
                        });
                      },
                      child: const Text("Reset Password"),
                    ),
                    TextButton(
                      onPressed: () => _showRegisterDialog(auth, api),
                      child: const Text("Register"),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TextButton.icon(
                  icon: const Icon(Icons.person_outline),
                  label: const Text("Continue as Guest"),
                  onPressed: () async {
                    await auth.setGuestMode(true);
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const WallLogPage()),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
