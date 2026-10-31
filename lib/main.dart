import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

// ───────────────────────── Farm palette ─────────────────────────
class Farm {
  static const soil = Color(0xFF3B2A1E); // text, dark surfaces
  static const field = Color(0xFF2F6B2F); // primary green
  static const leaf = Color(0xFF6AA84F); // light green
  static const wheat = Color(0xFFE3B54A); // accent
  static const sky = Color(0xFFCFE6EE); // hero sky
  static const meadow = Color(0xFFEDF1E3); // page background
  static const clay = Color(0xFFB5532F); // weed / warning
}

final String backendUrl = (kIsWeb &&
        Uri.base.host != 'localhost' &&
        Uri.base.host != '127.0.0.1')
    ? Uri.base.origin
    : 'http://127.0.0.1:8000';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Auth.restore();
  runApp(const MyApp());
}

String errorMessage(Object error) {
  if (error is http.ClientException) {
    return 'Cannot connect to backend at $backendUrl.';
  }
  if (error is TimeoutException) {
    return 'Request took too long. Please try again.';
  }
  return error.toString().replaceFirst('Exception: ', '');
}

Map<String, dynamic> readResponse(http.Response response) {
  final dynamic body;

  try {
    body = jsonDecode(utf8.decode(response.bodyBytes));
  } catch (_) {
    throw Exception('Backend returned an unreadable response.');
  }

  if (response.statusCode != 200) {
    throw Exception(
      body is Map && body['detail'] != null
          ? body['detail'].toString()
          : 'Request failed (${response.statusCode}).',
    );
  }

  if (body is! Map<String, dynamic>) {
    throw Exception('Invalid backend response.');
  }

  return body;
}

Widget photoPreview(Uint8List bytes) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: Image.memory(
      bytes,
      height: 300,
      fit: BoxFit.contain,
      errorBuilder: (_, error, stackTrace) {
        return const Padding(
          padding: EdgeInsets.all(20),
          child: Text('Image preview unavailable.'),
        );
      },
    ),
  );
}

// ───────────────────────── App ─────────────────────────
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Farm.field,
      primary: Farm.field,
      secondary: Farm.wheat,
      surface: Colors.white,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Weed Scan',
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: Farm.meadow,
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: Farm.soil,
              displayColor: Farm.soil,
            ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Farm.field,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Farm.meadow,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Farm.field, width: 2),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: Farm.field,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      home: Auth.isLoggedIn ? const FieldDetailsPage() : const LoginPage(),
    );
  }
}

// ───────────────────────── Authentication ─────────────────────────
/// false = demo mode (accounts live only in memory while the app is open).
/// true  = call your backend: POST /register and POST /login (JSON).
/// The backend should answer {"token": "...", "name": "..."}.
const bool useBackendAuth = true;

class Auth {
  static String name = '';
  static String email = '';
  static String? token;

  static const _kToken = 'auth_token';
  static const _kName = 'auth_name';
  static const _kEmail = 'auth_email';

  static bool get isLoggedIn => email.isNotEmpty;

