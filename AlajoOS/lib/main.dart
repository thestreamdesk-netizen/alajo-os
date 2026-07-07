import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';

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
          seedColor: const Color(0xFF0F5132), // Emerald Green
          primary: const Color(0xFF0F5132),
          secondary: const Color(0xFFD4AF37), // Metallic Gold
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
// DATABASE HELPER
// ============================================================================
class Customer {
  final String cardId;
  final String name;
  final String phone;
  final int dailyAmount;
  final int balance;
  final String lastCollection;

  const Customer({
    required this.cardId,
    required this.name,
    required this.phone,
    required this.dailyAmount,
    required this.balance,
    required this.lastCollection,
  });

  Map<String, dynamic> toMap() {
    return {
      'cardId': cardId,
      'name': name,
      'phone': phone,
      'dailyAmount': dailyAmount,
      'balance': balance,
      'lastCollection': lastCollection,
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
      if (id != null) 'id': id,
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
    if (_database != null) return _database!;
    _database = await _initDB('alajo_os.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
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
        lastCollection TEXT NOT NULL
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

    // Seed some initial contribution history
    final initialContributions = [
      Contribution(
        customerCardId: 'ALAJO-001',
        customerName: 'Iya Alata (Pepper Seller)',
        amountPaid: 1000,
        datePaid: now,
        notes: 'Daily contribution received',
      ),
      Contribution(
        customerCardId: 'ALAJO-002',
        customerName: 'Baba Ibadan (Tailor)',
        amountPaid: 2000,
        datePaid: now,
        notes: 'Paid cash',
      ),
      Contribution(
        customerCardId: 'ALAJO-003',
        customerName: 'Mama Ngozi (Provisions Shop)',
        amountPaid: 5000,
        datePaid: now,
        notes: 'Completed card target',
      ),
    ];

    for (var contribution in initialContributions) {
      await db.insert('contributions', contribution.toMap());
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
            ))
        .toList();
  }

  Future<Customer?> getCustomerByCardId(String cardId) async {
    final db = await instance.database;
    final result = await db.query(
      'customers',
      where: 'cardId = ?',
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
      );
    }
    return null;
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

  Future<void> addCollection(String cardId, int amount, String notes) async {
    final db = await instance.database;
    final customer = await getCustomerByCardId(cardId);
    if (customer == null) return;

    final nowStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final newBalance = customer.balance + amount;

    // Update customer balance and last collection time
    await db.update(
      'customers',
      {
        'balance': newBalance,
        'lastCollection': 'Just now',
      },
      where: 'cardId = ?',
      whereArgs: [cardId],
    );

    // Insert history record
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
  String _speechText = "Tap mic and say 'Collect [amount] for [Customer]'";

  final currencyFormat =
      NumberFormat.currency(locale: 'en_NG', symbol: '₦', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  void _initSpeech() async {
    try {
      await _speech.initialize();
    } catch (e) {
      // Speech recognition not supported or permission denied
    }
  }

  void _startListening() async {
    bool available = await _speech.initialize(
      onError: (val) => print('Speech Error: $val'),
      onStatus: (val) => print('Speech Status: $val'),
    );
    if (available) {
      setState(() {
        _isListening = true;
        _speechText = "Listening in Yoruba/Pidgin...";
      });
      _speech.listen(
        onResult: (val) {
          setState(() {
            _speechText = val.recognizedWords;
          });
          if (val.finalResult) {
            _parseVoiceCommand(val.recognizedWords);
          }
        },
      );
    } else {
      setState(() {
        _isListening = false;
        _speechText = "Speech recognition unavailable.";
      });
    }
  }

  void _stopListening() async {
    await _speech.stop();
    setState(() => _isListening = false);
  }

  // Parses voice strings (e.g. Pidgin: "Collect five k for Iya Alata" or Yoruba: "Gba egberun fun Iya Alata")
  void _parseVoiceCommand(String text) async {
    final cleanText = text.toLowerCase();

    // Find customer keyword matches
    String? matchedCardId;
    String matchedName = "";
    int amount = 1000; // default collection
    String notes = "Voice Input";

    if (cleanText.contains('iya alata') ||
        cleanText.contains('alata') ||
        cleanText.contains('pepper')) {
      matchedCardId = 'ALAJO-001';
      matchedName = 'Iya Alata';
    } else if (cleanText.contains('baba ibadan') ||
        cleanText.contains('ibadan') ||
        cleanText.contains('tailor')) {
      matchedCardId = 'ALAJO-002';
      matchedName = 'Baba Ibadan';
    } else if (cleanText.contains('mama ngozi') ||
        cleanText.contains('ngozi') ||
        cleanText.contains('provision')) {
      matchedCardId = 'ALAJO-003';
      matchedName = 'Mama Ngozi';
    }

    // Parse values from Yoruba / Pidgin / English terms
    if (cleanText.contains('five thousand') ||
        cleanText.contains('five k') ||
        cleanText.contains('5k') ||
        cleanText.contains('5000') ||
        cleanText.contains('egberun marun')) {
      amount = 5000;
    } else if (cleanText.contains('two thousand') ||
        cleanText.contains('two k') ||
        cleanText.contains('2k') ||
        cleanText.contains('2000') ||
        cleanText.contains('egberun meji')) {
      amount = 2000;
    } else if (cleanText.contains('one thousand') ||
        cleanText.contains('one k') ||
        cleanText.contains('1k') ||
        cleanText.contains('1000') ||
        cleanText.contains('egberun') ||
        cleanText.contains('okan')) {
      amount = 1000;
    }

    if (cleanText.contains('collect') ||
        cleanText.contains('pay') ||
        cleanText.contains('gba') ||
        cleanText.contains('san')) {
      notes = "Voice: Collected Ajo";
    }

    if (matchedCardId != null) {
      await DatabaseHelper.instance.addCollection(matchedCardId, amount, notes);
      _showSuccessDialog(
          "Success! Captured Voice payment of ${currencyFormat.format(amount)} for $matchedName.");
      setState(() {
        _speechText =
            "Success: Collected ${currencyFormat.format(amount)} from $matchedName";
      });
    } else {
      _showErrorDialog(
          "Could not identify customer. Say 'Collect 1000 for Iya Alata', 'Collect two k for Baba Ibadan' or 'Mama Ngozi pay 5000'.");
    }
  }

  void _showSuccessDialog(String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 10),
            Text('Collection Recorded'),
          ],
        ),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('O dabo / Done'),
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
            Text('Voice Not Understood'),
          ],
        ),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Try Again'),
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
            Text(
              'Alajo OS',
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
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
              // Voice Instruction Banner
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
                                Icon(Icons.record_voice_over_rounded,
                                    color: Color(0xFF0F5132)),
                                SizedBox(width: 8),
                                Text(
                                  'Voice Input (Pidgin/Yoruba)',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16),
                                ),
                              ],
                            ),
                            IconButton(
                              onPressed: _isListening
                                  ? _stopListening
                                  : _startListening,
                              icon: Icon(
                                _isListening
                                    ? Icons.mic_off_rounded
                                    : Icons.mic_rounded,
                                color: _isListening
                                    ? Colors.red
                                    : const Color(0xFF0F5132),
                                size: 30,
                              ),
                            )
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _speechText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: _isListening ? Colors.red : Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // THE 5 BIG BUTTONS CONTAINER
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  children: [
                    // Button 1: Scan Card
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F5132),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 64),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 4,
                      ),
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 28),
                      label: const Text('SCAN CARD',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1)),
                      onPressed: () => _openScanner(context),
                    ),
                    const SizedBox(height: 12),

                    // Buttons 2 & 3: Find By Name, Dashboard
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
                                side: const BorderSide(
                                    color: Color(0xFF0F5132), width: 1.5),
                              ),
                              elevation: 2,
                            ),
                            icon: const Icon(Icons.search_rounded),
                            label: const Text('FIND BY NAME',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold)),
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
                                side: const BorderSide(
                                    color: Color(0xFF0F5132), width: 1.5),
                              ),
                              elevation: 2,
                            ),
                            icon: const Icon(Icons.dashboard_rounded),
                            label: const Text('DASHBOARD',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold)),
                            onPressed: () => _showDashboard(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Buttons 4 & 5: Old Customers, Reset Demo
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
                                side: const BorderSide(
                                    color: Color(0xFF0F5132), width: 1.5),
                              ),
                              elevation: 2,
                            ),
                            icon: const Icon(Icons.group_rounded),
                            label: const Text('OLD CUSTOMERS',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold)),
                            onPressed: () => _viewOldCustomers(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(
                                  0xFF842029), // Crimson background for Reset
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 60),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              elevation: 2,
                            ),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('RESET DEMO',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold)),
                            onPressed: () => _resetDemo(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // DEMO QR CODES SECTION
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.0),
                child: Row(
                  children: [
                    Icon(Icons.qr_code_2_rounded, color: Color(0xFFD4AF37)),
                    SizedBox(width: 8),
                    Text(
                      '3 Test Savings Cards (QR Codes)',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF0F5132)),
                    ),
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

  // Helper widget to display the 3 QR cards of the demo clients on screen
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            child: Container(
              width: 140,
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(
                    client['name']!,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  QrImageView(
                    data: client['id']!,
                    version: QrVersions.auto,
                    size: 90.0,
                    gapless: false,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    client['id']!,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    client['desc']!,
                    style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF0F5132),
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ============================================================================
  // WORKFLOW: SCAN CARD (QR CODE SIMULATION & CAM SCREEN)
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
              // In mobile apps, uses actual camera
              MobileScanner(
                onDetect: (capture) {
                  final List<Barcode> barcodes = capture.barcodes;
                  if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                    final String cardId = barcodes.first.rawValue!;
                    Navigator.of(context).pop();
                    _handleScannedCard(cardId);
                  }
                },
              ),
              // Simulated overlay instructions
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      color: Colors.black54,
                      child: const Text(
                        'Align client QR Card inside box',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 30),
                    // Simulated QR scan options for developers in emulator
                    const Text('OR SELECT FOR DEMO',
                        style: TextStyle(
                            color: Colors.white54,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _handleScannedCard('ALAJO-001');
                          },
                          child: const Text('Iya Alata'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _handleScannedCard('ALAJO-002');
                          },
                          child: const Text('Baba Ibadan'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _handleScannedCard('ALAJO-003');
                          },
                          child: const Text('Mama Ngozi'),
                        ),
                      ],
                    )
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
      _showErrorDialog("Invalid card scanned: $cardId");
      return;
    }

    // Modal to add Ajo payment
    int paymentAmount = customer.dailyAmount;
    final textController =
        TextEditingController(text: paymentAmount.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.qr_code_rounded, color: Color(0xFF0F5132)),
            const SizedBox(width: 8),
            Text('Card Scanned: ${customer.name}'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Card Code: ${customer.cardId}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            const SizedBox(height: 6),
            Text('Current Balance: ${currencyFormat.format(customer.balance)}'),
            Text(
                'Expected Daily Contribution: ${currencyFormat.format(customer.dailyAmount)}'),
            const SizedBox(height: 16),
            TextField(
              controller: textController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount to Pay (₦)',
                border: OutlineInputBorder(),
              ),
              onChanged: (val) {
                paymentAmount = int.tryParse(val) ?? customer.dailyAmount;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F5132),
                foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await DatabaseHelper.instance.addCollection(
                  cardId, paymentAmount, 'QR Card Scanned Payment');
              _showSuccessDialog(
                  'Recorded payment of ${currencyFormat.format(paymentAmount)} for ${customer.name}. New Balance: ${currencyFormat.format(customer.balance + paymentAmount)}.');
            },
            child: const Text('Record Ajo'),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // WORKFLOW: FIND BY NAME
  // ============================================================================
  void _findByName(BuildContext context) async {
    final customers = await DatabaseHelper.instance.getCustomers();
    String searchQuery = "";

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = customers
                .where((c) =>
                    c.name.toLowerCase().contains(searchQuery.toLowerCase()))
                .toList();
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
                        hintText: 'Enter name (e.g. Iya, Mama, Tailor)',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        setModalState(() {
                          searchQuery = val;
                        });
                      },
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
                                  leading: const CircleAvatar(
                                    backgroundColor: Color(0xFF0F5132),
                                    foregroundColor: Colors.white,
                                    child: Icon(Icons.person),
                                  ),
                                  title: Text(c.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  subtitle: Text(
                                      '${c.cardId} • Targets ${currencyFormat.format(c.dailyAmount)}/day'),
                                  trailing: const Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 16),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _handleScannedCard(c.cardId);
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

  // ============================================================================
  // WORKFLOW: DASHBOARD OVERVIEW
  // ============================================================================
  void _showDashboard(BuildContext context) async {
    final customers = await DatabaseHelper.instance.getCustomers();
    final contributions = await DatabaseHelper.instance.getContributions();

    int totalSavings = 0;
    for (var c in customers) {
      totalSavings += c.balance;
    }

    int todayCollections = 0;
    // Simple filter of contributions created today or labeled "Just now" / "Voice"
    for (var con in contributions) {
      if (con.datePaid
              .contains(DateFormat('yyyy-MM-dd').format(DateTime.now())) ||
          con.notes.contains('Voice') ||
          con.notes.contains('QR')) {
        todayCollections += con.amountPaid;
      }
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              children: [
                Icon(Icons.dashboard_rounded,
                    color: Color(0xFF0F5132), size: 28),
                SizedBox(width: 8),
                Text('DAILY LEDGER SUMMARY',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        letterSpacing: 1)),
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
                          const Text('Today\'s Collection',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF0F5132))),
                          const SizedBox(height: 6),
                          Text(
                            currencyFormat.format(todayCollections),
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F5132)),
                          ),
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
                          const Text('Grand Total Saved',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF856404))),
                          const SizedBox(height: 6),
                          Text(
                            currencyFormat.format(totalSavings),
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF856404)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.people_alt_rounded,
                  color: Color(0xFF0F5132)),
              title: const Text('Registered Thrift Members'),
              trailing: Text('${customers.length} Accounts',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.history_edu_rounded,
                  color: Color(0xFF0F5132)),
              title: const Text('Total Contributions Ever Logged'),
              trailing: Text('${contributions.length} Deposits',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F5132),
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // WORKFLOW: VIEW OLD CUSTOMERS & HISTORY
  // ============================================================================
  void _viewOldCustomers(BuildContext context) async {
    final customers = await DatabaseHelper.instance.getCustomers();
    final contributions = await DatabaseHelper.instance.getContributions();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.badge_rounded, color: Color(0xFF0F5132)),
            SizedBox(width: 8),
            Text('Old Customers & Ledgers'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: DefaultTabController(
            length: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TabBar(
                  labelColor: Color(0xFF0F5132),
                  indicatorColor: Color(0xFF0F5132),
                  tabs: [
                    Tab(text: "Customers List"),
                    Tab(text: "Ledger History"),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 350,
                  child: TabBarView(
                    children: [
                      // TAB 1: CUSTOMERS LIST
                      ListView.builder(
                        itemCount: customers.length,
                        itemBuilder: (context, i) {
                          final c = customers[i];
                          return Card(
                            color: Colors.white,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              title: Text(c.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle:
                                  Text('ID: ${c.cardId} • Phone: ${c.phone}'),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(currencyFormat.format(c.balance),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green)),
                                  Text('L/C: ${c.lastCollection}',
                                      style: const TextStyle(
                                          fontSize: 10, color: Colors.grey)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      // TAB 2: LEDGER HISTORY
                      ListView.builder(
                        itemCount: contributions.length,
                        itemBuilder: (context, i) {
                          final h = contributions[i];
                          return Card(
                            color: Colors.white,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Color(0xFFD4AF37),
                                child: Icon(Icons.arrow_downward_rounded,
                                    color: Colors.white),
                              ),
                              title: Text(h.customerName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                              subtitle: Text('${h.notes}\n${h.datePaid}',
                                  style: const TextStyle(fontSize: 11)),
                              trailing: Text(
                                  currencyFormat.format(h.amountPaid),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green)),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // WORKFLOW: RESET DEMO DATABASE
  // ============================================================================
  void _resetDemo(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Demo Reset?'),
        content: const Text(
            'This will drop tables and reload standard customers (Iya Alata, Baba Ibadan, Mama Ngozi) with baseline balances and fresh records.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF842029),
                foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await DatabaseHelper.instance.resetDemoDatabase();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Demo Database Reloaded successfully!')),
              );
              setState(() {
                _speechText =
                    "Tap mic and say 'Collect [amount] for [Customer]'";
              });
            },
            child: const Text('Yes, Reload'),
          ),
        ],
      ),
    );
  }
}
