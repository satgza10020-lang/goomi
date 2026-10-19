import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // กำหนดค่าการเชื่อมต่อ Firebase Realtime Database
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyDXq50KzmXXIVTKdQ0Vl43iDeJg3OZkYxA",
      authDomain: "check-in2-cc7a2.firebaseapp.com",
      databaseURL: "https://check-in2-cc7a2-default-rtdb.asia-southeast1.firebasedatabase.app",
      projectId: "check-in2-cc7a2",
      storageBucket: "check-in2-cc7a2.firebasestorage.app",
      messagingSenderId: "708380482219",
      appId: "1:708380482219:web:48c0cb916ec952ac7275ee",
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ระบบบันทึกเวลาเข้า-ออกงาน (RFID)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF312E81), // Deep Indigo
          primary: const Color(0xFF312E81),
          secondary: const Color(0xFF4F46E5),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF1F5F9), // Slate 100
        useMaterial3: true,
        fontFamily: 'sans-serif',
      ),
      builder: (context, child) {
        final screenWidth = MediaQuery.of(context).size.width;
        final isDesktop = screenWidth > 520;
        return Container(
          color: isDesktop ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9), // Dark slate desktop background
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 480, // Portrait mobile app width
              ),
              child: Container(
                margin: isDesktop ? const EdgeInsets.symmetric(vertical: 24) : EdgeInsets.zero,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: isDesktop ? BorderRadius.circular(32) : BorderRadius.zero,
                  border: isDesktop ? Border.all(color: const Color(0xFF334155), width: 3.5) : null,
                  boxShadow: isDesktop
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.55),
                            blurRadius: 36,
                            offset: const Offset(0, 12),
                          ),
                        ]
                      : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: child!,
              ),
            ),
          ),
        );
      },
      home: const MainNavigationScreen(),
    );
  }
}

// ==============================================================================
// 1. MAIN NAVIGATION SCREEN (รองรับการนำทาง 4 หน้าจอ)
// ==============================================================================
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  // Realtime Data
  List<Map<dynamic, dynamic>> attendanceLogs = [];
  Map<dynamic, dynamic> users = {};
  bool isLoading = true;

  // Live Clock
  late Timer _clockTimer;
  DateTime _currentTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    final tabParam = Uri.base.queryParameters['tab'];
    if (tabParam != null) {
      final tabIdx = int.tryParse(tabParam);
      if (tabIdx != null && tabIdx >= 0 && tabIdx <= 4) {
        _currentIndex = tabIdx;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Uri.base.queryParameters['drawer'] == 'open') {
        _scaffoldKey.currentState?.openDrawer();
      }
    });
    _startClock();
    _listenToFirebase();
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  void _startClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  void _listenToFirebase() {
    // 1. ดึงข้อมูล Users แบบ Real-time
    _dbRef.child('users').onValue.listen((event) {
      if (event.snapshot.value != null && mounted) {
        setState(() {
          users = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
        });
      } else if (mounted) {
        setState(() {
          users = {};
        });
      }
    });

    // 2. ดึงข้อมูลประวัติการลงเวลาแบบ Real-time
    _dbRef.child('attendance').onValue.listen((event) {
      if (event.snapshot.value != null && mounted) {
        final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
        List<Map<dynamic, dynamic>> loadedList = [];

        data.forEach((key, value) {
          final valMap = Map<dynamic, dynamic>.from(value as Map);
          String status = valMap['status']?.toString() ?? '';
          final timestamp = valMap['timestamp'] ?? 0;

          // คำนวณสถานะอัตโนมัติตามเกณฑ์ 3 ข้อ หากยังไม่มี status ระบุมา
          if (status.isEmpty && timestamp != 0) {
            final scanDt = DateTime.fromMillisecondsSinceEpoch(
              timestamp > 10000000000 ? timestamp : timestamp * 1000,
            );
            if (scanDt.hour >= 17) {
              status = 'Check-out'; // เกณฑ์ 3: ออกงาน ตั้งแต่ 17.00 น.
            } else if (scanDt.hour < 9) {
              status = 'On-time'; // เกณฑ์ 1: ตรงเวลา ก่อน 9.00 น.
            } else {
              status = 'Late'; // เกณฑ์ 2: สาย ตั้งแต่ 9.00 น. เป็นต้นไป
            }
          }

          loadedList.add({
            'id': key,
            ...valMap,
            'status': status,
          });
        });

        // เรียงลำดับเวลาล่าสุดขึ้นก่อน
        loadedList.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));

        setState(() {
          attendanceLogs = loadedList;
          isLoading = false;
        });
      } else if (mounted) {
        setState(() {
          attendanceLogs = [];
          isLoading = false;
        });
      }
    });
  }

  // นำทางไปยังหน้าที่เลือก
  void _navigateToPage(int index) {
    setState(() {
      _currentIndex = index;
    });
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(); // ปิด Drawer ถ้าเปิดอยู่
    }
  }

  @override
  Widget build(BuildContext context) {
    // รายชื่อ 5 หน้าจอหลักของระบบตามเกณฑ์ขอบเขตโครงงาน
    final List<Widget> pages = [
      DashboardScreen(
        logs: attendanceLogs,
        users: users,
        currentTime: _currentTime,
        isLoading: isLoading,
        onNavigate: _navigateToPage,
      ),
      AttendanceLogsScreen(
        logs: attendanceLogs,
        users: users,
        dbRef: _dbRef,
      ),
      EmployeeManagementScreen(
        users: users,
        dbRef: _dbRef,
      ),
      AnalyticsReportScreen(
        logs: attendanceLogs,
        users: users,
      ),
      const TeamAboutScreen(),
    ];



    return Scaffold(
      key: _scaffoldKey,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF312E81), // Deep Indigo
            boxShadow: [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                children: [
                  // ปุ่มเปิดเมนู Drawer
                  Builder(
                    builder: (ctx) => IconButton(
                      icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 24),
                      tooltip: 'เปิดเมนูนำทาง',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // โลโก้และชื่อระบบ
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4F46E5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.nfc_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _getTitleForIndex(_currentIndex),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            overflow: TextOverflow.ellipsis,
                          ),
                          maxLines: 1,
                        ),
                        const Row(
                          children: [
                            Icon(Icons.circle, size: 6, color: Color(0xFF10B981)),
                            SizedBox(width: 4),
                            Text(
                              'RFID Active · Realtime',
                              style: TextStyle(color: Color(0xFFA5B4FC), fontSize: 10),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // เวลาสด
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        DateFormat('HH:mm:ss').format(_currentTime),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Text(
                        DateFormat('dd/MM/yy').format(_currentTime),
                        style: const TextStyle(color: Color(0xFFA5B4FC), fontSize: 9.5),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),

      // เมนูนำทาง Drawer ด้านข้าง (เข้าถึงได้ทุกหน้า ไม่มีหน้าตัน)
      drawer: Drawer(
        backgroundColor: Colors.white,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
              decoration: const BoxDecoration(
                color: Color(0xFF312E81),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4F46E5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.nfc_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Smart RFID System',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    'ระบบลงเวลาพนักงาน',
                    style: TextStyle(color: Color(0xFFA5B4FC), fontSize: 12),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _buildDrawerItem(
                    index: 0,
                    icon: Icons.dashboard_rounded,
                    title: 'หน้าหลักแดชบอร์ด (Dashboard)',
                    subtitle: 'ภาพรวมสถิติและสัดส่วน ',
                  ),
                  _buildDrawerItem(
                    index: 1,
                    icon: Icons.history_rounded,
                    title: 'ประวัติการลงเวลา (History Logs)',
                    subtitle: 'ค้นหาและกรองข้อมูลการสแกน',
                  ),
                  _buildDrawerItem(
                    index: 2,
                    icon: Icons.badge_rounded,
                    title: 'จัดการพนักงาน (Users / RFID)',
                    subtitle: '(เพิ่ม แก้ไข ลบ)ข้อมูลผู้ถือบัตร',
                  ),
                  _buildDrawerItem(
                    index: 3,
                    icon: Icons.analytics_rounded,
                    title: 'รายงานและสถิติ ',
                    subtitle: 'สถิติขั้นสูง',
                  ),
                  const Divider(color: Color(0xFFF1F5F9), height: 24),
                  _buildDrawerItem(
                    index: 4,
                    icon: Icons.people_alt_rounded,
                    title: 'ข้อมูลผู้จัดทำ (About & Team)',
                    subtitle: 'สมาชิกกลุ่มและรายละเอียดโครงงาน',
                  ),
                ],
              ),
            ),
            // Footer ใน Drawer
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFFF8FAFC),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Smart RFID Attendance System',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      // เนื้อหาของหน้าจอที่เลือก
      body: pages[_currentIndex],

      // เมนูนำทางด้านล่าง (BottomNavigationBar) 5 หน้าจอ
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        backgroundColor: const Color(0xFF0F172A), // Dark slate matching frame
        elevation: 4,
        indicatorColor: const Color(0xFF4F46E5).withValues(alpha: 0.22),
        height: 62,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10);
          }
          return const TextStyle(color: Color(0xFF94A3B8), fontSize: 10);
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined, color: Color(0xFF94A3B8), size: 20),
            selectedIcon: Icon(Icons.dashboard_rounded, color: Colors.white, size: 20),
            label: 'แดชบอร์ด',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined, color: Color(0xFF94A3B8), size: 20),
            selectedIcon: Icon(Icons.history_rounded, color: Colors.white, size: 20),
            label: 'ประวัติ',
          ),
          NavigationDestination(
            icon: Icon(Icons.badge_outlined, color: Color(0xFF94A3B8), size: 20),
            selectedIcon: Icon(Icons.badge_rounded, color: Colors.white, size: 20),
            label: 'พนักงาน',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined, color: Color(0xFF94A3B8), size: 20),
            selectedIcon: Icon(Icons.analytics_rounded, color: Colors.white, size: 20),
            label: 'สถิติ',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_alt_outlined, color: Color(0xFF94A3B8), size: 20),
            selectedIcon: Icon(Icons.people_alt_rounded, color: Colors.white, size: 20),
            label: 'ผู้จัดทำ',
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({
    required int index,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isSelected = _currentIndex == index;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Material(
        color: isSelected ? const Color(0xFF312E81).withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: ListTile(
        leading: Icon(
          icon,
          color: isSelected ? const Color(0xFF312E81) : const Color(0xFF64748B),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? const Color(0xFF312E81) : const Color(0xFF1E293B),
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 11, color: Color.fromARGB(255, 3, 104, 244)),
        ),
        selected: isSelected,
        onTap: () => _navigateToPage(index),
      ),
    ),
  );
  }

  String _getTitleForIndex(int index) {
    switch (index) {
      case 0:
        return 'หน้าหลักแดชบอร์ด';
      case 1:
        return 'ประวัติการลงเวลา';
      case 2:
        return 'จัดการข้อมูลพนักงาน';
      case 3:
        return 'รายงานและสถิติ';
      case 4:
        return 'ข้อมูลผู้จัดทำ';
      default:
        return 'RFID System';
    }
  }
}

