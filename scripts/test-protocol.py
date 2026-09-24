#!/usr/bin/env python3
"""Read-only live handshake check; invalid writes are rejected before execution."""
import json, subprocess, pathlib, selectors, time, uuid
root=pathlib.Path(__file__).resolve().parents[1]
p=subprocess.Popen([str(root/'build/Ark Module.app/Contents/MacOS/ArkPlugin'),'--neronook-plugin'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
session=str(uuid.uuid4()); plugin='cafe.nero.plugin.ark'
def send(kind,**kwargs):
 p.stdin.write(json.dumps(dict(apiVersion=1,type=kind,pluginID=plugin,session=session,sequence=0,**kwargs))+'\n');p.stdin.flush()
def wait_for(predicate):
 selector=selectors.DefaultSelector();selector.register(p.stdout,selectors.EVENT_READ)
 end=time.monotonic()+20
 try:
  while time.monotonic()<end:
   if selector.select(1):
    line=p.stdout.readline()
    if not line: raise AssertionError('module exited unexpectedly')
    message=json.loads(line)
    assert message['pluginID']==plugin and message['session'].lower()==session.lower()
    if predicate(message): return message
  raise AssertionError('module response deadline')
 finally: selector.close()
try:
 send('hello',features=['actions-v1','panels-v1','dashboard-v1','custom-views-v1','volume-v1'])
 ready=wait_for(lambda m:m['type']=='ready');assert 'actions-v1' in ready['features']
 snap=wait_for(lambda m:m['type']=='snapshot')['snapshot']
 assert len(snap['panels'])==1 and snap['panels'][0]['id']=='monitor'
 assert snap['panels'][0]['customView']['entry']=='monitor/index.html'
 assert len(json.dumps(snap['panels'][0]['customView']['state']).encode())<32768
 assert 'volume-v1' in ready['features']
 assert 'volumeEndpoints' in snap
 assert not snap['actions']
 assert len(snap['activity'])<=100
 request=str(uuid.uuid4())
 send('bus',bus=dict(operation='execute',requestID=request,address=dict(plugin=plugin,name='set_volume'),values=dict(device='invalid',volume=-1)))
 result=wait_for(lambda m:m['type']=='bus' and m.get('bus',{}).get('requestID','').lower()==request.lower())
 assert result['bus']['update']['phase']=='failed'
 volume_request=str(uuid.uuid4())
 send('volumeCommand',volumeCommand=dict(requestID=volume_request,endpointID='invalid-device',operation=dict(setVolume={'_0':0.16}),expiresAt=time.time()+10))
 volume_result=wait_for(lambda m:m['type']=='volumeResult' and m['volumeResult']['requestID'].lower()==volume_request.lower())['volumeResult']
 assert volume_result.get('error') and not volume_result.get('state')
 print('PASS: handshake, single custom monitor view, bounded state, status line, volume negotiation and invalid action/volume targets rejected without a write.')
finally:
 p.stdin.close()
 try:p.wait(timeout=3)
 except subprocess.TimeoutExpired:p.terminate();p.wait(timeout=3)
