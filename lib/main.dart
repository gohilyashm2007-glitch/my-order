import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final db = FirebaseFirestore.instance;
const kBg = Color(0xFFF2F2F7), kBlue = Color(0xFF007AFF), kGreen = Color(0xFF34C759);
const kRed = Color(0xFFFF3B30), kGray = Color(0xFF8E8E93), kBlueSoft = Color(0xFFE5F1FF);

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

num _n(dynamic v) => v is num ? v : 0;
String rs(num n) => '₹${n == n.roundToDouble() ? n.toInt() : n.toStringAsFixed(2)}';
num orderTotal(Map<String, dynamic> o) =>
    ((o['items'] ?? []) as List).fold<num>(0, (a, i) => a + _n(i['p']) * _n(i['q']));
num orderCost(Map<String, dynamic> o) =>
    ((o['items'] ?? []) as List).fold<num>(0, (a, i) => a + _n(i['c']) * _n(i['q']));
String genCode() {
  const ch = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random.secure();
  return List.generate(6, (_) => ch[r.nextInt(ch.length)]).join();
}

Widget card(Widget child,
        {EdgeInsets pad = const EdgeInsets.all(16), VoidCallback? onTap, Color color = Colors.white}) =>
    Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(padding: pad, child: child)),
      ),
    );

Widget box(List<Widget> ch) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    sliver: SliverList(delegate: SliverChildListDelegate(ch)));

class Pg extends StatelessWidget {
  final String title;
  final List<Widget> slivers;
  final List<Widget> actions;
  const Pg(this.title, this.slivers, {this.actions = const [], super.key});
  @override
  Widget build(BuildContext context) => CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar.large(
              title: Text(title),
              actions: actions,
              backgroundColor: kBg,
              surfaceTintColor: Colors.transparent),
          ...slivers,
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      );
}

Future<List<String>?> askForm(BuildContext context, String title, List<String> labels,
    {List<String>? init, Set<int> numeric = const {}}) {
  final cs = [for (var i = 0; i < labels.length; i++) TextEditingController(text: init?[i] ?? '')];
  return showDialog<List<String>>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
                controller: cs[i],
                keyboardType: numeric.contains(i) ? TextInputType.number : TextInputType.text,
                decoration: InputDecoration(labelText: labels[i])),
          ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(90, 44)),
            onPressed: () => Navigator.pop(d, cs.map((e) => e.text.trim()).toList()),
            child: const Text('Save')),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String msg) async =>
    (await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(title: Text(msg), actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Na')),
              FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(90, 44)),
                  onPressed: () => Navigator.pop(d, true),
                  child: const Text('Ha')),
            ]))) ??
    false;

class Ctx {
  final String rid, role, uname;
  final Map<String, dynamic> r;
  Ctx(this.rid, this.role, this.uname, this.r);
  CollectionReference<Map<String, dynamic>> col(String n) => db.collection('restaurants').doc(rid).collection(n);
  int get tables => _n(r['tables'] ?? 10).toInt();
  String get name => (r['name'] ?? '') as String;
  bool get owner => role == 'owner';
}

class MyOrderApp extends StatelessWidget {
  const MyOrderApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'My Order',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: kBlue).copyWith(primary: kBlue),
          scaffoldBackgroundColor: kBg,
          appBarTheme: const AppBarTheme(
              backgroundColor: kBg, elevation: 0, scrolledUnderElevation: 0, centerTitle: false),
          inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
          filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
          navigationBarTheme: const NavigationBarThemeData(
              backgroundColor: Colors.white, indicatorColor: kBlueSoft),
        ),
        home: const Root(),
      );
}

class Splash extends StatelessWidget {
  final bool logout;
  const Splash({this.logout = false, super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
          body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          if (logout)
            TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Logout')),
        ]),
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
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: db.collection('users').doc(u.uid).snapshots(),
            builder: (_, us) {
              if (!us.hasData || !us.data!.exists) return const Splash(logout: true);
              final ud = us.data!.data()!;
              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: db.collection('restaurants').doc(ud['rid'] as String).snapshots(),
                builder: (_, rs) {
                  if (!rs.hasData || !rs.data!.exists) return const Splash(logout: true);
                  return Home(
                      c: Ctx(ud['rid'] as String, ud['role'] as String, (ud['name'] ?? '') as String,
                          rs.data!.data()!));
                },
              );
            },
          );
        },
      );
}

