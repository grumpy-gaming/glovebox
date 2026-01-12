import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// --- NOTIFICATION SERVICE ---
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notifications.initialize(initSettings);
    
    // Request permission for Android 13+ (RAZR Fix)
    await _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> showAlert(String title, String body, bool isStealth) async {
    // Stealth Mode logic: Subtle vs High Alert
    String displayTitle = isStealth ? "System Sync" : title;
    String displayBody = isStealth ? "Background data refresh complete." : body;

    var androidDetails = AndroidNotificationDetails(
      'service_reminders', 
      'Service Reminders',
      channelDescription: 'Alerts for oil and tire maintenance',
      importance: isStealth ? Importance.low : Importance.max,
      priority: isStealth ? Priority.low : Priority.high,
      ticker: 'ticker',
    );

    var details = NotificationDetails(android: androidDetails);
    await _notifications.show(0, displayTitle, displayBody, details);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init(); // Initialize the ringer
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

class GloveBoxApp extends StatefulWidget {
  const GloveBoxApp({super.key});
  @override State<GloveBoxApp> createState() => _GloveBoxAppState();
}

class _GloveBoxAppState extends State<GloveBoxApp> {
  bool isStealthMode = false; 
  void toggleTheme() { setState(() { isStealthMode = !isStealthMode; }); }

  @override
  Widget build(BuildContext context) {
    Color primaryAccent = isStealthMode ? Colors.grey : Colors.blueAccent;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark, 
        scaffoldBackgroundColor: const Color(0xFF121212), 
        colorScheme: ColorScheme.fromSeed(seedColor: primaryAccent, brightness: Brightness.dark), 
        useMaterial3: true
      ),
      home: GarageScreen(onThemeToggle: toggleTheme, isStealth: isStealthMode),
    );
  }
}

class GarageScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;
  final bool isStealth;
  const GarageScreen({super.key, required this.onThemeToggle, required this.isStealth});
  @override State<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends State<GarageScreen> {
  String savedCarName = ""; String savedMileage = ""; String savedVIN = ""; String purchaseDateStr = "";
  String userEmail = ""; String? bannerImagePath; 
  Map<String, String> photoPaths = {}; Map<String, String> engineParts = {};
  double lastOilChangeAt = 0.0; double lastTireRotationAt = 0.0;
  double oilInterval = 5000.0; double tireInterval = 6000.0;
  final ImagePicker _picker = ImagePicker();
  bool _setupShown = false; 
  bool _isLoading = true; 

  @override void initState() { super.initState(); _loadAllData(); }

  Future<void> _loadAllData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      savedCarName = prefs.getString('carName') ?? "";
      savedMileage = prefs.getString('mileage') ?? "";
      savedVIN = prefs.getString('carVIN') ?? "";
      purchaseDateStr = prefs.getString('purchaseDate') ?? "";
      userEmail = prefs.getString('userEmail') ?? "";
      bannerImagePath = prefs.getString('bannerImage'); 
      lastOilChangeAt = prefs.getDouble('lastOilChange') ?? 0.0;
      lastTireRotationAt = prefs.getDouble('lastTireRotation') ?? 0.0;
      oilInterval = prefs.getDouble('oilInterval') ?? 5000.0;
      tireInterval = prefs.getDouble('tireInterval') ?? 6000.0;
      String? photosJson = prefs.getString('conditionPhotos');
      if (photosJson != null) { photoPaths = Map<String, String>.from(json.decode(photosJson)); }
      String? partsJson = prefs.getString('engineParts');
      if (partsJson != null) { engineParts = Map<String, String>.from(json.decode(partsJson)); }
      _isLoading = false; 
    });
    _checkServiceStatus(); // Check for alerts after data is loaded
  }

  // --- THE BRAINS OF THE NOTIFICATION ---
  Future<void> _checkServiceStatus() async {
    double current = double.tryParse(savedMileage) ?? 0.0;
    
    // Oil Alert (500 mile warning)
    if (current > 0 && (current - lastOilChangeAt) >= (oilInterval - 500)) {
      int dueIn = (oilInterval - (current - lastOilChangeAt)).toInt();
      NotificationService.showAlert(
        "Maintenance Alert", 
        dueIn <= 0 ? "Oil Change is OVERDUE!" : "Oil Change due in $dueIn miles.",
        widget.isStealth
      );
    }
  }

  void _showSetupDialog() {
    if (_setupShown) return;
    _setupShown = true;
    String tempVin = ""; String tempCarName = ""; String tempOdo = ""; String tempEmail = "";
    DateTime tempDate = DateTime.now(); int currentStep = 1; bool isSearching = false;

    showDialog(context: context, barrierDismissible: false, builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
          if (currentStep == 1) { 
            return AlertDialog(title: const Text("VEHICLE SETUP"), content: TextField(textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: "Enter VIN Number"), onChanged: (val) { tempVin = val; }), actions: [
                ElevatedButton(onPressed: isSearching ? null : () async {
                  if (tempVin.isNotEmpty) {
                    setDialogState(() => isSearching = true);
                    try {
                      final url = 'https://vpic.nhtsa.dot.gov/api/vehicles/decodevin/$tempVin?format=json';
                      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
                      if (response.statusCode == 200) {
                        final data = json.decode(response.body);
                        final results = data['Results'] as List;
                        String year = results.firstWhere((e) => e['Variable'] == 'Model Year', orElse: () => {'Value': ''})['Value'] ?? "";
                        String make = results.firstWhere((e) => e['Variable'] == 'Make', orElse: () => {'Value': ''})['Value'] ?? "";
                        String model = results.firstWhere((e) => e['Variable'] == 'Model', orElse: () => {'Value': ''})['Value'] ?? "";
                        setDialogState(() { tempCarName = "$year $make $model".trim(); currentStep = 2; });
                      }
                    } catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Connection Error")));
                    } finally { setDialogState(() => isSearching = false); }
                  }
                }, child: isSearching ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text("FIND CAR"))
              ]);
          }
          if (currentStep == 2) { 
            return AlertDialog(title: const Text("CONFIRM VEHICLE"), content: Text(tempCarName.isEmpty ? "Unknown Vehicle" : tempCarName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: widget.isStealth ? Colors.white70 : Colors.blueAccent)), actions: [
                TextButton(onPressed: () { setDialogState(() { currentStep = 1; }); }, child: const Text("BACK")),
                ElevatedButton(onPressed: () { setDialogState(() { currentStep = 3; }); }, child: const Text("YES, THAT'S IT")),
              ]);
          }
          return AlertDialog(title: const Text("FINAL DETAILS"), content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Current Odometer"), onChanged: (val) { tempOdo = val; }),
              TextField(keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: "Reminder Email"), onChanged: (val) { tempEmail = val; }),
              ListTile(title: const Text("Purchase Date", style: TextStyle(fontSize: 14)), subtitle: Text("${tempDate.month}/${tempDate.day}/${tempDate.year}"), trailing: const Icon(Icons.calendar_today), onTap: () async {
                  final picked = await showDatePicker(context: context, initialDate: tempDate, firstDate: DateTime(1900), lastDate: DateTime.now());
                  if (picked != null) { setDialogState(() { tempDate = picked; }); }
                }),
            ]), actions: [
              ElevatedButton(onPressed: () async {
                if (tempOdo.isNotEmpty) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('carName', tempCarName); await prefs.setString('mileage', tempOdo);
                  await prefs.setString('carVIN', tempVin.toUpperCase().trim()); await prefs.setString('purchaseDate', tempDate.toIso8601String()); await prefs.setString('userEmail', tempEmail);
                  setState(() { savedCarName = tempCarName; savedMileage = tempOdo; savedVIN = tempVin.toUpperCase().trim(); purchaseDateStr = tempDate.toIso8601String(); userEmail = tempEmail; });
                  if (context.mounted) { Navigator.of(context, rootNavigator: true).pop(); }
                  _setupShown = false;
                }
              }, child: const Text("COMPLETE SETUP"))
            ]);
        }));
  }

  void _editInterval(String type) {
    TextEditingController ctrl = TextEditingController(text: (type == "Oil" ? oilInterval : tireInterval).toInt().toString());
    showDialog(context: context, builder: (context) => AlertDialog(title: Text("EDIT $type INTERVAL"), content: TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Miles")), actions: [ElevatedButton(onPressed: () async {
        double newVal = double.tryParse(ctrl.text) ?? 5000.0;
        final prefs = await SharedPreferences.getInstance();
        setState(() { if (type == "Oil") { oilInterval = newVal; } else { tireInterval = newVal; } });
        await prefs.setDouble(type == "Oil" ? 'oilInterval' : 'tireInterval', newVal);
        if (context.mounted) { Navigator.pop(context); }
      }, child: const Text("SAVE"))]));
  }

  void _showPartsVault() {
    final List<String> partLabels = ["Oil Filter", "Spark Plugs", "Air Filter", "Cabin Filter", "Oil Type/Weight"];
    showDialog(context: context, builder: (context) => AlertDialog(title: const Text("PARTS VAULT"), content: SizedBox(width: double.maxFinite, child: ListView(shrinkWrap: true, children: partLabels.map((label) => TextField(controller: TextEditingController(text: engineParts[label]), decoration: InputDecoration(labelText: label, hintText: "Enter Part #"), onChanged: (val) { engineParts[label] = val; })).toList())), actions: [ElevatedButton(onPressed: () async {
        final prefs = await SharedPreferences.getInstance(); await prefs.setString('engineParts', json.encode(engineParts));
        if (context.mounted) { Navigator.pop(context); }
      }, child: const Text("SAVE SPECS"))]));
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoading && savedCarName.isEmpty && !_setupShown) { 
      Future.delayed(Duration.zero, () { if (mounted && savedCarName.isEmpty) { _showSetupDialog(); } }); 
    }
    if (_isLoading) { return const Scaffold(body: Center(child: CircularProgressIndicator())); }
    String displayDate = purchaseDateStr.isNotEmpty ? "${DateTime.parse(purchaseDateStr).month}/${DateTime.parse(purchaseDateStr).day}/${DateTime.parse(purchaseDateStr).year}" : "--/--/----";
    Color themeAccent = widget.isStealth ? Colors.white70 : Colors.blueAccent;

    return Scaffold(
      appBar: AppBar(title: const Text('GLOVEBOX'), centerTitle: true, actions: [IconButton(icon: Icon(widget.isStealth ? Icons.visibility_off : Icons.visibility, color: themeAccent), onPressed: widget.onThemeToggle)]),
      body: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 24), child: Column(children: [
          Container(height: 240, width: double.infinity, decoration: BoxDecoration(borderRadius: BorderRadius.circular(25), border: Border.all(color: themeAccent.withValues(alpha: 0.3))), clipBehavior: Clip.hardEdge, child: Stack(children: [
              Positioned.fill(child: bannerImagePath != null ? Image.file(File(bannerImagePath!), fit: BoxFit.cover) : Container(color: Colors.black26)),
              Positioned.fill(child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withValues(alpha: 0.9)])))),
              Positioned.fill(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const SizedBox(height: 20),
                  Text(savedCarName.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, shadows: [Shadow(blurRadius: 10, color: Colors.black)])),
                  Text("$savedMileage MILES", style: TextStyle(color: themeAccent, fontWeight: FontWeight.bold, fontSize: 36, shadows: const [Shadow(blurRadius: 10, color: Colors.black)])),
              ]))),
              Positioned(bottom: 0, left: 0, right: 0, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), color: Colors.black.withValues(alpha: 0.7), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text("PURCHASED: $displayDate", style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                    Row(children: [
                      Text("VIN: $savedVIN", style: const TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 5),
                      GestureDetector(onTap: () { Clipboard.setData(ClipboardData(text: savedVIN)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("VIN Copied"))); }, child: Icon(Icons.copy, size: 14, color: themeAccent)),
                    ]),
                  ]))),
              Positioned(top: 15, right: 15, child: CircleAvatar(backgroundColor: Colors.black54, child: IconButton(icon: const Icon(Icons.edit, color: Colors.white, size: 18), onPressed: () async {
                final img = await _picker.pickImage(source: ImageSource.gallery);
                if (img != null) { setState(() { bannerImagePath = img.path; }); final prefs = await SharedPreferences.getInstance(); await prefs.setString('bannerImage', img.path); }
              }))),
            ])),
          const SizedBox(height: 25),
          Wrap(alignment: WrapAlignment.spaceEvenly, spacing: 12, runSpacing: 15, children: [
            _mainBtn(Icons.local_gas_station, "FUEL LOG", () => Navigator.push(context, MaterialPageRoute(builder: (context) => const FuelLogScreen())).then((_) => _loadAllData()), Colors.purpleAccent),
            _mainBtn(Icons.build_circle, "SERVICES", () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MaintenanceLogScreen())), Colors.redAccent),
            _mainBtn(Icons.account_balance_wallet, "DOCS", () => Navigator.push(context, MaterialPageRoute(builder: (context) => const WalletScreen())), Colors.greenAccent),
            _mainBtn(Icons.list_alt, "SPECS", () => Navigator.push(context, MaterialPageRoute(builder: (context) => SpecsScreen(carVIN: savedVIN, carName: savedCarName, engineParts: engineParts, themeColor: themeAccent))), Colors.orangeAccent),
            _mainBtn(Icons.map, "MAPS", () => _launchUrl("https://www.google.com/maps"), Colors.blue),
            _mainBtn(Icons.menu_book, "MANUAL", () => _launchUrl("https://www.google.com/search?q=$savedCarName+owners+manual+pdf"), Colors.tealAccent),
          ]),
          const SizedBox(height: 25),
          const Align(alignment: Alignment.centerLeft, child: Text("MAINTENANCE STATUS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey))),
          const SizedBox(height: 10),
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(15)), child: Column(children: [
              _serviceBar("Oil Change", lastOilChangeAt, oilInterval, "Oil", themeAccent),
              _serviceBar("Tire Rotation", lastTireRotationAt, tireInterval, "Tire", themeAccent)
            ])),
          const SizedBox(height: 25),
          const Align(alignment: Alignment.centerLeft, child: Text("CONDITION RECORD", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey))),
          const SizedBox(height: 10),
          GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.5, children: ["FRONT", "REAR", "R FRONT", "L FRONT", "R REAR", "L REAR", "ENGINE"].map((label) => _photoSquare(label, themeAccent)).toList()),
          const SizedBox(height: 30),
          TextButton.icon(onPressed: () async {
            final prefs = await SharedPreferences.getInstance(); 
            await prefs.clear();
            setState(() { savedCarName = ""; savedMileage = ""; savedVIN = ""; bannerImagePath = null; photoPaths = {}; engineParts = {}; lastOilChangeAt = 0.0; lastTireRotationAt = 0.0; purchaseDateStr = ""; userEmail = ""; });
            _showSetupDialog();
          }, icon: const Icon(Icons.delete_forever, color: Colors.redAccent, size: 14), label: const Text("REPLACE VEHICLE", style: TextStyle(color: Colors.redAccent, fontSize: 10))),
          const SizedBox(height: 40),
        ])),
    );
  }

  Widget _mainBtn(IconData icon, String label, VoidCallback onTap, Color color) {
    return InkWell(onTap: onTap, child: Column(children: [CircleAvatar(backgroundColor: color.withValues(alpha: 0.1), child: Icon(icon, color: color, size: 20)), const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold))]));
  }

  Widget _serviceBar(String title, double lastAt, double interval, String type, Color accent) {
    double current = double.tryParse(savedMileage) ?? 0.0;
    double progress = ((current - lastAt) / interval).clamp(0.0, 1.0);
    int remaining = (interval - (current - lastAt)).toInt();
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), IconButton(icon: const Icon(Icons.edit, size: 12, color: Colors.grey), onPressed: () { _editInterval(type); })]),
        GestureDetector(onTap: () async {
          double curr = double.tryParse(savedMileage) ?? 0.0;
          final prefs = await SharedPreferences.getInstance();
          setState(() { if (type == "Oil") { lastOilChangeAt = curr; } else { lastTireRotationAt = curr; } }); 
          await prefs.setDouble(type == "Oil" ? 'lastOilChange' : 'lastTireRotation', curr);
          _checkServiceStatus(); // Check alerts again after reset
        }, child: Text(remaining <= 0 ? "RESET NOW" : "$remaining MI (RESET)", style: TextStyle(color: remaining <= 0 ? Colors.redAccent : accent, fontWeight: FontWeight.bold, fontSize: 10))),
      ]),
      const SizedBox(height: 2),
      LinearProgressIndicator(value: progress, minHeight: 8, borderRadius: BorderRadius.circular(4), color: progress > 0.9 ? Colors.redAccent : accent),
      const SizedBox(height: 12),
    ]);
  }

  Widget _photoSquare(String label, Color accent) {
    bool hasImage = photoPaths.containsKey(label);
    return GestureDetector(onTap: () async {
        showModalBottomSheet(context: context, builder: (context) => SafeArea(child: Wrap(children: [
          ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Take Photo'), onTap: () async { Navigator.pop(context); final img = await _picker.pickImage(source: ImageSource.camera); if (img != null) { setState(() { photoPaths[label] = img.path; }); final prefs = await SharedPreferences.getInstance(); await prefs.setString('conditionPhotos', json.encode(photoPaths)); } }),
          ListTile(leading: const Icon(Icons.photo_library), title: const Text('Gallery'), onTap: () async { Navigator.pop(context); final img = await _picker.pickImage(source: ImageSource.gallery); if (img != null) { setState(() { photoPaths[label] = img.path; }); final prefs = await SharedPreferences.getInstance(); await prefs.setString('conditionPhotos', json.encode(photoPaths)); } }),
        ])));
      }, child: Container(decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(12), image: hasImage ? DecorationImage(image: FileImage(File(photoPaths[label]!)), fit: BoxFit.cover) : null), child: Stack(children: [
           if (!hasImage) Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo, size: 16, color: accent), Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold))])),
           if (label == "ENGINE") Positioned(bottom: 5, right: 5, child: GestureDetector(onTap: () { _showPartsVault(); }, child: CircleAvatar(radius: 12, backgroundColor: accent, child: const Icon(Icons.settings, size: 14, color: Colors.white)))),
         ])));
  }

  Future<void> _launchUrl(String urlString) async { final Uri url = Uri.parse(urlString); if (!await launchUrl(url, mode: LaunchMode.externalApplication)) { debugPrint("Error"); } }
}

