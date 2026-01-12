import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'weather_gpx_tools.dart';
import 'weather_auto_open_meteo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('intakes');
  await Hive.openBox('activities');
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Nutrition ↔ Effort',
      theme: ThemeData(useMaterial3: true),
      home: const IntakeFormScreen(),
    );
  }
}

/// --- Screen 1: Add intake (extended) ---
class IntakeFormScreen extends StatefulWidget {
  const IntakeFormScreen({super.key});

  @override
  State<IntakeFormScreen> createState() => _IntakeFormScreenState();
}

class _IntakeFormScreenState extends State<IntakeFormScreen> {
  Box get _box => Hive.box('intakes');

  // Required
  final _brandCtrl = TextEditingController();
  final _productCtrl = TextEditingController();

  // General / macros
  final _servingSizeGCtrl =
      TextEditingController(); // taille de portion indiquée
  final _weightGCtrl = TextEditingController(); // poids de la prise (g)
  final _energyKcalCtrl = TextEditingController();
  final _fatGCtrl = TextEditingController();
  final _carbsGCtrl = TextEditingController();
  final _fiberGCtrl = TextEditingController();
  final _proteinGCtrl = TextEditingController();

  // Electrolytes / minerals
  final _chlorideMgCtrl = TextEditingController();
  final _sodiumMgCtrl = TextEditingController(); // sel/sodium
  final _potassiumMgCtrl = TextEditingController();
  final _calciumMgCtrl = TextEditingController();
  final _magnesiumMgCtrl = TextEditingController();
  final _ironMgCtrl = TextEditingController();

  // Vitamins
  final _vitCMgCtrl = TextEditingController();
  final _vitB12McgCtrl = TextEditingController(); // microgrammes
  final _vitB6MgCtrl = TextEditingController();
  final _vitB2MgCtrl = TextEditingController();

  // Hydration-specific
  final _tabletsCountCtrl = TextEditingController(); // nb pastilles
  final _powderGramsCtrl = TextEditingController(); // g poudre

  // UI state
  String _type = 'gel'; // gel, barre, boisson, puree, pastilles, poudre
  String _basis = 'portion'; // portion ou 100g
  String _message = '';
  String _intakeContext = 'unknown';

  static const Map<String, String> _typeLabels = {
    'gel': 'Gel',
    'barre': 'Barre',
    'boisson': 'Boisson',
    'puree': 'Purée',
    'pastilles': 'Pastilles (hydratation)',
    'poudre': 'Poudre à mélanger',
  };

  static const Map<String, String> _basisLabels = {
    'portion': 'Valeurs par portion',
    '100g': 'Valeurs pour 100 g',
  };

  static const Map<String, String> _contextLabels = {
    'before': 'Avant l’effort',
    'during': 'Pendant l’effort',
    'after': 'Après l’effort',
    'unknown': 'Non défini',
  };

  @override
  void dispose() {
    _brandCtrl.dispose();
    _productCtrl.dispose();
    _weightGCtrl.dispose();
    _energyKcalCtrl.dispose();
    _fatGCtrl.dispose();
    _carbsGCtrl.dispose();
    _fiberGCtrl.dispose();
    _proteinGCtrl.dispose();

    _chlorideMgCtrl.dispose();
    _sodiumMgCtrl.dispose();
    _potassiumMgCtrl.dispose();
    _calciumMgCtrl.dispose();
    _magnesiumMgCtrl.dispose();
    _ironMgCtrl.dispose();

    _vitCMgCtrl.dispose();
    _vitB12McgCtrl.dispose();
    _vitB6MgCtrl.dispose();
    _vitB2MgCtrl.dispose();

    _tabletsCountCtrl.dispose();
    _powderGramsCtrl.dispose();
    super.dispose();
  }

