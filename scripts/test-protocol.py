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
 send('hello',features=['actions-v1','panels-v1','dashboard-v1','diagrams-v1'])
 ready=wait_for(lambda m:m['type']=='ready');assert 'actions-v1' in ready['features']
 snap=wait_for(lambda m:m['type']=='snapshot')['snapshot']
 assert snap['panels'][0]['diagrams'][0]['width']/snap['panels'][0]['diagrams'][0]['height']==16/9
 assert len(snap['activity'])<=100
 request=str(uuid.uuid4())
 send('bus',bus=dict(operation='execute',requestID=request,address=dict(plugin=plugin,name='set_volume'),values=dict(device='invalid',volume=-1)))
 result=wait_for(lambda m:m['type']=='bus' and m.get('bus',{}).get('requestID','').lower()==request.lower())
 assert result['bus']['update']['phase']=='failed'
 print('PASS: handshake, 16:9 snapshot, status line, invalid action rejected without a write.')
finally:
 p.stdin.close()
 try:p.wait(timeout=3)
 except subprocess.TimeoutExpired:p.terminate();p.wait(timeout=3)
