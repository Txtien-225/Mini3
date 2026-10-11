import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ocr/ocr_service.dart';

void main() => runApp(const ExpenseApp());

class Expense {
  Expense({required this.merchant, required this.amount, required this.date, required this.category, this.note = ''});
  String merchant;
  double amount;
  DateTime date;
  String category;
  String note;
}

class ParsedReceipt {
  final String merchant;
  final double amount;
  final DateTime date;
  const ParsedReceipt(this.merchant, this.amount, this.date);
}

class ReceiptParser {
  static ParsedReceipt parse(String text) {
    final lines = text.split(RegExp(r'\r?\n')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final money = RegExp(r'(?:TOTAL|TỔNG|AMOUNT|THÀNH TIỀN)?\s*[:]?\s*([0-9][0-9., ]{2,})\s*(?:VND|VNĐ|đ|₫)?', caseSensitive: false);
    final values = <double>[];
    for (final m in money.allMatches(text)) {
      final raw = m.group(1)!.replaceAll(' ', '');
      final normalized = raw.contains(',') && raw.contains('.') ? raw.replaceAll('.', '').replaceAll(',', '.') : raw.replaceAll(RegExp(r'[,\.]'), '');
      final value = double.tryParse(normalized);
      if (value != null && value > 100) values.add(value);
    }
    final dateMatch = RegExp(r'(\d{1,2})[\/-](\d{1,2})[\/-](\d{2,4})').firstMatch(text);
    final now = DateTime.now();
    final date = dateMatch == null ? now : DateTime(int.parse(dateMatch.group(3)!.length == 2 ? '20${dateMatch.group(3)}' : dateMatch.group(3)!), int.parse(dateMatch.group(2)!), int.parse(dateMatch.group(1)!));
    final merchant = lines.isEmpty ? 'Unknown merchant' : lines.firstWhere((line) => !RegExp(r'^[0-9\s.,:/-]+$').hasMatch(line), orElse: () => lines.first);
    return ParsedReceipt(merchant, values.isEmpty ? 0 : values.reduce(math.max), date);
  }
}

class ExpenseStore extends ChangeNotifier {
  final List<Expense> expenses = [
    Expense(merchant: 'Circle K', amount: 85000, date: DateTime.now().subtract(const Duration(days: 1)), category: 'Food'),
    Expense(merchant: 'Book Shop', amount: 120000, date: DateTime.now().subtract(const Duration(days: 3)), category: 'Study'),
    Expense(merchant: 'Grab', amount: 56000, date: DateTime.now().subtract(const Duration(days: 5)), category: 'Travel'),
  ];
  Future<void> load() async { final prefs = await SharedPreferences.getInstance(); final raw = prefs.getString('expenses'); if (raw == null) return; final decoded = (jsonDecode(raw) as List).cast<Map<String, dynamic>>(); expenses..clear()..addAll(decoded.map((e) => Expense(merchant: e['merchant'] as String, amount: (e['amount'] as num).toDouble(), date: DateTime.parse(e['date'] as String), category: e['category'] as String, note: e['note'] as String? ?? ''))); notifyListeners(); }
  void add(Expense value) { expenses.insert(0, value); notifyListeners(); unawaited(_save()); }
  Future<void> _save() async { final prefs = await SharedPreferences.getInstance(); await prefs.setString('expenses', jsonEncode(expenses.map((e) => {'merchant': e.merchant, 'amount': e.amount, 'date': e.date.toIso8601String(), 'category': e.category, 'note': e.note}).toList())); }
  double get total => expenses.fold(0, (sum, item) => sum + item.amount);
  Map<String, double> byCategory() { final map = <String, double>{}; for (final e in expenses) { map[e.category] = (map[e.category] ?? 0) + e.amount; } return map; }
}

class ExpenseApp extends StatefulWidget { const ExpenseApp({super.key}); @override State<ExpenseApp> createState() => _ExpenseAppState(); }
class _ExpenseAppState extends State<ExpenseApp> {
  final store = ExpenseStore();
  @override void initState() { super.initState(); store.load(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(animation: store, builder: (_, __) => MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff5b4bdb), brightness: Brightness.light), useMaterial3: true), home: HomeScreen(store: store)));
}