// ==============================================================================
// หน้าจอที่ 1: DASHBOARD SCREEN (ภาพรวมสถิติ, กราฟสัดส่วน KPI, รายการล่าสุด)
// ==============================================================================
class DashboardScreen extends StatelessWidget {
  final List<Map<dynamic, dynamic>> logs;
  final Map<dynamic, dynamic> users;
  final DateTime currentTime;
  final bool isLoading;
  final Function(int) onNavigate;

  const DashboardScreen({
    super.key,
    required this.logs,
    required this.users,
    required this.currentTime,
    required this.isLoading,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF4F46E5)),
      );
    }

    // กรองเฉพาะข้อมูลของวัน ณ ปัจจุบัน (Today)
    final today = currentTime;
    final todayLogs = logs.where((e) {
      final ts = e['timestamp'] ?? 0;
      if (ts == 0) return false;
      final dt = DateTime.fromMillisecondsSinceEpoch(
        ts > 10000000000 ? ts : ts * 1000,
      );
      return dt.year == today.year &&
          dt.month == today.month &&
          dt.day == today.day;
    }).toList();

    final totalCount = todayLogs.length;
    final onTimeCount = todayLogs.where((e) => e['status'] == 'On-time').length;
    final lateCount = todayLogs.where((e) => e['status'] == 'Late').length;
    final checkOutCount = todayLogs.where((e) => e['status'] == 'Check-out').length;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 14.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. STAT CARDS (2x2 Grid สำหรับหน้าจอแนวตั้ง)
              LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = (constraints.maxWidth - 10) / 2;

                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: cardWidth,
                        child: _buildMetricCard(
                          title: 'สแกนทั้งหมด',
                          value: '$totalCount',
                          badge: 'วันนี้',
                          accentColor: const Color(0xFF4F46E5),
                          icon: Icons.calendar_today_rounded,
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _buildMetricCard(
                          title: 'ตรงเวลา',
                          value: '$onTimeCount',
                          badge: totalCount > 0 ? '${((onTimeCount / totalCount) * 100).toStringAsFixed(0)}%' : '0%',
                          accentColor: const Color(0xFF059669),
                          icon: Icons.check_circle_outline_rounded,
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _buildMetricCard(
                          title: 'มาสาย',
                          value: '$lateCount',
                          badge: totalCount > 0 ? '${((lateCount / totalCount) * 100).toStringAsFixed(0)}%' : '0%',
                          accentColor: const Color(0xFFD97706),
                          icon: Icons.access_time_rounded,
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _buildMetricCard(
                          title: 'ออกงาน',
                          value: '$checkOutCount',
                          badge: totalCount > 0 ? '${((checkOutCount / totalCount) * 100).toStringAsFixed(0)}%' : '0%',
                          accentColor: const Color(0xFF0284C7),
                          icon: Icons.logout_rounded,
                        ),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 18),

              // 2. DYNAMIC RATIO PROGRESS BAR
              _buildRatioCard(totalCount, onTimeCount, lateCount, checkOutCount),

              const SizedBox(height: 18),

              // 3. QUICK ACTION SHORTCUTS (เพิ่มความน่าสนใจในการใช้งาน)
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildQuickAction(
                        icon: Icons.badge_rounded,
                        label: 'จัดการพนักงาน',
                        color: const Color(0xFF059669),
                        onTap: () => onNavigate(2),
                      ),
                      _buildQuickAction(
                        icon: Icons.search_rounded,
                        label: 'ค้นหาประวัติ',
                        color: const Color(0xFF0284C7),
                        onTap: () => onNavigate(1),
                      ),
                      _buildQuickAction(
                        icon: Icons.analytics_rounded,
                        label: 'รายงานสถิติ',
                        color: const Color(0xFF6366F1),
                        onTap: () => onNavigate(3),
                      ),
                      _buildQuickAction(
                        icon: Icons.info_outline_rounded,
                        label: 'ผู้จัดทำ',
                        color: const Color.fromARGB(255, 146, 148, 11),
                        onTap: () => onNavigate(4),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 4. RECENT ACTIVITY LIST (แสดง 6 รายการล่าสุด)
              Card(
                elevation: 0,
                color: const Color.fromARGB(255, 255, 255, 255),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color.fromARGB(255, 0, 0, 0)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.bolt_rounded, color: Color.fromARGB(255, 250, 227, 21)),
                              SizedBox(width: 10),
                              Text(
                                'รายการแตะบัตรล่าสุด (Live Feed)',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                              ),
                            ],
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                            label: const Text('ดูทั้งหมด'),
                            onPressed: () => onNavigate(1),
                          ),
                        ],
                      ),
                      const Divider(color: Color.fromARGB(255, 74, 74, 74)),
                      if (todayLogs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text('ยังไม่มีข้อมูลการสแกนบัตรวันนี้', style: TextStyle(color: Color(0xFF94A3B8))),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: min(6, todayLogs.length),
                          separatorBuilder: (context, index) => const Divider(color: Color(0xFFF8FAFC), height: 1),
                          itemBuilder: (context, index) {
                            final item = todayLogs[index];
                            final uid = item['uid'] ?? 'N/A';
                            final userName = users[uid]?['name'] ?? 'ไม่พบชื่อ (UID: $uid)';
                            final dept = users[uid]?['dept'] ?? 'ทั่วไป';
                            final status = item['status'] ?? '-';
                            final timestamp = item['timestamp'] ?? 0;

                            final formattedTime = timestamp != 0
                                ? DateFormat('HH:mm:ss · dd/MM/yy').format(
                                    DateTime.fromMillisecondsSinceEpoch(
                                      timestamp > 10000000000 ? timestamp : timestamp * 1000,
                                    ),
                                  )
                                : '-';

                            final statusColor = _getStatusColor(status);

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                              leading: CircleAvatar(
                                radius: 20,
                                backgroundColor: statusColor.withValues(alpha: 0.12),
                                child: Icon(_getStatusIcon(status), color: statusColor, size: 20),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      userName,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF1E293B)),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                '$dept · $formattedTime',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  _getStatusText(status),
                                  style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10.5),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String badge,
    required Color accentColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x05000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, color: accentColor, size: 15),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accentColor.withValues(alpha: 0.2)),
                ),
                child: Text(
                  badge,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: accentColor),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRatioCard(int total, int onTime, int late, int checkOut) {
    final double onTimeRatio = total > 0 ? (onTime / total) : 0.0;
    final double lateRatio = total > 0 ? (late / total) : 0.0;
    final double checkOutRatio = total > 0 ? (checkOut / total) : 0.0;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'การลงเวลาประจำวัน',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                  ),
                  Text('รวม $total ครั้ง', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5))),
                ],
              ),
              const SizedBox(height: 3),
              const Text(
                'เกณฑ์: ตรงเวลา (< 9:00 น.) | มาสาย (≥ 9:00 น.) | ออกงาน (≥ 17:00 น.)',
                style: TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  if (onTimeRatio > 0)
                    Expanded(flex: (onTimeRatio * 1000).toInt(), child: Container(color: const Color(0xFF059669))),
                  if (lateRatio > 0)
                    Expanded(flex: (lateRatio * 1000).toInt(), child: Container(color: const Color(0xFFD97706))),
                  if (checkOutRatio > 0)
                    Expanded(flex: (checkOutRatio * 1000).toInt(), child: Container(color: const Color(0xFF0284C7))),
                  if (total == 0)
                    Expanded(child: Container(color: const Color(0xFFE2E8F0))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildLegend(const Color(0xFF059669), 'ตรงเวลา', '$onTime คน'),
              _buildLegend(const Color(0xFFD97706), 'มาสาย', '$late คน'),
              _buildLegend(const Color(0xFF0284C7), 'ออกงาน', '$checkOut คน'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(Color color, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text('$label: ', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
        Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
          ],
        ),
      ),
    );
  }
}

