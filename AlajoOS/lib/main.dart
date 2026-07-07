import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AlajoOsApp());
}

class AlajoOsApp extends StatelessWidget {
  const AlajoOsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alajo OS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F5132),
          primary: const Color(0xFF0F5132),
          secondary: const Color(0xFFD4AF37),
          background: const Color(0xFFF8F9FA),
        ),
        cardTheme: const CardThemeData(
          elevation: 2,
          margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        ),
        fontFamily: 'sans-serif',
      ),
      home: const HomeScreen(),
    );
  }
}

// ============================================================================
// DATABASE HELPER - UPDATED WITH PHOTO
// ============================================================================
class Customer {
  final String cardId;
  final String name;
  final String phone;
  final int dailyAmount;
  final int balance;
  final String lastCollection;
  final String? photoPath; // NEW: For photo

  const Customer({
    required this.cardId,
    required this.name,
    required this.phone,
    required this.dailyAmount,
    required this.balance,
    required this.lastCollection,
    this.photoPath,
  });

  Map<String, dynamic> toMap() {
    return {
      'cardId': cardId,
      'name': name,
      'phone': phone,
      'dailyAmount': dailyAmount,
      'balance': balance,
      'lastCollection': lastCollection,
      'photoPath': photoPath,
    };
  }
}

class Contribution {
  final int? id;
  final String customerCardId;
  final String customerName;
  final int amountPaid;
  final String datePaid;
  final String notes;

