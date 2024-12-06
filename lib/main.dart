import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';

part 'main.g.dart';

@HiveType(typeId: 0)
enum AttendanceType {
  @HiveField(0)
  absent,
  @HiveField(1)
  halfDay,
  @HiveField(2)
  fullDay,
  @HiveField(3)
  oneAndHalf,
  @HiveField(4)
  double,
}

extension AttendanceTypeExtension on AttendanceType {
  double toDouble() {
    switch (this) {
      case AttendanceType.absent:
        return 0;
      case AttendanceType.halfDay:
        return 0.5;
      case AttendanceType.fullDay:
        return 1;
      case AttendanceType.oneAndHalf:
        return 1.5;
      case AttendanceType.double:
        return 2;
    }
  }
}

@HiveType(typeId: 1)
class Labor extends HiveObject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  String name;
  @HiveField(2)
  double dailyWage;
  @HiveField(3)
  Map<String, double> advanceSalary;
  @HiveField(4)
  Map<String, AttendanceType> attendance;
  @HiveField(5)
  String department;

  Labor({
    String? id,
    required this.name,
    required this.dailyWage,
    Map<String, double>? advanceSalary,
    Map<String, AttendanceType>? attendance,
    required this.department,
  })  : id = id ?? const Uuid().v4(),
        advanceSalary = advanceSalary ?? {},
        attendance = attendance ?? {};

  double get totalDaysWorked => attendance.values.fold(0, (sum, value) => sum + value.toDouble());
  double get totalAdvanceSalary => advanceSalary.values.fold(0, (sum, value) => sum + value);
  double get totalSalary => (dailyWage * totalDaysWorked) - totalAdvanceSalary;

  Labor copyWith({
    String? name,
    double? dailyWage,
    Map<String, double>? advanceSalary,
    Map<String, AttendanceType>? attendance,
    String? department,
  }) {
    return Labor(
      id: id,
      name: name ?? this.name,
      dailyWage: dailyWage ?? this.dailyWage,
      advanceSalary: advanceSalary ?? Map.from(this.advanceSalary),
      attendance: attendance ?? Map.from(this.attendance),
      department: department ?? this.department,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'dailyWage': dailyWage,
        'advanceSalary': advanceSalary,
        'attendance': attendance.map((key, value) => MapEntry(key, value.index)),
        'department': department,
      };

  factory Labor.fromJson(Map<String, dynamic> json) => Labor(
        id: json['id'],
        name: json['name'],
        dailyWage: json['dailyWage'].toDouble(),
        advanceSalary: Map<String, double>.from(json['advanceSalary']),
        attendance: Map<String, AttendanceType>.from(
            json['attendance'].map((key, value) => MapEntry(key, AttendanceType.values[value]))),
        department: json['department'],
      );
}

@HiveType(typeId: 2)
class Department extends HiveObject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  String name;

  Department({String? id, required this.name}) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory Department.fromJson(Map<String, dynamic> json) => Department(id: json['id'], name: json['name']);
}

class LaborNotifier extends StateNotifier<List<Labor>> {
  LaborNotifier() : super([]) {
    _loadLabors();
  }

  Future<void> _loadLabors() async {
    final box = await Hive.openBox<Labor>('labors');
    state = box.values.toList();
  }

  Future<void> _saveLabors() async {
    final box = await Hive.openBox<Labor>('labors');
    await box.clear();
    await box.addAll(state);
  }

  void addLabor(Labor labor) {
    state = [...state, labor];
    _saveLabors();
  }

  void updateLabor(Labor updatedLabor) {
    state = [for (final labor in state) if (labor.id == updatedLabor.id) updatedLabor else labor];
    _saveLabors();
  }

  void deleteLabor(String id) {
    state = state.where((labor) => labor.id != id).toList();
    _saveLabors();
  }

