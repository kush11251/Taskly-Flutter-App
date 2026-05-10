import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

void main() async {
  // Required when executing async code before runApp()
  WidgetsFlutterBinding.ensureInitialized();

  // Load saved preferences on startup
  final prefs = await SharedPreferences.getInstance();
  final String? savedToken = prefs.getString('jwt_token');
  final String? savedUsername = prefs.getString('username');

  runApp(
    MultiProvider(
      providers: [
        // Pass the saved data into the AuthProvider
        ChangeNotifierProvider(
          create: (_) => AuthProvider(savedToken, savedUsername),
        ),
        ChangeNotifierProxyProvider<AuthProvider, TaskProvider>(
          create: (context) => TaskProvider(),
          update: (context, auth, previous) =>
              (previous ?? TaskProvider())..updateAuth(auth),
        ),
      ],
      child: const TasklyApp(),
    ),
  );
}

// ==========================================
// THEME & APP ROOT
// ==========================================
class TasklyApp extends StatelessWidget {
  const TasklyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Taskly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F13), // Deep AI-Native Dark
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7C3AED), // Neon Purple Accent
          secondary: Color(0xFF38BDF8), // Electric Blue
          surface: Color(0xFF1A1A24), // Elevated dark cards
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F0F13),
          elevation: 0,
          centerTitle: true,
        ),
        // FIX: Changed CardTheme to CardThemeData
        cardTheme: CardThemeData(
          color: const Color(0xFF1A1A24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 4,
        ),
      ),
      home: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          return auth.isAuthenticated
              ? const HomeScreen()
              : const LoginScreen();
        },
      ),
    );
  }
}

// ==========================================
// MODELS
// ==========================================
class Task {
  final String? id;
  final String title;
  final String description;
  final DateTime date;
  bool isCompleted;

  Task({
    this.id,
    required this.title,
    required this.description,
    required this.date,
    this.isCompleted = false,
  });

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['_id'],
    title: json['title'],
    description: json['description'] ?? '',
    date: DateTime.parse(json['date']).toLocal(),
    isCompleted: json['isCompleted'] ?? false,
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'date': date.toUtc().toIso8601String(),
    'isCompleted': isCompleted,
  };
}

// ==========================================
// API SERVICE
// ==========================================
class ApiService {
  final String baseUrl = "https://taskly-backend-xbv4.onrender.com/api";
  late Dio _dio;

  ApiService() {
    _dio = Dio(BaseOptions(baseUrl: baseUrl));
  }

  void setToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  void clearToken() {
    _dio.options.headers.remove('Authorization');
  }

  // --- NEW: Register API Call ---
  Future<Map<String, dynamic>> register(
    String username,
    String passcode,
  ) async {
    try {
      final response = await _dio.post(
        '/register',
        data: {'username': username, 'passcode': passcode},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? 'Registration failed');
    }
  }

  Future<Map<String, dynamic>> login(String username, String passcode) async {
    try {
      final response = await _dio.post(
        '/login',
        data: {'username': username, 'passcode': passcode},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? 'Login failed');
    }
  }

  Future<List<Task>> fetchTasks() async {
    final response = await _dio.get('/tasks');
    return (response.data as List).map((t) => Task.fromJson(t)).toList();
  }

  Future<Task> addTask(Task task) async {
    final response = await _dio.post('/tasks', data: task.toJson());
    return Task.fromJson(response.data);
  }

  Future<Task> updateTask(String id, Task task) async {
    final response = await _dio.put('/tasks/$id', data: task.toJson());
    return Task.fromJson(response.data);
  }

  Future<void> deleteTask(String id) async {
    await _dio.delete('/tasks/$id');
  }

  Future<List<AppUser>> fetchUsers() async {
    final response = await _dio.get('/users');
    return (response.data as List)
        .map((user) => AppUser.fromJson(user))
        .toList();
  }

  Future<void> deleteUser(String id) async {
    await _dio.delete('/users/$id');
  }
}

class AppUser {
  final String id;
  final String username;

