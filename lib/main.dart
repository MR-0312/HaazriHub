import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const LaborManagementApp());
}

// Main Application Entry
class LaborManagementApp extends StatelessWidget {
  const LaborManagementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Labor Management',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        fontFamily: GoogleFonts.poppins().fontFamily,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const HomeScreen(),
    );
  }
}

// Home Screen to List All Laborers
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<Labor> _laborers = [];

  void _addLabor(Labor labor) {
    setState(() {
      _laborers.add(labor);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Labor Management'),
      ),
      body: _laborers.isEmpty
          ? const Center(child: Text('No laborers added yet!'))
          : ListView.builder(
              itemCount: _laborers.length,
              itemBuilder: (context, index) {
                return LaborCard(
                  labor: _laborers[index],
                  onDelete: () {
                    setState(() {
                      _laborers.removeAt(index);
                    });
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => AddLaborScreen(onAdd: _addLabor)),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

// Labor Card Widget
class LaborCard extends StatelessWidget {
  final Labor labor;
  final VoidCallback onDelete;

  const LaborCard({Key? key, required this.labor, required this.onDelete}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: ListTile(
        title: Text(labor.name),
        subtitle: Text('Total Salary: ₹${labor.totalSalary.toStringAsFixed(2)}'),
        trailing: IconButton(
          icon: const Icon(Icons.delete),
          onPressed: onDelete,
        ),
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => LaborDetailScreen(labor: labor),
          ));
        },
      ),
    );
  }
}

// Labor Model
class Labor {
  String id;
  String name;
  double dailyWage;
  double advanceSalary;
  Map<String, double> attendance;

  Labor({
    required this.id,
    required this.name,
    required this.dailyWage,
    this.advanceSalary = 0,
    Map<String, double>? attendance,
  }) : attendance = attendance ?? {};

  double get totalDaysWorked => attendance.values.fold(0, (sum, value) => sum + value);

  double get totalSalary => (dailyWage * totalDaysWorked) - advanceSalary;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'dailyWage': dailyWage,
        'advanceSalary': advanceSalary,
        'attendance': attendance,
      };
}

// Add Labor Screen
class AddLaborScreen extends StatefulWidget {
  final Function(Labor) onAdd;

  const AddLaborScreen({Key? key, required this.onAdd}) : super(key: key);

  @override
  _AddLaborScreenState createState() => _AddLaborScreenState();
}

class _AddLaborScreenState extends State<AddLaborScreen> {
  final _nameController = TextEditingController();
  final _dailyWageController = TextEditingController();

  void _addLabor() {
    final newLabor = Labor(
      id: DateTime.now().toString(),
      name: _nameController.text,
      dailyWage: double.tryParse(_dailyWageController.text) ?? 0,
    );

    widget.onAdd(newLabor);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add New Labor')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _dailyWageController,
              decoration: const InputDecoration(labelText: 'Daily Wage'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _addLabor,
              child: const Text('Add Labor'),
            ),
          ],
        ),
      ),
    );
  }
}

// Labor Detail Screen
class LaborDetailScreen extends StatelessWidget {
  final Labor labor;

  const LaborDetailScreen({Key? key, required this.labor}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(labor.name)),
      body: Column(
        children: [
          ListTile(
            title: const Text('Daily Wage'),
            subtitle: Text('₹${labor.dailyWage}'),
          ),
          ListTile(
            title: const Text('Advance Salary'),
            subtitle: Text('₹${labor.advanceSalary}'),
          ),
          const Divider(),
          const Text('Attendance'),
          Expanded(child: AttendanceCalendar(labor: labor)),
        ],
      ),
    );
  }
}

// Attendance Calendar Widget
class AttendanceCalendar extends StatefulWidget {
  final Labor labor;

  const AttendanceCalendar({Key? key, required this.labor}) : super(key: key);

  @override
  _AttendanceCalendarState createState() => _AttendanceCalendarState();
}

class _AttendanceCalendarState extends State<AttendanceCalendar> {
  DateTime _selectedDay = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TableCalendar(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.now(),
          focusedDay: _selectedDay,
          selectedDayPredicate: (day) => isSameDay(day, _selectedDay),
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
            });
            _markAttendance(selectedDay);
          },
        ),
        const SizedBox(height: 20),
        Text('Total Days Worked: ${widget.labor.totalDaysWorked}'),
        Text('Total Salary: ₹${widget.labor.totalSalary.toStringAsFixed(2)}'),
      ],
    );
  }

  void _markAttendance(DateTime date) {
    if (widget.labor.attendance[DateFormat('yyyy-MM-dd').format(date)] == null) {
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
    setState(() {
      widget.labor.attendance[dateString] = days;
    });
  }
}