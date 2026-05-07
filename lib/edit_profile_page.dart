import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_state.dart';
import 'package:dtb2/services/api_service.dart';
import 'reset_password_dialog.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();

  static const List<String> _genderOptions = ['Male', 'Female', 'Other'];

  static const List<String> _countryOptions = [
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
    'United Kingdom',
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

  late final TextEditingController _usernameCtrl;
  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _townCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _dobCtrl;

  String? _selectedGender;
  String? _selectedCountry;

  bool _shareWithFriends = false;
  bool _isSaving = false;
  bool _changed = false;
  bool _blackList = false;

  late final ApiService _api;

  @override
  void initState() {
    super.initState();

    final auth = context.read<AuthState>();

    // _api = ApiService(
    //   "https://dtb2-func-hkhagfe5gkfaa0g9.ukwest-01.azurewebsites.net/api",
    // );

    _api = context.read<ApiService>();

    _usernameCtrl = TextEditingController(text: auth.username ?? '');
    _displayNameCtrl = TextEditingController(
      text: auth.displayName ?? auth.username ?? '',
    );
    _emailCtrl = TextEditingController(text: auth.email ?? '');
    _townCtrl = TextEditingController(text: auth.town ?? '');
    _bioCtrl = TextEditingController(text: auth.bio ?? '');
    _dobCtrl = TextEditingController(text: auth.dob ?? '');

    _selectedGender = _genderOptions.contains(auth.gender) ? auth.gender : null;

    _selectedCountry = _countryOptions.contains(auth.country)
        ? auth.country
        : null;

    _shareWithFriends = auth.shareWithFriends;
    _blackList = auth.blackList;

    _displayNameCtrl.addListener(_markChanged);
    _emailCtrl.addListener(_markChanged);
    _townCtrl.addListener(_markChanged);
    _bioCtrl.addListener(_markChanged);
    _dobCtrl.addListener(_markChanged);
  }

  void _markChanged() {
    if (!_changed) {
      setState(() {
        _changed = true;
      });
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();

    _displayNameCtrl.removeListener(_markChanged);
    _displayNameCtrl.dispose();

    _emailCtrl.removeListener(_markChanged);
    _emailCtrl.dispose();

    _townCtrl.removeListener(_markChanged);
    _townCtrl.dispose();

    _bioCtrl.removeListener(_markChanged);
    _bioCtrl.dispose();

    _dobCtrl.removeListener(_markChanged);
    _dobCtrl.dispose();

    super.dispose();
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

  Future<void> _pickDob() async {
    final initialDate = _parseDob(_dobCtrl.text.trim()) ?? DateTime(1990, 1, 1);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900, 1, 1),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      final formatted = _formatDate(picked);
      if (_dobCtrl.text != formatted) {
        setState(() {
          _dobCtrl.text = formatted;
          _changed = true;
        });
      }
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final auth = context.read<AuthState>();

      await _api.updateUserProfile(
        username: auth.username!,
        email: _emailCtrl.text.trim(),
        displayName: _displayNameCtrl.text.trim(),
        town: _townCtrl.text.trim(),
        country: _selectedCountry ?? '',
        gender: _selectedGender ?? '',
        dob: _dobCtrl.text.trim(),
        bio: _bioCtrl.text.trim(),
        shareWithFriends: _shareWithFriends,
        blackList: _blackList,
      );

      await auth.updateLocalProfile(
        email: _emailCtrl.text.trim(),
        displayName: _displayNameCtrl.text.trim(),
        town: _townCtrl.text.trim(),
        country: _selectedCountry ?? '',
        gender: _selectedGender ?? '',
        dob: _dobCtrl.text.trim(),
        bio: _bioCtrl.text.trim(),
        shareWithFriends: _shareWithFriends,
        blackList: _blackList,
      );

      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _changed = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save profile: $e')));
    }
  }

  Future<bool> _confirmDiscardChanges() async {
    if (!_changed) return true;

    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'You have unsaved profile changes. Do you want to discard them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    return discard ?? false;
  }

  void _openResetPasswordDialog() {
    final auth = context.read<AuthState>();

    showResetPasswordDialog(
      context,
      auth,
      _api,
      initialUsername: auth.username,
      initialEmail: auth.email,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final allow = await _confirmDiscardChanges();
        if (allow && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit Profile'),
          actions: [
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Profile Details',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _usernameCtrl,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            helperText: 'Username cannot currently be changed',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _displayNameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Display Name',
                            border: OutlineInputBorder(),
                          ),
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            final v = value?.trim() ?? '';
                            if (v.isEmpty) {
                              return 'Please enter a display name';
                            }
                            if (v.length > 40) {
                              return 'Display name must be 40 characters or less';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _emailCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            final v = value?.trim() ?? '';
                            if (v.isEmpty) {
                              return 'Please enter an email';
                            }

                            final emailRegex = RegExp(
                              r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                            );

                            if (!emailRegex.hasMatch(v)) {
                              return 'Please enter a valid email';
                            }

                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _townCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Town',
                            border: OutlineInputBorder(),
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 16),

                        DropdownButtonFormField<String>(
                          value: _selectedCountry,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Country',
                            border: OutlineInputBorder(),
                          ),
                          items: _countryOptions
                              .map(
                                (country) => DropdownMenuItem(
                                  value: country,
                                  child: Text(
                                    country,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedCountry = value;
                              _changed = true;
                            });
                          },
                        ),
                        const SizedBox(height: 16),

                        DropdownButtonFormField<String>(
                          value: _selectedGender,
                          decoration: const InputDecoration(
                            labelText: 'Gender',
                            border: OutlineInputBorder(),
                          ),
                          items: _genderOptions
                              .map(
                                (gender) => DropdownMenuItem(
                                  value: gender,
                                  child: Text(gender),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedGender = value;
                              _changed = true;
                            });
                          },
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _dobCtrl,
                          readOnly: true,
                          onTap: _pickDob,
                          decoration: InputDecoration(
                            labelText: 'Date of Birth',
                            hintText: 'YYYY-MM-DD',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              onPressed: _pickDob,
                              icon: const Icon(Icons.calendar_today),
                            ),
                          ),
                          validator: (value) {
                            final v = value?.trim() ?? '';
                            if (v.isEmpty) return null;
                            if (_parseDob(v) == null) {
                              return 'Please choose a valid date';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _bioCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Bio',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 3,
                          maxLength: 200,
                        ),

                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Share with friends'),
                          subtitle: const Text(
                            'Allow profile details to be shared with friends',
                          ),
                          value: _shareWithFriends,
                          onChanged: (value) {
                            setState(() {
                              _shareWithFriends = value;
                              _changed = true;
                            });
                          },
                        ),

                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Anonymous on leaderboards'),
                          subtitle: const Text(
                            'Your name will be hidden and shown as Anonymous',
                          ),
                          value: _blackList,
                          onChanged: (value) {
                            setState(() {
                              _blackList = value;
                              _changed = true;
                            });
                          },
                        ),

                        const SizedBox(height: 12),

                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _openResetPasswordDialog,
                            child: const Text('Reset Password'),
                          ),
                        ),

                        const SizedBox(height: 20),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _save,
                            child: _isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Save Changes'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
