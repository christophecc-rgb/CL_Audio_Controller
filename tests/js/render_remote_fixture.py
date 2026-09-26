import ast,sys,json
from pathlib import Path
r=Path(sys.argv[1]);s=Path(sys.argv[2]);tree=ast.parse((r/'app.py').read_text());f=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='decorate_remote_page_html')
class R:
 def __init__(self,t):self.t=t;self.headers={'Content-Type':'text/html'}
 def get_data(self,as_text=False):return self.t if as_text else self.t.encode()
 def set_data(self,t):self.t=t
class Q:path='/'
n={'request':Q(),'CL_AUDIO_REMOTE_SUBTITLES':{'/':'Session','/ab':'A/B','/arrangement':'Arrangement'}}
exec(compile(ast.Module(body=[f],type_ignores=[]),'decoration','exec'),n)
results={}
for route,file in [('/','index'),('/ab','ab'),('/arrangement','arrangement')]:
 Q.path=route;p=s/'templates'/f'{file}.html';p=p if p.exists() else r/'templates'/f'{file}.html';results[route]=n['decorate_remote_page_html'](R(p.read_text())).t
print(json.dumps(results))
