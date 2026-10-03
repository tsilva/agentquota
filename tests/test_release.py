"""Exercise release dispatch and publication gates without compiling or publishing."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = Path('.agents/skills/build-release/scripts')


def workflow_script(name):
    lines = (ROOT / '.github/workflows/release.yml').read_text().splitlines()
    start = lines.index('      - name: ' + name)
    start = next(i for i in range(start, len(lines)) if lines[i] == '        run: |') + 1
    script = []
    for line in lines[start:]:
        if line and not line.startswith('          '):
            break
        script.append(line[10:])
    return '\n'.join(script)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / 'repo'
        self.repo.mkdir()
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.log = self.base / 'commands.jsonl'
        self.git_command = shutil.which('git')
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM='1',
                        GIT_AUTHOR_NAME='Release Test', GIT_AUTHOR_EMAIL='test@example.invalid',
                        GIT_COMMITTER_NAME='Release Test', GIT_COMMITTER_EMAIL='test@example.invalid',
                        STUB_LOG=str(self.log), REAL_GIT=self.git_command,
                        GITHUB_ACTIONS='true', GITHUB_REPOSITORY='tsilva/agentquota',
                        GITHUB_OUTPUT=str(self.base / 'outputs'), RELEASE_PUBLISH='true')
        # Record dispatch/API calls and prevent any real compiler or network invocation.
        stub = f'''#!{shutil.which('python3')}
import json, os, pathlib, shutil, subprocess, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['STUB_LOG'], 'a') as f:
    f.write(json.dumps([name, *args]) + '\\n')
if name == 'git':
    if args[0] == 'fetch':
        sys.exit(0)
    sys.exit(subprocess.call([os.environ['REAL_GIT'], *args]))
if name == 'gh':
    if os.environ.get('STUB_GH_ERROR'):
        sys.exit(17)
    if args[:2] == ['repo', 'view']:
        print('tsilva/agentquota')
    elif args[:2] == ['release', 'download']:
        output = pathlib.Path(args[args.index('--dir') + 1])
        output.mkdir()
        for source in pathlib.Path('dist').iterdir():
            shutil.copy2(source, output / source.name)
        if os.environ.get('STUB_CORRUPT_DOWNLOAD'):
            next(output.glob('*.dmg')).write_bytes(b'corrupt download')
    elif args and args[0] == 'api':
        if '--method' in args and os.environ.get('STUB_TAG_CREATE_FAILURE'):
            sys.exit(17)
        if args[1].endswith('/git/ref/heads/main'):
            print(os.environ['RELEASE_SHA'])
        elif '/git/ref/tags/' in args[1]:
            print(os.environ['RELEASE_SHA'])
        elif any('/git/matching-refs/' in x for x in args):
            print(os.environ.get('STUB_TAGS', ''))
        elif any('/releases' in x for x in args):
            print(os.environ.get('STUB_RELEASES', ''))
    sys.exit(0)
if name == 'xcodebuild' and '-showBuildSettings' in args:
    print('MARKETING_VERSION = 1.0')
    sys.exit(0)
sys.exit(91)  # Stop before any compilation, signing or packaging.
'''
        for command in ['git', 'gh', 'xcodebuild', 'codesign', 'ditto', 'hdiutil',
                        'lipo', 'plutil', 'sips', 'xcrun']:
            path = self.bin / command
            path.write_text(stub)
            path.chmod(0o755)
        dest = self.repo / SCRIPTS
        dest.mkdir(parents=True)
        for name in ['build-release.zsh', 'build-release-ci.zsh', 'render-dmg-background.swift']:
            shutil.copy2(ROOT / SCRIPTS / name, dest / name)
        assets = dest.parent / 'assets'
        assets.mkdir()
        shutil.copy2(ROOT / SCRIPTS.parent / 'assets/dmg-layout.DS_Store', assets)
        (self.repo / 'AgentQuota').mkdir()
        (self.repo / 'AgentQuota/App.swift').write_text('// baseline\n')
        self.git('init', '-b', 'main')
        self.commit('Initial app')
        self.git('tag', 'v1.2.3')
        self.sync()

    def git(self, *args):
        return subprocess.check_output([self.git_command, *args], cwd=self.repo,
                                       env=self.env, text=True, stderr=subprocess.DEVNULL).strip()

    def commit(self, subject):
        self.git('add', '.')
        self.git('commit', '-m', subject)

    def sync(self):
        self.env['RELEASE_SHA'] = self.git('rev-parse', 'HEAD')
        self.git('update-ref', 'refs/remotes/origin/main', self.env['RELEASE_SHA'])

    def app_change(self, subject):
        (self.repo / 'AgentQuota/App.swift').write_text('// changed\n')
        self.commit(subject)
        self.sync()

    def run_script(self, name, *args):
        return subprocess.run(['zsh', str(self.repo / SCRIPTS / name), *args],
                              cwd=self.repo, env=self.env, text=True, capture_output=True)

    def commands(self):
        return [json.loads(x) for x in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_dispatch_publication_uses_exact_sha_without_build(self):
        result = self.run_script('build-release.zsh')
        self.assertEqual(result.returncode, 0, result.stderr)
        dispatch = next(x for x in self.commands() if x[:3] == ['gh', 'workflow', 'run'])
        self.assertIn('ref=' + self.env['RELEASE_SHA'], dispatch)
        self.assertIn('publish=true', dispatch)
        self.assertTrue(all(x[0] in ('git', 'gh') for x in self.commands()))

    def test_dry_run_dispatch_disables_publication(self):
        result = self.run_script('build-release.zsh', '--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('publish=false', next(x for x in self.commands() if x[:3] == ['gh', 'workflow', 'run']))

    def test_dispatch_rejects_dirty_tree(self):
        (self.repo / 'uncommitted').write_text('user work')
        result = self.run_script('build-release.zsh', '--dry-run')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('worktree must be clean', result.stderr)
        self.assertFalse(any(x[:3] == ['gh', 'workflow', 'run'] for x in self.commands()))

    def test_dispatch_rejects_unsynchronized_commit(self):
        (self.repo / 'README.md').write_text('local only')
        self.commit('Docs')
        result = self.run_script('build-release.zsh')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('exactly match origin/main', result.stderr)

    def test_dispatch_rejects_manual_version(self):
        result = self.run_script('build-release.zsh', '--version', '9.0.0')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.commands(), [])

    def test_dispatch_stops_on_authentication_failure(self):
        self.env['STUB_GH_ERROR'] = '1'
        self.assertNotEqual(self.run_script('build-release.zsh').returncode, 0)
        self.assertFalse(any(x[:3] == ['gh', 'workflow', 'run'] for x in self.commands()))

    def test_build_helper_rejects_local_execution(self):
        self.env['GITHUB_ACTIONS'] = 'false'
        result = self.run_script('build-release-ci.zsh', str(self.base / 'artifacts'))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('only in GitHub Actions', result.stderr)
        self.assertEqual(self.commands(), [])

    def test_build_helper_rejects_stale_sha(self):
        self.env['RELEASE_SHA'] = '0' * 40
        result = self.run_script('build-release-ci.zsh', str(self.base / 'artifacts'))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('exactly match origin/main', result.stderr)
        self.assertFalse(any(x[0] == 'xcodebuild' for x in self.commands()))

    def test_semantic_version_selection_and_no_local_tag_creation(self):
        for subject, expected in [('fix: correct quota', 'v1.2.4'),
                                  ('feat: new quota', 'v1.3.0'),
                                  ('Add quota view', 'v1.3.0'),
                                  ('feat!: replace protocol', 'v2.0.0')]:
            with self.subTest(subject=subject):
                self.git('reset', '--hard', 'v1.2.3')
                self.app_change(subject)
                result = self.run_script('build-release-ci.zsh', str(self.base / 'artifacts'))
                self.assertEqual(result.returncode, 91, result.stderr)
                self.assertIn('Automatically selected ' + expected, result.stdout)
                self.assertEqual(self.git('tag', '--list'), 'v1.2.3')
                shutil.rmtree(self.base / 'artifacts', ignore_errors=True)

    def test_first_release_normalizes_marketing_version(self):
        self.git('tag', '-d', 'v1.2.3')
        result = self.run_script('build-release-ci.zsh', str(self.base / 'artifacts'))
        self.assertEqual(result.returncode, 91, result.stderr)
        self.assertIn('Automatically selected v1.0.0', result.stdout)

    def test_documentation_only_changes_cannot_publish(self):
        (self.repo / 'README.md').write_text('docs')
        self.commit('feat: documentation')
        self.sync()
        result = self.run_script('build-release-ci.zsh', str(self.base / 'artifacts'))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('No releasable app changes', result.stderr)
        self.assertFalse(any(x[0] == 'xcodebuild' for x in self.commands()))

    def test_validation_can_rebuild_latest_version_without_new_release(self):
        self.env['RELEASE_PUBLISH'] = 'false'
        result = self.run_script('build-release-ci.zsh', str(self.base / 'artifacts'))
        self.assertEqual(result.returncode, 91, result.stderr)
        self.assertIn('Automatically selected v1.2.3', result.stdout)
        self.assertFalse(any(x[0] == 'gh' for x in self.commands()))

    def test_github_api_failure_prevents_build(self):
        self.app_change('fix: quota')
        self.env['STUB_GH_ERROR'] = '1'
        result = self.run_script('build-release-ci.zsh', str(self.base / 'artifacts'))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(x[0] == 'xcodebuild' for x in self.commands()))

    def candidate(self):
        import hashlib
        self.env.update(GH_REPO='tsilva/agentquota', RELEASE_VERSION='1.2.4', RELEASE_TAG='v1.2.4')
        dist = self.repo / 'dist'
        dist.mkdir()
        artifact = dist / 'AgentQuota-1.2.4-macOS-arm64.dmg'
        artifact.write_bytes(b'validated candidate')
        checksum = hashlib.sha256(artifact.read_bytes()).hexdigest()
        artifact.with_suffix('.dmg.sha256').write_text(checksum + '  ' + artifact.name + '\n')
        return artifact

    def candidate_gate(self):
        # macOS has shasum; use it to emulate the runner's GNU sha256sum.
        path = self.bin / 'sha256sum'
        path.write_text('#!/bin/sh\nexec shasum -a 256 "$@"\n')
        path.chmod(0o755)
        return subprocess.run(['bash', '-c', workflow_script('Verify candidate identity and unused release state')],
                              cwd=self.repo, env=self.env, text=True, capture_output=True)

    def test_valid_candidate_passes_publication_gate(self):
        self.candidate()
        result = self.candidate_gate()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_changed_candidate_fails_publication_gate(self):
        self.candidate().write_bytes(b'tampered')
        self.assertNotEqual(self.candidate_gate().returncode, 0)

    def test_extra_candidate_file_fails_publication_gate(self):
        self.candidate()
        (self.repo / 'dist/unexpected').write_text('extra')
        self.assertNotEqual(self.candidate_gate().returncode, 0)

    def test_existing_tag_fails_publication_gate(self):
        self.candidate()
        self.env['STUB_TAGS'] = 'refs/tags/v1.2.4'
        result = self.candidate_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('tag already exists', result.stderr)

    def test_existing_release_fails_publication_gate(self):
        self.candidate()
        self.env['STUB_RELEASES'] = 'v1.2.4'
        result = self.candidate_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Release already exists', result.stderr)

    def test_api_failure_fails_publication_gate(self):
        self.candidate()
        self.env['STUB_GH_ERROR'] = '1'
        self.assertNotEqual(self.candidate_gate().returncode, 0)

    def publication_step(self, name):
        return subprocess.run(['bash', '-c', workflow_script(name)],
                              cwd=self.repo, env=self.env, text=True, capture_output=True)

    def test_publication_creates_exact_tag_before_release(self):
        self.candidate()
        result = self.publication_step('Publish GitHub Release and exact validated assets')
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.commands()
        creation = next(x for x in commands if '--method' in x)
        self.assertIn('sha=' + self.env['RELEASE_SHA'], creation)
        self.assertIn('ref=refs/tags/v1.2.4', creation)
        release = next(x for x in commands if x[:3] == ['gh', 'release', 'create'])
        self.assertLess(commands.index(creation), commands.index(release))
        self.assertIn('--verify-tag', release)

    def test_tag_creation_failure_prevents_publication(self):
        self.candidate()
        self.env['STUB_TAG_CREATE_FAILURE'] = '1'
        result = self.publication_step('Publish GitHub Release and exact validated assets')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(x[:3] == ['gh', 'release', 'create'] for x in self.commands()))

    def test_fresh_downloads_match_validated_candidate(self):
        self.candidate()
        self.assertEqual(self.candidate_gate().returncode, 0)
        result = self.publication_step('Verify published tag and fresh release downloads')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_corrupt_fresh_downloads_fail_verification(self):
        self.candidate()
        self.assertEqual(self.candidate_gate().returncode, 0)
        self.env['STUB_CORRUPT_DOWNLOAD'] = '1'
        result = self.publication_step('Verify published tag and fresh release downloads')
        self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
