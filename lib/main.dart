import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

typedef Json = Map<String, dynamic>;
typedef QDoc = QueryDocumentSnapshot<Map<String, dynamic>>;

final db = FirebaseFirestore.instance;

const kInk = Color(0xFF111827);
const kMute = Color(0xFF6B7280);
const kLine = Color(0xFFE5E7EB);
const kBg = Color(0xFFF5F6F8);
const kBrand = Color(0xFFE4572E);
const kBrandSoft = Color(0xFFFDEEE9);
const kBrandLine = Color(0xFFF4B9A8);
const kOk = Color(0xFF16A34A);
const kOkSoft = Color(0xFFE7F6EC);
const kBad = Color(0xFFDC2626);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'AIzaSyB-l8MbY7reEOS8AUbH_ld87ZAP4Q0sh94',
      appId: '1:744106925844:android:0259baf77c1cee0dc82c01',
      messagingSenderId: '744106925844',
      projectId: 'restaurant-manager-c2368',
      storageBucket: 'restaurant-manager-c2368.firebasestorage.app',
    ),
  );
  runApp(const MyOrderApp());
}

// ---------------- helpers ----------------
num _n(dynamic v) => v is num ? v : 0;

String rs(num n) {
  final neg = n < 0;
  final v = n.abs();
  final s = v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  final p = s.split('.');
  var i = p[0];
  if (i.length > 3) {
    var rest = i.substring(0, i.length - 3);
    final last = i.substring(i.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    i = '${parts.join(',')},$last';
  }
  return '${neg ? '-' : ''}₹$i${p.length > 1 ? '.${p[1]}' : ''}';
}

num orderTotal(Json o) =>
    ((o['items'] ?? []) as List).fold<num>(0, (a, i) => a + _n(i['p']) * _n(i['q']));
num orderCost(Json o) =>
    ((o['items'] ?? []) as List).fold<num>(0, (a, i) => a + _n(i['c']) * _n(i['q']));

List<Json> grouped(Json o) {
  final m = <String, Json>{};
  for (final e in (o['items'] ?? []) as List) {
    final i = Map<String, dynamic>.from(e as Map);
    final k = '${i['n']}|${i['p']}';
    if (m.containsKey(k)) {
      m[k]!['q'] = _n(m[k]!['q']) + _n(i['q']);
    } else {
      m[k] = {'n': i['n'], 'p': i['p'], 'c': i['c'] ?? 0, 'q': _n(i['q'])};
    }
  }
  return m.values.toList();
}

String genCode() {
  const ch = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random.secure();
  return List.generate(6, (_) => ch[r.nextInt(ch.length)]).join();
}

String billText(String shop, Json o) {
  final b = StringBuffer('$shop\nTable ${o['table']}\n--------------------\n');
  for (final g in grouped(o)) {
    b.writeln('${g['n']} x${g['q']}   ${rs(_n(g['p']) * _n(g['q']))}');
  }
  b.write('--------------------\nTotal: ${rs(orderTotal(o))}\nAabhar, fari padharjo!');
  return b.toString();
}

void toast(BuildContext c, String m, {bool err = false, String? action, VoidCallback? onAction}) {
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(
    content: Text(m),
    behavior: SnackBarBehavior.floating,
    duration: Duration(seconds: action == null ? 4 : 9),
    backgroundColor: err ? kBad : kInk,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    action: action == null ? null : SnackBarAction(label: action, textColor: Colors.white, onPressed: onAction ?? () {}),
  ));
}

/// Firestore write. Internet na hoy to write queue ma jay (offline), app atkti nathi.
Future<bool> run(BuildContext context, Future<void> Function() w, {String? queued}) async {
  try {
    await w().timeout(const Duration(seconds: 5));
    return true;
  } on TimeoutException {
    if (context.mounted) toast(context, queued ?? 'Offline: internet aave tyare sync thase');
    return true;
  } catch (e) {
    if (context.mounted) toast(context, 'Error: $e', err: true);
    return false;
  }
}

const kOther = 'Bija';
String secOf(Json d) {
  final s = '${d['cat'] ?? ''}'.trim();
  return s.isEmpty ? kOther : s;
}

List<String> sectionOrder(Ctx c, List<QDoc> menu) {
  final out = <String>[...c.sections];
  final extra = <String>{for (final m in menu) secOf(m.data())}
      .where((x) => !out.contains(x) && x != kOther)
      .toList()
    ..sort();
  out.addAll(extra);
  if (menu.any((m) => secOf(m.data()) == kOther)) out.add(kOther);
  return out;
}

final _imgCache = <String, Uint8List>{};
Widget itemImg(String id, Json d, {double size = 52}) {
  final s = '${d['img'] ?? ''}';
  final ph = Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: kBrandSoft, borderRadius: BorderRadius.circular(12)),
    child: Icon(Icons.restaurant_menu, color: kBrand, size: size * 0.45),
  );
  if (s.isEmpty) return ph;
  final key = '${id}_${s.length}';
  Uint8List b;
  final cached = _imgCache[key];
  if (cached != null) {
    b = cached;
  } else {
    try {
      b = base64Decode(s);
    } catch (_) {
      return ph;
    }
    _imgCache[key] = b;
  }
  return ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Image.memory(b, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true),
  );
}

String errText(Object? e) {
  if (e is FirebaseException && e.code == 'permission-denied') {
    return 'Permission nathi (restaurant band che, approve baki che ke email verify baki che)';
  }
  return '$e';
}

String fmtDate(dynamic ts) {
  if (ts is! Timestamp) return '';
  const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final d = ts.toDate();
  return '${d.day} ${mo[d.month - 1]} ${d.year}';
}

// ---------------- UI kit ----------------
class Surface extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding, margin;
  final VoidCallback? onTap;
  final Color color, border;
  const Surface({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.color = Colors.white,
    this.border = kLine,
    super.key,
  });
  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
          boxShadow: const [BoxShadow(color: Color(0x0A101828), blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      );
}

Widget pill(String t, {Color bg = kBrandSoft, Color fg = kBrand}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(t, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );

Widget sectionTitle(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 0, 10),
      child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kInk)),
    );

Widget empty(IconData icon, String t) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(children: [
        Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: Color(0xFFE9EBEF), shape: BoxShape.circle),
            child: Icon(icon, color: kMute, size: 30)),
        const SizedBox(height: 12),
        Text(t, textAlign: TextAlign.center, style: const TextStyle(color: kMute)),
      ]),
    );

class Seg extends StatelessWidget {
  final List<String> items;
  final int index;
  final ValueChanged<int> onChanged;
  const Seg({required this.items, required this.index, required this.onChanged, super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: const Color(0xFFE9EBEF), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == index ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: i == index
                        ? const [BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1))]
                        : null,
                  ),
                  child: Text(items[i],
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                          color: i == index ? kInk : kMute)),
                ),
              ),
            ),
        ]),
      );
}

class Pg extends StatelessWidget {
  final String title;
  final String? sub;
  final Widget? trailing;
  final List<Widget> children;
  const Pg(this.title, {this.sub, this.trailing, required this.children, super.key});
  @override
  Widget build(BuildContext context) => SafeArea(
        bottom: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: kInk)),
                  if (sub != null) Text(sub!, style: const TextStyle(color: kMute, fontSize: 14)),
                ]),
              ),
              if (trailing != null) trailing!,
            ]),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      );
}