  double _d(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0.0;

  int _i(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  bool get _isHydration => _type == 'pastilles' || _type == 'poudre';

  Future<void> _save() async {
    final brand = _brandCtrl.text.trim();
    final product = _productCtrl.text.trim();

    if (brand.isEmpty || product.isEmpty) {
      setState(() => _message = 'Champs requis : Marque et Produit.');
      return;
    }

    // Hydration validation: at least one meaningful quantity (optional but recommended)
    if (_isHydration) {
      final tablets = _i(_tabletsCountCtrl);
      final powderG = _d(_powderGramsCtrl);
      if (tablets == 0 && powderG == 0) {
        setState(
          () => _message =
              'Hydratation : indique le nombre de pastilles ou le grammage de poudre (sinon 0).',
        );
        // No stop, default = 0. So continue.
      }
    }

    // calcul factor

    final weight = _d(_weightGCtrl);
    final serving = _d(_servingSizeGCtrl);

    double factor = 1.0;
    // si valeurs par portion, et que serving_size_g est renseigné + poids aussi,
    // on peut aussi convertir proportionnellement (optionnel)
    if (_basis == 'portion') {
      final serving = _d(_servingSizeGCtrl);
      final w = _d(_weightGCtrl);
      if (serving > 0 && w > 0) {
        factor = w / serving;
      } else {
        factor = 1.0; // par défaut
      }
    }

    if (_basis == '100g') {
      factor = weight > 0 ? weight / 100.0 : 0.0;
    } else if (_basis == 'portion') {
      // si masse, portion connue, etc.le; sinon laisse comme c'est
      factor = (serving > 0 && weight > 0) ? weight / serving : 1.0;
    }

    // final intake = { ... }
    final intake = {
      // --- meta ---
      'ts': DateTime.now().millisecondsSinceEpoch,
      'source': 'manual', // futur : 'photo_ai'
      // --- identity ---
      'brand': brand,
      'product': product,
      'type': _type, // gel / barre / poudre / pastille
      'basis': _basis, // 'portion' | '100g'
      // --- quantities ---
      'weight_g': _d(_weightGCtrl), // poids réellement consommé
      'serving_size_g': _d(
        _servingSizeGCtrl,
      ), // portion indiquée sur l’étiquette
      // --- nutrition declared (label values, default = 0) ---
      'energy_kcal': _d(_energyKcalCtrl),
      'fat_g': _d(_fatGCtrl),
      'carbs_g': _d(_carbsGCtrl),
      'fiber_g': _d(_fiberGCtrl),
      'protein_g': _d(_proteinGCtrl),

      // --- electrolytes / minerals declared ---
      'chloride_mg': _d(_chlorideMgCtrl),
      'sodium_mg': _d(_sodiumMgCtrl),
      'potassium_mg': _d(_potassiumMgCtrl),
      'calcium_mg': _d(_calciumMgCtrl),
      'magnesium_mg': _d(_magnesiumMgCtrl),
      'iron_mg': _d(_ironMgCtrl),

      // --- vitamins declared ---
      'vit_c_mg': _d(_vitCMgCtrl),
      'vit_b12_mcg': _d(_vitB12McgCtrl),
      'vit_b6_mg': _d(_vitB6MgCtrl),
      'vit_b2_mg': _d(_vitB2MgCtrl),

      // --- hydration extras ---
      'tablets_count': _i(_tabletsCountCtrl),
      'powder_g': _d(_powderGramsCtrl),

      // ======================================================
      // === EFFECTIVE VALUES (computed for the actual intake)
      // ======================================================
      'energy_effective_kcal': _d(_energyKcalCtrl) * factor,
      'fat_effective_g': _d(_fatGCtrl) * factor,
      'carbs_effective_g': _d(_carbsGCtrl) * factor,
      'fiber_effective_g': _d(_fiberGCtrl) * factor,
      'protein_effective_g': _d(_proteinGCtrl) * factor,

      'chloride_effective_mg': _d(_chlorideMgCtrl) * factor,
      'sodium_effective_mg': _d(_sodiumMgCtrl) * factor,
      'potassium_effective_mg': _d(_potassiumMgCtrl) * factor,
      'calcium_effective_mg': _d(_calciumMgCtrl) * factor,
      'magnesium_effective_mg': _d(_magnesiumMgCtrl) * factor,
      'iron_effective_mg': _d(_ironMgCtrl) * factor,

      'vit_c_effective_mg': _d(_vitCMgCtrl) * factor,
      'vit_b12_effective_mcg': _d(_vitB12McgCtrl) * factor,
      'vit_b6_effective_mg': _d(_vitB6MgCtrl) * factor,
      'vit_b2_effective_mg': _d(_vitB2MgCtrl) * factor,
    };

    await _box.add(intake);
    // enregistrement
    setState(() => _message = '✅ Prise enregistrée');

    // clear only the most used fields (keep brand for rapid input)
    _productCtrl.clear();
    _weightGCtrl.clear();
    _energyKcalCtrl.clear();
    _fatGCtrl.clear();
    _carbsGCtrl.clear();
    _fiberGCtrl.clear();
    _proteinGCtrl.clear();

    _chlorideMgCtrl.clear();
    _sodiumMgCtrl.clear();
    _potassiumMgCtrl.clear();
    _calciumMgCtrl.clear();
    _magnesiumMgCtrl.clear();
    _ironMgCtrl.clear();

    _vitCMgCtrl.clear();
    _vitB12McgCtrl.clear();
    _vitB6MgCtrl.clear();
    _vitB2MgCtrl.clear();

    _tabletsCountCtrl.clear();
    _powderGramsCtrl.clear();
  }

  Widget _sectionTitle(String s) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(
          s,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajouter une prise nutrition'),
        actions: [
          IconButton(
            tooltip: 'Historique',
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const IntakeHistoryScreen()),
              );
            },
          ),
          IconButton(
            tooltip: 'Activités',
            icon: const Icon(Icons.directions_run),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ActivityFormScreen()),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _brandCtrl,
            decoration: const InputDecoration(labelText: 'Marque (ex: Näak) *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _productCtrl,
            decoration: const InputDecoration(
              labelText: 'Produit (ex: Gel Maurten 160) *',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            items: _typeLabels.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: (v) => setState(() => _type = v ?? 'gel'),
            decoration: const InputDecoration(labelText: 'Type de produit'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _basis,
            items: _basisLabels.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: (v) => setState(() => _basis = v ?? 'portion'),
            decoration: const InputDecoration(labelText: 'Base des valeurs'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _intakeContext,
            items: _contextLabels.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: (v) => setState(() => _intakeContext = v ?? 'unknown'),
            decoration: const InputDecoration(labelText: 'Moment de la prise'),
          ),
          const SizedBox(height: 12),
          _sectionTitle('Quantité'),
          TextField(
            controller: _weightGCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Poids de la prise (g) (ex: 65)',
            ),
          ),
          if (_isHydration) ...[
            _sectionTitle('Hydratation'),
            TextField(
              controller: _tabletsCountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Nombre de pastilles (si applicable)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _powderGramsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Grammage de poudre (g) (si applicable)',
              ),
            ),
          ],
          _sectionTitle('Valeurs nutritionnelles'),
          TextField(
            controller: _energyKcalCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Énergie (kcal)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _fatGCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Matières grasses / Lipides (g)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _carbsGCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Glucides / Carbohydrates (g)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _fiberGCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Fibres alimentaires (g)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _proteinGCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Protéines (g)'),
          ),
          _sectionTitle('Électrolytes & minéraux'),
          TextField(
            controller: _chlorideMgCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Chlorure (mg)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sodiumMgCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Sel/Sodium (mg)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _potassiumMgCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Potassium (mg)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _calciumMgCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Calcium (mg)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _magnesiumMgCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Magnésium (mg)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ironMgCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Fer (mg)'),
          ),
          _sectionTitle('Vitamines'),
          TextField(
            controller: _vitCMgCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Vitamine C (mg)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _vitB12McgCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Vitamine B12 (µg)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _vitB6MgCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Vitamine B6 (mg)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _vitB2MgCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Vitamine B2 (mg)'),
          ),
          const SizedBox(height: 22),
          FilledButton(onPressed: _save, child: const Text('Enregistrer')),
          const SizedBox(height: 12),
          if (_message.isNotEmpty) Text(_message),
        ],
      ),
    );
  }
}

