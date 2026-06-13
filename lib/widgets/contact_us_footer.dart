import 'package:flutter/material.dart';
import '../screens/contact_us_screen.dart';

class ContactUsFooter extends StatelessWidget {
  const ContactUsFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ContactUsScreen()),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.help_outline,
                size: 14, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(width: 6),
            Text(
              'Need help?  ',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 12,
              ),
            ),
            Text(
              'Contact Us',
              style: TextStyle(
                color: Colors.blue.withValues(alpha: 0.7),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}