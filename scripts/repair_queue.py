#!/usr/bin/env python3
"""Local failure outbox. An authorized agent connector delivers and acknowledges reports."""
import argparse
import fcntl
import hashlib
import json
import os
import re
import unicodedata
from datetime import datetime, timezone
from pathlib import Path


def now():
    return datetime.now(timezone.utc).isoformat()


def epoch(value):
    try:
        return datetime.fromisoformat(str(value).replace('Z', '+00:00')).timestamp()
    except (ValueError, TypeError):
        return 0


def write(path, value):
    tmp = path.with_name(path.name + '.tmp-' + str(os.getpid()))
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def clean(value):
    if isinstance(value, dict):
        return {k: clean(v) for k, v in value.items()}
    if isinstance(value, list):
        return [clean(v) for v in value]
    if isinstance(value, str):
        return re.sub(r'(?i)(?:sk-[a-z0-9_-]{20,}|gh[pousr]_[a-z0-9]{20,}|Bearer\s+\S+)', '[redacted]', value)
    return value


def classify(error):
    text = error.casefold()
    if any(k in text for k in ('accessibility permission', 'microphone permission', 'speech permission', 'screen recording permission', 'macos permission', '-1743')):
        return 'permission', 'The error explicitly names a macOS permission. Confirm its actual state.'
    if any(k in text for k in ('did not show', 'receipt', 'transcript', 'not visible', 'could not confirm', 'не подтверд')):
        return 'observation', 'The error concerns observing the target or confirming delivery.'
    if any(k in text for k in ('exit', 'code 1', 'кодом 1', 'missing', 'not found', 'no such file', 'calibration', 'paint.sh', 'timed out', 'timeout')):
        return 'tool', 'The error reports a process, tool or timeout failure.'
    if any(k in text for k in ('bare promise', 'without action', 'claimed success')):
        return 'reasoning', 'The error explicitly reports an action/completion contract violation.'
    return 'unknown', 'No permission or root cause is established by this report.'


def normalized(value):
    return unicodedata.normalize('NFC', str(value)).strip()


def incidents(root):
    return [(p, json.loads(p.read_text())) for p in sorted((root / 'incidents').glob('*.json'))]