  /// Load a saved login from the device (called once at app start).
  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      email = prefs.getString(_kEmail) ?? '';
      name = prefs.getString(_kName) ?? '';
      token = prefs.getString(_kToken);
      // A login saved in demo mode has no token, so it is not valid
      // when real backend accounts are switched on.
      if (useBackendAuth && token == null) {
        email = '';
        name = '';
      }
    } catch (_) {}
  }

  static Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kEmail, email);
      await prefs.setString(_kName, name);
      if (token != null) {
        await prefs.setString(_kToken, token!);
      } else {
        await prefs.remove(_kToken);
      }
    } catch (_) {}
  }

  // Demo account so you can log in right away in demo mode.
  static final Map<String, Map<String, String>> _demo = {
    'farmer@weedscan.app': {'name': 'Farmer', 'password': 'farmer123'},
  };

  static Map<String, String> get _jsonHeaders =>
      {'Content-Type': 'application/json'};

  static void _apply(Map<String, dynamic> body, String fallbackName, String mail) {
    token = body['token']?.toString();
    name = body['name']?.toString() ?? fallbackName;
    email = mail;
  }

  static Future<void> register(
      String fullName, String mail, String password) async {
    if (useBackendAuth) {
      final response = await http
          .post(
            Uri.parse('$backendUrl/register'),
            headers: _jsonHeaders,
            body: jsonEncode(
                {'name': fullName, 'email': mail, 'password': password}),
          )
          .timeout(const Duration(seconds: 20));
      _apply(readResponse(response), fullName, mail);
      await _save();
      return;
    }

    final key = mail.toLowerCase();
    if (_demo.containsKey(key)) {
      throw Exception('This email is already registered. Please log in.');
    }
    _demo[key] = {'name': fullName, 'password': password};
    name = fullName;
    email = key;
    token = null;
    await _save();
  }

  static Future<void> login(String mail, String password) async {
    if (useBackendAuth) {
      final response = await http
          .post(
            Uri.parse('$backendUrl/login'),
            headers: _jsonHeaders,
            body: jsonEncode({'email': mail, 'password': password}),
          )
          .timeout(const Duration(seconds: 20));
      _apply(readResponse(response), '', mail);
      await _save();
      return;
    }

    final key = mail.toLowerCase();
    final account = _demo[key];
    if (account == null || account['password'] != password) {
      throw Exception('Wrong email or password.');
    }
    name = account['name'] ?? '';
    email = key;
    token = null;
    await _save();
  }

  static Future<void> logout() async {
    name = '';
    email = '';
    token = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kEmail);
      await prefs.remove(_kName);
      await prefs.remove(_kToken);
    } catch (_) {}
  }
}

