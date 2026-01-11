import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io'; 
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GloveBoxApp());
}

// --- DATA MODELS ---
class FuelEntry {
  final DateTime date; final String gallons; final String price; final String odometer;
  FuelEntry({required this.date, required this.gallons, required this.price, required this.odometer});
  Map<String, dynamic> toJson() => {'date': date.toIso8601String(), 'gallons': gallons, 'price': price, 'odometer': odometer};
  factory FuelEntry.fromJson(Map<String, dynamic> json) => FuelEntry(date: DateTime.parse(json['date']), gallons: json['gallons'], price: json['price'], odometer: json['odometer'] ?? "0");
}

class ServiceEntry {
  final DateTime date; final String mileage; final String task;
  ServiceEntry({required this.date, required this.mileage, required this.task});
  Map<String, dynamic> toJson() => {'date': date.toIso8601String(), 'mileage': mileage, 'task': task};
  factory ServiceEntry.fromJson(Map<String, dynamic> json) => ServiceEntry(date: DateTime.parse(json['date']), mileage: json['mileage'], task: json['task']);
}

class GloveBoxApp extends StatelessWidget {
  const GloveBoxApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: const Color(0xFF121212), colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent, brightness: Brightness.dark), useMaterial3: true),
      home: const GarageScreen(),
    );
  }
}