// ---------------- AUTH ----------------
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  int mode = 0;
  final em = TextEditingController(), pw = TextEditingController();
  final nm = TextEditingController(), rn = TextEditingController(), cd = TextEditingController();
  String? err;
  bool busy = false;

  String msg(String code) {
    switch (code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Email athva password khotu che';
      case 'email-already-in-use':
        return 'Aa email thi account pehla thi che';
      case 'weak-password':
        return 'Password ochha ma ochha 6 akshar no rakho';
      case 'invalid-email':
        return 'Email barobar nathi';
      case 'network-request-failed':
        return 'Internet check karo';
      default:
        return 'Error: $code';
    }
  }

  Future<void> go() async {
    final email = em.text.trim(), pass = pw.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => err = 'Email ane password nakho');
      return;
    }
    if (mode == 1 && (rn.text.trim().isEmpty || nm.text.trim().isEmpty)) {
      setState(() => err = 'Restaurant nu naam ane tamaru naam nakho');
      return;
    }
    if (mode == 2 && (cd.text.trim().isEmpty || nm.text.trim().isEmpty)) {
      setState(() => err = 'Code ane tamaru naam nakho');
      return;
    }
    setState(() {
      err = null;
      busy = true;
    });
    try {
      final auth = FirebaseAuth.instance;
      if (mode == 0) {
        await auth.signInWithEmailAndPassword(email: email, password: pass);
      } else if (mode == 1) {
        final cred = await auth.createUserWithEmailAndPassword(email: email, password: pass);
        final uid = cred.user!.uid;
        final rid = db.collection('restaurants').doc().id;
        final wc = genCode(), cc = genCode();
        await db.collection('restaurants').doc(rid).set({
          'name': rn.text.trim(),
          'ownerUid': uid,
          'tables': 10,
          'waiterCode': wc,
          'cashierCode': cc,
          'created': FieldValue.serverTimestamp(),
        });
        await db.collection('codes').doc(wc).set({'rid': rid, 'role': 'waiter'});
        await db.collection('codes').doc(cc).set({'rid': rid, 'role': 'cashier'});
        await db.collection('users').doc(uid).set({'rid': rid, 'role': 'owner', 'name': nm.text.trim()});
      } else {
        final code = cd.text.trim().toUpperCase();
        final cred = await auth.createUserWithEmailAndPassword(email: email, password: pass);
        final c = await db.collection('codes').doc(code).get();
        if (!c.exists) {
          await cred.user!.delete();
          setState(() => err = 'Code khoto che');
        } else {
          await db.collection('users').doc(cred.user!.uid).set({
            'rid': c['rid'],
            'role': c['role'],
            'code': code,
            'name': nm.text.trim(),
          });
        }
      }
    } on FirebaseAuthException catch (e) {
      err = msg(e.code);
    } catch (e) {
      err = 'Error: $e';
    }
    if (mounted) setState(() => busy = false);
  }

  Widget f(TextEditingController c, String l, {bool pass = false, TextInputType? t}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
            controller: c,
            obscureText: pass,
            keyboardType: t,
            textCapitalization: l == 'Code' ? TextCapitalization.characters : TextCapitalization.none,
            decoration: InputDecoration(labelText: l)),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 32),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: kBlue, borderRadius: BorderRadius.circular(18)),
                child: const Icon(Icons.restaurant, color: Colors.white, size: 38),
              ),
              const SizedBox(height: 20),
              const Text('My Order', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
              const Text('Restaurant ni badhi vyavastha, ek j app ma.', style: TextStyle(color: kGray, fontSize: 16)),
              const SizedBox(height: 24),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 0, label: Text('Login')),
                  ButtonSegment(value: 1, label: Text('Owner')),
                  ButtonSegment(value: 2, label: Text('Staff')),
                ],
                selected: {mode},
                onSelectionChanged: (s) => setState(() {
                  mode = s.first;
                  err = null;
                }),
              ),
              const SizedBox(height: 20),
              if (mode == 1) f(rn, 'Restaurant nu naam'),
              if (mode == 2) f(cd, 'Code'),
              if (mode != 0) f(nm, 'Tamaru naam'),
              f(em, 'Email', t: TextInputType.emailAddress),
              f(pw, 'Password', pass: true),
              if (err != null)
                Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(err!, style: const TextStyle(color: kRed))),
              FilledButton(
                  onPressed: busy ? null : go,
                  child: busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(mode == 0 ? 'Login' : mode == 1 ? 'Restaurant banavo' : 'Staff tarike jodayo')),
              const SizedBox(height: 8),
              if (mode == 1)
                const Text('Owner tarike register karo. Pachi Settings ma staff mate code male.',
                    style: TextStyle(color: kGray)),
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
      ['Tables', Icons.table_restaurant_outlined, TablesPage(c: c)],
      if (c.role != 'waiter') ['Bills', Icons.receipt_long_outlined, BillsPage(c: c)],
      if (c.owner) ['Menu', Icons.restaurant_menu, MenuPage(c: c)],
      if (c.owner) ['Report', Icons.bar_chart, ReportPage(c: c)],
      ['Settings', Icons.settings_outlined, SettingsPage(c: c)],
    ];
    if (i >= items.length) i = 0;
    return Scaffold(
      body: items[i][2] as Widget,
      bottomNavigationBar: NavigationBar(
        selectedIndex: i,
        onDestinationSelected: (v) => setState(() => i = v),
        destinations: [
          for (final t in items) NavigationDestination(icon: Icon(t[1] as IconData), label: t[0] as String)
        ],
      ),
    );
  }
}

