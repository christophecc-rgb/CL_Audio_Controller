"""Synthetic OOXML/CSV compatibility fixtures; no vendor application required."""
import io
import zipfile
from xml.sax.saxutils import escape
import pytest
from showcue_builder import import_csv, import_xlsx, BuilderImportError, _sheet_xml


def workbook(sheets, shared=False, table=False):
    ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
    relns = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
    files = {}
    strings = []
    for index, (name, rows) in enumerate(sheets, 1):
        xml = _sheet_xml(rows)
        if shared:
            import re
            def replace(match):
                strings.append(match.group(2))
                return f'<c r="{match.group(1)}" t="s"><v>{len(strings)-1}</v></c>'
            xml = re.sub(r'<c r="([A-Z]+[0-9]+)" t="inlineStr"><is><t xml:space="preserve">(.*?)</t></is></c>', replace, xml, flags=re.S)
        files[f'xl/worksheets/sheet{index}.xml'] = xml
    if table:
        files['xl/worksheets/_rels/sheet1.xml.rels'] = '<Relationships><Relationship Id="t1" Type="' + relns + '/table" Target="../tables/table1.xml"/></Relationships>'
        files['xl/tables/table1.xml'] = f'<table xmlns="{ns}" ref="A3:B4"><tableColumns><tableColumn id="1" name="Timecode"/><tableColumn id="2" name="Texte"/></tableColumns></table>'
    files['xl/workbook.xml'] = f'<workbook xmlns="{ns}" xmlns:r="{relns}"><sheets>' + ''.join(f'<sheet name="{escape(name)}" sheetId="{i}" r:id="r{i}"/>' for i,(name,rows) in enumerate(sheets,1)) + '</sheets></workbook>'
    files['xl/_rels/workbook.xml.rels'] = '<Relationships>' + ''.join(f'<Relationship Id="r{i}" Target="/xl/worksheets/sheet{i}.xml"/>' for i in range(1,len(sheets)+1)) + '</Relationships>'
    if shared:
        files['xl/sharedStrings.xml'] = f'<sst xmlns="{ns}">' + ''.join(f'<si><t>{s}</t></si>' for s in strings) + '</sst>'
    output = io.BytesIO()
    with zipfile.ZipFile(output,'w') as archive:
        for path,value in files.items():
            archive.writestr(path,value)
    return output.getvalue()


@pytest.mark.parametrize('vendor,shared', [('Numbers',False),('Excel',True),('LibreOffice',False),('Google Sheets',True)])
def test_renamed_shifted_sheet_and_strings(vendor, shared):
    diag = {}
    data = workbook([('Instructions', [['Ne pas importer'], ['Budget', 'Montant'], ['Total', '500']]),
                     (vendor + ' spectacle', [['Titre'], [], [' time\u200bcode ', ' TÉXTE\u00a0', 'Commentaire libre'],
                                              ['18:00:00:01', 'Élodie, à cour ; entrée', 'À conserver']])],shared)
    doc,unknown = import_xlsx(data,diag)
    assert len(doc['cues']) == 1
    assert doc['cues'][0]['timecode'] == '18:00:00:01'
    assert doc['cues'][0]['text'] == 'Élodie, à cour ; entrée'
    assert unknown == ['Commentaire libre']
    assert diag['conduite']['header_row'] == 3
    assert len(diag['sheets']) == 2
    assert diag['conduite_extra_values'][0]['values'][0]['value'] == 'À conserver'


@pytest.mark.parametrize('delimiter', [';', ',', '\t', '|'])
@pytest.mark.parametrize('encoding', ['utf-8','utf-8-sig','utf-16','utf-16-le','utf-16-be','cp1252'])
def test_csv_encodings_separators_and_preamble(delimiter,encoding):
    diag = {}
    import csv
    out = io.StringIO()
    out.write('Spectacle de rentrée\n\n')
    writer = csv.writer(out,delimiter=delimiter)
    writer.writerow(['Time code','Texte / action','Notes'])
    writer.writerow(['00:01:02:03','Élodie, retour ; scène','ligne 1\nligne 2'])
    doc,unknown = import_csv(out.getvalue().encode(encoding),diag)
    assert doc['cues'][0]['text'] == 'Élodie, retour ; scène'
    assert doc['cues'][0]['notes'] == 'ligne 1\nligne 2'
    assert diag['separator'] == delimiter
    assert diag['conduite']['header_row'] == 3
    assert not unknown


