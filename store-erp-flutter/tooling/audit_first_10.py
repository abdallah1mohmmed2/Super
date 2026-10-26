import re, sqlite3, hashlib, json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
db_src=(root/'lib/data/database_helper.dart').read_text()
config_src=(root/'lib/screens/screen_config.dart').read_text()
data_src=(root/'lib/screens/data_screen.dart').read_text()
module_src=(root/'lib/screens/modules/module_screen.dart').read_text()
main_src=(root/'lib/main.dart').read_text()
start=db_src.index('final statements = <String>['); end=db_src.index('];',start)
sqls=re.findall(r"'''(.*?)'''",db_src[start:end],re.S)
keys=['products','customers','suppliers','users','sales','returns','purchases','inventory','transfers','damage']
configs={}
for m in re.finditer(r"'([^']+)': ScreenConfig\('([^']*)','([^']*)',\[([^\]]*)\],\[([^\]]*)\]\)",config_src):
    key,title,table,fields,cols=m.groups()
    configs[key]={'table':table,'fields':re.findall(r"'([^']+)'",fields),'columns':re.findall(r"'([^']+)'",cols)}
checks=[]
for pass_no in range(1,11):
    conn=sqlite3.connect(':memory:'); conn.execute('PRAGMA foreign_keys=ON')
    for sql in sqls: conn.execute(sql)
    table_names={r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    assert all(k in configs for k in keys), 'missing config'
    for key in keys:
        cfg=configs[key]; assert cfg['table'] in table_names, f'{key}: missing table {cfg["table"]}'
        cols={r[1] for r in conn.execute(f'PRAGMA table_info({cfg["table"]})')}
        assert set(cfg['fields']) <= cols, f'{key}: missing form fields {set(cfg["fields"])-cols}'
        assert set(cfg['columns']) <= cols, f'{key}: missing display columns {set(cfg["columns"])-cols}'
        assert f"'{key}' =>" in module_src, f'{key}: missing route'
        assert (root/f'lib/screens/modules/{key}_screen.dart').exists(), f'{key}: missing screen file'
    assert "sha256.convert(utf8.encode(data['password_hash'].toString())).toString()" in data_src, 'password hash not saved safely'
    assert "field == 'password_hash' ? ''" in data_src, 'password hash exposed in edit form'
    assert "bool get _readOnly => widget.screenKey == 'inventory'" in data_src, 'inventory not read-only'
    assert "['invoice_no','invoice_date','customer_id','warehouse_id','cash_box_id','payment_method','discount','tax','paid','notes']" in config_src, 'calculated sales totals still editable'
    assert "['invoice_no','external_no','invoice_date','supplier_id','warehouse_id','cash_box_id','discount','tax','paid','notes']" in config_src, 'calculated purchase totals still editable'
    assert "['transfer_no','transfer_date','from_warehouse_id','to_warehouse_id','notes']" in config_src, 'transfer status can be manually edited'
    assert "if (widget.screenKey == 'transfers' && data['from_warehouse_id'] == data['to_warehouse_id'])" in data_src, 'same-warehouse transfer not prevented'
    assert 'await _recalculateDraftTotals();' in data_src, 'invoice totals not recalculated on save'
    assert "if (headerRows.isEmpty) { _message('المستند المحدد غير موجود'); return; }" in data_src, 'posting missing-header guard'
    # Smoke-check schema defaults, unique constraints and FK enforcement.
    conn.execute("INSERT INTO warehouses(name) VALUES('QA warehouse')")
    conn.execute("INSERT INTO products(name,code) VALUES('QA product','QA-1')")
    conn.execute("INSERT INTO inventory(product_id,warehouse_id,qty) VALUES(1,1,3)")
    try:
        conn.execute("INSERT INTO inventory(product_id,warehouse_id,qty) VALUES(1,1,3)")
        raise AssertionError('inventory uniqueness not enforced')
    except sqlite3.IntegrityError: pass
    try:
        conn.execute("INSERT INTO inventory(product_id,warehouse_id,qty) VALUES(999,1,3)")
        raise AssertionError('foreign key not enforced')
    except sqlite3.IntegrityError: pass
    conn.close()
    checks.append({'pass':pass_no,'interfaces_checked':len(keys),'schema_statements':len(sqls),'result':'PASS'})
print(json.dumps({'passes':checks,'total_interface_checks':sum(x['interfaces_checked'] for x in checks),'sql_statements':len(sqls),'configs':{k:configs[k]['table'] for k in keys}},ensure_ascii=False,indent=2))
