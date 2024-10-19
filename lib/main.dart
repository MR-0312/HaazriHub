import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sharedPreferences = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sharedPreferences),
    ],
    child: const LaborManagementApp(),
  ));
}

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError();
});

class LaborManagementApp extends StatelessWidget {
  const LaborManagementApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Labor Management',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        fontFamily: GoogleFonts.poppins().fontFamily,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const SafeArea(child: HomeScreen()),
    );
  }
}

class Labor {
  final String id;
  final String name;
  final double dailyWage;
  final Map<String, double> advanceSalary;
  final Map<String, double> attendance;

  Labor({
    String? id,
    required this.name,
    required this.dailyWage,
    Map<String, double>? advanceSalary,
    Map<String, double>? attendance,
  })  : id = id ?? const Uuid().v4(),
        advanceSalary = advanceSalary ?? {},
        attendance = attendance ?? {};

  double get totalDaysWorked => attendance.values.fold(0, (sum, value) => sum + value);

  double get totalAdvanceSalary => advanceSalary.values.fold(0, (sum, value) => sum + value);

  double get totalSalary => (dailyWage * totalDaysWorked) - totalAdvanceSalary;

  Labor copyWith({
    String? name,
    double? dailyWage,
    Map<String, double>? advanceSalary,
    Map<String, double>? attendance,
  }) {
    return Labor(
      id: id,
      name: name ?? this.name,
      dailyWage: dailyWage ?? this.dailyWage,
      advanceSalary: advanceSalary ?? Map.from(this.advanceSalary),
      attendance: attendance ?? Map.from(this.attendance),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'dailyWage': dailyWage,
    'advanceSalary': advanceSalary,
    'attendance': attendance,
  };

  factory Labor.fromJson(Map<String, dynamic> json) => Labor(
    id: json['id'],
    name: json['name'],
    dailyWage: json['dailyWage'],
    advanceSalary: Map<String, double>.from(json['advanceSalary']),
    attendance: Map<String, double>.from(json['attendance']),
  );
}

class LaborNotifier extends StateNotifier<List<Labor>> {
  LaborNotifier(this.ref) : super([]) {
    _loadLabors();
  }

  final Ref ref;

  Future<void> _loadLabors() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final laborsJson = prefs.getString('labors');
    if (laborsJson != null) {
      final laborsList = (jsonDecode(laborsJson) as List)
          .map((laborJson) => Labor.fromJson(laborJson))
          .toList();
      state = laborsList;
    }
  }

  Future<void> _saveLabors() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final laborsJson = jsonEncode(state.map((labor) => labor.toJson()).toList());
    await prefs.setString('labors', laborsJson);
  }

  void addLabor(Labor labor) {
    state = [...state, labor];
    _saveLabors();
  }

  void updateLabor(Labor updatedLabor) {
    state = [
      for (final labor in state)
        if (labor.id == updatedLabor.id) updatedLabor else labor
    ];
    _saveLabors();
  }

  void deleteLabor(String id) {
    state = state.where((labor) => labor.id != id).toList();
    _saveLabors();
  }
}

final laborProvider = StateNotifierProvider<LaborNotifier, List<Labor>>((ref) => LaborNotifier(ref));