class HomeScreen extends StatefulWidget { const HomeScreen({super.key, required this.store}); final ExpenseStore store; @override State<HomeScreen> createState() => _HomeScreenState(); }
class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;
  @override Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: IndexedStack(index: tab, children: [Dashboard(store: widget.store, onAdd: () => setState(() => tab = 1)), AddExpense(store: widget.store), History(store: widget.store)])),
    bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i), destinations: const [NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'), NavigationDestination(icon: Icon(Icons.document_scanner_outlined), label: 'Scan receipt'), NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'History')]),
  );
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key, required this.store, required this.onAdd});
  final ExpenseStore store;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final map = store.byCategory();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Good morning', style: TextStyle(color: Colors.grey)),
            Text('Your spending', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          ]),
          IconButton.filled(onPressed: onAdd, icon: const Icon(Icons.add)),
        ]),
        const SizedBox(height: 20),
        Card(color: const Color(0xff5b4bdb), child: Padding(padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('TOTAL THIS PERIOD', style: TextStyle(color: Colors.white70, letterSpacing: 1)),
          const SizedBox(height: 8),
          Text('${formatMoney(store.total)} VND', style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
          const SizedBox(height: 18),
          LinearProgressIndicator(value: (store.total / 1000000).clamp(0, 1), backgroundColor: Colors.white24, color: Colors.white),
          const SizedBox(height: 8),
          const Text('Budget target: 1,000,000 VND', style: TextStyle(color: Colors.white70)),
        ]))),
        const SizedBox(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Category split', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          Text('${store.expenses.length} transactions', style: const TextStyle(color: Colors.grey)),
        ]),
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Row(children: [
          SizedBox(width: 150, height: 150, child: DonutChart(values: map)),
          const SizedBox(width: 18),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: map.entries.map((e) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: categoryColor(e.key), shape: BoxShape.circle)),
            const SizedBox(width: 8), Expanded(child: Text(e.key)),
            Text('${(e.value / (store.total == 0 ? 1 : store.total) * 100).round()}%'),
          ]))).toList())),
        ]))),
        const SizedBox(height: 24),
        const Text('Recent transactions', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...store.expenses.take(5).map((e) => ExpenseTile(expense: e)),
      ],
    );
  }
}

class AddExpense extends StatefulWidget { const AddExpense({super.key, required this.store}); final ExpenseStore store; @override State<AddExpense> createState() => _AddExpenseState(); }
class _AddExpenseState extends State<AddExpense> {
  final merchant = TextEditingController(text: 'Demo Supermarket'); final amount = TextEditingController(text: '150000'); final receiptText = TextEditingController(text: 'DEMO SUPERMARKET\nTOTAL: 150,000 VND\nDATE: 11/10/2026'); String category = 'Food'; DateTime date = DateTime.now(); bool scanning = false;
  Future<void> scan() async { setState(() => scanning = true); await Future<void>.delayed(const Duration(milliseconds: 500)); final parsed = ReceiptParser.parse(receiptText.text); merchant.text = parsed.merchant; amount.text = parsed.amount.toStringAsFixed(0); date = parsed.date; setState(() => scanning = false); }
  Future<void> pickImage() async { if (kIsWeb) { await scan(); return; } final file = await ImagePicker().pickImage(source: ImageSource.camera); if (file != null) { setState(() => scanning = true); final text = await recognizeReceipt(file.path); if (text.isNotEmpty) receiptText.text = text; final parsed = ReceiptParser.parse(receiptText.text); merchant.text = parsed.merchant; amount.text = parsed.amount.toStringAsFixed(0); date = parsed.date; setState(() => scanning = false); } }
  void save() { final value = double.tryParse(amount.text.replaceAll(',', '').replaceAll('.', '')) ?? 0; if (merchant.text.trim().isEmpty || value <= 0) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid merchant and amount'))); return; } widget.store.add(Expense(merchant: merchant.text.trim(), amount: value, date: date, category: category)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expense saved'))); }
  @override Widget build(BuildContext context) => SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const SizedBox(height: 10), const Text('New expense', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)), const SizedBox(height: 6), const Text('Scan a receipt or enter it manually', style: TextStyle(color: Colors.grey)), const SizedBox(height: 20), Card(child: InkWell(onTap: pickImage, borderRadius: BorderRadius.circular(12), child: Container(height: 145, width: double.infinity, decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0xfff0efff)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(scanning ? Icons.hourglass_top : Icons.camera_alt_outlined, size: 42, color: const Color(0xff5b4bdb)), const SizedBox(height: 10), Text(scanning ? 'Reading receipt…' : 'Tap to scan with camera', style: const TextStyle(fontWeight: FontWeight.w600)), const Text('Web fallback: parse sample text below', style: TextStyle(color: Colors.grey, fontSize: 12))])))), const SizedBox(height: 18), TextField(controller: receiptText, maxLines: 3, decoration: const InputDecoration(labelText: 'OCR text / paste receipt text', border: OutlineInputBorder(), prefixIcon: Icon(Icons.text_snippet_outlined))), const SizedBox(height: 10), OutlinedButton.icon(onPressed: scan, icon: const Icon(Icons.auto_awesome), label: const Text('Parse text')), const SizedBox(height: 20), TextField(controller: merchant, decoration: const InputDecoration(labelText: 'Merchant', prefixIcon: Icon(Icons.storefront_outlined), border: OutlineInputBorder())), const SizedBox(height: 14), TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Total amount (VND)', prefixIcon: Icon(Icons.payments_outlined), border: OutlineInputBorder())), const SizedBox(height: 14), DropdownButtonFormField<String>(value: category, decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()), items: ['Food', 'Study', 'Travel', 'Gear', 'Entertainment'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => category = v!)), const SizedBox(height: 24), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: save, icon: const Icon(Icons.save_outlined), label: const Padding(padding: EdgeInsets.all(14), child: Text('Save expense'))))]));
}

