import 'package:flutter/material.dart';
import '../core/app_theme.dart';

class SectionCard extends StatelessWidget {
  final String title; final Widget child; final Widget? trailing;
  const SectionCard({super.key, required this.title, required this.child, this.trailing});
  @override Widget build(BuildContext context) => Card(margin: const EdgeInsets.only(bottom: 14), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Row(children: [Expanded(child: Text(title, style: const TextStyle(fontSize: 17,fontWeight: FontWeight.bold))), if(trailing!=null) trailing!]), const SizedBox(height: 14), child])));
}
class ActionButton extends StatelessWidget {
 final String label; final VoidCallback onPressed; final IconData? icon; final bool primary, danger;
 const ActionButton(this.label,{super.key,required this.onPressed,this.icon,this.primary=false,this.danger=false});
 @override Widget build(BuildContext context) => FilledButton.tonalIcon(onPressed:onPressed, icon:Icon(icon??Icons.check,size:18), label:Text(label), style:FilledButton.styleFrom(backgroundColor: danger?Colors.red.shade50:(primary?AppTheme.emerald.withValues(alpha:.14):null), foregroundColor:danger?Colors.red.shade700:(primary?const Color(0xFF047857):AppTheme.navy), padding:const EdgeInsets.symmetric(horizontal:14,vertical:13), shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12))));
}
class StatCard extends StatelessWidget { final String title,value; final IconData icon; final Color color; const StatCard({super.key,required this.title,required this.value,required this.icon,required this.color});
 @override Widget build(BuildContext context)=>Card(child:Padding(padding:const EdgeInsets.all(16),child:Row(children:[Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:color.withValues(alpha:.12),borderRadius:BorderRadius.circular(12)),child:Icon(icon,color:color)),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:TextStyle(color:Colors.blueGrey.shade600)),const SizedBox(height:6),Text(value,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:22))]))])));
}


/// Supplies a real close action to modules rendered inside the main shell.
class ModuleNavigationScope extends InheritedWidget {
  final VoidCallback onClose;

  const ModuleNavigationScope({
    super.key,
    required this.onClose,
    required super.child,
  });

  static ModuleNavigationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ModuleNavigationScope>();

  @override
  bool updateShouldNotify(ModuleNavigationScope oldWidget) =>
      onClose != oldWidget.onClose;
}

void closeModule(BuildContext context) {
  final scope = ModuleNavigationScope.maybeOf(context);
  if (scope != null) {
    scope.onClose();
  } else {
    Navigator.maybePop(context);
  }
}
