"""Offline smoke check executed by the frozen server executable."""
def run():
    import io
    import json
    import tempfile
    from pathlib import Path
    import app as server
    import pypdf
    from pypdf.generic import DictionaryObject, NameObject, DecodedStreamObject
    from cl_transport import load_library
    from showcue_session_archive import export_session, import_session
    with tempfile.TemporaryDirectory() as temporary:
        server.SHOW_CUES_DATA_DIRECTORY = Path(temporary)
        client = server.app.test_client()
        for route in ['/show-info', '/show-info/builder', '/show-info/builder/resources',
                      '/show-info/builder/document', '/show-info/builder/export.xlsx',
                      '/show-info/builder/export.csv', '/assets/paradis%20latin.jpg']:
            response = client.get(route)
            assert response.status_code == 200, (route, response.status_code)
        writer = pypdf.PdfWriter()
        page = writer.add_blank_page(600, 800)
        font = DictionaryObject({NameObject('/Type'): NameObject('/Font'),
                                 NameObject('/Subtype'): NameObject('/Type1'),
                                 NameObject('/BaseFont'): NameObject('/Helvetica')})
        page[NameObject('/Resources')] = DictionaryObject({NameObject('/Font'): DictionaryObject({NameObject('/F1'): writer._add_object(font)})})
        stream = DecodedStreamObject()
        stream.set_data(b'BT /F1 12 Tf 40 700 Td (1 WELCOME IN CABARET) Tj ET')
        page[NameObject('/Contents')] = writer._add_object(stream)
        pdf = io.BytesIO(); writer.write(pdf); pdf.seek(0)
        response = client.post('/show-info/builder/import.pdf', data={'file': (pdf, 'test.pdf')})
        assert response.status_code == 200, response.data
        registry, _, _ = server.ensure_show_cue_storage()
        data = export_session(Path(temporary), registry, registry['active_session_id'])
        updated = import_session(data, Path(temporary), registry)
        assert len(updated['sessions']) == 2
        print(json.dumps({'ok': True, 'pypdf': pypdf.__version__, 'pdf_import': True,
                          'templates_assets': True, 'session_roundtrip': True,
                          'libraries': {c: len(load_library(c, server.CONSOLE_LIBRARY_STORE)['library']) for c in ('cl5', 'ql1')}}))
