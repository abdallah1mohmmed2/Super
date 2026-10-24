import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'data/database_helper.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'core/app_theme.dart';
import 'providers/app_provider.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/modules/module_screen.dart';

void main() async { WidgetsFlutterBinding.ensureInitialized(); await windowManager.ensureInitialized(); const options=WindowOptions(size:Size(1440,900),minimumSize:Size(1000,650),center:true,title:'Store & ERP Management System'); windowManager.waitUntilReadyToShow(options,()async{await windowManager.maximize();await windowManager.show();await windowManager.focus();}); runApp(const StoreErpApp()); }
class StoreErpApp extends StatelessWidget { const StoreErpApp({super.key}); @override Widget build(BuildContext context)=>ChangeNotifierProvider(create:(_)=>AppProvider(),child:MaterialApp(debugShowCheckedModeBanner:false,title:'Store & ERP',theme:AppTheme.light,home:const RootShell())); }
class NavItem { final String key,title,group; final IconData icon; const NavItem(this.key,this.title,this.group,this.icon); }
const navItems=<NavItem>[
 NavItem('sales','المبيعات','العمليات',Icons.point_of_sale),NavItem('purchases','المشتريات','العمليات',Icons.shopping_cart),NavItem('returns','مرتجع البيع','العمليات',Icons.assignment_return),NavItem('inventory','المخزون','العمليات',Icons.inventory_2),NavItem('transfers','تحويل المخازن','العمليات',Icons.swap_horiz),NavItem('damage','سند التالف والمنتهي','العمليات',Icons.delete_sweep),
 NavItem('products','إدارة الأصناف','الإعدادات',Icons.category),NavItem('customers','إدارة العملاء','الإعدادات',Icons.people),NavItem('suppliers','إدارة الموردين','الإعدادات',Icons.local_shipping),NavItem('users','إدارة المستخدمين','الإعدادات',Icons.manage_accounts),NavItem('cashboxes','إدارة الصناديق','الإعدادات',Icons.account_balance_wallet),NavItem('cashtransfers','تحويل الصناديق','الإعدادات',Icons.swap_calls),NavItem('countdocs','متابعة مستندات الجرد','الإعدادات',Icons.fact_check),
 NavItem('counts','الجرد الفعلي','الجرد',Icons.checklist),NavItem('dailycount','الجرد اليومي','الجرد',Icons.today),NavItem('monthlycount','الجرد الشهري','الجرد',Icons.calendar_month),NavItem('yearlycount','الجرد السنوي','الجرد',Icons.event),NavItem('countreports','تقارير الجرد','الجرد',Icons.query_stats),
 NavItem('reports','التقارير العامة','الإدارة',Icons.bar_chart),NavItem('approvals','اعتمادات المدير','الإدارة',Icons.fact_check_outlined),NavItem('backup','النسخ الاحتياطي والاسترجاع','الإدارة',Icons.backup),NavItem('closing','الإقفال اليومي','الإدارة',Icons.lock_clock),
];
class RootShell extends StatefulWidget {const RootShell({super.key});@override State<RootShell> createState()=>_RootShellState();}
class _RootShellState extends State<RootShell>{
 String _selected='dashboard';
 bool _collapsed=false;
 Timer? _backupScheduleTimer;
 bool _scheduledBackupRunning=false;

 @override
 void initState() {
   super.initState();
   _backupScheduleTimer = Timer.periodic(const Duration(minutes: 1), (_) {
     _runScheduledBackup();
   });
 }

 @override
 void dispose() {
   _backupScheduleTimer?.cancel();
   super.dispose();
 }

 Future<void> _runScheduledBackup() async {
   if (_scheduledBackupRunning) return;
   _scheduledBackupRunning = true;
   String? attemptedPath;
   try {
     final support = await getApplicationSupportDirectory();
     final settingsFile = File(p.join(support.path, 'backup_settings.json'));
     if (!await settingsFile.exists()) return;
     final settings = jsonDecode(await settingsFile.readAsString()) as Map<String, dynamic>;
     if (settings['daily'] != true) return;
     final time = (settings['time'] ?? '22:00').toString().trim();
     final match = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').firstMatch(time);
     if (match == null) return;
     final hour = int.parse(match.group(1)!);
     final minute = int.parse(match.group(2)!);
     final now = DateTime.now();
     if (now.hour < hour || (now.hour == hour && now.minute < minute)) return;
     final today = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
     final lastRunFile = File(p.join(support.path, 'backup_last_attempt.txt'));
     if (await lastRunFile.exists() && (await lastRunFile.readAsString()).trim() == today) return;
     await lastRunFile.writeAsString(today, flush: true);
     final defaultFolder = p.join(support.path, 'backups');
     final folderPath = (settings['folder'] ?? defaultFolder).toString().trim();
     final rawName = (settings['filename'] ?? 'store_backup').toString().trim();
     if (folderPath.isEmpty || rawName.isEmpty) throw StateError('حدد مجلد واسم النسخة في إعدادات النسخ الاحتياطي');
     final safeName = p.basenameWithoutExtension(rawName).replaceAll(RegExp(r'[^a-zA-Z0-9_\-\u0600-\u06FF]'), '_');
     final stamp = now.toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
     final folder = Directory(folderPath);
     await folder.create(recursive: true);
     attemptedPath = p.join(folder.path, '${safeName}_daily_$stamp.db');
     final db = DatabaseHelper.instance;
     await db.prepareForBackup();
     final source = File(await db.databasePath);
     if (!await source.exists()) throw StateError('لم يتم العثور على ملف قاعدة البيانات');
     final target = await source.copy(attemptedPath);
     if (settings['verifyDaily'] == true) await db.verifyDatabaseFile(target.path);
     await db.insert('backup_history', {'file_path': target.path, 'status': 'نجاح'});
   } catch (e) {
     try {
       await DatabaseHelper.instance.insert('backup_history', {
         'file_path': attemptedPath ?? 'نسخة يومية',
         'status': 'فشل: $e',
       });
     } catch (_) {}
   } finally {
     _scheduledBackupRunning = false;
   }
 }

