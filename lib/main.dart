import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'weather_gpx_tools.dart';
import 'weather_service.dart';
import 'dart:convert';

import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('intakes');
  await Hive.openBox('activities');
  await Hive.openBox('weather_cache');
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
  Map<String, dynamic>? _ocrDetected;

  bool _ocrPending = false; // indique qu'on a une détection à valider

  final _picker = ImagePicker();
  String? _labelPhotoBase64; // photo emballage (base64)
  String? _labelPhotoPath; // chemin local (temp) pour OCR
  String _labelOcrText = ''; // texte brut OCR

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

  Future<void> _takeLabelPhoto() async {
    try {
      final x = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (x == null) return;

      final bytes = await x.readAsBytes();
      final b64 = base64Encode(bytes);

      setState(() {
        _labelPhotoBase64 = b64;
        _labelPhotoPath = x.path;
        _labelOcrText = '⏳ OCR en cours…';
        _message = '📷 Photo ajoutée';
      });

      // OCR local (ML Kit)
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final input = InputImage.fromFilePath(x.path);
        final result = await recognizer.processImage(input);

        if (!mounted) return;

        final raw = result.text.trim();
        final found = _extractNutritionFromOcr(raw);

        setState(() {
          _labelOcrText = raw.isEmpty ? '⚠️ Aucun texte détecté.' : raw;

          // on garde les valeurs détectées pour validation
          _ocrDetected = {
            'brand': found['brand'],
            'product': found['product'],
            'serving_size_g': found['serving_size_g'],
            'weight_g': found['weight_g'],
            'kcal': found['kcal'],
            'fat_g': found['fat_g'],
            'carbs_g': found['carbs_g'],
            'fiber_g': found['fiber_g'],
            'protein_g': found['protein_g'],
            'sodium_mg': found['sodium_mg'],
            'chloride_mg': found['chloride_mg'],
            'potassium_mg': found['potassium_mg'],
            'calcium_mg': found['calcium_mg'],
            'magnesium_mg': found['magnesium_mg'],
            'iron_mg': found['iron_mg'],
            'vit_c_mg': found['vit_c_mg'],
            'vit_b12_mcg': found['vit_b12_mcg'],
            'vit_b6_mg': found['vit_b6_mg'],
            'vit_b2_mg': found['vit_b2_mg'],
            'tablets_count': found['tablets_count'],
            'powder_g': found['powder_g'],
          };
          _ocrPending = raw.isNotEmpty;
        });
      } finally {
        await recognizer.close();
      }
    } catch (e) {
      setState(() => _message = 'Erreur caméra/OCR: $e');
    }
  }

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
      'source': 'manual',
      'label_photo_b64': _labelPhotoBase64,
      'label_text_ocr': _labelOcrText,

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
    _labelPhotoBase64 = null;
    _labelPhotoPath = null;
    _labelOcrText = '';

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

  Map<String, double?> _extractNutritionFromOcr(String raw) {
    // Normalisation simple
    final t = raw
        .replaceAll('\u00A0', ' ')
        .replaceAll(',', '.') // virgule -> point
        .toLowerCase();

    double? pick(RegExp re) {
      final m = re.firstMatch(t);
      if (m == null) return null;
      final s = m.group(1);
      if (s == null) return null;
      return double.tryParse(s);
    }

    // kcal / énergie
    // Ex: "énergie 250 kcal", "250kcal"
    final kcal = pick(RegExp(r'(\d+(?:\.\d+)?)\s*kcal'));

    // glucides
    // Ex: "glucides 30 g", "carbohydrates 30g"
    final carbs = pick(RegExp(
        r'(?:glucides|carbohydrates)\s*(?:[:\-]?\s*)?(\d+(?:\.\d+)?)\s*g'));

    // sodium (mg)
    // Ex: "sodium 300 mg"
    final sodiumMg =
        pick(RegExp(r'sodium\s*(?:[:\-]?\s*)?(\d+(?:\.\d+)?)\s*mg'));

    return {
      'kcal': kcal,
      'carbs_g': carbs,
      'sodium_mg': sodiumMg,
    };
  }

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
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _takeLabelPhoto,
            icon: const Icon(Icons.photo_camera),
            label: Text(_labelPhotoBase64 == null
                ? 'Prendre une photo (informations nutritionnelles)'
                : 'Reprendre la photo'),
          ),
          if (_labelPhotoBase64 != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                base64Decode(_labelPhotoBase64!),
                height: 180,
                fit: BoxFit.cover,
              ),
            ),
            if (_labelOcrText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _labelOcrText,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
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
  Box get _weatherCache => Hive.box('weather_cache');

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

  // --- Barre de Progression météo ---
  bool _weatherRunning = false;
  int _weatherDone = 0;
  int _weatherTotal = 0;

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

  Future<void> _importGpx() async {
    setState(() => _gpxMsg = '');

    FilePickerResult? res;
    try {
      res = await FilePicker.platform.pickFiles(
        type: FileType.any, // contourne le filtre Android
        withData: true,
      );
    } on PlatformException catch (e, st) {
      debugPrint('GPX: PlatformException ${e.code} ${e.message}');
      debugPrint('$st');
      setState(() => _gpxMsg = 'Erreur FilePicker (${e.code}) : ${e.message}');
      return;
    } catch (e, st) {
      debugPrint('GPX: FilePicker ERROR $e');
      debugPrint('$st');
      setState(() => _gpxMsg = 'Erreur FilePicker: $e');
      return;
    }

    if (res == null || res.files.isEmpty) {
      setState(() => _gpxMsg = 'Import annulé.');
      return;
    }

    final file = res.files.first;
    final name = file.name.toLowerCase(); // contrôle de l'extension
    if (!name.endsWith('.gpx')) {
      setState(
          () => _gpxMsg = 'Fichier non supporté: ${file.name} (attendu: .gpx)');
      return;
    }

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
    } catch (e, st) {
      debugPrint('GPX: PARSE ERROR $e');
      debugPrint('$st');
      setState(() => _gpxMsg = 'Erreur GPX : $e');
    }
  }

  Future<void> _save() async {
    final duration = _toInt(_durationCtrl.text);
    if (duration == null || duration <= 0) {
      setState(() => _message = 'Durée invalide');
      return;
    }

    // 1) Activité de base
    final activity = <String, dynamic>{
      'ts': DateTime.now().millisecondsSinceEpoch,
      'type': _type,
      'duration_min': duration,
      'distance_km': _toDouble(_distanceCtrl.text),
      'dplus_m': _toInt(_dplusCtrl.text),
      'rpe': _rpe,
      'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      'start_at_ms': _startAt?.millisecondsSinceEpoch,

      // GPX (si présent)
      'gpx_name': _gpxName,
      'gpx_samples_10m': _gpxSamples10m
          .map((p) => {'ts': p.ts, 'lat': p.lat, 'lon': p.lon})
          .toList(),

      // météo : placeholders (remplis plus bas si GPX présent)
      'weather': null,
      'weather_samples_10m': <Map<String, dynamic>>[],
      'weather_status': _gpxSamples10m.isNotEmpty ? 'pending' : 'none',
      'weather_error': null,
    };

    // Enregistre tout de suite (sans bloquer l'UI)
    final activityKey = await _box.add(activity);
    setState(
        () => _message = '✅ Activité enregistrée • 🌦️ Calcul météo en cours…');

    // calcule la météo en "tâche de fond" et met à jour l'entrée existante
    if (_gpxSamples10m.isNotEmpty) {
      Future(() async {
        try {
          final service = WeatherService();

          if (!mounted) return;
          setState(() {
            _weatherRunning = true;
            _weatherDone = 0;
            _weatherTotal = _gpxSamples10m.length; // total attendu
          });

          await Future.delayed(const Duration(milliseconds: 500));

          await service.computeAndAttachWeather(
            activityKey: activityKey,
            gpxSamples10m: _gpxSamples10m,
            onProgress: (done, total) {
              if (!mounted) return;
              setState(() {
                _weatherRunning = true;
                _weatherDone = done;
                _weatherTotal = total;
              });
            },
          );

          if (!mounted) return;
          setState(() {
            _weatherRunning = false;
            _message = '✅ Activité enregistrée + météo OK';
          });
        } catch (e, st) {
          debugPrint('WEATHER: ERROR $e');
          debugPrint('$st');

          final stored = _box.get(activityKey);
          if (stored is Map) {
            final updated = Map<String, dynamic>.from(stored);
            updated['weather_status'] = 'error';
            updated['weather_error'] = e.toString();
            await _box.put(activityKey, updated);
          }

          setState(() {
            _weatherRunning = false;
            _weatherDone = 0;
            _weatherTotal = 0;
            _message = '⚠️ Activité OK, météo en erreur: $e';
          });
        }
      });
    }
  } // Fin save()

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
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              _gpxName == null ? 'GPX : aucun fichier' : 'GPX : $_gpxName',
            ),
            subtitle: Text(
              _gpxSamples10m.isEmpty
                  ? 'Points 10 min : 0'
                  : 'Points 10 min : ${_gpxSamples10m.length}',
            ),
            trailing: OutlinedButton.icon(
              onPressed: _importGpx,
              icon: const Icon(Icons.upload_file),
              label: const Text('Importer GPX'),
            ),
          ),
          if (_gpxMsg.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_gpxMsg),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _save,
            child: const Text('Enregistrer l’activité'),
          ),
          if (_weatherRunning) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value:
                  (_weatherTotal <= 0) ? null : (_weatherDone / _weatherTotal),
            ),
            const SizedBox(height: 6),
            Text('Météo : $_weatherDone / $_weatherTotal'),
          ],
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
              String _f1(num v) => v.toStringAsFixed(1); //arrondi au dixième

              final weather = m['weather'];
              if (weather is Map) {
                final weatherParts = <String>[
                  if (weather['temp_c'] != null)
                    'T° ${_f1(weather['temp_c'])}°C',
                  if (weather['feels_like_c'] != null)
                    'ress. ${_f1(weather['feels_like_c'])}°C',
                  if (weather['humidity_pct'] != null)
                    'hum ${weather['humidity_pct']}%',
                  if (weather['wind_kph'] != null)
                    'vent ${_f1(weather['wind_kph'])} km/h',
                  if (weather['precip_mm'] != null)
                    'pluie ${_f1(weather['precip_mm'])} mm',
                ];
              } else {
                final status = m['weather_status'];
                if (status == 'running') {
                  parts.add('🌦️ météo: calcul…');
                } else if (status == 'ok') {
                  parts.add(
                      '🌦️ météo: —'); // cas rare: ok mais pas de map météo
                } else if (status == 'error') {
                  parts.add('🌦️ météo: erreur');
                } else {
                  parts.add('🌦️ météo: absente');
                }
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
                confirmDismiss: (_) async {
                  return await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Supprimer cette activité ?'),
                          content: const Text('Cette action est définitive.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Annuler'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Supprimer'),
                            ),
                          ],
                        ),
                      ) ??
                      false;
                },
                onDismissed: (_) => box.delete(key),
                child: ListTile(
                  tileColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  title: Text(title),
                  subtitle: subtitle.isEmpty ? null : Text(subtitle),
                  isThreeLine: true,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ActivityDetailScreen(
                          activity: Map<String, dynamic>.from(m as Map),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// --- Screen: Activity detail ---
class ActivityDetailScreen extends StatelessWidget {
  const ActivityDetailScreen({super.key, required this.activity});

  final Map<String, dynamic> activity;

  String _fmtTs(int? ts) {
    if (ts == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final ts = activity['ts'] as int?;
    final type = (activity['type'] ?? '').toString();
    final dur = activity['duration_min'];
    final dist = activity['distance_km'];
    final dplus = activity['dplus_m'];
    final rpe = activity['rpe'];

    final weather = activity['weather'];
    final samples = activity['weather_samples_10m'];
    final gpx = activity['gpx_samples_10m'];

    final temp = (weather is Map) ? weather['temp_c'] : null;
    final feels = (weather is Map) ? weather['feels_like_c'] : null;
    final hum = (weather is Map) ? weather['humidity_pct'] : null;
    final wind = (weather is Map) ? weather['wind_kph'] : null;
    final rain = (weather is Map) ? weather['precip_mm'] : null;

    final weatherLine = (weather is Map)
        ? [
            if (temp != null) 'T° ${_asDouble(temp).toStringAsFixed(1)}°C',
            if (feels != null) 'ress. ${_asDouble(feels).toStringAsFixed(1)}°C',
            if (hum != null) 'hum $hum%',
            if (wind != null) 'vent ${_asDouble(wind).toStringAsFixed(1)} km/h',
            if (rain != null) 'pluie ${_asDouble(rain).toStringAsFixed(1)} mm',
          ].join(' • ')
        : '—';

    final samplesCount = (samples is List) ? samples.length : 0;
    final gpxCount = (gpx is List) ? gpx.length : 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Détail activité')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${_fmtTs(ts)} • $type • ${dur ?? "?"} min',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _kv('Distance', dist == null ? '—' : '$dist km'),
          _kv('D+', dplus == null ? '—' : '$dplus m'),
          _kv('RPE', rpe == null ? '—' : '$rpe / 10'),
          const SizedBox(height: 16),
          const Text(
            'Météo moyenne (Open-Meteo)',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(weatherLine.isEmpty ? '—' : weatherLine),
          const SizedBox(height: 12),
          _kv('Échantillons météo (10 min)', '$samplesCount'),
          _kv('Points GPX (10 min)', '$gpxCount'),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 170, child: Text(k)),
            Expanded(child: Text(v)),
          ],
        ),
      );
}
