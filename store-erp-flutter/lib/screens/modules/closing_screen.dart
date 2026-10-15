import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/database_helper.dart';
import '../../providers/app_provider.dart';

class DailyClosingScreen extends StatefulWidget {
  const DailyClosingScreen({super.key});
  @override State<DailyClosingScreen> createState()=>_DailyClosingScreenState();
}
class _DailyClosingScreenState extends State<DailyClosingScreen> {
  late Future<List<Map<String,Object?>>> _future;
  DateTime _date=DateTime.now(); bool _busy=false;
  @override void initState(){super.initState();_future=DatabaseHelper.instance.query('daily_closings',orderBy:'close_date DESC');}
  String _money(Object? v)=>((v as num?)?.toDouble()??0).toStringAsFixed(2);
  void _reload(){setState(()=>_future=DatabaseHelper.instance.query('daily_closings',orderBy:'close_date DESC'));}
  Future<void> _closeDay() async {
    final date=_date.toIso8601String().substring(0,10);
    final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('تأكيد الإقفال اليومي'),content:Text('سيتم تثبيت ملخص اليوم $date. لا يمكن ترحيل فواتير مبيعات أو مشتريات جديدة لهذا التاريخ بعد الإقفال.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('رجوع')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('إقفال اليوم'))]));
    if(yes!=true||!mounted)return;setState(()=>_busy=true);
    try{final result=await DatabaseHelper.instance.closeDay(date,context.read<AppProvider>().currentUser);_reload();if(mounted)showDialog<void>(context:context,builder:(ctx)=>AlertDialog(title:const Text('تم الإقفال'),content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[Text('التاريخ: $date'),Text('المبيعات: ${_money(result['sales_total'])}'),Text('المتحصلات: ${_money(result['sales_paid'])}'),Text('المشتريات: ${_money(result['purchases_total'])}'),Text('أرصدة الصناديق: ${_money(result['cash_total'])}')]),actions:[FilledButton(onPressed:()=>Navigator.pop(ctx),child:const Text('موافق'))]));}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('تعذر الإقفال: $e')));}finally{if(mounted)setState(()=>_busy=false);}
  }
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(18),children:[const Text('الإقفال اليومي',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),const SizedBox(height:8),const Text('يمنع الإقفال وجود مستندات مبيعات أو مشتريات غير مرحلة في التاريخ المختار.'),const SizedBox(height:12),Card(child:Padding(padding:const EdgeInsets.all(16),child:Wrap(spacing:12,runSpacing:12,crossAxisAlignment:WrapCrossAlignment.center,children:[OutlinedButton.icon(onPressed:()async{final v=await showDatePicker(context:context,initialDate:_date,firstDate:DateTime(2000),lastDate:DateTime(2100));if(v!=null)setState(()=>_date=v);},icon:const Icon(Icons.calendar_month),label:Text('التاريخ: ${_date.toIso8601String().substring(0,10)}')),FilledButton.icon(onPressed:_busy?null:_closeDay,icon:const Icon(Icons.lock_clock),label:Text(_busy?'جارٍ الإقفال...':'إقفال اليوم'))]))),const SizedBox(height:14),FutureBuilder<List<Map<String,Object?>>>(future:_future,builder:(context,s)=>Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('سجل الإقفالات السابقة',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:8),if(s.connectionState==ConnectionState.waiting)const LinearProgressIndicator()else if(s.hasError)Text('خطأ: ${s.error}')else if((s.data??[]).isEmpty)const Text('لا توجد إقفالات سابقة')else SingleChildScrollView(scrollDirection:Axis.horizontal,child:DataTable(columns:const[DataColumn(label:Text('التاريخ')),DataColumn(label:Text('المبيعات')),DataColumn(label:Text('المتحصلات')),DataColumn(label:Text('المشتريات')),DataColumn(label:Text('أرصدة الصناديق')),DataColumn(label:Text('المستخدم'))],rows:s.data!.map((r)=>DataRow(cells:[DataCell(Text('${r['close_date']}')),DataCell(Text(_money(r['sales_total']))),DataCell(Text(_money(r['sales_paid']))),DataCell(Text(_money(r['purchases_total']))),DataCell(Text(_money(r['cash_total']))),DataCell(Text('${r['closed_by']??'—'}'))])).toList()))])))]);
}