  AppUser({required this.id, required this.username});

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['_id'] ?? json['id'] ?? '',
    username: json['username'] ?? json['name'] ?? 'Unknown',
  );
}

// ==========================================
// STATE MANAGEMENT (PROVIDERS)
// ==========================================
class AuthProvider with ChangeNotifier {
  final ApiService apiService = ApiService();
  String? _token;
  String? _username;

  // Constructor accepts saved credentials on startup
  AuthProvider(this._token, this._username) {
    if (_token != null) {
      // If a token was found on disk, attach it to Dio immediately
      apiService.setToken(_token!);
    }
  }

  bool get isAuthenticated => _token != null;
  String? get username => _username;

  Future<void> login(String username, String passcode) async {
    try {
      final data = await apiService.login(username, passcode);
      _token = data['token'];
      _username = data['username'];

      // Attach to Dio for future requests
      apiService.setToken(_token!);

      // --- NEW: Save to SharedPreferences ---
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jwt_token', _token!);
      await prefs.setString('username', _username!);

      notifyListeners();
    } catch (e) {
      throw Exception('Login Failed: Check credentials');
    }
  }

  Future<void> logout() async {
    _token = null;
    _username = null;
    apiService.clearToken();

    // --- NEW: Clear SharedPreferences ---
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('username');

    notifyListeners();
  }
}

class TaskProvider with ChangeNotifier {
  late AuthProvider _auth;
  List<Task> _tasks = [];
  bool _isLoading = false;

  List<Task> get tasks => _tasks;
  bool get isLoading => _isLoading;

  void updateAuth(AuthProvider auth) {
    _auth = auth;
    if (_auth.isAuthenticated) {
      fetchTasks();
    } else {
      _tasks = [];
    }
  }

  List<Task> getTasksForDay(DateTime day) {
    return _tasks.where((task) => isSameDay(task.date, day)).toList();
  }

  Future<void> fetchTasks() async {
    _isLoading = true;
    notifyListeners();
    try {
      _tasks = await _auth.apiService.fetchTasks();
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addTask(Task task) async {
    try {
      final newTask = await _auth.apiService.addTask(task);
      _tasks.add(newTask);
      notifyListeners();
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> toggleTaskStatus(Task task) async {
    final originalStatus = task.isCompleted;
    task.isCompleted = !task.isCompleted;
    notifyListeners(); // Optimistic update
    try {
      await _auth.apiService.updateTask(task.id!, task);
    } catch (e) {
      task.isCompleted = originalStatus; // Revert on failure
      notifyListeners();
    }
  }

  Future<void> deleteTask(String id) async {
    _tasks.removeWhere((t) => t.id == id);
    notifyListeners(); // Optimistic update
    try {
      await _auth.apiService.deleteTask(id);
    } catch (e) {
      fetchTasks(); // Re-fetch on failure to sync state
    }
  }
}

// ==========================================
// SCREENS
// ==========================================

/// LOGIN SCREEN WITH CUSTOM NUMPAD
class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  String _passcode = "";
  bool _isLoading = false;
  int _secretTapCount = 0;

  void _onNumpadTap(String value) {
    if (_passcode.length < 6) {
      setState(() => _passcode += value);
    }
  }

  void _onBackspace() {
    if (_passcode.isNotEmpty) {
      setState(() => _passcode = _passcode.substring(0, _passcode.length - 1));
    }
  }

  void _handleSecretTap() {
    _secretTapCount += 1;
    if (_secretTapCount >= 3) {
      _secretTapCount = 0;
      _openSecretUserAdmin();
    }
  }

  void _openSecretUserAdmin() {
    final api = Provider.of<AuthProvider>(context, listen: false).apiService;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SecretUsersScreen(apiService: api)),
    );
  }

  Future<void> _attemptLogin() async {
    if (_usernameController.text.isEmpty || _passcode.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      await Provider.of<AuthProvider>(
        context,
        listen: false,
      ).login(_usernameController.text, _passcode);
    } catch (e) {
      // Cleaned up the error message display
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
      setState(() => _passcode = ""); // clear on fail
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.visibility_off, color: Color(0xFF0F0F13)),
          tooltip: 'Secret access',
          onPressed: _handleSecretTap,
        ),
        actions: [
          // --- NEW: Create User Icon ---
          IconButton(
            icon: const Icon(Icons.person_add, color: Color(0xFF38BDF8)),
            tooltip: 'Create new user',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RegisterScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        // --- FIX: Wrapped in SingleChildScrollView to prevent keyboard overflow ---
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 32.0,
              vertical: 16.0,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 64,
                  color: Color(0xFF7C3AED),
                ),
                const SizedBox(height: 24),
                const Text(
                  "Secure Access",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: "Username",
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(6, (index) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: index < _passcode.length
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.surface,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 40),
                _buildNumpad(),
                const SizedBox(height: 24),
                _isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _attemptLogin,
                        child: const Text(
                          "Enter Vault",
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumpad() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.5,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: 12,
      itemBuilder: (context, index) {
        if (index == 9) return const SizedBox.shrink(); // Empty slot
        if (index == 11) {
          return IconButton(
            icon: const Icon(Icons.backspace_outlined, color: Colors.grey),
            onPressed: _onBackspace,
          );
        }
        final number = index == 10 ? '0' : '${index + 1}';
        return InkWell(
          onTap: () => _onNumpadTap(number),
          borderRadius: BorderRadius.circular(30),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
          ),
        );
      },
    );
  }
}

/// REGISTER SCREEN
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _usernameController = TextEditingController();
  String _passcode = "";
  bool _isLoading = false;

