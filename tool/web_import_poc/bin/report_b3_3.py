"""Offline B3.3 source-wording oracle; no fetch or production mutation."""
import json,re,statistics
from pathlib import Path
R=Path(__file__).resolve().parents[1]/'results'
load=lambda n:json.loads((R/n).read_text(encoding='utf-8-sig'))
m=load('b3_3_parser_measurements.json'); source=load('b3_2_content_source_quality.json')
norm=lambda s:re.sub(r'\s+',' ',s).strip().casefold()
# Explicitly reviewed primary measures, independent of the observed parser output.
# Whole cloves (23/5) are the spice, not a unit. Packaging after grams is descriptive.
unsupported={
'21/1':('tbsp','sunflower oil','SIMPLE_ALIAS_CANDIDATE'),
'21/3':('cloves','garlic crushed','SEMANTIC_DECISION'),
'21/4':('thumb-sized piece','ginger grated','SEMANTIC_DECISION'),
'21/6':('tbsp','medium spice paste (tikka works well)','SIMPLE_ALIAS_CANDIDATE'),
'21/9':('small bunch','coriander leaves chopped','SEMANTIC_DECISION'),
'22/4':('tbsp','sunflower or vegetable oil plus a little extra for frying','SIMPLE_ALIAS_CANDIDATE'),
'23/8':('small bunch','parsley leaves only, chopped','SEMANTIC_DECISION'),
'23/11':('pinch','freshly grated nutmeg','SEMANTIC_DECISION'),
'25/2':('tbsp','golden caster sugar','SIMPLE_ALIAS_CANDIDATE'),
'25/6':('tbsp','rolled oats','SIMPLE_ALIAS_CANDIDATE'),
'25/7':('tbsp','demerara sugar','SIMPLE_ALIAS_CANDIDATE'),
'26/1':('range + kg/lb/oz compound quantity','ripe tomatoes','QUANTITY_GRAMMAR'),
'26/4':('stick','celery','SEMANTIC_DECISION'),
'26/5':('tbsp','olive oil','SIMPLE_ALIAS_CANDIDATE'),
'26/6':('squirts + alternative tsp','tomato purée (about 2 tsp)','QUANTITY_GRAMMAR'),
'26/7':('good pinch','sugar','SEMANTIC_DECISION'),
'26/9':('litres/pints + alternative stock quantities','hot vegetable stock (made with boiling water and 4 rounded tsp bouillon powder or 2 stock cubes)','QUANTITY_GRAMMAR'),
'27/1':('tbsp','olive oil','SIMPLE_ALIAS_CANDIDATE'),
'27/3':('cloves','garlic finely chopped','SEMANTIC_DECISION'),
'27/4':('tbsp','tomato purée','SIMPLE_ALIAS_CANDIDATE'),
'27/6':('handful','basil leaf','SEMANTIC_DECISION'),
'27/7':('pinch','bicarbonate of soda','SEMANTIC_DECISION'),
'28/1':('tbsp','olive oil','SIMPLE_ALIAS_CANDIDATE'),
'28/4':('cloves','large garlic crushed','SEMANTIC_DECISION'),
'28/5':('small bunch','coriander stalks finely chopped and leaves roughly chopped','SEMANTIC_DECISION'),
'28/6':('tbsp','ground coriander','SIMPLE_ALIAS_CANDIDATE'),
'28/7':('tbsp','ground cumin','SIMPLE_ALIAS_CANDIDATE'),
'28/8':('range tsp','chipotle paste','QUANTITY_GRAMMAR'),
'28/10':('tbsp','tomato purée','SIMPLE_ALIAS_CANDIDATE'),
'28/12':('stick','small cinnamon','SEMANTIC_DECISION'),
'28/16':('tbsp','red wine vinegar','SIMPLE_ALIAS_CANDIDATE')}
rows=[]
for measured in m['rows']:
 r=dict(measured); key=f"{r['id']}/{r['row']}"; raw=r['raw_extracted_text']; text=re.sub(r'\s+',' ',raw).strip()
 assert 21<=int(r['id'])<=28
 evidence=next(x for x in source['recipes'] if x['id']==r['id'])['ingredients'][r['row']-1]
 assert evidence['json_ld_text']==raw and evidence['source_verdict'] in ['MATCH','FORMAT_DIFFERENCE']
 form='missing';q=1;u='db';name=text;token=None;explicit=False
 match=re.match(r'^(½|¼|¾|\d+/\d+|\d+(?:[.,]\d+)?)(.*)$',text)
 if match:
  token=match[1];q={'½':.5,'¼':.25,'¾':.75}.get(token)
  if q is None:q=float(token.replace(',','.')) if '/' not in token else int(token.split('/')[0])/int(token.split('/')[1])
  form='unicode_fraction' if token in '½¼¾' else 'slash_fraction' if '/' in token else 'comma_decimal' if ',' in token else 'decimal' if '.' in token else 'integer'
  name=match[2].strip();um=re.match(r'^(kg|g|ml|l)\b\s*',name)
  if um: u=um[1];name=name[um.end():];explicit=True
 if key in ['26/1','28/8']:form='range';q=None;token=text.split()[0]
 if key=='26/9':form='compound_alternative';q=None;token='1.2 litres/2 pints'
 if key in unsupported and not match:form='textual';q=None
 phrase,category=None,None
 if key in unsupported:
  phrase,name,category=unsupported[key];u=None
 qc=None if q is None else r['parsed_quantity']==q
 uc=None if u is None else r['parsed_unit']==u
 nc=norm(r['parsed_name'] or '')==norm(name)
 good=qc is True and uc is True and nc and r['output_count']==1
 verdict=('PARSER_LIMITATION' if category=='QUANTITY_GRAMMAR' else 'UNSUPPORTED_UNIT') if key in unsupported else ('CORRECT' if good else 'PARSER_ERROR')
 if good and raw!=text:verdict='FORMAT_ONLY'
 silent=key in unsupported and not r['warnings'] and r['output_count']==1 and isinstance(r['parsed_quantity'],(int,float)) and r['parsed_quantity']>0 and r['parsed_unit']=='db'
 r.update(source_status='VALID_SOURCE',source_quality=evidence,verdict=verdict,unsupported_phrase=phrase,unsupported_category=category,quantity_form=form,source_quantity_token=token,explicit_supported_unit=explicit,
 expected={'quantity':q,'unit':u,'name':name,'note':'Null = unsupported semantic quantity/unit, not expected null parser output.'},quantity_correct=qc,unit_correct=uc,name_correct=nc,silent_fallback=silent,
 fallback_behavior={'db':r['parsed_unit']=='db','unknown_unit_warning':'unknownUnit' in r['warnings'],'missing_quantity_warning':'missingQuantity' in r['warnings'],'invalid_quantity_warning':'invalidQuantity' in r['warnings'],'ambiguous_warning':'ambiguousIngredient' in r['warnings']},
 unit_phrase_in_name=key in unsupported and not nc,quantity_expression_in_name=form in ['range','compound_alternative','textual'] and norm(raw)==norm(r['parsed_name'] or ''),unit_incorrectly_consumed=False)
 rows.append(r)
