"""Offline B2.3 adjudication. No network or production changes.
Oracle is derived from source wording, not parser output. Primary unsupported
measures explicitly reviewed below. Packaging after an explicit mass stays a
source descriptor; whole countable ingredients use the existing db convention.
"""
import json,re,statistics
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; R=ROOT/'results'
load=lambda n:json.loads((R/n).read_text(encoding='utf-8-sig'))
measurement=load('b2_3_parser_measurements.json'); source=load('b2_2_content_source_quality.json'); extraction=load('b2_1_batch_11-20.json')
# id/row: unsupported primary measure, independently interpreted ingredient name.
unsupported={
'11/3':('fej','Hagyma'), '12/3':('fej','Hagyma'),'12/4':('gerezd','Fokhagyma'),
'12/7':('kávéskanál','édesnemes pirospaprika'),'12/10':('csipet','őrölt köménymag'),'12/11':('mokkáskanál','Majoránna'),
'13/5':('gerezd','Fokhagyma'),'14/1':('kis fej','Hagyma'),'14/8':('fej','édes káposzta'),'15/2':('fej','Vöröshagyma'),
'16/6':('cloves','plump garlic peeled and left whole'),
'17/5':('tsp','baking powder'),'17/6':('tbsp','milk'),'17/9':('drop','vanilla extract (optional)'),
'17/10':('half a … jar','good-quality strawberry jam'),
'18/3':('cloves','garlic'),'18/4':('tbsp','oil'),
'18/5':('heaped tsp; alternative level tbsp','hot chilli powder (or 1 level tbsp if you only have mild)'),
'18/6':('tsp','paprika'),'18/7':('tsp','ground cumin'),'18/11':('tsp','dried marjoram'),
'18/12':('tsp','sugar (or add a thumbnail-sized piece of dark chocolate along with the beans instead, see tip)'),
'18/13':('tbsp','tomato purée'),
'19/1':('tbsp','vegetable oil'),'19/4':('tbsp','chicken tikka masala paste (use shop-bought or make your own – see recipe, below)'),
'19/7':('2 x 400g cans','chopped tomatoes'),'19/8':('tbsp','tomato purée'),'19/9':('range tbsp','mango chutney'),
'20/1':('tbsp','olive oil'),'20/2':('rashers','smoked streaky bacon'),'20/4':('stick','celery, finely chopped'),
'20/6':('cloves','garlic finely chopped'),'20/8':('tbsp','tomato purée'),'20/9':('2 x 400g cans','chopped tomatoes'),
'20/10':('tbsp','clear honey'),'20/15':('large handful','basil leaves torn (optional)')}
norm=lambda s:re.sub(r'\s+',' ',s).strip().casefold()
unitmap={'dkg':('g',10),'dl':('ml',100),'darab':('db',1),'evőkanál':('ek',1),**{x:(x,1) for x in ['g','kg','ml','l','db','tk','ek']}}
rows=[]
for r in measurement['rows']:
 key=f"{r['id']}/{r['row']}"; raw=r['raw_extracted_text']; text=re.sub(r'\s+',' ',raw).strip()
 s=next(x for x in source['recipes'] if x['id']==r['id']); evidence=s['ingredients'][r['row']-1]
 assert evidence['json_ld_text']==raw
 b=next(x for x in extraction['results'] if x['id']==r['id']); assert b['candidates'][0]['ingredients'][r['row']-1]==raw
 source_error=evidence['source_verdict'] not in ['MATCH','FORMAT_DIFFERENCE']
 form='missing'; q=1; u='db'; name=text; token=None; conversion=False; explicit_supported_unit=False
 if re.match(r'^\d+\s+x\s+\d+',text): form='multiplier'; q=None
 elif re.match(r'^\d+-\d+',text): form='range'; q=None
 elif text.startswith('half a '): form='textual'; q=None
 elif key in ['17/9','20/15']: form='textual'; q=None
 else:
  m=re.match(r'^(½|¼|¾|\d+/\d+|\d+(?:[.,]\d+)?)(.*)$',text)
  if m:
   token=m[1]; q={'½':0.5,'¼':0.25,'¾':0.75}.get(token)
   if q is None: q=float(token.replace(',','.')) if '/' not in token else int(token.split('/')[0])/int(token.split('/')[1])
   form='unicode_fraction' if token in '½¼¾' else 'slash_fraction' if '/' in token else 'comma_decimal' if ',' in token else 'decimal' if '.' in token else 'integer'
   name=m[2].strip()
   um=re.match(r'^(dkg|kg|g|dl|ml|l|db|darab|tk|ek|evőkanál)\b\s*',name)
   if um:
    explicit_supported_unit=True; u,factor=unitmap[um[1]]; q*=factor; conversion=um[1]!=u
    name=name[um.end():]
 if key in unsupported: name=unsupported[key][1]; u=None
 q_correct=None if q is None else r['parsed_quantity']==q
 u_correct=None if u is None else r['parsed_unit']==u
 n_correct=norm(r['parsed_name'] or '')==norm(name)
 good=q_correct is True and u_correct is True and n_correct and r['output_count']==1
 verdict='UNSUPPORTED_UNIT' if key in unsupported else 'SUPPORTED_NORMALIZATION' if good and conversion else 'CORRECT' if good else 'PARSER_ERROR'
 if good and not conversion and raw!=text: verdict='FORMAT_ONLY'
 r.update({'source_quality':evidence,'source_truth_status':'SOURCE_ERROR' if source_error else 'VALID_SOURCE',
 'primary_classification':'SOURCE_ERROR' if source_error else verdict,'parser_verdict':verdict,
 'explicit_supported_unit':explicit_supported_unit,'quantity_form':form,'source_quantity_token':token,'unsupported_phrase':unsupported.get(key,(None,None))[0],
 'expected':{'name':name,'quantity':q,'unit':u,'note':'null quantity/unit = unsupported semantic expression; not expected parser null fallback'},
 'quantity_correct':q_correct,'unit_correct':u_correct,'name_correct':n_correct,
 'fallback_behavior':{'db':r['parsed_unit']=='db','missing_quantity':'missingQuantity' in r['warnings'],'unknown_unit':'unknownUnit' in r['warnings'],'ambiguous':'ambiguousIngredient' in r['warnings'],'invalid':'invalidQuantity' in r['warnings']},
 'unit_phrase_in_name':key in unsupported and not n_correct,
 'quantity_expression_in_name': form in ['range','multiplier','textual'] and norm(raw)==norm(r['parsed_name'] or ''),
 'unit_incorrectly_consumed':False,
 'limitation':'PARSER_LIMITATION' if form in ['range','multiplier','textual'] or key=='18/5' else None})
 rows.append(r)