class GarageScreen extends StatefulWidget {
  const GarageScreen({super.key});
  @override State<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends State<GarageScreen> {
  String savedCarName = ""; String savedMileage = "0"; String savedVIN = "";
  String? bannerImagePath; String currentAvgMpg = "--";
  Map<String, String> photoPaths = {};
  double lastOilChangeAt = 0.0; double lastTireRotationAt = 0.0;
  final ImagePicker _picker = ImagePicker();
  Map<String, String> walletPaths = {};

  @override void initState() { super.initState(); _loadAllData(); }

  Future<void> _loadAllData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      savedCarName = prefs.getString('carName') ?? "2022 Ford Mustang";
      savedMileage = prefs.getString('mileage') ?? "0";
      savedVIN = prefs.getString('carVIN') ?? "";
      bannerImagePath = prefs.getString('bannerImage'); 
      lastOilChangeAt = prefs.getDouble('lastOilChange') ?? 0.0;
      lastTireRotationAt = prefs.getDouble('lastTireRotation') ?? 0.0;
      String? photosJson = prefs.getString('conditionPhotos');
      if (photosJson != null) photoPaths = Map<String, String>.from(json.decode(photosJson));

      final List<String>? fuelStored = prefs.getStringList('fuelHistory');
      if (fuelStored != null && fuelStored.length >= 2) {
        final history = fuelStored.map((e) => FuelEntry.fromJson(json.decode(e))).toList();
        double miles = (double.tryParse(history.first.odometer) ?? 0) - (double.tryParse(history.last.odometer) ?? 0);
        double gals = history.take(history.length - 1).fold(0.0, (sum, item) => sum + (double.tryParse(item.gallons) ?? 0));
        if (gals > 0 && miles > 0) currentAvgMpg = (miles / gals).toStringAsFixed(1);
      }
    });
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) debugPrint("Error");
  }

  Future<void> _resetService(String type) async {
    double current = double.tryParse(savedMileage) ?? 0.0;
    final prefs = await SharedPreferences.getInstance();
    setState(() { 
      if (type == "Oil") { lastOilChangeAt = current; } else { lastTireRotationAt = current; }
    });
    await prefs.setDouble(type == "Oil" ? 'lastOilChange' : 'lastTireRotation', current);
  }

  Future<void> _pickImageFor(String label) async {
    showModalBottomSheet(context: context, builder: (context) => SafeArea(
      child: Wrap(children: [
        ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Camera'), onTap: () async {
          final img = await _picker.pickImage(source: ImageSource.camera);
          if (img != null) _updatePhoto(label, img.path);
          if (context.mounted) Navigator.pop(context);
        }),
        ListTile(leading: const Icon(Icons.photo_library), title: const Text('Gallery (Upload)'), onTap: () async {
          final img = await _picker.pickImage(source: ImageSource.gallery);
          if (img != null) _updatePhoto(label, img.path);
          if (context.mounted) Navigator.pop(context);
        }),
      ])),
    );
  }

  Future<void> _updatePhoto(String label, String path) async {
    setState(() => photoPaths[label] = path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('conditionPhotos', json.encode(photoPaths));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GLOVEBOX'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(children: [
          Container(
            clipBehavior: Clip.hardEdge, width: double.infinity, height: 180,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3))),
            child: Stack(children: [
              if (bannerImagePath != null) Positioned.fill(child: Image.file(File(bannerImagePath!), fit: BoxFit.cover)),
              Container(color: Colors.black.withValues(alpha: 0.4)),
              Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(savedCarName.toUpperCase(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                Text("$savedMileage MILES", style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 24)),
                const SizedBox(height: 8),
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.auto_graph, color: Colors.greenAccent, size: 14),
                    const SizedBox(width: 4),
                    Text("$currentAvgMpg AVG MPG", style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                  ]),
                )
              ])),
            ]),
          ),
          const SizedBox(height: 25),
          Wrap(alignment: WrapAlignment.spaceEvenly, spacing: 12, runSpacing: 15, children: [
            _mainBtn(Icons.local_gas_station, "FUEL LOG", () => Navigator.push(context, MaterialPageRoute(builder: (context) => const FuelLogScreen())).then((_) => _loadAllData()), Colors.purpleAccent),
            _mainBtn(Icons.build_circle, "SERVICES", () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MaintenanceLogScreen())), Colors.redAccent),
            _mainBtn(Icons.list_alt, "SPECS", () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SpecsScreen())), Colors.orangeAccent),
            _mainBtn(Icons.map, "MAPS", () => _launchUrl("https://www.google.com/maps/search/auto+repair+near+me"), Colors.blue),
            _mainBtn(Icons.menu_book, "MANUAL", () => _launchUrl("https://www.google.com/search?q=$savedCarName+owners+manual+pdf"), Colors.tealAccent),
            _mainBtn(Icons.assignment, "CARFAX", () => _launchUrl("https://www.carfax.com/vin/$savedVIN"), Colors.blueAccent),
            _mainBtn(Icons.account_balance_wallet, "WALLET", () => Navigator.push(context, MaterialPageRoute(builder: (context) => const WalletScreen())), Colors.amberAccent),
          ]),
          const SizedBox(height: 25),
          const Align(alignment: Alignment.centerLeft, child: Text("MAINTENANCE STATUS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey))),
          const SizedBox(height: 10),
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(15)),
            child: Column(children: [
              _serviceBar("Oil Change", lastOilChangeAt, 5000, "Oil"),
              _serviceBar("Tire Rotation", lastTireRotationAt, 6000, "Tire")
            ])),
          const SizedBox(height: 25),
          const Align(alignment: Alignment.centerLeft, child: Text("CONDITION RECORD", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey))),
          const SizedBox(height: 10),
          GridView.count(crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 8, crossAxisSpacing: 8, 
            children: ["FRONT", "REAR", "LEFT", "RIGHT", "INTERIOR", "ENGINE"].map((label) => _photoSquare(label)).toList()),
          const SizedBox(height: 25),
          TextButton.icon(onPressed: () {}, icon: const Icon(Icons.swap_horiz, color: Colors.redAccent, size: 14), label: const Text("REPLACE VEHICLE", style: TextStyle(color: Colors.redAccent, fontSize: 10))),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _mainBtn(IconData icon, String label, VoidCallback onTap, Color color) {
    return InkWell(onTap: onTap, child: Column(children: [CircleAvatar(backgroundColor: color.withValues(alpha: 0.1), child: Icon(icon, color: color, size: 20)), const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold))]));
  }

  Widget _serviceBar(String title, double lastAt, double interval, String type) {
    double current = double.tryParse(savedMileage) ?? 0.0;
    double progress = ((current - lastAt) / interval).clamp(0.0, 1.0);
    
    // 1. Calculate the miles left
    int remaining = (interval - (current - lastAt)).toInt();
    
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        GestureDetector(
          onTap: () => _resetService(type), 
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              // 2. This uses 'remaining' and puts (RESET) in parentheses
              remaining <= 0 ? "RESET NOW" : "$remaining MI (RESET)", 
              style: TextStyle(
                color: remaining <= 0 ? Colors.redAccent : Colors.blueAccent, 
                fontWeight: FontWeight.bold, 
                fontSize: 10
              ),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      LinearProgressIndicator(
        value: progress, 
        minHeight: 8, 
        borderRadius: BorderRadius.circular(4), 
        color: progress > 0.9 ? Colors.redAccent : Colors.blueAccent,
      ),
      const SizedBox(height: 12),
    ]);
  }

  Widget _photoSquare(String label) {
    bool hasImage = photoPaths.containsKey(label);
    return GestureDetector(onTap: () => _pickImageFor(label), child: Container(decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(12), image: hasImage ? DecorationImage(image: FileImage(File(photoPaths[label]!)), fit: BoxFit.cover) : null), 
       child: !hasImage ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.add_a_photo, size: 16, color: Colors.blueAccent), Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold))]) : null));
  }
}