assert len(rows)==82 and all(r['whole_vs_single_equal'] for r in m['recipes'])
def metric(v,key):
 a=[r for r in v if r[key] is not None];c=sum(r[key] is True for r in a)
 return dict(correct=c,denominator=len(a),percent=100*c/len(a) if a else None,not_applicable=len(v)-len(a))
def stats(v):
 supported=[r for r in v if r['verdict'] not in ['UNSUPPORTED_UNIT','PARSER_LIMITATION']];correct=[r for r in supported if r['verdict']!='PARSER_ERROR'];silent=[r for r in v if r['silent_fallback']]
 return dict(total=len(v),valid_source=len(v),source_errors=0,supported=len(supported),correct_supported=len(correct),parser_errors=len(supported)-len(correct),unsupported_rows=len(v)-len(supported),unsupported_unit_rows=sum(r['verdict']=='UNSUPPORTED_UNIT' for r in v),parser_limitation_rows=sum(r['verdict']=='PARSER_LIMITATION' for r in v),overall_valid_input_success_percent=100*len(correct)/len(v),supported_input_accuracy_percent=100*len(correct)/len(supported) if supported else None,quantity_accuracy=metric(v,'quantity_correct'),explicit_quantity_accuracy=metric([r for r in v if r['quantity_form']!='missing'],'quantity_correct'),supported_unit_accuracy=metric(supported,'unit_correct'),explicit_supported_unit_accuracy=metric([r for r in supported if r['explicit_supported_unit']],'unit_correct'),name_accuracy=metric(v,'name_correct'),supported_name_accuracy=metric(supported,'name_correct'),silent_fallback_rows=len(silent),silent_fallback_rate_percent=100*len(silent)/len(v),silent_fallback_affected_recipes=len(set(r['id'] for r in silent)))
