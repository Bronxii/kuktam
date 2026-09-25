Kuktám – webes receptimport tesztkorpusz

30 valódi receptoldal, három 10-es tesztkörre bontva.

Fájlpárok:
- website_XX.txt = az eredeti receptoldal URL-je
- recipe_XX.txt = kézzel ellenőrzött ground-truth recept

Körök:
- batch_1_01-10
- batch_2_11-20
- batch_3_21-30

A recipe_XX.txt fájlok csak a teszt szempontjából releváns adatokat tartalmazzák:
cím, hozzávalók, elkészítés.

Az elkészítések tömör, saját megfogalmazású ground-truth leírások; nem az oldalak
hosszú szövegének szó szerinti másolatai.

Benchmark-prioritás:
1. pontosság
2. megbízhatóság
3. sebesség

Mérendő idő minden URL-nél:
- fetch_ms
- extract_ms
- total_ms

Javaslat: egyszerre csak egy 10-es batch fusson, minden batch végén külön riporttal.