  Future<String> importData(String jsonString) async {
    try {
      final Map<String, dynamic> jsonData = jsonDecode(jsonString);
      final List<dynamic> laborJsonList = jsonData['labors'];
      final List<dynamic> departmentJsonList = jsonData['departments'];
      
      final List<Labor> importedLabors = [];
      final List<Department> importedDepartments = [];
      
      for (var json in laborJsonList) {
        try {
          final labor = Labor.fromJson(json);
          importedLabors.add(labor);
        } catch (e) {
          return 'Error: Invalid data format for one or more laborers';
        }
      }

      for (var json in departmentJsonList) {
        try {
          final department = Department.fromJson(json);
          importedDepartments.add(department);
        } catch (e) {
          return 'Error: Invalid data format for one or more departments';
        }
      }

      state = importedLabors;
      await _saveLabors();

      final departmentNotifier = DepartmentNotifier();
      departmentNotifier.state = importedDepartments;
      await departmentNotifier._saveDepartments();

      return 'Data imported successfully: ${importedLabors.length} laborers and ${importedDepartments.length} departments added';
    } catch (e) {
      return 'Error importing data: ${e.toString()}';
    }
  }

  String exportData() {
    final departmentNotifier = DepartmentNotifier();
    final Map<String, dynamic> exportData = {
      'labors': state.map((labor) => labor.toJson()).toList(),
      'departments': departmentNotifier.state.map((dept) => dept.toJson()).toList(),
    };
    return jsonEncode(exportData);
  }
}

class DepartmentNotifier extends StateNotifier<List<Department>> {
  DepartmentNotifier() : super([]) {
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    final box = await Hive.openBox<Department>('departments');
    state = box.values.toList();
  }

  Future<void> _saveDepartments() async {
    final box = await Hive.openBox<Department>('departments');
    await box.clear();
    await box.addAll(state);
  }

  void addDepartment(Department department) {
    state = [...state, department];
    _saveDepartments();
  }

  void updateDepartment(Department updatedDepartment) {
    state = [
      for (final dept in state)
        if (dept.id == updatedDepartment.id) updatedDepartment else dept
    ];
    _saveDepartments();
  }

  void deleteDepartment(String id) {
    state = state.where((dept) => dept.id != id).toList();
    _saveDepartments();
  }
}