// --- DOCS WALLET ---
class WalletScreen extends StatefulWidget { const WalletScreen({super.key}); @override State<WalletScreen> createState() => _WalletScreenState(); }
class _WalletScreenState extends State<WalletScreen> {
  Map<String, String> docs = {}; final ImagePicker _picker = ImagePicker();
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { final prefs = await SharedPreferences.getInstance(); String? jsonStr = prefs.getString('walletDocs'); if (jsonStr != null) { setState(() { docs = Map<String, String>.from(json.decode(jsonStr)); }); } }
  
  Future<void> _pick(String label) async {
    showModalBottomSheet(context: context, builder: (context) => SafeArea(child: Wrap(children: [
      ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Take Photo'), onTap: () async { Navigator.pop(context); final img = await _picker.pickImage(source: ImageSource.camera); if (img != null) { _saveDoc(label, img.path); } }),
      ListTile(leading: const Icon(Icons.photo_library), title: const Text('Upload from Gallery'), onTap: () async { Navigator.pop(context); final img = await _picker.pickImage(source: ImageSource.gallery); if (img != null) { _saveDoc(label, img.path); } }),
    ])));
  }

  void _saveDoc(String label, String path) async { final prefs = await SharedPreferences.getInstance(); setState(() { docs[label] = path; }); await prefs.setString('walletDocs', json.encode(docs)); }

