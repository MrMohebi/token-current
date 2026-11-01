"""Black-box synthetic-log tests for the actual agent and relay processes."""
import datetime
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import unittest
import urllib.request

ROOT = Path(__file__).resolve().parents[2]

def port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]

def request(url, token='', body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, headers={'Authorization': 'Bearer '+token, 'Content-Type': 'application/json'})
    with urllib.request.urlopen(r, timeout=3) as response:
        raw = response.read()
        return json.loads(raw) if raw else None

def eventually(fn, timeout=12):
    deadline = time.monotonic()+timeout
    last = None
    while time.monotonic() < deadline:
        try:
            result = fn()
            if result:
                return result
        except (OSError, ValueError, KeyError, IndexError) as error:
            last = error
        time.sleep(.2)
    raise AssertionError(f'Condition did not become true: {last}')

def matching(fetch, predicate):
    value = fetch()
    return value if predicate(value) else None

class NetworkEndToEnd(unittest.TestCase):
    def test_real_agent_direct_and_relay_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            d = Path(directory)
            suffix = '.exe' if os.name == 'nt' else ''
            for name in ('agent', 'relay'):
                subprocess.run(['go','build','-o',str(d/(name+suffix)),f'./cmd/token-current-{name}'], cwd=ROOT/'network', check=True)
            agent, relay = str(d/('agent'+suffix)), str(d/('relay'+suffix))
            state, config = d/'relay.json', d/'agent.json'
            relay_url, agent_url = f'http://127.0.0.1:{port()}', f'http://127.0.0.1:{port()}'
            subprocess.run([relay,'init','--state',str(state)],check=True,stdout=subprocess.DEVNULL)
            admin = json.loads(state.read_text())['adminToken']
            processes=[]
            def launch(args):
                p=subprocess.Popen(args,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL);processes.append(p);return p
            try:
                rp=launch([relay,'serve','--state',str(state),'--listen',relay_url.split('//')[1]])
                eventually(lambda: request(relay_url+'/healthz'))
                device=request(relay_url+'/api/v1/instances',admin,{'name':'Synthetic Linux','platform':'linux'})
                home=d/'claude';logs=home/'projects'/'project';logs.mkdir(parents=True)
                log=logs/'session.jsonl'
                def line(id, count):
                    return json.dumps({'type':'assistant','timestamp':datetime.datetime.now(datetime.timezone.utc).isoformat(),'requestId':'request','message':{'id':id,'usage':{'input_tokens':count,'output_tokens':10,'cache_read_input_tokens':30,'cache_creation_input_tokens':20}}})+'\n'
                log.write_text(line('first',100))
                subprocess.run([agent,'init','--config',str(config),'--listen',agent_url.split('//')[1],'--claude-home',str(home),'--codex-home',str(d/'codex')],check=True,stdout=subprocess.DEVNULL)
                read_token=json.loads(config.read_text())['readToken']
                subprocess.run([agent,'configure','--config',str(config),'--relay',relay_url],input=device['token']+'\n',text=True,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
                def start_agent(): return launch([agent,'run','--config',str(config)])
                ap=start_agent()
                def direct(): return request(agent_url+'/api/v1/snapshot',read_token)
                sample=eventually(lambda: matching(direct, lambda s: s['providers']['claude']['totals']['input']==150))
                self.assertEqual(sample['providers']['claude']['rate'],0)
                with log.open('a') as f: f.write(line('second',200))
                def relay_sample(): return request(relay_url+'/api/v1/mesh',admin)['machines'][0]
                sample=eventually(lambda: matching(relay_sample, lambda s: s.get('snapshot') and s['snapshot']['providers']['claude']['totals']['input']==400))
                self.assertEqual(sample['snapshot']['providers']['claude']['rate'],26)
                self.assertTrue(sample['online'])
                ap.terminate();ap.wait(timeout=5)
                ap=start_agent()
                sample=eventually(lambda: matching(direct, lambda s: s['sequence']>0))
                self.assertEqual(sample['providers']['claude']['totals']['input'],400)
                self.assertEqual(sample['providers']['claude']['rate'],0)
                rp.terminate();rp.wait(timeout=5)
                launch([relay,'serve','--state',str(state),'--listen',relay_url.split('//')[1]])
                eventually(lambda: relay_sample()['snapshot']['providers']['claude']['totals']['input']==400)
                # Read tokens must not grant relay management access.
                with self.assertRaises(urllib.error.HTTPError) as error:
                    request(relay_url+'/api/v1/mesh',device['token'])
                self.assertEqual(error.exception.code,401)
            finally:
                for p in reversed(processes):
                    if p.poll() is None: p.terminate()
                for p in processes:
                    try: p.wait(timeout=5)
                    except subprocess.TimeoutExpired: p.kill();p.wait()

    @unittest.skipIf(os.name == 'nt', 'Linux installer and POSIX CLI fixture')
    def test_linux_update_and_tailscale_serve_helper(self):
        import shutil
        with tempfile.TemporaryDirectory() as directory:
            d=Path(directory);stage=d/'archive';stage.mkdir()
            binary=stage/'token-current-agent'
            subprocess.run(['go','build','-o',str(binary),'./cmd/token-current-agent'],cwd=ROOT/'network',check=True)
            shutil.copy(ROOT/'network/install/install.sh',stage/'install.sh')
            env=dict(os.environ, XDG_CONFIG_HOME=str(d/'config'), TOKEN_CURRENT_BIN_DIR=str(d/'bin'))
            subprocess.run(['bash',str(stage/'install.sh'),'--no-service'],env=env,check=True,stdout=subprocess.DEVNULL)
            config=d/'config'/'Token Current'/'agent.json';original=json.loads(config.read_text())
            original['listen']=f'127.0.0.1:{port()}'
            config.write_text(json.dumps(original))
            installed=d/'bin'/'token-current-agent'
            p=subprocess.Popen([str(installed),'run'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            try:
                eventually(lambda: request('http://'+original['listen']+'/healthz'))
                subprocess.run(['bash',str(stage/'install.sh'),'--no-service'],env=env,check=True,stdout=subprocess.DEVNULL)
                self.assertEqual(json.loads(config.read_text())['readToken'],original['readToken'])
                self.assertIsNone(p.poll(), 'Updating killed the running process')
            finally:
                p.terminate();p.wait(timeout=5)
            # Exercise Tailscale setup without modifying a real tailnet.
            original['listen']='127.0.0.1:8790';config.write_text(json.dumps(original))
            fake=d/'bin'/'tailscale'
            fake.write_text("#!/usr/bin/env python3\nimport json,os,sys\nfrom pathlib import Path\na=sys.argv[1:]\nif a==['status','--json']: print(json.dumps({'BackendState':'Running','Self':{'DNSName':'fixture.tailnet.ts.net.'},'Peer':{}}))\nelif a==['serve','status','--json']: print(Path(os.environ['SERVE_FIXTURE']).read_text())\nelse: Path(os.environ['SERVE_CALL']).write_text(json.dumps(a))\n")
            fake.chmod(0o755);fixture=d/'serve.json';call=d/'call.json';fixture.write_text('{}')
            env.update(PATH=str(d/'bin')+os.pathsep+env['PATH'], SERVE_FIXTURE=str(fixture), SERVE_CALL=str(call))
            result=subprocess.run([str(installed),'tailscale'],env=env,check=True,capture_output=True,text=True)
            self.assertIn('https://fixture.tailnet.ts.net:8790',result.stdout)
            self.assertEqual(json.loads(call.read_text()),['serve','--bg','--https=8790','http://127.0.0.1:8790'])
            call.unlink();fixture.write_text('{"Web":{"fixture:8790":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:9000"}}}}}')
            result=subprocess.run([str(installed),'tailscale'],env=env,capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0);self.assertFalse(call.exists(),'Overwrote another Serve mapping')

if __name__ == '__main__': unittest.main()
