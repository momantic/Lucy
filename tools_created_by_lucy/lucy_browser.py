#!/usr/bin/env python3
import sys, json, urllib.request, urllib.parse, time, subprocess

BASE = "http://127.0.0.1:8765"

def get(path):
    return json.loads(urllib.request.urlopen(BASE + path, timeout=5).read())

def post(path, obj):
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(obj).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    return json.loads(urllib.request.urlopen(req, timeout=5).read())

args = sys.argv[1:]
cmd = args[0] if args else "state"
rest = " ".join(args[1:])

if cmd == "open":
    subprocess.run(["open", "-a", "Google Chrome", rest])
    print("Opened:", rest)

elif cmd == "linkedin_search":
    q = urllib.parse.quote(rest)
    url = f"https://www.linkedin.com/search/results/content/?keywords={q}"
    subprocess.run(["open", "-a", "Google Chrome", url])
    print("Opened LinkedIn search:", rest)
    time.sleep(5)
    print(json.dumps(get("/state"), indent=2)[:4000])

elif cmd == "read":
    print(json.dumps(get("/state"), indent=2)[:8000])

elif cmd == "page_text":
    print(get("/state").get("last_page", ""))

else:
    print(json.dumps(get("/state"), indent=2))
