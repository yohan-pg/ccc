#Fetch Alliance wiki pages as raw wikitext, past the Anubis proof-of-work gate.
#Usage: python3 fetch_wiki.py Rorqual Using_GPUs_with_Slurm ...   -> writes <Page>.wiki in cwd
#
#docs.alliancecan.ca sits behind Anubis (BotStopper): WebFetch and plain curl both get an
#"Access Denied" JS challenge page instead of content. The challenge is embedded in that page as
#a JSON <script id="anubis_challenge">, and is the ordinary hashcash one a browser solves: find a
#nonce whose sha256(randomData + nonce) has `difficulty` leading zero hex chars. Difficulty is 2,
#so it costs milliseconds. Submitting it to /api/pass-challenge sets the clearance cookie on the
#session, after which normal requests work.
#
#This is the intended client path, not a bypass — the PoW exists to make bulk scraping expensive,
#so pay it once per session and fetch only the pages you need. Prefer the MediaWiki API
#(action=parse&prop=wikitext) over HTML: it is smaller and far easier to read.
import hashlib, json, re, sys, time, urllib.parse
import requests

UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
BASE = "https://docs.alliancecan.ca"
s = requests.Session()
s.headers["User-Agent"] = UA


def solve(page_url):
    r = s.get(page_url)
    if "anubis_challenge" not in r.text:
        return r
    m = re.search(r'id="anubis_challenge" type="application/json">(.*?)\n?</script>', r.text, re.S)
    data = json.loads(m.group(1))
    rd = data["challenge"]["randomData"]
    diff = data["rules"]["difficulty"]
    t0 = time.time()
    n = 0
    while True:
        h = hashlib.sha256((rd + str(n)).encode()).hexdigest()
        if h.startswith("0" * diff):
            break
        n += 1
    q = urllib.parse.urlencode({
        "id": data["challenge"]["id"], "response": h, "nonce": n,
        "redir": page_url, "elapsedTime": int((time.time() - t0) * 1000) + 300,
    })
    r = s.get(f"{BASE}/.within.website/x/cmd/anubis/api/pass-challenge?{q}")
    return r


for page in sys.argv[1:]:
    url = f"{BASE}/mediawiki/api.php?action=parse&page={page}&prop=wikitext&format=json"
    r = solve(url)
    try:
        txt = r.json()["parse"]["wikitext"]["*"]
    except Exception:
        print(f"FAIL {page}: {r.status_code} {r.text[:200]}")
        continue
    open(f"{page.replace('/', '_')}.wiki", "w").write(txt)
    print(f"OK {page} {len(txt)}")