 @override Widget build(BuildContext context)=>Consumer<AppProvider>(builder:(context,provider,_)=>provider.loggedIn?_buildApp(context,provider):const Directionality(textDirection:TextDirection.rtl,child:LoginScreen()));
 Widget _buildApp(BuildContext context,AppProvider provider){return Directionality(textDirection:TextDirection.rtl,child:Scaffold(body:Row(children:[AnimatedContainer(duration:const Duration(milliseconds:180),width:_collapsed?76:258,color:AppTheme.navy,child:Column(children:[Padding(padding:const EdgeInsets.fromLTRB(14,20,14,18),child:Row(children:[const Icon(Icons.storefront,color:AppTheme.emerald,size:30),if(!_collapsed)const Expanded(child:Padding(padding:EdgeInsets.only(right:10),child:Text('متجر ERP',style:TextStyle(color:Colors.white,fontSize:18,fontWeight:FontWeight.bold))))]),),Expanded(child:ListView(children:[_navTile('dashboard','لوحة التحكم',Icons.dashboard_outlined),for(final group in ['العمليات','الإعدادات','الجرد','الإدارة'])...[_groupLabel(group),...navItems.where((e)=>e.group==group).map((e)=>_navTile(e.key,e.title,e.icon))]])),Padding(padding:const EdgeInsets.all(10),child:IconButton(onPressed:()=>setState(()=>_collapsed=!_collapsed),icon:Icon(_collapsed?Icons.chevron_left:Icons.chevron_right,color:Colors.white70)))])),Expanded(child:Column(children:[Container(height:68,padding:const EdgeInsets.symmetric(horizontal:22),color:Colors.white,child:Row(children:[IconButton(onPressed:()=>setState(()=>_collapsed=!_collapsed),icon:const Icon(Icons.menu)),const SizedBox(width:8),Expanded(child:Text(_selected=='dashboard'?'لوحة التحكم':navItems.firstWhere((e)=>e.key==_selected,orElse:()=>const NavItem('','النظام','',Icons.apps)).title,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold))),const Icon(Icons.circle,color:AppTheme.emerald,size:10),const SizedBox(width:6),const Text('متصل'),const SizedBox(width:18),CircleAvatar(backgroundColor:AppTheme.navy,child:Text(provider.currentUser.isEmpty?'أ':provider.currentUser.characters.first,style:const TextStyle(color:Colors.white))),const SizedBox(width:8),Text(provider.currentUser),const SizedBox(width:8),IconButton(tooltip:'تسجيل الخروج',onPressed:()=>setState(()=>provider.loggedIn=false),icon:const Icon(Icons.logout))])),Expanded(child:_selected=='dashboard'?DashboardScreen(onOpen:(key)=>setState(()=>_selected=key)):ModuleScreen(key:ValueKey(_selected),screenKey:_selected))]))])));}
 Widget _groupLabel(String group)=>Padding(padding:EdgeInsets.fromLTRB(_collapsed?0:18,18, _collapsed?0:18,6),child:Text(_collapsed?'•':group,style:const TextStyle(color:Colors.white54,fontSize:12,fontWeight:FontWeight.bold)));
 Widget _navTile(String key,String title,IconData icon){final active=_selected==key;return Tooltip(message:_collapsed?title:'',child:Padding(padding:const EdgeInsets.symmetric(horizontal:8,vertical:2),child:Material(color:active?AppTheme.emerald.withValues(alpha:.18):Colors.transparent,borderRadius:BorderRadius.circular(10),child:InkWell(borderRadius:BorderRadius.circular(10),onTap:()=>setState(()=>_selected=key),child:Padding(padding:EdgeInsets.symmetric(horizontal:_collapsed?0:12,vertical:12),child:Row(mainAxisAlignment:_collapsed?MainAxisAlignment.center:MainAxisAlignment.start,children:[Icon(icon,color:active?AppTheme.emerald:Colors.white70,size:21),if(!_collapsed)Expanded(child:Padding(padding:const EdgeInsets.only(right:12),child:Text(title,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:active?Colors.white:Colors.white70,fontWeight:active?FontWeight.bold:FontWeight.normal))))]))))));}
}