// --- FUEL LOG ---
class FuelLogScreen extends StatefulWidget {
  const FuelLogScreen({super.key});
  @override State<FuelLogScreen> createState() => _FuelLogScreenState();
}

class _FuelLogScreenState extends State<FuelLogScreen> {
  List<FuelEntry> fuelHistory = [];
  final TextEditingController _gallons = TextEditingController();
  final TextEditingController _price = TextEditingController();
  final TextEditingController _odo = TextEditingController();

  @override void initState() { super.initState(); _loadFuel(); }

  Future<void> _loadFuel() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? stored = prefs.getStringList('fuelHistory');
    if (stored != null) setState(() { fuelHistory = stored.map((e) => FuelEntry.fromJson(json.decode(e))).toList(); });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("FUEL LOG")),
      floatingActionButton: FloatingActionButton(backgroundColor: Colors.purpleAccent, onPressed: () {
        showDialog(context: context, builder: (context) => AlertDialog(title: const Text("New Fuel Entry"), content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _odo, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Odometer")),
          TextField(controller: _gallons, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Gallons")),
          TextField(controller: _price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Total Cost")),
        ]), actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(onPressed: () async {
            final odo = _odo.text;
            setState(() { fuelHistory.insert(0, FuelEntry(date: DateTime.now(), gallons: _gallons.text, price: _price.text, odometer: odo)); });
            final prefs = await SharedPreferences.getInstance();
            await prefs.setStringList('fuelHistory', fuelHistory.map((e) => json.encode(e.toJson())).toList());
            await prefs.setString('mileage', odo);
            if (context.mounted) Navigator.pop(context);
          }, child: const Text("Save"))
        ]));
      }, child: const Icon(Icons.add)),
      body: ListView.builder(itemCount: fuelHistory.length, itemBuilder: (context, index) {
        final entry = fuelHistory[index];
        return Card(color: const Color(0xFF1E1E1E), margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: ListTile(
          title: Text("${entry.gallons} Gal - \$${entry.price}"), subtitle: Text("Odo: ${entry.odometer}"),
        ));
      }),
    );
  }
}

// --- SERVICE LOG ---
class MaintenanceLogScreen extends StatefulWidget {
  const MaintenanceLogScreen({super.key});
  @override State<MaintenanceLogScreen> createState() => _MaintenanceLogScreenState();
}