summary=stats(rows)
summary['supported_quantity_accuracy']=metric([r for r in rows if r['verdict'] not in ['UNSUPPORTED_UNIT','PARSER_LIMITATION']],'quantity_correct')
summary['quantity_forms']={f:dict(count=len(v:=[r for r in rows if r['quantity_form']==f]),accuracy=metric(v,'quantity_correct')) for f in ['integer','decimal','comma_decimal','slash_fraction','unicode_fraction','mixed_fraction','range','multiplier','textual','missing','compound_alternative']}
summary['warning_rows']=sum(bool(r['warnings']) for r in rows)
summary['unknown_unit_warning_rows']=sum('unknownUnit' in r['warnings'] for r in rows)
summary['timing']={'avg_parser_ms_per_row':statistics.mean(r['parser_us'] for r in rows)/1000,'avg_parser_ms_per_recipe':statistics.mean(r['parser_us'] for r in m['recipes'])/1000,'batch_recipe_parser_ms':sum(r['parser_us'] for r in m['recipes'])/1000,'row_pass_parser_ms':sum(r['parser_us'] for r in rows)/1000,'method':'DESKTOP Dart JIT; one recipe pass plus independent row pass. Stopwatch excludes IO. First recipe includes cold/JIT cost. The two timings are separate, not interchangeable.'}
for recipe in m['recipes']:recipe['stats']=stats([r for r in rows if r['id']==recipe['id']])
phrases=[]
for phrase in sorted(set(r['unsupported_phrase'] for r in rows if r['unsupported_phrase'])):
 v=[r for r in rows if r['unsupported_phrase']==phrase]
 phrases.append(dict(phrase=phrase,count=len(v),category=v[0]['unsupported_category'],warning_rows=sum(bool(r['warnings']) for r in v),warnings=sorted(set(w for r in v for w in r['warnings'])),db_fallback_rows=sum(r['parsed_unit']=='db' for r in v),name_leak_rows=sum(r['unit_phrase_in_name'] for r in v),silent_rows=sum(r['silent_fallback'] for r in v),examples=[{'id':r['id'],'row':r['row'],'raw':r['raw_extracted_text'],'name':r['parsed_name'],'quantity':r['parsed_quantity']} for r in v]))
