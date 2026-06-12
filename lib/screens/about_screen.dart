import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1B2A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'About',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Logo
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.blue.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: const Icon(Icons.sensors, size: 52, color: Colors.blue),
            ),

            const SizedBox(height: 16),

            const Text(
              'SensorBox',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 4),

            Text(
              'Version 1.0.0',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 14,
              ),
            ),

            const SizedBox(height: 32),

            // Company card
            _buildCard(
              child: Column(
                children: [
                  _buildInfoRow(Icons.business, 'Company',
                      'Muonix Electrosystem'),
                  const Divider(color: Colors.white12),
                  _buildInfoRow(Icons.location_on, 'Location', 'Jaipur, Rajasthan, India'),
                  const Divider(color: Colors.white12),
                  _buildInfoRow(Icons.email, 'Support',
                      'support@muonix.in'),
                  const Divider(color: Colors.white12),
                  _buildInfoRow(Icons.language, 'Website',
                      'www.muonix.in'),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // App info card
            _buildCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'About This App',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'SensorBox is an IoT-based environment monitoring system that provides real-time temperature, humidity and gas level tracking with instant alerts.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Features card
            _buildCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Features',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureRow(Icons.thermostat, 'Real-time temperature monitoring'),
                  _buildFeatureRow(Icons.water_drop, 'Humidity tracking'),
                  _buildFeatureRow(Icons.air, 'Gas leak detection (MQ-6)'),
                  _buildFeatureRow(Icons.notifications, 'Instant alert notifications'),
                  _buildFeatureRow(Icons.history, 'Data history with date filter'),
                  _buildFeatureRow(Icons.qr_code_scanner, 'QR code device pairing'),
                  _buildFeatureRow(Icons.devices, 'Multiple device support'),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Legal card
            _buildCard(
              child: Column(
                children: [
                  _buildLegalRow(context, Icons.privacy_tip, 'Privacy Policy'),
                  const Divider(color: Colors.white12),
                  _buildLegalRow(context, Icons.description, 'Terms of Service'),
                ],
              ),
            ),

            const SizedBox(height: 32),

            Text(
              '© 2026 Muonix Electrosystem, Jaipur\nAll rights reserved.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.25),
                fontSize: 12,
                height: 1.6,
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: child,
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue, size: 18),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue, size: 16),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegalRow(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue, size: 18),
          const SizedBox(width: 12),
          Text(
            text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Icon(
            Icons.arrow_forward_ios,
            color: Colors.white.withValues(alpha: 0.3),
            size: 14,
          ),
        ],
      ),
    );
  }
}