def ingest(root, config):
    state_path = root / 'cursor.json'
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    for name in ('journal.jsonl', 'problems.jsonl'):
        path = Path(config['logs']) / name
        if not path.exists():
            continue
        stat = path.stat()
        cursor = state.get(name, {})
        offset = cursor.get('offset', 0) if cursor.get('inode') == stat.st_ino and stat.st_size >= cursor.get('offset', 0) else 0
        with path.open('rb') as stream:
            stream.seek(offset)
            while True:
                start = stream.tell()
                line = stream.readline()
                if not line:
                    break
                if not line.endswith(b'\n'):
                    stream.seek(start)
                    break
                try:
                    entry = json.loads(line)
                except (ValueError, UnicodeDecodeError):
                    state.setdefault('warnings', []).append({'file': name, 'offset': start, 'error': 'Malformed complete log record'})
                    continue
                at = entry.get('epoch') or epoch(entry.get('time'))
                if at < config['since']:
                    continue
                error = entry.get('error') or entry.get('problem') or ''
                outcome = entry.get('outcome', 'reported_failure')
                if name == 'journal.jsonl' and outcome not in ('failed', 'error', 'rejected'):
                    continue
                if not error:
                    error = entry.get('answer') or 'The command failed without a recorded explanation.'
                command = normalized(entry.get('command', ''))
                related = None
                if name == 'problems.jsonl':
                    for p, incident in incidents(root):
                        end = incident['epoch'] + incident.get('seconds', 0)
                        if command == incident['command'] and incident['epoch'] - 1 <= at <= end + 3:
                            related = (p, incident)
                            break
                if related:
                    p, incident = related
                    errors = incident.setdefault('related_errors', [])
                    if clean(error) not in errors:
                        errors.append(clean(error))
                        if incident['category'] == 'unknown':
                            incident['category'], incident['classification_evidence'] = classify(error)
                        write(p, incident)
                    continue
                identifier = hashlib.sha256((str(at) + '\n' + command + '\n' + name).encode()).hexdigest()[:20]
                p = root / 'incidents' / (identifier + '.json')
                if p.exists():
                    continue
                category, basis = classify(error)
                report = {'id': identifier, 'marker': '[Conductor repair ' + identifier + ']',
                          'status': 'queued', 'created_at': now(), 'epoch': at, 'source_time': entry.get('time'),
                          'command': command, 'error': error, 'outcome': outcome, 'seconds': entry.get('seconds', 0),
                          'category': category, 'classification_evidence': basis, 'owner': config['owner'],
                          'actual': {k: entry[k] for k in ('answer', 'check', 'code_actions', 'jev_actions', 'brain_model', 'source', 'frontmost_app') if k in entry},
                          'source_file': str(path), 'evidence': [], 'related_errors': []}
                write(p, clean(report))
            state[name] = {'inode': stat.st_ino, 'offset': stream.tell()}
    write(state_path, state)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path.home() / 'Library/Application Support/ai.conductor.public/RepairQueue')
    sub = parser.add_subparsers(dest='command', required=True)
    init = sub.add_parser('init')
    init.add_argument('--owner', required=True)
    init.add_argument('--coordinator', required=True)
    init.add_argument('--since', required=True, help='ISO timestamp: ignore failures before activation')
    init.add_argument('--logs', type=Path, default=Path.home() / 'Library/Application Support/ai.conductor.public/Logs')
    sub.add_parser('sync')
    listing = sub.add_parser('list')
    listing.add_argument('--all', action='store_true')
    show = sub.add_parser('show')
    show.add_argument('id')
    mark = sub.add_parser('mark')
    mark.add_argument('id')
    mark.add_argument('state', choices=('dispatching', 'dispatched', 'received', 'repairing', 'awaiting_verification', 'waiting_user', 'delivery_uncertain', 'closed'))
    mark.add_argument('--evidence', required=True)
    mark.add_argument('--owner', help='Transfer ownership explicitly, preserving the incident and evidence.')
    mark.add_argument('--category', choices=('permission', 'tool', 'observation', 'reasoning', 'unknown'))
    args = parser.parse_args()
    root = args.root
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(root, 0o700)
    (root / 'incidents').mkdir(exist_ok=True, mode=0o700)
    lock = root / '.lock'
    with lock.open('a') as handle:
        os.chmod(lock, 0o600)
        fcntl.flock(handle, fcntl.LOCK_EX)
        config_path = root / 'config.json'
        if args.command == 'init':
            if config_path.exists():
                parser.error('Queue already configured; inspect its config instead of resetting existing state.')
            since = epoch(args.since)
            if not since:
                parser.error('A valid activation timestamp is required.')
            write(config_path, {'owner': args.owner, 'coordinator': args.coordinator, 'host': 'local', 'since': since, 'logs': str(args.logs)})
        else:
            if not config_path.exists():
                parser.error('Run init once before processing failures.')
            config = json.loads(config_path.read_text())
            if args.command == 'sync':
                ingest(root, config)
            elif args.command == 'show':
                if not re.fullmatch(r'[0-9a-f]{20}', args.id):
                    parser.error('Invalid incident id.')
                print((root / 'incidents' / (args.id + '.json')).read_text())
                return
            elif args.command == 'mark':
                if not re.fullmatch(r'[0-9a-f]{20}', args.id) or not args.evidence.strip():
                    parser.error('A valid incident id and concrete evidence are required.')
                p = root / 'incidents' / (args.id + '.json')
                incident = json.loads(p.read_text())
                incident['status'] = args.state
                if args.owner:
                    incident['owner'] = args.owner
                if args.category:
                    incident['category'] = args.category
                    incident['classification_evidence'] = args.evidence
                incident['updated_at'] = now()
                incident['evidence'].append({'state': args.state, 'at': now(), 'text': args.evidence})
                write(p, incident)
        rows = [{'id': d['id'], 'status': d['status'], 'category': d['category'], 'command': d['command'], 'owner': d['owner'], 'report': str(p)}
                for p, d in incidents(root) if getattr(args, 'all', False) or d['status'] != 'closed']
        print(json.dumps(rows, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