final laborProvider = StateNotifierProvider<LaborNotifier, List<Labor>>((ref) => LaborNotifier());
final departmentProvider = StateNotifierProvider<DepartmentNotifier, List<Department>>((ref) => DepartmentNotifier());

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const _localizedValues = <String, Map<String, String>>{
    'en': {
      'appTitle': 'Labor Management',
      'addLabor': 'Add Labor',
      'addDepartment': 'Add Department',
      'name': 'Name',
      'dailyWage': 'Daily Wage',
      'department': 'Department',
      'save': 'Save',
      'cancel': 'Cancel',
      'edit': 'Edit',
      'delete': 'Delete',
      'confirmDelete': 'Confirm Delete',
      'areYouSure': 'Are you sure?',
      'totalSalary': 'Total Salary',
      'totalAdvance': 'Total Advance',
      'totalDaysWorked': 'Total Days Worked',
      'markAttendance': 'Mark Attendance',
      'addAdvanceSalary': 'Add Advance Salary',
      'date': 'Date',
      'amount': 'Amount',
      'absent': 'Absent',
      'halfDay': 'Half Day',
      'fullDay': 'Full Day',
      'oneAndHalfDay': '1.5 Day',
      'doubleDay': 'Double Day',
      'importData': 'Import Data',
      'exportData': 'Export Data',
      'manageDepartments': 'Manage Departments',
      'selectLanguage': 'Select Language',
      'welcome': 'Welcome to Labor Management',
      'noDepartments': 'No departments added yet!',
      'noLaborers': 'No laborers in',
      'changeLanguage': 'Change Language',
    },
    'gu': {
      'appTitle': 'મજૂર વ્યવસ્થાપન',
      'addLabor': 'મજૂર ઉમેરો',
      'addDepartment': 'વિભાગ ઉમેરો',
      'name': 'નામ',
      'dailyWage': 'દૈનિક વેતન',
      'department': 'વિભાગ',
      'save': 'સાચવો',
      'cancel': 'રદ કરો',
      'edit': 'સંપાદિત કરો',
      'delete': 'કાઢી નાખો',
      'confirmDelete': 'કાઢી નાખવાની પુષ્ટિ કરો',
      'areYouSure': 'શું તમને ખાતરી છે?',
      'totalSalary': 'કુલ પગાર',
      'totalAdvance': 'કુલ એડવાન્સ',
      'totalDaysWorked': 'કુલ કામ કરેલા દિવસો',
      'markAttendance': 'હાજરી નોંધો',
      'addAdvanceSalary': 'એડવાન્સ પગાર ઉમેરો',
      'date': 'તારીખ',
      'amount': 'રકમ',
      'absent': 'ગેરહાજર',
      'halfDay': 'અર્ધ દિવસ',
      'fullDay': 'પૂર્ણ દિવસ',
      'oneAndHalfDay': '1.5 દિવસ',
      'doubleDay': 'બમણો દિવસ',
      'importData': 'ડેટા આયાત કરો',
      'exportData': 'ડેટા નિકાસ કરો',
      'manageDepartments': 'વિભાગો સંચાલિત કરો',
      'selectLanguage': 'ભાષા પસંદ કરો',
      'welcome': 'મજૂર વ્યવસ્થાપનમાં આપનું સ્વાગત છે',
      'noDepartments': 'હજુ સુધી કોઈ વિભાગો ઉમેર્યા નથી!',
      'noLaborers': 'કોઈ મજૂરો નથી',
      'changeLanguage': 'ભાષા બદલો',
    },
  };

  String get appTitle => _localizedValues[locale.languageCode]!['appTitle']!;
  String get addLabor => _localizedValues[locale.languageCode]!['addLabor']!;
  String get addDepartment => _localizedValues[locale.languageCode]!['addDepartment']!;
  String get name => _localizedValues[locale.languageCode]!['name']!;
  String get dailyWage => _localizedValues[locale.languageCode]!['dailyWage']!;
  String get department => _localizedValues[locale.languageCode]!['department']!;
  String get save => _localizedValues[locale.languageCode]!['save']!;
  String get cancel => _localizedValues[locale.languageCode]!['cancel']!;
  String get edit => _localizedValues[locale.languageCode]!['edit']!;
  String get delete => _localizedValues[locale.languageCode]!['delete']!;
  String get confirmDelete => _localizedValues[locale.languageCode]!['confirmDelete']!;
  String get areYouSure => _localizedValues[locale.languageCode]!['areYouSure']!;
  String get totalSalary => _localizedValues[locale.languageCode]!['totalSalary']!;
  String get totalAdvance => _localizedValues[locale.languageCode]!['totalAdvance']!;
  
  String get totalDaysWorked => _localizedValues[locale.languageCode]!['totalDaysWorked']!;
  String get markAttendance => _localizedValues[locale.languageCode]!['markAttendance']!;
  String get addAdvanceSalary => _localizedValues[locale.languageCode]!['addAdvanceSalary']!;
  String get date => _localizedValues[locale.languageCode]!['date']!;
  String get amount => _localizedValues[locale.languageCode]!['amount']!;
  String get absent => _localizedValues[locale.languageCode]!['absent']!;
  String get halfDay => _localizedValues[locale.languageCode]!['halfDay']!;
  String get fullDay => _localizedValues[locale.languageCode]!['fullDay']!;
  String get oneAndHalfDay => _localizedValues[locale.languageCode]!['oneAndHalfDay']!;
  String get doubleDay => _localizedValues[locale.languageCode]!['doubleDay']!;
  String get importData => _localizedValues[locale.languageCode]!['importData']!;
  String get exportData => _localizedValues[locale.languageCode]!['exportData']!;
  String get manageDepartments => _localizedValues[locale.languageCode]!['manageDepartments']!;
  String get selectLanguage => _localizedValues[locale.languageCode]!['selectLanguage']!;
  String get welcome => _localizedValues[locale.languageCode]!['welcome']!;
  String get noDepartments => _localizedValues[locale.languageCode]!['noDepartments']!;
  String get noLaborers => _localizedValues[locale.languageCode]!['noLaborers']!;
  String get changeLanguage => _localizedValues[locale.languageCode]!['changeLanguage']!;
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'gu'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}

