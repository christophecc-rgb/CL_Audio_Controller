"""Integration check for the native monitor's real report writer (macOS)."""
import argparse,csv,json,pathlib,subprocess,tempfile
p=argparse.ArgumentParser();p.add_argument('binary',type=pathlib.Path);args=p.parse_args()
with tempfile.TemporaryDirectory(prefix='cl-performance-report-') as output:
    subprocess.run([str(args.binary.resolve()),'--self-test-report',output],check=True)
    folder=pathlib.Path(output);log=next(folder.glob('*.jsonl'))
    samples=[json.loads(line) for line in log.read_text().splitlines()]
    assert len(samples)>=3
    assert samples[0]['network_rx_bytes']==samples[0]['network_tx_bytes']==0
    assert all(s['interval_seconds']>=0 for s in samples)
    assert all('network_interfaces_delta' in s and 'telemetry_status' in s for s in samples)
    with log.with_suffix('.csv').open() as f:rows=list(csv.DictReader(f))
    assert len(rows)==len(samples)
    summary=log.with_suffix('.txt').read_text()
    assert 'PÉRIMÈTRE ET LIMITES' in summary and 'Réseau PAR INTERFACE' in summary
    assert 'pas un décalage audio' in summary
    print('PASS: CSV, JSONL, résumé, premier échantillon réseau et couverture des mesures.')