// ---------------- TABLES ----------------
class TablesPage extends StatelessWidget {
  final Ctx c;
  const TablesPage({required this.c, super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: c.col('orders').where('status', isEqualTo: 'open').snapshots(),
        builder: (_, s) {
          final by = <int, Map<String, dynamic>>{};
          for (final d in s.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
            by[_n(d.data()['table']).toInt()] = d.data();
          }
          return Pg(c.name, [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, mainAxisSpacing: 12, crossAxisSpacing: 12),
                delegate: SliverChildBuilderDelegate((_, i) {
                  final t = i + 1;
                  final o = by[t];
                  final open = o != null;
                  return GestureDetector(
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => OrderPage(c: c, table: t))),
                    child: Container(
                      decoration: BoxDecoration(
                          color: open ? kBlue : Colors.white, borderRadius: BorderRadius.circular(20)),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('$t',
                            style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                color: open ? Colors.white : Colors.black)),
                        Text(open ? rs(orderTotal(o)) : 'Khali',
                            style: TextStyle(color: open ? Colors.white70 : kGray)),
                      ]),
                    ),
                  );
                }, childCount: c.tables),
              ),
            ),
          ]);
        },
      );
}

class OrderPage extends StatefulWidget {
  final Ctx c;
  final int table;
  const OrderPage({required this.c, required this.table, super.key});
  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  final qty = <String, int>{};
  bool busy = false;