final languageProvider = StateProvider<Locale>((ref) => const Locale('en', ''));

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(LaborAdapter());
  Hive.registerAdapter(AttendanceTypeAdapter());
  Hive.registerAdapter(DepartmentAdapter());
  
  final prefs = await SharedPreferences.getInstance();
  final String? languageCode = prefs.getString('language');
  final initialLocale = languageCode != null ? Locale(languageCode) : const Locale('en', '');
  
  runApp(ProviderScope(
    overrides: [
      languageProvider.overrideWith((ref) => initialLocale),
    ],
    child: const LaborManagementApp(),
  ));
}

class LaborManagementApp extends ConsumerWidget {
  const LaborManagementApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(languageProvider);

    return MaterialApp(
      title: 'Labor Management',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        fontFamily: GoogleFonts.poppins().fontFamily,
        scaffoldBackgroundColor: Colors.grey[100],
        appBarTheme: AppBarTheme(
          elevation: 0,
          centerTitle: true,
          backgroundColor: Colors.teal.shade50,
          iconTheme: IconThemeData(color: Colors.teal.shade700),
          titleTextStyle: TextStyle(color: Colors.teal.shade700, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.teal.shade400,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: Colors.white,
        ),
      ),
      supportedLocales: const [Locale('en', ''), Locale('gu', '')],
      locale: currentLocale,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToHome();
  }

  Future<void> _navigateToHome() async {
    await Future.delayed(const Duration(seconds: 2));
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/icon/icon.png', width: 150, height: 150),
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(context).welcome,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.teal.shade700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final laborers = ref.watch(laborProvider);
    final departments = ref.watch(departmentProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.language),
            onPressed: () => _showLanguageSelectionDialog(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => _showMenu(context, ref),
          ),
        ],
      ),
      body: departments.isEmpty
          ? Center(
              child: Text(
                AppLocalizations.of(context).noDepartments,
                style: TextStyle(fontSize: 18, color: Colors.teal.shade700),
              ),
            )
          : ListView.builder(
              itemCount: departments.length,
              itemBuilder: (context, index) {
                final department = departments[index];
                final departmentLaborers = laborers.where((l) => l.department == department.name).toList();
                return ExpansionTile(
                  title: Text(department.name, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
                  children: departmentLaborers.isEmpty
                      ? [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text('${AppLocalizations.of(context).noLaborers} ${department.name}', style: TextStyle(color: Colors.grey[600])),
                          )
                        ]
                      : departmentLaborers.map((labor) => LaborCard(labor: labor)).toList(),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddOptions(context, ref),
        child: const Icon(Icons.add),
        backgroundColor: Colors.teal.shade400,
      ),
    );
  }

  void _showLanguageSelectionDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context).selectLanguage),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('English'),
                onTap: () => _changeLanguage(context, ref, const Locale('en', '')),
              ),
              ListTile(
                title: const Text('ગુજરાતી (Gujarati)'),
                onTap: () => _changeLanguage(context, ref, const Locale('gu', '')),
              ),
            ],
          ),
        );
      },
    );
  }

  void _changeLanguage(BuildContext context, WidgetRef ref, Locale newLocale) async {
    Navigator.of(context).pop();
    ref.read(languageProvider.notifier).state = newLocale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', newLocale.languageCode);
  }

  void _showMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.file_upload),
                title: Text(AppLocalizations.of(context).importData),
                onTap: () async {
                  Navigator.pop(context);
                  await _importData(context, ref);
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_download),
                title: Text(AppLocalizations.of(context).exportData),
                onTap: () async {
                  Navigator.pop(context);
                  await _exportData(context, ref);
                },
              ),
              ListTile(
                leading: const Icon(Icons.business),
                title: Text(AppLocalizations.of(context).manageDepartments),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ManageDepartmentsScreen()),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.person_add),
                title: Text(AppLocalizations.of(context).addLabor),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AddLaborScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.business),
                title: Text(AppLocalizations.of(context).addDepartment),
                onTap: () {
                  Navigator.pop(context);
                  _showAddDepartmentDialog(context, ref);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddDepartmentDialog(BuildContext context, WidgetRef ref) {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context).addDepartment),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(hintText: AppLocalizations.of(context).name),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(AppLocalizations.of(context).cancel),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: Text(AppLocalizations.of(context).save),
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  ref.read(departmentProvider.notifier).addDepartment(Department(name: controller.text));
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _importData(BuildContext context, WidgetRef ref) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null) {
        File file = File(result.files.single.path!);
        String contents = await file.readAsString();
        
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return const Center(child: CircularProgressIndicator());
          },
        );

        final importResult = await ref.read(laborProvider.notifier).importData(contents);
        
        Navigator.of(context).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(importResult)),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error importing data: $e')),
      );
    }
  }

  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    try {
      final status = await Permission.storage.request();
      if (status.isGranted) {
        final data = ref.read(laborProvider.notifier).exportData();
        final directory = await getExternalStorageDirectory();
        final file = File('${directory!.path}/labor_data.json');
        await file.writeAsString(data);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Data exported to ${file.path}')),
        );

        await OpenFile.open(file.path);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission denied to access storage')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting data: $e')),
      );
    }
  }
}

