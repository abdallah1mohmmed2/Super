"""Repeatable static/schema audit for every navigable module (10 rounds).
Requires Python 3 only; this is not a substitute for flutter analyze/test/build.
"""
import json, re, sqlite3
from pathlib import Path
root=Path(__file__).resolve().parents[1]
db_src=(root/'lib/data/database_helper.dart').read_text()
config_src=(root/'lib/screens/screen_config.dart').read_text()
data_src=(root/'lib/screens/data_screen.dart').read_text()
module_src=(root/'lib/screens/modules/module_screen.dart').read_text()
main_src=(root/'lib/main.dart').read_text()
start=db_src.index('final statements = <String>['); end=db_src.index('];',start)
sqls=re.findall(r"'''(.*?)'''",db_src[start:end],re.S)
configs={}
for m in re.finditer(r"'([^']+)': ScreenConfig\('([^']*)','([^']*)',\[([^\]]*)\],\[([^\]]*)\]\)",config_src):
    key,title,table,fields,cols=m.groups()
    configs[key]={'title':title,'table':table,'fields':re.findall(r"'([^']+)'",fields),'columns':re.findall(r"'([^']+)'",cols)}
keys=['products','customers','suppliers','users','sales','returns','purchases','inventory','transfers','damage','cashboxes','cashtransfers','countdocs','counts','dailycount','monthlycount','yearlycount','countreports','reports','backup','closing']
rounds=[]
for n in range(1,11):
    conn=sqlite3.connect(':memory:'); conn.execute('PRAGMA foreign_keys=ON')
    for sql in sqls: conn.execute(sql)
    table_names={r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    assert len(configs)==21, f'Expected 21 configs, found {len(configs)}'
    for key in keys:
        assert key in configs, f'{key}: missing screen config'
        cfg=configs[key]; assert cfg['table'] in table_names, f'{key}: missing table {cfg["table"]}'
        cols={r[1] for r in conn.execute(f'PRAGMA table_info({cfg["table"]})')}
        assert set(cfg['fields']) <= cols, f'{key}: unknown form fields {set(cfg["fields"])-cols}'
        assert set(cfg['columns']) <= cols, f'{key}: unknown display fields {set(cfg["columns"])-cols}'
        assert re.search(r"'"+re.escape(key)+r"'\s*=>",module_src), f'{key}: missing route mapping'
        assert (root/f'lib/screens/modules/{key}_screen.dart').exists(), f'{key}: missing screen file'
    assert 'int? limit, int? offset' in db_src and 'limit: limit, offset: offset' in db_src, 'query limit/offset passthrough missing'
    assert "sha256.convert(utf8.encode(data['password_hash'].toString())).toString()" in data_src
    assert "field == 'password_hash' ? ''" in data_src
    assert "['inventory','backup','counts','dailycount','monthlycount','yearlycount','countreports'].contains(widget.screenKey)" in data_src
    assert "data['from_cashbox_id'] == data['to_cashbox_id']" in data_src, 'same-cashbox guard missing'
    assert "'countdocs'=>'inventory_items'" in data_src, 'inventory count lines not wired'
    assert "'countdocs':'document_no'" in data_src, 'count document numbering missing'
    assert "if (headerRows.isEmpty) { _message('المستند المحدد غير موجود'); return; }" in data_src
    # Verify uniqueness and foreign-key protections in the stock table.
    conn.execute("INSERT INTO warehouses(name) VALUES('QA warehouse')")
    conn.execute("INSERT INTO products(name,code) VALUES('QA product','QA-1')")
    conn.execute("INSERT INTO inventory(product_id,warehouse_id,qty) VALUES(1,1,3)")
    for sql, label in [("INSERT INTO inventory(product_id,warehouse_id,qty) VALUES(1,1,3)",'inventory unique constraint'),("INSERT INTO inventory(product_id,warehouse_id,qty) VALUES(999,1,3)",'inventory foreign key')]:
        try: conn.execute(sql); raise AssertionError(label+' not enforced')
        except sqlite3.IntegrityError: pass
    # Ensure all route names used by the sidebar have configs.
    for key in re.findall(r"NavItem\('([^']+)'",main_src):
        if key!='dashboard': assert key in configs, f'{key}: sidebar item has no config'
    conn.close(); rounds.append({'round':n,'screens':len(keys),'schema_statements':len(sqls),'result':'PASS'})
print(json.dumps({'rounds':rounds,'screen_checks':len(keys)*len(rounds),'schema_statements':len(sqls),'screen_tables':{k:configs[k]['table'] for k in keys},'result':'PASS'},ensure_ascii=False,indent=2))