class Qty extends StatelessWidget {
  final int v;
  final VoidCallback onAdd, onSub;
  const Qty({required this.v, required this.onAdd, required this.onSub, super.key});
  Widget btn(IconData i, VoidCallback f, {bool fill = false}) => GestureDetector(
        onTap: f,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: fill ? kBrand : Colors.transparent, borderRadius: BorderRadius.circular(10)),
          child: Icon(i, size: 20, color: fill ? Colors.white : kBrand),
        ),
      );
  @override
  Widget build(BuildContext context) {
    if (v == 0) {
      return GestureDetector(
        onTap: onAdd,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBrand)),
          child: const Text('ADD', style: TextStyle(color: kBrand, fontWeight: FontWeight.w800, fontSize: 13)),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(color: kBrandSoft, borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.all(2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(Icons.remove, onSub),
        SizedBox(
            width: 26,
            child: Text('$v',
                textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        btn(Icons.add, onAdd, fill: true),
      ]),
    );
  }
}

Future<List<String>?> askForm(BuildContext context, String title, List<String> labels,
    {List<String>? init, Set<int> numeric = const {}}) {
  final cs = [for (var i = 0; i < labels.length; i++) TextEditingController(text: init?[i] ?? '')];
  return showDialog<List<String>>(
    context: context,
    builder: (d) => AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TextField(
                  controller: cs[i],
                  keyboardType: numeric.contains(i) ? TextInputType.number : TextInputType.text,
                  decoration: InputDecoration(labelText: labels[i])),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel', style: TextStyle(color: kMute))),
        FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
            onPressed: () => Navigator.pop(d, cs.map((e) => e.text.trim()).toList()),
            child: const Text('Save')),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String msg, {String yes = 'Ha'}) async =>
    (await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(msg, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Na', style: TextStyle(color: kMute))),
                FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(90, 44)),
                    onPressed: () => Navigator.pop(d, true),
                    child: Text(yes)),
              ],
            ))) ??
    false;

// ---------------- BILL IMAGE ----------------
class BillCard extends StatelessWidget {
  final String shop;
  final Json o;
  final String? pay;
  const BillCard({required this.shop, required this.o, this.pay, super.key});

  String when() {
    const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = DateTime.now();
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${mo[d.month - 1]} ${d.year}, $h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  Widget dash() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          for (var i = 0; i < 32; i++)
            Expanded(child: Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 2), color: const Color(0xFFD1D5DB))),
        ]),
      );

  Widget cols(String a, String b, String c, String d, {bool head = false}) {
    final st = TextStyle(fontSize: 13, fontWeight: head ? FontWeight.w700 : FontWeight.w500, color: head ? kMute : kInk);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(flex: 5, child: Text(a, style: st)),
        SizedBox(width: 28, child: Text(b, textAlign: TextAlign.center, style: st)),
        SizedBox(width: 58, child: Text(c, textAlign: TextAlign.right, style: st)),
        SizedBox(width: 68, child: Text(d, textAlign: TextAlign.right, style: st)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = grouped(o);
    return Container(
      width: 340,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: kBrand, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.restaurant, color: Colors.white, size: 26),
          ),
        ),
        const SizedBox(height: 10),
        Text(shop, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text('Table ${o['table']}  ·  ${when()}', textAlign: TextAlign.center, style: const TextStyle(color: kMute, fontSize: 12.5)),
        dash(),
        cols('Item', 'Qty', 'Rate', 'Rakam', head: true),
        for (final g in items) cols('${g['n']}', '${_n(g['q']).toInt()}', rs(_n(g['p'])), rs(_n(g['p']) * _n(g['q']))),
        dash(),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(rs(orderTotal(o)), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: kBrand)),
        ]),
        if (pay != null) ...[
          const SizedBox(height: 10),
          Center(child: pill('Paid  ·  $pay', bg: kOkSoft, fg: kOk)),
        ],
        dash(),
        const Text('Aabhar! Fari padharjo.', textAlign: TextAlign.center, style: TextStyle(color: kMute, fontSize: 13)),
      ]),
    );
  }
}

Future<void> shareBill(BuildContext context, GlobalKey key, Json o) async {
  try {
    final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 3);
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('${Directory.systemTemp.path}/bill_table_${o['table']}_${DateTime.now().millisecondsSinceEpoch}.png');
    await f.writeAsBytes(bd!.buffer.asUint8List());
    await Share.shareXFiles([XFile(f.path, mimeType: 'image/png')], text: 'Tamaru bill');
  } catch (e) {
    if (context.mounted) toast(context, 'Bill image banavva ma error: $e', err: true);
  }
}

Future<void> showBill(BuildContext context, String shop, Json o, {String? pay}) {
  final key = GlobalKey();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kBg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (b) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: SingleChildScrollView(
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: RepaintBoundary(key: key, child: BillCard(shop: shop, o: o, pay: pay)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
            onPressed: () => shareBill(b, key, o),
            icon: const Icon(Icons.share),
            label: const Text('WhatsApp par moklo'),
          ),
        ]),
      ),
    ),
  );
}

// ---------------- app / session ----------------
class Ctx {
  final String rid, role, uname;
  final Json r;
  Ctx(this.rid, this.role, this.uname, this.r);
  CollectionReference<Json> col(String n) => db.collection('restaurants').doc(rid).collection(n);
  int get tables => _n(r['tables'] ?? 10).toInt();
  String get name => (r['name'] ?? '') as String;
  bool get owner => role == 'owner';
  String get roleLabel => {'owner': 'Owner', 'waiter': 'Order lenar', 'cashier': 'Bill counter'}[role] ?? role;
  List<String> get sections => [for (final e in (r['sections'] ?? []) as List) '$e'];
}

class MyOrderApp extends StatelessWidget {
  const MyOrderApp({super.key});
  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: kBrand).copyWith(primary: kBrand, onSurface: kInk, surface: Colors.white),
      scaffoldBackgroundColor: kBg,
      appBarTheme: const AppBarTheme(
          backgroundColor: kBg,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(color: kInk, fontSize: 20, fontWeight: FontWeight.w800)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kLine)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kLine)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kBrand, width: 1.5)),
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
      navigationBarTheme: const NavigationBarThemeData(backgroundColor: Colors.white, indicatorColor: kBrandSoft),
    );
    return MaterialApp(
      title: 'My Order',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(textTheme: GoogleFonts.interTextTheme(base.textTheme)),
      home: const Root(),
    );
  }
}

class Splash extends StatelessWidget {
  final bool logout;
  const Splash({this.logout = false, super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
          body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: kBrand),
            if (logout) ...[
              const SizedBox(height: 20),
              const Text('Account taiyar thai rahyo che...', style: TextStyle(color: kMute)),
              TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Logout')),
            ],
          ]),
        ),
      ));
}

