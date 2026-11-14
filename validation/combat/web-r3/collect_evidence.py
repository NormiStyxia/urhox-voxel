import json, re
from pathlib import Path
p=Path(__file__).resolve().parent
def redact(s):
    return re.sub(r'((?:preview_login|access_token|token)=)[^&\s,"\\\]]+',r"\1[REDACTED]",s,flags=re.I)
for evidence in p.iterdir():
    if evidence.suffix in (".json",".jsonl",".log"):
        evidence.write_text(redact(evidence.read_text()))
src=Path(".maker/logs/runtime/runtime.log")
rows=[]
for line in src.read_text().splitlines():
    try:
        item=json.loads(line)
        item.pop("userId",None)
        rows.append(item)
    except ValueError:
        rows.append({"msg":line})
text="\n".join(json.dumps(r,ensure_ascii=False) for r in rows)
text=redact(text)
(p/"runtime-sanitized.jsonl").write_text(text+"\n")
messages=json.loads((p/"final-console.json").read_text())
messages=[m for m in messages if m.get("timestamp","") >= "2026-11-13T21:26:20Z"]
focus=[m for m in messages if re.search(r"Combat:|Dummy hit|Forge preview|WARNING|ERROR|attempt to|stack traceback|Could not open|foreign WorkQueue|CombatAudio",m.get("text",""),re.I)]
(p/"events.log").write_text("\n".join(m["timestamp"]+" "+m["text"] for m in focus)+"\n")
patterns=[r"\bERROR\b|attempt to|stack traceback",r"Could not open file",r"VoxelJobSystem.*foreign WorkQueue",r"CombatAudio.*(?:failed|error|degrad)"]
with (p/"error-scan.log").open("w") as f:
    f.write("Scope: browser captured console after 2026-11-14 05:26:20 +08 and copied current Web watcher runtime. Not a proof that page error badge is clear.\n")
    joined="\n".join(m.get("text","") for m in messages)+"\n"+text
    for pattern in patterns:
        found=re.findall(pattern,joined,re.I)
        f.write(f"{pattern}: {len(found)} matches\n")
    for m in focus:
        if "WARNING" in m["text"]: f.write(m["text"]+"\n")
print("Evidence collected; error scan and timestamped events saved.")