def metric(values,key):
 applicable=[r for r in values if r[key] is not None]; correct=sum(r[key] is True for r in applicable)
 return {'correct':correct,'denominator':len(applicable),'percent':100*correct/len(applicable) if applicable else None,'not_applicable':len(values)-len(applicable)}
def stats(values):
 valid=[r for r in values if r['source_truth_status']=='VALID_SOURCE']; supported=[r for r in valid if r['parser_verdict']!='UNSUPPORTED_UNIT']; good=[r for r in valid if r['parser_verdict'] in ['CORRECT','FORMAT_ONLY','SUPPORTED_NORMALIZATION']]
 return {'total':len(values),'source_errors':len(values)-len(valid),'valid_source':len(valid),'correct':len(good),'parser_errors':sum(r['parser_verdict']=='PARSER_ERROR' for r in valid),'unsupported':len(valid)-len(supported),'overall_accuracy_percent':100*len(good)/len(valid),'supported_input_accuracy':{'correct':len(good),'denominator':len(supported),'percent':100*len(good)/len(supported)},'quantity_accuracy':metric(valid,'quantity_correct'),'explicit_quantity_accuracy':metric([r for r in valid if r['quantity_form']!='missing'],'quantity_correct'),'supported_unit_accuracy':metric(supported,'unit_correct'),'explicit_supported_unit_accuracy':metric([r for r in supported if r['explicit_supported_unit']],'unit_correct'),'name_accuracy':metric(valid,'name_correct'),'supported_name_accuracy':metric(supported,'name_correct')}