  void _onNumpadTap(String value) {
    if (_passcode.length < 6) {
      setState(() => _passcode += value);
    }
  }

  void _onBackspace() {
    if (_passcode.isNotEmpty) {
      setState(() => _passcode = _passcode.substring(0, _passcode.length - 1));
    }
  }

  Future<void> _attemptRegister() async {
    if (_usernameController.text.isEmpty || _passcode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a username and passcode')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final apiService = Provider.of<AuthProvider>(
        context,
        listen: false,
      ).apiService;
      final response = await apiService.register(
        _usernameController.text,
        _passcode,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response['message'] ?? 'User registered successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); // Redirect back to login screen on success
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
      setState(() => _passcode = ""); // clear on fail
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("Create User"),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 32.0,
              vertical: 16.0,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.person_add_alt_1,
                  size: 64,
                  color: Color(0xFF38BDF8),
                ),
                const SizedBox(height: 24),
                const Text(
                  "Set Up Vault",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: "New Username",
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(6, (index) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: index < _passcode.length
                            ? Theme.of(context).colorScheme.secondary
                            : Theme.of(context).colorScheme.surface,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 40),
                _buildNumpad(),
                const SizedBox(height: 24),
                _isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.secondary,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _attemptRegister,
                        child: const Text(
                          "Register",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumpad() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.5,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: 12,
      itemBuilder: (context, index) {
        if (index == 9) return const SizedBox.shrink();
        if (index == 11) {
          return IconButton(
            icon: const Icon(Icons.backspace_outlined, color: Colors.grey),
            onPressed: _onBackspace,
          );
        }
        final number = index == 10 ? '0' : '${index + 1}';
        return InkWell(
          onTap: () => _onNumpadTap(number),
          borderRadius: BorderRadius.circular(30),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
          ),
        );
      },
    );
  }
}