class Root extends StatelessWidget {
  const Root({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (_, s) {
          if (s.connectionState == ConnectionState.waiting) return const Splash();
          final u = s.data;
          if (u == null) return const AuthPage();
          return Gate(key: ValueKey(u.uid), user: u);
        },
      );
}

/// Login pachi: admin check -> email verify -> profile -> restaurant (approval) -> Home.
class Gate extends StatefulWidget {
  final User user;
  const Gate({required this.user, super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  Stream<DocumentSnapshot<Json>>? adm, us, rs;
  String? watching;
  Timer? timer;
  int attempt = 0;
  bool ready = false, gaveUp = false;
  bool verified = FirebaseAuth.instance.currentUser?.emailVerified ?? false;

  Stream<DocumentSnapshot<Json>> admStream() => db.collection('admins').doc(widget.user.uid).snapshots();
  Stream<DocumentSnapshot<Json>> usStream() => db.collection('users').doc(widget.user.uid).snapshots();

  @override
  void initState() {
    super.initState();
    adm = admStream();
    us = usStream();
    timer = Timer(const Duration(seconds: 5), onSlow);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> restart({bool reconnect = false}) async {
    timer?.cancel();
    if (reconnect) {
      try {
        await db.disableNetwork();
        await db.enableNetwork();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      adm = admStream();
      us = usStream();
      rs = null;
      watching = null;
      ready = false;
      gaveUp = false;
    });
    timer = Timer(const Duration(seconds: 5), onSlow);
  }

  Future<void> onSlow() async {
    if (!mounted || ready) return;
    attempt++;
    if (attempt >= 3) {
      setState(() => gaveUp = true);
      return;
    }
    await restart(reconnect: true);
  }

  void manualRetry() {
    attempt = 0;
    restart(reconnect: true);
  }

  Widget wait(String label, {String? err}) {
    final stuck = gaveUp || err != null;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!stuck) const CircularProgressIndicator(color: kBrand),
            if (stuck) const Icon(Icons.wifi_off, size: 40, color: kMute),
            const SizedBox(height: 20),
            Text(
                err != null
                    ? 'Data load thayo nahi:\n$err'
                    : gaveUp
                        ? 'Server sathe connect thatu nathi.\nInternet check karo ane fari prayatn karo.'
                        : label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kMute)),
            if (stuck) ...[
              const SizedBox(height: 16),
              SizedBox(width: 220, child: FilledButton(onPressed: manualRetry, child: const Text('Fari prayatn karo'))),
            ],
            TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Logout')),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Json>>(
        stream: adm,
        builder: (_, a) {
          if (a.hasError) return wait('', err: errText(a.error));
          if (!a.hasData) return wait('Load thai rahyu che...');
          if (a.data!.exists) {
            ready = true;
            timer?.cancel();
            return const AdminPage();
          }
          if (!verified) {
            ready = true;
            timer?.cancel();
            return VerifyPage(onVerified: () {
              verified = true;
              attempt = 0;
              restart();
            });
          }
          return StreamBuilder<DocumentSnapshot<Json>>(
            stream: us,
            builder: (_, u) {
              if (u.hasError) return wait('', err: errText(u.error));
              if (!u.hasData || !u.data!.exists) return wait('Account taiyar thai rahyo che...');
              final ud = u.data!.data()!;
              final rid = ud['rid'] as String;
              if (watching != rid) {
                watching = rid;
                rs = db.collection('restaurants').doc(rid).snapshots();
              }
              return StreamBuilder<DocumentSnapshot<Json>>(
                stream: rs,
                builder: (_, r) {
                  if (r.hasError) return wait('', err: errText(r.error));
                  if (!r.hasData || !r.data!.exists) return wait('Restaurant load thai rahi che...');
                  final rd = r.data!.data()!;
                  ready = true;
                  timer?.cancel();
                  final st = '${rd['status'] ?? ''}';
                  if (st != 'approved') return PendingPage(name: '${rd['name'] ?? ''}', status: st);
                  return Home(c: Ctx(rid, ud['role'] as String, (ud['name'] ?? '') as String, rd));
                },
              );
            },
          );
        },
      );
}

// ---------------- EMAIL VERIFY ----------------
class VerifyPage extends StatefulWidget {
  final VoidCallback onVerified;
  const VerifyPage({required this.onVerified, super.key});
  @override
  State<VerifyPage> createState() => _VerifyPageState();
}

class _VerifyPageState extends State<VerifyPage> {
  bool busy = false;
  String? msg;
  Timer? poll;

  @override
  void initState() {
    super.initState();
    poll = Timer.periodic(const Duration(seconds: 4), (_) => check(silent: true));
  }

  @override
  void dispose() {
    poll?.cancel();
    super.dispose();
  }

  Future<void> check({bool silent = false}) async {
    if (!silent && mounted) setState(() => busy = true);
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      final u = FirebaseAuth.instance.currentUser;
      if (u != null && u.emailVerified) {
        await u.getIdToken(true);
        poll?.cancel();
        widget.onVerified();
        return;
      }
      if (!silent && mounted) setState(() => msg = 'Haji email verify thayo nathi. Email ma link par dabavo.');
    } catch (e) {
      if (!silent && mounted) setState(() => msg = 'Error: $e');
    }
    if (!silent && mounted) setState(() => busy = false);
  }

  Future<void> resend() async {
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (mounted) setState(() => msg = 'Verification email fari moklyo. Spam folder pan check karo.');
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => msg = e.code == 'too-many-requests' ? 'Thodi var pachi fari try karo' : 'Error: ${e.code}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(28),
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(color: kBrandSoft, shape: BoxShape.circle),
                  child: const Icon(Icons.mark_email_unread_outlined, color: kBrand, size: 34),
                ),
              ),
              const SizedBox(height: 22),
              const Text('Email verify karo', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('$email par verification link moklyo che.\nEmail ma link par dabavo, pachi ahiya pachha aavo. Spam folder pan check karo.',
                  textAlign: TextAlign.center, style: const TextStyle(color: kMute, height: 1.4)),
              if (msg != null)
                Padding(padding: const EdgeInsets.only(top: 14), child: Text(msg!, textAlign: TextAlign.center, style: const TextStyle(color: kBrand, fontWeight: FontWeight.w600))),
              const SizedBox(height: 24),
              FilledButton(
                  onPressed: busy ? null : () => check(),
                  child: busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : const Text('Meiil verify karyu, aagal vadho')),
              const SizedBox(height: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    side: const BorderSide(color: kLine),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                onPressed: resend,
                child: const Text('Fari email moklo', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Logout', style: TextStyle(color: kMute))),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- APPROVAL PENDING ----------------
class PendingPage extends StatelessWidget {
  final String name, status;
  const PendingPage({required this.name, required this.status, super.key});
  @override
  Widget build(BuildContext context) {
    final rej = status == 'rejected';
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: kBrandSoft, shape: BoxShape.circle),
              child: Icon(rej ? Icons.block : Icons.hourglass_top, color: kBrand, size: 34),
            ),
            const SizedBox(height: 22),
            Text(rej ? 'Approve thayu nathi' : 'Approval baki che', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
                rej
                    ? '"$name" ne admin e approve karyu nathi. Madad mate admin no sampark karo.'
                    : '"$name" admin approve kare tyare app potani jate chalu thase. Aa screen khuli rakhi shako.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: kMute, height: 1.4)),
            const SizedBox(height: 20),
            TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Logout')),
          ]),
        ),
      ),
    );
  }
}

