import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'app.dart';
import 'config.dart';
import 'services/billing.dart';
import 'services/token_store.dart';
import 'services/voice.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final api = HttpMasomoApi(baseUrl: AppConfig.apiBaseUrl);
  runApp(MasomoApp(api: api, tokens: SecureTokenStore(), voice: DeviceVoice(), billing: createBilling(api)));
}
