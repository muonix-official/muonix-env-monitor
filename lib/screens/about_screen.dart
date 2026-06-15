import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/contact_us_footer.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

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
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
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
                    'Muonix EnvGuard',
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

                  _buildCard(
                    child: Column(
                      children: [
                        _buildInfoRow(Icons.computer, 'Developer', 'Bhoomika Jalandhra'),
                        const Divider(color: Colors.white12),
                        _buildInfoRow(Icons.business, 'Company', 'Muonix Electrosystems LLP'),
                        const Divider(color: Colors.white12),
                        _buildInfoRow(Icons.phone, 'Contact', '+91 92160 60505'),
                        const Divider(color: Colors.white12),
                        _buildInfoRow(Icons.email, 'Email', 'enquiry@muonix.in'),
                        const Divider(color: Colors.white12),
                        _buildInfoRow(Icons.language, 'Website', 'muonix.co.in'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

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
                          'Muonix EnvGuard is an industrial IoT environment monitoring system that provides real-time temperature, humidity and gas level tracking with instant alerts when values exceed safe ranges. Designed for warehouses, factories, and industrial spaces, it supports multiple devices and multiple users with owner-controlled access.',
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
                        _buildFeatureRow(Icons.water_drop, 'Real-time humidity tracking'),
                        _buildFeatureRow(Icons.air, 'Gas leak detection (MQ-6 sensor)'),
                        _buildFeatureRow(Icons.notifications_active, 'Instant sensor alert notifications'),
                        _buildFeatureRow(Icons.wifi_off, 'Device online / offline notifications'),
                        _buildFeatureRow(Icons.history, 'Sensor data history with date filter'),
                        _buildFeatureRow(Icons.qr_code_scanner, 'QR code device pairing'),
                        _buildFeatureRow(Icons.devices, 'Multiple device support'),
                        _buildFeatureRow(Icons.group, 'Multi-user access with owner approval'),
                        _buildFeatureRow(Icons.edit, 'Custom device naming per user'),
                        _buildFeatureRow(Icons.tune, 'Configurable safe range thresholds'),
                        _buildFeatureRow(Icons.hourglass_top, 'Sensor warmup indicator'),
                        _buildFeatureRow(Icons.wifi, 'Auto WiFi reconnect (WiFiManager)'),
                        _buildFeatureRow(Icons.fingerprint, 'MAC address-based device identity'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  _buildCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hardware',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildFeatureRow(Icons.developer_board, 'NodeMCU ESP8266 microcontroller'),
                        _buildFeatureRow(Icons.thermostat, 'DHT11 temperature & humidity sensor'),
                        _buildFeatureRow(Icons.sensors, 'MQ-6 gas sensor (LPG / propane detection)'),
                        _buildFeatureRow(Icons.cloud, 'Firebase Realtime Database integration'),
                        _buildFeatureRow(Icons.update, 'Sensor readings every 5 seconds'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  _buildCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Follow Us',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildLegalRow(context, Icons.facebook, 'Facebook',
                            onTap: () => _launchURL('https://www.facebook.com/people/Muonix-Electrosystems-Jaipur/61582457949982/')),
                        const Divider(color: Colors.white12),
                        _buildLegalRow(context, Icons.work, 'LinkedIn',
                            onTap: () => _launchURL('https://in.linkedin.com/company/muonix-electrosystems')),
                        const Divider(color: Colors.white12),
                        _buildLegalRow(context, Icons.camera_alt, 'Instagram',
                            onTap: () => _launchURL('https://www.instagram.com/muonixelectrosystems/')),
                        const Divider(color: Colors.white12),
                        _buildLegalRow(context, Icons.play_circle, 'YouTube',
                            onTap: () => _launchURL('https://www.youtube.com/@MuonixElectrosystems/shorts')),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  _buildCard(
                    child: Column(
                      children: [
                        _buildLegalRow(
                          context,
                          Icons.privacy_tip,
                          'Privacy Policy',
                          onTap: () => _launchURL(
                              'https://muonix-official.github.io/muonix-env-monitor/privacy-policy.html'),
                        ),
                        const Divider(color: Colors.white12),
                        _buildLegalRow(
                          context,
                          Icons.description,
                          'Terms of Service',
                          onTap: () => _launchURL(
                              'https://muonix-official.github.io/muonix-env-monitor/privacy-policy.html'),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  Text(
                    '© 2025 Muonix Electrosystems LLP, Jaipur\nAll rights reserved.',
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
          ),
          const ContactUsFooter(),
        ],
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
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
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegalRow(BuildContext context, IconData icon, String text,
      {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
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
      ),
    );
  }
}