// ---------------- ADMIN PANEL ----------------
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  int tab = 0;
  static const keys = ['pending', 'approved', 'rejected'];

  String stOf(Json d) {
    final s = '${d['status'] ?? 'pending'}';
    return keys.contains(s) ? s : 'pending';
  }

  Widget btn(String label, VoidCallback f, {Color color = kOk, bool outline = false}) => Expanded(
        child: outline
            ? OutlinedButton(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: color,
                    side: BorderSide(color: color),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: f,
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)))
            : FilledButton(
                style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size.fromHeight(48)),
                onPressed: f,
                child: Text(label)),
      );

  Future<void> setStatus(QDoc d, String st) async {
    await run(context, () => d.reference.update({'status': st}));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: StreamBuilder<QuerySnapshot<Json>>(
          stream: db.collection('restaurants').snapshots(),
          builder: (_, s) {
            if (s.hasError) {
              return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: ${errText(s.error)}', textAlign: TextAlign.center)));
            }
            final List<QDoc> all = [...(s.data?.docs ?? <QDoc>[])];
            final counts = [for (final k in keys) all.where((d) => stOf(d.data()) == k).length];
            final List<QDoc> list = all.where((d) => stOf(d.data()) == keys[tab]).toList()
              ..sort((a, b) => ((b.data()['created'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
                  .compareTo((a.data()['created'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
            return Pg('Admin panel',
                sub: 'Restaurant approval',
                trailing: IconButton(onPressed: () => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout, color: kMute)),
                children: [
                  Seg(
                      items: ['Pending (${counts[0]})', 'Approved (${counts[1]})', 'Rejected (${counts[2]})'],
                      index: tab,
                      onChanged: (v) => setState(() => tab = v)),
                  const SizedBox(height: 16),
                  if (list.isEmpty) empty(Icons.verified_user_outlined, 'Aa list ma koi restaurant nathi'),
                  for (final d in list)
                    Surface(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text('${d['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                          pill(keys[tab] == 'pending' ? 'Pending' : keys[tab] == 'approved' ? 'Approved' : 'Rejected',
                              bg: keys[tab] == 'approved' ? kOkSoft : kBrandSoft, fg: keys[tab] == 'approved' ? kOk : kBrand),
                        ]),
                        const SizedBox(height: 6),
                        Text('${d.data()['ownerName'] ?? ''}  ·  ${d.data()['ownerEmail'] ?? 'email nathi'}', style: const TextStyle(color: kMute)),
                        Text('${d.data()['tables'] ?? 10} tables  ·  ${fmtDate(d.data()['created'])}', style: const TextStyle(color: kMute, fontSize: 13)),
                        const SizedBox(height: 14),
                        Row(children: [
                          if (keys[tab] == 'pending') ...[
                            btn('Reject', () => setStatus(d, 'rejected'), color: kBad, outline: true),
                            const SizedBox(width: 10),
                            btn('Approve', () => setStatus(d, 'approved')),
                          ],
                          if (keys[tab] == 'approved') btn('Band karo', () => setStatus(d, 'rejected'), color: kBad, outline: true),
                          if (keys[tab] == 'rejected') btn('Fari chalu karo', () => setStatus(d, 'approved')),
                        ]),
                      ]),
                    ),
                ]);
          },
        ),
      );
}

// ---------------- AUTH ----------------
final authErr = ValueNotifier<String?>(null);
int authModeKeep = 0;

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  late int mode = authModeKeep;
  final em = TextEditingController(), pw = TextEditingController();
  final nm = TextEditingController(), rn = TextEditingController(), cd = TextEditingController();
  bool busy = false;

  String msg(String code) {
    switch (code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Email athva password khotu che';
      case 'email-already-in-use':
        return 'Aa email thi account pehla thi che. Login karo.';
      case 'weak-password':
        return 'Password ochha ma ochha 6 akshar no rakho';
      case 'invalid-email':
        return 'Email barobar nathi';
      case 'network-request-failed':
        return 'Internet check karo';
      case 'too-many-requests':
        return 'Ghana prayatno thaya, thodi var pachi try karo';
      default:
        return 'Error: $code';
    }
  }

  Future<void> forgot() async {
    final email = em.text.trim();
    if (email.isEmpty) {
      authErr.value = 'Pehla email nakho';
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      authErr.value = null;
      if (mounted) toast(context, 'Password reset ni link email par moklai');
    } on FirebaseAuthException catch (e) {
      authErr.value = msg(e.code);
    }
  }

  Future<void> go() async {
    final email = em.text.trim(), pass = pw.text;
    if (email.isEmpty || pass.isEmpty) {
      authErr.value = 'Email ane password nakho';
      return;
    }
    if (mode == 1 && (rn.text.trim().isEmpty || nm.text.trim().isEmpty)) {
      authErr.value = 'Restaurant nu naam ane tamaru naam nakho';
      return;
    }
    if (mode == 2 && (cd.text.trim().isEmpty || nm.text.trim().isEmpty)) {
      authErr.value = 'Code ane tamaru naam nakho';
      return;
    }
    authErr.value = null;
    setState(() => busy = true);
    final auth = FirebaseAuth.instance;
    try {
      if (mode == 0) {
        await auth.signInWithEmailAndPassword(email: email, password: pass);
      } else {
        final cred = await auth.createUserWithEmailAndPassword(email: email, password: pass);
        try {
          final uid = cred.user!.uid;
          if (mode == 1) {
            final rid = db.collection('restaurants').doc().id;
            final wc = genCode(), cc = genCode();
            await db.collection('restaurants').doc(rid).set({
              'name': rn.text.trim(),
              'ownerUid': uid,
              'tables': 10,
              'status': 'pending',
              'ownerName': nm.text.trim(),
              'ownerEmail': email,
              'waiterCode': wc,
              'cashierCode': cc,
              'created': FieldValue.serverTimestamp(),
            });
            await db.collection('codes').doc(wc).set({'rid': rid, 'role': 'waiter'});
            await db.collection('codes').doc(cc).set({'rid': rid, 'role': 'cashier'});
            await db.collection('users').doc(uid).set({'rid': rid, 'role': 'owner', 'name': nm.text.trim()});
          } else {
            final code = cd.text.trim().toUpperCase();
            final c = await db.collection('codes').doc(code).get();
            if (!c.exists) throw 'Code khoto che';
            await db.collection('users').doc(uid).set({
              'rid': c['rid'],
              'role': c['role'],
              'code': code,
              'name': nm.text.trim(),
            });
          }
          try {
            await cred.user!.sendEmailVerification();
          } catch (_) {}
        } catch (e) {
          try {
            await cred.user?.delete();
          } catch (_) {}
          authErr.value = e is String
              ? e
              : (e is FirebaseException && e.code == 'permission-denied'
                  ? (mode == 2 ? 'Code khoto che ke aa restaurant haji approve thai nathi' : 'Permission error. Firebase rules publish karya che?')
                  : 'Setup thayu nahi: $e');
        }
      }
    } on FirebaseAuthException catch (e) {
      authErr.value = msg(e.code);
    } catch (e) {
      authErr.value = 'Error: $e';
    }
    if (mounted) setState(() => busy = false);
  }

  Widget field(TextEditingController c, String hint, IconData icon, {bool pass = false, TextInputType? t, bool caps = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          obscureText: pass,
          keyboardType: t,
          textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.none,
          decoration: InputDecoration(hintText: hint, prefixIcon: Icon(icon, color: kMute, size: 20)),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: kBg,
        body: SafeArea(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
            children: [
              Row(children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFFF7A45), kBrand], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(15)),
                  child: const Icon(Icons.restaurant, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 12),
                const Text('My Order', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              ]),
              const SizedBox(height: 28),
              Text(mode == 0 ? 'Pachha aavo' : mode == 1 ? 'Tamari restaurant banavo' : 'Staff tarike jodayo',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: 6),
              Text(
                  mode == 0
                      ? 'Tamara account thi login karo.'
                      : mode == 1
                          ? 'Owner account ek var banavo, pachi staff ne code aapo.'
                          : 'Owner e aapelo code nakho.',
                  style: const TextStyle(color: kMute, fontSize: 15)),
              const SizedBox(height: 22),
              Seg(
                  items: const ['Login', 'Owner', 'Staff'],
                  index: mode,
                  onChanged: (v) => setState(() {
                        mode = v;
                        authModeKeep = v;
                        authErr.value = null;
                      })),
              const SizedBox(height: 20),
              if (mode == 1) field(rn, 'Restaurant nu naam', Icons.storefront_outlined),
              if (mode == 2) field(cd, 'Staff code', Icons.vpn_key_outlined, caps: true),
              if (mode != 0) field(nm, 'Tamaru naam', Icons.person_outline),
              field(em, 'Email', Icons.mail_outline, t: TextInputType.emailAddress),
              field(pw, 'Password', Icons.lock_outline, pass: true),
              ValueListenableBuilder<String?>(
                valueListenable: authErr,
                builder: (_, e, __) => e == null
                    ? const SizedBox(height: 4)
                    : Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(12)),
                        child: Text(e, style: const TextStyle(color: kBad, fontWeight: FontWeight.w500)),
                      ),
              ),
              FilledButton(
                  onPressed: busy ? null : go,
                  child: busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : Text(mode == 0 ? 'Login' : mode == 1 ? 'Restaurant banavo' : 'Jodayo')),
              if (mode == 0)
                Center(
                    child: TextButton(
                        onPressed: forgot, child: const Text('Password bhuli gaya?', style: TextStyle(color: kMute)))),
            ],
          ),
        ),
      );
}

