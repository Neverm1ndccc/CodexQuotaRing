#!/usr/bin/python3
"""Deterministic stdio fixture; no authentication or network access."""
import json,sys,time,os
mode = sys.argv[1] if len(sys.argv)>1 else "normal"
if mode == "--version":
 print("quota-fixture 1.0");sys.exit(0)
initialized=False
notified=False
def scenario():
 if mode == "scenario":
  with open(sys.argv[2]) as f: return json.load(f)
 return {}
for line in sys.stdin:
 msg=json.loads(line); method=msg.get("method"); rid=msg.get("id")
 if method=="initialize":
  data=json.dumps({"id":rid,"result":{"userAgent":"fixture"}})+"\n"
  sys.stdout.write(data[:5]);sys.stdout.flush();time.sleep(.01);sys.stdout.write(data[5:]);sys.stdout.flush()
 elif method=="initialized": initialized=True
 elif not initialized:
  print(json.dumps({"id":rid,"error":{"code":-32002}}),flush=True)
 elif method=="timeout": pass
 elif method=="crash": os._exit(7)
 elif method=="events":
  payload={"rateLimits":{"limitId":"codex","primary":None,"secondary":{"usedPercent":50,"windowDurationMins":10080}}}
  sys.stdout.write(json.dumps({"method":"account/rateLimits/updated","params":payload})+"\n"+json.dumps({"id":rid,"result":{"ok":True}})+"\n");sys.stdout.flush()
 elif method=="account/read":
  state=scenario()
  if not notified:
   print(json.dumps({"method":"account/updated","params":{"authMode":"chatgpt"}}),flush=True);notified=True
  if state.get("loggedOut"):
   print(json.dumps({"id":rid,"result":{"account":None}}),flush=True);continue
  print(json.dumps({"id":rid,"result":{"account":{"type":"chatgpt","email":state.get("email","fixture@example.invalid"),"planType":"free"}}}),flush=True)
 elif method=="account/rateLimits/read":
  current=scenario()
  if current.get("crashOnce") and not current.get("crashed"):
   current["crashed"]=True
   with open(sys.argv[2],"w") as f: json.dump(current,f)
   os._exit(7)
  if current.get("error"):
   print(json.dumps({"id":rid,"error":{"code":-32000}}),flush=True);continue
  print(json.dumps({"id":rid,"result":{"accountId":"fixture-account","ordinaryUsageAllowed":False,"rateLimits":{"limitId":"codex","primary":None,"secondary":{"usedPercent":50,"windowDurationMins":10080}}}}),flush=True)
 elif method=="pid": print(json.dumps({"id":rid,"result":{"pid":os.getpid()}}),flush=True)
 else: print(json.dumps({"id":rid,"result":{"echo":method}}),flush=True)