// ───────────────────────── Login page ─────────────────────────
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _register = false;
  bool _hide = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_register) {
        await Auth.register(
            _name.text.trim(), _email.text.trim(), _password.text);
      } else {
        await Auth.login(_email.text.trim(), _password.text);
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const FieldDetailsPage()),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _tab(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: _loading ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? Farm.field : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: active ? Colors.white : Farm.soil,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const FieldPhotoBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.agriculture,
                          size: 56, color: Colors.white),
                      const SizedBox(height: 10),
                      const Text(
                        'Weed Scan',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          shadows: [
                            Shadow(blurRadius: 8, color: Colors.black54)
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Find weeds early. Protect your crop.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15.5,
                          color: Colors.white,
                          shadows: [
                            Shadow(blurRadius: 6, color: Colors.black54)
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      GlassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Farm.meadow,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    children: [
                                      _tab('Log in', !_register, () {
                                        setState(() {
                                          _register = false;
                                          _error = null;
                                        });
                                      }),
                                      _tab('Create account', _register, () {
                                        setState(() {
                                          _register = true;
                                          _error = null;
                                        });
                                      }),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 18),
                                if (_register) ...[
                                  TextFormField(
                                    controller: _name,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: 'Full name',
                                      prefixIcon: Icon(Icons.person_outline,
                                          color: Farm.field),
                                    ),
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                            ? 'Enter your name'
                                            : null,
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                TextFormField(
                                  controller: _email,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Email',
                                    prefixIcon: Icon(Icons.email_outlined,
                                        color: Farm.field),
                                  ),
                                  validator: (v) {
                                    final t = v?.trim() ?? '';
                                    return t.contains('@') && t.contains('.')
                                        ? null
                                        : 'Enter a valid email';
                                  },
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _password,
                                  obscureText: _hide,
                                  textInputAction: _register
                                      ? TextInputAction.next
                                      : TextInputAction.done,
                                  onFieldSubmitted: (_) {
                                    if (!_register) _submit();
                                  },
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    prefixIcon: const Icon(Icons.lock_outline,
                                        color: Farm.field),
                                    suffixIcon: IconButton(
                                      icon: Icon(_hide
                                          ? Icons.visibility_off
                                          : Icons.visibility),
                                      onPressed: () =>
                                          setState(() => _hide = !_hide),
                                    ),
                                  ),
                                  validator: (v) =>
                                      (v ?? '').length < 6
                                          ? 'Use at least 6 characters'
                                          : null,
                                ),
                                if (_register) ...[
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _confirm,
                                    obscureText: _hide,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => _submit(),
                                    decoration: const InputDecoration(
                                      labelText: 'Confirm password',
                                      prefixIcon: Icon(Icons.lock_outline,
                                          color: Farm.field),
                                    ),
                                    validator: (v) => v != _password.text
                                        ? 'Passwords do not match'
                                        : null,
                                  ),
                                ],
                                if (_error != null)
                                  Container(
                                    margin: const EdgeInsets.only(top: 14),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Farm.clay.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.error_outline,
                                            color: Farm.clay),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(_error!,
                                              style: const TextStyle(
                                                  color: Farm.clay)),
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 18),
                                FilledButton(
                                  onPressed: _loading ? null : _submit,
                                  child: _loading
                                      ? const SizedBox(
                                          height: 22,
                                          width: 22,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 3,
                                              color: Colors.white),
                                        )
                                      : Text(_register
                                          ? 'Create account'
                                          : 'Log in'),
                                ),
                                if (!useBackendAuth && !_register) ...[
                                  const SizedBox(height: 14),
                                  Text(
                                    'Demo login: farmer@weedscan.app / farmer123',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Farm.soil.withOpacity(0.7),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Session history ─────────────────────────
class ScanRecord {
  ScanRecord({
    required this.field,
    required this.crop,
    required this.zone,
    required this.weeds,
    required this.isVideo,
    required this.time,
  });

  final String field;
  final String crop;
  final String zone;
  final num? weeds;
  final bool isVideo;
  final DateTime? time;

  double get weedValue => weeds?.toDouble() ?? 0;

  String get weedLabel {
    final w = weeds;
    if (w == null) return '-';
    return w is int ? '$w' : w.toStringAsFixed(1);
  }

  factory ScanRecord.fromJson(Map<String, dynamic> j) {
    final isVideo = j['media_type'] == 'video';
    final weeds =
        isVideo ? j['average_weeds_per_sampled_frame'] : j['weed_count'];

    DateTime? time;
    for (final key in const [
      'created_at',
      'timestamp',
      'date',
      'saved_at',
      'scanned_at',
    ]) {
      final v = j[key];
      if (v is String) {
        time = DateTime.tryParse(v)?.toLocal();
        if (time != null) break;
      }
    }

    return ScanRecord(
      field: j['field_id']?.toString() ?? '-',
      crop: j['crop_type']?.toString() ?? '',
      zone: j['zone_id']?.toString() ?? '',
      weeds: weeds is num ? weeds : null,
      isVideo: isVideo,
      time: time,
    );
  }
}

/// Saved scans loaded from the backend (/history), newest first.
final ValueNotifier<List<ScanRecord>> scanHistory =
    ValueNotifier<List<ScanRecord>>([]);

Future<void> loadHistory() async {
  try {
    final response = await http.get(
      Uri.parse('$backendUrl/history'),
      headers: {
        if (Auth.token != null) 'Authorization': 'Bearer ${Auth.token}',
      },
    ).timeout(const Duration(seconds: 15));

    final body = readResponse(response);
    final scans = (body['scans'] as List?) ?? [];

    final list = <ScanRecord>[
      for (final item in scans)
        if (item is Map)
          ScanRecord.fromJson(Map<String, dynamic>.from(item)),
    ];

    if (list.isNotEmpty && list.every((r) => r.time != null)) {
      list.sort((a, b) => b.time!.compareTo(a.time!));
    }
    scanHistory.value = list;
  } catch (_) {
    // Keep whatever is already shown if the backend is not reachable.
  }
}

String greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

String clock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
}

class CropOption {
  const CropOption(this.name, this.emoji);
  final String name;
  final String emoji;
}

const List<CropOption> cropOptions = [
  CropOption('Paddy', '🌾'),
  CropOption('Maize', '🌽'),
  CropOption('Sugarcane', '🎋'),
  CropOption('Cotton', '🌿'),
  CropOption('Tomato', '🍅'),
  CropOption('Potato', '🥔'),
  CropOption('Chilli', '🌶️'),
  CropOption('Other', '✏️'),
];

const List<String> zoneNames = [
  'North-West', 'North', 'North-East',
  'West', 'Centre', 'East',
  'South-West', 'South', 'South-East',
];

const List<String> zoneShort = [
  'NW', 'N', 'NE',
  'W', 'C', 'E',
  'SW', 'S', 'SE',
];

// ───────────────────────── Home page ─────────────────────────
class FieldDetailsPage extends StatefulWidget {
  const FieldDetailsPage({super.key});

  @override
  State<FieldDetailsPage> createState() => _FieldDetailsPageState();
}

class _FieldDetailsPageState extends State<FieldDetailsPage> {
  final _field = TextEditingController(text: 'Field 1');
  final _otherCrop = TextEditingController();

  String? _crop;
  int? _zone;
  String? _error;

  @override
  void initState() {
    super.initState();
    loadHistory();
  }

  @override
  void dispose() {
    _field.dispose();
    _otherCrop.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await Auth.logout();
    scanHistory.value = [];
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _start() {
    final field = _field.text.trim();
    final crop = _crop == 'Other' ? _otherCrop.text.trim() : (_crop ?? '');

    String? error;
    if (field.isEmpty) {
      error = 'Enter a field name.';
    } else if (crop.isEmpty) {
      error = _crop == 'Other' ? 'Type your crop name.' : 'Choose your crop.';
    } else if (_zone == null) {
      error = 'Tap the part of the field you will scan.';
    }

    setState(() => _error = error);
    if (error != null) return;

    FocusScope.of(context).unfocus();

    final zoneId = _zone == 4 ? 'Centre Zone' : '${zoneNames[_zone!]} Zone';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScanPage(
          fieldId: field,
          cropType: crop,
          zoneId: zoneId,
        ),
      ),
    );
  }

  Widget _stepTitle(String number, String title, String hint) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: Farm.field,
          child: Text(
            number,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w800)),
              Text(hint,
                  style: TextStyle(
                      fontSize: 13.5, color: Farm.soil.withOpacity(0.7))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cropTile(CropOption option) {
    final selected = _crop == option.name;
    return Material(
      color: selected ? Farm.field : Farm.meadow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _crop = option.name),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(option.emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(height: 4),
              Text(
                option.name,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : Farm.soil,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _zoneCell(int index) {
    final selected = _zone == index;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: selected ? Farm.wheat : const Color(0xFF7FAE5B),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _zone = index),
          child: Center(
            child: selected
                ? const Icon(Icons.check_circle, color: Farm.soil, size: 30)
                : Text(
                    zoneShort[index],
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _zoneMap() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.north, size: 18, color: Farm.soil),
            SizedBox(width: 4),
            Text('North', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 1.5,
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: const Color(0xFF6B4A2F),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                for (var r = 0; r < 3; r++)
                  Expanded(
                    child: Row(
                      children: [
                        for (var c = 0; c < 3; c++)
                          Expanded(child: _zoneCell(r * 3 + c)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _zone == null
              ? 'No area selected'
              : 'Selected: ${_zone == 4 ? 'Centre' : zoneNames[_zone!]} area',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _recent() {
    return ValueListenableBuilder<List<ScanRecord>>(
      valueListenable: scanHistory,
      builder: (context, list, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Recent scans',
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          shadows: [
                            Shadow(blurRadius: 6, color: Colors.black54)
                          ])),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: loadHistory,
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (list.isEmpty)
              Text(
                'No saved scans yet.',
                style: const TextStyle(color: Colors.white),
              ),
            for (final r in list.take(5))
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Farm.soil.withOpacity(0.10)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: (r.weedValue > 0 ? Farm.clay : Farm.field)
                          .withOpacity(0.14),
                      child: Icon(
                        r.weedValue > 0
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline,
                        color: r.weedValue > 0 ? Farm.clay : Farm.field,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${r.field} · ${r.zone}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                          Text(
                              [
                                r.crop,
                                if (r.time != null) clock(r.time!),
                              ].join(' · '),
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Farm.soil.withOpacity(0.7))),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          r.weedLabel,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: r.weedValue > 0 ? Farm.clay : Farm.field,
                          ),
                        ),
                        Text(r.isVideo ? 'avg weeds' : 'weeds',
                            style: const TextStyle(fontSize: 11.5)),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
        title: Row(
          children: const [
            Icon(Icons.agriculture, size: 26),
            SizedBox(width: 10),
            Text('Weed Scan',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const FieldPhotoBackground(),
          SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, kToolbarHeight + 12, 18, 18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    Auth.name.isEmpty
                        ? greeting()
                        : '${greeting()}, ${Auth.name}',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Walk your field, take a photo, and find weeds early.',
                    style: const TextStyle(
                      fontSize: 15.5,
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Step 1
                  GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _stepTitle('1', 'Choose your crop',
                              'Tap the crop growing in this field'),
                          const SizedBox(height: 14),
                          GridView.count(
                            crossAxisCount: 4,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 0.95,
                            children: [
                              for (final c in cropOptions) _cropTile(c),
                            ],
                          ),
                          if (_crop == 'Other') ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller: _otherCrop,
                              decoration: const InputDecoration(
                                labelText: 'Crop name',
                                prefixIcon:
                                    Icon(Icons.grass, color: Farm.field),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Step 2
                  GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _stepTitle('2', 'Name your field',
                              'For example Field 1, or the owner\'s plot'),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _field,
                            decoration: const InputDecoration(
                              labelText: 'Field name',
                              prefixIcon:
                                  Icon(Icons.landscape, color: Farm.field),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Step 3
                  GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _stepTitle('3', 'Pick the area you will scan',
                              'This is a top view of your field. Tap one part.'),
                          const SizedBox(height: 14),
                          _zoneMap(),
                          const SizedBox(height: 8),
                          Text(
                            'Pick the same area each time you scan that spot, '
                            'so results can be compared.',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: Farm.soil.withOpacity(0.7)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Farm.clay),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_error!,
                                style: const TextStyle(color: Farm.clay)),
                          ),
                        ],
                      ),
                    ),

                  FilledButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Start scanning'),
                  ),
                  const SizedBox(height: 28),
                  _recent(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
        ],
      ),
    );
  }
}

const String fieldPhoto = 'assets/field_bg.jpg';

/// Full-screen misty plantation photo with a soft dark overlay for readability.
class FieldPhotoBackground extends StatelessWidget {
  const FieldPhotoBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          fieldPhoto,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) =>
              Container(color: Farm.field),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.45),
                Colors.black.withOpacity(0.12),
                Colors.black.withOpacity(0.55),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Frosted card that sits on top of the photo.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.88),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.6)),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ───────────────────────── Small shared widgets ─────────────────────────
class FarmCard extends StatelessWidget {
  const FarmCard({super.key, required this.child, this.clipBehavior = Clip.none});

  final Widget child;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Farm.soil.withOpacity(0.10)),
      ),
      child: child,
    );
  }
}