// ---------------- HOME ----------------
class Home extends StatefulWidget {
  final Ctx c;
  const Home({required this.c, super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int i = 0;
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final items = <List<dynamic>>[
      ['Tables', Icons.table_restaurant_outlined, Icons.table_restaurant, TablesPage(c: c)],
      if (c.role != 'waiter') ['Bills', Icons.receipt_long_outlined, Icons.receipt_long, BillsPage(c: c)],
      if (c.owner) ['Menu', Icons.restaurant_menu, Icons.restaurant_menu, MenuPage(c: c)],
      if (c.owner) ['Report', Icons.bar_chart, Icons.bar_chart, ReportPage(c: c)],
      ['Settings', Icons.settings_outlined, Icons.settings, SettingsPage(c: c)],
    ];
    if (i >= items.length) i = 0;
    return Scaffold(
      body: items[i][3] as Widget,
      bottomNavigationBar: NavigationBar(
        selectedIndex: i,
        onDestinationSelected: (v) => setState(() => i = v),
        destinations: [
          for (final t in items)
            NavigationDestination(
              icon: Icon(t[1] as IconData, color: kMute),
              selectedIcon: Icon(t[2] as IconData, color: kBrand),
              label: t[0] as String,
            ),
        ],
      ),
    );
  }
}

// ---------------- TABLES ----------------
class TablesPage extends StatelessWidget {
  final Ctx c;
  const TablesPage({required this.c, super.key});

  Widget stat(IconData icon, String label, String value, {Color tint = kBrand, Color soft = kBrandSoft}) => Expanded(
        child: Surface(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, color: tint, size: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMute, fontSize: 12)),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ]),
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Json>>(
        stream: c.col('orders').where('status', isEqualTo: 'open').snapshots(),
        builder: (_, s) {
          final by = <int, Json>{};
          for (final d in s.data?.docs ?? <QDoc>[]) {
            by[_n(d.data()['table']).toInt()] = d.data();
          }
          final openTotal = by.values.fold<num>(0, (a, o) => a + orderTotal(o));
          final now = DateTime.now();
          final today = Timestamp.fromDate(DateTime(now.year, now.month, now.day));
          return Pg(c.name, sub: 'Namaste, ${c.uname}', children: [
            Row(children: [
              stat(Icons.event_seat_outlined, 'Chalu tables', '${by.length} / ${c.tables}'),
              const SizedBox(width: 10),
              if (c.role == 'waiter')
                stat(Icons.shopping_bag_outlined, 'Chalu orders', rs(openTotal), tint: kOk, soft: kOkSoft)
              else
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Json>>(
                    stream: c.col('orders').where('paidTs', isGreaterThanOrEqualTo: today).snapshots(),
                    builder: (_, ps) {
                      final sum = (ps.data?.docs ?? <QDoc>[]).fold<num>(0, (a, d) => a + orderTotal(d.data()));
                      return Row(children: [stat(Icons.trending_up, 'Aaj nu vechan', rs(sum), tint: kOk, soft: kOkSoft)]);
                    },
                  ),
                ),
            ]),
            sectionTitle('Tables'),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.95,
              children: [for (var t = 1; t <= c.tables; t++) tile(context, t, by[t])],
            ),
          ]);
        },
      );

  Widget tile(BuildContext context, int t, Json? o) {
    final open = o != null;
    return Surface(
      padding: const EdgeInsets.all(12),
      color: open ? kBrandSoft : Colors.white,
      border: open ? kBrandLine : kLine,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderPage(c: c, table: t))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('T$t', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          Container(width: 9, height: 9, decoration: BoxDecoration(color: open ? kBrand : kOk, shape: BoxShape.circle)),
        ]),
        const Spacer(),
        Text(o != null ? rs(orderTotal(o)) : 'Khali',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: open ? kBrand : kInk)),
        Text(o != null ? '${grouped(o).length} item' : 'Order lo', style: const TextStyle(color: kMute, fontSize: 12)),
      ]),
    );
  }
}

// ---------------- ORDER ----------------
class OrderPage extends StatefulWidget {
  final Ctx c;
  final int table;
  const OrderPage({required this.c, required this.table, super.key});
  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  final qty = <String, int>{};
  String q = '', cat = '';
  bool busy = false;

  Future<void> save(List<QDoc> menu) async {
    final adds = <Json>[];
    for (final m in menu) {
      final n = qty[m.id] ?? 0;
      if (n > 0) {
        final d = m.data();
        adds.add({
          'k': '${DateTime.now().microsecondsSinceEpoch}${m.id}',
          'n': d['name'],
          'p': d['price'],
          'c': d['cost'] ?? 0,
          'q': n,
        });
      }
    }
    if (adds.isEmpty) return;
    setState(() => busy = true);
    final c = widget.c;
    final ref = c.col('orders').doc('open_${widget.table}');
    final ok = await run(
        context,
        () => ref.set({
              'table': widget.table,
              'status': 'open',
              'items': FieldValue.arrayUnion(adds),
              'by': c.uname,
              'updated': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true)),
        queued: 'Order save thayo (offline). Internet aave tyare sync thase');
    if (!mounted) return;
    setState(() => busy = false);
    if (ok) Navigator.pop(context);
  }