  Future<void> save(List<QueryDocumentSnapshot<Map<String, dynamic>>> menu,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> open) async {
    final adds = <Map<String, dynamic>>[];
    for (final m in menu) {
      final q = qty[m.id] ?? 0;
      if (q > 0) {
        adds.add({'n': m['name'], 'p': m['price'], 'c': m.data()['cost'] ?? 0, 'q': q});
      }
    }
    if (adds.isEmpty) return;
    setState(() => busy = true);
    final c = widget.c;
    if (open.isEmpty) {
      await c.col('orders').add({
        'table': widget.table,
        'status': 'open',
        'items': adds,
        'ts': FieldValue.serverTimestamp(),
        'by': c.uname,
      });
    } else {
      final ref = open.first.reference;
      await db.runTransaction((t) async {
        final snap = await t.get(ref);
        final items = [for (final e in (snap.data()!['items'] as List)) Map<String, dynamic>.from(e as Map)];
        for (final a in adds) {
          final ex = items.where((e) => e['n'] == a['n']).toList();
          if (ex.isEmpty) {
            items.add(a);
          } else {
            ex.first['q'] = _n(ex.first['q']) + a['q'];
          }
        }
        t.update(ref, {'items': items});
      });
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Scaffold(
      appBar: AppBar(title: Text('Table ${widget.table}')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: c.col('orders')
            .where('table', isEqualTo: widget.table)
            .where('status', isEqualTo: 'open')
            .snapshots(),
        builder: (_, os) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: c.col('menu').snapshots(),
          builder: (_, ms) {
            final open = os.data?.docs ?? [];
            final List<QueryDocumentSnapshot<Map<String, dynamic>>> menu = [...(ms.data?.docs ?? [])]
              ..sort((a, b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));
            final cur = open.isEmpty ? null : open.first.data();
            return Column(children: [
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (cur != null)
                      card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Chalu order', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                        const SizedBox(height: 8),
                        for (final i in cur['items'] as List)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Text('${i['n']} × ${i['q']}'),
                              Text(rs(_n(i['p']) * _n(i['q']))),
                            ]),
                          ),
                        const Divider(),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          const Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
                          Text(rs(orderTotal(cur)), style: const TextStyle(fontWeight: FontWeight.w700)),
                        ]),
                      ])),
                    const Padding(
                        padding: EdgeInsets.fromLTRB(4, 8, 0, 8),
                        child: Text('Item umero', style: TextStyle(color: kGray, fontWeight: FontWeight.w600))),
                    if (menu.isEmpty) const Text('Menu khali che. Owner e Menu ma item umeravo.'),
                    for (final m in menu)
                      card(
                          Row(children: [
                            Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${m['name']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                              Text(rs(_n(m['price'])), style: const TextStyle(color: kGray)),
                            ])),
                            IconButton(
                                onPressed: () => setState(() => qty[m.id] = max(0, (qty[m.id] ?? 0) - 1)),
                                icon: const Icon(Icons.remove_circle_outline)),
                            SizedBox(
                                width: 24,
                                child: Text('${qty[m.id] ?? 0}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                            IconButton(
                                onPressed: () => setState(() => qty[m.id] = (qty[m.id] ?? 0) + 1),
                                icon: const Icon(Icons.add_circle, color: kBlue)),
                          ]),
                          pad: const EdgeInsets.fromLTRB(16, 8, 8, 8)),
                  ],
                ),
              ),
              SafeArea(
                  child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: FilledButton(
                    onPressed: busy ? null : () => save(menu, open), child: const Text('Order save karo')),
              )),
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

  Future<void> removeItem(DocumentReference<Map<String, dynamic>> ref, int idx) async {
    await db.runTransaction((t) async {
      final snap = await t.get(ref);
      final items = [for (final e in (snap.data()!['items'] as List)) e];
      items.removeAt(idx);
      if (items.isEmpty) {
        t.delete(ref);
      } else {
        t.update(ref, {'items': items});
      }
    });
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: c.col('orders').where('status', isEqualTo: 'open').snapshots(),
        builder: (_, s) {
          final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = [...(s.data?.docs ?? [])]
            ..sort((a, b) => _n(a['table']).compareTo(_n(b['table'])));
          return Pg('Bills', [
            box([
              if (docs.isEmpty)
                const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(child: Text('Koi chalu order nathi', style: TextStyle(color: kGray)))),
              for (final d in docs)
                card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Table ${d['table']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    Text(rs(orderTotal(d.data())), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 6),
                  for (var k = 0; k < (d['items'] as List).length; k++)
                    Row(children: [
                      Expanded(child: Text('${d['items'][k]['n']} × ${d['items'][k]['q']}')),
                      Text(rs(_n(d['items'][k]['p']) * _n(d['items'][k]['q'])),
                          style: const TextStyle(color: kGray)),
                      IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () async {
                            if (await confirm(context, 'Aa item kadhvo?')) {
                              await removeItem(d.reference, k);
                            }
                          },
                          icon: const Icon(Icons.close, size: 18, color: kGray)),
                    ]),
                  const SizedBox(height: 10),
                  FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: kGreen),
                      onPressed: () async {
                        if (await confirm(context, 'Bill paid karvu?')) {
                          await d.reference.update({'status': 'paid', 'paidTs': FieldValue.serverTimestamp()});
                        }
                      },
                      child: const Text('Paid, bill close')),
                ])),
            ]),
          ]);
        },
      );
}

// ---------------- MENU ----------------
class MenuPage extends StatelessWidget {
  final Ctx c;
  const MenuPage({required this.c, super.key});