/// HOME SCREEN & CALENDAR
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => Provider.of<TaskProvider>(context, listen: false).fetchTasks(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final taskProvider = Provider.of<TaskProvider>(context);
    final selectedDayTasks = taskProvider.getTasksForDay(
      _selectedDay ?? _focusedDay,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () =>
                Provider.of<AuthProvider>(context, listen: false).logout(),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCalendar(taskProvider),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Tasks for ${DateFormat('MMM dd').format(_selectedDay ?? _focusedDay)}",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: taskProvider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : selectedDayTasks.isEmpty
                ? const Center(
                    child: Text(
                      "No tasks scheduled for this day.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: selectedDayTasks.length,
                    itemBuilder: (context, index) {
                      final task = selectedDayTasks[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: Checkbox(
                            value: task.isCompleted,
                            activeColor: Theme.of(
                              context,
                            ).colorScheme.secondary,
                            onChanged: (val) =>
                                taskProvider.toggleTaskStatus(task),
                          ),
                          title: Text(
                            task.title,
                            style: TextStyle(
                              decoration: task.isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: task.isCompleted
                                  ? Colors.grey
                                  : Colors.white,
                            ),
                          ),
                          subtitle: task.description.isNotEmpty
                              ? Text(
                                  task.description,
                                  style: const TextStyle(color: Colors.grey),
                                )
                              : null,
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                            ),
                            onPressed: () => taskProvider.deleteTask(task.id!),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  AddTaskScreen(selectedDate: _selectedDay ?? _focusedDay),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCalendar(TaskProvider taskProvider) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: TableCalendar(
        firstDay: DateTime.utc(2020, 1, 1),
        lastDay: DateTime.utc(2030, 12, 31),
        focusedDay: _focusedDay,
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        onDaySelected: (selectedDay, focusedDay) {
          setState(() {
            _selectedDay = selectedDay;
            _focusedDay = focusedDay;
          });
        },
        eventLoader: (day) => taskProvider.getTasksForDay(day),
        calendarStyle: CalendarStyle(
          todayDecoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
          selectedDecoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
          ),
          markerDecoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondary,
            shape: BoxShape.circle,
          ),
        ),
        headerStyle: const HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
        ),
      ),
    );
  }
}

class SecretUsersScreen extends StatefulWidget {
  final ApiService apiService;
  const SecretUsersScreen({Key? key, required this.apiService})
    : super(key: key);

  @override
  _SecretUsersScreenState createState() => _SecretUsersScreenState();
}

class _SecretUsersScreenState extends State<SecretUsersScreen> {
  List<AppUser> _users = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final users = await widget.apiService.fetchUsers();
      setState(() => _users = users);
    } catch (e) {
      setState(() => _error = 'Failed to load users');
      debugPrint(e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteUser(String id) async {
    setState(() {
      _users.removeWhere((user) => user.id == id);
      _isLoading = true;
    });

    try {
      await widget.apiService.deleteUser(id);
    } catch (e) {
      debugPrint(e.toString());
      await _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Unable to delete user.')));
      }
      return;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _confirmDeleteUser(AppUser user) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: Text(
          'Delete user "${user.username}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteUser(user.id);
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Secret Users'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadUsers),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            )
          : _users.isEmpty
          ? const Center(
              child: Text(
                'No users found.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              separatorBuilder: (_, __) => const Divider(color: Colors.white12),
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final user = _users[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  tileColor: Theme.of(context).colorScheme.surface,
                  leading: const Icon(Icons.person, color: Color(0xFF38BDF8)),
                  title: Text(
                    user.username,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    user.id,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                    ),
                    onPressed: () => _confirmDeleteUser(user),
                  ),
                );
              },
            ),
    );
  }
}

/// ADD TASK SCREEN
class AddTaskScreen extends StatefulWidget {
  final DateTime selectedDate;
  const AddTaskScreen({Key? key, required this.selectedDate}) : super(key: key);

  @override
  _AddTaskScreenState createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  late DateTime _taskDate;

  @override
  void initState() {
    super.initState();
    _taskDate = widget.selectedDate;
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _taskDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (date != null) setState(() => _taskDate = date);
  }

  void _submit() {
    if (_titleController.text.isEmpty) return;
    final task = Task(
      title: _titleController.text,
      description: _descController.text,
      date: _taskDate,
    );
    Provider.of<TaskProvider>(context, listen: false).addTask(task);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("New Task")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: "Task Title",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: "Description (Optional)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                "Date: ${DateFormat('yyyy-MM-dd').format(_taskDate)}",
              ),
              trailing: const Icon(
                Icons.calendar_month,
                color: Color(0xFF38BDF8),
              ),
              onTap: _pickDate,
            ),
            const Spacer(),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _submit,
              child: const Text(
                "Create Task",
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