  Widget chip(String label, String value) {
    final on = cat == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => cat = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
              color: on ? kInk : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: on ? kInk : kLine)),
          child: Text(label, style: TextStyle(color: on ? Colors.white : kInk, fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Scaffold(
      appBar: AppBar(title: Text('Table ${widget.table}')),
      body: StreamBuilder<DocumentSnapshot<Json>>(
        stream: c.col('orders').doc('open_${widget.table}').snapshots(),
        builder: (_, os) => StreamBuilder<QuerySnapshot<Json>>(
          stream: c.col('menu').snapshots(),
          builder: (_, ms) {
            final cur = (os.data != null && os.data!.exists) ? os.data!.data() : null;
            final List<QDoc> menu = [...(ms.data?.docs ?? <QDoc>[])]
              ..sort((a, b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));
            final order = sectionOrder(c, menu);
            final cats = order.where((x) => menu.any((m) => secOf(m.data()) == x)).toList();
            final shown = menu.where((m) {
              final d = m.data();
              return (cat.isEmpty || secOf(d) == cat) && '${d['name']}'.toLowerCase().contains(q.toLowerCase());
            }).toList();
            var count = 0;
            num total = 0;
            for (final m in menu) {
              final n = qty[m.id] ?? 0;
              count += n;
              total += n * _n(m.data()['price']);
            }
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  onChanged: (v) => setState(() => q = v),
                  decoration: const InputDecoration(
                      hintText: 'Item shodho', prefixIcon: Icon(Icons.search, color: kMute), contentPadding: EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
              if (cats.isNotEmpty)
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [chip('Badhu', ''), for (final k in cats) chip(k, k)],
                  ),
                ),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    if (cur != null)
                      Surface(
                        margin: const EdgeInsets.only(bottom: 4),
                        color: kBrandSoft,
                        border: kBrandLine,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Chalu order', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          const SizedBox(height: 8),
                          for (final g in grouped(cur))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                Expanded(child: Text('${g['n']} × ${g['q']}')),
                                Text(rs(_n(g['p']) * _n(g['q'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          const Divider(color: kBrandLine),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            const Text('Total', style: TextStyle(fontWeight: FontWeight.w800)),
                            Text(rs(orderTotal(cur)), style: const TextStyle(fontWeight: FontWeight.w800, color: kBrand)),
                          ]),
                        ]),
                      ),
                    sectionTitle('Item umero'),
                    if (menu.isEmpty) empty(Icons.restaurant_menu, 'Menu khali che.\nOwner e Menu ma item umeravo.'),
                    if (menu.isNotEmpty && shown.isEmpty) empty(Icons.search, 'Koi item malyo nahi'),
                    for (final sec in order)
                      if (shown.any((m) => secOf(m.data()) == sec)) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 10, 0, 10),
                          child: Row(children: [
                            Text(sec, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                            const SizedBox(width: 8),
                            pill('${shown.where((m) => secOf(m.data()) == sec).length}'),
                          ]),
                        ),
                        for (final m in shown.where((m) => secOf(m.data()) == sec))
                          Surface(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            child: Row(children: [
                              itemImg(m.id, m.data(), size: 56),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('${m['name']}',
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text(rs(_n(m['price'])), style: const TextStyle(color: kMute)),
                                ]),
                              ),
                              Qty(
                                v: qty[m.id] ?? 0,
                                onAdd: () => setState(() => qty[m.id] = (qty[m.id] ?? 0) + 1),
                                onSub: () => setState(() => qty[m.id] = max(0, (qty[m.id] ?? 0) - 1)),
                              ),
                            ]),
                          ),
                      ],
                  ],
                ),
              ),
              Container(
                decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: kLine))),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: SafeArea(
                  top: false,
                  child: Row(children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text('$count item', style: const TextStyle(color: kMute, fontSize: 13)),
                      Text(rs(total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    ]),
                    const SizedBox(width: 20),
                    Expanded(
                      child: FilledButton(
                          onPressed: (busy || count == 0) ? null : () => save(menu),
                          child: busy
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                              : const Text('Order save karo')),
                    ),
                  ]),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

// ---------------- BILLS ----------------
class BillsPage extends StatelessWidget {
  final Ctx c;
  const BillsPage({required this.c, super.key});

  Future<void> removeGroup(BuildContext context, DocumentReference<Json> ref, Json o, Json g) async {
    final all = [for (final e in (o['items'] as List)) Map<String, dynamic>.from(e as Map)];
    final rm = all.where((i) => i['n'] == g['n'] && i['p'] == g['p']).toList();
    if (rm.length == all.length) {
      await run(context, () => ref.delete());
    } else {
      await run(context, () => ref.update({'items': FieldValue.arrayRemove(rm)}));
    }
  }

  Future<String?> pickPay(BuildContext context, num total) => showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (b) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Payment ni rit', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('Total ${rs(total)}', style: const TextStyle(color: kMute)),
              const SizedBox(height: 16),
              for (final m in [
                ['Cash', Icons.payments_outlined],
                ['UPI', Icons.qr_code_2],
                ['Card', Icons.credit_card],
              ])
                Surface(
                  margin: const EdgeInsets.only(bottom: 10),
                  onTap: () => Navigator.pop(b, m[0] as String),
                  child: Row(children: [
                    Icon(m[1] as IconData, color: kBrand),
                    const SizedBox(width: 14),
                    Text(m[0] as String, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ]),
                ),
            ]),
          ),
        ),
      );

  Future<void> pay(BuildContext context, QDoc d) async {
    final o = d.data();
    final mode = await pickPay(context, orderTotal(o));
    if (mode == null || !context.mounted) return;
    final batch = db.batch();
    batch.set(c.col('orders').doc(), {
      'table': o['table'],
      'status': 'paid',
      'items': o['items'],
      'paidTs': FieldValue.serverTimestamp(),
      'pay': mode,
      'total': orderTotal(o),
      'cost': orderCost(o),
      'by': c.uname,
    });
    batch.delete(d.reference);
    final ok = await run(context, () => batch.commit(), queued: 'Bill close thayu (offline). Internet aave tyare sync thase');
    if (ok && context.mounted) {
      final paidO = <String, dynamic>{...o, 'pay': mode};
      toast(context, 'Table ${o['table']} nu bill ${rs(orderTotal(o))} ($mode) close thayu',
          action: 'Bill moklo', onAction: () => showBill(context, c.name, paidO, pay: mode));
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Json>>(
        stream: c.col('orders').where('status', isEqualTo: 'open').snapshots(),
        builder: (_, s) {
          final List<QDoc> docs = [...(s.data?.docs ?? <QDoc>[])]
            ..sort((a, b) => _n(a['table']).compareTo(_n(b['table'])));
          return Pg('Bills', sub: '${docs.length} chalu bill', children: [
            if (docs.isEmpty) empty(Icons.receipt_long_outlined, 'Koi chalu bill nathi.\nWaiter order lese tyare ahiya dekhase.'),
            for (final d in docs)
              Surface(
                margin: const EdgeInsets.only(bottom: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Row(children: [
                      Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: kBrandSoft, borderRadius: BorderRadius.circular(10)),
                          child: Text('T${d['table']}', style: const TextStyle(color: kBrand, fontWeight: FontWeight.w800))),
                      const SizedBox(width: 10),
                      Text('Table ${d['table']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    ]),
                    Text(rs(orderTotal(d.data())), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 10),
                  for (final g in grouped(d.data()))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Expanded(child: Text('${g['n']} × ${g['q']}')),
                        Text(rs(_n(g['p']) * _n(g['q'])), style: const TextStyle(color: kMute)),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () async {
                            if (await confirm(context, '${g['n']} kadhvo?')) {
                              if (context.mounted) await removeGroup(context, d.reference, d.data(), g);
                            }
                          },
                          child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close, size: 18, color: kMute)),
                        ),
                      ]),
                    ),
                  const SizedBox(height: 12),
                  Row(children: [
                    SizedBox(
                      width: 56,
                      height: 52,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            side: const BorderSide(color: kLine),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        onPressed: () => showBill(context, c.name, d.data()),
                        child: const Icon(Icons.share, size: 20, color: kInk),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: kOk),
                          onPressed: () => pay(context, d),
                          child: const Text('Paid, bill close')),
                    ),
                  ]),
                ]),
              ),
          ]);
        },
      );
}

// ---------------- MENU ----------------
class MenuPage extends StatelessWidget {
  final Ctx c;
  const MenuPage({required this.c, super.key});

  DocumentReference<Json> get rest => db.collection('restaurants').doc(c.rid);

  Future<void> addSection(BuildContext context) async {
    final v = await askForm(context, 'Navo section', ['Section nu naam (jem ke Chinese)']);
    if (v == null || v[0].isEmpty || !context.mounted) return;
    final name = v[0];
    if (c.sections.any((s) => s.toLowerCase() == name.toLowerCase())) {
      toast(context, 'Aa section pehla thi che', err: true);
      return;
    }
    await run(context, () => rest.update({'sections': FieldValue.arrayUnion([name])}));
  }

  Future<void> addSuggested(BuildContext context) async {
    const names = ['Starter', 'Punjabi', 'South Indian', 'Chinese', 'Dessert', 'Drinks'];
    await run(context, () => rest.update({'sections': FieldValue.arrayUnion(names)}));
  }