class LaborCard extends StatelessWidget {
  final Labor labor;

  const LaborCard({Key? key, required this.labor}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Colors.teal.shade100,
          child: Text(
            labor.name.substring(0, 1).toUpperCase(),
            style: TextStyle(color: Colors.teal.shade700, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(labor.name, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${AppLocalizations.of(context).dailyWage}: ₹${labor.dailyWage.toStringAsFixed(2)}'),
            Text('${AppLocalizations.of(context).department}: ${labor.department}'),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₹${labor.totalSalary.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
            ),
            Text('${labor.totalDaysWorked.toStringAsFixed(1)} ${AppLocalizations.of(context).totalDaysWorked}', style: const TextStyle(fontSize: 12)),
          ],
        ),
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => LaborDetailScreen(laborId: labor.id),
          ));
        },
      ),
    );
  }
}

class AddLaborScreen extends ConsumerStatefulWidget {
  const AddLaborScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<AddLaborScreen> createState() => _AddLaborScreenState();
}

class _AddLaborScreenState extends ConsumerState<AddLaborScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _dailyWageController = TextEditingController();
  String? _selectedDepartment;

  @override
  void dispose() {
    _nameController.dispose();
    _dailyWageController.dispose();
    super.dispose();
  }

  void _addLabor() {
    if (_formKey.currentState!.validate() && _selectedDepartment != null) {
      final name = _nameController.text.trim();
      final dailyWage = double.parse(_dailyWageController.text);

      final newLabor = Labor(
        name: name,
        dailyWage: dailyWage,
        department: _selectedDepartment!,
      );

      ref.read(laborProvider.notifier).addLabor(newLabor);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final departments = ref.watch(departmentProvider);

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).addLabor)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).name,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _dailyWageController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).dailyWage,
                  border: const OutlineInputBorder(),
                  prefixText: '₹ ',
                  prefixIcon: const Icon(Icons.money),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a daily wage';
                  }
                  if (double.tryParse(value) == null || double.parse(value) <= 0) {
                    return 'Please enter a valid wage';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedDepartment,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).department,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.business),
                ),
                items: departments.map((dept) {
                  return DropdownMenuItem(
                    value: dept.name,
                    child: Text(dept.name),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedDepartment = value;
                  });
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please select a department';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _addLabor,
                child: Text(AppLocalizations.of(context).save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LaborDetailScreen extends ConsumerWidget {
  final String laborId;

  const LaborDetailScreen({Key? key, required this.laborId}) : super(key: key);

  void _showAddAdvanceSalaryDialog(BuildContext context, WidgetRef ref, Labor labor) {
    final TextEditingController advanceSalaryController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(AppLocalizations.of(context).addAdvanceSalary),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: advanceSalaryController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context).amount,
                      border: const OutlineInputBorder(),
                      prefixText: '₹ ',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text('${AppLocalizations.of(context).date}: '),
                      TextButton(
                        onPressed: () async {
                          final DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null && picked != selectedDate) {
                            setState(() {
                              selectedDate = picked;
                            });
                          }
                        },
                        child: Text(DateFormat('yyyy-MM-dd').format(selectedDate)),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(AppLocalizations.of(context).cancel),
                ),
                ElevatedButton(
                  onPressed: () {
                    final double? advanceAmount = double.tryParse(advanceSalaryController.text);
                    if (advanceAmount != null && advanceAmount > 0) {
                      final dateString = DateFormat('yyyy-MM-dd').format(selectedDate);
                      final updatedAdvanceSalary = Map<String, double>.from(labor.advanceSalary);
                      updatedAdvanceSalary[dateString] = (updatedAdvanceSalary[dateString] ?? 0) + advanceAmount;
                      final updatedLabor = labor.copyWith(advanceSalary: updatedAdvanceSalary);
                      ref.read(laborProvider.notifier).updateLabor(updatedLabor);
                    }
                    Navigator.pop(context);
                  },
                  child: Text(AppLocalizations.of(context).save),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showMarkAttendanceDialog(BuildContext context, WidgetRef ref, Labor labor) {
    showDialog(
      context: context,
      builder: (context) => AttendanceDialog(labor: labor, onSave: (updatedLabor) {
        ref.read(laborProvider.notifier).updateLabor(updatedLabor);
      }),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labor = ref.watch(laborProvider.select((laborers) => laborers.firstWhere((l) => l.id == laborId)));

    return Scaffold(
      appBar: AppBar(
        title: Text(labor.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => EditLaborScreen(labor: labor)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => _showDeleteConfirmationDialog(context, ref, labor),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${AppLocalizations.of(context).dailyWage}: ₹${labor.dailyWage}', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('${AppLocalizations.of(context).totalAdvance}: ₹${labor.totalAdvanceSalary}', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('${AppLocalizations.of(context).totalSalary}: ₹${labor.totalSalary}', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('${AppLocalizations.of(context).totalDaysWorked}: ${labor.totalDaysWorked}', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('${AppLocalizations.of(context).department}: ${labor.department}', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: () => _showMarkAttendanceDialog(context, ref, labor),
                icon: const Icon(Icons.calendar_today),
                label: Text(AppLocalizations.of(context).markAttendance),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showAddAdvanceSalaryDialog(context, ref, labor),
                icon: const Icon(Icons.money),
                label: Text(AppLocalizations.of(context).addAdvanceSalary),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmationDialog(BuildContext context, WidgetRef ref, Labor labor) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context).confirmDelete),
          content: Text('${AppLocalizations.of(context).areYouSure} ${labor.name}?'),
          actions: <Widget>[
            TextButton(
              child: Text(AppLocalizations.of(context).cancel),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(AppLocalizations.of(context).delete, style: const TextStyle(color: Colors.red)),
              onPressed: () {
                ref.read(laborProvider.notifier).deleteLabor(labor.id);
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}

class AttendanceDialog extends StatefulWidget {
  final Labor labor;
  final Function(Labor) onSave;

  const AttendanceDialog({Key? key, required this.labor, required this.onSave}) : super(key: key);

  @override
  _AttendanceDialogState createState() => _AttendanceDialogState();
}

class _AttendanceDialogState extends State<AttendanceDialog> {
  late DateTime selectedDate;
  AttendanceType? selectedAttendance;

  @override
  void initState() {
    super.initState();
    selectedDate = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context).markAttendance),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('${AppLocalizations.of(context).date}: '),
              TextButton(
                onPressed: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null && picked != selectedDate) {
                    setState(() {
                      selectedDate = picked;
                    });
                  }
                },
                child: Text(DateFormat('yyyy-MM-dd').format(selectedDate)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AttendanceType.values.map((type) {
              return ChoiceChip(
                label: Text(_getAttendanceLabel(context, type)),
                selected: selectedAttendance == type,
                onSelected: (selected) {
                  setState(() {
                    selectedAttendance = selected ? type : null;
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context).cancel),
        ),
        ElevatedButton(
          onPressed: selectedAttendance == null ? null : () {
            final dateString = DateFormat('yyyy-MM-dd').format(selectedDate);
            final updatedAttendance = Map<String, AttendanceType>.from(widget.labor.attendance);
            updatedAttendance[dateString] = selectedAttendance!;
            final updatedLabor = widget.labor.copyWith(attendance: updatedAttendance);
            widget.onSave(updatedLabor);
            Navigator.pop(context);
          },
          child: Text(AppLocalizations.of(context).save),
        ),
      ],
    );
  }

  String _getAttendanceLabel(BuildContext context, AttendanceType type) {
    switch (type) {
      case AttendanceType.absent:
        return AppLocalizations.of(context).absent;
      case AttendanceType.halfDay:
        return AppLocalizations.of(context).halfDay;
      case AttendanceType.fullDay:
        return AppLocalizations.of(context).fullDay;
      case AttendanceType.oneAndHalf:
        return AppLocalizations.of(context).oneAndHalfDay;
      case AttendanceType.double:
        return AppLocalizations.of(context).doubleDay;
    }
  }
}

class EditLaborScreen extends ConsumerStatefulWidget {
  final Labor labor;

  const EditLaborScreen({Key? key, required this.labor}) : super(key: key);

  @override
  ConsumerState<EditLaborScreen> createState() => _EditLaborScreenState();
}

class _EditLaborScreenState extends ConsumerState<EditLaborScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _dailyWageController;
  late String _selectedDepartment;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.labor.name);
    _dailyWageController = TextEditingController(text: widget.labor.dailyWage.toString());
    _selectedDepartment = widget.labor.department;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dailyWageController.dispose();
    super.dispose();
  }

  void _updateLabor() {
    if (_formKey.currentState!.validate()) {
      final name = _nameController.text.trim();
      final dailyWage = double.parse(_dailyWageController.text);

      final updatedLabor = widget.labor.copyWith(
        name: name,
        dailyWage: dailyWage,
        department: _selectedDepartment,
      );

      ref.read(laborProvider.notifier).updateLabor(updatedLabor);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final departments = ref.watch(departmentProvider);

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).edit)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).name,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _dailyWageController,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).dailyWage,
                  border: const OutlineInputBorder(),
                  prefixText: '₹ ',
                  prefixIcon: const Icon(Icons.money),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a daily wage';
                  }
                  if (double.tryParse(value) == null || double.parse(value) <= 0) {
                    return 'Please enter a valid wage';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedDepartment,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).department,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.business),
                ),
                items: departments.map((dept) {
                  return DropdownMenuItem(
                    value: dept.name,
                    child: Text(dept.name),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedDepartment = value!;
                  });
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please select a department';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _updateLabor,
                child: Text(AppLocalizations.of(context).save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ManageDepartmentsScreen extends ConsumerWidget {
  const ManageDepartmentsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final departments = ref.watch(departmentProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).manageDepartments),
      ),
      body: ListView.builder(
        itemCount: departments.length,
        itemBuilder: (context, index) {
          final department = departments[index];
          return ListTile(
            title: Text(department.name),
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () {
                _showDeleteConfirmationDialog(context, ref, department);
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showAddDepartmentDialog(context, ref);
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddDepartmentDialog(BuildContext context, WidgetRef ref) {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context).addDepartment),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(hintText: AppLocalizations.of(context).name),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(AppLocalizations.of(context).cancel),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: Text(AppLocalizations.of(context).save),
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  ref.read(departmentProvider.notifier).addDepartment(Department(name: controller.text));
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmationDialog(BuildContext context, WidgetRef ref, Department department) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context).confirmDelete),
          content: Text('${AppLocalizations.of(context).areYouSure} "${department.name}"?'),
          actions: <Widget>[
            TextButton(
              child: Text(AppLocalizations.of(context).cancel),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(AppLocalizations.of(context).delete, style: const TextStyle(color: Colors.red)),
              onPressed: () {
                ref.read(departmentProvider.notifier).deleteDepartment(department.id);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}