def test_table_export_headers_without_sheet_header_cells():
    diag = {}
    doc,_ = import_xlsx(workbook([('Tableau 1',[['Titre'],[],['',''],['00:00:00:02','Annonce']])],table=True),diag)
    assert doc['cues'][0]['text'] == 'Annonce'
    assert diag['conduite']['header_row'] == 3


@pytest.mark.parametrize('data', [b'TC;TEXTE;Texte\n;A;B\n', b'TC;TEXTE\n;A\nTC;TEXTE\n;B\n'])
def test_duplicate_or_multiple_headers_rejected(data):
    with pytest.raises(BuilderImportError):
        import_csv(data)


def test_ambiguous_workbook_rejected_with_candidates():
    with pytest.raises(BuilderImportError) as exc:
        import_xlsx(workbook([('Conduite',[['TC','TEXTE'],['','A']]),('Copie',[['TC','TEXTE'],['','B']])]))
    assert len(exc.value.diagnostics['conduite_candidates']) == 2


def test_missing_columns_diagnostics():
    with pytest.raises(BuilderImportError) as exc:
        import_csv(b'Titre\nTC;Notes\n00:00:00:01;Hello\n')
    assert exc.value.diagnostics['conduite_candidates'][0]['missing_columns'] == ['TEXTE']
    assert exc.value.diagnostics['format'] == 'CSV'


def test_invalid_business_boolean_not_coerced():
    with pytest.raises(BuilderImportError,match='TRUE/FALSE'):
        import_csv(b'TC;TEXTE;FOH\n;Annonce;peut-etre\n')


def test_unlabelled_values_rejected():
    with pytest.raises(BuilderImportError, match='sans en-tête'):
        import_csv(b'TC;TEXTE\n;Annonce;non nomme\n')


def test_excel_separator_directive():
    diag = {}
    doc,_ = import_csv(b'sep=;\r\nTC;TEXTE\r\n;Annonce\r\n',diag)
    assert doc['cues'][0]['text'] == 'Annonce'
    assert diag['separator_directive'] == 'sep=;'


@pytest.mark.parametrize('row', ['00:99:00:00;Annonce', ';'])
def test_invalid_tc_or_missing_text_rejected(row):
    # A row containing a number must not be discarded as an empty spreadsheet row.
    with pytest.raises(BuilderImportError,match='Document Builder non valide'):
        import_csv(('TC;TEXTE;#\n' + row + ';1\n').encode())


def test_additional_values_survive_save_reload(tmp_path):
    from showcue_builder import save_builder_document, load_builder_document
    doc, unknown = import_csv('TC;TEXTE;Détail libre\n;Annonce;mémoire originale\n'.encode())
    assert unknown == ['Détail libre']
    path = tmp_path / 'builder.json'
    save_builder_document(path,doc)
    loaded = load_builder_document(path)
    assert loaded['import_source']['tables'][0]['rows'][0][2] == 'mémoire originale'


def test_invalid_distribution_equipment_rejected():
    data = ('TC;TEXTE\n;Annonce\n[DISTRIBUTION]\nRôle;Artiste;Actif;Équipement 1 Type;Équipement 1 Valeur\n'
            'MENEUSE;Élodie;TRUE;MICRO;\n')
    with pytest.raises(BuilderImportError,match='champ value vide'):
        import_csv(data.encode())


def rewrite_zip(payload, transform):
    out = io.BytesIO()
    with zipfile.ZipFile(io.BytesIO(payload)) as archive, zipfile.ZipFile(out,'w') as target:
        for name in archive.namelist():
            target.writestr(name,transform(name,archive.read(name).decode()))
    return out.getvalue()


def test_typed_cells_and_cached_formula_preserve_values():
    payload = workbook([('Conduite',[['#','TC','TEXTE','FOH'],['0','00:00:00:01','Annonce','1']])])
    def transform(name,xml):
        if name.endswith('sheet1.xml'):
            xml = xml.replace('<c r="A2" t="inlineStr"><is><t xml:space="preserve">0</t></is></c>', '<c r="A2"><v>0</v></c>')
            xml = xml.replace('<c r="D2" t="inlineStr"><is><t xml:space="preserve">1</t></is></c>', '<c r="D2" t="b"><v>1</v></c>')
            xml = xml.replace('<c r="C2" t="inlineStr"><is><t xml:space="preserve">Annonce</t></is></c>', '<c r="C2" t="str"><f>"Annonce"</f><v>Annonce</v></c>')
        return xml
    doc,_ = import_xlsx(rewrite_zip(payload,transform))
    assert doc['cues'][0]['number'] == '0'
    assert doc['cues'][0]['foh'] is True
    assert doc['cues'][0]['text'] == 'Annonce'