  Future<void> renameSection(BuildContext context, String old) async {
    final v = await askForm(context, 'Section badlo', ['Naam'], init: [old]);
    if (v == null || v[0].isEmpty || v[0] == old || !context.mounted) return;
    final name = v[0];
    if (c.sections.any((s) => s != old && s.toLowerCase() == name.toLowerCase())) {
      toast(context, 'Aa naam nu section pehla thi che', err: true);
      return;
    }
    await run(context, () async {
      final qs = await c.col('menu').where('cat', isEqualTo: old).get();
      final b = db.batch();
      for (final d in qs.docs) {
        b.update(d.reference, {'cat': name});
      }
      b.update(rest, {
        'sections': [for (final s in c.sections) s == old ? name : s]
      });
      await b.commit();
    });
  }

  Future<void> deleteSection(BuildContext context, String name) async {
    final yes = await confirm(context, '"$name" section delete karvu?\nItems delete nahi thay, "$kOther" ma jase.', yes: 'Delete');
    if (!yes || !context.mounted) return;
    await run(context, () async {
      final qs = await c.col('menu').where('cat', isEqualTo: name).get();
      final b = db.batch();
      for (final d in qs.docs) {
        b.update(d.reference, {'cat': ''});
      }
      b.update(rest, {
        'sections': [for (final s in c.sections) if (s != name) s]
      });
      await b.commit();
    });
  }

  Future<void> editItem(BuildContext context, QDoc? d) async {
    final m = d?.data();
    final nm = TextEditingController(text: '${m?['name'] ?? ''}');
    final pr = TextEditingController(text: m == null ? '' : '${m['price']}');
    final co = TextEditingController(text: m == null ? '' : '${m['cost'] ?? 0}');
    var sec = '${m?['cat'] ?? ''}';
    var img = '${m?['img'] ?? ''}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dc) => StatefulBuilder(
        builder: (sc, setS) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(d == null ? 'Navo item' : 'Item badlo', style: const TextStyle(fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: itemImg(d?.id ?? 'new', {'img': img}, size: 88)),
              const SizedBox(height: 10),
              Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                for (final src in [ImageSource.gallery, ImageSource.camera])
                  GestureDetector(
                    onTap: () async {
                      try {
                        final x = await ImagePicker().pickImage(source: src, maxWidth: 360, maxHeight: 360, imageQuality: 65);
                        if (x == null) return;
                        final bytes = await x.readAsBytes();
                        setS(() => img = base64Encode(bytes));
                      } catch (e) {
                        if (context.mounted) toast(context, 'Photo levama error: $e', err: true);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: kBrandSoft, borderRadius: BorderRadius.circular(20)),
                      child: Text(src == ImageSource.gallery ? 'Gallery' : 'Camera',
                          style: const TextStyle(color: kBrand, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ),
                if (img.isNotEmpty)
                  GestureDetector(
                    onTap: () => setS(() => img = ''),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(20)),
                      child: const Text('Kadho', style: TextStyle(color: kBad, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ),
              ]),
              const SizedBox(height: 14),
              TextField(controller: nm, decoration: const InputDecoration(labelText: 'Item nu naam')),
              const SizedBox(height: 10),
              TextField(
                  controller: pr,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Price (₹)')),
              const SizedBox(height: 10),
              TextField(
                  controller: co,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Cost / kharch (₹)')),
              const SizedBox(height: 16),
              const Text('Section', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (c.sections.isEmpty)
                const Text('Pehla Menu ma upar thi section umero (optional).', style: TextStyle(color: kMute, fontSize: 13)),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in c.sections)
                  GestureDetector(
                    onTap: () => setS(() => sec = sec == s ? '' : s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                          color: sec == s ? kBrand : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: sec == s ? kBrand : kLine)),
                      child: Text(s,
                          style: TextStyle(color: sec == s ? Colors.white : kInk, fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('Cancel', style: TextStyle(color: kMute))),
            FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
                onPressed: () => Navigator.pop(dc, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final name = nm.text.trim();
    final price = double.tryParse(pr.text.trim()) ?? 0;
    if (name.isEmpty || price <= 0) {
      toast(context, 'Item nu naam ane price nakho', err: true);
      return;
    }
    if (img.length > 600000) {
      toast(context, 'Photo ghano moto che, bijo photo lo', err: true);
      return;
    }
    final data = {'name': name, 'cat': sec, 'price': price, 'cost': double.tryParse(co.text.trim()) ?? 0, 'img': img};
    await run(context, () => d == null ? c.col('menu').add(data) : d.reference.update(data));
  }

  Widget secChip(BuildContext context, String s) => Container(
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: kLine)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
              onTap: () => renameSection(context, s),
              child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(s, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)))),
          GestureDetector(
            onTap: () => deleteSection(context, s),
            child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.close, size: 16, color: kMute)),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Json>>(
        stream: c.col('menu').snapshots(),
        builder: (_, s) {
          final List<QDoc> docs = [...(s.data?.docs ?? <QDoc>[])]
            ..sort((a, b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));
          final order = sectionOrder(c, docs);
          return Pg('Menu', sub: '${docs.length} item  ·  ${c.sections.length} section', children: [
            Surface(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Sections', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 2),
                const Text('Jem ke Chinese, South Indian, Starter. Naam par dabavo to badlay, ✕ thi delete.',
                    style: TextStyle(color: kMute, fontSize: 13)),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final sec in c.sections) secChip(context, sec),
                  GestureDetector(
                    onTap: () => addSection(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(color: kBrandSoft, borderRadius: BorderRadius.circular(20)),
                      child: const Text('+ Navu section', style: TextStyle(color: kBrand, fontWeight: FontWeight.w700, fontSize: 13.5)),
                    ),
                  ),
                ]),
                if (c.sections.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextButton(
                        onPressed: () => addSuggested(context),
                        child: const Text('Sujhaaveli sections umero (Starter, Punjabi, South Indian, Chinese, Dessert, Drinks)')),
                  ),
              ]),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: () => editItem(context, null), icon: const Icon(Icons.add), label: const Text('Navo item')),
            const SizedBox(height: 4),
            if (docs.isEmpty) empty(Icons.restaurant_menu, 'Menu khali che.\nPehlo item umero.'),
            for (final sec in order)
              ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 18, 0, 10),
                  child: Row(children: [
                    Text(sec, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 8),
                    pill('${docs.where((m) => secOf(m.data()) == sec).length}'),
                  ]),
                ),
                for (final d in docs.where((m) => secOf(m.data()) == sec))
                  Surface(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                    onTap: () => editItem(context, d),
                    child: Row(children: [
                      itemImg(d.id, d.data()),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${d['name']}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text('Price ${rs(_n(d['price']))}   ·   Cost ${rs(_n(d.data()['cost'] ?? 0))}',
                              style: const TextStyle(color: kMute, fontSize: 13)),
                        ]),
                      ),
                      IconButton(
                          onPressed: () async {
                            if (await confirm(context, '${d['name']} delete karvo?', yes: 'Delete')) {
                              if (context.mounted) await run(context, () => d.reference.delete());
                            }
                          },
                          icon: const Icon(Icons.delete_outline, color: kBad)),
                    ]),
                  ),
              ],
          ]);
        },
      );
}

// ---------------- REPORT ----------------
class ReportPage extends StatefulWidget {
  final Ctx c;
  const ReportPage({required this.c, super.key});
  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  int r = 0;
  DateTime from() {
    final n = DateTime.now();
    final d = DateTime(n.year, n.month, n.day);
    return [d, d.subtract(const Duration(days: 6)), DateTime(n.year, n.month, 1), DateTime(2000)][r];
  }