class History extends StatelessWidget { const History({super.key, required this.store}); final ExpenseStore store; @override Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [const SizedBox(height: 10), const Text('Transaction history', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)), const SizedBox(height: 18), ...store.expenses.map((e) => ExpenseTile(expense: e))]); }
class ExpenseTile extends StatelessWidget { const ExpenseTile({super.key, required this.expense}); final Expense expense; @override Widget build(BuildContext context) => Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(leading: CircleAvatar(backgroundColor: categoryColor(expense.category).withOpacity(.15), child: Icon(categoryIcon(expense.category), color: categoryColor(expense.category))), title: Text(expense.merchant, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text('${expense.category} • ${expense.date.day}/${expense.date.month}/${expense.date.year}'), trailing: Text('${formatMoney(expense.amount)}\nVND', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold)))); }

class DonutChart extends StatelessWidget { const DonutChart({super.key, required this.values}); final Map<String, double> values; @override Widget build(BuildContext context) => CustomPaint(painter: DonutPainter(values), child: const Center(child: Icon(Icons.pie_chart_outline, color: Color(0xff5b4bdb)))); }
class DonutPainter extends CustomPainter { DonutPainter(this.values); final Map<String, double> values; @override void paint(Canvas canvas, Size size) { final total = values.values.fold(0.0, (a, b) => a + b); final rect = Offset.zero & size; var start = -math.pi / 2; for (final e in values.entries) { final sweep = total == 0 ? 0.0 : e.value / total * math.pi * 2; canvas.drawArc(rect.deflate(12), start, sweep - .04, false, Paint()..color = categoryColor(e.key)..style = PaintingStyle.stroke..strokeWidth = 22..strokeCap = StrokeCap.round); start += sweep; } } @override bool shouldRepaint(covariant DonutPainter oldDelegate) => oldDelegate.values != values; }

String formatMoney(double value) => value.round().toString().replaceAllMapped(RegExp(r'(?<!^)(?=(\d{3})+$)'), (_) => ',');
Color categoryColor(String c) => {'Food': const Color(0xfff59e0b), 'Study': const Color(0xff5b4bdb), 'Travel': const Color(0xff10b981), 'Gear': const Color(0xffef4444), 'Entertainment': const Color(0xffec4899)}[c] ?? Colors.grey;
IconData categoryIcon(String c) => {'Food': Icons.restaurant, 'Study': Icons.menu_book, 'Travel': Icons.directions_car, 'Gear': Icons.shopping_bag, 'Entertainment': Icons.movie}[c] ?? Icons.receipt;