  @override Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text("DOCS WALLET")), body: ListView(padding: const EdgeInsets.all(16), children: ["INSURANCE", "REGISTRATION", "AAA CARD", "EMERGENCY INFO"].map((label) => _docTile(label)).toList()));
  }
  Widget _docTile(String label) {
    bool has = docs.containsKey(label);
    return Card(color: const Color(0xFF1E1E1E), margin: const EdgeInsets.only(bottom: 12), child: ListTile(title: Text(label), subtitle: Text(has ? "Document Saved" : "No image"), trailing: Icon(has ? Icons.check_circle : Icons.add_a_photo, color: has ? Colors.greenAccent : Colors.grey), onTap: () {
      if (has) { showDialog(context: context, builder: (context) => AlertDialog(content: Image.file(File(docs[label]!)), actions: [TextButton(onPressed: () => _pick(label), child: const Text("REPLACE")), TextButton(onPressed: () => Navigator.pop(context), child: const Text("CLOSE"))])); } 
      else { _pick(label); }
    }));
  }
}

// --- LOG SCREENS ---
class FuelLogScreen extends StatefulWidget { const FuelLogScreen({super.key}); @override State<FuelLogScreen> createState() => _FuelLogScreenState(); }
class _FuelLogScreenState extends State<FuelLogScreen> {
  List<FuelEntry> fuelHistory = []; final TextEditingController _gallons = TextEditingController(); final TextEditingController _price = TextEditingController(); final TextEditingController _odo = TextEditingController();
  @override void initState() { super.initState(); _loadFuel(); }
  Future<void> _loadFuel() async { final prefs = await SharedPreferences.getInstance(); final List<String>? stored = prefs.getStringList('fuelHistory'); if (stored != null) { setState(() { fuelHistory = stored.map((e) => FuelEntry.fromJson(json.decode(e))).toList(); }); } }
  @override Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text("FUEL LOG")), floatingActionButton: FloatingActionButton(backgroundColor: Colors.purpleAccent, onPressed: () {
        showDialog(context: context, builder: (context) => AlertDialog(title: const Text("NEW FUEL ENTRY"), content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _odo, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "ODOMETER")),
          TextField(controller: _gallons, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "GALLONS")),
          TextField(controller: _price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "TOTAL COST")),
        ]), actions: [ElevatedButton(onPressed: () async {
            final odo = _odo.text; setState(() { fuelHistory.insert(0, FuelEntry(date: DateTime.now(), gallons: _gallons.text, price: _price.text, odometer: odo)); });
            final prefs = await SharedPreferences.getInstance(); await prefs.setStringList('fuelHistory', fuelHistory.map((e) => json.encode(e.toJson())).toList()); await prefs.setString('mileage', odo);
            if (context.mounted) { Navigator.pop(context); }
          }, child: const Text("SAVE"))]));
      }, child: const Icon(Icons.add, color: Colors.white)), body: ListView.builder(itemCount: fuelHistory.length, itemBuilder: (context, index) { final entry = fuelHistory[index]; return Card(color: const Color(0xFF1E1E1E), margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: ListTile(title: Text("${entry.gallons} GAL - \$${entry.price}"), subtitle: Text("ODO: ${entry.odometer}"))); }));
  }
}