def test_error_on_irrelevant_sheet_does_not_block_conduite():
    payload = workbook([('Budget',[['Montant'],['5']]),('Déroulement',[['TC','TEXTE'],['','Annonce']])])
    def transform(name,xml):
        return xml.replace('<c r="A2" t="inlineStr"><is><t xml:space="preserve">5</t></is></c>', '<c r="A2" t="e"><v>#DIV/0!</v></c>') if name.endswith('sheet1.xml') else xml
    diag = {}
    doc,_ = import_xlsx(rewrite_zip(payload,transform),diag)
    assert doc['cues'][0]['text'] == 'Annonce'
    assert diag['ignored_sheets'] == ['Budget']
    assert 'Budget' in diag['cell_errors']


def test_uncached_formula_on_chosen_sheet_rejected():
    payload = workbook([('Conduite',[['TC','TEXTE'],['','Annonce']])])
    def transform(name,xml):
        return xml.replace('<c r="B2" t="inlineStr"><is><t xml:space="preserve">Annonce</t></is></c>', '<c r="B2"><f>"Annonce"</f></c>') if name.endswith('sheet1.xml') else xml
    with pytest.raises(BuilderImportError,match='sans résultat enregistré : B2'):
        import_xlsx(rewrite_zip(payload,transform))


def test_distribution_with_missing_column_is_not_discarded():
    with pytest.raises(BuilderImportError,match='colonnes obligatoires RÔLE, ARTISTE'):
        import_csv('TC;TEXTE\n;Annonce\n[DISTRIBUTION]\nRôle;Notes\nAVA;test\n'.encode())


def test_phase_and_section_are_distinct_original_values():
    doc,_ = import_csv('TC;TEXTE;Phase;Section\n;Annonce;PRÉ-SHOW;Partie parlée\n'.encode())
    assert doc['cues'][0]['phase'] == 'PRÉ-SHOW'
    assert doc['cues'][0]['section'] == 'Partie parlée'


def test_malformed_csv_reports_syntax_error():
    with pytest.raises(BuilderImportError,match='Syntaxe CSV invalide') as exc:
        import_csv(b'TC;TEXTE\n;"Annonce\n')
    assert exc.value.diagnostics['csv_syntax_errors']


def test_strict_ooxml_namespace():
    payload = workbook([('Conduite',[['TC','TEXTE'],['','Annonce']])],shared=True)
    payload = rewrite_zip(payload,lambda name,xml: xml.replace('http://schemas.openxmlformats.org/spreadsheetml/2006/main','http://purl.oclc.org/ooxml/spreadsheetml/main').replace('http://schemas.openxmlformats.org/officeDocument/2006/relationships','http://purl.oclc.org/ooxml/officeDocument/relationships'))
    doc,_ = import_xlsx(payload)
    assert doc['cues'][0]['text'] == 'Annonce'


def test_invalid_shared_string_index_reports_sheet_and_cell():
    payload = workbook([('Mon spectacle',[['TC','TEXTE'],['','Annonce']])],shared=True)
    def transform(name,xml):
        import re
        return re.sub(r'<c r="B2" t="s"><v>\d+</v></c>', '<c r="B2" t="s"><v>-1</v></c>', xml) if name.endswith('sheet1.xml') else xml
    with pytest.raises(BuilderImportError,match='cellule B2, index -1') as exc:
        import_xlsx(rewrite_zip(payload,transform))
    assert exc.value.diagnostics['sheet'] == 'Mon spectacle'


def test_nonempty_values_under_blank_column_are_rejected():
    with pytest.raises(BuilderImportError,match='colonnes sans en-tête'):
        import_csv(b'TC;TEXTE;;\n;Annonce;donnee non nommee;\n')


def test_table_header_conflict_is_explicit():
    payload = workbook([('Conduite',[['Titre'],[],['TC','Description différente'],['','Annonce']])],table=True)
    with pytest.raises(BuilderImportError,match='tableau contradictoire'):
        import_xlsx(payload)


def test_physical_line_numbers_with_multiline_preamble():
    diag = {}
    doc,_ = import_csv(b'"Titre\nsuite du titre"\nTC;TEXTE\n;Annonce\n',diag)
    assert diag['conduite']['header_row'] == 3
    assert diag['conduite']['row_numbers'][1] == 4
    assert doc['cues'][0]['text'] == 'Annonce'
