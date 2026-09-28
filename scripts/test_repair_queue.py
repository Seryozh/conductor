"""Offline regression checks for delivery deduplication and durable failure state."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('repair_queue', Path(__file__).with_name('repair_queue.py'))
queue = importlib.util.module_from_spec(spec)
spec.loader.exec_module(queue)


class OutboxTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name) / 'queue'
        (self.root / 'incidents').mkdir(parents=True)
        self.logs = Path(self.tmp.name) / 'logs'
        self.logs.mkdir()
        self.config = {'logs': str(self.logs), 'owner': 'owned-repair-task', 'since': 100}

    def tearDown(self):
        self.tmp.cleanup()

    def records(self, name, records):
        (self.logs / name).write_text(''.join(json.dumps(r) + '\n' for r in records))

    def test_only_new_failures_and_repeat_sync_are_deduplicated(self):
        self.records('journal.jsonl', [
            {'epoch': 99, 'command': 'old', 'outcome': 'failed', 'error': 'old'},
            {'epoch': 100, 'command': 'stop', 'outcome': 'cancelled'},
            {'epoch': 101, 'command': 'done', 'outcome': 'done'},
            {'epoch': 102, 'command': 'draw', 'outcome': 'failed', 'error': 'failed', 'seconds': 4}])
        self.records('problems.jsonl', [{'time': '1970-01-01T00:01:46Z', 'command': 'draw', 'problem': 'paint.sh exit 1'}] * 3)
        queue.ingest(self.root, self.config)
        queue.ingest(self.root, self.config)
        rows = queue.incidents(self.root)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0][1]['category'], 'tool')
        self.assertEqual(rows[0][1]['related_errors'], ['paint.sh exit 1'])
        self.assertEqual(rows[0][0].stat().st_mode & 0o777, 0o600)

    def test_partial_record_is_not_lost_and_closed_case_is_not_reopened(self):
        p = self.logs / 'journal.jsonl'
        row = json.dumps({'epoch': 105, 'command': 'send', 'outcome': 'error', 'error': 'no receipt'})
        p.write_text(row[:20])
        queue.ingest(self.root, self.config)
        self.assertEqual(queue.incidents(self.root), [])
        with p.open('a') as f:
            f.write(row[20:] + '\n')
        queue.ingest(self.root, self.config)
        case_path, case = queue.incidents(self.root)[0]
        case['status'] = 'closed'
        queue.write(case_path, case)
        p.write_text(row + '\n')
        queue.ingest(self.root, self.config)
        self.assertEqual(queue.incidents(self.root)[0][1]['status'], 'closed')

    def test_rotation_new_case_and_secret_redaction(self):
        self.records('journal.jsonl', [{'epoch': 102, 'command': 'x', 'outcome': 'error', 'error': 'failed sk-' + 'A' * 30}])
        queue.ingest(self.root, self.config)
        p = self.logs / 'journal.jsonl'
        p.rename(self.logs / 'old.jsonl')
        self.records('journal.jsonl', [{'epoch': 103, 'command': 'y', 'outcome': 'error', 'error': 'no receipt'}])
        queue.ingest(self.root, self.config)
        rows = queue.incidents(self.root)
        self.assertEqual(len(rows), 2)
        self.assertNotIn('sk-', ''.join(p.read_text() for p, _ in rows))

    def test_no_visibility_is_not_called_a_permission_failure(self):
        self.assertEqual(queue.classify('Codex did not show thread')[0], 'observation')
        self.assertEqual(queue.classify('missing tool')[0], 'tool')
        self.assertEqual(queue.classify('microphone permission denied')[0], 'permission')
        self.assertEqual(queue.classify('failed, reason unknown')[0], 'unknown')


if __name__ == '__main__':
    unittest.main()