class _MaintenanceLogScreenState extends State<MaintenanceLogScreen> {
  List<ServiceEntry> history = [];
  final TextEditingController _task = TextEditingController();
  final TextEditingController _odo = TextEditingController();

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? stored = prefs.getStringList('serviceHistory');
    if (stored != null) setState(() { history = stored.map((e) => ServiceEntry.fromJson(json.decode(e))).toList(); });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("SERVICE HISTORY")),
      floatingActionButton: FloatingActionButton(backgroundColor: Colors.redAccent, onPressed: () {
        showDialog(context: context, builder: (context) => AlertDialog(title: const Text("New Service"), content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _odo, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Odometer")),
          TextField(controller: _task, decoration: const InputDecoration(labelText: "Service Description")),
        ]), actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(onPressed: () async {
            setState(() { history.insert(0, ServiceEntry(date: DateTime.now(), mileage: _odo.text, task: _task.text)); });
            final prefs = await SharedPreferences.getInstance();
            await prefs.setStringList('serviceHistory', history.map((e) => json.encode(e.toJson())).toList());
            if (context.mounted) Navigator.pop(context);
          }, child: const Text("Save"))
        ]));
      }, child: const Icon(Icons.add)),
      body: ListView.builder(itemCount: history.length, itemBuilder: (context, index) {
        final entry = history[index];
        return ListTile(title: Text(entry.task), subtitle: Text("${entry.mileage} miles - ${entry.date.month}/${entry.date.day}/${entry.date.year}"));
      }),
    );
  }
}

// --- SPECS SCREEN ---
class SpecsScreen extends StatefulWidget {
  const SpecsScreen({super.key});
  @override State<SpecsScreen> createState() => _SpecsScreenState();
}

class _SpecsScreenState extends State<SpecsScreen> {
  Map<String, String> specs = {};
  final List<String> fields = ["Engine", "Horsepower", "Torque", "Tires", "Oil Type", "Spark Plugs"];

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    String? stored = prefs.getString('carSpecs');
    if (stored != null) setState(() { specs = Map<String, String>.from(json.decode(stored)); });
  }

  Future<void> _save(String key, String value) async {
    specs[key] = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('carSpecs', json.encode(specs));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("VEHICLE SPECS")),
      body: ListView(padding: const EdgeInsets.all(16), children: fields.map((field) => ListTile(
        title: Text(field, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        subtitle: TextField(
          decoration: InputDecoration(hintText: "Enter $field..."),
          controller: TextEditingController(text: specs[field]),
          onSubmitted: (val) => _save(field, val),
        ),
      )).toList()),
    );
  }
}

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});
  @override State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  Map<String, String> walletPaths = {};
  final ImagePicker _picker = ImagePicker();

  @override void initState() {
    super.initState();
    _loadWallet();
  }

  Future<void> _loadWallet() async {
    final prefs = await SharedPreferences.getInstance();
    String? stored = prefs.getString('walletDocs');
    if (stored != null) {
      setState(() { walletPaths = Map<String, String>.from(json.decode(stored)); });
    }
  }

  Future<void> _pickDoc(String label) async {
    showModalBottomSheet(context: context, builder: (context) => SafeArea(
      child: Wrap(children: [
        ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Scan with Camera'), onTap: () async {
          final img = await _picker.pickImage(source: ImageSource.camera);
          if (img != null) _saveDoc(label, img.path);
          if (context.mounted) Navigator.pop(context);
        }),
        ListTile(leading: const Icon(Icons.photo_library), title: const Text('Upload from Gallery'), onTap: () async {
          final img = await _picker.pickImage(source: ImageSource.gallery);
          if (img != null) _saveDoc(label, img.path);
          if (context.mounted) Navigator.pop(context);
        }),
      ])),
    );
  }

  Future<void> _saveDoc(String label, String path) async {
    setState(() { walletPaths[label] = path; });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('walletDocs', json.encode(walletPaths));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("DOCUMENTS WALLET")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _docCard("Insurance Card"),
          const SizedBox(height: 15),
          _docCard("Registration"),
          const SizedBox(height: 15),
          _docCard("Triple A / Roadside"),
          const SizedBox(height: 15),
          _docCard("Other Document"),
        ],
      ),
    );
  }

  Widget _docCard(String label) {
    bool hasFile = walletPaths.containsKey(label);
    return GestureDetector(
      onTap: () => _pickDoc(label),
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white10),
          image: hasFile ? DecorationImage(image: FileImage(File(walletPaths[label]!)), fit: BoxFit.contain) : null,
        ),
        child: !hasFile ? Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_a_photo, color: Colors.amberAccent, size: 40),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ],
        ) : Align(
          alignment: Alignment.bottomRight,
          child: Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.all(5),
            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
            child: const Icon(Icons.edit, size: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }
}