import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app_language.dart';

/// Class providing localized strings across the HealthKicks mobile application.
/// Supports French, English, Dutch, Spanish, German, Arabic, and Chinese.
class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('fr'));
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  String get languageCode => locale.languageCode;

  String translate(String key, [Map<String, String>? params]) {
    final langDict = _localizedValues[languageCode] ?? _localizedValues['fr']!;
    var value = langDict[key] ?? _localizedValues['fr']![key] ?? key;
    if (params != null) {
      params.forEach((paramKey, paramVal) {
        value = value.replaceAll('{$paramKey}', paramVal);
      });
    }
    return value;
  }

  // --- Common & Actions ---
  String get appName => translate('app_name');
  String get loading => translate('loading');
  String get save => translate('save');
  String get cancel => translate('cancel');
  String get close => translate('close');
  String get retry => translate('retry');
  String get refresh => translate('refresh');
  String get confirm => translate('confirm');
  String get viewAll => translate('view_all');
  String get connected => translate('connected');
  String get disconnected => translate('disconnected');
  String get status => translate('status');
  String get details => translate('details');
  String get error => translate('error');
  String get success => translate('success');
  String get active => translate('active');
  String get inactive => translate('inactive');

  // --- Authentication ---
  String get loginTitle => translate('login_title');
  String get loginSubtitle => translate('login_subtitle');
  String get emailLabel => translate('email_label');
  String get passwordLabel => translate('password_label');
  String get loginButton => translate('login_button');
  String get logout => translate('logout');
  String get sessionChecking => translate('session_checking');
  String get invalidCredentials => translate('invalid_credentials');

  // --- Dashboard ---
  String get dashboardTitle => translate('dashboard_title');
  String get bluetoothCardTitle => translate('ble_card_title');
  String get cloudCardTitle => translate('cloud_card_title');
  String get testHaptic => translate('test_haptic');
  String get testHapticDesc => translate('test_haptic_desc');
  String get studioSessionButton => translate('studio_session_btn');
  String get hapticSuccess => translate('haptic_success');

  // --- Steps & Pedometer ---
  String get stepsToday => translate('steps_today');
  String get stepsGoal => translate('steps_goal');
  String get cadence => translate('cadence');
  String get spmUnit => translate('spm_unit');
  String get stepsHistory => translate('steps_history');
  String get syncSteps => translate('sync_steps');
  String get stepsSyncSuccess => translate('steps_sync_success');

  // --- Activities & Falls ---
  String get recentActivities => translate('recent_activities');
  String get waitingDetections => translate('waiting_detections');
  String get fallBadge => translate('fall_badge');

  // --- Settings ---
  String get settingsTitle => translate('settings_title');
  String get bluetoothAndCloud => translate('bluetooth_and_cloud');
  String get bluetoothFootwear => translate('bluetooth_footwear');
  String get cloudIot => translate('cloud_iot');
  String get scanBle => translate('scan_ble');
  String get disconnectBle => translate('disconnect_ble');
  String get reconnectMqtt => translate('reconnect_mqtt');
  String get inactivitySection => translate('inactivity_section');
  String get inactivityTitle => translate('inactivity_title');
  String get inactivityDesc => translate('inactivity_desc');
  String inactivityThreshold(int minutes) =>
      translate('inactivity_threshold', {'minutes': minutes.toString()});
  String inactivityCooldown(int minutes) =>
      translate('inactivity_cooldown', {'minutes': minutes.toString()});
  String get sensorCalibrationSection => translate('sensor_calibration_section');
  String get sensorCalibrationTitle => translate('sensor_calibration_title');
  String get sensorCalibrationDesc => translate('sensor_calibration_desc');
  String get calibrateAction => translate('calibrate_action');
  String get appearanceTheme => translate('appearance_theme');
  String get themeTitle => translate('theme_title');
  String get themeDesc => translate('theme_desc');
  String get themeSystem => translate('theme_system');
  String get themeLight => translate('theme_light');
  String get themeDark => translate('theme_dark');
  String get languageRegion => translate('language_region');
  String get languageTitle => translate('language_title');
  String get languageDesc => translate('language_desc');
  String get systemInfo => translate('system_info');
  String get firmwareUpdate => translate('firmware_update');
  String get eventLogsTitle => translate('event_logs_title');
  String get clearLogs => translate('clear_logs');
  String get exportLogs => translate('export_logs');

  // --- Studio ---
  String get studioTitle => translate('studio_title');
  String get studioSubtitle => translate('studio_subtitle');
  String get studioActivityType => translate('studio_activity_type');
  String get studioStartRecording => translate('studio_start_recording');
  String get studioCountdown => translate('studio_countdown');
  String get studioRecording => translate('studio_recording');
  String get studioTransmitting => translate('studio_transmitting');
  String get studioSuccess => translate('studio_success');
  String get customActivityLabel => translate('custom_activity_label');

  /// Translates specific activity codes or fall types.
  String translateEventType(String eventType) {
    switch (eventType.toLowerCase()) {
      case 'fall_forward':
        return translate('evt_fall_forward');
      case 'fall_backward':
        return translate('evt_fall_backward');
      case 'fall_lateral':
        return translate('evt_fall_lateral');
      case 'fall_recovery':
        return translate('evt_fall_recovery');
      case 'stand_up':
        return translate('evt_stand_up');
      case 'fall_generic':
        return translate('evt_fall_generic');
      case 'fall':
      case 'fall_detected':
        return translate('evt_fall_detected');
      case 'free_fall':
        return translate('evt_free_fall');
      case 'high_impact':
        return translate('evt_high_impact');
      case 'stumble_recover':
        return translate('evt_stumble_recover');
      case 'prolonged_immobility':
        return translate('evt_prolonged_immobility');
      case 'inactivity_alert':
        return translate('evt_inactivity_alert');
      case 'walk':
      case 'walking':
        return translate('evt_walk');
      case 'run':
      case 'running':
        return translate('evt_run');
      case 'stairs_up':
        return translate('evt_stairs_up');
      case 'stairs_down':
        return translate('evt_stairs_down');
      case 'stairs':
        return translate('evt_stairs');
      case 'calibration':
      case 'sensor_calibration':
        return translate('evt_calibration');
      case 'idle':
        return translate('evt_idle');
      case 'sit_down':
      case 'sit':
        return translate('evt_sit_down');
      case 'jump':
        return translate('evt_jump');
      case 'activity_transition':
        return translate('evt_activity_transition');
      default:
        return eventType.replaceAll('_', ' ');
    }
  }

  // --- Dictionaries for all 7 languages ---
  static final Map<String, Map<String, String>> _localizedValues = {
    // 1. Français (FR)
    'fr': {
      'app_name': 'HealthKicks Mobile',
      'loading': 'Chargement…',
      'save': 'Enregistrer',
      'cancel': 'Annuler',
      'close': 'Fermer',
      'retry': 'Réessayer',
      'refresh': 'Actualiser',
      'confirm': 'Confirmer',
      'view_all': 'Voir tout',
      'connected': 'Connecté',
      'disconnected': 'Déconnecté',
      'status': 'Statut',
      'details': 'Détails',
      'error': 'Erreur',
      'success': 'Succès',
      'active': 'Actif',
      'inactive': 'Inactif',
      'login_title': 'Connexion',
      'login_subtitle': 'Accédez à votre espace HealthKicks',
      'email_label': 'Adresse email',
      'password_label': 'Mot de passe',
      'login_button': 'Se connecter',
      'logout': 'Déconnexion',
      'session_checking': 'Vérification de session...',
      'invalid_credentials': 'Email ou mot de passe invalide.',
      'dashboard_title': 'Tableau de bord Passerelle',
      'ble_card_title': 'Bluetooth Low Energy',
      'cloud_card_title': 'AWS IoT Core Cloud',
      'test_haptic': 'Test Haptique',
      'test_haptic_desc': 'Déclencher une impulsion vibrotactile',
      'studio_session_btn': 'Session Studio',
      'haptic_success': 'Vibration envoyée avec succès',
      'steps_today': 'Pas aujourd\'hui',
      'steps_goal': 'Objectif : {goal} pas',
      'cadence': 'Cadence',
      'spm_unit': 'PPM',
      'steps_history': 'Historique du Podomètre',
      'sync_steps': 'Synchroniser les pas',
      'steps_sync_success': 'Pas synchronisés avec succès',
      'recent_activities': 'Activités récentes',
      'waiting_detections': 'En attente de détections...',
      'fall_badge': 'CHUTE',
      'settings_title': 'Paramètres',
      'bluetooth_and_cloud': 'BLUETOOTH & CLOUD',
      'bluetooth_footwear': 'Chaussure connectée (BLE)',
      'cloud_iot': 'Passerelle Cloud (AWS IoT)',
      'scan_ble': 'Rechercher',
      'disconnect_ble': 'Déconnecter',
      'reconnect_mqtt': 'Reconnecter Cloud',
      'inactivity_section': 'RAPPEL D\'INACTIVITÉ PROLONGÉE',
      'inactivity_title': 'Rappel d\'inactivité prolongée',
      'inactivity_desc':
          'Fait vibrer discrètement la chaussure après une longue période assis sans marcher',
      'inactivity_threshold': 'Durée avant alerte : {minutes} minutes',
      'inactivity_cooldown': 'Délai de répétition : {minutes} minutes',
      'sensor_calibration_section': 'CALIBRATION DU CAPTEUR',
      'sensor_calibration_title': 'Calibration de l\'inclinaison',
      'sensor_calibration_desc':
          'Réétalonnez le capteur IMU pour un comptage et une orientation optimaux',
      'calibrate_action': 'Calibrer',
      'appearance_theme': 'APPARENCE & THÈME',
      'theme_title': 'Thème de l\'application',
      'theme_desc': 'Choisissez le mode d\'affichage clair, sombre ou automatique.',
      'theme_system': 'Système',
      'theme_light': 'Clair',
      'theme_dark': 'Sombre',
      'language_region': 'LANGUE & RÉGION',
      'language_title': 'Langue de l\'application',
      'language_desc': 'Choisissez la langue d\'affichage de l\'application.',
      'system_info': 'INFORMATIONS SYSTÈME',
      'firmware_update': 'Mise à jour du firmware (OTA)',
      'event_logs_title': 'Journal d\'événements',
      'clear_logs': 'Effacer les logs',
      'export_logs': 'Exporter par email',
      'studio_title': 'Session d\'enregistrement Studio',
      'studio_subtitle': 'Capture biomécanique haute fréquence à 54 Hz',
      'studio_activity_type': 'Type d\'activité',
      'studio_start_recording': 'Démarrer l\'enregistrement',
      'studio_countdown': 'Préparez-vous : {step}/3',
      'studio_recording': 'Enregistrement en cours...',
      'studio_transmitting': 'Synchronisation des données biomécaniques...',
      'studio_success': 'Capture terminée avec succès !',
      'custom_activity_label': 'Autre / Personnalisé',
      'evt_fall_forward': 'Chute avant',
      'evt_fall_backward': 'Chute arrière',
      'evt_fall_lateral': 'Chute latérale',
      'evt_fall_recovery': 'Chute relevée',
      'evt_stand_up': 'Relevage après chute',
      'evt_fall_generic': 'Chute',
      'evt_fall_detected': 'Chute détectée',
      'evt_free_fall': 'Chute libre (Impact violent)',
      'evt_high_impact': 'Impact élevé',
      'evt_stumble_recover': 'Trébuchement rattrapé',
      'evt_prolonged_immobility': 'Immobilité prolongée',
      'evt_inactivity_alert': 'Rappel inactivité',
      'evt_walk': 'Marche',
      'evt_run': 'Course',
      'evt_stairs': 'Escaliers',
      'evt_stairs_up': 'Escaliers (Montée)',
      'evt_stairs_down': 'Escaliers (Descente)',
      'evt_calibration': 'Calibration des capteurs',
      'evt_idle': 'Immobile',
      'evt_sit_down': 'Position assise',
      'evt_jump': 'Saut',
      'evt_activity_transition': 'Transition d\'activité',
    },

    // 2. English (EN)
    'en': {
      'app_name': 'HealthKicks Mobile',
      'loading': 'Loading…',
      'save': 'Save',
      'cancel': 'Cancel',
      'close': 'Close',
      'retry': 'Retry',
      'refresh': 'Refresh',
      'confirm': 'Confirm',
      'view_all': 'View all',
      'connected': 'Connected',
      'disconnected': 'Disconnected',
      'status': 'Status',
      'details': 'Details',
      'error': 'Error',
      'success': 'Success',
      'active': 'Active',
      'inactive': 'Inactive',
      'login_title': 'Sign In',
      'login_subtitle': 'Access your HealthKicks space',
      'email_label': 'Email address',
      'password_label': 'Password',
      'login_button': 'Sign In',
      'logout': 'Log Out',
      'session_checking': 'Checking session...',
      'invalid_credentials': 'Invalid email or password.',
      'dashboard_title': 'Gateway Dashboard',
      'ble_card_title': 'Bluetooth Low Energy',
      'cloud_card_title': 'AWS IoT Core Cloud',
      'test_haptic': 'Haptic Test',
      'test_haptic_desc': 'Trigger a vibrotactile pulse',
      'studio_session_btn': 'Studio Session',
      'haptic_success': 'Vibration sent successfully',
      'steps_today': 'Steps today',
      'steps_goal': 'Goal: {goal} steps',
      'cadence': 'Cadence',
      'spm_unit': 'SPM',
      'steps_history': 'Pedometer History',
      'sync_steps': 'Sync steps',
      'steps_sync_success': 'Steps synchronized successfully',
      'recent_activities': 'Recent activities',
      'waiting_detections': 'Waiting for detections...',
      'fall_badge': 'FALL',
      'settings_title': 'Settings',
      'bluetooth_and_cloud': 'BLUETOOTH & CLOUD',
      'bluetooth_footwear': 'Connected footwear (BLE)',
      'cloud_iot': 'Cloud Gateway (AWS IoT)',
      'scan_ble': 'Scan',
      'disconnect_ble': 'Disconnect',
      'reconnect_mqtt': 'Reconnect Cloud',
      'inactivity_section': 'PROLONGED INACTIVITY REMINDER',
      'inactivity_title': 'Prolonged inactivity reminder',
      'inactivity_desc':
          'Discreetly vibrates the shoe after a long period of sitting without walking',
      'inactivity_threshold': 'Duration before alert: {minutes} minutes',
      'inactivity_cooldown': 'Repeat delay: {minutes} minutes',
      'sensor_calibration_section': 'SENSOR CALIBRATION',
      'sensor_calibration_title': 'Tilt Calibration',
      'sensor_calibration_desc':
          'Recalibrate IMU sensor for optimal step counting and orientation',
      'calibrate_action': 'Calibrate',
      'appearance_theme': 'APPEARANCE & THEME',
      'theme_title': 'Application theme',
      'theme_desc': 'Choose light, dark, or automatic system theme.',
      'theme_system': 'System',
      'theme_light': 'Light',
      'theme_dark': 'Dark',
      'language_region': 'LANGUAGE & REGION',
      'language_title': 'Application language',
      'language_desc': 'Select your preferred display language.',
      'system_info': 'SYSTEM INFORMATION',
      'firmware_update': 'Firmware update (OTA)',
      'event_logs_title': 'Event Logs',
      'clear_logs': 'Clear logs',
      'export_logs': 'Export by email',
      'studio_title': 'Studio Recording Session',
      'studio_subtitle': 'High-frequency 54 Hz biomechanical capture',
      'studio_activity_type': 'Activity type',
      'studio_start_recording': 'Start recording',
      'studio_countdown': 'Get ready: {step}/3',
      'studio_recording': 'Recording in progress...',
      'studio_transmitting': 'Syncing biomechanical telemetry...',
      'studio_success': 'Capture completed successfully!',
      'custom_activity_label': 'Other / Custom',
      'evt_fall_forward': 'Forward fall',
      'evt_fall_backward': 'Backward fall',
      'evt_fall_lateral': 'Lateral fall',
      'evt_fall_recovery': 'Recovered fall',
      'evt_stand_up': 'Standing up',
      'evt_fall_generic': 'Fall',
      'evt_fall_detected': 'Fall detected',
      'evt_free_fall': 'Free fall (high impact)',
      'evt_high_impact': 'High impact',
      'evt_stumble_recover': 'Stumble recovered',
      'evt_prolonged_immobility': 'Prolonged immobility',
      'evt_inactivity_alert': 'Inactivity reminder',
      'evt_walk': 'Walking',
      'evt_run': 'Running',
      'evt_stairs': 'Stairs',
      'evt_stairs_up': 'Stairs (Ascent)',
      'evt_stairs_down': 'Stairs (Descent)',
      'evt_calibration': 'Sensor calibration',
      'evt_idle': 'Idle',
      'evt_sit_down': 'Seated',
      'evt_jump': 'Jump',
      'evt_activity_transition': 'Activity transition',
    },

    // 3. Nederlands (NL)
    'nl': {
      'app_name': 'HealthKicks Mobiel',
      'loading': 'Laden…',
      'save': 'Opslaan',
      'cancel': 'Annuleren',
      'close': 'Sluiten',
      'retry': 'Opnieuw proberen',
      'refresh': 'Vernieuwen',
      'confirm': 'Bevestigen',
      'view_all': 'Alles bekijken',
      'connected': 'Verbonden',
      'disconnected': 'Niet verbonden',
      'status': 'Status',
      'details': 'Details',
      'error': 'Fout',
      'success': 'Succes',
      'active': 'Actief',
      'inactive': 'Inactief',
      'login_title': 'Inloggen',
      'login_subtitle': 'Toegang tot uw HealthKicks-ruimte',
      'email_label': 'E-mailadres',
      'password_label': 'Wachtwoord',
      'login_button': 'Inloggen',
      'logout': 'Uitloggen',
      'session_checking': 'Sessie controleren...',
      'invalid_credentials': 'Ongeldig e-mailadres of wachtwoord.',
      'dashboard_title': 'Gateway Dashboard',
      'ble_card_title': 'Bluetooth Low Energy',
      'cloud_card_title': 'AWS IoT Core Cloud',
      'test_haptic': 'Haptische test',
      'test_haptic_desc': 'Een trillingspuls verzenden',
      'studio_session_btn': 'Studio-sessie',
      'haptic_success': 'Trilling succesvol verzonden',
      'steps_today': 'Stappen vandaag',
      'steps_goal': 'Doel: {goal} stappen',
      'cadence': 'Cadans',
      'spm_unit': 'SPM',
      'steps_history': 'Stappengeschiedenis',
      'sync_steps': 'Stappen synchroniseren',
      'steps_sync_success': 'Stappen succesvol gesynchroniseerd',
      'recent_activities': 'Recente activiteiten',
      'waiting_detections': 'Wachten op detecties...',
      'fall_badge': 'VAL',
      'settings_title': 'Instellingen',
      'bluetooth_and_cloud': 'BLUETOOTH & CLOUD',
      'bluetooth_footwear': 'Verbonden schoen (BLE)',
      'cloud_iot': 'Cloud Gateway (AWS IoT)',
      'scan_ble': 'Zoeken',
      'disconnect_ble': 'Verbinding verbreken',
      'reconnect_mqtt': 'Cloud opnieuw verbinden',
      'inactivity_section': 'HERINNERING LANGE INACTIVITEIT',
      'inactivity_title': 'Herinnering lange inactiviteit',
      'inactivity_desc':
          'Laat de schoen discreet trillen na een lange periode stilzitten',
      'inactivity_threshold': 'Tijd voor melding: {minutes} minuten',
      'inactivity_cooldown': 'Herhaaltijd: {minutes} minuten',
      'sensor_calibration_section': 'SENSOR KALIBRATIE',
      'sensor_calibration_title': 'Hellingshoekkalibratie',
      'sensor_calibration_desc':
          'Kalibreer de IMU-sensor voor optimale stapmeting en oriëntatie',
      'calibrate_action': 'Kalibreren',
      'appearance_theme': 'UITERLIJK & THEMA',
      'theme_title': 'Applicatiethema',
      'theme_desc': 'Kies licht, donker of automatisch systeemthema.',
      'theme_system': 'Systeem',
      'theme_light': 'Licht',
      'theme_dark': 'Donker',
      'language_region': 'TAAL & REGIO',
      'language_title': 'Applicatietaal',
      'language_desc': 'Kies uw gewenste weergavetaal.',
      'system_info': 'SYSTEEMINFORMATIE',
      'firmware_update': 'Firmware-update (OTA)',
      'event_logs_title': 'Gebeurtenissenlogboek',
      'clear_logs': 'Logboek wissen',
      'export_logs': 'Exporteren via e-mail',
      'studio_title': 'Studio-opnamesessie',
      'studio_subtitle': 'Hoge-frequentie 54 Hz biomechanische registratie',
      'studio_activity_type': 'Type activiteit',
      'studio_start_recording': 'Opname starten',
      'studio_countdown': 'Bereid u voor: {step}/3',
      'studio_recording': 'Opname bezig...',
      'studio_transmitting': 'Biomechanische gegevens synchroniseren...',
      'studio_success': 'Opname succesvol voltooid!',
      'custom_activity_label': 'Overig / Aangepast',
      'evt_fall_forward': 'Val voorover',
      'evt_fall_backward': 'Val achterover',
      'evt_fall_lateral': 'Zijwaartse val',
      'evt_fall_recovery': 'Herstelde val',
      'evt_stand_up': 'Opstaan',
      'evt_fall_generic': 'Val',
      'evt_fall_detected': 'Val gedetecteerd',
      'evt_free_fall': 'Vrije val (zware impact)',
      'evt_high_impact': 'Hoge impact',
      'evt_stumble_recover': 'Herstelde struikeling',
      'evt_prolonged_immobility': 'Langdurige immobiliteit',
      'evt_inactivity_alert': 'Inactiviteitsherinnering',
      'evt_walk': 'Lopen',
      'evt_run': 'Hardlopen',
      'evt_stairs': 'Trappen',
      'evt_stairs_up': 'Trappen (Omhoog)',
      'evt_stairs_down': 'Trappen (Omlaag)',
      'evt_calibration': 'Sensorkalibratie',
      'evt_idle': 'Stilstaand / Zittend',
      'evt_sit_down': 'Zittend',
      'evt_jump': 'Sprong',
      'evt_activity_transition': 'Activiteitsovergang',
    },

    // 4. Español (ES)
    'es': {
      'app_name': 'HealthKicks Móvil',
      'loading': 'Cargando…',
      'save': 'Guardar',
      'cancel': 'Cancelar',
      'close': 'Cerrar',
      'retry': 'Reintentar',
      'refresh': 'Actualizar',
      'confirm': 'Confirmar',
      'view_all': 'Ver todo',
      'connected': 'Conectado',
      'disconnected': 'Desconectado',
      'status': 'Estado',
      'details': 'Detalles',
      'error': 'Error',
      'success': 'Éxito',
      'active': 'Activo',
      'inactive': 'Inactivo',
      'login_title': 'Iniciar Sesión',
      'login_subtitle': 'Acceda a su espacio HealthKicks',
      'email_label': 'Correo electrónico',
      'password_label': 'Contraseña',
      'login_button': 'Iniciar Sesión',
      'logout': 'Cerrar Sesión',
      'session_checking': 'Comprobando sesión...',
      'invalid_credentials': 'Email o contraseña inválidos.',
      'dashboard_title': 'Panel de Control Gateway',
      'ble_card_title': 'Bluetooth Low Energy',
      'cloud_card_title': 'AWS IoT Core Cloud',
      'test_haptic': 'Prueba Háptica',
      'test_haptic_desc': 'Activar pulso vibrotáctil',
      'studio_session_btn': 'Sesión Studio',
      'haptic_success': 'Vibración enviada con éxito',
      'steps_today': 'Pasos hoy',
      'steps_goal': 'Objetivo: {goal} pasos',
      'cadence': 'Cadencia',
      'spm_unit': 'PPM',
      'steps_history': 'Historial del Podómetro',
      'sync_steps': 'Sincronizar pasos',
      'steps_sync_success': 'Pasos sincronizados con éxito',
      'recent_activities': 'Actividades recientes',
      'waiting_detections': 'Esperando detecciones...',
      'fall_badge': 'CAÍDA',
      'settings_title': 'Configuración',
      'bluetooth_and_cloud': 'BLUETOOTH Y CLOUD',
      'bluetooth_footwear': 'Calzado conectado (BLE)',
      'cloud_iot': 'Pasarela Cloud (AWS IoT)',
      'scan_ble': 'Buscar',
      'disconnect_ble': 'Desconectar',
      'reconnect_mqtt': 'Reconectar Cloud',
      'inactivity_section': 'RECORDATORIO DE INACTIVIDAD',
      'inactivity_title': 'Recordatorio de inactividad prolongada',
      'inactivity_desc':
          'Vibra discretamente el calzado tras un largo periodo sentado sin caminar',
      'inactivity_threshold': 'Tiempo antes de alerta: {minutes} minutos',
      'inactivity_cooldown': 'Intervalo de repetición: {minutes} minutos',
      'sensor_calibration_section': 'CALIBRACIÓN DEL SENSOR',
      'sensor_calibration_title': 'Calibración de inclinación',
      'sensor_calibration_desc':
          'Recalibre el sensor IMU para conteo de pasos y orientación óptimos',
      'calibrate_action': 'Calibrar',
      'appearance_theme': 'APARIENCIA Y TEMA',
      'theme_title': 'Tema de la aplicación',
      'theme_desc': 'Elija modo claro, oscuro o automático del sistema.',
      'theme_system': 'Sistema',
      'theme_light': 'Claro',
      'theme_dark': 'Oscuro',
      'language_region': 'IDIOMA Y REGIÓN',
      'language_title': 'Idioma de la aplicación',
      'language_desc': 'Seleccione su idioma de visualización preferido.',
      'system_info': 'INFORMACIÓN DEL SISTEMA',
      'firmware_update': 'Actualización de firmware (OTA)',
      'event_logs_title': 'Registro de eventos',
      'clear_logs': 'Limpiar registros',
      'export_logs': 'Exportar por email',
      'studio_title': 'Sesión de Grabación Studio',
      'studio_subtitle': 'Captura biomecánica de alta frecuencia a 54 Hz',
      'studio_activity_type': 'Tipo de actividad',
      'studio_start_recording': 'Iniciar grabación',
      'studio_countdown': 'Prepárese: {step}/3',
      'studio_recording': 'Grabación en curso...',
      'studio_transmitting': 'Sincronizando datos biomecánicos...',
      'studio_success': '¡Captura completada con éxito!',
      'custom_activity_label': 'Otro / Personalizado',
      'evt_fall_forward': 'Caída frontal',
      'evt_fall_backward': 'Caída hacia atrás',
      'evt_fall_lateral': 'Caída lateral',
      'evt_fall_recovery': 'Caída recuperada',
      'evt_stand_up': 'Levantarse',
      'evt_fall_generic': 'Caída',
      'evt_fall_detected': 'Caída detectada',
      'evt_free_fall': 'Caída libre (fuerte impacto)',
      'evt_high_impact': 'Impacto elevado',
      'evt_stumble_recover': 'Tropiezo recuperado',
      'evt_prolonged_immobility': 'Inmovilidad prolongada',
      'evt_inactivity_alert': 'Aviso de inactividad',
      'evt_walk': 'Caminata',
      'evt_run': 'Carrera',
      'evt_stairs': 'Escaleras',
      'evt_stairs_up': 'Escaleras (Subida)',
      'evt_stairs_down': 'Escaleras (Bajada)',
      'evt_calibration': 'Calibración de sensores',
      'evt_idle': 'En reposo / Sentado',
      'evt_sit_down': 'Sentado',
      'evt_jump': 'Salto',
      'evt_activity_transition': 'Transición de actividad',
    },

    // 5. Deutsch (DE)
    'de': {
      'app_name': 'HealthKicks Mobil',
      'loading': 'Laden…',
      'save': 'Speichern',
      'cancel': 'Abbrechen',
      'close': 'Schließen',
      'retry': 'Wiederholen',
      'refresh': 'Aktualisieren',
      'confirm': 'Bestätigen',
      'view_all': 'Alle anzeigen',
      'connected': 'Verbunden',
      'disconnected': 'Getrennt',
      'status': 'Status',
      'details': 'Details',
      'error': 'Fehler',
      'success': 'Erfolg',
      'active': 'Aktiv',
      'inactive': 'Inaktiv',
      'login_title': 'Anmelden',
      'login_subtitle': 'Greifen Sie auf Ihr HealthKicks-Konto zu',
      'email_label': 'E-Mail-Adresse',
      'password_label': 'Passwort',
      'login_button': 'Anmelden',
      'logout': 'Abmelden',
      'session_checking': 'Sitzung wird überprüft...',
      'invalid_credentials': 'Ungültige E-Mail-Adresse oder Passwort.',
      'dashboard_title': 'Gateway-Dashboard',
      'ble_card_title': 'Bluetooth Low Energy',
      'cloud_card_title': 'AWS IoT Core Cloud',
      'test_haptic': 'Haptik-Test',
      'test_haptic_desc': 'Vibrationsimpuls auslösen',
      'studio_session_btn': 'Studio-Sitzung',
      'haptic_success': 'Vibration erfolgreich gesendet',
      'steps_today': 'Schritte heute',
      'steps_goal': 'Ziel: {goal} Schritte',
      'cadence': 'Kadenz',
      'spm_unit': 'SPM',
      'steps_history': 'Schrittverlauf',
      'sync_steps': 'Schritte synchronisieren',
      'steps_sync_success': 'Schritte erfolgreich synchronisiert',
      'recent_activities': 'Aktuelle Aktivitäten',
      'waiting_detections': 'Warten auf Erkennungen...',
      'fall_badge': 'STURZ',
      'settings_title': 'Einstellungen',
      'bluetooth_and_cloud': 'BLUETOOTH & CLOUD',
      'bluetooth_footwear': 'Verbundener Schuh (BLE)',
      'cloud_iot': 'Cloud-Gateway (AWS IoT)',
      'scan_ble': 'Suchen',
      'disconnect_ble': 'Trennen',
      'reconnect_mqtt': 'Cloud neu verbinden',
      'inactivity_section': 'INAKTIVITÄTS-ERINNERUNG',
      'inactivity_title': 'Erinnerung bei langer Inaktivität',
      'inactivity_desc':
          'Lässt den Schuh nach längerem Sitzen ohne Bewegung dezent vibrieren',
      'inactivity_threshold': 'Dauer vor Alarm: {minutes} Minuten',
      'inactivity_cooldown': 'Wiederholungsverzögerung: {minutes} Minuten',
      'sensor_calibration_section': 'SENSOR-KALIBRIERUNG',
      'sensor_calibration_title': 'Neigungskalibrierung',
      'sensor_calibration_desc':
          'Kalibrieren Sie den IMU-Sensor für optimale Schritterkennung',
      'calibrate_action': 'Kalibrieren',
      'appearance_theme': 'ERSCHEINUNGSBILD & THEMA',
      'theme_title': 'App-Thema',
      'theme_desc': 'Wählen Sie helles, dunkles oder System-Design.',
      'theme_system': 'System',
      'theme_light': 'Hell',
      'theme_dark': 'Dunkel',
      'language_region': 'SPRACHE & REGION',
      'language_title': 'App-Sprache',
      'language_desc': 'Wählen Sie Ihre bevorzugte Anzeigesprache.',
      'system_info': 'SYSTEMINFORMATIONEN',
      'firmware_update': 'Firmware-Aktualisierung (OTA)',
      'event_logs_title': 'Ereignisprotokoll',
      'clear_logs': 'Protokoll löschen',
      'export_logs': 'Per E-Mail exportieren',
      'studio_title': 'Studio-Aufnahmesitzung',
      'studio_subtitle': 'Hochfrequente biomechanische 54-Hz-Erfassung',
      'studio_activity_type': 'Aktivitätstyp',
      'studio_start_recording': 'Aufnahme starten',
      'studio_countdown': 'Bereitmachen: {step}/3',
      'studio_recording': 'Aufnahme läuft...',
      'studio_transmitting': 'Biomechanische Daten werden übertragen...',
      'studio_success': 'Aufnahme erfolgreich abgeschlossen!',
      'custom_activity_label': 'Andere / Benutzerdefiniert',
      'evt_fall_forward': 'Sturz vorwärts',
      'evt_fall_backward': 'Sturz rückwärts',
      'evt_fall_lateral': 'Seitlicher Sturz',
      'evt_fall_recovery': 'Wiederaufgerichteter Sturz',
      'evt_stand_up': 'Aufstehen',
      'evt_fall_generic': 'Sturz',
      'evt_fall_detected': 'Sturz erkannt',
      'evt_free_fall': 'Freier Fall (harter Aufprall)',
      'evt_high_impact': 'Starker Aufprall',
      'evt_stumble_recover': 'Stolpern abgefangen',
      'evt_prolonged_immobility': 'Längere Bewegungslosigkeit',
      'evt_inactivity_alert': 'Inaktivitäts-Erinnerung',
      'evt_walk': 'Gehen',
      'evt_run': 'Laufen',
      'evt_stairs': 'Treppen',
      'evt_stairs_up': 'Treppen (Aufwärts)',
      'evt_stairs_down': 'Treppen (Abwärts)',
      'evt_calibration': 'Sensorkalibrierung',
      'evt_idle': 'Ruhe / Sitzen',
      'evt_sit_down': 'Sitzend',
      'evt_jump': 'Sprung',
      'evt_activity_transition': 'Aktivitätsübergang',
    },

    // 6. العربية (AR) - RTL
    'ar': {
      'app_name': 'هيلث كيكس موبايل',
      'loading': 'جارٍ التحميل…',
      'save': 'حفظ',
      'cancel': 'إلغاء',
      'close': 'إغلاق',
      'retry': 'إعادة المحاولة',
      'refresh': 'تحديث',
      'confirm': 'تأكيد',
      'view_all': 'عرض الكل',
      'connected': 'متصل',
      'disconnected': 'غير متصل',
      'status': 'الحالة',
      'details': 'التفاصيل',
      'error': 'خطأ',
      'success': 'نجاح',
      'active': 'نشط',
      'inactive': 'غير نشط',
      'login_title': 'تسجيل الدخول',
      'login_subtitle': 'ادخل إلى مساحتك في هيلث كيكس',
      'email_label': 'البريد الإلكتروني',
      'password_label': 'كلمة المرور',
      'login_button': 'تسجيل الدخول',
      'logout': 'تسجيل الخروج',
      'session_checking': 'جارٍ التحقق من الجلسة...',
      'invalid_credentials': 'البريد الإلكتروني أو كلمة المرور غير صالحة.',
      'dashboard_title': 'لوحة تحكم البوابة',
      'ble_card_title': 'البلوتوث منخفض الطاقة',
      'cloud_card_title': 'سحابة AWS IoT Core',
      'test_haptic': 'اختبار الاهتزاز',
      'test_haptic_desc': 'تشغيل نبضة اهتزازية تجريبية',
      'studio_session_btn': 'جلسة الاستوديو',
      'haptic_success': 'تم إرسال الاهتزاز بنجاح',
      'steps_today': 'خطوات اليوم',
      'steps_goal': 'الهدف: {goal} خطوة',
      'cadence': 'معدل الخطوات',
      'spm_unit': 'خطوة/د',
      'steps_history': 'سجل عداد الخطوات',
      'sync_steps': 'مزامنة الخطوات',
      'steps_sync_success': 'تمت مزامنة الخطوات بنجاح',
      'recent_activities': 'الأنشطة الأخيرة',
      'waiting_detections': 'في انتظار عمليات الرصد...',
      'fall_badge': 'سقوط',
      'settings_title': 'الإعدادات',
      'bluetooth_and_cloud': 'البلوتوث والسحابة',
      'bluetooth_footwear': 'الحذاء المتصل (BLE)',
      'cloud_iot': 'بوابة السحابة (AWS IoT)',
      'scan_ble': 'بحث',
      'disconnect_ble': 'قطع الاتصال',
      'reconnect_mqtt': 'إعادة الاتصال بالسحابة',
      'inactivity_section': 'تنبيه الخمول المطول',
      'inactivity_title': 'تنبيه الخمول المطول',
      'inactivity_desc': 'يهتز الحذاء بهدوء بعد الجلوس لفترة طويلة دون حركة',
      'inactivity_threshold': 'المدة قبل التنبيه: {minutes} دقيقة',
      'inactivity_cooldown': 'مهلة التكرار: {minutes} دقيقة',
      'sensor_calibration_section': 'معايرة الحساس',
      'sensor_calibration_title': 'معايرة زاوية الميل',
      'sensor_calibration_desc':
          'إعادة معايرة حساس IMU لضمان دقة احتساب الخطوات وتحديد الاتجاه',
      'calibrate_action': 'معايرة',
      'appearance_theme': 'المظهر والسمة',
      'theme_title': 'سمة التطبيق',
      'theme_desc': 'اختر الوضع الفاتح أو الداكن أو التلقائي للنظام.',
      'theme_system': 'تلقائي النظام',
      'theme_light': 'فاتح',
      'theme_dark': 'داكن',
      'language_region': 'اللغة والمنطقة',
      'language_title': 'لغة التطبيق',
      'language_desc': 'اختر لغة عرض واجهة التطبيق.',
      'system_info': 'معلومات النظام',
      'firmware_update': 'تحديث البرنامج الثابت (OTA)',
      'event_logs_title': 'سجل الأحداث',
      'clear_logs': 'مسح السجلات',
      'export_logs': 'تصدير عبر البريد',
      'studio_title': 'جلسة تسجيل الاستوديو',
      'studio_subtitle': 'تسجيل حركي حيوي عالي الدقة بتردد 54 هرتز',
      'studio_activity_type': 'نوع النشاط',
      'studio_start_recording': 'بدء التسجيل',
      'studio_countdown': 'استعد: {step}/3',
      'studio_recording': 'التسجيل جارٍ الآن...',
      'studio_transmitting': 'مزامنة البيانات الحركية...',
      'studio_success': 'اكتمل التسجيل بنجاح!',
      'custom_activity_label': 'أخرى / مخصص',
      'evt_fall_forward': 'سقوط إلى الأمام',
      'evt_fall_backward': 'سقوط إلى الخلف',
      'evt_fall_lateral': 'سقوط جانبي',
      'evt_fall_recovery': 'نهوض بعد سقوط',
      'evt_stand_up': 'نهوض',
      'evt_fall_generic': 'سقوط',
      'evt_fall_detected': 'تم رصد سقوط',
      'evt_free_fall': 'سقوط حر (صدمة عنيفة)',
      'evt_high_impact': 'صدمة قوية',
      'evt_stumble_recover': 'تعثر مع استعادة التوازن',
      'evt_prolonged_immobility': 'سكون مطول',
      'evt_inactivity_alert': 'تنبيه الخمول',
      'evt_walk': 'مشي',
      'evt_run': 'جري',
      'evt_stairs': 'درج',
      'evt_stairs_up': 'درج (صعود)',
      'evt_stairs_down': 'درج (نزول)',
      'evt_calibration': 'معايرة الحساسات',
      'evt_idle': 'راحة / جلوس',
      'evt_sit_down': 'جالس',
      'evt_jump': 'قفز',
      'evt_activity_transition': 'تغير النشاط',
    },

    // 7. 中文 (ZH)
    'zh': {
      'app_name': 'HealthKicks 移动端',
      'loading': '加载中…',
      'save': '保存',
      'cancel': '取消',
      'close': '关闭',
      'retry': '重试',
      'refresh': '刷新',
      'confirm': '确认',
      'view_all': '查看全部',
      'connected': '已连接',
      'disconnected': '已断开',
      'status': '状态',
      'details': '详情',
      'error': '错误',
      'success': '成功',
      'active': '运行中',
      'inactive': '未激活',
      'login_title': '登录',
      'login_subtitle': '进入您的 HealthKicks 健康空间',
      'email_label': '电子邮箱',
      'password_label': '密码',
      'login_button': '登录',
      'logout': '退出登录',
      'session_checking': '正在检查登录状态...',
      'invalid_credentials': '邮箱或密码不正确。',
      'dashboard_title': '网关控制台',
      'ble_card_title': '低功耗蓝牙 (BLE)',
      'cloud_card_title': 'AWS IoT 核心云端',
      'test_haptic': '触觉测试',
      'test_haptic_desc': '触发鞋端振动脉冲',
      'studio_session_btn': 'Studio 动作采集',
      'haptic_success': '振动指令已成功发送',
      'steps_today': '今日步数',
      'steps_goal': '目标：{goal} 步',
      'cadence': '步频',
      'spm_unit': '步/分',
      'steps_history': '计步历史记录',
      'sync_steps': '同步计步数据',
      'steps_sync_success': '计步数据已同步成功',
      'recent_activities': '近期活动',
      'waiting_detections': '等待活动识别...',
      'fall_badge': '跌倒',
      'settings_title': '设置',
      'bluetooth_and_cloud': '蓝牙与云端连接',
      'bluetooth_footwear': '智能鞋夹设备 (BLE)',
      'cloud_iot': '云端网关 (AWS IoT)',
      'scan_ble': '搜索',
      'disconnect_ble': '断开连接',
      'reconnect_mqtt': '重新连接云端',
      'inactivity_section': '久坐防衰提醒',
      'inactivity_title': '长时间久坐不活动提醒',
      'inactivity_desc': '当长时间保持静坐未行走时，鞋端将进行温和微振动提醒',
      'inactivity_threshold': '告警等待时长：{minutes} 分钟',
      'inactivity_cooldown': '重复提醒间隔：{minutes} 分钟',
      'sensor_calibration_section': '传感器校准',
      'sensor_calibration_title': '倾角与零偏校准',
      'sensor_calibration_desc': '校准 IMU 惯性传感器以获得精准的计步与姿态',
      'calibrate_action': '开始校准',
      'appearance_theme': '外观与主题',
      'theme_title': '应用主题',
      'theme_desc': '选择浅色、深色或随系统自动切换。',
      'theme_system': '跟随系统',
      'theme_light': '浅色模式',
      'theme_dark': '深色模式',
      'language_region': '语言与地区',
      'language_title': '应用语言',
      'language_desc': '选择您偏好的应用界面显示语言。',
      'system_info': '系统信息',
      'firmware_update': '固件 OTA 在线升级',
      'event_logs_title': '系统事件日志',
      'clear_logs': '清空日志',
      'export_logs': '邮件导出日志',
      'studio_title': 'Studio 动作录制会话',
      'studio_subtitle': '54 Hz 高频生物力学姿态采集',
      'studio_activity_type': '动作类型',
      'studio_start_recording': '开始录制',
      'studio_countdown': '准备阶段：{step}/3',
      'studio_recording': '正在高频采集录制中...',
      'studio_transmitting': '正在同步生物力学遥测数据...',
      'studio_success': '数据采集已成功完成！',
      'custom_activity_label': '其他 / 自定义标签',
      'evt_fall_forward': '向前跌倒',
      'evt_fall_backward': '向后跌倒',
      'evt_fall_lateral': '侧向跌倒',
      'evt_fall_recovery': '跌倒后站起',
      'evt_stand_up': '站起',
      'evt_fall_generic': '跌倒',
      'evt_fall_detected': '检测到跌倒',
      'evt_free_fall': '自由落体（剧烈冲击）',
      'evt_high_impact': '剧烈撞击',
      'evt_stumble_recover': '绊倒并恢复平衡',
      'evt_prolonged_immobility': '长时间静止不动',
      'evt_inactivity_alert': '久坐提醒',
      'evt_walk': '日常行走',
      'evt_run': '奔跑',
      'evt_stairs': '爬楼梯',
      'evt_stairs_up': '上楼梯',
      'evt_stairs_down': '下楼梯',
      'evt_calibration': '传感器校准',
      'evt_idle': '静止休息 / 坐姿',
      'evt_sit_down': '坐姿',
      'evt_jump': '跳跃',
      'evt_activity_transition': '活动状态转换',
    },
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLanguage.supportedLocales
        .any((l) => l.languageCode == locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