terms=['tsp','tbsp','cloves','clove','cans','can','tin','tins','handful','bunch','sprigs','slices','stick','piece','knob','rashers','optional','to serve','divided','half','quarter','dkg','dl','kk']
inventory={t:sum(bool(re.search(r'(?<![A-Za-z])'+re.escape(t)+r'(?![A-Za-z])',r['raw_extracted_text'],re.I)) for r in rows) for t in terms}
report={'method':'Offline 21–28 only. Independent source-wording expectations and explicit reviewed unsupported primary measures. 4 absent group headings are source metadata only. No ingredient SOURCE_ERROR. Missing unspecified quantities use accepted 1 db fallback; warnings retained. Whole countable items use db, including cloves as spice (23/5). Garlic cloves and celery/cinnamon sticks treated as semantic unit decisions, consistent with Batch 2. Packaging after explicit grams remains a descriptor. Unsupported names scored against semantic ingredient-name expectation, not raw preservation; raw text is retained. Null quantity/unit metrics excluded and denominators explicit. No invented scores for absent quantity forms. Unsupported means unit or grammar, not supported-input parser error. Production warnings and audit classifications remain separate.', 'summary':summary,'recipes':m['recipes'],'rows':rows,'unsupported_phrases':phrases,'token_inventory':inventory,'source_group_heading_omissions':4,'excluded':{'29':'NOT_TESTED_DUE_TO_ACCESS_BLOCK','30':'NOT_TESTED_DUE_TO_ACCESS_BLOCK'}}
(R/'b3_3_parser_batch_21-28.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
md=['# B3.3 – RecipeTextParser benchmark, 21–28','',report['method'],'','## Summary','```json',json.dumps(summary,ensure_ascii=False,indent=2),'```','','## Per recipe','| ID | Rows | Supported | Correct | Unsupported (incl. grammar) | Errors | Silent | Overall success |','|---|---|---|---|---|---|---|---|']
for recipe in m['recipes']:
 s=recipe['stats'];md.append(f"| {recipe['id']} | {s['total']} | {s['supported']} | {s['correct_supported']} | {s['unsupported_rows']} | {s['parser_errors']} | {s['silent_fallback_rows']} | {s['overall_valid_input_success_percent']:.2f}% |")
md+=['','## Unsupported inventory','| Token/expression | Count | Warning rows | db | In name | Silent | Category |','|---|---|---|---|---|---|---|']
for u in phrases:md.append(f"| {u['phrase']} | {u['count']} | {u['warning_rows']} | {u['db_fallback_rows']} | {u['name_leak_rows']} | {u['silent_rows']} | {u['category']} |")
md+=['','## Token coverage (including secondary notes)','```json',json.dumps(inventory,indent=2),'```','Absent forms have no benchmark evidence. ½ occurs once and its numeric value is preserved (0.5), while tbsp is unsupported. Compound kg/lb/oz and litres/pints expressions are limitations, not supported metric unit failures. Explicit dkg/dl/kk conversions do not occur. Optional/to serve text remains in ingredient names; absent group headings cannot be recovered.','','## Row evidence']
for r in rows:md.append(f"- **{r['id']}/{r['row']}** `{r['raw_extracted_text']}` → {r['parsed_quantity']} {r['parsed_unit']} | `{r['parsed_name']}`; raw quantity `{r['raw_quantity']}`; production warnings {r['warnings']}; **{r['verdict']}**; silent fallback {r['silent_fallback']}; expected {json.dumps(r['expected'],ensure_ascii=False)}.")
md+=['','## Quantity interpretation','The one explicit numeric mismatch is 26/6: 2 squirts with alternative (about 2 tsp) produces ambiguousIngredient and null quantity. It belongs to PARSER_LIMITATION, not supported-input error. The 1.2 decimal occurs only inside a compound litres/pints expression; the zero standalone decimal count does not mean that no decimal characters appear. Semantic unsupported names retain all original words but are not normalized ingredient-only names.','','## Decision','No production parser change is needed before a supervised B3.4 POC simulation. Carry all unsupported classifications into explicit POC review warnings, including silent fallbacks. This is not approval for unattended production import. 29–30: NOT_TESTED_DUE_TO_ACCESS_BLOCK (HTTP 403), absent from every parser denominator. B3.4 not started. No network or production changes.']
(R/'b3_3_parser_batch_21-28.md').write_text('\n'.join(md)+'\n',encoding='utf-8',newline='\n')
print(json.dumps(summary,indent=2))