assert all(r['whole_vs_single_equal'] for r in measurement['recipes'])
summary=stats(rows); summary['warning_rows']=sum(bool(r['warnings']) for r in rows); summary['unknown_unit_warning_rows']=sum('unknownUnit' in r['warnings'] for r in rows); summary['unit_phrase_in_name_rows']=sum(r['unit_phrase_in_name'] for r in rows); summary['supported_normalization_rows']=sum(r['parser_verdict']=='SUPPORTED_NORMALIZATION' and r['source_truth_status']=='VALID_SOURCE' for r in rows);  summary['quantity_forms']={k:{'count':len(v:=[r for r in rows if r['quantity_form']==k]),'valid_source_accuracy':metric([r for r in v if r['source_truth_status']=='VALID_SOURCE'],'quantity_correct')} for k in ['integer','decimal','comma_decimal','slash_fraction','unicode_fraction','mixed_fraction','range','multiplier','missing','textual']}
summary['domains']={d:stats([r for r in rows if r['domain']==d]) for d in sorted(set(r['domain'] for r in rows))}
for recipe in measurement['recipes']: recipe['stats']=stats([r for r in rows if r['id']==recipe['id']])
summary['timing']={'avg_parser_ms_per_ingredient':statistics.mean(r['parser_us'] for r in rows)/1000,'avg_parser_ms_per_recipe':statistics.mean(r['parser_us'] for r in measurement['recipes'])/1000,'batch_recipe_parser_ms':sum(r['parser_us'] for r in measurement['recipes'])/1000,'row_pass_parser_ms':sum(r['parser_us'] for r in rows)/1000,'all_calls_parser_ms':(sum(r['parser_us'] for r in rows)+sum(r['parser_us'] for r in measurement['recipes']))/1000,'method':'One desktop Dart JIT pass; recipe pass then separate row calls. First recipe includes cold/JIT cost; IO excluded. Recipe and row times are separate measurements.'}
unit_rows=[]
for phrase in sorted(set(r['unsupported_phrase'] for r in rows if r['unsupported_phrase'])):
 items=[r for r in rows if r['unsupported_phrase']==phrase]
 unit_rows.append({'phrase':phrase,'count_all':len(items),'count_valid_source':sum(r['source_truth_status']=='VALID_SOURCE' for r in items),'row_ids':[f"{r['id']}/{r['row']}" for r in items],'warnings':sorted(set(w for r in items for w in r['warnings'])),'warning_rows':sum(bool(r['warnings']) for r in items),'db_fallback_rows':sum(r['parsed_unit']=='db' for r in items),'name_leak_rows':sum(r['unit_phrase_in_name'] for r in items),'behavior_examples':[{'raw':r['raw_extracted_text'],'name':r['parsed_name'],'quantity':r['parsed_quantity'],'warnings':r['warnings']} for r in items],'future_handling':'Explicit unsupported warning preserving raw intent; semantic mapping only after product decision. Range/multiplier/textual quantity needs separate grammar, not an alias.'})