class InfoChip extends StatelessWidget {
  const InfoChip({super.key, required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Farm.wheat),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 11, color: Colors.white70)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ],
          ),
        ],
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 34, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}

/// Heat-map style grid: the more weeds in a cell, the stronger the colour.
class CountGrid extends StatelessWidget {
  const CountGrid({super.key, required this.rows, this.highlightFn, this.decimals = 0});

  final List<dynamic> rows;
  final bool Function(int row, int column)? highlightFn;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    double maxValue = 0;
    for (final row in rows) {
      for (final v in row as List) {
        if (v is num && v > maxValue) maxValue = v.toDouble();
      }
    }

    return Column(
      children: [
        for (var r = 0; r < rows.length; r++)
          Row(
            children: [
              for (var c = 0; c < (rows[r] as List).length; c++)
                Expanded(child: _cell(r, c, maxValue)),
            ],
          ),
      ],
    );
  }

  Widget _cell(int r, int c, double maxValue) {
    final raw = (rows[r] as List)[c];
    final value = raw is num ? raw.toDouble() : 0.0;
    final t = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);
    final base = Color.lerp(const Color(0xFFDDEBCB), Farm.clay, t)!;
    final marked = highlightFn?.call(r, c) ?? false;

    return Container(
      margin: const EdgeInsets.all(3),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(10),
        border: marked ? Border.all(color: Farm.soil, width: 3) : null,
      ),
      child: Text(
        decimals == 0 ? value.round().toString() : value.toStringAsFixed(decimals),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: t > 0.55 ? Colors.white : Farm.soil,
        ),
      ),
    );
  }
}