// ==============================================================================
// หน้าจอที่ 2: ATTENDANCE LOGS SCREEN (ประวัติการลงเวลา & ค้นหา/กรองขั้นสูง)
// ==============================================================================
class AttendanceLogsScreen extends StatefulWidget {
  final List<Map<dynamic, dynamic>> logs;
  final Map<dynamic, dynamic> users;
  final DatabaseReference dbRef;

  const AttendanceLogsScreen({
    super.key,
    required this.logs,
    required this.users,
    required this.dbRef,
  });

  @override
  State<AttendanceLogsScreen> createState() => _AttendanceLogsScreenState();
}

class _AttendanceLogsScreenState extends State<AttendanceLogsScreen> {
  String searchQuery = '';
  String selectedFilter = 'ทั้งหมด';
  DateTime? selectedDate = DateTime.now();
  final TextEditingController _searchController = TextEditingController();

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Uri.base.queryParameters['dialog'] == 'scan') {
        _showScanDialog();
      } else if (Uri.base.queryParameters['dialog'] == 'datepicker') {
        _pickDate();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<dynamic, dynamic>> get _filteredList {
    return widget.logs.where((item) {
      final uid = (item['uid'] ?? '').toString().toLowerCase();
      final userName = (widget.users[item['uid']]?['name'] ?? '').toString().toLowerCase();
      final status = (item['status'] ?? '').toString();
      final timestamp = item['timestamp'] ?? 0;

      // 1. ตรวจสอบการค้นหาชื่อหรือ UID
      final query = searchQuery.toLowerCase();
      final matchesSearch = query.isEmpty || userName.contains(query) || uid.contains(query);

      // 2. ตรวจสอบตัวกรองสถานะ
      bool matchesFilter = true;
      if (selectedFilter == 'ตรงเวลา') {
        matchesFilter = status == 'On-time';
      } else if (selectedFilter == 'มาสาย') {
        matchesFilter = status == 'Late';
      } else if (selectedFilter == 'ออกงาน') {
        matchesFilter = status == 'Check-out';
      }

      // 3. ตรวจสอบตัวกรองวันที่ (ค่าเริ่มต้นคือวัน ณ ปัจจุบัน)
      bool matchesDate = true;
      if (selectedDate != null) {
        if (timestamp == 0) {
          matchesDate = false;
        } else {
          final itemDate = DateTime.fromMillisecondsSinceEpoch(
            timestamp > 10000000000 ? timestamp : timestamp * 1000,
          );
          matchesDate = itemDate.year == selectedDate!.year &&
              itemDate.month == selectedDate!.month &&
              itemDate.day == selectedDate!.day;
        }
      }

      return matchesSearch && matchesFilter && matchesDate;
    }).toList();
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      helpText: 'เลือกวันที่',
      cancelText: 'ยกเลิก',
      confirmText: 'ยืนยัน',
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF312E81),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF1E293B),
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: Colors.white,
              headerBackgroundColor: const Color(0xFF312E81),
              headerForegroundColor: Colors.white,
              headerHelpStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFFC7D2FE),
              ),
              headerHeadlineStyle: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              dayStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              todayBorder: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
              todayForegroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Colors.white; 
                  }
                  return const Color(0xFF312E81); 
                }),
              confirmButtonStyle: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(const Color(0xFF312E81)),
                foregroundColor: WidgetStateProperty.all(Colors.white),
                padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 18, vertical: 10)),
                shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              ),
              cancelButtonStyle: ButtonStyle(
                foregroundColor: WidgetStateProperty.all(const Color(0xFF64748B)),
                padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayLogs = _filteredList;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 14.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // TOOLBAR ค้นหาและตัวกรอง
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'ประวัติการลงเวลา',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${displayLogs.length} รายการ',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF312E81)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.nfc_rounded, size: 18),
                        label: const Text('จำลองสแกนบัตร (ทดสอบระบบ)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF312E81),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _showScanDialog,
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFC7D2FE)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.schedule_rounded, size: 16, color: Color(0xFF4F46E5)),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'เกณฑ์เวลา: 1. ตรงเวลา (< 9:00) | 2. สาย (≥ 9:00) | 3. ออกงาน (≥ 17:00)\n*สแกนเข้าได้ 1 ครั้ง/วัน และสแกนออกได้หลัง 17:00 น.',
                                style: TextStyle(fontSize: 10.5, color: Color(0xFF312E81), height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // ค้นหาและเลือกวันที่
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 40,
                              child: TextField(
                                controller: _searchController,
                                onChanged: (val) => setState(() => searchQuery = val.trim()),
                                style: const TextStyle(fontSize: 12.5),
                                decoration: InputDecoration(
                                  hintText: 'ค้นหาชื่อ หรือ UID...',
                                  hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                                  prefixIcon: const Icon(Icons.search, size: 17, color: Color(0xFF94A3B8)),
                                  suffixIcon: searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear, size: 15),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() => searchQuery = '');
                                          },
                                        )
                                      : null,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          PopupMenuButton<String>(
                            tooltip: 'ตัวเลือกวันที่',
                            onSelected: (value) {
                              if (value == 'today') {
                                setState(() => selectedDate = DateTime.now());
                              } else if (value == 'custom') {
                                _pickDate();
                              } else if (value == 'all') {
                                setState(() => selectedDate = null);
                              }
                            },
                            offset: const Offset(0, 44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            color: Colors.white,
                            elevation: 6,
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'today',
                                height: 38,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.today_rounded,
                                      size: 16,
                                      color: _isToday(selectedDate ?? DateTime(2000)) ? const Color(0xFF312E81) : const Color(0xFF64748B),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'วันนี้',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: _isToday(selectedDate ?? DateTime(2000)) ? FontWeight.bold : FontWeight.normal,
                                        color: _isToday(selectedDate ?? DateTime(2000)) ? const Color(0xFF312E81) : const Color(0xFF1E293B),
                                      ),
                                    ),
                                    if (_isToday(selectedDate ?? DateTime(2000))) ...[
                                      const Spacer(),
                                      const Icon(Icons.check_rounded, size: 16, color: Color(0xFF312E81)),
                                    ],
                                  ],
                                ),
                              ),
                              const PopupMenuDivider(height: 1),
                              const PopupMenuItem(
                                value: 'custom',
                                height: 38,
                                child: Row(
                                  children: [
                                    Icon(Icons.calendar_month_rounded, size: 16, color: Color(0xFF64748B)),
                                    SizedBox(width: 8),
                                    Text('เลือกจากปฏิทิน...', style: TextStyle(fontSize: 12.5, color: Color(0xFF1E293B))),
                                  ],
                                ),
                              ),
                              const PopupMenuDivider(height: 1),
                              PopupMenuItem(
                                value: 'all',
                                height: 38,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.all_inclusive_rounded,
                                      size: 16,
                                      color: selectedDate == null ? const Color(0xFF312E81) : const Color(0xFF64748B),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'ดูทั้งหมด',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: selectedDate == null ? FontWeight.bold : FontWeight.normal,
                                        color: selectedDate == null ? const Color(0xFF312E81) : const Color(0xFF1E293B),
                                      ),
                                    ),
                                    if (selectedDate == null) ...[
                                      const Spacer(),
                                      const Icon(Icons.check_rounded, size: 16, color: Color(0xFF312E81)),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                            child: Container(
                              height: 40,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: selectedDate != null ? const Color(0xFFEEF2FF) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selectedDate != null ? const Color(0xFF312E81) : const Color(0xFFE2E8F0),
                                  width: selectedDate != null ? 1.2 : 1.0,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.calendar_month_rounded,
                                    size: 15,
                                    color: selectedDate != null ? const Color(0xFF312E81) : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    selectedDate == null
                                        ? 'ดูทั้งหมด'
                                        : _isToday(selectedDate!)
                                            ? 'วันนี้'
                                            : DateFormat('dd/MM/yyyy').format(selectedDate!),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: selectedDate != null ? FontWeight.w600 : FontWeight.normal,
                                      color: selectedDate != null ? const Color(0xFF312E81) : const Color(0xFF64748B),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.arrow_drop_down_rounded,
                                    size: 18,
                                    color: selectedDate != null ? const Color(0xFF312E81) : const Color(0xFF64748B),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: ['ทั้งหมด', 'ตรงเวลา', 'มาสาย', 'ออกงาน'].map((label) {
                          final isSelected = selectedFilter == label;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3.0),
                              child: ChoiceChip(
                                label: Center(child: Text(label)),
                                selected: isSelected,
                                showCheckmark: false,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                onSelected: (sel) {
                                  if (sel) setState(() => selectedFilter = label);
                                },
                                selectedColor: const Color(0xFF312E81),
                                backgroundColor: const Color(0xFFF1F5F9),
                                labelStyle: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected ? Colors.white : const Color(0xFF475569),
                                ),
                                labelPadding: EdgeInsets.zero,
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                side: BorderSide(
                                  color: isSelected ? const Color(0xFF312E81) : const Color(0xFFE2E8F0),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // RESULT COUNT & TABLE
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'รายการสแกน (${displayLogs.length})',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                          ),
                          const Text(
                            'Real-time Firebase',
                            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Divider(color: Color(0xFFF1F5F9)),
                      if (displayLogs.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          alignment: Alignment.center,
                          child: const Column(
                            children: [
                              Icon(Icons.search_off_rounded, size: 40, color: Color(0xFFCBD5E1)),
                              SizedBox(height: 10),
                              Text('ไม่พบข้อมูลการสแกนที่ตรงตามเงื่อนไข', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                            ],
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: displayLogs.length,
                          separatorBuilder: (context, index) => const Divider(color: Color(0xFFF8FAFC), height: 1),
                          itemBuilder: (context, index) {
                            final item = displayLogs[index];
                            final id = item['id'];
                            final uid = item['uid'] ?? 'N/A';
                            final userName = widget.users[uid]?['name'] ?? 'ไม่พบชื่อ (UID: $uid)';
                            final dept = widget.users[uid]?['dept'] ?? 'ทั่วไป';
                            final status = item['status'] ?? '-';
                            final timestamp = item['timestamp'] ?? 0;

                            final formattedTime = timestamp != 0
                                ? DateFormat('dd/MM/yyyy HH:mm:ss').format(
                                    DateTime.fromMillisecondsSinceEpoch(
                                      timestamp > 10000000000 ? timestamp : timestamp * 1000,
                                    ),
                                  )
                                : '-';

                            final statusColor = _getStatusColor(status);

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: statusColor.withValues(alpha: 0.12),
                                child: Icon(_getStatusIcon(status), color: statusColor, size: 18),
                              ),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      userName,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      uid,
                                      style: const TextStyle(fontSize: 9.5, fontFamily: 'monospace', color: Color(0xFF475569)),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                '$dept · $formattedTime',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      _getStatusText(status),
                                      style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10.5),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
                                    tooltip: 'ลบรายการนี้',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () {
                                      _confirmDeleteLog(context, id);
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteLog(BuildContext context, dynamic id) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการลบรายการ'),
        content: const Text('ต้องการลบบันทึกการลงเวลานี้ออกจากระบบใช่หรือไม่?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.dbRef.child('attendance').child(id.toString()).remove();
              scaffoldMessenger.showSnackBar(
                const SnackBar(content: Text('ลบรายการเรียบร้อยแล้ว')),
              );
            },
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
  }

  void _showScanNoticeDialog({
    required String title,
    required String message,
    required bool isSuccess,
    Color? statusColor,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
              color: isSuccess ? (statusColor ?? const Color(0xFF059669)) : const Color(0xFFDC2626),
              size: 26,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF334155)),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF312E81),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
  }

  Future<void> _processScan(String uid, DateTime scanTime) async {
    if (uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาระบุรหัสบัตร RFID (UID)')),
      );
      return;
    }

    final userName = widget.users[uid]?['name'] ?? 'พนักงานทั่วไป (UID: $uid)';
    final timeStr = DateFormat('HH:mm:ss').format(scanTime);
    final hour = scanTime.hour;

    // ตรวจสอบประวัติการลงเวลาในวันเดียวกันของพนักงานคนนี้
    final sameDayLogs = widget.logs.where((item) {
      if (item['uid']?.toString() != uid) return false;
      final ts = item['timestamp'] ?? 0;
      if (ts == 0) return false;
      final itemDate = DateTime.fromMillisecondsSinceEpoch(
        ts > 10000000000 ? ts : ts * 1000,
      );
      return itemDate.year == scanTime.year &&
          itemDate.month == scanTime.month &&
          itemDate.day == scanTime.day;
    }).toList();

    // เงื่อนไข 3.1 & 3.2:
    // 1. ตรงเวลา: เข้าก่อน 9.00 น.
    // 2. สาย: ตั้งแต่ 9.00 น. เป็นต้นไป
    // 3. ออกงาน: หลังจาก 17.00 น. เป็นต้นไป
    if (hour < 17) {
      // ช่วงเวลาก่อน 17:00 น. (ช่วงเข้างาน)
      final hasCheckedIn = sameDayLogs.any((item) {
        final status = item['status'];
        return status == 'On-time' || status == 'Late';
      });

      if (hasCheckedIn) {
        final firstCheckIn = sameDayLogs.firstWhere(
          (item) => item['status'] == 'On-time' || item['status'] == 'Late',
        );
        final firstTs = firstCheckIn['timestamp'] ?? 0;
        final firstTimeStr = firstTs != 0
            ? DateFormat('HH:mm:ss').format(
                DateTime.fromMillisecondsSinceEpoch(
                  firstTs > 10000000000 ? firstTs : firstTs * 1000,
                ),
              )
            : '-';
        final firstStatusText = _getStatusText(firstCheckIn['status'] ?? '');

        _showScanNoticeDialog(
          title: 'ไม่สามารถสแกนซ้ำได้',
          message: 'คุณ $userName ได้ลงเวลาเข้างานของวันนี้ไปแล้วเมื่อเวลา $firstTimeStr น. (สถานะ: $firstStatusText)\n\nตามเงื่อนไข: สแกนเข้างานแล้ว 1 รอบ จะสแกนอีกรอบไม่ได้ จนกว่าจะถึงเวลาเลิกงาน (17:00 น. เป็นต้นไป)',
          isSuccess: false,
        );
        return;
      }

      // ตรวจสอบเวลาเข้างาน: ก่อน 9:00 = On-time, ตั้งแต่ 9:00 = Late
      final String status = hour < 9 ? 'On-time' : 'Late';
      final ts = (scanTime.millisecondsSinceEpoch / 1000).round();

      await widget.dbRef.child('attendance').push().set({
        'uid': uid,
        'status': status,
        'timestamp': ts,
      });

      _showScanNoticeDialog(
        title: status == 'On-time' ? 'ลงเวลาเข้างาน: ตรงเวลา' : 'ลงเวลาเข้างาน: มาสาย',
        message: 'บันทึกเวลาเข้างานเรียบร้อยแล้ว!\n• พนักงาน: $userName\n• รหัสบัตร: $uid\n• เวลาสแกน: $timeStr น.\n• สถานะ: ${_getStatusText(status)}',
        isSuccess: true,
        statusColor: _getStatusColor(status),
      );
    } else {
      // ช่วงเวลาเลิกงาน (ตั้งแต่ 17:00 น. เป็นต้นไป)
      final hasCheckedOut = sameDayLogs.any((item) => item['status'] == 'Check-out');

      if (hasCheckedOut) {
        final firstCheckOut = sameDayLogs.firstWhere((item) => item['status'] == 'Check-out');
        final firstTs = firstCheckOut['timestamp'] ?? 0;
        final firstTimeStr = firstTs != 0
            ? DateFormat('HH:mm:ss').format(
                DateTime.fromMillisecondsSinceEpoch(
                  firstTs > 10000000000 ? firstTs : firstTs * 1000,
                ),
              )
            : '-';

        _showScanNoticeDialog(
          title: 'สแกนออกงานแล้ว',
          message: 'คุณ $userName ได้ลงเวลาออกงานของวันนี้ไปแล้วเมื่อเวลา $firstTimeStr น.\nไม่สามารถสแกนออกงานซ้ำได้',
          isSuccess: false,
        );
        return;
      }

      const status = 'Check-out';
      final ts = (scanTime.millisecondsSinceEpoch / 1000).round();

      await widget.dbRef.child('attendance').push().set({
        'uid': uid,
        'status': status,
        'timestamp': ts,
      });

      _showScanNoticeDialog(
        title: 'ลงเวลาออกงานสำเร็จ',
        message: 'บันทึกเวลาเลิกงานเรียบร้อยแล้ว!\n• พนักงาน: $userName\n• รหัสบัตร: $uid\n• เวลาสแกน: $timeStr น.\n• สถานะ: ออกงาน (Check-out)',
        isSuccess: true,
        statusColor: _getStatusColor(status),
      );
    }
  }

  void _showScanDialog() {
    final userList = widget.users.entries.toList();
    String selectedUid = userList.isNotEmpty ? userList.first.key.toString() : '';
    final TextEditingController customUidCtrl = TextEditingController(text: selectedUid);
    String timePreset = 'live'; // 'live', 'morning', 'late', 'evening'

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.nfc_rounded, color: Color(0xFF312E81)),
                SizedBox(width: 8),
                Text('จำลองสแกนบัตร RFID', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('เลือกพนักงานในระบบ:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                    const SizedBox(height: 6),
                    if (userList.isNotEmpty)
                      DropdownButtonFormField<String>(
                        initialValue: selectedUid.isNotEmpty ? selectedUid : null,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: userList.map((e) {
                          final uid = e.key.toString();
                          final name = e.value['name'] ?? uid;
                          return DropdownMenuItem(value: uid, child: Text('$name ($uid)', style: const TextStyle(fontSize: 13)));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDlgState(() {
                              selectedUid = val;
                              customUidCtrl.text = val;
                            });
                          }
                        },
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: customUidCtrl,
                      decoration: InputDecoration(
                        labelText: 'หรือพิมพ์รหัสบัตร UID',
                        hintText: 'เช่น 4A88F12C',
                        prefixIcon: const Icon(Icons.credit_card_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onChanged: (val) => selectedUid = val.trim().toUpperCase(),
                    ),
                    const SizedBox(height: 16),
                    const Text('เลือกช่วงเวลาทดสอบตามเกณฑ์:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ChoiceChip(
                          label: const Text('เวลาปัจจุบัน'),
                          selected: timePreset == 'live',
                          selectedColor: const Color(0xFF312E81),
                          labelStyle: TextStyle(fontSize: 11, color: timePreset == 'live' ? Colors.white : const Color(0xFF334155)),
                          onSelected: (sel) {
                            if (sel) setDlgState(() => timePreset = 'live');
                          },
                        ),
                        ChoiceChip(
                          label: const Text('08:30 (ตรงเวลา < 9:00)'),
                          selected: timePreset == 'morning',
                          selectedColor: const Color(0xFF059669),
                          labelStyle: TextStyle(fontSize: 11, color: timePreset == 'morning' ? Colors.white : const Color(0xFF334155)),
                          onSelected: (sel) {
                            if (sel) setDlgState(() => timePreset = 'morning');
                          },
                        ),
                        ChoiceChip(
                          label: const Text('09:15 (มาสาย ≥ 9:00)'),
                          selected: timePreset == 'late',
                          selectedColor: const Color(0xFFD97706),
                          labelStyle: TextStyle(fontSize: 11, color: timePreset == 'late' ? Colors.white : const Color(0xFF334155)),
                          onSelected: (sel) {
                            if (sel) setDlgState(() => timePreset = 'late');
                          },
                        ),
                        ChoiceChip(
                          label: const Text('17:15 (ออกงาน ≥ 17:00)'),
                          selected: timePreset == 'evening',
                          selectedColor: const Color(0xFF0284C7),
                          labelStyle: TextStyle(fontSize: 11, color: timePreset == 'evening' ? Colors.white : const Color(0xFF334155)),
                          onSelected: (sel) {
                            if (sel) setDlgState(() => timePreset = 'evening');
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
              ElevatedButton.icon(
                icon: const Icon(Icons.sensors_rounded, size: 18),
                label: const Text('บันทึกสแกนบัตร'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF312E81),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  final uid = customUidCtrl.text.trim().toUpperCase();
                  if (uid.isEmpty) return;
                  Navigator.pop(ctx);

                  final now = DateTime.now();
                  DateTime scanTime = now;
                  if (timePreset == 'morning') {
                    scanTime = DateTime(now.year, now.month, now.day, 8, 30, 0);
                  } else if (timePreset == 'late') {
                    scanTime = DateTime(now.year, now.month, now.day, 9, 15, 0);
                  } else if (timePreset == 'evening') {
                    scanTime = DateTime(now.year, now.month, now.day, 17, 15, 0);
                  }

                  _processScan(uid, scanTime);
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

// ==============================================================================
// หน้าจอที่ 3: EMPLOYEE MANAGEMENT SCREEN (ลงทะเบียนพนักงาน & จัดการบัตร RFID)
// ==============================================================================
class EmployeeManagementScreen extends StatefulWidget {
  final Map<dynamic, dynamic> users;
  final DatabaseReference dbRef;

  const EmployeeManagementScreen({
    super.key,
    required this.users,
    required this.dbRef,
  });

  @override
  State<EmployeeManagementScreen> createState() => _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState extends State<EmployeeManagementScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _uidCtrl = TextEditingController();
  String _selectedDept = 'วิศวกรรมซอฟต์แวร์';

  final List<String> deptOptions = [
    'วิศวกรรมซอฟต์แวร์',
    'ฝ่ายบุคคล (HR)',
    'ฝ่ายการตลาด',
    'การเงินและบัญชี',
    'ฝ่ายขาย (Sales)',
    'ทั่วไป',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Uri.base.queryParameters['dialog'] == 'add') {
        _showAddEmployeeDialog();
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _uidCtrl.dispose();
    super.dispose();
  }

  void _showAddEmployeeDialog({String? editUid, String? initialName, String? initialDept}) {
    final isEdit = editUid != null;
    _nameCtrl.text = initialName ?? '';
    _uidCtrl.text = editUid ?? '';
    _selectedDept = initialDept ?? deptOptions.first;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(isEdit ? Icons.edit_rounded : Icons.person_add_rounded, color: const Color(0xFF312E81)),
              const SizedBox(width: 8),
              Text(isEdit ? 'แก้ไขข้อมูลพนักงาน' : 'ลงทะเบียนพนักงานใหม่'),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'ชื่อ - นามสกุล',
                      hintText: 'เช่น กานดา พัฒนศิลป์',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedDept,
                    decoration: InputDecoration(
                      labelText: 'แผนก / ฝ่ายงาน',
                      prefixIcon: const Icon(Icons.business_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    items: deptOptions
                        .map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 13))))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => _selectedDept = val);
                    },
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _uidCtrl,
                    enabled: !isEdit, // ถ้าแก้ไขห้ามเปลี่ยน UID
                    decoration: InputDecoration(
                      labelText: 'รหัสบัตร RFID (UID)',
                      hintText: 'เช่น 4A88F12C',
                      prefixIcon: const Icon(Icons.nfc_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF312E81),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final name = _nameCtrl.text.trim();
                final uid = _uidCtrl.text.trim().toUpperCase();

                if (name.isEmpty || uid.isEmpty) {
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(content: Text('กรุณากรอกข้อมูลให้ครบถ้วน')),
                  );
                  return;
                }

                Navigator.pop(ctx);
                await widget.dbRef.child('users').child(uid).set({
                  'name': name,
                  'dept': _selectedDept,
                });

                scaffoldMessenger.showSnackBar(
                  SnackBar(content: Text(isEdit ? 'แก้ไขข้อมูลสำเร็จ' : 'เพิ่มพนักงาน $name เรียบร้อย')),
                );
              },
              child: Text(isEdit ? 'บันทึกการแก้ไข' : 'บันทึกพนักงาน'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteUser(String uid, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการลบพนักงาน'),
        content: Text('ต้องการลบคุณ $name (UID: $uid) ออกจากระบบใช่หรือไม่?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.dbRef.child('users').child(uid).remove();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('ลบพนักงาน $name เรียบร้อยแล้ว')),
                );
              }
            },
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userList = widget.users.entries.toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 14.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // หัวข้อ & ปุ่มเพิ่มพนักงาน
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ทะเบียนพนักงาน',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'ทั้งหมด ${userList.length} คน',
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('เพิ่มพนักงาน'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF312E81),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => _showAddEmployeeDialog(),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // ตาราง/การ์ดรายชื่อพนักงาน
              if (userList.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  alignment: Alignment.center,
                  child: const Column(
                    children: [
                      Icon(Icons.person_off_rounded, size: 40, color: Color(0xFFCBD5E1)),
                      SizedBox(height: 10),
                      Text('ยังไม่มีข้อมูลพนักงานในระบบ', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                    ],
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: userList.map((entry) {
                        final uid = entry.key.toString();
                        final val = entry.value as Map<dynamic, dynamic>;
                        final name = val['name'] ?? 'ไม่ระบุชื่อ';
                        final dept = val['dept'] ?? 'ทั่วไป';

                        return SizedBox(
                          width: constraints.maxWidth,
                          child: Card(
                            elevation: 0,
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                                    child: const Icon(Icons.person_rounded, color: Color(0xFF4F46E5), size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1E293B),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          dept,
                                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'UID: $uid',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontFamily: 'monospace',
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF334155),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF4F46E5)),
                                    tooltip: 'แก้ไข',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => _showAddEmployeeDialog(
                                      editUid: uid,
                                      initialName: name,
                                      initialDept: dept,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                    tooltip: 'ลบ',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => _confirmDeleteUser(uid, name),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// หน้าจอที่ 5: TEAM & ABOUT SCREEN (หน้าผู้จัดทำ & ข้อมูลโครงงาน)
// ==============================================================================
class TeamAboutScreen extends StatelessWidget {
  const TeamAboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 14.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // BANNER ข้อมูลโครงงาน
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF312E81), Color(0xFF4F46E5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(color: Color(0x1F000000), blurRadius: 10, offset: Offset(0, 4)),
                  ],
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Smart RFID Attendance',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'ระบบบันทึกเวลาปฏิบัติงานพนักงานด้วยบัตร RFID และ Firebase Realtime Database',
                      style: TextStyle(color: Color(0xFFC7D2FE), fontSize: 12),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // การ์ดสมาชิกผู้จัดทำ (Team Members)
              const Text(
                'ผู้จัดทำโครงงาน (Project Creator)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 10),

              _buildCreatorCard(
                name: 'นายวรากร นุชชาติ (Warakorn Nootchat)',
                studentId: 'รหัสนักศึกษา: 016830641020-5',
                role: 'โครงงาน / ระบบสแกนบัตรเข้างาน',
                email: 'warakorn.noo@rmutto.ac.th',
                avatarEmoji: '👨‍💻',
              ),

              const SizedBox(height: 10),

              // รายละเอียดวิชาและสถาบัน
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'รายละเอียดของโปรเจกต์',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                      ),
                      SizedBox(height: 12),
                      _InfoRow(label: 'วิชา', val: 'Application Development for Mobile Devices & Embeded Systems and Internet of Things'),
                      _InfoRow(label: 'ฐานข้อมูลหลังบ้าน', val: 'Firebase Realtime Database (Real-time Sync)'),
                      _InfoRow(label: 'ส่วนของ IoT', val: 'Arduino IDE '),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreatorCard({
    required String name,
    required String studentId,
    required String role,
    required String email,
    required String avatarEmoji,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Center(child: Text(avatarEmoji, style: const TextStyle(fontSize: 24))),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                  const SizedBox(height: 2),
                  Text(studentId, style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                  Text(role, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF4F46E5))),
                  Text(email, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String val;
  const _InfoRow({required this.label, required this.val});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
          const SizedBox(height: 2),
          Text(val, style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B), height: 1.3)),
        ],
      ),
    );
  }
}

// ==============================================================================
// หน้าจอที่ 4: ANALYTICS & EXPORT REPORT SCREEN (รายงานสรุปและสถิติขั้นสูง)
// ==============================================================================
class AnalyticsReportScreen extends StatefulWidget {
  final List<Map<dynamic, dynamic>> logs;
  final Map<dynamic, dynamic> users;

  const AnalyticsReportScreen({
    super.key,
    required this.logs,
    required this.users,
  });

  @override
  State<AnalyticsReportScreen> createState() => _AnalyticsReportScreenState();
}

class _AnalyticsReportScreenState extends State<AnalyticsReportScreen> {
  int _selectedFilterDays = 1; // 1 วัน (วัน ณ ปัจจุบัน เป็นค่าเริ่มต้น), 7 วัน, 30 วัน, หรือทั้งหมด (0)

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // กรองข้อมูลตามช่วงเวลาที่เลือก
    final filteredLogs = widget.logs.where((log) {
      if (_selectedFilterDays == 0) return true;
      final ts = log['timestamp'] ?? 0;
      if (ts == 0) return true;
      final logDate = DateTime.fromMillisecondsSinceEpoch(
        ts > 10000000000 ? ts : ts * 1000,
      );

      if (_selectedFilterDays == 1) {
        // เฉพาะวันนี้
        return logDate.year == now.year &&
            logDate.month == now.month &&
            logDate.day == now.day;
      }
      return now.difference(logDate).inDays < _selectedFilterDays;
    }).toList();

    final totalScans = filteredLogs.length;
    final onTimeScans = filteredLogs.where((l) => l['status'] == 'On-time').length;
    final lateScans = filteredLogs.where((l) => l['status'] == 'Late').length;
    final checkOutScans = filteredLogs.where((l) => l['status'] == 'Check-out').length;

    final onTimePercent = totalScans > 0 ? (onTimeScans / totalScans * 100).toStringAsFixed(1) : '0.0';
    final latePercent = totalScans > 0 ? (lateScans / totalScans * 100).toStringAsFixed(1) : '0.0';
    final checkOutPercent = totalScans > 0 ? (checkOutScans / totalScans * 100).toStringAsFixed(1) : '0.0';

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. หัวเรื่องหน้าจอ
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF312E81), Color(0xFF4F46E5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x264F46E5),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.analytics_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'รายงานและสถิติ',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Analytics ',
                              style: TextStyle(color: Color(0xFFA5B4FC), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'วิเคราะห์ภาพรวมการบันทึกเวลาเข้า-ออกงาน',
                    style: TextStyle(color: Color(0xFFE0E7FF), fontSize: 11.5, height: 1.3),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 2. แถบเลือกช่วงเวลา (เพิ่ม 1 วัน เข้าไปตามที่ระบุ)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text(
                    'ช่วงเวลาข้อมูล:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip('1 วัน', 1),
                  const SizedBox(width: 6),
                  _buildFilterChip('7 วันล่าสุด', 7),
                  const SizedBox(width: 6),
                  _buildFilterChip('30 วัน', 30),
                  const SizedBox(width: 6),
                  _buildFilterChip('ทั้งหมด', 0),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 3. การ์ดสถิติ 4 ใบ
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    title: 'สแกนรวม',
                    val: '$totalScans',
                    unit: 'ครั้ง',
                    icon: Icons.account_circle,
                    color: const Color(0xFF4F46E5),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildMetricCard(
                    title: 'ตรงเวลา',
                    val: '$onTimePercent%',
                    unit: '$onTimeScans ครั้ง',
                    icon: Icons.check_circle_rounded,
                    color: const Color(0xFF059669),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    title: 'มาสาย',
                    val: '$latePercent%',
                    unit: '$lateScans ครั้ง',
                    icon: Icons.access_time_filled_rounded,
                    color: const Color(0xFFD97706),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildMetricCard(
                    title: 'ออกงาน',
                    val: '$checkOutPercent%',
                    unit: '$checkOutScans ครั้ง',
                    icon: Icons.logout_rounded,
                    color: const Color(0xFF0284C7),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, int days) {
    final isSelected = _selectedFilterDays == days;
    return InkWell(
      onTap: () => setState(() => _selectedFilterDays = days),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF312E81) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? const Color(0xFF312E81) : const Color(0xFFCBD5E1)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String val,
    required String unit,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
              Icon(icon, color: color, size: 18),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            val,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
          ),
          Text(unit, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
        ],
      ),
    );
  }
}

// ==============================================================================
// HELPER FUNCTIONS (สี ไอคอน ข้อความสถานะ)
// ==============================================================================
Color _getStatusColor(String status) {
  switch (status) {
    case 'On-time':
      return const Color(0xFF059669); // Emerald 600
    case 'Late':
      return const Color(0xFFD97706); // Amber 600
    case 'Check-out':
      return const Color(0xFF0284C7); // Sky 600
    default:
      return const Color(0xFF64748B);
  }
}

String _getStatusText(String status) {
  switch (status) {
    case 'On-time':
      return 'ตรงเวลา';
    case 'Late':
      return 'มาสาย';
    case 'Check-out':
      return 'ออกงาน';
    default:
      return status;
  }
}

IconData _getStatusIcon(String status) {
  switch (status) {
    case 'On-time':
      return Icons.check_circle_outline_rounded;
    case 'Late':
      return Icons.access_time_rounded;
    case 'Check-out':
      return Icons.logout_rounded;
    default:
      return Icons.help_outline_rounded;
  }
}