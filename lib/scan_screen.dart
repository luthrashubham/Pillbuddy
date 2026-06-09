import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'history_screen.dart';
import 'remainder_screen.dart';

class ScanScreen extends StatefulWidget {
  @override
  _ScanScreenState createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  String statusMessage = "Enter ESP IP shown on device and fetch scan.";
  Map<String, dynamic>? fetchedMedicine;
  String? currentBarcode;
  bool isBusy = false;

  final DatabaseReference ref = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL:
        'https://abhiyantrix-330d6-default-rtdb.asia-southeast1.firebasedatabase.app/',
  ).ref();

  final TextEditingController ipController = TextEditingController();
  String? savedIP;

  @override
  void initState() {
    super.initState();
    loadSavedIP();
  }

  bool isValidIP(String ip) {
    final regex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
    if (!regex.hasMatch(ip)) return false;

    final parts = ip.split('.');
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return false;
    }
    return true;
  }

  Color getStatusColor() {
    final text = statusMessage.toLowerCase();
    if (text.contains("found") || text.contains("saved")) return Colors.green;
    if (text.contains("error") ||
        text.contains("failed") ||
        text.contains("timeout") ||
        text.contains("not reachable") ||
        text.contains("not responding")) {
      return Colors.red;
    }
    if (text.contains("scanning") ||
        text.contains("checking") ||
        text.contains("fetching") ||
        text.contains("preparing") ||
        text.contains("connecting")) {
      return Colors.orange;
    }
    return Colors.grey;
  }

  Future<void> loadSavedIP() async {
    final prefs = await SharedPreferences.getInstance();
    final ip = prefs.getString('esp_ip');
    if (ip != null) {
      setState(() {
        savedIP = ip;
        ipController.text = ip;
      });
    }
  }

  Future<void> saveIP() async {
    final ip = ipController.text.trim();
    if (!isValidIP(ip)) {
      setState(() => statusMessage = "Invalid IP Format");
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('esp_ip', ip);
    setState(() {
      savedIP = ip;
      statusMessage = "ESP IP saved!";
    });
  }

  Future<void> fetchData(String inputBarcode) async {
    final trimmedBarcode = inputBarcode.trim();
    if (trimmedBarcode.isEmpty) {
      setState(() => statusMessage = "Invalid barcode");
      return;
    }

    setState(() => statusMessage = "Fetching from Firestore...");

    try {
      final doc = await FirebaseFirestore.instance
          .collection('medicines')
          .doc(trimmedBarcode)
          .get();

      if (doc.exists && doc.data() != null) {
        setState(() {
          fetchedMedicine = doc.data();
          currentBarcode = trimmedBarcode;
          statusMessage = "Medicine found!";
        });
      } else {
        setState(() {
          fetchedMedicine = null;
          statusMessage = "Medicine not found in Firestore";
        });
      }
    } catch (e) {
      print("Firestore Error: $e");
      setState(() => statusMessage = "Firestore Error");
    }
  }

  Future<String?> _readBarcodeFromRTDB() async {
    try {
      final snapshot = await ref.child('hardware_scans/latest/barcode').get();

      print("RTDB barcode snapshot = ${snapshot.value}");

      if (snapshot.exists && snapshot.value != null) {
        return snapshot.value.toString().trim();
      }
    } catch (e) {
      print("RTDB Error: $e");
    }
    return null;
  }

  Future<String?> _waitForBarcodeUpload() async {
    const int maxTries = 20;

    for (int i = 0; i < maxTries; i++) {
      if (!mounted) return null;

      setState(() => statusMessage = "Checking RTDB (${i + 1}/20)");
      await Future.delayed(const Duration(seconds: 1));

      final barcode = await _readBarcodeFromRTDB();
      if (barcode != null && barcode.isNotEmpty) return barcode;
    }
    return null;
  }

  Future<void> _startHardwareScan() async {
    if (isBusy) return;

    if (savedIP == null || savedIP!.isEmpty) {
      setState(() {
        statusMessage = "Please enter ESP IP first";
        fetchedMedicine = null;
      });
      return;
    }

    setState(() {
      isBusy = true;
      fetchedMedicine = null;
      currentBarcode = null;
      statusMessage = "Preparing scanner...";
    });

    try {
      await ref.child('hardware_scans/latest').remove();
      print("Old RTDB data cleared.");

      final response = await http
          .get(Uri.parse("http://$savedIP/scan"))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final barcode = await _waitForBarcodeUpload();

        if (barcode == null) {
          setState(() {
            statusMessage = "Scan to get data";
            fetchedMedicine = null;
          });
          return;
        }

        setState(() {
          statusMessage = "Barcode received: $barcode";
        });

        await fetchData(barcode);
      } else {
        setState(() => statusMessage = "ESP not responding");
      }
    } catch (e) {
      print("HTTP Error: $e");
      setState(() => statusMessage = "ESP not reachable. Check WiFi");
    } finally {
      if (mounted) setState(() => isBusy = false);
    }
  }

  Future<void> _saveMedicineWithDetails({
    required int dose,
    required List<String> periods,
  }) async {
    if (fetchedMedicine == null || currentBarcode == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('history')
        .add({
      ...fetchedMedicine!,
      'barcode': currentBarcode,
      'dosePerDay': dose,
      'doseTiming': periods,
      'timestamp': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Medicine saved to history")));
  }

  void _showDoseDialog() {
    int dose = 1;
    final List<String> periods = [];

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Widget localPeriodChip(String label) {
              final selected = periods.contains(label);
              final bool reachedLimit = periods.length >= dose;
              final bool isDisabled = !selected && reachedLimit;

              return FilterChip(
                label: Text(label),
                selected: selected,
                onSelected: isDisabled
                    ? null
                    : (value) {
                        setDialogState(() {
                          if (value) {
                            periods.add(label);
                          } else {
                            periods.remove(label);
                          }
                        });
                      },
              );
            }

            Future<void> handleSave({required bool openReminder}) async {
              if (periods.length != dose) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      "Please select exactly $dose timing${dose > 1 ? 's' : ''} for $dose dose${dose > 1 ? 's' : ''}.",
                    ),
                  ),
                );
                return;
              }

              Navigator.pop(dialogContext);

              await _saveMedicineWithDetails(
                dose: dose,
                periods: List<String>.from(periods),
              );

              if (openReminder) {
                if (!mounted) return;

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RemainderScreen(
                      existingData: {
                        "medicines": [
                          fetchedMedicine!['BrandName'] ?? "Medicine",
                        ],
                        "times": [],
                      },
                    ),
                  ),
                );
              }
            }

            return AlertDialog(
              title: const Text("Save Medicine", textAlign: TextAlign.center),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Dose per day"),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: () {
                            if (dose > 1) {
                              setDialogState(() {
                                dose--;
                                while (periods.length > dose) {
                                  periods.removeLast();
                                }
                              });
                            }
                          },
                          icon: const Icon(
                            Icons.remove_circle,
                            size: 35,
                            color: Colors.red,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          child: Text(
                            "$dose",
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            setDialogState(() => dose++);
                          },
                          icon: const Icon(
                            Icons.add_circle,
                            size: 35,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Preferred timing",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        localPeriodChip("Morning"),
                        localPeriodChip("Afternoon"),
                        localPeriodChip("Evening"),
                        localPeriodChip("Night"),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Selected ${periods.length} of $dose timing${dose > 1 ? 's' : ''}",
                      style: TextStyle(
                        color:
                            periods.length == dose ? Colors.green : Colors.orange,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (periods.length >= dose)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          "Max timings selected for this dose.",
                          style: TextStyle(color: Colors.orange, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => handleSave(openReminder: false),
                  child: const Text("Save Only"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => handleSave(openReminder: true),
                  child: const Text("Add Reminder"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan Medicine"), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.router, color: Colors.deepPurple),
                        SizedBox(width: 8),
                        Text(
                          "ESP Connection",
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: ipController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: "ESP IP Address",
                        prefixIcon: const Icon(Icons.wifi),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: saveIP,
                        icon: const Icon(Icons.save),
                        label: const Text("Save IP"),
                      ),
                    ),
                    if (savedIP != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          "Saved IP: $savedIP",
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isBusy ? null : _startHardwareScan,
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(
                  isBusy ? "Please wait..." : "Fetch Hardware Scan",
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              statusMessage,
              style: TextStyle(
                fontSize: 16,
                color: getStatusColor(),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            if (fetchedMedicine != null) ...[
              const SizedBox(height: 20),
              Card(
                elevation: 5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.medical_services,
                        size: 42,
                        color: Colors.deepPurple,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        fetchedMedicine!['BrandName'] ?? 'Unknown',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const Divider(),
                      Text(
                        "Composition: ${fetchedMedicine!['Composition'] ?? 'N/A'}",
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Pack Size: ${fetchedMedicine!['PackSize'] ?? 'N/A'}",
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _showDoseDialog,
                  icon: const Icon(Icons.medication),
                  label: const Text("Save Medicine to History"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}