  Future<void> edit(BuildContext context, DocumentSnapshot<Map<String, dynamic>>? d) async {
    final m = d?.data();
    final r = await askForm(context, d == null ? 'Navo item' : 'Item badlo',
        ['Naam', 'Price (₹)', 'Cost / kharch (₹)'],
        init: m == null ? null : ['${m['name']}', '${m['price']}', '${m['cost'] ?? 0}'], numeric: {1, 2});
    if (r == null || r[0].isEmpty) return;
    final data = {
      'name': r[0],
      'price': double.tryParse(r[1]) ?? 0,
      'cost': double.tryParse(r[2]) ?? 0,
    };
    if (d == null) {
      await c.col('menu').add(data);
    } else {
      await d.reference.update(data);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: c.col('menu').snapshots(),
        builder: (_, s) {
          final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = [...(s.data?.docs ?? [])]
            ..sort((a, b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));
          return Pg('Menu', [
            box([
              FilledButton.icon(
                  onPressed: () => edit(context, null), icon: const Icon(Icons.add), label: const Text('Navo item')),
              const SizedBox(height: 16),
              for (final d in docs)
                card(
                    Row(children: [
                      Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${d['name']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                        Text('Price ${rs(_n(d['price']))}  ·  Cost ${rs(_n(d.data()['cost'] ?? 0))}',
                            style: const TextStyle(color: kGray)),
                      ])),
                      IconButton(
                          onPressed: () async {
                            if (await confirm(context, 'Item delete karvo?')) await d.reference.delete();
                          },
                          icon: const Icon(Icons.delete_outline, color: kRed)),
                    ]),
                    onTap: () => edit(context, d)),
            ]),
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

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final f = Timestamp.fromDate(from());
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: c.col('orders').where('paidTs', isGreaterThanOrEqualTo: f).snapshots(),
      builder: (_, os) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: c.col('expenses').where('ts', isGreaterThanOrEqualTo: f).snapshots(),
        builder: (_, es) {
          final orders = os.data?.docs ?? [];
          final List<QueryDocumentSnapshot<Map<String, dynamic>>> exps = [...(es.data?.docs ?? [])]
            ..sort((a, b) => ((b['ts'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
                .compareTo((a['ts'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
          final sales = orders.fold<num>(0, (a, d) => a + orderTotal(d.data()));
          final cost = orders.fold<num>(0, (a, d) => a + orderCost(d.data()));
          final ex = exps.fold<num>(0, (a, d) => a + _n(d['amount']));
          final profit = sales - cost - ex;
          Widget line(String l, num v) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(l, style: const TextStyle(fontSize: 16)),
                Text(rs(v), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ]));
          return Pg('Report', [
            box([
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 0, label: Text('Aaj')),
                  ButtonSegment(value: 1, label: Text('7 divas')),
                  ButtonSegment(value: 2, label: Text('Mahino')),
                  ButtonSegment(value: 3, label: Text('Badhu')),
                ],
                selected: {r},
                onSelectionChanged: (s) => setState(() => r = s.first),
              ),
              const SizedBox(height: 16),
              card(Column(children: [
                const Text('Net Profit', style: TextStyle(color: kGray)),
                Text(rs(profit),
                    style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: profit >= 0 ? kGreen : kRed)),
                Text('${orders.length} bill', style: const TextStyle(color: kGray)),
              ]), pad: const EdgeInsets.all(20)),
              card(Column(children: [
                line('Kul vechan', sales),
                line('Item cost', cost),
                line('Biji kharch', ex),
              ])),
              FilledButton.icon(
                  onPressed: () async {
                    final v = await askForm(context, 'Kharch umero', ['Vigat (bhadu, pagar...)', 'Rakam (₹)'],
                        numeric: {1});
                    if (v == null || v[0].isEmpty) return;
                    await c.col('expenses').add({
                      'title': v[0],
                      'amount': double.tryParse(v[1]) ?? 0,
                      'ts': FieldValue.serverTimestamp(),
                    });
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Kharch umero')),
              const SizedBox(height: 16),
              for (final d in exps)
                card(
                    Row(children: [
                      Expanded(child: Text('${d['title']}', style: const TextStyle(fontSize: 16))),
                      Text(rs(_n(d['amount'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                      IconButton(
                          onPressed: () => d.reference.delete(),
                          icon: const Icon(Icons.close, size: 18, color: kGray)),
                    ]),
                    pad: const EdgeInsets.fromLTRB(16, 4, 4, 4)),
            ]),
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
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text(code, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 2)),
          IconButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copy thayu')));
              },
              icon: const Icon(Icons.copy, size: 18)),
        ]),
      );

  @override
  Widget build(BuildContext context) => Pg('Settings', [
        box([
          card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            Text('${c.uname}  ·  ${{'owner': 'Owner', 'waiter': 'Order lenar', 'cashier': 'Bill counter'}[c.role]}',
                style: const TextStyle(color: kGray)),
          ])),
          if (c.owner) ...[
            card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Staff mate code', style: TextStyle(fontWeight: FontWeight.w700)),
              const Text('Staff e app ma "Staff" tab ma aa code thi register karvu.', style: TextStyle(color: kGray)),
              codeRow(context, 'Order lenar', '${c.r['waiterCode']}'),
              codeRow(context, 'Bill counter', '${c.r['cashierCode']}'),
            ])),
            card(
                Row(children: [
                  const Expanded(child: Text('Tables ni sankhya')),
                  Text('${c.tables}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const Icon(Icons.chevron_right, color: kGray),
                ]),
                onTap: () async {
                  final v = await askForm(context, 'Tables ni sankhya', ['Sankhya'], init: ['${c.tables}'], numeric: {0});
                  final n = int.tryParse(v?[0] ?? '');
                  if (n != null && n > 0 && n <= 100) {
                    await db.collection('restaurants').doc(c.rid).update({'tables': n});
                  }
                }),
          ],
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kRed),
              onPressed: () => FirebaseAuth.instance.signOut(),
              child: const Text('Logout')),
        ]),
      ]);
}