/// --- Screen 2: Intake history (extended) ---
class IntakeHistoryScreen extends StatelessWidget {
  const IntakeHistoryScreen({super.key});

  Box get _box => Hive.box('intakes');

  String _formatTs(dynamic ts) {
    if (ts is! int) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String _typeLabel(dynamic t) {
    switch (t) {
      case 'barre':
        return 'Barre';
      case 'boisson':
        return 'Boisson';
      case 'puree':
        return 'Purée';
      case 'pastilles':
        return 'Pastilles';
      case 'poudre':
        return 'Poudre';
      default:
        return 'Gel';
    }
  }

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0.0;
  }

  String _fmt1(dynamic v) => _asDouble(v).toStringAsFixed(1);
  String _fmt0(dynamic v) => _asDouble(v).toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historique des prises')),
      body: ValueListenableBuilder(
        valueListenable: _box.listenable(),
        builder: (context, Box<dynamic> box, _) {
          if (box.isEmpty) {
            return const Center(child: Text('Aucune prise enregistrée.'));
          }

          final keys = box.keys.toList().reversed.toList();

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: keys.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final key = keys[i];
              final m = box.get(key);

              if (m is! Map) {
                return ListTile(title: Text('Entrée invalide (clé: $key)'));
              }

              final brand = (m['brand'] ?? '').toString();
              final product = (m['product'] ?? '').toString();
              final type = _typeLabel(m['type']);

              final basisRaw = (m['basis'] ?? 'portion').toString();
              final basisLabel =
                  (basisRaw == '100g') ? 'pour 100g' : 'par portion';

              final weightG = _asDouble(m['weight_g']);
              final servingG = _asDouble(m['serving_size_g']);

              // Declared (label)
              final energyD = _fmt0(m['energy_kcal']);
              final carbsD = _fmt1(m['carbs_g']);
              final sodiumD = _fmt0(m['sodium_mg']);

              // Effective (computed for actual intake)
              final energyE = _fmt0(m['energy_effective_kcal']);
              final carbsE = _fmt1(m['carbs_effective_g']);
              final sodiumE = _fmt0(m['sodium_effective_mg']);

              // Optional hydration extras
              final t = (m['type'] ?? '').toString();
              final isHydration = (t == 'pastilles' || t == 'poudre');
              final tablets = (m['tablets_count'] ?? 0).toString();
              final powderG = _fmt0(m['powder_g']);

              final lineMeta = [
                _formatTs(m['ts']),
                type,
                'base: $basisLabel',
                if (weightG > 0) 'poids: ${weightG.toStringAsFixed(0)} g',
                if (servingG > 0) 'portion: ${servingG.toStringAsFixed(0)} g',
              ].join(' • ');

              final lineDeclared =
                  'Déclaré ($basisLabel) : $energyD kcal • $carbsD g glucides • $sodiumD mg sodium';

              final lineEffective =
                  'Effectif (prise) : $energyE kcal • $carbsE g glucides • $sodiumE mg sodium';

              final lineHydra = isHydration
                  ? 'Hydratation : $tablets pastille(s) • $powderG g poudre'
                  : null;

              final linked = m['activity_key'] != null;

              return Dismissible(
                key: ValueKey(key),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  color: Colors.red.withOpacity(0.15),
                  child: const Icon(Icons.delete),
                ),
                confirmDismiss: (_) async {
                  return await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Supprimer cette prise ?'),
                          content: const Text('Cette action est irréversible.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Annuler'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Supprimer'),
                            ),
                          ],
                        ),
                      ) ??
                      false;
                },
                onDismissed: (_) => box.delete(key),
                child: ListTile(
                  tileColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  title: Text('$brand — $product'),
                  subtitle: Text(
                    [
                      lineMeta,
                      lineDeclared,
                      lineEffective,
                      if (lineHydra != null) lineHydra,
                      linked ? '🔗 Associée à une activité' : '⚪ Non associée',
                    ].join('\n'),
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// --- Screen: Add activity ---
class ActivityFormScreen extends StatefulWidget {
  const ActivityFormScreen({super.key});

  @override
  State<ActivityFormScreen> createState() => _ActivityFormScreenState();
}

class _ActivityFormScreenState extends State<ActivityFormScreen> {
  Box get _box => Hive.box('activities');

  // --- State ---
  String _type = 'sortie_longue';
  int _rpe = 5;
  String _message = '';
  String _fmtStartAt(DateTime? dt) {
    if (dt == null) return 'Non défini';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  DateTime? _startAt;
  // --- GPX (échantillonnage 10 min) ---
  String? _gpxName;
  List<GpxPoint> _gpxSamples10m = const [];
  String _gpxMsg = '';

  // --- Weather (manual for now) ---
  final _tempCtrl = TextEditingController();
  final _feelsLikeCtrl = TextEditingController();
  final _humidityCtrl = TextEditingController();
  final _windCtrl = TextEditingController();
  final _precipCtrl = TextEditingController();

  final _tempMinCtrl = TextEditingController();
  final _tempMaxCtrl = TextEditingController();
  final _heatIndexCtrl = TextEditingController();
  final _windChillCtrl = TextEditingController();
  final _confidenceCtrl = TextEditingController(text: '1.0');

  final _durationCtrl = TextEditingController();
  final _distanceCtrl = TextEditingController();
  final _dplusCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  static const Map<String, String> _types = {
    'sortie_longue': 'Sortie longue',
    'fractionne': 'Fractionné',
    'competition': 'Compétition',
    'recup': 'Récupération',
  };

  @override
  void dispose() {
    _durationCtrl.dispose();
    _distanceCtrl.dispose();
    _dplusCtrl.dispose();
    _notesCtrl.dispose();

    _tempCtrl.dispose();
    _feelsLikeCtrl.dispose();
    _humidityCtrl.dispose();
    _windCtrl.dispose();
    _precipCtrl.dispose();
    _tempMinCtrl.dispose();
    _tempMaxCtrl.dispose();
    _heatIndexCtrl.dispose();
    _windChillCtrl.dispose();
    _confidenceCtrl.dispose();

    super.dispose();
  }

  int? _toInt(String s) => int.tryParse(s.trim());
  double? _toDouble(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
  double? _toDoubleOrNull(String s) {
    final t = s.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _startAt ?? now;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
    );

    if (picked == null) return;

    setState(() {
      final current = _startAt ?? now;
      _startAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        current.hour,
        current.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final initial = _startAt ?? now;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    );

    if (picked == null) return;

    setState(() {
      final current = _startAt ?? now;
      _startAt = DateTime(
        current.year,
        current.month,
        current.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _pickGpxAndSample10m() async {
    setState(() => _gpxMsg = '');

    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gpx'],
      withData: true, // important: on récupère les bytes
    );

    if (res == null || res.files.isEmpty) return;

    final file = res.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(
          () => _gpxMsg = 'Impossible de lire le fichier GPX (bytes null).');
      return;
    }

    final xml = utf8.decode(bytes, allowMalformed: true);

    try {
      final pts = parseGpxPoints(xml);
      final sampled = sampleEveryMinutes(pts, everyMinutes: 10);

      setState(() {
        _gpxName = file.name;
        _gpxSamples10m = sampled;
        _gpxMsg = '✅ GPX importé : ${sampled.length} point(s) (10 min)';
      });
    } catch (e) {
      setState(() => _gpxMsg = 'Erreur GPX : $e');
    }
  }

  Future<void> _save() async {
    final duration = _toInt(_durationCtrl.text);
    if (duration == null || duration <= 0) {
      setState(() => _message = 'Durée invalide');
      return;
    }
    if (_startAt == null) {
      setState(() => _message = 'Date/heure de départ manquante');
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final tsEnd = now + (duration * 60 * 1000);

    final weather = {
      'source': 'manual',
      'ts_start': now,
      'ts_end': tsEnd,
      'temp_c': _toDoubleOrNull(_tempCtrl.text),
      'feels_like_c': _toDoubleOrNull(_feelsLikeCtrl.text),
      'temp_min_c': _toDoubleOrNull(_tempMinCtrl.text),
      'temp_max_c': _toDoubleOrNull(_tempMaxCtrl.text),
      'heat_index_c': _toDoubleOrNull(_heatIndexCtrl.text),
      'wind_chill_c': _toDoubleOrNull(_windChillCtrl.text),
      'humidity_pct': _toDoubleOrNull(_humidityCtrl.text),
      'wind_kmh': _toDoubleOrNull(_windCtrl.text),
      'precip_mm': _toDoubleOrNull(_precipCtrl.text),
      'confidence': _toDoubleOrNull(_confidenceCtrl.text) ?? 1.0,
    };

    // 1) Construire l'activité "de base" (sans météo auto)
    final activity = <String, dynamic>{
      'ts': DateTime.now().millisecondsSinceEpoch,
      'start_at': _startAt?.toUtc().millisecondsSinceEpoch, // optionnel
      'type': _type,
      'duration_min': duration,
      'distance_km': _toDouble(_distanceCtrl.text),
      'dplus_m': _toInt(_dplusCtrl.text),
      'rpe': _rpe,
      'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),

      // 2) météo manuelle
      'weather_manual': {
        'temp_c': _toDouble(_tempCtrl.text),
        'feels_like_c': _toDouble(_feelsLikeCtrl.text),
        'humidity_pct': _toInt(_humidityCtrl.text),
        'wind_kph': _toDouble(_windCtrl.text),
        'precip_mm': _toDouble(_precipCtrl.text),
        'heat_index_c': _toDouble(_heatIndexCtrl.text),
        'wind_chill_c': _toDouble(_windChillCtrl.text),
        'confidence': _toDouble(_confidenceCtrl.text),
      },
    };

    // 3) Stocker la trace GPX échantillonnée (si dispo)
    activity['gpx_samples_10m'] = _gpxSamples10m
        .map((p) => {'ts': p.ts, 'lat': p.lat, 'lon': p.lon})
        .toList();

    // 4) Météo automatique (Open-Meteo) à partir des points GPX
    final client = OpenMeteoArchiveClient();
    final samples = <Map<String, dynamic>>[];

    for (final p in _gpxSamples10m) {
      final w = await client.fetchForPoint(
        ts: DateTime.fromMillisecondsSinceEpoch(p.ts, isUtc: true),
        lat: p.lat,
        lon: p.lon,
      );
      if (w != null) samples.add(w.toMap());
    }

    // 5) Stockage détaillé
    activity['weather_samples_10m'] = samples;

    // 6) Résumé simple pour l’historique (moyennes)
    double avg(List<double> xs) =>
        xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;

    final temps = samples
        .whereType<Map>()
        .map((m) => m['temp_c'])
        .whereType<num>()
        .map((v) => v.toDouble())
        .toList();
    final feels = samples
        .whereType<Map>()
        .map((m) => m['feels_like_c'])
        .whereType<num>()
        .map((v) => v.toDouble())
        .toList();
    final hums = samples
        .whereType<Map>()
        .map((m) => m['humidity_pct'])
        .whereType<num>()
        .map((v) => v.toDouble())
        .toList();
    final winds = samples
        .whereType<Map>()
        .map((m) => m['wind_kph'])
        .whereType<num>()
        .map((v) => v.toDouble())
        .toList();
    final precs = samples
        .whereType<Map>()
        .map((m) => m['precip_mm'])
        .whereType<num>()
        .map((v) => v.toDouble())
        .toList();

    activity['weather'] = {
      'temp_c': temps.isEmpty ? null : avg(temps),
      'feels_like_c': feels.isEmpty ? null : avg(feels),
      'humidity_pct': hums.isEmpty ? null : avg(hums).round(),
      'wind_kph': winds.isEmpty ? null : avg(winds),
      'precip_mm': precs.isEmpty ? null : avg(precs),
      'provider': 'open-meteo',
      'heat_index_c': null,
      'wind_chill_c': null,
    };

    debugPrint('ACTIVITY TO SAVE: $activity');

    await _box.add(activity);
    setState(() => _message = '✅ Activité enregistrée');

    _durationCtrl.clear(); // durée effort
    _distanceCtrl.clear(); // distance effort
    _dplusCtrl.clear(); // dénivelé effort
    _notesCtrl.clear(); // notes effort
    setState(() => _startAt = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajouter une activité'),
        actions: [
          IconButton(
            tooltip: 'Historique',
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ActivityHistoryScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _type,
            items: _types.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: (v) => setState(() => _type = v ?? 'sortie_longue'),
            decoration: const InputDecoration(labelText: 'Type d’effort'),
          ),
          const SizedBox(height: 12),
          Text('Départ : ${_fmtStartAt(_startAt)}'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today),
                  label: const Text('Date'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule),
                  label: const Text('Heure'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _durationCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Durée (minutes) *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _distanceCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Distance (km)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dplusCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'D+ (m)'),
          ),
          const SizedBox(height: 16),
          Text('RPE : $_rpe / 10'),
          Slider(
            value: _rpe.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            label: '$_rpe',
            onChanged: (v) => setState(() => _rpe = v.round()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes',
              hintText: 'Chaleur, fatigue, digestion…',
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Météo (manuel pour l’instant)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _tempCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Température (°C)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _feelsLikeCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Ressenti (°C)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _humidityCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Humidité (%)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _windCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Vent (km/h)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _precipCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Précipitations (mm)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _heatIndexCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Heat index (°C) (optionnel)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _windChillCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Wind chill (°C) (optionnel)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confidenceCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Confiance (0–1)'),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
                _gpxName == null ? 'GPX : aucun fichier' : 'GPX : $_gpxName'),
            subtitle: Text(
              _gpxSamples10m.isEmpty
                  ? 'Points 10 min : 0'
                  : 'Points 10 min : ${_gpxSamples10m.length}',
            ),
            trailing: OutlinedButton.icon(
              onPressed: () async {
                debugPrint('GPX: click');

                try {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: const ['gpx', 'xml'],
                    withData: true, // important sur Android
                  );

                  if (result == null) {
                    debugPrint('GPX: cancelled (result == null)');
                    return;
                  }

                  final file = result.files.single;

                  debugPrint(
                      'GPX: picked name=${file.name} path=${file.path} bytes=${file.bytes?.length}');

                  final bytes = file.bytes;
                  if (bytes == null) {
                    debugPrint(
                        'GPX: bytes == null (impossible de lire le fichier)');
                    return;
                  }

                  final xml = utf8.decode(bytes);
                  debugPrint('GPX: xml length=${xml.length}');

                  // ensuite ton parse + sampling
                } catch (e, st) {
                  debugPrint('GPX: ERROR $e');
                  debugPrint('$st');
                }
              },
              icon: const Icon(Icons.upload_file),
              label: const Text('Importer GPX'),
            ),
          ),
          if (_gpxMsg.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_gpxMsg),
          ],
          const SizedBox(height: 12),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _save,
            child: const Text('Enregistrer l’activité'),
          ),
          const SizedBox(height: 12),
          if (_message.isNotEmpty) Text(_message),
        ],
      ),
    );
  }
}

/// --- Screen: Activity history ---
class ActivityHistoryScreen extends StatelessWidget {
  const ActivityHistoryScreen({super.key});

  Box get _box => Hive.box('activities');

  String _formatTs(dynamic ts) {
    if (ts is! int) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String _label(String key) {
    switch (key) {
      case 'fractionne':
        return 'Fractionné';
      case 'competition':
        return 'Compétition';
      case 'recup':
        return 'Récupération';
      default:
        return 'Sortie longue';
    }
  }

  @override
  Widget build(BuildContext context) {
    print('>>> ActivityHistoryScreen BUILD <<<');
    return Scaffold(
      appBar: AppBar(title: const Text('Historique des activités')),
      body: ValueListenableBuilder(
        valueListenable: _box.listenable(),
        builder: (context, Box box, _) {
          if (box.isEmpty) {
            return const Center(child: Text('Aucune activité enregistrée.'));
          }

          final keys = box.keys.toList().reversed.toList();

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: keys.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final key = keys[i];
              final m = box.get(key);
              print('>>> ITEM BUILDER HIT <<<');
              print('ACTIVITY RAW: $m');

              if (m is! Map) {
                return ListTile(title: Text('Entrée invalide (clé: $key)'));
              }

              final title =
                  '${_formatTs(m['ts'])} • ${_label(m['type'])} • ${m['duration_min'] ?? "?"} min';

              final parts = <String>[
                if (m['distance_km'] != null) '${m['distance_km']} km',
                if (m['dplus_m'] != null) 'D+ ${m['dplus_m']} m',
                if (m['rpe'] != null) 'RPE ${m['rpe']}',
                if (m['notes'] != null) '📝 ${m['notes']}',
              ];

              // --- météo ---
              final weather = m['weather'];
              if (weather is Map) {
                final weatherParts = <String>[
                  if (weather['temp_c'] != null) 'T° ${weather['temp_c']}°C',
                  if (weather['feels_like_c'] != null)
                    'ress. ${weather['feels_like_c']}°C',
                  if (weather['humidity_pct'] != null)
                    'hum ${weather['humidity_pct']}%',
                  if (weather['wind_kph'] != null)
                    'vent ${weather['wind_kph']} km/h',
                  if (weather['precip_mm'] != null)
                    'pluie ${weather['precip_mm']} mm',
                  if (weather['heat_index_c'] != null &&
                      weather['heat_index_c'] != 0)
                    'heat ${weather['heat_index_c']}°C',
                  if (weather['wind_chill_c'] != null &&
                      weather['wind_chill_c'] != 0)
                    'chill ${weather['wind_chill_c']}°C',
                ];

                parts.add(
                  weatherParts.isEmpty
                      ? '🌦️ météo: —'
                      : '🌦️ ${weatherParts.join(' • ')}',
                );
              } else {
                parts.add('🌦️ météo: absente');
              }

              final subtitle = parts.join(' • ');

              return Dismissible(
                key: ValueKey(key),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  color: Colors.red.withOpacity(0.15),
                  child: const Icon(Icons.delete),
                ),
                onDismissed: (_) => box.delete(key),
                child: ListTile(
                  tileColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  title: Text(title),
                  subtitle: subtitle.isEmpty ? null : Text(subtitle),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