  const Contribution({
    this.id,
    required this.customerCardId,
    required this.customerName,
    required this.amountPaid,
    required this.datePaid,
    required this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id!= null) 'id': id,
      'customerCardId': customerCardId,
      'customerName': customerName,
      'amountPaid': amountPaid,
      'datePaid': datePaid,
      'notes': notes,
    };
  }
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database!= null) return _database!;
    _database = await _initDB('alajo_os.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2, // UPGRADED VERSION FOR PHOTO
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE customers (
        cardId TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        dailyAmount INTEGER NOT NULL,
        balance INTEGER NOT NULL,
        lastCollection TEXT NOT NULL,
        photoPath TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE contributions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customerCardId TEXT NOT NULL,
        customerName TEXT NOT NULL,
        amountPaid INTEGER NOT NULL,
        datePaid TEXT NOT NULL,
        notes TEXT NOT NULL,
        FOREIGN KEY (customerCardId) REFERENCES customers (cardId)
      )
    ''');

    await _seedDatabase(db);
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE customers ADD COLUMN photoPath TEXT');
    }
  }

  Future _seedDatabase(Database db) async {
    final now = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final demoCustomers = [
      const Customer(
        cardId: 'ALAJO-001',
        name: 'Iya Alata (Pepper Seller)',
        phone: '08034455667',
        dailyAmount: 1000,
        balance: 15000,
        lastCollection: 'Yesterday',
      ),
      const Customer(
        cardId: 'ALAJO-002',
        name: 'Baba Ibadan (Tailor)',
        phone: '08122334455',
        dailyAmount: 2000,
        balance: 32000,
        lastCollection: 'Two days ago',
      ),
      const Customer(
        cardId: 'ALAJO-003',
        name: 'Mama Ngozi (Provisions Shop)',
        phone: '09055667788',
        dailyAmount: 5000,
        balance: 85000,
        lastCollection: 'Today',
      ),
    ];

    for (var customer in demoCustomers) {
      await db.insert('customers', customer.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<List<Customer>> getCustomers() async {
    final db = await instance.database;
    final result = await db.query('customers');
    return result
       .map((json) => Customer(
              cardId: json['cardId'] as String,
              name: json['name'] as String,
              phone: json['phone'] as String,
              dailyAmount: json['dailyAmount'] as int,
              balance: json['balance'] as int,
              lastCollection: json['lastCollection'] as String,
              photoPath: json['photoPath'] as String?,
            ))
       .toList();
  }

  Future<Customer?> getCustomerByCardId(String cardId) async {
    final db = await instance.database;
    final result = await db.query(
      'customers',
      where: 'cardId =?',
      whereArgs: [cardId],
    );
    if (result.isNotEmpty) {
      final json = result.first;
      return Customer(
        cardId: json['cardId'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String,
        dailyAmount: json['dailyAmount'] as int,
        balance: json['balance'] as int,
        lastCollection: json['lastCollection'] as String,
        photoPath: json['photoPath'] as String?,
      );
    }
    return null;
  }

  Future<void> addCustomer(Customer customer) async {
    final db = await instance.database;
    await db.insert('customers', customer.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String> generateNewCardId() async {
    final db = await instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM customers');
    int count = Sqflite.firstIntValue(result)?? 0;
    return 'ALJ${(count + 1).toString().padLeft(3, '0')}';
  }

  Future<void> addCollection(String cardId, int amount, String notes) async {
    final db = await instance.database;
    final customer = await getCustomerByCardId(cardId);
    if (customer == null) return;

    final nowStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final newBalance = customer.balance + amount;

    await db.update(
      'customers',
      {
        'balance': newBalance,
        'lastCollection': 'Just now',
      },
      where: 'cardId =?',
      whereArgs: [cardId],
    );

    await db.insert(
        'contributions',
        Contribution(
          customerCardId: cardId,
          customerName: customer.name,
          amountPaid: amount,
          datePaid: nowStr,
          notes: notes,
        ).toMap());
  }

  Future<List<Contribution>> getContributions() async {
    final db = await instance.database;
    final result = await db.query('contributions', orderBy: 'id DESC');
    return result
       .map((json) => Contribution(
              id: json['id'] as int?,
              customerCardId: json['customerCardId'] as String,
              customerName: json['customerName'] as String,
              amountPaid: json['amountPaid'] as int,
              datePaid: json['datePaid'] as String,
              notes: json['notes'] as String,
            ))
       .toList();
  }

  Future<void> resetDemoDatabase() async {
    final db = await instance.database;
    await db.delete('contributions');
    await db.delete('customers');
    await _seedDatabase(db);
  }
}

// ============================================================================
// HOME SCREEN - UPDATED WITH VOICE FIX
// ============================================================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _speechText = "Tap mic and say amount";
  final currencyFormat = NumberFormat.currency(locale: 'en_NG', symbol: '₦', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  void _initSpeech() async {
    try {
      await _speech.initialize();
    } catch (e) {
      print('Speech error: $e');
    }
  }

  void _startListening(TextEditingController amountController) async {
    bool available = await _speech.initialize(
      onError: (val) => print('Speech Error: $val'),
      onStatus: (val) => print('Speech Status: $val'),
    );
    if (available) {
      setState(() => _isListening = true);
      _speech.listen(
        onResult: (val) {
          setState(() {
            _speechText = val.recognizedWords;
            // Extract numbers from speech
            String numbers = val.recognizedWords.replaceAll(RegExp(r'[^0-9]'), '');
            if (numbers.isNotEmpty) {
              amountController.text = numbers;
            }
          });
          if (val.finalResult) {
            setState(() => _isListening = false);
          }
        },
      );
    }
  }

  void _stopListening() async {
    await _speech.stop();
    setState(() => _isListening = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.savings_rounded, color: Colors.amber, size: 28),
            SizedBox(width: 10),
            Text('Alajo OS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 4,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE8F0EA), Color(0xFFF8F9FA)],
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Voice Input Card - UPDATED
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Card(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.record_voice_over_rounded, color: Color(0xFF0F5132)),
                                SizedBox(width: 8),
                                Text('Voice Input', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isListening? "Listening... $_speechText" : _speechText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: _isListening? Colors.red : Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // THE 5 BIG BUTTONS
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F5132),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 64),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 4,
                      ),
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 28),
                      label: const Text('SCAN CARD', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                      onPressed: () => _openScanner(context),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF0F5132),
                              minimumSize: const Size(0, 60),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(color: Color(0xFF0F5132), width: 1.5),
                              ),
                              elevation: 2,
                            ),
                            icon: const Icon(Icons.search_rounded),
                            label: const Text('FIND BY NAME', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            onPressed: () => _findByName(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF0F5132),
                              minimumSize: const Size(0, 60),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(color: Color(0xFF0F5132), width: 1.5),
                              ),
                              elevation: 2,
                            ),
                            icon: const Icon(Icons.dashboard_rounded),
                            label: const Text('DASHBOARD', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            onPressed: () => _showDashboard(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF0F5132),
                              minimumSize: const Size(0, 60),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(color: Color(0xFF0F5132), width: 1.5),
                              ),
                              elevation: 2,
                            ),
                            icon: const Icon(Icons.group_rounded),
                            label: const Text('OLD CUSTOMERS', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            onPressed: () => _viewOldCustomers(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF842029),
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 60),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 2,
                            ),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('RESET DEMO', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            onPressed: () => _resetDemo(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.0),
                child: Row(
                  children: [
                    Icon(Icons.qr_code_2_rounded, color: Color(0xFFD4AF37)),
                    SizedBox(width: 8),
                    Text('3 Test Savings Cards (QR Codes)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F5132))),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildDemoQrSection(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDemoQrSection() {
    final demoClients = [
      {'id': 'ALAJO-001', 'name': 'Iya Alata', 'desc': '₦1,000 / Day'},
      {'id': 'ALAJO-002', 'name': 'Baba Ibadan', 'desc': '₦2,000 / Day'},
      {'id': 'ALAJO-003', 'name': 'Mama Ngozi', 'desc': '₦5,000 / Day'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: demoClients.map((client) {
          return Card(
            color: Colors.white,
            elevation: 3,
            shadowColor: Colors.black26,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE0E0E0))),
            child: Container(
              width: 140,
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(client['name']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center),
                  const SizedBox(height: 6),
                  QrImageView(data: client['id']!, version: QrVersions.auto, size: 90.0, gapless: false),
                  const SizedBox(height: 6),
                  Text(client['id']!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Colors.blueGrey)),
                  const SizedBox(height: 2),
                  Text(client['desc']!, style: const TextStyle(fontSize: 11, color: Color(0xFF0F5132), fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ============================================================================
  // UPDATED SCAN FLOW - CHECK IF USER EXISTS
  // ============================================================================
  void _openScanner(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Scan Savings Card QR'),
            backgroundColor: const Color(0xFF0F5132),
            foregroundColor: Colors.white,
          ),
          body: Stack(
            children: [
              MobileScanner(
                onDetect: (capture) {
                  final List<Barcode> barcodes = capture.barcodes;
                  if (barcodes.isNotEmpty && barcodes.first.rawValue!= null) {
                    final String cardId = barcodes.first.rawValue!;
                    Navigator.of(context).pop();
                    _handleScannedCard(cardId);
                  }
                },
              ),
              Positioned.fill(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.amber, width: 4),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: Colors.black54,
                      child: const Text('Align client QR Card inside box', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleScannedCard(String cardId) async {
    final customer = await DatabaseHelper.instance.getCustomerByCardId(cardId);
    
    if (customer == null) {
      // NO DATA FOUND - SHOW ADD USER SCREEN
      _showAddUserScreen(cardId);
    } else {
      // USER EXISTS - SHOW PAYMENT SCREEN
      _showPaymentScreen(customer);
    }
  }

  // NEW: SHOW CARD INFO + AMOUNT INPUT
  void _showPaymentScreen(Customer customer) {
    final amountController = TextEditingController(text: customer.dailyAmount.toString());
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.person, color: Color(0xFF0F5132)),
            const SizedBox(width: 8),
            Expanded(child: Text(customer.name, style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (customer.photoPath!= null)
                CircleAvatar(
                  radius: 40,
                  backgroundImage: FileImage(File(customer.photoPath!)),
                ),
              const SizedBox(height: 12),
              Text('Card ID: ${customer.cardId}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
              Text('Phone: ${customer.phone}'),
              const SizedBox(height: 6),
              Text('Current Balance: ${currencyFormat.format(customer.balance)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              Text('Daily Target: ${currencyFormat.format(customer.dailyAmount)}'),
              Text('Last Collection: ${customer.lastCollection}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Amount Collected (₦)',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_isListening? Icons.mic : Icons.mic_none, color: _isListening? Colors.red : const Color(0xFF0F5132)),
                    onPressed: () => _isListening? _stopListening() : _startListening(amountController),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(_speechText, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F5132), foregroundColor: Colors.white),
            onPressed: () async {
              int amount = int.tryParse(amountController.text)?? 0;
              if (amount > 0) {
                Navigator.pop(ctx);
                await DatabaseHelper.instance.addCollection(customer.cardId, amount, 'Cash Collection');
                _showSuccessDialog('Recorded ${currencyFormat.format(amount)} for ${customer.name}');
              }
            },
            child: const Text('Save Payment'),
          ),
        ],
      ),
    );
  }

  // NEW: ADD USER SCREEN
  void _showAddUserScreen(String cardId) async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final dailyAmountController = TextEditingController(text: '1000');
    String? photoPath;
    final ImagePicker picker = ImagePicker();
    String newId = await DatabaseHelper.instance.generateNewCardId();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.person_add, color: Colors.orange),
              SizedBox(width: 8),
              Text('No Data - Add User'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('QR Code: $cardId', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                Text('New ID: $newId', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                // Photo picker
                GestureDetector(
                  onTap: () async {
                    final XFile? image = await picker.pickImage(source: ImageSource.camera);
                    if (image!= null) {
                      setDialogState(() => photoPath = image.path);
                    }
                  },
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.grey[300],
                    backgroundImage: photoPath!= null? FileImage(File(photoPath!)) : null,
                    child: photoPath == null? const Icon(Icons.camera_alt, size: 40, color: Colors.grey) : null,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Tap to take photo', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone Number', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dailyAmountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Daily Amount (₦)', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F5132), foregroundColor: Colors.white),
              onPressed: () async {
                if (nameController.text.isEmpty || phoneController.text.isEmpty) {
                  _showErrorDialog('Name and Phone are required');
                  return;
                }
                Navigator.pop(ctx);
                final newCustomer = Customer(
                  cardId: newId,
                  name: nameController.text,
                  phone: phoneController.text,
                  dailyAmount: int.tryParse(dailyAmountController.text)?? 1000,
                  balance: 0,
                  lastCollection: 'Never',
                  photoPath: photoPath,
                );
                await DatabaseHelper.instance.addCustomer(newCustomer);
                _showSuccessDialog('Added ${newCustomer.name} with ID $newId');
                // Open payment screen immediately
                _showPaymentScreen(newCustomer);
              },
              child: const Text('Save User'),
            ),
          ],
        ),
      ),
    );
  }

  void _findByName(BuildContext context) async {
    final customers = await DatabaseHelper.instance.getCustomers();
    String searchQuery = "";

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = customers.where((c) => c.name.toLowerCase().contains(searchQuery.toLowerCase())).toList();
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.search_rounded, color: Color(0xFF0F5132)),
                  SizedBox(width: 8),
                  Text('Search Alajo Clients'),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Enter name',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) => setModalState(() => searchQuery = val),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                         ? const Center(child: Text('No customers found'))
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final c = filtered[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: const Color(0xFF0F5132),
                                    backgroundImage: c.photoPath!= null? FileImage(File(c.photoPath!)) : null,
                                    child: c.photoPath == null? const Icon(Icons.person, color: Colors.white) : null,
                                  ),
                                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text('${c.cardId} • ${currencyFormat.format(c.dailyAmount)}/day'),
                                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _showPaymentScreen(c);
                                  },
                                );
                              },
                            ),
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showDashboard(BuildContext context) async {
    final customers = await DatabaseHelper.instance.getCustomers();
    final contributions = await DatabaseHelper.instance.getContributions();
    int totalSavings = customers.fold(0, (sum, c) => sum + c.balance);
    int todayCollections = contributions.where((con) => con.datePaid.contains(DateFormat('yyyy-MM-dd').format(DateTime.now()))).fold(0, (sum, c) => sum + c.amountPaid);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              children: [
                Icon(Icons.dashboard_rounded, color: Color(0xFF0F5132), size: 28),
                SizedBox(width: 8),
                Text('DAILY LEDGER SUMMARY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1)),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: Card(
                    color: const Color(0xFFE8F0EA),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          const Text('Today\'s Collection', style: TextStyle(fontSize: 12, color: Color(0xFF0F5132))),
                          const SizedBox(height: 6),
                          Text(currencyFormat.format(todayCollections), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F5132))),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Card(
                    color: const Color(0xFFFCF8E3),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          const Text('Grand Total Saved', style: TextStyle(fontSize: 12, color: Color(0xFF856404))),
                          const SizedBox(height: 6),
                          Text(currencyFormat.format(totalSavings), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF856404))),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.people_alt_rounded, color: Color(0xFF0F5132)),
              title: const Text('Registered Thrift Members'),
              trailing: Text('${customers.length} Accounts', style: const