// ───────────────────────── Scan page ─────────────────────────
class ScanPage extends StatefulWidget {
  const ScanPage({
    super.key,
    required this.fieldId,
    required this.cropType,
    required this.zoneId,
  });

  final String fieldId;
  final String cropType;
  final String zoneId;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final _picker = ImagePicker();

  XFile? _selectedFile;
  Uint8List? _photoBytes;
  bool _isVideo = false;
  bool _busy = false;
  bool _analyzing = false;

  Map<String, dynamic>? _scanResult;
  String? _scanError;
  http.Client? _activeClient;

  bool get _locked => _busy || _analyzing;

  @override
  void dispose() {
    _activeClient?.close();
    super.dispose();
  }

  Future<void> _pickMedia({
    required bool video,
    required ImageSource source,
  }) async {
    if (_locked) return;
    setState(() => _busy = true);

    try {
      final XFile? file = video
          ? await _picker.pickVideo(source: source)
          : await _picker.pickImage(source: source);

      if (file == null) return;

      if (await file.length() > 100 * 1024 * 1024) {
        throw Exception('Maximum file size is 100 MB.');
      }

      final bytes = video ? null : await file.readAsBytes();

      if (!mounted) return;
      setState(() {
        _selectedFile = file;
        _photoBytes = bytes;
        _isVideo = video;
        _scanResult = null;
        _scanError = null;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _removeMedia() {
    if (_locked) return;

    setState(() {
      _selectedFile = null;
      _photoBytes = null;
      _isVideo = false;
      _scanResult = null;
      _scanError = null;
    });
  }

  Future<void> _analyzeMedia() async {
    final file = _selectedFile;
    if (file == null || _locked) return;

    setState(() {
      _analyzing = true;
      _scanResult = null;
      _scanError = null;
    });

    final client = http.Client();
    _activeClient = client;

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$backendUrl/scan'),
      );

      request.fields.addAll({
        'field_id': widget.fieldId,
        'crop_type': widget.cropType,
        'zone_id': widget.zoneId,
      });

      if (Auth.token != null) {
        request.headers['Authorization'] = 'Bearer ${Auth.token}';
      }

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          await file.readAsBytes(),
          filename: file.name,
        ),
      );

      final response = await (() async {
        final streamed = await client.send(request);
        return await http.Response.fromStream(streamed);
      })().timeout(const Duration(minutes: 10));

      final result = readResponse(response);

      if (!mounted) return;
      setState(() => _scanResult = result);

      loadHistory();
    } catch (error) {
      if (!mounted) return;
      setState(() => _scanError = errorMessage(error));
    } finally {
      client.close();
      if (identical(_activeClient, client)) {
        _activeClient = null;
      }
      if (mounted) setState(() => _analyzing = false);
    }
  }