class MaintenanceLogScreen extends StatefulWidget { const MaintenanceLogScreen({super.key}); @override State<MaintenanceLogScreen> createState() => _MaintenanceLogScreenState(); }
class _MaintenanceLogScreenState extends State<MaintenanceLogScreen> {
  List<ServiceEntry> history = []; final TextEditingController _task = TextEditingController(); final TextEditingController _odo = TextEditingController();
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { final prefs = await SharedPreferences.getInstance(); final List<String>? stored = prefs.getStringList('serviceHistory'); if (stored != null) { setState(() { history = stored.map((e) => ServiceEntry.fromJson(json.decode(e))).toList(); }); } }
  @override Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text("SERVICE HISTORY")), floatingActionButton: FloatingActionButton(backgroundColor: Colors.redAccent, onPressed: () {
        showDialog(context: context, builder: (context) => AlertDialog(title: const Text("NEW SERVICE"), content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _odo, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "ODOMETER")),
          TextField(controller: _task, decoration: const InputDecoration(labelText: "DESCRIPTION")),
        ]), actions: [ElevatedButton(onPressed: () async { setState(() { history.insert(0, ServiceEntry(date: DateTime.now(), mileage: _odo.text, task: _task.text)); });
            final prefs = await SharedPreferences.getInstance(); await prefs.setStringList('serviceHistory', history.map((e) => json.encode(e.toJson())).toList());
            if (context.mounted) { Navigator.pop(context); }
          }, child: const Text("SAVE"))]));
      }, child: const Icon(Icons.add, color: Colors.white)), body: ListView.builder(itemCount: history.length, itemBuilder: (context, index) { final entry = history[index]; return ListTile(title: Text(entry.task), subtitle: Text("${entry.mileage} MILES - ${entry.date.month}/${entry.date.day}/${entry.date.year}")); }));
  }
}

