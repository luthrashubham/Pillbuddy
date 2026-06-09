import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'profile_screen.dart';
import 'history_screen.dart';
import 'login_screen.dart';
import 'scan_screen.dart';
import 'manage_reminders_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final User? user;
  String userName = "Pill Buddy User";

  @override
  void initState() {
    super.initState();
    user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName;
    if (name != null && name.isNotEmpty) {
      userName = name;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Home")),

      // ✅ DRAWER
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // 🔹 HEADER
            UserAccountsDrawerHeader(
              accountName: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      userName,
                      style: TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              accountEmail: Text(user?.email ?? "No Email"),
              currentAccountPicture: CircleAvatar(
                child: Icon(Icons.person, size: 30),
              ),
            ),

            // 📜 HISTORY
            ListTile(
              leading: Icon(Icons.history),
              title: Text("Medicine History"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => HistoryScreen()),
                );
              },
            ),

            // 📋 MANAGE REMINDERS
            ListTile(
              leading: Icon(Icons.alarm),
              title: Text("Reminders"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ManageRemindersScreen()),
                );
              },
            ),

            // 👤 PROFILE
            ListTile(
              leading: Icon(Icons.person),
              title: Text("Profile"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ProfileScreen()),
                ).then((_) {
                  setState(() {
                    final currentUser = FirebaseAuth.instance.currentUser;
                    final name = currentUser?.displayName;
                    if (name != null && name.isNotEmpty) {
                      userName = name;
                    }
                  });
                });
              },
            ),

            Divider(),

            // 🚪 LOGOUT
            ListTile(
              leading: Icon(Icons.logout),
              title: Text("Logout"),
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                if (!context.mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => LoginScreen()),
                  (route) => false,
                );
              },
            ),
          ],
        ),
      ),

      // ✅ MAIN BODY
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                "Welcome to Pill Buddy!",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: 30),

              // 🔘 SCAN BUTTON
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ScanScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                ),
                child: Text("Scan Medicine"),
              ),

              SizedBox(height: 20),

              // 📡 STATUS TEXT
              Text(
                "Waiting for scan...",
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),

              SizedBox(height: 20),

              // ⏰ REMINDERS BUTTON
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ManageRemindersScreen()),
                  );
                },
                child: Text("Reminders"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
