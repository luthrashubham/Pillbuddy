import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final user = FirebaseAuth.instance.currentUser;
  final TextEditingController nameController = TextEditingController();
  final TextEditingController ageController = TextEditingController();
  final TextEditingController allergiesController = TextEditingController();

  bool isLoading = false;
  bool isEditing = false;
  bool hasSaved = false;

  String selectedGender = "Male"; // default

  @override
  void initState() {
    super.initState();
    nameController.text = user?.displayName ?? "";
    isLoading = true; // Show loading indicator while fetching user data
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();

      if (doc.exists) {
        final data = doc.data()!;

        setState(() {
          // Fallback to name from DB if Auth display name is empty
          if (data.containsKey('name') && nameController.text.isEmpty) {
            nameController.text = data['name'];
          }
          if (data.containsKey('age')) {
            ageController.text = data['age'].toString();
          }
          if (data.containsKey('gender')) {
            selectedGender = data['gender'];
          }
          if (data.containsKey('allergies')) {
            allergiesController.text = data['allergies'];
          }
          isEditing = false;
          isLoading = false;
        });
      } else {
        // Document does not exist. This is a newly signed-up user!
        setState(() {
          isEditing = true; // Force them into edit mode
          isLoading = false;
        });
      }
    } else {
      setState(() => isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (user == null) return;
    setState(() => isLoading = true);

    try {
      final newName = nameController.text.trim();
      final newAge = ageController.text.trim();
      final parsedAge = int.tryParse(newAge);
      final allergies = allergiesController.text.trim();

      if (newName.isNotEmpty && newName != user!.displayName) {
        await user!.updateDisplayName(newName);
      }

      await FirebaseFirestore.instance.collection('users').doc(user!.uid).set({
        'name': newName,
        'age': parsedAge ?? newAge,
        'gender': selectedGender,
        'allergies': allergies,
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile updated successfully!")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error saving profile: $e")));
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          isEditing = false;
          hasSaved = true;
        });
      }
    }
  }

  Widget buildGenderSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Gender",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Row(
          children: ["Male", "Female", "Others"].map((gender) {
            return Row(
              children: [
                Radio<String>(
                  value: gender,
                  groupValue: selectedGender,
                  onChanged: isEditing
                      ? (value) {
                          setState(() {
                            selectedGender = value!;
                          });
                        }
                      : null,
                ),
                Text(gender),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Profile")),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(radius: 50, child: Icon(Icons.person, size: 50)),
              SizedBox(height: 20),
              Text(
                "Logged in as:\n${user?.email}",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              SizedBox(height: 30),

              TextField(
                controller: nameController,
                readOnly: !isEditing,
                decoration: InputDecoration(
                  labelText: "Name",
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                  filled: !isEditing,
                  fillColor: Colors.grey.shade200,
                ),
              ),

              SizedBox(height: 16),

              TextField(
                controller: ageController,
                keyboardType: TextInputType.number,
                readOnly: !isEditing,
                decoration: InputDecoration(
                  labelText: "Age",
                  prefixIcon: Icon(Icons.cake),
                  border: OutlineInputBorder(),
                  filled: !isEditing,
                  fillColor: Colors.grey.shade200,
                ),
              ),

              SizedBox(height: 20),

              // 🔵 GENDER SELECTOR
              buildGenderSelector(),

              SizedBox(height: 20),

              // 🔴 ALLERGIES FIELD
              TextField(
                controller: allergiesController,
                readOnly: !isEditing,
                decoration: InputDecoration(
                  labelText: "Allergies (optional)",
                  prefixIcon: Icon(Icons.warning_amber_rounded),
                  border: OutlineInputBorder(),
                  filled: !isEditing,
                  fillColor: Colors.grey.shade200,
                ),
              ),

              SizedBox(height: 24),

              isLoading
                  ? CircularProgressIndicator()
                  : isEditing
                  ? ElevatedButton(
                      onPressed: _saveProfile,
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 15,
                        ),
                      ),
                      child: Text("Save Profile"),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (hasSaved) ...[
                          Icon(Icons.check_circle, color: Colors.green),
                          SizedBox(width: 8),
                          Text(
                            "Saved",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          SizedBox(width: 16),
                        ],
                        TextButton.icon(
                          icon: Icon(Icons.edit, color: Colors.deepPurple),
                          label: Text(
                            "Edit Profile",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepPurple,
                            ),
                          ),
                          onPressed: () {
                            setState(() {
                              isEditing = true;
                              hasSaved = false;
                            });
                          },
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