class SpecsScreen extends StatefulWidget { final String carVIN; final String carName; final Map<String, String> engineParts; final Color themeColor; const SpecsScreen({super.key, required this.carVIN, required this.carName, required this.engineParts, required this.themeColor}); @override State<SpecsScreen> createState() => _SpecsScreenState(); }
class _SpecsScreenState extends State<SpecsScreen> {
  Map<String, String> specs = {};
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { final prefs = await SharedPreferences.getInstance(); String? stored = prefs.getString('carSpecs'); if (stored != null) { setState(() { specs = Map<String, String>.from(json.decode(stored)); }); } }
  void _emailMechanic() async { String body = "Vehicle: ${widget.carName}\nVIN: ${widget.carVIN}\n\nSPECS:\n"; specs.forEach((k, v) { body += "$k: $v\n"; }); body += "\nENGINE PARTS:\n"; widget.engineParts.forEach((k, v) { body += "$k: $v\n"; }); final Uri emailLaunchUri = Uri(scheme: 'mailto', path: '', query: 'subject=Specs: ${widget.carName}&body=${Uri.encodeComponent(body)}'); if (!await launchUrl(emailLaunchUri)) { debugPrint("Error"); } }
  @override Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text("VEHICLE SPECS"), actions: [IconButton(icon: Icon(Icons.send, color: widget.themeColor), onPressed: () { _emailMechanic(); })]), body: ListView(padding: const EdgeInsets.all(16), children: ["Engine", "Horsepower", "Torque", "Tires", "Oil Type", "Spark Plugs"].map((field) => ListTile(title: Text(field, style: const TextStyle(color: Colors.grey, fontSize: 12)), subtitle: TextField(decoration: InputDecoration(hintText: "ENTER $field..."), controller: TextEditingController(text: specs[field]), onSubmitted: (val) async { specs[field] = val; final prefs = await SharedPreferences.getInstance(); await prefs.setString('carSpecs', json.encode(specs)); }))).toList()));
  }
}