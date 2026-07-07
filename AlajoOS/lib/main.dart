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
  final String? photoPath;

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
      version: 2,
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
// HOME SCREEN
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

  // FIX: ADD THESE 2 MISSING FUNCTIONS
  void _showSuccessDialog(String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 10),
            Text('Success'),
          ],
        ),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          )
        ],
      ),
    );
  }

  void _showErrorDialog(String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 10),
            Text('Error'),
          ],
        ),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          )
        ],
      ),
    );
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
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Card(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.record_voice_over_rounded, color: Color(0xFF0F5132)),
                            SizedBox(width: 8),
                            Text('Voice Input', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                  Text(client['name']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign
