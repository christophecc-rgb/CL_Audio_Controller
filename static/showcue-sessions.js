/* Shared by the server page and the desktop bundle (including older servers). */
(async function () {
    if (window.clSessionManager) return;
    window.clSessionManager = true;
    const oldInput = document.getElementById('cl-session-upload');
    if (oldInput) oldInput.closest('details').remove();
    const panel = document.createElement('details');
    panel.className = 'validation';
    panel.open = true;
    panel.innerHTML = '<summary>SHOWS / SESSIONS</summary><label>Show enregistré <select id="cl-saved-sessions"></select></label> <button id="cl-open-session">OUVRIR</button><hr><label>IMPORTER ET OUVRIR UN SHOW <input id="cl-session-upload" type="file" accept=".showcue,.showcue.zip"></label><div id="cl-session-archives"></div><div id="cl-libraries"></div><a href="/show-info/builder/sessions/export">EXPORTER LE SHOW ACTIF</a><div id="cl-import-result" role="status"></div>';
    document.querySelector('header.top').append(panel);
    const output = document.getElementById('cl-import-result');
    const selector = document.getElementById('cl-saved-sessions');
    const request = api;
    let busy = false;
    function message(error) { output.textContent = error.message || String(error); }
    async function registry() { return request('/show-info/sessions'); }
    async function refresh() {
        const data = await registry();
        selector.replaceChildren();
        for (const session of data.sessions) {
            const option = document.createElement('option');
            option.value = session.id; option.textContent = session.name;
            option.selected = session.id === data.active_session_id;
            selector.append(option);
        }
        selector.value = data.active_session_id;
        return data;
    }
    async function recover(current) {
        if (current.document.cues.length || !window.pywebview?.api?.recover_builder) return current;
        const before = await registry();
        if (before.active_session_id !== current.session_id) throw Error('La session active a changé. Rechargez.');
        const response = await fetch('/show-info/builder/sessions/export', {cache: 'no-store'});
        if (!response.ok) throw Error('Impossible de lire la conduite pour restaurer le Builder.');
        const bytes = new Uint8Array(await response.arrayBuffer());
        let binary = '';
        for (let i = 0; i < bytes.length; i += 32768) binary += String.fromCharCode(...bytes.subarray(i, i + 32768));
        const recovered = await window.pywebview.api.recover_builder(btoa(binary), current.document);
        if (!recovered.ok) throw Error(recovered.message);
        if (!recovered.document.cues.length) return current;
        const after = await registry();
        if (after.active_session_id !== current.session_id) throw Error('La session active a changé. Rechargez.');
        return request('/show-info/builder/document', {method: 'PUT', body: JSON.stringify({session_id: current.session_id, document: recovered.document})});
    }
    // Also protect saves sent by an older server page, through its existing API.
    api = async function (url, options = {}) {
        if (url === '/show-info/builder/document' && options.method === 'PUT') {
            const incoming = JSON.parse(options.body);
            if (!incoming.document?.cues?.length) {
                const current = await recover(await request('/show-info/builder/document'));
                if (current.document.cues.length) throw Error('Builder vide refusé : une conduite existe dans cette session.');
            }
        }
        return request(url, options);
    };
    async function openSession(id) {
        await request('/show-info/sessions/' + encodeURIComponent(id) + '/activate', {method: 'POST', body: '{}'});
        location.reload();
    }
    async function importArchive(body) {
        if (busy) return;
        busy = true;
        output.textContent = 'Import du show…';
        try {
            await ready;
            // Never save the currently displayed table as a side effect of importing.
            const result = await request('/show-info/builder/sessions/import', {method: 'POST', body});
            await refresh();
            output.textContent = 'Show importé : ' + result.imported_session.name;
            await openSession(result.imported_session.id);
        } catch (error) { message(error); }
        finally { busy = false; }
    }
    document.getElementById('cl-session-upload').onchange = event => {
        if (!event.target.files.length) return;
        const body = new FormData(); body.append('file', event.target.files[0]);
        const pending = importArchive(body); event.target.value = ''; return pending;
    };
    document.getElementById('cl-open-session').onclick = async () => {
        if (busy) return;
        busy = true;
        try { await ready; await openSession(selector.value); }
        catch (error) { message(error); }
        finally { busy = false; }
    };
    const ready = (async () => {
        await refresh();
        // The desktop bridge reconstructs with the same Python code as the server.
        try {
        const current = await request('/show-info/builder/document');
        const restored = await recover(current);
        if (restored !== current && !preview && (!documentData.cues.length || sessionId === restored.session_id)) {
            sessionId = restored.session_id; documentData = restored.document;
            document.getElementById('session').textContent = sessionId;
            render(); showValidation(restored.validation);
            output.textContent = 'Builder restauré depuis la conduite : ' + restored.document.cues.length + ' cues.';
        }
        } catch (error) {
            message(error); // A failed recovery must not block importing a healthy archive.
        }
    })();
    try {
        await ready;
        const data = await request('/show-info/builder/resources');
        const archives = document.getElementById('cl-session-archives');
        for (const [name, value] of Object.entries(data.libraries || {})) {
            const row = document.createElement('div');
            row.textContent = name.toUpperCase() + ' — ' + value.count + ' entrées — ' + value.source;
            document.getElementById('cl-libraries').append(row);
        }
        for (const item of data.sessions) {
            const row = document.createElement('div'), button = document.createElement('button');
            row.textContent = item.name + ' — ' + item.source + ' ';
            button.textContent = 'IMPORTER ET OUVRIR';
            button.onclick = () => importArchive(JSON.stringify(item));
            row.append(button); archives.append(row);
        }
    } catch (error) { message(error); }
})();