  Widget mini(String l, String v) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
          const SizedBox(height: 2),
          Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final f = Timestamp.fromDate(from());
    return StreamBuilder<QuerySnapshot<Json>>(
      stream: c.col('orders').where('paidTs', isGreaterThanOrEqualTo: f).snapshots(),
      builder: (_, os) => StreamBuilder<QuerySnapshot<Json>>(
        stream: c.col('expenses').where('ts', isGreaterThanOrEqualTo: f).snapshots(),
        builder: (_, es) {
          final orders = os.data?.docs ?? <QDoc>[];
          final List<QDoc> exps = [...(es.data?.docs ?? <QDoc>[])]
            ..sort((a, b) => ((b['ts'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
                .compareTo((a['ts'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
          final sales = orders.fold<num>(0, (a, d) => a + orderTotal(d.data()));
          final cost = orders.fold<num>(0, (a, d) => a + orderCost(d.data()));
          final ex = exps.fold<num>(0, (a, d) => a + _n(d['amount']));
          final profit = sales - cost - ex;
          final pays = <String, num>{'Cash': 0, 'UPI': 0, 'Card': 0};
          final top = <String, List<num>>{};
          for (final d in orders) {
            final o = d.data();
            final k = '${o['pay'] ?? 'Cash'}';
            pays[k] = (pays[k] ?? 0) + orderTotal(o);
            for (final g in grouped(o)) {
              final t = top.putIfAbsent('${g['n']}', () => [0, 0]);
              t[0] += _n(g['q']);
              t[1] += _n(g['p']) * _n(g['q']);
            }
          }
          final topList = top.entries.toList()..sort((a, b) => b.value[0].compareTo(a.value[0]));
          return Pg('Report', sub: 'Vechan, kharch ane profit', children: [
            Seg(items: const ['Aaj', '7 divas', 'Mahino', 'Badhu'], index: r, onChanged: (v) => setState(() => r = v)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: kInk, borderRadius: BorderRadius.circular(20)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Net profit', style: TextStyle(color: Color(0xFF9CA3AF))),
                  pill(sales > 0 ? '${(profit / sales * 100).toStringAsFixed(0)}% margin' : '${orders.length} bill',
                      bg: profit >= 0 ? const Color(0xFF14532D) : const Color(0xFF7F1D1D),
                      fg: profit >= 0 ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5)),
                ]),
                const SizedBox(height: 6),
                Text(rs(profit), style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800, letterSpacing: -1)),
                const SizedBox(height: 16),
                Row(children: [mini('Vechan', rs(sales)), mini('Item cost', rs(cost)), mini('Kharch', rs(ex))]),
              ]),
            ),
            sectionTitle('Payment pramane'),
            Row(children: [
              for (final k in ['Cash', 'UPI', 'Card'])
                Expanded(
                  child: Surface(
                    margin: EdgeInsets.only(right: k == 'Card' ? 0 : 10),
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(k, style: const TextStyle(color: kMute, fontSize: 12)),
                      const SizedBox(height: 2),
                      Text(rs(pays[k] ?? 0), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),
            ]),
            sectionTitle('Sauthi vadhu vechata item'),
            if (topList.isEmpty) Surface(child: const Text('Haji koi vechan nathi', style: TextStyle(color: kMute))),
            if (topList.isNotEmpty)
              Surface(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(children: [
                  for (var i = 0; i < min(5, topList.length); i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: kBrandSoft, borderRadius: BorderRadius.circular(8)),
                            child: Text('${i + 1}', style: const TextStyle(color: kBrand, fontWeight: FontWeight.w800, fontSize: 13))),
                        const SizedBox(width: 12),
                        Expanded(child: Text(topList[i].key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                        Text('${topList[i].value[0].toInt()} nang', style: const TextStyle(color: kMute, fontSize: 13)),
                        const SizedBox(width: 12),
                        Text(rs(topList[i].value[1]), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ]),
                    ),
                ]),
              ),
            sectionTitle('Kharch'),
            FilledButton.icon(
                onPressed: () async {
                  final v = await askForm(context, 'Kharch umero', ['Vigat (bhadu, pagar, gas...)', 'Rakam (₹)'], numeric: {1});
                  if (v == null || v[0].isEmpty || !context.mounted) return;
                  final a = double.tryParse(v[1]) ?? 0;
                  if (a <= 0) {
                    toast(context, 'Rakam nakho', err: true);
                    return;
                  }
                  await run(context, () => c.col('expenses').add({'title': v[0], 'amount': a, 'ts': FieldValue.serverTimestamp()}));
                },
                icon: const Icon(Icons.add),
                label: const Text('Kharch umero')),
            const SizedBox(height: 12),
            if (exps.isEmpty) Surface(child: const Text('Aa samay ma koi kharch nathi', style: TextStyle(color: kMute))),
            for (final d in exps)
              Surface(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                child: Row(children: [
                  Expanded(child: Text('${d['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                  Text(rs(_n(d['amount'])), style: const TextStyle(fontWeight: FontWeight.w800)),
                  IconButton(
                      onPressed: () async {
                        if (await confirm(context, 'Aa kharch delete karvo?', yes: 'Delete')) {
                          if (context.mounted) await run(context, () => d.reference.delete());
                        }
                      },
                      icon: const Icon(Icons.close, size: 18, color: kMute)),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}

// ---------------- SETTINGS ----------------
class SettingsPage extends StatelessWidget {
  final Ctx c;
  const SettingsPage({required this.c, super.key});

  Widget codeRow(BuildContext context, String label, String code) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(10)),
            child: Text(code, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 3)),
          ),
          IconButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                toast(context, 'Code copy thayo');
              },
              icon: const Icon(Icons.content_copy, size: 18, color: kMute)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final ini = c.uname.trim().isEmpty ? '?' : c.uname.trim()[0].toUpperCase();
    return Pg('Settings', children: [
      Surface(
        child: Row(children: [
          Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: kBrandSoft, shape: BoxShape.circle),
              child: Text(ini, style: const TextStyle(color: kBrand, fontSize: 22, fontWeight: FontWeight.w800))),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.uname, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(c.name, style: const TextStyle(color: kMute)),
              const SizedBox(height: 6),
              pill(c.roleLabel),
            ]),
          ),
        ]),
      ),
      if (c.owner) ...[
        sectionTitle('Staff'),
        Surface(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Staff mate code', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            const Text('Staff e app ma "Staff" tab ma aa code thi register karvu.', style: TextStyle(color: kMute, fontSize: 13)),
            const SizedBox(height: 8),
            codeRow(context, 'Order lenar', '${c.r['waiterCode']}'),
            codeRow(context, 'Bill counter', '${c.r['cashierCode']}'),
          ]),
        ),
        sectionTitle('Restaurant'),
        Surface(
          onTap: () async {
            final v = await askForm(context, 'Tables ni sankhya', ['Sankhya (1 thi 100)'], init: ['${c.tables}'], numeric: {0});
            final n = int.tryParse(v?[0] ?? '');
            if (n == null || n < 1 || n > 100 || !context.mounted) return;
            await run(context, () => db.collection('restaurants').doc(c.rid).update({'tables': n}));
          },
          child: Row(children: [
            const Icon(Icons.table_restaurant_outlined, color: kBrand),
            const SizedBox(width: 12),
            const Expanded(child: Text('Tables ni sankhya', style: TextStyle(fontWeight: FontWeight.w600))),
            Text('${c.tables}', style: const TextStyle(fontWeight: FontWeight.w800)),
            const Icon(Icons.chevron_right, color: kMute),
          ]),
        ),
      ],
      const SizedBox(height: 18),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            foregroundColor: kBad,
            side: const BorderSide(color: kLine),
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        onPressed: () async {
          if (await confirm(context, 'Logout karvu?', yes: 'Logout')) await FirebaseAuth.instance.signOut();
        },
        icon: const Icon(Icons.logout, size: 20),
        label: const Text('Logout', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      const SizedBox(height: 16),
      const Center(child: Text('My Order  ·  v1.1', style: TextStyle(color: kMute, fontSize: 12))),
    ]);
  }
}