terms=['g','kg','ml','l','tsp','tbsp','oz','lb','cup','cans','cloves','rashers','bunch','handful','slices','sticks','sprigs','knob','piece','thumb-sized piece','optional','to serve','divided']
inventory={t:sum(bool(re.search(r'(?<![A-Za-z])'+re.escape(t)+r'(?![A-Za-z])',r['raw_extracted_text'],re.I)) for r in rows) for t in terms}
report={'method':'Offline 11–20 only. Independent source-wording oracle: leading quantity and reviewed supported-unit arithmetic; explicit unsupported semantic phrase inventory. No production normalizer used as oracle. Two SOURCE_ERROR rows excluded from every accuracy denominator. Null metric is not supported/measurable, not correct. Missing quantities use accepted 1 db fallback, not source-provided quantity. Primary gram/ml quantities stay supported even with can/pack/ball descriptors; whole eggs, onions, stock cubes use db. Name fidelity compares case/whitespace only, retains optional/to serve/other notes. Group heading omission is source-level only, never injected as an ingredient. Secondary mentions (alternative tbsp, thumbnail-sized piece) retained as notes. This is not automatic English recipe support.', 'summary':summary,'english_token_inventory':inventory,'unsupported_phrases':unit_rows,'recipes':measurement['recipes'],'rows':rows}
(R/'b2_3_parser_batch_11-20.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
md=['# B2.3 – RecipeTextParser compatibility, 11–20','',report['method'],'','```json',json.dumps(summary,ensure_ascii=False,indent=2),'```','','## Recipe results','','| ID | Valid | Correct | Parser error | Unsupported | Supported accuracy |','|---|---|---|---|---|---|']
for r in measurement['recipes']:
 s=r['stats']; a=s['supported_input_accuracy'];md.append(f"| {r['id']} | {s['valid_source']} | {s['correct']} | {s['parser_errors']} | {s['unsupported']} | {a['correct']}/{a['denominator']} |")
md+=['','## Unsupported primary measures','','| Phrase | Rows (all/valid) | Warning rows | db fallback | Unit/phrase retained in name |','|---|---|---|---|---|']
for u in unit_rows:md.append(f"| {u['phrase']} | {u['count_all']}/{u['count_valid_source']} | {u['warning_rows']} | {u['db_fallback_rows']} | {u['name_leak_rows']} |")
md+=['','## Requested English token coverage (rows containing token, including notes)','','```json',json.dumps(inventory,ensure_ascii=False,indent=2),'```','','Absent tokens have no corpus evidence; no synthetic accuracy claim. `stick` occurs once, `sticks` zero. `thumbnail-sized piece` is a secondary alternative note, not primary ingredient quantity. `can`/`pack`/`ball` after explicit gram weights are retained descriptors.','','## Per-row evidence','']
for r in rows:md.append(f"- **{r['id']}/{r['row']}** `{r['raw_extracted_text']}` → `{r['parsed_name']}` | {r['parsed_quantity']} {r['parsed_unit']}; raw quantity `{r['raw_quantity']}`; warnings {r['warnings']}; **{r['primary_classification']}**; expected {json.dumps(r['expected'],ensure_ascii=False)}.")
md+=['','## Interpretation','','Source errors: 14/8 missing (1,5 kg), 14/9 missing (házi). They cannot be recovered by the parser and do not reduce parser scores. The 17 group heading omission is not an ingredient parser error.','','English tsp/tbsp mostly remain in the name with db and no warning. Unicode ½ itself parses as 0.5 even when tsp is unsupported. Ranges can become missingQuantity + 1 db with the complete raw name; multiplier expressions and half-a-jar become ambiguous with null quantity. The alternative numbered quantity in 18/5 also makes the row ambiguous. These are unsupported-input limitations, not supported-input regressions.','','No production parser change is required to RUN a supervised B2.4 simulation. English drafts will need substantial review; unsupported tokens must not be presented as reliable canonical units. Highest-value future option: consistent unsupported-measure warnings before any deliberate alias decisions. Multipliers/ranges/textual fractions require separate, tested grammar. No implementation performed.','','B2.4 not started. No network, commit, push, corpus or production changes.']
(R/'b2_3_parser_batch_11-20.md').write_text('\n'.join(md)+'\n',encoding='utf-8')
print(json.dumps(summary,ensure_ascii=False,indent=2))
