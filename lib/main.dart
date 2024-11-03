import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:convert';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(LaborAdapter());
  Hive.registerAdapter(AttendanceTypeAdapter());
  Hive.registerAdapter(DepartmentAdapter());
  runApp(const ProviderScope(child: LaborManagementApp()));
}

class LaborManagementApp extends StatelessWidget {
  const LaborManagementApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const SafeArea(child: HomeScreen())),
      );
    });
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
              'Labor Management',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.teal.shade700),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _searchQuery = '';
  String _sortBy = 'name';
  bool _sortAscending = true;

  @override
  Widget build(BuildContext context) {
    final laborers = ref.watch(laborProvider);
    final departments = ref.watch(departmentProvider);

    List<Labor> filteredAndSortedLaborers = laborers
        .where((labor) =>
            labor.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            labor.department.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    filteredAndSortedLaborers.sort((a, b) {
      int comparison;
      switch (_sortBy) {
        case 'name':
          comparison = a.name.compareTo(b.name);
          break;
        case 'department':
          comparison = a.department.compareTo(b.department);
          break;
        case 'salary':
          comparison = a.totalSalary.compareTo(b.totalSalary);
          break;
        case 'daysWorked':
          comparison = a.totalDaysWorked.compareTo(b.totalDaysWorked);
          break;
        default:
          comparison = 0;
      }
      return _sortAscending ? comparison : -comparison;
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Labor Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AnalyticsScreen()),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'import':
                  await _importData(context, ref);
                  break;
                case 'export':
                  await _exportData(context, ref);
                  break;
                case 'exportMonthly':
                  await _exportMonthlyReport(context, ref);
                  break;
                case 'manageDepartments':
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ManageDepartmentsScreen()),
                  );
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.file_upload, color: Colors.teal),
                  title: Text('Import Data'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.file_download, color: Colors.teal),
                  title: Text('Export Data'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'exportMonthly',
                child: ListTile(
                  leading: Icon(Icons.summarize, color:  Colors.teal),
                  title: Text('Export Monthly Report'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'manageDepartments',
                child: ListTile(
                  leading: Icon(Icons.business, color: Colors.teal),
                  title: Text('Manage Departments'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                labelText: 'Search',
                hintText: 'Search by name or department',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                const Text('Sort by: '),
                DropdownButton<String>(
                  value: _sortBy,
                  items: [
                    DropdownMenuItem(value: 'name', child: Text('Name')),
                    DropdownMenuItem(value: 'department', child: Text('Department')),
                    DropdownMenuItem(value: 'salary', child: Text('Salary')),
                    DropdownMenuItem(value: 'daysWorked', child: Text('Days Worked')),
                  ],
                  onChanged: (value) => setState(() => _sortBy = value!),
                ),
                IconButton(
                  icon: Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
                  onPressed: () => setState(() => _sortAscending = !_sortAscending),
                ),
              ],
            ),
          ),
          Expanded(
            child: filteredAndSortedLaborers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_add, size: 64, color: Colors.teal.shade300),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty
                              ? 'No laborers added yet!'
                              : 'No laborers found matching "$_searchQuery"',
                          style: TextStyle(fontSize: 18, color: Colors.teal.shade700),
                        ),
                        const SizedBox(height: 16),
                        if (_searchQuery.isEmpty)
                          ElevatedButton.icon(
                            onPressed: () => _showAddOptions(context, ref),
                            icon: const Icon(Icons.add),
                            label: const Text('Add Labor or Department'),
                          ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: departments.length,
                    itemBuilder: (context, index) {
                      final department = departments[index];
                      final departmentLaborers = filteredAndSortedLaborers.where((l) => l.department == department.name).toList();
                      if (departmentLaborers.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return ExpansionTile(
                        title: Text(department.name, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
                        children: departmentLaborers.map((labor) => LaborCard(labor: labor)).toList(),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddOptions(context, ref),
        child: const Icon(Icons.add),
        backgroundColor: Colors.teal.shade400,
      ),
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
                title: const Text('Add Labor'),
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
                title: const Text('Add Department'),
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
          title: const Text('Add Department'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: "Enter department name"),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: const Text('Add'),
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
        final file = File('/storage/emulated/0/Download/labor_data.json');
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

  Future<void> _exportMonthlyReport(BuildContext context, WidgetRef ref) async {
    try {
      final status = await Permission.storage.request();
      if (status.isGranted) {
        final laborers = ref.read(laborProvider);
        final pdf = pw.Document();

        pdf.addPage(
          pw.Page(
            build: (pw.Context context) {
              return pw.Column(
                children: [
                  pw.Header(
                    level: 0,
                    child: pw.Text('Monthly Labor Report'),
                  ),
                  pw.Table.fromTextArray(
                    context: context,
                    data: <List<String>>[
                      <String>['Name', 'Department', 'Total Days', 'Total Salary', 'Advance Salary'],
                      ...laborers.map((labor) => [
                        labor.name,
                        labor.department,
                        labor.totalDaysWorked.toStringAsFixed(1),
                        labor.totalSalary.toStringAsFixed(2),
                        labor.totalAdvanceSalary.toStringAsFixed(2),
                      ]),
                    ],
                  ),
                ],
              );
            },
          ),
        );

        final file = File('/storage/emulated/0/Download/monthly_report.pdf');
        await file.writeAsBytes(await pdf.save());

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Monthly report exported to ${file.path}')),
        );

        await OpenFile.open(file.path);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission denied to access storage')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting monthly report: $e')),
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
            Text('Daily Wage: ₹${labor.dailyWage.toStringAsFixed(2)}'),
            Text('Department: ${labor.department}'),
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
            Text('${labor.totalDaysWorked.toStringAsFixed(1)} days', style: const TextStyle(fontSize: 12)),
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
      appBar: AppBar(title: const Text('Add New Labor')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
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
                decoration: const InputDecoration(
                  labelText: 'Daily Wage',
                  border: OutlineInputBorder(),
                  prefixText: '₹ ',
                  prefixIcon: Icon(Icons.money),
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
                decoration: const InputDecoration(
                  labelText: 'Department',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business),
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
                child: const Text('Add Labor'),
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
              title: const Text('Add Advance Salary'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: advanceSalaryController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Advance Salary',
                      border: OutlineInputBorder(),
                      prefixText: '₹ ',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Date: '),
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
                  child: const Text('Cancel'),
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
                  child: const Text('Add'),
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
            icon: const Icon(Icons.analytics),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => LaborAnalyticsScreen(labor: labor)),
            ),
          ),
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
                  Text('Daily Wage: ₹${labor.dailyWage}', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('Total Advance Salary: ₹${labor.totalAdvanceSalary}', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Total Salary: ₹${labor.totalSalary}', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Total Days Worked: ${labor.totalDaysWorked}', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Department: ${labor.department}', style: Theme.of(context).textTheme.titleMedium),
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
                label: const Text('Mark Attendance'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showAddAdvanceSalaryDialog(context, ref, labor),
                icon: const Icon(Icons.money),
                label: const Text('Add Advance Salary'),
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
          title: const Text('Confirm Deletion'),
          content: Text('Are you sure you want to delete ${labor.name}?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
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
      title: const Text('Mark Attendance'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('Date: '),
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
                label: Text(_getAttendanceLabel(type)),
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
          child: const Text('Cancel'),
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
          child: const Text('Save'),
        ),
      ],
    );
  }

  String _getAttendanceLabel(AttendanceType type) {
    switch (type) {
      case AttendanceType.absent:
        return 'Absent';
      case AttendanceType.halfDay:
        return 'Half Day';
      case AttendanceType.fullDay:
        return 'Full Day';
      case AttendanceType.oneAndHalf:
        return '1.5 Day';
      case AttendanceType.double:
        return 'Double Day';
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
      appBar: AppBar(title: const Text('Edit Labor')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
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
                decoration: const InputDecoration(
                  labelText: 'Daily Wage',
                  border: OutlineInputBorder(),
                  prefixText: '₹ ',
                  prefixIcon: Icon(Icons.money),
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
                decoration: const InputDecoration(
                  labelText: 'Department',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business),
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
                child: const Text('Update Labor'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final laborers = ref.watch(laborProvider);

    final totalSalaryPaid = laborers.fold(0.0, (sum, labor) => sum + labor.totalSalary);
    final totalAdvanceSalary = laborers.fold(0.0, (sum, labor) => sum + labor.totalAdvanceSalary);
    final totalDaysWorked = laborers.fold(0.0, (sum, labor) => sum + labor.totalDaysWorked);

    final sortedLaborers = List<Labor>.from(laborers)..sort((a, b) => b.totalSalary.compareTo(a.totalSalary));

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total Salary Paid: ₹${totalSalaryPaid.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('Total Advance Salary: ₹${totalAdvanceSalary.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Total Days Worked: ${totalDaysWorked.toStringAsFixed(1)}', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Salary Distribution', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(
            height: 300,
            child: PieChart(
              PieChartData(
                sections: laborers.map((labor) => PieChartSectionData(
                  color: Colors.primaries[laborers.indexOf(labor) % Colors.primaries.length],
                  value: labor.totalSalary,
                  title: '${labor.name}\n₹${labor.totalSalary.toStringAsFixed(0)}',
                  radius: 100,
                  titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                )).toList(),
                sectionsSpace: 2,
                centerSpaceRadius: 40,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Top Earners', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...sortedLaborers.take(5).map((labor) => ListTile(
            title: Text(labor.name),
            subtitle: Text(labor.department),
            trailing: Text('₹${labor.totalSalary.toStringAsFixed(2)}'),
          )),
        ],
      ),
    );
  }
}

class LaborAnalyticsScreen extends StatelessWidget {
  final Labor labor;

  const LaborAnalyticsScreen({Key? key, required this.labor}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final attendanceData = labor.attendance.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    final salaryData = attendanceData.map((entry) {
      final date = DateTime.parse(entry.key);
      final daysWorked = entry.value.toDouble();
      final salary = labor.dailyWage * daysWorked;
      return MapEntry(date, salary);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: Text('${labor.name} Analytics')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total Days Worked: ${labor.totalDaysWorked.toStringAsFixed(1)}', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Total Salary: ₹${labor.totalSalary.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Total Advance Salary: ₹${labor.totalAdvanceSalary.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Attendance History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(
            height: 300,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true, drawVerticalLine: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        return Text(value.toStringAsFixed(1));
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(DateFormat('dd/MM').format(date), style: const TextStyle(fontSize: 10)),
                        );
                      },
                    ),
                  ),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: true),
                minX: attendanceData.isNotEmpty ? DateTime.parse(attendanceData.first.key).millisecondsSinceEpoch.toDouble() : 0,
                maxX: attendanceData.isNotEmpty ? DateTime.parse(attendanceData.last.key).millisecondsSinceEpoch.toDouble() : 0,
                minY: 0,
                maxY: 2,
                lineBarsData: [
                  LineChartBarData(
                    spots: attendanceData.map((entry) => FlSpot(
                      DateTime.parse(entry.key).millisecondsSinceEpoch.toDouble(),
                      entry.value.toDouble(),
                    )).toList(),
                    isCurved: true,
                    color: Colors.teal,
                    barWidth: 4,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: true),
                    belowBarData: BarAreaData(show: true, color: Colors.teal.withOpacity(0.2)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Salary History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(
            height: 300,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true, drawVerticalLine: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 60,
                      getTitlesWidget: (value, meta) {
                        return Text('₹${value.toStringAsFixed(0)}');
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(DateFormat('dd/MM').format(date), style: const TextStyle(fontSize: 10)),
                        );
                      },
                    ),
                  ),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: true),
                minX: salaryData.isNotEmpty ? salaryData.first.key.millisecondsSinceEpoch.toDouble() : 0,
                maxX: salaryData.isNotEmpty ? salaryData.last.key.millisecondsSinceEpoch.toDouble() : 0,
                minY: 0,
                maxY: salaryData.isNotEmpty ? salaryData.map((e) => e.value).reduce((a, b) => a > b ? a : b) : 0,
                lineBarsData: [
                  LineChartBarData(
                    spots: salaryData.map((entry) => FlSpot(
                      entry.key.millisecondsSinceEpoch.toDouble(),
                      entry.value,
                    )).toList(),
                    isCurved: true,
                    color: Colors.green,
                    barWidth: 4,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: true),
                    belowBarData: BarAreaData(show: true, color: Colors.green.withOpacity(0.2)),
                  ),
                ],
              ),
            ),
          ),
        ],
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
        title: const Text('Manage Departments'),
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
          title: const Text('Add Department'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: "Enter department name"),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: const Text('Add'),
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
          title: const Text('Confirm Deletion'),
          content: Text('Are you sure you want to delete the department "${department.name}"?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
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