class HomeScreen extends ConsumerWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final laborers = ref.watch(laborProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Labor Management'),
      ),
      body: laborers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_add, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No laborers added yet!', style: TextStyle(fontSize: 18, color: Colors.grey)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AddLaborScreen()),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Labor'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: laborers.length,
              itemBuilder: (context, index) {
                return LaborCard(labor: laborers[index]);
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddLaborScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class LaborCard extends ConsumerWidget {
  final Labor labor;

  const LaborCard({Key? key, required this.labor}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(labor.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text('Daily Wage: ₹${labor.dailyWage.toStringAsFixed(2)}'),
            Text('Total Salary: ₹${labor.totalSalary.toStringAsFixed(2)}'),
            Text('Advance Salary: ₹${labor.totalAdvanceSalary.toStringAsFixed(2)}'),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: () => _showDeleteConfirmationDialog(context, ref),
        ),
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => LaborDetailScreen(laborId: labor.id),
          ));
        },
      ),
    );
  }

  void _showDeleteConfirmationDialog(BuildContext context, WidgetRef ref) {
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
              },
            ),
          ],
        );
      },
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

  @override
  void dispose() {
    _nameController.dispose();
    _dailyWageController.dispose();
    super.dispose();
  }

  void _addLabor() {
    if (_formKey.currentState!.validate()) {
      final name = _nameController.text.trim();
      final dailyWage = double.parse(_dailyWageController.text);

      final newLabor = Labor(
        name: name,
        dailyWage: dailyWage,
      );

      ref.read(laborProvider.notifier).addLabor(newLabor);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _addLabor,
                child: const Text('Add Labor'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labor = ref.watch(laborProvider.select((laborers) => laborers.firstWhere((l) => l.id == laborId)));

    return Scaffold(
      appBar: AppBar(title: Text(labor.name)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child:  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Daily Wage: ₹${labor.dailyWage}', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text('Total Advance Salary: ₹${labor.totalAdvanceSalary}', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text('Total Salary: ₹${labor.totalSalary}', style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Attendance & Advance Salary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Expanded(child: AttendanceCalendar(laborId: laborId)),
              ElevatedButton(
                onPressed: () => _showAddAdvanceSalaryDialog(context, ref, labor),
                child: const Text('Add Advance Salary'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AttendanceCalendar extends ConsumerStatefulWidget {
  final String laborId;

  const AttendanceCalendar({Key? key, required this.laborId}) : super(key: key);

  @override
  ConsumerState<AttendanceCalendar> createState() => _AttendanceCalendarState();
}

class _AttendanceCalendarState extends ConsumerState<AttendanceCalendar> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
    _selectedDay = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final labor = ref.watch(laborProvider.select((laborers) => laborers.firstWhere((l) => l.id == widget.laborId)));

    return SingleChildScrollView(
      child: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.now(),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
              _showDayDetailsDialog(selectedDay, labor);
            },
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, date, _) {
                final dateString = DateFormat('yyyy-MM-dd').format(date);
                final attendance = labor.attendance[dateString];
                final advanceSalary = labor.advanceSalary[dateString];
                
                List<Widget> markers = [];
                
                if (attendance != null) {
                  markers.add(Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: attendance == 1 ? Colors.green : Colors.orange,
                    ),
                    width: 8,
                    height: 8,
                  ));
                }
                
                if (advanceSalary != null) {
                  markers.add(Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red,
                    ),
                    width: 8,
                    height: 8,
                  ));
                }
                
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: markers,
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Text('Total Days Worked: ${labor.totalDaysWorked.toStringAsFixed(1)}'),
          Text('Total Salary: ₹${labor.totalSalary.toStringAsFixed(2)}'),
          const SizedBox(height: 10),
          const Text('Legend:', style: TextStyle(fontWeight: FontWeight.bold)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem('Full Day', Colors.green),
              const SizedBox(width: 10),
              _buildLegendItem('Half Day', Colors.orange),
              const SizedBox(width: 10),
              _buildLegendItem('Advance Salary', Colors.red),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }

  void _showDayDetailsDialog(DateTime date, Labor labor) {
    final dateString = DateFormat('yyyy-MM-dd').format(date);
    final attendance = labor.attendance[dateString];
    final advanceSalary = labor.advanceSalary[dateString];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(DateFormat('MMMM d, yyyy').format(date)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (attendance != null)
                Text('Attendance: ${attendance == 1 ? 'Full Day' : 'Half Day'}'),
              if (advanceSalary != null)
                Text('Advance Salary: ₹${advanceSalary.toStringAsFixed(2)}'),
              if (attendance == null && advanceSalary == null)
                const Text('No data for this day'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            if (attendance == null)
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _markAttendance(date);
                },
                child: const Text('Mark Attendance'),
              ),
          ],
        );
      },
    );
  }

  void _markAttendance(DateTime date) {
    final dateString = DateFormat('yyyy-MM-dd').format(date);
    final labor = ref.read(laborProvider.notifier).state.firstWhere((l) => l.id == widget.laborId);
    
    if (labor.attendance[dateString] == null) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Mark Attendance'),
            content: const Text('Choose attendance type:'),
            actions: [
              TextButton(
                onPressed: () {
                  _addAttendance(date, 1);
                  Navigator.pop(context);
                },
                child: const Text('Full Day'),
              ),
              TextButton(
                onPressed: () {
                  _addAttendance(date, 0.5);
                  Navigator.pop(context);
                },
                child: const Text('Half Day'),
              ),
            ],
          );
        },
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attendance already marked!')),
      );
    }
  }

  void _addAttendance(DateTime date, double days) {
    final dateString = DateFormat('yyyy-MM-dd').format(date);
    final labor = ref.read(laborProvider.notifier).state.firstWhere((l) => l.id == widget.laborId);
    final updatedAttendance = Map<String, double>.from(labor.attendance);
    
    updatedAttendance[dateString] = days;

    final updatedLabor = labor.copyWith(attendance: updatedAttendance);
    
    ref.read(laborProvider.notifier).updateLabor(updatedLabor);
  }
}
