import 'package:flutter/material.dart';

import '../../../home/views/widgets/mesh_status.dart';

class MeScreen extends StatelessWidget {
  const MeScreen({super.key, required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(
              "Me",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(width: 12),


            MeshStatus(
              dotColor: isActive ? Color(0xFF0053DB) : Colors.red,
              text: isActive
                  ? "Mesh Active"
                  : "Mesh Inactive",
            ),
          ],
        ),
      ),
    );
  }
}