  // Big tappable capture tile
  Widget _mediaTile(
    String text,
    IconData icon,
    bool video,
    ImageSource source,
  ) {
    final enabled = !_locked;
    return Material(
      color: enabled ? Colors.white : Colors.white70,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? () => _pickMedia(video: video, source: source) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Farm.field.withOpacity(0.25)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Farm.field.withOpacity(0.12),
                child: Icon(icon, color: Farm.field, size: 26),
              ),
              const SizedBox(height: 10),
              Text(text,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _results() {
    final result = _scanResult!;
    final video = result['media_type'] == 'video';
    final frames = (result['frames'] as List?) ?? [];

    final String? preview = video
        ? (frames.isNotEmpty
            ? frames.first['annotated_image_base64'] as String?
            : null)
        : result['annotated_image_base64'] as String?;

    Uint8List? bytes;
    if (preview != null) {
      try {
        bytes = base64Decode(preview);
      } catch (_) {
        bytes = null;
      }
    }

    final grid = (result['image_grid_weed_counts'] as List?) ?? [];

    return FarmCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: const [
                Icon(Icons.agriculture, color: Farm.field),
                SizedBox(width: 8),
                Text(
                  'Scan results',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (bytes != null) photoPreview(bytes),
            const SizedBox(height: 16),
            if (!video) ...[
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      icon: Icons.grass,
                      label: 'Crops detected',
                      value: '${result['crop_count']}',
                      color: Farm.field,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      icon: Icons.warning_amber_rounded,
                      label: 'Weeds detected',
                      value: '${result['weed_count']}',
                      color: Farm.clay,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(result['summary']?.toString() ?? ''),
              const SizedBox(height: 18),
              const Text(
                'Weeds by image cell',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              CountGrid(rows: grid),
              const SizedBox(height: 4),
              Text(
                'Darker red means more weeds in that part of the photo.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Farm.soil.withOpacity(0.7),
                ),
              ),
              if (result['zone_assessment'] is Map) ...[
                const SizedBox(height: 16),
                ZoneAssessmentCard(
                  assessment: Map<String, dynamic>.from(
                    result['zone_assessment'] as Map,
                  ),
                ),
              ],
            ],
            if (video) ...[
              const Text('Preview: first accepted sampled frame.'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      icon: Icons.movie_filter,
                      label: 'Frames analyzed',
                      value: '${result['sampled_frames']}',
                      color: Farm.field,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      icon: Icons.warning_amber_rounded,
                      label: 'Avg weeds per frame',
                      value: '${result['average_weeds_per_sampled_frame']}',
                      color: Farm.clay,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final frame in frames)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Farm.meadow,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${frame['timestamp_seconds']} seconds: '
                    '${frame['crop_count']} crops, '
                    '${frame['weed_count']} weeds',
                  ),
                ),
              const SizedBox(height: 8),
              Text(result['video_note']?.toString() ?? ''),
            ],
            const SizedBox(height: 16),
            if (result['saved'] == true)
              Row(
                children: const [
                  Icon(Icons.check_circle, color: Farm.field, size: 20),
                  SizedBox(width: 6),
                  Text('Scan saved to history.'),
                ],
              ),
            if (result['scan_id'] != null)
              Text('Scan ID: ${result['scan_id']}',
                  style: TextStyle(color: Farm.soil.withOpacity(0.7))),
            const SizedBox(height: 8),
            Text(result['note']?.toString() ?? ''),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan your field')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Field header band
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 60, 20, 22),
                decoration: BoxDecoration(
                  color: Farm.field,
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(24)),
                  image: DecorationImage(
                    image: const AssetImage(fieldPhoto),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                        Colors.black.withOpacity(0.35), BlendMode.darken),
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 650),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        InfoChip(
                            icon: Icons.landscape,
                            label: 'Field',
                            value: widget.fieldId),
                        InfoChip(
                            icon: Icons.grass,
                            label: 'Crop',
                            value: widget.cropType),
                        InfoChip(
                            icon: Icons.location_on,
                            label: 'Zone',
                            value: widget.zoneId),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 650),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Add a photo or video',
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Use a clear, close field view in daylight. '
                          'Move slowly when recording video.',
                          style: TextStyle(
                              color: Farm.soil.withOpacity(0.75)),
                        ),
                        const SizedBox(height: 16),
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.45,
                          children: [
                            _mediaTile('Take photo', Icons.camera_alt, false,
                                ImageSource.camera),
                            _mediaTile('Record video', Icons.videocam, true,
                                ImageSource.camera),
                            _mediaTile('Upload photo', Icons.photo_library,
                                false, ImageSource.gallery),
                            _mediaTile('Upload video', Icons.video_library,
                                true, ImageSource.gallery),
                          ],
                        ),
                        const SizedBox(height: 20),
                        if (_busy)
                          const Center(child: CircularProgressIndicator()),
                        if (_selectedFile == null && !_busy)
                          Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Farm.field.withOpacity(0.35),
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              children: const [
                                Icon(Icons.add_a_photo_outlined,
                                    size: 44, color: Farm.leaf),
                                SizedBox(height: 8),
                                Text(
                                  'No photo or video selected yet.',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        if (_selectedFile != null) ...[
                          FarmCard(
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (!_isVideo && _photoBytes != null)
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: photoPreview(_photoBytes!),
                                  ),
                                if (_isVideo)
                                  const Padding(
                                    padding: EdgeInsets.all(32),
                                    child: Column(
                                      children: [
                                        Icon(Icons.video_file,
                                            size: 72, color: Farm.field),
                                        Text('Video selected'),
                                      ],
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Text(
                                    _selectedFile!.name,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _locked ? null : _removeMedia,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Remove selected file'),
                          ),
                          const SizedBox(height: 4),
                          FilledButton.icon(
                            onPressed: _locked ? null : _analyzeMedia,
                            icon: const Icon(Icons.search),
                            label: Text(
                              _analyzing ? 'Analyzing...' : 'Analyze scan',
                            ),
                          ),
                        ],
                        if (_analyzing)
                          Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: Column(
                              children: [
                                const LinearProgressIndicator(
                                  color: Farm.field,
                                  minHeight: 6,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _isVideo
                                      ? 'Looking for weeds. Videos can take a few minutes.'
                                      : 'Looking for weeds in your photo...',
                                ),
                              ],
                            ),
                          ),
                        if (_scanError != null)
                          Container(
                            margin: const EdgeInsets.only(top: 16),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Farm.clay.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.error_outline,
                                    color: Farm.clay),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _scanError!,
                                    style:
                                        const TextStyle(color: Farm.clay),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_scanResult != null) ...[
                          const SizedBox(height: 20),
                          _results(),
                        ],
                        const SizedBox(height: 24),
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

// ───────────────────────── Zone assessment ─────────────────────────
class ZoneAssessmentCard extends StatefulWidget {
  const ZoneAssessmentCard({
    super.key,
    required this.assessment,
  });

  final Map<String, dynamic> assessment;

  @override
  State<ZoneAssessmentCard> createState() => _ZoneAssessmentCardState();
}

class _ZoneAssessmentCardState extends State<ZoneAssessmentCard> {
  int _scenarioIndex = 0;

  @override
  void didUpdateWidget(covariant ZoneAssessmentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assessment != widget.assessment) {
      _scenarioIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.assessment;
    final leaders = (data['current_inspection_cells'] as List?) ?? [];
    final scenarios = (data['scenarios'] as List?) ?? [];
    final lstm = (data['lstm_forecast'] as Map?) ?? {};

    final grid = scenarios.isEmpty
        ? <dynamic>[]
        : scenarios[_scenarioIndex]['illustrative_counts'] as List;

    bool highlighted(int row, int column) {
      return leaders.any(
        (cell) => cell['row'] == row + 1 && cell['column'] == column + 1,
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6DD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Farm.wheat.withOpacity(0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: const [
              Icon(Icons.pin_drop, color: Farm.clay),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Which scanned area needs attention now?',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (leaders.isEmpty)
            const Text(
              'No weeds detected. No cell can be ranked from '
              'detections. This does not confirm the field is weed-free.',
            ),
          for (final cell in leaders)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Inspect image row ${cell['row']}, '
                'column ${cell['column']} first: '
                '${cell['weed_count']} detected weeds '
                '(highest current count).',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 4),
          Text(data['scope_note']?.toString() ?? ''),
          const Divider(height: 32),
          const Text(
            'Experimental future scenarios',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Assumptions only, not LSTM predictions. '
            'A future most-affected zone has not been established.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < scenarios.length; i++)
                ChoiceChip(
                  label: Text(scenarios[i]['label'].toString()),
                  selected: _scenarioIndex == i,
                  selectedColor: Farm.leaf.withOpacity(0.35),
                  onSelected: (_) => setState(() => _scenarioIndex = i),
                ),
            ],
          ),
          const SizedBox(height: 12),
          CountGrid(rows: grid, highlightFn: highlighted, decimals: 2),
          const SizedBox(height: 8),
          const Text(
            'Numbers are illustrative count equivalents. '
            'Outlined cells mark highest CURRENT counts, '
            'not validated future risk.',
            style: TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          Text(data['scenario_note']?.toString() ?? ''),
          const Divider(height: 32),
          Row(
            children: const [
              Icon(Icons.timeline, size: 20),
              SizedBox(width: 6),
              Text(
                'LSTM field forecast: unavailable',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(lstm['reason']?.toString() ?? ''),
        ],
      ),
    );
  }
}